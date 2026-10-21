begin;
-- The initial catalogue starts when it is provisioned; an actor starts at enrollment.
-- These are server installation boundaries, not approval of future rule-edit timing.
alter table public.task_definitions add column provisioned_at timestamptz not null default clock_timestamp();
alter table public.family_actors add column enrolled_at timestamptz not null default clock_timestamp();

create function petal_private.protect_initial_rule() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 raise exception 'rule_change_policy_unresolved';
end $$;
revoke execute on function petal_private.protect_initial_rule() from public,anon,authenticated;
create trigger immutable_initial_rule before update or delete on public.rule_versions
for each row execute function petal_private.protect_initial_rule();

create or replace function petal_private.reconcile_occurrences(p_family_id uuid,p_teen_id uuid,p_from_date date,p_to_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=petal_private.require_identity();
 today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
 actor_started date;
 r record;
 slot_date date;
 rows jsonb;
 blocked jsonb;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not found or not petal_private.can_read_teen(p_family_id,p_teen_id) then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 select (a.enrolled_at at time zone 'America/Costa_Rica')::date into actor_started
 from public.family_actors a where a.family_id=p_family_id and a.id=p_teen_id and a.role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 if p_from_date is null or p_to_date is null or p_from_date>p_to_date
 or p_to_date>today or p_to_date-p_from_date>30 then
  raise exception 'invalid_reconciliation_range';
 end if;

 -- Only the one immutable initial version is knowable before rule-edit policy exists.
 -- Missing deadlines and multi-version definitions stay blocked instead of guessing.
 for r in
  select d.id,d.family_id,(d.provisioned_at at time zone 'America/Costa_Rica')::date as definition_started,
   v.id as rule_id,v.points,v.local_due_time,v.weekdays
  from public.task_definitions d join public.rule_versions v on v.definition_id=d.id and v.family_id=d.family_id
  where d.family_id=p_family_id and d.enabled and v.version=1 and v.current_version
   and v.local_due_time is not null
   and (select count(*) from public.rule_versions x where x.definition_id=d.id)=1
 loop
  slot_date:=greatest(p_from_date,actor_started,r.definition_started);
  while slot_date<=p_to_date loop
   if extract(dow from slot_date)::integer=any(r.weekdays) then
    insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at)
    values(p_family_id,r.id,p_teen_id,r.rule_id,slot_date,r.points,
     (slot_date+r.local_due_time) at time zone 'America/Costa_Rica')
    on conflict(definition_id,teen_id,local_date,slot_key) do nothing;
   end if;
   slot_date:=slot_date+1;
  end loop;
 end loop;

 select coalesce(jsonb_agg(jsonb_build_object('definition_id',d.id,'reason',
  case when not exists(select 1 from public.rule_versions v where v.definition_id=d.id and v.current_version and v.local_due_time is not null)
   then 'unresolved_schedule' else 'rule_change_policy_unresolved' end)),'[]'::jsonb)
 into blocked from public.task_definitions d where d.family_id=p_family_id and d.enabled
 and not exists(select 1 from public.rule_versions v where v.definition_id=d.id and v.version=1 and v.current_version
  and v.local_due_time is not null and (select count(*) from public.rule_versions x where x.definition_id=d.id)=1);

 select coalesce(jsonb_agg(to_jsonb(o) order by o.local_date,o.id),'[]'::jsonb) into rows
 from public.task_occurrences o where o.family_id=p_family_id and o.teen_id=p_teen_id
 and o.local_date between p_from_date and p_to_date;
 return jsonb_build_object('server_local_date',today,'occurrences',rows,'blocked_definitions',blocked,
  'historical_generation_status','initial_version_only','new_rule_activation_status','blocked_rule_effective_date_policy');
end $$;

-- No previously held request can publish a missing historical version via today's RPC.
-- Only private provisioning/migration can add definitions/versions; no client edit grant exists.
commit;
