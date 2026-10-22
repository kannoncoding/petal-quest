-- Owner decisions 22 October: correction debt, unsealed bonus window, shared parent-edited notes.
begin;
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
commit;
