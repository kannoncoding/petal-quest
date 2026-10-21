# Petal Quest Android

Separate Teen and Parent applications with shared Kotlin/Compose and Java/Room modules. Phase 6 development foundation is accepted as complete (2026-10-21); see docs/phase6/Completion-Report.md for evidence and limitations.

## Modules

- app: Teen, petalquest.teen.dev in debug.
- parent: Parent, petalquest.parent.dev in debug.
- core:model, core:network, core:data, core:ui: shared contracts, HTTPS transport, account-scoped encrypted sessions, Room cache/queue and family access UI.
- supabase: ordered migrations, fresh-install bundle and synthetic verification tooling.
- verification: isolated offline Android storage instrumentation.
- liveVerification: separate development-only manual network/retry helper; not a product app.

## Build

Open this folder in Android Studio and sync Gradle, or use `tools/Build-Debug.ps1 -IncludeParent`. The helper builds, without running test tasks, using Android Studio's bundled JDK. APKs are under app/build/outputs/apk/debug and parent/build/outputs/apk/debug.

Current configured toolchain is declared in the wrapper/version catalog: compile/target API 37, production-app minimum API 24, Java 11 source, AGP 9.4.1 and Compose plugin 2.2.10. Verification helpers have their own documented minimums.

## Local configuration

No real configuration or credentials are tracked. Copy configuration-examples/supabase/development.example.json to ../Configuration/Supabase/development.local.json and fill only the development publishable key. Never use an administrator/service-role key in an app. service-config.gradle.kts reads the sibling Configuration directory and pins development/production endpoints; unconfigured live access stays disabled. Staging requires explicit separate matching service/Firebase configuration.

Place Firebase client files in app/src/debug/google-services.json and parent/src/debug/google-services.json with their matching petalquest.teen.dev and petalquest.parent.dev registrations. Release client files use the matching release IDs. Keep signing material, passwords, session tokens, database exports and private health data outside Git.

## Accepted development foundation

Both configured apps built and installed. Owner confirmed Test Family 1 enrollment for two parents and a teen. Recorded verification includes 10 Android instrumentation cases, 35 local PostgreSQL checks, 13 live unpaired checks, 10 hosted paired groups, owner-console private-outbox counts and owner-confirmed Samsung offline process-restart/reconciliation/replay. Keep each evidence source distinct; see docs/phase6.

The development schema and receipt repair were deployed. supabase/deploy-development.sql is for a fresh database and refuses an existing schema: never rerun it to repair an existing installation. Apply forward migrations only. The local Auth fixture in supabase/review is exclusively for a disposable local database, never hosted Supabase.

Phase 5 launcher/splash, UI icons, empty states and dog animations are integrated. Source asset masters and broader phase documents remain in the sibling Images and Documentation folders; they are not yet all included in this repository. Preserve that workspace backup too.

Production deployment and other family-phone compatibility are deferred. Full product quests/rewards/finalization, health logging/locking and reminder delivery are later phases; approval currently records raw contribution and never mints spendable XP/coins directly. Tests use fictional development fixtures, which remain as evidence. Real Teen/Parent sessions were not cleared for verification.

## Phase 7 implementation

The Teen app now includes a private cycle activity and a separate core:health encrypted local vault, phone authentication/relocking, calendar/history/optional observations, encrypted passphrase export and explicit health deletion. Parent has no core:health dependency. Both debug builds compile; the Teen update is installed on the Samsung. Static privacy QA passed after corrections. Phone feature acceptance is still pending, and no new automated Phase7 tests were run. See docs/phase7/Owner-Actions.md and Build-and-Privacy-Review.md. No Phase7 completion or restore interoperability is claimed.
