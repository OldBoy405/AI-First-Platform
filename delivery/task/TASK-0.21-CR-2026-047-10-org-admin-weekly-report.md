---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-047-TASK-10
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: Org Admin 幂等初始化 + 周报 Autopilot + envelope 回传
slug: org-admin-weekly-report
status: pending
estimate: 20h
depends-on: ["CR-2026-047-TASK-02", "CR-2026-047-TASK-05", "CR-2026-047-TASK-08"]
created: 2026-08-20T01:30:30+08:00
---

# TASK-10 Org Admin + 周报 Autopilot

## 任务描述

按 SDD §4.6/§3.7 实现 E3：Org Admin 项目与 Agent 幂等初始化、每周一 09:00 Asia/Shanghai schedule、内置 skill 生成五节周报（第 4 周附 8 项基线建议）、`agent_task_queue.result` envelope 回传 + inbox 通知。server 不读 daemon 文件系统。

## 涉及文件 / 模块

- `server/internal/service/org_admin.go`（新建：幂等初始化）
- `server/internal/service/maturity_report.go`（新建：既有 Autopilot enqueue、envelope 校验、去重查询）
- `server/internal/service/builtin_skills/multica-maturity-weekly-report/SKILL.md`（新建；由 `server/internal/service/builtin_skills.go` 的 `//go:embed builtin_skills` 自动打包）
- `server/internal/handler/org_admin.go` + `server/cmd/server/router.go`：在现有 `/api/agents/mika` 旁注册 `POST /api/agents/org-admin`（Owner/Admin、body=`{runtime_id}`）
- `packages/core/api/client.ts`：新增 `ensureOrgAdminWorkspace(workspaceId,runtimeId)`
- `server/pkg/db/queries/maturity.sql`（追加：Org Admin 项目/Agent 查找、envelope 查询复用 TASK-08 `MaturityReportHistory/Latest`）

## 实现要点

- `func EnsureOrgAdminWorkspace(ctx context.Context, queries *db.Queries, txStarter TxStarter, workspaceID, ownerID, runtimeID pgtype.UUID) (*OrgAdminRef, error)`；内部 `type OrgAdminRef struct{ ProjectID, AgentID, AutopilotID, TriggerID pgtype.UUID }`。事务内 `pg_advisory_xact_lock(hashtextextended('org-admin:'||workspaceID,0))`；`project.settings->>'system_key'='org-admin-workspace'` 查不到才用既有 `CreateProject` INSERT；Agent 先 `GetAgentBySystemKey(workspaceID,'org-admin')`，缺失才按 `CreateMikaAgent` 锁内复查+创建模式创建，project lead 指向该 Agent。重复调用零新增行。首次初始化入口由 Owner 的 Org Admin 设置动作提供 `runtimeID`；无 runtime 时不猜默认值，返回 `runtime_required` 供 UI 引导。
- 首次使用入口：`func (h *Handler) CreateOrgAdminAgent(w http.ResponseWriter,r *http.Request)` 只接受 `runtime_id`，从认证上下文取 workspace/owner；拒绝非 Owner/Admin 与跨 workspace runtime；调用 `EnsureOrgAdminWorkspace`，重复请求返回同一 `OrgAdminRef`。前端只在 latest report empty 且 Org Admin 未初始化时向 Owner/Admin展示 runtime 选择与初始化动作；普通成员只看到 unavailable，不得触发创建。
- schedule 不新增 scheduler job：advisory lock 内先以 `(workspace_id,project_id,title='AI Maturity Weekly Report')` 查询已有 Autopilot、再按 `autopilot_id + kind='schedule'` 查询 trigger；缺失才复用 `db.Queries.CreateAutopilot` + `CreateAutopilotTrigger` 建 active Autopilot，schedule trigger 固定 `cron_expression='0 9 * * 1'`、`timezone='Asia/Shanghai'`。新增两个 workspace-scoped sqlc 查询 `MaturityOrgAdminAutopilot` 与 `MaturityOrgAdminScheduleTrigger`，从而重复调用不会依赖标题以外的客户端输入。运行时由既有 `scheduler.JobNameAutopilotScheduleDispatch='autopilot_schedule_dispatch'`、`ScopeKindAutopilotTrigger='autopilot_trigger'` 与 scope_id=trigger UUID 写 `sys_cron_executions` 幂等；运营只经既有 Autopilot UI 改 cron。enqueue 必须：`agent_task_queue.project_id=OrgAdminProjectID`、绑定项目 `chat_session_id`；未绑 `local_directory` 时不产生任务，显式记录 `unavailable` 原因并产出 inbox 提示。
- skill 输出：`docs/org-admin/maturity-review-{YYYY-Www}.md`（daemon 绑定目录，原子写临时文件+rename）；五节模板=个人效率/团队交付/知识复利/风险收益/成本，每节引用 snapshot/governance 指标（数据经 TASK-08 API 取，含 §3.2 overall 与 §3.6 config）。
- 第 4 周基线建议：直接消费 TASK-05 `MaturityBaselinePercentiles(workspaceID)` 的 PostgreSQL 结果；查询未返回的 metric（非连续28日或ready样本<21）标 unavailable；`P75<=P10` 标 `degenerate_distribution` 且不给可写值；建议只进报告，绝不写 `maturity-config.yaml`，不得在 Go/LLM 重算分位数。
- envelope：`func BuildReportEnvelope(workspaceID pgtype.UUID, week string, markdown []byte, taskID, chatSessionID pgtype.UUID, configRevs []string) (maturity.MaturityReport, error)`；函数内部校验 week 格式、计算 `content_sha256` 与 `relative_path`，并生成 `report_key=workspaceUUID+":"+YYYY-Www`；写入 `agent_task_queue.result` 的 `schema='ai-first.maturity-report/v1'`；server 侧 `VerifyReportSHA(markdown,content_sha256) bool` 校验通过才作为投影持久化（持久化点=任务完成时既有 result 写入路径）。
- API 去重：同 `report_key` 取 `completed_at` 最新且 SHA 有效一条（TASK-08 已实现，本 TASK 只保证写侧唯一语义）。

## 验收条件

1. `EnsureOrgAdminWorkspace` 连调两次：project.settings system key、Agent system_key、Autopilot 与 schedule trigger 各唯一一行（AC-17）；`POST /api/agents/org-admin` 非 Owner/Admin=403、跨 workspace runtime=400、重复请求返回相同四个 ID。
2. 同 ISO week 重试：同一 `report_key` 文件、result envelope、inbox 各一份（AC-18）；文件路径在 daemon 目录、未进入 git（`git status` 干净）。
3. 报告五节均存在且各引用对应指标 key（AC-19）；第 4 周样本 25 个时产出 8 项 P10/P75 建议、样本 10 个时该项 unavailable；建议前后 `maturity-config.yaml` 字节与 HEAD SHA 不变（AC-22）。
4. `chat_session_id` 连续两轮追问仍带报告上下文（AC-21）。

## 完成标志

E3 service+daemon integration 用例全绿；envelope SHA 校验与去重单测全绿。

## 接口契约

- 消费（TASK-08）：`*MaturityService.Overall/Config`、`maturity.MaturityReport`；TASK-05 `db.Queries.MaturityBaselinePercentiles(ctx,workspaceID)`；TASK-02 379 索引语义；既有 `db.Queries.GetAgentBySystemKey/CreateProject/CreateAutopilot/CreateAutopilotTrigger`、`scheduler.JobNameAutopilotScheduleDispatch`、`agent_task_queue` 完成写入路径。
- 产出（供 TASK-09/11）：
  - `func EnsureOrgAdminWorkspace(ctx context.Context, queries *db.Queries, txStarter TxStarter, workspaceID, ownerID, runtimeID pgtype.UUID) (*OrgAdminRef, error)`
  - `func BuildReportEnvelope(workspaceID pgtype.UUID, week string, markdown []byte, taskID, chatSessionID pgtype.UUID, configRevs []string) (maturity.MaturityReport, error)`
  - `func VerifyReportSHA(markdown []byte, contentSHA256 string) bool`
  - `func (h *Handler) CreateOrgAdminAgent(w http.ResponseWriter, r *http.Request)`；request=`{runtime_id:string}`；response DTO=`OrgAdminResponse{project_id:string,agent_id:string,autopilot_id:string,trigger_id:string}`（handler 用现有 UUID string helper 映射内部 pgtype）
  - `type OrgAdminRef struct{ ProjectID, AgentID, AutopilotID, TriggerID pgtype.UUID }`
  - `packages/core/api/client.ts#ensureOrgAdminWorkspace(workspaceId:string,runtimeId:string): Promise<OrgAdminResponse>`
