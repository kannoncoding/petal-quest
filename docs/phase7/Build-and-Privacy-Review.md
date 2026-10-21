# Phase 7 build and privacy review — current revision

Both updated applications built and installed in place on the connected Samsung. Existing app data was preserved. Gradle :app:assembleDebug :parent:assembleDebug succeeded in 9 seconds, 167 tasks (4 executed, 163 up-to-date). Local build log: approved-alert-build.local.log.

- Teen APK SHA256: 510FD3CF7155FEBC4D335E31C08E0F23B0286B1A70A045246B161828ECAD89C8
- Parent APK SHA256: 7F73A2E2332F7C3D077A73F4632D966310B83CBFBE4EB38BC52E04ABC8011D4B

Independent source review covered authentication/background clearing, vault fail-closed handling, export derivation outside the vault monitor, dedicated date pickers, limited payloads, generation-bound deletion, claim/ACK persistence, correction ordering, session refresh races, Parent receiver recipient gating and Costa Rica expiry. Parent has no CycleVault dependency. Teen has no bulk health deletion/reset control.

Owner reported initial journal unlock/persistence success and then the expected policy activation row (include_backdated=false, approved text). A read-only public endpoint check found health routes present and denied anonymous access (401/42501). This does not prove complete deployed permissions or feature behavior. The forward activation query applies migration004's expiry repair.

Node syntax check passed for the Edge worker source. No new automated tests or SQL runtime tests were run. Builds and static review do not establish phone authentication lifecycle, actual backup/transfer exclusion, portable restore, date-sharing/deletion behavior or push delivery. Worker/secrets/schedule remain pending. Other family phones and API24–29 fallback remain unverified. Import/restore remains Phase11.

The owner-authorized sharing scope supersedes earlier claims that all health data stays local: only confirmed period ranges and generic check-in metadata leave the device; notes, descriptions, symptoms, exact pain scores and keys remain local. Shared metadata is subject to provider retention. Remote deletion excludes exported files and provider backups. See Parent-Controls-and-Sharing.md, Owner-Actions.md and Push-Setup.md.
