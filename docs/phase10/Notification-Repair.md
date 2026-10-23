# Notification repair — 23 October 2026

## Observed

School creation and cross-app list refresh passed with no XP/coin award. Expected Parent push was not observed. Ten generic family notices opened Teen. Morning local Parent checkpoint arrived.

Correct-project read-only diagnostics: school creation produced two Parent notices, zero Teen notices; both app registrations are active/current; scoped Parent delivery is pending. Recent source traffic includes fourteen per-duty notices (six done/eight pending), fourteen older reviews and other older Teen updates. No evidence supports changing school recipient roles or opening Parent notices in Teen. Earlier production query only failed to find tables; no repair should run there.

## Prepared changes

1. Migration018, applied using `supabase/phase10-notice-coalescing-fix.sql`: one daily duty-list/catalogue-batch alert, per-installation enrollment cutoff and fresh-event priority. Committed task, review, school and wallet history is retained. Older facts remain visible through authorized refresh rather than generating first-enrollment alert floods.
2. New APKs: generic cloud events update one current family notification card with only the first update alerting; the latest authenticated destination remains tappable. Existing old event-specific cards are cleared when a new current family card is posted. Personal and task-time local reminder behavior is separate.
3. Explicit enable waits for the family-device registration receipt. Existing active registrations were confirmed by diagnostics; this is a truthful-status fix, not a claim that registrations were missing.

## Owner steps when ready

1. In **Petal Quest Dev**, run the complete `phase10-notice-coalescing-fix.sql`. Expected booleans: grouped_notices_ready, grouped_fanout_ready, enrollment_cutoff_ready, fresh_delivery_priority_ready all true. Do not rerun the original upgrade. This is a new live forward repair; the worker endpoint/secret need no replacement.
2. Within the next five-minute cycle, inspect Parent's notification shade and refresh Parent School for the existing fictional item. The previously pending school event remains eligible if created after that installation's enrollment.
3. Rerun the read-only notification diagnostics if Parent notice is still missing. Delivery rows now include attempts and next due time so pending never-attempted can be distinguished from retrying.
4. Reconnect/unlock Samsung for in-place installation of the newly built APKs. Preserve data; older installed hashes remain in the historical build table.
5. Repeat a controlled school change-request action and inspect correct Parent arrival/one card behavior. Then check Parent approval produces the corresponding Teen update.

Schema readiness, successful build, server delivery completion and a physically displayed notification are distinct evidence. All live repair/device outcomes remain pending until reported or observed.

## Repair deployment confirmed — 23 October 2026

Owner reports all four readiness checks true for phase10-notice-coalescing-fix.sql in Petal Quest Dev: grouped_notices_ready, grouped_fanout_ready, enrollment_cutoff_ready and fresh_delivery_priority_ready. No original upgrade was rerun.

Connected Samsung SM-S918B/R5CWB2MXQHZ: SHA-256 matched the prepared Teen 41F8C38F435DF58531F993453C8A829D2D933ED836403A2E73B2E908632FE1F1 and Parent 82238075F0983B8810DE44F340CD7CC7629D6C2691F2D51A2D748EF8D1C5F408 APKs. Sequential ADB install -r returned Success for both. No uninstall or data clear was performed.

Next acceptance: enable/retry notifications in both updated apps, leave Parent in background, request an edit to the existing fictional school item in Teen, and verify the Parent notification and pending change. Then approve in Parent and verify the Teen update. Physical display and delivery repair remain unverified until that walkthrough is reported.

## School notification repair acceptance — 23 October 2026

After migration018 readiness passed and both repaired APKs were installed in place, the owner completed the requested school-edit walkthrough and reports: separate notifications arrived, opened the correct apps, and everything worked as expected. Record the Parent-bound Teen edit request and the Teen-bound Parent approval notification/deep link as owner-observed passes on the same Samsung. This does not establish independent-device delivery, all event types, offline/reboot recovery or scheduled reminder boundaries.
