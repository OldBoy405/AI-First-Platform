---
cr: CR-2026-073
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-09-30T14:34:55+08:00"
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
| TASK-04 普通 CR 定向验收口径 | cmd-06/07/08 三个 Skill 的文字合同与夹具判据 | pass（cmd-06/07/08，**仅证明合同**，见 §5 未覆盖风险） |

实现修订：`tools` 仓 `ab01e2b`（`runTestPlan` 有界 buffer + ENOBUFS 分类；`crctl.mjs` 三终态 adapter 审计根/事前 actor/事件去重键；三个 develop Skill 口径；`gate-registry.json` 登记两个新测试文件 3+3 例）。命令的 `sourceRevision` 由 `crctl test` 从执行时 tools CR worktree HEAD 记录，证据哈希见机器区 `resultFacts`。

## 2. 验证命令与结果解读

- `cmd-01`：单段 stdout 2 MiB+12345 B、stderr 64 KiB+7 B，`exit-code: 0`。`cmd-01.log` 与期望内容**逐字节相等**（两域分区完整、未截断）⇒ 默认约 1 MiB 上限已解除且未丢输出（AC-1）。
- `cmd-02`：`process.exit(3)` → `status=block`、`exit-code: 3`（真实非零仍是业务失败并发布 canonical block 证据）；`timeoutSeconds: 1` 下挂起命令 → `timed-out: true`、`started: true`；不存在的 executable → 技术错误 `TEST_EXECUTABLE_INVALID`（`errCode: ENOENT`）且零 canonical 发布（AC-2）。
- `cmd-03`：11 MiB 单段输出 → 技术错误 `TEST_OUTPUT_EXCEEDED`，`errCode: ENOBUFS`、`maxBufferBytes: 10485760`、`exitCode: null`；捕获片段仅落诊断文件、不回显；canonical 四类文件与溢出前**逐字节相同**（AC-3）。
- `cmd-04`：merge 从 KB 主 checkout 与 CR worktree 两个入口执行，`merge` 审计均只出现在 install-root（CR worktree / txws 内 0 条），`actor` 为非空非 `unknown`；writeback-apply 从 txws 入口执行，`advance`（键 `advance:{cr}:{commit}` 保持原样）与 `writeback` 审计同留 install-root；抹掉本地与全局 git 身份后 merge 在副作用前以 `IDENTITY_UNAVAILABLE` 中止，状态保持 `code-approved`、零审计、零事务目录（AC-4）。
- `cmd-05`：已完成 writeback 阶段重放 → `phase=complete`、`changed=false`，audit.log **逐字节不变**；baseline 与 traceability 两条 `writeback` 审计键互不相同（不同事务不误合并）；merge 重入 → `MERGE_STATE_MISMATCH` 且 merge 审计仍为 1 条；archive 成功 → `archive` 审计 1 条、`actor` 仍可证明（清理后未退化为 `unknown`）、CR worktree/txws 已删除且**未为写审计重建**（无 `.crctl` 目录）、旧审计行逐字节前缀保留；再从 install-root 重放 → 幂等、archive 审计仍 1 条；从已删 txws 入口重放 → `WORKSPACE_NOT_FOUND` 且不复活（AC-5）。
- `cmd-06/07/08`：三个 Skill 文字合同的机械断言 + 可判定夹具判据（定向命令零违规；误设全仓与子集冒充全量均判违规并带 FR/AC 与 `cmd-NN`；上游同步是独立例外，不改绿已知失败）。**这三个绿色只证明合同与判据，不证明任何真实 verdict。**
- 额外（非替代 cmd 的整体验证，原文见 `test-evidence/extra-checks.log`）：`node skills/shared/crctl/scripts/lint-prompts.mjs` → `0 findings`；`node skills/shared/crctl/scripts/check-skill-matrix.mjs` → `56 个 active skill，8 个 actor…一致`。

## 3. TASK 验收覆盖矩阵

| TASK | 验收证据 | 结果 | 未覆盖/说明 |
|---|---|---|---|
| CR-2026-073-TASK-01 | cmd-01、cmd-02、cmd-03 | pass | 无（三个定向案例均在临时仓夹具真实运行） |
| CR-2026-073-TASK-02 | cmd-04 | pass | 无 |
| CR-2026-073-TASK-03 | cmd-05 | pass | 无 |
| CR-2026-073-TASK-04 | cmd-06、cmd-07、cmd-08 | pass（合同级） | U/S/P 独立 verdict 与上游同步原始全量/Windows 基线**未取得**，见 §5 |

## 4. 新增/修改测试文件

- 新增 `tools/skills/shared/crctl/scripts/test/terminal-audit.test.mjs`（3 例：三入口审计根与 actor、身份不可证明中止、去重与清理后重放）。
- 新增 `tools/skills/shared/crctl/scripts/test/skill-scope.test.mjs`（3 例：定向证据合同、误设全仓/子集冒充全量判 blocker 口径、上游全量例外）。
- 扩展 `tools/skills/shared/crctl/scripts/test/test-cr.test.mjs`（+3 例：长输出完整、真失败与旧类分类、溢出保 canonical）。
- `tools/skills/shared/crctl/scripts/test/gate-registry.json`：登记两个新测试文件与用例基线（`manifest.files` 与磁盘集合相等，已机械核对）。

## 5. 未覆盖风险（不适用与未闭合项，不得空白通过）

1. **AC-6 / AC-7 的评审部分未闭合**（阻塞原因已定位到平台前置）：plan §5 的 U/S/P 三个快照需要各自的**新独立 `quality-reviewer-agent` run** 按 `review-dev-plan` 给出真实 verdict。本轮已把三案夹具落盘并跑通可评审状态（`CR-2026-901/902/903`，`status=task-breakdown`、`next=review-dev-plan`，夹具根 `C:\Users\GOBAO\Downloads\AI\cr073-scope-fixtures`；构建器与自检原文见 `test-evidence/scope-review/fixtures/`、`test-evidence/scope-review/MECHANISM.md`），但**平台委派的 reviewer run 会在 `review-dev-plan` Step 3.0 的 `multica cr bind-current-task` 处技术中止**：绑定要求平台侧已有该 CR 的投影行（`server/internal/service/task.go#LockCrForCrBind` → `CR_NOT_FOUND`/404 零写入），而隔离夹具 CR 没有平台行（平台行只由已配置 root 的 outbox 状态事件或 root `_backlog.yml` 快照产生）。三条可行路径（A 平台可见测试 CR / B 无 task context 的本地执行 / C 正式修订验收合同）与各自代价逐条见 `test-evidence/scope-review/MECHANISM.md` §3，需人工或平台决定后执行。`cmd-06`/`cmd-07` 的绿色**不能代替**这些 verdict。缺口与判据清单：`test-evidence/scope-review/NOT-CLOSED.md`。
2. **AC-7 的上游同步部分未闭合**：两轮检索（`Downloads/AI` 与 `.multica` 深度 6、>100 KB 日志、PowerShell 命令历史、2026-09-29 之后的 agent 会话记录）均找不到第七次同步的原始全量日志（命令/cwd/commit SHA/时间/exit code）与合并前 `95da7c9d7` 基线日志；`CUSTOM.md#已知测试失败基线`（140 项 vs 合并前 114 项）只是摘要，按 plan §5 不足以宣称该场景通过。三个可复跑的同条件提交在本机均存在（`95da7c9d7` / fork `main` / `upstream/main @ 4736a85d4`），重跑取证需授权。缺口与补取方式：`test-evidence/upstream-sync/NOT-CLOSED.md`。
3. **不适用项**：本 CR 无 schema/数据迁移、无 feature flag、无常驻服务/浏览器/数据库依赖，故无对应验证；上游 merge/rebase 不在本 CR 范围（plan 明确不执行），故未运行上游全量 `make test`/`go test ./...`——这正是 C 项要收敛的默认全仓门槛，本 CR 的关键证据为定向 `cmd-NN`。
4. **范围边界**：`cmd-04`/`cmd-05` 只跑 `terminal-audit.test.mjs` 的定向案例，不声称 tools 全仓套件通过；`cmd-06`～`cmd-08` 只跑 `skill-scope.test.mjs`，不声称任何运行时行为或评审结论。

## 6. 下一步建议

1. 由平台/协调者安排 U/S/P 三个快照的独立 reviewer run 与上游同步原始日志补取；两项补齐后本报告 §5 相应条目可改为闭合引用。
2. 在此之前进入 `review-code` 时，请将 §5 第 1、2 条视为**已知未闭合证据**而非实现缺陷（实现与本地证据均已落盘且可重复执行）。
