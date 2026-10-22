# Owner decisions: Phase 3

Recorded 2026-10-20. This register distinguishes explicit owner decisions from draft proposals and the original spreadsheet snapshot.

## Confirmed

| ID | Decision | Evidence |
| --- | --- | --- |
| P3-001 | Family timezone is `America/Costa_Rica`. | Owner answered scheduling question. |
| P3-002 | Each scoring week starts Sunday at 00:00 local time. | Owner selected Costa Rica time; Sunday start. |
| P3-003 | Weekend research/writing task is **1 XP**, replacing the spreadsheet's 2 XP for the app rules. | Owner selected Change weekend research from 2 XP to 1 XP. |
| P3-004 | Preserve accumulated earning rules: daily score below 85 gives zero earned XP; 85-99 earns its score; exactly 100 earns 200 XP. | Owner selected Preserve the current formula rules. |
| P3-005 | Passing day remains score 90 or above; the earning threshold of 85 is distinct. | Included explicitly in the question whose earning rules the owner chose to preserve. |
| P3-006 | Weekend Room + Laundry deadline is **11:00 AM**, correcting the source's 11 PM label for the app. | Owner selected It should be 11 AM. |
| P3-007 | On-time submitted work remains eligible for its original day's full score when parent review is delayed. | Owner selected Yes; delayed parent review does not penalize her. |
| P3-008 | Finalized earned XP automatically converts to coins at **1 XP : 1 coin**; spending coins does not erase earned-XP history. | Owner selected automatic conversion in the explicit 1:1 question. |
| P3-009 | A parent explicitly finalizes each day; the parent app provides multiple reminders and a final evening check-in, with **9 PM given as an example**. | Owner's custom daily-finalization answer. Exact reminder schedule remains to be settled. |
| P3-010 | Excused work supplies **virtual points protecting the daily result**, without earning actual XP or coins. | Owner's custom excused-work answer. The interaction with the earnings threshold and perfect-day bonus needs an explicit worked-example decision. |
| P3-011 | On a day with excused work, the parent app shows a special action to offer bonus work that can convert those virtual points into earned points. | Owner's custom excused-work answer. Approval, timing and duplicate handling are being specified. |
| P3-012 | Reward request is free; either parent may approve and debit the saved price once; cancellation before approval is free; parent cancellation before fulfillment refunds once. | Owner selected Use that reward flow. |
| P3-013 | Actual points alone must reach **85** before any XP is earned; virtual protection cannot unlock earnings below that threshold. | Owner explicitly said keep zero XP earning until actual points reach 85. |
| P3-014 | A day earning points through bonus actions converting virtual points has **no perfect-day bonus**. At actual score 100 it earns **100 XP**, not 200, and therefore 100 coins. | Owner explicitly specified no perfect-day bonus for such a day. |
| P3-015 | Parent reminder checkpoints are **07:15, 15:20, 17:00, 19:00 and 21:00**, in Costa Rica time. | Owner supplied all five times, superseding the proposed 19:00/20:00/21:00 schedule. |
| P3-016 | The owner will provide each reminder's labels, text and specific task-check context **when the reminders are built**. | Explicit owner instruction; do not request final copy now or treat all checkpoints as identical day-finalization prompts. |
| P3-017 | Coin rank/tier follows **available coins**, matching the current tracker; spending can change that tier without erasing earned-XP history. | Owner explicitly distinguished the coins rank. |
| P3-018 | Growth/performance rating is **daily**, distinct from the coin tier. | Owner explicitly said her own growth rank is daily. No permanent lifetime-XP level was requested. |
| P3-019 | Normally, a teen may appeal a day's result through the following local day. At **00:00 on the second following day**, the original day seals. Monday's result can be appealed Tuesday; it seals Wednesday at 00:00 Costa Rica time. | Explicit owner appeal-window instruction; late first publication has the approved exception P3-022. |
| P3-020 | The teen has multiple reminders for pending items and things to do, including a specific **17:00** reminder to review the previous day's result before sealing. | Explicit owner teen-reminder instruction. Other teen reminder times/context are not yet specified. |
| P3-021 | An unresolved appeal **expires when its result seals**. A parent cannot resolve it afterward. | Owner selected unresolved appeals expire when the day seals. |
| P3-022 | If a parent first finalizes/publishes a result **after its normal sealing boundary**, allow appeals through the day after that publication. | Owner selected Allow through the day after that result is published in the late-first-publication question. |
| P3-023 | **Sealed results are final.** Parents cannot correct a sealed result outside the appeal window. | Owner selected No; sealed results are final. Together with P3-021, no unresolved appeal creates post-seal correction authority. |

Both weekday and corrected weekend task sets now total 100 XP. This correction does not introduce a new score cap or change achievement awards. Original `Tracker-Rule-Extract.json` preserves the source as read, including the original weekend value; the app catalogue records the explicit override.

The live Google Sheet has not been edited. The user's answer settled app behavior in the scoring question; no spreadsheet repair or source mutation was performed.

## Existing requirements retained

- Either parent can approve duties, subject to authenticated authority in the adopted separate-app architecture.
- Backend is authoritative; duplicate requests and simultaneous parents cannot create duplicate awards.
- Rules stay versioned on occurrences; corrections preserve history.
- Health entries never affect discipline XP.

## Still requiring specification or confirmation

Unspecified deadlines and teen late work; returned/resubmitted work; bonus-action eligibility/window before sealing; pre-seal correction authorization and negative balance policy; rule effective dates; achievement consistency and weekly aggregation. The actual-only 85-point earnings gate and removal of the perfect-day bonus on conversion days are settled. Parent-driven finalization, reminder times, virtual-point protection, coin rank versus daily growth, reward lifecycle and appeal/sealing exceptions are also settled. No day should auto-finalize merely because an evening reminder fired.

The phone remains unnecessary. No installation, credentials or repeated Phase 2 checks are needed.

## Appeals and sealing

The normal deadline uses the original family-local result day, not a rolling 24 hours after viewing it. A Monday result may be appealed Tuesday at 23:59; filing or deciding an appeal at Wednesday 00:00 is too late under the normal window. Unresolved appeals expire at that boundary and leave the result unchanged. Preserve the appeal history rather than deleting it.

Approved late-publication exception: if Monday's result is first finalized/published on Wednesday, appeals are allowed through Thursday and the result seals Friday at 00:00. The extension is scoped to the question the owner answered: first publication at/after the original sealing boundary. A publication before that normal boundary keeps the normal window; no broader extension was requested. First-publication time must remain stable, so editing or republishing a result cannot restart the clock.

All dates use `America/Costa_Rica`. The deadline is exclusive. The 17:00 teen reminder is a review prompt, not the filing cutoff. Sunday weekly rollover must not shorten a Saturday result's Sunday appeal window. An appeal request, expiry or seal does not itself grant or remove XP/coins.

Sealing is final for the day's score and earnings. Reject subsequent result-changing approvals, bonus conversions, deductions, appeal decisions and parent corrections; earlier draft post-finalization adjustments apply only before sealing. This does not freeze unrelated reward spending/refunds or private health entries. Delayed-parent-review protection does not grant authority to mutate an already sealed result.

An unfinalized day is not silently finalized with zero earnings at its original calendar boundary. If its first publication is late, apply the approved exception above. A stale client or delayed sealing job cannot permit a mutation after the effective server deadline. Retrying a previously filed appeal returns its current outcome, including expired if unresolved at sealing, without re-filing or reopening it.

## Current clarifications

The earlier proposed 80-actual/20-virtual example yielding 80 XP and then 200 XP was **not adopted**. The owner instead chose zero below 85 actual points and no perfect-day bonus on virtual-conversion days. Thus 80 actual + 20 virtual earns zero; converting all 20 through qualifying bonus work brings actual score to 100 and earns 100 XP total. Virtual protection and earned accounting remain distinct.

The three questions in the last reminder/rank batch have now been answered. The owner replaced the proposed reminder schedule and clarified two separate ratings. Do not re-ask them.

## Optional idea, not a committed feature

The owner suggested **maybe** adding a rating based on average month-to-date performance. Keep this as an optional proposal; no new monthly rank, formula, threshold, denominator or growth-level system is approved by that tentative wording. Daily-rating and coin-tier work can proceed without it.

Reminder content and task-specific conditions are deliberately deferred to implementation. The five timings do not by themselves settle recipients, weekday/weekend applicability, quiet-hours behavior or whether finalizing one day suppresses an unrelated task checkpoint. Preserve those implementation decisions rather than inheriting the old all-reminders-until-finalized proposal.

## Phase 8 owner updates — 21 October 2026

P8-001: revised daily task labels with XP unchanged are now recorded in App-Rule-Catalogue.draft.json; original source snapshot remains unchanged. See ../Phase8/Requirements-and-Owner-Decisions.md for the exact stable-ID mapping.

P8-002: either parent may enter tracker deductions before sealing; sealed days remain final. This resolves the deduction seal deadline, not the previously open negative-balance correction policy.

P8-003: both apps need month/week/day history and the supplied eight performance bands/icons. For excused work the icon uses protected score; XP/coins still use actual-score thresholds and no perfect-day bonus on conversion days. No monthly-average rank formula was approved.
