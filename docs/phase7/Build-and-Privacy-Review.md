# Phase 7 build and static privacy review

Status: implementation built and installed; physical-device feature acceptance pending. No new automated tests were added or run.

## Build/install evidence

Final command: Gradle :app:assembleDebug :parent:assembleDebug. BUILD SUCCESSFUL in 11 seconds; 167 actionable tasks (8 executed,159 up-to-date). Local log: build-debug.local.log. Uses the existing Android Studio JDK/Gradle cache and process-local selector temporary directory.

- Teen APK SHA256: 0ac43f701c1ba88e65154997436d37b0f82b34d3d5b54a05c047a8f8e8265047
- Parent APK SHA256: 320ff8bfcfe2f44a07b40b8db9c7e0efd3c7134e6b96f847ffad57b617f60c99

ADB install -r of Teen succeeded on Samsung R5CWB2MXQHZ; MainActivity launched. No app data was cleared. Parent was built for integration but not reinstalled. Static APK string inspection found CycleVault in Teen DEX and absent from Parent DEX; this is supporting dependency evidence, not a complete privacy penetration test.

## Reviewed controls and corrections

Independent static privacy QA reviewed both developer agents' code. Findings corrected: Costa Rica date timezone; Sunday calendar markers; no saved/autofill health form state; synchronous composition disposal and vault locking on stop; stale authentication callback/export destination cleanup; subjective enum flow; password keyboard settings; responsive flow choices; encrypted export; expensive password derivation moved off UI thread/outside the vault monitor; fresh phone authentication for destructive locked recovery reset without requiring a readable vault.

Storage uses standard AES-256-GCM with platform random IVs and authenticated envelope metadata; a random data key is wrapped under an authentication-required Android Keystore key. The active data key is only held for the unlocked session. Failure to open existing files/keys is explicit and does not silently create replacement content. Export uses PBKDF2-HMAC-SHA256 on API26+ or the documented standard SHA1 fallback on API24-25, random salt and AES-GCM; encryption parameters and future restore restrictions are documented in core/health/README.md. There is no plaintext file export or custom encryption primitive.

The new module has no networking dependencies. Only Teen depends on it; Parent has no health UI/API. All health content is in noBackupFilesDir/private_cycle, with whole-vault encryption. Shared family logout does not delete it. Existing all-domain backup/cloud/device-transfer exclusions remain in Teen XML. FLAG_SECURE applies to the private activity; forms are discarded on background, rotation or leaving. The store is device-local, not automatically synchronized by family membership.

## Limits requiring acceptance

A successful build/static review does not prove Samsung biometric/device-credential callback lifecycle, automatic locking/screen capture behavior, persisted corrections, validation usability, export ciphertext/portable restore or real OS backup/device-transfer behavior. Owner fictional-record walkthrough is in Owner-Actions.md. API24-29 credential fallback and other family phones are untested. Import/restore is Phase11; the encrypted format exists, but no successful restore is claimed.

Anyone with the accepted phone credential or enrolled strong biometric can unlock this phone's journal. Parent accounts gain no default data access through the Parent app. If a device-bound key or export passphrase is lost, no administrator/parent reset can decrypt the old data; destructive reset only removes it.

References: Android Developers cryptography, Android Keystore and biometric/device-credential authentication documentation. Full implementation notes are in core/health/README.md.
