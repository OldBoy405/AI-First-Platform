---
id: CR-2026-007-TASK-03
type: TASK
cr-ref: CR-2026-007
plan-ref: "change-requests/CR-2026-007/plan.md"
sdd-ref: "change-requests/CR-2026-007/sdd.md"
title: core 层：items schema/query + 撤回 mutation 三分支 + store 过滤字段
slug: core-queue-items
status: done
estimate: 4h
depends-on: [CR-2026-007-TASK-01]
assignee: ""
created: "2026-08-02T13:10:00+08:00"
---

## 任务描述
packages/core 的全部增量。本任务是 **TSUG-006/TSUG-007/TSUG-002(前端半边)** 的落地点。

## 涉及文件
- `packages/core/api/schemas.ts`：QueueItems 响应 schema（originator nullable）+
  `AgentTaskSchema` 增 optional `originator_user_id`
- `packages/core/api/client.ts`：`getProjectQueueStatus` 可选 include 参数（无参调用零变化）
- `packages/core/projects/queries.ts`：`projectQueueItemsOptions`
- `packages/core/projects/mutations.ts`：`useCancelProjectQueueTask`
- `packages/core/projects/project-chat-store.ts`：`agentRequestFilter: Record<projectId, boolean>`

## 实现要点
1. **TSUG-006**：queueItems 的 query key **必须**挂在 queueStatus 前缀下——
   `[...projectKeys.queueStatus(wsId, id), "items"]`——白拿 `use-realtime-sync.ts:541`
   的 `queueStatusAll` 前缀失效，**失效处零改动**（不要去 use-realtime-sync 加第二行）。
2. **TSUG-007** 撤回 mutation 三分支（调 `api.cancelTaskById`，SDD DD-2）：
   - 响应 `status === 'cancelled'` → 成功；**含重复撤回已 cancelled 项（幂等 200）——
     静默成功不弹任何 toast**（双击撤回不误报）；
   - 其它终态（completed/failed）→ toast「任务已结束，无法撤回」；
   - 403 → toast 服务端 message。
   onSettled invalidate queueStatus 前缀（items 同前缀自动覆盖）。
   测试**必须**覆盖三分支（callable-store mock 规范沿 CR-A：`Object.assign(selectorFn, {getState})`）。
3. **TSUG-002（前端半边）**："是我发起的"判定统一走 `task.originator_user_id ===
   currentUserId`（T01 新字段）——**禁止**用 trigger_comment_id→timeline 作者映射
   （coalesce re-stamp MUL-4195 有漂移边界）。
4. store 新字段 persist 缺省 `{}`（旧持久化数据兼容）；默认 false。
