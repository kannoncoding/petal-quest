# Phase 6 Supabase backend foundation

Local source only. No hosted database was read or changed; no credentials were used. SQL has not been executed. Apply migrations in filename order in a disposable local Supabase database for review. Do not run the synthetic fixture against a hosted project. The fixture is optional and is not production seed data.

Keep `petal_private` OUT of PostgREST exposed schemas. Public wrappers run as SECURITY INVOKER; explicitly granted private implementations use SECURITY DEFINER, empty search paths, qualified relations, authoritative Auth identities and active server memberships. Never grant app roles direct table writes, service-role keys, or membership-edit privileges. No health table or health field belongs in this database.

The migration set creates the schema, recovery/API boundary, new-family duty provisioning, initial-version schedule catch-up and API contract handshake. `create_family` provisions 28 Phase 3 duty definitions using the committed catalogue, including weekend research 1 point and weekend Room + Laundry 11:00. Unknown deadlines remain NULL and cannot generate submittable occurrences. This does not settle draft correction/effective-date policies.

Review scripts are deliberately manual and unexecuted:

- `review/fixture.sql`: two synthetic families, two parents in A, one teen per family, synthetic Auth identities and clearly labeled synthetic task rules.
- `review/manual-review.sql`: individual identity/denial scenarios, duplicate requests, two-session simultaneous parent approvals, revoked-session and replacement scenarios, local date/version checks. Substitute returned UUIDs where indicated; inspect expected outcomes manually.

No outbox worker, push sender, day finalization, wallet, reward mutation, appeals, correction, deduction, automatic lateness penalty, or future rule activation policy is supplied. Outbox entries persist atomically alongside submissions/approvals; eventual workers must independently resolve current active recipients and register delivery receipts. Approval contributes scoring input and always mints zero XP/coins. See `Documentation/Phase6/Backend-Handoff.md` for RPC contracts and limitations.

The coordinator prepared deploy-development.sql as one atomic initial deployment for the existing development project. Prepare-DevelopmentBundle.ps1 rebuilds it from the ordered migrations without executing SQL. The development project reference is an instruction for the owner to select the correct dashboard, not a database-enforced project identity check. No credentials or automatic deployment command are included. Follow Documentation/Phase6/Owner-Actions.md. Preserve the set as a whole; exposing migration 001 without the later boundary is not the reviewed final configuration.

Migration 005 supersedes the intermediate retrieve-only reconciliation: it catches up missing slots only under the single immutable initial rule, from server provisioning/enrollment onward, with known deadlines. Future/multiple rule versions and unknown schedules stay blocked. Migration 006 exposes an authenticated API contract version, checked before client family reads or mutations. No hosted deployment or SQL runtime validation is claimed.

