# Dedicated live Phase 6 offline probe

This module is **network enabled**, uses application ID `petalquest.verification.live`, and is separate from the existing `:verification` instrumentation module. It has INTERNET and ACCESS_NETWORK_STATE permissions, no Firebase dependency, no shared app storage, and disables Android backup and screenshots. Existing synthetic instrumentation remains unchanged.

Only the development service URL is accepted at runtime, including release variants. Public service configuration comes from the existing local build configuration. Never pass a password or token in build arguments, shell commands, logs, or evidence exports.

Build `:liveVerification:assembleDebug`, install its APK, and open **Petal Quest Live QA**. Enter only fictional `qa-parent-c@example.com` credentials on the device. The parent session stays in memory and is signed out with local scope after pairing. The password field has save and autofill disabled. Preparation resumes only a `QA P6 ` family or creates `QA P6 Offline ...` if parent C has no membership. It creates a separate anonymous teen without revoking any existing actor. The teen session uses the shared encrypted SessionStore in this app's own sandbox. Server family creation provisions the catalogue; reconciliation obtains only known due occurrences. No known deadline at least five minutes ahead means blocked, not a pass.

1. Prepare online. Note the selected occurrence and its known deadline.
2. Disable both Wi-Fi and mobile data using Android controls, then queue locally. This calls the real QueuedSubmissions.enqueue and saves the real repository request UUID.
3. Force stop only `petalquest.verification.live`, relaunch while still offline, and press the restart verification button. A process UUID change and the same persisted queue payload are required.
4. Reconnect internet and send. This calls the real QueuedSubmissions.retry adapter. It acknowledges only the exact authenticated server request receipt, then displays the empty queue.
5. Replay the same request. The server must return the same request and submission IDs; an authenticated submissions query must return exactly one matching row.
6. Display sanitized JSON evidence. It contains only the probe application ID, request/submission IDs, pending count, restart flag, and replay flag. Screen text can also be captured as evidence.

Restore the device's original Wi-Fi/mobile data settings after the probe, including if a step fails. The app does not change connectivity settings itself. Prepare cannot overwrite an existing probe. Never clear app data or uninstall while an unresolved queue needs to be retained.

The offline steps refuse any active INTERNET-capable network, conservatively requiring the owner to disable connectivity. Online status is provisional until the authenticated requests complete. The UI does not claim a failed offline dispatch was performed: it proves offline enqueue, persistence across process restart, online real-adapter acknowledgement, and server idempotent replay. No runtime success is claimed merely by building or installing this module.
