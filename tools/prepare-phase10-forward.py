"""Assemble the reviewed Phase 10 migrations into one atomic owner-run forward upgrade."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
names = ["202610220015_phase10_notifications.sql", "202610220016_phase10_school.sql", "202610220017_phase10_vacations.sql", "202610230018_phase10_notice_coalescing.sql"]
parts = []
for name in names:
    source = (root / "supabase" / "migrations" / name).read_text(encoding="utf-8-sig")
    parts.append("-- " + name + "\n" + re.sub(r"(?m)^(begin|commit);[ \t]*\r?$", "", source).strip())
header = """-- DEVELOPMENT OWNER ONLY: accepted Phase9 -> complete Phase10; run the complete file once.
-- Includes notifications, school checklist and vacation mode. All schema changes commit together.
-- Explicit RLS is included. Do not use the dashboard's automatic RLS rewriting.
begin;
do $$ begin
 if to_regclass('public.assigned_routine_versions') is null or to_regprocedure('petal_private.phase9_audit_outbox()') is null then raise exception 'Accepted Phase9 prerequisite missing';end if;
 if to_regclass('public.family_notices') is not null or to_regclass('public.school_items') is not null or to_regclass('public.vacation_policy_versions') is not null then raise exception 'Phase10 objects already present; stop and report, do not reapply';end if;
end $$;
"""
footer = """
select
 (select relrowsecurity from pg_class where oid='public.family_notices'::regclass) as notices_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.school_items'::regclass) as school_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.school_change_requests'::regclass) as school_changes_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.school_item_history'::regclass) as school_history_rls_enabled,
 (select relrowsecurity from pg_class where oid='public.vacation_policy_versions'::regclass) as vacation_rls_enabled,
 not has_table_privilege('authenticated','petal_private.family_devices','SELECT') as tokens_not_client_readable,
 not has_function_privilege('authenticated','public.claim_family_event_push(integer)','EXECUTE') as claims_service_only,
 to_regprocedure('public.school_item_action(uuid,uuid,uuid,text,text,integer,uuid,uuid)') is not null as school_actions_ready,
 to_regprocedure('petal_private.snapshot_vacation_occurrence()') is not null as vacation_snapshot_ready,
 date '2026-11-27' as last_school_day, date '2026-11-28' as automatic_vacation_start,
 to_regprocedure('petal_private.wake_family_events_worker()') is not null as webhook_setup_present;
commit;
"""
(root / "supabase" / "phase10-notifications-upgrade.sql").write_text(header + "\n\n".join(parts) + footer, encoding="utf-8")
print("Prepared atomic Phase10 upgrade: migrations015-018. No SQL executed.")
