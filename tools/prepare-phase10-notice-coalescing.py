"""Prepare a forward-only live repair; never execute SQL or read credentials."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "supabase/migrations/202610220015_phase10_notifications.sql").read_text(encoding="utf-8-sig")
start = source.index("create function petal_private.materialize_family_notice(")
end = source.index("create function petal_private.family_notice_outbox(", start)
function = source[start:end].strip()
function = function.replace("create function petal_private.materialize_family_notice", "create or replace function petal_private.materialize_family_notice", 1)
function = function.replace("sender uuid;", "sender uuid;alert_group text;", 1)
function = function.replace(" sender:=case", " if e.topic='task.assigned' then alert_group:='task_day:'||t::text||':'||dt::text;\n elsif e.topic='catalogue.updated' then alert_group:='catalogue:'||(j->>'kind')||':'||(j->>'effective_from');end if;\n sender:=case", 1)
function = function.replace("destination,created_at,expires_at)", "destination,created_at,expires_at,alert_group_key)", 1)
function = function.replace("else e.created_at+interval '7 days' end\n from public.memberships", "else e.created_at+interval '7 days' end,alert_group\n from public.memberships", 1)
function = function.replace("on conflict(source_event_id,recipient_user_id) do nothing;", "on conflict do nothing;", 1)
def extract(first, following):
    begin = source.index(first)
    finish = source.index(following, begin)
    return source[begin:finish].strip()

registration = extract("create function public.register_family_device(", "create function public.unregister_family_device(")
registration = registration.replace("create function public.register_family_device", "create or replace function public.register_family_device", 1)
registration = registration.replace("active=true,updated_at=clock_timestamp() returning", "enrolled_at=case when family_devices.user_id=u and family_devices.family_id=m.family_id and family_devices.app=m.role and family_devices.active then family_devices.enrolled_at else clock_timestamp() end,\n active=true,updated_at=clock_timestamp() returning", 1)
authorization = extract("create function petal_private.family_delivery_authorized(", "create function public.claim_family_event_push(")
authorization = authorization.replace("create function petal_private.family_delivery_authorized", "create or replace function petal_private.family_delivery_authorized", 1)
authorization = authorization.replace("and d.active", "and n.created_at>=d.enrolled_at and d.active", 1)
claim = extract("create function public.claim_family_event_push(", "create function public.authorize_family_event_push(")
claim = claim.replace("create function public.claim_family_event_push", "create or replace function public.claim_family_event_push", 1)
claim = claim.replace("where n.expires_at>clock_timestamp() and d.active", "where n.expires_at>clock_timestamp() and n.created_at>=d.enrolled_at and d.active", 1)
claim = claim.replace("and d.active and d.binding_id=q.binding_id", "and n.created_at>=d.enrolled_at and d.active and d.binding_id=q.binding_id", 1)
claim = claim.replace("order by q.next_attempt_at,q.id", "order by case when n.created_at>=clock_timestamp()-interval '10 minutes' then 0 else 1 end,q.next_attempt_at,q.id", 1)
header = """-- DEVELOPMENT ONLY. Coalesce automatic duty lists/catalogue batches, preserving source facts.
-- Run only after the notification diagnostic confirms the expected development schema.
begin;
do $$ begin
 if to_regclass('public.family_notices') is null or to_regclass('public.school_items') is null then raise exception 'Phase10 schema missing; stop and verify the project/database';end if;
end $$;
alter table public.family_notices add column if not exists alert_group_key text;
alter table petal_private.family_devices add column if not exists enrolled_at timestamptz;
update petal_private.family_devices set enrolled_at=updated_at where enrolled_at is null;
alter table petal_private.family_devices alter column enrolled_at set default clock_timestamp();
alter table petal_private.family_devices alter column enrolled_at set not null;
-- Retain every prior notice for audit; expire only redundant entries in the same logical update.
with groups as (
 select n.event_id,n.recipient_user_id,n.family_id,
  case when e.topic='task.assigned' then 'task_day:'||n.teen_id::text||':'||n.local_date::text
   when e.topic='catalogue.updated' then 'catalogue:'||c.kind||':'||c.effective_from::text end group_key
 from public.family_notices n join petal_private.outbox e on e.id=n.source_event_id
 left join public.catalogue_versions c on e.topic='catalogue.updated' and c.id=e.source_id and c.family_id=n.family_id
 where e.topic in ('task.assigned','catalogue.updated')
), ranked as (
 select g.*,row_number() over(partition by g.recipient_user_id,g.family_id,g.group_key order by n.created_at,n.event_id) group_position
 from groups g join public.family_notices n on n.event_id=g.event_id where group_key is not null
)
update public.family_notices n set alert_group_key=case when r.group_position=1 then r.group_key end,
 expires_at=case when r.group_position>1 then least(n.expires_at,clock_timestamp()) else n.expires_at end
from ranked r where n.event_id=r.event_id;
create unique index if not exists family_notice_alert_group on public.family_notices(recipient_user_id,family_id,alert_group_key) where alert_group_key is not null;
update petal_private.family_notice_deliveries q set state='dead',lease_id=null,lease_until=null
where q.state in ('pending','leased') and exists(select 1 from public.family_notices n where n.event_id=q.event_id and n.expires_at<=clock_timestamp());
-- Suppress old backlog per installation; all committed sources and completed receipts remain intact.
update petal_private.family_notice_deliveries q set state='dead',lease_id=null,lease_until=null
from public.family_notices n,petal_private.family_devices d
where q.event_id=n.event_id and q.installation_id=d.installation_id and q.state in ('pending','leased') and n.created_at<d.enrolled_at;
"""
footer = """
revoke execute on function petal_private.materialize_family_notice(uuid) from public,anon,authenticated;
commit;
select exists(select 1 from pg_indexes where schemaname='public' and indexname='family_notice_alert_group') as grouped_notices_ready,
 position('alert_group_key' in pg_get_functiondef('petal_private.materialize_family_notice(uuid)'::regprocedure))>0 as grouped_fanout_ready,
 position('enrolled_at' in pg_get_functiondef('petal_private.family_delivery_authorized(uuid,uuid)'::regprocedure))>0 as enrollment_cutoff_ready,
 position('10 minutes' in pg_get_functiondef('public.claim_family_event_push(integer)'::regprocedure))>0 as fresh_delivery_priority_ready;
"""
output = header + function + "\n" + registration + "\n" + authorization + "\n" + claim + "\n" + footer
(root / "supabase/migrations/202610230018_phase10_notice_coalescing.sql").write_text(output, encoding="utf-8")
(root / "supabase/phase10-notice-coalescing-fix.sql").write_text(output, encoding="utf-8")
print("Prepared notice coalescing migration018 and forward repair. No SQL executed.")
