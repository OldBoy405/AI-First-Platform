# AIFI-45 通知广播 fail-closed — STDD strong 独立审核

- 档位：strong，独立只读审核（未运行DB/容器/真实通知，未修改源码）
- 范围：nil broadcaster / BusBroadcaster 缺 bus、loader、空载荷 / silent 路径 / 事务后出错保留 pending / 既有调用兼容；对照 design §5
- 结论：**有条件通过（代码逻辑层面）**。缺依赖 guard 符合 §5 第76、81、83行；剩余风险与未验收项见 §5。

## 0. 覆盖范围与快照声明

本报告**只覆盖下表三项原始快照**（基于 HEAD `81e5293ad` 的未提交工作区，源文件 LF）。作者之后对源码的任何修订均**不在本报告覆盖范围内，不因本报告自动获认可**，需按新 SHA 重新审核。

| 文件（`multica/server/internal/governance/`） | 审核时 sha256 | 审核时 git blob |
|---|---|---|
| `execution_notice.go` | `821a334fcaedf3fa4d36a946187f121708d445b91ce5b01ecb2fd3b51de71fd2` | `7545039ef03ad86a712a5380c5fc18bc58411d4e` |
| `execution_notice_test.go` | `8d9a72282cb77f558915b621f62111aec9e8234c77a0a1f4fff87586889faa8f` | `fdc8690fb28ffdecd5f2bc80428a6d1df30fb462` |
| `noticeguard_test/execution_notice_test.go`（新文件，untracked） | `e90f0f215b9c65e4173b05804f81470487d3eb6966130ce9329970214cb76966` | `0ee8067f6463627c22241a25a54999be0f3b7c3a` |

设计依据：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/design.md`，sha256 `c97d10135d1f3ad1783ac2d39d3343123e89428b415e1579436fd8084bcfec3b`（133行；§5 = 第74–84行）。

**归档时漂移记录（仅记录，未审核）**：归档时重新计算得到 `execution_notice.go` = `3c523681b010b4c70f4ba96122d57851f21801c5bef4e9ea9b9c7727f819085f`，`noticeguard_test/execution_notice_test.go` = `184f920c7277e1684d8c2a29c139bff8eb6e5bb990b435e8874c5d990cd49def`，均与审核快照不同；`execution_notice_test.go` 与 design.md 未变。上述新版本未经本报告审核。

## 1. 首轮审核：缺依赖 guard（原快照）

### 1.1 逐项核对
- **nil broadcaster**
  - `DeliverNotice` 在 `pool.Begin` 之前拒绝：顺序为 silent 判断 → `BuildNotice` → uuid 解析 → broadcaster 检查，不访问数据库。
  - `RecoverPendingNotices` 在 `Query` 之前拒绝。
  - broadcaster 是函数类型而非接口，不存在“带类型的 nil”绕过。✔
- **BusBroadcaster 缺依赖**：缺 bus、缺 loader、loader 返回错误、loader 返回 nil map，四种情况均在 `Publish` 之前返回错误；测试断言订阅者收到 0 次调用。✔
- **silent 路径**：静默判断位于最前，不需要 broadcaster 和数据库，返回 `State="silent"`。✔
- **事务提交后出错保留 pending**
  - after-commit / broadcast 出错：返回 `{Created:true, Broadcast:false, State:pending}` + 错误。
  - before-mark / mark 出错：返回 `{Broadcast:true, State:pending}` + 错误。
  - DB 行保持 pending，由恢复流程在同一 inbox id 上重新广播。✔
  - 恢复中途失败返回已完成数量，未处理行保持 pending。✔
- **既有调用兼容**
  - 生产代码中**无任何** `DeliverNotice` / `RecoverPendingNotices` / `BusBroadcaster` / `LoadInboxItem` 调用，仅测试使用；签名未变，不破坏现有调用。
  - DB 测试原传 nil 的三处已改为 `noopNoticeBroadcast`。
  - `TC_NTF_006(3)` 仍传 nil，但在 `BuildNotice` 阶段先失败，结果不受影响。✔
  - 行为变化：去重命中路径现在也要求传入 broadcaster。

### 1.2 首轮问题
1. **中：`Bus.Publish` 无送达回执。** 进程内同步调用，吞掉订阅者 panic，无订阅者时直接返回；`Publish` 返回即标 delivered，故 delivered 仅表示“已发布到 bus”。（首轮曾建议加 `SubscriberCount` 检查，已在 §3 修正其限度。）
2. **中：缺依赖错误在提交后才暴露。** `BusBroadcaster(nil, …)` 返回非 nil 闭包，前置 nil 检查拦不住；inbox 行已提交可见，通知行停在 pending。恢复用同一坏 broadcaster 会持续失败，且首条失败即停，后续全部卡住（队头阻塞）。不丢通知，但“已入库、无实时推送”。建议提供构造期校验变体，或恢复时跳过失败项继续。
3. **低：空载荷未完全拦截。** 仅判断 `item == nil`；非 nil 空 map 或 id/workspace 不一致的 item 仍会被发布。`LoadInboxItem` 输出规范，风险仅在自定义 loader。建议校验 `item["id"] == inboxItemID`。
4. **低（原有）：恢复时传原始 workspaceID 字符串。** `RecoverPendingNotices` 把调用方字符串原样交给 broadcast 而非 `wsID.String()`；大写或带花括号的 UUID 可能导致 `Event.WorkspaceID` 不规范、路由不到房间，但仍标 delivered。
5. **低（原有设计）：去重命中已存在的 pending 通知不重新广播**，返回 `Created:false, State:pending`、无错误，依赖恢复流程；恢复无行锁，可能与投递并发重复广播——在“至少一次 + 消费方按 inbox id 幂等”前提下可接受。

## 2. 补核：design §5（第78–83行）对照

| 行 | 设计要求 | 实现（原快照） | 判定 |
|---|---|---|---|
| 76 | 机械事件只留运行记录，不主动通知 | silent 判断最前，无需 broadcaster/DB | ✔ |
| 81 | 提交后广播成功才标 delivered | 旧代码在 broadcaster nil / bus nil 时未广播即标 delivered（违规）；新代码仅在 `Publish` 返回后标 delivered，提交后任何出错保持 pending | ✔ 本次修复 |
| 81 | 广播前崩溃扫描 pending 恢复；广播后标记前崩溃允许同 ID 重投；不宣称 exactly-once | 恢复缺 broadcaster 直接报错，无“假恢复”；重投同一 inbox id | ✔ |
| 81 | 已 delivered 相同事件重放不再广播 | 去重命中直接返回，不广播 | ✔ |
| 83 | 通知失败不回滚已提交业务事实；沿原通知语义有界恢复 | broadcaster nil 在建事务前报错，不写记录；此时无 pending 可恢复，调用方须暴露错误、不吞、不当业务失败。生产无调用方，未验证 | ✔ 逻辑成立，待接线 |

**与设计不一致（本次改动之前已存在，不属本次修改范围，记录备查）：**
- **第78、80行 存储位置**：设计要求键写在既有 `inbox_item.details.execution_notification_key`，配 `(workspace_id, recipient_type, recipient_id, key)` partial UNIQUE 索引，明确不建独立去重账本；实现使用独立表 `cr_execution_notice`，`UNIQUE(workspace_id, dedupe_key)`，pending/delivered 也存于该表而非 `details.execution_delivery`。
- **第78、82行 去重键缺字段**：设计要求键含可信 project 与规范化接收者，且“接收者变化必须得到不同事件身份”；实现 `NoticeDedupeKey` 仅含 CR、cause、证据摘要、audience，**缺 project 与 recipient**。同受众换接收者会被旧记录吞掉，直接违反第82行。

## 3. SubscriberCount 建议的修正

首轮“在 `BusBroadcaster` 中检查 `SubscriberCount(EventInboxNew) > 0`”的建议，经核实存在以下限度：

- **TOCTOU**：`Bus` 无 Unsubscribe，订阅者只增不减，不会出现检查时有、发布时无；但“检查时 >0”与“发布时 handler 成功处理”之间无任何保证。
- **假阳性（误判已接线）**：`inbox:new` 订阅者除 realtime 桥接（`cmd/server/listeners.go:108`）外还有 WeCom 出站（`internal/integrations/wecom/outbound.go:180`）；仅 WeCom 订阅即可使计数 >0，即便 realtime 未接线。
- **假阴性（误判未接线）**：`SubscribeAll` 全局 handler（`listeners.go:243`）不计入。
- **>0 不等于送达**：handler panic 被 `Publish` 吞掉；跨副本经 Redis 转发失败只记日志；用户可能离线/无连接；无任何用户层送达回执。

**精确限度**：`SubscriberCount(EventInboxNew) > 0` 只证明“检查瞬间，本进程至少注册过一个专订 `inbox:new` 的 handler（不一定是 realtime 桥接）”。它只能用作启动/接线期检查，发现“bus 上无人订阅”类配置错误；不得写入逐次投递判断冒充送达，不得改变 `Broadcast=true` / `delivered` 的语义——二者只能表示“已提交到进程内 bus 且 `Publish` 已返回”，须与“用户已收到”区分。真正送达证明需消费端回执（如客户端按 inbox id ACK），或以 inbox 读侧（用户之后仍能查到该记录）作为送达保证，均不在本次范围。

## 4. 方法
- 读取原快照三文件全文、`git diff`（HEAD `81e5293ad`）、`internal/events/bus.go`；仓内 grep 调用方与 `inbox:new` 订阅者；读取 design.md §5。
- 未运行任何测试（含 noticeguard 单元测试与 DB 测试 `TC_NTF_001/002/005/006/007`）；未触碰 DB/容器/真实通知；未修改源码。

## 5. 合并结论
- **本次改动（原快照）**：缺依赖 guard 符合 §5 第76、81、83行，判定通过。
- **剩余风险**：
  1. 中 — 存储模型与去重键偏离设计（原有）：缺 project/recipient，接收者变化被吞。
  2. 中 — 送达只到“已发布到 bus”，无回执。
  3. 中 — `BusBroadcaster` 依赖错误提交后才暴露，通知停 pending；恢复首条失败即停，队头阻塞。
  4. 低 — 非 nil 空 map 或 id 不一致 item 仍会发布。
  5. 低 — 恢复使用未规范化的 workspaceID 字符串。
- **未验收**：生产未接线（无调用方、无恢复任务）；真实 DB 测试与 noticeguard 测试本轮均未运行；源码在归档时已漂移，新版本未审。
