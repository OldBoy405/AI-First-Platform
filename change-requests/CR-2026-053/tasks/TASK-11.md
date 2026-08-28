---
id: CR-2026-053-TASK-11
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 存量 CR-2026-051/052 修复（按 FR-B8 来源 Issue 表）
slug: existing-cr-fix
status: pending
estimate: 2h
depends-on: [CR-2026-053-TASK-05, CR-2026-053-TASK-08]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

存量 CR-2026-051 和 CR-2026-052 走同一受控 task + 绑定接口修复（FR-B8），禁用直接 SQL：

| CR | 来源 Issue | Issue UUID | project_id |
|---|---|---|---|
| CR-2026-051 | AIFI-3 | `6a8cd56a-12b3-49d9-80bb-4657da15c3b0` | `e3480ca6-29ba-42cc-87b9-6118921d3cfb` |
| CR-2026-052 | AIFI-6 | `1766573d-f7bd-465b-bbc4-bcb65a84c880` | `e3480ca6-29ba-42cc-87b9-6118921d3cfb` |

修复步骤（AC-D1~D6）：人类按 FR-B8 表确认来源 Issue → 从该 Issue 启动受控 task → 调用 `bind-current-task-to-cr(CR-ID)` → 服务端校验/CAS/审计 → 项目 gates 重新查询验证卡片可见。

## 涉及文件 / 模块

- CR-2026-051 和 CR-2026-052 的受控 task（经绑定接口，不直接改 SQL）

## 实现要点

参考 SDD §6 FR-B8：
- 以 FR-B8 表为唯一可重复的权威查找输入，不接受运行时猜测
- 未确认不得执行绑定；实际来源与表不符时停止并人工核对（AC-D6）

## 验收条件

1. 从 AIFI-3 启动受控 task 执行 `multica cr bind-current-task CR-2026-051` → `changed=true`，`cr.shell_issue_id = 6a8cd56a-12b3-49d9-80bb-4657da15c3b0`（AC-D1）
2. 从 AIFI-6 启动受控 task 执行 `multica cr bind-current-task CR-2026-052` → `cr.shell_issue_id = 1766573d-f7bd-465b-bbc4-bcb65a84c880`（AC-D2）
3. gates 查询锚点：`go test ./server/internal/governance/ -run TestApprovalGateShellIssueIDTwoStates` 通过（`shell_issue_id` 非空时进入项目 gates 投影，AC-D4 可查询）
4. audit 留痕锚点：`go test ./server/internal/service/... -run TestBindCurrentTaskToCR` 通过（断言成功写 `activity_log(action='cr_issue_bound')`、冲突写 `cr_issue_bind_rejected`，AC-D3 未直接 SQL）

## 完成标志

- 两个 CR 均通过 AC-D1~D6 验收清单

## 接口契约

**消费**:
- CLI 命令 `multica cr bind-current-task <CR-ID>`（由 CR-2026-053-TASK-08 实现；该命令消费 CR-2026-053-TASK-05 的 `POST /api/crs/{cr_id}/bind-current-task` 接口）
