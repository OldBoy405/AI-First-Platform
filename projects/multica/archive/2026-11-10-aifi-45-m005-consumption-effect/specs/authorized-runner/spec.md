# Spec: authorized-runner

> Change: 2026-11-10-aifi-45-m005-consumption-effect | Auto-generated Human View

## Requirements

### Requirement: （MODIFIED，仅 SC-RUN-003）实际认证入口绑定充分授权，ACK 与已提交业务消费分离。

#### Scenario: SC-RUN-003

- **GIVEN** grant 送达落盘并 ACK，但对应 task 的平台 consumption effect 尚未提交。
- **WHEN** ACK 回调及 periodic wake 发生。
- **THEN** SHALL 只唤醒核验，不完成业务 gate 或直接派旧 continuation；该 effect 提交后才依实际状态推进。
- **AND** 对 execution-consume，上述「提交」由 consumption-effect 能力（平台签发）满足；T 的裁决只是候选，不入链，也不被当作提交。
- **AND** 其余既有 AND 条款（daemon_token 与 DB claim、投影不等于 fresh 证明、verdict 写入的验签与逐项绑定）保持不变。
