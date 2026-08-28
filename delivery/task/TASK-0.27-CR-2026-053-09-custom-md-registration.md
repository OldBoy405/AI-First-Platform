---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-053-TASK-09
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: CUSTOM.md 台账登记
slug: custom-md-registration
status: pending
estimate: 1h
depends-on: [CR-2026-053-TASK-05, CR-2026-053-TASK-06, CR-2026-053-TASK-07, CR-2026-053-TASK-08]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

按 AGENTS.md 工程纪律第 10 条，在 multica 仓 `CUSTOM.md` 对照其当时实际结构登记本 CR 的全部代码变更（FR-B10）：
- 绑定接口路由 + handler + `TaskService.BindCurrentTaskToCR`
- `agent.sql` 绑定读写 query + `CreatePipelineTask` 列继承 + sqlc 生成物
- CLI 薄命令（`server/cmd/multica/cmd_cr.go`）
- 前端 `cr-gate-card.tsx`（提取 ApprovalCard）+ `project-team-agent-chat.tsx`（渲染规则）+ 对应测试
- 编号顺延；原因追溯含 CR-2026-053 + 具体 TASK 编号

## 涉及文件 / 模块

- `CUSTOM.md`（multica 仓根）

## 实现要点

参考 SDD §6 FR-B10：
- 登记所有新增文件与修改文件，对照 CUSTOM.md 现状结构
- 编号顺延无重复
- 原因含 CR-2026-053 + TASK 编号

## 验收条件

1. `grep -n "CR-2026-053" CUSTOM.md` 命中且覆盖上述全部变更文件
2. `grep -oE '^\| [0-9]+ \|' CUSTOM.md | grep -oE '[0-9]+' | sort | uniq -d` 为空（编号无重复）

## 完成标志

- CUSTOM.md 修改已 commit

## 接口契约

无接口产出。
