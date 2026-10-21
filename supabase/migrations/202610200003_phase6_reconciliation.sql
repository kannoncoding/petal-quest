begin;
-- Bounded reconciliation of server records, never guesses historical rule versions.
create function petal_private.reconcile_occurrences(p_family_id uuid,p_teen_id uuid,p_from_date date,p_to_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date; rows jsonb;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_from_date is null or p_to_date is null or p_from_date>p_to_date or p_to_date>today or p_to_date-p_from_date>30 then raise exception 'invalid_reconciliation_range'; end if;
 select coalesce(jsonb_agg(to_jsonb(o) order by o.local_date,o.id),'[]'::jsonb) into rows from public.task_occurrences o
 where o.family_id=p_family_id and o.teen_id=p_teen_id and o.local_date between p_from_date and p_to_date;
 return jsonb_build_object('server_local_date',today,'occurrences',rows,
 'historical_generation_status','blocked_rule_effective_date_policy',
 'current_day_generation_rpc','create_occurrence');
end $$;
revoke execute on function petal_private.reconcile_occurrences(uuid,uuid,date,date) from public,anon;
grant execute on function petal_private.reconcile_occurrences(uuid,uuid,date,date) to authenticated;
create function public.reconcile_occurrences(p_family_id uuid,p_teen_id uuid,p_from_date date,p_to_date date)
returns jsonb language sql security invoker set search_path='' as $$
 select petal_private.reconcile_occurrences(p_family_id,p_teen_id,p_from_date,p_to_date); $$;
revoke execute on function public.reconcile_occurrences(uuid,uuid,date,date) from public,anon;
grant execute on function public.reconcile_occurrences(uuid,uuid,date,date) to authenticated;
commit;
