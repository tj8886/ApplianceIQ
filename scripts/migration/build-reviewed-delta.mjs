// Build transactional DML from operator-reviewed row hashes. Never save source payloads in git.
import {createHash} from 'node:crypto';
const allowed=['decision_cases','decision_predictions','field_floor_snapshots','iq_staffing_predictions','phase6_revenue_opportunities','phase7_action_runs','platform_connector_alerts','platform_connector_incident_metrics'];
const literal=s=>"'"+String(s).replaceAll("'","''")+"'";
const ident=s=>{if(!/^[a-z_][a-z0-9_]*$/.test(s))throw Error('invalid_identifier');return `"${s}"`;};
export function buildReviewedDelta(plan) {
  let sql="BEGIN; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; SET LOCAL statement_timeout='60s';\n";
  for (const item of plan.tables) {
    if (!allowed.includes(item.table)) throw Error('table_not_reviewed');
    const table=ident(item.table),key=ident(item.key),columns=item.columns.map(ident).join(','),temp=ident('delta_'+item.table);
    const payload='['+item.rows.map(r=>r.row_data).join(',')+']';
    // Existing target hashes form the precondition, including records untouched by this copy.
    const baseline=createHash('md5').update(item.before.map(r=>r.checksum).sort().join('')).digest('hex');
    sql+=`LOCK TABLE tj.${table} IN SHARE ROW EXCLUSIVE MODE;\nDO $guard$ DECLARE n bigint; h text; BEGIN SELECT count(*),md5(coalesce(string_agg(x,'' ORDER BY x COLLATE "C"),'')) INTO n,h FROM (SELECT md5(to_jsonb(t)::text) x FROM tj.${table} t) q; IF n<>${item.before.length} OR h<>${literal(baseline)} THEN RAISE EXCEPTION 'destination_changed: ${item.table}'; END IF; END $guard$;\n`;
    sql+=`CREATE TEMP TABLE ${temp} (LIKE tj.${table}) ON COMMIT DROP;\nINSERT INTO ${temp}(${columns}) SELECT ${columns} FROM jsonb_populate_recordset(NULL::tj.${table},${literal(payload)}::jsonb);\n`;
    const expected=item.rows.map(r=>`(${literal(r.row_key)},${literal(r.checksum)})`).join(',');
    sql+=`DO $source$ BEGIN IF EXISTS(SELECT 1 FROM ${temp} s JOIN (VALUES ${expected}) e(k,h) ON e.k=s.${key}::text WHERE md5(to_jsonb(s)::text)<>e.h) OR (SELECT count(*) FROM ${temp})<>${item.rows.length} THEN RAISE EXCEPTION 'source_row_mismatch'; END IF; END $source$;\n`;
    sql+=`INSERT INTO tj_private.migration_delta_before_images(run_id,table_name,row_key,organization_id,before_data,source_checksum) SELECT ${literal(plan.run_id)}::uuid,${literal(item.table)},s.${key}::text,to_jsonb(s)->>'organization_id',to_jsonb(d),md5(to_jsonb(s)::text) FROM ${temp} s LEFT JOIN tj.${table} d USING(${key});\n`.replace("to_jsonb(s)->>'organization_id'","(to_jsonb(s)->>'organization_id')::uuid");
    sql+=`INSERT INTO tj.${table}(${columns}) SELECT ${columns} FROM ${temp} ON CONFLICT(${key}) DO UPDATE SET ${item.columns.filter(c=>c!==item.key).map(c=>`${ident(c)}=EXCLUDED.${ident(c)}`).join(',')};\n`;
    // decision_cases_touch intentionally recomputes priority and stamps destination updated_at.
    const normalize=item.table==='decision_cases'?" - 'updated_at'":'';
    sql+=`DO $saved$ BEGIN IF EXISTS(SELECT 1 FROM ${temp} s LEFT JOIN tj.${table} d USING(${key}) WHERE d.${key} IS NULL OR (to_jsonb(s)${normalize}) IS DISTINCT FROM (to_jsonb(d)${normalize})) THEN RAISE EXCEPTION 'saved_row_mismatch: ${item.table}'; END IF; END $saved$;\n`;
    sql+=`UPDATE tj_private.migration_delta_before_images j SET after_checksum=md5(to_jsonb(d)::text) FROM tj.${table} d WHERE j.run_id=${literal(plan.run_id)}::uuid AND j.table_name=${literal(item.table)} AND j.row_key=d.${key}::text;\n`;
    if(item.table==='iq_staffing_predictions') sql+=`INSERT INTO tj_private.approved_staffing_prediction_ids(prediction_id,basis) SELECT ${key},'verified_canada_source' FROM ${temp} ON CONFLICT DO NOTHING;\n`;
  }
  return sql+`COMMIT; SELECT table_name,count(*) FILTER(WHERE before_data IS NULL) inserted,count(*) FILTER(WHERE before_data IS NOT NULL) updated,count(*) FILTER(WHERE after_checksum IS NULL) unverified FROM tj_private.migration_delta_before_images WHERE run_id=${literal(plan.run_id)}::uuid GROUP BY table_name ORDER BY table_name;\n`;
}
