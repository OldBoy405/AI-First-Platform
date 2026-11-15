# workflow-routing — 规格

> Change: 2026-11-06-stdd-default-cr-opt-in
> 依据：[已确认提案](../../canonical/proposals/2026-11-06-stdd-default-cr-opt-in.yaml) 的 C2–C4、constraints 与成功标准；设计见 [design.md](../../archive/2026-11-06-stdd-default-cr-opt-in/design.md) D1。
> 证据：TC-WFR-001（人工盲评，见 [test-plan.md](../../archive/2026-11-06-stdd-default-cr-opt-in/test-plan.md)）。本规格只约束入口文案承诺，不证明运行时模型行为。

## REQ-WFR-001 — 入口按变更身份选择流程，授权互相独立

#### Scenario: SC-WFR-001 — 六类输入的入口决定

- **TC**：TC-WFR-001；**Confidence**：high。
- **GIVEN**：请求属于下列之一：只读分析或问答；已有 STDD change 或 CR；未指定流程的新开发；显式选择 tools CR 的新变更；目标、绑定或归属不明；仅持有一个 STDD Gate 或另一流程的批准，却要求推进 CR、提交、推送或部署。
- **WHEN**：Agent 只读取知识库根入口与 tools 入口，据此决定下一步。
- **THEN**：SHALL 得到 design D1 表中对应的流程选择、写入边界和所需授权：只读不创建变更；已有变更沿用原流程、换流程须单独确认；新开发默认 STDD 并先核实目标业务仓、绑定与三根；显式 CR 走合法注册入口；不明则停止并询问；Gate、CR 审批与 Git／部署授权互不替代。
- **AND**：知识库 cwd 无绑定、但目标业务仓及其绑定明确时，先核实三根并从该业务仓执行，而不是停止或回退旧模式。
- **AND**：两份入口中都没有与上述相反的无条件要求，例如无条件读取完整 CR 手册，或把 STDD 默认值套到已有 CR。

## 覆盖与评审边界

1 个 Requirement、1 个 Scenario、1 个 TC（人工）。Scenario 的预期以 design D1 表为准；评审者作答时不看该表。
