# Phase 9 next owner actions

Development SQL is owner-confirmed. Email recovery is deferred. Both APKs were installed in place on the Samsung on 22 October 2026; fictional-data acceptance is in progress.

## 1. Development database upgrade — completed

Owner confirmed all five expected flags true on 22 October 2026. Do not rerun the upgrade. The steps below are retained as the deployment record.

1. Open Petal Quest Dev SQL Editor: https://supabase.com/dashboard/project/hijtwgugzzpjjkuutyfy/sql/new . Confirm the development reference hijtwgugzzpjjkuutyfy.
2. Open E:\CAT\Petal Quest\Android Dev\supabase\phase9-parent-upgrade.sql, copy all and paste into a new query. This forward bundle requires the accepted Phase8 schema, runs in one transaction and stops if Phase9 already exists.
3. Review and run once. RLS is explicitly enabled for every new table; no dashboard auto-RLS fix should be needed. If a warning or SQL error differs from expectations, report its sanitized text before changing the query. Do not run deploy-development.sql or earlier initial bundles on this database.
4. Expected one row: parent_dashboard_ready=true, corrections_ready=true, bonus_ready=true, notes_ready=true, rls_enabled=true. These flags confirm schema objects, not functional acceptance.

No secret/service-role key belongs in chat, SQL source or the Android app. Keep petal_private outside exposed API schemas. Production is untouched.

## 2. Recovery email setup — deferred by owner

Owner chose manual Supabase account administration for this private family app on 22 October 2026. SMTP and in-app email recovery are excluded from Phase9 acceptance; the Parent recovery entry point is hidden. Prepared recovery code/template are retained for optional future use. No Gmail App Password or provider setup is needed now.

## 3. Installation complete; verify

Both APK installations returned Success and preserved existing data. Begin with Parent dashboard refresh and one fictional pending-task review; do not immediately exercise destructive account/device actions or real reward debits. Acceptance-Checklist.md and Expected-Accounting-Examples.md cover the remaining stages, including the Phase8 pending finalized-total checks.

For concurrent Parent scenarios, use two distinct authenticated Parent sessions with fictional data. The second family phone may wait; an independently authenticated emulator/session can serve the same protocol purpose when available. No phone, emulator or external service was newly installed as part of this preparation.

## Assigned routine addition — owner confirmed

In Petal Quest Dev SQL Editor, run the complete `E:\CAT\Petal Quest\Android Dev\supabase\phase9-routines-upgrade.sql` once. Expected row: routines_ready=true and rls_enabled=true. It adds only versioned routines and dashboard fields, enables RLS explicitly and rejects repeat execution. Do not rerun the earlier Phase9 upgrade or any initial deployment. The installed APKs include this editor. Owner confirmed routines_ready=true and rls_enabled=true on 22 October 2026; do not rerun this upgrade.

The first dedicated backend runner attempt failed qa-parent-a@example.com authentication before any test fixture mutation. Confirm the exact fictional account in development Auth, or reset its password there privately. Do not send passwords in chat. The runner cannot proceed until its dedicated accounts authenticate; the phone walkthrough can proceed independently.
## Current next action: repair review audit

Owner observed Teen still pending after Parent Return. Owner has now confirmed phase9_review_audit_fix_ready=true from the repair below; do not rerun it for the walkthrough. Deployment record: run only `E:\CAT\Petal Quest\Android Dev\supabase\phase9-review-fix.sql` in Petal Quest Dev. Expected: phase9_review_audit_fix_ready=true. It replaces the trigger function only; no task/wallet rows are rewritten. Then repeat the review walkthrough and new QA hidden-prompt run. Reconnect/unlock Samsung for the prepared Parent error-feedback update; the last installation attempt found no devices.