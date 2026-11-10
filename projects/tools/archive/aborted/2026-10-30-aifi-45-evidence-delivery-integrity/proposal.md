# AIFI-45 证据交付完整性与合同防降级

<!-- source_hash: f0b43a10e2cd4670 -->
<!-- generated_at: 2026-10-30T10:25:46.253749 -->
<!-- canonical: canonical/proposals/2026-10-30-aifi-45-evidence-delivery-integrity.yaml -->

## Why

AIFI-45 的交付检查需同时保护新合同不被删除字段降级，并避免追溯性阻断合法 legacy。现有 YAML 和报告解析、合同选择及证据身份绑定仍有未闭合问题；局部 guard 或纯函数测试不证明真实 CLI、两个 gate 与可信来源已贯通。


## What Changes

- 先核查权威注册与迁移历史，设计新旧合同选择和防删除降级；异常不得静默回退 legacy。
- 评审新合同的严格解析范围：未知字段、重复键、非 mapping 头部、未消费输入及报告 fence 的处置，并盘点受支持语法与历史兼容性。
- 闭合授权、验证和评审的来源及 subject 绑定，并通过经安全审查的隔离 fixture 验证真实 CLI 与相关 gate。
- 评审机械例外中 env 等包装器、组件 not-applicable 的版本与来源证明、unknown 作者和 Cf 身份策略；未完成前保留在 AIFI-45 pending。
- 回传可追溯证据给 AIFI-45；现有任务和规格不因拆分自动完成或取消。

### Modified Capabilities

- **evidence-delivery-contract**：保障交付证据解析、合同选择和来源验证的完整性。

## Success Criteria

- [ ] 批准的合同选择和解析策略具有可核验的权威来源、兼容盘点及明确失败行为。
- [ ] 新合同覆盖未知字段、重复键、非 mapping、字段删除、解析错误、报告 fence 和来源错配的正反例；合法 legacy 有兼容回归。
- [ ] 隔离的真实 CLI 和两个相关 gate 验证防降级与证据链；结果交由 AIFI-45 对原 SC/TC 独立验收。
