---
cr: CR-2026-073
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-09-30T19:24:28+08:00"
command-digest: 2a5174de7ff697df682d05f99ca0bb1f2fe2781a2fd8b298a9581f842c99035c
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 long output complete", skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 true failure and legacy classification", skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 overflow preserves canonical", skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 terminal audit root and actor", skills/shared/crctl/scripts/test/terminal-audit.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 terminal audit replay and cleanup", skills/shared/crctl/scripts/test/terminal-audit.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 ordinary CR targeted evidence", skills/shared/crctl/scripts/test/skill-scope.test.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-06.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 scope mismatch blocks review", skills/shared/crctl/scripts/test/skill-scope.test.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-07.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, --test-name-pattern, "CR073 upstream full-suite exception", skills/shared/crctl/scripts/test/skill-scope.test.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-073/test-evidence/cmd-08.log
---

# 测试报告 · CR-2026-073

<!-- crctl:analysis-below -->
## 1. 测试摘要（对应 TASK 验收条件）

| TASK | 验收条件 | 结果 |
|---|---|---|
| TASK-01 有界测试输出 | cmd-01 真实 >1 MiB 单段输出完整落盘 + 真实退出码；cmd-02 真实非零仍 block、timeout/启动失败沿用旧类；cmd-03 ENOBUFS/10485760/null exit 明示且 canonical 四类逐字节不变 | pass（cmd-01/02/03 各 `exit-code: 0`） |
| TASK-02 终态审计根与事前 actor | cmd-04 三入口（KB 主 checkout / CR worktree / txws）审计同留 install-root、actor 可证明、身份不可证明时副作用前技术中止 | pass（cmd-04） |
| TASK-03 终态事件去重与清理重放 | cmd-05 同业务事件重放不重复、不同 stage/事务不误合并、merge 重入被状态机拒绝且无额外成功审计、清理后不重建且旧历史不倒填 | pass（cmd-05） |
| TASK-04 普通 CR 定向验收口径 | cmd-06/07/08 三个 Skill 的文字合同与夹具判据；U/S/P 三案独立 verdict；上游同步全量原始日志与基线对照 | pass（cmd-06/07/08 合同级 + U/S/P 真实 verdict + 上游 rerun；逐项见 §2 后两条与 §5 第 1/2 条） |

实现修订：`tools` 仓 `ab01e2b`（`runTestPlan` 有界 buffer + ENOBUFS 分类；`crctl.mjs` 三终态 adapter 审计根/事前 actor/事件去重键；三个 develop Skill 口径；`gate-registry.json` 登记两个新测试文件 3+3 例）。命令的 `sourceRevision` 由 `crctl test` 从执行时 tools CR worktree HEAD 记录，证据哈希见机器区 `resultFacts`。

## 2. 验证命令与结果解读

- `cmd-01`：单段 stdout 2 MiB+12345 B、stderr 64 KiB+7 B，`exit-code: 0`。`cmd-01.log` 与期望内容**逐字节相等**（两域分区完整、未截断）⇒ 默认约 1 MiB 上限已解除且未丢输出（AC-1）。
- `cmd-02`：`process.exit(3)` → `status=block`、`exit-code: 3`（真实非零仍是业务失败并发布 canonical block 证据）；`timeoutSeconds: 1` 下挂起命令 → `timed-out: true`、`started: true`；不存在的 executable → 技术错误 `TEST_EXECUTABLE_INVALID`（`errCode: ENOENT`）且零 canonical 发布（AC-2）。
- `cmd-03`：11 MiB 单段输出 → 技术错误 `TEST_OUTPUT_EXCEEDED`，`errCode: ENOBUFS`、`maxBufferBytes: 10485760`、`exitCode: null`；捕获片段仅落诊断文件、不回显；canonical 四类文件与溢出前**逐字节相同**（AC-3）。
- `cmd-04`：merge 从 KB 主 checkout 与 CR worktree 两个入口执行，`merge` 审计均只出现在 install-root（CR worktree / txws 内 0 条），`actor` 为非空非 `unknown`；writeback-apply 从 txws 入口执行，`advance`（键 `advance:{cr}:{commit}` 保持原样）与 `writeback` 审计同留 install-root；抹掉本地与全局 git 身份后 merge 在副作用前以 `IDENTITY_UNAVAILABLE` 中止，状态保持 `code-approved`、零审计、零事务目录（AC-4）。
- `cmd-05`：已完成 writeback 阶段重放 → `phase=complete`、`changed=false`，audit.log **逐字节不变**；baseline 与 traceability 两条 `writeback` 审计键互不相同（不同事务不误合并）；merge 重入 → `MERGE_STATE_MISMATCH` 且 merge 审计仍为 1 条；archive 成功 → `archive` 审计 1 条、`actor` 仍可证明（清理后未退化为 `unknown`）、CR worktree/txws 已删除且**未为写审计重建**（无 `.crctl` 目录）、旧审计行逐字节前缀保留；再从 install-root 重放 → 幂等、archive 审计仍 1 条；从已删 txws 入口重放 → `WORKSPACE_NOT_FOUND` 且不复活（AC-5）。
- `cmd-06/07/08`：三个 Skill 文字合同的机械断言 + 可判定夹具判据（定向命令零违规；误设全仓与子集冒充全量均判违规并带 FR/AC 与 `cmd-NN`；上游同步是独立例外，不改绿已知失败）。**这三个绿色只证明合同与判据，不证明任何真实 verdict。**
- **独立 reviewer verdict（非 cmd 证据，TASK-04 / AC-6、AC-7 评审部分）**：三案在隔离夹具（`CR-2026-901/902/903`）内各由一个**新的独立本地 reviewer run**（无 Multica task context，Ray 的 B-C1 裁决选 2）按 `review-dev-plan` 评审；证据逐案在 `test-evidence/scope-review/independent-run/{U,S,P}/`：
  - **U（CR-2026-901）**：`verdict=block`、1 blocker——FR-1/AC-1 的关键证据被设为全仓 `cmd-01`（`repo=tools`、`make test`），且 plan §2/§3/§5 与 `TASK-01` 完成标志把「全仓 `make test` 全绿」设为本 CR 验收基线与 TASK 完成前置（已批准 SDD §4/§8 与 PRD AC-1 只要求最窄定向用例）；`repair-target=write-dev-plan`、`subject-sha256=64cc536dd0ab6dc6…`、`crctl next` → `write-dev-plan`。
  - **S（CR-2026-902）**：`verdict=block`、1 blocker——AC-1/AC-2（FR-1/FR-2）声称「全量测试通过」而关键证据 `cmd-01`/`cmd-02` 各只跑一个定向用例（子集冒充全量）；`repair-target=write-dev-plan`、`subject-sha256=2ab660f153bd5b32…`、`crctl next` → `write-dev-plan`。
  - **P（CR-2026-903）**：`verdict=pass`、`blockers=[]`，`acceptance-verifiability: pass` 明示两条 `cmd-NN` 为最窄定向命令、plan §5 与 TASK 完成标志显式标注子集范围，**不因缺全仓测试被 block、不触发 FR-7 的 blocker**；`subject-sha256=c733264659bb7d65…`、`crctl next` → `crctl approve --stage dev-start`（`humanApproval=true`）。
  - 每案 6 项证据：未截断 `reviewer-run.log`（128838 / 142506 / 50021 bytes）、`canonical/` 四件（`dev-plan.yml`、`review-loop.yml`、`traceability.yml`、`cr.md`）、`crctl-next.txt`、`fixture-head.txt`、`fixture-status.txt`、含逐文件 sha256 的 `MANIFEST.txt`（三个 MANIFEST 均无 `MISSING:` 行；夹具 HEAD U `ff5dea8b…` / S `428b9f68…` / P `54da2095…`）。
  - dev-agent 只读复核（本报告引用前的独立核对）：`canonical/` 四件 sha256 与各自 `MANIFEST.txt` 逐条相等；用**版本化夹具**（`scope-review/fixtures/variants/{U,S,P}` + `fixtures/build-output.json#generatedAt`）按 `crctl` 的 dev-plan composite digest 口径（`plan.md` + `tasks/TASK-*.md`，LF 规范化后 `sha256(JSON.stringify(entries))`）重算 `subject-sha256`，三案与 canonical 记录**逐一相等**（U/S/P 全中）。
  - 未见闭合项（由 reviewer 裁定）：零平台副作用下三案无 Multica issue reviewer 评论，以 `reviewer-run.log` 替代——详见 §5 第 1 条。
- **上游同步真实运行证据（非 cmd 证据，TASK-04 / AC-7 上游场景）**：三提交 × 两条件共 6 份未截断全套件原始日志 + 逐包条数/失败清单 + 基线对照，入口 `test-evidence/upstream-sync/rerun/`（`COMPARISON.md`、`counts.tsv`、`failure-sets/`、`cond-a-tasktmp/`、`cond-b-shorttmp/`）；dev-agent 只读复核：抽查 4 份日志的字节数与 sha256 与 `COMPARISON.md` §1 表格全等，`counts.tsv` 逐树合计与 §1 表格数字全等（cond-a 176/148/178，cond-b 135/115/137）。详见 §5 第 2 条。
- 额外（非替代 cmd 的整体验证，原文见 `test-evidence/extra-checks.log`）：`node skills/shared/crctl/scripts/lint-prompts.mjs` → `0 findings`；`node skills/shared/crctl/scripts/check-skill-matrix.mjs` → `56 个 active skill，8 个 actor…一致`。

## 3. TASK 验收覆盖矩阵

| TASK | 验收证据 | 结果 | 未覆盖/说明 |
|---|---|---|---|
| CR-2026-073-TASK-01 | cmd-01、cmd-02、cmd-03 | pass | 无（三个定向案例均在临时仓夹具真实运行） |
| CR-2026-073-TASK-02 | cmd-04 | pass | 无 |
| CR-2026-073-TASK-03 | cmd-05 | pass | 无 |
| CR-2026-073-TASK-04 | cmd-06、cmd-07、cmd-08（**只证明文字合同**）；`scope-review/independent-run/{U,S,P}` 三案独立 verdict；`upstream-sync/rerun` 全量原始日志与基线对照 | pass | 合同级证据不证明任何 verdict；真实 verdict 与上游运行证据的逐项结论与残余偏离见 §2 后两条、§5 第 1/2 条 |

## 4. 新增/修改测试文件

- 新增 `tools/skills/shared/crctl/scripts/test/terminal-audit.test.mjs`（3 例：三入口审计根与 actor、身份不可证明中止、去重与清理后重放）。
- 新增 `tools/skills/shared/crctl/scripts/test/skill-scope.test.mjs`（3 例：定向证据合同、误设全仓/子集冒充全量判 blocker 口径、上游全量例外）。
- 扩展 `tools/skills/shared/crctl/scripts/test/test-cr.test.mjs`（+3 例：长输出完整、真失败与旧类分类、溢出保 canonical）。
- `tools/skills/shared/crctl/scripts/test/gate-registry.json`：登记两个新测试文件与用例基线（`manifest.files` 与磁盘集合相等，已机械核对）。

## 5. 未覆盖风险（不适用与未闭合项，不得空白通过）

1. **AC-6 / AC-7 的评审部分：三案 verdict 已取得并逐案引用（唯一残余偏离：评论形态，未闭合，须 reviewer 裁定）**。U/S/P 三案各由一个**新的独立本地 reviewer run**（无 Multica task context，Ray 的 B-C1 裁决选 2：按 FR-A7 本地执行、保持隔离与零平台副作用，不在真实 KB root 建 CR 行、不动 `MULTICA_CR_WORKSPACES`）按 `review-dev-plan` 评审，实测与设计判据一致——**U `block`（FR-1/AC-1 + `cmd-01`，`repair-target=write-dev-plan`）、S `block`（AC-1/AC-2 子集冒充全量，`repair-target=write-dev-plan`）、P `pass`（`blockers=[]`，明示不因缺全仓被 block）**；原始 run 日志、canonical 四件、`crctl next` 路由、夹具 HEAD/状态与逐文件 sha256 清单见 `test-evidence/scope-review/independent-run/{U,S,P}/`，逐项事实与 dev-agent 的独立重算见 §2。`cmd-06`/`cmd-07` 的绿色**未**被用来代替这些 verdict。**残余偏离（本项**未**声称已闭合）**：零平台副作用下本地 run 不产出 Multica issue reviewer 评论，以 `reviewer-run.log`（reviewer 原始报告，sha256 见各 `MANIFEST.txt`）替代 plan §5 所列的「对应 issue reviewer 评论」形态；是否接受该替代由本轮 reviewer 裁定，或由人把 verdict 摘要作为人发评论补到 AIFI-38。夹具根在原 install root `C:\Users\GOBAO\Downloads\AI\cr073-scope-fixtures`（三案快照 SHA 与被评版本见 `scope-review/NOT-CLOSED.md` §4）；本 CR 未执行任一夹具 run、未代跑、未改任何夹具 canonical。
2. **AC-7 的上游同步部分：已按 Ray 裁决（B-C2 选 2）补齐**。在三个已记录提交（合并结果 `820bb5a11` / 合并前 `95da7c9d7` / 纯上游 `4736a85d4`）上重跑同条件全量带库 Go 套件（无 `--race`；每组条件三树同一 TMPDIR、每树新建空库与全新 GOCACHE），保留未截断原始日志（命令、cwd、提交 SHA、起止时间、exit code、字节数与 sha256）并与 `CUSTOM.md#已知测试失败基线` 第七次同步行逐包、逐项对照。关键结论：`merged − upstream = 0`（合并结果相对纯上游无额外失败项）；与记录基线同包同名同量级（cond-b：merged 135 / premerge 115 / upstream 137 vs 记录 140 / 114；cond-a：176 / 148 / 178）；差额来源逐条可核（空库 vs 累计状态库、premerge 的 `cmd/multica` 因包超时中止而清单不完整、`execenv` Hermes 组取到本任务 `MULTICA_TASK_CONFIG_ROOT`）。dev-agent 只读复核：`COMPARISON.md` §1 六行日志的字节数与 sha256 与磁盘逐份全等（抽查 4 份），`counts.tsv` 逐树合计与 §1 表格数字全等。**未观察面**：`./pkg/agent/...` 半程未执行（`scripts/test-go.sh` 为 `set -eu`，与记录同构），本项**不**声称上游全绿。入口：`test-evidence/upstream-sync/rerun/README.md`、`COMPARISON.md`、`NOT-CLOSED.md`（文件名保留，内容已更新为已补齐）。
2. **AC-7 的上游同步部分：已按 Ray 裁决（B-C2 选 2）补齐**。在三个已记录提交（合并结果 `820bb5a11` / 合并前 `95da7c9d7` / 纯上游 `4736a85d4`）上重跑同条件全量带库 Go 套件（无 `--race`；每组条件三树同一 TMPDIR、每树新建空库与全新 GOCACHE），保留未截断原始日志（命令、cwd、提交 SHA、起止时间、exit code、字节数与 sha256）并与 `CUSTOM.md#已知测试失败基线` 第七次同步行逐包、逐项对照。关键结论：`merged − upstream = 0`（合并结果相对纯上游无额外失败项）；与记录基线同包同名同量级（cond-b：merged 135 / premerge 115 / upstream 137 vs 记录 140 / 114）；差额来源逐条可核（空库 vs 累计状态库、premerge 的 `cmd/multica` 因包超时中止而清单不完整、`execenv` Hermes 组取到本任务 `MULTICA_TASK_CONFIG_ROOT`）。**未观察面**：`./pkg/agent/...` 半程未执行（`scripts/test-go.sh` 为 `set -eu`，与记录同构）。入口：`test-evidence/upstream-sync/rerun/README.md`、`COMPARISON.md`、`NOT-CLOSED.md`（文件名保留，内容已更新为已补齐）。
3. **不适用项**：本 CR 无 schema/数据迁移、无 feature flag、无常驻服务/浏览器/数据库依赖，故无对应验证；上游 merge/rebase 不在本 CR 范围（plan 明确不执行），故未运行上游全量 `make test`/`go test ./...`——这正是 C 项要收敛的默认全仓门槛，本 CR 的关键证据为定向 `cmd-NN`。
4. **范围边界**：`cmd-04`/`cmd-05` 只跑 `terminal-audit.test.mjs` 的定向案例，不声称 tools 全仓套件通过；`cmd-06`～`cmd-08` 只跑 `skill-scope.test.mjs`，不声称任何运行时行为或评审结论。

## 6. 下一步建议

1. U/S/P 三案的人侧 run 与采集**已完成**，本报告已逐案引用（§2、§3、§5 第 1 条）；请独立 `quality-reviewer-agent` 复评 `review-code`（attempt 2/3），并就是否接受「以 `reviewer-run.log` 替代 issue 评论」这一残余偏离给出裁定（§5 第 1 条末段）。
2. 上游同步原始日志：已按 B-C2 选 2 补齐并复核（§5 第 2 条），无需再动；`review-code` 时请把 §5 第 1 条的**评论形态偏离**与其余已闭合项分开判定。
