# Parent check-in push worker — prepared, not deployed

Development-only server function for generic parent check-in messages. It never receives or sends notes, symptoms, pain scores, period dates or encryption keys. Firebase delivery is a notification transport; the authorized Parent app is the source for current family information.

Uses the official Google authentication library, pinned to verified npm version 10.3.0, to obtain short-lived FCM OAuth access tokens. The development Supabase and Firebase project IDs are pinned. A production deployment requires a separately reviewed configuration.

## Server configuration required

1. Deploy the reviewed health/alert migrations to development. Alert timing and notification wording must first be approved and enabled in the private policy row; its default is disabled.
2. Deploy this function as `parent-checkin-push`. Disable Supabase's legacy JWT gateway verification **for this function only**; the function independently requires the `x-petal-worker-key` secret on every invocation. Never put that secret in an Android app.
3. Add Edge Function secrets `PETAL_CHECKIN_WORKER_SECRET` (a random secret of at least 32 characters) and `PETAL_FCM_SERVICE_ACCOUNT_JSON` (the service-account JSON for Firebase **petal-quest-dev**, with permission to send FCM messages). Enter them only in the server secret manager; do not paste keys into chat or source control. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase's server environment.
4. Use an authenticated server scheduler to POST to the deployed endpoint, sending `x-petal-worker-key` from a protected secret store. No request payload is needed. Scheduling, secret provisioning and actual delivery are owner console steps, currently unperformed. Do not schedule paid services or change the project's plan.
5. The Parent app must register its own FCM token through the existing authorized device-registration RPC and have notification permission. A pending alert with no registered destination is not proof of delivery.

Ordinary clients cannot invoke the queue claim/complete RPCs: their grants are service-role only. The database rechecks current family/installation/parent membership at lease time. A revocation occurring after the lease and before network delivery can race with one generic in-flight notification.

Messages are data-only. The Parent app verifies its currently stored account matches the intended recipient before displaying the fixed text; logged-out and switched accounts discard the message. Token registration and notification permission require Parent-app setup.

Retries may send the same message again after uncertain transport outcomes. The stable FCM tag/collapse key replaces matching outstanding notifications where supported; exactly-once phone display is not promised. Queue completion means each destination was accepted by FCM or reported permanently unregistered. A batch containing only unregistered destinations produced no accepted send. Completion does not prove phone display or human receipt. Exported files and cloud/provider backup retention are outside remote deletion of current records.

No deployment, scheduler run or live FCM acceptance is claimed for this source. See [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api) and [Supabase server secrets](https://supabase.com/docs/guides/functions/secrets).
