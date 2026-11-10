# Verdict 结果契约静态分析

**性质**：独立 explore 审阅的源码分析，由协调者整理；未进行攻击复现、数据库、容器或真实 CR 操作。只针对以下 SHA 快照，不推断生产部署、数据库存量或其他调用方式。19 个精确字节副本位于 `verdict-outcome-source-20261029/`。请求模型不证明实际 backend；无 backend receipt。

## 发现

- `multica/server/internal/governance/execution_control_store_state.go:354-399` 验签入库时绑定签名字节与 request、epoch、sequence、前序摘要及调用方提供的 scope，但不验证可信结果的语义。签名覆盖原 payload 字节不等于每个未知字段都可成为授权事实。
- `execution_control_settlement.go:31-69,72-148` 的 `Kind` 由调用方提供，形状校验不把 verdict 的经认证结果与 effect 绑定；已撤销时可将 effect 降为 no_effect（`:109-120`）。`execution_admission.go:181-185` 查询 `s.kind='effect'`，并不读取判定结果。它把 request ID 与 consumed task ID 相等作为尚待核实的假设（`:151-154`）。
- 归档的 canonical verdict 文档未给出完整 verdict 字段表；归档 `specs/verdict-channel/spec.md:54`（SC-VC-006）规定未知字段不产生授权事实。先前设计输入提出 `disposition` 等字段，但该输入不是已批准字段契约。不能简单因载荷额外携带一个字段就将其认作授权凭据。
- 已检查源码中未找到 `SettleCandidateTx` 和 `ControlWorker.ApplyTx` 的生产调用方，也未找到所述 ingest 路由；main 未注入 decider，当前源码启用 runner 会退出。**这不是对部署和数据库的证明**。如果未来错误地把调用方自报 kind 或仅有 verdict 当作可信 effect，可能构成错误放行；本次未证明现实可利用路径，也没有签名 deny 的现成反例。
- readiness 是独立缺口：归档契约要求结果入签名，而 `execution_policy_readiness.go:241-273` 保存输入、`execution_deployment.go:73-126` 按明文 JSON 读取；如何接可信验签及其部署事实待专门复核，不能从此静态分析直接声称可安全投入生产。

## 分流

消费侧必须默认拒绝无法认证的结果，且另核 request/lineage、可信 manifest 来源、代次和锁；不能仅靠消费侧空值检查证明正向授权。涉及既有签名契约的待判定问题已在 multica/tools 同 ID `2026-10-29-trusted-verdict-outcome-binding` **草案**中登记，草案负责人为 Ray（不据此推定实际签发主体），Gate pending；是否必须扩展契约仍须评审。`v2`、签名 disposition、command digest 等均只是候选，不是批准方案；须先确认结果真实来源、签发主体、现网与历史存量、兼容和恢复。该草案不替代 AIFI-45 的 RUN 验收。此段记录分析时状态；后续 Gate1 用户确认与快照见 `verdict-outcome-ray-review-request-20261030.md`，不改变上述事实不确定性。

## 原始 SHA-256

以下 `M:` 相对 sibling `multica/server/`；`T:` 相对 sibling `tools/`；`W:` 相对本工作区 `projects/`。

| 文件 | SHA-256 |
|---|---|
| M:internal/governance/execution_control_store_state.go | `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f` |
| M:internal/governance/execution_control_settlement.go | `1a6c8072e068462b2e6c79fefa253ff1936a1da812dbfa94c25a7440da749311` |
| M:internal/governance/execution_control_protocol.go | `f808f2e4d2b112467707f9f2a2aa45db4adb98988ec8b330b26b1d5758ef2641` |
| M:internal/governance/execution_admission.go | `23cac3ae674b5aa7e93676bc3c2f04c691e5dde27a695ad0e347a0b266c5a92e` |
| M:internal/governance/execution_channel_reader.go | `ad7e0e6078bdb32a28be927457b4c1af74f473d77e426d4bef94c26ccedd55e5` |
| M:internal/governance/execution_policy_readiness.go | `079410205927ed5a5fcf8fb82c78d78463cb75c93efce43e84da6189e9589ed9` |
| M:internal/governance/execution_deployment.go | `0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a` |
| M:internal/daemon/execution_control_worker.go | `23d65168cad81433af10f64f9084fab0d57745b690c82c47679e8317a53cfd3b` |
| M:internal/daemon/execution_control_client.go | `12df5bf254aa5935982a6efdcf4ac0d9b1c7226f8771f96b8345be8704668843` |
| M:cmd/server/router.go | `0ee5c8cfeafd688a851c8604d2382354f2fb2171d7facbe18a5185eee7b18f87` |
| M:cmd/server/main.go | `fab1a8fa1b71f2bc3984d52fcb5493255f6ababeae481c5205fd9639d5b81add` |
| M:cmd/server/execution_run_003_test.go | `ce969f52c4f194baa07d95f43d45dc23d5d687ca71e3f3586ed16c8577b3477e` |
| T:skills/shared/crctl/scripts/lib/execution-control-store.mjs | `1533dffc3206b8cd3a50119652efa62c49c195a24c328c19c35b864b6bab6a69` |
| W:multica/archive/2026-10-27-trusted-verdict-channel/design.md | `73834bd4bfbbb6b16384387e05ee09a899bbde034170ccf25a33e709c02586f8` |
| W:multica/archive/2026-10-27-trusted-verdict-channel/specs/verdict-channel/spec.md | `1a21b91d7de7492edbf68795c90aacb9d83a82dd75b090a59bfd4936648e56f9` |
| W:multica/archive/2026-10-27-trusted-verdict-channel/canonical/specs/code/verdict-channel.yaml | `9be455730dd4584069cd0d4cab071ae1f6a7a330e18acceda9014151153ba6a2` |
| W:multica/archive/2026-10-27-trusted-verdict-channel/specs/deployment-readiness/spec.md | `d8efbf32e3d110936aa9a92f3646d30adcf15e2a5542b140283fe6262abf05f8` |
| W:tools/archive/2026-10-27-trusted-verdict-channel/design.md | `6df4bf799b63bdd0cc3326f61328bbfb08720492d9e653113c5c887df30fb563` |
| W:multica/changes/2026-10-22-aifi-45-authorized-execution/validation/trusted-verdict-channel-implementation-plan-20261026.md | `55ee0d01e3b7ff62fabbcccef3dd8a8369c47e70dd89806ca6b75dce6a88b4d8` |
