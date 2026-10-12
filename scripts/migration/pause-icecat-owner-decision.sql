-- Owner requested skipping Icecat while considering discontinuation. Preserve existing enrichment data.
DO $$ DECLARE j record; BEGIN FOR j IN SELECT jobid FROM cron.job WHERE jobname='enrich-icecat' LOOP PERFORM cron.alter_job(j.jobid,active:=false); END LOOP; END $$;
