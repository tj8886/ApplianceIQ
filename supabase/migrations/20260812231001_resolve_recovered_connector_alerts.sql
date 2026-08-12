create or replace function public.platform_connector_alert_scan()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare r record; created_count int:=0; resolved_count int:=0; resolved_step int:=0; fp text; sev text; ttl text; msg text;
begin
  for r in
    select c.id,c.display_name,h.status health_status,h.health_score,h.dead_letter_records,h.quarantined_records,h.unresolved_matches
    from public.platform_connector_connections c
    left join lateral (
      select * from public.platform_connector_health_snapshots hs where hs.connection_id=c.id order by hs.captured_at desc limit 1
    ) h on true
    where c.status <> 'disabled'
  loop
    if coalesce(r.health_status,'offline') in ('unhealthy','offline') or coalesce(r.health_score,0)<60 then
      fp:='health:'||coalesce(r.health_status,'offline');
      sev:=case when coalesce(r.health_status,'offline')='offline' then 'critical' else 'warning' end;
      ttl:=coalesce(r.display_name,'Connector')||' is '||coalesce(r.health_status,'offline');
      msg:='Connector health score: '||coalesce(r.health_score::text,'0');
      insert into public.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details)
      values(r.id,'health',sev,ttl,msg,fp,jsonb_build_object('health_score',r.health_score,'health_status',r.health_status))
      on conflict (connection_id,fingerprint) where status in ('open','acknowledged')
      do update set last_seen_at=now(),message=excluded.message,details=excluded.details;
      created_count:=created_count+1;
    end if;
    if coalesce(r.dead_letter_records,0)>0 then
      fp:='dead_letter';
      insert into public.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details)
      values(r.id,'dead_letter','critical',coalesce(r.display_name,'Connector')||' has dead-letter records',r.dead_letter_records||' record(s) require intervention',fp,jsonb_build_object('dead_letter_records',r.dead_letter_records))
      on conflict (connection_id,fingerprint) where status in ('open','acknowledged')
      do update set last_seen_at=now(),message=excluded.message,details=excluded.details;
      created_count:=created_count+1;
    end if;
  end loop;

  for r in
    select rr.connection_id,rr.id,rr.discrepancies,c.display_name
    from public.platform_connector_reconciliation_runs rr
    join public.platform_connector_connections c on c.id=rr.connection_id
    where rr.completed_at > now()-interval '24 hours' and rr.status not in ('success','matched','clean')
  loop
    fp:='reconciliation:'||r.id::text;
    insert into public.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details)
    values(r.connection_id,'reconciliation','warning',coalesce(r.display_name,'Connector')||' reconciliation variance','Source and IQ record counts require review',fp,coalesce(r.discrepancies,'{}'::jsonb))
    on conflict (connection_id,fingerprint) where status in ('open','acknowledged')
    do update set last_seen_at=now(),details=excluded.details;
    created_count:=created_count+1;
  end loop;

  update public.platform_connector_alerts a
  set status='resolved',resolved_at=now(),last_seen_at=now()
  where a.status in ('open','acknowledged') and a.alert_type='dead_letter'
    and not exists (select 1 from public.platform_connector_quarantine q where q.connection_id=a.connection_id and q.status='dead_letter');
  get diagnostics resolved_step=row_count; resolved_count:=resolved_count+resolved_step;

  update public.platform_connector_alerts a
  set status='resolved',resolved_at=now(),last_seen_at=now()
  where a.status in ('open','acknowledged') and a.alert_type='health'
    and exists (
      select 1 from lateral (
        select hs.status,hs.health_score from public.platform_connector_health_snapshots hs
        where hs.connection_id=a.connection_id order by hs.captured_at desc limit 1
      ) h where coalesce(h.status,'offline') not in ('unhealthy','offline') and coalesce(h.health_score,0)>=60
    );
  get diagnostics resolved_step=row_count; resolved_count:=resolved_count+resolved_step;

  update public.platform_connector_alerts a
  set status='resolved',resolved_at=now(),last_seen_at=now()
  where a.status in ('open','acknowledged') and a.alert_type='reconciliation'
    and not exists (
      select 1 from public.platform_connector_reconciliation_runs rr
      where ('reconciliation:'||rr.id::text)=a.fingerprint
        and rr.completed_at > now()-interval '24 hours'
        and rr.status not in ('success','matched','clean')
    );
  get diagnostics resolved_step=row_count; resolved_count:=resolved_count+resolved_step;

  return jsonb_build_object('alerts_touched',created_count,'alerts_resolved',resolved_count);
end
$function$;
revoke all on function public.platform_connector_alert_scan() from public,anon,authenticated;
grant execute on function public.platform_connector_alert_scan() to service_role;
