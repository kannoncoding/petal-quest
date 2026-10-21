# Phase 7 — private cycle logging

Status: implementation started 2026-10-21. Source: development plan revision 4, page 11; privacy boundary page 2; recovery/export extension page 15. Phase 6 baseline committed and pushed to GitHub main as 2cd1620 before Phase 7 code changes.

## Approved lock decision

Owner chose the phone's screen-lock PIN/password or biometrics. The private section must request OS authentication on entry, relock on leaving/background, block without a secure screen lock, and keep parent approval authorization independent. Someone who knows that phone unlock credential or has an accepted enrolled biometric can unlock health on that phone. The Parent app itself receives no health-store API or data.

## Implementation scope

- Start/end dates, ongoing episodes, editable history and confirmed-date calendar.
- Reject invalid/future dates, end-before-start, duplicates and overlaps. Allow backdated corrections and missing optional observations.
- Optional daily subjective flow, self-described consistency, pain score/location, symptoms and notes. No inferred discipline evidence, predictions or medical advice.
- Period duration includes its start/end dates; interval between successive start dates is a distinct summary.
- Separate core:health dependency linked only by Teen. Whole encrypted local vault under noBackupFilesDir/private_cycle, standard AES-GCM, random per-store data key wrapped by an authentication-required Android Keystore key. No plaintext health Room data, family queue, Supabase endpoint, Firebase payload, logs, analytics or saved UI state.
- Phone-key authentication unwraps the data key into memory only for the active private session. Lock invalidates stale operations and clears keys/view state. Existing key/data loss or unreadable ciphertext fails closed; no silent data reset or replacement key.
- Explicit user-confirmed health deletions affect only health. App family logout retains the health vault. Explicit export is encrypted using a separate user-retained passphrase and a versioned standard KDF/AES-GCM format. No plaintext document export.
- Backup/data-transfer exclusions and secure-window behavior retained. Recovery/import and replacement-phone restore are Phase 11 work; lost device keys cannot be regenerated to decrypt an old vault. Lost export passphrases have no parent/admin reset.

## Team and evidence

Health storage developer and Teen UI developer implement separate files; independent privacy QA reviews static code and corrections. Coordinator handles integration, builds, Git history and owner handoff. No new automated tests have been requested or run for Phase 7. A successful build/static review will not imply physical-device authentication, backup or privacy acceptance.

## Exit evidence needed

Use fictional records only: owner authenticates on the Samsung, saves/reopens/corrects episodes and observations, confirms validation and calendar, backgrounds/returns to require authentication, cancels authentication, exports encrypted data and explicitly deletes only health content. Confirm no lock-screen previews/screenshots or shared/parent data exposure. Actual backup/transfer behavior on unsupported/unavailable phone versions remains unverified until those devices are available. Record each accepted scope honestly before phase closure.

## Integration update

Both debug applications build successfully. Independent static privacy review findings were corrected. The updated Teen APK was installed in place on the Samsung; existing application data was preserved. No automated Phase7 tests ran. Phase7 remains open for the owner fictional-record authentication/persistence/privacy walkthrough in Owner-Actions.md; see Build-and-Privacy-Review.md for exact hashes, findings and limits.
