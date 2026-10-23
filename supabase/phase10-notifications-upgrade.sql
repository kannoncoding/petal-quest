-- DEVELOPMENT OWNER ONLY: accepted Phase9 -> complete Phase10; run the complete file once.
-- Includes notifications, school checklist and vacation mode. All schema changes commit together.
-- Explicit RLS is included. Do not use the dashboard's automatic RLS rewriting.
begin;
do $$ begin
 if to_regclass('public.assigned_routine_versions') is null or to_regprocedure('petal_private.phase9_audit_outbox()') is null then raise exception 'Accepted Phase9 prerequisite missing';end if;
 if to_regclass('public.family_notices') is not null or to_regclass('public.school_items') is not null or to_regclass('public.vacation_policy_versions') is not null then raise exception 'Phase10 objects already present; stop and report, do not reapply';end if;
end $$;
-- 202610220015_phase10_notifications.sql
-- Phase10 family business notices. Forward only after migrations001–014; no health transport changes.

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

-- 202610220016_phase10_school.sql
-- School checklist is unscored and distinct from immutable daily duty records.

create table public.school_items (
 id uuid primary key, family_id uuid not null references public.families(id),teen_id uuid not null,
 title text not null check(length(trim(title)) between 1 and 200),version integer not null default 1,
 completed boolean not null default false,removed boolean not null default false,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.school_change_requests (
 id uuid primary key default gen_random_uuid(),family_id uuid not null references public.families(id),teen_id uuid not null,
 item_id uuid not null references public.school_items(id),expected_version integer not null,
 action text not null check(action in ('edit','remove')),proposed_title text,
 requested_by uuid not null references auth.users(id),status text not null default 'pending' check(status in ('pending','approved','rejected','superseded')),
 decided_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),decided_at timestamptz
);
create unique index one_pending_school_change on public.school_change_requests(item_id) where status='pending';
create table public.school_item_history (
 id uuid primary key default gen_random_uuid(),family_id uuid not null references public.families(id),teen_id uuid not null,
 item_id uuid not null references public.school_items(id),actor_id uuid not null references auth.users(id),
 action text not null,before_state jsonb,after_state jsonb,request_id uuid not null,created_at timestamptz not null default clock_timestamp(),
 unique(actor_id,request_id)
);
alter table public.school_items enable row level security;
alter table public.school_change_requests enable row level security;
alter table public.school_item_history enable row level security;
revoke all on public.school_items,public.school_change_requests,public.school_item_history from public,anon,authenticated;
grant select on public.school_items,public.school_change_requests,public.school_item_history to authenticated;
create policy school_read on public.school_items for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy school_change_read on public.school_change_requests for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy school_history_read on public.school_item_history for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));

create function public.list_school_items(p_family_id uuid,p_teen_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform petal_private.require_identity(false);
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'family_access_required' using errcode='42501';end if;
 return jsonb_build_object('family_id',p_family_id,'teen_id',p_teen_id,'school_active',(clock_timestamp() at time zone 'America/Costa_Rica')::date<=date '2026-11-27',
 'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]') from public.school_items i where family_id=p_family_id and teen_id=p_teen_id),
 'changes',(select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at),'[]') from public.school_change_requests c where family_id=p_family_id and teen_id=p_teen_id));
end $$;

create function public.school_item_action(p_family_id uuid,p_teen_id uuid,p_item_id uuid,p_action text,p_title text,p_expected_version integer,p_request_id uuid,p_change_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(false);is_parent boolean;r public.school_items%rowtype;c public.school_change_requests%rowtype;answer jsonb;before_state jsonb;change_id uuid;history_id uuid;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'family_access_required' using errcode='42501';end if;
 is_parent:=petal_private.is_member(p_family_id,'parent');
 if is_parent then perform petal_private.require_identity(true);end if;
 if not exists(select 1 from public.family_actors where family_id=p_family_id and id=p_teen_id and role='teen') then raise exception 'teen_required';end if;
 answer:=petal_private.begin_request(p_request_id,'school_item_action',jsonb_build_object('family',p_family_id,'teen',p_teen_id,'item',p_item_id,'action',p_action,'title',p_title,'version',p_expected_version,'change',p_change_id));
 if answer is not null then return answer;end if;
 if p_action not in ('create','edit','remove','complete','approve','reject') or p_action is null then raise exception 'invalid_school_action';end if;
 if p_action in ('create','edit') and (p_title is null or length(trim(p_title)) not between 1 and 200) then raise exception 'invalid_school_title';end if;
 if p_action='create' then
  if (clock_timestamp() at time zone 'America/Costa_Rica')::date>date '2026-11-27' then raise exception 'school_term_ended';end if;
  insert into public.school_items(id,family_id,teen_id,title,created_by) values(p_item_id,p_family_id,p_teen_id,trim(p_title),u) returning * into r;
 else
  select * into r from public.school_items where id=p_item_id and family_id=p_family_id and teen_id=p_teen_id for update;
  if not found or r.removed then raise exception 'school_item_unavailable';end if;
  before_state:=to_jsonb(r);
  if p_action in ('approve','reject') then
   if not is_parent then raise exception 'parent_required' using errcode='42501';end if;
   select * into c from public.school_change_requests where id=p_change_id and item_id=r.id and family_id=p_family_id and teen_id=p_teen_id and status='pending' for update;
   if not found then raise exception 'school_change_unavailable';end if;
   if p_action='approve' and c.expected_version<>r.version then raise exception 'stale_school_item';end if;
   if p_action='approve' then
    update public.school_items set title=case when c.action='edit' then c.proposed_title else title end,removed=c.action='remove',version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
   end if;
   update public.school_change_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,decided_by=u,decided_at=clock_timestamp() where id=c.id;
   change_id:=c.id;
  else
   if p_expected_version is distinct from r.version then raise exception 'stale_school_item';end if;
   if p_action='complete' then
    update public.school_items set completed=true,version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
    update public.school_change_requests set status='superseded',decided_at=clock_timestamp() where item_id=r.id and status='pending';
   elsif is_parent then
    update public.school_items set title=case when p_action='edit' then trim(p_title) else title end,removed=p_action='remove',version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
    update public.school_change_requests set status='superseded',decided_at=clock_timestamp() where item_id=r.id and status='pending';
   else
    insert into public.school_change_requests(family_id,teen_id,item_id,expected_version,action,proposed_title,requested_by)
    values(p_family_id,p_teen_id,r.id,r.version,p_action,case when p_action='edit' then trim(p_title) end,u) returning id into change_id;
   end if;
  end if;
 end if;
 insert into public.school_item_history(family_id,teen_id,item_id,actor_id,action,before_state,after_state,request_id)
 values(p_family_id,p_teen_id,r.id,u,p_action,before_state,to_jsonb(r)||jsonb_build_object('change_id',change_id),p_request_id) returning id into history_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(p_family_id,
  case when p_action in ('approve','reject') then 'school.change_reviewed' when change_id is not null then 'school.change_requested' else 'school.item_saved' end,
  coalesce(change_id,history_id),jsonb_build_object('teen_id',p_teen_id));
 answer:=jsonb_build_object('request_id',p_request_id,'item',to_jsonb(r),'change_id',change_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
revoke execute on function public.list_school_items(uuid,uuid),public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) from public,anon;
grant execute on function public.list_school_items(uuid,uuid),public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) to authenticated;
alter publication supabase_realtime add table public.school_items,public.school_change_requests;

-- 202610220017_phase10_vacations.sql
-- Vacation overlays affect NEW occurrence snapshots only. Existing facts/wallets never change.

create table public.vacation_policy_versions (
 id uuid primary key default gen_random_uuid(),family_id uuid not null references public.families(id),
 effective_from date not null,enabled boolean not null,created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp()
);
alter table public.vacation_policy_versions enable row level security;
revoke all on public.vacation_policy_versions from public,anon,authenticated;
grant select on public.vacation_policy_versions to authenticated;
create policy family_read on public.vacation_policy_versions for select to authenticated using(petal_private.is_member(family_id));
create function petal_private.is_vacation(p_family_id uuid,p_date date) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select enabled from (
  select effective_from,enabled,created_at,1 priority,id::text tie from public.vacation_policy_versions where family_id=p_family_id and effective_from<=p_date
  union all select date '2026-11-28',true,'1970-01-01'::timestamptz,0,'' where p_date>=date '2026-11-28'
 ) v order by effective_from desc,priority desc,created_at desc,tie desc limit 1),false);
$$;
create function petal_private.vacation_day_catalogue(p_family_id uuid,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare answer jsonb;total integer;
begin
 -- Use the effective catalogue, including Parent edits, before calculating the vacation overlay.
 with baseline as (
  select d.id definition_id,d.catalogue_key,
   coalesce(v.payload->>'title',d.title) title,coalesce((v.payload->>'points')::integer,r.points) points,
   case when v.id is null then r.local_due_time::text else v.payload->>'local_due_time' end due,
   case when v.id is null then r.weekdays else array(select value::integer from jsonb_array_elements_text(v.payload->'weekdays')) end weekdays,
   coalesce((v.payload->>'enabled')::boolean,d.enabled) enabled
  from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
  left join lateral(select * from public.catalogue_versions where family_id=p_family_id and catalogue_key=d.catalogue_key and kind in ('task','rule') and effective_from<=p_date order by effective_from desc,created_at desc,id desc limit 1) v on true
  where d.family_id=p_family_id
 ), active as (
  select *,catalogue_key in ('duty-wd-003','duty-we-004') removed,
   catalogue_key not in ('duty-wd-003','duty-we-004','duty-wd-007','duty-we-007','duty-wd-008','duty-we-008','duty-wd-009','duty-we-009','duty-wd-010','duty-we-010','duty-wd-011','duty-we-011','duty-wd-012','duty-we-012','duty-wd-013','duty-we-013') eligible
  from baseline where enabled and extract(dow from p_date)::integer=any(weekdays)
 ), amounts as (
  select *,sum(points) filter(where removed) over() removed_points,sum(points) filter(where eligible) over() eligible_points from active
 ), fractions as (
  select *,case when eligible then coalesce(removed_points,0)*points::numeric/nullif(eligible_points,0) else 0 end extra from amounts where not removed
 ), ranked as (
  select *,row_number() over(order by (extra-floor(extra)) desc,eligible desc,catalogue_key) remainder_rank,
   coalesce(removed_points,0)-sum(floor(extra)) over() remainder_count from fractions
 ) select coalesce(jsonb_agg(jsonb_build_object('definition_id',definition_id,'catalogue_key',catalogue_key,
  'title',case catalogue_key when 'duty-wd-002' then 'Shower + Room @4PM' when 'duty-wd-005' then 'Room clean up @6PM' else title end,
  'points',points+floor(extra)::integer+case when eligible and remainder_rank<=remainder_count then 1 else 0 end,
  'local_due_time',due,'weekdays',weekdays,'enabled',true) order by catalogue_key),'[]') into answer from ranked;
 select coalesce(sum((value->>'points')::integer),0) into total from jsonb_array_elements(answer);
 if total<>100 then raise exception 'vacation_day_must_total_100';end if;
 return answer;
end $$;
create function public.set_vacation_schedule(p_family_id uuid,p_start_date date,p_end_date date,p_expected_version uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);answer jsonb;dt date;today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'set_vacation_schedule',jsonb_build_object('family',p_family_id,'start',p_start_date,'end',p_end_date,'expected',p_expected_version));if answer is not null then return answer;end if;
 if (select id from public.vacation_policy_versions where family_id=p_family_id order by created_at desc,id desc limit 1) is distinct from p_expected_version then raise exception 'stale_vacation_policy';end if;
 if p_start_date is null or p_start_date<=today or p_end_date<p_start_date then raise exception 'future_vacation_dates_required';end if;
 -- Validate each weekday against the actual effective baseline before accepting the schedule.
 for dt in select p_start_date+i from generate_series(0,6) as s(i) loop perform petal_private.vacation_day_catalogue(p_family_id,dt);end loop;
 insert into public.vacation_policy_versions(family_id,effective_from,enabled,created_by) values(p_family_id,p_start_date,true,u);
 if p_end_date is not null then insert into public.vacation_policy_versions(family_id,effective_from,enabled,created_by) values(p_family_id,p_end_date+1,false,u);end if;
 answer:=jsonb_build_object('request_id',p_request_id,'starts',p_start_date,'ends',p_end_date);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function public.end_vacation_mode(p_family_id uuid,p_effective_from date,p_expected_version uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);answer jsonb;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'end_vacation_mode',jsonb_build_object('family',p_family_id,'from',p_effective_from,'expected',p_expected_version));if answer is not null then return answer;end if;
 if (select id from public.vacation_policy_versions where family_id=p_family_id order by created_at desc,id desc limit 1) is distinct from p_expected_version then raise exception 'stale_vacation_policy';end if;
 if p_effective_from is null or p_effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'future_vacation_dates_required';end if;
 insert into public.vacation_policy_versions(family_id,effective_from,enabled,created_by) values(p_family_id,p_effective_from,false,u);
 answer:=jsonb_build_object('request_id',p_request_id,'school_mode_from',p_effective_from);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function public.get_vacation_preview(p_family_id uuid,p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform petal_private.require_identity(true);
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 if p_date is null then raise exception 'date_required';end if;
 return jsonb_build_object('family_id',p_family_id,'local_date',p_date,'tasks',petal_private.vacation_day_catalogue(p_family_id,p_date),'maximum',100);
end $$;
create function petal_private.snapshot_vacation_occurrence() returns trigger language plpgsql security definer set search_path='' as $$
declare row_data jsonb;source text;r uuid;n integer;
begin
 if not petal_private.is_vacation(new.family_id,new.local_date) then return new;end if;
 select value into row_data from jsonb_array_elements(petal_private.vacation_day_catalogue(new.family_id,new.local_date)) where (value->>'definition_id')::uuid=new.definition_id;
 if row_data is null then return null;end if;
 source:='Phase10 vacation v1 '||md5(row_data::text);
 select id into r from public.rule_versions where definition_id=new.definition_id and approved_source=source;
 if r is null then
  select coalesce(max(version),0)+1 into n from public.rule_versions where definition_id=new.definition_id;
  insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
  values(new.family_id,new.definition_id,n,(row_data->>'points')::integer,(row_data->>'local_due_time')::time,array(select value::integer from jsonb_array_elements_text(row_data->'weekdays')),false,source) returning id into r;
 end if;
 new.rule_version_id:=r;new.title_snapshot:=row_data->>'title';new.points_snapshot:=(row_data->>'points')::integer;
 return new;
end $$;
create trigger zz_phase10_vacation_snapshot before insert on public.task_occurrences for each row execute function petal_private.snapshot_vacation_occurrence();
create function petal_private.vacation_metadata(p_family_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('active',petal_private.is_vacation(p_family_id,(clock_timestamp() at time zone 'America/Costa_Rica')::date),'automatic_start','2026-11-28','last_school_day','2026-11-27',
  'latest_version',(select id from public.vacation_policy_versions where family_id=p_family_id order by created_at desc,id desc limit 1),
  'schedule',(select coalesce(jsonb_agg(to_jsonb(v) order by effective_from,created_at),'[]') from public.vacation_policy_versions v where family_id=p_family_id));
$$;
alter function public.list_school_items(uuid,uuid) rename to list_school_items_before_vacations;
create function public.list_school_items(p_family_id uuid,p_teen_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;begin
 answer:=public.list_school_items_before_vacations(p_family_id,p_teen_id);
 return answer||jsonb_build_object('school_active',(answer->>'school_active')::boolean and not petal_private.is_vacation(p_family_id,(clock_timestamp() at time zone 'America/Costa_Rica')::date));
end $$;
alter function public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) rename to school_item_action_before_vacations;
create function public.school_item_action(p_family_id uuid,p_teen_id uuid,p_item_id uuid,p_action text,p_title text,p_expected_version integer,p_request_id uuid,p_change_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;begin
 perform petal_private.require_identity(false);
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'family_access_required' using errcode='42501';end if;
 -- Idempotent receipts are replayable even when the term or mode changed after original commit.
 select result into answer from petal_private.idempotency where user_id=auth.uid() and request_id=p_request_id;
 if answer is null and p_action not in ('approve','reject') and ((clock_timestamp() at time zone 'America/Costa_Rica')::date>date '2026-11-27' or petal_private.is_vacation(p_family_id,(clock_timestamp() at time zone 'America/Costa_Rica')::date)) then raise exception 'school_term_inactive';end if;
 return public.school_item_action_before_vacations(p_family_id,p_teen_id,p_item_id,p_action,p_title,p_expected_version,p_request_id,p_change_id);
end $$;
revoke execute on function public.list_school_items_before_vacations(uuid,uuid),public.school_item_action_before_vacations(uuid,uuid,uuid,text,text,integer,uuid,uuid) from public,anon,authenticated;
revoke execute on function public.list_school_items(uuid,uuid),public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) from public,anon;
grant execute on function public.list_school_items(uuid,uuid),public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) to authenticated;
alter function petal_private.get_parent_dashboard(uuid,uuid,date,date) rename to get_parent_dashboard_before_vacations;
create function petal_private.get_parent_dashboard(p_family_id uuid,p_teen_id uuid,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;begin answer:=petal_private.get_parent_dashboard_before_vacations(p_family_id,p_teen_id,p_from,p_to);return answer||jsonb_build_object('vacation',petal_private.vacation_metadata(p_family_id));end $$;
alter function petal_private.get_teen_dashboard(date,date) rename to get_teen_dashboard_before_vacations;
create function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;begin answer:=petal_private.get_teen_dashboard_before_vacations(p_from,p_to);return answer||jsonb_build_object('vacation',petal_private.vacation_metadata((answer->>'family_id')::uuid));end $$;
revoke execute on function petal_private.get_parent_dashboard_before_vacations(uuid,uuid,date,date),petal_private.get_teen_dashboard_before_vacations(date,date),petal_private.is_vacation(uuid,date),petal_private.vacation_day_catalogue(uuid,date),petal_private.snapshot_vacation_occurrence(),petal_private.vacation_metadata(uuid) from public,anon,authenticated;
revoke execute on function petal_private.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_teen_dashboard(date,date),public.set_vacation_schedule(uuid,date,date,uuid,uuid),public.end_vacation_mode(uuid,date,uuid,uuid) from public,anon;
grant execute on function petal_private.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_teen_dashboard(date,date),public.set_vacation_schedule(uuid,date,date,uuid,uuid),public.end_vacation_mode(uuid,date,uuid,uuid) to authenticated;
revoke execute on function public.get_vacation_preview(uuid,date) from public,anon;
grant execute on function public.get_vacation_preview(uuid,date) to authenticated;
alter publication supabase_realtime add table public.vacation_policy_versions;
notify pgrst,'reload schema';

-- 202610230018_phase10_notice_coalescing.sql
-- DEVELOPMENT ONLY. Coalesce automatic duty lists/catalogue batches, preserving source facts.
-- Run only after the notification diagnostic confirms the expected development schema.

do $$ begin
 if to_regclass('public.family_notices') is null or to_regclass('public.school_items') is null then raise exception 'Phase10 schema missing; stop and verify the project/database';end if;
end $$;
alter table public.family_notices add column if not exists alert_group_key text;
alter table petal_private.family_devices add column if not exists enrolled_at timestamptz;
update petal_private.family_devices set enrolled_at=updated_at where enrolled_at is null;
alter table petal_private.family_devices alter column enrolled_at set default clock_timestamp();
alter table petal_private.family_devices alter column enrolled_at set not null;
-- Retain every prior notice for audit; expire only redundant entries in the same logical update.
with groups as (
 select n.event_id,n.recipient_user_id,n.family_id,
  case when e.topic='task.assigned' then 'task_day:'||n.teen_id::text||':'||n.local_date::text
   when e.topic='catalogue.updated' then 'catalogue:'||c.kind||':'||c.effective_from::text end group_key
 from public.family_notices n join petal_private.outbox e on e.id=n.source_event_id
 left join public.catalogue_versions c on e.topic='catalogue.updated' and c.id=e.source_id and c.family_id=n.family_id
 where e.topic in ('task.assigned','catalogue.updated')
), ranked as (
 select g.*,row_number() over(partition by g.recipient_user_id,g.family_id,g.group_key order by n.created_at,n.event_id) group_position
 from groups g join public.family_notices n on n.event_id=g.event_id where group_key is not null
)
update public.family_notices n set alert_group_key=case when r.group_position=1 then r.group_key end,
 expires_at=case when r.group_position>1 then least(n.expires_at,clock_timestamp()) else n.expires_at end
from ranked r where n.event_id=r.event_id;
create unique index if not exists family_notice_alert_group on public.family_notices(recipient_user_id,family_id,alert_group_key) where alert_group_key is not null;
update petal_private.family_notice_deliveries q set state='dead',lease_id=null,lease_until=null
where q.state in ('pending','leased') and exists(select 1 from public.family_notices n where n.event_id=q.event_id and n.expires_at<=clock_timestamp());
-- Suppress old backlog per installation; all committed sources and completed receipts remain intact.
update petal_private.family_notice_deliveries q set state='dead',lease_id=null,lease_until=null
from public.family_notices n,petal_private.family_devices d
where q.event_id=n.event_id and q.installation_id=d.installation_id and q.state in ('pending','leased') and n.created_at<d.enrolled_at;
create or replace function petal_private.materialize_family_notice(p_event_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare e petal_private.outbox%rowtype;j jsonb;t uuid;dt date;r text:='teen';dest text:='today';sender uuid;alert_group text;
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
 if e.topic='task.assigned' then alert_group:='task_day:'||t::text||':'||dt::text;
 elsif e.topic='catalogue.updated' then alert_group:='catalogue:'||(j->>'kind')||':'||(j->>'effective_from');end if;
 sender:=case when r='teen' then coalesce((j->>'parent_user_id')::uuid,(j->>'created_by')::uuid) else null end;
 insert into public.family_notices(source_event_id,recipient_user_id,family_id,recipient_role,teen_id,local_date,destination,created_at,expires_at,alert_group_key)
 select e.id,m.user_id,e.family_id,m.role,case when m.role='teen' then m.actor_id else t end,dt,dest,e.created_at,
  case when dest='school' then least(e.created_at+interval '7 days',timestamp '2026-11-28 00:00:00' at time zone 'America/Costa_Rica') else e.created_at+interval '7 days' end,alert_group
 from public.memberships m where m.family_id=e.family_id and m.active and m.role=r and (r='parent' or t is null or m.actor_id=t) and m.user_id is distinct from sender
 on conflict do nothing;
end $$;
create or replace function public.register_family_device(p_installation_id uuid,p_token text,p_app text,p_request_id uuid) returns jsonb
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
 enrolled_at=case when family_devices.user_id=u and family_devices.family_id=m.family_id and family_devices.app=m.role and family_devices.active then family_devices.enrolled_at else clock_timestamp() end,
 active=true,updated_at=clock_timestamp() returning binding_id into b;
 a:=jsonb_build_object('status','registered','installation_id',p_installation_id,'request_id',p_request_id);
 update petal_private.idempotency set result=a where user_id=u and request_id=p_request_id;return a;
end $$;
create or replace function petal_private.family_delivery_authorized(p_delivery_id uuid,p_lease_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from petal_private.family_notice_deliveries q join public.family_notices n on n.event_id=q.event_id
 join petal_private.family_devices d on d.installation_id=q.installation_id join public.memberships m on m.user_id=n.recipient_user_id and m.family_id=n.family_id
 where q.id=p_delivery_id and q.lease_id=p_lease_id and q.state='leased' and q.lease_until>clock_timestamp() and n.expires_at>clock_timestamp()
 and n.created_at>=d.enrolled_at and d.active and d.binding_id=q.binding_id and d.user_id=n.recipient_user_id and d.family_id=n.family_id and d.app=n.recipient_role
 and m.active and m.role=n.recipient_role and (m.role='parent' or m.actor_id=n.teen_id));
$$;
create or replace function public.claim_family_event_push(p_limit integer default 10) returns jsonb language plpgsql security definer set search_path='' as $$
declare e record;answer jsonb;
begin
 -- Reconcile retained committed facts even if immediate fanout failed; each source is isolated.
 for e in select id from petal_private.outbox where created_at>clock_timestamp()-interval '7 days' order by created_at loop
 begin perform petal_private.materialize_family_notice(e.id);exception when others then null;end;
 end loop;
 insert into petal_private.family_notice_deliveries(event_id,installation_id,binding_id)
 select n.event_id,d.installation_id,d.binding_id from public.family_notices n join petal_private.family_devices d on d.user_id=n.recipient_user_id and d.family_id=n.family_id and d.app=n.recipient_role
 join public.memberships m on m.user_id=n.recipient_user_id and m.family_id=n.family_id
 where n.expires_at>clock_timestamp() and n.created_at>=d.enrolled_at and d.active and m.active and m.role=n.recipient_role and (m.role='parent' or m.actor_id=n.teen_id)
 on conflict(event_id,installation_id,binding_id) do nothing;
 update petal_private.family_notice_deliveries q set state='dead',lease_id=null,lease_until=null
 where state in ('pending','leased') and ((attempts>=8 and (state='pending' or lease_until<=clock_timestamp())) or exists(select 1 from public.family_notices n where n.event_id=q.event_id and n.expires_at<=clock_timestamp()));
 with candidates as (
 select q.id from petal_private.family_notice_deliveries q join public.family_notices n on n.event_id=q.event_id
 join petal_private.family_devices d on d.installation_id=q.installation_id join public.memberships m on m.user_id=n.recipient_user_id and m.family_id=n.family_id
 where (q.state='pending' or (q.state='leased' and q.lease_until<=clock_timestamp())) and q.next_attempt_at<=clock_timestamp() and q.attempts<8 and n.expires_at>clock_timestamp()
 and n.created_at>=d.enrolled_at and d.active and d.binding_id=q.binding_id and d.user_id=n.recipient_user_id and d.family_id=n.family_id and d.app=n.recipient_role
 and m.active and m.role=n.recipient_role and (m.role='parent' or m.actor_id=n.teen_id)
 order by case when n.created_at>=clock_timestamp()-interval '10 minutes' then 0 else 1 end,q.next_attempt_at,q.id for update of q skip locked limit greatest(1,least(coalesce(p_limit,10),20))
 ), claimed as (
 update petal_private.family_notice_deliveries q set state='leased',attempts=q.attempts+1,lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '90 seconds'
 from candidates c where q.id=c.id returning q.*)
 select coalesce(jsonb_agg(jsonb_build_object('delivery_id',q.id,'lease_id',q.lease_id,'event_id',n.event_id)), '[]'::jsonb) into answer
 from claimed q join public.family_notices n on n.event_id=q.event_id;
 return jsonb_build_object('deliveries',answer);
end $$;

revoke execute on function petal_private.materialize_family_notice(uuid) from public,anon,authenticated;

select exists(select 1 from pg_indexes where schemaname='public' and indexname='family_notice_alert_group') as grouped_notices_ready,
 position('alert_group_key' in pg_get_functiondef('petal_private.materialize_family_notice(uuid)'::regprocedure))>0 as grouped_fanout_ready,
 position('enrolled_at' in pg_get_functiondef('petal_private.family_delivery_authorized(uuid,uuid)'::regprocedure))>0 as enrollment_cutoff_ready,
 position('10 minutes' in pg_get_functiondef('public.claim_family_event_push(integer)'::regprocedure))>0 as fresh_delivery_priority_ready;
select
 (select relrowsecurity from pg_class where oid='public.family_notices'::regclass) as notices_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.school_items'::regclass) as school_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.school_change_requests'::regclass) as school_changes_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.school_item_history'::regclass) as school_history_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.vacation_policy_versions'::regclass) as vacation_rls_enabled,
 not has_table_privilege('authenticated','petal_private.family_devices','SELECT') as tokens_not_client_readable,
 not has_function_privilege('authenticated','public.claim_family_event_push(integer)','EXECUTE') as claims_service_only,
 to_regprocedure('public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid)') is not null as school_actions_ready,
 to_regprocedure('petal_private.snapshot_vacation_occurrence()') is not null as vacation_snapshot_ready,
 date '2026-11-27' as last_school_day, date '2026-11-28' as automatic_vacation_start,
 to_regprocedure('petal_private.wake_family_events_worker()') is not null as webhook_setup_present;
commit;
