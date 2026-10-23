-- DEVELOPMENT ONLY. Coalesce automatic duty lists/catalogue batches, preserving source facts.
-- Run only after the notification diagnostic confirms the expected development schema.
begin;
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
commit;
select exists(select 1 from pg_indexes where schemaname='public' and indexname='family_notice_alert_group') as grouped_notices_ready,
 position('alert_group_key' in pg_get_functiondef('petal_private.materialize_family_notice(uuid)'::regprocedure))>0 as grouped_fanout_ready,
 position('enrolled_at' in pg_get_functiondef('petal_private.family_delivery_authorized(uuid,uuid)'::regprocedure))>0 as enrollment_cutoff_ready,
 position('10 minutes' in pg_get_functiondef('public.claim_family_event_push(integer)'::regprocedure))>0 as fresh_delivery_priority_ready;
