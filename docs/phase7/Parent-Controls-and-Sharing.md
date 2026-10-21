# Phase 7 owner changes: parent controls and limited sharing

Status: both apps built, statically reviewed and installed. Owner confirmed the expected activated policy row and expiry repair. Worker/secrets/schedule and feature acceptance remain pending. This supersedes earlier Phase7 statements that all health stays local and Teen can bulk-reset/delete its journal.

## Confirmed changes

- Both period start and end have dedicated calendar pickers. Selecting a daily calendar date no longer resets an unfinished period form. Ongoing periods retain a blank end.
- Teen has no delete-all/reset health control. Individual record corrections/deletions remain available; the owner restricted bulk deletion.
- Parent may request remote deletion of a specific enrolled Teen device's local health journal. The app processes it on its next active, connected synchronization; it is not an instant operating-system remote wipe.
- Parent may read only confirmed period date ranges. Daily descriptions, notes, symptoms, consistency, flow category, exact pain score/location and encryption keys remain local.
- Pain scores 7-10 trigger a generic check-in candidate after a daily entry is saved. This is a family notification preference, not a clinical severity assessment.
- Owner approved today-only entries in Costa Rica, with text: High pain levels today - please check in. The policy is activated by owner report. Dispatch and receiver expiry guards prevent a prior-day message being displayed as today. Backdated entries do not qualify.

## New data boundary

The private encrypted vault and export remain on-device under the original protections. Explicitly enabled sharing sends start/end dates to a family-isolated Supabase table and, once configured, a generic check-in date/flag to an authorized recipient queue. These server metadata are not covered by Android's local backup exclusions and may be subject to provider backups/retention. Notes and symptoms are absent from these payloads. No health input affects XP or parent task-approval authority.

Device-control setup requires the matching Teen family session and fresh phone authentication but can run without opening a damaged health vault. This enrolls metadata only and gives a stable device code for the Parent screen. Date sharing is enabled separately after opening the journal and acknowledging the limited-sharing notice. Historical dates are not silently uploaded at app startup.

## Remote deletion safeguards

- Parent request binds installation, enrollment generation, current Teen identity/actor and family; stale confirmations cannot target a later journal generation.
- Only an active same-family parent can request; issuer/target authority is rechecked when the Teen claims the command under a family lock. Authorization takes effect at this atomic claim; later revocation can race with an already authorized in-flight action.
- Before erasure the Teen persists a local applying receipt outside the journal. After erasure it persists done, then acknowledges the server. A crash/retry cannot erase a newly created journal again; opening a new journal is blocked until the pending command/ACK/generation rotation is resolved.
- Acknowledgement removes live shared date/check-in metadata and reports completion even if the local journal was empty. No deleted record count or prior presence is exposed.
- Offline/logged-out devices cannot claim new commands. Unclaimed requests expire after 30 days; Parent can issue a new request. Already exported backups, OS app-data removal/uninstallation and provider backup retention are outside this app command.

## Push delivery

A prepared development-only Supabase Edge worker uses server-held FCM service-account credentials and service-role-only queue leases. Data-only messages include an intended parent identity; the Parent receiver checks its current account before displaying approved fixed text. No raw health details or tokens are logged. Retries are deduplicated/tagged, but exactly-once phone display and human receipt are not guaranteed. The policy is applied; worker deployment, scheduler and server secrets remain pending. Actual delivery is not accepted yet.

## Evidence

Both debug apps compile; Node syntax-check of the Edge TypeScript source passes. Independent source QA reviewed device/generation targeting, correction synchronization, claim/ACK crash handling, enrollment recovery, limited payloads, disabled alert privacy gate and receiver account gating. No new automated tests or SQL runtime checks were run. The previous initial unlock/persistence walkthrough was owner-confirmed successful before these changes. Both revised APKs are now installed in place on the Samsung. New sharing/deletion/delivery walkthroughs remain pending.
