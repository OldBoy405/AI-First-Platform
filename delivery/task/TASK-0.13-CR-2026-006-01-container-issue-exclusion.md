---
id: CR-2026-006-TASK-01
type: TASK
cr-ref: CR-2026-006
plan-ref: "change-requests/CR-2026-006/plan.md"
sdd-ref: "change-requests/CR-2026-006/sdd.md"
title: 容器 Issue 迁移 + 排除谓词 + settings 白名单键
slug: container-issue-exclusion
status: done
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-02T01:15:00+08:00"
spec-id: ai-first-platform
version: "0.13"
---

## 任务描述
在 multica 落地 SDD §3/§4.1/§4.2/§4.4：新增 `origin_type='project_chat'` 的容器 Issue 支撑设施，
以及把它从所有既有 Issue 查询入口排除掉（SDD §6.1 的全量清单）。这是 T02~T05 的唯一硬前置。

## 涉及文件
- `server/migrations/1xx_issue_origin_project_chat.up.sql`（+down）：`issue.origin_type` CHECK 约束扩值
  `'project_chat'`（照抄 149 的 DROP+ADD 模式）+ 部分唯一索引
  `issue_project_chat_unique ON issue(project_id) WHERE origin_type='project_chat'`（防并发重复创建）
- `server/internal/handler/issue.go`：`ListIssues`（:938 where 初始化处，同时覆盖 list+count）、
  `ListGroupedIssues`（:1270）、`buildSearchQuery`（:465-468，**注意该查询含 comment 内容子查询，
  必须排除否则聊天内容会从全局搜索泄漏进 Issue 结果**）三处手写 SQL 加排除谓词
  `i.origin_type IS DISTINCT FROM 'project_chat'`
- `server/pkg/db/queries/issue.sql`：`ListIssues`/`CountIssues`/`ListOpenIssues` 加同一谓词，
  `make sqlc` 重新生成（diff 审查限定 issue 相关 .sql.go，不误动无关生成文件）
- `server/pkg/db/queries/project.sql`（:41-51）：`GetProjectIssueStats`/`CountIssuesByProject` 加谓词
  （容器 Issue 不应计入项目 Issue 总数）
- 新增 `GET /api/projects/{id}/chat` handler：项目成员鉴权 → 查/建容器 Issue（依赖上面的唯一索引
  防并发）→ 返回 `{ issue_id, team_agent_id | null }`（`team_agent_id` 读 `project.settings`）
- `UpdateProject` 白名单扩键 `settings.team_agent_id`：owner/admin 可写（沿 CR-2026-004 的
  `team_agent_queue_limit` 校验模式），校验 agent 存在且对项目所在 workspace 可见

## 实现要点
- 排除谓词统一写法，7 处（5 查询 + 2 统计）逐一核对，不要遗漏 `buildSearchQuery` 的 comment 子查询分支。
- 容器 Issue lazy 创建：`INSERT ... ON CONFLICT DO NOTHING` 后按 `project_id` 重查，取已存在或新建的一条。
- 本任务**不**改动通知/订阅逻辑——已核实容器 Issue 天生无订阅者（订阅仅来自 3 处显式
  `AddIssueSubscriber` 路径），@提及通知路径本就无视订阅直达，符合设计意图，无需处理。
- 单测覆盖：排除谓词生效（构造一条 project_chat Issue，验证 7 个查询入口均不返回它）；
  并发创建容器 Issue 幂等（两个并发请求最终只有一条记录）。
