---
id: CR-2026-011-TASK-04
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: gates 端点 + canApprove 角色策略 + pending_advance + StartTask 归因
slug: gates-endpoint-approval-policy
status: pending
estimate: 6h
depends-on: [CR-2026-011-TASK-01]
assignee: ""
created: "2026-08-02T12:40:00+08:00"
---

## 任务描述
落地 SDD §4.3/§4.4/§4.5 + DD-2/DD-4/DD-5：前端唯一数据入口 `GET /api/projects/{projectID}/gates`、
审批角色策略补缺、「已批准待推进」服务端派生态（TSUG-001）、StartTask cr_id 归因。

## 涉及文件
- `server/internal/governance/`（新 handler 文件）：`GET /api/projects/{projectID}/gates`——
  `cr JOIN issue ON cr.shell_issue_id=issue.id AND issue.project_id=$1` 取非终态 CR，每条带：
  16 态 status、needs_reconcile、`can_approve`、pending 审批段（DD-2：status ∈
  approvalStages[stage].expect）+ 内联 approval 卡数据（latestEvidence 摘要 + digest + key_id，
  沿 approval.go:169-182 逻辑）、gate node_run 列表（status/attempt/detail）、
  **`pending_advance`**（TSUG-001：join approval_record——同 cr+stage+当前 evidence_digest
  的最新 decision=approve 存在 → 已批准待推进，卡片按此渲染跨端一致态）
- `server/cmd/server/router.go`：挂 approvalSvc 条件组；project 级成员校验**对齐 project
  路由组既有中间件模式**（TSUG-003，不新写鉴权）
- `server/internal/governance/approval.go`：新增 `canApprove(userID, cr, stage)` 单函数
  （workspace owner/admin ∨ cr.owners 对应角色：requirement→requirement，
  tech-design/dev-start/code→development）；`HandleApprove` 强制 → 403
  `{"error":"FORBIDDEN_APPROVER","required_role":…}`；GET gates 的 can_approve 调同函数
- `server/internal/handler/daemon.go`（:2376 StartTask）：请求体增可选 `cr_id`；服务端校验
  cr 行存在且 workspace 一致 → UPDATE agent_task_queue.cr_id；校验不过静默忽略
- daemon 侧（multica-daemon）：start 上报前从任务 workdir `git rev-parse --abbrev-ref HEAD`
  匹配 `requirement/CR-*` 派生 cr_id

## 实现要点
- **TSUG-003 边界**：`shell_issue_id IS NULL` 历史行从 join 自然消失——显式语义，写进查询注释
  与 T07 验收说明；开发前 SELECT 预检存量数据。
- requireHumanActor / EVIDENCE_DRIFT 409 / grant 幂等语义全部不动，既有单测保持绿。
- 单测：canApprove 角色矩阵（owner/admin/对应 owner 角色/无关成员×四 stage）；
  pending_advance 三态（无记录/已批准未推进/已推进后消失）；FORBIDDEN_APPROVER 403；
  StartTask 归因（合法落列/非法静默忽略/非 CR 任务不写）；shell_issue_id NULL 行不出现。
