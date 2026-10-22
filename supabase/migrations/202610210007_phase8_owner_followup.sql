begin;
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
