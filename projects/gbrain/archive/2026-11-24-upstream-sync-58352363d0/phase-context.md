# Phase Context: SPEC

- change_id: 2026-11-24-upstream-sync-58352363d0
- mode: thorough
- Gate 1 reapproved: 2026-11-24T19:43:29
- Gate 2 approved: 2026-11-24T19:43:42; reapproved for the narrowed scope and assertion sync
- Gate 3 approved: 2026-11-25T08:18:17Z, run `20261125T084500Z`, evidence “确认”
- confirmation: 重签 Gate 1，批准 Gate 2，确认 Gate 3

## Frozen inputs

- FORK=8f0e2d99983885d980fef98d6d5088c2649b38e5
- UPSTREAM=17b68cef4f4267ca0e5710b42f6ddc95acf9fe51
- BASE=553b5473344af4b8d9e09ebb8078e4e51a6d15eb
- rollback tag: pre-sync/2026-11-24-58352363d0 -> FORK
- fork commits: 59; upstream commits: 13; target VERSION: 0.60.638.0

## Locked decisions

- Merge the v0.60.638.0 window only; later releases remain separate changes.
- Attribute all 516 fork-side changed paths before admitting them to the candidate.
- Resolve six bilateral paths by behavior and true sources; never use whole-file ours/theirs.
- Keep upstream migration v297 and fork Inbox migration v298; do not import v299-v331.
- Rebuild generated artifacts from their true sources and require a no-drift second run.
- Apply only minimal candidate-tree repairs for the two merge-window gaps: Inbox managed content and query.trace retrieval diagnostics.
- The Graph visibility/degree gap is a pre-existing FORK issue in files the upstream window did not touch; per the 2026-11-25 user directive it is outside this merge and is not implemented or registered here.
- query.trace keeps full diagnostics in trace.retrieval while MCP _meta.retrieval remains independent; Admin must not discard _meta.
- Compare whitespace against both frozen parents; new warnings in this change must be zero.
- Baseline gaps and merge-introduced regressions are attributed separately.

## Phase 2 artifacts

- canonical/proposals/2026-11-24-upstream-sync-58352363d0.yaml
- design.md
- canonical/specs/code/fork-custom-behavior.yaml
- canonical/specs/code/upstream-sync-merge.yaml
- canonical/specs/agent/upstream-sync-verification.yaml
- anchors/L2-interfaces/2026-11-24-upstream-sync-58352363d0/api-contract.yaml
- test-plan.md
- specs/fork-custom-behavior/spec.md
- specs/upstream-sync-merge/spec.md

## Verification state

- Canonical DC-HASH/DC-BODY: 2/2 passed.
- Agent evidence plan dry-run: passed; adjusted to 10 CPs for the confirmed scope (Graph and Windows full unit declared `not_applicable`).
- 14 requirements, 14 scenarios, 14 TC checks; 150 unique inputs cover all 72 upstream paths.
- Phase 3 execution mode was `full_auto`, pre-authorized with `确认全部`; downgraded to `normal` after the full-regression execution blocker was identified.
- Candidate worktree: `C:/Users/GOBAO/Downloads/AI/gbrain-sync-2026-11-24-17b68cef`.
- Candidate branch: `sync/upstream-2026-11-24-17b68cef`; merge commit `0ad0323773`; master and `origin/master` at `7ccb531039`.
- Delivery executed with user authorization; production content sync/dream and the isolated legacy-DB upgrade probe remain not run.

## Phase 3 slice records

### Slice 1 — 隔离候选与三方合并

- TC coverage: 3/3 (TC-USM-001/002/003); new tests: 0 (diagnostic slice).
- `freeze`: passed; 59/13 commits, upstream VERSION 0.60.638.0, rollback anchor and main worktree verified.
- `bilateral`: passed; six bilateral paths, 11/11 fork baseline rows, two atom-fence rows, zero duplicate routes and zero atom-fence trailing whitespace.
- Manual attribution: 516/516 fork paths accounted for; `admin/src/routes.test.ts` added to ledger #15.
- Generated skills lock and 16 generated surfaces rebuilt; Admin dist/embedded manifest staged as one group.
- Evidence: `verification/runs/slice1/freeze/result.json` and `verification/runs/slice1/bilateral/result.json`.

### Slice 2 — 上游行为、迁移与生成物

- TC coverage: 3/3 (TC-USM-004/005/006); new tests: 44 (35 in four new files, nine added to common files; one replaced case).
- `upstream`: 114 pass / 0 fail / 0 skip / 0 timeout across all eight required files.
- `migrations`: order and registry passed with frozen UPSTREAM base; base max v297, fork-only v298, zero new migrations, zero skips. `database_upgrade_verified=false` because no isolated legacy-database probe was run.
- `generated`: Admin dist present, embedded check not skipped, regen/freshness/build passed, second regen produced no drift.
- Windows baseline A/B: system `core.autocrlf=true` with no explicit attributes made restored files probe as `unknown`/dirty and produced the 12k-file `ENOBUFS`; pristine upstream failed identically. With only `GIT_CONFIG_NOSYSTEM=1`, the restore file passed 26/26 and the 12k case passed on pristine upstream, fixed FORK and candidate.
- Evidence: `verification/runs/slice2-win-isolated/{upstream,migrations,generated}/result.json` and `verification/runs/slice2-win-isolated/baseline/result.json`.

### Slice 3 — Inbox managed 内容与 auto-link 守卫

- TC coverage: 1/1 (TC-FCB-001); new tests: 2 (managed actual write and committed-snapshot/permission guard); one existing unmanaged test renamed and strengthened.
- RED: 61 pass / 1 fail / 0 skip; the managed page lacked `inbox_status`, `raw_content`, `captured_at`, and ingestion metadata because the door received `event.content`.
- GREEN: 62 pass / 0 fail / 0 skip / 0 timeout; all three required Inbox cases passed. Reader/revision regression: 14 pass / 0 fail. Typecheck and staged/unstaged whitespace checks passed.
- Product change: managed `put_page` now receives the prepared `content`; source snapshot, expected revision, provenance, idempotency, trusted inline auto-link, and webhook permission checks remain unchanged.
- Evidence: `verification/runs/slice3-red/inbox/result.json` and `verification/runs/slice3-green/inbox/result.json`.

### Slice 4 — Admin 鉴权与审计合同

- TC coverage: 1/1 (TC-FCB-002); new tests: 3 real Express + PGLite runtime contracts in the existing route-guard file.
- Initial run: 14 pass / 1 fail / 0 skip; the only failure was the new test reading a legacy nested error shape instead of the current top-level agent envelope. No product defect was found.
- GREEN: 15 pass / 0 fail / 0 skip / 0 timeout; unauthenticated requests perform zero engine calls and emit no audit, authenticated purge is refused by the remote trust guard, and one successful op writes exactly one `admin-ui` row plus one independent SSE event.
- Product change: none. Existing `requireAdmin` ordering, `remote:true`, source header, scope check, and single audit path were retained.
- Typecheck and staged/unstaged whitespace checks passed.
- Evidence: `verification/runs/slice4-final/admin/result.json`; the assertion-shape correction is preserved in `verification/runs/slice4-red/admin/result.json`.

### Slice 5 — query.trace diagnostics (targeted complete; full-run waived on known Windows baseline)

- TC-FCB-003 targeted GREEN: all eight required trace, MCP, CLI and Admin cases passed with zero skips; nine tests were added. Evidence: `verification/runs/slice5-green-2/trace/result.json`.
- Windows harness fix: `run-unit-shard.sh` and `run-unit-parallel.sh` normalize `\` and `/` when matching Bun file headers; `test-env.sh` accepts native drive paths and uses `cygpath -m` for JUnit output. Candidate runner tests: 22 pass / 0 fail (81 expect calls).
- Full `bun run test` was stopped after the runner started one Bun process per file for 1145 files/shard; group 1 `test/setup.test.ts` alone had 51 known Windows launcher failures. The full run is not a pass and no full-run signal is claimed.
- Targeted merge batch (all 16 non-e2e changed test files): 224 pass / 1 fail / 0 skip. The only failure was `relative()` returning `src\...` against forward-slash REVIEWED keys, not a missed caller. After a test-side separator normalization in `test/takes-reservation-callers.test.ts`, that file passes 1/1 and the changed serial file passes 8/8.
- Admin suite: 28 files / 229 tests pass, 0 fail (`D:/tmp/gbrain-sync-tests/candidate-admin-test.log`).
- `check:regen-all` and `check:admin-embedded` pass; `scripts/structural-suites.tsv` was regenerated and staged. `check:newlines` and `check:module-size` pass when run individually with a longer timeout.
- `bun run verify`: 79 pass / 16 fail. Two timeout items pass when run individually; 12 failures fully match the documented Windows baseline. `check:function-size` additionally reports 2 pre-existing over-limit functions not in the baseline (`makeIngestCaptureHandler` 309 and inner 307), and `check:derived-census` has 1 pre-existing undispositioned inbox `softDeletePage` site; both exist at HEAD and are not merge-introduced. All failing inputs are files the merge did not touch; no merge-introduced verify failure remains.
- Merge-touched E2E PGLite arm: 2 pass / 0 fail. Postgres arm and live database upgrade were not run.
- Admin standalone TypeScript checking has two failures also present in unchanged FORK files; it is not reported as passed.
- Machine final audit: `final_audit_ok=True`, `unmerged_paths=0`, `new_whitespace_warnings=0`, both parent diffs and delivery boundary true; 592 candidate paths, 0 unexpected. Run: `verification/runs/20261125T072507Z/final`.
- `remaining` capability CP: root rc=0/fail=0, Admin rc=0, jobs suite passed, duplicate operations=0, required cases missing=0. Run: `verification/runs/20261125T072507Z/remaining`.
- `verify_upstream_sync.py` unit tests: 4/4 pass. Fixes were limited to the intentional path allowlist and reading the JUnit `file` attribute for the jobs suite; no product files changed.
- C1 three-way review: code review found no merge-blocking issue and confirmed all 99 paths, six bilateral unions, trust boundary, trace, migrations and Admin bundle; delivery review found no candidate-tree blocker after the ledger record was staged; test review’s actionable gaps were closed (E2E PGLite 2/2, fixture consumers classified as Windows-only, function-size/derived-census debt re-attributed).
- `check:skills-manifest` confirms `skills/skills.lock.json` is fresh, closing the code-review hash residual risk.
- Gate 3 formal run `20261125T084500Z`: 10/10 CPs pass; 2 manual receipts pass; Graph and Windows full unit are declared `not_applicable`. Same-run `stdd ci check-failures`: 9/9, TC execution coverage 14/14. Gate 3 confirmed with evidence “确认”.

## Delivery

- Merge commit `0ad0323773b751799f3938c1d4877ea35291113b`, parents `8f0e2d99` (FORK) and `17b68cef` (UPSTREAM); sync branch pushed.
- `master` fast-forwarded to `0ad0323773`; delivery ledger commits `7ccb531039` and `2e50b638f2`; local and `origin/master` both at `2e50b638f2`.
- Deployed CLI: `gbrain --version` = `0.60.638.0`; main-worktree `bun run typecheck` rc=0.
- Production migration: `apply-migrations --yes --no-autopilot-install` rc=0, `pending=[]`, `All migrations up to date`; 0.53.0 remains the registered `action_required` host action with no grants/consent change. Doctor connects to 22 pages; only `sync_freshness` and `cycle_freshness` fail, both content-maintenance state.
- Remote GitHub Release run `45575930229` failed in the `version` job; `build`/`ci-gate` skipped, logs unavailable. Master Test/E2E runs remain queued/pending. Remote release is not claimed published; no workflow change was made.
- Rollback anchor `pre-sync/2026-11-24-58352363d0` retained. Sync branch retained; no release tag created.

## Pending

- Phase 3 is complete: Gate 3 confirmed with the adjusted 10-CP evidence plan (Graph and Windows full unit declared `not_applicable`); `test-report.md` and `design-adjustments.md` are final.
- Slice 5 remains unregistered in `.stdd.yaml`: the Windows full-run baseline prevents a complete B3.4 regression; the formal Gate 3 run records the targeted evidence and limitation.
- Slice 6 Graph is outside this merge.
- Production content `sync`/`dream` was not run; it needs separate authorization.
- The isolated legacy-database upgrade probe was not run; `database_upgrade_verified=False`.
- Remote Release/Test/E2E status remains outside this delivery: Release `version` failed before build; Test/E2E are queued/pending. No workflow or permission change was made.
