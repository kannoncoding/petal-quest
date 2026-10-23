-- School checklist is unscored and distinct from immutable daily duty records.
begin;
create table public.school_items (
 id uuid primary key, family_id uuid not null references public.families(id),teen_id uuid not null,
 title text not null check(length(trim(title)) between 1 and 200),version integer not null default 1,
 completed boolean not null default false,removed boolean not null default false,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(family_id,teen_id) references public.family_actors(family_id,id)
);
create table public.school_change_requests (
 id uuid primary key default gen_random_uuid(),family_id uuid not null references public.families(id),teen_id uuid not null,
 item_id uuid not null references public.school_items(id),expected_version integer not null,
 action text not null check(action in ('edit','remove')),proposed_title text,
 requested_by uuid not null references auth.users(id),status text not null default 'pending' check(status in ('pending','approved','rejected','superseded')),
 decided_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),decided_at timestamptz
);
create unique index one_pending_school_change on public.school_change_requests(item_id) where status='pending';
create table public.school_item_history (
 id uuid primary key default gen_random_uuid(),family_id uuid not null references public.families(id),teen_id uuid not null,
 item_id uuid not null references public.school_items(id),actor_id uuid not null references auth.users(id),
 action text not null,before_state jsonb,after_state jsonb,request_id uuid not null,created_at timestamptz not null default clock_timestamp(),
 unique(actor_id,request_id)
);
alter table public.school_items enable row level security;
alter table public.school_change_requests enable row level security;
alter table public.school_item_history enable row level security;
revoke all on public.school_items,public.school_change_requests,public.school_item_history from public,anon,authenticated;
grant select on public.school_items,public.school_change_requests,public.school_item_history to authenticated;
create policy school_read on public.school_items for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy school_change_read on public.school_change_requests for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));
create policy school_history_read on public.school_item_history for select to authenticated using(petal_private.can_read_teen(family_id,teen_id));

create function public.list_school_items(p_family_id uuid,p_teen_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform petal_private.require_identity(false);
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'family_access_required' using errcode='42501';end if;
 return jsonb_build_object('family_id',p_family_id,'teen_id',p_teen_id,'school_active',(clock_timestamp() at time zone 'America/Costa_Rica')::date<=date '2026-11-27',
 'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]') from public.school_items i where family_id=p_family_id and teen_id=p_teen_id),
 'changes',(select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at),'[]') from public.school_change_requests c where family_id=p_family_id and teen_id=p_teen_id));
end $$;

create function public.school_item_action(p_family_id uuid,p_teen_id uuid,p_item_id uuid,p_action text,p_title text,p_expected_version integer,p_request_id uuid,p_change_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=petal_private.require_identity(false);is_parent boolean;r public.school_items%rowtype;c public.school_change_requests%rowtype;answer jsonb;before_state jsonb;change_id uuid;history_id uuid;
begin
 perform 1 from public.families where id=p_family_id for update;
 if not petal_private.can_read_teen(p_family_id,p_teen_id) then raise exception 'family_access_required' using errcode='42501';end if;
 is_parent:=petal_private.is_member(p_family_id,'parent');
 if is_parent then perform petal_private.require_identity(true);end if;
 if not exists(select 1 from public.family_actors where family_id=p_family_id and id=p_teen_id and role='teen') then raise exception 'teen_required';end if;
 answer:=petal_private.begin_request(p_request_id,'school_item_action',jsonb_build_object('family',p_family_id,'teen',p_teen_id,'item',p_item_id,'action',p_action,'title',p_title,'version',p_expected_version,'change',p_change_id));
 if answer is not null then return answer;end if;
 if p_action not in ('create','edit','remove','complete','approve','reject') or p_action is null then raise exception 'invalid_school_action';end if;
 if p_action in ('create','edit') and (p_title is null or length(trim(p_title)) not between 1 and 200) then raise exception 'invalid_school_title';end if;
 if p_action='create' then
  if (clock_timestamp() at time zone 'America/Costa_Rica')::date>date '2026-11-27' then raise exception 'school_term_ended';end if;
  insert into public.school_items(id,family_id,teen_id,title,created_by) values(p_item_id,p_family_id,p_teen_id,trim(p_title),u) returning * into r;
 else
  select * into r from public.school_items where id=p_item_id and family_id=p_family_id and teen_id=p_teen_id for update;
  if not found or r.removed then raise exception 'school_item_unavailable';end if;
  before_state:=to_jsonb(r);
  if p_action in ('approve','reject') then
   if not is_parent then raise exception 'parent_required' using errcode='42501';end if;
   select * into c from public.school_change_requests where id=p_change_id and item_id=r.id and family_id=p_family_id and teen_id=p_teen_id and status='pending' for update;
   if not found then raise exception 'school_change_unavailable';end if;
   if p_action='approve' and c.expected_version<>r.version then raise exception 'stale_school_item';end if;
   if p_action='approve' then
    update public.school_items set title=case when c.action='edit' then c.proposed_title else title end,removed=c.action='remove',version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
   end if;
   update public.school_change_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,decided_by=u,decided_at=clock_timestamp() where id=c.id;
   change_id:=c.id;
  else
   if p_expected_version is distinct from r.version then raise exception 'stale_school_item';end if;
   if p_action='complete' then
    update public.school_items set completed=true,version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
    update public.school_change_requests set status='superseded',decided_at=clock_timestamp() where item_id=r.id and status='pending';
   elsif is_parent then
    update public.school_items set title=case when p_action='edit' then trim(p_title) else title end,removed=p_action='remove',version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
    update public.school_change_requests set status='superseded',decided_at=clock_timestamp() where item_id=r.id and status='pending';
   else
    insert into public.school_change_requests(family_id,teen_id,item_id,expected_version,action,proposed_title,requested_by)
    values(p_family_id,p_teen_id,r.id,r.version,p_action,case when p_action='edit' then trim(p_title) end,u) returning id into change_id;
   end if;
  end if;
 end if;
 insert into public.school_item_history(family_id,teen_id,item_id,actor_id,action,before_state,after_state,request_id)
 values(p_family_id,p_teen_id,r.id,u,p_action,before_state,to_jsonb(r)||jsonb_build_object('change_id',change_id),p_request_id) returning id into history_id;
 insert into petal_private.outbox(family_id,topic,source_id,payload) values(p_family_id,
  case when p_action in ('approve','reject') then 'school.change_reviewed' when change_id is not null then 'school.change_requested' else 'school.item_saved' end,
  coalesce(change_id,history_id),jsonb_build_object('teen_id',p_teen_id));
 answer:=jsonb_build_object('request_id',p_request_id,'item',to_jsonb(r),'change_id',change_id);
 update petal_private.idempotency set result=answer where user_id=u and request_id=p_request_id;
 return answer;
end $$;
revoke execute on function public.list_school_items(uuid,uuid),public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) from public,anon;
grant execute on function public.list_school_items(uuid,uuid),public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid) to authenticated;
alter publication supabase_realtime add table public.school_items,public.school_change_requests;
commit;
