---
id: CR-2026-008-TASK-02
type: TASK
cr-ref: CR-2026-008
plan-ref: "change-requests/CR-2026-008/plan.md"
sdd-ref: "change-requests/CR-2026-008/sdd.md"
title: 隐私收敛——chat 事件 per-user 定向推送（fail-closed）
slug: chat-events-per-user-push
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-02T11:25:00+08:00"
---

# TASK-02 — 隐私收敛：chat 事件 per-user 定向推送

## 任务描述

把所有携带 ChatSessionID 的事件从 workspace 广播收敛为 SendToUser 定向推送（SDD §4.3/§4.4，
DD-1/DD-2），fail-closed：有 ChatSessionID 无收件人 → 丢弃 + ERROR 日志，永不回落广播。
这是 PRD FR-6/NFR-1 隐私红线的主体实现，同时顺带修复既有全局 1:1 chat 的同一泄漏面。

## 发布点全量清单（SDD-SUG-001 落地，拆分期 grep 固化，实施时逐项打勾）

| # | 位置 | 事件 | 收件人来源 |
|---|---|---|---|
| 1 | `handler/chat.go:303/350/399/489/680/880`（publishChat ×6） | chat:message、session_updated/deleted/read | caller userID（HTTP 已强制 =creator） |
| 2 | `handler/chat_title.go:104`（publishChat） | chat:session_updated | 会话 creator |
| 3 | `service/task.go:2818` | chat:done | `GetChatSession(task.ChatSessionID).CreatorID`（:579 同款取法） |
| 4 | `service/task.go:2743 broadcastTaskEvent`（**咽喉点，覆盖 17 个调用点**：queued/cancelled/running/waiting/completed/failed/requeued） | task:* 生命周期 | task.ChatSessionID.Valid 时取 session creator |
| 5 | `service/task.go:2419`（超时清扫路径，持有 task 结构体） | task:failed | 同 #4 |
| 6 | `service/task.go:2462 ReportProgress`（**特例：仅有 taskID 字符串**） | task:progress | 调用方传 task 或按 taskID 查一次；见实现要点 |
| 7 | `service/task.go:2734`（EventTaskDispatch，持有 task） | task:dispatch | 同 #4 |
| 8 | `handler/daemon.go:3192`（EventTaskMessage，**chat 任务流式内容，泄漏面最大**） | task:message | task.ChatSessionID.Valid 时取 creator，一次/批次 |
| 9 | `cmd/server/runtime_sweeper.go:339`（持有 task） | task:failed | 同 #4 |

## 涉及文件 / 模块

- `server/internal/events/bus.go`（Event 加 `ChatRecipientID`）
- `server/internal/handler/handler.go`（publishChat 签名加 recipient）+ 上表 9 处发布点
- `server/cmd/server/listeners.go`（SubscribeAll 加 ChatSessionID 分支：SendToUser / fail-closed 丢弃）

## 实现要点

- creator 取值热点：sessionID→creatorID 是**不可变映射**，service 内加进程级小缓存
  （容量上限即可，无失效问题）；#8 每批次取一次。
- #6 ReportProgress 二选一：调用方补传 task / 按 taskID 查任务再走缓存；若实施发现调用方
  分散，允许暂缓该单点并在测试报告记录残余（task:progress 仅含进度摘要，无消息正文）。
- 桥接分支照 SDD §4.3 伪代码；ERROR 日志只记 id 不记正文（审计脱敏约束）。
- Lark 集成订阅在 bus 层（outbound.go:262），不经 WS 桥，不受影响——回归确认即可。
- 前端零改动是设计目标：不得动 use-realtime-sync.ts。

## 验收条件

1. 单测：含 ChatSessionID 的事件不进 `BroadcastToWorkspace`；无收件人时丢弃且有 ERROR 日志；
   无 ChatSessionID 的事件路径不变。
2. 集成：A 用户 chat 全流程（发送→流式→done→已读→改题），B 用户连接收到 0 条相关帧；
   A 的第二连接（多设备）全部收到。
3. 回归清单全绿：浮窗收发/未读徽标/全页 /chat 流式/pending FAB/chat:done 缓存直写/Lark 出站。

## 完成标志

单测+集成通过 + 回归清单逐项记录 + lint 零报错。
