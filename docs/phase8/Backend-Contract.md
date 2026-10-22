# Phase 8 backend contract

Local implementation, not deployed. Apply existing Phase6/7 migrations then `202610210005_phase8_teen.sql`, `202610210006_phase8_deductions.sql`, and `202610210007_phase8_owner_followup.sql`. `Prepare-Phase8Bundle.ps1` prepares the additive upgrade; `Prepare-DevelopmentBundle.ps1` prepares the initial schema. Neither executes SQL. No cloud changes, secrets, database execution or tests were used while authoring.

Existing public API signatures, Phase6 contribution receipts, Phase7 private health APIs and `get_contract_version()` version1 remain compatible. Phase8 dashboard independently advertises `api_contract_version: 2`.

## Catalogue and occurrences

The approved title revision activates **2026-10-21 America/Costa_Rica**, with task XP and deadlines unchanged. Existing submitted/published occurrences retain their original rule/title snapshots. Unsubmitted occurrences on/after activation adopt the owner revision. Rule semantic fields and source provenance remain immutable; the guard permits only current-version selection changes. Both weekday/weekend duty sets total100; weekend research remains1 and Room/Laundry11AM.

`materialize_teen_tasks()` derives the active Teen identity from Auth, locks its family, and creates today's fourteen applicable authoritative occurrences once. Unknown deadlines remain null without hiding those tasks. Historical versions/dates are not guessed. Stable occurrence IDs prevent date/definition duplication. Existing snapshots preserve weights, deadlines, titles and rule version.

`submit_occurrence(p_occurrence_id uuid,p_request_id uuid)` retains its prior response shape. Late/offline/returned work can reach the server until the original day actually seals; parent review determines credit. Unpublished days have **no seal yet**, including after the normal calendar boundary. Parent first publication establishes the approved normal or late-publication window. Client clocks and queued timestamps cannot authorize after-seal writes. The first on-time submission timestamp retains original-day eligibility; returning/resubmitting does not rewrite it.

`review_submission(p_submission_id uuid,p_outcome text,p_review_note text,p_request_id uuid)` accepts approved/rejected/returned from pending. Returned work becomes pending only through explicit Teen resubmission. A stale competing parent cannot overwrite a returned/rejected outcome. Existing approved work returns the same approval without crediting twice; approval reversal requires the unresolved correction policy. All review events remain available in history.

## Dashboard

`get_teen_dashboard(p_from date,p_to date)` accepts an inclusive range of at most366 days, restricted to the authenticated Teen actor/family. It supports day, Sunday-start week, and month navigation without inventing monthly ranks. Absent/unfinished results are never confirmed bad days.

| Field | Contents |
| --- | --- |
| `server_now`, `server_local_date` | Server instant, Costa Rica date |
| `tasks` | Occurrence columns plus `catalogue_key`, `title_snapshot`, `status`, `submission_id`, `submitted_at`, `decision_id`, `reviewed_at`, `submission_ready`, `readiness_reason`, `is_late`, `effective_seal_at`, latest `review_note` |
| `day_summaries` | `local_date`, `week_start`, publication/seal timestamps, pending/finalized/sealed `status`, accounting revision, `actual_score`, `virtual_remaining`, `protected_score`, `converted_points`, `conversion_history`, `earned_xp`, `coins_earned`, deduction total, `rule_snapshot`, `rule_version_id`, performance icon/label |
| `balance` | Confirmed `earned_xp`, `available_coins`, `coin_rank`; rank boundaries100/500/1000/2500/5000/10000 |
| `deductions`, `review_history` | Authorized facts with actors, timestamps, versions and stable identities |
| `reward_catalogue` |29 entries preserving `id`, `title`, `coinCost`, `sourceStatus`, `type`, `tier` |
| `reward_requests` | Saved title/price, actual debit and current server status |
| `achievements` |6 catalogue descriptions/XP; Teen can request, parent confirmation required |
| `tracker_rules` | Full live rules-only snapshot (`rules` sheet/range/values); owner overrides take precedence; no private journal/personal history |
| `outcome_catalogue` | Cash and13 privilege/consequence entries with stable IDs/title/description |
| `extra_outcome_requests` | Durable cash/achievement/privilege requests awaiting parent confirmation |
| `day_appeals` | Published result revision, original day/reason, effective seal and current authoritative status |
| `readiness` | Explicit remaining action policies; available features stay usable |

Pending result scores, earnings and performance icons are null. Published icons use protected score, independent of actual-only XP/Coins. Actual100 ordinary earns200; conversion provenance suppresses doubling and actual below85 earns0. No inferred permanent growth level, monthly average or direct virtual Coin payout is introduced.

## Accounting and deductions

`finalize_complete_day(p_teen_id,p_local_date,p_request_id)` is the retained additive RPC name for **all score ranges**. Parent explicitly publishes; unsubmitted duties contribute0 and pending reviews must first be resolved. Fourteen authoritative occurrence snapshots are required to avoid guessing historical task sets. Approved original-day points minus fixed deductions use floor0; actual below85 earns0,85–99 earns its score, ordinary100 earns200.

Publication appends an accounting revision and one linked wallet effect in the same transaction. Each finalized earned XP credits exactly one Coin. Phase6 task contributions remain nonspendable; they are never counted again as wallet earnings. Delayed authorized approval before sealing recomputes full original-day state and appends `F(new)-F(old)`. Wallet source uniqueness independently prevents economic replay across new request IDs.

First publication is immutable. Normal exclusive seal is original local date+2 at00:00. If first publication occurs at/after that boundary, seal is publication-local-date+2 at00:00. Republishing cannot restart it. Deferred accounting/deduction/day-wallet/submission/review/appeal guards check the server deadline again at transaction completion; expiry-job lag never reopens authority.

`enter_deduction(p_teen_id,p_local_date,p_deduction_key,p_entry_id,p_request_id)` allows either authenticated permanent same-family parent before sealing. Fixed keys/magnitudes: `dirty-lunchbag:5`, `torn-clothes:20`, `instructions:6`, `shower-items:4`, `messy-items:5`. More than one intentional issue may exist; entry identity prevents retry duplication. Finalized corrections use the full nonlinear earnings difference with linked XP/Coin delta. If already-spent Coins would create debt, the transaction fails explicitly with `negative_correction_debt_policy_required`; no debt policy is invented. Sealed results reject changes.

## Rewards and extra outcomes

`request_reward(p_reward_key,p_request_id)` snapshots server catalogue title/price without charging. `approve_reward_request(p_reward_request_id,p_request_id)` requires either permanent parent, locks the family wallet, checks available Coins and debits saved price once. `cancel_reward_request(p_reward_request_id,p_request_id)` cancels a Teen's pending request free; a parent can cancel an approved/unfulfilled request and refund actual debit once. Spending/refunding never erases earned XP. Fulfillment/exceptional cancellation remains Phase9.

`request_extra_outcome(p_kind,p_outcome_key,p_target_date,p_reason,p_request_id)` creates a free request for `cash`, `achievement`, or `privilege`. Keys come from `outcome_catalogue` or the six achievements. No client supplies award amounts. Stable pending identity is family/Teen/kind/key/date, so another request ID cannot duplicate it. Each creates one durable notification-outbox fact. Cash key is `daily-cash`; privilege keys are `privilege-001` through `privilege-010`, `privilege-skincare`, `privilege-hikari-money`, `privilege-week-plans`. Cash/achievement/privilege recommendations require parent confirmation; confirmation UI/accounting is Phase9. Source references retain ₡500 per point above95, cascading privileges and skincare/Hikari/week-plan consequences without automatic cash or device-permission actions.

## Appeals and remaining policies

`request_day_appeal(p_local_date,p_reason,p_request_id)` files against a published unsealed accounting revision. Filing awards nothing and does not mutate the result. One existing day appeal is reused until changed-revision/multiple-appeal amendment policy is defined. The response/dashboard derives expired status at the effective seal even without an expiry job. Retrying after sealing returns the existing now-expired outcome. Parent resolution is Phase9 and cannot occur after sealing.

Excuse allocation, bonus eligibility/conversion workflow, approved-work reversal, debt handling, appeal amendment/evidence, broader historical backfill and parent outcome confirmation remain explicit readiness gates. Actual/protected/conversion fields and confirmed earnings formula are ready without fabricating approval facts. No unapproved automatic outcomes or hidden timing rules are selected.

All new public tables use RLS subject predicates with select-only client grants. Public wrappers are SECURITY INVOKER; private implementations pin an empty search path and check active family/actor authority. Canonical payload hashing reserves request identity across operations. Family locks serialize approval, spending, refund, finalization and corrections; source uniqueness protects each economic event independently of transport identity.
