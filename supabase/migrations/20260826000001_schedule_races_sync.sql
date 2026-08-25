-- Daily cron trigger for the AIMS race sync Edge Function.
-- The function has verify_jwt = false (see supabase/config.toml), so no auth header is required.

select cron.schedule(
  'sync-races-aims-daily',
  '0 3 * * *',
  $$
  select net.http_post(
    url := 'https://ijgycurltaznhcdoclhv.supabase.co/functions/v1/sync-races-aims',
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  $$
);
