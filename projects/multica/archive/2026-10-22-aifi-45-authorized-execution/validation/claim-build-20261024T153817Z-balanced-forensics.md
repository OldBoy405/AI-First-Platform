# Balanced rerun forensics — approval_record drift

Read-only follow-up. No tests, DB SQL, container commands, source edits, cleanup or history reconstruction were performed. Existing report/raw evidence was not modified.

## Source identity (correction to the earlier report)

`validation/claim-build-20261024T153817Z-author-source.json` matches the current balanced snapshot **5/5** exactly for all five slice files. The earlier report sentence that author evidence does not correspond to current source is superseded by this correction.

`validation/claim-build-20261024T153817Z-before-manifest.json` is the **preimplementation T baseline**; it differs from current/author source on `task.go`, `daemon.go` and `daemon_start_claim_test.go`. That is expected implementation movement, not an author/current mismatch. The five current hashes are recorded in `claim-build-20261024T153817Z-balanced-source-manifest.json`.

## Root-cause mechanism (code-level)

- `server/internal/governance/crsync_test.go:41 TestMain` runs the whole package, then `:79 cleanup(ctx, pool)`.
- `server/internal/governance/crsync_test.go:94 cleanup` deletes `cr_sync_event`, `agent_task_queue` and `cr` rows (`:96-98`) but **does not delete `approval_record`**. Test-created approval rows can therefore survive suite cleanup.
- `server/internal/governance/crsync_test.go:104 resetCR` deletes `approval_record WHERE cr_id=$1` at `:114` (plus CR/task/sync rows). `server/internal/governance/gate_projection_test.go:11 resetGateProjection` repeats the same approval delete at `:16` before calling `resetCR`.
- The full governance `^Test` run includes the approval/crsync tests that call these helpers (e.g. `approval_ack_cp_test.go:83,138`, `approval_continuation_test.go:173,326`, `approval_gate_binding_test.go:161,499`, `approval_test.go:247`, `crsync_approval_gate_test.go:117`). The author green2 argv only ran `^TestExecutionStartClaimDaemonOwnership$` (3/3), so those reset tests were newly included in this batch.
- Most plausible mechanism: a full-suite test resets a CR whose approval history contains the 41 baseline rows; `resetCR:114` removes exactly those 41. The tests then write 40 approval rows, and `cleanup:94-99` leaves those approval rows behind. Arithmetic is exactly 83 − 41 + 40 = 82. This is consistent with the observed missing/extra counts, but the exact triggering test and CR are **not yet proven** from the persisted artifacts.

## Evidence boundary

The 41 missing and 40 extra ID sets were not written to durable evidence by this rerun; the published report contains only example IDs, and the T baseline stores `id|md5` strings without `cr_id`. Therefore I cannot verify from the current artifacts whether the missing set overlaps the separate `20261024T122543Z-aifi45-review3-baseline42-before.json` set. The count 83 = 42 + 41 is suggestive, but not proof that baseline42 is intact.

No claim is made that data was not lost, and no automatic history reconstruction is proposed. To close this, main needs a read-only DB/backup comparison that maps the full missing/extra IDs to `approval_record.cr_id` (and, if needed, baseline42 IDs), then identifies the first full-suite test using that CR. Do not rerun the suite or mutate the DB from this evidence.
