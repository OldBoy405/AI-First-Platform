# AIFI-45 C1 balanced independent review — 20261024T115444Z

## Verdict

- The selected component baseline passed in this independent re-run: **no FAIL, no SKIP, all selected Go test processes exit 0**.
- This is not a complete business-TC pass. Complete business TC remains **0/49**; this review does not promote slices or close majors.
- A **P2 static defect** was reported by the independent reviewer and is included below. It was **not dynamically reproduced** in this review. The existing green baseline must not be treated as defect-free.
- The dedicated DB was released after the three sequential runs: no advisory fixture lock and no other DB session remain.

## Reviewed scope: the 17 initial-head files only

All 17 files match `initial-head-source-manifest.json` after the declared CRLF-to-LF normalization (17/17 OK).

- Hand-written production (7): `execution_authorization_head.go`, `execution_authorization_http.go`, `execution_authorization_routes.go`, `cmd/server/router.go`, `pkg/db/queries/approval.sql`, migration `642_*.up.sql`, migration `642_*.down.sql`
- Tests (2): `internal/governance/execution_authorization_head_test.go`, `cmd/server/execution_authorization_head_test.go`
- sqlc-generated (8): `agent.sql.go`, `approval.sql.go`, `autopilot.sql.go`, `chat.sql.go`, `models.go`, `runtime.sql.go`, `supplement.sql.go`, `wakeup.sql.go`

No unrelated uncommitted AIFI-45 files were assessed as this round's source scope.

## Author RED/GREEN evidence read from raw Go JSON

The author's raw artifacts were parsed directly; summaries were not substituted for the JSONL. All listed stderr files are empty. The actual failure text below is from the raw JSON.

| Artifact | RUN/PASS/FAIL/SKIP | exit | Raw result |
|---|---:|---:|---|
| `initial-head-red.go.jsonl` | 1/0/1/0 | 1 | `current head HTTP = 404, want 200 after authenticated initial issuance: 404 page not found` |
| `initial-head-green.go.jsonl` | 1/1/0/0 | 0 | pass |
| `initial-head-negatives.go.jsonl` | 44/44/0/0 | 0 | pass |
| `initial-head-complete.go.jsonl` | 50/50/0/0 | 0 | pass |
| `initial-head-router-red.go.jsonl` | 4/2/2/0 | 1 | `server current-head route = 404, want 503: 404 page not found` |
| `initial-head-router-green.go.jsonl` | 4/4/0/0 | 0 | pass |
| `initial-head-router-final.go.jsonl` | 4/4/0/0 | 0 | pass |
| `initial-head-final.go.jsonl` | 118/118/0/0 | 0 | pass; 24 top-level names |
| `initial-head-consumption-final.go.jsonl` | 2/2/0/0 | 0 | pass |
| `initial-head-index-conventions.go.jsonl` | 3/3/0/0 | 0 | pass |

The RED failure is a real 404 at the current-head route after a successful initial POST, not a compile error or zero selection. The router RED is a real `404` where the default-off route must return `503`. The later green artifacts do not erase those raw failures.

## Independent re-run: actual command and results

All three runs were sequential, single Go test process each, through the unchanged dedicated runner `C:/Users/GOBAO/AppData/Local/Temp/aifi45-gotest.cjs`. The runner's identity checks, dedicated DB URL construction, `GOPROXY=off`, and removal of `KNOWLEDGE_BASE_*`/`GITHUB_TOKEN`/`GH_TOKEN` were retained.

### 1. Governance head/Auth/crctl

Final argv derived from the unchanged runner source and the appended extras:

```text
go test ./internal/governance \
  -run '^(TestExecutionAuthoriz|TestExecutionGrantCheckAgainstRealCrctlCLI|TestDaemonAuthenticatedDeliveryRunsCrctl|TestDaemonFetchesAndInstallsExecutionAuthorization)' \
  -count=1 -json -shuffle=on -count=2
```

The wrapper could not capture the spawn argument array because the `spawnSync` result has no `args` field, and its post-processing crashed after raw capture. Effective count=2 is independently proven by the raw events: each of the 24 distinct top-level names ran exactly 2 times, and each of the 94 distinct subtest names ran exactly 2 times. `-shuffle=on` is proven by the raw line `-test.shuffle 1792842887735739800`.

| Level | RUN | PASS | FAIL | SKIP |
|---|---:|---:|---:|---:|
| top-level | 48 | 48 | 0 | 0 |
| subtest | 188 | 188 | 0 | 0 |
| all test events | 236 | 236 | 0 | 0 |

- exit: **0**
- Go package elapsed: **6.537 s**
- raw JSON span: **6.537 s**
- raw JSON lines: 948
- shuffle seed: `1792842887735739800`
- distinct top-level names: 24 (each run twice)
- distinct subtest names: 94 (each run twice)
- zero-match: none in the selected set; no SKIP hidden as PASS

Exact top-level names (all PASS twice):

```text
TestDaemonAuthenticatedDeliveryRunsCrctl
TestDaemonFetchesAndInstallsExecutionAuthorization
TestExecutionAuthorizationBuildsSignedStructuredSource
TestExecutionAuthorizationHeadHTTPAuthAndConfiguration
TestExecutionAuthorizationHeadHTTPPersistsInitial
TestExecutionAuthorizationHeadHTTPPointerIsTheOnlySelector
TestExecutionAuthorizationHeadHTTPPreservesOriginalCRLFBytes
TestExecutionAuthorizationHeadHTTPRejectsForeignHistoryAndProject
TestExecutionAuthorizationHeadHTTPRejectsMissingAndDriftedAuthority
TestExecutionAuthorizationHeadHTTPRejectsSignedInvalidPayload
TestExecutionAuthorizationHeadHTTPReplayNeverRebuildsAuthority
TestExecutionAuthorizationHeadHTTPRollsBackHistoryWhenHeadWriteFails
TestExecutionAuthorizationHeadMigrationDoesNotBackfill
TestExecutionAuthorizationRejectsDuplicateJSONKeys
TestExecutionAuthorizationRejectsOversizedGrantEnvelope
TestExecutionAuthorizationRejectsUntrustedSources
TestExecutionAuthorizationRouteDisabledAndTaskToken
TestExecutionAuthorizationRouteUsesRealAuthAndWorkspace
TestExecutionAuthorizePersistsAndReplaysSource
TestExecutionAuthorizeRejectsCrossWorkspaceAndProjectMismatch
TestExecutionAuthorizeRejectsStaleOrForeignResource
TestExecutionAuthorizeRejectsUntrustedCallers
TestExecutionAuthorizeRequiresFrozenCoordinatorRoot
TestExecutionGrantCrossVerifiesWithCrctlCLI
```

### 2. cmd/server default-off 4-event test

`go test ./cmd/server -run '^TestExecutionAuthorizationHeadRouterDefaultOff$' -count=1 -json`

| Level | RUN | PASS | FAIL | SKIP |
|---|---:|---:|---:|---:|
| top-level | 1 | 1 | 0 | 0 |
| subtest | 3 | 3 | 0 | 0 |
| all test events | 4 | 4 | 0 | 0 |

- exit: **0**
- package elapsed: **2.096 s**
- exact names: `TestExecutionAuthorizationHeadRouterDefaultOff` plus subtests `authenticated_head_is_explicitly_disabled`, `head_still_requires_real_auth`, `legacy_delivery_stays_conditionally_mounted`
- no SKIP/FAIL/zero-match

### 3. daemon two continue-to-refuse-consumption tests

`go test ./internal/daemon -run '^(TestExecutionVerifierRequiresExplicitNegativeFacts|TestClaimedExecutionTaskCannotStartOnRootAttributionAlone)$' -count=1 -json`

| Level | RUN | PASS | FAIL | SKIP |
|---|---:|---:|---:|---:|
| top-level | 2 | 2 | 0 | 0 |
| subtest | 0 | 0 | 0 | 0 |
| all test events | 2 | 2 | 0 | 0 |

- exit: **0**
- package elapsed: **1.788 s**
- exact names: `TestExecutionVerifierRequiresExplicitNegativeFacts`, `TestClaimedExecutionTaskCannotStartOnRootAttributionAlone`
- no SKIP/FAIL/zero-match

### Review harness defect (post-capture only)

After each raw stdout/stderr was written, the inline wrapper crashed with:

```text
TypeError: Cannot read properties of undefined (reading '0')
at command_equivalent: [captured.args[0], ...captured.args.slice(1)]
```

The test process itself had already finished; the runner printed `exit=0`, and each raw JSONL ends in a package `pass` event. The wrapper's `RUN_STATUS` of 1 is **not** a Go test failure. No test was rerun. The three `.meta.json` files were reconstructed from the actual raw JSONL and are marked with `wrapper_error` and `note`; they are not claimed to be direct wrapper output.

## P2 static defect: `-0` source token vs canonical payload integer

This was found statically and was **not dynamically reproduced** in this review. It is a real correctness risk for a successful POST followed by an unrepairable current-head GET failure.

- `execution_authorization_head.go:162` compares each raw source field with the signed payload field using `executionJSONEqual`.
- `execution_authorization_head.go:202` decodes both sides with `UseNumber` and compares with `reflect.DeepEqual`; therefore JSON token `-0` and `0` are different (`json.Number("-0")` vs `json.Number("0")`) even though both mean zero.
- Issuance accepts `-0`: `executionSafeInteger` at `execution_authorization.go:665` matches `^-?\d+$` and `strconv.ParseInt("-0")` returns zero.
- `repair_limit` is parsed at `execution_authorization.go:588`; `sensitive_actions[].limit` at `execution_authorization.go:1013`.
- Static consequence: a source body containing `-0` for either field can be issued and signed with payload `0` (POST 201), while the current-head GET compares raw `-0` against payload `0`, rejects with 409, and cannot recover by replay. This is not covered by the existing green tests.
- Same class of token/value mismatch also applies to other non-canonical integer spellings accepted by `executionIntegerPattern` (for example `00`/`01`); the reported concrete cases are the two zero-min fields above.

Required next action (not performed here): add a real HTTP RED for `repair_limit: -0` and `sensitive_actions[].limit: -0` (and, if accepted, leading-zero variants), then fix the canonicalization/rejection or semantic comparison. Do not treat the current green run as proving this path safe. No source was changed by this review.

## DB/schema/sqlc/config verification

- Container `stdd-aifi45-20261022-pg`, ID `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`; running; label `stdd.change=2026-10-22-aifi-45-authorized-execution`; only `127.0.0.1:55432`.
- DB/user `stdd_aifi45_20261022`/`stdd`; `schema_migrations` 671, max `642_cr_execution_authorization_head`; exactly one 642 ledger row.
- `cr.execution_authorization_head_id`: `uuid`, nullable, default `<null>`.
- FKs on `public.cr`: 2 pre-existing (`cr_shell_issue_id_fkey`, `cr_workspace_id_fkey`); no FK on the new column.
- Indexes on `public.cr` containing `execution_authorization_head_id`: 0.
- Advisory fixture lease before and after: 0. Other DB sessions before and after: 0.
- Protected config snapshot hashes match exactly:
  - T `config.d/quality.yaml` `25380eed...fcf2`
  - T `.stdd/binding.yaml` `31546e1a...cf7b`
  - M `config.d/quality.yaml` `05a0e3eb...09af`
  - M `.stdd/binding.yaml` `ae676b9a...6d89`
- Installed sqlc `v1.31.1`; module `github.com/sqlc-dev/sqlc v1.31.1`; author generation artifact exit 0 with `normalized_generated_drift: []`; `server/sqlc.yaml` has no working-tree change.
- Harness metadata only: `PI_PROVIDER=Gobao`, `PI_MODEL=deepseek-flash`, `PI_REASONING_LEVEL=max`. Actual provider/model/effort identity remains **unknown**.
- Generated diffs are head-query/columns plus `workflow_step` reorder churn; no hand-authored columns found. The broad generated reorder is still churn worth guarding.

## Findings

### Blockers / coverage blockers (not test failures)

1. **Configured router path is untested.** `TestExecutionAuthorizationHeadRouterDefaultOff` calls `NewRouter` -> `RouterOptions{}`, so it only exercises disabled/unauthenticated/legacy behavior. The governance tests mount `DaemonAuth` and the route helper directly. No test sets `RouterOptions.ExecutionContract`, lets `NewRouterWithOptions` configure the service, and then reads the current head through the actual server router. This blocks a claim that the production configured wiring is integration-tested.
2. **No concurrent head-write/response-loss test.** The implementation uses CR row locking plus `SetInitialExecutionAuthorizationHead ... IS NULL`, but the tests are sequential and the rollback test uses a fixture CHECK constraint. There is no two-writer race, no response-loss-after-commit, and no assertion that one and only one initial head wins. This blocks an exactly-once/current-head claim.
3. **P2 static defect above.** The current green baseline does not exercise non-canonical source integer tokens; posting `-0` can create an unreadable head. This blocks treating current-head as defect-free.

### Suggestions

1. **Test cleanup:** after the run, 36 `approval_record` rows for `CR-9061*` remain while 0 matching `cr` rows remain. `TestMain` cleanup does not delete `approval_record`; add cleanup (or a dedicated schema/transaction teardown) so the dedicated DB is actually free of test history.
2. **Migration coverage:** the 642 up/down/up test runs against a temporary `cr` shadow, not the public production-shaped table. Add a non-destructive shadow-schema/table test that proves down preserves history, up does not backfill, and the migration ledger is idempotent.
3. **Head payload coverage:** add signed-invalid-payload cases for `repair_limit`, `sensitive_actions[].limit`, `allowed_paths`, `delivery_targets`, `acceptance`, `prohibitions`, `repository_bindings`, `coordinator_binding`, `source_bindings`, and `approved_at`, not only identity/policy digest fields.
4. **sqlc drift:** add CI `sqlc diff`/generated-hash enforcement; the current broad `workflow_step` reorder is only manually accepted.
5. **Router disabled human POST:** add a router-level test for `/api/workspaces/{workspaceID}/crs/{crID}/execution-authorization` with nil service, expecting 503; the current default-off router test covers only the daemon GET.
6. **Additional auth edge cases:** invalid CR ID (400), expired/unknown daemon token (401), and DB-error mapping (500) are not covered on the head route.

## Artifacts and hashes

Raw and reconstructed meta files are in this same validation directory.

| Artifact | SHA256 |
|---|---|
| `20261024T115444Z-aifi45-review-governance-head-auth-crctl.go.jsonl` | `5c70cd70667dcfc4288488f88fa6d59d0f73b3752786a1921d4099eda8a5cea3` |
| `...governance...stderr.log` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `...governance...meta.json` | `15b1bb2c8b3cf062953186153da0f5a6a0bfcd71381842b1e27af3e3f069e0e9` |
| `20261024T115444Z-aifi45-review-cmd-server-defaultoff.go.jsonl` | `475e97e2a6efa0e40e27326844da4a16570e4e9a01dff892bc98eac801f3b0f2` |
| `...cmd-server...stderr.log` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `...cmd-server...meta.json` | `9d549505b05eb10d429c5c4d6dc9bdbe0283e81f485f49dd5a85c5a05353dc1b` |
| `20261024T115444Z-aifi45-review-daemon-consumption.go.jsonl` | `fa46ed4bfc0f0ae7031e25ccd372169a00856d5eb9d7cfa900c2cb5a10c0928b` |
| `...daemon...stderr.log` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `...daemon...meta.json` | `c0665fa98eca9e491a31fb0435c7ee42d36371945e8259e287522d6b5f5bcd44` |

The raw files contain no DB password, `DATABASE_URL`, GitHub/PAT token, or `<redacted>` marker. The three PI keys are harness metadata only; actual backend identity remains unknown.

## DB release

No test process, advisory fixture lock, or DB session remains. No further Go test execution followed the three captured runs; post-run checks were read-only identity/schema/row-count queries and all sessions are closed. The dedicated DB is released for the main thread/author.

## Claim boundary

The 48 top-level RUN events are 24 distinct tests run twice; the 188 subtest RUN events are 94 distinct subtests run twice. They are not 236 independent business TCs. Complete business TC remains 0/49, the five majors remain unresolved, and this review does not authorize consumption, deployment, commit/push, or Gate advancement.
