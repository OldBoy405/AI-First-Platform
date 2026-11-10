# AIFI-45：CR 事件投影与 ACK 当前源码静态复核

**状态：静态调查，不是测试通过或部署事实。** 本记录基于当前 `../multica/` 工作树，可能含未提交变化，未将某个 commit 当作完整源码快照；未运行代码、业务测试或数据库，也未访问事故资源。旧调查作为当时快照保留，不能不经复核地当作当前实现。

## 现状与边界

1. `server/internal/governance/crsync.go` 的普通 `ingest` 在幂等键冲突后检查 `processed_at`：已处理则返回成功；**未处理的重复投递会继续 `apply`**，成功后再标记 processed。此前“只要 ledger 已插入就直接 ACK、永不补投影”的概括不再适用于当前代码。`TestDuplicateOfAnUnprojectedEventIsProjected` 的源码覆盖预置未处理行后重投，但本轮未运行，也没有证明任意部分失败或并发都能恢复。
2. 当前 AIFI-68 相关代码接受带 ledger key 的 CR ID，将 status 的 from/to/trigger 纳入新写入的 payload，并在重复事件的原 evidence 恰为空对象且新 evidence 非空时补入。它不证明既有空 payload 被补齐，也不覆盖任意非空 evidence 冲突；已 processed 的行即使补证据也不会因此重跑投影。
3. `applyStatus` 可以先更新 CR 行，再调用 `projectGateTransition`。后者调用 `projectGateTransitionErr` 后丢弃错误，函数体没有其注释所称的日志。因此，若 gate/run/node 投影失败而后续 processed 写入成功，事件仍可能 accepted；同键重投在已 processed 分支不会自动补该 gate。这是静态控制流，不是已注入故障的运行结果。乱序/非法状态另有 reconcile 路径，不能概括为所有状态都成功投影。
4. review 调用 `applyReview`，其返回的错误与 status 的 best-effort gate 路径不同，不可笼统称所有 review 失败都被吞掉。未知 review stage 是独立 no-op 情况。trace 使用另一套事务/冲突处理，也不能把其保证套到普通 status/review。
5. `server/internal/daemon/crevents.go` 的 `applyAck` 对普通 outbox rejected 记错；对 `commit:` / `snapshot:` 合成 ID 的 rejected 则跳过。故不能笼统声称全部拒收都会阻止游标推进，也不能声称所有普通 outbox 拒收均被忽略；实际游标、重试和死信仍需按通道及批次验证。

## 未完成工作

- 定义并评审 CR 状态、gate 投影、processed、并发重复与外部 ACK 的原子性/恢复合同，包括 status 已写但投影或 processed 失败后的重试、历史已 ACK 事件与合成事件；不能仅给现有投影函数加错误返回即宣称修复。
- 在获准的隔离环境中对真实入口做故障注入，分别检查实际投影、processed、accepted/rejected、游标与重投；区分已 processed、未 processed、状态已先改变、review 和合成事件。不得以现有测试源码、组件检查或 fixture 代替端到端 TC。
- 设计和行为变更若触及现有 best-effort 合同，先按适用流程审议；在明确批准前不修改产品行为、不操作真实 CR。

## 来源

独立只读调查 session `01a18d02-21b8-7468-8217-4a629d4fde38`，请求 `OpenAIPersonal/gpt-6.1-sol:high`，actual backend 无回执记 unknown。协调者核对了 `crsync.go`、`gate_projection.go`、`crevents.go` 及 `crsync_test.go` 的相应代码片段；结果不代表生产部署或 Gate3 通过。
