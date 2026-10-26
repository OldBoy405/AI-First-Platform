# AIFI-45 M initial current-head — component validation

## Scope and result

Source root: `C:/Users/GOBAO/Downloads/AI/multica`.

Implemented only the first current-head segment from T `wire-contract.md` §3.1. No T/CUSTOM edits, revoke request/signature, binding signer, claim attestation, consumption, Gate/state update, commit or push. Five majors remain unresolved; complete business TC remains **0/49**.

- `cr.execution_authorization_head_id` is nullable UUID, references the independent `approval_record.id` by application checks, and has no FK/cascade/default/backfill/index.
- Initial INSERT and pointer update use the existing CR `FOR UPDATE` transaction; a non-null orphan pointer cannot start another lineage. Exact historical replay returns the frozen history and never repairs a missing pointer, including after deletion/recreation of the CR projection.
- New real DaemonAuth route: `GET /api/daemon/crs/{crID}/execution-authorization/head`. Requires the daemon-token workspace/daemon context, not JWT/PAT compatibility headers. One SQL snapshot joins the exact pointer to matching workspace/CR/stage/decision history and same-workspace current shell issue/project.
- Checks service deployment contract, service public key/signature, canonical original base64, payload/source schema and identities, purpose=initial/revision=1/lineage=grant, DB metadata, frozen source digest/mappings/scope and frozen repository descriptors. Original payload/source bytes are neither normalized nor re-signed.
- Response is exactly `{record,public_key,head}`; head is exactly `{grant_id,lineage_id,grant_digest,authorization_revision,purpose}`. It is a DB read snapshot, not binding/freshness/claim proof or permission to consume. No nonce endpoint exists. `Cache-Control: no-store` is transport hygiene only.
- Historical GET retains its historical read-only behavior and conditional mounting. Current-head stays mounted when the signer is absent and returns 503 after real authentication.

## Actual RED → GREEN

The balanced baseline had finished (10/10, exit0, schema670/latest641) before this writer used the dedicated DB. No running Go test process was observed. Existing baseline files were read, not changed.

1. Wrote the public HTTP test `TestExecutionAuthorizationHeadHTTPPersistsInitial`. It calls real human Auth/membership POST, then the production-shared mount behind real DB-backed DaemonAuth, without injecting trusted actor/workspace context or seeding auth caches.
2. **Old implementation RED**: RUN1/PASS0/FAIL1/SKIP0/exit1. Exact assertion in `initial-head-red.go.jsonl`: `current head HTTP = 404, want 200 after authenticated initial issuance: 404 page not found`. Initial POST had succeeded. The failure preceded the new-column assertion, so it was not a missing migration/compile/zero-selection failure.
3. Applied migration642 and minimum implementation. **GREEN**: RUN1/PASS1/FAIL0/SKIP0/exit0 (`initial-head-green.go.jsonl`). Between RED/GREEN, the upstream §3.1 clarification removed the still-unreached response `record_id` assertion; the original failing HTTP condition was unchanged. Final tests explicitly exercise distinct record ID and grant ID.
4. Progressive negative tests: `initial-head-negatives.go.jsonl` 44/44; `initial-head-complete.go.jsonl` 50/50. These were additions after the first RED/GREEN, not fabricated separate RED claims.
5. A second actual routing RED caught production conditional mounting when signer=nil. `TestExecutionAuthorizationHeadRouterDefaultOff/authenticated_head_is_explicitly_disabled`: `server current-head route = 404, want 503: 404 page not found`. RUN4/PASS2/FAIL2 (one leaf plus parent)/SKIP0/exit1. Moved the shared mount outside the signer conditional, preserving historical conditional registration. GREEN/final router 4/4, exit0.

Raw artifacts: `initial-head-{red,green,negatives,complete,router-red}.*`. They remain separate; no failures were overwritten with later green output.

## Final executed commands and counts

All Go test commands ran from `multica/server` through the unchanged existing dedicated runner `C:/Users/GOBAO/AppData/Local/Temp/aifi45-gotest.cjs`, with inline capture of raw stdout/stderr and actual exit. `GOPROXY=off`; runner removed `KNOWLEDGE_BASE_*`, `GITHUB_TOKEN`, `GH_TOKEN`; DB password/URL stayed only in memory. Only the three allowed PI keys were recorded.

| Artifact prefix | Actual command | RUN/PASS/FAIL/SKIP | Exit |
|---|---|---|---|
| `initial-head-final` | `go test ./internal/governance -run '^(TestExecutionAuthoriz\|TestExecutionGrantCheckAgainstRealCrctlCLI\|TestDaemonAuthenticatedDeliveryRunsCrctl\|TestDaemonFetchesAndInstallsExecutionAuthorization)' -count=1 -json` | 118/118/0/0 | 0 |
| `initial-head-router-final` | `go test ./cmd/server -run '^TestExecutionAuthorizationHeadRouterDefaultOff$' -count=1 -json` | 4/4/0/0 | 0 |
| `initial-head-consumption-final` | `go test ./internal/daemon -run '^(TestExecutionVerifierRequiresExplicitNegativeFacts\|TestClaimedExecutionTaskCannotStartOnRootAttributionAlone)$' -count=1 -json` | 2/2/0/0 | 0 |
| `initial-head-index-conventions` | `go test ./cmd/migrate -run '^(TestConcurrentIndexCleanupsMatchTheirMigrations\|TestEveryConcurrentDownBuildHasCleanup\|TestEveryConcurrentUpBuildHasCleanup)$' -count=1 -json` | 3/3/0/0 | 0 |

The backslashes before pipes above escape Markdown table separators, not the actual regex. Exact argv is in each `.meta.json`. Counts include subtests and parent tests; they are not independent business TC counts. Governance top-level is 24/24. No full governance/service suite, race test, real-agent execution, deployment or actual CR was run.

Additional checks:

- `go run ./cmd/migrate up`: first run exit0, 670/641 → **671/642_cr_execution_authorization_head**; repeat run exit0, no new migration applied. Raw output is `initial-head-migrate.*` and `initial-head-migrate-repeat.*`. Migration runner lines saying `skip ... already applied` are migration ledger decisions, not skipped tests.
- New migration test executes the real 642 up/down/up files against a transaction-local temporary `cr` table shadowing public.cr; old row head remains NULL. Public production-shaped table was not down-migrated. Fixture-only failure CHECK forces the HTTP head UPDATE to fail after history INSERT; test verifies rollback leaves zero history and NULL pointer, then successful retry creates one record/head. CHECK is removed in cleanup.
- Repository Makefile invocation `GOPROXY=off go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate` was blocked by the Go module deprecation lookup (`module lookup disabled by GOPROXY=off`). It was not called a test RED. Existing installed `sqlc version` and `go version -m .../sqlc.exe` proved v1.31.1. Ran **`sqlc generate`** with `server/sqlc.yaml`, exit0; no dependency installation. Repeated generation had zero CRLF→LF-normalized drift (`initial-head-generation.json`). No generated columns were hand-authored.
- `GOPROXY=off go vet ./internal/governance ./cmd/server`, gofmt -l for six hand-written Go files, and git diff --check for owned tracked paths all exit0; gofmt emitted no filenames (`initial-head-static.*`).

## Dedicated DB evidence

Each final execution used existing runner identity checks, plus live database/user/watermark checks. Container ID starts `666bfec52ac3`, change label is `2026-10-22-aifi-45-authorized-execution`, only loopback port 55432, database `stdd_aifi45_20261022`, user `stdd`. No shared database was accessed.

`initial-head-schema-proof.log` records:

```text
stdd_aifi45_20261022|stdd
671|642_cr_execution_authorization_head
uuid|YES|<null>
0
```

Last two lines establish nullable UUID/no default and zero constraints on the new column in public.cr. The migration creates no index, so no concurrent-index cleanup registration was added.

## Exact source files owned by this sub-slice

Hand-written production:

- `server/internal/governance/execution_authorization_head.go` (new)
- `server/internal/governance/execution_authorization_http.go` (existing working-tree file; modified only here)
- `server/internal/governance/execution_authorization_routes.go` (existing working-tree file)
- `server/cmd/server/router.go` (only daemon mount placement)
- `server/pkg/db/queries/approval.sql`
- `server/migrations/642_cr_execution_authorization_head.up.sql` (new)
- `server/migrations/642_cr_execution_authorization_head.down.sql` (new)

Tests:

- `server/internal/governance/execution_authorization_head_test.go` (new)
- `server/cmd/server/execution_authorization_head_test.go` (new)

sqlc-generated (eight files; never hand-edited):

- `server/pkg/db/generated/{agent.sql.go,approval.sql.go,autopilot.sql.go,chat.sql.go,models.go,runtime.sql.go,supplement.sql.go,wakeup.sql.go}`

`approval.sql.go` contains the three new queries and updated CR scan; `models.go` contains the nullable pointer; an existing CR scan in `agent.sql.go` also acquires the new column. Full generation additionally reorders workflow_step relative to fork-added task fields consistently in projections/scans. These ordering-only differences are generator/schema-order drift, not a new claim implementation. Twelve additional EOL-only generated rewrites with zero normalized git diff were restored to their prior checkout content. Other pre-existing working-tree changes were not reverted.

Own plan/report/raw evidence are added only under this validation directory. CUSTOM is intentionally left to the main thread, as requested. Ordinary source manifest hashes normalize CRLF→LF; original signed data and raw evidence artifacts are not rewritten for hashing.

## Remaining boundaries

- No signed revoke/extend chain, predecessor CAS, trusted DB task claim, per-repository current resource read, isolated daemon/agent credential boundary, undeletable activation, T consumption or permanent logical dispatch was implemented.
- This HTTP response cannot prevent a later head/project change or serve as a reusable binding proof. Future admission must revalidate in its own trusted transaction/control chain.
- Service key rotation currently fails closed for existing heads unless the configured service key verifies them; no keyring/rotation fallback was invented.
- Destructive projection reconstruction loses the pointer and cannot silently recover it from historical initial. Explicit repair/migration remains a future authorized protocol.
- No claim of concurrency/crash-kill exactly-once, OS isolation, full-suite compatibility, deployment or 49-TC completion. Source comments are English. No code commit/push, shared DB operation or Gate advancement occurred.

Harness metadata from this writer: `PI_PROVIDER=OpenAIPersonal`, `PI_MODEL=gpt-6.1-sol`, `PI_REASONING_LEVEL=high`; actual backend identity beyond harness metadata remains unknown.
