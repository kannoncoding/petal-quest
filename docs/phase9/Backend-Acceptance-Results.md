# Phase 9 backend acceptance — baseline

Live development HTTPS run completed 22 October 2026 at 12:06:21 Costa Rica time (18:06:21 UTC). Source: local sanitized runner report, corroborated by owner screenshot. Dedicated fictional QA families only; no owner family or health data accessed. All temporary Teen memberships revoked and local test sessions logged out without reported cleanup failures.

Result: 15 PASS, 0 FAIL, 9 UNVERIFIED. Exit2 represents outstanding gates, not a failed assertion. These observations cover server APIs and do not replace the Android walkthrough.

| Check | Result | Remaining limitation |
| --- | --- | --- |
| Parent A authentication | PASS |  |
| Parent B authentication | PASS |  |
| Parent C authentication | PASS |  |
| contract3 and complete immutable 100 point manifest | PASS |  |
| parent APIs deny teen and foreign family authority | PASS |  |
| checked review return, stale generation, concurrent single decision | PASS |  |
| shared notes authority, optimistic version, replay and history | PASS |  |
| ordinary100 publication pays200; replay does not duplicate | PASS |  |
| appeal approval requires a correction; rejection awards nothing | PASS |  |
| actual99 earns99; restoring ordinary100 earns200 | PASS |  |
| 100 to95 deduction appends nonlinear minus105; reversal restores once | PASS |  |
| 85 pays85,80 pays0, reversal credits85 | PASS |  |
| bonus provenance prevents perfect doubling and bounds conversion | PASS |  |
| reward saved price, approval, cancellation refunds once, fulfillment is final | PASS |  |
| published correction creates coin debt and blocks spending | PASS |  |
| catalogue effective date, optimistic edit and saved price after effective edit | UNVERIFIED | Future catalogue changes require a dedicated family schedule across server dates; this runner does not alter shared QA catalogue versions. |
| competing approve versus return decisions | UNVERIFIED | Current concurrent check covers approve versus approve only. |
| reward transition races | UNVERIFIED | Sequential approval, refund and fulfillment checks do not prove competing transition races. |
| revoked Parent session authority | UNVERIFIED | Cleanup revokes only newly created Teen memberships; existing QA Parent memberships are preserved. |
| lost response and process restart recovery | UNVERIFIED | Immediate same-request replay does not simulate a lost HTTPS response or process restart. |
| score floor below zero | UNVERIFIED | Threshold80 pays0 is covered; negative raw score clamping is not exercised. |
| cash and privilege confirmations | UNVERIFIED | No explicit cash amount or privilege confirmation is exercised. |
| seal boundary and appeal expiry | UNVERIFIED | Requires real server seal passage; no privileged time manipulation is used. |
| private outbox payload and uniqueness | UNVERIFIED | Requires separate read-only owner SQL audit; public parent credentials cannot inspect private outbox. |

The review-audit repair was applied before this passing run. The previous failed authentication attempt and pre-repair phone return remain historical failures; this report records the later actual success. Phase9 is not yet fully accepted.

## Second live batch — 22 October 2026,12:20:16 Costa Rica

14 PASS,0 FAIL,6 UNVERIFIED. These are additional run results, including three repeated authentication checks; do not call29 run passes29 unique scenarios. Three new disposable Teen memberships were revoked and sessions logged out without reported cleanup failures. Separate-process replay is a Node/API test, not an Android restart test.

| Check | Result | Remaining limitation |
| --- | --- | --- |
| Parent A authentication | PASS |  |
| Parent B authentication | PASS |  |
| Parent C authentication | PASS |  |
| approve versus return race commits one checked generation; both dashboards agree | PASS |  |
| negative raw score clamps actual/protected/earned to zero without negative earnings | PASS |  |
| cash explicit amount and privilege confirmations are audited/idempotent and award no coins | PASS |  |
| reward approval race debits saved price exactly once | PASS |  |
| competing reward approval and cancellation has at most one debit/refund | PASS |  |
| competing fulfilled versus cancellation preserves one terminal outcome and wallet amount | PASS |  |
| discarded receipt and separate Node process restart replay one durable request | PASS |  |
| assigned routine optimistic versions, future snapshot, isolation and inactive cleanup | PASS |  |
| future complete task catalogue validates total, stale version and immutable current snapshots | PASS |  |
| appeal approval references a later correction and does not itself change accounting | PASS |  |
| unsubmitted complete day pays0; actual80 virtual20 pays0; conversion85 then100 never doubles | PASS |  |
| revoked Parent old JWT authority | UNVERIFIED | Public revoke leaves an inactive membership; public invite refuses any existing membership. Reusable QA Parent B cannot be restored safely; requires disposable fourth confirmed Parent or a reviewed restoration API. |
| real future task and routine activation | UNVERIFIED | Future-date dashboard previews and unchanged catalogue writes do not prove materialization after the server date advances. |
| saved reward price after catalogue activation | UNVERIFIED | Requires real future effective server date; future unchanged task save does not prove reward activation. |
| Android process restart and device response loss | UNVERIFIED | Separate Node processes verify server request replay only; Android durable outbox/device restart needs device evidence. |
| seal boundary and appeal expiry | UNVERIFIED | Requires real server seal passage; no privileged clock manipulation. |
| private outbox payload and uniqueness | UNVERIFIED | Run generated read-only owner audit separately. |

### Subsequent owner outbox audit

Owner ran the read-only baseline-scoped audit and reported all11 aggregate boolean checks true. Every listed immutable source had exactly one event with its exact minimal payload. No duplicate topic/source or unexpected scoped event was found; the one resubmission and bonus-submission counts matched. Both anon and authenticated had0 readable private relations; outbox RLS was enabled. This closes the baseline outbox gate only, not FCM delivery or stage2-source payload auditing.

## Subsequent owner-console fixtures

| Fixture | Owner result | Evidence limit |
| --- | --- | --- |
| Revoked Parent authority |10/10 boolean checks true | Authenticated database role/claims; no real signed-JWT HTTP replay |
| Sealing deadline |14/14 boolean checks true | Synthetic five-second deadline crossed by real clock; no normal midnight-formula execution |
| Activated versions/saved prices |8/8 check rows true | Already-effective synthetic records; no literal midnight passage |

All fixture scripts terminate with ROLLBACK and target exact fictional QA identities only. The sealing table was pasted twice initially and counted once; revocation was subsequently supplied distinctly. Activation was supplied separately with its correct two-column output. Source checks and partial results were not substituted for these observed outputs.