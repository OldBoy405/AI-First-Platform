---
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
- `server/internal/service/maturity_report.go`（新建：schedule enqueue、envelope 校验、去重查询）
- 内置 skill `multica-maturity-weekly-report`（multica 内置 skill 打包路径，实施时按 repo 现状接线）
- `server/pkg/db/queries/maturity.sql`（追加：Org Admin 项目/Agent 查找、envelope 查询复用 TASK-08 `MaturityReportHistory/Latest`）

## 实现要点

- `func EnsureOrgAdminWorkspace(ctx context.Context, db DBTX, wsID string) (*OrgAdminRef, error)`；`type OrgAdminRef struct{ ProjectID, AgentID string }`。事务内 `pg_try_advisory_xact_lock`（按 workspace）；`project.settings->>'system_key'='org-admin-workspace'` 查不到才 INSERT（settings 里写 system_key）；Agent `system_key='org-admin'` 复用 `CreateMikaAgent` 的 `(workspace,owner,runtime,system_key)` 幂等语义，project lead 指向该 Agent。重复调用零新增行。
- schedule：沿用既有 Autopilot schedule trigger 机制（运营可在既有 UI 改 cron）；`job_name='maturity_weekly_report'` 之类复用 `sys_cron_executions(job_name,scope_kind,scope_id,plan_time)` 幂等（精确命名实施时对齐 repo 习惯）。enqueue 必须：`agent_task_queue.project_id=OrgAdminProjectID`、绑定项目 `chat_session_id`；未绑 `local_directory` 时不产生任务，显式记录 `unavailable` 原因并产出 inbox 提示。
- skill 输出：`docs/org-admin/maturity-review-{YYYY-Www}.md`（daemon 绑定目录，原子写临时文件+rename）；五节模板=个人效率/团队交付/知识复利/风险收益/成本，每节引用 snapshot/governance 指标（数据经 TASK-08 API 取，含 §3.2 overall 与 §3.6 config）。
- 第 4 周基线建议：取 TASK-05 `MaturityOrgScoreSamples` 最早连续 28 个 org ready raw，样本<21 → 该指标建议 unavailable；≥21 用 `percentile_cont(0.10/0.75)`（线性插值）→ floor/target 建议；`P75<=P10` 标 `degenerate_distribution` 且不给可写值；建议只进报告，绝不写 `maturity-config.yaml`。
- envelope：`func BuildReportEnvelope(week string, markdown []byte, sha string, taskID, chatSessionID string, configRevs []string) maturity.MaturityReport`；`report_key=wsID+":"+YYYY-Www`；写入 `agent_task_queue.result` 的 `schema='ai-first.maturity-report/v1'`；server 侧 `VerifyReportSHA(markdown, content_sha256) bool` 校验通过才作为投影持久化（持久化点=任务完成时既有 result 写入路径）。
- API 去重：同 `report_key` 取 `completed_at` 最新且 SHA 有效一条（TASK-08 已实现，本 TASK 只保证写侧唯一语义）。

## 验收条件

1. `EnsureOrgAdminWorkspace` 连调两次：project.settings system key 与 Agent system_key 各唯一一行（AC-17）。
2. 同 ISO week 重试：同一 `report_key` 文件、result envelope、inbox 各一份（AC-18）；文件路径在 daemon 目录、未进入 git（`git status` 干净）。
3. 报告五节均存在且各引用对应指标 key（AC-19）；第 4 周样本 25 个时产出 8 项 P10/P75 建议、样本 10 个时该项 unavailable；建议前后 `maturity-config.yaml` 字节与 HEAD SHA 不变（AC-22）。
4. `chat_session_id` 连续两轮追问仍带报告上下文（AC-21）。

## 完成标志

E3 service+daemon integration 用例全绿；envelope SHA 校验与去重单测全绿。

## 接口契约

- 消费（TASK-08）：`*MaturityService.Overall/Config`、`maturity.MaturityReport`；TASK-05 `MaturityOrgScoreSamples`；TASK-02 379 索引语义；既有 `CreateMikaAgent`、Autopilot schedule、`agent_task_queue` 完成写入路径。
- 产出（供 TASK-11 集成验证）：
  - `func EnsureOrgAdminWorkspace(ctx context.Context, db DBTX, wsID string) (*OrgAdminRef, error)`
  - `func BuildReportEnvelope(week string, markdown []byte, sha string, taskID string, chatSessionID string, configRevs []string) maturity.MaturityReport`
  - `func VerifyReportSHA(markdown []byte, contentSHA256 string) bool`
  - `type OrgAdminRef struct{ ProjectID, AgentID string }`
