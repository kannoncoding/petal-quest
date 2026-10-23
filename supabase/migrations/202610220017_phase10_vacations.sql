-- Vacation overlays affect NEW occurrence snapshots only. Existing facts/wallets never change.
begin;
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
commit;
