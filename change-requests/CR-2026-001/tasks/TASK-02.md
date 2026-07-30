---
id: CR-2026-001-TASK-02
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: 查证 multica agent create 的参数面与校验规则（编码前置）
status: pending
estimate: 4h
depends-on: [CR-2026-001-TASK-01]
assignee: ""
created: "2026-07-30T22:43:34+08:00"
---

# TASK-02 查证 multica agent create 的参数面与校验规则

## 任务描述

SDD §3 的硬性约定任务（评审建议落地）：在写适配器代码**之前**，确认 Agent 创建路径的完整契约。这是 TASK-03 的前置依赖，不得跳过或与 TASK-03 合并执行。

## 涉及文件 / 模块（只读，不改）

- `server/internal/service/builtin_skills/multica-creating-agents/SKILL.md`
- 同目录 `references/creating-agents-source-map.md`
- `server/pkg/db/queries/agent.sql`（CreateAgent 查询）
- 必要时对照 `server/pkg/db/generated/models.go` 的 `Agent` struct

## 实现要点

确认并记录：① `multica agent create` CLI 是否支持非交互/脚本化调用及其完整 flag 列表；② name/description/instructions 之外哪些字段必填、有何长度/枚举校验；③ 按 name 查重的现成途径（CLI 或 API）；④ CLI 不满足时 `POST /api/agents` 的请求体与鉴权要求（SDD 备选路径）。

## 验收条件

1. 产出一份查证结论（记入本 TASK 的完成说明或 worktree 内笔记文件）：明确"选 CLI 还是 API"及理由，列出将使用的完整参数
2. 结论中对 SDD §2 表格里"具体落点留到开发计划阶段再定"的 `permission.bash` 记录位置给出定论（用哪个字段/日志承载）

## 完成标志

查证结论落盘且 TASK-03 可直接按结论编码，不需要再回头翻源码。
