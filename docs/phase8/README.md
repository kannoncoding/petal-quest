# Phase 8 — Teen quests, rewards and history

Updated 21 October 2026. Status: local implementation built and independently source-reviewed; development SQL deployment, APK installation and owner acceptance remain pending. Phase8 is not complete.

## Implemented locally

- Daily/weekly authoritative occurrences with the approved task changes and unchanged XP; historical submitted/finalized snapshots stay intact.
- Durable offline completion, reward, extra-outcome and appeal requests with stable identities. Cached membership/dashboard access survives cold start; no local confirmation of XP or Coins.
- Server review status/notes, original-day attribution, returned-work resubmission until sealing and parent-decided late credit.
- Confirmed daily earnings/Coins, available-coin ranks, eight protected-score performance icons and day/week/month navigation. Ordinary finalization supports every score: unsubmitted0, pending reviews must resolve first.
- All29 reward entries and6 achievement definitions, fixed5 deduction types,10 source privileges plus skincare/Hikari/week-plan outcomes, tracker cash/consequence guidance, and free Teen extra-outcome requests awaiting Parent confirmation.
- Server-side same-family review, fixed deductions, ordinary finalization, reward approval and pre-fulfillment refund building blocks. Their full Parent screens belong to Phase9.
- Approval animation reacts only to newly observed confirmed transitions; cached refresh/range changes do not replay initial approvals. Reduced-motion option and existing private-cycle entry remain available.

## Full tracker coverage

The live Google Sheet was read without modification. See Tracker-Feature-Coverage.md for every source feature and its implementation phase. Approved owner overrides supersede source task labels, weekend research/time errors and legacy manual coin conversion. Personal completion history and notes were not imported.

Reflection-note editing/permissions, Parent editors/history and explicit outcome-confirmation/accounting are Phase9 work; contextual reminders/background notification completion are Phase10. Excuse allocation/bonus conversion and negative-balance correction policy still need their remaining rules before those mutations can be enabled. Source features are not silently discarded or claimed deployed.

## Build evidence

Both debug APKs: BUILD SUCCESSFUL in10 seconds;167 tasks (4 executed,163 up-to-date). No new automated tests or SQL runtime tests were run. Source review is not evidence of deployed RLS correctness or actual device/offline behavior.

- Teen SHA256: A75ABDBDE4616A7F49B98CE178AF2BB54F93695B9CDF3A5150366CD77EA58221
- Parent SHA256: BACEE4EB48FBE78FF74C752D93EC6ADD97981E9C995C53DFE9279E0F1D424970

No Android device was connected at the latest ADB check. Neither new APK has been installed yet. Existing app data will be retained on in-place install. The compatible shared family API remains version1; the new dashboard contract advertises version2 additively.

## Next owner actions

1. Open Petal Quest Dev SQL Editor (project hijtwgugzzpjjkuutyfy).
2. Copy all of E:\CAT\Petal Quest\Android Dev\supabase\phase8-teen-upgrade.sql into a new query and run once. This is the forward Phase7→Phase8 upgrade; do not run deploy-development.sql or rerun Phase6/7 initial bundles. Keep petal_private outside exposed API schemas. No new key or Firebase setup is needed.
3. Expected row: effective_from2026-10-21, task_variants28, rewards29, achievements6. Report only that result or sanitized error. The prerequisite/already-applied checks stop incompatible reapplication.
4. Reconnect/unlock the Samsung and notify the coordinator for in-place installation of both prepared apps. No other family phone is needed for the first trial.
5. Follow Owner-Walkthrough.md and report actual results. Parent review/confirmation user interfaces follow in Phase9; do not imply an absent Parent button is already implemented.

Code/build/source readiness and owner acceptance are separate milestones. No production changes or cloud deployment are claimed.
