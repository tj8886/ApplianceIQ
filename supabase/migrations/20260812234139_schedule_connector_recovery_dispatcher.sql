select cron.schedule(
  'iq-connector-recovery-dispatch',
  '*/5 * * * *',
  $$
  select net.http_post(
    url:='https://fumwwhyozeouoqscolke.supabase.co/functions/v1/connector-recovery-dispatcher',
    headers:=jsonb_build_object(
      'Content-Type','application/json',
      'x-connector-dispatch-token',(
        select decrypted_secret
        from vault.decrypted_secrets
        where name='connector_recovery_dispatch'
        limit 1
      )
    ),
    body:='{}'::jsonb
  );
  $$
);
