## Final status — 23 October 2026

Phase10 is complete for the owner's accepted Samsung-only scope. Owner confirmed the final Parent Vacation previews, duties and points. See Completion-Report.md for the consolidated evidence and explicit rollout/regression deferrals. Earlier pending statements below are chronological; do not repeat completed upgrades or request other family phones. Phase11 is prepared in ../phase11/Preparation-Report.md. Production remains untouched.
## Current acceptance scope — owner decision, 23 October 2026

All preproduction phone acceptance uses the owner's Samsung, with the Teen and Parent apps and fictional Test Family 1. Do not request the girlfriend's or daughter's phones during development; the apps are a surprise. Their phones will first be enrolled when the apps and production projects/environments are ready for family use. Independent-device/version/battery behavior is deferred to that rollout and is not a Phase10 exit blocker. Do not record those unperformed tests as passed.

The owner will collect feedback over multiple days after rollout for subsequent fixes. This decision does not authorize premature production deployment or any production mutation. Preserve the existing development/production separation. This section supersedes older statements below requiring independent family phones for Phase10 completion.
# Phase 10 acceptance — in progress

The numbered list is the acceptance plan; dated evidence below records observed passes. Unreported steps remain pending. Use fictional Test Family 1 and dedicated QA accounts. Preserve installed data. Do not change the device clock or use private health information.

## Code and cloud

- Android compilation: both debug variants have compiled; final artifact hashes belong in Preparation-Report.md after the last build.
- Database migration: owner applied the atomic upgrade and reported passing schema/readiness checks. Per-role RLS behavior and business RPC acceptance remain pending.
- New Edge worker: deployed as swift-worker; webhook/Cron routes repaired and confirmed. Owner reports HTTP200 and, after migration018 and APK repair, successful Parent/Teen school-change notifications opening the correct apps. Other event types and independent-device delivery remain pending.
- Existing pain-check-in path: preserved in source; Phase 10 regression delivery not repeated.

## Phone walkthrough after development deployment

1. Enable family notifications on each signed-in installation; verify permission refusal leaves tasks and reminders usable.
2. Submit a fictional Teen duty. Confirm Parent receives a generic review notification. Review it while Teen is open; confirmed status should refresh automatically, without awarding XP for approval alone.
3. Repeat with a second Parent installation; verify both converge after one decision, and one unreachable installation does not complete another installation's delivery receipt.
4. Queue Teen completion offline, close/reopen, then reconnect. The exact request should reconcile once. Repeat after a normal device reboot; retain rejected requests visibly for review.
5. Queue only an explicitly confirmed Parent decision with uncertain receipt. Reconnect and verify stable replay, one outcome, and correct failure feedback. Unconfirmed dialog choices must never dispatch.
6. Revoke or replace access. Verify stale push, cached actions, deep links and previous account installations cannot reveal another family's updates or mutate results. Test online and offline logout.
7. Create, edit, dismiss and snooze a personal reminder. Confirm quiet hours 22:00–07:00 and snooze 10 minutes; edits to preferences survive refresh. Permission/channel denial should not erase reminder records.
8. Sync an assigned routine, disconnect, and confirm local scheduling survives app restart and device reboot. Reconnect after a routine edit/removal and verify old alarms are replaced.
9. For yesterday's published unsealed result, verify the Teen 17:00 review reminder routes to that date; a sealed or absent result must not produce it. Check stale notification taps after sealing.
10. Check battery saver, timezone/clock changes, app update, missed push and resume refresh. Record actual delays. Force-stop and powered-off delivery are not promised.
11. Check Parent checkpoints for both parents every day, suppression after finalization, Wednesday shifts through November27 and final21:10 review. A day with no materialized tasks should still get an unfinalized reminder. Offline devices use the last confirmed state.
12. Inspect Special achievements at the bottom of Quests: shortcut, card spacing, request dialog, pending state, Parent confirmation and existing award history. No award should happen merely from a Teen request.
13. School: both roles create; Teen completion cancels reminders; Teen edit/removal preserves the original until Parent decision. Check stale versions, concurrent Parents, duplicate requests, offline/restart replay, revoked/cross-family denial and audit facts. Verify no XP changes. Check weekdays, break carry-forward,06:55 quiet exception and November27 expiry.
14. Vacation: preview all seven days, maximum100, excluded points unchanged, school duties omitted and correct changed titles. Check default November28 activation, future vacation/return versions, stale requests, replay and old snapshots/XP unchanged. Calendar boundaries need controlled development fixtures or real observation; do not change live family/device clocks.

## Required devices

The owner's Samsung is the sole preproduction acceptance device. Independent family-phone delivery, Android-version and battery behavior checks are deferred to the production family rollout by explicit owner decision; they do not block Phase10.

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
