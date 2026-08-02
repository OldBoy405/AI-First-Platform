---
id: CR-2026-011
title: P2 三模式聊天 CR-F — D7 门禁接合（B4 迁移 + 审批卡/blocker/CR 徽标）
summary: >-
  门禁接合（交付切分 v2 的 CR-F，后端 + 前端，跨 P1 链路）：
  ① B4 后端迁移：agent_task_queue 增 cr_id / pipeline_node_run_id 两列
  （P0 设计有、迁移未做）。
  ② 消息流内门禁状态条：pipeline 节点任务（pipeline_node_run_id 非空）渲染门禁状态；
  human_approval 节点渲染审批卡——走 P1 服务端签名审批（Ed25519，非 TTY），有权限者
  见批准/驳回，驳回 reject_reason 注入 review_feedback；review 节点 verdict=block
  显示 blocker 列表 + reviewLoop attempt N/3。
  ③ chatHeader 显示 CR 16 态徽标（消费 P1 已交付的 cr 投影表同步链路）。
  审批卡视觉自定（CodeBanana 无实物快照），语义严格按 P1 签名审批链路；
  核心验收：真实跑一条带 human_approval 的 pipeline，网页批准 → 服务端签名 grant →
  crctl 验签推进，全链路不落 TTY。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-02T10:00:39+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-02T10:00:39+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-02T10:00:39+08:00"
target-version: "0.18"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-F"
status: requirement-approved
created: "2026-08-02T10:00:39+08:00"
updated: "2026-08-02T10:00:39+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-02T10:00:39+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-02T10:00:39+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-02T10:00:39+08:00"
    reason: initial-assignment
handover-history: []
---
