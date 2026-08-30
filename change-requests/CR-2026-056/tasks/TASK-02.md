---
id: CR-2026-056-TASK-02
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M1 迁移 472–480（新表 / 索引 / 废唯一索引）
slug: m1-migrations-472-480
status: pending
estimate: 8h
depends-on: [CR-2026-056-TASK-01]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

按 SDD §2.1/§2.6 落 9 组迁移文件（472–480），建立 `project_chat_session` 表、扩展 `chat_session` 四列、废除 `issue_project_chat_unique` 并建立容器新唯一索引。对应 plan.md M1 前半。

输入条件：TASK-01 已确认最大迁移号 471、multica 基线 `8746add...`。

## 涉及文件 / 模块

- `server/migrations/472_project_chat_session.up.sql` / `.down.sql`
- `server/migrations/473_project_chat_session_id_uidx.{up,down}.sql`
- `server/migrations/474_project_chat_session_pkey.{up,down}.sql`
- `server/migrations/475_project_chat_session_project_active_unique.{up,down}.sql`
- `server/migrations/476_project_chat_session_issue_uidx.{up,down}.sql`
- `server/migrations/477_project_chat_session_project_index.{up,down}.sql`
- `server/migrations/478_chat_session_chat_config_columns.{up,down}.sql`
- `server/migrations/479_drop_issue_project_chat_unique.{up,down}.sql`
- `server/migrations/480_issue_project_chat_session_origin_uidx.{up,down}.sql`

（文件名后缀风格以仓内既有迁移惯例为准；编号与语句内容以 SDD §2.6 表为准。）

## 实现要点

1. 一文件一条语句；全部无 `REFERENCES` / 级联（FR-20 / ARCHITECTURE.md Migration safety）；索引一律 `CONCURRENTLY`。
2. 472：`CREATE TABLE project_chat_session`，列与类型按 SDD §2.1：`id UUID`、`workspace_id UUID NOT NULL`、`project_id UUID NOT NULL`、`agent_id UUID NOT NULL`、`issue_id UUID NULL`、`base_model TEXT NULL`、`base_thinking_level TEXT NULL`、`model_override TEXT NULL`、`thinking_level_override TEXT NULL`、`status TEXT NOT NULL`（CHECK `status IN ('active','closed')`）、`created_by UUID NOT NULL`、`created_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`；不含 PK/UNIQUE/FK。
3. 473/474：`CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_id_uidx ON project_chat_session (id)`；`ALTER TABLE project_chat_session ADD CONSTRAINT project_chat_session_pkey PRIMARY KEY USING INDEX project_chat_session_id_uidx`。
4. 475：`CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_project_active_unique ON project_chat_session (workspace_id, project_id) WHERE status = 'active'`。
5. 476：`CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_issue_uidx ON project_chat_session (issue_id) WHERE issue_id IS NOT NULL`。
6. 477：`CREATE INDEX CONCURRENTLY` 于 `(workspace_id, project_id)`（含 closed 历史行）。
7. 478：`ALTER TABLE chat_session ADD COLUMN base_model TEXT, ADD COLUMN base_thinking_level TEXT, ADD COLUMN model_override TEXT, ADD COLUMN thinking_level_override TEXT;`（单语句四列；历史行保持 NULL，兼容规则见 FR-11）。
8. 479：`DROP INDEX CONCURRENTLY IF EXISTS issue_project_chat_unique;`（AC-22）。
9. 480：`CREATE UNIQUE INDEX CONCURRENTLY issue_project_chat_session_origin_uidx ON issue (workspace_id, origin_id) WHERE origin_type = 'project_chat' AND origin_id IS NOT NULL;`
10. down 文件按仓惯例与 up 配对（逆操作）；回滚顺序 480→472 逆序（plan §6 回滚原则）。

## 验收条件

1. 9 组文件逐个人工核对：一文件一句、无 `REFERENCES`、索引带 `CONCURRENTLY`、down 配对（AC-22）。
2. 迁移在本地数据库 up 全量应用成功；随后按 480→472 逆序执行 down 全部成功。
3. up 后断言：`issue_project_chat_unique` 不存在；同 `(workspace_id, origin_id)` 且 `origin_type='project_chat'` 第二行插入被 480 拒绝；同项目两个 `active` session 被 475 拒绝；同 `issue_id` 挂两个 session 被 476 拒绝。
4. `go build ./server/...` 绿（迁移不引用不存在符号）。

## 完成标志

迁移文件提交至 multica CR worktree，上述 4 条验收记录留档。

## 接口契约

- 消费：TASK-01 事实（迁移编号起点 472、基线）。
- 产出：表 `project_chat_session`（列清单见实现要点 2）、`chat_session` 四列（`base_model` / `base_thinking_level` / `model_override` / `thinking_level_override`，均 `TEXT NULL`）、索引 `issue_project_chat_session_origin_uidx`——供 TASK-03 的 sqlc 查询引用。
