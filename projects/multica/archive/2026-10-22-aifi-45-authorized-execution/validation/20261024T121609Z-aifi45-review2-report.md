# AIFI-45 C1 balanced review 2 — 20261024T121609Z

## Verdict

- P2 negative-zero defect was independently confirmed from the author's raw RED artifact: **0 PASS / 3 FAIL / 0 SKIP**, exit 1, with real `POST=201 → GET=409` on both `repair_limit:-0` and `sensitive_actions[0].limit:-0`.
- The minimal 3-file fix is present and the new GREEN artifact is 3/3 exit 0. This review does not treat the earlier green baseline as defect-free.
- Both prior coverage blockers are closed by real tests:
  1. `RouterOptions.ExecutionContract` → `NewRouterWithOptions` configured current-head 200 is exercised by `TestExecutionAuthorizationHeadRouterConfigured`.
  2. Concurrent same/different raw one-head and post-commit lost-response retry are exercised by `TestExecutionAuthorizationHeadHTTPConcurrentInitial` and `TestExecutionAuthorizationHeadHTTPReplayAfterLostResponse`.
- The final 38-row `CR-9061*` history invariant is intact: 38 before, 38 after, exact per-row IDs/content hashes unchanged, 0 removed, 0 added.
- **Global no-new-residue does not fully hold:** the combined governance run left 4 new `approval_record` rows outside `CR-9061*` from pre-existing tests. Details below. No broad cleanup was performed.
- The prior `00/01` analogy is withdrawn: `00`/`01` are not legal JSON, were not a negative-zero risk, and are not treated as a code defect.
- No new product-code defect was found in the 3-file P2 fix within this review scope.

## P2 raw RED/GREEN, read from JSONL

### RED

`20261024T120130Z-head-p2-negative-zero-red.go.jsonl`

- all: RUN 3 / PASS 0 / FAIL 3 / SKIP 0, exit 1
- top: RUN 1 / PASS 0 / FAIL 1 / SKIP 0
- test: `TestExecutionAuthorizationHeadHTTPPreservesNegativeZeroSource/repair_limit` and `/sensitive_action_limit`; parent also fails.
- actual output (not summary):

```text
before replay: initial POST=201, head GET=409
before replay head GET = 409, want 200 after accepted negative-zero initial:
{"error":"EXECUTION_AUTHORIZATION_HEAD_INVALID"}
after exact replay: initial POST=201, head GET=409
after exact replay head GET = 409, want 200 after accepted negative-zero initial:
{"error":"EXECUTION_AUTHORIZATION_HEAD_INVALID"}
```

- RED production `execution_authorization_head.go` hash was `6500eb93...404f` (the v1 hash), so the failure was against the original implementation, not a compile/DB/zero-selection failure.
- raw SHA256: `173e283337d58d38de45def02d0307e7c63c03130ece54fba17412f593cf2ed4`

### GREEN

`20261024T120233Z-head-p2-negative-zero-green.go.jsonl`

- all: RUN 3 / PASS 3 / FAIL 0 / SKIP 0, exit 0
- the same two negative-zero subtests pass.
- raw SHA256: `118797961548cc09d2bb95c552a8cbf40144236ffbc7a3fc795abb2a4592c834`

## P2 fix and 3-file scope

Current source manifest `initial-head-p2-source-manifest.json`: **17/17** files match after CRLF→LF normalization. Exactly the 3 files below changed from v1; the other 14 are unchanged.

| File | Current SHA256 (LF-normalized) |
|---|---|
| `server/internal/governance/execution_authorization_head.go` | `4d5ab17a7010b8d96112f5c6645a7f46eec4cedb6f371b9f1faee97968658556` |
| `server/internal/governance/execution_authorization_head_test.go` | `2c2dd8aef9eedf12f7123e017b844a56b9a23bea38afd3b671ea62bc219831f1` |
| `server/cmd/server/execution_authorization_head_test.go` | `1a4ef311fdf185c8bf98c9546d93485ddc689775e3c879df7cbb6f3c0d02009e` |

`execution_authorization_head.go:202-243` now:

- calls `ValidateExecutionJSON` before comparison (duplicate keys, invalid JSON, multi-doc, invalid UTF-8 still rejected);
- recursively decodes `json.Number` values through `executionSafeInteger(..., min=0)` into exact int64 values;
- compares integer values, so valid `-0` equals `0`, without rewriting the source/payload buffers;
- rejects strings, null, bool, decimals, exponents, negatives, unsafe/overflow values.

`00`, `01`, and `-00` are invalid JSON and are rejected before integer comparison. The previous review's analogy between those spellings and `-0` is explicitly withdrawn and is not counted as a defect.

## Independent re-run

All runs were sequential, one Go test process each, through the unchanged runner. The runner retained its container ID/label/port/DB checks, `GOPROXY=off`, and removal of GitHub/knowledge tokens. New raw/meta files do not overwrite earlier evidence.

### 1. Governance same combo, `-count=1 -shuffle=on` (approximately 172 events)

Final argv captured before invocation:

```text
go test ./internal/governance \
  -run '^(TestExecutionAuthoriz|TestExecutionGrantCheckAgainstRealCrctlCLI|TestDaemonAuthenticatedDeliveryRunsCrctl|TestDaemonFetchesAndInstallsExecutionAuthorization)' \
  -count=1 -json -shuffle=on
```

| Level | RUN | PASS | FAIL | SKIP |
|---|---:|---:|---:|---:|
| top-level | 30 | 30 | 0 | 0 |
| subtest | 142 | 142 | 0 | 0 |
| all test events | **172** | **172** | **0** | **0** |

- exit: 0
- package elapsed: 5.330 s; process wall clock: 7.369 s
- shuffle seed: `1792844201595387800`
- exact raw names: 30 top-level, 142 subtest names; no fail/skip; no zero-match
- new tests actually present and passing: `TestExecutionAuthorizationHeadHTTPConcurrentInitial` (same/different raw), `TestExecutionAuthorizationHeadHTTPReplayAfterLostResponse`, `TestExecutionAuthorizationHeadHTTPPreservesNegativeZeroSource`, `TestExecutionAuthorizationHeadHTTPIntegerInputBoundaries`, `TestExecutionAuthorizationHeadIntegerComparisonBoundaries`, `TestExecutionAuthorizationHeadFixtureCleanupIsScoped`.

Top-level names (all PASS):

```text
TestDaemonAuthenticatedDeliveryRunsCrctl
TestDaemonFetchesAndInstallsExecutionAuthorization
TestExecutionAuthorizationBuildsSignedStructuredSource
TestExecutionAuthorizationHeadFixtureCleanupIsScoped
TestExecutionAuthorizationHeadHTTPAuthAndConfiguration
TestExecutionAuthorizationHeadHTTPConcurrentInitial
TestExecutionAuthorizationHeadHTTPIntegerInputBoundaries
TestExecutionAuthorizationHeadHTTPPersistsInitial
TestExecutionAuthorizationHeadHTTPPointerIsTheOnlySelector
TestExecutionAuthorizationHeadHTTPPreservesNegativeZeroSource
TestExecutionAuthorizationHeadHTTPPreservesOriginalCRLFBytes
TestExecutionAuthorizationHeadHTTPRejectsForeignHistoryAndProject
TestExecutionAuthorizationHeadHTTPRejectsMissingAndDriftedAuthority
TestExecutionAuthorizationHeadHTTPRejectsSignedInvalidPayload
TestExecutionAuthorizationHeadHTTPReplayAfterLostResponse
TestExecutionAuthorizationHeadHTTPReplayNeverRebuildsAuthority
TestExecutionAuthorizationHeadHTTPRollsBackHistoryWhenHeadWriteFails
TestExecutionAuthorizationHeadIntegerComparisonBoundaries
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
TestExecutionGrantCheckAgainstRealCrctlCLI
```

The concurrency test explicitly observes both HTTP transactions waiting on `FOR UPDATE OF cr`, then asserts 201+200/reused for same raw and 201+409 for different raw, one history/head, and daemon GET reads the sole winner. The lost-response test uses a real HTTP handler with a response writer that returns `io.ErrClosedPipe` on the post-commit 201 write, verifies the committed history/head, replays the exact bytes, and asserts 200/reused without rebuilding. This is response-writer fault injection, not a TCP disconnect or process crash proof.

### 2. cmd/server current-head router tests

Final argv:

```text
go test ./cmd/server -run '^TestExecutionAuthorizationHeadRouter' -count=1 -json -shuffle=on
```

| Level | RUN | PASS | FAIL | SKIP |
|---|---:|---:|---:|---:|
| top-level | 2 | 2 | 0 | 0 |
| subtest | 3 | 3 | 0 | 0 |
| all test events | **5** | **5** | **0** | **0** |

- exit: 0
- package elapsed: 1.879 s; process wall clock: 4.706 s
- shuffle seed: `1792844242141441700`
- top-level: `TestExecutionAuthorizationHeadRouterConfigured`, `TestExecutionAuthorizationHeadRouterDefaultOff`
- subtests: `authenticated_head_is_explicitly_disabled`, `head_still_requires_real_auth`, `legacy_delivery_stays_conditionally_mounted`
- `RouterOptions.ExecutionContract` → `NewRouterWithOptions` → real human POST 201 → DB-backed daemon-token GET 200 → unchanged record/signature/head/no-store is covered by the configured test.

### 3. daemon consume-refusal tests

```text
go test ./internal/daemon \
  -run '^(TestExecutionVerifierRequiresExplicitNegativeFacts|TestClaimedExecutionTaskCannotStartOnRootAttributionAlone)$' \
  -count=1 -json
```

- all: RUN 2 / PASS 2 / FAIL 0 / SKIP 0, exit 0
- top-level: 2/2; subtest: 0
- package elapsed: 1.728 s; process wall clock: 4.291 s
- exact names: `TestExecutionVerifierRequiresExplicitNegativeFacts`, `TestClaimedExecutionTaskCannotStartOnRootAttributionAlone`

## Coverage blockers closed

- **Configured-router blocker: CLOSED.** The new configured test uses `RouterOptions{ExecutionContract: &contract}` and `NewRouterWithOptions`; the independent cmd/server run includes it and passes 5/5 events. It is not just the shared mount helper.
- **Concurrency/response-loss blocker: CLOSED for the previously missing test coverage.** Same/different concurrent initial requests and post-commit response-writer failure/retry now have real tests, both passing. Residual boundary: no crash-kill, TCP disconnect, or all distributed exactly-once proof; the test report itself says the same.
- **P2 negative-zero blocker: CLOSED for the reported `-0` cases.** RED was real and GREEN now passes. `00`/`01` are not a valid-JSON analogue and are withdrawn from the defect theory.

## 38-history invariant and residue

Before snapshot: `20261024T121609Z-aifi45-review2-db-before.json`
After snapshot: `20261024T121609Z-aifi45-review2-db-after.json`

- `CR-9061*` history: **38 before → 38 after**
- aggregate content SHA256: `b25a957283bc9e9cb7c30999bad87f0560f4b338328d1811e6c2a0b7edc06733` in both snapshots
- per-row ID/content hashes: identical; **0 removed, 0 added**
- matching `cr` rows: 0 before and after
- schema/migrations unchanged: 671 / `642_cr_execution_authorization_head`; new column uuid/nullable/default null; 2 existing FKs, 0 new-column index.

**Residue finding (new, test hygiene):** `20261024T121609Z-aifi45-review2-new-residue.json` shows 4 new `approval_record` rows created after the cutoff and outside `CR-9061*`:

| CR | source test |
|---|---|
| `CR-9050-045` | `TestDaemonFetchesAndInstallsExecutionAuthorization` |
| `CR-9060-045` | `TestDaemonAuthenticatedDeliveryRunsCrctl` |
| `CR-9050-002` | `TestExecutionAuthorizePersistsAndReplaysSource` |
| `CR-9060-001` | `TestExecutionAuthorizationRouteUsesRealAuthAndWorkspace` |

These are from pre-existing tests in the selected governance combo, not the new P2 head fixture. The new scoped cleanup test passes and left no new `CR-9061*` row. No new `cr`, project, issue, project_resource, workspace, agent_task_queue, or daemon_token rows remain. The one `CR-9061` row with a future `created_at` (CR-9061-220 decoy) is pre-existing and is one of the unchanged 38, not a new row.

Minimal fix (not applied): add exact per-CR `t.Cleanup` for those four old test fixtures, or give them unique CR IDs. **Do not** add workspace-wide `approval_record` cleanup: the 38 protected rows share the test workspace and would be swept. The `TestMain` cleanup currently deletes `cr` but not `approval_record`; that is why these four persist.

## DB release

Post-run: advisory fixture lock **0**, other DB sessions **0**. No further Go test execution after the three runs. The dedicated DB is released. Post-run reads were identity/schema/history checks only.

## Artifacts and hashes

| Artifact | SHA256 |
|---|---|
| `20261024T121609Z-aifi45-review2-governance-combo.go.jsonl` | `0a79b3625c9ce80d0fb0f8f2444cbf14db545a306316eacb4aa7fb52d6577ed3` |
| `...governance-combo.meta.json` | `00a03933a8f8ad80fd94094bb123c89ea9603ed125ec692d45d57882608df7f8` |
| `...governance-combo.stderr.log` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `20261024T121609Z-aifi45-review2-cmdserver-current-head.go.jsonl` | `6b9bacc278bd13147998bace3989274c4cb43ef7889a6e6f42a2d79c99dde1e1` |
| `...cmdserver-current-head.meta.json` | `7fd365a2924c7e7fed78e44cafac93dcf59caf9a2630ceeb8b6d9e16c8875336` |
| `...cmdserver-current-head.stderr.log` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `20261024T121609Z-aifi45-review2-daemon-consumption.go.jsonl` | `35ab4ae64c34d632197243e7f2fb80ae4c3bc1306a8337cc6eace187b09fedff` |
| `...daemon-consumption.meta.json` | `26fdd6cf1307640a0890c9d8eafbadaa6d4e1e23d687610e29b00f340d00295d` |
| `...daemon-consumption.stderr.log` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `20261024T121609Z-aifi45-review2-db-before.json` | `072291e48d43bfd8b1648c9dc12e89260186d21c911c394cd43af2b2401ff41d` |
| `20261024T121609Z-aifi45-review2-db-after.json` | `d904e8ba3cb74df42fa192fc2ff962fb37a6d691ede1874032007395d9fa2281` |
| `20261024T121609Z-aifi45-review2-new-residue.json` | `72b76f697293220af299c1f9b57bfeba311c50bb1dddd5f685a931c96b11261b` |

No source/config/migration was changed by this review. No Gate, commit, or push. PI metadata only: `PI_PROVIDER=Gobao`, `PI_MODEL=deepseek-flash`, `PI_REASONING_LEVEL=max`; actual backend identity remains unknown. Complete business TC remains 0/49.
