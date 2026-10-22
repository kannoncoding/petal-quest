# Phase 9 owner decisions — 22 October 2026

These confirmed choices supplement Phase3/8. Existing protected-score icons, actual85 earning threshold, conversion-day no-doubling, fixed tracker deductions, original-day attribution and sealed-result finality remain in force.

| ID | Confirmed owner decision |
| --- | --- |
| P9-001 | Valid pre-seal corrections/deductions may make available coins negative. Future earnings repay the debt; spending approvals remain blocked until repaid and affordable. Preserve earned-event history and exact correction delta; no clamping or lost correction. |
| P9-002 | Bonus work converting excused virtual points may be completed any time before its original day seals. Parent approval must also happen before sealing. It does not earn an ordinary perfect-day bonus. |
| P9-003 | Reflection notes: Parents edit; Teen has view-only access. Private health notes stay separate and are never imported into these notes. |

## Implementation choices preserving approved rules

- Save a complete future task schedule atomically and require each of seven weekdays to total100. No automatic reweighting is authorized. New/archived duties retain stable IDs; existing submitted/published/sealed occurrences keep their snapshots. Expected day manifests replace a permanently hardcoded fourteen-duty count.
- A distinct achievement request represents a distinct claimed accomplishment; Parent explicitly confirms it. The source Any test scored100 and Times Achieved support repeat accomplishments. This is a source-based implementation interpretation, not an invented automatic cadence. Reconfirming the same request can award only once.
- A conversion offer uses the full original weight of one explicitly excused duty and may consume that allocation once. Converted points are gross accepted bonus weight, before deductions. Actual=max(0,ordinary-approved+converted-deductions); protected=max(0,ordinary-approved+excused-deductions). Do not move deductions away from actual points to make conversion look larger. For example, ordinary0/excused100/deduction5/approved-conversion90 gives actual85, protected95, earned85.
- Explicit pre-seal review corrections and deduction reversals require reasons and the current day edit generation. Original review races use submission generations; a new ordinary review never silently overrides an earlier decision.
- Appeal resolution records the Parent outcome and actual accounting revision; accepting a correction-based appeal requires the corresponding corrected result first. It never invents a freely editable XP number or reopens the sealing deadline.
- Approved-bonus reversal and reopening a cancelled offer remain unavailable pending an explicit lifecycle policy. These limits must be visible and must not conceal lost history or invent extra allocation.

No new owner phone or installation is needed to record these decisions. Production is untouched.
