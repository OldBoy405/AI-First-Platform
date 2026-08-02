---
id: CR-2026-010
title: P2 三模式聊天 CR-E — D4 presenter 控制权（claim 串行化键 agent_id→project_id）
summary: >-
  presenter 控制权（交付切分 v2 的 CR-E，后端重、风险面独立）：
  ① 后端改造：claim SQL 串行化键从 agent_id 换 project_id（P0 §2.2 论证过），
  presenter 判定接入入队/claim 路径——单一写者语义：presenter 非空时其他成员消息
  不被执行（排队或拒绝，按设计稿口径）；Admin 在 Agent 空闲时可直接接管。
  ② 前端：设计稿 §3.1 状态机全部 6 个通知文案（申请/批准/转让/撤销/拒绝/释放）、
  chatControlPanel 权限面板、chatHeader「当前主持人」显示实时更新。
  可选吸收 CodeBanana 的系统状态卡（内联状态条）作为通知呈现形式。
  首要风险与独立成 CR 的主因：claim 串行化键改造后，既有单 agent 并发语义
  （CR-2026-004 的容量守卫/插队/撤回与 CR-2026-006 的群聊入队）回归测试必须全绿。
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
target-version: "0.17"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-E"
status: code-approved
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
