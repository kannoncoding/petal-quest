-- DEVELOPMENT ONLY: select Petal Quest Dev (hijtwgugzzpjjkuutyfy) in the dashboard.
-- Atomic initial deployment; no synthetic Auth fixture. Stop if a schema already exists.
begin;
do $preflight$
begin
 if exists(select 1 from information_schema.tables where table_schema='public' and table_name='families') then
  raise exception 'Phase 6 families table already exists. Stop; do not rerun the initial deployment.';
 end if;
end $preflight$;
-- SOURCE: migrations/202610200001_phase6_foundation.sql
-- Phase 6 local foundation. Apply with a privileged migration identity, never an app key.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists petal_private;
revoke all on schema petal_private from public, anon, authenticated;

create table public.families (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 80),
 timezone text not null default 'America/Costa_Rica' check(timezone='America/Costa_Rica'), created_at timestamptz not null default clock_timestamp()
);
create table public.family_actors (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
 role text not null check(role in ('parent','teen')), unique(family_id,id)
);
create table public.memberships (
 family_id uuid not null references public.families(id), user_id uuid not null references auth.users(id),
 role text not null check(role in ('parent','teen')), actor_id uuid not null, active boolean not null default true, revoked_at timestamptz,
 foreign key(family_id,actor_id) references public.family_actors(family_id,id), created_at timestamptz not null default clock_timestamp(),
 primary key(family_id,user_id), unique(user_id)
);
create unique index one_active_identity_per_actor on public.memberships(actor_id) where active;
create table public.task_definitions (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
 title text not null, enabled boolean not null default false, unique(id,family_id)
);
create table public.rule_versions (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, definition_id uuid not null,
 version integer not null check(version>0), points integer not null check(points between 1 and 100),
 local_due_time time, weekdays integer[] not null check(cardinality(weekdays)>0 and weekdays <@ array[0,1,2,3,4,5,6]),
 current_version boolean not null default false, approved_source text not null,
 unique(definition_id,version), unique(id,family_id),
 foreign key(definition_id,family_id) references public.task_definitions(id,family_id)
);
create unique index one_current_rule on public.rule_versions(definition_id) where current_version;
create table public.task_occurrences (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, definition_id uuid not null,
 teen_id uuid not null, rule_version_id uuid not null, local_date date not null, slot_key text not null default 'daily',
 points_snapshot integer not null check(points_snapshot between 1 and 100), due_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),
 unique(definition_id,teen_id,local_date,slot_key), unique(id,family_id),
 foreign key(definition_id,family_id) references public.task_definitions(id,family_id),
 foreign key(rule_version_id,family_id) references public.rule_versions(id,family_id),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.submissions (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, occurrence_id uuid not null unique,
 teen_id uuid not null, submitted_at timestamptz not null default clock_timestamp(),
 status text not null default 'pending' check(status in ('pending','approved')),
 unique(id,family_id), foreign key(occurrence_id,family_id) references public.task_occurrences(id,family_id),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.decisions (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, submission_id uuid not null unique,
 parent_id uuid not null references auth.users(id), status text not null check(status='approved'),
 contribution_points integer not null check(contribution_points between 1 and 100),
 decided_at timestamptz not null default clock_timestamp(), unique(id,family_id),
 foreign key(submission_id,family_id) references public.submissions(id,family_id)
);
create table public.xp_events (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, teen_id uuid not null,
 decision_id uuid not null unique, local_date date not null,
 event_kind text not null default 'duty_contribution' check(event_kind='duty_contribution'),
 contribution_points integer not null check(contribution_points between 1 and 100),
 spendable_xp integer not null default 0 check(spendable_xp=0), coins integer not null default 0 check(coins=0),
 created_at timestamptz not null default clock_timestamp(),
 foreign key(decision_id,family_id) references public.decisions(id,family_id),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
-- Reserved day guard: no publication/finalization RPC in Phase 6. Once a result exists,
-- ordinary approvals fail closed pending the unresolved pre-seal correction contract.
create table public.day_results (
 family_id uuid not null, teen_id uuid not null, local_date date not null,
 first_published_at timestamptz not null, effective_seal_at timestamptz not null,
 primary key(family_id,teen_id,local_date),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.reward_requests (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, teen_id uuid not null,
 title_snapshot text not null, price_snapshot integer not null check(price_snapshot>0),
 status text not null default 'requested' check(status in ('requested','approved','cancelled','fulfilled')),
 created_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.device_registrations (
 id uuid primary key default gen_random_uuid(), family_id uuid not null, user_id uuid not null,
 push_token text not null, updated_at timestamptz not null default clock_timestamp(),
 unique(user_id,push_token), foreign key(family_id,user_id) references public.memberships(family_id,user_id)
);
create table petal_private.invites (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
 kind text not null check(kind in ('parent','teen')), replacement_actor_id uuid references public.family_actors(id), revoked boolean not null default false, code_hash bytea not null unique,
 issued_by uuid not null references auth.users(id), created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null, consumed_by uuid references auth.users(id), consumed_at timestamptz,
 check((consumed_by is null)=(consumed_at is null))
);
create table petal_private.rate_limits (
 user_id uuid not null references auth.users(id), action text not null, window_start timestamptz not null,
 attempts integer not null, primary key(user_id,action)
);
create table petal_private.idempotency (
 user_id uuid not null references auth.users(id), request_id uuid not null, action text not null,
 request_hash bytea not null, result jsonb, created_at timestamptz not null default clock_timestamp(),
 primary key(user_id,request_id)
);
create table petal_private.outbox (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
 topic text not null, source_id uuid not null, payload jsonb not null,
 created_at timestamptz not null default clock_timestamp(), delivered_at timestamptz,
 unique(topic,source_id)
);

-- Explicit declarations keep every created table protected and make the migration
-- visible to static SQL-editor checks as well as PostgreSQL itself.
alter table public.families enable row level security;
alter table public.family_actors enable row level security;
alter table public.memberships enable row level security;
alter table public.task_definitions enable row level security;
alter table public.rule_versions enable row level security;
alter table public.task_occurrences enable row level security;
alter table public.submissions enable row level security;
alter table public.decisions enable row level security;
alter table public.xp_events enable row level security;
alter table public.day_results enable row level security;
alter table public.reward_requests enable row level security;
alter table public.device_registrations enable row level security;
alter table petal_private.invites enable row level security;
alter table petal_private.rate_limits enable row level security;
alter table petal_private.idempotency enable row level security;
alter table petal_private.outbox enable row level security;

create function petal_private.is_member(p_family_id uuid, p_role text default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.memberships m where m.family_id=p_family_id and m.user_id=auth.uid() and m.active
 and (p_role is null or m.role=p_role));
$$;
create function petal_private.require_identity(p_permanent boolean default false)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
 if u is null or not exists(select 1 from auth.users where id=u) then raise exception 'authentication_required' using errcode='42501'; end if;
 -- Consult authoritative Auth record as well as signed JWT; user_metadata never grants authority.
 if p_permanent and (coalesce((auth.jwt()->>'is_anonymous')::boolean,true)
 or exists(select 1 from auth.users where id=u and is_anonymous)) then
 raise exception 'permanent_identity_required' using errcode='42501'; end if;
 return u;
end $$;
create function petal_private.consume_rate(p_action text,p_limit integer)
returns boolean language plpgsql security definer set search_path='' as $$
declare n integer; t timestamptz:=clock_timestamp(); u uuid:=petal_private.require_identity();
begin
 insert into petal_private.rate_limits(user_id,action,window_start,attempts) values(u,p_action,t,1)
 on conflict(user_id,action) do update set
 attempts=case when petal_private.rate_limits.window_start<=t-interval '1 hour' then 1 else petal_private.rate_limits.attempts+1 end,
 window_start=case when petal_private.rate_limits.window_start<=t-interval '1 hour' then t else petal_private.rate_limits.window_start end
 returning attempts into n;
 return n<=p_limit;
end $$;
create function public.create_family(p_name text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); f uuid; a uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.memberships where user_id=u) then raise exception 'already_joined'; end if;
 insert into public.families(name) values(trim(p_name)) returning id into f;
 insert into public.family_actors(family_id,role) values(f,'parent') returning id into a;
 insert into public.memberships(family_id,user_id,role,actor_id) values(f,u,'parent',a);
 return jsonb_build_object('family_id',f);
end $$;

create function petal_private.issue_invite(p_family_id uuid,p_kind text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); c text; e timestamptz;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.is_member(p_family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 if not petal_private.consume_rate('issue_invite',5) then return jsonb_build_object('error','rate_limited'); end if;
 perform 1 from public.families where id=p_family_id for update;
 if p_kind='parent' and (select count(*) from public.memberships where family_id=p_family_id and role='parent' and active)>=2 then raise exception 'parent_slots_full'; end if;
 c:=encode(extensions.gen_random_bytes(32),'hex'); e:=clock_timestamp()+interval '15 minutes';
 insert into petal_private.invites(family_id,kind,code_hash,issued_by,expires_at)
 values(p_family_id,p_kind,extensions.digest(c,'sha256'),u,e);
 return jsonb_build_object('code',c,'expires_at',e);
end $$;
create function public.issue_parent_invite(p_family_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select petal_private.issue_invite(p_family_id,'parent'); $$;
create function public.issue_teen_pairing(p_family_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select petal_private.issue_invite(p_family_id,'teen'); $$;

create function petal_private.redeem_invite(p_code text,p_kind text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(p_kind='parent'); i petal_private.invites%rowtype; a uuid;
begin
 -- Invalid attempts return normally so the rate-limit write commits.
 if not petal_private.consume_rate('redeem_invite',10) then return jsonb_build_object('error','rate_limited'); end if;
 if p_code is null or length(p_code)<>64 then return jsonb_build_object('error','invalid_or_expired_code'); end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 select * into i from petal_private.invites where code_hash=extensions.digest(lower(trim(p_code)),'sha256') and kind=p_kind;
 if not found then return jsonb_build_object('error','invalid_or_expired_code'); end if;
 perform 1 from public.families where id=i.family_id for update;
 select * into i from petal_private.invites where id=i.id for update;
 if not found then return jsonb_build_object('error','invalid_or_expired_code'); end if;
 if i.consumed_by=u and not i.revoked and exists(select 1 from public.memberships where user_id=u and family_id=i.family_id and active) then return (select jsonb_build_object('family_id',i.family_id,'role',role,'actor_id',actor_id) from public.memberships where user_id=u); end if;
 if i.revoked or i.consumed_by is not null or i.expires_at<=clock_timestamp() then return jsonb_build_object('error','invalid_or_expired_code'); end if;
 perform 1 from public.families where id=i.family_id for update;
 if exists(select 1 from public.memberships where user_id=u) then return jsonb_build_object('error','already_joined'); end if;
 if p_kind='parent' and (select count(*) from public.memberships where family_id=i.family_id and role='parent' and active)>=2 then return jsonb_build_object('error','parent_slots_full'); end if;
 if not exists(select 1 from public.memberships where family_id=i.family_id and user_id=i.issued_by and role='parent' and active) then return jsonb_build_object('error','invalid_or_expired_code'); end if;
 if i.replacement_actor_id is not null then
 a:=i.replacement_actor_id;
 if not exists(select 1 from public.family_actors where id=a and family_id=i.family_id and role='teen') or exists(select 1 from public.memberships where actor_id=a and active) then return jsonb_build_object('error','replacement_unavailable'); end if;
 else
 insert into public.family_actors(family_id,role) values(i.family_id,i.kind) returning id into a;
 end if;
 insert into public.memberships(family_id,user_id,role,actor_id) values(i.family_id,u,i.kind,a);
 update petal_private.invites set consumed_by=u,consumed_at=clock_timestamp() where id=i.id;
 return jsonb_build_object('family_id',i.family_id,'role',i.kind,'actor_id',a);
end $$;
create function public.accept_parent_invite(p_code text) returns jsonb language sql security definer set search_path='' as $$
 select petal_private.redeem_invite(p_code,'parent'); $$;
create function public.redeem_teen_pairing(p_code text) returns jsonb language sql security definer set search_path='' as $$
 select petal_private.redeem_invite(p_code,'teen'); $$;

create function public.create_occurrence(p_definition_id uuid,p_teen_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); d public.task_definitions%rowtype; r public.rule_versions%rowtype;
 o public.task_occurrences%rowtype; today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 select * into d from public.task_definitions where id=p_definition_id and enabled;
 if not found then raise exception 'not_authorized' using errcode='42501'; end if;
 perform 1 from public.families where id=d.family_id for update;
 if not found or not petal_private.is_member(d.family_id) then raise exception 'not_authorized' using errcode='42501'; end if;
 if not petal_private.is_member(d.family_id,'parent') and not exists(select 1 from public.memberships where user_id=u and actor_id=p_teen_id and active) then raise exception 'not_authorized' using errcode='42501'; end if;
 if not exists(select 1 from public.memberships where family_id=d.family_id and actor_id=p_teen_id and role='teen' and active) then raise exception 'teen_required'; end if;
 -- Serialize catalog/slot access to preserve the first rule snapshot.
 perform 1 from public.task_definitions where id=d.id for update;
 select * into o from public.task_occurrences where definition_id=d.id and teen_id=p_teen_id and local_date=today and slot_key='daily';
 if found then return to_jsonb(o); end if;
 select * into r from public.rule_versions where definition_id=d.id and current_version;
 if not found or r.local_due_time is null then raise exception 'unresolved_schedule'; end if;
 if not (extract(dow from today)::integer=any(r.weekdays)) then raise exception 'not_scheduled_today'; end if;
 insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at)
 values(d.family_id,d.id,p_teen_id,r.id,today,r.points,(today+r.local_due_time) at time zone 'America/Costa_Rica') returning * into o;
 return to_jsonb(o);
end $$;

-- Reserve request identity across actions; canonical JSONB is hashed server-side.
create function petal_private.begin_request(p_request_id uuid,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); h bytea:=extensions.digest(p_payload::text,'sha256'); i petal_private.idempotency%rowtype;
begin
 if p_request_id is null then raise exception 'request_id_required'; end if;
 insert into petal_private.idempotency(user_id,request_id,action,request_hash) values(u,p_request_id,p_action,h) on conflict do nothing;
 select * into i from petal_private.idempotency where user_id=u and request_id=p_request_id for update;
 if i.action<>p_action or i.request_hash<>h then raise exception 'idempotency_payload_conflict' using errcode='22023'; end if;
 return i.result;
end $$;
create function public.submit_occurrence(p_occurrence_id uuid,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); o public.task_occurrences%rowtype; s public.submissions%rowtype; result jsonb;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;
 if not found then raise exception 'teen_owner_required' using errcode='42501'; end if;
 perform 1 from public.families where id=o.family_id for update;
 if not found or not exists(select 1 from public.memberships where user_id=u and actor_id=o.teen_id and active) or not petal_private.is_member(o.family_id,'teen') then raise exception 'teen_owner_required' using errcode='42501'; end if;
 result:=petal_private.begin_request(p_request_id,'submit',jsonb_build_object('occurrence_id',p_occurrence_id));
 if result is not null then return result; end if;
 perform 1 from public.task_occurrences where id=o.id for update;
 select * into s from public.submissions where occurrence_id=o.id;
 if not found then
 if o.due_at is null or clock_timestamp()>o.due_at then raise exception 'late_policy_unresolved'; end if;
 insert into public.submissions(family_id,occurrence_id,teen_id) values(o.family_id,o.id,o.teen_id) returning * into s;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(o.family_id,'submission.pending',s.id,jsonb_build_object('submission_id',s.id));
 end if;
 result:=to_jsonb(s)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=submit_occurrence.result where user_id=u and request_id=p_request_id;
 return result;
end $$;

create function public.approve_submission(p_submission_id uuid,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true); s public.submissions%rowtype; o public.task_occurrences%rowtype;
 d public.decisions%rowtype; result jsonb;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=s.family_id for update;
 if not found or not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 result:=petal_private.begin_request(p_request_id,'approve',jsonb_build_object('submission_id',p_submission_id));
 if result is not null then return result; end if;
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
 result:=jsonb_build_object('request_id',p_request_id,'decision_id',d.id,'submission_id',s.id,'status',d.status,'contribution_points',d.contribution_points,'spendable_xp',0);
 update petal_private.idempotency set result=approve_submission.result where user_id=u and request_id=p_request_id;
 return result;
end $$;

-- Every exposed table denies writes; membership itself is never client controlled.
do $$ declare t text; begin
 foreach t in array array['families','family_actors','memberships','task_definitions','rule_versions','task_occurrences','submissions','decisions','xp_events','day_results','reward_requests'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public, anon, authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 if t='families' then
 execute format('create policy member_read on public.%I for select to authenticated using (petal_private.is_member(id))',t);
 else
 execute format('create policy member_read on public.%I for select to authenticated using (petal_private.is_member(family_id))',t);
 end if;
 end loop;
end $$;
alter table public.device_registrations enable row level security;
revoke all on public.device_registrations from public, anon, authenticated;
grant select on public.device_registrations to authenticated;
create policy own_device_read on public.device_registrations for select to authenticated using(user_id=auth.uid() and petal_private.is_member(family_id));
revoke all on all tables in schema petal_private from public,anon,authenticated;
revoke execute on all functions in schema petal_private from public,anon,authenticated;
-- RLS needs only the boolean predicate. Keep petal_private outside exposed API schemas.
grant usage on schema petal_private to authenticated;
grant execute on function petal_private.is_member(uuid,text) to authenticated;
revoke execute on function public.create_family(text),public.issue_parent_invite(uuid),public.issue_teen_pairing(uuid),public.accept_parent_invite(text),public.redeem_teen_pairing(text),public.create_occurrence(uuid,uuid),public.submit_occurrence(uuid,uuid),public.approve_submission(uuid,uuid) from public,anon;
grant execute on function public.create_family(text),public.issue_parent_invite(uuid),public.issue_teen_pairing(uuid),public.accept_parent_invite(text),public.redeem_teen_pairing(text),public.create_occurrence(uuid,uuid),public.submit_occurrence(uuid,uuid),public.approve_submission(uuid,uuid) to authenticated;

-- SOURCE: migrations/202610200002_phase6_recovery_and_api.sql

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

-- SOURCE: migrations/202610200003_phase6_reconciliation.sql

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

-- SOURCE: migrations/202610200004_phase6_catalogue.sql

alter table public.task_definitions add column catalogue_key text;
create unique index unique_family_catalogue_key on public.task_definitions(family_id,catalogue_key);
-- Exact committed Phase3 duties only; NULL deadlines remain unresolved and blocked.
create function petal_private.seed_family_catalogue(p_family_id uuid) returns void
language plpgsql security definer set search_path='' as $seed$
declare item jsonb; d uuid;
begin
 for item in select value from jsonb_array_elements($catalogue$[{"key":"duty-wd-001","title":"⚠️ 1st Attitude Check","points":15,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-001","title":"⚠️ 1st Attitude Check","points":15,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-002","title":"🎒 BagPack + Lunchbag + Shower + Room @4PM","points":11,"due_time":"16:00","weekdays":[1,2,3,4,5]},{"key":"duty-we-002","title":"➡️ Room + Laundry @11AM","points":12,"due_time":"11:00","weekdays":[6,0]},{"key":"duty-wd-003","title":"📚 Homework/Study @5:30PM","points":12,"due_time":"17:30","weekdays":[1,2,3,4,5]},{"key":"duty-we-003","title":"🚿 Shower +No Mess @1PM","points":11,"due_time":"13:00","weekdays":[6,0]},{"key":"duty-wd-004","title":"⚠️ 2nd Attitude Check","points":15,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-004","title":"📚 Check HS + Other Pendings / Study @2PM","points":11,"due_time":"14:00","weekdays":[6,0]},{"key":"duty-wd-005","title":"➡️ Next Day Prepare @6PM","points":11,"due_time":"18:00","weekdays":[1,2,3,4,5]},{"key":"duty-we-005","title":"⚠️ 2nd Attitude Check @5PM","points":15,"due_time":"17:00","weekdays":[6,0]},{"key":"duty-wd-006","title":"✨ House Help","points":11,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-006","title":"✨ House Help","points":11,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-007","title":"📖 Read a new book -or- Bible","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-007","title":"📖 Read a new book -or- Bible","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-008","title":"💧 Drink 3 glasses of water (House)","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-008","title":"💧 Drink 3 glasses of water (House)","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-009","title":"📝 Research & write by hand","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-009","title":"📝 Research & write by hand","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-010","title":"🎨 Draw / Create Dance","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-010","title":"🎨 Draw / Create Dance","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-011","title":"🧹 Clean up Closet / Shoes","points":2,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-011","title":"🧹 Clean up Closet / Shoes","points":2,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-012","title":"🎁 Declutter/give away items","points":2,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-012","title":"🎁 Declutter/give away items","points":2,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-013","title":"📚 Hikari Shop","points":2,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-013","title":"📚 Hikari Shop","points":2,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-014","title":"🙂 Final Attitude Check","points":15,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-014","title":"🙂 Final Attitude Check","points":15,"due_time":null,"weekdays":[6,0]}]$catalogue$::jsonb) loop
 insert into public.task_definitions(family_id,title,enabled,catalogue_key) values(p_family_id,item->>'title',true,item->>'key') returning id into d;
 insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
 values(p_family_id,d,1,(item->>'points')::integer,(item->>'due_time')::time,array(select value::integer from jsonb_array_elements_text(item->'weekdays')),true,'Phase3 App-Rule-Catalogue.draft.json; Owner-Decisions P3-003/P3-006');
 end loop;
end $seed$;
revoke execute on function petal_private.seed_family_catalogue(uuid) from public,anon,authenticated;
create or replace function petal_private.create_family(p_name text) returns jsonb
language plpgsql security definer set search_path='' as $create$
declare u uuid:=petal_private.require_identity(true); f uuid; a uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.memberships where user_id=u) then raise exception 'already_joined'; end if;
 insert into public.families(name) values(trim(p_name)) returning id into f;
 insert into public.family_actors(family_id,role) values(f,'parent') returning id into a;
 insert into public.memberships(family_id,user_id,role,actor_id) values(f,u,'parent',a);
 perform petal_private.seed_family_catalogue(f);
 return jsonb_build_object('family_id',f);
end $create$;

-- SOURCE: migrations/202610200005_phase6_initial_schedule.sql

-- The initial catalogue starts when it is provisioned; an actor starts at enrollment.
-- These are server installation boundaries, not approval of future rule-edit timing.
alter table public.task_definitions add column provisioned_at timestamptz not null default clock_timestamp();
alter table public.family_actors add column enrolled_at timestamptz not null default clock_timestamp();

create function petal_private.protect_initial_rule() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 raise exception 'rule_change_policy_unresolved';
end $$;
revoke execute on function petal_private.protect_initial_rule() from public,anon,authenticated;
create trigger immutable_initial_rule before update or delete on public.rule_versions
for each row execute function petal_private.protect_initial_rule();

create or replace function petal_private.reconcile_occurrences(p_family_id uuid,p_teen_id uuid,p_from_date date,p_to_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=petal_private.require_identity();
 today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
 actor_started date;
 r record;
 slot_date date;
 rows jsonb;
 blocked jsonb;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not found or not petal_private.can_read_teen(p_family_id,p_teen_id) then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 select (a.enrolled_at at time zone 'America/Costa_Rica')::date into actor_started
 from public.family_actors a where a.family_id=p_family_id and a.id=p_teen_id and a.role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 if p_from_date is null or p_to_date is null or p_from_date>p_to_date
 or p_to_date>today or p_to_date-p_from_date>30 then
  raise exception 'invalid_reconciliation_range';
 end if;

 -- Only the one immutable initial version is knowable before rule-edit policy exists.
 -- Missing deadlines and multi-version definitions stay blocked instead of guessing.
 for r in
  select d.id,d.family_id,(d.provisioned_at at time zone 'America/Costa_Rica')::date as definition_started,
   v.id as rule_id,v.points,v.local_due_time,v.weekdays
  from public.task_definitions d join public.rule_versions v on v.definition_id=d.id and v.family_id=d.family_id
  where d.family_id=p_family_id and d.enabled and v.version=1 and v.current_version
   and v.local_due_time is not null
   and (select count(*) from public.rule_versions x where x.definition_id=d.id)=1
 loop
  slot_date:=greatest(p_from_date,actor_started,r.definition_started);
  while slot_date<=p_to_date loop
   if extract(dow from slot_date)::integer=any(r.weekdays) then
    insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at)
    values(p_family_id,r.id,p_teen_id,r.rule_id,slot_date,r.points,
     (slot_date+r.local_due_time) at time zone 'America/Costa_Rica')
    on conflict(definition_id,teen_id,local_date,slot_key) do nothing;
   end if;
   slot_date:=slot_date+1;
  end loop;
 end loop;

 select coalesce(jsonb_agg(jsonb_build_object('definition_id',d.id,'reason',
  case when not exists(select 1 from public.rule_versions v where v.definition_id=d.id and v.current_version and v.local_due_time is not null)
   then 'unresolved_schedule' else 'rule_change_policy_unresolved' end)),'[]'::jsonb)
 into blocked from public.task_definitions d where d.family_id=p_family_id and d.enabled
 and not exists(select 1 from public.rule_versions v where v.definition_id=d.id and v.version=1 and v.current_version
  and v.local_due_time is not null and (select count(*) from public.rule_versions x where x.definition_id=d.id)=1);

 select coalesce(jsonb_agg(to_jsonb(o) order by o.local_date,o.id),'[]'::jsonb) into rows
 from public.task_occurrences o where o.family_id=p_family_id and o.teen_id=p_teen_id
 and o.local_date between p_from_date and p_to_date;
 return jsonb_build_object('server_local_date',today,'occurrences',rows,'blocked_definitions',blocked,
  'historical_generation_status','initial_version_only','new_rule_activation_status','blocked_rule_effective_date_policy');
end $$;

-- No previously held request can publish a missing historical version via today's RPC.
-- Only private provisioning/migration can add definitions/versions; no client edit grant exists.

-- SOURCE: migrations/202610200006_phase6_api_contract.sql

create function public.get_contract_version() returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('api_contract_version',1,'family_timezone','America/Costa_Rica','week_start','Sunday');
$$;
revoke execute on function public.get_contract_version() from public,anon;
grant execute on function public.get_contract_version() to authenticated;
notify pgrst, 'reload schema';

-- SOURCE: migrations/202610210001_phase6_receipt_fix.sql
-- Receipt variable correction found by executable local PostgreSQL verification.

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

-- SOURCE: migrations/202610210004_phase7_alert_expiry.sql
-- Forward compatibility: claim includes the actual check-in day for TTL/receiver expiry.

create or replace function petal_private.claim_high_pain_push(p_limit integer default 20) returns jsonb
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
notify pgrst, 'reload schema';

-- SOURCE: migrations/202610210005_phase8_teen.sql

-- New contracts are additive: Phase6/7 RPC names and their return shapes remain intact.
alter table public.task_occurrences add column title_snapshot text;
update public.task_occurrences o set title_snapshot=d.title from public.task_definitions d where d.id=o.definition_id;
alter table public.task_occurrences alter column title_snapshot set not null;
create function petal_private.snapshot_occurrence_title() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select title into new.title_snapshot from public.task_definitions where id=new.definition_id and family_id=new.family_id;
 return new;
end $$;
create trigger occurrence_title_before_insert before insert on public.task_occurrences for each row execute function petal_private.snapshot_occurrence_title();

create table petal_private.phase8_catalogue (
 singleton boolean primary key default true check(singleton), catalogue jsonb not null, tracker_rules jsonb not null,
 effective_from date -- Explicit deployment choice required; never guessed from a client clock.
);
create table public.daily_accounting (
 family_id uuid not null,teen_id uuid not null,local_date date not null,
 revision integer not null check(revision>0), actual_score integer not null check(actual_score between 0 and 100),
 virtual_remaining integer not null default 0 check(virtual_remaining between 0 and 100),
 protected_score integer not null check(protected_score between actual_score and 100),
 converted_points integer not null default 0 check(converted_points between 0 and 100),
 conversion_history boolean not null default false,
 earned_xp integer not null check(earned_xp between 0 and 200),
 rule_snapshot jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(family_id,teen_id,local_date,revision),
 foreign key(family_id,teen_id,local_date) references public.day_results(family_id,teen_id,local_date),
 check(earned_xp=case when actual_score<85 then 0 when actual_score=100 and not conversion_history then 200 else actual_score end)
);
create table public.wallet_events (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,
 source_key text not null unique,local_date date,earned_xp_delta integer not null default 0,coin_delta integer not null,
 created_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.deduction_entries (
 id uuid primary key, family_id uuid not null,teen_id uuid not null,local_date date not null,
 deduction_key text not null,points integer not null check(points>0),parent_user_id uuid not null references auth.users(id),
 rule_version text not null default 'phase3-deductions-v1',created_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id),
 check((deduction_key,points) in (('dirty-lunchbag',5),('torn-clothes',20),('instructions',6),('shower-items',4),('messy-items',5)))
);
alter table public.reward_requests add column catalogue_key text;
alter table public.reward_requests add column debit_coins integer not null default 0 check(debit_coins>=0);
alter table public.reward_requests add column updated_at timestamptz not null default clock_timestamp();

-- Explicit declarations keep the dashboard's static RLS check informed.
alter table public.daily_accounting enable row level security;
alter table public.wallet_events enable row level security;
alter table public.deduction_entries enable row level security;
do $$ declare t text; begin
 foreach t in array array['daily_accounting','wallet_events','deduction_entries'] loop
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy subject_read on public.%I for select to authenticated using(petal_private.can_read_teen(family_id,teen_id))',t);
 end loop;
end $$;
alter table petal_private.phase8_catalogue enable row level security;
revoke all on petal_private.phase8_catalogue from public,anon,authenticated;

create function petal_private.performance_band(p_score integer) returns jsonb language sql immutable set search_path='' as $$
 select case when p_score=100 then jsonb_build_object('icon','🌟','label','Exceptional Day')
 when p_score>=96 then jsonb_build_object('icon','💎','label','Amazing Day')
 when p_score>=91 then jsonb_build_object('icon','🏆','label','Excellent Day')
 when p_score=90 then jsonb_build_object('icon','✅','label','Passed Day — Good Day')
 when p_score>=85 then jsonb_build_object('icon','⚠️','label','Almost Passed')
 when p_score>=75 then jsonb_build_object('icon','🟠','label','Needs Improvement')
 when p_score>=60 then jsonb_build_object('icon','🔴','label','Poor Day')
 else jsonb_build_object('icon','⛔','label','Bad Day') end;
$$;

create function petal_private.materialize_teen_tasks() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; today date:=(clock_timestamp() at time zone 'America/Costa_Rica')::date;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at,title_snapshot)
 select d.family_id,d.id,m.actor_id,r.id,today,r.points,
 case when r.local_due_time is not null then (today+r.local_due_time) at time zone 'America/Costa_Rica' end,d.title
 from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
 where d.family_id=m.family_id and d.enabled and extract(dow from today)::integer=any(r.weekdays)
 on conflict(definition_id,teen_id,local_date,slot_key) do nothing;
 return jsonb_build_object('server_local_date',today,'status','ready','unknown_due_policy','submission_blocked_until_schedule_confirmed');
end $$;

create function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; c jsonb; tr jsonb; tasks jsonb; days jsonb;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then raise exception 'invalid_history_range'; end if;
 select catalogue,tracker_rules into c,tr from petal_private.phase8_catalogue where singleton;
 select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('catalogue_key',d.catalogue_key,'status',coalesce(s.status,'open'),
 'submission_id',s.id,'submitted_at',s.submitted_at,'decision_id',dc.id,'reviewed_at',dc.decided_at,
 'submission_ready',o.due_at is not null,'readiness_reason',case when o.due_at is null then 'unresolved_schedule' end) order by o.local_date,o.due_at nulls last,o.id),'[]') into tasks
 from public.task_occurrences o join public.task_definitions d on d.id=o.definition_id
 left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id
 where o.family_id=m.family_id and o.teen_id=m.actor_id and o.local_date between p_from and p_to;
 with dates as (
 select local_date from public.task_occurrences where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 union select local_date from public.day_results where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 ), summaries as (
 select dt.local_date,dr.first_published_at,dr.effective_seal_at,a.revision,a.actual_score,a.virtual_remaining,a.protected_score,a.converted_points,a.conversion_history,a.earned_xp,a.rule_snapshot,
 (select coalesce(sum(points),0) from public.deduction_entries de where de.family_id=m.family_id and de.teen_id=m.actor_id and de.local_date=dt.local_date) deduction_points
 from dates dt left join public.day_results dr on dr.family_id=m.family_id and dr.teen_id=m.actor_id and dr.local_date=dt.local_date
 left join lateral(select * from public.daily_accounting da where da.family_id=m.family_id and da.teen_id=m.actor_id and da.local_date=dt.local_date order by revision desc limit 1) a on true
 ) select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('status',case when first_published_at is null then 'pending' when clock_timestamp()>=effective_seal_at then 'sealed' else 'finalized' end,
 'coins_earned',earned_xp,'rule_version_id',rule_snapshot->>'version','performance_icon',case when revision is not null then petal_private.performance_band(protected_score)->>'icon' end,
 'performance_label',case when revision is not null then petal_private.performance_band(protected_score)->>'label' end,
 'week_start',local_date-extract(dow from local_date)::integer) order by local_date),'[]') into days from summaries s;
 return jsonb_build_object('api_contract_version',2,'server_now',clock_timestamp(),'server_local_date',(clock_timestamp() at time zone 'America/Costa_Rica')::date,
 'family_id',m.family_id,'teen_id',m.actor_id,'tasks',tasks,'day_summaries',days,
 'balance',(select jsonb_build_object('earned_xp',coalesce(sum(earned_xp_delta),0),'available_coins',coalesce(sum(coin_delta),0),'coin_rank',case when coalesce(sum(coin_delta),0)>=10000 then 'Diamond' when coalesce(sum(coin_delta),0)>=5000 then 'Emerald' when coalesce(sum(coin_delta),0)>=2500 then 'Sapphire' when coalesce(sum(coin_delta),0)>=1000 then 'Ruby' when coalesce(sum(coin_delta),0)>=500 then 'Gold' when coalesce(sum(coin_delta),0)>=100 then 'Silver' else 'Base' end) from public.wallet_events where family_id=m.family_id and teen_id=m.actor_id),
 'deductions',(select coalesce(jsonb_agg(to_jsonb(de) order by created_at),'[]') from public.deduction_entries de where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to),
 'reward_catalogue',coalesce(c->'rewards','[]'),'achievements',coalesce(c->'achievements','[]'),'tracker_rules',tr,
 'reward_requests',(select coalesce(jsonb_agg(to_jsonb(rr) order by created_at desc),'[]') from public.reward_requests rr where family_id=m.family_id and teen_id=m.actor_id),
 'readiness',jsonb_build_object('unknown_due_times','per_task_block','phase8_title_activation','effective_date_required','partial_day_finalization','policy_required',
 'excuses_and_conversion','allocation_and_bonus_policy_required','appeals','revision_and_evidence_policy_required','achievements','qualification_policy_required',
 'negative_corrections','debt_policy_required','cash_and_privileges','parent_manual_decision_required','historical_generation','effective_date_policy_required'));
end $$;

create function petal_private.request_reward(p_reward_key text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;item jsonb;answer jsonb;r public.reward_requests%rowtype;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'request_reward',jsonb_build_object('reward_key',p_reward_key));
 if answer is not null then return answer; end if;
 select value into item from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'rewards') where value->>'id'=p_reward_key;
 if item is null or item->>'sourceStatus'<>'Available' then raise exception 'reward_unavailable'; end if;
 insert into public.reward_requests(family_id,teen_id,title_snapshot,price_snapshot,catalogue_key)
 values(m.family_id,m.actor_id,item->>'title',(item->>'coinCost')::integer,p_reward_key) returning * into r;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'reward.requested',r.id,jsonb_build_object('reward_request_id',r.id));
 return answer;
end $$;
create function petal_private.cancel_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;r public.reward_requests%rowtype;answer jsonb;
begin
 select * into m from public.memberships where user_id=u and active;
 if not found then raise exception 'not_authorized' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id) then raise exception 'not_authorized' using errcode='42501'; end if;
 select * into r from public.reward_requests where id=p_reward_request_id and family_id=m.family_id and (m.role='parent' or teen_id=m.actor_id) for update;
 if not found then raise exception 'not_authorized' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'cancel_reward',jsonb_build_object('reward_request_id',p_reward_request_id));
 if answer is not null then return answer; end if;
 if r.status='fulfilled' or (r.status='approved' and m.role<>'parent') then raise exception 'parent_cancellation_required'; end if;
 if r.status<>'cancelled' then
 if r.status='approved' then
 insert into public.wallet_events(family_id,teen_id,source_key,coin_delta) values(r.family_id,r.teen_id,'reward-refund:'||r.id,r.debit_coins) on conflict(source_key) do nothing;
 end if;
 update public.reward_requests set status='cancelled',updated_at=clock_timestamp() where id=r.id returning * into r;
 end if;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
create function petal_private.approve_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);r public.reward_requests%rowtype;answer jsonb;balance bigint;
begin
 select * into r from public.reward_requests where id=p_reward_request_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=r.family_id for update;
 if not petal_private.is_member(r.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'approve_reward',jsonb_build_object('reward_request_id',p_reward_request_id));
 if answer is not null then return answer; end if;
 select * into r from public.reward_requests where id=p_reward_request_id for update;
 if r.status='requested' then
 select coalesce(sum(coin_delta),0) into balance from public.wallet_events where family_id=r.family_id and teen_id=r.teen_id;
 if balance<r.price_snapshot then raise exception 'insufficient_coins'; end if;
 insert into public.wallet_events(family_id,teen_id,source_key,coin_delta) values(r.family_id,r.teen_id,'reward-debit:'||r.id,-r.price_snapshot);
 update public.reward_requests set status='approved',debit_coins=price_snapshot,updated_at=clock_timestamp() where id=r.id returning * into r;
 elsif r.status<>'approved' then raise exception 'invalid_reward_transition'; end if;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

-- Complete-day-only settlement avoids selecting an unresolved partial/pending policy.
create function petal_private.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;answer jsonb;actual integer;ded integer;earned integer;n integer;published timestamptz;seal timestamptz;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';
 if f is null then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'finalize_complete_day',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date));
 if answer is not null then return answer; end if;
 if exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date) then raise exception 'published_day_correction_unresolved'; end if;
 if p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day'; end if;
 select count(*),coalesce(sum(o.points_snapshot),0) into n,actual from public.task_occurrences o join public.submissions s on s.occurrence_id=o.id join public.decisions d on d.submission_id=s.id
 where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date;
 if n<>14 or actual<>100 then raise exception 'partial_day_finalization_policy_required'; end if;
 select coalesce(sum(points),0) into ded from public.deduction_entries where family_id=f and teen_id=p_teen_id and local_date=p_local_date;
 actual:=greatest(0,actual-ded);earned:=case when actual<85 then 0 when actual=100 then 200 else actual end;
 published:=clock_timestamp();seal:=((p_local_date+2)::timestamp at time zone 'America/Costa_Rica');
 if published>=seal then seal:=((((published at time zone 'America/Costa_Rica')::date+2)::timestamp) at time zone 'America/Costa_Rica'); end if;
 insert into public.day_results values(f,p_teen_id,p_local_date,published,seal);
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,rule_snapshot)
 values(f,p_teen_id,p_local_date,1,actual,actual,earned,jsonb_build_object('version','phase3-owner-confirmed-v1','deductions',ded));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(f,p_teen_id,'day:'||p_teen_id||':'||p_local_date||':1',p_local_date,earned,earned);
 answer:=jsonb_build_object('status','finalized','earned_xp',earned,'coins_earned',earned,'actual_score',actual,'effective_seal_at',seal);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

-- Public wrappers follow the Phase6 invoker/private-definer boundary.
do $wrappers$ declare signature text;begin
 foreach signature in array array['materialize_teen_tasks()','get_teen_dashboard(date,date)','request_reward(text,uuid)','cancel_reward_request(uuid,uuid)','approve_reward_request(uuid,uuid)','finalize_complete_day(uuid,date,uuid)'] loop
 execute 'revoke execute on function petal_private.'||signature||' from public,anon';
 execute 'grant execute on function petal_private.'||signature||' to authenticated';
 end loop;
end $wrappers$;
create function public.materialize_teen_tasks() returns jsonb language sql security invoker set search_path='' as $$ select petal_private.materialize_teen_tasks(); $$;
create function public.get_teen_dashboard(p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.get_teen_dashboard(p_from,p_to); $$;
create function public.request_reward(p_reward_key text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.request_reward(p_reward_key,p_request_id); $$;
create function public.cancel_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.cancel_reward_request(p_reward_request_id,p_request_id); $$;
create function public.approve_reward_request(p_reward_request_id uuid,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.approve_reward_request(p_reward_request_id,p_request_id); $$;
create function public.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select petal_private.finalize_complete_day(p_teen_id,p_local_date,p_request_id); $$;
do $$ declare signature text;begin
 foreach signature in array array['materialize_teen_tasks()','get_teen_dashboard(date,date)','request_reward(text,uuid)','cancel_reward_request(uuid,uuid)','approve_reward_request(uuid,uuid)','finalize_complete_day(uuid,date,uuid)'] loop
 execute 'revoke execute on function public.'||signature||' from public,anon';execute 'grant execute on function public.'||signature||' to authenticated';
 end loop;
end $$;
revoke execute on function petal_private.performance_band(integer),petal_private.snapshot_occurrence_title() from public,anon,authenticated;
insert into petal_private.phase8_catalogue(singleton,catalogue,tracker_rules) values(true,$catalogue${"status":"draft catalogue; sourced values plus explicit owner override; identifiers assigned once and retained","date":"2026-10-21","timezone":"America/Costa_Rica","weekStart":"Sunday 00:00","sourceSnapshot":"Tracker-Rule-Extract.json","duties":[{"id":"duty-wd-001","title":"⚠️ 1st Attitude Check","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":2,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-001","title":"⚠️ 1st Attitude Check","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":2,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-002","title":"🎒 Lunchbag + Shower + Room @4PM","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":3,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":"16:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"🎒 BagPack + Lunchbag + Shower + Room @4PM"},{"id":"duty-we-002","title":"➡️ Room + Laundry @11AM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":3,"sourceXp":12,"xp":12,"decisionRef":null,"dueTime":"11:00","approvalPolicy":"either-parent; per-duty review details pending","sourceTitle":"➡️ Room + Laundry @11PM","dueTimeDecisionRef":"P3-006"},{"id":"duty-wd-003","title":"📚 Homework/Study + HighSchool Pendings + BagPack preparation + review @5:30PM","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":4,"sourceXp":12,"xp":12,"decisionRef":"P8-001","dueTime":"17:30","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"📚 Homework/Study @5:30PM"},{"id":"duty-we-003","title":"🚿 Shower +No Mess @1PM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":4,"sourceXp":11,"xp":11,"decisionRef":null,"dueTime":"13:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label"},{"id":"duty-wd-004","title":"⚠️ 2nd Attitude Check + mouth piece check","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":5,"sourceXp":15,"xp":15,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"⚠️ 2nd Attitude Check"},{"id":"duty-we-004","title":"📚 Check HS + Other Pendings / Study @2PM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":5,"sourceXp":11,"xp":11,"decisionRef":null,"dueTime":"14:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label"},{"id":"duty-wd-005","title":"➡️ Next Day Prepare + Room clean up @6PM","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":6,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":"18:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"➡️ Next Day Prepare @6PM"},{"id":"duty-we-005","title":"⚠️ 2nd Attitude Check + mouth piece check @5PM","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":6,"sourceXp":15,"xp":15,"decisionRef":"P8-001","dueTime":"17:00","approvalPolicy":"either-parent; per-duty review details pending","dueTimeBasis":"explicit time in owner-supplied source duty label","previousTitle":"⚠️ 2nd Attitude Check @5PM"},{"id":"duty-wd-006","title":"✨ House Help + meditation/reading","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":7,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"✨ House Help"},{"id":"duty-we-006","title":"✨ House Help + meditation/reading","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":7,"sourceXp":11,"xp":11,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"✨ House Help"},{"id":"duty-wd-007","title":"🌱 Water plants","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":8,"sourceXp":1,"xp":1,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"📖 Read a new book -or- Bible"},{"id":"duty-we-007","title":"🌱 Water plants","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":8,"sourceXp":1,"xp":1,"decisionRef":"P8-001","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending","previousTitle":"📖 Read a new book -or- Bible"},{"id":"duty-wd-008","title":"💧 Drink 3 glasses of water (House)","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":9,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-008","title":"💧 Drink 3 glasses of water (House)","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":9,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-009","title":"📝 Research & write by hand","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":10,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-009","title":"📝 Research & write by hand","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":10,"sourceXp":2,"xp":1,"decisionRef":"P3-003","dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-010","title":"🎨 Draw / Create Dance","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":11,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-010","title":"🎨 Draw / Create Dance","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":11,"sourceXp":1,"xp":1,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-011","title":"🧹 Clean up Closet / Shoes","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":12,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-011","title":"🧹 Clean up Closet / Shoes","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":12,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-012","title":"🎁 Declutter/give away items","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":13,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-012","title":"🎁 Declutter/give away items","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":13,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-013","title":"📚 Hikari Shop","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":14,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-013","title":"📚 Hikari Shop","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":14,"sourceXp":2,"xp":2,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-wd-014","title":"🙂 Final Attitude Check","variant":"weekday","days":["Monday","Tuesday","Wednesday","Thursday","Friday"],"sourceSheet":"Task Lists","sourceRow":15,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"},{"id":"duty-we-014","title":"🙂 Final Attitude Check","variant":"weekend","days":["Saturday","Sunday"],"sourceSheet":"Task Lists","sourceRow":15,"sourceXp":15,"xp":15,"decisionRef":null,"dueTime":null,"approvalPolicy":"either-parent; per-duty review details pending"}],"rewards":[{"id":"reward-001","sourceId":"1","title":"🎬 Choose a movie/TV Show for family movie night","coinCost":450,"sourceStatus":"Available","type":"In-House Event","tier":"1 ~ $10"},{"id":"reward-002","sourceId":"2","title":"🃏 Pokémon Booster Pack (~$8)","coinCost":600,"sourceStatus":"Available","type":"Purchase -Game","tier":"1 ~ $10"},{"id":"reward-003","sourceId":"3","title":"💍 Small accessory: earrings, bracelet, hair clips, phone charm, etc.","coinCost":650,"sourceStatus":"Available","type":"Purchase -Accessory","tier":"1 ~ $10"},{"id":"reward-004","sourceId":"4","title":"🧋 Boba, smoothie, café or dessert outing with parent","coinCost":675,"sourceStatus":"Available","type":"Outdoors Food","tier":"1 ~ $10"},{"id":"reward-005","sourceId":"5","title":"🧴 Small self-care/skincare item ($10 max)","coinCost":800,"sourceStatus":"Available","type":"Purchase -Beauty","tier":"1 ~ $10"},{"id":"reward-006","sourceId":"6","title":"🍕 Pizza/takeout family night","coinCost":1200,"sourceStatus":"Available","type":"In-House Event Food","tier":"2 ~ $20"},{"id":"reward-007","sourceId":"7","title":"📚 Book, novel, comic or manga under $20","coinCost":1200,"sourceStatus":"Available","type":"Purchase -Book","tier":"2 ~ $20"},{"id":"reward-008","sourceId":"8","title":"☕ Special parent-daughter outing","coinCost":1200,"sourceStatus":"Available","type":"Outdoors Food","tier":"2 ~ $20"},{"id":"reward-009","sourceId":"9","title":"🎲 Afternoon at the Arcade","coinCost":1350,"sourceStatus":"Available","type":"In-House Event","tier":"2 ~ $20"},{"id":"reward-010","sourceId":"10","title":"💄 Skincare/beauty mini-haul ($20 max)","coinCost":1400,"sourceStatus":"Available","type":"Purchase -Beauty","tier":"2 ~ $20"},{"id":"reward-011","sourceId":"11","title":"📖 New book or manga ($30 max)","coinCost":1850,"sourceStatus":"Available","type":"Purchase -Book","tier":"3 ~ $30"},{"id":"reward-012","sourceId":"12","title":"👯 Friend comes over + favorite takeout/snacks","coinCost":1900,"sourceStatus":"Available","type":"In-House Event Food","tier":"3 ~ $30"},{"id":"reward-013","sourceId":"13","title":"🎥 Go to the movies","coinCost":1950,"sourceStatus":"Available","type":"Outdoors Event","tier":"3 ~ $30"},{"id":"reward-014","sourceId":"14","title":"👕 Branded T-shirt / band / K-pop / anime shirt or accessory","coinCost":2000,"sourceStatus":"Available","type":"Purchase -Clothing","tier":"3 ~ $30"},{"id":"reward-015","sourceId":"15","title":"🧸 Pokémon/anime/K-pop collectible or plush ($30 max)","coinCost":2050,"sourceStatus":"Available","type":"Purchase -Collectible","tier":"3 ~ $30"},{"id":"reward-016","sourceId":"16","title":"👯 Bring a friend to movies / café / eat out","coinCost":2500,"sourceStatus":"Available","type":"Outdoors Event","tier":"4 ~ $40"},{"id":"reward-017","sourceId":"17","title":"🎲 New family board game ($40 max)","coinCost":2500,"sourceStatus":"Available","type":"Purchase -Game","tier":"4 ~ $40"},{"id":"reward-018","sourceId":"18","title":"🏃 Sports/running/fitness gear upgrade","coinCost":2550,"sourceStatus":"Available","type":"Purchase -Sports","tier":"4 ~ $40"},{"id":"reward-019","sourceId":"19","title":"🪞 Room décor / vanity / aesthetic bedroom upgrade ($40)","coinCost":2650,"sourceStatus":"Available","type":"Purchase -Room Decor","tier":"4 ~ $40"},{"id":"reward-020","sourceId":"20","title":"🎒 School-style upgrade: backpack, tote, bottle, pencil case, etc.","coinCost":5000,"sourceStatus":"Available","type":"Purchase -Tools","tier":"5 ~ $75"},{"id":"reward-021","sourceId":"21","title":"👟 Shoes/sneakers ($70)","coinCost":5500,"sourceStatus":"Available","type":"Purchase -Clothing","tier":"5 ~ $75"},{"id":"reward-022","sourceId":"22","title":"🎓 Enroll in a short course/workshop she chooses","coinCost":6000,"sourceStatus":"Available","type":"Purchase -Class","tier":"5 ~ $75"},{"id":"reward-023","sourceId":"23","title":"🃏 Pokémon ETB","coinCost":6000,"sourceStatus":"Available","type":"Purchase -Game","tier":"5 ~ $75"},{"id":"reward-024","sourceId":"24","title":"💄 Premium skincare/beauty/fashion item ($60–75 max)","coinCost":6000,"sourceStatus":"Available","type":"Purchase -Beauty","tier":"5 ~ $75"},{"id":"reward-025","sourceId":"25","title":"🎒 Premium backpack + full school/style kit","coinCost":10000,"sourceStatus":"Available","type":"Purchase -Tools","tier":"Premium ~ $100"},{"id":"reward-026","sourceId":"26","title":"🎫 Contribution toward a concert/show/event she really wants","coinCost":10000,"sourceStatus":"Available","type":"Purchase -Event","tier":"Premium ~ $100"},{"id":"reward-027","sourceId":"27","title":"🚗 Family day trip / nearby destination","coinCost":11000,"sourceStatus":"Available","type":"Outdoors Event","tier":"Premium ~ $100"},{"id":"reward-028","sourceId":"28","title":"🛍️ $100 shopping/gift-card budget for K-pop, fashion, beauty, etc.","coinCost":12500,"sourceStatus":"Available","type":"Purchase","tier":"Premium ~ $100"},{"id":"reward-029","sourceId":"29","title":"🎢 Theme park / major special-event day","coinCost":16000,"sourceStatus":"Available","type":"Outdoors Event","tier":"Platinum ~ $150+"}],"achievements":[{"id":"achievement-001","title":"Aced Test","xp":50,"sourceCondition":"Any test scored 100","preciseAwardCondition":"pending specification"},{"id":"achievement-002","title":"Student of Excellence I","xp":250,"sourceCondition":"All trimester grades > 97","preciseAwardCondition":"pending specification"},{"id":"achievement-003","title":"Student of Excellence II","xp":300,"sourceCondition":"Best student of the Class","preciseAwardCondition":"pending specification"},{"id":"achievement-004","title":"Student of Excellence III","xp":400,"sourceCondition":"Best student of the Gen","preciseAwardCondition":"pending specification"},{"id":"achievement-005","title":"Girl Machine","xp":1000,"sourceCondition":"1 month good behavior consistency","preciseAwardCondition":"pending specification"},{"id":"achievement-006","title":"Wise Princess","xp":2000,"sourceCondition":"2 month FULL required consistency","preciseAwardCondition":"pending specification"}],"scoring":{"scoreFloor":0,"earningThreshold":85,"passThreshold":90,"exceptionalScore":100,"exceptionalEarnedXp":200,"dailyScoreUpperCap":"none newly introduced; both standard task sets total 100","weekdayTaskTotal":100,"weekendTaskTotal":100,"decisionRefs":["P3-003","P3-004","P3-005"]},"reviewTiming":{"onTimeSubmissionDelayedReview":"retain original-day eligibility","decisionRef":"P3-007"},"coinConversion":{"mode":"automatic on finalized earned XP","coinsPerXp":1,"spendingErasesEarnedHistory":false,"decisionRef":"P3-008","finalizationSchedule":"explicit parent action; reminder timing separate","correctionDebtPolicy":"pending"},"finalization":{"mode":"explicit parent action","remindersRequired":true,"finalReminderExampleLocalTime":"21:00","exactReminderSchedule":"07:15,15:20,17:00,19:00,21:00 America/Costa_Rica; checkpoint context deferred","reminderDoesNotFinalize":true,"decisionRef":"P3-009","reminderTimesLocal":["07:15","15:20","17:00","19:00","21:00"],"reminderContext":"owner supplies labels,text,task context during implementation; do not treat all slots as finalization-only prompts","reminderDecisionRefs":["P3-015","P3-016"]},"excuses":{"protectDailyResult":true,"protectionUsesVirtualPoints":true,"virtualPointsEarnCoins":false,"parentBonusOfferAction":true,"exactThresholdAndBonusMath":"actual-only score must reach 85; days earning points through virtual conversion have no perfect-day bonus, max earned 100","decisionRefs":["P3-010","P3-011","P3-013","P3-014"],"actualOnlyEarningThreshold":85,"perfectBonusOnConversionDay":false,"maxEarnedXpOnConversionDay":100},"rewardLifecycle":{"requestChargesCoins":false,"approveBy":"either authorized parent","charge":"saved price once on approval","cancelBeforeApproval":"free","parentCancelBeforeFulfillment":"refund original debit once","afterFulfillment":"exception policy pending","decisionRef":"P3-012"},"ratings":{"coinRankBasis":"available coins","growthRatingPeriod":"daily","permanentLifetimeXpLevelApproved":false,"optionalMonthToDateRating":"tentative idea, not approved","monthlyFormula":null,"decisionRefs":["P3-017","P3-018"]},"appeals":{"filingWindow":"original result day through end of following local day","sealsAt":"start of original result day plus two calendar days","timezone":"America/Costa_Rica","deadlineExclusive":true,"example":"Monday result seals Wednesday 00:00","timelyPendingAppealAtSeal":"expire unresolved; no post-seal decision","latePublishedResult":"if first publication at or after normal original-day-plus-two boundary: seal at start of publication-local-date plus two days; no deadline refresh on later revision","sealedParentCorrectionPolicy":"forbidden; sealed result final","appealAloneAwardsXp":false,"decisionRef":"P3-019","decisionRefs":["P3-019","P3-021","P3-022","P3-023"],"examples":["Monday result normally seals Wednesday 00:00; unresolved appeal expires then","Monday result first published Wednesday: appeal through Thursday, seals Friday 00:00"]},"teenReminders":{"previousDayResultReviewTimeLocal":"17:00","timezone":"America/Costa_Rica","otherPendingTaskRemindersRequired":true,"otherTimesAndContent":"not specified","reminderIsNotAppealDeadline":true,"decisionRef":"P3-020"},"deploymentStatus":"Owner-approved title overrides recorded; not yet deployed. Effective-date/version rollout must preserve historical occurrences."}$catalogue$::jsonb,$tracker${"sourceSpreadsheetId":"1GpYowblGnc-3ZOzwLs7HUgdnNQ67vT9ShnfrLAcmQ9Q","readDate":"2026-10-21","note":"Read-only catalogue/policy snapshot. Owner overrides take precedence. Achievement counters and personal notes/history excluded.","rules":[{"sheet":"⚙️ Task Lists","range":"'⚙️ Task Lists'!A1:H20","values":[["Weekday Task","Weekday XP",null,"Weekend Task","Weekend XP"],["⚠️ 1st Attitude Check","15",null,"⚠️ 1st Attitude Check","15"],["🎒 BagPack + Lunchbag + Shower + Room @4PM","11",null,"➡️ Room + Laundry @11PM","12"],["📚 Homework/Study @5:30PM","12",null,"🚿 Shower +No Mess @1PM","11"],["⚠️ 2nd Attitude Check","15",null,"📚 Check HS + Other Pendings / Study @2PM","11"],["➡️ Next Day Prepare @6PM","11",null,"⚠️ 2nd Attitude Check @5PM","15"],["✨ House Help","11",null,"✨ House Help","11"],["📖 Read a new book -or- Bible","1",null,"📖 Read a new book -or- Bible","1"],["💧 Drink 3 glasses of water (House)","1",null,"💧 Drink 3 glasses of water (House)","1"],["📝 Research & write by hand","1",null,"📝 Research & write by hand","2"],["🎨 Draw / Create Dance","1",null,"🎨 Draw / Create Dance","1"],["🧹 Clean up Closet / Shoes","2",null,"🧹 Clean up Closet / Shoes","2"],["🎁 Declutter/give away items","2",null,"🎁 Declutter/give away items","2"],["📚 Hikari Shop","2",null,"📚 Hikari Shop","2"],["🙂 Final Attitude Check","15",null,"🙂 Final Attitude Check","15"]]},{"sheet":"🎁 List_of_Rewards","range":"'🎁 List_of_Rewards'!A1:F35","values":[["#","Reward","Coins","Status","Type","Tier"],["1","🎬 Choose a movie/TV Show for family movie night","450","Available","In-House Event","1 ~ $10"],["2","🃏 Pokémon Booster Pack (~$8)","600","Available","Purchase -Game","1 ~ $10"],["3","💍 Small accessory: earrings, bracelet, hair clips, phone charm, etc.","650","Available","Purchase -Accessory","1 ~ $10"],["4","🧋 Boba, smoothie, café or dessert outing with parent","675","Available","Outdoors Food","1 ~ $10"],["5","🧴 Small self-care/skincare item ($10 max)","800","Available","Purchase -Beauty","1 ~ $10"],["6","🍕 Pizza/takeout family night","1200","Available","In-House Event Food","2 ~ $20"],["7","📚 Book, novel, comic or manga under $20","1200","Available","Purchase -Book","2 ~ $20"],["8","☕ Special parent-daughter outing","1200","Available","Outdoors Food","2 ~ $20"],["9","🎲 Afternoon at the Arcade","1350","Available","In-House Event","2 ~ $20"],["10","💄 Skincare/beauty mini-haul ($20 max)","1400","Available","Purchase -Beauty","2 ~ $20"],["11","📖 New book or manga ($30 max)","1850","Available","Purchase -Book","3 ~ $30"],["12","👯 Friend comes over + favorite takeout/snacks","1900","Available","In-House Event Food","3 ~ $30"],["13","🎥 Go to the movies","1950","Available","Outdoors Event","3 ~ $30"],["14","👕 Branded T-shirt / band / K-pop / anime shirt or accessory","2000","Available","Purchase -Clothing","3 ~ $30"],["15","🧸 Pokémon/anime/K-pop collectible or plush ($30 max)","2050","Available","Purchase -Collectible","3 ~ $30"],["16","👯 Bring a friend to movies / café / eat out","2500","Available","Outdoors Event","4 ~ $40"],["17","🎲 New family board game ($40 max)","2500","Available","Purchase -Game","4 ~ $40"],["18","🏃 Sports/running/fitness gear upgrade","2550","Available","Purchase -Sports","4 ~ $40"],["19","🪞 Room décor / vanity / aesthetic bedroom upgrade ($40)","2650","Available","Purchase -Room Decor","4 ~ $40"],["20","🎒 School-style upgrade: backpack, tote, bottle, pencil case, etc.","5000","Available","Purchase -Tools","5 ~ $75"],["21","👟 Shoes/sneakers ($70)","5500","Available","Purchase -Clothing","5 ~ $75"],["22","🎓 Enroll in a short course/workshop she chooses","6000","Available","Purchase -Class","5 ~ $75"],["23","🃏 Pokémon ETB","6000","Available","Purchase -Game","5 ~ $75"],["24","💄 Premium skincare/beauty/fashion item ($60–75 max)","6000","Available","Purchase -Beauty","5 ~ $75"],["25","🎒 Premium backpack + full school/style kit","10000","Available","Purchase -Tools","Premium ~ $100"],["26","🎫 Contribution toward a concert/show/event she really wants","10000","Available","Purchase -Event","Premium ~ $100"],["27","🚗 Family day trip / nearby destination","11000","Available","Outdoors Event","Premium ~ $100"],["28","🛍️ $100 shopping/gift-card budget for K-pop, fashion, beauty, etc.","12500","Available","Purchase","Premium ~ $100"],["29","🎢 Theme park / major special-event day","16000","Available","Outdoors Event","Platinum ~ $150+"]]},{"sheet":"🏆 Achievements","range":"'🏆 Achievements'!A1:J24","values":[[],["Action","XP/Coins Awarded","Notes"],["Aced Test","50","Any test scored 100"],["Student of Excellence I","250","All trimester grades > 97"],["Student of Excellence II","300","Best student of the Class"],["Student of Excellence III","400","Best student of the Gen"],["Girl Machine","1000","1 month good behavior consistency"],["Wise Princess","2000","2 month FULL required consistency"],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[null,null,null],[],[],[],[],["Total Achievements XP","0"]]},{"sheet":"⚖️ Accountability & Privileges","range":"'⚖️ Accountability & Privileges'!A1:H48","values":[["⚖️ ACCOUNTABILITY & PRIVILEGES",null,null,null,null,null,"🎁 BENEFITS & PRIVILEGES"],["Your final daily XP determines the type of day. 90 is the minimum passing score; scores above 90 move into higher-performance levels.",null,null,null,null,null,"Use this list as the master catalog of benefits and privileges that can be kept, lost, or earned depending on the daily result."],[],["Score","Day Type","Level","Meaning",null,null,"#","Benefit / Privilege"],["100","🌟 Exceptional Day","Above Pass","Maximum daily score",null,null,"1","Agregar 15mins a WhatsApp"],["96–99","💎 Amazing Day","Above Pass","Outstanding day",null,null,"2","Habilitar Cámara y Galería"],["91–95","🏆 Excellent Day","Above Pass","Exceeded the passing standard",null,null,"3","30mins de Televisión"],["90","✅ Passed Day — Good Day","Pass","Minimum passing score met",null,null,"4","Habilitar Walkman"],["85–89","⚠️ Almost Passed","Below Pass","Close to the standard, but the day does not pass (still gets the XP)",null,null,"5","Habilitar Chess App"],["75–84","🟠 Needs Improvement","Below Pass","Daily standard was not met",null,null,"6","Habilitar Pokémon TCG App"],["60–74","🔴 Poor Day","Below Pass","Significant improvement is needed",null,null,"7","Habilitar Emulador GBA"],["0–59","⛔ Bad Day","Below Pass","Major expectations were not met",null,null,"8","Habilitar Google Search"],[null,null,null,null,null,null,"9","Habilitar YouTube Music"],[null,null,null,null,null,null,"10","Habilitar YouTube"],["🎯 RESULTS BY DAY TYPE",null,null,null,null,null,"11"],["Use this section to define exactly what privileges are kept, what is lost, and what extra benefits or rewards are earned at each level.",null,null,null,null,null,"12"],[null,null,null,null,null,null,"13"],["Score","Day Type","Result",null,null,null,"14"],["100","🌟 Exceptional Day","⬇️ + Double XP boost",null,null,null,"15"],["96–99","💎 Amazing Day","⬇️ + ₡500 for each XP point above 95"],["91–95","🏆 Excellent Day","⬇️ + Skin Care regained"],["90","✅ Passed Day — Good Day","⬇️ + add one lost benefit / privilege"],["85–89","⚠️ Almost Passed","Keep your current benefits and privileges."],["75–84","🟠 Needs Improvement","Lose 1-2 benefits or privileges"],["60–74","🔴 Poor Day","Lose 3-4 benefits or privileges"],["0–59","⛔ Bad Day","Lose all benefits and privileges - Lose Hikari Money - Week plans canceled"],[],[],["⚠️ ACCOUNTABILITY DEDUCTIONS"],["These deductions reduce the final XP for the day. Multiple deductions may be added together when more than one accountability issue happens on the same day."],[],["Accountability Deduction",null,"XP Deduction","Notes / Examples"],["🥪 Dirty Lunchbag",null,"-5 XP"],["👕 Torn Clothes",null,"-20 XP"],["🚫 Did Not Follow Instructions",null,"-6 XP"],["🚿 Forgot Towel or Clothes for Shower",null,"-4 XP"],["✨ Messy / Dirty Items",null,"-5 XP"]]},{"sheet":"🪙 XP & Coins","range":"'🪙 XP & Coins'!I1:V5","values":[["base",null,"silver",null,"gold",null,"ruby",null,"sapphire",null,"emerald",null,"diamond"]]}]}$tracker$::jsonb);
notify pgrst, 'reload schema';

-- SOURCE: migrations/202610210006_phase8_deductions.sql
-- Apply only after 202610210005. Either parent records the fixed tracker amounts.

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

-- SOURCE: migrations/202610210007_phase8_owner_followup.sql

-- P8 owner follow-up: activate today; existing submitted/finalized snapshots remain intact.
update petal_private.phase8_catalogue set effective_from='2026-10-21';
alter table public.submissions drop constraint submissions_status_check;
alter table public.submissions add constraint submissions_status_check check(status in ('pending','approved','rejected','returned'));
create table public.submission_reviews (
 id uuid primary key default gen_random_uuid(),family_id uuid not null,submission_id uuid not null,
 parent_user_id uuid not null references auth.users(id),outcome text not null check(outcome in ('approved','rejected','returned')),
 review_note text not null default '' check(length(review_note)<=2000),reviewed_at timestamptz not null default clock_timestamp(),
 foreign key(submission_id,family_id) references public.submissions(id,family_id)
);
alter table public.submission_reviews enable row level security;
revoke all on public.submission_reviews from public,anon,authenticated;
grant select on public.submission_reviews to authenticated;
create policy subject_read on public.submission_reviews for select to authenticated using(exists(select 1 from public.submissions s where s.id=submission_id and petal_private.can_read_teen(s.family_id,s.teen_id)));
-- Rule semantics and source provenance remain immutable; only current-version selection may change.
create or replace function petal_private.protect_initial_rule() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'historical_rule_immutable'; end if;
 if (to_jsonb(new)-'current_version') is distinct from (to_jsonb(old)-'current_version') then raise exception 'historical_rule_immutable'; end if;
 return new;
end $$;
-- Version each revised rule without changing points, weekdays or due times.
do $$ declare f uuid;item jsonb;d public.task_definitions%rowtype;r public.rule_versions%rowtype;new_rule uuid;begin
 for f in select id from public.families loop
 for item in select value from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'duties') where value->>'decisionRef'='P8-001' loop
 select * into d from public.task_definitions where family_id=f and catalogue_key=item->>'id';
 if not found then continue; end if;
 select * into r from public.rule_versions where definition_id=d.id and current_version;
 update public.rule_versions set current_version=false where id=r.id;
 insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
 values(f,d.id,r.version+1,r.points,r.local_due_time,r.weekdays,true,'Phase8 P8-001; effective 2026-10-21; XP unchanged') returning id into new_rule;
 update public.task_definitions set title=item->>'title' where id=d.id;
 update public.task_occurrences o set title_snapshot=item->>'title',rule_version_id=new_rule where o.definition_id=d.id and o.local_date>='2026-10-21'
 and not exists(select 1 from public.submissions s where s.occurrence_id=o.id)
 and not exists(select 1 from public.day_results dr where dr.family_id=o.family_id and dr.teen_id=o.teen_id and dr.local_date=o.local_date);
 end loop;end loop;
end $$;
-- New families seed approved current labels as part of their same creation transaction.
alter function petal_private.seed_family_catalogue(uuid) rename to seed_family_catalogue_phase6;
create function petal_private.seed_family_catalogue(p_family_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform petal_private.seed_family_catalogue_phase6(p_family_id);
 update public.task_definitions d set title=item.value->>'title' from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'duties') item
 where d.family_id=p_family_id and d.catalogue_key=item.value->>'id';

end $$;
revoke execute on function petal_private.seed_family_catalogue(uuid),petal_private.seed_family_catalogue_phase6(uuid) from public,anon,authenticated;

create function petal_private.day_deadline(p_family_id uuid,p_teen_id uuid,p_local_date date) returns timestamptz language sql stable security definer set search_path='' as $$
 select effective_seal_at from public.day_results where family_id=p_family_id and teen_id=p_teen_id and local_date=p_local_date;
$$;
create or replace function petal_private.submit_occurrence(p_occurrence_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();o public.task_occurrences%rowtype;s public.submissions%rowtype;answer jsonb;
begin
 select * into o from public.task_occurrences where id=p_occurrence_id;
 if not found then raise exception 'teen_owner_required' using errcode='42501'; end if;
 perform 1 from public.families where id=o.family_id for update;
 if not exists(select 1 from public.memberships where user_id=u and actor_id=o.teen_id and family_id=o.family_id and active and role='teen') then raise exception 'teen_owner_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'submit',jsonb_build_object('occurrence_id',p_occurrence_id));
 if answer is not null then return answer; end if;
 select * into s from public.submissions where occurrence_id=o.id for update;
 -- Replays of a committed outcome remain historical; a new resubmission is checked against the server deadline.
 if s.id is null or s.status='returned' then
 if clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then raise exception 'day_sealed'; end if;
 if o.local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'future_task'; end if;
 if s.id is null then
 insert into public.submissions(family_id,occurrence_id,teen_id) values(o.family_id,o.id,o.teen_id) returning * into s;
 else
 update public.submissions set status='pending' where id=s.id returning * into s;
 end if;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(o.family_id,'submission.pending',s.id,jsonb_build_object('submission_id',s.id)) on conflict(topic,source_id) do nothing;
 end if;
 answer:=to_jsonb(s)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

create function petal_private.review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;o public.task_occurrences%rowtype;d public.decisions%rowtype;a public.daily_accounting%rowtype;answer jsonb;review_id uuid;score integer;earned integer;delta integer;ded integer;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 if p_outcome not in ('approved','rejected','returned') or p_outcome is null then raise exception 'invalid_review_outcome'; end if;
 answer:=petal_private.begin_request(p_request_id,'review_submission',jsonb_build_object('submission_id',p_submission_id,'outcome',p_outcome,'review_note',coalesce(p_review_note,'')));
 if answer is not null then return answer; end if;
 select * into s from public.submissions where id=p_submission_id for update;
 select * into o from public.task_occurrences where id=s.occurrence_id;
 select * into d from public.decisions where submission_id=s.id;
 if d.id is not null then
 if p_outcome<>'approved' then raise exception 'approved_work_correction_policy_required'; end if;
 else
 if clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then raise exception 'day_sealed'; end if;
 if s.status<>'pending' then raise exception 'review_transition_unavailable_refresh_required'; end if;
 insert into public.submission_reviews(family_id,submission_id,parent_user_id,outcome,review_note) values(s.family_id,s.id,u,p_outcome,coalesce(p_review_note,'')) returning id into review_id;
 update public.submissions set status=p_outcome where id=s.id;
 if p_outcome='approved' then
 insert into public.decisions(family_id,submission_id,parent_id,status,contribution_points) values(s.family_id,s.id,u,'approved',o.points_snapshot) returning * into d;
 insert into public.xp_events(family_id,teen_id,decision_id,local_date,contribution_points) values(s.family_id,s.teen_id,d.id,o.local_date,d.contribution_points);
 -- A delayed approved submission belongs to the original task day. Recompute full state.
 select * into a from public.daily_accounting where family_id=o.family_id and teen_id=o.teen_id and local_date=o.local_date order by revision desc limit 1;
 if found then
 if a.virtual_remaining<>0 or a.converted_points<>0 then raise exception 'excused_correction_policy_required'; end if;
 select coalesce(sum(dec.contribution_points),0) into score from public.decisions dec join public.submissions sub on sub.id=dec.submission_id join public.task_occurrences oc on oc.id=sub.occurrence_id where oc.family_id=o.family_id and oc.teen_id=o.teen_id and oc.local_date=o.local_date;
 select coalesce(sum(points),0) into ded from public.deduction_entries where family_id=o.family_id and teen_id=o.teen_id and local_date=o.local_date;
 score:=greatest(0,score-ded);earned:=case when score<85 then 0 when score=100 and not a.conversion_history then 200 else score end;delta:=earned-a.earned_xp;
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,conversion_history,rule_snapshot) values(o.family_id,o.teen_id,o.local_date,a.revision+1,score,score,earned,a.conversion_history,a.rule_snapshot||jsonb_build_object('review_id',review_id));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(o.family_id,o.teen_id,'review:'||review_id,o.local_date,delta,delta);
 end if;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(s.family_id,'submission.approved',d.id,jsonb_build_object('submission_id',s.id,'decision_id',d.id));
 end if;
 end if;
 answer:=jsonb_build_object('request_id',p_request_id,'submission_id',s.id,'decision_id',d.id,'status',p_outcome,'review_id',review_id,'contribution_points',coalesce(d.contribution_points,0),'spendable_xp',0);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
-- Preserve Phase6 approval response keys and operation identity while adopting approved late-work policy.
create or replace function petal_private.approve_submission(p_submission_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);s public.submissions%rowtype;answer jsonb;internal_id uuid;
begin
 select * into s from public.submissions where id=p_submission_id;
 if not found then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=s.family_id for update;
 if not petal_private.is_member(s.family_id,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'approve',jsonb_build_object('submission_id',p_submission_id));
 if answer is not null then return answer; end if;
 internal_id:=gen_random_uuid();
 answer:=petal_private.review_submission(p_submission_id,'approved','',internal_id)||jsonb_build_object('request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
create function public.review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.review_submission(p_submission_id,p_outcome,p_review_note,p_request_id);$$;
revoke execute on function petal_private.review_submission(uuid,text,text,uuid),public.review_submission(uuid,text,text,uuid) from public,anon;
grant execute on function petal_private.review_submission(uuid,text,text,uuid),public.review_submission(uuid,text,text,uuid) to authenticated;
revoke execute on function petal_private.day_deadline(uuid,uuid,date) from public,anon,authenticated;
-- Parent explicitly finalizes; unsubmitted duties contribute zero and pending reviews block publication.
create or replace function petal_private.finalize_complete_day(p_teen_id uuid,p_local_date date,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(true);f uuid;answer jsonb;actual integer;ded integer;earned integer;published timestamptz;seal timestamptz;
begin
 select family_id into f from public.family_actors where id=p_teen_id and role='teen';
 if f is null then raise exception 'parent_required' using errcode='42501'; end if;
 perform 1 from public.families where id=f for update;
 if not petal_private.is_member(f,'parent') then raise exception 'parent_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'finalize_complete_day',jsonb_build_object('teen_id',p_teen_id,'local_date',p_local_date));
 if answer is not null then return answer; end if;
 if exists(select 1 from public.day_results where family_id=f and teen_id=p_teen_id and local_date=p_local_date) then raise exception 'published_day_correction_unresolved'; end if;
 if p_local_date is null or p_local_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_day'; end if;
 if exists(select 1 from public.submissions s join public.task_occurrences o on o.id=s.occurrence_id where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date and s.status='pending') then raise exception 'pending_reviews_require_resolution'; end if;
 if (select count(*) from public.task_occurrences where family_id=f and teen_id=p_teen_id and local_date=p_local_date)<>14 then raise exception 'historical_catalogue_snapshot_required'; end if;
 select coalesce(sum(d.contribution_points),0) into actual from public.decisions d join public.submissions s on s.id=d.submission_id join public.task_occurrences o on o.id=s.occurrence_id where o.family_id=f and o.teen_id=p_teen_id and o.local_date=p_local_date;
 select coalesce(sum(points),0) into ded from public.deduction_entries where family_id=f and teen_id=p_teen_id and local_date=p_local_date;
 actual:=greatest(0,actual-ded);earned:=case when actual<85 then 0 when actual=100 then 200 else actual end;
 published:=clock_timestamp();seal:=((p_local_date+2)::timestamp at time zone 'America/Costa_Rica');
 if published>=seal then seal:=((((published at time zone 'America/Costa_Rica')::date+2)::timestamp) at time zone 'America/Costa_Rica'); end if;
 insert into public.day_results values(f,p_teen_id,p_local_date,published,seal);
 insert into public.daily_accounting(family_id,teen_id,local_date,revision,actual_score,protected_score,earned_xp,rule_snapshot) values(f,p_teen_id,p_local_date,1,actual,actual,earned,jsonb_build_object('version','phase3-owner-confirmed-v1','deductions',ded,'finalization','unsubmitted_zero_pending_reviews_resolved'));
 insert into public.wallet_events(family_id,teen_id,source_key,local_date,earned_xp_delta,coin_delta) values(f,p_teen_id,'day:'||p_teen_id||':'||p_local_date||':1',p_local_date,earned,earned);
 answer:=jsonb_build_object('status','finalized','earned_xp',earned,'coins_earned',earned,'actual_score',actual,'effective_seal_at',seal);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;

create table public.extra_outcome_requests(
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,
 kind text not null check(kind in ('cash','achievement','privilege')),outcome_key text not null,target_date date not null,
 reason text not null default '' check(length(reason)<=2000),status text not null default 'requested' check(status in ('requested','confirmed','declined','cancelled')),
 created_at timestamptz not null default clock_timestamp(),foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create unique index one_pending_extra_outcome on public.extra_outcome_requests(family_id,teen_id,kind,outcome_key,target_date) where status='requested';
alter table public.extra_outcome_requests enable row level security;
revoke all on public.extra_outcome_requests from public,anon,authenticated;
grant select on public.extra_outcome_requests to authenticated;
create policy subject_read on public.extra_outcome_requests for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create function petal_private.outcome_catalogue() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('cash',jsonb_build_array(jsonb_build_object('id','daily-cash','title','Daily cash','description','Tracker ₡500 per point above95; parent confirms eligibility and amount.')),
 'privileges',(select jsonb_agg(item) from (
 select jsonb_build_object('id','privilege-'||lpad(privrow.value->>6,3,'0'),'title',privrow.value->>7,'description','Parent confirms kept, lost or regained privilege from the daily recommendation.') item
 from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.tracker_rules->'rules') sheet cross join lateral jsonb_array_elements(sheet->'values') privrow
 where sheet->>'sheet' like '%Accountability%' and privrow.value->>6 ~ '^([1-9]|10)$' and privrow.value->>7 is not null
 union all select jsonb_build_object('id','privilege-skincare','title','Skin Care','description','Tracker recommendation: regained on Excellent Day or higher; parent confirms.')
 union all select jsonb_build_object('id','privilege-hikari-money','title','Hikari Money','description','Tracker consequence: lost on Bad Day; parent confirms.')
 union all select jsonb_build_object('id','privilege-week-plans','title','Week plans','description','Tracker consequence: cancelled on Bad Day; parent confirms.')
 ) outcomes));
$$;
create function petal_private.request_extra_outcome(p_kind text,p_outcome_key text,p_target_date date,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;answer jsonb;r public.extra_outcome_requests%rowtype;valid boolean;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'request_extra_outcome',jsonb_build_object('kind',p_kind,'outcome_key',p_outcome_key,'target_date',p_target_date,'reason',coalesce(p_reason,'')));
 if answer is not null then return answer; end if;
 if p_target_date is null or p_target_date>(clock_timestamp() at time zone 'America/Costa_Rica')::date then raise exception 'invalid_target_date'; end if;
 if p_kind='achievement' then
 select exists(select 1 from petal_private.phase8_catalogue c cross join lateral jsonb_array_elements(c.catalogue->'achievements') v where v->>'id'=p_outcome_key) into valid;
 elsif p_kind in ('cash','privilege') then
 select exists(select 1 from jsonb_array_elements(petal_private.outcome_catalogue()->case p_kind when 'cash' then 'cash' else 'privileges' end) v where v->>'id'=p_outcome_key) into valid;
 end if;
 if not coalesce(valid,false) then raise exception 'unknown_outcome'; end if;
 insert into public.extra_outcome_requests(family_id,teen_id,kind,outcome_key,target_date,reason) values(m.family_id,m.actor_id,p_kind,p_outcome_key,p_target_date,coalesce(p_reason,''))
 on conflict(family_id,teen_id,kind,outcome_key,target_date) where status='requested' do nothing returning * into r;
 if r.id is null then select * into r from public.extra_outcome_requests where family_id=m.family_id and teen_id=m.actor_id and kind=p_kind and outcome_key=p_outcome_key and target_date=p_target_date and status='requested'; end if;
 answer:=to_jsonb(r)||jsonb_build_object('request_id',p_request_id,'authority','parent_confirmation_required');
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'extra_outcome.requested',r.id,jsonb_build_object('outcome_request_id',r.id,'kind',r.kind)) on conflict(topic,source_id) do nothing;
 return answer;
end $$;
create function public.request_extra_outcome(p_kind text,p_outcome_key text,p_target_date date,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.request_extra_outcome(p_kind,p_outcome_key,p_target_date,p_reason,p_request_id);$$;
revoke execute on function petal_private.request_extra_outcome(text,text,date,text,uuid),public.request_extra_outcome(text,text,date,text,uuid) from public,anon;
grant execute on function petal_private.request_extra_outcome(text,text,date,text,uuid),public.request_extra_outcome(text,text,date,text,uuid) to authenticated;
revoke execute on function petal_private.outcome_catalogue() from public,anon,authenticated;




create function petal_private.guard_submission_seal() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.task_occurrences%rowtype; sid uuid;
begin
 if tg_table_name='submission_reviews' then sid:=new.submission_id; else sid:=new.id; end if;
 select oc.* into o from public.task_occurrences oc join public.submissions s on s.occurrence_id=oc.id where s.id=sid;
 if clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then raise exception 'day_sealed'; end if;
 return new;
end $$;
create constraint trigger submission_commit_seal after insert or update on public.submissions deferrable initially deferred for each row execute function petal_private.guard_submission_seal();
create constraint trigger review_commit_seal after insert on public.submission_reviews deferrable initially deferred for each row execute function petal_private.guard_submission_seal();
revoke execute on function petal_private.guard_submission_seal() from public,anon,authenticated;

create table public.day_appeals(
 id uuid primary key default gen_random_uuid(),family_id uuid not null,teen_id uuid not null,local_date date not null,result_revision integer not null,
 reason text not null check(length(trim(reason)) between 1 and 2000),status text not null default 'requested' check(status in ('requested','expired','resolved')),
 created_at timestamptz not null default clock_timestamp(),unique(family_id,teen_id,local_date),
 foreign key(family_id,teen_id,local_date,result_revision) references public.daily_accounting(family_id,teen_id,local_date,revision)
);
alter table public.day_appeals enable row level security;
revoke all on public.day_appeals from public,anon,authenticated;
grant select on public.day_appeals to authenticated;
create policy subject_read on public.day_appeals for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create function petal_private.request_day_appeal(p_local_date date,p_reason text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity();m public.memberships%rowtype;answer jsonb;r public.day_appeals%rowtype;a public.daily_accounting%rowtype;seal timestamptz;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 perform 1 from public.families where id=m.family_id for update;
 if not petal_private.is_member(m.family_id,'teen') then raise exception 'teen_required' using errcode='42501'; end if;
 answer:=petal_private.begin_request(p_request_id,'request_day_appeal',jsonb_build_object('local_date',p_local_date,'reason',p_reason));
 seal:=petal_private.day_deadline(m.family_id,m.actor_id,p_local_date);
 if answer is not null then
 select * into r from public.day_appeals where family_id=m.family_id and teen_id=m.actor_id and local_date=p_local_date;
 return to_jsonb(r)||jsonb_build_object('status',case when r.status='requested' and clock_timestamp()>=seal then 'expired' else r.status end,'effective_seal_at',seal,'request_id',p_request_id);
 end if;
 if seal is null then raise exception 'published_result_required'; end if;
 if clock_timestamp()>=seal then raise exception 'day_sealed'; end if;
 select * into a from public.daily_accounting where family_id=m.family_id and teen_id=m.actor_id and local_date=p_local_date order by revision desc limit 1;
 if not found then raise exception 'published_accounting_required'; end if;
 insert into public.day_appeals(family_id,teen_id,local_date,result_revision,reason) values(m.family_id,m.actor_id,p_local_date,a.revision,trim(p_reason)) on conflict(family_id,teen_id,local_date) do nothing returning * into r;
 if r.id is null then select * into r from public.day_appeals where family_id=m.family_id and teen_id=m.actor_id and local_date=p_local_date; end if;
 answer:=to_jsonb(r)||jsonb_build_object('effective_seal_at',seal,'request_id',p_request_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(m.family_id,'day_appeal.requested',r.id,jsonb_build_object('day_appeal_id',r.id)) on conflict(topic,source_id) do nothing;
 return answer;
end $$;
create function public.request_day_appeal(p_local_date date,p_reason text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select petal_private.request_day_appeal(p_local_date,p_reason,p_request_id);$$;
revoke execute on function petal_private.request_day_appeal(date,text,uuid),public.request_day_appeal(date,text,uuid) from public,anon;
grant execute on function petal_private.request_day_appeal(date,text,uuid),public.request_day_appeal(date,text,uuid) to authenticated;
-- Appeal filing itself must also be before the effective seal at transaction completion.
create constraint trigger appeal_commit_seal after insert on public.day_appeals deferrable initially deferred for each row execute function petal_private.guard_result_seal();
create or replace function petal_private.get_teen_dashboard(p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(); m public.memberships%rowtype; c jsonb; tr jsonb; tasks jsonb; days jsonb;
begin
 select * into m from public.memberships where user_id=u and active and role='teen';
 if not found then raise exception 'teen_required' using errcode='42501'; end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 then raise exception 'invalid_history_range'; end if;
 select catalogue,tracker_rules into c,tr from petal_private.phase8_catalogue where singleton;
 select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('catalogue_key',d.catalogue_key,'status',coalesce(s.status,'open'),
 'submission_id',s.id,'submitted_at',s.submitted_at,'decision_id',dc.id,'reviewed_at',dc.decided_at,
 'submission_ready',coalesce(clock_timestamp()<petal_private.day_deadline(o.family_id,o.teen_id,o.local_date),true),'readiness_reason',case when clock_timestamp()>=petal_private.day_deadline(o.family_id,o.teen_id,o.local_date) then 'day_sealed' end,'is_late',case when o.due_at is not null then coalesce(s.submitted_at,clock_timestamp())>o.due_at end,'effective_seal_at',petal_private.day_deadline(o.family_id,o.teen_id,o.local_date),'review_note',(select review_note from public.submission_reviews rv where rv.submission_id=s.id order by reviewed_at desc,id desc limit 1)) order by o.local_date,o.due_at nulls last,o.id),'[]') into tasks
 from public.task_occurrences o join public.task_definitions d on d.id=o.definition_id
 left join public.submissions s on s.occurrence_id=o.id left join public.decisions dc on dc.submission_id=s.id
 where o.family_id=m.family_id and o.teen_id=m.actor_id and o.local_date between p_from and p_to;
 with dates as (
 select local_date from public.task_occurrences where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 union select local_date from public.day_results where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to
 ), summaries as (
 select dt.local_date,dr.first_published_at,dr.effective_seal_at,a.revision,a.actual_score,a.virtual_remaining,a.protected_score,a.converted_points,a.conversion_history,a.earned_xp,a.rule_snapshot,
 (select coalesce(sum(points),0) from public.deduction_entries de where de.family_id=m.family_id and de.teen_id=m.actor_id and de.local_date=dt.local_date) deduction_points
 from dates dt left join public.day_results dr on dr.family_id=m.family_id and dr.teen_id=m.actor_id and dr.local_date=dt.local_date
 left join lateral(select * from public.daily_accounting da where da.family_id=m.family_id and da.teen_id=m.actor_id and da.local_date=dt.local_date order by revision desc limit 1) a on true
 ) select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('status',case when first_published_at is null then 'pending' when clock_timestamp()>=effective_seal_at then 'sealed' else 'finalized' end,
 'coins_earned',earned_xp,'rule_version_id',rule_snapshot->>'version','performance_icon',case when revision is not null then petal_private.performance_band(protected_score)->>'icon' end,
 'performance_label',case when revision is not null then petal_private.performance_band(protected_score)->>'label' end,
 'week_start',local_date-extract(dow from local_date)::integer) order by local_date),'[]') into days from summaries s;
 return jsonb_build_object('api_contract_version',2,'server_now',clock_timestamp(),'server_local_date',(clock_timestamp() at time zone 'America/Costa_Rica')::date,
 'family_id',m.family_id,'teen_id',m.actor_id,'tasks',tasks,'day_summaries',days,
 'balance',(select jsonb_build_object('earned_xp',coalesce(sum(earned_xp_delta),0),'available_coins',coalesce(sum(coin_delta),0),'coin_rank',case when coalesce(sum(coin_delta),0)>=10000 then 'Diamond' when coalesce(sum(coin_delta),0)>=5000 then 'Emerald' when coalesce(sum(coin_delta),0)>=2500 then 'Sapphire' when coalesce(sum(coin_delta),0)>=1000 then 'Ruby' when coalesce(sum(coin_delta),0)>=500 then 'Gold' when coalesce(sum(coin_delta),0)>=100 then 'Silver' else 'Base' end) from public.wallet_events where family_id=m.family_id and teen_id=m.actor_id),
 'deductions',(select coalesce(jsonb_agg(to_jsonb(de) order by created_at),'[]') from public.deduction_entries de where family_id=m.family_id and teen_id=m.actor_id and local_date between p_from and p_to),
 'reward_catalogue',coalesce(c->'rewards','[]'),'achievements',coalesce(c->'achievements','[]'),'tracker_rules',tr,
 'reward_requests',(select coalesce(jsonb_agg(to_jsonb(rr) order by created_at desc),'[]') from public.reward_requests rr where family_id=m.family_id and teen_id=m.actor_id),
 'day_appeals',(select coalesce(jsonb_agg(to_jsonb(ap)||jsonb_build_object('status',case when ap.status='requested' and clock_timestamp()>=petal_private.day_deadline(ap.family_id,ap.teen_id,ap.local_date) then 'expired' else ap.status end,'effective_seal_at',petal_private.day_deadline(ap.family_id,ap.teen_id,ap.local_date)) order by ap.created_at desc),'[]') from public.day_appeals ap where ap.family_id=m.family_id and ap.teen_id=m.actor_id),'review_history',(select coalesce(jsonb_agg(to_jsonb(rv) order by rv.reviewed_at),'[]') from public.submission_reviews rv join public.submissions sub on sub.id=rv.submission_id join public.task_occurrences oc on oc.id=sub.occurrence_id where oc.family_id=m.family_id and oc.teen_id=m.actor_id and oc.local_date between p_from and p_to),'outcome_catalogue',petal_private.outcome_catalogue(),'extra_outcome_requests',(select coalesce(jsonb_agg(to_jsonb(er) order by created_at desc),'[]') from public.extra_outcome_requests er where er.family_id=m.family_id and er.teen_id=m.actor_id),'readiness',jsonb_build_object('unknown_due_times','no_invented_due_time_parent_reviews_credit','phase8_title_activation','effective_2026-10-21','partial_day_finalization','unsubmitted_zero_pending_reviews_resolved',
 'excuses_and_conversion','allocation_and_bonus_policy_required','appeals','filing_ready_parent_resolution_phase9','achievements','teen_requests_parent_confirms',
 'negative_corrections','debt_policy_required','cash_and_privileges','teen_requests_parent_confirms','historical_generation','effective_date_policy_required'));
end $$;

notify pgrst,'reload schema';

commit;
