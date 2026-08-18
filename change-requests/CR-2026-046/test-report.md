---
cr: CR-2026-046
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-18T21:54:54+08:00"
command-digest: 70bff5413e8c6e84b91513175d8466eb242560107218f7d6f2dc726152a90028
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/register-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-046/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/merge-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-046/test-evidence/cmd-02.log
---

# 测试报告 · CR-2026-046

<!-- crctl:analysis-below -->

## 测试摘要

本 CR 两个纵切 TASK 已完成：

- **TASK-01（注册路径）**：`ensureRepoWorkspace` missing 分支改为 fetch --prune + 重新分类 + 远端 trunk 建分支，新增 `WORKSPACE_TRUNK_UNAVAILABLE` 错误码。
- **TASK-02（merge 路径）**：新增 `reconcileLocalTrunks` helper 与 `mergeCr` 的 `localTrunkSync` 输出；`durable-tx.mjs` FAULT_POINTS 表新增 `local-sync-ff-only-failed`（1 行）。

机器区命令 exit-code 均为 0，status=pass。

## 验证命令与结果解读

| 命令 | 结果 | 覆盖 |
|---|---|---|
| `node --test register-tx.test.mjs` | exit 0，17/17 | 既有 12 用例零回归 + 新增 5 用例（AC-1/2/3a/3b/4） |
| `node --test merge-tx.test.mjs` | exit 0，17/17 | 既有 14 用例零回归 + 新增 3 用例（happy path 断言 / 表驱动六场景 / faultPoint 注入） |
| `node --test "test/*.test.mjs"`（全量，机器区外手动执行） | 429/430 | 唯一失败为 checkpoint-tx T05 pipeline 契约用例，主仓未改动基线复现同一失败，确认为既有失败，与本 CR 无关 |

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 |
|---|---|---|
| TASK-01 | stale trunk 基点（AC-1）、远端 CR 分支恢复（AC-2）、fetch 失败/trunk 缺失结构化错误（AC-3a/3b）、healthy/branch-only 不 fetch（AC-4）、既有回归 | register-tx.test.mjs 5 个新用例全绿 + 既有 12 用例零回归 |
| TASK-02 | synced/unchanged（AC-6）、skipped 三态（AC-6）、failed 三态 + SHA/null 规则（AC-6）、faultPoint exit 0/phase=complete/远端成功（AC-7）、既有回归（AC-8） | merge-tx.test.mjs 3 个新用例全绿 + 既有 14 用例零回归 |
| TASK-02 全量回归 | `node --test "test/*.test.mjs"` | 429/430；失败项为主仓既有 checkpoint T05（非回归），详见下 |

## 新增/修改文件

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：`ensureRepoWorkspace` missing 分支改造 + 新增 `reconcileLocalTrunks` + `mergeCr` 接线（+83/-5）。
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`：FAULT_POINTS 登记 `local-sync-ff-only-failed`（+1）。
- `skills/shared/crctl/scripts/test/register-tx.test.mjs`：+95 行（5 用例 + import）。
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`：+110 行（3 用例 + import）。

## 未覆盖风险

1. **既有失败（非回归）**：全量套件中 `checkpoint-tx.test.mjs` 的“T05 contract：Pipeline 只编排 Skill”用例失败（architecture-design.pipeline.json 的 push-progress 节点含 `crctl checkpoint` 字样，与该用例旧正则不匹配）。在未修改的 tools 主 checkout（custom/main）复现同一失败，确认与本 CR 无关；不在本 CR 范围修复，建议另立 CR 处理。
2. **进程在 merge `save('complete')` 后、helper 前退出的补偿路径**：SDD 明确不做恢复（PRD FR-10），用户原生 `git pull --ff-only`，无自动化测试（PRD 范围排除第 4 条）。
3. **helper 的 `before=null` 边缘**（HEAD 不可解析且 symbolic-ref 也失败）：归入 wrong-branch/diverged 兜底，未单独构造破坏性 git 仓库测试；判据 1/6 已覆盖该兜底语义。
4. **不适用项**：无 build 步骤（纯 Node + 原生 git，零构建）；无 lint 步骤（本仓无 lint 配置，由 git hooks 的 skill matrix/lint-prompts 校验承担，提交时已通过）。

## 下一步建议

- 状态 `developing`，测试报告 status=pass；下一步进入 `review-code`（代码评审）与 `approve-code`。
- 若评审要求收紧既有失败处置，可将 checkpoint T05 契约修复作为独立 CR 提出。