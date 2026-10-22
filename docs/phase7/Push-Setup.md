## Delivery acceptance — 21 October 2026

Owner confirmed receipt of the approved Parent notification after saving today's fictional pain-8 entry in Teen. Development Edge worker, matching Edge/Vault worker secrets and minute schedule are operational for this observed delivery. Earlier deployment/delivery-pending statements below are historical. The missing Edge worker secret was added and the Vault value replaced; the sanitized header check then returned true (pg_net 0.20.4). Previous HTTP calls had failed before reaching the worker with a libcurl bad-argument error. Receipt confirms this delivery path, not all retry/revocation/expiry scenarios or either other family phone.

Phase 7 remains open for explicit date-sharing visibility, remote deletion and remaining journal privacy/export acceptance. Initial journal unlock/persistence and this actual push delivery are accepted by owner report. No new automated tests were run.

# Phase 7 push setup — owner console steps

Status: today-only policy/expiry repair applied by owner report. Worker, secrets, schedule and actual delivery are still pending. Development only; no plan upgrade is required by these instructions.

## 1. Firebase development server credential

Open Firebase project petal-quest-dev → Project settings → Service accounts → Generate new private key. Keep the downloaded JSON outside the project/repository. Open it locally for step 2; it is not the Android google-services.json. Do not send it in chat. If key creation is unavailable, report that blocker without changing organization policy.

Reference: [Firebase server credentials](https://firebase.google.com/docs/admin/setup).

## 2. Supabase Edge Function secrets

In Petal Quest Dev (hijtwgugzzpjjkuutyfy), open Edge Functions → Secrets. Add:

- PETAL_FCM_SERVICE_ACCOUNT_JSON: the complete JSON from step 1.
- PETAL_CHECKIN_WORKER_SECRET: a newly generated random secret, at least 32 characters.

To generate a secret in PowerShell without printing it, run:

```powershell
$petalRandom = New-Object byte[] 32
$petalRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$petalRng.GetBytes($petalRandom)
$petalRng.Dispose()
[Convert]::ToBase64String($petalRandom) | Set-Clipboard
```

Paste this value into the Edge secret, then also save the SAME value in Supabase Vault as a secret named petal_checkin_worker_secret (step 4). Do not regenerate between those two pastes. Do not copy either secret into source files or Android. Supabase supplies the worker's service-role environment variable itself.

Reference: [Edge secrets](https://supabase.com/docs/guides/functions/secrets).

## 3. Deploy the function

Edge Functions → Deploy new function → Via Editor. Name it parent-checkin-push. Replace index.ts with the complete contents of:

E:\CAT\Petal Quest\Android Dev\supabase\functions\parent-checkin-push\index.ts

Deploy. In this function's settings only, turn OFF legacy JWT verification: requests are authenticated by the worker's x-petal-worker-key header instead. Keep that secret server-side. Report a sanitized deployment error if one occurs.

Reference: [Dashboard deployment](https://supabase.com/docs/guides/functions/quickstart-dashboard).

## 4. Schedule delivery

Enable pg_cron and pg_net in the development database Extensions screen. In Vault create exactly one secret named petal_checkin_worker_secret using the SAME value saved in step 2. Then open SQL Editor and run all of:

E:\CAT\Petal Quest\Android Dev\supabase\phase7-schedule-parent-checkins.sql

Expected: one active job named petal-parent-checkins-development, schedule * * * * *. The job invokes the worker every minute; it does not send a notification when no eligible delivery exists. Do not paste a literal credential into SQL. Clear the clipboard after saving the matching secrets.

Reference: [Scheduled functions and Vault](https://supabase.com/docs/guides/functions/schedule-functions).

## 5. Accept delivery

Follow the fictional-record walkthrough in Owner-Actions.md. Parent must be signed in, registered for notifications and online. Background it without force-stopping. Save today's fictional 7–10 pain entry in the enrolled Teen journal. Wait for the schedule; report receipt of High pain levels today - please check in or a sanitized function status. Keep tokens, credentials and health descriptions out of screenshots.

FCM acceptance, queue completion and phone display are different outcomes. Delivery has not yet been demonstrated. A delayed message expires at the next Costa Rica midnight. No records/alerts from backdated days qualify.
