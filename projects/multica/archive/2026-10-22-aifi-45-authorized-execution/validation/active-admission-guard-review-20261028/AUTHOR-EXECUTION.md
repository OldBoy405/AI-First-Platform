# Author execution: ACTIVE admission guard

## Scope and evidence boundary

This is the author's observation of a local guard-order fix, not an independent review or RUN-006 acceptance evidence. The implementation change was limited to `server/internal/governance/execution_deployment.go`; the new test is `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`. `CUSTOM.md` was not modified by this task.

The test calls `CheckDeploymentAccessTx` through a fake `pgx.Tx`. It checks the expected head → event → readiness query order, SQL fragments and arguments; a missing head stops after the head query. STOP_NEW uses an event with a nil verdict reference, matching the existing stop writer. The tests do not exercise a PostgreSQL server, real transaction locking, production integration, or container behavior. No parent-package tests, DB, or containers were run or operated. This local result **does not count as TC-RUN-006 passing**.

The command outputs were observed in the agent tool responses; no separate raw output log was retained. The excerpts and counts below are observations, not claims of saved log files.

## Commands and environment

All Go tests were run from `C:/Users/GOBAO/Downloads/AI/multica/server`, with `DATABASE_URL` cleared, all inherited `PG*` variables unset, common `PG*` variables explicitly set to empty, and `GOPROXY=off`. The same package command was used for every run:

```bash
while IFS='=' read -r name _; do
  case "${name^^}" in PG*) unset "$name";; esac
done < <(env)
export DATABASE_URL='' PGHOST='' PGHOSTADDR='' PGPORT='' PGDATABASE='' PGUSER='' PGPASSWORD='' PGSERVICE='' PGSERVICEFILE='' PGPASSFILE='' PGOPTIONS='' PGSSLMODE='' GOPROXY=off
go test -v -count=1 ./internal/governance/deploymentaccess_test
```

Before the initial RED the new test was formatted with `gofmt -w internal/governance/deploymentaccess_test/execution_deployment_test.go`. Before the first GREEN both allowed files were formatted with `gofmt -w internal/governance/execution_deployment.go internal/governance/deploymentaccess_test/execution_deployment_test.go`. A later `gofmt -d` of both files produced no diff. `git diff --check` on the production file produced no whitespace errors; Git did warn that LF would be replaced by CRLF the next time Git touches that file.

## Observed sequence

1. **Initial RED:** the independent test package compiled and executed against the unmodified guard order. Five ACTIVE/unexpired cases failed: `new_admission`, `new_selection`, `command_issue`, `new_candidate`, and `new_effect`. The other 50 leaf cases passed. The relevant observed diagnostic was:

   ```text
   CheckDeploymentAccessTx(new_admission) = Denied, want NewAdmission
   ```

   This was an assertion failure, not a compile or fixture failure. The observed source had `denyOps` before the ACTIVE/unexpired branch, so it rejected these operations unconditionally. Before the subsequent fix the source and test SHA-256 values were measured as the original and test hashes listed below; a hash was not separately captured immediately before the initial RED.

2. **First GREEN:** moved only the `denyOps` guard to after the ACTIVE/unexpired branch. The same package command passed all three top-level tests and all 55 leaf cases: 20 new-operation/state cases, 20 audit/state cases, and 15 recovery cases. The tests include STOP_NEW, ACTIVE expiry, missing head, audit, matching recovery and several recovery rejection controls.

3. **Targeted mutation RED:** moved the guard back to its original, incorrect position before the ACTIVE branch. The mutated source SHA matched the measured original source SHA. The same package command again failed exactly the five ACTIVE/unexpired new-operation cases; the remaining 50 leaf cases passed. The `new_admission` diagnostic again reported `Denied`, wanted `NewAdmission`.

4. **Restore and GREEN:** moved the guard back after the ACTIVE branch. Before rerunning, the source SHA matched the first GREEN source SHA exactly and the test SHA remained unchanged. The same package command passed all 55 leaf cases again. Both hashes were also unchanged after that run.

## SHA-256 of observed source states

| File / state | Raw SHA-256 |
|---|---|
| `server/internal/governance/execution_deployment.go`, original before fix and mutation | `479d203e3268b5ccc3fa8e396560cecc3311ebf5b3176eedfe3680d179c4999e` |
| `server/internal/governance/execution_deployment.go`, first GREEN and restored final | `f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811` |
| `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`, measured before fix and unchanged through final GREEN | `c30f2816bd0f48359941f1993f85273feb481bc2169b6abc688d0b5f68b573f0` |

The final production diff shows only the guard relocation. These fake-query tests demonstrate the local branch behavior and the targeted mutation sensitivity; they do not establish database semantics or the broader RUN-006 execution and recovery flow.
