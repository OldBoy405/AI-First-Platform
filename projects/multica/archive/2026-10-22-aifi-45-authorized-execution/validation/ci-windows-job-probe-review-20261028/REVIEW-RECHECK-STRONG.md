# STDD strong recheck — revised Windows Job probe, safe-first-run (static, read-only)

Date: 2026-10-28
Mode: independent, read-only, static. **The reviewer did not run anything for this review.** Nothing was compiled or run; no test, process, DB or container was started.
Scope: only F1, F2, and any new timeout or resource-safety regressions. **Capability acceptance is out of scope.**
Earlier report: `REVIEW-STRONG.md` (raw sha256 `62d3bce892415b70588b8567905bc3175b08fd8735e5ae264c41777d2be2f2b7`). It is left unchanged and still records the old snapshot.

## 1. Snapshot reviewed

- File: `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/supervisorjob_test/job_windows_test.go`
- File sha256: `27bb70f91c0f05cf20ac01e472e12bb65b5ac2b2474a7d9478bf4e38aa941c3a` (matches the requested SHA; re-checked before this report was written)
- git blob: `5e2cd6b8368b606666e05fce9eb8b3fa5a89756e`
- Size: 9056 bytes
- Repo HEAD: `81e5293adc758e392a045026cf81ec5cc1bac72d` (file untracked)
- Old snapshot (for comparison): sha256 `ea4746d75b74ef2f064debde8856ce0099322cc05bbcb95dbdae1d5719144535`, git blob `c393150c4974916aa511f9298d0f6722da7d5fe7`
- Comparison method: the old file had been overwritten, so the new source was compared against the findings in the earlier report rather than with a raw diff.

Any change to the source invalidates this conclusion.

## 2. Verdict

**PASS-for-safe-first-run** (run safety only).

- This means a first run should not affect any process outside the test's own tree. It should not leak handles, secrets or output, and it must end within a bounded time. Every failure must stop the test rather than produce a false pass.
- This is **not** capability acceptance. A first-run PASS or FAIL is evidence to be evaluated separately.
- This conclusion is static. It has not been confirmed by actually running the probe.

## 3. F1 — terminated-count assumption removed: resolved

- `membersAndAccounting(job, self, child, total)` no longer takes an expected terminated count.
- All three calls were updated:

  | Call | Expected members | Expected total ever joined |
  |---|---|---|
  | Initial | 1 | 1 |
  | With child | 2 | 2 |
  | Final | 1 | 2 |

- The final check now passes only if all of these hold:
  - the Job's process list is exactly `{self}`;
  - `ActiveProcesses == 1`;
  - `TotalProcesses == 2`.
- The bounded 2-second poll is unchanged.
- The `totalTerminatedProcesses` field is still in `basicAccounting`, only to keep the Windows struct layout. It is not read, does not stop compilation and does not affect safety.
- Any mismatch still returns a failure code. There is no false-pass path.

## 4. F2 — explicit opt-in passed parent → helper → child, not triggerable by default: resolved

- **Parent:** skips unless `MULTICA_TEST_WINDOWS_JOB_PROBE=1`.
- **Parent → helper:** `cmd.Env = {optInEnv=1, roleEnv=helper}`.
- **Helper → child:** `cmd.Env = {optInEnv=1, roleEnv=child}`.
- No other environment is inherited; Go adds SYSTEMROOT.
- **Re-entry test:** returns immediately unless `optInEnv == "1"`. A plain `go test`, even with the role variable left set, can no longer start a helper or child.
- **Residual risk (non-blocking):** an operator who sets both the opt-in and the role variable in their own shell can still trigger a role inside the `go test` process. The `-test.paniconexit0` flag that `go test` passes makes `os.Exit(0)` fail that run, and the effect stays within the test process and the child it starts. This needs a deliberate double setting.
- **Cosmetic:** without the opt-in, the re-entry test returns and shows as PASS rather than SKIP.

## 5. Timeout and resource regressions: none found

- **Timeouts unchanged:**
  - parent: 40s context, WaitDelay 3s;
  - helper: `-test.timeout=25s`;
  - helper's context for the child: 12s, which also bounds the ready-read;
  - child: `-test.timeout=15s`.
- **Kills:** each level kills only the single process it started. If the helper exits or is killed, kill-on-close takes down only members of its own Job.
- **Job:** still anonymous, created with nil attributes so its handle can't be inherited. The helper still refuses to continue if `BREAKAWAY_OK` or `SILENT_BREAKAWAY_OK` is set. Still only the helper itself and the child it starts can be members.
- **Handles and pipes:** unchanged. Before self-assignment, the Job handle is closed on failure. After assignment it stays open until process exit. Pipes are closed by defers, and an unfinished child is always waited for.
- **Output and exit:** unchanged. The parent keeps only the first stdout byte and a count, discards stderr and uses fixed failure messages. Checks run in order: status byte, timeout, exit code.
- **Compiles (static inspection only):** the call sites match the new signature, all imports are used, and the x/sys v0.48.0 APIs used are the same as in the earlier review.

## 6. Still open (non-blocking)

- **F3:** passing `uintptr(unsafe.Pointer(&local))` carries a rare risk of a stale pointer if the stack grows. Any damage stays inside the test process.
- **F4:** a pass does not prove kill-on-close and does not prove the whole process tree exited. The child is released gracefully, so kill-on-close is never triggered or observed, and nothing checks the tree after the helper exits.
- An EDR tool or Process Explorer holding a duplicate Job handle could delay kill-on-close. This affects only the test's own processes.
- If conhost or WER processes end up in the Job, the run fails rather than passing falsely.

## 7. Next step

The source with sha256 `27bb70f9…941c3a` may be used for a first run. Before running, confirm the file SHA is unchanged. The first-run result is evidence for a separate capability review. This report does not count as capability acceptance.
