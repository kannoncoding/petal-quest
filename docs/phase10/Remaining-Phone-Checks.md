## Final status — 23 October 2026

Phase10 is complete for the owner's accepted Samsung-only scope. Owner confirmed the final Parent Vacation previews, duties and points. See Completion-Report.md for the consolidated evidence and explicit rollout/regression deferrals. Earlier pending statements below are chronological; do not repeat completed upgrades or request other family phones. Phase11 is prepared in ../phase11/Preparation-Report.md. Production remains untouched.
## Current acceptance scope — owner decision, 23 October 2026

All preproduction phone acceptance uses the owner's Samsung, with the Teen and Parent apps and fictional Test Family 1. Do not request the girlfriend's or daughter's phones during development; the apps are a surprise. Their phones will first be enrolled when the apps and production projects/environments are ready for family use. Independent-device/version/battery behavior is deferred to that rollout and is not a Phase10 exit blocker. Do not record those unperformed tests as passed.

The owner will collect feedback over multiple days after rollout for subsequent fixes. This decision does not authorize premature production deployment or any production mutation. Preserve the existing development/production separation. This section supersedes older statements below requiring independent family phones for Phase10 completion.
# Remaining Phase 10 checks — 23 October 2026

Use fictional Test Family 1 only. Do not clear data, uninstall, change device clocks or open private health records. Independent-device acceptance is pending until the other phones are available.

## 1. Offline completion and automatic convergence

1. Open Teen Quests online; wait for confirmed current data.
2. Turn off Wi-Fi and mobile data. Keep USB connected if convenient.
3. Submit one unsubmitted duty. Expect queued offline.
4. Remove Teen from Recents, reopen and confirm the queue survives.
5. Restore internet, leave Teen open for up to two minutes.
6. Open Parent Review: exactly one submission should appear. Approve once.
7. Return to Teen without tapping Refresh. Expect the approved state, with no earned XP/coins for approval alone.

If today has no unsubmitted duty, stop; do not reopen a finalized day. Removing from Recents is not an Android force-stop or proof of process death. A normal reboot is the stronger separate persistence check.

## 2. Local reminder delivery, snooze, edit and reboot

After the offline completion check finishes:

1. Teen → Local reminders. Note current quiet hours and snooze: expected 22:00, 07:00 and 10 minutes. Do not replace previously customized choices silently.
2. Create a one-off personal reminder titled **Phase 10 offline reminder**, dated today, with a time at least five minutes ahead using HH:mm. Keep America/Costa_Rica and select no weekdays.
3. Turn off both Wi-Fi and mobile data. Press Home; remove Teen from Recents. Wait for its local reminder in the notification shade. Record scheduled/observed times and whether sound or only a shade entry appeared.
4. Expand the notification and tap Snooze. Expect it to disappear and return about ten minutes later, subject to Android delay. Tap Dismiss when it returns.
5. Reopen Local reminders offline. The personal rule and preferences should remain. Edit that reminder to another time at least five minutes ahead and save.
6. After the other phone work has finished, reboot the Samsung normally while offline. Unlock it. Do not use force-stop. Check that the edited reminder still appears around the new time. Record the observed delay.
7. Delete the fictional personal reminder, restore internet and reopen both apps. Confirm current family state returns. Personal reminder actions never complete scored duties or award points.

Home/school/checkpoint suppression is distinct from deleting a personal reminder. Observe the next actual scheduled checkpoint after a confirmed completion/finalization. Future Wednesday/term behavior also has policy tests; these do not prove OS delivery at future times.

## 3. Vacation allocation and history

Run the complete **supabase/tests/phase10-vacation-rollback.sql** in the development owner SQL Editor, including its final ROLLBACK. If prompted choose Run without RLS; the temporary result table explicitly enables RLS. Every check row should be true. It tests preview and actual insertion triggers with a disposable actor, then undoes the fixture and its events. If interrupted, issue ROLLBACK in the same SQL session.

The script checks the default schedule only and deliberately stops if Test Family 1 has custom vacation versions or an unexpected catalogue. Do not remove records to bypass that guard. Share the sanitized error for adjustment.

For the Parent UI, open Vacation and preview November 28, 2026 and November 30, 2026 (weekend/weekday). Expect maximum 100, no school study duty, unchanged excluded optional points and approved weekday title changes. Preview only; do not confirm a new vacation schedule for this check. Record whether it matches the SQL previews. Existing History and balances should remain unchanged.

## 4. Independent family phones

Each separate phone needs internet, the matching APK, notification permission and an authorized Test Family 1 role. USB is needed only if installing through this PC; normal use and delivery work without USB. Record Android version and battery restrictions for each phone.

With Teen on one phone and each Parent on a different phone:

1. Enable notifications in all three installations. Leave both Parent apps in background.
2. Teen requests one school-item edit; both Parents should receive their own notice. Opening one must not consume the other phone's notice or receipt.
3. One Parent approves; the other Parent and Teen converge on the same outcome without duplicate history or XP.
4. Keep one Parent offline for a second request. The online Parent should receive it; reconnecting the other must recover its own eligible update and current state.
5. Complete one unscored school item; reminders for it stop after confirmed synchronization.

Do not reuse one account's session files or extract tokens to simulate separate people. Existing invitation/pairing flows supply the roles. If the other phones are unavailable, this remains an explicit outstanding check, not a Samsung pass.

## Evidence so far

- School creation and Parent change approval synchronize without XP; both repaired notification directions and app destinations passed by owner report.
- Samsung is Android 16 / API 36. POST_NOTIFICATIONS is granted for both dev apps. Both packages have alarm entries; counts do not establish delivery.
- Ten CheckpointPolicyTest unit tests passed, zero skipped/failures/errors. They cover school break times/carry-over/cutoff, normal and Wednesday home times, pending text and Parent slot times. No Android alarm/FCM runtime claim follows from these tests.
- Offline/reboot/snooze, vacation SQL/UI results and independent phones remain pending until observed.

## Owner acceptance results — 23 October 2026

Offline submission/recovery: owner completed the requested offline duty submission, removal from Recents, reopen, reconnection, single Parent review and approval, then Teen return without manual refresh. Report: all correct; Teen shows approved and earning confirmed only on day finalization. Record offline queue persistence across app reopen, reconciliation and automatic/resume approval refresh as passed. This was not a device reboot, verified process kill or concurrent independent-phone test.

Vacation SQL: owner returned all 14 check rows true from phase10-vacation-rollback.sql, including deferred constraints, seven-day maximum100, excluded points unchanged, default November27/28 boundary, new occurrence snapshots and immutable rule points, original occurrences/manifests and all wallet events unchanged, deterministic previews, school-study removal and approved weekday titles. Record the rollback fixture as passed; it does not establish future real-clock activation or HTTPS role authorization.

Other family phones are unavailable per owner. Independent-phone delivery remains pending; do not ask to repeat availability during these Samsung checks. Remaining immediate phone work: local reminder delivery, snooze/dismiss, edit and offline reboot persistence; Parent Vacation UI preview. No pass inferred for unreported steps.

## Owner local reminder acceptance — 23 October 2026

Owner reports all seven requested local reminder steps passed: confirmed quiet/snooze defaults; created one-off reminder; received it offline with app in background; snoozed for the configured ten minutes then dismissed; edited the rule offline; rebooted/unlocked and received the edited reminder offline; deleted the fictional reminder and restored internet. Exact scheduled/observed timestamps were not supplied, so no precise delivery-latency guarantee is recorded. This pass covers the personal local reminder path, not every scheduled home/school/Parent checkpoint or finalization-suppression boundary.

Other two family phones remain unavailable. Independent-device installation, role enrollment, notification permissions, delivery to both Parents and reconnection acceptance remain outstanding. Parent Vacation UI previews were requested separately and are not included in the owner's numbered 1–7 pass; vacation database rollback checks already passed.
