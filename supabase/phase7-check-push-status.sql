-- DEVELOPMENT ONLY, read-only. Returns counts/statuses, never keys or tokens.
-- Queue counts cover today's development records, not a selected family.
select
 (select extversion from pg_extension where extname='pg_net') as pg_net_version,
 (select count(*)=1 and coalesce(bool_and(length(decrypted_secret)>=32
   and decrypted_secret !~ '[^!-~]'),false)
  from vault.decrypted_secrets where name='petal_checkin_worker_secret') as worker_secret_header_valid,
 (select count(*) from public.health_installations) as enrolled_devices,
 (select count(*) from public.device_registrations d where exists
   (select 1 from public.memberships m where m.user_id=d.user_id
    and m.family_id=d.family_id and m.role='parent' and m.active)) as registered_parent_devices,
 (select count(*) from petal_private.health_checkin_events
  where local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date) as todays_events,
 (select count(*) from petal_private.health_alert_recipients
  where local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date) as todays_recipients,
 (select coalesce(sum(attempts),0) from petal_private.health_alert_recipients
  where local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date) as delivery_attempts,
 (select count(*) from petal_private.health_alert_recipients
  where local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date
   and delivered_at is not null) as terminal_deliveries,
 (select count(*) from cron.job
  where jobname='petal-parent-checkins-development' and active) as active_worker_jobs,
 (select count(*) from net.http_request_queue) as pending_http_requests,
 -- No headers, request bodies or response bodies are exposed.
 -- Recent HTTP statuses include all pg_net jobs in this development project.
 (select coalesce(jsonb_agg(to_jsonb(recent)), '[]'::jsonb) from
   (select status_code, timed_out, error_msg, created
    from net._http_response order by created desc limit 5) recent) as recent_http_results;
