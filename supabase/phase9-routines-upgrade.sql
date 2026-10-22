-- Apply once after the accepted Phase9 parent upgrade. Forward only; no reset.
-- Assigned routines are reminders only: no occurrence, approval, score or XP.
begin;
do $preflight$
begin
 if to_regclass('public.reflection_notes') is null or to_regprocedure('public.get_parent_dashboard(uuid,uuid,date,date)') is null then
  raise exception 'Accepted Phase9 parent upgrade is required; stop and report.';
 end if;
 if to_regclass('public.assigned_routine_versions') is not null then
  raise exception 'Assigned routines already exist; do not rerun this upgrade.';
 end if;
end $preflight$;
create table public.assigned_routine_versions (
 id uuid primary key default gen_random_uuid(), routine_id uuid not null,
 family_id uuid not null references public.families(id), teen_id uuid not null,
 version integer not null check(version>0), effective_from date not null,
 title text not null check(length(trim(title)) between 1 and 200),
 local_times text[] not null check(cardinality(local_times) between 1 and 24),
 weekdays integer[] not null check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[0,1,2,3,4,5,6]),
 active boolean not null, created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 unique(routine_id,version),foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
alter table public.assigned_routine_versions enable row level security;
revoke all on public.assigned_routine_versions from public,anon,authenticated;
grant select on public.assigned_routine_versions to authenticated;
create policy subject_read on public.assigned_routine_versions for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create function petal_private.save_assigned_routine(p_family_id uuid,p_teen_id uuid,p_routine_id uuid,p_expected_version uuid,p_effective_from date,p_title text,p_local_times jsonb,p_weekdays jsonb,p_active boolean,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);answer jsonb;prior public.assigned_routine_versions%rowtype;r public.assigned_routine_versions%rowtype;times text[];days integer[];
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 if not exists(select 1 from public.family_actors a join public.memberships m on m.family_id=a.family_id and m.actor_id=a.id where a.family_id=p_family_id and a.id=p_teen_id and a.role='teen' and m.role='teen' and m.active) then raise exception 'active_teen_required' using errcode='42501';end if;
 answer:=petal_private.begin_request(p_request_id,'save_assigned_routine',jsonb_build_object('family_id',p_family_id,'teen_id',p_teen_id,'routine_id',p_routine_id,'expected_version',p_expected_version,'effective_from',p_effective_from,'title',p_title,'local_times',p_local_times,'weekdays',p_weekdays,'active',p_active));
 if answer is not null then return answer;end if;
 if p_routine_id is null then raise exception 'routine_id_required';end if;
 select * into prior from public.assigned_routine_versions where routine_id=p_routine_id order by version desc limit 1;
 if prior.id is not null and (prior.family_id<>p_family_id or prior.teen_id<>p_teen_id) then raise exception 'parent_required' using errcode='42501';end if;
 if prior.id is distinct from p_expected_version then raise exception 'stale_routine_refresh_required';end if;
 if p_effective_from is null or p_effective_from<=(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'future_effective_date_required';end if;
 -- Later edits cannot rewrite a previously scheduled interval or erase history.
 if prior.id is not null and p_effective_from<prior.effective_from then raise exception 'routine_effective_date_out_of_order';end if;
 if length(trim(coalesce(p_title,''))) not between 1 and 200 or p_active is null then raise exception 'invalid_routine';end if;
 if jsonb_typeof(p_local_times) is distinct from 'array' or jsonb_typeof(p_weekdays) is distinct from 'array' then raise exception 'invalid_routine_schedule';end if;
 if jsonb_array_length(p_local_times) not between 1 and 24 or exists(select 1 from jsonb_array_elements(p_local_times) t where jsonb_typeof(t)<>'string' or t#>>'{}' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then raise exception 'invalid_due_time';end if;
 if jsonb_array_length(p_weekdays) not between 1 and 7 or exists(select 1 from jsonb_array_elements(p_weekdays) d where jsonb_typeof(d)<>'number' or d::text !~ '^[0-6]$') then raise exception 'invalid_weekdays';end if;
 select array_agg(distinct value order by value) into times from jsonb_array_elements_text(p_local_times);
 select array_agg(distinct value::integer order by value::integer) into days from jsonb_array_elements_text(p_weekdays);
 insert into public.assigned_routine_versions(routine_id,family_id,teen_id,version,effective_from,title,local_times,weekdays,active,created_by)
 values(p_routine_id,p_family_id,p_teen_id,coalesce(prior.version,0)+1,p_effective_from,trim(p_title),times,days,p_active,u) returning * into r;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;return answer;
end $$;
create function public.save_assigned_routine(p_family_id uuid,p_teen_id uuid,p_routine_id uuid,p_expected_version uuid,p_effective_from date,p_title text,p_local_times jsonb,p_weekdays jsonb,p_active boolean,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.save_assigned_routine(p_family_id,p_teen_id,p_routine_id,p_expected_version,p_effective_from,p_title,p_local_times,p_weekdays,p_active,p_request_id);$$;
-- Resolve immutable versions per local date, including historical titles and times.
create function petal_private.routine_snapshot(p_family_id uuid,p_teen_id uuid,p_from date,p_to date) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('local_date',d::date) order by d,r.title,r.routine_id),'[]'::jsonb)
 from pg_catalog.generate_series(p_from::timestamp,p_to::timestamp,interval '1 day') d
 cross join lateral (select distinct on (routine_id) * from public.assigned_routine_versions where family_id=p_family_id and teen_id=p_teen_id and effective_from<=d::date order by routine_id,effective_from desc,version desc) r
 where r.active and extract(dow from d)::integer=any(r.weekdays) and petal_private.can_read_teen(p_family_id,p_teen_id);
$$;
alter function petal_private.get_parent_dashboard(uuid,uuid,date,date) rename to get_parent_dashboard_before_routines;
create function petal_private.get_parent_dashboard(p_family_id uuid,p_teen_id uuid,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;t uuid;
begin
 answer:=petal_private.get_parent_dashboard_before_routines(p_family_id,p_teen_id,p_from,p_to);t:=(answer->>'teen_id')::uuid;
 return answer||jsonb_build_object('assigned_routines',petal_private.routine_snapshot(p_family_id,t,p_from,p_to),'assigned_routine_versions',(select coalesce(jsonb_agg(to_jsonb(r) order by version desc),'[]'::jsonb) from public.assigned_routine_versions r where family_id=p_family_id and teen_id=t));
end $$;
alter function petal_private.get_teen_dashboard(date,date) rename to get_teen_dashboard_before_routines;
create function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;
begin
 answer:=petal_private.get_teen_dashboard_before_routines(p_from,p_to);
 return answer||jsonb_build_object('assigned_routines',petal_private.routine_snapshot((answer->>'family_id')::uuid,(answer->>'teen_id')::uuid,p_from,p_to));
end $$;
revoke execute on function petal_private.routine_snapshot(uuid,uuid,date,date),petal_private.get_parent_dashboard_before_routines(uuid,uuid,date,date),petal_private.get_teen_dashboard_before_routines(date,date) from public,anon,authenticated;
revoke execute on function public.save_assigned_routine(uuid,uuid,uuid,uuid,date,text,jsonb,jsonb,boolean,uuid),petal_private.save_assigned_routine(uuid,uuid,uuid,uuid,date,text,jsonb,jsonb,boolean,uuid),petal_private.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_teen_dashboard(date,date) from public,anon;
grant execute on function public.save_assigned_routine(uuid,uuid,uuid,uuid,date,text,jsonb,jsonb,boolean,uuid),petal_private.save_assigned_routine(uuid,uuid,uuid,uuid,date,text,jsonb,jsonb,boolean,uuid),petal_private.get_parent_dashboard(uuid,uuid,date,date),petal_private.get_teen_dashboard(date,date) to authenticated;
select
 to_regprocedure('public.save_assigned_routine(uuid,uuid,uuid,uuid,date,text,jsonb,jsonb,boolean,uuid)') is not null as routines_ready,
 (select relrowsecurity from pg_class where oid='public.assigned_routine_versions'::regclass) as rls_enabled;
commit;
