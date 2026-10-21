-- Receipt variable correction found by executable local PostgreSQL verification.
begin;
create or replace function petal_private.submit_occurrence(p_occurrence_id uuid,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); o public.task_occurrences%rowtype; s public.submissions%rowtype; v_result jsonb;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;
 if not found then raise exception 'teen_owner_required' using errcode='42501'; end if;
 perform 1 from public.families where id=o.family_id for update;
 if not found or not exists(select 1 from public.memberships where user_id=u and actor_id=o.teen_id and active) or not petal_private.is_member(o.family_id,'teen') then raise exception 'teen_owner_required' using errcode='42501'; end if;
 v_result:=petal_private.begin_request(p_request_id,'submit',jsonb_build_object('occurrence_id',p_occurrence_id));
 if v_result is not null then return v_result; end if;
 perform 1 from public.task_occurrences where id=o.id for update;
 select * into s from public.submissions where occurrence_id=o.id;
 if not found then
 if o.due_at is null or clock_timestamp()>o.due_at then raise exception 'late_policy_unresolved'; end if;
 insert into public.submissions(family_id,occurrence_id,teen_id) values(o.family_id,o.id,o.teen_id) returning * into s;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(o.family_id,'submission.pending',s.id,jsonb_build_object('submission_id',s.id));
 end if;
 v_result:=to_jsonb(s)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=v_result where user_id=u and request_id=p_request_id;
 return v_result;
end $$;
create or replace function petal_private.approve_submission(p_submission_id uuid,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); s public.submissions%rowtype; o public.task_occurrences%rowtype;
 d public.decisions%rowtype; v_result jsonb;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=s.family_id for update;
 if not found or not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 v_result:=petal_private.begin_request(p_request_id,'approve',jsonb_build_object('submission_id',p_submission_id));
 if v_result is not null then return v_result; end if;
 -- Family lock reserves a common order with the future finalization operation.
 perform 1 from public.families where id=s.family_id for update;
 select * into s from public.submissions where id=p_submission_id for update;
 select * into d from public.decisions where submission_id=s.id;
 if not found then
 select * into o from public.task_occurrences where id=s.occurrence_id;
 if exists(select 1 from public.day_results where family_id=o.family_id and teen_id=o.teen_id and local_date=o.local_date) then raise exception 'published_day_correction_unresolved'; end if;
 if o.due_at is null or s.submitted_at>o.due_at then raise exception 'late_policy_unresolved'; end if;
 insert into public.decisions(family_id,submission_id,parent_id,status,contribution_points)
 values(s.family_id,s.id,u,'approved',o.points_snapshot) returning * into d;
 update public.submissions set status='approved' where id=s.id;
 insert into public.xp_events(family_id,teen_id,decision_id,local_date,contribution_points) values(s.family_id,s.teen_id,d.id,o.local_date,d.contribution_points);
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(s.family_id,'submission.approved',d.id,jsonb_build_object('submission_id',s.id,'decision_id',d.id));
 end if;
 v_result:=jsonb_build_object('request_id',p_request_id,'decision_id',d.id,'submission_id',s.id,'status',d.status,'contribution_points',d.contribution_points,'spendable_xp',0);
 update petal_private.idempotency set result=v_result where user_id=u and request_id=p_request_id;
 return v_result;
end $$;
revoke execute on function petal_private.submit_occurrence(uuid,uuid),petal_private.approve_submission(uuid,uuid) from public,anon;
grant execute on function petal_private.submit_occurrence(uuid,uuid),petal_private.approve_submission(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
