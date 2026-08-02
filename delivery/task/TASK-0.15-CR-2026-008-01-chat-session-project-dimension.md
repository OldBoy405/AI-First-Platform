---
id: CR-2026-008-TASK-01
type: TASK
cr-ref: CR-2026-008
plan-ref: "change-requests/CR-2026-008/plan.md"
sdd-ref: "change-requests/CR-2026-008/sdd.md"
title: B2 迁移 + get-or-create 端点（chat_session 项目维度）
slug: chat-session-project-dimension
status: done
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-02T11:25:00+08:00"
spec-id: ai-first-platform
version: "0.15"
---

# TASK-01 — B2 迁移 + get-or-create 端点

## 任务描述

给 `chat_session` 加项目维度（SDD §3 M1），提供 Private Ask 的会话 get-or-create 能力
（SDD §4.2，取法=DEC-1：最新 active，无则建），并给既有全局 chat 查询加排除谓词（DD-5）。

## 涉及文件 / 模块（multica 仓）

- `server/migrations/161_chat_session_project.up.sql` / `.down.sql`（新建）
- `server/pkg/db/queries/chat.sql`（`GetProjectChatSessionForCreator` 新增、`CreateChatSession`
  扩 project_id、`ListChatSessionsByCreator`/`ListAllChatSessionsByCreator` 加 `project_id IS NULL`）
- pending 聚合查询（按 `chat_pending_tasks_test.go` 定位 query 名，加同款谓词）
- `server/internal/handler/project_chat.go`（`GetProjectPrivateChat` 新增，挂
  `GET /api/projects/{id}/private-chat`，router.go 项目路由组）

## 实现要点

- M1 三条 DDL 照 SDD §3 原文；nullable + 部分索引保证存量零改写。
- get-or-create：成员鉴权（沿 GetProjectChat 先例）→ 查最新 active → 无则建
  （agent=settings.team_agent_id，未配置 409 `team_agent_not_configured`；work_dir 不设；
  title 固定 `Private Ask`）→ 唯一索引冲突（并发双开）重查返回。
- 响应带 agent/runtime 信息对齐既有会话接口形状（前端 availability 复用）。
- 实施时 `grep -n "FROM chat_session" server/pkg/db/queries/*.sql` 全量核对排除谓词覆盖面
  （GC 检查与按 id 取会话**不加**谓词，SDD §4.1）。
- multica 仓代码注释一律英文（其 CLAUDE.md 硬规则）。

## 验收条件

1. 含存量 chat_session 数据的库上 M1 up→down→up 三遍无损（存量行 project_id 均为 NULL）。
2. 集成测试:同 (project, user) 并发两次 get-or-create 返回同一 session（唯一索引兜底）;
   archived 后再进返回新 session；无 team_agent 配置返回 409。
3. 单测：全局列表两条查询不含 project 会话；pending 聚合不含 project 会话的任务。
4. `make sqlc` 后 diff 限于 chat 相关 .sql.go。

## 完成标志

后端单测/集成测试通过 + lint 零报错 + migration 双向可执行。
