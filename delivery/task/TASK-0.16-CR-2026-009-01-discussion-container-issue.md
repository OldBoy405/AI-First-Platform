---
id: CR-2026-009-TASK-01
type: TASK
cr-ref: CR-2026-009
plan-ref: "change-requests/CR-2026-009/plan.md"
sdd-ref: "change-requests/CR-2026-009/sdd.md"
title: discussion 容器迁移 + 谓词清单化 + ensure 抽取与端点
slug: discussion-container-issue
status: done
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-02T11:55:00+08:00"
spec-id: ai-first-platform
version: "0.16"
---

## 任务描述
落地 SDD §3/§4.1/§4.2：新增 `origin_type='project_discussion'` 容器支撑设施，把既有 8 处
排除谓词从单值改为 NULL 安全容器清单，抽取共用 ensure 并新增 Discussion 入口端点。
T02~T04 的唯一硬前置。

## 涉及文件
- `server/migrations/161_issue_origin_project_discussion.up.sql`（+down）：CHECK 扩值
  `'project_discussion'`（照抄 160 DROP+ADD 模式）+ 部分唯一索引
  `issue_project_discussion_unique ON issue(project_id) WHERE origin_type='project_discussion'`；
  down 照抄 160.down「先删容器数据再收约束」，**确认 comment→issue 级联行为并本地演练
  down→up 往返（PSUG-001）**
- `server/internal/handler/issue.go`（:474/:945/:1279）+ `server/pkg/db/queries/issue.sql`
  （:15/:176/:224）+ `server/pkg/db/queries/project.sql`（:45/:54）：谓词统一替换为
  `(i.origin_type IS NULL OR i.origin_type NOT IN ('project_chat','project_discussion'))`，
  `make sqlc`（diff 限定 issue/project 两个 .sql.go）
- `server/internal/service/project_chat.go`：`EnsureProjectChatIssue` 容器创建主体抽为私有
  `ensureContainerIssue(originType, title)`，新增 `EnsureProjectDiscussionIssue`（title 固定
  `Discussion`）；**保留既有 chat ensure 单测并补 discussion 同构用例（PSUG-002）**
- `server/pkg/db/queries/issue.sql`：新增 `GetProjectDiscussionIssue`（照抄 :358-360 改类型值）
- `server/internal/handler/project_chat.go` + `server/cmd/server/router.go`（:1080 旁）：
  `GET /api/projects/{id}/discussion` → `{ issue_id }`（与 GetProjectChat 同构）

## 实现要点
- 谓词替换后 `grep -rn "project_chat'" server` 断言零残留单值谓词（generated 除外，以 queries 源为准）。
- lazy 创建幂等：INSERT ON CONFLICT DO NOTHING 后重查（照抄 CR-A）。
- multica 仓代码注释一律英文（其 CLAUDE.md 硬规则）。

## 验收条件
1. 单测：构造 discussion 容器 Issue 后，8 个查询入口（列表/count/open/分组/搜索含 comment 子查询/统计×2）均不返回它；既有 project_chat 排除行为不变。
2. 单测：并发两次 EnsureProjectDiscussionIssue 最终仅一条容器记录；EnsureProjectChatIssue 既有单测全绿。
3. 本地库 migration down→up 往返成功（容器挂有 comment 的场景）。

## 完成标志
`go test ./...` 相关包全绿 + `make sqlc` 生成 diff 干净 + lint 零报错。
