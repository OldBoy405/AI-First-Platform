# AIFI-45 governance test baseline — 20261024T113019Z

Change: `2026-10-22-aifi-45-authorized-execution`

## Scope and command

One execution only, via the existing dedicated runner
`C:/Users/GOBAO/AppData/Local/Temp/aifi45-gotest.cjs`. The runner file was not
modified. An inline Node preload captured the runner's `spawnSync('go', ...)`
stdout/stderr and left the runner's container-identity checks and spawn logic in
effect.

Equivalent Go invocation:

```text
go test ./internal/governance \
  -run '^(TestExecutionAuthorize|TestExecutionAuthorizationRoute|TestDaemonFetchesAndInstallsExecutionAuthorization)' \
  -count=1 -json
```

The proposed prefix `TestDaemonExecutionAuthorization` had zero source matches;
the actual relevant test was statically verified as
`TestDaemonFetchesAndInstallsExecutionAuthorization` and used instead.

## Actual result

| Metric | Value |
|---|---|
| exit | 0 |
| RUN (all JSON test events) | 10 |
| PASS (all JSON test events) | 10 |
| FAIL (all JSON test events) | 0 |
| SKIP (all JSON test events) | 0 |
| top-level RUN/PASS/FAIL/SKIP | 8/8/0/0 |
| wall-clock duration | 15,881 ms |
| Go package elapsed (last JSON event) | 2.427 s |
| raw JSON lines | 44 |
| subtest events | 2 |

Both subtest events are under
`TestDaemonFetchesAndInstallsExecutionAuthorization`:
`record_is_invisible_to_another_workspace_binding` and
`missing_record_and_missing_daemon_binding_fail_closed`; both passed.

### Exact top-level test names (all passed)

- `TestExecutionAuthorizeRejectsUntrustedCallers`
- `TestExecutionAuthorizePersistsAndReplaysSource`
- `TestExecutionAuthorizeRejectsCrossWorkspaceAndProjectMismatch`
- `TestExecutionAuthorizeRejectsStaleOrForeignResource`
- `TestExecutionAuthorizeRequiresFrozenCoordinatorRoot`
- `TestExecutionAuthorizationRouteUsesRealAuthAndWorkspace`
- `TestExecutionAuthorizationRouteDisabledAndTaskToken`
- `TestDaemonFetchesAndInstallsExecutionAuthorization`

No fail/skip names were emitted. Raw Go JSON contains every exact event name,
including the two subtests.

## Environment verification

- Container: `stdd-aifi45-20261022-pg`
- Full container ID:
  `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823`
  (runner prefix check `666bfec52ac3` passed)
- Running: true
- Label: `stdd.change=2026-10-22-aifi-45-authorized-execution`
- Port binding: `127.0.0.1:55432` only
- `POSTGRES_DB=stdd_aifi45_20261022`, `POSTGRES_USER=stdd`
- Live DB query: `current_database=stdd_aifi45_20261022`,
  `current_user=stdd`
- `schema_migrations` count: 670; latest version:
  `641_issue_context_refs_gin`
- `DATABASE_URL` was constructed only in memory by the runner from the
  container env; password was not printed or written.
- `GOPROXY=off`; runner deleted `KNOWLEDGE_BASE_*`, `GITHUB_TOKEN`, and
  `GH_TOKEN` from the child environment.
- No shared database or shared multica instance was accessed or modified.
- Raw logs were scanned for `postgres://user:pass@`, GitHub token patterns,
  `POSTGRES_PASSWORD`, and `DATABASE_URL=`; no matches remain. Only potential
  URL userinfo/GitHub token patterns would have been redacted by the wrapper.

## Harness metadata

From the three allowed environment keys:

- `PI_PROVIDER=Gobao`
- `PI_MODEL=deepseek-flash`
- `PI_REASONING_LEVEL=max`

Backend/provider identity beyond these harness environment values remains
**unknown**. No model identity is inferred from this test run.

## Artifacts

- Raw Go JSON stdout:
  `20261024T113019Z-aifi45-governance-baseline.go.jsonl`
  - 44 lines, package elapsed 2.427 s
  - SHA256: `447597c374ed3d81159b4d75658eb0be348b1fdb3899ff5b77c37dda87bf1072`
- Raw Go stderr:
  `20261024T113019Z-aifi45-governance-baseline.stderr.log`
  - SHA256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
  - empty
- Machine summary:
  `20261024T113019Z-aifi45-governance-baseline.meta.json`

## Claim boundary

This is a selected governance test baseline only. It does not close the full
business TC set, does not claim 49/49 TC completion, and does not verify the
unimplemented authorization/consumption/isolation paths. No source, business
configuration, documentation, or prior evidence was modified. No commit, push,
Gate, or infrastructure change was made.
