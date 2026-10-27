# 可信 T committed verdict channel — multica 测试方案

> STDD Phase 2 / Gate 2 草案。**本文件不声称任何测试已运行**：43 个 TC 全部为待实现/未运行。
> 设计输入：前身 change `validation/trusted-verdict-channel-implementation-plan-20261026.md`（v0.6.5）。
> 跨仓 tools 侧测试方案见[配套文档](../../../tools/changes/2026-10-27-trusted-verdict-channel/test-plan.md)。
> 必达 leaf 全名以 `validation/channel-test-expectations.json` 为唯一权威（SPEC 已冻结：41 label / 215 leaf，每个 leaf 标注所属 SC）；本文件只引用、不另立名单。

## 一、测试策略

### 1.1 金字塔与边界

优先**真实入口级隔离集成**：真实 DB Tx primitives → 真实 worker/daemon 路由 → 真实 service/TaskService；
协议向量与迁移专例单列。不以 fake enqueuer、直接 walker、纯函数替身或父测试 PASS 代证。

### 1.2 安全与执行原则

- Gate 2 之后逐个 TC 走 RED→GREEN；当前不跑数据库迁移、不跑业务测试、不部署。
- DB 只用 `scripts/aifi45-db/run.mjs` 的**本轮独占 nonce 库**，须 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip=0`；
  指针不匹配或语义漂移立即 STOP 并保留现场。
- governance 全包需 `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`，否则 TC-AUTH-010 按设计 Fatal。
- 并发/崩溃用确定性 barrier、`lock_timeout` 与 `55P03` 探针，不靠随机 sleep；失败断言不得是超时或连接错误。
- 每条 mutation 须使对应 leaf 的**断言**失败并保存 patch hash、基线与恢复后 source hash、实际 argv；编译错、连接错、零匹配、夹具错不计 RED。
- 零新 grant/receipt/task/敏感副作用是负例的默认断言。
- 真实 UUID/隔离根/安装快照不构成运行证据；P0 隔离证明与 S8 部署就绪的 profile 未确定前记 UNVERIFIED。

### 1.3 已有资产与拟新增

| 资产（相对 M 仓） | 当前作用及限制 | 本轮处理 |
|---|---|---|
| `server/internal/governance/execution_*` | 643–647 的 grant/verifier/claim/binding 实现与测试 | 复用为前置，不重写；新用例只消费其真实记录 |
| `server/internal/daemon/execution_*` | daemon 授权安装、binding 端点与 client | 复用传输/认证主体；新增 execution-control 端点 |
| `server/migrations/64{3..7}_*.up.sql` | 既有 5 张 `cr_execution_*` 表 | 648 迁移专例的受保护数据夹具 |
| `scripts/aifi45-db/run.mjs` | nonce 库入口 | 所有 DB 用例的唯一入口 |
| 新增 `server/internal/governance/execution_control_*` | 无 | 选择/reservation/store/facts/ingest/reader/merge-* |
| 新增 `server/internal/daemon/execution_control_*` | 无 | worker/recovery/observer/deployment/launch |
| 新增 `server/internal/service/execution_channel_task_tx_test.go` | 无 | `TestChannelTaskTx` 承接 `task-tx` 模板 |
| 新增 `cmd/server/execution_control_composition_test.go` | 无 | `TestChannelComposition` 与 `TestChannelCompositionReadiness` |
| 新增 `scripts/aifi45-verify/channel-evidence.mjs`（+ `.test.mjs`） | 目录现只有 `posix-daemon.sh` | 只读证据校验：按冻结名单核真实非 skip PASS leaf |
| `validation/channel-test-expectations.json`（本 change） | SPEC 阶段已冻结，未运行 | 跨仓唯一 leaf 名单；tools 侧引用，不另存副本 |

## 二、详细测试案例

### 功能 1：可信选择与冷启动（REQ-VC-001/002）

#### 案例 1.1 — strict selection 不降级

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-001 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-001 |
| **优先级** | P0 |
| **预置条件** | 隔离库已有 Strict selection；另有 legacy 目录证明夹具与缺失 selection 夹具 |
| **输入** | 分别删除/改空/改写 trigger 合同字段与 `cr.md` 字段，再解析 selection |
| **预期结果** | strict 得 `T_VERDICT_BINDING_MISMATCH`；Unknown/读失败拒绝新增 effect；legacy 只按目录证明 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.2 — control reservation 不可执行

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-002 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-002 |
| **优先级** | P0 |
| **预置条件** | 已建 selection 与 reservation，候选 task UUID 未入队 |
| **输入** | 尝试 claim reservation；随后由 T permit 触发真实 enqueue |
| **预期结果** | reservation 不可 claim/不可执行且不出现于任务队列；permit 后只出现固定候选 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.3 — 同 Tx root+task+settlement

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-003 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-003 |
| **优先级** | P0 |
| **预置条件** | 合法 source 与固定 ID；注入 commit 后通知与 rollback 两个分支 |
| **输入** | 执行 `AdmitDispatchRootTx`/`EnqueuePipelineTaskTx`；再以同 ID 逐字段不同 payload 重试 |
| **预期结果** | commit 得唯一 root/task 且只在 commit 后通知；rollback 零新增零通知；同 ID 异字段被拒 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.4 — adoption 终态竞争

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-004 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-004 |
| **优先级** | P0 |
| **预置条件** | `ValidationTestHook` 内另连接 `lock_timeout=300ms`；另有顺序用例夹具 |
| **输入** | 原事务推进 root adoption 时并发改同一 logical root 终态 |
| **预期结果** | 并发写入只认 SQLSTATE `55P03`；存在无锁冲突正对照；已终态根不被 adopt、终态后不重建同逻辑根 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施）；green 前置为 AIFI-45 G5 已修 |

#### 案例 1.5 — FreshWork 注册

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-005 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-005 |
| **优先级** | P0 |
| **预置条件** | 可信 intake 来源记录；含别名/重开映射与未知项 |
| **输入** | 首次注册、同 origin 换 CR 再注册、来源不可读时注册 |
| **预期结果** | 只有 NEW 且 unresolved 为空可出 selection；同 origin 第二次被拒；不可读得 UNKNOWN；追加 proof 不改历史 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 2：wire 与信任根（REQ-VC-003）

#### 案例 2.1 — purpose/domain/scope

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-006 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-006 |
| **优先级** | P0 |
| **预置条件** | 合法 command/verdict 原字节与四组错用变体 |
| **输入** | 调用 `VerifyEnvelope` 验签 |
| **预期结果** | 仅三元组完全匹配通过；缺字段与未知字段不产生授权事实 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 2.2 — 跨语言原字节向量

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-007 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-007 |
| **优先级** | P0 |
| **预置条件** | Go 与 Node 各自生成向量与签名 |
| **输入** | 双向验证对方原始字节并比较 digest |
| **预期结果** | 双向通过且 digest 一致；任侧重序列化即失败 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 2.3 — exact keys 与 key-purpose

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-008 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-008 |
| **优先级** | P0 |
| **预置条件** | trust manifest 含 attestation/human key；含重复键与 union 双分支变体 |
| **输入** | 越用途签名、重复键、manifest 指向 agent 可写路径 |
| **预期结果** | 全部拒绝；只接受绝对路径+原始 SHA256 pin 的 exact keys；禁 agent enrollment |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 3：受保护 store 与状态机（REQ-VC-004/005）

#### 案例 3.1 — 唯一性与重放

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-009 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-009 |
| **优先级** | P0 |
| **预置条件** | 同一 request 的并发写入夹具 |
| **输入** | 并发写、原字节重放、rollback 后重投 |
| **预期结果** | request 与 store/epoch/seq 唯一；重放返原记录与原 bytes；回滚无残留 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.2 — 帧链 digest

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-010 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-010 |
| **优先级** | P0 |
| **预置条件** | 合法帧链与断链/跳号/占位签名变体 |
| **输入** | 入库校验并与 cursor `last_digest` 比对 |
| **预期结果** | 断链、跳号、占位签名一律拒收且不推进 cursor |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.3 — cursor 与 fence

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-011 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-011 |
| **优先级** | P0 |
| **预置条件** | 已有 open command；旧 owner 持旧 fence |
| **输入** | 发起第二 command、旧 fence 写操作 |
| **预期结果** | 行锁+CAS 拒绝第二 command；旧 fence 不执行新操作 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.4 — 状态机与 ACK

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-012 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-012 |
| **优先级** | P0 |
| **预置条件** | command 处于 created/issued/result_ready/settled/uncertain；另有 verdict 篡改尝试 |
| **输入** | 推进状态、取消、ingest ACK、UPDATE/DELETE/TRUNCATE |
| **预期结果** | 只允许受限转换；uncertain 冻结；ACK 不释 slot；verdict 不可篡改 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.5 — 撤销排序

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-013 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-013 |
| **优先级** | P0 |
| **预置条件** | 撤销与 effect 提交两种交错顺序；部分仓已发布夹具 |
| **输入** | 旧 permit 继续尝试产生效果 |
| **预期结果** | 撤销先提交→`no_effect`；effect 先提交→不追溯；撤销不等待 slot；部分发布保留 journal/receipt 转人工 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.6 — stop 排序

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-014 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-014 |
| **优先级** | P1 |
| **预置条件** | 前一 effect 未 settlement；已提交 effect |
| **输入** | 发送 stop 指令 |
| **预期结果** | 按 T sequence 生效；前一 effect settled 后才发后续；不越序撤销 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 4：恢复（REQ-VC-006）

#### 案例 4.1 — 恢复表

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-015 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-015 |
| **优先级** | P0 |
| **预置条件** | tail 相同/恰领先一项/M 已 settled/journal prepared/缺失分叉五类夹具 |
| **输入** | 执行 `ReconcileOwnerTx` |
| **预期结果** | 每类给出固定动作；freeze 不猜未消费、不清 slot、不建空 store |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.2 — restart 与 fence

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-016 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-016 |
| **优先级** | P0 |
| **预置条件** | 普通 restart、key rotation、旧 fence worker、缺 checkpoint |
| **输入** | 恢复 worker 并继续服务 |
| **预期结果** | epoch/seq 不变且重发原 bytes；新 key 只签新 verdict；旧 fence/缺 checkpoint 不接单 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 5：facts、repair 与 sensitive action（REQ-VC-007）

#### 案例 5.1 — facts 来源

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-017 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-017 |
| **优先级** | P0 |
| **预置条件** | 已验签 grant 与未验签记录各一份；解码 payload 自带额度 |
| **输入** | repair admit 走 `ResolveFactsTx` |
| **预期结果** | 只用已验签 facts；未验签拒；额度不来自 payload；无 Go 预算分支 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 5.2 — repair 追加

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-018 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-018 |
| **优先级** | P0 |
| **预置条件** | 追加请求含新增仓库；并发两份追加；原请求重放 |
| **输入** | 处理追加授权 |
| **预期结果** | 只扩额度不扩仓库；CAS 只接受一份；重放返原结果 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 5.3 — signed resume

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-019 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-019 |
| **优先级** | P0 |
| **预置条件** | 合法/越权 resume；revoked 与 terminal root；重复调用 |
| **输入** | 执行 resume |
| **预期结果** | 绑定 stop_ref/subject/epoch 且只消耗一次；不复活 revoked/terminal |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 5.4 — sensitive action

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-020 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-020 |
| **优先级** | P0 |
| **预置条件** | 精确 target/environment 夹具；复制安装根后新 operation；撤销交错；旧账本不可核实 |
| **输入** | 执行专项动作 |
| **预期结果** | 只允许 exact target；新 operation EXHAUSTED 且原计数不变；重放原 receipt；交错时 no_effect；旧账本拒 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 6：ingest、settlement 与 binding（REQ-VC-008）

#### 案例 6.1 — 重送与丢响应

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-021 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-021 |
| **优先级** | P0 |
| **预置条件** | T commit 后 M rollback；M effect commit 后 response 丢失 |
| **输入** | 重发原 bytes、重试结算 |
| **预期结果** | 返回与首次相同结果；已 settled 只返原 mapping；不退款 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 6.2 — ACK 与 no_effect

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-022 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-022 |
| **优先级** | P0 |
| **预置条件** | ACK 分支；pending/deny/stopped；permit 过时/撤销 |
| **输入** | 后续尝试产生 effect |
| **预期结果** | ACK 不释 slot 不发 task；上述判决结算 no_effect；未知不推断未消费 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 6.3 — 启动前全量匹配

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-023 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-023 |
| **优先级** | P0 |
| **预置条件** | 真实 task/runtime/dispatched_at/daemon generation；643–645 记录一致与不一致夹具 |
| **输入** | task-start preflight 后尝试启动 |
| **预期结果** | 不一致或未完成不启动；binding 不二次消费 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 6.4 — challenge 与终态竞争

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-024 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-024 |
| **优先级** | P0 |
| **预置条件** | 跨签发 challenge、旧 dispatched_at、同 nonce 异 proof、claim 后转终态夹具 |
| **输入** | 尝试写入消费或 activation |
| **预期结果** | 全部拒绝；终态后写入由 `55P03` 证明被锁阻止 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施）；green 前置为 AIFI-45 G1/G2/G4 残余 |

### 功能 7：reader 与 fence（REQ-VC-009）

#### 案例 7.1 — 无 committed T

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-025 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-025 |
| **优先级** | P0 |
| **预置条件** | ACK/平台 receipt/伪 Git pass 三种伪证据；已 settled 与未 settled 夹具 |
| **输入** | 调用 `ReadCommitted` 与 `SettleCandidateTx` |
| **预期结果** | 零 root/task；重复 settle 返原 mapping；未 settled 不接受换候选 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 7.2 — strict fence 依据

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-026 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-026 |
| **优先级** | P0 |
| **预置条件** | Strict 删字段、目录缺行/读失败、已证明 legacy 三套夹具 |
| **输入** | 执行 strict fence 判定 |
| **预期结果** | 删字段仍 strict；Unknown 不降 legacy；legacy 行为不变 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 7.3 — 终态 fence 并集

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-027 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-027 |
| **优先级** | P0 |
| **预置条件** | `fence_required` 两种来源；重领换 generation；读失败；STOP_NEW 期间收尾 |
| **输入** | 在终态事务内持行锁判定并写入 |
| **预期结果** | 缺 claim 409；重领仍 409；读失败拒；两字段皆缺且 `fence_required=false` 才走旧路径 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 8：迁移（REQ-VC-010）

#### 案例 8.1 — up/down/reapply

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-028 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-028 |
| **优先级** | P0 |
| **预置条件** | 空库、已 up、up→down、up→down→up 四种 nonce 库状态 |
| **输入** | 执行 648 up/down/reapply |
| **预期结果** | up 具 14 表与全部对象；down 全撤；reapply 恢复且无遗留业务行；每表至少一个 leaf |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 8.2 — 受保护数据

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-029 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-029 |
| **优先级** | P0 |
| **预置条件** | up 状态已建 643–647 夹具行与对象 |
| **输入** | 精确 648 down/up |
| **预期结果** | 原夹具行与对象不变；无 648 孤儿对象 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 9：merge-facts 端点（REQ-VC-011）

#### 案例 9.1 — 认证主体解析

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-030 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-030 |
| **优先级** | P0 |
| **预置条件** | 合法 MDT 凭据、他人 crID、PAT/JWT/task-token |
| **输入** | 调用 `GET /api/daemon/execution-control/merge-facts/{crID}` |
| **预期结果** | 他人 crID 404；回退凭据 403；认证先于资源查找；不接受版本参数 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 9.2 — 冻结行追加写

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-031 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-031 |
| **优先级** | P0 |
| **预置条件** | 已有一条当前行；再批准与撤销两支 |
| **输入** | 写 `code_source_freeze` |
| **预期结果** | 追加写并 supersede；撤销同事务置 `revoked_at`；不删行；部分唯一生效 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 9.3 — 响应闭集与绑定三态

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-032 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-032 |
| **优先级** | P0 |
| **预置条件** | 集合完整/多仓/少仓/替换 repo_id/摘要不符/三态绑定/部分 revoked 夹具 |
| **输入** | 生成并校验响应 |
| **预期结果** | 闭集字段与自洽 `repos_digest`；三态与 `head_revoked` 如实；易变字段不入摘要 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 9.4 — 失败码分层

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-033 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-033 |
| **优先级** | P0 |
| **预置条件** | 不可达/超时/5xx/400/未知 code/撤销/head 前移/越界与不可核实并存 |
| **输入** | 端点返回并由 CLI 映射外层码 |
| **预期结果** | 只用闭集非 200 码；优先级 `UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE` |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 10：merge-effects 端点（REQ-VC-012）

#### 案例 10.1 — reserve 事务

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-034 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-034 |
| **优先级** | P0 |
| **预置条件** | 预检冻结 base/head/候选写集摘要；撤销连接并发 |
| **输入** | 提交 `op=reserve` |
| **预期结果** | CR 行 `FOR SHARE` 串行；同事务重验四项；写 issued command；Tx 内无网络 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 10.2 — attempt 语义

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-035 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-035 |
| **优先级** | P0 |
| **预置条件** | 同 attempt 重放、前 attempt 已 settled、无未终结前 attempt、前 attempt 未终结 |
| **输入** | 提交 reserve |
| **预期结果** | 200 原结果 / 200 原 mapping / 201 新 command / 409 CONFLICT 四支互斥 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 10.3 — 码序与 effect 复用

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-036 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-036 |
| **优先级** | P0 |
| **预置条件** | 畸形请求、PAT+他人 crID、合法+他人 crID、不可用、head 前移且摘要不同、finalize push |
| **输入** | 提交 reserve/report |
| **预期结果** | 400/403/404/503/HEAD_MOVED 且非授权失败不写 halted；码序固定；finalize 为独立 `merge_publish` effect |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 11：部署就绪控制面（REQ-DR-001..004）

#### 案例 11.1 — 可信观测

| 字段 | 内容 |
|------|------|
| **ID** | TC-DR-001 |
| **对应 Spec** | deployment-readiness/spec.md → Scenario: SC-DR-001 |
| **优先级** | P0 |
| **预置条件** | 批准 profile；agent 可写安装根、env 自报、Git SHA、marker-only 四类伪观测 |
| **输入** | 采集快照并校验闭包 |
| **预期结果** | 自报值不作观测；缺失/空/损坏/删必需项不产生 READY；受保护观测为正对照 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 11.2 — inventory 全覆盖

| 字段 | 内容 |
|------|------|
| **ID** | TC-DR-002 |
| **对应 Spec** | deployment-readiness/spec.md → Scenario: SC-DR-002 |
| **优先级** | P0 |
| **预置条件** | 多实例含离线旧副本；滚动更新场景 |
| **输入** | 生成 snapshot 并递增 generation |
| **预期结果** | 覆盖全部合格实例；离线实例先撤销或核实；旧 verdict 因 generation 失效 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 11.3 — readiness 结果类型

| 字段 | 内容 |
|------|------|
| **ID** | TC-DR-003 |
| **对应 Spec** | deployment-readiness/spec.md → Scenario: SC-DR-003 |
| **优先级** | P0 |
| **预置条件** | `verify-channel` 正例；`strict-production` 缺 AdmissionDecider |
| **输入** | 持久化 readiness 结果并尝试用于 activation |
| **预期结果** | READY_COMPONENT 不得用于生产 activation；strict 缺 decider 必 NOT_READY；结果不可改 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 11.4 — 原子启停

| 字段 | 内容 |
|------|------|
| **ID** | TC-DR-004 |
| **对应 Spec** | deployment-readiness/spec.md → Scenario: SC-DR-004 |
| **优先级** | P0 |
| **预置条件** | 并发启用、签后变代、response 丢失、nonce 重放、DB 失败 |
| **输入** | `ActivatePolicyTx`/`StopNewAdmissionsTx` |
| **预期结果** | 同一 CAS/锁点原子推进；STOP_NEW 固化边界不改历史/预算；generation 不归零 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 11.5 — 退役

| 字段 | 内容 |
|------|------|
| **ID** | TC-DR-005 |
| **对应 Spec** | deployment-readiness/spec.md → Scenario: SC-DR-005 |
| **优先级** | P1 |
| **预置条件** | 旧 run 存活、未知未决任务、签发后新增 legacy 工作、work revision 漂移 |
| **输入** | `BeginLegacyDrainTx`/`FinalizeLegacyRetirementTx` |
| **预期结果** | 未纳管 writer 或未知未决时不出 drain 证明；revision 漂移拒 RETIRED |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 11.6 — strict 启动 fence

| 字段 | 内容 |
|------|------|
| **ID** | TC-DR-006 |
| **对应 Spec** | deployment-readiness/spec.md → Scenario: SC-DR-006 |
| **优先级** | P0 |
| **预置条件** | issued 请求在 STOP_NEW/过期后恢复；新候选/换 origin；preflight 与 execute 之间换代 |
| **输入** | `CheckDeploymentAccessTx` 与 `PrepareLaunch`/`CommitLaunch` |
| **预期结果** | 原 issued 精确恢复；新候选/换 origin 拒；换代只能拒绝或加载原固定快照 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 12：P0 隔离证明（REQ-VC-013）

#### 案例 12.1 — daemon 侧登记进程身份

| 字段 | 内容 |
|------|------|
| **ID** | TC-VC-037 |
| **对应 Spec** | verdict-channel/spec.md → Scenario: SC-VC-037 |
| **优先级** | P0 |
| **预置条件** | 获授权 Linux 与 Windows 测试机、批准 profile（两个真实受限身份、受审核 launcher、私有根与 pin） |
| **输入** | 自报 pid/root、他 run 连接、fd 转移、PID 复用；Windows 命名管道他 run 连接与自报值 |
| **预期结果** | 只用 daemon 登记事实；自报值被忽略；树外/他 run 连接被拒；两平台各自出证，缺一 UNVERIFIED |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施）；环境未获授权前不可执行，不以组件 PASS 替代 |

## 三、追溯矩阵

| Requirement | Scenario | 顶层测试 | 必达 leaf（摘要，权威见 expectations.json） |
|---|---|---|---|
| REQ-VC-001 | SC-VC-001/002 | TestChannelFoundationSelection、/Reservation | selection 不可降级、control reservation 不可执行 |
| REQ-VC-001 | SC-VC-003/004 | TestChannelFoundationReservation | fixed_id_conflict_and_rollback、root_adoption_terminal_race |
| REQ-VC-002 | SC-VC-005 | TestChannelFoundationFreshWork | 同 origin 拒第二次、UNKNOWN 不出 selection |
| REQ-VC-003 | SC-VC-006..008 | TestChannelProtocol | purpose_domain_scope、cross_language_vectors、exact_keys |
| REQ-VC-004 | SC-VC-009..012 | TestChannelStoreState | request_unique_replay、frame_chain_digest、cursor_single_open、state_machine_and_ack、verdict_immutable |
| REQ-VC-005 | SC-VC-013/014 | TestChannelStoreState | revoke_ordering、stop_ordering |
| REQ-VC-006 | SC-VC-015/016 | TestChannelRecovery | 恢复表五类、restart_keeps_epoch |
| REQ-VC-007 | SC-VC-017..020 | TestChannelPolicyFacts、/Resume | repair_admit_fact_refs_verified、repair_extension_*、signed_resume、sensitive_* |
| REQ-VC-008 | SC-VC-021..024 | TestChannelIngestSettlement、/Binding | ack_no_slot_release、cross_issuance_challenge、same_task_redispatch_challenge、same_nonce_different_proof、claim_terminated_before_consume |
| REQ-VC-009 | SC-VC-025..027 | TestChannelReader | 缺 T 零派发、selected_strict_field_deleted、unknown_selection_not_legacy、never_selected_legacy_unchanged、terminal_report_without_claim、terminal_fence_survives_reclaim、legacy_consumed_keeps_fence、terminal_fence_read_failure |
| REQ-VC-010 | SC-VC-028/029 | TestChannelMigrationAfterUp/Down/Reapply/ProtectedData | 14 表逐表 leaf、受保护数据不变 |
| REQ-VC-011 | SC-VC-030..033 | TestChannelMergeFacts | authn_workspace、reject_fallback_credentials、source_freeze_append_only、response_closed_set、current_binding_tristate、failure_code_layering |
| REQ-VC-012 | SC-VC-034..036 | TestChannelMergeEffects | reserve_shared_lock、attempt_semantics、code_order、non_auth_failure_no_halt |
| REQ-DR-001 | SC-DR-001/002 | TestChannelDeploymentObserver | 自报值不作观测、inventory_all_instances、generation_supersedes |
| REQ-DR-002 | SC-DR-003 | TestChannelReadinessProtocol、TestChannelReadinessComponentBoundary | READY_COMPONENT 不得启用生产 |
| REQ-DR-003 | SC-DR-004/005 | TestChannelPolicyActivation、TestChannelReadinessRetirement | CAS 原子、drain/retire 反例 |
| REQ-DR-004 | SC-DR-006 | TestChannelDeploymentAccess（governance）、TestChannelDeploymentLaunch（daemon） | issued 精确恢复、换代只拒或原快照 |
| REQ-VC-013 | SC-VC-037 | TestChannelIsolation（daemon，Linux/Windows 分别） | peer_credential_match、self_reported_fact_ignored、foreign_run_socket、fd_transfer、pid_reuse、windows_* 三条 |

## 四、执行矩阵与未验证声明

| 模块 | 单元 | 隔离集成 | E2E | 状态 |
|---|---|---|---|---|
| selection/reservation/root | 部分 | 真实 DB Tx | 否 | 未实施 |
| 协议与 store | Go↔Node 向量 | 真实 store/文件故障注入 | 否 | 未实施 |
| ingest/binding/settlement | 否 | 真实 daemon+DB | 需 AIFI-45 业务链 | 未实施 |
| merge-facts/merge-effects | 否 | 真实 HTTP+DB | 需 tools CLI 联调 | 未实施 |
| 迁移 | 否 | nonce 库 up/down/reapply | 否 | 未实施 |
| D7 部署就绪 | 部分 | 真实 Tx + 隔离夹具 | 真实 strict 正例归 AIFI-45 下游 | 未实施 |

- 本仓 43 个 TC **全部未实现、未运行**；本文件不提供任何通过率。
- 部署/启用/真实 CR 均未发生；P0 与 S8 的 profile/实例清单在 Gate 2 后由实施授权确定，未定前记 UNVERIFIED。
- 通道组件通过不自动回填 AIFI-45 的 41/49；`TC-RUN-001/002/003/006/007/010` 的重跑前置见 deliver 产物。
