-- DEVELOPMENT ONLY. Route the existing family worker to its confirmed dashboard slug.
-- The deployed swift-worker code was supplied by the owner and matches the family-events worker.
begin;
do $$ begin
 if to_regprocedure('petal_private.wake_family_events_worker()') is null then raise exception 'Family webhook setup is missing; stop and report';end if;
 if (select count(*) from cron.job where jobname='petal-family-events-development')<>1 then raise exception 'Expected exactly one family retry job; stop and report';end if;
 if not exists(select 1 from cron.job where jobname='petal-family-events-development' and
  (strpos(command,'https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/family-events-push')>0 or strpos(command,'https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker')>0)) then raise exception 'Family retry route differs from the expected development endpoints; stop and report';end if;
 if (select count(*) from vault.decrypted_secrets where name='petal_family_worker_secret')<>1 then raise exception 'Expected one family worker Vault secret';end if;
 if not exists(select 1 from vault.decrypted_secrets where name='petal_family_worker_secret' and decrypted_secret ~ '^[A-Za-z0-9_-]{32,128}$') then raise exception 'Family worker secret must be a single valid header value';end if;
end $$;
create or replace function petal_private.wake_family_events_worker() returns trigger language plpgsql security definer set search_path='' as $$
begin
 begin
 perform net.http_post(url:='https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker',
  headers:=jsonb_build_object('Content-Type','application/json','x-petal-worker-key',(select decrypted_secret from vault.decrypted_secrets where name='petal_family_worker_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=120000);
 exception when others then null;end;
 return new;
end $$;
revoke execute on function petal_private.wake_family_events_worker() from public,anon,authenticated;
do $$ begin
 perform cron.schedule('petal-family-events-development','*/5 * * * *', $job$
  select net.http_post(url:='https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker',
   headers:=jsonb_build_object('Content-Type','application/json','x-petal-worker-key',(select decrypted_secret from vault.decrypted_secrets where name='petal_family_worker_secret')),
   body:='{}'::jsonb,timeout_milliseconds:=120000);
 $job$);
end $$;
commit;
select jobname,schedule,active,
 strpos(command,'https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker')>0 as retry_route_correct,
 strpos(pg_get_functiondef('petal_private.wake_family_events_worker()'::regprocedure),'https://hijtwgugzzpjjkuutyfy.supabase.co/functions/v1/swift-worker')>0 as webhook_route_correct
from cron.job where jobname='petal-family-events-development';
