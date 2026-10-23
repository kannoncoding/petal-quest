## Final status — 23 October 2026

Phase10 is complete for the owner's accepted Samsung-only scope. Owner confirmed the final Parent Vacation previews, duties and points. See Completion-Report.md for the consolidated evidence and explicit rollout/regression deferrals. Earlier pending statements below are chronological; do not repeat completed upgrades or request other family phones. Phase11 is prepared in ../phase11/Preparation-Report.md. Production remains untouched.
# Phase 10 development deployment results

22 October 2026. Owner-reported Supabase Dev SQL Editor result for the complete atomic forward upgrade (migrations 015–017):

| Check | Result |
| --- | --- |
| notices_rls_enabled | true |
| school_rls_enabled | true |
| school_changes_rls_enabled | true |
| school_history_rls_enabled | true |
| vacation_rls_enabled | true |
| tokens_not_client_readable | true |
| claims_service_only | true |
| school_actions_ready | true |
| vacation_snapshot_ready | true |
| last_school_day | 2026-11-27 |
| automatic_vacation_start | 2026-11-28 |
| webhook_setup_present | false, expected before worker setup |

The owner has applied the schema upgrade. Do not rerun it. These checks establish reported schema/readiness conditions; they do not prove business RPC execution, correct per-row authorization, vacation allocation on live records, notification delivery or device behavior.

Subsequent owner report: both matching worker secrets saved in Edge and Vault. Secret values were not accessed; equality has not been verified by a live call.

Connected Samsung SM-S918B/R5CWB2MXQHZ: both recorded APK hashes matched Build-Artifacts.md. ADB install -r returned Success for Teen and Parent. Data was not cleared. Runtime walkthrough is still pending.

Owner reports family-events-push deployed through the development dashboard and legacy JWT verification disabled as instructed. The handler authenticates its worker-secret header. No successful invocation has been observed yet.

Owner applied phase10-schedule-family-events.sql and returned the expected row: jobname=petal-family-events-development, schedule=*/5 * * * *, active=true. This confirms the named retry job is configured and active; successful HTTP worker invocation and device delivery are not yet established.

Invocation follow-up: owner sees only parent-checkin-push and “swift worker,” not family-events-push. The prior deployment report therefore does not establish that the expected endpoint exists. The Cron/webhook target remains /functions/v1/family-events-push. Inspect the other function's exact slug and code before identifying it or changing routes. No successful worker invocation is confirmed.

Owner supplied the exact URL ending /functions/v1/swift-worker and the full deployed code. It matches the family-events worker, including PETAL_FAMILY_WORKER_SECRET and school routing. Confirmed deployment name: swift-worker. Prepared phase10-worker-route-fix.sql updates only the named family webhook function and retry job to that endpoint; the repair has not yet been applied. No secrets were supplied or accessed.

Owner applied phase10-worker-route-fix.sql and reported: jobname=petal-family-events-development, schedule=*/5 * * * *, active=true, retry_route_correct=true, webhook_route_correct=true. Both configured routes now target the confirmed swift-worker endpoint. Successful HTTP invocation remains unobserved.

Owner inspected swift-worker Invocations and reports HTTP200 on both POST entries. This confirms successful worker HTTP responses for those calls. Per-device FCM success, actual notification display, checked business RPC behavior and local alarm delivery are not established by these statuses.

Pending: controlled development acceptance and phone checks. Existing health worker is separate. Production is untouched.

## First phone report — 23 October 2026

Owner reports Parent and Teen notification controls enabled; fictional school item appears in both apps; school creation awarded no XP/coins. The expected Parent notice was not observed. About ten notices arrived and all opened Teen. Their channel/source is not yet identified; earlier Parent-opening notices also arrived during setup. Do not count this as a Parent-push pass or conclude recipient misrouting without source/registration evidence.

Owner also reports the morning Parent after-school-drop checkpoint arrived. This establishes that observed local checkpoint only, not the separate family-event FCM path.

Prepared phase10-notification-diagnostics.sql: read-only aggregate scope for exactly one Test Family 1 and the latest fictional permission-slip creation. It distinguishes source fanout, Parent device registration, delivery states and older queued events without returning credentials, tokens, identities or item text. Awaiting owner execution.

Owner identified the first failed read-only query as having been run in production. The correct development result reports exactly one family/item/create event; creator role Teen; two Parent notices and zero Teen notices for school creation; one active registered installation in each app with matching memberships; one pending Parent delivery for the scoped creation. Recent delivery aggregates include six delivered and eight pending task.assigned notices, plus fourteen older submission.reviewed notices and other older Teen results. This establishes correct school recipient fanout and identifies automatic duty-list/older-event traffic; the exact ten tapped notifications were not individually attributed.

Prepared forward-only migration018 / phase10-notice-coalescing-fix.sql: coalesces daily duty lists and catalogue batches per recipient, preserves source history, expires redundant notice entries, suppresses pre-enrollment delivery backlog per installation and prioritizes fresh events. Existing registration timestamps seed the enrollment cutoff; token rotation preserves enrollment, account/role rebind resets it. Not applied yet.

Android fixes prepared: one visible generic family update per family/app, role-specific title and no repeated alert on card update; explicit enable waits for confirmed family registration instead of reporting success from token/legacy health registration alone. These changes do not establish that registration was the original failure—the diagnostic shows both registrations active. New builds/installation evidence belongs in Build-Artifacts.md. Samsung was not connected at latest ADB check; new APKs are not yet installed.

## Repair deployment confirmed — 23 October 2026

Owner reports all four readiness checks true for phase10-notice-coalescing-fix.sql in Petal Quest Dev: grouped_notices_ready, grouped_fanout_ready, enrollment_cutoff_ready and fresh_delivery_priority_ready. No original upgrade was rerun.

Connected Samsung SM-S918B/R5CWB2MXQHZ: SHA-256 matched the prepared Teen 41F8C38F435DF58531F993453C8A829D2D933ED836403A2E73B2E908632FE1F1 and Parent 82238075F0983B8810DE44F340CD7CC7629D6C2691F2D51A2D748EF8D1C5F408 APKs. Sequential ADB install -r returned Success for both. No uninstall or data clear was performed.

Next acceptance: enable/retry notifications in both updated apps, leave Parent in background, request an edit to the existing fictional school item in Teen, and verify the Parent notification and pending change. Then approve in Parent and verify the Teen update. Physical display and delivery repair remain unverified until that walkthrough is reported.

## School notification repair acceptance — 23 October 2026

After migration018 readiness passed and both repaired APKs were installed in place, the owner completed the requested school-edit walkthrough and reports: separate notifications arrived, opened the correct apps, and everything worked as expected. Record the Parent-bound Teen edit request and the Teen-bound Parent approval notification/deep link as owner-observed passes on the same Samsung. This does not establish independent-device delivery, all event types, offline/reboot recovery or scheduled reminder boundaries.

## Remaining acceptance work started — 23 October 2026

Samsung connected; Android16/API36 confirmed. Both dev apps have POST_NOTIFICATIONS granted and alarm entries present. Only aggregate alarm counts were read, not app records. Alarm presence is not delivery evidence.

Added and executed core:reminders CheckpointPolicyTest: 10 tests, zero failures/errors/skips; Gradle testDebugUnitTest succeeded. Coverage: school break schedule, next-break/weekend carry-over, final November27 break, post-term cutoff, normal/Wednesday home times and end of Wednesday exception, pending text and Parent slots. Installed application behavior was not changed by adding these tests; no APK replacement is needed for this test-only addition.

Prepared supabase/tests/phase10-vacation-rollback.sql for owner execution in Dev: disposable actor plus seven days of real occurrence insertion triggers, previews/100 totals, excluded optional points, approved title changes, default boundary and unchanged original occurrence/manifest/wallet fingerprints. Complete transaction rolls back; live result pending. Does not test HTTPS authorization or a custom vacation schedule.

Offline completion/automatic refresh walkthrough and availability of other family phones were requested. Full follow-on steps are in Remaining-Phone-Checks.md. No result is assumed while answers are pending.

## Owner acceptance results — 23 October 2026

Offline submission/recovery: owner completed the requested offline duty submission, removal from Recents, reopen, reconnection, single Parent review and approval, then Teen return without manual refresh. Report: all correct; Teen shows approved and earning confirmed only on day finalization. Record offline queue persistence across app reopen, reconciliation and automatic/resume approval refresh as passed. This was not a device reboot, verified process kill or concurrent independent-phone test.

Vacation SQL: owner returned all 14 check rows true from phase10-vacation-rollback.sql, including deferred constraints, seven-day maximum100, excluded points unchanged, default November27/28 boundary, new occurrence snapshots and immutable rule points, original occurrences/manifests and all wallet events unchanged, deterministic previews, school-study removal and approved weekday titles. Record the rollback fixture as passed; it does not establish future real-clock activation or HTTPS role authorization.

Other family phones are unavailable per owner. Independent-phone delivery remains pending; do not ask to repeat availability during these Samsung checks. Remaining immediate phone work: local reminder delivery, snooze/dismiss, edit and offline reboot persistence; Parent Vacation UI preview. No pass inferred for unreported steps.

## Owner local reminder acceptance — 23 October 2026

Owner reports all seven requested local reminder steps passed: confirmed quiet/snooze defaults; created one-off reminder; received it offline with app in background; snoozed for the configured ten minutes then dismissed; edited the rule offline; rebooted/unlocked and received the edited reminder offline; deleted the fictional reminder and restored internet. Exact scheduled/observed timestamps were not supplied, so no precise delivery-latency guarantee is recorded. This pass covers the personal local reminder path, not every scheduled home/school/Parent checkpoint or finalization-suppression boundary.

Other two family phones remain unavailable. Independent-device installation, role enrollment, notification permissions, delivery to both Parents and reconnection acceptance remain outstanding. Parent Vacation UI previews were requested separately and are not included in the owner's numbered 1–7 pass; vacation database rollback checks already passed.
