-- Destination-only preparation: rehearse against a restored US East baseline first.
-- Never apply to the Canadian source. Missing staging tables are a hard failure.
-- All checks and replacements execute atomically; no CASCADE or data cleanup.
DO $migration$
DECLARE
  item record;
  actual_definition text;
  has_duplicates boolean;
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  PERFORM set_config('statement_timeout', '60s', true);
  LOCK TABLE tj.performance_competencies,
             tj.performance_metric_competency_map,
             tj.performance_scenarios IN ACCESS EXCLUSIVE MODE;

  FOR item IN
    SELECT * FROM (VALUES
      ('performance_competencies',
       'performance_competencies_organization_id_code_key',
       'organization_id, code'),
      ('performance_metric_competency_map',
       'performance_metric_competency_organization_id_metric_key_co_key',
       'organization_id, metric_key, competency_id'),
      ('performance_scenarios',
       'performance_scenarios_organization_id_code_key',
       'organization_id, code')
    ) AS specifications(table_name, constraint_name, columns_sql)
  LOOP
    SELECT pg_get_constraintdef(c.oid) INTO actual_definition
    FROM pg_constraint c
    WHERE c.conrelid = format('tj.%I', item.table_name)::regclass
      AND c.conname = item.constraint_name AND c.contype = 'u';

    IF actual_definition IS DISTINCT FROM format('UNIQUE (%s)', item.columns_sql)
       AND actual_definition IS DISTINCT FROM
           format('UNIQUE NULLS NOT DISTINCT (%s)', item.columns_sql) THEN
      RAISE EXCEPTION 'Unexpected or missing constraint %.%: %',
        item.table_name, item.constraint_name, actual_definition;
    END IF;

    EXECUTE format(
      'SELECT EXISTS (SELECT 1 FROM tj.%I GROUP BY %s HAVING count(*) > 1)',
      item.table_name, item.columns_sql) INTO has_duplicates;
    IF has_duplicates THEN
      RAISE EXCEPTION 'Duplicate keys in tj.%; reconcile before applying', item.table_name;
    END IF;
  END LOOP;

  -- Preflight every table before replacing any constraint.
  ALTER TABLE tj.performance_competencies
    DROP CONSTRAINT performance_competencies_organization_id_code_key,
    ADD CONSTRAINT performance_competencies_organization_id_code_key
      UNIQUE NULLS NOT DISTINCT (organization_id, code);
  ALTER TABLE tj.performance_metric_competency_map
    DROP CONSTRAINT performance_metric_competency_organization_id_metric_key_co_key,
    ADD CONSTRAINT performance_metric_competency_organization_id_metric_key_co_key
      UNIQUE NULLS NOT DISTINCT (organization_id, metric_key, competency_id);
  ALTER TABLE tj.performance_scenarios
    DROP CONSTRAINT performance_scenarios_organization_id_code_key,
    ADD CONSTRAINT performance_scenarios_organization_id_code_key
      UNIQUE NULLS NOT DISTINCT (organization_id, code);
END
$migration$;
