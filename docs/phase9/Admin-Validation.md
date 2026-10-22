# Phase 9 owner-console validation — prepared, not executed

These checks target only the exact disposable QA actors recorded by the passing baseline run. They are not app migrations. Do not run initial deployment or upgrade bundles to perform these checks. Run them separately from the live stage2 runner.

## 1. Business notification outbox

`supabase/tests/phase9-outbox-audit.local.sql` is one read-only SELECT. It verifies known source facts, exactly one event per source, minimal exact payloads and private table privileges. Expected: all boolean columns true. It emits aggregates only; no payload values, notes, health records or credentials. This does not establish FCM delivery; new business notification delivery remains Phase10.

## 2. Revoked Parent database authority

`supabase/tests/phase9-revocation-rollback.local.sql` temporarily deactivates only the confirmed QA Parent B membership inside an uncommitted transaction. It tests public RPC and direct RLS access as authenticated with identical claims before/after revocation, emits booleans and ends with ROLLBACK. No permanent change or restoration action is intended. Run the complete script. If interrupted, issue ROLLBACK in the same SQL session.

This exercises database role/claims enforcement, not a real signed-JWT HTTP request. Do not report gateway/session revocation or Android cache behavior as passed from this fixture.

## 3. Sealing enforcement

`supabase/tests/phase9-seal-boundary-rollback.local.sql` creates an explicitly synthetic five-second deadline on a new empty yesterday result for one exact disposable QA Teen. It temporarily reactivates only that test membership, proves before-boundary actions, lets the real server clock cross the deadline and verifies deferred rejection/rollback, later action denial and expired appeal display. The complete transaction ends with ROLLBACK; no existing timestamps, app functions, triggers or clocks change. It briefly holds the QA family lock, so run separately from other QA requests.

Expected: all boolean columns true. This validates boundary enforcement with controlled data; it does not validate the ordinary calendar-deadline calculation or HTTP gateway. No calendar formula or real future activation pass may be inferred.

## 4. Activated schedule and saved-price selection

`supabase/tests/phase9-activation-rollback.local.sql` uses already-effective synthetic versions inside a rolled-back transaction to exercise reward saved prices, current/future routine selection and materialization on a new empty QA actor. It temporarily remaps only the exact anonymous QA membership. No existing historical snapshot, clock, function or trigger is changed. Expected: every functional check row passed=true. This tests resolver behavior with controlled effective records, not literal midnight passage or the HTTPS gateway. Owner execution is pending.

All result tables explicitly enable RLS. If the SQL Editor still warns, use plain Run without its auto-RLS rewrite for these reviewed scripts; keep the final ROLLBACK.

All fixture files are machine-local ignored SQL containing fictional fixture identifiers. Keep them outside commits. Source review is complete; owner execution results remain pending.
