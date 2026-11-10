# WP6 通知：同事务投递原语 + 接收者进入通知身份（2026-11-04）

> 目标是通知意图与业务事实同事务、同一通知重投不重复创建 Inbox；目前仅实现部分原语，尚未证明这两项端到端保证。
> 未部署、未连数据库、未跑 DB 级 TC（TC-NTF-001～007 仍无业务证据）；`noticeguard_test` 是离线包，不代替真实入口。

## 1. 改了什么

文件：`multica/server/internal/governance/execution_notice.go`

### 1.1 拆出可加入业务事务的投递原语

原来 `deliverNoticeWith` 自己 `pool.Begin`：notice 行和 inbox 行虽然同事务，但**不能与产生它的业务事实同事务**——业务回滚会留下无主提醒，业务提交也可能漏掉提醒。

| 函数 | 职责 |
|---|---|
| `DeliverNoticeTx(ctx, tx, ev)` | 在**调用方事务**内写 notice + inbox；不提交、不广播、不标记 |
| `BroadcastNotice(ctx, pool, ws, outcome, broadcast)` | 事务提交后广播，再置 `delivered` |
| `deliverNoticeWith`（`DeliverNotice` 的实现） | 独立路径包装：静默 → 内容校验 → 地址校验 → 自开事务 → 提交 → `BroadcastNotice` |

顺序是刻意的，而且顺序错了会真的改变行为（本轮踩了三次，见 §4）：静默检查先于任何接线依赖；内容校验先于接线校验；地址校验先于需要 pool 的步骤。

### 1.2 接收者进入通知身份

`NoticeDedupeKey` 原来只含 `cr / cause / evidenceDigest / audience`。后果：同一失败**换人处置**时键不变 → 新责任人被去重吞掉，永远收不到提醒（TC-NTF-006 要求的"接收者变化必须通知"不成立）。

现在：

- 键里加入接收者，并**规范化成 canonical UUID**（32 位十六进制与连字符写法是同一个收件人，否则同一个人会收到两条）。
- 空接收者**不**在 `BuildNotice` 阶段报错——渲染与投递是两件事，仓库里 4 处 DB 用例只渲染不投递。空值在键里保持独立（不会与真实收件人合流），在 `DeliverNoticeTx`/`deliverNoticeWith` 的**地址校验**处被拒绝。

去重权威仍只有**一处**：`cr_execution_notice (workspace_id, dedupe_key)` 唯一索引 + 同事务一并写 inbox。

**没有**按 design §5 第 80 行新增 Inbox partial UNIQUE 索引；拟复用既有 notice 唯一键以避免重复权威。但旧键不含接收者，新旧键不同可能使同一事件升级重投生成第二条，且数据库并发尚未验证，不能宣称现有约束已满足全部原设计保证。该偏离登记 `ADJ-AIFI45-M009`，仍未解决。

## 2. 证据

```text
RED（定向变异：把接收者从键里去掉）
  --- FAIL: TestNoticeDedupeIdentityIncludesRecipient
      RECIPIENT_CHANGE_SWALLOWED: 换接收者仍得到同一个键，新责任人会被静默去重
  （恢复后 SHA 逐字节一致）

GREEN  noticeguard_test exit 0  顶层 14（原 13）  子例 661
build ./... exit 0    vet ./... exit 0
```

`TestNoticeDedupeIdentityIncludesRecipient` 的断言各自钉一个错误行为：

1. 同一事件重投 → 同一个键
2. 外层空白/大小写 → 同一个键
3. **换接收者 → 不同键**（变异能且只能打红这一条）
4. 空接收者 → 键与真实收件人**不同**，且投递被拒（`notice recipient id`）
5. 同一 UUID 的连字符/紧凑写法 → 同一个键

**后续离线夹具纠正：** 原 fixture UUID 全数字，大小写断言不能区分去掉 lower/UUID 规范化的回归。定向测试先因旧夹具无法辨识大小写而 RED；改为含字母 UUID 后分别验证大小写和外层空白，离线包重跑 exit 0，676 个父/子 PASS 事件、零 fail/skip（不将父子事件相加称为业务 TC）。另明确当前带空白 recipient 可以渲染，但 `DeliverNoticeTx` 与独立包装投递入口拒绝；该测试刻画不一致而非批准合同。该次 `noticeguard_test/execution_notice_test.go` 的 LF SHA-256 为 `3d273b8a4e64576018922a84b1f195141d8f4b2b157c01f101120e814d489fff`，已登记 `multica/CUSTOM.md` #301。独立只读复核 `01a1a8fa-617f-7374-9f4d-47283f4c1be8` 静态确认测试可区分大小写回归、范围及台账；指出刚才的 RED 只是数字夹具不含字母，不能当作实现缺陷 RED。随后补齐静默事务入口 `Created/Broadcast` 均为 false 的断言，最新测试文件 LF SHA-256 为 `f3bdd67938b7b07fd16c49202bce2e9ab2fdb7871004be763bd79e635f47a057`；对该最新快照仅离线重跑 `TestNoticePaddedRecipientCurrentDeliveryBoundary`，其 leaf 和包各 PASS、0 fail/skip，未重跑全包。复核未运行测试、未证明后台模型身份；未连接 DB，未留全量 TAP/JSON。

## 3. 独立复核（strong `GB-JP/kimi-k3.1-pro:high`，只读）

首轮结论 **BLOCK**；下列三处之后已修改：

| 复核发现 | 修法 |
|---|---|
| 广播收的是事件里的原始 `WorkspaceID`，旧实现传解析后的 canonical UUID；非规范 UUID 会改变广播入参 | `BroadcastNotice` 先 `uuid.Parse`，用 `wsID.String()` 广播，再标记 delivered |
| 空接收者检查抢在 maintainer `TriedPaths` 的 payload 守卫之前 → 错误优先级变了；且 4 处只渲染的 DB 用例 fixture 未带接收者 | 撤销 `BuildNotice` 的空接收者报错，改为键内区分 + 投递期拒绝；错误优先级回到原样 |
| 仅 trim/lower 不是 UUID 归一化，32hex 与连字符写法会生成不同键 → 同一人两条 Inbox | 键内 `uuid.Parse(...).String()` 归一化（解析失败才退回 trim/lower） |

后续针对当前版本的第二次 strong 只读复核确认三处修改及事务/广播拆分，但总体仍 **BLOCK**：旧键重投兼容缺失、缺业务接线及调用方事务/并发 DB 验证；当时还发现 `CUSTOM.md` 未登记，现已补 #300。该复核未运行测试，actual backend 无独立回执。

## 4. 过程中自己造成的四次红，都修了并留痕

1. `broadcast == nil` 早于静默检查 → `TestSilentEventsNeedNoBroadcasterOrDB` 红。
2. 空接收者检查早于既有 guard → 6 个 guard 用例的错误码被改写。
3. `broadcast` 检查早于 `BuildNotice` → 7 个内容守卫用例拿到 "notice broadcast is required"。
4. 空接收者硬失败 → 4 处只渲染的 DB 用例 fixture 会红（由独立复核发现，未跑到）。

四次都是**我自己的顺序/契约错误**，没有为了让测试变绿去改断言。

## 5. 这条链路仍然没通

- `DeliverNoticeTx` 仅被内部 `deliverNoticeWith` 包装调用；没有业务事实生产者调用事务入口，不能证明业务事实与通知意图同事务。
- `RecoverPendingNotices` 同样无生产调用：漏提交即无行，漏广播且无恢复则长期 pending。
- DB 级 TC-NTF-001～007（Inbox 事务、广播故障、并发重放）未运行；客户端"重投不产生第二条可见提醒"未验证。
- 旧键升级重投可能重复；当前不能承诺完整幂等投递，更不承诺桌面弹窗出现或用户已读。
- pi-web 只读复核 `01a1a773-8f97-7374-9f4d-4709c969f238` 指出：旧 hash 可以在持有**原始输入**时重算，但旧 notice 行本身不保存 project、完整证据或稳定失败事件身份；不能凭 hash、当前成员或关联 Inbox 推断历史归属。无条件复用可能吞掉不同收件人或新失败，直接写新键可能产生第二条 Inbox；查询旧键再写新键也不能阻止旧写者并发，旧恢复器还可能先广播后更新。当前没有证据证明生产是否存在旧行。
- 当前局部新键未绑定可信 project/稳定事件，M009 的 `cr_execution_notice` 索引替代原 inbox details / partial UNIQUE 合同仍待批准；不能因新键同版本组件通过宣称 SC-NTF-005/006/007 已满足。`BuildNotice` 对 UUID 去空白后算键，但 `DeliverNoticeTx` 的 recipient 解析未去空白，属于输入契约不一致，须随可信 producer/键方案决定而统一，不能因此放宽旧键判定。
- 未知旧归属、旧 pending 与已存在的双行如何对账及何时解冻，须按适用人工/合同流程决定；同一 Inbox 的重复广播与新建第二条 Inbox 是不同事实。该复核仅静态读源码，未运行 DB/网络/客户端或接触 HOLD，requested model 不证明实际 backend。

原始输出：`red-recipient-identity.txt`、`green-noticeguard.{txt,json}`、`build-vet.txt`。
