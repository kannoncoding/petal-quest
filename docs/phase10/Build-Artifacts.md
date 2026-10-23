# Phase 10 APK build history

## Current prepared repair — 23 October 2026

Notification burst/confirmed-registration repair built successfully in 9 seconds: 206 tasks, 7 executed and 199 up to date. Both APKs are prepared, **not installed**; Samsung was disconnected at the latest check. Live notification acceptance remains pending.

| App | Current APK | SHA-256 |
| --- | --- | --- |
| Teen | app/build/outputs/apk/debug/app-debug.apk | `41F8C38F435DF58531F993453C8A829D2D933ED836403A2E73B2E908632FE1F1` |
| Parent | parent/build/outputs/apk/debug/parent-debug.apk | `82238075F0983B8810DE44F340CD7CC7629D6C2691F2D51A2D748EF8D1C5F408` |

## Previously installed build — 22 October 2026

The hashes below identify the build installed before the first phone walkthrough. The output paths have since been rebuilt with the repair above.

Both debug variants compiled successfully in 15 seconds: 206 tasks, 17 executed and 189 up to date. No device installation or Phase 10 runtime acceptance is claimed.

| App | Local APK | SHA-256 |
| --- | --- | --- |
| Teen | app/build/outputs/apk/debug/app-debug.apk | `DBB8EFC0C18CBC5E2CD9117C6C933D561B651E3AF0C53446213155B57FDB6BD7` |
| Parent | parent/build/outputs/apk/debug/parent-debug.apk | `86FA1BED9CCB486138D8107ABF26886ACF30DC3CEF0822C3C1D39E32DD845799` |

Includes confirmed Parent checkpoints, School checklist and Parent change approval, school/home reminder scheduling, Vacation controls and occurrence overlay preparation, local reminder settings and separate Special achievements. All owner policy choices are incorporated; development deployment and live acceptance remain pending.

## Repair deployment confirmed — 23 October 2026

Owner reports all four readiness checks true for phase10-notice-coalescing-fix.sql in Petal Quest Dev: grouped_notices_ready, grouped_fanout_ready, enrollment_cutoff_ready and fresh_delivery_priority_ready. No original upgrade was rerun.

Connected Samsung SM-S918B/R5CWB2MXQHZ: SHA-256 matched the prepared Teen 41F8C38F435DF58531F993453C8A829D2D933ED836403A2E73B2E908632FE1F1 and Parent 82238075F0983B8810DE44F340CD7CC7629D6C2691F2D51A2D748EF8D1C5F408 APKs. Sequential ADB install -r returned Success for both. No uninstall or data clear was performed.

Next acceptance: enable/retry notifications in both updated apps, leave Parent in background, request an edit to the existing fictional school item in Teen, and verify the Parent notification and pending change. Then approve in Parent and verify the Teen update. Physical display and delivery repair remain unverified until that walkthrough is reported.
