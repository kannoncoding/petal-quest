-- Manual review scenarios, NOT executed by Codex. Use a disposable LOCAL fixture.
-- Execute each transaction separately; expected denials abort that transaction.
-- 1. Family A teen reads only A and cannot write roles or inspect pairing metadata.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated","is_anonymous":true}',true);
select * from public.families; -- A only
select * from public.task_occurrences where family_id='20000000-0000-0000-0000-000000000000'; -- zero
select public.create_occurrence('13000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000003'); -- save id
commit;

-- 2. Substitute the returned occurrence UUID for :occurrence_id (psql variable).
-- Two calls with same request ID must return same submission id and request_id.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated","is_anonymous":true}',true);
select public.submit_occurrence(:'occurrence_id','14000000-0000-0000-0000-000000000001');
select public.submit_occurrence(:'occurrence_id','14000000-0000-0000-0000-000000000001');
commit;

-- 3. Parent A approves saved :submission_id. Repeat with second parent in another
-- session while first transaction is open; second blocks until COMMIT, then returns
-- the same decision_id. Its request_id is its own; no second event/outbox row.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":false}',true);
select public.approve_submission(:'submission_id','15000000-0000-0000-0000-000000000001');
select public.approve_submission(:'submission_id','15000000-0000-0000-0000-000000000001');
commit;
-- Second parent JWT sub=10000000-0000-0000-0000-000000000002;
-- use request_id=15000000-0000-0000-0000-000000000002.

-- 4. Privileged local inspection: one approved decision, one contribution event,
-- one approval outbox item, spendable_xp=coins=0, original local_date retained.
select * from public.decisions where submission_id=:'submission_id';
select * from public.xp_events where decision_id in (select id from public.decisions where submission_id=:'submission_id');
select * from petal_private.outbox where topic='submission.approved';

-- Run each denial separately with the same set local role/JWT pattern; ROLLBACK.
-- Teen A: public.approve_submission(:submission_id,new uuid) => parent_required.
-- Parent B: approve A submission => parent_required; A reads return no rows.
-- Teen A: create_occurrence(B definition,A actor) => not_authorized.
-- Teen A: update public.memberships set role='parent' => permission denied.
-- Any app identity: select * from petal_private.invites/outbox/idempotency => denied.
-- Parent A: same committed request_id + different authorized submission =>
-- idempotency_payload_conflict. Same request_id across submit/approve => conflict.
-- Invalid invite string ten times => invalid_or_expired_code; eleventh => rate_limited.
-- Use each as separate committed RPC transaction: ROLLBACK would erase attempts.
-- Parent-issued code: anonymous Auth identity cannot accept_parent_invite;
-- redeem_teen_pairing(parent-code) => invalid_or_expired_code, never parent authority.
-- Parent A issues teen code; two anonymous users redeem concurrently => one winner.
-- Revoke that teen; old JWT can neither select nor submit nor reuse consumed code.
-- issue_teen_replacement(A,old_actor_id); fresh anonymous identity redeems -> same
-- actor_id, old occurrences still visible, no new scoring events.
-- Revoke parent B; all its issued codes are revoked. Last active parent revocation denied.
-- Admin sets occurrence due_at earlier than server receipt: new submit denied
-- late_policy_unresolved; no penalty/event. A preexisting on-time submission can
-- be approved later with original local_date unless day_results already published.
-- Admin inserts published day_results row: new approval denied; already committed
-- approval retry returns its existing outcome. No correction or late-award path.
-- Server-local midnight: create_occurrence returns the new day's distinct slot;
-- same-day retries always return the first occurrence/rule_version snapshot.
