---
cr: CR-2026-054
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-29T21:23:49+08:00"
command-digest: dbd75753df8ef79feae96dbd3f8fba318d53c9c4287c72302241467d10d3367c
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/yaml-subset.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-054/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-name-pattern=CR-2026-054", skills/shared/crctl/scripts/test/archive-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-054/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/, -run, "TerminalReport|ReplayTerminal|ReportTerminalTask|ReportTaskResult", "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-054/test-evidence/cmd-03.log
---

# 测试报告 · CR-2026-054

<!-- crctl:analysis-below -->

## 测试摘要（对应 TASK 验收条件）

三个业务域的规范测试入口均已执行并通过：

1. **tools / archive 安全轨**：`yaml-subset.test.mjs` 17/17 通过（TASK-01）；`archive-tx.test.mjs` 的 CR-2026-054 场景 4/4 通过，覆盖首次构建损坏候选、history/index 必需根键缺失、remote rebuild 损坏基线和零 Git 副作用（TASK-02/TASK-03）。
2. **multica / 终态补投轨**：daemon 定向测试全绿，覆盖入队去重、单轮重放、瞬时错误后下一轮继续、永久错误删除、取消、complete/fail fallback、payload 保真和日志脱敏（TASK-05/06/07）。
3. **Agent 执行边界轨**：文档 diff 仅覆盖 SDD 约定的四个文件；tools 提交钩子 `skill matrix`/`agents.contract`/`lint-prompts` 全部零发现（TASK-04）。
4. **真实账本只读验证**：对真实 workspace 的 `_backlog.yml`、`_history.yml`、`_index.yml` 与 `cr.md` frontmatter 执行一次性只读 strict 解析，全部通过（未新增常驻脚本/CLI）。

## 验证命令与结果解读

| 命令 | 范围 | 结果 |
|---|---|---|
| `node --test skills/shared/crctl/scripts/test/yaml-subset.test.mjs`（tools worktree） | strict 模式与默认模式兼容回归 | 17/17 pass（cmd-01.log） |
| `node --test --test-name-pattern=CR-2026-054 archive-tx.test.mjs`（tools worktree） | 首次构建 8 种损坏候选、history/index 缺根键、rebuild 损坏基线；断言错误码/类别与零 stage/commit/push/HEAD 移动 | 4/4 pass（cmd-02.log） |
| `go test ./internal/daemon/ -run 'TerminalReport\|ReplayTerminal\|ReportTerminalTask\|ReportTaskResult' -count=1`（multica worktree/server） | 单轮瞬时失败后的 worker 可继续下一轮、入队/去重、complete/fail、fallback、取消、payload 和脱敏 | 全绿（cmd-03.log） |
| 一次性只读 strict 解析真实三账本 + cr.md frontmatter | 真实权威文件无误拒 | 全部通过（临时脚本已删除） |
| `go build ./internal/daemon/`（multica） | 编译 | 通过 |

## TASK 验收覆盖矩阵

| TASK | AC | 证据 |
|---|---|---|
| TASK-01 yaml strict 可选模式 | AC-1 | cmd-01 + 真实账本 strict 解析 |
| TASK-02 archive 候选校验接入 | AC-2 | cmd-02（含 required root key 校验与 rebuild） |
| TASK-03 archive 校验与 Git 副作用测试 | AC-1/AC-2 | cmd-02：4/4，零 stage/commit/push/HEAD 移动 |
| TASK-04 Agent 执行边界文档 | AC-3/AC-4 | 提交钩子零发现 + diff 仅四文件 |
| TASK-05 daemon 终态补投核心 | AC-5/AC-6 | cmd-03（enqueue/LogValue/值复制） |
| TASK-06 daemon 出口与重放 worker | AC-5/AC-6 | cmd-03（瞬时 round 后继续、单轮 helper、不递归、取消不 drain） |
| TASK-07 终态补投测试与定制登记 | AC-5/AC-6 | cmd-03 + `CUSTOM.md` #58 登记核对 |
| TASK-08 集成验证与 AC 证据映射 | AC-1~AC-7 | 本节矩阵 + test-report 机器区 |

## 新增/修改测试文件

- `tools: skills/shared/crctl/scripts/test/yaml-subset.test.mjs`（新）
- `tools: shared/crctl/scripts/test/archive-tx.test.mjs`（追加 CR-2026-054 缺根键回归）
- `multica: server/internal/daemon/terminal_report_retry_test.go`（新增瞬时 round 后继续断言）

## 未覆盖风险与已知失败（不适用说明）

1. **上游预存失败（tools）**：`archive-tx.test.mjs` 全量套件中的 `TASK-01 RED-7` 失败；既有基线复跑已确认与本 CR 无关，计划内仍只执行 CR-2026-054 场景。
2. **上游预存失败（multica）**：`TestRepoCheckoutReturnsRetryableBusyToCapableClient` 在 trunk 基线同样失败，与终态补投无关，已登记 `CUSTOM.md` 已知失败基线。
3. **不适用**：本 CR 不新增前端、数据库迁移或迁移测试；multica 全量 daemon 测试不进入计划，Windows 环境存在上游已知基线。
4. **重放真实 ticker**：按 SDD §7.3，测试驱动单轮 helper，不等待真实 30 秒 ticker；本轮新增回归验证瞬时轮返回后下一轮仍可执行。
5. **archive 真实归档端到端**：候选校验经 `archiveCr` 全路径测试，合法 `archived`/`rejected`/`withdrawn` 用例在既有 archive-tx 套件中完成手动复核。

## 下一步建议

- 进入第二轮 `review-code`，核对 daemon worker 生命周期和 archive required root key 校验。
- 评审通过后，人工执行 `crctl approve --stage code`；后续状态和门禁以 `crctl next CR-2026-054` 为准。