begin;
create function public.revoke_membership(p_family_id uuid,p_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); m public.memberships%rowtype;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 select * into m from public.memberships where family_id=p_family_id and user_id=p_user_id for update;
 if not found then raise exception 'membership_not_found'; end if;
 if m.active and m.role='parent' and (select count(*) from public.memberships where family_id=p_family_id and role='parent' and active)<=1 then raise exception 'last_parent_cannot_be_revoked'; end if;
 update public.memberships set active=false,revoked_at=coalesce(revoked_at,clock_timestamp()) where family_id=p_family_id and user_id=p_user_id;
 update petal_private.invites set revoked=true where family_id=p_family_id and (issued_by=p_user_id or consumed_by=p_user_id);
 delete from public.device_registrations where family_id=p_family_id and user_id=p_user_id;
 return jsonb_build_object('family_id',p_family_id,'user_id',p_user_id,'actor_id',m.actor_id,'active',false);
end $$;

create function public.issue_teen_replacement(p_family_id uuid,p_actor_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); c text; e timestamptz;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 if not exists(select 1 from public.family_actors where family_id=p_family_id and id=p_actor_id and role='teen')
 or exists(select 1 from public.memberships where actor_id=p_actor_id and active) then raise exception 'inactive_teen_required'; end if;
 if not petal_private.consume_rate('issue_invite',5) then return jsonb_build_object('error','rate_limited'); end if;
 update petal_private.invites set revoked=true where family_id=p_family_id and replacement_actor_id=p_actor_id and consumed_at is null;
 c:=encode(extensions.gen_random_bytes(32),'hex'); e:=clock_timestamp()+interval '15 minutes';
 insert into petal_private.invites(family_id,kind,replacement_actor_id,code_hash,issued_by,expires_at)
 values(p_family_id,'teen',p_actor_id,extensions.digest(c,'sha256'),u,e);
 return jsonb_build_object('code',c,'expires_at',e);
end $$;

create function public.register_device(p_family_id uuid,p_push_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); d public.device_registrations%rowtype;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id) then raise exception 'membership_required' using errcode='42501'; end if;
 if p_push_token is null or length(p_push_token) not between 1 and 4096 then raise exception 'invalid_push_token'; end if;
 insert into public.device_registrations(family_id,user_id,push_token) values(p_family_id,u,p_push_token)
 on conflict(user_id,push_token) do update set updated_at=clock_timestamp() returning * into d;
 return jsonb_build_object('device_id',d.id);
end $$;

-- Teens read their stable subject's work; parents read the family's work.
create function petal_private.can_read_teen(p_family_id uuid,p_actor_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.memberships where family_id=p_family_id and user_id=auth.uid() and active and (role='parent' or actor_id=p_actor_id));
$$;
grant execute on function petal_private.can_read_teen(uuid,uuid) to authenticated;
revoke execute on function petal_private.can_read_teen(uuid,uuid) from public,anon;
do $$ declare t text; begin
 foreach t in array array['task_occurrences','submissions','xp_events','day_results','reward_requests'] loop
 execute format('drop policy member_read on public.%I',t);
 execute format('create policy subject_read on public.%I for select to authenticated using (petal_private.can_read_teen(family_id,teen_id))',t);
 end loop;
end $$;
drop policy member_read on public.decisions;
create policy subject_read on public.decisions for select to authenticated using(
 exists(select 1 from public.submissions s where s.id=submission_id and petal_private.can_read_teen(s.family_id,s.teen_id))
);

-- Only these thin SECURITY INVOKER functions are exposed through PostgREST.
-- Private implementations retain explicit checks and a pinned empty search_path.
alter function public.create_family(text) set schema petal_private;
alter function public.issue_parent_invite(uuid) set schema petal_private;
alter function public.issue_teen_pairing(uuid) set schema petal_private;
alter function public.accept_parent_invite(text) set schema petal_private;
alter function public.redeem_teen_pairing(text) set schema petal_private;
alter function public.create_occurrence(uuid,uuid) set schema petal_private;
alter function public.submit_occurrence(uuid,uuid) set schema petal_private;
alter function public.approve_submission(uuid,uuid) set schema petal_private;
alter function public.revoke_membership(uuid,uuid) set schema petal_private;
alter function public.issue_teen_replacement(uuid,uuid) set schema petal_private;
alter function public.register_device(uuid,text) set schema petal_private;
create function public.create_family(p_name text) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.create_family(p_name); $$;
create function public.issue_parent_invite(p_family_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.issue_parent_invite(p_family_id); $$;
create function public.issue_teen_pairing(p_family_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.issue_teen_pairing(p_family_id); $$;
create function public.accept_parent_invite(p_code text) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.accept_parent_invite(p_code); $$;
create function public.redeem_teen_pairing(p_code text) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.redeem_teen_pairing(p_code); $$;
create function public.create_occurrence(p_definition_id uuid,p_teen_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.create_occurrence(p_definition_id,p_teen_id); $$;
create function public.submit_occurrence(p_occurrence_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.submit_occurrence(p_occurrence_id,p_request_id); $$;
create function public.approve_submission(p_submission_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.approve_submission(p_submission_id,p_request_id); $$;
create function public.revoke_membership(p_family_id uuid,p_user_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.revoke_membership(p_family_id,p_user_id); $$;
create function public.issue_teen_replacement(p_family_id uuid,p_actor_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.issue_teen_replacement(p_family_id,p_actor_id); $$;
create function public.register_device(p_family_id uuid,p_push_token text) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.register_device(p_family_id,p_push_token); $$;
do $$ declare sig text; begin
 foreach sig in array array['create_family(text)','issue_parent_invite(uuid)','issue_teen_pairing(uuid)','accept_parent_invite(text)','redeem_teen_pairing(text)','create_occurrence(uuid,uuid)','submit_occurrence(uuid,uuid)','approve_submission(uuid,uuid)','revoke_membership(uuid,uuid)','issue_teen_replacement(uuid,uuid)','register_device(uuid,text)'] loop
 execute 'revoke execute on function public.'||sig||' from public,anon';
 execute 'grant execute on function public.'||sig||' to authenticated';
 execute 'revoke execute on function petal_private.'||sig||' from public,anon';
 execute 'grant execute on function petal_private.'||sig||' to authenticated';
 end loop;
end $$;
commit;
