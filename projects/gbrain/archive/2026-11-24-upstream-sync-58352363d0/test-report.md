# Test Report — 2026-11-24-upstream-sync-58352363d0

## Selected run

- Run id: `20261125T084500Z` (selected); earlier partial runs `20261125T072507Z` and `20261125T081600Z` were superseded.
- Machine final audit: `verification/runs/20261125T084500Z/final` — `final_audit_ok=True`, `unmerged_paths=0`, `new_whitespace_warnings=0`, delivery boundary true.
- Formal agent verification: 10/10 CPs pass, 2 manual TC receipts pass, 2 declared `not_applicable` (Graph, Windows full unit). Report: `validation/runs/20261125T084500Z/agent-verification-report.md`.
- Same-run CI failure-mode checks: 9/9 pass, TC execution coverage 14/14 (100%).
- Remaining capability CP: `verification/runs/20261125T084500Z/remaining` — root/Admin rc=0, jobs suite passed, duplicate operations=0, required cases missing=0.

## TC coverage

- Planned scenarios/TC checks: 14.
- Gate 3 execution coverage: 14/14 (10 CP-backed, 2 manual, 2 declared not applicable).
- Slice 5 is not registered in `.stdd.yaml`: the Windows full-run baseline prevents a complete B3.4 regression; the formal Gate 3 run records the targeted evidence and the limitation.
- Slice 6 (Graph visibility/parity) is out of scope per the 2026-11-25 user directive; `CP-FCB-004` is declared `not_applicable` in the evidence plan, not executed.

## Results

| Check | Result |
|---|---|
| Merge-surface non-serial tests | 16 files / 225 tests: 224 pass / 1 fail, then the one Windows path false positive was fixed; fixed file 1/1 pass |
| Merge-surface serial test | 8 pass / 0 fail |
| Merge-touched E2E PGLite arm | `test/e2e/managed-sync-shared-origin-6517.test.ts` 2 pass / 0 fail |
| Changed fixture consumers | doctor content/hot-checks: Windows temp-git `writer_manifest_unsafe`; doctor-json: path-separator diff; fold-hook: Windows-only `source_path` SQL; all pre-existing Windows, not merge-caused |
| Admin suite | 28 files / 229 tests pass, 0 fail |
| Slice 3 Inbox targeted | 62 pass / 0 fail / 0 skip |
| Slice 4 Admin runtime contract | 15 pass / 0 fail / 0 skip |
| Slice 5 trace targeted | 8 required cases pass, 0 skip |
| Remaining CP | root/Admin pass, minions suite pass, duplicate operations 0 |
| Formal agent verification | 10/10 CPs pass; 2 manual receipts; 2 declared not applicable |
| `stdd ci check-failures` | 9/9 checks pass; TC execution coverage 14/14 |
| `check:regen-all` | pass |
| `check:skills-manifest` | `skills/skills.lock.json is fresh` |
| `check:admin-embedded` | pass |
| `check:newlines` | pass when run individually |
| `check:module-size` | pass when run individually |
| `bun run verify` | 79 pass / 16 fail; 2 timeout items pass individually; 12 failures fully match documented Windows baseline; `function-size` also reports 2 pre-existing over-limit functions absent from the baseline (ingest-capture 309/307), and `derived-census` has 1 pre-existing undispositioned inbox `softDeletePage` site |
| `bun run test` | not completed on Windows; runner baseline, no full-run signal claimed |
| E2E | merge-touched file's PGLite arm passes 2/2; Postgres arm and live database upgrade not run; `database_upgrade_verified=False` |
| Ledger sync record | 2026-11-24 record staged in candidate `CUSTOM-LEDGER.md`; main worktree remains clean on master/FORK |

## Failure-mode checks

- Scope: Graph work removed after the user narrowed the goal to the upstream merge; harness and evidence-script changes are limited to executing that merge.
- Hallucination/anchoring: final audit and verifier checks use actual git/test outputs; no PASS-label-only evidence is claimed.
- Coverage vacuum: Slice 5 and full unit limitations are explicit, not counted as passes.
- Cross-system consistency: Admin/Slice/CP counts agree with their logs; JUnit file fields are normalized for the remaining jobs check.
- Pipeline break: candidate index/worktree are consistent, with no unmerged entries.

## Known issues

- Full `bun run test` on Windows: one Bun process per file over 1145 files/shard, plus the documented `test/setup.test.ts` launcher failures. Targeted batches are the available signal; a Linux CI/Ubicloud run is still required for a full-unit claim.
- `bun run verify` has 14 remaining failures: 12 fully match documented Windows baseline; `check:function-size` additionally reports 2 pre-existing over-limit functions not in the baseline (`makeIngestCaptureHandler` 309 and its inner 307, unchanged at HEAD), and `check:derived-census` has one pre-existing undispositioned `src/core/ops/inbox.ts` soft-delete site. These need separate disposition before release; they are not merge-introduced.
- Changed doctor/fold-hook fixture consumers fail only on Windows (temp-git manifest, path separators, platform-conditional source-path SQL). The fixtures are upstream-identical and their Linux behavior is covered by upstream CI, not locally.
- Admin standalone `tsc` retains two pre-existing FORK errors; not reported as passed.
- `scripts/structural-suites.tsv` is Windows-backslash formatted at HEAD; the merge’s added/updated rows follow that format. A Linux regeneration would rewrite the whole file. This is pre-existing cross-platform formatting debt, not a merge regression.
- Graph visibility/degree remains a pre-existing FORK gap and is not fixed in this merge.
- No candidate commit, push, master merge, deployment, or production migration has occurred.
