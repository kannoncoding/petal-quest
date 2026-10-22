-- Apply only after 202610210005. Either parent records the fixed tracker amounts.
begin;
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
commit;
