# Petal Quest Android starter

This is the Phase 2 Kotlin/Jetpack Compose starter. Debug builds open a development-only Firebase connection/notification check; release builds retain the placeholder greeting. Product features and the separate teen/parent application modules are scheduled for later phases.

## Verified development toolchain

- Android Studio 2026.2.1, bundled JDK 25.0.3.
- Gradle wrapper 9.6.0 with distribution SHA256 pinned.
- Android Gradle Plugin 9.4.1; Kotlin Compose plugin 2.2.10.
- Compose BOM 2026.02.01; compile/target API 37; minimum API 24.
- Google services plugin 4.5.0; Firebase BOM 35.0.2; Messaging SDK only.

The wrapper and version catalog are the source for build versions. Use Android Studio's compatible bundled JDK; the computer's shell default Java can differ.

## Build on Windows

Open this directory in Android Studio, let Gradle synchronization finish, and build the app. Alternatively, run from PowerShell:

```powershell
.\tools\Build-Debug.ps1
```

For a different Android Studio location, pass `-StudioDirectory 'C:\your\Android Studio'`. The helper temporarily selects Studio's bundled JDK and a short Java socket directory inside the ignored `.gradle` cache, then restores the process environment. This fixes the Java selector startup error observed in the automation environment without modifying system settings.

The output is `app\build\outputs\apk\debug\app-debug.apk`. It is a debug-signed starter for toolchain checks; production signing comes later. Building requires the installed SDK and access to dependency repositories or their cached artifacts.

Firebase client configuration is supplied locally and ignored by Git. For a fresh checkout, download `google-services.json` from Firebase project **petal-quest-dev**, ensuring it includes Android ID **petalquest.teen.dev**, and save it at `app/src/debug/google-services.json`. Release configuration belongs at `app/src/release/google-services.json` from project **petal-quest**, matching **petalquest.teen**. Both files are already installed on the owner's current workstation. The namespace remains `com.example.petalquest`; the installed application IDs use the registered `petalquest.teen` names.

## Physical-device check

Enable USB debugging on the unlocked phone, connect a data cable, and authorize this computer. Select the phone in Android Studio and run `app`. The Phase 2 exit check still requires a real-phone launch and actual cloud authorization/FCM checks.

In the debug setup screen, allow notifications, obtain and copy the test token, and send a Firebase console test to that device while this app is in the background. Tokens are kept in memory and copied only on request; they are not logged or displayed in screenshots. The setup screen uses the documented console-compatible registration-token API; current FCM SDKs also offer newer Installation ID registration, which needs review when building production device registration.

Official setup reference: https://firebase.google.com/docs/android/setup. Console test procedure: https://firebase.google.com/docs/cloud-messaging/android/get-started#send_a_notification_message.

## Repository hygiene

Keep SDK paths, signing material, administrative credentials and real family/health records outside Git. `.gitignore` excludes local settings, build caches, environment-specific Firebase files, keys, databases and designated private folders. Only fictional data belongs in development fixtures; review every staged file before pushing. Supabase live authorization remains unverified.

The starter retains Android's template backup configuration. Implement and verify sensitive-data exclusions before adding private cycle storage.
