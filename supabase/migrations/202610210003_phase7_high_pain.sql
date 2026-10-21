-- Phase 7 high-pain generic check-ins. Disabled until explicit owner policy exists.
begin;
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
