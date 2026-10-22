# Phase 8 owner walkthrough — prepared, not executed

Use fictional tasks/rewards/outcomes in development. This checklist does not claim app or service acceptance.

## Prerequisites

Coordinator prepares compatible APKs and the reviewed forward SQL bundle. Owner applies SQL in Petal Quest Dev only. Reconnect/unlock the Samsung for in-place installation; do not uninstall or reset app data. The other family phones are not needed for this first trial.

## Quests and history

1. Open Petal Quest → Family service access → Test Family 1. Load the quest screen online. Confirm revised task labels, unchanged weights, weekday/weekend schedule and full reward catalogue.
2. Complete one fictional task. Confirm server-received/awaiting-parent-review differs from local waiting-to-send. No confirmed XP is awarded merely by tapping complete.
3. After loading the day's data online, disable internet. Queue a different completion, close/reopen the app, and confirm cached tasks plus the same pending request survive. Reconnect and retry; confirm one server submission and no duplicate earning.
4. Request a reward offline; restart/reconnect/retry and confirm one request with saved price. Request grants no coins or reward by itself. Cancel a pending reward once and retry safely.
5. Check daily/weekly/monthly navigation, original task dates, Sunday week boundaries, protected-score day icon and separate actual XP/coins. Missing/unfinalized days must not look like confirmed bad days. Parent finalization/approval UI belongs to Phase9; don't assume a phase8 read-only status can perform those actions.
6. Check approved/returned/rejected decisions and notes when a parent-capable service workflow supplies them. Returned work may be resubmitted while unsealed; sealed results cannot be modified.
7. Check achievement/cash/privilege recommendations and Teen requests; confirm pending requests do not change balances/privileges. Parent confirmation screens follow in Phase9.
8. Sign out/switch family identity and confirm old cached family details do not appear under the new session. Phase7 private-health behavior remains separate.

## Limits

Build and source review do not establish cloud RLS correctness, concurrent behavior, actual offline restart/retry or final device results. No new automated tests are run without an explicit request. Completion requires observed walkthrough results, not just a successful build. Record any feature still missing in the coverage matrix.
