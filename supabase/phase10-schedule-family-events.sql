-- DEVELOPMENT ONLY: prepare AFTER worker deployment and matching Edge/Vault secret setup.
-- Requires pg_net, pg_cron, and exactly one Vault secret petal_family_worker_secret.
-- No secret value belongs here. Worker uses PETAL_FAMILY_WORKER_SECRET.
begin;
do $$ begin
 if to_regnamespace('net') is null or to_regnamespace('cron') is null then raise exception 'Enable pg_net and pg_cron in development first';end if;
 if to_regclass('public.family_notices') is null then raise exception 'Install Phase10 forward migration first';end if;
 if (select count(*) from vault.decrypted_secrets where name='petal_family_worker_secret')<>1 then raise exception 'Create exactly one development Vault secret petal_family_worker_secret';end if;
 if not exists(select 1 from vault.decrypted_secrets where name='petal_family_worker_secret' and decrypted_secret ~ '^[A-Za-z0-9_-]{32,128}$') then raise exception 'Worker secret contains invalid header characters; use the generated single-line secret in both Edge and Vault';end if;
end $$;
create or replace function petal_private.wake_family_events_worker() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- An HTTP scheduling outage must never undo the business outbox or XP. Cron retries.
 begin
 perform net.http_post(url:='https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker',
 headers:=jsonb_build_object('Content-Type','application/json','x-petal-worker-key',(select decrypted_secret from vault.decrypted_secrets where name='petal_family_worker_secret')),
 body:='{}'::jsonb,timeout_milliseconds:=120000);
 exception when others then null;end;return new;
end $$;
revoke execute on function petal_private.wake_family_events_worker() from public,anon,authenticated;
drop trigger if exists phase10_family_worker_webhook on petal_private.outbox;
create trigger phase10_family_worker_webhook after insert on petal_private.outbox for each row
 when (new.topic in ('school.change_requested','school.change_reviewed','school.item_saved','submission.pending','submission.resubmitted','submission.approved','submission.reviewed','reward.requested','extra_outcome.requested','day_appeal.requested','parent.action_recorded','occurrence.corrected','deduction.reversed','bonus.offered','bonus.submitted','bonus.reviewed','appeal.resolved','reflection.updated','day.finalized','routine.updated','catalogue.updated','task.assigned'))
 execute function petal_private.wake_family_events_worker();
select cron.schedule('petal-family-events-development','*/5 * * * *', $job$
 select net.http_post(url:='https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker',
 headers:=jsonb_build_object('Content-Type','application/json','x-petal-worker-key',(select decrypted_secret from vault.decrypted_secrets where name='petal_family_worker_secret')),
 body:='{}'::jsonb,timeout_milliseconds:=120000);
$job$);
commit;
select jobname,schedule,active from cron.job where jobname='petal-family-events-development';
