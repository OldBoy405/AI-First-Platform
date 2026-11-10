# 2026-11-09 范围并入（决策 D3）

- 决定：本 change 为可信裁决 / 信任缝的**唯一载体**；`2026-10-30-aifi-45-evidence-delivery-integrity` 的未完成范围并入本 change，不单独立项继续。
- 原因：同一信任与证据缝并行两条线会产出两套合同判定；一种事实只保留一个权威。
- 并入内容（来自原 change 的 What Changes）：证据交付解析与合同选择、防删除降级、异常不回退 legacy、机械例外的包装器与版本证明、授权/验证/评审的 subject 绑定。
- 不并入：已在归档 change 中关闭的条款（EVD-004/005 机械免审例外、EVD-007 的 readiness/恢复断言）。
- 保留：原 change 的 `proposal.md` / `design.md` / `specs/` 原样保留作来源登记，不删除、不改写；其 `.stdd.yaml` 不手工改状态。
- 边界：并入不改变本 change 当前 Gate 状态，也不授权 BUILD；范围正式生效仍须 Gate 2。
