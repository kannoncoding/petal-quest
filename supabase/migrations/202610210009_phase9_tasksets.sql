-- Atomic versioned duty sets and immutable expected-day manifests.
begin;
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
commit;
