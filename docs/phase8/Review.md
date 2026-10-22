# Phase8 source and static implementation review

Reviewed 21 October 2026. No tests, builds, emulator/device runs, database migrations, cloud deployments or notification sends were executed by this review. Conclusions below come from reading sources; they do not establish runtime correctness or deployment status.

## Evidence and source parity

Read the Phase3 extract, Owner-Decisions, Scoring-Specification, Phase8 requirements and live rule-only snapshot. `Tracker-Feature-Coverage.md` enumerates28 duty variants,5 deductions,29 rewards,6 achievements,8 daily bands,10 benefits/privileges, cash consequences, available-coin ranks and period/history features. Owner overrides govern task labels, weekend research1, weekend Room/Laundry11:00, actual 85 earnings gate, conversion-day bonus exclusion and protected-score icons. Manual source XP redemption is superseded by automatic finalized1:1 coins for new app earnings.

The source Notes feature is family reflections/promises/deals/goals/events. Personal entries were not copied. No recurring allowance amount/schedule is specified by source Hikari Money references. Cash/privilege effects remain policy work; monthly-average ranks and lifetime-XP levels are not approved features.

## Boundaries observed in current source

Read `202610210005_phase8_teen.sql`, `202610210006_phase8_deductions.sql`, `202610210007_phase8_owner_followup.sql`, prerequisite Phase6 tables/submission/approval/idempotency functions, `FamilyService.kt`, `FamilyRepository.java`, `FamilyDao.java`, `QueuedSubmissions.kt` and `TeenQuestScreen.kt`.

- New accounting, wallet and deduction tables deny client writes and use family/Teen read policies. Private security-definer functions use empty search paths; public wrappers preserve the authenticated invoker boundary. Active same-family membership is checked before reward mutation and complete-day finalization.
- Family locks serialize balance-affecting reward approval/cancel/finalization. Saved reward price is debited once; unique wallet source keys protect debit/refund posting. Stable request IDs are payload-bound through the existing idempotency helper. Teen cancellation of an approved reward is rejected; Parent pre-fulfillment cancellation refunds the original debit.
- New wallet balances consume finalized earnings only. Existing duty-contribution events retain zero spendable XP/coins. An ordinary approved task does not independently grant spendable earnings.
- Occurrence titles are snapshotted at insertion; current rules remain separate from history. Dashboard range queries bind family and Teen to the authenticated membership. Result state derives from server publication/deadline; missing accounting does not emit a bad-day icon.
- Queue payloads allow only explicit family fields. Stable local request IDs survive retries; server response IDs must match before acknowledgement. Cache and queue access require the active user/endpoint/session generation. Cached facts are labeled saved snapshots; local intent does not calculate XP or available coins. Private health storage is separate and absent from dashboard history.
- Parent finalization preserves first publication and the approved late-publication sealing extension. Before sealing, a newly approved submission recomputes original-day totals and credits only the derived wallet difference; changing an already approved contribution remains blocked pending correction policy. No score-changing post-seal mutation is authorized.
- Deduction entry uses either same-family Parent, fixed catalog magnitudes, stable entry identity and payload-bound request IDs. Finalized-but-unsealed ordinary results are recalculated through the earnings function and wallet difference, including loss of the perfect-day bonus or threshold earnings. A correction that would make available coins negative fails without posting. Deferred constraint triggers recheck effective seal time for deduction/accounting/day-wallet inserts at transaction completion. Excused/converted corrections remain gated.

## Material completion limits

This is an implementation foundation with intentional policy gates. It is not evidence that all Phase8 workflows work end to end.

| Area | Current limitation / required decision |
| --- | --- |
| Unspecified times | P8-005 permits late/offline/returned submissions before effective seal even when due time is null. New007 removes the old null-time submission block; no deadline is invented. |
| Finalized earnings | Complete-day endpoint requires 14 approved duties totaling 100 before deductions. Combined with unspecified deadlines, fresh full days cannot reach this path until schedule policy is resolved. Partial/pending-day finalization is not implemented. |
| Rules activation | P8-004 activates labels2026-10-21 in staged007; submitted/finalized occurrences remain unchanged. Local migration code is not evidence of cloud deployment. |
| Deductions | Backend entry and ordinary unsealed correction are staged; Parent UI remains Phase9 work. Debt after spending and excused corrections are blocked pending policy; no arbitrary custom values are authorized. |
| Excuses/conversions | Read contract separates actual, virtual and converted points. Allocations, qualifying bonus work, approvals and correction posting remain unresolved; no working conversion flow is demonstrated. |
| Appeals | Teen filing and effective expiry display are staged, including current-state expired responses on retries and commit-time sealing checks. Parent decision/revision workflow remains Phase9. |
| Achievement awards | P8-006 permits Teen requests with Parent confirmation; no automatic consistency streak is inferred. Catalogue/request contract is staged; Parent confirmed award posting/history remains Phase9. |
| Cash/privileges | P8-006 uses tracker recommendations and Teen requests, with Parent confirmation granting outcomes. Requests themselves award nothing; Parent confirmation/accounting UI remains Phase9. |
| Periods/reflections | Navigation/read models do not establish weekly close/reopen, bonuses or editable family reflection notes. Legacy tracker history import is not included. |
| Sync/reminders | Explicit retries are implemented; contextual reminders, background reconciliation and broad notification behavior remain Phase10. |

## Integration findings sent to implementation owners

Static review identified task submit readiness ignored by the initial UI, missing server coin rank, a mismatched day rule-version field and raw developer readiness strings in product UI. These were sent to the Backend/Teen owners for correction. Backend subsequently added available-coin rank and day rule snapshot/version fields. Final UI changes should be checked against those contracts before a deployment claim. This review does not substitute for owner-authorized runtime verification.

Follow-up source review confirms the Teen UI now respects per-task readiness, permits saving intent from a cached snapshot, binds the screen to session generation, translates readiness messages, and stores observed approval status to avoid replaying a celebration when navigating/retrying. Backend rank/rule snapshot additions match the UI contract. The final source also persists verified membership snapshots bound to user/endpoint/session access, restoring the cold-start cached Teen screen with stale-access messaging; every dispatched mutation still rechecks server membership.

Owner follow-up received during implementation: activate updated labels on 2026-10-21 and accept late/returned submissions until sealing, with Parent deciding credit. Migration007 versions changed definitions while preserving existing submitted and published occurrences; new family seeding uses approved labels. Its public review wrapper and private implementation both receive authenticated execution, internal seed/deadline helpers are revoked from app roles, and the existing schema usage grant supports the invoker boundary. `petal_private` must remain outside exposed PostgREST schemas.

The completion table incorporates P8-004 through P8-007: activation date, late/returned submission, manually confirmed outcomes and unsubmitted-zero finalization are approved. The unpublished-day deadline concern was corrected: no effective seal exists until publication; late first publication retains its approved extension. Submission/review and appeal inserts now have deferred seal guards. The immutable initial-rule trigger was narrowed to permit only current-version selection changes while retaining immutable rule semantics/provenance. The full review history is returned separately from latest notes.

## Owner decisions still needed

P8-004 through P8-007 settle activation, late/offline/returned submission, manual Parent confirmation of extra outcomes and unsubmitted-zero finalization. Remaining detailed policy concerns bonus eligibility/window, correction debt after spending and Parent fulfillment/reversal semantics for cash/privileges/achievements. Reminder text/task context remains deliberately deferred to Phase10 and should not be re-requested now.

Final static conclusion: no further deployment-blocking defect identified after the communicated fixes. This conclusion is limited to source inspection; SQL execution and device behavior remain unverified by this review. Parent outcome confirmation, family-note permission/edit workflow and excuse/bonus allocation remain Phase9 scope.

Final handoff recheck: new Parent reviews require a pending submission; stale returned/rejected decisions cannot be overwritten, returned work must first be explicitly resubmitted by the Teen, and duplicate approved outcomes reuse the existing decision. Teen day detail renders full review history; tab/range/date navigation is disabled while a fetch/action runs; readiness notices display unresolved policies only. The forward Phase8 bundle contains migrations005/006/007 inside one outer transaction, Phase7 prerequisite and already-applied guards, and a final catalogue count query expecting28 duty variants,29 rewards and6 achievements. No additional static blocker was identified. Root separately reports a successful debug build; this review did not run that build or any tests/SQL.
