-- DEVELOPMENT ONLY. Run only AFTER worker deployment and secret setup.
-- Enable pg_cron and pg_net in the Dev dashboard's database extensions.
-- In Supabase Vault create exactly one secret named
-- petal_checkin_worker_secret with the SAME value as Edge Function secret
-- PETAL_CHECKIN_WORKER_SECRET. No secret value belongs in this file.
do $preflight$
begin
 if to_regnamespace('cron') is null or to_regnamespace('net') is null then
  raise exception 'Enable pg_cron and pg_net in development first.';
 end if;
 if (select count(*) from vault.decrypted_secrets where name='petal_checkin_worker_secret' and length(decrypted_secret)>=32)<>1 then
  raise exception 'Create the unique matching worker secret in development Vault first.';
 end if;
end $preflight$;

select cron.schedule(
 'petal-parent-checkins-development',
 '* * * * *',
 $job$
 select net.http_post(
  url:='https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/parent-checkin-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-petal-worker-key',
   (select decrypted_secret from vault.decrypted_secrets where name='petal_checkin_worker_secret')),
  body:='{}'::jsonb,
  timeout_milliseconds:=120000
 );
 $job$
);
select jobid,jobname,schedule,active from cron.job
where jobname='petal-parent-checkins-development';
