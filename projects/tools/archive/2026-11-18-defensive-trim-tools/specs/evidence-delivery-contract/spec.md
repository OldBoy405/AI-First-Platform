# Spec: evidence-delivery-contract

> Change: 2026-11-18-defensive-trim-tools | Auto-generated Human View

## Requirements

### Requirement: 只有适用组件就绪要求的 CR 才读取交付工作区配置，且只有成功读取有效配置才能认定组件未声明。

#### Scenario: SC-EVD-101

- **GIVEN** 已选定且未被合同诊断拒绝的合同 CR，其交付工作区 dir-graph.yaml 缺失、不可读，或 workspace.components 已声明但非列表（含显式 null）。
- **WHEN** 运行 evidence-check 或同一采集器的 evidenceDelivery gate。
- **THEN** SHALL 退出 1，报告 EVIDENCE_COMPONENT_CONFIG_INVALID、文件路径和原因，无放行输出。
- **AND** 配置可读且有效，components 真正缺省或为 [] 时，若其余证据齐全则 decision: deliver。

#### Scenario: SC-EVD-102

- **GIVEN** 交付工作区组件配置错误，CR 为真正的 legacy，或已被合同非法、登记非法、降级或不一致诊断拒绝。
- **WHEN** 运行 evidence-check 或同一采集器的 evidenceDelivery gate。
- **THEN** SHALL 对 legacy 按原交付条件判定，对已拒绝的 CR 报告原合同诊断，均不报组件配置错误。

### Requirement: 组件判定器是就绪结论的唯一来源，交付只合并其 findings。

#### Scenario: SC-EVD-103

- **GIVEN** 适用组件就绪要求的合同 CR 有非空组件声明。
- **WHEN** 根据实际观测判定交付。
- **THEN** SHALL 在组件匹配且其他条件满足时放行，有组件 findings 时阻断并原样按顺序报告。
- **AND** 授权或验证也有 finding 时，与组件 findings 一并报告。
