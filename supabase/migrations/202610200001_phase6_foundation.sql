-- Phase 6 local foundation. Apply with a privileged migration identity, never an app key.
begin;
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
commit;
