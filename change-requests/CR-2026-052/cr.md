---
id: CR-2026-052
title: Multica 审批后自动续跑 + audit-drift 去重修复
summary: "依据《Multica 执行性能分析与模块职责边界》（CR-2026-051 复盘）注册，一个 CR 覆盖附件全部可实施范围：(1) Multica 侧——人工审批完成后在 grant 可靠写入 worktree 的 ACK 时点幂等唤醒既有 CR 任务自动续跑，覆盖需求/架构/开发启动/代码四类审批，通过与驳回均续跑，持续推进到下一个人工审批点或明确阻塞点；最小可靠性约束：pgx/sqlc 原生原子事务、kind=approval_continuation 窄唯一约束、ACK 失败可返回错误并由 daemon 15s 重试、同 CR 最多保留一个后继任务、无 leader 不回退、只处理新 ACK 不回填历史、不复制状态机/门禁/Pipeline 语义，Architecture Runner 保持关闭；(2) tools 侧——crctl outbox audit-drift 去重缺陷修复（comparable() 含 payload.detected_at 导致同一漂移再观测必冲突，与'待采集期间只留一份'语义矛盾）。附件其余范围（已解决基础设施、2026-08-26 已落地平台配置、明确不做清单）仅作背景与边界，不在本 CR 重复实施。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-27T00:17:26+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-27T00:17:26+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-27T00:17:26+08:00"
target-version: tbd
source: "docs/product/Multica执行性能分析与模块职责边界.md"
origin: ""
status: writing-back
created: "2026-08-27T00:17:26+08:00"
updated: "2026-08-27T16:25:11+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-27T00:17:26+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-27T00:17:26+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-27T00:17:26+08:00", reason: initial-assignment }
handover-history: []
---
