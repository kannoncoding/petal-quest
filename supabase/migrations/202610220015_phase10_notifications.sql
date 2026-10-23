-- Phase10 family business notices. Forward only after migrations001–014; no health transport changes.
begin;
create table public.family_notices (
 event_id uuid primary key default gen_random_uuid(),source_event_id uuid not null references petal_private.outbox(id),
 recipient_user_id uuid not null references auth.users(id),family_id uuid not null references public.families(id),
 recipient_role text not null check(recipient_role in ('parent','teen')),teen_id uuid,local_date date,
 destination text not null check(destination in ('review','today','results','rewards','routines','school')),
 created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,
 unique(source_event_id,recipient_user_id)
);
create table petal_private.family_devices (
 installation_id uuid primary key,user_id uuid not null references auth.users(id),family_id uuid not null,
 app text not null check(app in ('parent','teen')),token text unique,binding_id uuid not null default gen_random_uuid(),
 active boolean not null default true,updated_at timestamptz not null default clock_timestamp()
);
create table petal_private.family_notice_deliveries (
 id uuid primary key default gen_random_uuid(),event_id uuid not null references public.family_notices(event_id),
 installation_id uuid not null references petal_private.family_devices(installation_id),binding_id uuid not null,
 state text not null default 'pending' check(state in ('pending','leased','done','dead')),attempts integer not null default 0,
 next_attempt_at timestamptz not null default clock_timestamp(),lease_id uuid,lease_until timestamptz,
 unique(event_id,installation_id,binding_id)
);
create index phase10_notices_recipient_time on public.family_notices(recipient_user_id,created_at desc,event_id desc);
create index phase10_delivery_retry on petal_private.family_notice_deliveries(next_attempt_at,id) where state in ('pending','leased');
create index phase10_outbox_created on petal_private.outbox(created_at);
alter table public.family_notices enable row level security;
alter table petal_private.family_devices enable row level security;
alter table petal_private.family_notice_deliveries enable row level security;
revoke all on public.family_notices,petal_private.family_devices,petal_private.family_notice_deliveries from public,anon,authenticated;
grant select on public.family_notices to authenticated;
create policy own_current_notices on public.family_notices for select to authenticated using (
 recipient_user_id=auth.uid() and expires_at>clock_timestamp() and exists(select 1 from public.memberships m
 where m.user_id=auth.uid() and m.family_id=family_notices.family_id and m.active and m.role=family_notices.recipient_role
 and (m.role='parent' or m.actor_id=family_notices.teen_id)));
create function public.register_family_device(p_installation_id uuid,p_token text,p_app text,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;a jsonb;b uuid;
begin
 select * into m from public.memberships where user_id=u and active for share;
 if not found or p_app is distinct from m.role then raise exception 'active_matching_membership_required' using errcode='42501';end if;
 if p_installation_id is null or p_token is null or length(p_token) not between 1 and 4096 then raise exception 'invalid_device';end if;
 a:=petal_private.begin_request(p_request_id,'register_family_device',jsonb_build_object('installation',p_installation_id,'token_hash',encode(extensions.digest(p_token,'sha256'),'hex'),'app',p_app));
 if a is not null then return a;end if;
 -- Serialize both identifiers. A token can never remain active on the previous account.
 perform pg_advisory_xact_lock(hashtextextended('family-device-binding',0));
 update petal_private.family_devices set token=null,active=false,binding_id=gen_random_uuid(),updated_at=clock_timestamp() where token=p_token and installation_id<>p_installation_id;
 insert into petal_private.family_devices(installation_id,user_id,family_id,app,token) values(p_installation_id,u,m.family_id,m.role,p_token)
 on conflict(installation_id) do update set user_id=u,family_id=m.family_id,app=m.role,token=p_token,
 binding_id=case when family_devices.user_id=u and family_devices.family_id=m.family_id and family_devices.app=m.role and family_devices.token=p_token and family_devices.active then family_devices.binding_id else gen_random_uuid() end,
 active=true,updated_at=clock_timestamp() returning binding_id into b;
 a:=jsonb_build_object('status','registered','installation_id',p_installation_id,'request_id',p_request_id);
 update petal_private.idempotency set result=a where user_id=u and request_id=p_request_id;return a;
end $$;
create function public.unregister_family_device(p_installation_id uuid,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();a jsonb;
begin
 a:=petal_private.begin_request(p_request_id,'unregister_family_device',jsonb_build_object('installation',p_installation_id));if a is not null then return a;end if;
 update petal_private.family_devices set active=false,binding_id=gen_random_uuid(),updated_at=clock_timestamp() where installation_id=p_installation_id and user_id=u;
 a:=jsonb_build_object('status','unregistered','request_id',p_request_id);update petal_private.idempotency set result=a where user_id=u and request_id=p_request_id;return a;
end $$;
create function public.list_family_notices(p_limit integer default 50,p_before timestamptz default null) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('notices',coalesce(jsonb_agg(to_jsonb(n)-'source_event_id'-'recipient_role' order by n.created_at desc,n.event_id desc),'[]'::jsonb))
 from (select * from public.family_notices where p_before is null or created_at<p_before order by created_at desc,event_id desc limit greatest(1,least(coalesce(p_limit,50),100))) n;
$$;
-- Resolve only allowlisted business topics against authoritative rows, never arbitrary payload roles/recipients.
create function petal_private.materialize_family_notice(p_event_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare e petal_private.outbox%rowtype;j jsonb;t uuid;dt date;r text:='teen';dest text:='today';sender uuid;
begin
 select * into e from petal_private.outbox where id=p_event_id;
 if not found or e.created_at<clock_timestamp()-interval '7 days' then return;end if;
 if e.topic like 'school.%' and (clock_timestamp() at time zone 'America/Costa_Rica')::date>date '2026-11-27' then return;end if;
 case e.topic
 when 'school.change_requested' then select to_jsonb(x) into j from public.school_change_requests x where x.id=e.source_id and x.family_id=e.family_id and x.status='pending';r:='parent';dest:='school';
 when 'school.change_reviewed' then select to_jsonb(x) into j from public.school_change_requests x where x.id=e.source_id and x.family_id=e.family_id;dest:='school';
 when 'school.item_saved' then
  select to_jsonb(x)||jsonb_build_object('created_by',x.actor_id) into j from public.school_item_history x where x.id=e.source_id and x.family_id=e.family_id;
  if exists(select 1 from public.memberships where family_id=e.family_id and user_id=(j->>'actor_id')::uuid and active and role='teen') then r:='parent';end if;dest:='school';
 when 'submission.pending','submission.resubmitted','submission.approved','submission.reviewed' then
 select to_jsonb(s)||jsonb_build_object('local_date',o.local_date) into j from public.submissions s join public.task_occurrences o on o.id=s.occurrence_id where s.family_id=e.family_id and s.id=(e.payload->>'submission_id')::uuid;
 if e.topic in ('submission.pending','submission.resubmitted') then r:='parent';dest:='review';end if;
 -- reviewed is the canonical post-Phase8 review notice; approval outbox remains an accounting fact.
 if e.topic='submission.approved' and exists(select 1 from public.submission_reviews where submission_id=(j->>'id')::uuid) then return;end if;
 when 'reward.requested' then select to_jsonb(x) into j from public.reward_requests x where x.id=e.source_id and x.family_id=e.family_id;r:='parent';dest:='rewards';
 when 'extra_outcome.requested' then select to_jsonb(x) into j from public.extra_outcome_requests x where x.id=e.source_id and x.family_id=e.family_id;r:='parent';dest:='review';
 when 'day_appeal.requested' then select to_jsonb(x) into j from public.day_appeals x where x.id=e.source_id and x.family_id=e.family_id;r:='parent';dest:='review';
 when 'parent.action_recorded' then select to_jsonb(x) into j from public.parent_actions x where x.id=e.source_id and x.family_id=e.family_id;dest:='rewards';
 when 'occurrence.corrected' then select to_jsonb(x) into j from public.task_occurrences x where x.id=(e.payload->>'occurrence_id')::uuid and x.family_id=e.family_id;
 when 'deduction.reversed' then select to_jsonb(x) into j from public.deduction_entries x where x.id=(e.payload->>'entry_id')::uuid and x.family_id=e.family_id;dest:='results';
 when 'bonus.offered','bonus.submitted','bonus.reviewed' then select to_jsonb(x) into j from public.bonus_activities x where x.id=(e.payload->>'bonus_id')::uuid and x.family_id=e.family_id;if e.topic='bonus.submitted' then r:='parent';dest:='review';end if;
 when 'appeal.resolved' then select to_jsonb(x) into j from public.day_appeals x where x.id=(e.payload->>'appeal_id')::uuid and x.family_id=e.family_id;dest:='results';
 when 'reflection.updated' then select to_jsonb(x) into j from public.reflection_note_history x where x.id=e.source_id and x.family_id=e.family_id;dest:='results';
 when 'day.finalized' then select to_jsonb(x) into j from public.day_results x where x.family_id=e.family_id and x.teen_id=(e.payload->>'teen_id')::uuid and x.local_date=(e.payload->>'local_date')::date;dest:='results';
 when 'routine.updated' then select to_jsonb(x) into j from public.assigned_routine_versions x where x.id=e.source_id and x.family_id=e.family_id;dest:='routines';
 when 'catalogue.updated' then select to_jsonb(x) into j from public.catalogue_versions x where x.id=e.source_id and x.family_id=e.family_id;
 when 'task.assigned' then select to_jsonb(x) into j from public.task_occurrences x where x.id=e.source_id and x.family_id=e.family_id;
 else return; -- health and unknown topics can never enter this transport
 end case;
 if j is null then return;end if;
 t:=(j->>'teen_id')::uuid;dt:=coalesce((j->>'local_date')::date,(j->>'target_date')::date);
 sender:=case when r='teen' then coalesce((j->>'parent_user_id')::uuid,(j->>'created_by')::uuid) else null end;
 insert into public.family_notices(source_event_id,recipient_user_id,family_id,recipient_role,teen_id,local_date,destination,created_at,expires_at)
 select e.id,m.user_id,e.family_id,m.role,case when m.role='teen' then m.actor_id else t end,dt,dest,e.created_at,
  case when dest='school' then least(e.created_at+interval '7 days',timestamp '2026-11-28 00:00:00' at time zone 'America/Costa_Rica') else e.created_at+interval '7 days' end
 from public.memberships m where m.family_id=e.family_id and m.active and m.role=r and (r='parent' or t is null or m.actor_id=t) and m.user_id is distinct from sender
 on conflict(source_event_id,recipient_user_id) do nothing;
end $$;
create function petal_private.family_notice_outbox() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- A notice failure must not roll back a committed business mutation. Claim reconciles retained outbox facts.
 begin perform petal_private.materialize_family_notice(new.id);exception when others then null;end;return new;
end $$;
create trigger phase10_notice_outbox after insert on petal_private.outbox for each row execute function petal_private.family_notice_outbox();
create function petal_private.family_change_outbox() returns trigger language plpgsql security definer set search_path='' as $$
declare topic_name text;
begin
 topic_name:=case tg_table_name when 'assigned_routine_versions' then 'routine.updated' when 'catalogue_versions' then 'catalogue.updated' else 'task.assigned' end;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(new.family_id,topic_name,new.id,'{}'::jsonb) on conflict(topic,source_id) do nothing;return new;
end $$;
create trigger phase10_routine_outbox after insert on public.assigned_routine_versions for each row execute function petal_private.family_change_outbox();
create trigger phase10_catalogue_outbox after insert on public.catalogue_versions for each row execute function petal_private.family_change_outbox();
create trigger phase10_task_outbox after insert on public.task_occurrences for each row execute function petal_private.family_change_outbox();
create function petal_private.family_delivery_authorized(p_delivery_id uuid,p_lease_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from petal_private.family_notice_deliveries q join public.family_notices n on n.event_id=q.event_id
 join petal_private.family_devices d on d.installation_id=q.installation_id join public.memberships m on m.user_id=n.recipient_user_id and m.family_id=n.family_id
 where q.id=p_delivery_id and q.lease_id=p_lease_id and q.state='leased' and q.lease_until>clock_timestamp() and n.expires_at>clock_timestamp()
 and d.active and d.binding_id=q.binding_id and d.user_id=n.recipient_user_id and d.family_id=n.family_id and d.app=n.recipient_role
 and m.active and m.role=n.recipient_role and (m.role='parent' or m.actor_id=n.teen_id));
$$;
create function public.claim_family_event_push(p_limit integer default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare e record;answer jsonb;
begin
 -- Reconcile retained committed facts even if immediate fanout failed; each source is isolated.
 for e in select id from petal_private.outbox where created_at>clock_timestamp()-interval '7 days' order by created_at loop
 begin perform petal_private.materialize_family_notice(e.id);exception when others then null;end;
 end loop;
 insert into petal_private.family_notice_deliveries(event_id,installation_id,binding_id)
 select n.event_id,d.installation_id,d.binding_id from public.family_notices n join petal_private.family_devices d on d.user_id=n.recipient_user_id and d.family_id=n.family_id and d.app=n.recipient_role
 join public.memberships m on m.user_id=n.recipient_user_id and m.family_id=n.family_id
 where n.expires_at>clock_timestamp() and d.active and m.active and m.role=n.recipient_role and (m.role='parent' or m.actor_id=n.teen_id)
 on conflict(event_id,installation_id,binding_id) do nothing;
 update petal_private.family_notice_deliveries q set state='dead',lease_id=null,lease_until=null
 where state in ('pending','leased') and ((attempts>=8 and (state='pending' or lease_until<=clock_timestamp())) or exists(select 1 from public.family_notices n where n.event_id=q.event_id and n.expires_at<=clock_timestamp()));
 with candidates as (
 select q.id from petal_private.family_notice_deliveries q join public.family_notices n on n.event_id=q.event_id
 join petal_private.family_devices d on d.installation_id=q.installation_id join public.memberships m on m.user_id=n.recipient_user_id and m.family_id=n.family_id
 where (q.state='pending' or (q.state='leased' and q.lease_until<=clock_timestamp())) and q.next_attempt_at<=clock_timestamp() and q.attempts<8 and n.expires_at>clock_timestamp()
 and d.active and d.binding_id=q.binding_id and d.user_id=n.recipient_user_id and d.family_id=n.family_id and d.app=n.recipient_role
 and m.active and m.role=n.recipient_role and (m.role='parent' or m.actor_id=n.teen_id)
 order by q.next_attempt_at,q.id for update of q skip locked limit greatest(1,least(coalesce(p_limit,10),20))
 ), claimed as (
 update petal_private.family_notice_deliveries q set state='leased',attempts=q.attempts+1,lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '90 seconds'
 from candidates c where q.id=c.id returning q.*)
 select coalesce(jsonb_agg(jsonb_build_object('delivery_id',q.id,'lease_id',q.lease_id,'event_id',n.event_id)), '[]'::jsonb) into answer
 from claimed q join public.family_notices n on n.event_id=q.event_id;
 return jsonb_build_object('deliveries',answer);
end $$;
create function public.authorize_family_event_push(p_delivery_id uuid,p_lease_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return coalesce((select jsonb_build_object('authorized',true,'token',d.token,'event_id',n.event_id,'recipient_user_id',n.recipient_user_id,'family_id',n.family_id,'teen_id',n.teen_id,'local_date',n.local_date,'destination',n.destination,'expires_at',n.expires_at)
 from petal_private.family_notice_deliveries q join public.family_notices n on n.event_id=q.event_id join petal_private.family_devices d on d.installation_id=q.installation_id where q.id=p_delivery_id and petal_private.family_delivery_authorized(p_delivery_id,p_lease_id)),jsonb_build_object('authorized',false));
end $$;
create function public.complete_family_event_push(p_delivery_id uuid,p_lease_id uuid,p_success boolean,p_invalid_token boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare q petal_private.family_notice_deliveries%rowtype;
begin
 select * into q from petal_private.family_notice_deliveries where id=p_delivery_id for update;
 if not found or q.lease_id is distinct from p_lease_id or q.state<>'leased' or q.lease_until<=clock_timestamp() then return jsonb_build_object('status','stale_lease');end if;
 if p_invalid_token then update petal_private.family_devices set active=false where installation_id=q.installation_id and binding_id=q.binding_id;end if;
 update petal_private.family_notice_deliveries set state=case when p_success then 'done' when p_invalid_token or q.attempts>=8 or not petal_private.family_delivery_authorized(p_delivery_id,p_lease_id) then 'dead' else 'pending' end,
 next_attempt_at=clock_timestamp()+make_interval(secs=>least(3600,30*(2^least(q.attempts,7))::integer)),lease_id=null,lease_until=null where id=q.id;
 return jsonb_build_object('status',(select state from petal_private.family_notice_deliveries where id=q.id));
end $$;
-- Revocation invalidates leases and registrations before the next worker authorization.
create function petal_private.revoke_family_device_binding() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not new.active or new.family_id is distinct from old.family_id or new.role is distinct from old.role or new.actor_id is distinct from old.actor_id then
 update petal_private.family_devices set active=false,binding_id=gen_random_uuid() where user_id=old.user_id;end if;return new;
end $$;
create trigger phase10_membership_device_revoke after update on public.memberships for each row execute function petal_private.revoke_family_device_binding();
revoke execute on function public.register_family_device(uuid,text,text,uuid),public.unregister_family_device(uuid,uuid),public.list_family_notices(integer,timestamptz) from public,anon;
grant execute on function public.register_family_device(uuid,text,text,uuid),public.unregister_family_device(uuid,uuid),public.list_family_notices(integer,timestamptz) to authenticated;
revoke execute on function public.claim_family_event_push(integer),public.authorize_family_event_push(uuid,uuid),public.complete_family_event_push(uuid,uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.claim_family_event_push(integer),public.authorize_family_event_push(uuid,uuid),public.complete_family_event_push(uuid,uuid,boolean,boolean) to service_role;
revoke execute on function petal_private.materialize_family_notice(uuid),petal_private.family_notice_outbox(),petal_private.family_change_outbox(),petal_private.family_delivery_authorized(uuid,uuid),petal_private.revoke_family_device_binding() from public,anon,authenticated;
-- Publication is explicitly allowlisted; no private, health, device, Auth or session tables.
do $$ declare t text;begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime' and puballtables) then raise exception 'realtime_publication_must_be_explicit_allowlist';end if;
 if exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and (schemaname<>'public' or tablename not in ('family_notices','families','memberships','family_actors','task_definitions','rule_versions','task_occurrences','submissions','decisions','xp_events','day_results','reward_requests','daily_accounting','wallet_events','deduction_entries','submission_reviews','extra_outcome_requests','day_appeals','catalogue_versions','parent_actions','day_tasksets','assigned_routine_versions','occurrence_corrections','deduction_reversals','bonus_activities','bonus_reviews','appeal_resolutions','reflection_notes','reflection_note_history'))) then raise exception 'Remove tables outside the authorized family allowlist from Realtime before Phase10';end if;
 if not exists(select 1 from pg_publication where pubname='supabase_realtime') then create publication supabase_realtime;end if;
 foreach t in array array['family_notices','memberships','family_actors','task_occurrences','submissions','submission_reviews','day_results','reward_requests','extra_outcome_requests','day_appeals','assigned_routine_versions','parent_actions'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime add table public.%I',t);end if;
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
