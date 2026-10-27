# S0 build report — test reliability/root fixes only

## Checkpoint / scope

- Scope: ordinary maintenance Issue/PR; S0a/S0b only at current resumed checkpoint. No registry/template/Agent feature implementation, real CR, DB, dependency/global configuration/hook changes, commit, push or branch creation.
- Business root: `C:/Users/GOBAO/Downloads/AI/tools`.
- Owned business files: `skills/shared/crctl/scripts/crctl.mjs`, `skills/shared/crctl/scripts/test/crctl.test.mjs`; minimum existing caller test/whitelist adjustment only if proven legitimate under its existing non-executable-mention policy.
- All progress/evidence records stay in this file. State/tasks/specs/phase-context are not edited. Final full regression is reserved for main after independent review; do not rerun the baseline.
- Read execution-policy/tasks/design (including final diagnosis), canonical `test-execution-reliability.yaml`, test-plan; tools AGENTS/dir-graph/matrix/README and diagnosing-bugs/systematic-debugging/tdd/ponytail/karpathy skills before code changes.

## Completed untouched full baseline

- Before any source/test mutation, discovery found exactly **35 files**: 31 `skills/shared/crctl/scripts/test/*.test.mjs`, 3 `output-guard/test/*.test.mjs`, 1 `pipeline-templates/*.test.mjs`.
- Environment: Windows x64, Node `v24.15.0`, Git `2.54.0.windows.1`. Original business Git status: only pre-existing `M .gitignore`; preserve it.
- Exact argv/file manifest, versions and initial SHA-256 hashes: `C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-build-9LHovb/baseline-command.json`.
- Command (cwd business root): `node --test --test-concurrency=2 --test-reporter=tap <all 35 explicit discovered paths from baseline-command.json>`; no name filter/exclusion. Process budget **2400 seconds**, tool budget 2700 seconds. stdout/stderr written directly to separate files, not piped for status.
- **Natural exit 1**, signal null, process error null. Monotonic elapsed (`process.hrtime.bigint()`): **2116.4877057 seconds**.
- Actual TAP totals: **869 tests, 0 suites, 862 pass, 7 fail, 0 cancelled, 0 skipped, 0 todo**.
- stdout: `C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-build-9LHovb/baseline-stdout.log`.
- stderr: `C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-build-9LHovb/baseline-stderr.log`.
- Result: `C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-build-9LHovb/baseline-result.json`.
- The result's `skips` string-search field contains an existing test title mentioning literal `# SKIP`; these are **not actual skipped tests** (TAP skipped total is zero).
- Baseline process completed; PID was not captured. At resume, main independently confirmed zero matching Node `--test` processes. No second full suite started and no processes killed.

### Actual failed test titles

1. `caller-09 扫描面内每处 CR 数据命令调用都携带非空 --workspace（或在白名单登记为非可执行提及）`
2. `review-record：--bump-attempt 级联 attempt 记账（复用既有 bumpAttempt）`
3. `CR-2026-025 投影①b：tech-design 与 code stage 同构投影（repair-target 分别为 write-tech-design / implement-code）`
4. `TASK-06 ①: payload 伪造 release-subjects -> RELEASE_SUBJECTS_FORGED，annotation 零写入（AC-1）`
5. `CR-2026-044 TASK-03: workspace 非 healthy（dirty/wrong-branch/missing/path-unregistered）零 snapshot 硬失败并返回分类事实`
6. `CR-2026-076 B-07：code 评审提交后恢复必须重核原 release-subjects 与实际对象——受控 artifact 被替换 → TX_RECOVERY_CONFLICT，annotation 与 HEAD 零改写`
7. `AIFI-69 B1/R1：显式 --operational-workspace 仍按传入值；authority 解析失败时零业务写入`

### Baseline classification / implementation pending

- Five payload failures: actual `PAYLOAD_NOT_FOUND`; fixtures place payload in main checkout although review-record resolves the CR authority worktree. Preserve original forged/drift/recovery/zero-write assertions; correct fixture authority or explicit absolute `--from` as appropriate, not production authority.
- R1: actual `INTERNAL_ERROR` wrapping genuine `TxError(CR_WORKTREE_STATUS_MISSING)`. Shared helper must format only genuine TxError **after existing tolerance decisions**, keeping explicit override, first-catch legacy allowances and second-catch unbound fallback (including unknown errors). Unknown exceptions on originally throwing paths must remain INTERNAL_ERROR; no global arbitrary-code passthrough.
- Caller-09: baseline reports `crctl.mjs:5421` help comment plus nine `code-implementation.pipeline.json` workspace mentions (41/50/96/105/114/123/165/174/238). Inspect executable versus non-executable meaning and existing whitelist policy before deciding; no broad waiver or template feature changes.
- Prior session made no source/test/docs edits. This initial checkpoint was written before the resumed mutations below. Final acceptance remains **pending**.

## Resumed targeted TDD checkpoint

All artifacts below are in `C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-build-9LHovb/`; each label has `-command.json` (exact cwd/executable/argv/budget), `-stdout.log`, `-stderr.log`, `-result.json`. Status is the actual child status, elapsed is monotonic; no output pipelines, hook changes, dependencies, or full-suite reruns.

| Run label | Actual result | Elapsed seconds | Purpose |
| --- | --- | ---: | --- |
| `original7-red` | exit 1; 7 tests, 0 pass, 7 fail; 0 skip/todo/cancelled | 5.9273036 | Reproduced all seven exact baseline titles before source/test mutation. |
| `authority-red` | exit 1; 4 tests, 2 pass, 2 fail; 0 skip/todo/cancelled | 4.5936506 | Original R1 + new sibling/legacy/unknown CLI regressions before production fix; sibling and original R1 fail as expected. |
| `authority-green` | exit 0; 4 tests, 4 pass, 0 fail; 0 skip/todo/cancelled | 5.2220674 | Same args after minimal shared mapping; both helper catches covered for genuine errors, legacy and unbound unknown behavior preserved. |
| `original7-regressions-green` | exit 1; 11 tests, 9 pass, 2 fail; 0 skip/todo/cancelled | 9.6160494 | Repair round 1: caller + original7 + new regressions; only bump-attempt and code projection still fail, now RELEASE_WORKSPACE_INVALID/dirty, not payload missing. |
| `original7-regressions-green-r2` | **exit 0; 11 tests, 11 pass, 0 fail; 0 skip/todo/cancelled** | 10.345507 | Repair round 2: all seven original titles + 3 authority regressions + caller-09a pass. |

- One initial **capture-wrapper syntax error** occurred before a test child was spawned (exit 1); corrected the wrapper's regex escaping with built-in `RegExp.escape`. This is not a test result or repair round.
- First authority implementation (**superseded after cleanup review below**): first catch formats genuine TxError only after its original tolerated-graph decision; second catch returns original ws for **all unbound failures**, then formats genuine TxError on bound paths and rethrows unknown errors. The global main catch is unchanged.
- Caller trace completed: direct callers are `readDataRoot` (status/gate/next), `preflightAdvance` (including writeback validation callback), `performAdvance`, approve, task done, attempt, review-loop reset, review-record, review-note, version-set, and test. `cmdAdvance` already maps TxError; several sibling entrypoints did not. `cmdTest` also resolves repositories independently before the shared authority call; that unrelated seam was not changed.
- New authority regression uses existing CLI subprocess wrappers, isolated workspaces, business/HEAD and runtime snapshots. Sibling review-note verifies first-catch REPO_GRAPH_INVALID plus second-catch CR_WORKTREE_STATUS_MISSING including original message/extra. Legacy tests cover bound/unbound no-repositories, unbound invalid graph, unbound resolver failure. Filesystem-boundary injection gives an ordinary Error a plausible code: bound remains INTERNAL_ERROR with zero business/runtime writes, unbound still falls back. Original override/R1 assertions remain intact.
- Five payload fixtures corrected to actual authority; unhealthy-workspace vector intentionally uses existing absolute `--from` because it removes/damages the authority worktree. Original forged, classification, recovery conflict and main HEAD assertions retained, with authority zero-write/HEAD assertions strengthened.
- Repair-round-1 diagnosis: moving the redundant CR reset into two authority worktrees dirtied a fixture whose developing state was already committed by `makeCodeStageWorkspace`. Removed those redundant resets (not assertions); no production trust/classification change. Same targeted command passed in repair round 2. No further repair rounds used.

### Seventh failure: caller-09 classification and narrow fix

- Nine template hits are bare prose references (`execution_context` comes from task injection or the named workspace inspect interface). They contain no CR-ID/arguments and are not executable invocations. The bootstrap at original line 32 actually executes inspect and already includes `--workspace <workspace>`; it is not exempted.
- Original `crctl.mjs:5421` is a JS comment explaining `gate --help`, not a CR data invocation. Existing help behavior handles this before root validation.
- Existing policy explicitly permits audited non-executable prose via `NON_EXEC_CR_DATA_HITS`. Added two **token-start-anchored** entries, not an entire file/command waiver: `crctl gate --help` followed by the original closing backtick/Chinese explanation, and `crctl workspace inspect` followed by the original closing backtick/`为准`.
- The scanner regex/root extraction rules and all original assertions remain unchanged. Optional anchors are checked against each hit's own command segment; stale-entry checking now verifies anchored entries actually match. New caller-09a asserts a real missing-root invocation **on the same line** is not exempted, while a real explicit-root invocation remains checked normally.
- No template/Agent/registry content changed; caller-09 and caller-09a passed in the first combined run. No seventh-failure blocker remains based on targeted evidence so far; final full acceptance is not claimed.

## Adjacent tests and existing quality entrypoints

Same artifact directory and four-file naming convention as above. Every run below completed naturally (signal/error null). Test counts are per run and overlap; they are **not** a replacement aggregate for the final full suite.

| Run label | Actual result | Monotonic seconds |
| --- | --- | ---: |
| `adjacent-authority` | exit 0; **33 tests / 33 pass / 0 fail / 0 skipped / 0 todo / 0 cancelled** | 48.5158837 |
| `caller-complete` | exit 0; **16 tests / 16 pass / 0 fail / 0 skipped / 0 todo / 0 cancelled** | 0.457122 |
| `existing-contract-tests` | exit 0; **83 tests / 83 pass / 0 fail / 0 skipped / 0 todo / 0 cancelled** | 2.8775709 |
| `check-agents-contract` | exit 0 | 0.0475809 |
| `check-skill-matrix` | exit 0 | 0.0617311 |
| `lint-prompts` | exit 0; one existing OUTDATED finding, detailed below | 0.1013114 |
| `pipeline-json` | exit 0; `json ok` | 0.0415926 |

- Adjacent authority coverage includes explicit workspace/override, cross-project fail-closed binding, bound graph corruption/missing worktree zero-write checks, legacy modes, status/next/gate authority, approve key/grant roots, task/review-note/attempt writes, all signed release snapshot/forged/drift vectors, and the original intentional missing-payload negative case.
- Complete caller test file ran without a name filter; caller-09, caller-09a, stale whitelist checks and its existing outside-surface/explicit-root vectors pass.
- Quality test files: check-agents-contract, check-skill-matrix, contract-scan, lint-prompts, skill-scope. No tests/assertions skipped or deleted to pass. No actual intentional or unexpected skipped cases occurred in any run.
- Actual lint warning retained, not repaired out of scope: `skills/sync/handover-cr/SKILL.md:59 [OUTDATED] R5: 引用过时机制/口径：attempts[]`. The `existing-contract-tests` log's additional OUTDATED text is a test title about the rule, not another repository lint finding.

### Exact command evidence / reproduction

All commands ran from the business root with the existing Node/Git and unchanged hooks. `*-command.json` is the authoritative exact executable/argv (including Unicode regex escaping); logs/result files are adjacent. No shell pipe was used to infer a test status.

For `original7-red`, the exact name-pattern was constructed as `P7 = '^(?:' + baselineResult.failedTitles.map(t => RegExp.escape(t)).join('|') + ')$'` using the seven literal titles above, in their recorded order. Actual argv was:

```text
node --test --test-concurrency=2 --test-reporter=tap --test-name-pattern=<P7> skills/shared/crctl/scripts/test/caller-contract.test.mjs skills/shared/crctl/scripts/test/crctl.test.mjs
```

For both combined repair runs the same argv used `P7 + '|^S0 authority：|^caller-09a '` as the pattern (exact expanded argv saved in each command JSON). For both authority-only RED/GREEN runs:

```sh
node --test --test-reporter=tap '--test-name-pattern=^S0 authority：|^AIFI-69 B1/R1：' skills/shared/crctl/scripts/test/crctl.test.mjs
```

Other actual commands:

```sh
node --test --test-reporter=tap '--test-name-pattern=^CR-2026-072:|^CR-2026-075 A|^CR-2026-075 B1/B3:|^CR-2026-075 TASK-08 FR-04|^AIFI-65 R[12]:|^AIFI-67 B3|^AIFI-69|^S0 authority：|^TASK-06 |^CR-2026-044 TASK-03:|^review-record：payload 缺失' skills/shared/crctl/scripts/test/crctl.test.mjs
node --test --test-reporter=tap skills/shared/crctl/scripts/test/caller-contract.test.mjs
node --test --test-concurrency=2 --test-reporter=tap skills/shared/crctl/scripts/test/check-agents-contract.test.mjs skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs skills/shared/crctl/scripts/test/contract-scan.test.mjs skills/shared/crctl/scripts/test/lint-prompts.test.mjs skills/shared/crctl/scripts/test/skill-scope.test.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
```

The targeted original7/authority runs had 300s child budgets. Adjacent/caller/quality runs had 600s child budgets; none timed out. These are execution-supervisor budgets, not changed product/test timeouts.

## Diff review / handoff to main

Business files changed (paths relative to tools):

- `skills/shared/crctl/scripts/crctl.mjs:749` (mapping at 765 and 772): **4 additions / 2 deletions**, two shared catch boundaries only. Explicit override, tolerated branches and main INTERNAL_ERROR boundary unchanged; no production abstraction introduced.
- `skills/shared/crctl/scripts/test/crctl.test.mjs:2588,3146,6057,6436,8261`: five existing fixture corrections, all original assertions retained or strengthened. New sibling/legacy/unknown regressions at `8818,8845,8862`. Total **97 additions / 16 deletions**.
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs:47-48,277,393-431`: two narrowly anchored audited mentions, per-hit matching/stale checking and one negative regression. **27 additions / 5 deletions**. Regex/root validation logic not weakened; original assertions remain.
- Process record: this `S0-build-report.md` only. No state/tasks/specs/phase-context edits.

Self-review completed with `git diff --check` (exit 0) and full scoped diff inspection; independent review belongs to main and is **pending**, not claimed here. Original `.gitignore` SHA-256 remains exactly the baseline value `53be5051929c1edd520fa13d852243c12558322ffb8f8d462f5c104c50940174`; no settings/hooks/env/dependencies changed.

Every owned test/check command returned naturally; isolated fixtures use existing finally cleanup. Final read-only process inspection (`Get-CimInstance Win32_Process`, node.exe + `--test` + the crctl test path) found **0 matching test processes**. No kill/blanket cleanup was used. Evidence logs intentionally remain in the owned OS-temp directory.

**Prior stop point (superseded by review below):** S0a classification and S0b targeted fixes/evidence were handed to main review. Four new tests live in existing files (discovery remains 35 files). Do **not** infer final full-suite totals from targeted runs. No final full run was started: main will independently review and schedule one adequately budgeted owned full35+new-regressions run with persistent capture. S0c/full-baseline milestone and cross-platform verification remain pending. Only Windows/Node24 was tested. No registry/template/Agent or other AIFI-45 product feature implementation has begun; leave this diff uncommitted.

## Independent review follow-up: P2 cleanup fidelity blocker

- Main reported reviewer `01a15381-c89d-75ce-a57c-1b7685dbf81d` found a correctness blocker in the first authority mapping implementation. No final full suite was started.
- Confirmed path: `cmdWritebackApply` supplies `preflightAdvance` as `validateBaselineAdvance`; baseline recovery with an existing writeback journal and null statusTransition calls that callback **inside** `applyWritebackAtomic`'s writeback lock. The first S0 implementation's shared `fail()` called process.exit before transaction finally/lock.release could run. Prior unit/CLI classification tests did not cover this cleanup path; their pass results above are historical, not evidence that this blocker was absent.
- Allowed correction is internal cleanup fidelity under TC-T-TEST-006, not a new business/security/permission contract. Five fixture fixes and anchored caller fixes must remain intact. Maximum three repair rounds for this blocker. RED reproduction, implementation repair round 1, minimal GREEN and adjacent verification are complete; main re-review remains pending.
- Implementation direction after retracing callers: shared authority resolution must mark only genuine, originally escaping authority TxError and **rethrow**, retaining tolerance decisions. Existing `runTxAsync`/cmdAdvance formatting can then run after their underlying work unwinds; otherwise the existing main boundary may format only privately marked genuine authority errors. Unknown/plain-code errors and genuine errors from unrelated paths must keep their previous behavior. No global TxError/code passthrough.

### Cleanup blocker RED and repair round 1

- New existing-file regression: `writeback-tx.test.mjs` uses `makeMergedFixture`, the existing CLI/faultpoint harness and real isolated Git origins/worktrees. First call hits `writeback-after-journal-create` and proves the real persisted journal has `statusTransition: null` and no lock. On retry, a child-local filesystem read shim makes CR worktree status missing **only while the actual writeback lock exists**; initial mode/version/opWs preflight reads stay real. This reaches the actual CLI-supplied preflightAdvance recovery callback, not a mocked callback.
- RED `cleanup-red`: **exit 1**, **2 tests / 1 pass / 1 fail / 0 skipped / 0 todo / 0 cancelled**, monotonic **8.0696435s**. The expected classified code/nonzero assertions passed; precise failure was lock existence (`actual true`, `expected false`) immediately after the failed child, before any retry/fixture deletion can mask it. No source implementation mutation preceded RED. The isolated fixture's finally removes its owned base after the assertion, including the intentionally demonstrated stale lock.
- The second test in that RED is a new CLI trust guard: genuine non-authority `TxError` from upgrade-check's direct repository resolver still becomes INTERNAL_ERROR. It passed before the implementation adjustment.
- Artifacts: same owned temp directory, `cleanup-red-{command.json,stdout.log,stderr.log,result.json}`. Exact command: `node --test --test-concurrency=2 --test-reporter=tap '--test-name-pattern=^S0 authority cleanup：|^S0 authority：未经过 authority' skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/crctl.test.mjs` (300s process budget, natural completion).
- Repair round 1: replaced direct shared fail calls with private WeakSet marking of genuine TxError **after** the unchanged tolerance decisions, followed by rethrow of the original object. Existing runTxAsync and cmdAdvance format after their underlying operations unwind; the outer main catch additionally formats only `e instanceof TxError && authorityErrors.has(e)`. Error code/message/extra and identity are unchanged; unknown/unbound behavior is unchanged. No helper exits while a deep caller owns a lock.
- Minimal GREEN `cleanup-green-r1`: **exit 0**, **2 tests / 2 pass / 0 fail / 0 skipped / 0 todo / 0 cancelled**, monotonic **8.9107981s**, same argv and 300s budget as RED. The recovery callback failure now preserves CR_WORKTREE_STATUS_MISSING, releases the actual writeback lock before the CLI returns, leaves business/spec/candidate/journal/HEAD/index/published count snapshots unchanged, and the subsequent unshimmed same-command recovery succeeds and releases its lock. All original error-code/zero-write/lock assertions retained. Only one implementation repair round used for this blocker.
- Genuine non-authority TxError behavior does **not** change: objects never escaping shared authority are not marked and cannot take the new outer mapping branch. Existing local adapters retain their original genuine-TxError mappings; unhandled unrelated genuine errors still go to INTERNAL_ERROR. Plain errors with arbitrary code are never marked or promoted. No global allow/authorization/signature/isolation change, no new public API/flag/config/dependency or transaction engine. Prior fixture and scanner corrections are untouched.

### Post-review targeted and adjacent results (current implementation)

All rows naturally completed with real status 0, signal/error null; all test rows have **0 fail / 0 skipped / 0 todo / 0 cancelled**. Per-run totals overlap; not a full-suite aggregate. Each label has exact `-command.json`, `-stdout.log`, `-stderr.log`, `-result.json` under the same owned temp directory.

| Run label | Actual test/pass count or check result | Monotonic seconds |
| --- | --- | ---: |
| `cleanup-original7-regressions` | **13 tests / 13 pass**, exit 0: all original seven + all six new S0 regressions | 11.9616301 |
| `cleanup-adjacent-writeback` | **8 tests / 8 pass**, exit 0: existing baseline publication, journal-created recovery, projection repair, CLI validation/idempotence, commit fault, origin/graph drift and new cleanup regression | 69.48338 |
| `cleanup-adjacent-authority` | **34 tests / 34 pass**, exit 0: previous 33-case authority selection + non-authority genuine-error guard | 50.906524 |
| `cleanup-caller-complete` | **16 tests / 16 pass**, exit 0; whole caller file, no name filter | 0.5003518 |
| `cleanup-existing-contract-tests` | **83 tests / 83 pass**, exit 0; same five existing contract test files as above | 2.9811344 |
| `cleanup-check-agents-contract` | exit 0 | 0.0427842 |
| `cleanup-check-skill-matrix` | exit 0 | 0.0521269 |
| `cleanup-lint-prompts` | exit 0; same existing handover-cr line 59 OUTDATED finding, not hidden | 0.0914332 |

Actual combined selection is the previously recorded P7 plus `|^S0 authority：|^caller-09a |^S0 authority cleanup：` across caller-contract/crctl/writeback-tx files, with 300s process budget. Minimal GREEN reused the exact RED argv. Other post-review commands reused exact `adjacent-authority`, `caller-complete`, `existing-contract-tests` and checker argv recorded above (new artifact labels prefixed `cleanup-`, 600s child budgets). The additional writeback adjacency command was:

```sh
node --test --test-reporter=tap '--test-name-pattern=^TASK-02：|^TASK-04：公共 CLI|^TASK-04：writeback-after-commit|^review repair：commit 后|^S0 authority cleanup：' skills/shared/crctl/scripts/test/writeback-tx.test.mjs
```

### Updated diff / stop point after cleanup repair

- `skills/shared/crctl/scripts/crctl.mjs:72,768,775,5500-5503`: private authority-only marker + two mark/rethrow catches + narrowly gated existing main adapter. Current complete S0 diff versus original baseline: **11 additions / 3 deletions**; no per-caller patches.
- `skills/shared/crctl/scripts/test/crctl.test.mjs:8862`: added non-authority genuine TxError guard; earlier five fixtures and three authority regressions remain unchanged. Current complete S0 diff: **109 additions / 16 deletions**.
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs:14,155-199`: reuse existing baseEnv and add actual journal recovery/cleanup regression; **47 additions / 1 deletion**. No lib/workspace-transactions/durable-tx or other production module edited.
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`: no changes in cleanup follow-up; original anchored-mention repair remains **27 additions / 5 deletions**.
- Records: this report only; state/tasks/specs/design/phase-context unchanged. The prior diff-review section is historical; this section describes current production behavior and counts.
- `git diff --check` exit 0. Scoped diff self-reviewed; main independent **re-review pending**. `.gitignore` SHA-256 rechecked and matches baseline exactly (`53be5051929c1edd520fa13d852243c12558322ffb8f8d462f5c104c50940174`). No hooks/settings/env/dependency/branch/commit/push/real CR/DB actions.
- After all owned child commands returned, the same read-only process inspection found **0 matching Node --test processes**. No processes killed; fixture cleanup is in existing finally blocks, evidence files retained in owned OS temp.
- **Stop now for main re-review.** Only one repair round for the cleanup blocker. Six added tests remain in existing files; discovery still 35 files. No final full35 run was started or claimed, and no registry/template/Agent feature implementation began. Final full regression, S0c milestone and cross-platform verification remain pending.
