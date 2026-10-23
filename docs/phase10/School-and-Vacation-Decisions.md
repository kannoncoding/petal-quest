# Confirmed school, home and vacation policies

Owner decisions received 22 October 2026. Implementation is local preparation; SQL and device behavior are not yet verified in development.

## School checklist

- Teen and Parents can create school-premises items immediately. Creation earns no XP.
- Teen can mark completed. Teen edits/removal create a pending change for Parent approval; original text/item remains until approved. Parents can edit/remove directly, or approve/reject requests.
- Version checks reject stale changes. Completion and direct Parent changes supersede pending change requests. Durable request IDs support retry without duplicating a committed action.
- Items, requests and history have RLS and no client write grants. RPCs verify current family/Teen authority; requests and decisions are audited. Notice payloads contain only routing metadata, never item text.
- Monday–Friday reminders: 06:55, 08:21, 09:46, 11:26, 12:11, 13:31 Costa Rica. An incomplete item remains at subsequent breaks and the next school day. This is separate from personal ten-minute snooze.
- Specifically requested 06:55 is an exception to local quiet hours ending 07:00. Android notification settings and inexact-delivery limits still apply; this does not bypass system Do Not Disturb.
- Friday **27 November 2026** is the last school day. No school-premises reminders from November 28; school-drop Parent checkpoints also stop. Historical items are retained. Another school-term reminder calendar needs explicit future dates.

## Home reminders

- Normal days: 15:45, 16:45, 18:00, 20:00.
- Wednesdays through November 27: 17:45, 18:45, 19:45, 20:55 (15 minutes before Parent afternoon/evening reviews).
- Open/returned duties are pending. A locally queued or server-received Teen submission stops its reminder; returned duties become pending again. Terminal approved/excused/rejected work is not nagged.
- Exactly one pending title is displayed; multiple use “Review your pending tasks”; zero schedules none. Each day's reminder occurrences expire at Costa Rica midnight.
- Reminder expiry never fails a duty, deducts points or changes existing late-work, review, finalization or sealing rules.

## Parent checkpoints

Both Parents, every day, on their authenticated installations. Times 07:15, 16:00, 17:00, 20:00, 21:10. Wednesday afternoon shifts to 18:00/19:00 through November 27. All checkpoints are removed after a confirmed finalized/sealed result. Offline suppression uses the most recently confirmed state. School-drop reminders are not scheduled in vacations or after the school term.

## Vacation mode

- Automatic default begins **28 November 2026**. Parents can schedule additional future vacations and a future return to ordinary duties. Changes are versioned, audited and never rewrite already-created daily snapshots.
- `duty-wd-002`: Shower + Room. `duty-wd-005`: Room clean up. Weekday homework/study (`duty-wd-003`) and weekend school pending/study (`duty-we-004`) are omitted.
- Removed points are distributed proportionally across the other enabled duties, excluding water plants, drink water, research, draw/dance, closet/shoes, declutter and Hikari Shop (stable keys007–013 in both variants).
- Whole points use largest-remainder allocation with stable catalogue-key tie breaking. Daily maximum remains100. Current unchanged catalogue: eligible required duties total90, excluded activities retain their combined10. Passing remains90; actual<85 earns0;85–99 earns its score; ordinary100 earns200; converted bonus days never double.
- Current weekday vacation required points: attitude checks17 each, Shower+Room13, Room clean up13, House Help13. Weekend: attitude checks17 each, Room+Laundry14, Shower+No Mess13, House Help12. These are a source-derived preview, not a live SQL acceptance result; future effective Parent edits are resolved before allocation.
- Parent Vacation tab has a server preview and confirmation before scheduling changes. Ending vacation restores ordinary duties; a new school-term reminder calendar is configured separately.

## Prepared database delivery

`supabase/phase10-notifications-upgrade.sql` now atomically includes migrations015 (family events),016 (school checklist) and017 (vacation mode). The generator is `tools/prepare-phase10-forward.py`. It refuses existing Phase10 objects. The owner must run the whole forward file; do not run initial deployment files against an existing database.

Pending: development SQL execution, Edge deployment, authenticated webhook/Cron setup, live RLS/RPC/notification checks and physical phone acceptance. Compilation alone does not establish those outcomes.

Source review checked the vacation trigger order against [PostgreSQL trigger behavior](https://www.postgresql.org/docs/current/trigger-definition.html) and deferred PL/pgSQL SQL planning against [PostgreSQL PL/pgSQL implementation](https://www.postgresql.org/docs/17/plpgsql-implementation.html). These references support the source design; they do not constitute database execution.
