# Parent password recovery setup — development only

DEFERRED by owner on 22 October 2026 for private family use. Parent recovery UI is hidden; this optional future setup is not a Phase9 completion requirement. Owner-managed Supabase account administration is the chosen approach. No recovery emails have been sent by the coordinator.
## Prerequisite: custom SMTP

The development dashboard requires custom SMTP before editing email templates (owner screenshot confirmed 22 October 2026). Select Set up SMTP to open configuration. This requires an email-sending provider's SMTP host, port, username/password and sender details; the button does not create a provider account or credentials. Provider selection and configuration are pending owner input. Keep credentials in provider/Supabase settings, never in chat or this repository.

After SMTP is configured, follow the template steps below. The prepared Parent app expects a recovery code using {{ .Token }}; its recovery screen does not handle the default email's reset link. Recovery remains pending while other Phase 9 walkthroughs can proceed. See [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

1. Open Petal Quest Dev (hijtwgugzzpjjkuutyfy), Authentication → Email templates (sometimes under Notifications → Emails).
2. Open Reset password / Password recovery. Preserve the existing template outside the repository if you want a local rollback copy.
3. Set the subject to Reset your Petal Quest password.
4. Replace its body with docs/phase9/Recovery-Email-Template.html. Keep {{ .Token }} exactly as written; Supabase replaces it with the one-time code. Save. Leave other email templates and production unchanged.
5. When the Parent APK is installed, use Forgot password? on the signed-out Parent screen. Enter the actual account email, request a code, read the email privately, return to the app and enter the code. Choose a new password of at least12 characters satisfying the project's server password policy. Then sign in normally.

The verified recovery credential is kept only in memory, does not activate a family session and is cleared when the app leaves the foreground. If you leave after verification, request a fresh code before continuing. If email delivery is unavailable/rate-limited, report only the sanitized error; do not change billing or share codes/passwords in chat. Fictional example.com test accounts cannot receive email; use an owner-controlled development test inbox for this separate recovery check.

References: [Supabase email template variables](https://supabase.com/docs/guides/auth/auth-email-templates), [Auth API recovery/verification](https://github.com/supabase/auth/blob/master/README.md). The implementation uses recovery-specific verification followed by an authenticated password update and discards the transient recovery session.
