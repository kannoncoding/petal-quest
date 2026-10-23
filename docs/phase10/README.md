# Phase 10 — synchronization and notifications

Status: complete for the owner's accepted Samsung-only preproduction scope, 23 October 2026. See Completion-Report.md for observed passes and explicit deferrals. Development migrations015–018, worker/routes and repaired APKs are deployed. Production remains untouched. Phase11 preparation is in ../phase11/Preparation-Report.md.

## Prepared scope

- Authorized foreground Realtime invalidation and refresh on resume; server responses remain authoritative.
- Connected WorkManager retries for durable Teen submissions and confirmed Parent actions, stable request IDs, guarded session refresh and retained actionable failures.
- Family-device registration and a separate committed-event push worker, with membership checks, per-device retries and discreet notification text.
- Local personal reminders, confirmed assigned-routine schedules, weekday/one-off recurrence, optional quiet hours and snooze, and rebuilding after reboot, update and clock changes.
- Teen 17:00 Costa Rica reminder for yesterday's published, unsealed result.
- Separate School tabs in both apps: shared unscored checklist, Parent approval of Teen edits/removal, audit history and durable retries.
- Vacation mode starts November28 automatically. Parent future scheduling/return controls and server preview preserve100-point daily totals without rewriting existing records.

The working private-health push worker is retained separately. Reminder actions do not alter scores, approvals or health records.

## Confirmed owner choices

Parent checkpoints go to both parents every day:07:15 morning after high-school drop;16:00 first task completion;17:00 more tasks/attitude;20:00 all tasks;21:10 final review. All are suppressed after confirmed finalization. Wednesday afternoon shifts18:00/19:00 end November27. School-drop reminders stop in vacations and after the term. Offline suppression uses the last confirmed state. Each installation binds its own authenticated recipient.

Teen school-premises breaks: 06:55, 08:21, 09:46, 11:26, 12:11 and 13:31. Incomplete school items advance to the next break or next school day. Home reminders: 15:45, 16:45, 18:00 and 20:00. One pending task uses its title; multiple pending tasks use “Review your pending tasks”; none produces no reminder. Home reminder occurrences expire at midnight and never change task scores or completion status themselves.

School reminders run Monday–Friday through November27. Both roles create items immediately; Teen edits/removal require Parent approval, while completion remains available. Wednesday home times17:45/18:45/19:45/20:55 are confirmed. Home reminders stop on Teen submission, resume for returned work and expire at midnight without changing scores. See School-and-Vacation-Decisions.md for the full policy and vacation allocation exclusions.

Quiet hours22:00–07:00 Costa Rica and snooze10 minutes are confirmed defaults, preserving explicit edits. The specifically requested06:55 pre-class reminder takes precedence over the07:00 quiet end. School items recur at the next break rather than using personal ten-minute snooze.

Special achievements now have a separate section at the bottom of Teen Quests, with a shortcut near the daily tasks heading, individual achievement cards, and a request dialog. They retain Parent confirmation and existing accounting rules; cash and privileges remain in Rewards.

## Completion evidence

1. Both debug APKs compiled and were installed in place with matching recorded hashes.
2. Development schema, route repairs and worker setup passed readiness checks; do not rerun upgrades or setup scripts.
3. Owner confirmed correct Parent/Teen school notifications and app destinations, offline duty recovery and automatic/resume approval refresh without approval-only earnings.
4. Owner passed local reminder delivery, ten-minute snooze, edit, offline reboot and cleanup. Ten calendar unit tests passed.
5. All fourteen vacation rollback checks passed; owner confirmed the final weekend/weekday Parent UI previews and points.
6. Other family phones and device-specific behavior are deferred to private production rollout by explicit owner decision. Additional unobserved regression scenarios remain documented in Completion-Report.md rather than recorded as passes.

Android may delay inexact reminders; force-stop and powered-off devices cannot be promised delivery. Refreshing authorized state recovers missed push hints. Production remains untouched.
