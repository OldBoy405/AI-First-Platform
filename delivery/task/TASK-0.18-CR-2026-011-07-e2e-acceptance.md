---
id: CR-2026-011-TASK-07
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: 端到端验收（AC-1~7，含无 TTY grant 链路实跑）
slug: e2e-acceptance
status: done
estimate: 6h
depends-on: [CR-2026-011-TASK-02, CR-2026-011-TASK-03, CR-2026-011-TASK-04, CR-2026-011-TASK-06]
assignee: ""
created: "2026-08-02T12:40:00+08:00"
spec-id: ai-first-platform
version: "0.18"
---

## 任务描述
按 SDD §9 全场景验收并出 test-report.md。核心是 AC-1 的真实链路：本 workspace 真实 CR 的
requirement 段——网页批准 → 服务端签名 grant → daemon 落盘 → `crctl approve --grant`
验签级联 advance → 事件回流 → 卡片闭环，**全程无 TTY**。

## 验收清单（对照 PRD §5）
- AC-1 核心链路：审批卡出现 → 批准 → approval_record SELECT → `.crctl/grants/` 落盘 →
  --grant 推进 → cr:updated → 卡片转历史条；无手动刷新
- AC-2 驳回：reason → grant(reject) → 状态回退 → review_feedback 注入核对 → attempt 递增
- AC-3 blocker：构造 verdict=block 评审 commit → 扫描 → blocked 卡与 yml 逐字段一致
- AC-4 徽标：advance 后 WS 实时变化；16 态逐态核对；**多 CR 边界**（同项目 2 条在途 CR，
  徽标取 updated_at 较新者，popover 全列——SDD §6.2）
- AC-5 迁移回归：七路入队 + claim + 撤回 + 容量守卫全绿；非 CR 任务两列 NULL；
  retry 保留 cr_id；SET NULL 实测；**pipeline_node_run_id 全表恒 NULL 断言**（SDD §6.1）
- AC-6 安全回归：mat_ 403；篡改证据 → 409 指纹对比呈现；can_approve=false 无按钮 +
  直接 POST → FORBIDDEN_APPROVER 403
- AC-7 双端/locale：web + desktop 目视回归；parity 全绿

## 实现要点
- 环境前置：server 配 APPROVAL_SIGNING_KEY（+公钥入 knowledge-base `.crctl/keys/`）、
  daemon 在线、真实 CR worktree。另跑一遍**未配置 KEY 的冒烟**（DD-8 降级：门禁 UI 整体不渲染）。
- `shell_issue_id IS NULL` 历史 CR 不出现在 gates 响应是**显式语义**（SDD TSUG-003 定案），
  验收记录该行为而非当缺陷。
- 产出 `change-requests/CR-2026-011/test-report.md`（status 字段是 code 审批段证据）。
