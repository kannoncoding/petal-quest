# Phase 6 isolated Android data verification

## Scope and isolation

The `:verification` Android application runs the real `:core:data` implementation using synthetic fixtures. Its application ID is `petalquest.verification`; its instrumentation APK is separate from both production applications. It declares no Internet permission, applies no Google Services plugin, and contains no Firebase configuration or valid credentials. `:core:network` is linked to preserve the shared module dependency context; these tests never instantiate a network client or make a cloud request.

Every test first asserts the target package is `petalquest.verification`. All storage changes are restricted to that package's private `no_backup/petalquest` directory and its UID-scoped Android Keystore alias. Tests neither read nor clear the Teen or Parent application data. No phone Wi-Fi changes are required.

The target compiles and targets API 37, with minimum API 24. The current test fixture uses Java NIO file helpers (API 26+), so execute this instrumented suite on API 26 or newer. This does not change the production app minimum API.

## Cases

Source: `Android Dev/verification/src/androidTest/java/petalquest/verification/LocalDataVerificationTest.java`.

| Case | Assertions |
| --- | --- |
| `cacheAndEncryptedSessionPersistAcrossCloseReopen` | A canonical Room snapshot survives owner close/reopen; saved session has the encrypted version frame and contains neither dummy token nor synthetic user ID in plaintext; Android Keystore decrypts both dummy tokens after reopening. |
| `queuePersistsStableIdCanonicalPayloadAndReconcileState` | UUID and canonical payload survive close/reopen and dispatch; pre-dispatch acknowledgement fails; repeat dispatch does not create a new intent; wrong IDs do not mark or acknowledge another operation; unresolved state survives reopening; exact acknowledgement removes the intent once. |
| `allOperationKindsRejectHealthUnknownCredentialsAndNestedFields` | All six operation kinds reject representative health, credential and unknown field names. Each kind rejects object and array values under an allowed field; no rejected payload enters the queue. |
| `logoutClearsCacheQueueAndCredentialsRetainsHealthMarker` | Logout removes credentials and current family cache/queue, invalidates the old handle, and retains a byte-identical synthetic health filename marker. Relogin has no previous family rows. |
| `accountSwitchClearsPreviousDataAndRejectsOldHandle` | Changing account invalidates old handles, rejects mismatched handle creation, and clears old cache/queue even when returning to the previous account. |
| `endpointSwitchClearsPreviousDataAndRejectsOldHandle` | Changing endpoint for the same account isolates both family cache and queue and invalidates the previous handle, including after switching back. |
| `logoutSameAccountReloginInvalidatesEveryOldHandleOperation` | After logout and same-account relogin, the previous handle rejects cache reads/writes, enqueue, pending reads, dispatch and acknowledgement. |
| `tokenRefreshPreservesExistingValidHandle` | Updating dummy tokens for the same account and normalized endpoint retains the handle generation, existing snapshot and queue, and allows dispatch from the valid existing handle. |
| `corruptSessionRequiresExplicitResetAndRetainsHealthMarker` | A flipped ciphertext authentication-tag byte causes session read, old-handle access, logout and replacement activation to fail without overwriting the damaged file. Explicit reset clears family/session state and preserves the health marker; same-account activation cannot reuse an old handle. |
| `atomicFileRecoversBackupWhenBaseIsAbsent` | Moving the encrypted session base to `.bak` simulates interrupted legacy AtomicFile recovery. Reading after close/reopen restores the exact encrypted bytes, removes `.bak`, and preserves family cache/queue. |

The health database is reserved for a later phase and deliberately exposes no data write API. The health check writes a synthetic marker to its reserved filename while that Room database is unopened. It proves file retention only; it does not claim encrypted health storage, health record persistence, or a health repository implementation.

## Running and evidence

From `Android Dev`, using the project's configured JDK and Android SDK:

```powershell
.\gradlew.bat :verification:assembleDebug :verification:assembleDebugAndroidTest
.\gradlew.bat :verification:connectedDebugAndroidTest
```

Observed result on 2026-10-21 at 16:01:24 UTC (10:01:24 Costa Rica): **10 tests passed, 0 failures, 0 errors, 0 skipped** on the connected Samsung SM-S918B running Android 16. The coordinating agent completed the build and connected-device run. The generated XML was inspected and lists all ten cases above; its suite duration is 1.718 seconds.

Evidence, relative to `Android Dev`:

- XML: `verification/build/outputs/androidTest-results/connected/debug/TEST-SM-S918B - 16.xml`
- HTML report: `verification/build/reports/androidTests/connected/debug/index.html`

This is one observed run on one device and Android version. Close/reopen tests exercise storage-owner lifecycle and persisted disk state within instrumentation, rather than a device reboot or an operating-system process kill. The backup test exercises `.bak` restoration with a missing base file; it does not simulate every possible crash timing or Keystore failure. The ciphertext inspection checks the saved session file for the known synthetic credentials and user ID and verifies successful decryption; it is not a cryptographic audit.

These are local storage and state transition tests. They do not verify backend authorization, genuine authentication/refresh, remote retry reconciliation, push delivery, cloud connectivity, or production Teen/Parent UI workflows.
