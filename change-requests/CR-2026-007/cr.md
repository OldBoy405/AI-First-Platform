---
id: CR-2026-007
title: P2 三模式聊天 CR-B — D3 完整形态（队列条展开/逐项撤回/停止/过滤开关）
summary: >-
  Team Agent 面的队列与控制完整形态（交付切分 v2 的 CR-B，纯前端，后端能力
  CR-2026-004（D1）已全量交付，不动后端）：
  ① 队列条常驻「{count} 条排队」，展开列表逐项显示发起人（fromUser）；发起人对自己的
  排队项有「清除对话」撤回按钮（调 D1 cancel 端点，403/409 结构化反馈）。
  ② 停止：发送者停自己（运行中或排队中）、Owner 停任意（D1 已收紧的服务端权限直接生效）；
  停止后已生成内容保留、下一条自动开始。
  ③ 「只看 Agent 请求」过滤开关（吸收 CodeBanana 双入口动机）：本地过滤消息流，
  只影响渲染不动数据。
  ④ 消息悬浮操作本期只做复制（回复/转发按切分文档 §0.4 排除）。
  队列条 WS 实时无手动刷新。
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
target-version: "0.14"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-B"
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
