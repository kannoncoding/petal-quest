# Phase 8 requirements — 21 October 2026

Status: approved task/deduction/history requirements recorded; Phase8 app implementation is pending. Source: owner instructions and performance-table attachment, plus the Phase3 tracker extract. The original tracker snapshot and live Google Sheet are unchanged.

## P8-001 — task changes, XP unchanged

| Variant / stable ID | New task | XP | Due time |
| --- | --- | ---: | --- |
| Weekday duty-wd-002 | 🎒 Lunchbag + Shower + Room | 11 | 16:00 |
| Weekday duty-wd-003 | 📚 Homework/Study + HighSchool Pendings + BagPack preparation + review | 12 | 17:30 |
| Weekday duty-wd-004 | ⚠️ 2nd Attitude Check + mouth piece check | 15 | Unspecified, unchanged |
| Weekend duty-we-005 | ⚠️ 2nd Attitude Check + mouth piece check | 15 | 17:00 |
| Weekday duty-wd-005 | ➡️ Next Day Prepare + Room clean up | 11 | 18:00 |
| Weekday/weekend duty-wd-006 / duty-we-006 | ✨ House Help + meditation/reading | 11 each | Unspecified, unchanged |
| Weekday/weekend duty-wd-007 / duty-we-007 | 🌱 Water plants | 1 each | Unspecified, unchanged |

Combined activities remain one duty with the existing combined XP allocation. Reading/Bible is replaced by watering plants, not added as a second duty. Other duties, schedules, XP, the weekend research override and day totals remain unchanged. Historical occurrences retain their original labels and rule snapshot; a deployment effective date must be established before activating this revision.

## P8-002 — Parent-entered deductions

Either authorized same-family parent may enter deductions while the target day is unsealed. Owner explicitly reaffirmed sealed days are final. The backend must check seal state at commit, not just when an editor opens. The Teen app cannot create or authorize deductions.

Preserve the verified tracker catalog: dirty lunchbag 5; torn clothes 20; did not follow instructions 6; forgot towel/clothes for shower 4; messy/dirty items 5. More than one accountability issue can contribute deductions on the same day. Each intentional entry has its own stable ID; retries must not duplicate it. Record parent actor, target day, deduction type, point magnitude, rule version and timestamp in authorized family history. Score retains its zero floor; apply the existing earnings formula, not a flat subtraction from earned coins that bypasses the 85-point/perfect-day thresholds.

Finalized-but-unsealed result adjustment uses the approved scoring rules. Negative-balance/debt handling for corrections after coins were spent remains a previously documented decision to settle before enabling that edge case; do not silently invent a policy. No new arbitrary/custom deduction amounts are authorized by this request.

## P8-003 — shared history and daily performance icons

Both apps must allow browsing prior months, weeks and days, with day detail for duties, reviews, deductions, actual points, excused/converted points, earned XP/coins and result/seal status. Family access remains authorized and isolated; notes from the private health journal do not enter this history. Costa Rica dates and Sunday-start weeks apply. Display pending/finalized/sealed status explicitly; do not represent an unfinished or missing result as a confirmed bad day. Keep historical rule versions; edits must not relabel or recalculate sealed days.

Owner confirmed the day icon uses protected score: actual points plus remaining excused virtual points after deductions (deduct only once). XP/coin earnings still require at least 85 actual points. Virtual-conversion days never receive the perfect-day doubling bonus. A protected score of 100 may therefore show Exceptional Day while earnings remain zero; show actual score, virtual protection and earnings separately to explain this.

| Protected score | Icon | Day type |
| --- | --- | --- |
| 100 | 🌟 | Exceptional Day |
| 96–99 | 💎 | Amazing Day |
| 91–95 | 🏆 | Excellent Day |
| 90 | ✅ | Passed Day — Good Day |
| 85–89 | ⚠️ | Almost Passed |
| 75–84 | 🟠 | Needs Improvement |
| 60–74 | 🔴 | Poor Day |
| 0–59 | ⛔ | Bad Day |

Use both icon and readable label; do not rely on color alone. These are daily score categories, not the available-coin rank or an invented monthly rank. Month/week navigation does not define a new monthly-average ranking formula.

## Phase placement

Phase8 implements Teen tasks, submission/review status, confirmed balances, rewards and history consumption. Include authoritative deduction facts and protected-score day summaries in shared service contracts now. Phase9 implements Parent task/rule editors, deduction entry and Parent history UI. Phase10 completes contextual reminders and broader synchronization/notification behavior. Do not claim these new screens or deductions are already deployed.

## P8-004 through P8-007 — follow-up decisions

Confirmed 21 October 2026:

- P8-004: Activate revised tasks today in Costa Rica while preserving existing submitted/finalized records and historical snapshots.
- P8-005: Teen may submit late work, upload offline completions and resubmit returned work until the original day's effective seal. Parent decides credit. On-time work retains original-day eligibility despite delayed parent review. Null due times do not imply an invented deadline or prevent this approved submission flow.
- P8-006: Show tracker-based cash/achievement/privilege recommendations; Teen may request the outcome; Parent confirms it. A request grants nothing by itself. These actions record family outcomes and do not control unrelated apps. Consistency achievements require explicit parent confirmation, not an invented automatic streak interpretation.
- P8-007: On parent finalization, unsubmitted tasks count as zero; submitted reviews must first be resolved (approved, returned, rejected or excused). Finalization must support below-100 days, preserving existing actual-score earnings and protected-score icons.

Existing negative-balance correction/debt handling remains unresolved. Server rejection must explain that limit rather than silently clamping coins or inventing debt. Historical import from the tracker has not been requested; the feature migration does not copy the child's old personal journal or workbook completion records.
