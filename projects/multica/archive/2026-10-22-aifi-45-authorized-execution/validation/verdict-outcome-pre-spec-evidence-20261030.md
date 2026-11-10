# Verdict outcome：Gate1 后、SPEC 前的只读证据

## 范围与状态

用户对 multica/tools 两侧 proposal 和 canonical 的原话是“审阅确认”；两侧 Gate1 已登记、阶段已推进至 SPEC，Gate2/3 仍 pending。审阅快照和自动重渲染说明见 `verdict-outcome-ray-review-request-20261030.md`。

流程遗漏：提交 Gate1 时未展示并确认执行模式。两侧原先 `.stdd.yaml` 的 `mode: standard` 为初始化默认值，`complexity_score` 和 `score_confidence` 均为空，不应冒充用户已选模式。随后建议两侧使用 `thorough`：本变更涉及高风险授权、签名安全和跨仓数据契约，按各自 `config.d/lite.yaml` 估计分别为 4 + 3 + 2 = 9 分，达到 8 分阈值；文件数与行数尚未估计，实际是否变更 wire 尚未决定，因此只是初步建议，不是完整评分。

用户回复“确认采用 thorough，全自动长程模式”；两侧 `.stdd.yaml` 均按确认选择改为 `mode: thorough`，复杂度分数仍未填。用户表达的长程执行意向须在 Gate2 后按原生流程处理，不能替代 Gate2 确认，也不解除已有 HOLD、真实审批及资源操作边界。

两项定向源码调查使用原生只读 explore 子代理，请求 `step/step-5-preview:max`；实际 backend 无回执，记为 unknown。仅静态阅读，无测试、数据库、服务、容器或真实凭据操作。以下关键结论经协调者复核源码；不代表现网或历史数据。

## 已核静态事实

1. tools `skills/shared/crctl/scripts/lib/execution-control-protocol.mjs`：`verifyControlEnvelope` 对 envelope、purpose、domain、scope 和签名原字节做验证，返回解析 payload；签名认证原字节不自动赋予任一额外字段业务授权语义。前像为 `domain || NUL || payloadBytes`；store 文件头明确帧 digest 不认证历史，且 store 本身不验签。
2. tools 的 `test/fixtures/control-vectors.json` 中一个 verdict 向量的 payload 包含 `verdict: permit`、`seq`、`request_id`。这是测试向量事实，不是已批准的完整生产结果合同，也不是实际执行 effect 的证明。
3. multica `server/internal/governance/execution_control_store_state.go` 的 `verifyVerdictSubject` 要求已签字段 `request_id`、`epoch`、`sequence`、`previous_verdict_digest` 对应输入帧；上述 tools 测试向量没有其中后三个字段（其使用 `seq` 而非 `sequence`）。因此**该示例不能直接作为满足 `verifyVerdictSubject` 帧入库要求的证据**；基础 envelope 互操作通过也不能代替端到端帧写入与授权语义测试。是否还有其他合法向量、生产格式或适配路径，仍需完整核查。
4. multica `execution_control_settlement.go` 对已有结算先原样重放；撤销先于本次结算时可把调用方输入的 effect 降为 no_effect。`execution_admission.go` 当前查询把结算 `kind='effect'`、关联 verdict 和已覆盖的 cursor 当作可信计数；注释明确该查询不确立 manifest 来源、不重验签或结算权威，并称 request ID 与消费 task ID 对应及生产 wiring 待验证。
5. `execution_control_settlement.go:157-179` 的撤销重读实际对 `pgx.ErrNoRows` 返回 `false, nil`，决策为 nil 时也返回 false；`SettleControlCommandTx` 仅在返回 true 且输入为 effect 时降为 no_effect。函数上的注释与调用处“链缺失不猜”的注释不能证明缺链时拒绝。此为源码静态发现，不证明现网可达或完整事务已放行；当前代码、既有合同与所需失败关闭行为须进一步评审。
6. 当前非测试 Go 源文件里有多处向 `cr_execution_control_settlement` 插入的 SQL：`execution_channel_admission.go:192`、`execution_control_policy.go:219,301,370`、`execution_control_settlement.go:140`、`execution_merge_effect.go:217`。不能仅检查 `SettleControlCommandTx` 就断言全部结算入口被覆盖；各写入者的前提和真实可达性仍待逐项核查。
7. 两仓按项目语言运行 `stdd experience list --language ... --format json`，分别返回空数组。`extract-proposal` 为两侧各提取一个 `verdict-channel` capability；该 CLI 输出未展示 canonical 中的 constraints/non_goals，后续仍须直接读取已确认 canonical。

## 未知及禁止推断

真实生产者、私钥持有者、权威 manifest 来源、签发时机、存量与部署均未获权威确认；源码未发现调用方不等于生产不存在。`permit` 与实际 effect 是不同事实，不能仅凭 fixture、签名或调用方 `settlement.kind` 推断可信放行。签名字段/version 是否变化、兼容/冻结和恢复策略均待设计和人审。AIFI-45 既有实际入口、代次、锁、RUN 与 Gate3 验收不会因本 change 被替代。

## 复核快照（raw SHA-256）

| 相对仓路径 | SHA-256 |
|---|---|
| tools `skills/shared/crctl/scripts/lib/execution-control-protocol.mjs` | `345eaa6037fc36a2eb5a40243581e78a4578ca18a30018032785d877f8ad38d8` |
| tools `skills/shared/crctl/scripts/lib/execution-control-store.mjs` | `1533dffc3206b8cd3a50119652efa62c49c195a24c328c19c35b864b6bab6a69` |
| tools `skills/shared/crctl/scripts/test/fixtures/control-vectors.json` | `51f1634ec2a83ed1a8461f3843ed2b3c1500dc2f7071f6619ef8b6c0b7f7d8f1` |
| multica `server/internal/governance/execution_control_store_state.go` | `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f` |
| multica `server/internal/governance/execution_control_settlement.go` | `1a6c8072e068462b2e6c79fefa253ff1936a1da812dbfa94c25a7440da749311` |
| multica `server/internal/governance/execution_admission.go` | `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e` |
| multica `server/internal/governance/execution_channel_admission.go` | `3fff5e31721a4b4da4f8d8f30781cbd96e95feda0ef2ca751471fb2529c04b6e` |
| multica `server/internal/governance/execution_control_policy.go` | `b36c6480da8bf3325df0fe66a399efda0538f6dacdfeda01fe24878d69bfe86b` |
| multica `server/internal/governance/execution_merge_effect.go` | `7ced7b43f560289cd2cbc427e1fea3db7d88edb39aa0f8bb6a97e323c3f87679` |
| multica `server/internal/governance/execution_channel_reader.go` | `ad7e0e6078bdb32a28be927457b4c1af74f473d77e426d4bef94c26ccedd55e5` |
| multica `server/internal/governance/execution_authorization_routes.go` | `36b084498c4bcd40563c88e869a953c302d7406ecdd8bb53d4225790f27b956d` |
| multica `server/internal/governance/execution_sensitive_action.go` | `92a2111fd7c258b8fbd767009cb09cc63459e87ee2a092cd18603a06625013cf` |
