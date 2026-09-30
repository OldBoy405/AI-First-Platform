---
id: CR-2026-074-TASK-10
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: ARCHITECTURE.md 地图维护
slug: architecture-map-maintenance
status: pending
estimate: 1h
depends-on: [CR-2026-074-TASK-01]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

tools 仓 `ARCHITECTURE.md` 按 SDD §8 该行与 dep-15 地图维护规则，补无 CR 初始化写入入口与权限/事务边界（技术审批已通过，本 TASK 实施该行；plan R7：明确列入 code review 检查项）。

## 涉及文件 / 模块

- `ARCHITECTURE.md`（tools 仓根；dep-15 §4/§5/§8 现有地图结构）— 补 kb init 无 CR 初始化写入入口、权限/事务边界；非新增业务能力。

## 实现要点

- 内容与代码事实逐字一致（消费 TASK-01 最终实现）：kb 分支在 `requireExplicitWorkspace` 后、`detectWorkspace/loadGates` 前特判派发 `cmdKbInit`；两账本模板独占创建、普通 Git 提交/push；无跨阶段事务隔离承诺（SDD §4.1）；audit 无 CR outbox（SDD §3.1）；错误边界与前置顺序按 SDD §3.2。
- 不改架构不变量（零依赖、状态/门禁经 crctl、目录与权限单一事实源）；不新增业务能力条目。
- 与 TASK-01/TASK-09 产出（入口行为、SKILL/README 描述）口径一致，不出现第三种表述。
- 初始化属于无 CR 的显式引导，不建立第二事务框架（SDD §1）。

## 验收条件

1. `ARCHITECTURE.md` diff 检查：新增条目仅覆盖 kb init 入口与权限/事务边界，与代码事实（KbInitResult、错误码集合、前置顺序）一致，不与其他章节冲突。
2. 文件为 UTF-8/LF，`git -C <tools worktree> status --porcelain` 中本 TASK 相关变更仅 `ARCHITECTURE.md`。

## 完成标志

- `ARCHITECTURE.md` 更新提交，作为 review-code 的 R7 检查项。
- 不夹带生产代码与其他文档变更（SDD §8 该行范围之外零 diff）。

## 接口契约

**消费**：TASK-01 `cmdKbInit`/KbInitResult 的最终实现事实（含 TASK-09 后的 HELP 形态）；dep-15 `ARCHITECTURE.md` §4/§5/§8 现有地图结构与维护规则（新增写入子命令触发地图维护）。

**产出**：`ARCHITECTURE.md` 中 kb init 地图条目（无代码签名变化）。review-code 的 R7 检查项与 TASK-09 的文档口径引用本条目，不得另造口径。
