# Phase 9 next owner actions

No phone connection is needed for steps1–2. Both APKs are built; they are not installed yet.

## 1. Development database upgrade

1. Open Petal Quest Dev SQL Editor: https://supabase.com/dashboard/project/hijtwgugzzpjjkuutyfy/sql/new . Confirm the development reference hijtwgugzzpjjkuutyfy.
2. Open E:\CAT\Petal Quest\Android Dev\supabase\phase9-parent-upgrade.sql, copy all and paste into a new query. This forward bundle requires the accepted Phase8 schema, runs in one transaction and stops if Phase9 already exists.
3. Review and run once. RLS is explicitly enabled for every new table; no dashboard auto-RLS fix should be needed. If a warning or SQL error differs from expectations, report its sanitized text before changing the query. Do not run deploy-development.sql or earlier initial bundles on this database.
4. Expected one row: parent_dashboard_ready=true, corrections_ready=true, bonus_ready=true, notes_ready=true, rls_enabled=true. These flags confirm schema objects, not functional acceptance.

No secret/service-role key belongs in chat, SQL source or the Android app. Keep petal_private outside exposed API schemas. Production is untouched.

## 2. Recovery email setup

Follow Recovery-Setup.md. The prepared Recovery-Email-Template.html contains the exact one-time-code placeholder. Change the development Reset password template only. Keep passwords/codes private; no real email has been sent by the coordinator.

## 3. Later: install and verify

Reconnect/unlock the Samsung and notify the coordinator for in-place installation of both APKs. Then begin with Parent dashboard refresh and one fictional pending-task review; do not immediately exercise destructive account/device actions or real reward debits. Acceptance-Checklist.md and Expected-Accounting-Examples.md cover the remaining stages, including the Phase8 pending finalized-total checks.

For concurrent Parent scenarios, use two distinct authenticated Parent sessions with fictional data. The second family phone may wait; an independently authenticated emulator/session can serve the same protocol purpose when available. No phone, emulator or external service was newly installed as part of this preparation.
