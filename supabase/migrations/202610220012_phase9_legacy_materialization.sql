-- Old clients must not materialize baseline slots after a versioned schedule edit.
begin;
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
