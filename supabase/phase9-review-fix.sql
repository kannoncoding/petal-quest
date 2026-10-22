-- DEV forward repair only. No family/task/accounting data is updated.
-- Safe to reapply: CREATE OR REPLACE retains the existing trigger and owner.
begin;
do $preflight$
begin
 if to_regprocedure('petal_private.phase9_audit_outbox()') is null
 or to_regprocedure('public.review_submission_checked(uuid,text,text,integer,uuid)') is null
 or to_regclass('public.occurrence_corrections') is null then
  raise exception 'Accepted Phase9 accounting upgrade is required; stop and report.';
 end if;
end $preflight$;
create or replace function petal_private.phase9_audit_outbox() returns trigger language plpgsql security definer set search_path='' as $$
declare v_rowdata jsonb:=to_jsonb(new);v_event_topic text;v_source uuid;v_payload jsonb;
begin
 v_source:=(v_rowdata->>'id')::uuid;v_payload:=jsonb_build_object('source_id',v_source);
 case tg_table_name
 when 'parent_actions' then v_event_topic:='parent.action_recorded';v_payload:=v_payload||jsonb_build_object('source_kind',v_rowdata->'source_kind','subject_id',v_rowdata->'source_id');
 when 'submission_reviews' then v_event_topic:='submission.reviewed';v_payload:=v_payload||jsonb_build_object('submission_id',v_rowdata->'submission_id','outcome',v_rowdata->'outcome');
 when 'occurrence_corrections' then v_event_topic:='occurrence.corrected';v_payload:=v_payload||jsonb_build_object('occurrence_id',v_rowdata->'occurrence_id');
 when 'deduction_reversals' then v_event_topic:='deduction.reversed';v_payload:=v_payload||jsonb_build_object('entry_id',v_rowdata->'entry_id');
 when 'bonus_reviews' then v_event_topic:='bonus.reviewed';v_payload:=v_payload||jsonb_build_object('bonus_id',v_rowdata->'bonus_id');
 when 'appeal_resolutions' then v_event_topic:='appeal.resolved';v_payload:=v_payload||jsonb_build_object('appeal_id',v_rowdata->'appeal_id');
 when 'reflection_note_history' then v_event_topic:='reflection.updated';
 when 'bonus_activities' then
 if tg_op='INSERT' then v_event_topic:='bonus.offered';
 elsif new.status='submitted' and new.status is distinct from old.status then v_event_topic:='bonus.submitted';v_source:=gen_random_uuid();
 else return new;end if;v_payload:=jsonb_build_object('bonus_id',new.id);
 when 'day_results' then v_event_topic:='day.finalized';v_source:=md5(new.family_id::text||':'||new.teen_id||':'||new.local_date)::uuid;v_payload:=jsonb_build_object('teen_id',new.teen_id,'local_date',new.local_date);
 else raise exception 'unknown_audit_source';end case;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values((v_rowdata->>'family_id')::uuid,v_event_topic,v_source,v_payload) on conflict(topic,source_id) do nothing;return new;
end $$;
revoke execute on function petal_private.phase9_audit_outbox() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
-- Definition readiness only: live workflow acceptance must still run.
select position('v_event_topic' in pg_get_functiondef('petal_private.phase9_audit_outbox()'::regprocedure))>0
 and position('on conflict(topic,source_id)' in pg_get_functiondef('petal_private.phase9_audit_outbox()'::regprocedure))>0
 as phase9_review_audit_fix_ready;
