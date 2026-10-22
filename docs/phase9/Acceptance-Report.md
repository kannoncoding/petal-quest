# Phase 9 acceptance report — 22 October 2026

Status: in progress. Do not treat build, installation, schema flags or source review as live functional acceptance.

## Confirmed evidence

- Owner confirmed the development upgrade returned `parent_dashboard_ready`, `corrections_ready`, `bonus_ready`, `notes_ready` and `rls_enabled` all true. Do not rerun that forward upgrade.
- Owner deferred custom SMTP and in-app email password recovery for this private family application. Prepared recovery code remains in source; the Parent entry point is removed. This is excluded from Phase 9 acceptance.
- Coordinator rebuilt Teen and Parent: Gradle `:app:assembleDebug :parent:assembleDebug`, BUILD SUCCESSFUL in 12 seconds, 167 tasks (15 executed, 152 up-to-date).
- Coordinator installed both APKs in place on Samsung SM-S918B, serial ending QHZ; ADB returned Success for each. No uninstall or app-data clearing was performed.
- Installed Teen APK SHA256: `B11072AC789C6EA84AE21D6243402B9335975A25A20CF7C1469C7CA1832D42C5`.
- Installed Parent APK SHA256: `6CD7B88FC1500F819F078690532A6F3E8C5FC90654B658A3E2CFE4174F5C74C7`.

## In progress

- Owner phone walkthrough: first group requested is submit → Parent return → Teen resubmit → Parent approve, with no approval-only wallet award. Owner reported tapping Return in Parent, but Teen continued to show awaiting review. This group failed acceptance; no committed Return is claimed. Static diagnosis found a PL/pgSQL variable/column ambiguity in the audit trigger that can roll back the action. Migration014 and phase9-review-fix.sql repair the function; Owner confirmed phase9_review_audit_fix_ready=true; live retry is pending.
- Dedicated fictional-family backend acceptance runner passed JS syntax and PowerShell parsing checks. First live attempt failed Parent A authentication (HTTP400), before B/C sign-in, fixture creation or scoring mutations. Exact Auth error was not retained; diagnostics have been corrected to identify each Parent and known sanitized Auth error codes. No live functional gate passed. Owner reports accidentally closing the PowerShell window. No conclusion about the account/password validity is justified from that report. A fresh hidden-prompt run is pending after the SQL repair; passwords stay local.
- Plan 9.2 assigned routine schedules were identified as distinct from duty recurrence/deadlines. A separate versioned Parent editor and Teen read-only schedule are now implemented, source-reviewed, built and installed. Owner confirmed their additional forward SQL upgrade (`supabase/phase9-routines-upgrade.sql`) returned routines_ready=true and rls_enabled=true. Live schedule verification is pending. Notification scheduling/delivery remains Phase 10.

## Remaining acceptance

Use Acceptance-Checklist.md and Owner-Walkthrough.md for review races, finalization thresholds, nonlinear deductions/reversals/debt, bonus provenance, appeals/sealing, rewards and extra outcomes, effective-dated editing, shared notes/history, retries and session/family isolation. Record API results separately from phone observations. Two independently authenticated Parent sessions can verify server concurrency without requiring two physical family phones.

The Parent-dependent Phase 8 finalized-accounting/review/appeal gates stay open until the relevant observations are recorded. Real server sealing boundaries and private outbox audit require their own evidence; a source check cannot close them. No health journal contents or real tracker history are part of this walkthrough.

## Review repair owner-applied; live retry pending

- Independent QA confirmed the `topic` local variable in `phase9_audit_outbox` conflicts with the INSERT conflict-column name. Both dashboards already read the same submission status; no fabricated client status override was added.
- `supabase/phase9-review-fix.sql` is the minimal forward repair: prefixed local variables, unchanged triggers/payloads/privileges, no task/wallet data rewrite. Owner confirmed the readiness flag true. This proves function definition only; actual workflow must be repeated.
- Parent decision failures now display an immediate dialog and the status message near dashboard refresh, rather than only at the bottom of a long page. Existing unresolved request identities are preserved for uncertain failures.
- Latest build passed: 12 seconds, 167 tasks (4 executed,163 up-to-date). Updated Parent SHA256 `4C972B4E6EA53D8FB011457127832AE6D90BA1060F3F81A8F5104AFD778140E8` is prepared but NOT installed: ADB found no devices on attempted installation. Reconnect/unlock Samsung for this incremental update. The previously installed hashes above remain the installed evidence.
QA hidden-password window reopened after owner confirmed the repair (process43096). Backend results pending; no extra live pass is asserted. ADB still showed no connected phone, so the Parent feedback APK remains prepared but not installed.

## Baseline live backend run passed

Owner screenshot and saved sanitized report agree: 22 October 2026 at12:06:21 Costa Rica time,15 PASS,0 FAIL,9 UNVERIFIED. See Backend-Acceptance-Results.md for exact gates and limits. The accounts all authenticated; the earlier authentication attempt is superseded for those accounts. Server Return/resubmission, stale-generation denial, concurrent approve/approve, note permissions/history,100/99/85/80 earnings, nonlinear deduction/reversal, conversion no-doubling, appeal rejection guard, saved-price refund/fulfillment and debt spending denial passed. Phone display/interaction remains separate and is pending the owner's retry.

Samsung reconnected; coordinator installed the prepared Parent feedback APK in place successfully (SHA2564C972B4E6EA53D8FB011457127832AE6D90BA1060F3F81A8F5104AFD778140E8). The earlier disconnected-install limitation is resolved. No app data was cleared.
## Device refresh mismatch and second batch

Owner confirmed returned duty/note reaches Teen after014. After resubmission/Parent approval, Teen still appeared pending; requested explicit Parent dashboard History status and service acknowledgement plus explicit Teen refresh. This phone approval check remains open.

Coordinator found the built Teen foreground-refresh update had not yet been installed with the Parent feedback update. Teen APK SHA256BEF775D329B0A10BB957BA53DCE2F0BB9B118E1C39DF3E4FB3A01F58ABB9DE60 was then installed in place successfully. Parent4C972B... remains installed. Current builds refresh server snapshots on return from another app, without replaying queued mutations. Actual phone observations must confirm it.

Second QA batch credential window opened (process29896); results pending. Baseline audit SQL is read-only, scoped to the exact prior two fictional actors, and emits aggregate booleans/counts rather than payload contents. Owner result pending.
## Latest owner acceptance

- Phone return + note, resubmission and approval now show correctly in both apps after current-build installation/refresh. Owner confirms XP and Coins remain0 after approval, as required before day publication. This resolves the reported status mismatch; device finalization remains separate.
- Second live batch at12:20:16 Costa Rica:14 PASS,0 FAIL,6 UNVERIFIED. Review/reward races, floor0, explicit cash/privileges, routine and catalogue versions, approved appeal linkage, separate Node process replay and80/20 conversion thresholds all passed. See Backend-Acceptance-Results.md; duplicate login checks are not unique extra scenarios.
- Owner read-only outbox audit: all11 booleans true,0 private relations readable by anon/authenticated, exact one source event/minimal payload across baseline facts. This closes the baseline private-outbox gate. No push delivery pass is inferred.
- Owner requested next: execute each complete rollback-only revocation and synthetic seal fixture separately, and perform phone batch review/publication against its server preview. No SQL fixture result or device publication pass is asserted yet.
## Published result and latest Teen build

Owner finalized a day with78 actual task points;0 earned XP/coins is expected below85. Owner then confirmed published information displays correctly in both apps and proceeded with further submissions; no specific later total was supplied. Phone review/publication/display accepted to this scope, not a fabricated200-XP result.

Teen Quests now displays today's finalized/sealed summary from authoritative day_summaries and links to that date in History. It distinguishes actual/protected points from earned XP/coins and explains the below85 threshold. Latest build passed in11 seconds (167 tasks,4 executed/163 up-to-date); Teen APK SHA256F0515358E95C2366702014A58FB7A4279AA3D8ED519E65744C3B9F065B2EB491 installed in place successfully after the owner's current task check finished. Parent4C972B... remains installed.

Both earlier rollback fixture scripts now explicitly enable RLS on their temporary result tables. Owner pasted the updated revocation query; coordinator confirmed its RLS statement and instructed plain Run without RLS auto-editing in Dev, retaining final ROLLBACK. Results pending. A separate activated-version/saved-price rollback fixture is prepared and independently reviewed, not executed. No fixture is a production migration or a claim of literal midnight/HTTPS gateway testing.

Owner explicitly approved commit/push to GitHub main; code and safe reports may be committed, local credentials/fixture identifiers/results remain ignored.