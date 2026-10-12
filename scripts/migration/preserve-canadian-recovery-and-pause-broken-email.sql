-- Canadian source recovery preservation. No source records or files are removed.
DO $pause$ DECLARE j record; BEGIN FOR j IN SELECT jobid FROM cron.job WHERE jobname IN ('archive-intelligence-events','prune-product-versions','prune-old-notifications','mdf-audit-cleanup','mdf-email-cleanup','mdf-process-email-queue') LOOP PERFORM cron.alter_job(j.jobid,active:=false); END LOOP; END $pause$;
