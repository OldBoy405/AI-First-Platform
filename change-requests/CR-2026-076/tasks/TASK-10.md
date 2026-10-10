---
id: CR-2026-076-TASK-10
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "freshness 三段路由与 workspace inspect 等价结论输出"
slug: workspace-freshness-three-way-routing
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-09]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-10；AC-18／AC-19；SDD §4.9 + §3.1 E7）：把同步后的「最小重验」做成三段路由输出，并在 `workspace inspect` 输出中新增 `freshness` 块（各仓 tree 结论与比较输入），供实施前／评审前两个 gate 消费。

背景与输入条件：TASK-09 已产出唯一比较缝 `compareTree`（`purpose=g06`）。`dep-7` 结论原文——`findPipelineCRRoot`／`inspectPipelineWorkspace` 的 CR 根唯一性与 workspace 健康预检已实现。既有 freshness 判定 `classifyWorkspaceFreshness`（`workspace-transactions.mjs:1014`）与测试 `test/workspace-freshness.test.mjs` 已在位。

明确不做：不新增 CR 状态、不建完整执行器、不加后台重试；等价比较**不替代**有效报告、日志、真实退出码与 verdict；不把未执行验证宣称已测；不改 `workspace inspect` 既有字段类型。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：`export function classifyWorkspaceFreshness(ctx, cr)`（:1014，消费 TASK-09 的 `compareTree`）
- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdWorkspace(ws, positional, flags)`（:3731，新增 `freshness` 块）
- `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs`
- 合同文本：`skills/sync/workspace-freshness/SKILL.md`、`skills/sync/push-progress/SKILL.md`

## 实现要点

1. 路由严格按 SDD §4.9（两个 gate 分开）：
   ```text
   实施前 gate=implement-start：
     fresh / behind-clean → 继续（必要同步后继续尚未开始的实施）
   评审前 gate=review-start：
     tree 与有效测试源相同 → 接续现有评审，不因同步重复实现/测试
     tree 改变 → 先走既有 write-test-report 与 review-code 节点
     仅真实测试/评审失败 → 回 implement-code
   dirty / 分叉 / 冲突 / 同步失败 / 环境不匹配 → 既有失败合同（技术中止不计业务失败）
   ```
2. `workspace inspect` 新增 `freshness` 块（E7）：逐仓 tree 结论与比较输入（比较输入须可追溯到 `compareTree` 的 `refA`／`refB`／`equal`／`reason`），既有字段类型与值不变。
3. `behind-clean` 的同步前移只在显式同步动作下发生（既有 `pull-progress` 能力），本 TASK 不新增自动合并、不自动重试。
4. 等价判定必须带 SHA 追溯（AC-17 已由 TASK-09 断言），本 TASK 只消费结论，不重复判定。
5. Skill 文本同步范围：`workspace-freshness` 增补消费 tree 等价结论与三段路由；`push-progress` 增补与发布 source 固定／实际生效核对的引用（§4.10、§4.13 引用口径）。

## 验收条件

1. **AC-19（cmd-08）**：`workspace-freshness.test.mjs` 单文件断言 fresh／behind-clean／diverged／unknown 四态与三段路由（接续／最小复评／技术失败）——同步后 tree 相同则接续既有评审；不同则产生新测试／复评步骤；实施前同步则继续尚未开始的实施；dirty／分叉／冲突／环境不匹配 → 既有技术失败输出。
2. **AC-18（cmd-08 + cmd-07）**：tree 不同时流程回到 `write-test-report`／`review-code`，仅真实失败回 `implement-code`；比较覆盖整棵 tree，不受扩展名过滤影响（无白名单设计）。
3. **输出面**：`workspace inspect` 的 `freshness` 块字段可用且既有字段（`operationalWorkspace`／`operationalWorkspaceError`／`resources[].{repo,branch,worktreePath,classification,dirty}`／`changed`）取值与类型不变。
4. 运行范围以 plan §6.2 为唯一事实源：`cmd-08` = `workspace-freshness.test.mjs` 单文件；**不声称**覆盖 `workspace inspect` 的其他输出面。真实执行输出落 `test-evidence/cmd-08.log`，不新增 plan 未列命令。

## 完成标志

- 四态与三段路由（含两个 gate 的分支）有用例覆盖，`cmd-08` 真实执行退出码 0 并留证；
- `workspace inspect` 的 `freshness` 块落地，`skills/sync/workspace-freshness/SKILL.md` 与 `skills/sync/push-progress/SKILL.md` 文本同步落盘；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-09 产出，不得缩写）：
- `compareTree(ws, cr, { purpose })` → `{ perRepo: [{repo, refA, refB, equal, reason}], allEqual }`（`purpose=g06` 为测试报告源 vs 同步后源；`purpose=g05` 由 TASK-09 的 `cmdMerge` 消费，本 TASK 不重复判定）；
- `export function classifyWorkspaceFreshness(ctx, cr)`（`workspace-transactions.mjs:1014`）既有四态输出（fresh／behind-clean／diverged／unknown）；
- `resources[].classification` 与 `resources[].worktreePath`（TASK-03 口径，逐仓 path authority）。

产出（供 TASK-17 与 pipeline 的 `workspace-freshness` 节点消费，消费方不得缩写）：
- `workspace inspect` 输出新增 `freshness` 块：各仓 tree 结论与其比较输入（`{repo, refA, refB, equal, reason}` 逐仓），既有 `mode`／`resources`／`changed` 字段不变；
- 路由标识符（与 Pipeline 节点逐字一致）：`implement-start`（fresh／behind-clean → continue／synced-continue）、`review-start`（tree 相同 → 接续既有评审；tree 改变 → `write-test-report` → `review-code`；仅真实失败 → `implement-code`）；
- 技术失败出口沿用既有 code（dirty／diverged／unknown／环境不匹配），不新增同义错误码。
