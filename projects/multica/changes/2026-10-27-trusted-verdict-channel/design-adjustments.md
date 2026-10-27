# 设计偏离记录 — 2026-10-27-trusted-verdict-channel

> BUILD 期起用。每条记录「原设计 → 实际做法 / 原因 / 影响范围 / 结论是否受影响」。
> 未经 Gate 2 批准的范围变更不在此处顺手改，须回规格修订。

## ADJ-1（协调，2026-10-27）：EVD-007 已由 AIFI-45 会话先落到 tools 交付 gate

- **事实**：tools `f3946ce`（2026-10-27 15:41）把 `evaluateComponentReadiness` 接进 `collectEvidenceDeliveryFacts`/
  `evaluateEvidenceDelivery`，观测来源是 `dir-graph.yaml#workspace.components` 声明 + tools marker digest +
  `MULTICA_COMPONENT_*`；改动文件为 `crctl.mjs`、`lib/evidence-delivery.mjs`、`test/evidence-delivery-gate.test.mjs`。
  该提交自述「不是部署就绪（隔离/Runner 二进制/已安装版本归 G8/M002）」。multica `CUSTOM.md` 已登记到 **#219**。
- **原设计**：plan §7.1 假定 `component-readiness.mjs` 只有测试调用、无生产 caller，本 change 直接加固并新增严格入口。
- **实际做法**：
  1. 本 change 的 T-S8 **不改** EVD-007 的 opt-in 语义（未声明组件的工作区行为必须不变），只在
     `component-readiness.mjs` 内新增「严格入口 / strict 模式」，宽松结果照旧只作诊断，不得签发 deployment verdict。
  2. 不重写 `evidence-delivery.mjs`；如需把严格 readiness 折入交付 gate，另行规格修订，不在本 change 顺手改。
  3. `CUSTOM.md` 新登记从 **#220** 起（原计划 #219 已被占用）。
- **影响范围**：SC-TR-012（求值器加固）与 SC-DR-001..006（D7 路径）的实现边界；不影响必达 leaf 名单。
- **结论是否受影响**：否。范围与 S8 目标不变；变的是「严格入口与既有宽松路径共存」这一实现约束，已写入规格与任务。

## ADJ-2（单一写者，2026-10-27）：AIFI-45 会话仍在两个源码仓活动

- **事实**：tools 最近 6 个提交与 multica 最近 6 个提交均属 AIFI-45 会话（B16/EVD gate/G1/G2/G3/G5/NTF-003/EVD-007）。
- **实际做法**：本 change 先做「新增文件」类切片（`lib/execution-control-*`、新增 Go 包内文件、648 迁移），
  对共享文件的插入（`workspace-transactions.mjs` 的 merge 插入点、`repair-governance.mjs`、
  `execution-sensitive-action.mjs`、`component-readiness.mjs`）在动工前先核对方是否有未提交改动；
  检测到同文件在途即停手，不并行写同一文件。
- **影响范围**：切片顺序（不改变依赖 DAG），与 Gate 3 的证据完整性无关。
- **结论是否受影响**：否。
