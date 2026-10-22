# Phase 9 status — 22 October 2026

Status: COMPLETE for the agreed development/family scope on 22 October 2026. Implementation, development upgrades, both APK installations, live service checks, controlled owner-console fixtures and final Samsung walkthrough accepted. Existing data retained. Email recovery is explicitly owner-deferred. Verification limits below are retained; no production deployment is claimed.

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
- Assigned routine schedules: separate versioned Parent editor with titles, local times, Sunday-based recurrence, future effective dates and archive state; Teen reads date-resolved snapshots. No XP, approvals or notification delivery. Migration013 owner-confirmed: routines_ready and rls_enabled true; live schedule checks pending.
- Shared reflection notes: Parents edit with optimistic versions and history; Teen read-only. Private health remains separate and existing limited Parent health controls are retained.
- Password recovery: deferred by owner for private family use. Prepared code is retained, but the Parent recovery entry point is hidden. No SMTP or recovery email check is required to close Phase9; owner-managed account administration is the chosen approach.

## Source and build evidence

Developers and independent QA reviewed authorization, explicit RLS, family isolation, source/request identity, stale generations, financial provenance and commit-time sealing. Coordinator additionally reviewed full actual/protected/converted-score arithmetic, debt deltas, legacy materialization gates and recovery lifecycle. That initial source review did not execute tests. Subsequently the explicitly authorized live HTTPS baseline runner completed15 PASS with9 outstanding gates; see Backend-Acceptance-Results.md. Read Review.md and Expected-Accounting-Examples.md for the boundaries of this evidence.

Final Gradle :app:assembleDebug :parent:assembleDebug: BUILD SUCCESSFUL in11 seconds;167 tasks (4 executed,163 up-to-date). Local log: Documentation/Phase9/build-debug.local.log.

- Teen APK SHA256 F0515358E95C2366702014A58FB7A4279AA3D8ED519E65744C3B9F065B2EB491
- Parent APK SHA256 4C972B4E6EA53D8FB011457127832AE6D90BA1060F3F81A8F5104AFD778140E8

## Owner actions before/after reconnecting

1. Development SQL upgrade completed with the expected five schema flags. Do not rerun the forward upgrade or an initial deployment bundle.
2. Email recovery and SMTP deferred by owner; no email setup required.
3. Completed: both apps installed in place on the Samsung. Keep existing app data; do not uninstall/reset.
4. Use Acceptance-Checklist.md for fictional-data verification. Two independently authenticated Parent sessions are needed for the concurrency gate; two physical family phones are one option, not a requirement for preparing code. The other phones/Android versions remain unverified until available.

## Remaining limits

Schema deployment is owner-confirmed. Baseline live API checks passed for authority/isolation, accounting thresholds, approve/approve concurrency and retry identities; other races, boundary and phone checks remain open. SMTP and app-based recovery are owner-deferred, not completion blockers. The remaining Phase8 finalized-result/review/appeal checks can be exercised through these Parent screens after deployment/install; they are not retroactively marked passed. The retained, deferred recovery implementation would need custom SMTP and a receivable development inbox if enabled later. Optional Parent quick unlock is not enabled; ordinary authenticated sign-in remains the authority.

Approved-bonus reversal and reopening cancelled offers are unavailable pending explicit lifecycle rules. Fulfilled reward reversal is unavailable. Parent notes do not alter sealed scores; shared notes are visible to the Teen. Transactional outbox events are prepared, but delivery for these new topics and contextual reminders remain Phase10. No production deployment or personal tracker-history import was performed.

## Current acceptance

- All three development forward upgrades are owner-confirmed: core Phase9, assigned routines013 and review audit repair014. Do not rerun those upgrades for tests.
- Baseline live HTTPS QA:15 PASS,0 FAIL,9 initially unverified. Second batch:14 PASS,0 FAIL,6 initially unverified (three login checks repeat). Exact coverage and limits are in Backend-Acceptance-Results.md.
- Owner read-only baseline outbox audit: all11 booleans true, correct source uniqueness/minimal payloads and0 private relations readable by anon/authenticated. This closes that baseline gate; business push delivery remains Phase10.
- Owner phone return/note/resubmission/approval now matches in both apps. Approval alone leaves XP/coins unchanged. Owner published78 actual points (correctly0 earned), then confirmed all published information displays correctly in both apps while submitting further work. Do not invent an unreported final total.
- Latest Teen Quests screen includes today's published result card and link to full history; Gradle build passed and APK installed in place. Latest complete hashes are above. Parent error feedback and foreground refresh are installed. No app data was cleared.
- Owner rollback-only results: revoked Parent DB authority10/10 true; synthetic sealing14/14 true. Controlled activation/saved-price fixture passed8/8 true. Remaining: final staged Parent phone observations (deduction/reversal, notes, reward debit/refund and offline restart/reconnect). These fixtures use temporary result tables with explicit RLS. Run whole scripts through ROLLBACK; the SQL-editor auto-RLS wrapper is unnecessary.
- GitHub commit/push explicitly approved by owner. Final required Parent phone evidence has now been supplied; Phase9 is complete to the documented scope and verification limits.
Database evidence is complete to the documented method limits. Owner confirmed all four final Parent phone checks passed. Phase9 is complete to the documented scope and verification limits.

## Final owner acceptance

Owner confirmed all final checks passed: deduction/reversal restored totals, Parent reflection was Teen-readable without editing, reward approval/cancellation debited/refunded once without reducing earned XP, and Parent offline close/reopen showed saved read-only facts then refreshed correctly after reconnection. No required owner action remains for this Phase9 scope. See Acceptance-Report.md for exact evidence and method limits. Phase10 notification/synchronization work has not started.