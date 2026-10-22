-- Stale legacy review routes cannot approve a new returned/resubmitted generation.
begin;
alter function petal_private.review_submission(uuid,text,text,uuid) rename to review_submission_core;
create function petal_private.review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501';end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501';end if;
 if not exists(select 1 from petal_private.idempotency where user_id=u and request_id=p_request_id and result is not null)
 and not (p_outcome='approved' and exists(select 1 from public.decisions where submission_id=s.id))
 and exists(select 1 from public.submission_reviews where submission_id=s.id and outcome in ('returned','rejected')) then raise exception 'stale_review_refresh_required';end if;
 return petal_private.review_submission_core(p_submission_id,p_outcome,p_review_note,p_request_id);
end $$;
revoke execute on function petal_private.review_submission_core(uuid,text,text,uuid) from public,anon,authenticated;
revoke execute on function petal_private.review_submission(uuid,text,text,uuid) from public,anon;
grant execute on function petal_private.review_submission(uuid,text,text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
