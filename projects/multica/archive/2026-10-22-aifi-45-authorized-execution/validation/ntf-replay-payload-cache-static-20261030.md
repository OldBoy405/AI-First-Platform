# AIFI-45 NTF-005/007：通知载荷与重投幂等静态核查

**状态：经独立静态复核的条件性发现；未运行测试，未证实线上可达或用户实际收到重复提醒。** 本文件不改批准合同或产品代码；历史事故资源继续 HOLD。用户确认的限定授权允许调查与列出的前端测试命令，但该命令的初始化、缓存、临时文件及选中前置尚未证实，当前不可执行。

## 已批准需求及边界

`canonical/specs/code/attention-routing.yaml` 的 SC-NTF-005 要求 pending 恢复可重投同一 Inbox ID、消费端幂等展示，并区分不同 CR；SC-NTF-007 要求沿原身份恢复已提交业务后的通知，不能把内部唯一保证扩大成第三方 exactly-once。`design.md` 将新策略标记与已有 Inbox 记录结合。这里区分**本地代码会选择什么发送路径**、客户端是否去重、系统是否真正显示和是否已经生产接线，不混为一谈。

## 发现一：已查 server 载荷与客户端新策略入口不一致

1. `../multica/server/internal/governance/execution_notice.go` 中 `DeliverNotice` 的写入只指定 Inbox 的 id、workspace、recipient、type、severity、title、body，未显式写 `details`。迁移 `019_inbox_details.up.sql` 新增的 details 默认值为 `{}`；不假定已部署数据库的实际 schema/内容。
2. 同文件 `LoadInboxItem` 的 SELECT 和返回 map 没有读取或附带 `details`；`BusBroadcaster` 将所供 loader 的 item 作为 `inbox:new` 发布。继续静态追踪 `cmd/server/listeners.go`：该事件从嵌套 item 取 recipient，经 `projectOutbound` 送 `SendToUser`，这条路径不补 `details`。因此，若该 loader、广播及 listener 实际接线且发送条件满足，WS 载荷仍不带客户端策略 key；这不证明不存在其他 loader、路径或部署接线。
3. `../multica/packages/core/inbox/ws-updaters.ts` 的 `hasExecutionNotificationKey` 要求非空 `details.execution_notification_key` 与 item ID；`realtime/use-realtime-sync.ts` 的 `handleInboxNew` 只有 key 存在才 claim/释放新策略，否则进入 legacy 发送分支。前端现有重投测试则在 fixture 中手工加入该字段，因而不能证明上述 server 形状进入新策略。
4. 对当前可检索 Go 源码的静态搜索，`DeliverNotice`、`RecoverPendingNotices` 与 `BusBroadcaster`/`LoadInboxItem` 的调用可见于测试，尚未找到生产调用者；动态调用、构建条件、其他仓或线上部署均未核实。去重命中后 `DeliverNotice` 直接复用而不再广播，当前代码中的 pending 重投由 `RecoverPendingNotices` 发起。该恢复查询未见行锁，也不区分正在投递和崩溃后待恢复，随后先广播再更新；恢复与首次广播或其他恢复并发、以及广播后标记失败，均可能造成重复广播。是否实际发生仍取决于调用及并发条件，恢复入口的生产调度同样未证实。
5. `design.md` §5 要求 key、投递状态在 Inbox details，配既有 Inbox 的 partial UNIQUE；现实现使用独立 `cr_execution_notice` 表。已存在的 `validation/notice-broadcast-review-20261028/REVIEW-STRONG.md` 记录了该结构偏离及 dedupe key 缺 project 和具体 recipient。本次复核的 `NoticeEvent`、`NoticeDedupeKey` 与冲突查询仍呈现相同结构：同 workspace、CR、cause、digest、audience 但接收者变化时可能命中旧行，而设计要求变化后的接收者得到必要通知。是否有外层额外保障未证实；不能擅自把独立表视为合同已修订。

现有 `use-realtime-sync-inbox.test.tsx` 的 legacy 无 key 用例源码对同一 item 连续两次事件断言 `showNotification` 被调用两次；本轮未运行该测试。它说明该测试预期发送调用重复，不能证明操作系统实际显示两次。已有新策略用例的 key 来自手工 fixture，不是服务端真实载荷证据。

**这些都是合同与已检索源码组合的条件性缺口，不是已证实的生产事故或真实用户体验结论。** 在事件可达、重复收到同一载荷且焦点/偏好允许发送时，缺 key 走 legacy 而不是新策略 claim：web 可再次构造浏览器通知，浏览器可能按 item ID tag 替换；desktop 可再次发 IPC，但主进程还有基于 item ID 的 gate（进程内、最多记 1,000 项）。静态代码不能据此断言用户看到两次。WeCom 同样订阅 `inbox:new`，实际链路和第三方去重仍待核，不能把内部唯一性扩大成其 exactly-once 保证。

## 发现二：仅在已有 key 场景下的缓存寿命待验证

- 新策略的 `claimExecutionNotificationDelivery` 以 workspace + Inbox ID 创建 TanStack Query 布尔标记；该文件未对标记显式设定独立生命周期。`packages/core/query-client.ts` 默认 query `gcTime` 为 10 分钟。
- 已读的当前安装版本 Query 实现对无 observer 且 idle 的 query 在 GC 时移除；当前工作树 `notification-delivered` 键只见该 helper 定义。新 query 创建时启动 GC；`setData` 与重投时失败的 claim 不重置计时。若期间无 observer 且定时器正常执行，**静态推导** marker 在首次创建后可能被清理，之后的同 ID 重投可再次通过 claim。这不是已运行的 fake-timer RED 或真实客户端验证；清除、登出及定时器节流等也影响生命周期。
- 所核 SC-NTF-005、设计 §5 和 test-plan 的相关条目未写明 10 分钟或进程重启的幂等边界；`validation/ntf-x6-convergence-recheck-strong-20261028.md` 中客户端范围是待定方案，不是已批准的豁免。不能自行增加时间上限或假定跨重启、跨设备 exactly-once，也不能用无界永久全局集合回避已批准的“不新增全局去重账本”约束。
- 桌面新策略确认成功后主进程另有独立 gate，未重启且未被容量挤掉时可阻止同 key 重放；超时释放后迟到显示、进程重启或容量淘汰等仍需另核。浏览器可能按 tag 合并；不能从 query 缺口直接推出 OS 级最终结果。

## 后续验证所需最小证据（当前均未运行）

1. 在已批准且安全的隔离 DB 上，用真实 `DeliverNotice → LoadInboxItem → BusBroadcaster` 检查持久 row 的 details、广播 payload、workspace/recipient 与同 ID pending 重投；检查真实生产 wiring，而不仅测试中自造 item。旧 runner 不得运行或换 URL。
2. 用当前可核形状的 server payload 构造 UI 反例，并保留有 key、不同 ID/不同 workspace、focus/mute 与失败释放的正反对照；断言发送调用和 OS 实际显示分别计数。`NTF-005`/`NTF-007` 筛选标签当前不在文件中，零匹配和 skip 不算测试。
3. 对有 key 的重投增加受控时钟的生命周期测试，确认标记创建、idle/observer、GC 前后及失败释放，并核各客户端的后续防重；fake timer 成功不能代替进程重启、多设备或 OS 真实通知。
4. 两条已列前端命令虽然获列入限定清单，但 Vite/Vitest 可能读取 `.env*`、创建缓存及临时目录；其实际模块初始化、无网络、文件归属/清理及零选中均尚未核实。未满足前置不运行。不同命令或参数需先按清单获得确认。
5. 若准备修复，按已批准合同核实 producer 可信性、字段定义、旧通知兼容、受众绑定和原恢复窗口，再用真实 RED→GREEN；不通过猜测 type 把 legacy 一律改成新策略，也不以 UI fixture 或静态结论关闭完整 TC、major 或 Gate3。

## 证据与执行记录

平衡档只读调查 session `01a18c5b-0d05-725c-98fc-910f140274f5`，请求 `OpenAIPersonal/gpt-6.1-terra:high`；独立强档静态复核 session `01a18c62-c6c8-725c-98fc-91148135d181`，请求 `GBClaude/claude-opus-5-5:high`；实际 backend 均无回执，记 unknown。协调者复核上述 server 写入/读取、恢复、client claim/fallback、默认 GC、desktop gate 和测试 fixture。另有独立只读复核 session `01a18cfc-38b1-7468-8217-4a5d2d2534ae`，请求 `GBClaude/claude-opus-5-5:high`，actual backend 无回执记 unknown；本次补充 listener 转发、恢复查询及 legacy fixture 断言的静态证据。两次调查均未运行项目代码、DB 测试或生产服务；源码版本及部署均未锁定，本记录不构成生产安全签核。
