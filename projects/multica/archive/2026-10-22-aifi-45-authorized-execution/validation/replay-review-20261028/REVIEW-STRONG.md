## 本次受限 verdict：**BLOCK（静态审查），不是 Gate3**

写前验签和签名主体绑定已有实质加强，但**不能据此宣称整体生产 PASS**。以下为源码推演，未运行测试或数据库验证。

### 1. 快照一致性

已先读取指定 `source-manifest.json`，按 checkout **原始字节**计算 SHA-256：

- `multica_checkout_sha256`：**12/12 一致**
- `change_checkout_sha256`：**10/10 一致**
- 未发现所列文件缺失或 SHA 漂移。

限制：这是**核对当时**的结果，未做结束时第二次核对；未核验 manifest 中三个仓的 HEAD，也不代表未列文件被冻结。以下 `G/`、`D/`、`S/` 分别指 `../multica/server/internal/governance/`、`internal/daemon/`、`cmd/server/`。

## 2. 发现

### F1 — P2：验签之后等待锁，过期后仍能首次提交

**位置：**
- `G/execution_control_store_state.go:156–159`：command 先验签，再等待 lineage 锁。
- 同文件 `:399–403, :441–472`：verdict 先验签，再等待 cursor 锁、写入。
- `G/execution_control_protocol.go:389–395`：有效期按验签时传入的时间判断。

**可复现交错：**

1. 可信 key 在时间 `E` 到期；T1 持有目标 lineage/cursor 锁。
2. T2 在 `E−ε` 调用 writer，签名及有效期检查通过。
3. T2 等锁直至 `E+ε`。
4. T1 提交；T2 锁后只重新查询 replay/链状态，**没有重新检查有效期**，首次插入成功。

这不需要攻击者替换 manifest 或时钟；即使调用方完全可信，锁等待仍能造成该时序。它违反 hardening 文档提出的“锁后读取有效期、使用等待后的实时时钟”要求。当前没有生产接线，**不能据此宣称已有外部利用路径**。

**测试检测能力：不足。**现有两个 concurrent exact replay 测试检测等待与重放，但 key 有效期长达一小时，没有跨到期点的 barrier。

### F2 — P2：精确历史重放被当前 key 有效期阻断

**位置：**
- `G/execution_control_store_state.go:156` 在 command replay 查询 `:164–181` 之前验签。
- 同文件 `:399` 在 verdict replay 查询 `:405–437` 之前验签。

**可复现时序：**

1. 在 key 有效时成功提交请求 R。
2. key 到期后，以完全相同的 payload、envelope 和不可变字段重试 R。
3. writer 在读取已提交记录之前返回 key expired，不能返回原记录。

这与文件顶部 `:4` 的“重复提交返回原字节，不重算”及恢复重放承诺存在冲突。它是**恢复可用性/合同问题，不是越权放行**。若设计本意是“历史重放也必须满足当前 key 策略”，须明确修改合同并说明恢复办法；不能同时承诺无条件原记录重放。

**测试检测能力：不足。**精确重放均在 key 未过期时完成。应区分“首次写入过期拒绝”与“已提交历史记录查询”，不能简单取消首次写入的有效期检查。

### F3 — P2：不同 lineage 的同 request 并发，冲突语义不稳定

**位置：**
- command：`G/execution_control_store_state.go:159–181, :198–207`
- verdict：同文件 `:405–437, :441–472`
- `server/migrations/648_cr_execution_control.up.sql:76, :134`：request 全局唯一约束。

**可复现交错：**

1. T1、T2 使用相同 request UUID，但分别持有合法签名、不同 lineage 的输入。
2. 两者 replay 查询均看不到对方未提交的记录。
3. lineage/cursor 锁不同，锁后二次查询也可能均无记录。
4. T1 插入；T2 在唯一索引处等待。
5. T1 提交后，T2 得到 **23505**，而不是 `ErrControlStoreConflict`；事务进入失败状态。

串行提交同样的冲突输入会得到应用层 Conflict；并发时却得到数据库错误。唯一约束保护了数据，**没有证明能双写或泄漏原记录**，但不满足一致的 request 冲突接口语义。

**测试检测能力：不足。**现有并发用例只覆盖同 request、同 lineage、完全相同输入；未覆盖上述不同 lineage 交错。

## 3. 已核实有效的防线

- verdict 验签发生在 INSERT 前；核对可信 key purpose/domain/scope，并逐字节比较被签 payload。
- 签名主体绑定 `request_id`、`epoch`、`sequence`、`previous_verdict_digest`；首帧前驱缺失/null 被拒绝。
- verdict replay 比较 ID、scope、lineage、store、epoch、seq、前驱、payload、envelope、digest、commit/receipt ref，并返回**数据库中的 ID/digest**。
- cursor 锁后二次 replay 查询，能处理 **READ COMMITTED、同 cursor 的精确并发重放**；现有测试确实观察锁等待，而非只靠 sleep。
- command 的 lineage advisory 锁对 UUID 使用 PostgreSQL 规范化文本，大小写变体不会拆成两把锁；入口明确拒绝非 READ COMMITTED。
- `COALESCE` 对空前驱/receipt 的处理与 INSERT 的 `NULLIF` 对应。未发现这里通过 SQL NULL 绕过比较的路径。
- envelope 是 **JSONB 结构相等**，不是原始信封字节相等；规格已明确承认这一限制，不另报为新缺陷。
- 未发现当前 replay 返回其他 lineage 原记录内容的直接路径；跨 lineage 不一致字段会拒绝或撞唯一约束。

## 4. RUN003：真实桥接成立，但只成立于受限测试前提

`S/execution_run_003_test.go` 确实覆盖：

- 真实授权路由、真实 daemon ACK；
- ACK/consumption/settlement/伪签名拒绝的分阶段等待；
- 真实 verdict writer → AdmissionDecider → Runner → 路由构造的 TaskService；
- 最终任务的 node-run、executor、issue 归因及重复 wake 保持同一 task ID。

因此不是“永远走不到派发路径”的空绿测试。

但它的可信前提明显由 fixture 提供：

- consumption、settlement、cursor 直接 SQL 构造；
- 测试临时生成 key，并直接提供 manifest/scope；
- settlement 的 `effect_ref` 是 `{}`；verdict payload 只有最低主体字段；
- 直接调用 writer 和 `WakeGrant`，没有经过真实 producer/ingest、实际 daemon 子进程或 periodic 调度链。

此外，文件顶部称“每阶段均检查 human gate”，实际 human gate 检查位于最终派发后；不能把这句描述当作每阶段断言证据。

**结论：RUN003 支持受限组件桥接证据，不支持完整可信生产闭环。**

## 5. 明确开放边界，不冒报为已暴露漏洞

以下已由 hardening 文档声明，必须阻断生产启用，但不等于已经发现对外可利用入口：

- caller-supplied `Manifest`、`AttestationScope`、`Now`；
- 完整 B、权威实体/当前 generation 与授权关联未闭合；
- cursor 的 frozen、owner/fence、open-request 归属未由底层 append 完整验证；append 会无条件清空 `open_request_id`；
- Go payload digest 与 Node frame digest 的互操作；
- producer/ingest 尚未接线。

静态调用搜索确认：`ControlWorker.ApplyTx` 调用 append，但未见其生产调用方。因此判定器与 producer/ingest 必须成对审批、接线，不能单独开启。

## 6. 本次未检查

- 未运行任何测试、变异、并发复现、数据库查询、迁移或真实 CR。
- 未验证历史测试日志、skip 数、环境隔离及清理证据真实性。
- 未核验运行中服务、密钥配置/权限、安装版本及实际生产路由。
- 未完成原始 M003 全部合同与历史版本的逐条对照；上述合同冲突仅依据已读 writer 承诺、当前规格和 hardening 文档。
- 未完整审查 settlement、policy、reservation、恢复 worker、全部 Runner/TaskService 路径及完整锁图。
- 未审 Node 实现及跨语言向量，不能判断摘要兼容。
- manifest 中部分测试、台账及既往评审文件仅核 SHA，未逐行审阅；未借用既往评审 verdict。
- 未核验 HEAD、全工作树变更清单或审查结束时漂移。

**最终判断：快照所列 SHA 核对一致；验签/主体绑定的最低防线有实质证据，但存在上述时序与并发合同问题，且生产可信链仍开放。本次维持 BLOCK，不是 Gate3，也不是整体生产安全结论。**