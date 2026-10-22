# Phase 9 staged fictional-family walkthrough

Status: instructions prepared from the current UI; no observations or passes recorded here. Record actual results separately with build hash, service revision, date, observer, fictional family/actors, expected facts and actual facts. Installation/build success does not establish acceptance.

Use **Test Family1** and fictional tasks, notes and rewards only. Keep existing app data during an in-place update. Confirm the selected family and teen before each group. Do not open private health records, change device pairing or revoke an active family member during the core walkthrough. Owner deferred password recovery; it is outside this session's acceptance.

The two installed apps can exercise the core groups sequentially on one phone. Open the Parent app or Teen app as indicated; return to the other app and refresh after each change. These steps require an authorized fictional Parent session and paired fictional Teen session. If the service rejects a step, record the sanitized error and stop that group; do not infer success from the confirmation dialog.

## Parent confirmation controls

Every proposed Parent mutation opens **Confirm family decision**. Read its action list, original date and note. **Confirm 1 action(s)** sends a single action; batch review shows **Confirm N action(s)**. **Keep reviewing** dismisses the proposal without sending it. Wait for service acknowledgement and refreshed facts before continuing.

If **An earlier decision needs confirmation from the service** appears, use **Review and retry saved decision**, inspect the saved payload, then confirm. Do not create a replacement action to resolve an unknown outcome. Failed refresh must show saved/read-only information; Parent decision controls must remain unavailable until a successful refresh.

## Group 1 — return, explicit resubmission and approval

1. Parent: **Refresh dashboard**. Check **Current family information**, selected **Teen 1** (or the intended fictional teen), **History date (YYYY-MM-DD)** and **Day**. Open **Review**.
2. Teen: **Quests** → **Refresh confirmed results**. Choose one open fictional duty and **Mark completed**. Observe server-received awaiting review; record the balances. This submission must not award confirmed XP or coins.
3. Parent: **Refresh dashboard**. Find that exact duty and original date. Enter `Phase9 fictional return` in **Decision note**, then **Return** → **Confirm 1 action(s)**. Record acknowledged status and note.
4. Teen: **Refresh confirmed results**. Verify returned status/note and **Resubmit for review**. Refresh alone must not resubmit. Tap **Resubmit for review**.
5. Parent: refresh, enter `Phase9 fictional approval`, **Approve** → **Confirm 1 action(s)**. Teen refresh must show approval. Approval contributes points; day publication determines earned XP and coins.
6. Repeat submission on a different fictional duty, then Parent **Reject** → confirm. Teen refresh must show rejection; the rejected duty must not offer the returned-work resubmit button.
7. For a deliberately prepared fictional pending set, Parent **Review approval of all N pending submissions**. Inspect every action/date and **Keep reviewing** first. Reopen and **Confirm N action(s)** only for the intended set. Record actual acknowledgements if the batch stops partway through.

## Group 2 — publication and accounting

1. With at least one pending submitted duty, Parent **Review** must prevent publication. Resolve all pending submissions for the selected day.
2. Record **Not finalized · service preview**: actual score, protected score, remaining virtual points, expected XP/coins, deduction points and approved bonus points. Unsubmitted duties contribute zero.
3. **Publish this day's result** → inspect preview → **Confirm 1 action(s)**. Record the published result, revision, seal time and wallet change in Parent **History**.
4. Teen **Refresh confirmed results** → **History** → **Day** → **Today** (or **Previous**/**Next** to the same date) → dated result row. Compare actual, virtual, protected, earned XP, coins and sealing time with Parent.
5. Ordinary actual 100 should earn 200; 99 earns 99; 85 earns 85; below 85 earns zero. Exercise these distinct examples with isolated fictional fixtures/API gates rather than assuming one day's result proves every threshold.

## Group 3 — deduction and reasoned reversal

1. On a published, unsealed fictional day, Parent **Review** → **Dirty lunchbag · 5** → **Confirm 1 action(s)**. Record score and wallet deltas. This is a five-point deduction before earnings calculation, not a flat five-coin fee.
2. Parent **Adjust**: enter `Phase9 fictional deduction reversal` in **Reason for this decision**. Choose **Reverse deduction · DATE · 5 points** → confirm. Record the restored accounting and history.
3. Expected examples: ordinary 100→95 changes earnings 200→95 (−105); 85→80 changes 85→0 (−85). A permitted correction may create coin debt; available coins must not silently clamp to zero. Debt/insufficient-spend gates need separately prepared fictional balances.

## Group 4 — excuse and bounded conversion bonus

1. Parent **Adjust**: select an intended fictional duty on an unsealed day; enter a reason and **Excuse** → confirm. Verify its virtual allocation protects the score without earning XP/coins.
2. Enter `Fictional conversion task` in **Bonus work to complete**. **Offer bonus · DUTY** → confirm. Check the original date and offered points.
3. Teen **Quests** → refresh → **Bonus work** → **Mark bonus completed**. For prior current-week duties, enable **Weekly view** to see their task rows. Completion alone must not award points.
4. Parent **Adjust** → refresh; enter a reason, locate the submitted bonus and **Approve** → confirm. Verify converted allocation, actual/virtual changes and wallet difference on the original day.
5. Conversion days do not receive ordinary perfect-day doubling. Real 80 + virtual 20 earns zero; approved conversion of 5 yields actual 85 and earnings 85; converting the remaining 15 yields earnings 100, never 200. Exact allocation/retry/sealing cases require controlled fixtures. Approved bonus reversal is unavailable.

## Group 5 — appeal and shared reflection

1. Teen **History** → select the published, unsealed date. Enter `Phase9 fictional review request` under **Why should this result be reviewed?** → **Ask parent to review result**. Record no wallet change from filing.
2. Parent **Adjust**: if justified, make the specific duty correction first using **Credit**, **Remove credit** or **Excuse**, with a reason and confirmation. Then under **Resolve an appeal**, enter a reason and **Accept appeal** or **Decline appeal** → confirm. Resolution records the decision and does not itself enter a score.
3. Parent **Adjust** → **Family reflection note**: enter `Phase9 fictional shared note` → **Review reflection note** → confirm. Teen refresh must show the same note under **Quests** for today/current week or the matching **History** date. The Teen has no note edit control.

## Group 6 — reward and extra outcome lifecycle

1. Teen **Rewards**: choose a fictional reward → **Request reward · free**. Record title/saved price/requested status and unchanged coins.
2. Parent **Review** → **Reward requests**: same request **Approve and debit** → confirm. Record one debit of the saved price; earned XP history stays unchanged.
3. Same approved/unfulfilled request **Cancel and refund** → confirm. Record one refund of its actual debit. Use a separate fictional request to exercise **Mark fulfilled**; fulfilled reversal is unavailable.
4. A separate pending request can use Teen **Cancel request · free before approval** or Parent **Decline request**; neither refunds coins because no debit occurred.
5. Teen **Rewards** → **Request date · YYYY-MM-DD**, optional reason, then the selected achievement/cash/privilege **Request parent confirmation**. Request alone grants nothing.
6. Parent **Review** → **Cash, achievement and privilege requests**: **Confirm** or **Decline** → confirm the dialog. Cash confirmation additionally requires **Confirmed cash amount in whole colones** and a nonblank **Decision note**; recording transfers no money. Record authoritative catalogue awards and once-only effects of the source request.

## Group 7 — history and future schedule editing

1. Parent **History date (YYYY-MM-DD)**, **Day**/**Week**/**Month**, **History**. Teen **History**, **Day**/**Week**/**Month**, **Previous**/**Today**/**Next** and dated row. Compare Sunday week boundaries, original dates, pending/finalized labels, review notes, reasons, audit, deduction facts, reflection notes and wallet changes. Missing/pending days must not acquire a confirmed bad-day label.
2. Parent **Edit** → **Duties and rules**: choose a duty, future **Effective date (YYYY-MM-DD)**, edit **Title**, **Duty points**, **Deadline HH:mm · leave empty if unspecified**, **Repeat days: Sunday 0 through Saturday 6, comma separated**, or **Enabled**. **Apply to duty draft** for each change. Daily totals must remain 100 across all seven days before **Review complete future schedule** → confirm. **Add duty** also needs a complete balanced draft. Do not rewrite the real family schedule for this check.
3. Parent **Edit** → **Rewards**, choose an existing reward, enter future effective date and edit title/price/availability → **Review future reward version** → confirm. Compare unchanged historical snapshots and saved request price. Creating new reward keys is unavailable.
4. After the separate routine service upgrade, Parent **Edit** → **Assigned routines** → **Add assigned routine**. Enter a fictional **Routine title**, **Local times HH:mm, comma separated**, **Weekdays 0–6, comma separated** and **Future effective date YYYY-MM-DD**. Leave **Active from effective date** enabled. **Review routine change** → inspect the schedule → **Confirm 1 action(s)**. Record the saved immutable version; the routine must not create tasks, pending approvals, XP or coin changes.
5. Use **Edit routine or schedule archive** to propose a later version. Turn **Active from effective date** off to schedule an archive; **Review routine change** → confirm. Prior saved versions must stay visible. Parent date navigation and Teen **History** date range must show the version effective for each date, only on its selected weekdays. Teen routine display is read-only. On its effective date, Teen **Quests** → refresh must show the assigned title and times; creating a future version does not make it active today. Local notification delivery remains Phase 10.

## Separate host API and controlled-data gates

These gates require independently authenticated fictional sessions and authoritative server facts. One phone's sequential UI walkthrough does not prove them:

- Two Parents: approve/approve and approve/return races, stale review generation, stale full-schedule/reward version, note conflicts and fulfill/cancel race. Exactly one compatible transition must commit.
- Same request ID retry after timeout/restart and changed-payload rejection; different IDs for the same economic source must not duplicate award/debit/refund/conversion. Inspect exact committed facts, not only HTTP success.
- Revoked/expired Parent session, Teen and unrelated-family attempts against Parent RPCs and direct exposed-table reads. A revocation fixture must be an isolated test member, not an active real session.
- All threshold/deduction/floor/debt examples; pending versus unsubmitted publication; delayed original-day review and weekly totals; finite conversion allocations and repeated source use.
- Normal and delayed-publication seal boundaries, exclusive commit-time deadline, republish not extending time, appeal expiration and sealed mutation rejection. Use controlled fictional fixtures; do not change the phone clock or production records.
- Parent offline/read-only display, durable unresolved retry identity after process restart, Teen pending-send replay and account-change cache isolation. Phone UI observations remain necessary even if API receipt checks pass.

Assigned routine authoring uses a separate service upgrade and needs its own live acceptance evidence, including stale-parent conflicts, Teen write denial and unrelated-family read/write denial. Contextual notification delivery is Phase 10. Recovery is owner-deferred; optional quick unlock is not enabled. None of these boundaries is an inferred pass of the original plan.
