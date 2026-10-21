# Phase 7 next owner actions — revised scope

## Current state

The calendar correction and new Parent control/sharing sources build successfully. The Samsung disconnected before installation, so reconnect/unlock it for the coordinator to install both updates in place. No local app data was cleared. These new features are not yet accepted as working on the phone or deployed to Supabase.

## Development database upgrade

After the coordinator confirms the prepared revision is ready:

1. Open Petal Quest Dev SQL Editor: https://supabase.com/dashboard/project/hijtwgugzzpjjkuutyfy/sql/new . Confirm development project reference hijtwgugzzpjjkuutyfy.
2. Open `E:\CAT\Petal Quest\Android Dev\supabase\phase7-parent-health-upgrade.sql` in Notepad, copy all, paste into a new query and run once.
3. Report Success. No rows returned or the sanitized error. The atomic upgrade adds the two new migrations to an existing accepted Phase6 schema and refuses an already-upgraded schema. Do not drop tables, rerun the Phase6 initial bundle or expose the private schema.
4. Alert policy remains disabled after this upgrade. No prior private dates are uploaded merely by running SQL.

No administrator or service-role key is needed in chat or Android configuration. The coordinator has no authorized database admin connection; this SQL action needs the owner console.

## Enroll the fictional Teen device and date sharing

1. Keep the Samsung online and the Teen app paired to Test Family 1. In Private cycle log use Set up parent device controls and authenticate with the phone lock. Note the stable device code. This setup does not read the journal and works even if its key cannot open.
2. Unlock the private journal, acknowledge/enable the date-sharing notice, and share only fictional periods for this trial. Descriptions/notes stay local. Confirm both period fields now open their own date pickers and daily calendar selection preserves the period form.
3. In Parent Dev, switch to live service, refresh family access, then refresh device status and period dates. Match the stable device code; verify fictional start/end dates appear and daily details do not.
4. After preserving any desired fictional test backup, use the Parent-only remote deletion action, type DELETE and confirm the correct device. Keep the Teen app online/open; refresh Parent status until completed. Confirm Teen relocks and its fictional journal/shared live date rows are erased. Repeat/retry must not delete a new journal. Do not perform this test with real records.

The initial unlock and persistence check already passed by owner report. Remaining corrections/validation, cancel/background/screen-off, encrypted export and new sharing/deletion acceptance remain open. The other family phones are unnecessary for this first trial.

## Remaining alert choices and manual setup

Pain threshold is confirmed as 7-10. Still needed:

- Only today's saved entries, or also backdated entries/corrections?
- Fixed notification text: Petal Quest: please check in, or Check on daughter — feeling pain?

After these answers, the coordinator can supply the exact policy activation query. The generic alert transport additionally needs a development FCM service account stored only as a Supabase Edge secret, deployment of `supabase/functions/parent-checkin-push`, and an authenticated server schedule. Source/readiness instructions are in that function's README; no worker or schedule is currently deployed. Do not send private keys in chat. No paid services or production project changes are authorized/required.

In Parent Dev use Enable / retry notifications to grant permission and register this Parent device. Successful registration alone does not prove alert delivery. Final acceptance needs a fictional qualifying saved pain entry and actual notification receipt after server setup.
