-- LOCAL PHASE9 FORWARD UPGRADE. Review before applying. This generator executes no SQL.
begin;
do $phase9_preflight$
begin
 if to_regprocedure('public.get_teen_dashboard(date,date)') is null
 or to_regclass('public.day_appeals') is null then
  raise exception 'Accepted Phase8 prerequisite missing; stop and report this message.';
 end if;
 if to_regclass('public.catalogue_versions') is not null then
  raise exception 'Phase9 already exists; do not rerun this initial forward upgrade.';
 end if;
end $phase9_preflight$;
-- SOURCE: migrations/202610210008_phase9_parent.sql
-- Local Phase9 forward migration. No database execution or cloud deployment.

create table public.catalogue_versions (
 id uuid primary key default gen_random_uuid(),family_id uuid not null references public.families(id),
 kind text not null check(kind in ('task','rule','reward')),catalogue_key text not null,effective_from date not null,
 payload jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(family_id,kind,catalogue_key,effective_from)
);
create table public.parent_actions (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,
 source_kind text not null,source_id uuid not null,outcome text not null,note text not null check(length(note)<=2000),
 snapshot jsonb not null,parent_user_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(source_kind,source_id,outcome),foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
alter table public.catalogue_versions enable row level security;
alter table public.parent_actions enable row level security;
revoke all on public.catalogue_versions,public.parent_actions from public,anon,authenticated;
grant select on public.catalogue_versions,public.parent_actions to authenticated;
create policy family_read on public.catalogue_versions for select to authenticated using(petal_private.is_member(family_id));
create policy subject_read on public.parent_actions for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
-- Immutable saved achievement award; requests never take an amount from a client.
alter table public.extra_outcome_requests add column catalogue_snapshot jsonb;
update public.extra_outcome_requests r set catalogue_snapshot=coalesce((select x from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'achievements') x where x->>'id'=r.outcome_key),jsonb_build_object('id',r.outcome_key,'kind',r.kind));
create function petal_private.snapshot_extra_outcome() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind='achievement' then select x into new.catalogue_snapshot from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'achievements') x where x->>'id'=new.outcome_key;
 else new.catalogue_snapshot:=jsonb_build_object('id',new.outcome_key,'kind',new.kind);end if;return new;
end $$;
create function petal_private.save_catalogue_version(p_family_id uuid,p_kind text,p_catalogue_key text,p_effective_from date,p_payload jsonb,p_request_id uuid,p_expected_version uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);answer jsonb;r public.catalogue_versions%rowtype;days integer[];v text;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'save_catalogue_version',jsonb_build_object('family_id',p_family_id,'kind',p_kind,'key',p_catalogue_key,'effective_from',p_effective_from,'payload',p_payload,'expected_version',p_expected_version));
 if answer is not null then return answer;end if;
 if (select id from public.catalogue_versions where family_id=p_family_id order by created_at desc,id desc limit 1) is distinct from p_expected_version then raise exception 'stale_catalogue_refresh_required';end if;
 if p_effective_from is null or p_effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'future_effective_date_required';end if;
 if p_kind not in ('task','rule','reward') or p_kind is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid_catalogue_version';end if;
 if length(trim(coalesce(p_payload->>'title',''))) not between 1 and 200 then raise exception 'title_required';end if;
 if p_kind in ('task','rule') then
 if not exists(select 1 from public.task_definitions where family_id=p_family_id and catalogue_key=p_catalogue_key) then raise exception 'unknown_task';end if;
 if coalesce((p_payload->>'points')::integer,0) not between 1 and 100 then raise exception 'invalid_points';end if;
 select array_agg(value::integer) into days from jsonb_array_elements_text(p_payload->'weekdays');
 if coalesce(cardinality(days),0)=0 or not days <@ array[0,1,2,3,4,5,6] then raise exception 'invalid_weekdays';end if;
 v:=p_payload->>'local_due_time';if v is not null then perform v::time;end if;
 if jsonb_typeof(p_payload->'enabled') is distinct from 'boolean' then raise exception 'enabled_required';end if;
 else
 if not exists(select 1 from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'rewards') x where x->>'id'=p_catalogue_key) then raise exception 'unknown_reward';end if;
 if coalesce((p_payload->>'coinCost')::integer,0)<=0 or coalesce(p_payload->>'sourceStatus','') not in ('Available','Unavailable') then raise exception 'invalid_reward';end if;
 end if;
 insert into public.catalogue_versions(family_id,kind,catalogue_key,effective_from,payload,created_by) values(p_family_id,p_kind,p_catalogue_key,p_effective_from,p_payload,u) returning * into r;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create trigger snapshot_extra_outcome before insert on public.extra_outcome_requests for each row execute function petal_private.snapshot_extra_outcome();
create function petal_private.review_reward_request(p_reward_request_id uuid,p_outcome text,p_note text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);r public.reward_requests%rowtype;answer jsonb;
begin
 select * into r from public.reward_requests where id=p_reward_request_id;
 if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=r.family_id for update;
 if not petal_private.is_member(r.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'review_reward_request',jsonb_build_object('id',p_reward_request_id,'outcome',p_outcome,'note',coalesce(p_note,'')));
 if answer is not null then return answer;end if;
 select * into r from public.reward_requests where id=p_reward_request_id for update;
 if p_outcome='approved' then answer:=petal_private.approve_reward_request(r.id,gen_random_uuid());
 elsif p_outcome='cancelled' then answer:=petal_private.cancel_reward_request(r.id,gen_random_uuid());
 elsif p_outcome='fulfilled' then
 if r.status not in ('approved','fulfilled') then raise exception 'approved_reward_required';end if;
 if r.status<>'fulfilled' then update public.reward_requests set status='fulfilled',updated_at=clock_timestamp() where id=r.id returning * into r;end if;answer:=to_jsonb(r);
 else raise exception 'invalid_reward_outcome';end if;
 insert into public.parent_actions(family_id,teen_id,source_kind,source_id,outcome,note,snapshot,parent_user_id) values(r.family_id,r.teen_id,'reward',r.id,p_outcome,coalesce(p_note,''),answer,u) on conflict(source_kind,source_id,outcome) do nothing;
 answer:=answer||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.review_extra_outcome(p_outcome_request_id uuid,p_outcome text,p_note text,p_request_id uuid,p_cash_amount integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);r public.extra_outcome_requests%rowtype;answer jsonb;award integer:=0;a public.parent_actions%rowtype;
begin
 select * into r from public.extra_outcome_requests where id=p_outcome_request_id;
 if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=r.family_id for update;
 if not petal_private.is_member(r.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'review_extra_outcome',jsonb_build_object('id',p_outcome_request_id,'outcome',p_outcome,'note',coalesce(p_note,''),'cash_amount',p_cash_amount));
 if answer is not null then return answer;end if;
 select * into r from public.extra_outcome_requests where id=p_outcome_request_id for update;
 if p_cash_amount is not null and r.kind<>'cash' then raise exception 'cash_request_required';end if;
 if p_outcome not in ('confirmed','declined') or p_outcome is null then raise exception 'invalid_outcome';end if;
 select * into a from public.parent_actions where source_kind='extra_outcome' and source_id=r.id;
 if found then
 if a.outcome<>p_outcome then raise exception 'outcome_already_resolved';end if;
 answer:=to_jsonb(a);
 else
 if r.status<>'requested' then raise exception 'outcome_already_resolved';end if;
 if r.kind='cash' and p_outcome='confirmed' and (p_cash_amount is null or p_cash_amount<0 or length(trim(coalesce(p_note,'')))=0) then raise exception 'explicit_cash_amount_and_reason_required';end if;
 if p_outcome='confirmed' and r.kind='achievement' then
 award:=(r.catalogue_snapshot->>'xp')::integer;
 if award is null or award<=0 then raise exception 'saved_achievement_xp_required';end if;
 -- Explicit parent confirmation identifies this qualifying accomplishment request.
 insert into public.wallet_events(family_id,teen_id,source_key,earned_xp_delta,coin_delta) values(r.family_id,r.teen_id,'achievement:'||r.id,award,award);
 end if;
 insert into public.parent_actions(family_id,teen_id,source_kind,source_id,outcome,note,snapshot,parent_user_id) values(r.family_id,r.teen_id,'extra_outcome',r.id,p_outcome,coalesce(p_note,''),r.catalogue_snapshot||jsonb_build_object('awarded_xp',award,'cash_payment_automatic',false,'cash_amount',p_cash_amount),u) returning * into a;
 update public.extra_outcome_requests set status=p_outcome where id=r.id;answer:=to_jsonb(a);
 end if;
 answer:=answer||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;


-- Effective versions are selected at occurrence creation; existing snapshots are never rewritten.
create or replace function petal_private.snapshot_occurrence_title() returns trigger language plpgsql security definer set search_path='' as $$
declare d public.task_definitions%rowtype;v public.catalogue_versions%rowtype;r uuid;n integer;
begin
 select * into d from public.task_definitions where id=new.definition_id and family_id=new.family_id;
 new.title_snapshot:=d.title;
 select * into v from public.catalogue_versions where family_id=new.family_id and catalogue_key=d.catalogue_key and kind in ('task','rule') and effective_from<=new.local_date order by effective_from desc,created_at desc,id desc limit 1;
 if found then
 if not (v.payload->>'enabled')::boolean or not exists(select 1 from jsonb_array_elements_text(v.payload->'weekdays') w where w::integer=extract(dow from new.local_date)::integer) then return null;end if;
 select id into r from public.rule_versions where definition_id=d.id and approved_source='Phase9 catalogue version '||v.id;
 if r is null then
 select coalesce(max(version),0)+1 into n from public.rule_versions where definition_id=d.id;
 insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
 values(d.family_id,d.id,n,(v.payload->>'points')::integer,(v.payload->>'local_due_time')::time,array(select value::integer from jsonb_array_elements_text(v.payload->'weekdays')),false,'Phase9 catalogue version '||v.id) returning id into r;
 end if;
 new.rule_version_id:=r;new.points_snapshot:=(v.payload->>'points')::integer;new.title_snapshot:=v.payload->>'title';new.due_at:=case when v.payload->>'local_due_time' is not null then (new.local_date+(v.payload->>'local_due_time')::time) at time zone 'America/Costa_Rica' end;
 end if;return new;
end $$;
create or replace function petal_private.materialize_teen_tasks() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501';end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501';end if;
 insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at,title_snapshot)
 select d.family_id,d.id,m.actor_id,r.id,today,r.points,case when r.local_due_time is not null then (today+r.local_due_time) at time zone 'America/Costa_Rica' end,d.title
 from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
 where d.family_id=m.family_id and ((d.enabled and extract(dow from today)::integer=any(r.weekdays)) or exists(select 1 from public.catalogue_versions v where v.family_id=d.family_id and v.catalogue_key=d.catalogue_key and v.kind in ('task','rule') and v.effective_from<=today))
 on conflict(definition_id,teen_id,local_date,slot_key) do nothing;
 return jsonb_build_object('server_local_date',today,'status','ready');
end $$;
create or replace function petal_private.request_reward(p_reward_key text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;item jsonb;answer jsonb;r public.reward_requests%rowtype;v public.catalogue_versions%rowtype;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501';end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'request_reward',jsonb_build_object('reward_key',p_reward_key));if answer is not null then return answer;end if;
 select value into item from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'rewards') where value->>'id'=p_reward_key;
 select * into v from public.catalogue_versions where family_id=m.family_id and kind='reward' and catalogue_key=p_reward_key and effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date order by effective_from desc,created_at desc,id desc limit 1;
 if found then item:=v.payload||jsonb_build_object('id',p_reward_key);end if;
 if item is null or item->>'sourceStatus'<>'Available' then raise exception 'reward_unavailable';end if;
 insert into public.reward_requests(family_id,teen_id,title_snapshot,price_snapshot,catalogue_key) values(m.family_id,m.actor_id,item->>'title',(item->>'coinCost')::integer,p_reward_key) returning * into r;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'reward.requested',r.id,jsonb_build_object('reward_request_id',r.id));return answer;
end $$;
create function petal_private.get_parent_dashboard(p_family_id uuid,p_teen_id uuid,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;t uuid;tasks jsonb;days jsonb;answer jsonb;c jsonb;
begin
 select family_id into f from public.memberships where user_id=u and active and role='parent' and (p_family_id is null or family_id=p_family_id);
 if f is null then raise exception 'parent_required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then raise exception 'invalid_history_range';end if;
 select id into t from public.family_actors where family_id=f and role='teen' and (p_teen_id is null or id=p_teen_id) order by enrolled_at,id limit 1;
 if p_teen_id is not null and t is null then raise exception 'teen_required';end if;
 select catalogue into c from petal_private.phase8_catalogue where singleton;
 select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('catalogue_key',d.catalogue_key,'status',coalesce(s.status,'open'),'submission_id',s.id,'review_version',s.review_version,'submitted_at',s.submitted_at,'decision_id',dc.id,'reviewed_at',dc.decided_at,'submission_ready',coalesce(clock_timestamp()<petal_private.day_deadline(f,t,o.local_date),true),'effective_seal_at',petal_private.day_deadline(f,t,o.local_date),'is_late',case when o.due_at is not null then coalesce(s.submitted_at,clock_timestamp())>o.due_at end,'review_note',(select review_note from public.submission_reviews rv where rv.submission_id=s.id order by reviewed_at desc,id desc limit 1)) order by o.local_date,o.due_at nulls last,o.id),'[]') into tasks from public.task_occurrences o join public.task_definitions d on d.id=o.definition_id left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id where o.family_id=f and o.teen_id=t and o.local_date between p_from and p_to;
 with dates as(select local_date from public.task_occurrences where family_id=f and teen_id=t and local_date between p_from and p_to union select local_date from public.day_results where family_id=f and teen_id=t and local_date between p_from and p_to)
 select coalesce(jsonb_agg(jsonb_build_object('local_date',dt.local_date,'week_start',dt.local_date-extract(dow from dt.local_date)::integer,'first_published_at',dr.first_published_at,'effective_seal_at',dr.effective_seal_at,'status',case when dr.first_published_at is null then 'pending' when clock_timestamp()>=dr.effective_seal_at then 'sealed' else 'finalized' end,'revision',a.revision,'actual_score',a.actual_score,'virtual_remaining',a.virtual_remaining,'protected_score',a.protected_score,'converted_points',a.converted_points,'conversion_history',a.conversion_history,'earned_xp',a.earned_xp,'coins_earned',a.earned_xp,'rule_snapshot',a.rule_snapshot,'performance_icon',case when a.revision is not null then petal_private.performance_band(a.protected_score)->>'icon' end,'performance_label',case when a.revision is not null then petal_private.performance_band(a.protected_score)->>'label' end) order by dt.local_date),'[]') into days from dates dt left join public.day_results dr on dr.family_id=f and dr.teen_id=t and dr.local_date=dt.local_date left join lateral(select * from public.daily_accounting da where da.family_id=f and da.teen_id=t and da.local_date=dt.local_date order by revision desc limit 1) a on true;
 answer:=jsonb_build_object('api_contract_version',3,'server_now',clock_timestamp(),'server_local_date',(clock_timestamp() at time zone 'America/Costa_Rica')::date,'family_id',f,'teen_id',t,'tasks',tasks,'day_summaries',days,
 'families',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.families x where id=f),
 'actors',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('actor_id',x.id)),'[]') from public.family_actors x where family_id=f),
 'memberships',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.memberships x where family_id=f),
 'devices',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'user_id',user_id,'updated_at',updated_at)),'[]') from public.device_registrations where family_id=f),
 'balance',(select jsonb_build_object('earned_xp',coalesce(sum(earned_xp_delta),0),'available_coins',coalesce(sum(coin_delta),0)) from public.wallet_events where family_id=f and teen_id=t),
 'reward_catalogue',petal_private.effective_rewards(f),'achievements',c->'achievements','outcome_catalogue',petal_private.outcome_catalogue(),
 'task_definitions',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('points',r.points,'local_due_time',r.local_due_time,'weekdays',r.weekdays)||coalesce(v.payload,'{}'::jsonb)),'[]') from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version left join lateral(select payload from public.catalogue_versions where family_id=f and catalogue_key=d.catalogue_key and kind in ('task','rule') and effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date order by effective_from desc,created_at desc,id desc limit 1) v on true where d.family_id=f),
 'rule_versions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.rule_versions x where family_id=f),
 'catalogue_versions',(select coalesce(jsonb_agg(to_jsonb(x) order by effective_from,created_at),'[]') from public.catalogue_versions x where family_id=f),
 'reward_requests',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc),'[]') from public.reward_requests x where family_id=f and teen_id=t),
 'extra_outcome_requests',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc),'[]') from public.extra_outcome_requests x where family_id=f and teen_id=t),
 'parent_actions',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at),'[]') from public.parent_actions x where family_id=f and teen_id=t),
 'day_appeals',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('status',case when status='requested' and clock_timestamp()>=petal_private.day_deadline(f,t,local_date) then 'expired' else status end) order by created_at),'[]') from public.day_appeals x where family_id=f and teen_id=t),
 'deductions',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at),'[]') from public.deduction_entries x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'wallet_events',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at),'[]') from public.wallet_events x where family_id=f and teen_id=t and (local_date between p_from and p_to or local_date is null)),
 'review_history',(select coalesce(jsonb_agg(to_jsonb(x) order by reviewed_at),'[]') from public.submission_reviews x join public.submissions s on s.id=x.submission_id join public.task_occurrences o on o.id=s.occurrence_id where o.family_id=f and o.teen_id=t and o.local_date between p_from and p_to));
 return answer;
end $$;

alter table public.submissions add column review_version integer not null default 1;
create function petal_private.bump_review_version() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.status is distinct from old.status then new.review_version:=old.review_version+1;end if;return new;end $$;
create trigger submission_review_generation before update on public.submissions for each row execute function petal_private.bump_review_version();
create function petal_private.review_submission_checked(p_submission_id uuid,p_outcome text,p_review_note text,p_expected_version integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;answer jsonb;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'review_submission_checked',jsonb_build_object('id',p_submission_id,'outcome',p_outcome,'note',p_review_note,'expected_version',p_expected_version));if answer is not null then return answer;end if;
 select * into s from public.submissions where id=p_submission_id for update;
 if s.review_version is distinct from p_expected_version then raise exception 'stale_review_refresh_required';end if;
 answer:=petal_private.review_submission_core(p_submission_id,p_outcome,p_review_note,gen_random_uuid())||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;

-- Explicit wrapper/grant declarations keep the API surface auditable.
create function public.get_parent_dashboard(p_family_id uuid,p_teen_id uuid,p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$select petal_private.get_parent_dashboard(p_family_id,p_teen_id,p_from,p_to);$$;
create function public.save_catalogue_version(p_family_id uuid,p_kind text,p_catalogue_key text,p_effective_from date,p_payload jsonb,p_request_id uuid,p_expected_version uuid default null) returns jsonb language sql security invoker set search_path='' as $$select petal_private.save_catalogue_version(p_family_id,p_kind,p_catalogue_key,p_effective_from,p_payload,p_request_id,p_expected_version);$$;
create function public.review_reward_request(p_reward_request_id uuid,p_outcome text,p_note text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_reward_request(p_reward_request_id,p_outcome,p_note,p_request_id);$$;
create function public.review_extra_outcome(p_outcome_request_id uuid,p_outcome text,p_note text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_extra_outcome(p_outcome_request_id,p_outcome,p_note,p_request_id);$$;
create function public.review_submission_checked(p_submission_id uuid,p_outcome text,p_review_note text,p_expected_version integer,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_submission_checked(p_submission_id,p_outcome,p_review_note,p_expected_version,p_request_id);$$;
revoke execute on function public.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_parent_dashboard(uuid,uuid,date,date),public.save_catalogue_version(uuid,text,text,date,jsonb,uuid,uuid),petal_private.save_catalogue_version(uuid,text,text,date,jsonb,uuid,uuid),public.review_reward_request(uuid,text,text,uuid),petal_private.review_reward_request(uuid,text,text,uuid),public.review_extra_outcome(uuid,text,text,uuid),petal_private.review_extra_outcome(uuid,text,text,uuid,integer),public.review_submission_checked(uuid,text,text,integer,uuid),petal_private.review_submission_checked(uuid,text,text,integer,uuid) from public,anon;
grant execute on function public.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_parent_dashboard(uuid,uuid,date,date),public.save_catalogue_version(uuid,text,text,date,jsonb,uuid,uuid),petal_private.save_catalogue_version(uuid,text,text,date,jsonb,uuid,uuid),public.review_reward_request(uuid,text,text,uuid),petal_private.review_reward_request(uuid,text,text,uuid),public.review_extra_outcome(uuid,text,text,uuid),petal_private.review_extra_outcome(uuid,text,text,uuid,integer),public.review_submission_checked(uuid,text,text,integer,uuid),petal_private.review_submission_checked(uuid,text,text,integer,uuid) to authenticated;
revoke execute on function petal_private.snapshot_extra_outcome(),petal_private.bump_review_version() from public,anon,authenticated;
-- Display the same effective reward price that request_reward snapshots.
create function petal_private.effective_rewards(p_family_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(coalesce(v.payload,b.item)||jsonb_build_object('id',b.item->>'id')),'[]')
 from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'rewards') b(item)
 left join lateral(select payload from public.catalogue_versions where family_id=p_family_id and kind='reward' and catalogue_key=b.item->>'id' and effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date order by effective_from desc,created_at desc,id desc limit 1) v on true;
$$;
alter function petal_private.get_teen_dashboard(date,date) rename to get_teen_dashboard_phase8;
create function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;
begin answer:=petal_private.get_teen_dashboard_phase8(p_from,p_to);return answer||jsonb_build_object('reward_catalogue',petal_private.effective_rewards((answer->>'family_id')::uuid),'parent_actions',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at),'[]') from public.parent_actions x where family_id=(answer->>'family_id')::uuid and teen_id=(answer->>'teen_id')::uuid));end $$;
revoke execute on function petal_private.effective_rewards(uuid),petal_private.get_teen_dashboard_phase8(date,date) from public,anon,authenticated;
revoke execute on function petal_private.get_teen_dashboard(date,date) from public,anon;
grant execute on function petal_private.get_teen_dashboard(date,date) to authenticated;

create function public.confirm_cash_outcome(p_outcome_request_id uuid,p_cash_amount integer,p_note text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_extra_outcome(p_outcome_request_id,'confirmed',p_note,p_request_id,p_cash_amount);$$;
revoke execute on function public.confirm_cash_outcome(uuid,integer,text,uuid) from public,anon;
grant execute on function public.confirm_cash_outcome(uuid,integer,text,uuid) to authenticated;
notify pgrst,'reload schema';

-- SOURCE: migrations/202610210009_phase9_tasksets.sql
-- Atomic versioned duty sets and immutable expected-day manifests.

create table public.day_tasksets (
 family_id uuid not null,teen_id uuid not null,local_date date not null,expected_tasks jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(family_id,teen_id,local_date),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
alter table public.day_tasksets enable row level security;
revoke all on public.day_tasksets from public,anon,authenticated;
grant select on public.day_tasksets to authenticated;
create policy subject_read on public.day_tasksets for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create function petal_private.validate_task_catalogue(p_family_id uuid,p_date date) returns void language plpgsql security definer set search_path='' as $$
declare day integer;total integer;n integer;
begin
 for day in 0..6 loop
 select coalesce(sum(coalesce((v.payload->>'points')::integer,r.points)),0),count(*) into total,n
 from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
 left join lateral(select payload from public.catalogue_versions where family_id=d.family_id and catalogue_key=d.catalogue_key and kind in ('task','rule') and effective_from<=p_date order by effective_from desc,created_at desc,id desc limit 1) v on true
 where d.family_id=p_family_id and coalesce((v.payload->>'enabled')::boolean,d.enabled)
 and day=any(case when v.payload is null then r.weekdays else array(select value::integer from jsonb_array_elements_text(v.payload->'weekdays')) end);
 if total<>100 or n=0 then raise exception 'catalogue_day_must_total_100:%',day;end if;
 end loop;
end $$;
-- Validate each boundary after all rows in the transaction are staged.
create function petal_private.guard_catalogue_totals() returns trigger language plpgsql security definer set search_path='' as $$
declare dt date;
begin
 for dt in select distinct effective_from from public.catalogue_versions where family_id=new.family_id and kind in ('task','rule') and effective_from>=new.effective_from loop perform petal_private.validate_task_catalogue(new.family_id,dt);end loop;
 return new;
end $$;
create constraint trigger catalogue_totals_commit after insert on public.catalogue_versions deferrable initially deferred for each row when(new.kind in ('task','rule')) execute function petal_private.guard_catalogue_totals();
create function petal_private.save_task_catalogue(p_family_id uuid,p_effective_from date,p_tasks jsonb,p_expected_version uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);answer jsonb;item jsonb;d uuid;days integer[];v text;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'save_task_catalogue',jsonb_build_object('family_id',p_family_id,'effective_from',p_effective_from,'tasks',p_tasks,'expected_version',p_expected_version));if answer is not null then return answer;end if;
 if (select id from public.catalogue_versions where family_id=p_family_id order by created_at desc,id desc limit 1) is distinct from p_expected_version then raise exception 'stale_catalogue_refresh_required';end if;
 if p_effective_from is null or p_effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'future_effective_date_required';end if;
 if jsonb_typeof(p_tasks) is distinct from 'array' or jsonb_array_length(p_tasks)=0 or jsonb_array_length(p_tasks)>100 then raise exception 'full_catalogue_required';end if;
 if exists(select 1 from public.task_definitions x where family_id=p_family_id and not exists(select 1 from jsonb_array_elements(p_tasks) y where y->>'catalogue_key'=x.catalogue_key)) then raise exception 'full_catalogue_required';end if;
 if (select count(distinct value->>'catalogue_key') from jsonb_array_elements(p_tasks))<>jsonb_array_length(p_tasks) then raise exception 'duplicate_catalogue_key';end if;
 for item in select value from jsonb_array_elements(p_tasks) loop
 if length(trim(coalesce(item->>'catalogue_key',''))) not between 1 and 100 or length(trim(coalesce(item->>'title',''))) not between 1 and 200 or coalesce((item->>'points')::integer,0) not between 1 and 100 or jsonb_typeof(item->'enabled') is distinct from 'boolean' then raise exception 'invalid_task';end if;
 select array_agg(value::integer) into days from jsonb_array_elements_text(item->'weekdays');if coalesce(cardinality(days),0)=0 or not days <@ array[0,1,2,3,4,5,6] then raise exception 'invalid_weekdays';end if;
 v:=item->>'local_due_time';if v is not null then perform v::time;end if;
 select id into d from public.task_definitions where family_id=p_family_id and catalogue_key=item->>'catalogue_key';
 if d is null then
 insert into public.task_definitions(family_id,title,enabled,catalogue_key) values(p_family_id,item->>'title',false,item->>'catalogue_key') returning id into d;
 insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source) values(p_family_id,d,1,(item->>'points')::integer,v::time,days,true,'Phase9 future-only task baseline');
 end if;
 insert into public.catalogue_versions(family_id,kind,catalogue_key,effective_from,payload,created_by) values(p_family_id,'task',item->>'catalogue_key',p_effective_from,item-'catalogue_key',u);
 end loop;
 perform petal_private.validate_task_catalogue(p_family_id,p_effective_from);
 answer:=jsonb_build_object('status','saved','effective_from',p_effective_from,'request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function public.save_task_catalogue(p_family_id uuid,p_effective_from date,p_tasks jsonb,p_expected_version uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.save_task_catalogue(p_family_id,p_effective_from,p_tasks,p_expected_version,p_request_id);$$;
revoke execute on function public.save_task_catalogue(uuid,date,jsonb,uuid,uuid),petal_private.save_task_catalogue(uuid,date,jsonb,uuid,uuid) from public,anon;
grant execute on function public.save_task_catalogue(uuid,date,jsonb,uuid,uuid),petal_private.save_task_catalogue(uuid,date,jsonb,uuid,uuid) to authenticated;
revoke execute on function petal_private.validate_task_catalogue(uuid,date),petal_private.guard_catalogue_totals() from public,anon,authenticated;

create function petal_private.day_task_manifest(p_family_id uuid,p_teen_id uuid,p_local_date date) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'definition_id',definition_id,'rule_version_id',rule_version_id,'points_snapshot',points_snapshot,'title_snapshot',title_snapshot) order by id),'[]') from public.task_occurrences where family_id=p_family_id and teen_id=p_teen_id and local_date=p_local_date;
$$;
-- Existing accepted complete sets can be certified without guessing missing history.
insert into public.day_tasksets(family_id,teen_id,local_date,expected_tasks)
 select family_id,teen_id,local_date,petal_private.day_task_manifest(family_id,teen_id,local_date) from public.task_occurrences group by family_id,teen_id,local_date having count(*)=14 and sum(points_snapshot)=100;
alter function petal_private.materialize_teen_tasks() rename to materialize_teen_tasks_core;
create function petal_private.materialize_teen_tasks() returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;m public.memberships%rowtype;dt date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 answer:=petal_private.materialize_teen_tasks_core();select * into m from public.memberships where user_id=auth.uid() and active and role='teen';
 if (select coalesce(sum(points_snapshot),0) from public.task_occurrences where family_id=m.family_id and teen_id=m.actor_id and local_date=dt)<>100 then raise exception 'day_taskset_must_total_100';end if;
 insert into public.day_tasksets(family_id,teen_id,local_date,expected_tasks) values(m.family_id,m.actor_id,dt,petal_private.day_task_manifest(m.family_id,m.actor_id,dt)) on conflict do nothing;
 return answer;
end $$;
revoke execute on function petal_private.day_task_manifest(uuid,uuid,date),petal_private.materialize_teen_tasks_core() from public,anon,authenticated;
revoke execute on function petal_private.materialize_teen_tasks() from public,anon;
grant execute on function petal_private.materialize_teen_tasks() to authenticated;
create or replace function petal_private.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;answer jsonb;actual integer;ded integer;earned integer;published timestamptz;seal timestamptz;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';
 if f is null then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'finalize_complete_day',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date));
 if answer is not null then return answer; end if;
 if exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date) then raise exception 'published_day_correction_unresolved'; end if;
 if p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day'; end if;
 if exists(select 1 from public.submissions s join public.task_occurrences o on o.id=s.occurrence_id where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date and s.status='pending') then raise exception 'pending_reviews_require_resolution'; end if;
 if not exists(select 1 from public.day_tasksets where family_id=f and teen_id=p_teen_id and local_date=p_local_date and expected_tasks=petal_private.day_task_manifest(f,p_teen_id,p_local_date)) or (select sum(points_snapshot) from public.task_occurrences where family_id=f and teen_id=p_teen_id and local_date=p_local_date)<>100 then raise exception 'historical_catalogue_snapshot_required';end if;
 select coalesce(sum(d.contribution_points),0) into actual from public.decisions d join public.submissions s on s.id=d.submission_id join public.task_occurrences o on o.id=s.occurrence_id where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date;
 select coalesce(sum(points),0) into ded from public.deduction_entries where family_id=f and teen_id=p_teen_id and local_date=p_local_date;
 actual:=greatest(0,actual-ded);earned:=case when actual<85 then 0 when actual=100 then 200 else actual end;
 published:=clock_timestamp();seal:=((p_local_date+2)::timestamp at time zone 'America/Costa_Rica');
 if published>=seal then seal:=((((published at time zone 'America/Costa_Rica')::date+2)::timestamp) at time zone 'America/Costa_Rica'); end if;
 insert into public.day_results values(f,p_teen_id,p_local_date,published,seal);
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,rule_snapshot) values(f,p_teen_id,p_local_date,1,actual,actual,earned,jsonb_build_object('version','phase3-owner-confirmed-v1','deductions',ded,'finalization','unsubmitted_zero_pending_reviews_resolved'));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(f,p_teen_id,'day:'||p_teen_id||':'||p_local_date||':1',p_local_date,earned,earned);
 answer:=jsonb_build_object('status','finalized','earned_xp',earned,'coins_earned',earned,'actual_score',actual,'effective_seal_at',seal);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;


notify pgrst,'reload schema';

-- SOURCE: migrations/202610210010_phase9_review_guard.sql
-- Stale legacy review routes cannot approve a new returned/resubmitted generation.

alter function petal_private.review_submission(uuid,text,text,uuid) rename to review_submission_core;
create function petal_private.review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 if not exists(select 1 from petal_private.idempotency where user_id=u and request_id=p_request_id and result is not null)
 and not (p_outcome='approved' and exists(select 1 from public.decisions where submission_id=s.id))
 and exists(select 1 from public.submission_reviews where submission_id=s.id and outcome in ('returned','rejected')) then raise exception 'stale_review_refresh_required';end if;
 return petal_private.review_submission_core(p_submission_id,p_outcome,p_review_note,p_request_id);
end $$;
revoke execute on function petal_private.review_submission_core(uuid,text,text,uuid) from public,anon,authenticated;
revoke execute on function petal_private.review_submission(uuid,text,text,uuid) from public,anon;
grant execute on function petal_private.review_submission(uuid,text,text,uuid) to authenticated;
notify pgrst,'reload schema';

-- SOURCE: migrations/202610220011_phase9_accounting.sql
-- Owner decisions 22 October: correction debt, unsealed bonus window, shared parent-edited notes.

create table public.occurrence_corrections (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,
 occurrence_id uuid not null references public.task_occurrences(id),outcome text not null check(outcome in ('approved','rejected','excused')),
 reason text not null check(length(trim(reason)) between 1 and 2000),parent_user_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
create table public.deduction_reversals (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,
 entry_id uuid not null unique references public.deduction_entries(id),reason text not null check(length(trim(reason)) between 1 and 2000),
 parent_user_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
create table public.bonus_activities (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,
 occurrence_id uuid not null unique references public.task_occurrences(id),description text not null check(length(trim(description)) between 1 and 2000),
 points_snapshot integer not null check(points_snapshot between 1 and 100),status text not null default 'offered' check(status in ('offered','submitted','returned','approved','cancelled')),
 parent_user_id uuid not null references auth.users(id),submitted_at timestamptz,approved_at timestamptz,created_at timestamptz not null default clock_timestamp()
);
create table public.bonus_reviews (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,
 bonus_id uuid not null references public.bonus_activities(id),outcome text not null,reason text not null check(length(reason)<=2000),
 parent_user_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
create table public.appeal_resolutions (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,
 appeal_id uuid not null unique references public.day_appeals(id),outcome text not null check(outcome in ('approved','rejected')),
 result_revision integer not null,reason text not null check(length(trim(reason)) between 1 and 2000),
 parent_user_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
create table public.reflection_notes (
 family_id uuid not null,teen_id uuid not null,local_date date not null,text text not null check(length(text)<=4000),
 version integer not null,parent_user_id uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp(),
 primary key(family_id,teen_id,local_date),foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.reflection_note_history (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,text text not null,
 version integer not null,parent_user_id uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp(),unique(family_id,teen_id,local_date,version)
);
alter table public.occurrence_corrections enable row level security;
alter table public.deduction_reversals enable row level security;
alter table public.bonus_activities enable row level security;
alter table public.bonus_reviews enable row level security;
alter table public.appeal_resolutions enable row level security;
alter table public.reflection_notes enable row level security;
alter table public.reflection_note_history enable row level security;
revoke all on public.occurrence_corrections,public.deduction_reversals,public.bonus_activities,public.bonus_reviews,public.appeal_resolutions,public.reflection_notes,public.reflection_note_history from public,anon,authenticated;
grant select on public.occurrence_corrections,public.deduction_reversals,public.bonus_activities,public.bonus_reviews,public.appeal_resolutions,public.reflection_notes,public.reflection_note_history to authenticated;
create policy subject_read on public.occurrence_corrections for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy subject_read on public.deduction_reversals for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy subject_read on public.bonus_activities for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy subject_read on public.bonus_reviews for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy subject_read on public.appeal_resolutions for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy subject_read on public.reflection_notes for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy subject_read on public.reflection_note_history for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create constraint trigger correction_commit_seal after insert on public.occurrence_corrections deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create constraint trigger reversal_commit_seal after insert on public.deduction_reversals deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create constraint trigger bonus_commit_seal after insert or update on public.bonus_activities deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create constraint trigger bonus_review_commit_seal after insert on public.bonus_reviews deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create constraint trigger resolution_commit_seal after insert on public.appeal_resolutions deferrable initially deferred for each row execute function petal_private.guard_result_seal();
-- Caller holds the family lock. All day mutations use this one full-state calculation.
create function petal_private.day_state(p_family_id uuid,p_teen_id uuid,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actual integer;virtual integer;converted integer;ded integer;protected integer;earned integer;provenance boolean;
begin
 select coalesce(sum(case when coalesce(c.outcome,case when dc.id is not null then 'approved' end)='approved' then o.points_snapshot else 0 end),0),
 coalesce(sum(case when c.outcome='excused' then o.points_snapshot else 0 end),0),
 coalesce(sum(case when c.outcome='excused' and b.status='approved' then least(o.points_snapshot,b.points_snapshot) else 0 end),0),coalesce(bool_or(b.status='approved'),false)
 into actual,virtual,converted,provenance from public.task_occurrences o
 left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id
 left join lateral(select outcome from public.occurrence_corrections where occurrence_id=o.id order by created_at desc,id desc limit 1) c on true
 left join public.bonus_activities b on b.occurrence_id=o.id where o.family_id=p_family_id and o.teen_id=p_teen_id and o.local_date=p_date;
 select coalesce(sum(e.points),0) into ded from public.deduction_entries e where e.family_id=p_family_id and e.teen_id=p_teen_id and e.local_date=p_date and not exists(select 1 from public.deduction_reversals where entry_id=e.id);
 actual:=greatest(0,actual+converted-ded);virtual:=virtual-converted;protected:=greatest(0,actual+least(virtual,greatest(0,100-actual)));
 -- Deductions consume actual first, then any remaining virtual protection, exactly once.
 select greatest(0,coalesce(sum(case when coalesce(c.outcome,case when dc.id is not null then 'approved' end) in ('approved','excused') then o.points_snapshot else 0 end),0)-ded) into protected
 from public.task_occurrences o left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id left join lateral(select outcome from public.occurrence_corrections where occurrence_id=o.id order by created_at desc,id desc limit 1) c on true where o.family_id=p_family_id and o.teen_id=p_teen_id and o.local_date=p_date;
 virtual:=greatest(0,protected-actual);earned:=case when actual<85 then 0 when actual=100 and not provenance then 200 else actual end;
 return jsonb_build_object('actual_score',actual,'virtual_remaining',virtual,'protected_score',protected,'converted_points',converted,'conversion_history',provenance,'earned_xp',earned,'coins_earned',earned,'deduction_points',ded);
end $$;
create table petal_private.day_edit_versions(family_id uuid not null,teen_id uuid not null,local_date date not null,version integer not null,primary key(family_id,teen_id,local_date));
alter table petal_private.day_edit_versions enable row level security;
revoke all on petal_private.day_edit_versions from public,anon,authenticated;
insert into petal_private.day_edit_versions select family_id,teen_id,local_date,max(revision) from public.daily_accounting group by family_id,teen_id,local_date;
create function petal_private.current_day_revision(p_family_id uuid,p_teen_id uuid,p_date date) returns integer language sql stable security definer set search_path='' as $$select coalesce((select version from petal_private.day_edit_versions where family_id=p_family_id and teen_id=p_teen_id and local_date=p_date),0);$$;
create function petal_private.require_day_revision(p_family_id uuid,p_teen_id uuid,p_date date,p_expected_revision integer) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_date is null or p_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day';end if;
 if clock_timestamp()>=petal_private.day_deadline(p_family_id,p_teen_id,p_date) then raise exception 'day_sealed';end if;
 if petal_private.current_day_revision(p_family_id,p_teen_id,p_date) is distinct from p_expected_revision then raise exception 'stale_day_revision_refresh_required';end if;
end $$;
create function petal_private.recompute_day(p_family_id uuid,p_teen_id uuid,p_date date,p_source uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare state jsonb;a public.daily_accounting%rowtype;n integer;delta integer;
begin
 if clock_timestamp()>=petal_private.day_deadline(p_family_id,p_teen_id,p_date) then raise exception 'day_sealed';end if;
 state:=petal_private.day_state(p_family_id,p_teen_id,p_date);
 insert into petal_private.day_edit_versions(family_id,teen_id,local_date,version) values(p_family_id,p_teen_id,p_date,1) on conflict(family_id,teen_id,local_date) do update set version=petal_private.day_edit_versions.version+1 returning version into n;
 if not exists(select 1 from public.day_results where family_id=p_family_id and teen_id=p_teen_id and local_date=p_date) then return state||jsonb_build_object('edit_revision',n,'revision',null,'status','pending');end if;
 select * into a from public.daily_accounting where family_id=p_family_id and teen_id=p_teen_id and local_date=p_date order by revision desc limit 1;
 delta:=(state->>'earned_xp')::integer-coalesce(a.earned_xp,0);
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,virtual_remaining,protected_score,converted_points,conversion_history,earned_xp,rule_snapshot)
 values(p_family_id,p_teen_id,p_date,n,(state->>'actual_score')::integer,(state->>'virtual_remaining')::integer,(state->>'protected_score')::integer,(state->>'converted_points')::integer,(state->>'conversion_history')::boolean,(state->>'earned_xp')::integer,jsonb_build_object('version','phase9-owner-confirmed-v1','source_id',p_source,'deductions',state->'deduction_points'));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(p_family_id,p_teen_id,'day:'||p_teen_id||':'||p_date||':'||n,p_date,delta,delta);
 return state||jsonb_build_object('edit_revision',n,'revision',n,'status','finalized');
end $$;
create function petal_private.correct_occurrence(p_occurrence_id uuid,p_outcome text,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);o public.task_occurrences%rowtype;answer jsonb;cid uuid;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=o.family_id for update;if not petal_private.is_member(o.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'correct_occurrence',jsonb_build_object('occurrence_id',p_occurrence_id,'outcome',p_outcome,'expected_revision',p_expected_revision,'reason',p_reason));if answer is not null then return answer;end if;
 perform petal_private.require_day_revision(o.family_id,o.teen_id,o.local_date,p_expected_revision);
 if exists(select 1 from public.bonus_activities where occurrence_id=o.id and status='approved') then raise exception 'approved_bonus_correction_unavailable';end if;
 insert into public.occurrence_corrections(family_id,teen_id,local_date,occurrence_id,outcome,reason,parent_user_id) values(o.family_id,o.teen_id,o.local_date,o.id,p_outcome,p_reason,u) returning id into cid;
 answer:=petal_private.recompute_day(o.family_id,o.teen_id,o.local_date,cid)||jsonb_build_object('correction_id',cid,'request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.reverse_deduction(p_entry_id uuid,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);e public.deduction_entries%rowtype;answer jsonb;rid uuid;
begin
 select * into e from public.deduction_entries where id=p_entry_id;if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=e.family_id for update;if not petal_private.is_member(e.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'reverse_deduction',jsonb_build_object('entry_id',p_entry_id,'expected_revision',p_expected_revision,'reason',p_reason));if answer is not null then return answer;end if;
 perform petal_private.require_day_revision(e.family_id,e.teen_id,e.local_date,p_expected_revision);
 if exists(select 1 from public.deduction_reversals where entry_id=e.id) then raise exception 'deduction_already_reversed';end if;
 insert into public.deduction_reversals(family_id,teen_id,local_date,entry_id,reason,parent_user_id) values(e.family_id,e.teen_id,e.local_date,e.id,p_reason,u) returning id into rid;
 answer:=petal_private.recompute_day(e.family_id,e.teen_id,e.local_date,rid)||jsonb_build_object('reversal_id',rid,'request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.offer_bonus(p_occurrence_id uuid,p_description text,p_expected_revision integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);o public.task_occurrences%rowtype;b public.bonus_activities%rowtype;answer jsonb;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=o.family_id for update;if not petal_private.is_member(o.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'offer_bonus',jsonb_build_object('occurrence_id',p_occurrence_id,'description',p_description,'expected_revision',p_expected_revision));if answer is not null then return answer;end if;
 perform petal_private.require_day_revision(o.family_id,o.teen_id,o.local_date,p_expected_revision);
 if (select outcome from public.occurrence_corrections where occurrence_id=o.id order by created_at desc,id desc limit 1) is distinct from 'excused' then raise exception 'excused_occurrence_required';end if;
 insert into public.bonus_activities(family_id,teen_id,local_date,occurrence_id,description,points_snapshot,parent_user_id) values(o.family_id,o.teen_id,o.local_date,o.id,p_description,o.points_snapshot,u) returning * into b;
 perform petal_private.recompute_day(b.family_id,b.teen_id,b.local_date,b.id);
 answer:=to_jsonb(b)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.submit_bonus(p_bonus_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();b public.bonus_activities%rowtype;answer jsonb;
begin
 select * into b from public.bonus_activities where id=p_bonus_id;if not found then raise exception 'teen_required' using errcode='42501';end if;
 perform 1 from public.families where id=b.family_id for update;
 if not exists(select 1 from public.memberships where user_id=u and family_id=b.family_id and actor_id=b.teen_id and active and role='teen') then raise exception 'teen_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'submit_bonus',jsonb_build_object('bonus_id',p_bonus_id));if answer is not null then return answer;end if;
 select * into b from public.bonus_activities where id=p_bonus_id for update;
 if clock_timestamp()>=petal_private.day_deadline(b.family_id,b.teen_id,b.local_date) then raise exception 'day_sealed';end if;
 if b.status not in ('offered','returned','submitted') then raise exception 'bonus_submission_unavailable';end if;
 if b.status<>'submitted' then update public.bonus_activities set status='submitted',submitted_at=clock_timestamp() where id=b.id returning * into b;perform petal_private.recompute_day(b.family_id,b.teen_id,b.local_date,b.id);end if;
 answer:=to_jsonb(b)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.review_bonus(p_bonus_id uuid,p_outcome text,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);b public.bonus_activities%rowtype;answer jsonb;rid uuid;
begin
 select * into b from public.bonus_activities where id=p_bonus_id;if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=b.family_id for update;if not petal_private.is_member(b.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'review_bonus',jsonb_build_object('bonus_id',p_bonus_id,'outcome',p_outcome,'expected_revision',p_expected_revision,'reason',p_reason));if answer is not null then return answer;end if;
 select * into b from public.bonus_activities where id=p_bonus_id for update;
 perform petal_private.require_day_revision(b.family_id,b.teen_id,b.local_date,p_expected_revision);
 if p_outcome not in ('approved','returned','cancelled') or p_outcome is null then raise exception 'invalid_bonus_outcome';end if;
 if b.status in ('approved','cancelled') then raise exception 'bonus_already_resolved';end if;
 if p_outcome in ('approved','returned') and b.status<>'submitted' then raise exception 'submitted_bonus_required';end if;
 if p_outcome<>'cancelled' and (select outcome from public.occurrence_corrections where occurrence_id=b.occurrence_id order by created_at desc,id desc limit 1) is distinct from 'excused' then raise exception 'excused_occurrence_required';end if;
 insert into public.bonus_reviews(family_id,teen_id,local_date,bonus_id,outcome,reason,parent_user_id) values(b.family_id,b.teen_id,b.local_date,b.id,p_outcome,coalesce(p_reason,''),u) returning id into rid;
 update public.bonus_activities set status=p_outcome,approved_at=case when p_outcome='approved' then clock_timestamp() end where id=b.id;
 answer:=petal_private.recompute_day(b.family_id,b.teen_id,b.local_date,rid)||jsonb_build_object('bonus_id',b.id,'request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.resolve_day_appeal(p_appeal_id uuid,p_outcome text,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);a public.day_appeals%rowtype;answer jsonb;r public.appeal_resolutions%rowtype;accounting_revision integer;
begin
 select * into a from public.day_appeals where id=p_appeal_id;if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=a.family_id for update;if not petal_private.is_member(a.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'resolve_day_appeal',jsonb_build_object('appeal_id',p_appeal_id,'outcome',p_outcome,'expected_revision',p_expected_revision,'reason',p_reason));if answer is not null then return answer;end if;
 select * into a from public.day_appeals where id=p_appeal_id for update;
 perform petal_private.require_day_revision(a.family_id,a.teen_id,a.local_date,p_expected_revision);
 if a.status<>'requested' or exists(select 1 from public.appeal_resolutions where appeal_id=a.id) then raise exception 'appeal_already_resolved';end if;
 select max(revision) into accounting_revision from public.daily_accounting where family_id=a.family_id and teen_id=a.teen_id and local_date=a.local_date;
 if p_outcome='approved' and accounting_revision<=a.result_revision then raise exception 'approved_appeal_requires_corrected_revision';end if;
 insert into public.appeal_resolutions(family_id,teen_id,local_date,appeal_id,outcome,result_revision,reason,parent_user_id) values(a.family_id,a.teen_id,a.local_date,a.id,p_outcome,accounting_revision,p_reason,u) returning * into r;
 update public.day_appeals set status='resolved' where id=a.id;answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function petal_private.save_reflection_note(p_teen_id uuid,p_local_date date,p_text text,p_expected_version integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;answer jsonb;r public.reflection_notes%rowtype;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';if f is null then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=f for update;if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'save_reflection_note',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date,'text',p_text,'expected_version',p_expected_version));if answer is not null then return answer;end if;
 if p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day';end if;
 select * into r from public.reflection_notes where family_id=f and teen_id=p_teen_id and local_date=p_local_date for update;
 if coalesce(r.version,0) is distinct from p_expected_version then raise exception 'stale_note_refresh_required';end if;
 insert into public.reflection_notes(family_id,teen_id,local_date,text,version,parent_user_id) values(f,p_teen_id,p_local_date,p_text,p_expected_version+1,u) on conflict(family_id,teen_id,local_date) do update set text=excluded.text,version=excluded.version,parent_user_id=u,updated_at=clock_timestamp() returning * into r;
 insert into public.reflection_note_history(family_id,teen_id,local_date,text,version,parent_user_id,updated_at) values(f,p_teen_id,p_local_date,r.text,r.version,u,r.updated_at);
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;

create or replace function petal_private.review_submission_core(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;o public.task_occurrences%rowtype;d public.decisions%rowtype;a public.daily_accounting%rowtype;answer jsonb;review_id uuid;score integer;earned integer;delta integer;ded integer;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 if p_outcome not in ('approved','rejected','returned') or p_outcome is null then raise exception 'invalid_review_outcome'; end if;
 answer:=petal_private.begin_request(p_request_id,'review_submission',jsonb_build_object('submission_id',p_submission_id,'outcome',p_outcome,'review_note',coalesce(p_review_note,'')));
 if answer is not null then return answer; end if;
 select * into s from public.submissions where id=p_submission_id for update;
 select * into o from public.task_occurrences where id=s.occurrence_id;
 select * into d from public.decisions where submission_id=s.id;
 if exists(select 1 from public.occurrence_corrections where occurrence_id=o.id) then raise exception 'explicit_occurrence_correction_required';end if;
 if d.id is not null then
 if p_outcome<>'approved' then raise exception 'approved_work_correction_policy_required'; end if;
 else
 if clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then raise exception 'day_sealed'; end if;
 if s.status<>'pending' then raise exception 'review_transition_unavailable_refresh_required'; end if;
 insert into public.submission_reviews(family_id,submission_id,parent_user_id,outcome,review_note) values(s.family_id,s.id,u,p_outcome,coalesce(p_review_note,'')) returning id into review_id;
 update public.submissions set status=p_outcome where id=s.id;
 if p_outcome='approved' then
 insert into public.decisions(family_id,submission_id,parent_id,status,contribution_points) values(s.family_id,s.id,u,'approved',o.points_snapshot) returning * into d;
 insert into public.xp_events(family_id,teen_id,decision_id,local_date,contribution_points) values(s.family_id,s.teen_id,d.id,o.local_date,d.contribution_points);
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(s.family_id,'submission.approved',d.id,jsonb_build_object('submission_id',s.id,'decision_id',d.id));
 end if;
 end if;
 if review_id is not null then perform petal_private.recompute_day(o.family_id,o.teen_id,o.local_date,review_id);end if;
 answer:=jsonb_build_object('request_id',p_request_id,'submission_id',s.id,'decision_id',d.id,'status',p_outcome,'review_id',review_id,'contribution_points',coalesce(d.contribution_points,0),'spendable_xp',0);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

create or replace function petal_private.enter_deduction(p_teen_id uuid,p_local_date date,p_deduction_key text,p_entry_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;amount integer;answer jsonb;e public.deduction_entries%rowtype;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';if f is null then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=f for update;if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'enter_deduction',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date,'deduction_key',p_deduction_key,'entry_id',p_entry_id));if answer is not null then return answer;end if;
 select * into e from public.deduction_entries where id=p_entry_id;
 if found then
 if e.family_id<>f or e.teen_id<>p_teen_id or e.local_date<>p_local_date or e.deduction_key<>p_deduction_key then raise exception 'deduction_identity_conflict';end if;
 else
 if p_entry_id is null or p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day';end if;
 if clock_timestamp()>=petal_private.day_deadline(f,p_teen_id,p_local_date) then raise exception 'day_sealed';end if;
 amount:=case p_deduction_key when 'dirty-lunchbag' then 5 when 'torn-clothes' then 20 when 'instructions' then 6 when 'shower-items' then 4 when 'messy-items' then 5 end;if amount is null then raise exception 'unknown_deduction';end if;
 insert into public.deduction_entries(id,family_id,teen_id,local_date,deduction_key,points,parent_user_id) values(p_entry_id,f,p_teen_id,p_local_date,p_deduction_key,amount,u) returning * into e;
 perform petal_private.recompute_day(f,p_teen_id,p_local_date,e.id);
 end if;
 answer:=to_jsonb(e)||jsonb_build_object('request_id',p_request_id);update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create or replace function petal_private.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;answer jsonb;actual integer;ded integer;earned integer;published timestamptz;seal timestamptz;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';
 if f is null then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'finalize_complete_day',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date));
 if answer is not null then return answer; end if;
 if exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date) then raise exception 'published_day_correction_unresolved'; end if;
 if p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day'; end if;
 if exists(select 1 from public.submissions s join public.task_occurrences o on o.id=s.occurrence_id where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date and s.status='pending' and not exists(select 1 from public.occurrence_corrections c where c.occurrence_id=o.id)) then raise exception 'pending_reviews_require_resolution'; end if;
 if not exists(select 1 from public.day_tasksets where family_id=f and teen_id=p_teen_id and local_date=p_local_date and expected_tasks=petal_private.day_task_manifest(f,p_teen_id,p_local_date)) or (select sum(points_snapshot) from public.task_occurrences where family_id=f and teen_id=p_teen_id and local_date=p_local_date)<>100 then raise exception 'historical_catalogue_snapshot_required';end if;
 published:=clock_timestamp();seal:=((p_local_date+2)::timestamp at time zone 'America/Costa_Rica');
 if published>=seal then seal:=((((published at time zone 'America/Costa_Rica')::date+2)::timestamp) at time zone 'America/Costa_Rica'); end if;
 insert into public.day_results values(f,p_teen_id,p_local_date,published,seal);
 answer:=petal_private.recompute_day(f,p_teen_id,p_local_date,p_request_id)||jsonb_build_object('effective_seal_at',seal,'request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;




create function petal_private.phase9_history(p_dashboard jsonb,p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f uuid:=(p_dashboard->>'family_id')::uuid;t uuid:=(p_dashboard->>'teen_id')::uuid;answer jsonb;coins bigint;
begin
 select coalesce(sum(coin_delta),0) into coins from public.wallet_events where family_id=f and teen_id=t;
 answer:=p_dashboard||jsonb_build_object(
 'occurrence_corrections',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at,id),'[]') from public.occurrence_corrections x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'deduction_reversals',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at,id),'[]') from public.deduction_reversals x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'bonus_activities',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at,id),'[]') from public.bonus_activities x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'bonus_reviews',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at,id),'[]') from public.bonus_reviews x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'appeal_resolutions',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at,id),'[]') from public.appeal_resolutions x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'reflection_notes',(select coalesce(jsonb_agg(to_jsonb(x) order by local_date),'[]') from public.reflection_notes x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'reflection_note_history',(select coalesce(jsonb_agg(to_jsonb(x) order by updated_at,id),'[]') from public.reflection_note_history x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'readiness',coalesce(p_dashboard->'readiness','{}')||jsonb_build_object('excuses_and_conversion','parent_offer_teen_submission_parent_review_before_seal','negative_corrections','debt_allowed_spending_blocked_until_repaid','appeals','parent_resolution_before_seal','historical_generation','immutable_effective_day_task_manifest_required'),
 'balance',coalesce(p_dashboard->'balance','{}')||jsonb_build_object('available_coins',coins,'coin_debt',greatest(0,-coins),'spending_blocked',coins<0),
 'deductions',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('reversed',exists(select 1 from public.deduction_reversals where entry_id=x.id)) order by created_at,id),'[]') from public.deduction_entries x where family_id=f and teen_id=t and local_date between p_from and p_to),
 'tasks',(select coalesce(jsonb_agg(x||jsonb_build_object('status',coalesce((select outcome from public.occurrence_corrections where occurrence_id=(x->>'id')::uuid order by created_at desc,id desc limit 1),x->>'status')) order by x->>'local_date',x->>'id'),'[]') from jsonb_array_elements(p_dashboard->'tasks') x),
 'day_summaries',(select coalesce(jsonb_agg(x||jsonb_build_object('edit_revision',petal_private.current_day_revision(f,t,(x->>'local_date')::date),'preview',petal_private.day_state(f,t,(x->>'local_date')::date)) order by x->>'local_date'),'[]') from jsonb_array_elements(p_dashboard->'day_summaries') x));
 return answer;
end $$;
alter function petal_private.get_parent_dashboard(uuid,uuid,date,date) rename to get_parent_dashboard_phase9_base;
create function petal_private.get_parent_dashboard(p_family_id uuid,p_teen_id uuid,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
begin return petal_private.phase9_history(petal_private.get_parent_dashboard_phase9_base(p_family_id,p_teen_id,p_from,p_to),p_from,p_to);end $$;
alter function petal_private.get_teen_dashboard(date,date) rename to get_teen_dashboard_phase9_base;
create function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
begin return petal_private.phase9_history(petal_private.get_teen_dashboard_phase9_base(p_from,p_to),p_from,p_to);end $$;
revoke execute on function petal_private.phase9_history(jsonb,date,date),petal_private.get_parent_dashboard_phase9_base(uuid,uuid,date,date),petal_private.get_teen_dashboard_phase9_base(date,date),petal_private.current_day_revision(uuid,uuid,date),petal_private.day_state(uuid,uuid,date),petal_private.require_day_revision(uuid,uuid,date,integer),petal_private.recompute_day(uuid,uuid,date,uuid),petal_private.review_submission_core(uuid,text,text,uuid) from public,anon,authenticated;
revoke execute on function petal_private.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_teen_dashboard(date,date) from public,anon;
grant execute on function petal_private.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_teen_dashboard(date,date) to authenticated;
create function public.correct_occurrence(p_occurrence_id uuid,p_outcome text,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.correct_occurrence(p_occurrence_id,p_outcome,p_expected_revision,p_reason,p_request_id);$$;
revoke execute on function public.correct_occurrence(uuid,text,integer,text,uuid),petal_private.correct_occurrence(uuid,text,integer,text,uuid) from public,anon;
grant execute on function public.correct_occurrence(uuid,text,integer,text,uuid),petal_private.correct_occurrence(uuid,text,integer,text,uuid) to authenticated;
create function public.reverse_deduction(p_entry_id uuid,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.reverse_deduction(p_entry_id,p_expected_revision,p_reason,p_request_id);$$;
revoke execute on function public.reverse_deduction(uuid,integer,text,uuid),petal_private.reverse_deduction(uuid,integer,text,uuid) from public,anon;
grant execute on function public.reverse_deduction(uuid,integer,text,uuid),petal_private.reverse_deduction(uuid,integer,text,uuid) to authenticated;
create function public.offer_bonus(p_occurrence_id uuid,p_description text,p_expected_revision integer,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.offer_bonus(p_occurrence_id,p_description,p_expected_revision,p_request_id);$$;
revoke execute on function public.offer_bonus(uuid,text,integer,uuid),petal_private.offer_bonus(uuid,text,integer,uuid) from public,anon;
grant execute on function public.offer_bonus(uuid,text,integer,uuid),petal_private.offer_bonus(uuid,text,integer,uuid) to authenticated;
create function public.submit_bonus(p_bonus_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.submit_bonus(p_bonus_id,p_request_id);$$;
revoke execute on function public.submit_bonus(uuid,uuid),petal_private.submit_bonus(uuid,uuid) from public,anon;
grant execute on function public.submit_bonus(uuid,uuid),petal_private.submit_bonus(uuid,uuid) to authenticated;
create function public.review_bonus(p_bonus_id uuid,p_outcome text,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_bonus(p_bonus_id,p_outcome,p_expected_revision,p_reason,p_request_id);$$;
revoke execute on function public.review_bonus(uuid,text,integer,text,uuid),petal_private.review_bonus(uuid,text,integer,text,uuid) from public,anon;
grant execute on function public.review_bonus(uuid,text,integer,text,uuid),petal_private.review_bonus(uuid,text,integer,text,uuid) to authenticated;
create function public.resolve_day_appeal(p_appeal_id uuid,p_outcome text,p_expected_revision integer,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.resolve_day_appeal(p_appeal_id,p_outcome,p_expected_revision,p_reason,p_request_id);$$;
revoke execute on function public.resolve_day_appeal(uuid,text,integer,text,uuid),petal_private.resolve_day_appeal(uuid,text,integer,text,uuid) from public,anon;
grant execute on function public.resolve_day_appeal(uuid,text,integer,text,uuid),petal_private.resolve_day_appeal(uuid,text,integer,text,uuid) to authenticated;
create function public.save_reflection_note(p_teen_id uuid,p_local_date date,p_text text,p_expected_version integer,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.save_reflection_note(p_teen_id,p_local_date,p_text,p_expected_version,p_request_id);$$;
revoke execute on function public.save_reflection_note(uuid,date,text,integer,uuid),petal_private.save_reflection_note(uuid,date,text,integer,uuid) from public,anon;
grant execute on function public.save_reflection_note(uuid,date,text,integer,uuid),petal_private.save_reflection_note(uuid,date,text,integer,uuid) to authenticated;
-- A parent correction closes the original duty; only another explicit correction may change it.
alter function petal_private.submit_occurrence(uuid,uuid) rename to submit_occurrence_phase8_base;
create function petal_private.submit_occurrence(p_occurrence_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();o public.task_occurrences%rowtype;answer jsonb;previous_status text;previous_id uuid;current_status text;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;if not found then raise exception 'teen_owner_required' using errcode='42501';end if;
 perform 1 from public.families where id=o.family_id for update;
 if not exists(select 1 from public.memberships where user_id=u and family_id=o.family_id and actor_id=o.teen_id and role='teen' and active) then raise exception 'teen_owner_required' using errcode='42501';end if;
 if exists(select 1 from public.occurrence_corrections where occurrence_id=o.id) and not exists(select 1 from petal_private.idempotency where user_id=u and request_id=p_request_id and result is not null) then raise exception 'parent_corrected_occurrence_closed';end if;
 select id,status into previous_id,previous_status from public.submissions where occurrence_id=o.id;
 answer:=petal_private.submit_occurrence_phase8_base(p_occurrence_id,p_request_id);
 select status into current_status from public.submissions where occurrence_id=o.id;
 if (previous_id is null or previous_status='returned') and current_status='pending' then
 perform petal_private.recompute_day(o.family_id,o.teen_id,o.local_date,(answer->>'id')::uuid);
 if previous_status='returned' then insert into petal_private.outbox(family_id,topic,source_id,payload) select o.family_id,'submission.resubmitted',md5(s.id::text||':'||s.review_version)::uuid,jsonb_build_object('submission_id',s.id,'review_version',s.review_version) from public.submissions s where s.occurrence_id=o.id on conflict(topic,source_id) do nothing;end if;
 end if;
 return answer;
end $$;
revoke execute on function petal_private.submit_occurrence_phase8_base(uuid,uuid) from public,anon,authenticated;
revoke execute on function petal_private.submit_occurrence(uuid,uuid) from public,anon;
grant execute on function petal_private.submit_occurrence(uuid,uuid) to authenticated;
-- Durable business transition facts only. Delivery is Phase10; payloads never include notes.
create function petal_private.phase9_audit_outbox() returns trigger language plpgsql security definer set search_path='' as $$
declare rowdata jsonb:=to_jsonb(new);topic text;source uuid;payload jsonb;
begin
 source:=(rowdata->>'id')::uuid;payload:=jsonb_build_object('source_id',source);
 case tg_table_name
 when 'parent_actions' then topic:='parent.action_recorded';payload:=payload||jsonb_build_object('source_kind',rowdata->'source_kind','subject_id',rowdata->'source_id');
 when 'submission_reviews' then topic:='submission.reviewed';payload:=payload||jsonb_build_object('submission_id',rowdata->'submission_id','outcome',rowdata->'outcome');
 when 'occurrence_corrections' then topic:='occurrence.corrected';payload:=payload||jsonb_build_object('occurrence_id',rowdata->'occurrence_id');
 when 'deduction_reversals' then topic:='deduction.reversed';payload:=payload||jsonb_build_object('entry_id',rowdata->'entry_id');
 when 'bonus_reviews' then topic:='bonus.reviewed';payload:=payload||jsonb_build_object('bonus_id',rowdata->'bonus_id');
 when 'appeal_resolutions' then topic:='appeal.resolved';payload:=payload||jsonb_build_object('appeal_id',rowdata->'appeal_id');
 when 'reflection_note_history' then topic:='reflection.updated';
 when 'bonus_activities' then
 if tg_op='INSERT' then topic:='bonus.offered';
 elsif new.status='submitted' and new.status is distinct from old.status then topic:='bonus.submitted';source:=gen_random_uuid();
 else return new;end if;payload:=jsonb_build_object('bonus_id',new.id);
 when 'day_results' then topic:='day.finalized';source:=md5(new.family_id::text||':'||new.teen_id||':'||new.local_date)::uuid;payload:=jsonb_build_object('teen_id',new.teen_id,'local_date',new.local_date);
 else raise exception 'unknown_audit_source';end case;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values((rowdata->>'family_id')::uuid,topic,source,payload) on conflict(topic,source_id) do nothing;return new;
end $$;
create trigger phase9_parent_action_outbox after insert on public.parent_actions for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_review_outbox after insert on public.submission_reviews for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_correction_outbox after insert on public.occurrence_corrections for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_reversal_outbox after insert on public.deduction_reversals for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_bonus_outbox after insert or update on public.bonus_activities for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_bonus_review_outbox after insert on public.bonus_reviews for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_appeal_outbox after insert on public.appeal_resolutions for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_note_outbox after insert on public.reflection_note_history for each row execute function petal_private.phase9_audit_outbox();
create trigger phase9_finalization_outbox after insert on public.day_results for each row execute function petal_private.phase9_audit_outbox();
revoke execute on function petal_private.phase9_audit_outbox() from public,anon,authenticated;
notify pgrst,'reload schema';

-- SOURCE: migrations/202610220012_phase9_legacy_materialization.sql
-- Old clients must not materialize baseline slots after a versioned schedule edit.

alter function petal_private.create_occurrence(uuid,uuid) rename to create_occurrence_phase6;
create function petal_private.create_occurrence(p_definition_id uuid,p_teen_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();f uuid;o public.task_occurrences%rowtype;
begin
 select family_id into f from public.task_definitions where id=p_definition_id;
 if f is null then raise exception 'not_authorized' using errcode='42501';end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.can_read_teen(f,p_teen_id) then raise exception 'not_authorized' using errcode='42501';end if;
 if exists(select 1 from public.catalogue_versions where family_id=f and kind in ('task','rule')) then
  select * into o from public.task_occurrences where family_id=f and definition_id=p_definition_id and teen_id=p_teen_id
   and local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date and slot_key='daily';
  if found then return to_jsonb(o);end if;
  raise exception 'catalogue_materialization_required';
 end if;
 return petal_private.create_occurrence_phase6(p_definition_id,p_teen_id);
end $$;
alter function petal_private.reconcile_occurrences(uuid,uuid,date,date) rename to reconcile_occurrences_phase6;
create function petal_private.reconcile_occurrences(p_family_id uuid,p_teen_id uuid,p_from_date date,p_to_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;rows jsonb;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'not_authorized' using errcode='42501';end if;
 if p_from_date is null or p_to_date is null or p_from_date>p_to_date or p_to_date>today or p_to_date-p_from_date>30 then raise exception 'invalid_reconciliation_range';end if;
 if exists(select 1 from public.catalogue_versions where family_id=p_family_id and kind in ('task','rule')) then
  select coalesce(jsonb_agg(to_jsonb(o) order by o.local_date,o.id),'[]'::jsonb) into rows from public.task_occurrences o
   where o.family_id=p_family_id and o.teen_id=p_teen_id and o.local_date between p_from_date and p_to_date;
  return jsonb_build_object('server_local_date',today,'occurrences',rows,'historical_generation_status','existing_snapshots_only','current_day_generation_rpc','materialize_teen_tasks');
 end if;
 return petal_private.reconcile_occurrences_phase6(p_family_id,p_teen_id,p_from_date,p_to_date);
end $$;
revoke execute on function petal_private.create_occurrence_phase6(uuid,uuid),petal_private.reconcile_occurrences_phase6(uuid,uuid,date,date) from public,anon,authenticated;
revoke execute on function petal_private.create_occurrence(uuid,uuid),petal_private.reconcile_occurrences(uuid,uuid,date,date) from public,anon;
grant execute on function petal_private.create_occurrence(uuid,uuid),petal_private.reconcile_occurrences(uuid,uuid,date,date) to authenticated;
notify pgrst,'reload schema';

commit;
-- Schema readiness only; this does not execute or certify business workflows.
select
 to_regprocedure('public.get_parent_dashboard(uuid,uuid,date,date)') is not null as parent_dashboard_ready,
 to_regprocedure('public.correct_occurrence(uuid,text,integer,text,uuid)') is not null as corrections_ready,
 to_regprocedure('public.review_bonus(uuid,text,integer,text,uuid)') is not null as bonus_ready,
 to_regprocedure('public.save_reflection_note(uuid,date,text,integer,uuid)') is not null as notes_ready,
 (select count(*)=11 and bool_and(c.relrowsecurity)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where (n.nspname='public' and c.relname in ('catalogue_versions','parent_actions','day_tasksets','occurrence_corrections','deduction_reversals','bonus_activities','bonus_reviews','appeal_resolutions','reflection_notes','reflection_note_history'))
   or (n.nspname='petal_private' and c.relname='day_edit_versions')) as rls_enabled;
