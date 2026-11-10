# AIFI-45 disposable database checks

This experiment is authorized only for the pinned AIFI-45 PostgreSQL container.
It is not a production installer, an agent sandbox, or execution admission.

## Run

From the repository root, supply an unused evidence prefix outside the source tree:

```sh
node --test --test-reporter=tap scripts/aifi45-db/run.test.mjs
node scripts/aifi45-db/run.mjs ./internal/governance '^TestExecutionStartClaimDaemonOwnership$' /absolute/validation/unique-prefix
```

Run one DB invocation at a time. Each invocation creates a different database
and restricted login, executes exactly one approved Go package, and checks the
preserved source database before another invocation may start. Optional arguments
are limited to `-skip=...`, `-shuffle=...`, `-timeout=...`, and ordered
`-migration=server/migrations/NNN_name.up.sql` or `.down.sql` arguments.
Selected migrations run in the nonce database as its restricted owner; they do
not establish that the schema matches a full migration history.

## Boundaries

- Pin the complete container ID, change label, running state, loopback port,
  original database and original role. No environment override selects another server.
- Read the preserved database only. Save non-system table row-content summaries,
  approval IDs/full-row hashes, an original approval-record data dump, and a
  schema-only dump before creating resources. After schema import, the runner
  initializes `public.task_usage_hourly_rollup_state` with migration 101's default
  row in the disposable database. No preserved table rows are imported; the
  approval-record data dump is retained only as sensitive evidence.
- Create a nonce-named database from `template0` and a separate login without
  superuser, create-database, create-role, inheritance, replication or RLS bypass.
  Import the schema as that login, making it the test-table owner. Its password
  exists only in memory/stdin and the test process environment, never in evidence.
- Verify empty approval/workspace tables and the actual login identity. A real
  read against the preserved approval table must fail with permission denied.
  This is database permission separation, not isolation from malicious local code.
- Replace inherited database settings in the child environment, disable real-agent
  smoke tests, and remove keys matching the blacklist in `testEnvironment` (including
  `GH_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, and `ANTHROPIC_API_KEY`). This is
  not a comprehensive secret scrub or environment isolation. Require at least one
  passed leaf test; zero matches and all-skipped leaves fail, even with a passing parent.
  A `-skip` exclusion may produce no skip event, so independently confirm that
  all intended tests were selected; skip counts alone do not prove coverage.
- Preserve raw stdout/stderr unless a generated credential is detected, in which
  case redact it, mark that fact and fail. Parent/child events are not business TCs;
  SKIP is not PASS.
- The runner replaces `AIFI45_DISPOSABLE_NONCE` with its generated nonce. At
  startup, before any fixture setup or cleanup, `cmd/server` integration `TestMain`
  checks the actual database, current and session roles, owner, both identity markers
  and restricted role attributes against it. The check is not repeated immediately
  before teardown. Direct invocation without this disposable identity fails. This
  guards accidental misconnection, not an operator able to forge the markers.
- Compare the original table summaries and approval IDs/hashes once per runner
  invocation in `finally`, including after a failed test or setup when the initial
  snapshot exists. Check other source sessions and advisory locks there too; drift
  or an unreleased source stops cleanup. These row summaries do not cover schema,
  grants, sequences or every possible database change, and the runner does not
  enforce a cross-invocation lock; the operator must run invocations sequentially.
- Delete only the current nonce database and login after checking exact OIDs,
  database owner and ownership comments. No broad name sweep, `DROP OWNED`, role
  reassignment or forced termination is used. Cleanup failure is a failed run;
  consult the append-only event journal for exact retained identities. Creation
  intent is logged before SQL; a lost creation acknowledgement is not proof of
  absence. Catalog checks must confirm both exact names are actually absent before
  the runner reports successful cleanup.
- All evidence files are created without overwriting existing files. The event
  journal records partial creation/cleanup but never records passwords or URLs.
  The approval-record dump contains preserved database rows and must be handled
  as sensitive evidence.

## Instance lifecycle draft

`instance-lifecycle.mjs` is a fake-I/O component, not a connected engine or
cleanup authority. Its probe must return a synchronous, non-Proxy exit receipt;
Promise, thenable and Proxy receipts are unresolved and preserve the instance.
Rejecting a Proxy can leave its underlying rejected Promise unhandled, so the
adapter must own rejection handling. Even an accepted ordinary receipt is not
proof of real process or process-tree exit; a trusted adapter and durable journal
are still required before any real resource cleanup.

## Supervisor collector draft

`supervisor-collector.mjs` is a controlled-event component, not an operational
supervisor. On both EOF events it decodes nonempty stdout and attempts to erase
its private buffer before publishing the decoded result. A sticky failure retries
an incomplete erase on a later event. This does not erase caller, runtime, or OS
copies; an unfinished stream or a repeatedly failing erase can retain bytes.

Any future pump must treat every collector exception as failure, never log the
raw exception or subprocess output, and attempt `result()` on completion or
`abort()` on failure before discarding the collector. If a call throws, a bounded
retry may attempt the erase again; catch retry exceptions and mark cleanup as
unproved rather than claiming erasure. No pump, process-tree termination, or
cleanup authority is established by this component.

The previous incident remains an incident: preserving the 82-row post-incident
source does not restore the original 83-row history. The old temporary runner's
`AIFI45_DB_HOLD` remains active. This runner does not close the AIFI-45 major
adjustments or authorize Gate 3, commits, pushes, releases or real CR trials.
