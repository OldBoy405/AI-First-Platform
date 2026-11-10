# AIFI-45 控制通道：剩余信任边界与实施顺序

> 状态：BUILD 中的分析和建议，不是 Gate3 批准或安全验收。`TC-RUN-003` 尚未独立验收；生产判定器与 verdict producer/ingest 均不得单独启用。command 路径单独评估，不能借 verdict 的测试结论。

## 已证实的边界

- `ApplyControlCommandTx` 和 `AppendVerdictFrameTx` 目前都从调用参数接收 `Manifest`、`AttestationScope` 和 `Now`。它们可证明输入与所提供的密钥/作用域一致，**不能自行证明这些输入来自服务端受保护配置**。当前无已确认的生产 verdict 写入调用方；不能据此推断现有对外利用路径，也不能把以后接线时的信任来源留给请求方。
- command 仅验证部分 B；请求字段与签名相等不等于与服务端授权的 workspace/project/CR、reservation、候选任务和执行者等事实相等。当前 writer 尚未完整核对 cursor 的 store/epoch、owner/fence、tail、open slot 与已验证路由。
- `ApplyControlPolicyEventTx` 当前是内部入口；需查明 revoke/stop 与权威 head 或签名停止结果之间的来源及顺序，不能把任意调用者填写的事件等同权威。协作式 advisory 锁也不能约束绕开入口的写表者。
- verdict 的 payload 原字节可核对；envelope 存在 JSONB 中，当前只能比较结构值，不能证明原始信封格式字节被保存。Go writer 的 payload 摘要和 Node store 的 frame 摘要仍需跨语言统一及向量测试。
- 原 verdict 重放按 request 命中后曾不核内容，且返回调用者提供的 verdict ID；现已按存储字段核对并返回数据库 ID。详见台账增量 86；这不消除信任根、时钟或 producer 缺口。

## 最小可信配套（建议，尚未全部实现）

1. **服务端私有信任快照**：启动时读取一次并固定控制通道 manifest 的原始字节及其批准 SHA，使用同一份字节解析；密钥表、预期 scope 和服务端时钟不由 HTTP body、命令或任务输入覆盖。配置缺失/不一致即不可用，不回落到临时 key。command 与 verdict 分别核对 purpose/domain/scope；复用当前 verifier，不把不同用途的执行合同 manifest 当作控制密钥表。
2. **权威候选及路由**：事务内从 selection、reservation、已签当前 head、实际 run/node/task、执行者、daemon、store 与受保护 subject/capture 构造预期 B，再逐字段比较签名内容；不得把解出的 B 自身当作预期值。冷启动 control 分支不能强行要求尚不存在的 task。缺权威数据即拒绝，不靠自报补齐。
3. **原子占槽与链状态**：按经过锁图复核的顺序获得业务/head 与规范 lineage、cursor 锁；锁后重新读取有效期、scope、owner/fence、epoch、tail、open slot 和当前撤销；命令插入与占槽同事务。锁等待后使用服务端实时时钟或数据库 `clock_timestamp()`，不能用事务开始时的 `now()` 冒充等待后的当前时间。网络调用不放在持锁事务内。
4. **明确取消、恢复与序列**：按 M003 合同区分原始 owner fence 与恢复后的 effective fence，保留恢复证明；精确重放返回原记录，不同签名载荷/不可变字段冲突。现有 command 的唯一序列也容纳 policy 事件和未发行取消，而设计中的 expected sequence 指向下一 T verdict；未经解决直接加 `last_seq+1` 会阻塞合法恢复。建议 T 序列仅由已提交 T 帧推进，未发行取消不占 T 序列；若须持久化该区分，用前向迁移而不是修改已应用的 648。此处是待确认的合同设计，不是既有实现事实。
5. **配对接线和门禁**：先完成 Go/Node 签名字段、链摘要、首帧前驱、原始 bytes 和错误码的互操作向量，再做实际 producer→ingest→settlement→Admission→Runner 的正反例；组件版本、密钥、迁移及回退证据共同评审。Gate3 人工批准前不接 `main.go`，批准后也必须判定器与 producer/ingest 同批接入。

## 先验验证

- 自签陌生 key、由输入替换 manifest/scope/时间、过期/未来生效 key、等待锁期间过期；正控使用固定可信 key。
- 每个 B 字段、跨 tenant/CR/任务、错误 executor、头撤销及 owner/fence/epoch 漂移各自改一项；失败时同事务回读零 command/占槽，无从共享签名 payload 派生“期望值”。
- cursor 缺失、冻结、跳号、错前驱、open slot 不一致；并发重放与冲突、撤销与占槽、owner takeover 与恢复；真实 DB 观察持锁及释放后的结果。
- 两种 target 不得混用；取消/恢复不得占用不存在的 T 帧序号；跨语言相同原始 bytes/摘要/验签向量；失败注入证明插入和占槽同回滚。
- 所有 DB 证据经版本化隔离库 harness，skip 0 且 original unchanged / owned resources cleaned；不能以模拟 counter 或 exit 0 的零用例替代真实行和实际选中测试。

## 来源与开放决策

只读规划 session `01a18177-0ec0-7020-aecc-d1592f8c9cf5`，最终消息 `d1b3edaa`，响应元数据 `OpenAIPersonal/gpt-6.1-sol`，报告 SHA256 `95a1c009858db2f7b2a053c4ffd51f711779797f4cfe088bfcc27ebb3be28323`；仅静态调查，未冻结源码、未运行 DB，也未给安全通过结论。现有 claim 锁序与 M003 提议锁序不同，需先做完整锁图；路由注册/受保护 capture 的事实源及序列迁移方案仍需设计与独立复核，不能用未经验证的 writer-only 补丁宣称闭合。
