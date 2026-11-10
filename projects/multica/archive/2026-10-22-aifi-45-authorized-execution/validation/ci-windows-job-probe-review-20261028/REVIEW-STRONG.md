# STDD strong review — Windows Job probe, safe-first-run (read-only)

Date: 2026-10-28
Mode: independent, read-only. Nothing was executed or built. No test, process, DB, container or engine was started.
Scope: whether a first run of the not-yet-run probe is safe. This is **not** capability acceptance.

## 1. Snapshot reviewed (old source; this verdict is bound to it)

- File: `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/supervisorjob_test/job_windows_test.go` (untracked at review time)
- Repo HEAD: `81e5293adc758e392a045026cf81ec5cc1bac72d`
- File sha256: `ea4746d75b74ef2f064debde8856ce0099322cc05bbcb95dbdae1d5719144535`
- git blob: `c393150c4974916aa511f9298d0f6722da7d5fe7`
- Size: 9053 bytes
- Dependency: `golang.org/x/sys v0.48.0` (go.mod line 35), checked against the module-cache source

**Snapshot status:** the author has since changed the probe based on these findings. This verdict applies **only** to the old snapshot above. It must **not** be carried over to the new snapshot automatically. The new source needs its own SHA record and a review of the changes (at least F1 and F2) before it is run.

## 2. Verdict (for the old snapshot)

**PASS-for-safe-first-run** (safety only).

- Safe-first-run means a run should not affect any process outside the test's own tree. It should not leak handles, secrets or output, and it must end within a bounded time. Every failure must stop the test rather than produce a false pass.
- Capability means the probe gives evidence about Windows Job behaviour that we can rely on. The old snapshot **does not** meet this. Because of F1, it would very likely fail at the final step (`probeFinalMembership`), so that result would not be useful evidence.
- Even after F1 is fixed, a pass is limited by F4. It is not evidence of kill-on-close termination or of a general process-tree exit.

## 3. Safety findings (old snapshot, all OK)

| Area | Conclusion |
|---|---|
| Only the test's own Job | `CreateJobObject(nil, nil)` makes an anonymous Job whose handle can't be inherited. Only the helper holds it. Nothing outside can open it by name or inherit it. |
| Who joins the Job | Only `AssignProcessToJobObject(job, CurrentProcess())` (the helper itself), plus the child the helper starts, which joins by inheritance. The code reads the limits back and refuses to continue if `BREAKAWAY_OK` or `SILENT_BREAKAWAY_OK` is set. No other process can be added. |
| Kill-on-close reach | Fires when the helper exits and its last handle closes. Reaches only the helper and its descendants still in the Job. The parent test process is never in the Job. |
| Nested host Job | If the host already runs the helper in a Job, the new Job sits underneath it, and its kill reaches only its own members. Nesting not supported → `probeAssignSelf` and stop. If the child is not in the Job, the membership check fails, then stdin EOF releases the child and it is waited for. |
| Handles | If setup fails before self-assignment, the Job handle is closed. After assignment it is deliberately left open until process exit (closing it would kill the helper). Pipes are closed by defers. Go exec passes only the standard I/O handles to children. |
| Default skip / switch | The test skips unless `MULTICA_TEST_WINDOWS_JOB_PROBE=1`. Child environment is only the role variable (Go adds SYSTEMROOT). No project imports and no TestMain, so no DB, container or engine. Re-run test binaries don't get `-test.paniconexit0`, so `os.Exit(0)` works as intended. |
| Hangs / timeouts | Parent: 40s context, WaitDelay 3s. Helper: `-test.timeout=25s`. Helper's context for the child: 12s; it also bounds the blocking ready-read (the pipe hits EOF when the child is killed). Child: `-test.timeout=15s`. Kills target only the single process each level started. If the helper is killed, closing its Job kills the child. |
| Exit code / stdout secrets | The parent stores only the first stdout byte and a count; any extra output fails the test. stderr is discarded, failure messages are fixed strings, and `err` is never printed. Checked in order: status byte, timeout, exit code. No path gives a false pass. |
| x/sys compile (by inspection) | Every API and constant used matches v0.48.0. Class constants are untyped, so they fit both int32 (Query) and uint32 (Set). The accounting struct (48 B) and process-ID list struct (24 B on amd64) match the Windows layouts. All imports are used. |

## 4. Findings

### F1 — must fix (result validity, not safety)
The final check expects `TotalTerminatedProcesses == 1`. Microsoft documents this field as counting processes **terminated because of a limit violation**, not normal exits. After the child exits normally it should be 0. The old snapshot would therefore very likely return `probeFinalMembership` after its 2-second poll.
Fix: change the expected value to `0`, or drop that field and keep `ActiveProcesses` plus the process ID list.

### F2 — should fix (switch hardening)
The helper and child roles only check `MULTICA_TEST_WINDOWS_JOB_PROBE_ROLE`; they don't require the opt-in switch. If the role variable is left set, a plain `go test` would run the helper inside the test process. Damage stays inside the test process (paniconexit0 makes it fail), but the child role could block on stdin until the default 10-minute test timeout.
Fix: require the opt-in or a per-run token for the roles, and `t.Skip` when the role is empty.

### F3 — should fix (memory hardening)
The `uintptr(unsafe.Pointer(&local))` buffers could, rarely, go stale if the goroutine stack grows before the syscall. The worst case is memory corruption inside the test process only. Common x/sys pattern; low risk.

### F4 — claim scope (must not be overstated)
A pass shows only these things:
- the Job can be created and its limits set and read back;
- the helper can join it, including when nested in a host Job;
- the child inherits membership;
- the Job holds only the helper after the child exits.

The child is released gracefully, so kill-on-close is never actually triggered or observed. Nothing checks that the tree is empty after the helper exits. Processes created on the test's behalf by services (WMI, COM, scheduled tasks) are out of scope. The test name "Capability" must not be cited as kill or tree-exit evidence.

## 5. Remaining risks
- EDR or Process Explorer holding a duplicate Job handle would delay kill-on-close (only for the test's own tree).
- If conhost or WER processes end up in the Job, the run fails rather than passing falsely.

## 6. Required next step
The author's revised snapshot is a new input. Record its file sha256 and git blob, then do a review of the changes (F1 must be resolved; check F2–F4). Only then decide whether it is safe to run. This report does not extend to the new snapshot.
