-- Phase 7: narrowly shared dates and installation-scoped wipe commands. Local source only.
begin;
create table public.health_installations (
 installation_id uuid not null, user_id uuid not null references auth.users(id),
 family_id uuid not null references public.families(id), teen_id uuid not null,
 enrollment_generation uuid not null, registered_at timestamptz not null default clock_timestamp(),
 primary key(installation_id,user_id),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table petal_private.health_installation_generations (
 installation_id uuid not null, user_id uuid not null, enrollment_generation uuid not null,
 primary key(installation_id,user_id,enrollment_generation)
);
alter table petal_private.health_installation_generations enable row level security;
revoke all on petal_private.health_installation_generations from public,anon,authenticated;
create table public.period_date_ranges (
 installation_id uuid not null, user_id uuid not null, enrollment_generation uuid not null,
 record_id uuid not null, family_id uuid not null, teen_id uuid not null,
 start_date date not null, end_date date,
 primary key(installation_id,user_id,enrollment_generation,record_id),
 foreign key(installation_id,user_id) references public.health_installations(installation_id,user_id),
 check(end_date is null or end_date>=start_date)
);
create table petal_private.health_wipe_commands (
 id uuid primary key default gen_random_uuid(), installation_id uuid not null, target_user_id uuid not null,
 family_id uuid not null, teen_id uuid not null, enrollment_generation uuid not null,
 issuer_user_id uuid not null references auth.users(id), request_id uuid not null,
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null default clock_timestamp()+interval '30 days',
 claimed_at timestamptz, acknowledged_at timestamptz, unique(issuer_user_id,request_id)
);
-- Reserved recipient queue only: no ingestion RPC, threshold, text, or delivery pipeline
-- exists until the product owner supplies the high-pain alert contract.
create table petal_private.health_alert_recipients (
 id uuid primary key default gen_random_uuid(), installation_id uuid not null, target_user_id uuid not null,
 enrollment_generation uuid not null, family_id uuid not null, recipient_user_id uuid not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table public.health_installations enable row level security;
alter table public.period_date_ranges enable row level security;
alter table petal_private.health_wipe_commands enable row level security;
alter table petal_private.health_alert_recipients enable row level security;
revoke all on public.health_installations,public.period_date_ranges from public,anon,authenticated;
revoke all on petal_private.health_wipe_commands,petal_private.health_alert_recipients from public,anon,authenticated;
grant select on public.health_installations,public.period_date_ranges to authenticated;

create function petal_private.health_visible(p_family_id uuid,p_teen_id uuid,p_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.memberships t where t.family_id=p_family_id and t.actor_id=p_teen_id and t.user_id=p_user_id and t.role='teen' and t.active)
 and exists(select 1 from public.memberships m where m.family_id=p_family_id and m.user_id=auth.uid() and m.active and (m.role='parent' or (m.role='teen' and m.user_id=p_user_id)));
$$;
create policy current_installations on public.health_installations for select to authenticated
 using(petal_private.health_visible(family_id,teen_id,user_id));
create policy current_period_dates on public.period_date_ranges for select to authenticated
 using(petal_private.health_visible(family_id,teen_id,user_id) and exists(select 1 from public.health_installations i where i.installation_id=period_date_ranges.installation_id and i.user_id=period_date_ranges.user_id and i.enrollment_generation=period_date_ranges.enrollment_generation));

-- Every mutation locks the family before rechecking membership, matching revocation.
create function petal_private.require_health_installation(p_installation_id uuid,p_enrollment_generation uuid)
returns public.health_installations language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); i public.health_installations%rowtype;
begin
 select * into i from public.health_installations where installation_id=p_installation_id and user_id=u;
 if not found then raise exception 'installation_not_authorized' using errcode='42501'; end if;
 perform 1 from public.families where id=i.family_id for update;
 select * into i from public.health_installations where installation_id=p_installation_id and user_id=u for update;
 if i.enrollment_generation<>p_enrollment_generation or p_enrollment_generation is null or not exists(select 1 from public.memberships where family_id=i.family_id and user_id=u and actor_id=i.teen_id and role='teen' and active) then raise exception 'installation_not_authorized' using errcode='42501'; end if;
 return i;
end $$;
create function petal_private.register_health_installation(p_installation_id uuid,p_enrollment_generation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; old public.health_installations%rowtype;
begin
 if p_installation_id is null or p_enrollment_generation is null then raise exception 'invalid_installation'; end if;
 select * into m from public.memberships where user_id=u and role='teen' and active;
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 select * into m from public.memberships where user_id=u and role='teen' and active;
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 -- Serialize initial registration as well as rotation for this installation/identity.
 perform pg_advisory_xact_lock(hashtextextended(p_installation_id::text||u::text,0));
 select * into old from public.health_installations where installation_id=p_installation_id and user_id=u for update;
 if found and old.enrollment_generation=p_enrollment_generation and (old.family_id<>m.family_id or old.teen_id<>m.actor_id) then raise exception 'generation_rotation_required'; end if;
 if old.installation_id is null or old.enrollment_generation<>p_enrollment_generation then
 if exists(select 1 from petal_private.health_installation_generations where installation_id=p_installation_id and user_id=u and enrollment_generation=p_enrollment_generation) then raise exception 'retired_generation'; end if;
 insert into petal_private.health_installation_generations values(p_installation_id,u,p_enrollment_generation);
 end if;
 if old.installation_id is not null and old.enrollment_generation<>p_enrollment_generation then
 delete from public.period_date_ranges where installation_id=p_installation_id and user_id=u;
 delete from petal_private.health_alert_recipients where installation_id=p_installation_id and target_user_id=u;
 end if;
 insert into public.health_installations(installation_id,user_id,family_id,teen_id,enrollment_generation)
 values(p_installation_id,u,m.family_id,m.actor_id,p_enrollment_generation)
 on conflict(installation_id,user_id) do update set family_id=excluded.family_id,teen_id=excluded.teen_id,enrollment_generation=excluded.enrollment_generation;
 return jsonb_build_object('installation_id',p_installation_id,'enrollment_generation',p_enrollment_generation,'family_id',m.family_id,'teen_id',m.actor_id,'label','Teen device');
end $$;
create function petal_private.list_health_installations() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('installations',coalesce(jsonb_agg(jsonb_build_object('family_id',i.family_id,'installation_id',i.installation_id,'teen_id',i.teen_id,'enrollment_generation',i.enrollment_generation,'label','Teen device','latest_wipe_status',(select case when c.acknowledged_at is not null then 'done' when c.claimed_at is not null then 'claimed' when c.expires_at<=clock_timestamp() then 'expired' else 'requested' end from petal_private.health_wipe_commands c where c.installation_id=i.installation_id and c.target_user_id=i.user_id and c.family_id=i.family_id order by c.created_at desc,c.id desc limit 1))),'[]'::jsonb))
 from public.health_installations i where petal_private.health_visible(i.family_id,i.teen_id,i.user_id);
$$;
create function petal_private.list_period_ranges(p_family_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('period_ranges',coalesce(jsonb_agg(jsonb_build_object('installation_id',r.installation_id,'record_id',r.record_id,'start_date',r.start_date,'end_date',r.end_date) order by r.start_date),'[]'::jsonb))
 from public.period_date_ranges r join public.health_installations i on i.installation_id=r.installation_id and i.user_id=r.user_id and i.enrollment_generation=r.enrollment_generation
 where r.family_id=p_family_id and petal_private.health_visible(r.family_id,r.teen_id,r.user_id);
$$;
create function petal_private.request_wipe(p_installation_id uuid,p_enrollment_generation uuid,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); m public.memberships%rowtype; i public.health_installations%rowtype; c petal_private.health_wipe_commands%rowtype;
begin
 if p_request_id is null or p_installation_id is null or p_enrollment_generation is null then raise exception 'request_target_required'; end if;
 select * into m from public.memberships where user_id=u and role='parent' and active;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 select * into c from petal_private.health_wipe_commands where issuer_user_id=u and request_id=p_request_id;
 if found then
 if p_enrollment_generation is null or c.installation_id<>p_installation_id or c.family_id<>m.family_id or c.enrollment_generation<>p_enrollment_generation then raise exception 'idempotency_conflict'; end if;
 return jsonb_build_object('command_id',c.id,'status','requested','requested_at',c.created_at,'expires_at',c.expires_at);
 end if;
 if (select count(*) from public.health_installations x where x.installation_id=p_installation_id and x.family_id=m.family_id and petal_private.health_visible(x.family_id,x.teen_id,x.user_id))<>1 then raise exception 'installation_not_authorized' using errcode='42501'; end if;
 select * into i from public.health_installations x where x.installation_id=p_installation_id and x.family_id=m.family_id and petal_private.health_visible(x.family_id,x.teen_id,x.user_id) for update;
 if p_enrollment_generation is null or i.enrollment_generation<>p_enrollment_generation then raise exception 'generation_changed'; end if;
 insert into petal_private.health_wipe_commands(installation_id,target_user_id,family_id,teen_id,enrollment_generation,issuer_user_id,request_id)
 values(i.installation_id,i.user_id,i.family_id,i.teen_id,i.enrollment_generation,u,p_request_id) returning * into c;
 return jsonb_build_object('command_id',c.id,'status','requested','requested_at',c.created_at,'expires_at',c.expires_at);
end $$;
create function petal_private.list_pending_wipes(p_installation_id uuid,p_enrollment_generation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.health_installations%rowtype;
begin
 i:=petal_private.require_health_installation(p_installation_id,p_enrollment_generation);
 return (select jsonb_build_object('commands',coalesce(jsonb_agg(jsonb_build_object('command_id',c.id,'claimed',c.claimed_at is not null,'expires_at',c.expires_at)),'[]'::jsonb)) from petal_private.health_wipe_commands c where c.installation_id=i.installation_id and c.target_user_id=i.user_id and c.family_id=i.family_id and c.teen_id=i.teen_id and c.enrollment_generation=i.enrollment_generation and c.acknowledged_at is null and (c.claimed_at is not null or c.expires_at>clock_timestamp()) and (c.claimed_at is not null or exists(select 1 from public.memberships where family_id=c.family_id and user_id=c.issuer_user_id and role='parent' and active)));
end $$;
create function petal_private.claim_wipe(p_command_id uuid,p_installation_id uuid,p_enrollment_generation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.health_installations%rowtype; c petal_private.health_wipe_commands%rowtype;
begin
 i:=petal_private.require_health_installation(p_installation_id,p_enrollment_generation);
 select * into c from petal_private.health_wipe_commands where id=p_command_id and installation_id=i.installation_id and target_user_id=i.user_id and family_id=i.family_id and teen_id=i.teen_id and enrollment_generation=i.enrollment_generation for update;
 if not found then raise exception 'command_not_authorized' using errcode='42501'; end if;
 if c.acknowledged_at is not null then return jsonb_build_object('status','done'); end if;
 -- First successful claim is the authorization instant. Retrying that claim remains
 -- authorized after issuer revocation/expiry; the already authorized wipe may race it.
 if c.claimed_at is null then
 if c.expires_at<=clock_timestamp() or not exists(select 1 from public.memberships where family_id=c.family_id and user_id=c.issuer_user_id and role='parent' and active) then raise exception 'command_not_authorized' using errcode='42501'; end if;
 update petal_private.health_wipe_commands set claimed_at=clock_timestamp() where id=c.id;
 end if;
 return jsonb_build_object('status','claimed','command_id',c.id,'enrollment_generation',c.enrollment_generation);
end $$;
create function petal_private.acknowledge_wipe(p_command_id uuid,p_installation_id uuid,p_enrollment_generation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.health_installations%rowtype; c petal_private.health_wipe_commands%rowtype;
begin
 i:=petal_private.require_health_installation(p_installation_id,p_enrollment_generation);
 select * into c from petal_private.health_wipe_commands where id=p_command_id and installation_id=i.installation_id and target_user_id=i.user_id and family_id=i.family_id and teen_id=i.teen_id and enrollment_generation=i.enrollment_generation for update;
 if not found or c.claimed_at is null then raise exception 'command_not_authorized' using errcode='42501'; end if;
 -- Client ACKs only after its local transaction erased the vault; empty vaults ACK
 -- identically. No parent-visible health presence or wipe success oracle is exposed.
 if c.acknowledged_at is null then
 delete from public.period_date_ranges where installation_id=i.installation_id and user_id=i.user_id and enrollment_generation=i.enrollment_generation;
 delete from petal_private.health_alert_recipients where installation_id=i.installation_id and target_user_id=i.user_id and enrollment_generation=i.enrollment_generation;
 update petal_private.health_wipe_commands set acknowledged_at=clock_timestamp() where id=c.id;
 end if;
 return jsonb_build_object('status','done');
end $$;
create function petal_private.upsert_period_range(p_installation_id uuid,p_enrollment_generation uuid,p_record_id uuid,p_start_date date,p_end_date date default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.health_installations%rowtype; today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 i:=petal_private.require_health_installation(p_installation_id,p_enrollment_generation);
 if exists(select 1 from petal_private.health_wipe_commands c where c.installation_id=i.installation_id and c.target_user_id=i.user_id and c.enrollment_generation=i.enrollment_generation and c.claimed_at is not null) then raise exception 'generation_rotation_required'; end if;
 if p_record_id is null or p_start_date is null or p_start_date>today or (p_end_date is not null and (p_end_date<p_start_date or p_end_date>today)) then raise exception 'invalid_period_range'; end if;
 if exists(select 1 from public.period_date_ranges r where r.user_id=i.user_id and not (r.installation_id=i.installation_id and r.enrollment_generation=i.enrollment_generation and r.record_id=p_record_id) and daterange(r.start_date,coalesce(r.end_date,today),'[]') && daterange(p_start_date,coalesce(p_end_date,today),'[]')) then raise exception 'overlapping_period_range'; end if;
 insert into public.period_date_ranges values(i.installation_id,i.user_id,i.enrollment_generation,p_record_id,i.family_id,i.teen_id,p_start_date,p_end_date)
 on conflict(installation_id,user_id,enrollment_generation,record_id) do update set start_date=excluded.start_date,end_date=excluded.end_date;
 return jsonb_build_object('status','saved','record_id',p_record_id);
end $$;
create function petal_private.delete_period_range(p_installation_id uuid,p_enrollment_generation uuid,p_record_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.health_installations%rowtype;
begin
 i:=petal_private.require_health_installation(p_installation_id,p_enrollment_generation);
 delete from public.period_date_ranges where installation_id=i.installation_id and user_id=i.user_id and enrollment_generation=i.enrollment_generation and record_id=p_record_id;
 return jsonb_build_object('status','deleted');
end $$;

-- Generate only thin, explicitly named public wrappers and narrowly scoped grants.
do $boundary$
declare spec text[]; signature text;
begin
 foreach spec slice 1 in array array[
 ['register_health_installation','p_installation_id uuid,p_enrollment_generation uuid','uuid,uuid','p_installation_id,p_enrollment_generation'],
 ['list_health_installations','','',''],
 ['list_period_ranges','p_family_id uuid','uuid','p_family_id'],
 ['request_wipe','p_installation_id uuid,p_enrollment_generation uuid,p_request_id uuid','uuid,uuid,uuid','p_installation_id,p_enrollment_generation,p_request_id'],
 ['list_pending_wipes','p_installation_id uuid,p_enrollment_generation uuid','uuid,uuid','p_installation_id,p_enrollment_generation'],
 ['claim_wipe','p_command_id uuid,p_installation_id uuid,p_enrollment_generation uuid','uuid,uuid,uuid','p_command_id,p_installation_id,p_enrollment_generation'],
 ['acknowledge_wipe','p_command_id uuid,p_installation_id uuid,p_enrollment_generation uuid','uuid,uuid,uuid','p_command_id,p_installation_id,p_enrollment_generation'],
 ['upsert_period_range','p_installation_id uuid,p_enrollment_generation uuid,p_record_id uuid,p_start_date date,p_end_date date default null','uuid,uuid,uuid,date,date','p_installation_id,p_enrollment_generation,p_record_id,p_start_date,p_end_date'],
 ['delete_period_range','p_installation_id uuid,p_enrollment_generation uuid,p_record_id uuid','uuid,uuid,uuid','p_installation_id,p_enrollment_generation,p_record_id']
 ] loop
 execute format('create function public.%I(%s) returns jsonb language sql security invoker set search_path='''' as %L',spec[1],spec[2],'select petal_private.'||spec[1]||'('||spec[4]||');');
 signature:=spec[1]||'('||spec[3]||')';
 execute 'revoke execute on function public.'||signature||' from public,anon';
 execute 'grant execute on function public.'||signature||' to authenticated';
 execute 'revoke execute on function petal_private.'||signature||' from public,anon';
 execute 'grant execute on function petal_private.'||signature||' to authenticated';
 end loop;
end $boundary$;
revoke execute on function petal_private.require_health_installation(uuid,uuid) from public,anon,authenticated;
revoke execute on function petal_private.health_visible(uuid,uuid,uuid) from public,anon;
grant execute on function petal_private.health_visible(uuid,uuid,uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
