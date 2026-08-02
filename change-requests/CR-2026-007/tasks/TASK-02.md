---
id: CR-2026-007-TASK-02
type: TASK
cr-ref: CR-2026-007
plan-ref: "change-requests/CR-2026-007/plan.md"
sdd-ref: "change-requests/CR-2026-007/sdd.md"
title: CancelTaskByUser 权限调序（originator 先行放行）+ 幂等/权限单测
slug: cancel-permission-reorder
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-02T13:10:00+08:00"
---

## 任务描述
实现 SDD DD-2 的服务端唯一写路径改动：修复"私有 Team Agent 下发得进撤不回"的权限
不对称（技术评审 blocker 2）。本任务是 **TSUG-004(半)** 的落地点。

## 涉及文件
- `server/internal/handler/chat.go`：`CancelTaskByUser` 非 chat 分支（约 :1122-1149）
- `server/internal/handler/cancel_task_by_user_test.go`：新增用例

## 实现要点
1. 调序：非 chat 分支先判 `uuidToString(task.OriginatorUserID) == userID` → 直接放行到
   `CancelTaskWithResult`（发起人对自己发起的任务天然知情，无泄漏面）；仅当**非发起人**时
   才走原有 `canAccessPrivateAgent` + owner/admin 检查——原逻辑一行不改，只包进 else 分支。
   集合语义必须"只放宽不收紧"：原放行集 {access∧(originator∨owner/admin)} ⊆ 新放行集。
2. **不**改 chat 分支（1:1 chat 隐私语义原样）、不改 `CancelTaskWithResult`。
3. 单测（**TSUG-004 半**）：
   - private agent + 群聊成员撤自己的 queued 任务 → 200 cancelled（改动前 403，回归靶点）；
   - private agent + 非发起人普通成员撤他人 → 403（access gate 仍在）；
   - owner 撤任意 → 200（原行为不回归）；
   - **cancel 已完成任务 → 幂等 200 + 原状态任务体**（技术评审 blocker 1 的服务端
     行为固化断言，防止未来有人"顺手"改成报错，破坏 T03 前端三分支的前提）。
