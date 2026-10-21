# Phase 6 verification — 2026-10-21

Status: **Phase 6 development foundation accepted as complete, 2026-10-21**. See Completion-Report.md for current scope and evidence. The chronological sections below retain earlier states; their pending statements are superseded by the final acceptance entry.

## Executed evidence

| Environment | Passed | Failed | What this establishes |
| --- | ---: | ---: | --- |
| Connected Samsung, Android 16 / API 36 | 10 | 0 | Real Android Keystore/session persistence, Room cache/queue persistence, account/endpoint/logout isolation, rejected payloads and corrupted-session recovery in a separate verification package. |
| Disposable local PostgreSQL (PGlite 0.5.11) | 35 | 0 | All seven migrations apply; RLS/grants, two-family isolation, role/self-award denials, idempotent submission/approval, single accounting/outbox effects, pairing/revocation and bounded recurrence scenarios. |
| Actual development Supabase HTTPS API | 13 | 0 | Unauthenticated denials, private schema isolation, unpaired anonymous JWT contract access, empty family/work reads, and denied parent/role/XP/approval operations. |

Machine reports: `backend-local-results.json` and `backend-live-public-results.json` in this directory. Samsung instrumentation XML: `Android Dev/verification/build/outputs/androidTest-results/connected/debug/TEST-SM-S918B - 16.xml` (10 tests, zero failures/errors/skips); detailed case descriptions are in Android-Verification.md.

The phone suite used application ID `petalquest.verification`, synthetic data and no Internet permission. It did not read or clear either signed-in Teen or Parent app's private data. Health coverage is reserved-file retention only, not a completed health feature. One new unpaired anonymous Auth identity was created for live checks and signed out; its Auth row remains. No family or scoring records were created by that live probe.

The owner separately confirmed first-parent family creation, teen pairing and second-parent invitation acceptance in Test Family 1. That is live UI evidence, separate from automated test results.

## Defect found and repaired locally

Executing a valid submission uncovered a PostgreSQL name-resolution error in both submission and approval receipt updates (`missing FROM-clause entry`). Pairing uses different functions, so successful enrollment did not expose it.

Prepared forward migration:

`Android Dev/supabase/migrations/202610210001_phase6_receipt_fix.sql`

It replaces only the two private function definitions, uses an unambiguous local receipt variable, preserves the authenticated execution grants, and requests API schema reload. It does not delete family data or modify scoring rules. All 35 local cases pass with this patch. The owner subsequently reported **Success. No rows returned** after applying this patch to the hosted development database. Deployment is accepted by owner evidence; valid hosted submission/approval has not yet been exercised. Production is untouched.

The initial deployment bundle was regenerated with all seven migrations for future fresh installations. **Do not rerun that initial bundle against the existing development database.** Apply only the forward patch described in Owner-Actions.md.

## Evidence still required before Phase 6 closes

1. Development receipt patch: completed by owner-reported SQL success; positive hosted submission/approval behavior remains part of the checks below.
2. Authenticated paired-user checks against the deployed service: positive own-family reads, cross-family denials and teen self-award denial with actual paired identities. Existing live unpaired checks do not prove paired isolation.
3. Actual simultaneous parent approvals from separate connections, duplicate retry reconciliation and exactly one committed effect. PGlite runs on one connection; its sequential two-parent/idempotency cases do not establish concurrent lock behavior.
4. Hosted revocation/replacement and real disconnected/reconnected submission reconciliation. Android queue persistence passes, but no end-to-end offline retry is claimed.

There are no administrator credentials or existing paired-account credentials available to the coordinator. The publishable key cannot deploy migrations or impersonate the paired users. Passwords and tokens must remain off chat; any later credentialed checker must accept them privately and avoid saving them. A disposable second fictional family will be needed for live cross-family verification; do not alter real family records for testing.

The connected Samsung is sufficient for the next checks. No new installation is required from the owner for this SQL repair. The other two family phones can wait; their compatibility has not been verified. Android 7 / API 24 remains the application minimum.

## Implementation boundaries

Approval contributes raw points only; daily finalization, spendable XP/coins, complete quests/rewards interfaces, health entry/encryption/lock, reminder delivery and full account-management screens remain later-phase work. Unspecified late/correction/effective-date policies remain blocked. These tests do not approve missing business decisions or complete those later features.


## Acceptance tooling readiness

The owner confirmed three dedicated fictional parent users are ready. The PC private-credential checker has passed syntax/parser and seven mocked behavioral groups; no hosted paired pass is inferred. Independent QA findings were corrected. The separate liveVerification debug APK built successfully, installed and opened on the Samsung (SHA256 6C27326931C992197B32762C2CACC9BD498E543A6569A8CE923B2CF57B054476). Existing teen/parent apps were untouched. Owner private credential entry is now pending in the opened PowerShell window. See Live-Acceptance-Handoff.md for exact PC, generated read-only outbox audit and phone steps. Live results have not been produced yet.

## First credentialed hosted attempt

At 2026-10-21 16:53:51 UTC, the checker stopped in its prerequisite sequence before recording acceptance passes or generating an outbox audit. The report did not distinguish authentication/network/setup failure. This is a failed attempt, not an acceptance pass, and its cause is not yet established. Sanitized evidence is archived in live-acceptance-attempt-1.json. The coordinator added per-parent sign-in results, safe stage labels and allowlisted HTTP/error-code diagnostics; simulated success and deliberately failed authentication/redaction tests pass. Credentials were not retained, so owner re-entry is required for the diagnostic retry. No phone offline acceptance has been executed yet.

## Windows PowerShell launcher correction

The second owner screenshot showed a launcher failure before the Node runner. Reproduced under Windows PowerShell 5.1: ProcessStartInfo lacks StandardInputEncoding. The coordinator replaced this unsupported property with explicit UTF-8 bytes through StandardInput.BaseStream and added a runtime preflight before credential entry. Added a no-network/no-file self-check mode, executed the complete launcher under Windows PowerShell 5.1 for both success and deliberate authentication failure, including Unicode synthetic passwords; both expected outcomes passed. No live credential replay was possible because credentials were not retained. The first actual hosted failure remains undiagnosed pending the next live run.

## Actual paired hosted acceptance — 2026-10-21 11:09 Costa Rica

Saved report confirmed 10 PASS groups (three parent authentications and seven paired-service acceptance groups), zero FAIL, one UNVERIFIED private-outbox check. Actual development calls verified populated family isolation, direct role/XP denial, valid patched submission/approval receipts, duplicate/replay behavior, concurrent parent HTTPS approvals producing one public decision/contribution effect with zero spendable XP/coins, and old-identity revocation plus stable-actor/history replacement. Evidence archived in live-acceptance-results.json. This supersedes earlier statements that paired checks are pending. Two remaining acceptance items: owner-only SELECT audit of one pending and one approved outbox event, and the Samsung real disconnected-queue/process-restart/online-reconciliation flow. No real-family sessions were touched.

## Private-outbox audit accepted

Owner supplied development SQL Editor screenshot showing submission.approved event_count=1 and submission.pending event_count=1 for the generated fixture audit. Private-outbox uniqueness is accepted by owner-console evidence. The only remaining Phase 6 service acceptance item is the Samsung disconnected queue, actual process restart and online acknowledgement/replay test. Keep USB connected for coordinator force-stop/relaunch; disable Wi-Fi and mobile data for the offline steps, with USB tethering off. No Phase 6 completion claimed yet.

## Final Samsung acceptance and phase closure

Owner first confirmed QUEUED OFFLINE, then the coordinator used ADB to force-stop and reopen only petalquest.verification.live while connectivity remained disabled. Owner confirmed RESTART VERIFIED OFFLINE, pending 1. After reconnecting, owner confirmed all requested remaining results as expected: exact receipt acknowledged/pending 0, followed by replay confirming one server submission. These final phone assertions are owner-reported; no separate exported phone JSON was inspected. Combined with the previously saved hosted acceptance report and owner-console outbox screenshot, this closes the agreed Phase 6 development foundation exit checks. No Phase 6 owner action remains. Deferred phone compatibility, production rollout, later-phase functionality and retained synthetic fixtures are listed in Completion-Report.md.
