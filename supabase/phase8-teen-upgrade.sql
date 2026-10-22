-- LOCAL PHASE8 UPGRADE ONLY. Review owner readiness decisions before applying. No SQL is executed by this script.
begin;
-- Forward upgrade of the accepted Phase7 development schema only.
do $phase8_preflight$
begin
 if to_regclass('public.health_installations') is null
    or to_regprocedure('public.get_checkin_policy()') is null then
  raise exception 'Phase7 prerequisite missing; stop and report this message.';
 end if;
 if to_regclass('public.daily_accounting') is not null then
  raise exception 'Phase8 schema already exists; do not rerun this initial upgrade.';
 end if;
end $phase8_preflight$;
-- SOURCE: migrations/202610210005_phase8_teen.sql

-- New contracts are additive: Phase6/7 RPC names and their return shapes remain intact.
alter table public.task_occurrences add column title_snapshot text;
update public.task_occurrences o set title_snapshot=d.title from public.task_definitions d where d.id=o.definition_id;
alter table public.task_occurrences alter column title_snapshot set not null;
create function petal_private.snapshot_occurrence_title() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select title into new.title_snapshot from public.task_definitions where id=new.definition_id and family_id=new.family_id;
 return new;
end $$;
create trigger occurrence_title_before_insert before insert on public.task_occurrences for each row execute function petal_private.snapshot_occurrence_title();

create table petal_private.phase8_catalogue (
 singleton boolean primary key default true check(singleton), catalogue jsonb not null, tracker_rules jsonb not null,
 effective_from date -- Explicit deployment choice required; never guessed from a client clock.
);
create table public.daily_accounting (
 family_id uuid not null,teen_id uuid not null,local_date date not null,
 revision integer not null check(revision>0), actual_score integer not null check(actual_score between 0 and 100),
 virtual_remaining integer not null default 0 check(virtual_remaining between 0 and 100),
 protected_score integer not null check(protected_score between actual_score and 100),
 converted_points integer not null default 0 check(converted_points between 0 and 100),
 conversion_history boolean not null default false,
 earned_xp integer not null check(earned_xp between 0 and 200),
 rule_snapshot jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(family_id,teen_id,local_date,revision),
 foreign key(family_id,teen_id,local_date) references public.day_results(family_id,teen_id,local_date),
 check(earned_xp=case when actual_score<85 then 0 when actual_score=100 and not conversion_history then 200 else actual_score end)
);
create table public.wallet_events (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,
 source_key text not null unique,local_date date,earned_xp_delta integer not null default 0,coin_delta integer not null,
 created_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.deduction_entries (
 id uuid primary key, family_id uuid not null,teen_id uuid not null,local_date date not null,
 deduction_key text not null,points integer not null check(points>0),parent_user_id uuid not null references auth.users(id),
 rule_version text not null default 'phase3-deductions-v1',created_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id),
 check((deduction_key,points) in (('dirty-lunchbag',5),('torn-clothes',20),('instructions',6),('shower-items',4),('messy-items',5)))
);
alter table public.reward_requests add column catalogue_key text;
alter table public.reward_requests add column debit_coins integer not null default 0 check(debit_coins>=0);
alter table public.reward_requests add column updated_at timestamptz not null default clock_timestamp();

-- Explicit declarations keep the dashboard's static RLS check informed.
alter table public.daily_accounting enable row level security;
alter table public.wallet_events enable row level security;
alter table public.deduction_entries enable row level security;
do $$ declare t text; begin
 foreach t in array array['daily_accounting','wallet_events','deduction_entries'] loop
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy subject_read on public.%I for select to authenticated using(petal_private.can_read_teen(family_id,teen_id))',t);
 end loop;
end $$;
alter table petal_private.phase8_catalogue enable row level security;
revoke all on petal_private.phase8_catalogue from public,anon,authenticated;

create function petal_private.performance_band(p_score integer) returns jsonb language sql immutable set search_path='' as $$
 select case when p_score=100 then jsonb_build_object('icon','🌟','label','Exceptional Day')
 when p_score>=96 then jsonb_build_object('icon','💎','label','Amazing Day')
 when p_score>=91 then jsonb_build_object('icon','🏆','label','Excellent Day')
 when p_score=90 then jsonb_build_object('icon','✅','label','Passed Day — Good Day')
 when p_score>=85 then jsonb_build_object('icon','⚠️','label','Almost Passed')
 when p_score>=75 then jsonb_build_object('icon','🟠','label','Needs Improvement')
 when p_score>=60 then jsonb_build_object('icon','🔴','label','Poor Day')
 else jsonb_build_object('icon','⛔','label','Bad Day') end;
$$;

create function petal_private.materialize_teen_tasks() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at,title_snapshot)
 select d.family_id,d.id,m.actor_id,r.id,today,r.points,
 case when r.local_due_time is not null then (today+r.local_due_time) at time zone 'America/Costa_Rica' end,d.title
 from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
 where d.family_id=m.family_id and d.enabled and extract(dow from today)::integer=any(r.weekdays)
 on conflict(definition_id,teen_id,local_date,slot_key) do nothing;
 return jsonb_build_object('server_local_date',today,'status','ready','unknown_due_policy','submission_blocked_until_schedule_confirmed');
end $$;

create function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; c jsonb; tr jsonb; tasks jsonb; days jsonb;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then raise exception 'invalid_history_range'; end if;
 select catalogue,tracker_rules into c,tr from petal_private.phase8_catalogue where singleton;
 select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('catalogue_key',d.catalogue_key,'status',coalesce(s.status,'open'),
 'submission_id',s.id,'submitted_at',s.submitted_at,'decision_id',dc.id,'reviewed_at',dc.decided_at,
 'submission_ready',o.due_at is not null,'readiness_reason',case when o.due_at is null then 'unresolved_schedule' end) order by o.local_date,o.due_at nulls last,o.id),'[]') into tasks
 from public.task_occurrences o join public.task_definitions d on d.id=o.definition_id
 left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id
 where o.family_id=m.family_id and o.teen_id=m.actor_id and o.local_date between p_from and p_to;
 with dates as (
 select local_date from public.task_occurrences where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 union select local_date from public.day_results where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 ), summaries as (
 select dt.local_date,dr.first_published_at,dr.effective_seal_at,a.revision,a.actual_score,a.virtual_remaining,a.protected_score,a.converted_points,a.conversion_history,a.earned_xp,a.rule_snapshot,
 (select coalesce(sum(points),0) from public.deduction_entries de where de.family_id=m.family_id and de.teen_id=m.actor_id and de.local_date=dt.local_date) deduction_points
 from dates dt left join public.day_results dr on dr.family_id=m.family_id and dr.teen_id=m.actor_id and dr.local_date=dt.local_date
 left join lateral(select * from public.daily_accounting da where da.family_id=m.family_id and da.teen_id=m.actor_id and da.local_date=dt.local_date order by revision desc limit 1) a on true
 ) select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('status',case when first_published_at is null then 'pending' when clock_timestamp()>=effective_seal_at then 'sealed' else 'finalized' end,
 'coins_earned',earned_xp,'rule_version_id',rule_snapshot->>'version','performance_icon',case when revision is not null then petal_private.performance_band(protected_score)->>'icon' end,
 'performance_label',case when revision is not null then petal_private.performance_band(protected_score)->>'label' end,
 'week_start',local_date-extract(dow from local_date)::integer) order by local_date),'[]') into days from summaries s;
 return jsonb_build_object('api_contract_version',2,'server_now',clock_timestamp(),'server_local_date',(clock_timestamp() at time zone 'America/Costa_Rica')::date,
 'family_id',m.family_id,'teen_id',m.actor_id,'tasks',tasks,'day_summaries',days,
 'balance',(select jsonb_build_object('earned_xp',coalesce(sum(earned_xp_delta),0),'available_coins',coalesce(sum(coin_delta),0),'coin_rank',case when coalesce(sum(coin_delta),0)>=10000 then 'Diamond' when coalesce(sum(coin_delta),0)>=5000 then 'Emerald' when coalesce(sum(coin_delta),0)>=2500 then 'Sapphire' when coalesce(sum(coin_delta),0)>=1000 then 'Ruby' when coalesce(sum(coin_delta),0)>=500 then 'Gold' when coalesce(sum(coin_delta),0)>=100 then 'Silver' else 'Base' end) from public.wallet_events where family_id=m.family_id and teen_id=m.actor_id),
 'deductions',(select coalesce(jsonb_agg(to_jsonb(de) order by created_at),'[]') from public.deduction_entries de where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to),
 'reward_catalogue',coalesce(c->'rewards','[]'),'achievements',coalesce(c->'achievements','[]'),'tracker_rules',tr,
 'reward_requests',(select coalesce(jsonb_agg(to_jsonb(rr) order by created_at desc),'[]') from public.reward_requests rr where family_id=m.family_id and teen_id=m.actor_id),
 'readiness',jsonb_build_object('unknown_due_times','per_task_block','phase8_title_activation','effective_date_required','partial_day_finalization','policy_required',
 'excuses_and_conversion','allocation_and_bonus_policy_required','appeals','revision_and_evidence_policy_required','achievements','qualification_policy_required',
 'negative_corrections','debt_policy_required','cash_and_privileges','parent_manual_decision_required','historical_generation','effective_date_policy_required'));
end $$;

create function petal_private.request_reward(p_reward_key text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;item jsonb;answer jsonb;r public.reward_requests%rowtype;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'request_reward',jsonb_build_object('reward_key',p_reward_key));
 if answer is not null then return answer; end if;
 select value into item from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'rewards') where value->>'id'=p_reward_key;
 if item is null or item->>'sourceStatus'<>'Available' then raise exception 'reward_unavailable'; end if;
 insert into public.reward_requests(family_id,teen_id,title_snapshot,price_snapshot,catalogue_key)
 values(m.family_id,m.actor_id,item->>'title',(item->>'coinCost')::integer,p_reward_key) returning * into r;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'reward.requested',r.id,jsonb_build_object('reward_request_id',r.id));
 return answer;
end $$;
create function petal_private.cancel_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;r public.reward_requests%rowtype;answer jsonb;
begin
 select * into m from public.memberships where user_id=u and active;
 if not found then raise exception 'not_authorized' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id) then raise exception 'not_authorized' using errcode='42501'; end if;
 select * into r from public.reward_requests where id=p_reward_request_id and family_id=m.family_id and (m.role='parent' or teen_id=m.actor_id) for update;
 if not found then raise exception 'not_authorized' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'cancel_reward',jsonb_build_object('reward_request_id',p_reward_request_id));
 if answer is not null then return answer; end if;
 if r.status='fulfilled' or (r.status='approved' and m.role<>'parent') then raise exception 'parent_cancellation_required'; end if;
 if r.status<>'cancelled' then
 if r.status='approved' then
 insert into public.wallet_events(family_id,teen_id,source_key,coin_delta) values(r.family_id,r.teen_id,'reward-refund:'||r.id,r.debit_coins) on conflict(source_key) do nothing;
 end if;
 update public.reward_requests set status='cancelled',updated_at=clock_timestamp() where id=r.id returning * into r;
 end if;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
create function petal_private.approve_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);r public.reward_requests%rowtype;answer jsonb;balance bigint;
begin
 select * into r from public.reward_requests where id=p_reward_request_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=r.family_id for update;
 if not petal_private.is_member(r.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'approve_reward',jsonb_build_object('reward_request_id',p_reward_request_id));
 if answer is not null then return answer; end if;
 select * into r from public.reward_requests where id=p_reward_request_id for update;
 if r.status='requested' then
 select coalesce(sum(coin_delta),0) into balance from public.wallet_events where family_id=r.family_id and teen_id=r.teen_id;
 if balance<r.price_snapshot then raise exception 'insufficient_coins'; end if;
 insert into public.wallet_events(family_id,teen_id,source_key,coin_delta) values(r.family_id,r.teen_id,'reward-debit:'||r.id,-r.price_snapshot);
 update public.reward_requests set status='approved',debit_coins=price_snapshot,updated_at=clock_timestamp() where id=r.id returning * into r;
 elsif r.status<>'approved' then raise exception 'invalid_reward_transition'; end if;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

-- Complete-day-only settlement avoids selecting an unresolved partial/pending policy.
create function petal_private.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;answer jsonb;actual integer;ded integer;earned integer;n integer;published timestamptz;seal timestamptz;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';
 if f is null then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'finalize_complete_day',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date));
 if answer is not null then return answer; end if;
 if exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date) then raise exception 'published_day_correction_unresolved'; end if;
 if p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day'; end if;
 select count(*),coalesce(sum(o.points_snapshot),0) into n,actual from public.task_occurrences o join public.submissions s on s.occurrence_id=o.id join public.decisions d on d.submission_id=s.id
 where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date;
 if n<>14 or actual<>100 then raise exception 'partial_day_finalization_policy_required'; end if;
 select coalesce(sum(points),0) into ded from public.deduction_entries where family_id=f and teen_id=p_teen_id and local_date=p_local_date;
 actual:=greatest(0,actual-ded);earned:=case when actual<85 then 0 when actual=100 then 200 else actual end;
 published:=clock_timestamp();seal:=((p_local_date+2)::timestamp at time zone 'America/Costa_Rica');
 if published>=seal then seal:=((((published at time zone 'America/Costa_Rica')::date+2)::timestamp) at time zone 'America/Costa_Rica'); end if;
 insert into public.day_results values(f,p_teen_id,p_local_date,published,seal);
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,rule_snapshot)
 values(f,p_teen_id,p_local_date,1,actual,actual,earned,jsonb_build_object('version','phase3-owner-confirmed-v1','deductions',ded));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(f,p_teen_id,'day:'||p_teen_id||':'||p_local_date||':1',p_local_date,earned,earned);
 answer:=jsonb_build_object('status','finalized','earned_xp',earned,'coins_earned',earned,'actual_score',actual,'effective_seal_at',seal);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

-- Public wrappers follow the Phase6 invoker/private-definer boundary.
do $wrappers$ declare signature text;begin
 foreach signature in array array['materialize_teen_tasks()','get_teen_dashboard(date,date)','request_reward(text,uuid)','cancel_reward_request(uuid,uuid)','approve_reward_request(uuid,uuid)','finalize_complete_day(uuid,date,uuid)'] loop
 execute 'revoke execute on function petal_private.'||signature||' from public,anon';
 execute 'grant execute on function petal_private.'||signature||' to authenticated';
 end loop;
end $wrappers$;
create function public.materialize_teen_tasks() returns jsonb language sql security invoker set search_path='' as $$ select petal_private.materialize_teen_tasks(); $$;
create function public.get_teen_dashboard(p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.get_teen_dashboard(p_from,p_to); $$;
create function public.request_reward(p_reward_key text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.request_reward(p_reward_key,p_request_id); $$;
create function public.cancel_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.cancel_reward_request(p_reward_request_id,p_request_id); $$;
create function public.approve_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.approve_reward_request(p_reward_request_id,p_request_id); $$;
create function public.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.finalize_complete_day(p_teen_id,p_local_date,p_request_id); $$;
do $$ declare signature text;begin
 foreach signature in array array['materialize_teen_tasks()','get_teen_dashboard(date,date)','request_reward(text,uuid)','cancel_reward_request(uuid,uuid)','approve_reward_request(uuid,uuid)','finalize_complete_day(uuid,date,uuid)'] loop
 execute 'revoke execute on function public.'||signature||' from public,anon';execute 'grant execute on function public.'||signature||' to authenticated';
 end loop;
end $$;
revoke execute on function petal_private.performance_band(integer),petal_private.snapshot_occurrence_title() from public,anon,authenticated;
insert into petal_private.phase8_catalogue(singleton,catalogue,tracker_rules) values(true,$catalogue${"status":"draft catalogue; sourced values plus explicit owner override; identifiers assigned once and retained","date":"2026-10-21","timezone":"America/Costa_Rica","weekStart":"Sunday 00:00","sourceSnapshot":"Tracker-Rule-Extract.json","duties":[{"id":"duty-wd-001","title":"⚠️ 1st Attitude Check","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":2,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-001","title":"⚠️ 1st Attitude Check","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":2,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-002","title":"🎒 Lunchbag + Shower + Room @4PM","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":3,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":"16:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"🎒 BagPack + Lunchbag + Shower + Room @4PM"},{"id":"duty-we-002","title":"➡️ Room + Laundry @11AM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":3,"sourceXp":12,"xp":12,"decisionRef":null,"dueTime":"11:00","approvalPolicy":"either-parent; per-duty review details pending","sourceTitle":"➡️ Room + Laundry @11PM","dueTimeDecisionRef":"P3-006"},{"id":"duty-wd-003","title":"📚 Homework/Study + HighSchool Pendings + BagPack preparation + review @5:30PM","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":4,"sourceXp":12,"xp":12,"decisionRef":"P8-001","dueTime":"17:30","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"📚 Homework/Study @5:30PM"},{"id":"duty-we-003","title":"🚿 Shower +No Mess @1PM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":4,"sourceXp":11,"xp":11,"decisionRef":null,"dueTime":"13:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label"},{"id":"duty-wd-004","title":"⚠️ 2nd Attitude Check + mouth piece check","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":5,"sourceXp":15,"xp":15,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"⚠️ 2nd Attitude Check"},{"id":"duty-we-004","title":"📚 Check HS + Other Pendings / Study @2PM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":5,"sourceXp":11,"xp":11,"decisionRef":null,"dueTime":"14:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label"},{"id":"duty-wd-005","title":"➡️ Next Day Prepare + Room clean up @6PM","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":6,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":"18:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"➡️ Next Day Prepare @6PM"},{"id":"duty-we-005","title":"⚠️ 2nd Attitude Check + mouth piece check @5PM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":6,"sourceXp":15,"xp":15,"decisionRef":"P8-001","dueTime":"17:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"⚠️ 2nd Attitude Check @5PM"},{"id":"duty-wd-006","title":"✨ House Help + meditation/reading","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":7,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"✨ House Help"},{"id":"duty-we-006","title":"✨ House Help + meditation/reading","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":7,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"✨ House Help"},{"id":"duty-wd-007","title":"🌱 Water plants","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":8,"sourceXp":1,"xp":1,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"📖 Read a new book -or- Bible"},{"id":"duty-we-007","title":"🌱 Water plants","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":8,"sourceXp":1,"xp":1,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"📖 Read a new book -or- Bible"},{"id":"duty-wd-008","title":"💧 Drink 3 glasses of water (House)","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":9,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-008","title":"💧 Drink 3 glasses of water (House)","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":9,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-009","title":"📝 Research & write by hand","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":10,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-009","title":"📝 Research & write by hand","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":10,"sourceXp":2,"xp":1,"decisionRef":"P3-003","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-010","title":"🎨 Draw / Create Dance","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":11,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-010","title":"🎨 Draw / Create Dance","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":11,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-011","title":"🧹 Clean up Closet / Shoes","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":12,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-011","title":"🧹 Clean up Closet / Shoes","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":12,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-012","title":"🎁 Declutter/give away items","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":13,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-012","title":"🎁 Declutter/give away items","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":13,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-013","title":"📚 Hikari Shop","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":14,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-013","title":"📚 Hikari Shop","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":14,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-014","title":"🙂 Final Attitude Check","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":15,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-014","title":"🙂 Final Attitude Check","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":15,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"}],"rewards":[{"id":"reward-001","sourceId":"1","title":"🎬 Choose a movie/TV Show for family movie night","coinCost":450,"sourceStatus":"Available","type":"In-House Event","tier":"1 ~ $10"},{"id":"reward-002","sourceId":"2","title":"🃏 Pokémon Booster Pack (~$8)","coinCost":600,"sourceStatus":"Available","type":"Purchase -Game","tier":"1 ~ $10"},{"id":"reward-003","sourceId":"3","title":"💍 Small accessory: earrings, bracelet, hair clips, phone charm, etc.","coinCost":650,"sourceStatus":"Available","type":"Purchase -Accessory","tier":"1 ~ $10"},{"id":"reward-004","sourceId":"4","title":"🧋 Boba, smoothie, café or dessert outing with parent","coinCost":675,"sourceStatus":"Available","type":"Outdoors Food","tier":"1 ~ $10"},{"id":"reward-005","sourceId":"5","title":"🧴 Small self-care/skincare item ($10 max)","coinCost":800,"sourceStatus":"Available","type":"Purchase -Beauty","tier":"1 ~ $10"},{"id":"reward-006","sourceId":"6","title":"🍕 Pizza/takeout family night","coinCost":1200,"sourceStatus":"Available","type":"In-House Event Food","tier":"2 ~ $20"},{"id":"reward-007","sourceId":"7","title":"📚 Book, novel, comic or manga under $20","coinCost":1200,"sourceStatus":"Available","type":"Purchase -Book","tier":"2 ~ $20"},{"id":"reward-008","sourceId":"8","title":"☕ Special parent-daughter outing","coinCost":1200,"sourceStatus":"Available","type":"Outdoors Food","tier":"2 ~ $20"},{"id":"reward-009","sourceId":"9","title":"🎲 Afternoon at the Arcade","coinCost":1350,"sourceStatus":"Available","type":"In-House Event","tier":"2 ~ $20"},{"id":"reward-010","sourceId":"10","title":"💄 Skincare/beauty mini-haul ($20 max)","coinCost":1400,"sourceStatus":"Available","type":"Purchase -Beauty","tier":"2 ~ $20"},{"id":"reward-011","sourceId":"11","title":"📖 New book or manga ($30 max)","coinCost":1850,"sourceStatus":"Available","type":"Purchase -Book","tier":"3 ~ $30"},{"id":"reward-012","sourceId":"12","title":"👯 Friend comes over + favorite takeout/snacks","coinCost":1900,"sourceStatus":"Available","type":"In-House Event Food","tier":"3 ~ $30"},{"id":"reward-013","sourceId":"13","title":"🎥 Go to the movies","coinCost":1950,"sourceStatus":"Available","type":"Outdoors Event","tier":"3 ~ $30"},{"id":"reward-014","sourceId":"14","title":"👕 Branded T-shirt / band / K-pop / anime shirt or accessory","coinCost":2000,"sourceStatus":"Available","type":"Purchase -Clothing","tier":"3 ~ $30"},{"id":"reward-015","sourceId":"15","title":"🧸 Pokémon/anime/K-pop collectible or plush ($30 max)","coinCost":2050,"sourceStatus":"Available","type":"Purchase -Collectible","tier":"3 ~ $30"},{"id":"reward-016","sourceId":"16","title":"👯 Bring a friend to movies / café / eat out","coinCost":2500,"sourceStatus":"Available","type":"Outdoors Event","tier":"4 ~ $40"},{"id":"reward-017","sourceId":"17","title":"🎲 New family board game ($40 max)","coinCost":2500,"sourceStatus":"Available","type":"Purchase -Game","tier":"4 ~ $40"},{"id":"reward-018","sourceId":"18","title":"🏃 Sports/running/fitness gear upgrade","coinCost":2550,"sourceStatus":"Available","type":"Purchase -Sports","tier":"4 ~ $40"},{"id":"reward-019","sourceId":"19","title":"🪞 Room décor / vanity / aesthetic bedroom upgrade ($40)","coinCost":2650,"sourceStatus":"Available","type":"Purchase -Room Decor","tier":"4 ~ $40"},{"id":"reward-020","sourceId":"20","title":"🎒 School-style upgrade: backpack, tote, bottle, pencil case, etc.","coinCost":5000,"sourceStatus":"Available","type":"Purchase -Tools","tier":"5 ~ $75"},{"id":"reward-021","sourceId":"21","title":"👟 Shoes/sneakers ($70)","coinCost":5500,"sourceStatus":"Available","type":"Purchase -Clothing","tier":"5 ~ $75"},{"id":"reward-022","sourceId":"22","title":"🎓 Enroll in a short course/workshop she chooses","coinCost":6000,"sourceStatus":"Available","type":"Purchase -Class","tier":"5 ~ $75"},{"id":"reward-023","sourceId":"23","title":"🃏 Pokémon ETB","coinCost":6000,"sourceStatus":"Available","type":"Purchase -Game","tier":"5 ~ $75"},{"id":"reward-024","sourceId":"24","title":"💄 Premium skincare/beauty/fashion item ($60–75 max)","coinCost":6000,"sourceStatus":"Available","type":"Purchase -Beauty","tier":"5 ~ $75"},{"id":"reward-025","sourceId":"25","title":"🎒 Premium backpack + full school/style kit","coinCost":10000,"sourceStatus":"Available","type":"Purchase -Tools","tier":"Premium ~ $100"},{"id":"reward-026","sourceId":"26","title":"🎫 Contribution toward a concert/show/event she really wants","coinCost":10000,"sourceStatus":"Available","type":"Purchase -Event","tier":"Premium ~ $100"},{"id":"reward-027","sourceId":"27","title":"🚗 Family day trip / nearby destination","coinCost":11000,"sourceStatus":"Available","type":"Outdoors Event","tier":"Premium ~ $100"},{"id":"reward-028","sourceId":"28","title":"🛍️ $100 shopping/gift-card budget for K-pop, fashion, beauty, etc.","coinCost":12500,"sourceStatus":"Available","type":"Purchase","tier":"Premium ~ $100"},{"id":"reward-029","sourceId":"29","title":"🎢 Theme park / major special-event day","coinCost":16000,"sourceStatus":"Available","type":"Outdoors Event","tier":"Platinum ~ $150+"}],"achievements":[{"id":"achievement-001","title":"Aced Test","xp":50,"sourceCondition":"Any test scored 100","preciseAwardCondition":"pending specification"},{"id":"achievement-002","title":"Student of Excellence I","xp":250,"sourceCondition":"All trimester grades > 97","preciseAwardCondition":"pending specification"},{"id":"achievement-003","title":"Student of Excellence II","xp":300,"sourceCondition":"Best student of the Class","preciseAwardCondition":"pending specification"},{"id":"achievement-004","title":"Student of Excellence III","xp":400,"sourceCondition":"Best student of the Gen","preciseAwardCondition":"pending specification"},{"id":"achievement-005","title":"Girl Machine","xp":1000,"sourceCondition":"1 month good behavior consistency","preciseAwardCondition":"pending specification"},{"id":"achievement-006","title":"Wise Princess","xp":2000,"sourceCondition":"2 month FULL required consistency","preciseAwardCondition":"pending specification"}],"scoring":{"scoreFloor":0,"earningThreshold":85,"passThreshold":90,"exceptionalScore":100,"exceptionalEarnedXp":200,"dailyScoreUpperCap":"none newly introduced; both standard task sets total 100","weekdayTaskTotal":100,"weekendTaskTotal":100,"decisionRefs":["P3-003","P3-004","P3-005"]},"reviewTiming":{"onTimeSubmissionDelayedReview":"retain original-day eligibility","decisionRef":"P3-007"},"coinConversion":{"mode":"automatic on finalized earned XP","coinsPerXp":1,"spendingErasesEarnedHistory":false,"decisionRef":"P3-008","finalizationSchedule":"explicit parent action; reminder timing separate","correctionDebtPolicy":"pending"},"finalization":{"mode":"explicit parent action","remindersRequired":true,"finalReminderExampleLocalTime":"21:00","exactReminderSchedule":"07:15,15:20,17:00,19:00,21:00 America/Costa_Rica; checkpoint context deferred","reminderDoesNotFinalize":true,"decisionRef":"P3-009","reminderTimesLocal":["07:15","15:20","17:00","19:00","21:00"],"reminderContext":"owner supplies labels,text,task context during implementation; do not treat all slots as finalization-only prompts","reminderDecisionRefs":["P3-015","P3-016"]},"excuses":{"protectDailyResult":true,"protectionUsesVirtualPoints":true,"virtualPointsEarnCoins":false,"parentBonusOfferAction":true,"exactThresholdAndBonusMath":"actual-only score must reach 85; days earning points through virtual conversion have no perfect-day bonus, max earned 100","decisionRefs":["P3-010","P3-011","P3-013","P3-014"],"actualOnlyEarningThreshold":85,"perfectBonusOnConversionDay":false,"maxEarnedXpOnConversionDay":100},"rewardLifecycle":{"requestChargesCoins":false,"approveBy":"either authorized parent","charge":"saved price once on approval","cancelBeforeApproval":"free","parentCancelBeforeFulfillment":"refund original debit once","afterFulfillment":"exception policy pending","decisionRef":"P3-012"},"ratings":{"coinRankBasis":"available coins","growthRatingPeriod":"daily","permanentLifetimeXpLevelApproved":false,"optionalMonthToDateRating":"tentative idea, not approved","monthlyFormula":null,"decisionRefs":["P3-017","P3-018"]},"appeals":{"filingWindow":"original result day through end of following local day","sealsAt":"start of original result day plus two calendar days","timezone":"America/Costa_Rica","deadlineExclusive":true,"example":"Monday result seals Wednesday 00:00","timelyPendingAppealAtSeal":"expire unresolved; no post-seal decision","latePublishedResult":"if first publication at or after normal original-day-plus-two boundary: seal at start of publication-local-date plus two days; no deadline refresh on later revision","sealedParentCorrectionPolicy":"forbidden; sealed result final","appealAloneAwardsXp":false,"decisionRef":"P3-019","decisionRefs":["P3-019","P3-021","P3-022","P3-023"],"examples":["Monday result normally seals Wednesday 00:00; unresolved appeal expires then","Monday result first published Wednesday: appeal through Thursday, seals Friday 00:00"]},"teenReminders":{"previousDayResultReviewTimeLocal":"17:00","timezone":"America/Costa_Rica","otherPendingTaskRemindersRequired":true,"otherTimesAndContent":"not specified","reminderIsNotAppealDeadline":true,"decisionRef":"P3-020"},"deploymentStatus":"Owner-approved title overrides recorded; not yet deployed. Effective-date/version rollout must preserve historical occurrences."}$catalogue$::jsonb,$tracker${"sourceSpreadsheetId":"1GpYowblGnc-3ZOzwLs7HUgdnNQ67vT9ShnfrLAcmQ9Q","readDate":"2026-10-21","note":"Read-only catalogue/policy snapshot. Owner overrides take precedence. Achievement counters and personal notes/history excluded.","rules":[{"sheet":"⚙️ Task Lists","range":"'⚙️ Task Lists'!A1:H20","values":[["Weekday Task","Weekday XP",null,"Weekend Task","Weekend XP"],["⚠️ 1st Attitude Check","15",null,"⚠️ 1st Attitude Check","15"],["🎒 BagPack + Lunchbag + Shower + Room @4PM","11",null,"➡️ Room + Laundry @11PM","12"],["📚 Homework/Study @5:30PM","12",null,"🚿 Shower +No Mess @1PM","11"],["⚠️ 2nd Attitude Check","15",null,"📚 Check HS + Other Pendings / Study @2PM","11"],["➡️ Next Day Prepare @6PM","11",null,"⚠️ 2nd Attitude Check @5PM","15"],["✨ House Help","11",null,"✨ House Help","11"],["📖 Read a new book -or- Bible","1",null,"📖 Read a new book -or- Bible","1"],["💧 Drink 3 glasses of water (House)","1",null,"💧 Drink 3 glasses of water (House)","1"],["📝 Research & write by hand","1",null,"📝 Research & write by hand","2"],["🎨 Draw / Create Dance","1",null,"🎨 Draw / Create Dance","1"],["🧹 Clean up Closet / Shoes","2",null,"🧹 Clean up Closet / Shoes","2"],["🎁 Declutter/give away items","2",null,"🎁 Declutter/give away items","2"],["📚 Hikari Shop","2",null,"📚 Hikari Shop","2"],["🙂 Final Attitude Check","15",null,"🙂 Final Attitude Check","15"]]},{"sheet":"🎁 List_of_Rewards","range":"'🎁 List_of_Rewards'!A1:F35","values":[["#","Reward","Coins","Status","Type","Tier"],["1","🎬 Choose a movie/TV Show for family movie night","450","Available","In-House Event","1 ~ $10"],["2","🃏 Pokémon Booster Pack (~$8)","600","Available","Purchase -Game","1 ~ $10"],["3","💍 Small accessory: earrings, bracelet, hair clips, phone charm, etc.","650","Available","Purchase -Accessory","1 ~ $10"],["4","🧋 Boba, smoothie, café or dessert outing with parent","675","Available","Outdoors Food","1 ~ $10"],["5","🧴 Small self-care/skincare item ($10 max)","800","Available","Purchase -Beauty","1 ~ $10"],["6","🍕 Pizza/takeout family night","1200","Available","In-House Event Food","2 ~ $20"],["7","📚 Book, novel, comic or manga under $20","1200","Available","Purchase -Book","2 ~ $20"],["8","☕ Special parent-daughter outing","1200","Available","Outdoors Food","2 ~ $20"],["9","🎲 Afternoon at the Arcade","1350","Available","In-House Event","2 ~ $20"],["10","💄 Skincare/beauty mini-haul ($20 max)","1400","Available","Purchase -Beauty","2 ~ $20"],["11","📖 New book or manga ($30 max)","1850","Available","Purchase -Book","3 ~ $30"],["12","👯 Friend comes over + favorite takeout/snacks","1900","Available","In-House Event Food","3 ~ $30"],["13","🎥 Go to the movies","1950","Available","Outdoors Event","3 ~ $30"],["14","👕 Branded T-shirt / band / K-pop / anime shirt or accessory","2000","Available","Purchase -Clothing","3 ~ $30"],["15","🧸 Pokémon/anime/K-pop collectible or plush ($30 max)","2050","Available","Purchase -Collectible","3 ~ $30"],["16","👯 Bring a friend to movies / café / eat out","2500","Available","Outdoors Event","4 ~ $40"],["17","🎲 New family board game ($40 max)","2500","Available","Purchase -Game","4 ~ $40"],["18","🏃 Sports/running/fitness gear upgrade","2550","Available","Purchase -Sports","4 ~ $40"],["19","🪞 Room décor / vanity / aesthetic bedroom upgrade ($40)","2650","Available","Purchase -Room Decor","4 ~ $40"],["20","🎒 School-style upgrade: backpack, tote, bottle, pencil case, etc.","5000","Available","Purchase -Tools","5 ~ $75"],["21","👟 Shoes/sneakers ($70)","5500","Available","Purchase -Clothing","5 ~ $75"],["22","🎓 Enroll in a short course/workshop she chooses","6000","Available","Purchase -Class","5 ~ $75"],["23","🃏 Pokémon ETB","6000","Available","Purchase -Game","5 ~ $75"],["24","💄 Premium skincare/beauty/fashion item ($60–75 max)","6000","Available","Purchase -Beauty","5 ~ $75"],["25","🎒 Premium backpack + full school/style kit","10000","Available","Purchase -Tools","Premium ~ $100"],["26","🎫 Contribution toward a concert/show/event she really wants","10000","Available","Purchase -Event","Premium ~ $100"],["27","🚗 Family day trip / nearby destination","11000","Available","Outdoors Event","Premium ~ $100"],["28","🛍️ $100 shopping/gift-card budget for K-pop, fashion, beauty, etc.","12500","Available","Purchase","Premium ~ $100"],["29","🎢 Theme park / major special-event day","16000","Available","Outdoors Event","Platinum ~ $150+"]]},{"sheet":"🏆 Achievements","range":"'🏆 Achievements'!A1:J24","values":[[],["Action","XP/Coins Awarded","Notes"],["Aced Test","50","Any test scored 100"],["Student of Excellence I","250","All trimester grades > 97"],["Student of Excellence II","300","Best student of the Class"],["Student of Excellence III","400","Best student of the Gen"],["Girl Machine","1000","1 month good behavior consistency"],["Wise Princess","2000","2 month FULL required consistency"],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[],[],[],[],["Total Achievements XP","0"]]},{"sheet":"⚖️ Accountability & Privileges","range":"'⚖️ Accountability & Privileges'!A1:H48","values":[["⚖️ ACCOUNTABILITY & PRIVILEGES",null,null,null,null,null,"🎁 BENEFITS & PRIVILEGES"],["Your final daily XP determines the type of day. 90 is the minimum passing score; scores above 90 move into higher-performance levels.",null,null,null,null,null,"Use this list as the master catalog of benefits and privileges that can be kept, lost, or earned depending on the daily result."],[],["Score","Day Type","Level","Meaning",null,null,"#","Benefit / Privilege"],["100","🌟 Exceptional Day","Above Pass","Maximum daily score",null,null,"1","Agregar 15mins a WhatsApp"],["96–99","💎 Amazing Day","Above Pass","Outstanding day",null,null,"2","Habilitar Cámara y Galería"],["91–95","🏆 Excellent Day","Above Pass","Exceeded the passing standard",null,null,"3","30mins de Televisión"],["90","✅ Passed Day — Good Day","Pass","Minimum passing score met",null,null,"4","Habilitar Walkman"],["85–89","⚠️ Almost Passed","Below Pass","Close to the standard, but the day does not pass (still gets the XP)",null,null,"5","Habilitar Chess App"],["75–84","🟠 Needs Improvement","Below Pass","Daily standard was not met",null,null,"6","Habilitar Pokémon TCG App"],["60–74","🔴 Poor Day","Below Pass","Significant improvement is needed",null,null,"7","Habilitar Emulador GBA"],["0–59","⛔ Bad Day","Below Pass","Major expectations were not met",null,null,"8","Habilitar Google Search"],[null,null,null,null,null,null,"9","Habilitar YouTube Music"],[null,null,null,null,null,null,"10","Habilitar YouTube"],["🎯 RESULTS BY DAY TYPE",null,null,null,null,null,"11"],["Use this section to define exactly what privileges are kept, what is lost, and what extra benefits or rewards are earned at each level.",null,null,null,null,null,"12"],[null,null,null,null,null,null,"13"],["Score","Day Type","Result",null,null,null,"14"],["100","🌟 Exceptional Day","⬇️ + Double XP boost",null,null,null,"15"],["96–99","💎 Amazing Day","⬇️ + ₡500 for each XP point above 95"],["91–95","🏆 Excellent Day","⬇️ + Skin Care regained"],["90","✅ Passed Day — Good Day","⬇️ + add one lost benefit / privilege"],["85–89","⚠️ Almost Passed","Keep your current benefits and privileges."],["75–84","🟠 Needs Improvement","Lose 1-2 benefits or privileges"],["60–74","🔴 Poor Day","Lose 3-4 benefits or privileges"],["0–59","⛔ Bad Day","Lose all benefits and privileges - Lose Hikari Money - Week plans canceled"],[],[],["⚠️ ACCOUNTABILITY DEDUCTIONS"],["These deductions reduce the final XP for the day. Multiple deductions may be added together when more than one accountability issue happens on the same day."],[],["Accountability Deduction",null,"XP Deduction","Notes / Examples"],["🥪 Dirty Lunchbag",null,"-5 XP"],["👕 Torn Clothes",null,"-20 XP"],["🚫 Did Not Follow Instructions",null,"-6 XP"],["🚿 Forgot Towel or Clothes for Shower",null,"-4 XP"],["✨ Messy / Dirty Items",null,"-5 XP"]]},{"sheet":"🪙 XP & Coins","range":"'🪙 XP & Coins'!I1:V5","values":[["base",null,"silver",null,"gold",null,"ruby",null,"sapphire",null,"emerald",null,"diamond"]]}]}$tracker$::jsonb);
notify pgrst, 'reload schema';

-- SOURCE: migrations/202610210006_phase8_deductions.sql
-- Apply only after 202610210005. Either parent records the fixed tracker amounts.

create function petal_private.enter_deduction(p_teen_id uuid,p_local_date date,p_deduction_key text,p_entry_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;amount integer;answer jsonb;entry public.deduction_entries%rowtype;a public.daily_accounting%rowtype;score integer;earned integer;delta integer;balance bigint;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';
 if f is null then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'enter_deduction',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date,'deduction_key',p_deduction_key,'entry_id',p_entry_id));
 if answer is not null then return answer; end if;
 select * into entry from public.deduction_entries where id=p_entry_id;
 if found then
 if entry.family_id<>f or entry.teen_id<>p_teen_id or entry.local_date<>p_local_date or entry.deduction_key<>p_deduction_key then raise exception 'deduction_identity_conflict'; end if;
 answer:=to_jsonb(entry);
 else
 if p_entry_id is null or p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day'; end if;
 if exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date and effective_seal_at<=clock_timestamp()) then raise exception 'day_sealed'; end if;
 amount:=case p_deduction_key when 'dirty-lunchbag' then 5 when 'torn-clothes' then 20 when 'instructions' then 6 when 'shower-items' then 4 when 'messy-items' then 5 end;
 if amount is null then raise exception 'unknown_deduction'; end if;
 select * into a from public.daily_accounting where family_id=f and teen_id=p_teen_id and local_date=p_local_date order by revision desc limit 1;
 if found then
 if a.virtual_remaining<>0 or a.converted_points<>0 then raise exception 'excused_correction_policy_required'; end if;
 score:=greatest(0,a.actual_score-amount);earned:=case when score<85 then 0 when score=100 and not a.conversion_history then 200 else score end;delta:=earned-a.earned_xp;
 select coalesce(sum(coin_delta),0) into balance from public.wallet_events where family_id=f and teen_id=p_teen_id;
 if balance+delta<0 then raise exception 'negative_correction_debt_policy_required'; end if;
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,conversion_history,rule_snapshot)
 values(f,p_teen_id,p_local_date,a.revision+1,score,score,earned,a.conversion_history,a.rule_snapshot||jsonb_build_object('deduction_entry_id',p_entry_id));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta)
 values(f,p_teen_id,'deduction:'||p_entry_id,p_local_date,delta,delta);
 elsif exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date) then raise exception 'accounting_revision_required';
 end if;
 insert into public.deduction_entries(id,family_id,teen_id,local_date,deduction_key,points,parent_user_id)
 values(p_entry_id,f,p_teen_id,p_local_date,p_deduction_key,amount,u) returning * into entry;
 answer:=to_jsonb(entry);
 end if;
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
create function public.enter_deduction(p_teen_id uuid,p_local_date date,p_deduction_key text,p_entry_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.enter_deduction(p_teen_id,p_local_date,p_deduction_key,p_entry_id,p_request_id);$$;
revoke execute on function public.enter_deduction(uuid,date,text,uuid,uuid),petal_private.enter_deduction(uuid,date,text,uuid,uuid) from public,anon;
grant execute on function public.enter_deduction(uuid,date,text,uuid,uuid),petal_private.enter_deduction(uuid,date,text,uuid,uuid) to authenticated;
-- Deferred checks run again at transaction completion, independent of expiry-job lag.
create function petal_private.guard_result_seal() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.day_results where family_id=new.family_id and teen_id=new.teen_id and local_date=new.local_date and effective_seal_at<=clock_timestamp()) then raise exception 'day_sealed'; end if;
 return new;
end $$;
create constraint trigger deduction_commit_seal after insert on public.deduction_entries deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create constraint trigger accounting_commit_seal after insert on public.daily_accounting deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create constraint trigger wallet_commit_seal after insert on public.wallet_events deferrable initially deferred for each row when(new.local_date is not null) execute function petal_private.guard_result_seal();
revoke execute on function petal_private.guard_result_seal() from public,anon,authenticated;
notify pgrst,'reload schema';

-- SOURCE: migrations/202610210007_phase8_owner_followup.sql

-- P8 owner follow-up: activate today; existing submitted/finalized snapshots remain intact.
update petal_private.phase8_catalogue set effective_from='2026-10-21';
alter table public.submissions drop constraint submissions_status_check;
alter table public.submissions add constraint submissions_status_check check(status in ('pending','approved','rejected','returned'));
create table public.submission_reviews (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,submission_id uuid not null,
 parent_user_id uuid not null references auth.users(id),outcome text not null check(outcome in ('approved','rejected','returned')),
 review_note text not null default '' check(length(review_note)<=2000),reviewed_at timestamptz not null default clock_timestamp(),
 foreign key(submission_id,family_id) references public.submissions(id,family_id)
);
alter table public.submission_reviews enable row level security;
revoke all on public.submission_reviews from public,anon,authenticated;
grant select on public.submission_reviews to authenticated;
create policy subject_read on public.submission_reviews for select to authenticated using(exists(select 1 from public.submissions s where s.id=submission_id and petal_private.can_read_teen(s.family_id,s.teen_id)));
-- Rule semantics and source provenance remain immutable; only current-version selection may change.
create or replace function petal_private.protect_initial_rule() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'historical_rule_immutable'; end if;
 if (to_jsonb(new)-'current_version') is distinct from (to_jsonb(old)-'current_version') then raise exception 'historical_rule_immutable'; end if;
 return new;
end $$;
-- Version each revised rule without changing points, weekdays or due times.
do $$ declare f uuid;item jsonb;d public.task_definitions%rowtype;r public.rule_versions%rowtype;new_rule uuid;begin
 for f in select id from public.families loop
 for item in select value from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'duties') where value->>'decisionRef'='P8-001' loop
 select * into d from public.task_definitions where family_id=f and catalogue_key=item->>'id';
 if not found then continue; end if;
 select * into r from public.rule_versions where definition_id=d.id and current_version;
 update public.rule_versions set current_version=false where id=r.id;
 insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
 values(f,d.id,r.version+1,r.points,r.local_due_time,r.weekdays,true,'Phase8 P8-001; effective 2026-10-21; XP unchanged') returning id into new_rule;
 update public.task_definitions set title=item->>'title' where id=d.id;
 update public.task_occurrences o set title_snapshot=item->>'title',rule_version_id=new_rule where o.definition_id=d.id and o.local_date>='2026-10-21'
 and not exists(select 1 from public.submissions s where s.occurrence_id=o.id)
 and not exists(select 1 from public.day_results dr where dr.family_id=o.family_id and dr.teen_id=o.teen_id and dr.local_date=o.local_date);
 end loop;end loop;
end $$;
-- New families seed approved current labels as part of their same creation transaction.
alter function petal_private.seed_family_catalogue(uuid) rename to seed_family_catalogue_phase6;
create function petal_private.seed_family_catalogue(p_family_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform petal_private.seed_family_catalogue_phase6(p_family_id);
 update public.task_definitions d set title=item.value->>'title' from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'duties') item
 where d.family_id=p_family_id and d.catalogue_key=item.value->>'id';

end $$;
revoke execute on function petal_private.seed_family_catalogue(uuid),petal_private.seed_family_catalogue_phase6(uuid) from public,anon,authenticated;

create function petal_private.day_deadline(p_family_id uuid,p_teen_id uuid,p_local_date date) returns timestamptz language sql stable security definer set search_path='' as $$
 select effective_seal_at from public.day_results where family_id=p_family_id and teen_id=p_teen_id and local_date=p_local_date;
$$;
create or replace function petal_private.submit_occurrence(p_occurrence_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();o public.task_occurrences%rowtype;s public.submissions%rowtype;answer jsonb;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;
 if not found then raise exception 'teen_owner_required' using errcode='42501'; end if;
 perform 1 from public.families where id=o.family_id for update;
 if not exists(select 1 from public.memberships where user_id=u and actor_id=o.teen_id and family_id=o.family_id and active and role='teen') then raise exception 'teen_owner_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'submit',jsonb_build_object('occurrence_id',p_occurrence_id));
 if answer is not null then return answer; end if;
 select * into s from public.submissions where occurrence_id=o.id for update;
 -- Replays of a committed outcome remain historical; a new resubmission is checked against the server deadline.
 if s.id is null or s.status='returned' then
 if clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then raise exception 'day_sealed'; end if;
 if o.local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'future_task'; end if;
 if s.id is null then
 insert into public.submissions(family_id,occurrence_id,teen_id) values(o.family_id,o.id,o.teen_id) returning * into s;
 else
 update public.submissions set status='pending' where id=s.id returning * into s;
 end if;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(o.family_id,'submission.pending',s.id,jsonb_build_object('submission_id',s.id)) on conflict(topic,source_id) do nothing;
 end if;
 answer:=to_jsonb(s)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

create function petal_private.review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 -- A delayed approved submission belongs to the original task day. Recompute full state.
 select * into a from public.daily_accounting where family_id=o.family_id and teen_id=o.teen_id and local_date=o.local_date order by revision desc limit 1;
 if found then
 if a.virtual_remaining<>0 or a.converted_points<>0 then raise exception 'excused_correction_policy_required'; end if;
 select coalesce(sum(dec.contribution_points),0) into score from public.decisions dec join public.submissions sub on sub.id=dec.submission_id join public.task_occurrences oc on oc.id=sub.occurrence_id where oc.family_id=o.family_id and oc.teen_id=o.teen_id and oc.local_date=o.local_date;
 select coalesce(sum(points),0) into ded from public.deduction_entries where family_id=o.family_id and teen_id=o.teen_id and local_date=o.local_date;
 score:=greatest(0,score-ded);earned:=case when score<85 then 0 when score=100 and not a.conversion_history then 200 else score end;delta:=earned-a.earned_xp;
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,conversion_history,rule_snapshot) values(o.family_id,o.teen_id,o.local_date,a.revision+1,score,score,earned,a.conversion_history,a.rule_snapshot||jsonb_build_object('review_id',review_id));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(o.family_id,o.teen_id,'review:'||review_id,o.local_date,delta,delta);
 end if;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(s.family_id,'submission.approved',d.id,jsonb_build_object('submission_id',s.id,'decision_id',d.id));
 end if;
 end if;
 answer:=jsonb_build_object('request_id',p_request_id,'submission_id',s.id,'decision_id',d.id,'status',p_outcome,'review_id',review_id,'contribution_points',coalesce(d.contribution_points,0),'spendable_xp',0);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
-- Preserve Phase6 approval response keys and operation identity while adopting approved late-work policy.
create or replace function petal_private.approve_submission(p_submission_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;answer jsonb;internal_id uuid;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'approve',jsonb_build_object('submission_id',p_submission_id));
 if answer is not null then return answer; end if;
 internal_id:=gen_random_uuid();
 answer:=petal_private.review_submission(p_submission_id,'approved','',internal_id)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
create function public.review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_submission(p_submission_id,p_outcome,p_review_note,p_request_id);$$;
revoke execute on function petal_private.review_submission(uuid,text,text,uuid),public.review_submission(uuid,text,text,uuid) from public,anon;
grant execute on function petal_private.review_submission(uuid,text,text,uuid),public.review_submission(uuid,text,text,uuid) to authenticated;
revoke execute on function petal_private.day_deadline(uuid,uuid,date) from public,anon,authenticated;
-- Parent explicitly finalizes; unsubmitted duties contribute zero and pending reviews block publication.
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
 if (select count(*) from public.task_occurrences where family_id=f and teen_id=p_teen_id and local_date=p_local_date)<>14 then raise exception 'historical_catalogue_snapshot_required'; end if;
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

create table public.extra_outcome_requests(
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,
 kind text not null check(kind in ('cash','achievement','privilege')),outcome_key text not null,target_date date not null,
 reason text not null default '' check(length(reason)<=2000),status text not null default 'requested' check(status in ('requested','confirmed','declined','cancelled')),
 created_at timestamptz not null default clock_timestamp(),foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create unique index one_pending_extra_outcome on public.extra_outcome_requests(family_id,teen_id,kind,outcome_key,target_date) where status='requested';
alter table public.extra_outcome_requests enable row level security;
revoke all on public.extra_outcome_requests from public,anon,authenticated;
grant select on public.extra_outcome_requests to authenticated;
create policy subject_read on public.extra_outcome_requests for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create function petal_private.outcome_catalogue() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('cash',jsonb_build_array(jsonb_build_object('id','daily-cash','title','Daily cash','description','Tracker ₡500 per point above95; parent confirms eligibility and amount.')),
 'privileges',(select jsonb_agg(item) from (
 select jsonb_build_object('id','privilege-'||lpad(privrow.value->>6,3,'0'),'title',privrow.value->>7,'description','Parent confirms kept, lost or regained privilege from the daily recommendation.') item
 from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.tracker_rules->'rules') sheet cross join lateral jsonb_array_elements(sheet->'values') privrow
 where sheet->>'sheet' like '%Accountability%' and privrow.value->>6 ~ '^([1-9]|10)$' and privrow.value->>7 is not null
 union all select jsonb_build_object('id','privilege-skincare','title','Skin Care','description','Tracker recommendation: regained on Excellent Day or higher; parent confirms.')
 union all select jsonb_build_object('id','privilege-hikari-money','title','Hikari Money','description','Tracker consequence: lost on Bad Day; parent confirms.')
 union all select jsonb_build_object('id','privilege-week-plans','title','Week plans','description','Tracker consequence: cancelled on Bad Day; parent confirms.')
 ) outcomes));
$$;
create function petal_private.request_extra_outcome(p_kind text,p_outcome_key text,p_target_date date,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;answer jsonb;r public.extra_outcome_requests%rowtype;valid boolean;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'request_extra_outcome',jsonb_build_object('kind',p_kind,'outcome_key',p_outcome_key,'target_date',p_target_date,'reason',coalesce(p_reason,'')));
 if answer is not null then return answer; end if;
 if p_target_date is null or p_target_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_target_date'; end if;
 if p_kind='achievement' then
 select exists(select 1 from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'achievements') v where v->>'id'=p_outcome_key) into valid;
 elsif p_kind in ('cash','privilege') then
 select exists(select 1 from jsonb_array_elements(petal_private.outcome_catalogue()->case p_kind when 'cash' then 'cash' else 'privileges' end) v where v->>'id'=p_outcome_key) into valid;
 end if;
 if not coalesce(valid,false) then raise exception 'unknown_outcome'; end if;
 insert into public.extra_outcome_requests(family_id,teen_id,kind,outcome_key,target_date,reason) values(m.family_id,m.actor_id,p_kind,p_outcome_key,p_target_date,coalesce(p_reason,''))
 on conflict(family_id,teen_id,kind,outcome_key,target_date) where status='requested' do nothing returning * into r;
 if r.id is null then select * into r from public.extra_outcome_requests where family_id=m.family_id and teen_id=m.actor_id and kind=p_kind and outcome_key=p_outcome_key and target_date=p_target_date and status='requested'; end if;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id,'authority','parent_confirmation_required');
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'extra_outcome.requested',r.id,jsonb_build_object('outcome_request_id',r.id,'kind',r.kind)) on conflict(topic,source_id) do nothing;
 return answer;
end $$;
create function public.request_extra_outcome(p_kind text,p_outcome_key text,p_target_date date,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.request_extra_outcome(p_kind,p_outcome_key,p_target_date,p_reason,p_request_id);$$;
revoke execute on function petal_private.request_extra_outcome(text,text,date,text,uuid),public.request_extra_outcome(text,text,date,text,uuid) from public,anon;
grant execute on function petal_private.request_extra_outcome(text,text,date,text,uuid),public.request_extra_outcome(text,text,date,text,uuid) to authenticated;
revoke execute on function petal_private.outcome_catalogue() from public,anon,authenticated;




create function petal_private.guard_submission_seal() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.task_occurrences%rowtype; sid uuid;
begin
 if tg_table_name='submission_reviews' then sid:=new.submission_id; else sid:=new.id; end if;
 select oc.* into o from public.task_occurrences oc join public.submissions s on s.occurrence_id=oc.id where s.id=sid;
 if clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then raise exception 'day_sealed'; end if;
 return new;
end $$;
create constraint trigger submission_commit_seal after insert or update on public.submissions deferrable initially deferred for each row execute function petal_private.guard_submission_seal();
create constraint trigger review_commit_seal after insert on public.submission_reviews deferrable initially deferred for each row execute function petal_private.guard_submission_seal();
revoke execute on function petal_private.guard_submission_seal() from public,anon,authenticated;

create table public.day_appeals(
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,result_revision integer not null,
 reason text not null check(length(trim(reason)) between 1 and 2000),status text not null default 'requested' check(status in ('requested','expired','resolved')),
 created_at timestamptz not null default clock_timestamp(),unique(family_id,teen_id,local_date),
 foreign key(family_id,teen_id,local_date,result_revision) references public.daily_accounting(family_id,teen_id,local_date,revision)
);
alter table public.day_appeals enable row level security;
revoke all on public.day_appeals from public,anon,authenticated;
grant select on public.day_appeals to authenticated;
create policy subject_read on public.day_appeals for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create function petal_private.request_day_appeal(p_local_date date,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;answer jsonb;r public.day_appeals%rowtype;a public.daily_accounting%rowtype;seal timestamptz;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'request_day_appeal',jsonb_build_object('local_date',p_local_date,'reason',p_reason));
 seal:=petal_private.day_deadline(m.family_id,m.actor_id,p_local_date);
 if answer is not null then
 select * into r from public.day_appeals where family_id=m.family_id and teen_id=m.actor_id and local_date=p_local_date;
 return to_jsonb(r)||jsonb_build_object('status',case when r.status='requested' and clock_timestamp()>=seal then 'expired' else r.status end,'effective_seal_at',seal,'request_id',p_request_id);
 end if;
 if seal is null then raise exception 'published_result_required'; end if;
 if clock_timestamp()>=seal then raise exception 'day_sealed'; end if;
 select * into a from public.daily_accounting where family_id=m.family_id and teen_id=m.actor_id and local_date=p_local_date order by revision desc limit 1;
 if not found then raise exception 'published_accounting_required'; end if;
 insert into public.day_appeals(family_id,teen_id,local_date,result_revision,reason) values(m.family_id,m.actor_id,p_local_date,a.revision,trim(p_reason)) on conflict(family_id,teen_id,local_date) do nothing returning * into r;
 if r.id is null then select * into r from public.day_appeals where family_id=m.family_id and teen_id=m.actor_id and local_date=p_local_date; end if;
 answer:=to_jsonb(r)||jsonb_build_object('effective_seal_at',seal,'request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'day_appeal.requested',r.id,jsonb_build_object('day_appeal_id',r.id)) on conflict(topic,source_id) do nothing;
 return answer;
end $$;
create function public.request_day_appeal(p_local_date date,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.request_day_appeal(p_local_date,p_reason,p_request_id);$$;
revoke execute on function petal_private.request_day_appeal(date,text,uuid),public.request_day_appeal(date,text,uuid) from public,anon;
grant execute on function petal_private.request_day_appeal(date,text,uuid),public.request_day_appeal(date,text,uuid) to authenticated;
-- Appeal filing itself must also be before the effective seal at transaction completion.
create constraint trigger appeal_commit_seal after insert on public.day_appeals deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create or replace function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; c jsonb; tr jsonb; tasks jsonb; days jsonb;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then raise exception 'invalid_history_range'; end if;
 select catalogue,tracker_rules into c,tr from petal_private.phase8_catalogue where singleton;
 select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('catalogue_key',d.catalogue_key,'status',coalesce(s.status,'open'),
 'submission_id',s.id,'submitted_at',s.submitted_at,'decision_id',dc.id,'reviewed_at',dc.decided_at,
 'submission_ready',coalesce(clock_timestamp()<petal_private.day_deadline(o.family_id,o.teen_id,o.local_date),true),'readiness_reason',case when clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then 'day_sealed' end,'is_late',case when o.due_at is not null then coalesce(s.submitted_at,clock_timestamp())>o.due_at end,'effective_seal_at',petal_private.day_deadline(o.family_id,o.teen_id,o.local_date),'review_note',(select review_note from public.submission_reviews rv where rv.submission_id=s.id order by reviewed_at desc,id desc limit 1)) order by o.local_date,o.due_at nulls last,o.id),'[]') into tasks
 from public.task_occurrences o join public.task_definitions d on d.id=o.definition_id
 left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id
 where o.family_id=m.family_id and o.teen_id=m.actor_id and o.local_date between p_from and p_to;
 with dates as (
 select local_date from public.task_occurrences where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 union select local_date from public.day_results where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 ), summaries as (
 select dt.local_date,dr.first_published_at,dr.effective_seal_at,a.revision,a.actual_score,a.virtual_remaining,a.protected_score,a.converted_points,a.conversion_history,a.earned_xp,a.rule_snapshot,
 (select coalesce(sum(points),0) from public.deduction_entries de where de.family_id=m.family_id and de.teen_id=m.actor_id and de.local_date=dt.local_date) deduction_points
 from dates dt left join public.day_results dr on dr.family_id=m.family_id and dr.teen_id=m.actor_id and dr.local_date=dt.local_date
 left join lateral(select * from public.daily_accounting da where da.family_id=m.family_id and da.teen_id=m.actor_id and da.local_date=dt.local_date order by revision desc limit 1) a on true
 ) select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('status',case when first_published_at is null then 'pending' when clock_timestamp()>=effective_seal_at then 'sealed' else 'finalized' end,
 'coins_earned',earned_xp,'rule_version_id',rule_snapshot->>'version','performance_icon',case when revision is not null then petal_private.performance_band(protected_score)->>'icon' end,
 'performance_label',case when revision is not null then petal_private.performance_band(protected_score)->>'label' end,
 'week_start',local_date-extract(dow from local_date)::integer) order by local_date),'[]') into days from summaries s;
 return jsonb_build_object('api_contract_version',2,'server_now',clock_timestamp(),'server_local_date',(clock_timestamp() at time zone 'America/Costa_Rica')::date,
 'family_id',m.family_id,'teen_id',m.actor_id,'tasks',tasks,'day_summaries',days,
 'balance',(select jsonb_build_object('earned_xp',coalesce(sum(earned_xp_delta),0),'available_coins',coalesce(sum(coin_delta),0),'coin_rank',case when coalesce(sum(coin_delta),0)>=10000 then 'Diamond' when coalesce(sum(coin_delta),0)>=5000 then 'Emerald' when coalesce(sum(coin_delta),0)>=2500 then 'Sapphire' when coalesce(sum(coin_delta),0)>=1000 then 'Ruby' when coalesce(sum(coin_delta),0)>=500 then 'Gold' when coalesce(sum(coin_delta),0)>=100 then 'Silver' else 'Base' end) from public.wallet_events where family_id=m.family_id and teen_id=m.actor_id),
 'deductions',(select coalesce(jsonb_agg(to_jsonb(de) order by created_at),'[]') from public.deduction_entries de where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to),
 'reward_catalogue',coalesce(c->'rewards','[]'),'achievements',coalesce(c->'achievements','[]'),'tracker_rules',tr,
 'reward_requests',(select coalesce(jsonb_agg(to_jsonb(rr) order by created_at desc),'[]') from public.reward_requests rr where family_id=m.family_id and teen_id=m.actor_id),
 'day_appeals',(select coalesce(jsonb_agg(to_jsonb(ap)||jsonb_build_object('status',case when ap.status='requested' and clock_timestamp()>=petal_private.day_deadline(ap.family_id,ap.teen_id,ap.local_date) then 'expired' else ap.status end,'effective_seal_at',petal_private.day_deadline(ap.family_id,ap.teen_id,ap.local_date)) order by ap.created_at desc),'[]') from public.day_appeals ap where ap.family_id=m.family_id and ap.teen_id=m.actor_id),'review_history',(select coalesce(jsonb_agg(to_jsonb(rv) order by rv.reviewed_at),'[]') from public.submission_reviews rv join public.submissions sub on sub.id=rv.submission_id join public.task_occurrences oc on oc.id=sub.occurrence_id where oc.family_id=m.family_id and oc.teen_id=m.actor_id and oc.local_date between p_from and p_to),'outcome_catalogue',petal_private.outcome_catalogue(),'extra_outcome_requests',(select coalesce(jsonb_agg(to_jsonb(er) order by created_at desc),'[]') from public.extra_outcome_requests er where er.family_id=m.family_id and er.teen_id=m.actor_id),'readiness',jsonb_build_object('unknown_due_times','no_invented_due_time_parent_reviews_credit','phase8_title_activation','effective_2026-10-21','partial_day_finalization','unsubmitted_zero_pending_reviews_resolved',
 'excuses_and_conversion','allocation_and_bonus_policy_required','appeals','filing_ready_parent_resolution_phase9','achievements','teen_requests_parent_confirms',
 'negative_corrections','debt_policy_required','cash_and_privileges','teen_requests_parent_confirms','historical_generation','effective_date_policy_required'));
end $$;

notify pgrst,'reload schema';

commit;
select effective_from,
 jsonb_array_length(catalogue->'duties') as task_variants,
 jsonb_array_length(catalogue->'rewards') as rewards,
 jsonb_array_length(catalogue->'achievements') as achievements
from petal_private.phase8_catalogue where singleton;
