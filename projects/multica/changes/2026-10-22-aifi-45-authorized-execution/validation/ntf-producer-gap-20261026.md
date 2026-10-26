# NTF（attention routing）生产入口核实：缺的不是接线，是「谁来写通知正文」

日期 2026-10-26。只读核实，未改产品源码、未跑 DB、未部署。

## 结论

`cr_execution_notice` 子系统**实现完整、无生产调用点，且两仓都没有产出方**。它和 EVD-009 不是同一类问题：

- EVD-009：判定函数已存在、生产路径**有**对应事实，只差在既有接缝上多一次比较 → 可直接接线（已做）。
- NTF：生产路径**没有**通知正文所需的事实。`BuildNotice` 强制要求 `cause`、`conclusion`、`action` 三项人类可读文本（`execution_notice.go:173-198`），而唯一的候选入口 `SyncService.ingest` 手里只有机读事件（`OutboxEvent`: event_kind/payload/evidence）。把机读事件翻译成"结论是什么、人需要做什么"是**语义决定**，不是接线。

## 已核实的证据

| 符号 | 非测试调用点 |
|---|---|
| `DeliverNotice` | **0**（仅 `execution_notice.go:235` 定义 + 测试） |
| `RecoverPendingNotices` | **0** |
| `BusBroadcaster` | **0** |
| `LoadInboxItem` | **0** |
| `BuildNotice` | 1（内部 `deliverNoticeWith:243`） |

- `SyncService` 已持有 `pool` 与 `bus`（`crsync.go:133-141`），所以**广播器与恢复的接线本身是可行的、且不需要语义**。
- `NoticeSilentKinds` 的键（`run-node-started/ack/completed`、`repair-progress`）与 `cr_sync_event.event_kind` 同一词表 → 说明设计意图确实是把"事件进入处"当入口；但入口只决定**要不要**通知，不决定**正文**。
- tools 侧 `notice` **零命中**；tools 只有另一套既有的 `inbox` 事件（`crctl.mjs:4332` inbox-emit，用于 owner handover），与 NTF 无关。所以"让 crctl 产出通知"不是现成的一半。

## 为什么不能自己补正文

规范 SC-NTF-002/003/004 用的是自然语言："包含结论、必要错误、canonical 证据链接和明确所需动作"、维护故障要"带已试路径"。把它落到具体事件上需要一张映射表：

- 哪些事件算"需补授权"（SC-NTF-004）、哪些算"有界恢复后仍阻断"（SC-NTF-003）、哪些算"已完成约定交付"（SC-NTF-002）；
- 每种情况下的结论短语、所需动作短语、`cause` 取值（决定 audience 与 dedupe）；
- `TriedPaths` 从哪来（只有真跑过恢复路径的一方才说得准）。

这正是 RUN-009 被 BLOCK 的那类决定（替规范选语义），不应在 BUILD 里单方面拍。

## 可以立刻做、且不含语义的两半（但要一并决定要不要现在做）

1. **广播器 + 启动恢复**：`BusBroadcaster(s.bus, LoadInboxItem(s.pool))` 注入 `SyncService`；服务启动时按 workspace 调 `RecoverPendingNotices`。这满足 SC-NTF-007「提交后尚未广播的提醒不丢」，且不含任何正文语义。
2. **唯一入口的调用位**：在 `SyncService.ingest` 事件提交成功后调用一次 sink，由 silence 规则决定跳过 —— 但若 producer 未定，sink 无法构造 `NoticeEvent`。

**取舍**：只做第 1 半在没有 producer 时是空转（YAGNI）；做第 2 半必须先有映射。所以本轮**不动 NTF**，把它记成待决策项，而不是假装接线完成。

## 建议的决策问题（给规范/设计，不是给我）

> NTF 的 `cause/conclusion/action` 由哪一层决定？  
> (A) multica runner 在 stop/wait 点按固定映射生成（需要一张 事件→四元组 的表，须审阅）；  
> (B) tools 在 CR 状态推进时就产出通知条目，multica 只负责投放（需在 crctl 新增域，且要过可信来源问题）；  
> (C) 本期只交付"投放+恢复"，明确记录 NTF 通知正文生产方未实现，并在台账标注"能力不可达"。

## 台账影响

- NTF 7 条 TC 的 CP 口径与计数**不变**（仍计入现有 41/49）。
- 但必须与 F7（`relayExecutionBinding` 无生产调用点）同样标注：**函数存在 ≠ 生产可用**；不得据单测通过声称"通知已能送达责任人"。
