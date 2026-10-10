-- Run only on the isolated, restored rehearsal database.
-- Reads public/tj foreign keys, including constraints marked NOT VALID.
-- Prints constraint names and summary counts, never row contents.
BEGIN;
SET TRANSACTION READ ONLY;
DO $check$
DECLARE
  fk record;
  nonnull_all text;
  nonnull_any text;
  null_any text;
  equality_sql text;
  predicate_sql text;
  broken boolean;
  checked integer := 0;
  failures integer := 0;
BEGIN
  FOR fk IN
    SELECT c.* FROM pg_constraint c
    JOIN pg_namespace n ON n.oid=c.connamespace
    WHERE c.contype='f' AND c.conparentid=0
      AND n.nspname IN ('public','tj')
    ORDER BY c.conrelid,c.conname
  LOOP
    SELECT
      string_agg(format('child.%I IS NOT NULL', a.attname),' AND ' ORDER BY k.position),
      string_agg(format('child.%I IS NOT NULL', a.attname),' OR ' ORDER BY k.position),
      string_agg(format('child.%I IS NULL', a.attname),' OR ' ORDER BY k.position),
      string_agg(format('parent.%I OPERATOR(%I.%s) child.%I',
        b.attname,onsp.nspname,op.oprname,a.attname),' AND ' ORDER BY k.position)
    INTO nonnull_all,nonnull_any,null_any,equality_sql
    FROM generate_subscripts(fk.conkey,1) AS k(position)
    JOIN pg_attribute a ON a.attrelid=fk.conrelid AND a.attnum=fk.conkey[k.position]
    JOIN pg_attribute b ON b.attrelid=fk.confrelid AND b.attnum=fk.confkey[k.position]
    JOIN pg_operator op ON op.oid=fk.conpfeqop[k.position]
    JOIN pg_namespace onsp ON onsp.oid=op.oprnamespace;

    predicate_sql := format('(%s) AND NOT EXISTS (SELECT 1 FROM %s parent WHERE %s)',
      nonnull_all,fk.confrelid::regclass,equality_sql);
    IF fk.confmatchtype='f' THEN
      predicate_sql := format('(%s) OR ((%s) AND (%s))',
        predicate_sql,nonnull_any,null_any);
    ELSIF fk.confmatchtype<>'s' THEN
      RAISE EXCEPTION 'Unsupported foreign-key match type: %',fk.conname;
    END IF;

    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s child WHERE %s)',
      fk.conrelid::regclass,predicate_sql) INTO broken;
    checked := checked+1;
    IF broken THEN
      failures := failures+1;
      RAISE NOTICE 'BROKEN REFERENCE: %.%',fk.conrelid::regclass,fk.conname;
    END IF;
    IF checked % 100=0 THEN
      RAISE NOTICE 'Checked % foreign keys...',checked;
    END IF;
  END LOOP;
  RAISE NOTICE 'Foreign-key check complete: % checked, % failures.',checked,failures;
  IF failures>0 THEN
    RAISE EXCEPTION 'Restore integrity check failed; investigate % constraints.',failures;
  END IF;
END
$check$;
ROLLBACK;
