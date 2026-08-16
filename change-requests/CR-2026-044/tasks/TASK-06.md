---
id: CR-2026-044-TASK-06
type: TASK
cr-ref: CR-2026-044
plan-ref: "change-requests/CR-2026-044/plan.md"
sdd-ref: "change-requests/CR-2026-044/sdd.md"
title: 架构文档同步与全量回归
slug: docs-sync-and-regression
status: pending
estimate: 4h
depends-on: [CR-2026-044-TASK-02, CR-2026-044-TASK-03, CR-2026-044-TASK-04, CR-2026-044-TASK-05]
created: 2026-08-17T00:02:54+08:00
---

# TASK-06 架构文档同步与全量回归

## 1. 任务描述

按 SDD §2.2 的 README 职责（人读总览，不复制算法）跨两个 CR worktree 同步本地/发布边界、交接条件与恢复入口：knowledge-base 修改 ADR-0004，tools 修改 ARCHITECTURE/README；执行全量回归并确认 multica 零改动、零新增依赖、零 schema/状态机变化。对应 PRD FR-10、FR-11、AC-18~AC-23。

## 2. 涉及文件 / 模块

- knowledge-base repo/worktree：`docs/adr/0004-执行层职责边界.md`（本地证据/发布事实边界与 upgrade 启用条款）
- tools repo/worktree：`ARCHITECTURE.md`（§3 crctl 代码地图、§5 不变量相关措辞，不改变不变量本身）
- tools repo/worktree：`README.md`（需求/架构/代码三条流程的 checkpoint 完成条件与恢复入口描述）
- tools repo/worktree：`skills/shared/crctl/scripts/test/`（只运行，不修改）
- multica repo/worktree：零修改，仅在最终 diff 核对中确认 clean

## 3. 实现要点

- knowledge-base ADR-0004：修订 release snapshot 与 merge source 段落为“本地 verifier 决定证据有效性、checkpoint/merge 决定发布完成”；保留既有 publish 后 drift 硬阻断与 journal 版本边界条款；补充 FR-11 启用合同。
- tools ARCHITECTURE.md：只更新与本次行为相关的事实描述（verifier 本地化、merge preflight、inspect authority path），不新增章节、不改 §5 不变量编号与内容。
- tools README.md：三条 Pipeline 的节点表标注审批后 checkpoint 为完成条件；恢复入口统一写“重跑返回的 recoverCommand”；不复制分类算法。
- 每仓文件只在其 `dir-graph.yaml#repositories` 对应 CR worktree 修改；禁止在 tools worktree 猜测 `docs/adr`，禁止在 knowledge-base 主 checkout 修改 Tools 文档。
- 回归命令按 SDD §10.5 全量执行；记录结果到 test-report 前置证据（本 TASK 只收集，test-report 由 write-test-report 生成）。
- 核对 AC-19：`git diff --stat` 确认无 `package.json` 依赖变化、无 gates.json/dir-graph 状态机变化。

## 4. 验收条件

1. knowledge-base diff 只含 `docs/adr/0004-执行层职责边界.md` 与 CR 过程文件；tools diff 含 ARCHITECTURE/README 及 TASK-02~05 实现；multica worktree clean。
2. 三份文档与 TASK-02~05 落地行为一致，无算法复制（grep 不到 fetch/lease/journal 步骤文本）。
3. 全量回归通过：crctl/checkpoint/merge/writeback/archive/upgrade-check/pipeline-structure 七组测试 + 三个契约/lint 脚本。
4. 依赖清单与 schema 零新增断言成立（无 package.json diff、无 gates/status 新增）。

## 5. 完成标志

knowledge-base ADR 提交 + tools 两份文档提交 + multica clean + 全量回归命令全部 exit 0。

## 6. 接口契约

- 消费：TASK-02（TTY 合同）、TASK-03（本地 verifier）、TASK-04（preflight 与 recoverCommand）、TASK-05（Pipeline checkpoint 与 inspect 字段）的最终行为。
- 产出：无代码产出；回归证据清单供 write-test-report 与 review-code 消费。
