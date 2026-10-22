# Parent password recovery setup — development only

Prepared, not applied or live-verified. No recovery emails have been sent by the coordinator.

1. Open Petal Quest Dev (hijtwgugzzpjjkuutyfy), Authentication → Email templates (sometimes under Notifications → Emails).
2. Open Reset password / Password recovery. Preserve the existing template outside the repository if you want a local rollback copy.
3. Set the subject to Reset your Petal Quest password.
4. Replace its body with docs/phase9/Recovery-Email-Template.html. Keep {{ .Token }} exactly as written; Supabase replaces it with the one-time code. Save. Leave other email templates and production unchanged.
5. When the Parent APK is installed, use Forgot password? on the signed-out Parent screen. Enter the actual account email, request a code, read the email privately, return to the app and enter the code. Choose a new password of at least12 characters satisfying the project's server password policy. Then sign in normally.

The verified recovery credential is kept only in memory, does not activate a family session and is cleared when the app leaves the foreground. If you leave after verification, request a fresh code before continuing. If email delivery is unavailable/rate-limited, report only the sanitized error; do not change billing or share codes/passwords in chat. Fictional example.com test accounts cannot receive email; use an owner-controlled development test inbox for this separate recovery check.

References: [Supabase email template variables](https://supabase.com/docs/guides/auth/auth-email-templates), [Auth API recovery/verification](https://github.com/supabase/auth/blob/master/README.md). The implementation uses recovery-specific verification followed by an authenticated password update and discards the transient recovery session.
