-- Process future eligible PIM changes once per minute, filling gaps only.
SELECT cron.schedule('applianceiq-pim-fill-blanks','* * * * *',
 $$SELECT tj_private.pim_web_complete_batch(1000);$$);
