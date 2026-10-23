# Phase 11 preparation — settings, recovery and operations

Status: prepared for implementation, 23 October 2026. Phase10 is accepted under the owner's Samsung-only preproduction scope; see ../phase10/Completion-Report.md. No Phase11 feature completion or production deployment is claimed.

## Standing decisions

- Private family use only: owner, girlfriend and daughter. No public distribution/marketing scope.
- Use the owner's Samsung for all preproduction phone acceptance. Other family phones join only when production apps/environments are ready. Do not request them in development.
- Keep development and production separate; no production changes are authorized by preparation or the Git push.
- Manual Supabase account administration/recovery; custom SMTP and in-app email recovery remain deferred.
- Private cycle journal uses phone screen-lock credentials or biometrics. Parents may see period date ranges and the approved generic pain alerts, but not descriptions/notes. Parent remote wipe authority does not grant journal read/export authority.
- Shared reflections are Parent-editable and Teen-readable. Shared history/XP/coin rules remain unchanged.

## Current code inventory

| Area | Existing | Phase11 work |
| --- | --- | --- |
| Journal backup | core/health/CycleVault.java exports passphrase-encrypted JSON; PrivateCycleActivity launches Android CreateDocument after authentication | Implement explicit import/restore and its validation/confirmation flow |
| Backup format | Version1 format petalquest-cycle-backup; authenticated metadata; password-derived encryption key; minimum12-character passphrase | Preserve version1 compatibility, bound file/KDF sizes, authenticate before parsing or writing, reject wrong passwords/tampering/unsupported versions safely |
| Private lifecycle | Journal locks on background; authentication and generation checks; remote-wipe/replacement synchronization | Restore must recheck current identity, wipe/replacement generation and authorization before committing; no stale import may resurrect a wiped journal |
| Shared records | Authoritative Supabase records plus local authorized caches and durable queues | Export/data-removal scope, replacement-device/revocation runbook, stable signing/schema compatibility |
| Local preferences | Notification quiet hours/snooze and personal reminder controls | Inspect language/theme/other app settings coverage; collect preferences before implementation |
| Account recovery | Manual owner administration selected | Document exact supported lost-login/lost-phone flow without adding SMTP |
| Operations | Development migration/Edge/Cron scripts and reports | Manual encrypted backup custody, isolated restore exercise, service outage/resume and usage monitoring guidance |

Inventory is source-only; no real journal, session, credential or backup payload was opened. Import/export implementation is not yet changed.

## Implementation order

1. Confirm backup passphrase custody and destination, language/theme choices, and later Parent quick-unlock preference. Keep secret values out of chat.
2. Define backup/import format limits, version compatibility, replacement versus merge behavior, family/Teen identity mapping and wipe-generation safeguards. Ask before choosing a flow that changes data semantics or access.
3. Implement authenticated, user-selected journal restore with complete validation before an atomic write; cancellation, wrong passphrase and invalid files leave the current journal unchanged. Keep imported private details off the shared backend and Parent screens.
4. Add agreed app settings and explicit export/deletion descriptions distinguishing device cache, account/family history, private journal and previously exported files.
5. Prepare manual account/lost-device recovery and encrypted database backup/restore runbooks. Restore backend backups only into an isolated environment; never overwrite the current family database as an exercise.
6. Document compatible app/backend updates, signing-key custody, basic usage/cost checks and service resume. Verify current official provider instructions/limits when implementing those operational steps; do not upgrade billing automatically.
7. Use synthetic data on the Samsung for restore/failure/recovery checks. No backups of actual family/health data are needed during preparation. Carry independent-device observations to the private production rollout.

## Decisions needed

- **Health backup passphrase custody:** Teen only, or shared with parents? Anyone with the backup and passphrase can read its private journal contents; sharing custody would expand access beyond the existing Parent app view.
- **Encrypted backup destination:** owner-selected PC storage, private cloud folder through the Android picker, or another destination. Store the passphrase separately from the backup.
- **Language/theme:** English only or English/Spanish; follow phone theme or offer explicit light/dark/system controls.
- Later: Parent quick unlock (if desired), weekly manual backup routine and whether journal import replaces or merges existing entries.

These choices guide implementation. No passphrases, SMTP credentials, production keys or private records should be sent in chat. No recurring automation is created by a manual-backup plan.

## Exit evidence to collect during implementation

Encrypted export/import round-trip on fictional entries; canceled/failed auth, wrong password, tampered/truncated/oversized/unsupported backup rejection; unchanged data on failure; background-lock behavior; wipe/replacement race handling; shared/private export boundaries; manual account recovery; isolated backend restore and compatible in-place update. Record actual results and explicit deferrals, not inferred passes.
