# Phase9 DEV live acceptance

Launch from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\CAT\Petal Quest\Android Dev\supabase\tests\Run-Phase9-Acceptance.ps1"
```

Requires Node with built-in fetch, the local development Supabase configuration, deployed migrations008–012, anonymous Auth enabled, and confirmed dedicated accounts `qa-parent-a@example.com`, `qa-parent-b@example.com`, and `qa-parent-c@example.com`. The launcher prompts for each hidden password. Credentials travel through private stdin and remain in process memory; no token, password, pairing code, or response body is written to a report.

The runner pins project `hijtwgugzzpjjkuutyfy`. Before mutations it checks every supplied Parent membership and accepts only family names beginning `QA P6 ` or `QA P9 `. Parents A/B share the first QA family; C uses another. It creates new fictional anonymous Teen actors and uses only those for scoring and economic changes. It never accesses health data or owner families. Finally it revokes the newly created Teen memberships and logs out its sessions. Audit facts, actors and anonymous Auth identities remain as fictional DEV records; no privileged deletion is attempted. Failed cleanup is explicitly reported.

The current accepted catalogue supplies the450 Coin reward and400 XP achievement used to fund a fictional reward lifecycle and demonstrate debt. Existing QA Teen balances and catalogues are untouched. A future catalogue differing from these prerequisites can block that sequence.

Results go to the ignored `phase9-live-acceptance-results.local.json`; only fixture family/actor IDs, check names, result categories and sanitized diagnostics are recorded. Exit0 means every included gate was verified;1 means failure;2 means required manual gates remain unverified. The normal successful automated run returns2 because future effective catalogue changes, transition races, process restart, revoked Parent sessions, negative score floor, cash/privilege confirmation, real server sealing and private outbox inspection need additional evidence. None of those are reported as PASS.

The checks exercise public HTTPS RPCs rather than privileged SQL. A syntax check validates parsing only and is not live acceptance evidence.
