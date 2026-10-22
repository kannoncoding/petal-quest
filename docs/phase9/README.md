# Phase 9 status — 22 October 2026

Status: prepared locally, both APKs built, source-reviewed. Not deployed, installed or physically accepted. Phase9 remains open. The phone was intentionally unavailable; no installation was attempted.

## Prepared implementation

- Parent family dashboard with current/saved-state labels, original task dates, rule snapshots, review notes and actor history.
- Approve/return/reject with submission-generation checks, explicit batch preview and preserved retry payloads. Stale Parents cannot silently overwrite another review cycle.
- Parent-triggered finalization with server-calculated preview; unsubmitted0 and pending-review resolution. Confirmed earning and Coin changes occur only on server acknowledgement.
- Fixed tracker deductions/reversals and explicit reasoned corrections using current day edit generations. Full-state nonlinear earnings differences may create Coin debt; future earnings repay it and spending approvals require sufficient Coins.
- Exact-weight excused virtual allocation, bounded bonus offers, durable Teen bonus completion, Parent approval before sealing and persistent conversion-day no-doubling provenance.
- Appeal resolution against actual accounting revisions without reopening the deadline or granting arbitrary scores.
- Rewards: saved-price approval, fulfillment, free pending cancellation and once-only approved/unfulfilled refund. Existing29 reward entries can be edited with future versions; creating new reward keys is not implemented.
- Achievement/cash/privilege request confirmations with immutable award source, saved achievement XP, explicit cash amount/reason and audit. No automatic payments, app permission control or inferred consistency awards.
- Full duty-set editor: add/archive duties, daily/weekly recurrence, points/deadlines and future effective date. Every weekday must total100; changes commit atomically, preserving historical snapshots and exact expected day sets.
- Shared reflection notes: Parents edit with optimistic versions and history; Teen read-only. Private health remains separate and existing limited Parent health controls are retained.
- Password recovery: emailed one-time recovery code, transient credentials, authenticated password update and normal sign-in afterward. Requires the prepared development email-template update.

## Source and build evidence

Developers and independent QA reviewed authorization, explicit RLS, family isolation, source/request identity, stale generations, financial provenance and commit-time sealing. Coordinator additionally reviewed full actual/protected/converted-score arithmetic, debt deltas, legacy materialization gates and recovery lifecycle. No new automated tests or SQL runtime tests were added or run. Read Review.md and Expected-Accounting-Examples.md for the boundaries of this evidence.

Final Gradle :app:assembleDebug :parent:assembleDebug: BUILD SUCCESSFUL in11 seconds;167 tasks (8 executed,159 up-to-date). Local log: Documentation/Phase9/build-debug.local.log.

- Teen APK SHA256 F9D50116EAE2635B60D03497956FAC3C69B308F8CEF1F1A3F0EDDFF485B1CC9C
- Parent APK SHA256 BF455919B94D85A300294B410B7920C4223E2ED6F15C781C0C322205CEF09F78

## Owner actions before/after reconnecting

1. Without the phone: apply the reviewed forward SQL file in Petal Quest Dev only, as described in Owner-Actions.md. Do not rerun an initial deployment bundle. No new key, Firebase project or production change is required.
2. Without the phone: configure only the development password-recovery email template using Recovery-Setup.md, if ready to exercise recovery.
3. Later reconnect/unlock the Samsung for in-place installation of both prepared apps. Keep existing app data; do not uninstall/reset.
4. Use Acceptance-Checklist.md for fictional-data verification. Two independently authenticated Parent sessions are needed for the concurrency gate; two physical family phones are one option, not a requirement for preparing code. The other phones/Android versions remain unverified until available.

## Remaining limits

Actual deployment, RLS behavior, accounting, concurrent requests, retries and phone interaction remain unverified. The remaining Phase8 finalized-result/review/appeal checks can be exercised through these Parent screens after deployment/install; they are not retroactively marked passed. Recovery needs a receivable owner-controlled development inbox; example.com QA accounts cannot receive mail. Optional Parent quick unlock is not enabled; ordinary authenticated sign-in remains the authority.

Approved-bonus reversal and reopening cancelled offers are unavailable pending explicit lifecycle rules. Fulfilled reward reversal is unavailable. Parent notes do not alter sealed scores; shared notes are visible to the Teen. Transactional outbox events are prepared, but delivery for these new topics and contextual reminders remain Phase10. No production deployment or personal tracker-history import was performed.
