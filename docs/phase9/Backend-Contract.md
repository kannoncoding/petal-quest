# Phase 9 backend contract

Local, reviewable forward implementation over the accepted Phase8 schema. Migrations008–012 add Parent workflows; no SQL, cloud deployment, credentials, or tests were executed. `supabase/Prepare-Phase9Bundle.ps1` generates `phase9-parent-upgrade.sql` without database access. Its prerequisite guard rejects missing Phase8 and an already installed Phase9. The development generator also includes these migrations for a fresh schema; never use that initial bundle on the accepted deployed schema.

## Authority and transport

Public mutation wrappers are SECURITY INVOKER. Private implementations pin an empty search path, derive Auth identity, require permanent active same-family Parent authority, acquire the family row lock, then check current state. Teen bonus submission derives the authenticated actor and cannot select another Teen. New public tables explicitly enable RLS and grant clients SELECT only. Private helpers and historical cores are revoked from clients. Existing Phase6/7 health interfaces stay separate; dashboards do not join private health records.

Every new Phase9 mutation accepts a UUID request identity; the pre-existing membership/device recovery interfaces retain their original signatures. Canonical operation/payload hashing detects identity reuse with a changed payload. Retry the same pending action with the same identity; after a stale-state error refresh and obtain a new explicit confirmation. Source uniqueness independently prevents duplicate reward debits/refunds, achievement awards, deduction reversals, and approved bonus conversion.

## Dashboard and history

`get_parent_dashboard(p_family_id uuid,p_teen_id uuid,p_from date,p_to date)` accepts an inclusive range up to366 days. A null family selects the authenticated Parent's authorized family; a null Teen selects its first Teen. The response advertises contract3 and includes `families`, `actors` (`id` and `actor_id`), `memberships`, and device IDs/user IDs/update times. Push tokens and Auth emails are excluded. Current membership schema permits one family per Auth identity.

`tasks` preserve occurrence IDs, saved titles/points/deadlines/rule IDs and submission/review facts. `review_version` is the submission generation. `status` overlays the latest explicit Parent correction, including `excused`. Corrections close ordinary Teen submission/review paths; another explicit Parent correction is required to change that duty. Original historical facts remain intact.

Both dashboards include `day_summaries`, deductions, review/history facts, reward and extra-outcome requests, and these additions:

| Field | Contents |
| --- | --- |
| `occurrence_corrections` | Original duty/day, approved/rejected/excused outcome, required reason, actor, timestamp |
| `deduction_reversals` | Original fixed deduction, reason, actor, timestamp; deductions also expose `reversed` |
| `bonus_activities`, `bonus_reviews` | Original excused duty, exact saved points, description, submission/approval status and audit history |
| `appeal_resolutions` | Original appeal, approved/rejected decision, reason, linked accounting revision |
| `reflection_notes`, `reflection_note_history` | Shared Teen-readable notes with Parent author and independent optimistic version |
| `parent_actions` | Reward and extra-outcome confirmation audit with saved catalogue and amounts |
| `catalogue_versions` | Parent editor versions, effective dates and creator; Parent dashboard only |

Fact arrays order by timestamp then stable ID where applicable. Day navigation uses Costa Rica dates and Sunday-start weeks. Pending days retain null confirmed earnings/performance; `preview` supplies separately labelled current full-state values. `revision` is the published accounting revision. `edit_revision` is the independent current day mutation generation, including unpublished changes; use it for `p_expected_revision`. No monthly-average rank is invented.

Balances preserve earned XP separately from available Coins. Corrections may create negative Coins under the22October owner decision; `coin_debt` and `spending_blocked` expose it. Future credits repay debt naturally. Reward approval checks available Coins against the saved positive price under the same lock, so debt prevents spending. Refunds and spending never erase earned XP.

## Reviews, corrections and finalization

`review_submission_checked(p_submission_id,p_outcome,p_review_note,p_expected_version,p_request_id)` accepts approved/rejected/returned from the observed pending generation. `p_expected_version` is `tasks.review_version`. Returning and Teen resubmission increment that generation. Legacy review/approval routes preserve first-cycle compatibility and historical committed retries, but reject a new decision after a return/reject cycle; they cannot bypass generation checks.

`correct_occurrence(p_occurrence_id,p_outcome,p_expected_revision,p_reason,p_request_id)` records an explicit approved/rejected/excused override of the exact original duty weight. A nonblank reason is required. The expected edit generation prevents competing corrections from silently overwriting each other, even before first publication. An occurrence with an already approved bonus remains closed to further correction until its exceptional reversal policy is specified.

`enter_deduction` retains the existing fixed five keys and entry identity. `reverse_deduction(p_entry_id,p_expected_revision,p_reason,p_request_id)` appends a reasoned reversal once; it never deletes the original entry.

The retained `finalize_complete_day(p_teen_id,p_local_date,p_request_id)` explicitly publishes any score. Unsubmitted work contributes0; pending reviews without an explicit correction block publication. An immutable authoritative day task manifest must match the original occurrence IDs/weights/rules and total100. Existing accepted complete14-duty/100 sets can be certified conservatively; incomplete historical sets remain blocked. Future valid edited catalogues can have another task count.

One centralized full-state calculation handles ordinary approvals, corrections, excuses, conversions, fixed deductions/reversals and publication. With original approved points `R`, original excused points `V`, gross accepted conversion allocation `B`, and active deductions `D`, actual is `max(0,R+B-D)` and protected is `max(0,R+V-D)`. `converted_points` reports gross allocation; `virtual_remaining` reports net remaining protection (`protected-actual`). For example, R0/V100/D5/B90 produces actual85, protected95, converted90, remaining virtual10, and85 earned XP/Coins. This preserves the deduction's effect on the85 threshold. Actual below85 earns0; ordinary100 earns200; otherwise actual score is earned. Any approved conversion permanently suppresses perfect doubling for that day. Virtual protection does not itself pay XP or Coins. Every published mutation appends its accounting revision and exactly the nonlinear difference `F(new)-F(old)` to both earned XP and Coins. Wallet source identity is Teen/day/revision; pending changes update only preview/edit generation.

The original publication timestamp and exclusive seal never restart. Normal seal is original date+2 at00:00 Costa Rica; publication at/after that boundary uses publication-local-date+2. All score-changing operations check current server time, with deferred commit seal guards for authoritative records and day wallet/accounting effects. Sealed results are final.

## Bonus and appeals

`offer_bonus(p_occurrence_id,p_description,p_expected_revision,p_request_id)` requires the latest duty outcome to be excused. One activity identity is linked to that original occurrence, with points fixed to its weight. `submit_bonus(p_bonus_id,p_request_id)` is Teen-only and changes offered/returned to submitted. Committed repeated submission does not create a second generation/event. Completion can reach the server any time before the original day seals; device timestamps cannot override the deadline.

`review_bonus(p_bonus_id,p_outcome,p_expected_revision,p_reason,p_request_id)` accepts approved/returned from submitted, or cancellation before approval. Approval must also commit before sealing. Approved bonus conversion cannot exceed the original remaining excused weight and cannot be paid twice. Approved conversion cannot be cancelled through the ordinary cancellation path. Cancelling a stale unapproved offer is allowed even if an explicit correction changed the original duty. Cancelled offer reopening/approved reversal remains unavailable.

`resolve_day_appeal(p_appeal_id,p_outcome,p_expected_revision,p_reason,p_request_id)` records approved/rejected with a nonblank reason while unsealed. Approval requires an accounting revision after the appeal's original revision; perform the explicit correction first. The resolution stores the actual accounting revision, distinct from the expected edit generation. Filing or resolving alone awards nothing. An unresolved appeal expires at seal; no delayed worker can reopen authority.

## Rewards and extra outcomes

`review_reward_request(p_reward_request_id,p_outcome,p_note,p_request_id)` supports approved/cancelled/fulfilled. Approval uses the original saved title/price and existing one-time debit. Cancellation before approval is free; Parent cancellation of approved/unfulfilled refunds the actual debit once. Fulfillment requires approval. Repeated fulfillment preserves the first timestamp; fulfilled cancellation/reversal is unavailable.

`review_extra_outcome(p_outcome_request_id,p_outcome,p_note,p_request_id)` supports confirmed/declined. Achievement confirmation pays the request's immutable saved catalogue `xp` once, with one Coin per XP. Every qualifying accomplishment requires explicit Parent confirmation; a later distinct request may represent another legitimate accomplishment, including the same date. Consistency eligibility remains manual rather than an inferred streak.

`confirm_cash_outcome(p_outcome_request_id,p_cash_amount,p_note,p_request_id)` requires a nonnegative explicit integer CRC amount and nonblank reason. It records a real-world outcome, not a Coin payment. Generic cash confirmation without an explicit amount is rejected. Cash/privilege recommendations do not automatically select actual-versus-protected eligibility, award cash, or control another app. Audit snapshots retain the chosen amount and Parent decision.

## Future catalogue editors

`save_catalogue_version(p_family_id,p_kind,p_catalogue_key,p_effective_from,p_payload,p_request_id,p_expected_version)` handles existing task/rule/reward keys. Expected version is the globally latest family catalogue row ID ordered by `created_at DESC,id DESC`, or null initially. Task/rule payload is `{title,points,local_due_time,weekdays,enabled}`; reward payload is `{title,coinCost,sourceStatus,type,tier}`. Effective date must be strictly after server today. Historical versions and occurrence snapshots are immutable.

`save_task_catalogue(p_family_id,p_effective_from,p_tasks,p_expected_version,p_request_id)` atomically saves a full duty set. Each item adds `catalogue_key` to the task payload. Every existing definition must be present, including archived entries; new keys are allowed. Each weekday's effective enabled duty set must total100, including all later effective boundaries. Multi-point/recurrence changes therefore commit together rather than temporarily invalidating the approved scoring model. No automatic normalization or new score cap is introduced. Materialization chooses immutable effective versions and snapshots the complete expected day set. Legacy creation cannot bypass that full materializer after catalogue edits.

## Reflection notes and delivery

`save_reflection_note(p_teen_id,p_local_date,p_text,p_expected_version,p_request_id)` is Parent-only; absent notes use version0. Updates append history and return the next version. Teen can read, never edit. These shared family reflections remain separate from private health notes and do not change scores or reopen sealed days.

New business transitions append transactional outbox facts for review, correction, bonus offer/submission/review, reversal, appeal resolution, reflection update and finalization. Payloads contain stable IDs and minimal status/date fields, never descriptions/reasons/note text. Phase10 owns delivery; existing Phase7 health delivery workers do not consume these topics.
