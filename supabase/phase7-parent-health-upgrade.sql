-- DEVELOPMENT ONLY: Petal Quest Dev hijtwgugzzpjjkuutyfy. Existing accepted Phase 6 schema required.
-- Adds date-only sharing, device-bound parent deletion and disabled high-pain alert policy. No existing health records are uploaded by SQL.
begin;
do $upgrade_preflight$
begin
 if to_regclass('public.families') is null then raise exception 'Apply the Phase 6 foundation before this upgrade.'; end if;
 if to_regclass('public.health_installations') is not null then raise exception 'Phase 7 health tables already exist. Stop; do not rerun this initial upgrade or drop tables.'; end if;
end $upgrade_preflight$;
-- SOURCE: migrations/202610210002_phase7_parent_health.sql
-- Phase 7: narrowly shared dates and installation-scoped wipe commands. Local source only.

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

-- SOURCE: migrations/202610210003_phase7_high_pain.sql
-- Phase 7 high-pain generic check-ins. Disabled until explicit owner policy exists.

create table petal_private.health_checkin_policy (
 singleton boolean primary key default true check(singleton), include_backdated boolean,
 push_text text check(push_text is null or length(trim(push_text)) between 1 and 240)
);
insert into petal_private.health_checkin_policy(singleton) values(true);
create table petal_private.health_checkin_events (
 id uuid primary key default gen_random_uuid(), installation_id uuid not null, target_user_id uuid not null,
 enrollment_generation uuid not null, family_id uuid not null, teen_id uuid not null,
 event_id uuid not null, local_date date not null, created_at timestamptz not null default clock_timestamp(),
 unique(target_user_id,event_id), unique(installation_id,target_user_id,enrollment_generation,local_date)
);
alter table petal_private.health_checkin_policy enable row level security;
alter table petal_private.health_checkin_events enable row level security;
revoke all on petal_private.health_checkin_policy,petal_private.health_checkin_events from public,anon,authenticated;
alter table petal_private.health_alert_recipients
 add column event_id uuid references petal_private.health_checkin_events(id) on delete cascade,
 add column local_date date,
 add column lease_id uuid,
 add column lease_until timestamptz,
 add column attempts integer not null default 0,
 add column delivered_at timestamptz,
 add constraint one_health_alert_per_recipient_date unique(installation_id,target_user_id,enrollment_generation,local_date,recipient_user_id);

-- Purge private date/event dedup metadata when the target vault generation ends.
create function petal_private.purge_checkin_generation() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_NAME='health_installations' then
 if old.enrollment_generation is distinct from new.enrollment_generation or old.family_id is distinct from new.family_id then
 delete from petal_private.health_checkin_events where installation_id=old.installation_id and target_user_id=old.user_id and enrollment_generation=old.enrollment_generation;
 end if;
 else
 if old.acknowledged_at is null and new.acknowledged_at is not null then
 delete from petal_private.health_checkin_events where installation_id=new.installation_id and target_user_id=new.target_user_id and enrollment_generation=new.enrollment_generation;
 end if;
 end if;
 return new;
end $$;
revoke execute on function petal_private.purge_checkin_generation() from public,anon,authenticated;
create trigger health_checkins_rotated after update on public.health_installations for each row execute function petal_private.purge_checkin_generation();
create trigger health_checkins_wiped after update on petal_private.health_wipe_commands for each row execute function petal_private.purge_checkin_generation();
create function petal_private.submit_high_pain_checkin(p_installation_id uuid,p_enrollment_generation uuid,p_local_date date,p_event_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.health_installations%rowtype; policy petal_private.health_checkin_policy%rowtype;
 e petal_private.health_checkin_events%rowtype; today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 i:=petal_private.require_health_installation(p_installation_id,p_enrollment_generation);
 select * into policy from petal_private.health_checkin_policy where singleton;
 if policy.include_backdated is null or policy.push_text is null then return jsonb_build_object('status','policy_not_configured'); end if;
 if p_event_id is null or p_local_date is null or p_local_date>today then raise exception 'invalid_checkin'; end if;
 if not policy.include_backdated and p_local_date<>today then return jsonb_build_object('status','date_not_eligible'); end if;
 if exists(select 1 from petal_private.health_wipe_commands c where c.installation_id=i.installation_id and c.target_user_id=i.user_id and c.enrollment_generation=i.enrollment_generation and c.claimed_at is not null) then raise exception 'generation_rotation_required'; end if;
 select * into e from petal_private.health_checkin_events where target_user_id=i.user_id and event_id=p_event_id;
 if found then
 if e.installation_id<>i.installation_id or e.enrollment_generation<>i.enrollment_generation or e.family_id<>i.family_id or e.local_date<>p_local_date then raise exception 'idempotency_conflict'; end if;
 return jsonb_build_object('status','duplicate');
 end if;
 if exists(select 1 from petal_private.health_checkin_events where installation_id=i.installation_id and target_user_id=i.user_id and enrollment_generation=i.enrollment_generation and local_date=p_local_date) then return jsonb_build_object('status','duplicate'); end if;
 insert into petal_private.health_checkin_events(installation_id,target_user_id,enrollment_generation,family_id,teen_id,event_id,local_date)
 values(i.installation_id,i.user_id,i.enrollment_generation,i.family_id,i.teen_id,p_event_id,p_local_date) returning * into e;
 insert into petal_private.health_alert_recipients(installation_id,target_user_id,enrollment_generation,family_id,recipient_user_id,event_id,local_date)
 select i.installation_id,i.user_id,i.enrollment_generation,i.family_id,m.user_id,e.id,p_local_date
 from public.memberships m where m.family_id=i.family_id and m.role='parent' and m.active;
 return jsonb_build_object('status','queued');
end $$;
create function petal_private.list_parent_checkins() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('checkins',coalesce(jsonb_agg(jsonb_build_object('local_date',q.local_date) order by q.local_date desc),'[]'::jsonb))
 from petal_private.health_alert_recipients q
 join public.health_installations i on i.installation_id=q.installation_id and i.user_id=q.target_user_id and i.enrollment_generation=q.enrollment_generation and i.family_id=q.family_id
 where q.recipient_user_id=auth.uid() and q.local_date is not null
 and exists(select 1 from public.memberships m where m.family_id=q.family_id and m.user_id=auth.uid() and m.role='parent' and m.active)
 and exists(select 1 from public.memberships t where t.family_id=i.family_id and t.user_id=i.user_id and t.actor_id=i.teen_id and t.role='teen' and t.active);
$$;
create function petal_private.claim_high_pain_push(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path='' as $$
declare q petal_private.health_alert_recipients%rowtype; lease uuid; payload jsonb; deliveries jsonb:='[]'::jsonb; approved_text text;
begin
 select push_text into approved_text from petal_private.health_checkin_policy where singleton and include_backdated is not null;
 if approved_text is null then return jsonb_build_object('deliveries',deliveries); end if;
 for q in select r.* from petal_private.health_alert_recipients r
 join public.health_installations i on i.installation_id=r.installation_id and i.user_id=r.target_user_id and i.enrollment_generation=r.enrollment_generation and i.family_id=r.family_id
 where ((select include_backdated from petal_private.health_checkin_policy where singleton) or r.local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date) and r.delivered_at is null and (r.lease_until is null or r.lease_until<=clock_timestamp()) and r.local_date is not null
 and exists(select 1 from public.memberships p where p.family_id=r.family_id and p.user_id=r.recipient_user_id and p.role='parent' and p.active)
 and exists(select 1 from public.memberships t where t.family_id=i.family_id and t.user_id=i.user_id and t.actor_id=i.teen_id and t.role='teen' and t.active)
 and exists(select 1 from public.device_registrations d where d.family_id=r.family_id and d.user_id=r.recipient_user_id)
 order by r.created_at,r.id limit greatest(1,least(coalesce(p_limit,20),100)) for update of r skip locked
 loop
 lease:=gen_random_uuid();
 update petal_private.health_alert_recipients set lease_id=lease,lease_until=clock_timestamp()+interval '5 minutes',attempts=attempts+1 where id=q.id;
 select coalesce(jsonb_agg(d.push_token),'[]'::jsonb) into payload from public.device_registrations d
 where d.family_id=q.family_id and d.user_id=q.recipient_user_id
 and exists(select 1 from public.memberships p where p.family_id=d.family_id and p.user_id=d.user_id and p.role='parent' and p.active);
 deliveries:=deliveries||jsonb_build_array(jsonb_build_object('delivery_id',q.id,'lease_id',lease,'recipient_user_id',q.recipient_user_id,'local_date',q.local_date,'tokens',payload,'push_text',approved_text));
 end loop;
 return jsonb_build_object('deliveries',deliveries);
end $$;
create function petal_private.complete_high_pain_push(p_delivery_id uuid,p_lease_id uuid,p_success boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 update petal_private.health_alert_recipients set delivered_at=case when p_success then clock_timestamp() else delivered_at end,lease_id=null,lease_until=null
 where id=p_delivery_id and lease_id=p_lease_id and lease_until>clock_timestamp();
 if not found then return jsonb_build_object('status','stale_lease'); end if;
 return jsonb_build_object('status','done');
end $$;
-- Clients learn the approved policy before transmitting even a check-in date.
create function petal_private.get_checkin_policy() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('enabled',include_backdated is not null and push_text is not null,
 'include_backdated',coalesce(include_backdated,false),'server_today',(clock_timestamp() at time zone 'America/Costa_Rica')::date)
 from petal_private.health_checkin_policy where singleton;
$$;
create function public.get_checkin_policy() returns jsonb
language sql security invoker set search_path='' as $$ select petal_private.get_checkin_policy(); $$;
create function public.submit_high_pain_checkin(p_installation_id uuid,p_enrollment_generation uuid,p_local_date date,p_event_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select petal_private.submit_high_pain_checkin(p_installation_id,p_enrollment_generation,p_local_date,p_event_id); $$;
create function public.list_parent_checkins() returns jsonb
language sql security invoker set search_path='' as $$ select petal_private.list_parent_checkins(); $$;
create function public.claim_high_pain_push(p_limit integer default 20) returns jsonb
language sql security invoker set search_path='' as $$ select petal_private.claim_high_pain_push(p_limit); $$;
create function public.complete_high_pain_push(p_delivery_id uuid,p_lease_id uuid,p_success boolean) returns jsonb
language sql security invoker set search_path='' as $$ select petal_private.complete_high_pain_push(p_delivery_id,p_lease_id,p_success); $$;
do $$ declare sig text; begin
 foreach sig in array array['submit_high_pain_checkin(uuid,uuid,date,uuid)','list_parent_checkins()','get_checkin_policy()'] loop
 execute 'revoke execute on function public.'||sig||' from public,anon';
 execute 'revoke execute on function petal_private.'||sig||' from public,anon';
 execute 'grant execute on function public.'||sig||' to authenticated';
 execute 'grant execute on function petal_private.'||sig||' to authenticated';
 end loop;
 foreach sig in array array['claim_high_pain_push(integer)','complete_high_pain_push(uuid,uuid,boolean)'] loop
 execute 'revoke execute on function public.'||sig||' from public,anon,authenticated';
 execute 'revoke execute on function petal_private.'||sig||' from public,anon,authenticated';
 execute 'grant execute on function public.'||sig||' to service_role';
 execute 'grant execute on function petal_private.'||sig||' to service_role';
 end loop;
end $$;
grant usage on schema petal_private to service_role;
notify pgrst, 'reload schema';

commit;
