-- Local Phase9 forward migration. No database execution or cloud deployment.
begin;
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
commit;
