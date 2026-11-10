# AIFI-45 test-fixture owned-record cleanup — review 3

## Verdict

- The four pre-existing governance tests now use unique CR IDs and exact owned-record cleanup. No broad CR/workspace/history deletion was introduced.
- The new public-seam cleanup behavior test was genuinely RED against the old helpers: the subtest created a 201 record, ended, and the parent observed `count=1`. It is now GREEN: the helper's `t.Cleanup` removes that exact record before the parent reads the fixture result.
- The original **38 `CR-9061*`** rows and the original **4 CR-9050/CR-9060 rows** remain byte-for-byte unchanged. Baseline 42-row aggregate: `a3c26e5cb2927a88b01e74c2b07a0837ceef44daada4e18448db8097f2346f19` before and after.
- Post-fix reruns: governance four-old-plus-head **115/115** (top 20, sub 95), cmd/server current-head router **5/5** (top 2, sub 3), daemon consume-refusal **2/2**; all exit 0, zero skip/fail.
- No new approval_record, CR, project, issue, project_resource, workspace, agent_task_queue, or daemon_token rows remain after the post-fix runs. DB released with 0 advisory fixture lock and 0 other sessions.
- No production, protocol, migration, generated, or quality-config file changed. Only test files and validation evidence changed.

## Source changes

New test helper/test file:

- `server/internal/governance/execution_fixture_ownership_test.go`

Modified test files:

- `server/internal/governance/execution_authorization_http_test.go`
- `server/internal/governance/execution_authorization_routes_test.go`
- `server/internal/governance/execution_fixture_export_test.go`
- `server/internal/governance/execution_trust_install_test.go`
- `server/internal/governance/execution_verifier_test.go`

`20261024T122543Z-aifi45-review3-source-delta-manifest.json` records the current hashes. All 17 files in `initial-head-p2-source-manifest.json` still match **17/17**, including the production head/router/SQL/migration/generated files. HEAD remains `f6e90ab8090c8a712c7fe2a324e977f10a39499c`.

## Helper design

- `executionTestCRID(base)` appends a random UUID decimal suffix; the four old tests now allocate a fresh CR per run.
- `executionAssertCRUnused` counts `cr` plus `approval_record` for the exact workspace+CR. If either exists, it hard-fails instead of pre-deleting old history.
- `ExecutionHTTPRecordForTest` now calls the unused guard instead of `resetCR`; external `governance_test` tests receive the allocator through the test-only `governance.ExecutionTestCRIDForTest` bridge.
- `executionHTTPPost` and `executionRoutePost` register cleanup only on `201 Created`.
- The helper resolves the newly created row by exact workspace+CR+stage=`execution`+decision=`approve`+response signature+source digest, then requires exactly one row.
- Cleanup deletes only `id=$recordID AND workspace_id=$ws AND cr_id=$cr AND stage='execution'`. Idempotent replays (200) and conflicts (409) never register ownership. No `DELETE ... WHERE workspace_id` or prefix-wide deletion exists.
- The four old tests no longer call `resetCR`: `TestExecutionAuthorizePersistsAndReplaysSource`, `TestExecutionAuthorizationRouteUsesRealAuthAndWorkspace`, `TestDaemonFetchesAndInstallsExecutionAuthorization`, `TestDaemonAuthenticatedDeliveryRunsCrctl`.

## RED → GREEN

### RED (old helpers)

`20261024T122422Z-aifi45-review3-cleanup-behavior-red.go.jsonl`

- top: RUN 1 / PASS 0 / FAIL 1 / SKIP 0
- all: RUN 2 / PASS 1 / FAIL 1 / SKIP 0
- exit 1; package 1.435 s; wall 5.281 s
- actual failure:

```text
=== RUN   TestExecutionAuthorizationCreatedRecordCleanupAtSubtestEnd
    execution_fixture_ownership_test.go:172: subtest-end cleanup left created approval_record 34bf88f0-cd9c-4a55-8e0d-7a1281695329 (count=1)
--- FAIL: TestExecutionAuthorizationCreatedRecordCleanupAtSubtestEnd (0.00s)
```

This is a real end-of-subtest fixture observation, not a compile error and not an assertion that old history is absent. The parent's exact cleanup then removed the RED-created row; post-RED query for that ID returned 0.

### Intermediate implementation build failure (not RED/GREEN evidence)

`20261024T122513Z-aifi45-review3-cleanup-behavior-green.*` is an intermediate build-failed attempt: the external `governance_test` package could not see the unexported helper (`undefined: executionTestCRID`). It produced 0 test events and exit 1. It is not counted as RED or GREEN. The exported test-only bridge was added and the final run was repeated.

### GREEN (final helper)

`20261024T122543Z-aifi45-review3-cleanup-behavior-green.go.jsonl`

- top: RUN 1 / PASS 1 / FAIL 0 / SKIP 0
- all: RUN 2 / PASS 2 / FAIL 0 / SKIP 0
- exit 0; package 1.533 s; wall 5.374 s
- the subtest-ended created record is gone before the parent count check.

## Post-fix reruns

### Four original tests plus head suite

`20261024T122543Z-aifi45-review3-postfix-governance.go.jsonl`

```text
go test ./internal/governance \
  -run '^(TestExecutionAuthorizePersistsAndReplaysSource|TestExecutionAuthorizationRouteUsesRealAuthAndWorkspace|TestDaemonFetchesAndInstallsExecutionAuthorization|TestDaemonAuthenticatedDeliveryRunsCrctl|TestExecutionAuthorizationHead)' \
  -count=1 -json -shuffle=on
```

| Level | RUN | PASS | FAIL | SKIP |
|---|---:|---:|---:|---:|
| top-level | 20 | 20 | 0 | 0 |
| subtest | 95 | 95 | 0 | 0 |
| all | **115** | **115** | **0** | **0** |

- exit 0; package 4.359 s; wall 6.213 s; shuffle seed `1792844787339333800`.
- all four original tests are in the selected top-level set and pass.
- no fail/skip/zero-match.

### Actual configured and default-off router

`20261024T122543Z-aifi45-review3-postfix-router.go.jsonl`

- top 2/2, sub 3/3, all 5/5; exit 0; package 1.858 s; shuffle seed `1792844805746728900`.
- top-level: `TestExecutionAuthorizationHeadRouterConfigured`, `TestExecutionAuthorizationHeadRouterDefaultOff`.
- wrapper crashed after raw capture because a metadata helper was undefined; the meta was reconstructed from raw and is marked accordingly. No rerun.

### daemon consume-refusal pair

`20261024T122543Z-aifi45-review3-postfix-daemon.go.jsonl`

- top 2/2, sub 0, all 2/2; exit 0; package 1.656 s.
- `TestExecutionVerifierRequiresExplicitNegativeFacts`, `TestClaimedExecutionTaskCannotStartOnRootAttributionAlone`.

## Protected history and residue

`20261024T122543Z-aifi45-review3-baseline42-before.json` and `...-after.json`:

- protected count: **42 before → 42 after**
- aggregate SHA256: `a3c26e5cb2927a88b01e74c2b07a0837ceef44daada4e18448db8097f2346f19` in both
- per-row IDs/content hashes: identical; **0 removed, 0 added**
- the 38 `CR-9061*` subset remains at aggregate `b25a957283bc9e9cb7c30999bad87f0560f4b338328d1811e6c2a0b7edc06733`
- the original four rows remain:
  - `CR-9050-002` id `d05e3645-f17d-4773-94ff-2bc4ac4b024f`, hash `503c1b4524987db31fb3797ce13e96696739f34d73e77eca79fd15c739622464`
  - `CR-9050-045` id `3dab082d-08e6-4f5d-88e5-1af3ef436770`, hash `a8e0f3478a2ce32529011bd80f06be24df09b162d3e3344294a9b12b216f4cb7`
  - `CR-9060-001` id `9d1deaf6-0e3e-4dd4-8d1d-58f53a9c7e04`, hash `4a79f47f227cd99d06c8b22f111f86ae85b6886ecdc3d8f9cc3fba58cb8a85e4`
  - `CR-9060-045` id `3a3edf4d-8751-452d-bcc2-ab1f79c5de0d`, hash `9620e9e1cce1076c7c9874adde7b38de979ce83df520bda6de83ebb233e959c1`

`20261024T122543Z-aifi45-review3-new-residue.json` after the post-fix runs:

- new approval_record rows after cutoff: **0**
- new cr/project/issue/project_resource/workspace/agent_task_queue/daemon_token: **0** each
- no broad SQL cleanup was performed. The four baseline rows were retained, not deleted.

DB release: advisory fixture lock **0**, other DB sessions **0**. Post-run identity/schema checks still show 671 migrations / latest `642_cr_execution_authorization_head`.

## Evidence hashes

| Artifact | SHA256 |
|---|---|
| `20261024T122422Z-aifi45-review3-cleanup-behavior-red.go.jsonl` | `96dbe93a2f0a189d49f716e13cdc9051a32ed079be899ecdd627e0cdf5982de4` |
| `...cleanup-behavior-red.meta.json` | `14bf80de4a9ce1dd1c4af15ae2a5cb2a3c8fdce27672cb8e5517f08b857d3f5d` |
| `20261024T122543Z-aifi45-review3-cleanup-behavior-green.go.jsonl` | `2a5508b4f5a7bace1cc5422efcbda1be0d20c2629d0e4e9fbae408eea041f65b` |
| `...cleanup-behavior-green.meta.json` | `f051700586a6378110b3c17d83546a782be966f32a9a2a22bc9a1062b07d5acf` |
| `20261024T122543Z-aifi45-review3-postfix-governance.go.jsonl` | `ad42a62baca622339480d3a2ede7873e8400828f80f80c0f2315dc35c282d478` |
| `...postfix-governance.meta.json` | `13ee16deea89dc77ac0172250c86c965a875bb3d5af4541a169834e5ce431109` |
| `20261024T122543Z-aifi45-review3-postfix-router.go.jsonl` | `5b264db7fcb0d975b728b540ee603b304bb9d4cbf088d9e1e1fc2e1028a0600b` |
| `...postfix-router.meta.json` | `0ccfda7154e165b52b922d11d2612cf8860f75bcc835735a6ee1f8a07a70673a` |
| `20261024T122543Z-aifi45-review3-postfix-daemon.go.jsonl` | `167745dcec10f1ed3da4757cb582c699380dcd3cc136e107a1803f248f11dd9f` |
| `...postfix-daemon.meta.json` | `77aec7a516b064e42b1bba2e83251711ca9e584ec86e9c7c47ecbad4bd6aef83` |
| `20261024T122543Z-aifi45-review3-baseline42-before.json` | `2b0759a5eb4ede1ea10e413681b3c9110bf4aa063cf3b1b9c3546d34ea41718a` |
| `20261024T122543Z-aifi45-review3-baseline42-after.json` | `5feeff56b932f1ec5203618038405dbfb83cdd6a2a61af96203bb1d63ffa4518` |
| `20261024T122543Z-aifi45-review3-new-residue.json` | `817b67dfb6707556235e329452398ba0caf15c20e7301d97be37efa8d519cca4` |
| `20261024T122543Z-aifi45-review3-source-delta-manifest.json` | `c5e4c699a1949d5bf347f394da50709f607d54b7d0af69a4b1a83b848b22e9bd` |

## Boundaries

- Only test files changed. No production code, protocol, migration, generated SQL, business quality config, CUSTOM, or main-thread resume record was modified.
- No Gate, commit, push, or deployment. Complete business TC remains 0/49.
- PI metadata only: `PI_PROVIDER=Gobao`, `PI_MODEL=deepseek-flash`, `PI_REASONING_LEVEL=max`; actual backend identity remains unknown.
