---
cr: CR-2026-054
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-29T19:50:41+08:00"
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

1. **tools / archive 安全轨**：`yaml-subset.test.mjs` 17/17 通过（TASK-01 验收）；`archive-tx.test.mjs` 中新增的两条候选校验测试（首次构建 8 种损坏场景 + remote rebuild 损坏基线）通过（TASK-02/TASK-03 验收）。
2. **multica / 终态补投轨**：`terminal_report_retry_test.go` 新增 12 项 + 既有 `TestReportTaskResult_*`/`TestTerminalReports*` 回归全部通过（TASK-05/06/07 验收）。
3. **Agent 执行边界轨**：文档 diff 仅覆盖 SDD 约定的四个文件；tools 提交钩子 `skill matrix`/`agents.contract`/`lint-prompts` 全部零发现（TASK-04 验收）。
4. **真实账本只读验证**：对真实 workspace 的 `_backlog.yml`、`_history.yml`、`_index.yml` 与 `cr.md` frontmatter 执行一次性只读 strict 解析，全部通过（未新增常驻脚本/CLI）。

## 验证命令与结果解读

| 命令 | 范围 | 结果 |
|---|---|---|
| `node --test skills/shared/crctl/scripts/test/yaml-subset.test.mjs`（tools worktree） | strict 模式 17 用例 + 默认模式兼容回归 | 17/17 pass（cmd-01.log） |
| `node --test --test-name-pattern=CR-2026-054 archive-tx.test.mjs`（tools worktree） | 首次构建 8 种损坏候选（duplicate-key/unconsumed-line/invalid-shape/invalid-indentation/archive-invariant）+ rebuild 损坏基线；断言错误码/类别/行号与零 stage/commit/push/HEAD 移动 | 2/2 pass（cmd-02.log） |
| `go test ./internal/daemon/ -run 'TerminalReport\|ReplayTerminal\|ReportTerminalTask\|ReportTaskResult' -count=1`（multica worktree/server） | 入队去重/冲突 first-wins/值复制、单轮重放三结果、root 取消不 drain、瞬时入队/永久不入队、complete 瞬时不 fallback、永久 fallback 一次且 payload 保真、fallback 瞬时入队 fail/永久丢弃、LogValue 仅三字段且日志不含原始 cause/payload | 全绿（cmd-03.log） |
| 一次性只读 strict 解析真实三账本 + cr.md frontmatter | 真实权威文件无误拒 | 全部通过（执行输出已保留在会话记录，临时脚本已删除） |
| `go build ./internal/daemon/`（multica） | 编译 | 通过 |

## TASK 验收覆盖矩阵

| TASK | AC | 证据 |
|---|---|---|
| TASK-01 yaml strict 可选模式 | AC-1 | cmd-01 + 真实账本 strict 解析 |
| TASK-02 archive 候选校验接入 | AC-2 | cmd-02（含 rebuild 路径） |
| TASK-03 archive 校验与 Git 副作用测试 | AC-1/AC-2 | cmd-02：零 stage/commit/push/HEAD 断言 |
| TASK-04 Agent 执行边界文档 | AC-3/AC-4 | 提交钩子零发现 + diff 仅四文件 |
| TASK-05 daemon 终态补投核心 | AC-5/AC-6 | cmd-03（enqueue/LogValue/值复制） |
| TASK-06 daemon 出口与重放 worker | AC-5/AC-6 | cmd-03（单轮 helper、不递归、取消不 drain） |
| TASK-07 终态补投测试与定制登记 | AC-5/AC-6 | cmd-03 + `CUSTOM.md` #58 登记核对 |
| TASK-08 集成验证与 AC 证据映射 | AC-1~AC-7 | 本节矩阵 + test-report 机器区 |

## 新增/修改测试文件

- `tools: skills/shared/crctl/scripts/test/yaml-subset.test.mjs`（新）
- `tools: skills/shared/crctl/scripts/test/archive-tx.test.mjs`（追加两条 CR-2026-054 测试）
- `multica: server/internal/daemon/terminal_report_retry_test.go`（新）

## 未覆盖风险与已知失败（不适用说明）

1. **上游预存失败（tools）**：`archive-tx.test.mjs` 全量 19 项中 `TASK-01 RED-7` 失败；已在未改动 HEAD（stash 摘除本 CR 改动）上复跑，失败一致，确认为上游预存，与本 CR 无关。故计划内只跑本 CR 新增的两条候选校验测试（`--test-name-pattern=CR-2026-054`）。
2. **上游预存失败（multica）**：`TestRepoCheckoutReturnsRetryableBusyToCapableClient` 在未改动 main 检出（trunk 基线）上同样失败（`expected 503, got 400`），与终态补投无关；已登记 `CUSTOM.md` 已知失败基线（2026-08-29）。
3. **不适用**：本 CR 不新增前端、数据库迁移或迁移测试；multica 全量 daemon 测试不进入计划（Windows 环境存在上游已知基线，超出本 CR 证据面，见 `CUSTOM.md` 已知失败基线清单）。
4. **重放真实 ticker**：按 SDD §7.3，测试只驱动单轮 helper，不等待真实 30 秒 ticker；周期常量与取消语义由单轮测试覆盖。
5. **archive 真实归档端到端**：校验器经 `archiveCr` 全路径测试（合法 archived/rejected/withdrawn 用例在既有 archive-tx 套件中全部通过，属 cmd-02 外的手动复核，未进机器区）。

## 下一步建议

- 进入 `review-code`（独立 reviewer）与人工 code 审批前，先提交 test-report/traceability/review-loop 账本。
- 代码评审重点核对：FR-18 的 multica 最小 diff（daemon.go 仅两处 AIFIRST 挂钩）、日志脱敏断言、`CUSTOM.md` #58 与实际 diff 一致。