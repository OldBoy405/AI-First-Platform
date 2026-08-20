---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-048-TASK-06
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: 认领路径遥测接线 + builtin 合成 id 断言锁
slug: claim-telemetry
status: pending
estimate: 6h
depends-on: [CR-2026-048-TASK-05]
created: 2026-08-20T14:32:57+08:00
---

# TASK-06 认领遥测接线

## 任务描述

在 `buildClaimedTaskResponse` 的 `useSkillRefs` 分支写遥测行，并把 builtin 合成 id 规则用测试锁住。SDD §4.1。

## 涉及文件 / 模块

- `server/internal/handler/daemon.go`（改：useSkillRefs 分支内循环 INSERT）
- `server/internal/handler/daemon_test.go` 或同包测试（增）
- `server/internal/service/skill_bundle_test.go`（增一条 builtin ref 断言，与 `TestBuildAgentSkillBundlesAssignsBuiltinID` 同款）

## 实现要点

- 在 `resp.Agent.SkillRefs = skillRefs` 之后循环：`h.Queries.InsertSkillUsageEvent(r.Context(), runtimeWorkspaceID, ref.ID, task.ID, task.ProjectID)`（`runtimeWorkspaceID` 是函数现成形参，零额外查询）。
- 写入错误 `slog.Error` 后继续，绝不触碰 claim 结果（遥测是观测面不是门禁）；不加补偿逻辑（构建后被跳过/取消的任务因到不了 `completed` 被 §4.3 过滤）。
- `TaskCompleteRequest` 与 `sanitizeTaskCompleteRequest` **零改动**（AC-4，diff 为证）。
- skill_bundle 测试断言：`BuildAgentSkillBundles([]AgentSkillData{{Name: "multica-working-on-issues", Content: "body"}})` 返回的 `refs[0].ID == "builtin:multica-working-on-issues"`。

## 验收条件

1. （AC-3）单条 claim（ClaimTaskByRuntime）与批量 claim（ClaimTasksByRuntime）各派发一个用 1 个 workspace Skill + 1 个 builtin 的任务，`skill_usage_event` 各新增 2 行，`workspace_id` = 运行时 workspace，`skill_ref` 分别为 uuid 文本与 `builtin:<name>`。
2. （AC-3）人为使 InsertSkillUsageEvent 失败（fixture 注入），claim 仍成功返回且任务可正常执行。
3. （AC-4）diff 中 `TaskCompleteRequest`/`sanitizeTaskCompleteRequest` 零改动。

## 完成标志

`go test ./internal/handler/ -run 'ClaimTaskWritesSkillUsage|ClaimTasksWriteSkillUsage|ClaimSurvivesSkillUsageInsertFailure' -v` 与 `go test ./internal/service/ -run 'BuildAgentSkillBundles' -v` 均通过（测试名以此为准新建，不用占位表述）。

## 接口契约

- 消费：`db.InsertSkillUsageEvent`（TASK-05）、`skillRefs []AgentSkillRefData`（既有 `TaskService.LoadAgentSkillBundles`）、`runtimeWorkspaceID string`（函数形参）。
- 产出：`skill_usage_event` 行（无新导出 Go 符号）。
