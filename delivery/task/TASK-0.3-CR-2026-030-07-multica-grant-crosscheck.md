---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-07
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 扩展 Multica grant test-only 跨接缝
slug: multica-grant-crosscheck
status: pending
estimate: 6h
depends-on: [CR-2026-030-TASK-04]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-07 扩展 Multica grant test-only 跨接缝

## 1. 任务描述

按 SDD §7.3 扩展既有 Go 到真实 crctl 的审批跨接缝：由 Multica `ApprovalService` 生成 approve/reject grant，真实执行 CR-2026-030 tools worktree 的 crctl，验证 reject 回退和紧邻幂等。Multica 保持 test-only，不新增 production consumer、migration、Runner 或测试框架。

## 2. 涉及文件 / 模块

- Multica：`server/internal/governance/approval_crosscheck_test.go`
- Multica：`CUSTOM.md`

## 3. 实现要点

- 先读并遵守 Multica `CLAUDE.md`，所有新增代码注释使用英文并检查所有错误。
- 从现有 `TestGrantCrossVerifiesWithCrctl` 提取最小 fixture helper，使用 table/subtests，不创建新测试包。
- fixture 建立 `cr.md` 与 v2 backlog 最小结构；reject 断言 `APPROVAL_DECLINED_ROLLED_BACK`、权威 target/trigger 和重放 `changed=false`。
- 测试执行显式设置 `CRCTL_PATH=<tools CR worktree>/skills/shared/crctl/scripts/crctl.mjs`，verbose 输出必须证明未 skip。
- 按 `CUSTOM.md` 当前实际表结构登记 CR-2026-030 与 TASK-07。

## 4. 验收条件

1. Go 签发的四阶段 approve/reject grant 可由真实 crctl 验签；至少 reject 回退与同 grant 紧邻重放均通过。
2. 定向 `go test -v` 输出无 skip，错误结果能显示 crctl stdout/stderr。
3. Multica diff 仅包含 `approval_crosscheck_test.go` 与 `CUSTOM.md`，production Go 与 CI workflow 零 diff。
4. CUSTOM 台账追溯包含 CR-2026-030 和 TASK-07，未把 CUSTOM-TODO 标为已交付。

## 5. 完成标志

显式 `CRCTL_PATH` 的定向 Go 测试通过且无 skip，CUSTOM 台账已登记，`tasks/_index.yml` 中 TASK-07 标记 `done`。

## 6. 接口契约

- **消费**：Multica `ApprovalService` 现有 grant v1 输出；tools `crctl approve <cr> --stage <stage> --grant <path>`。
- **产出**：test-only 跨接缝向量与 CUSTOM 追溯记录；不产出 Multica production API。
