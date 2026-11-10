# workflow-routing — 人工评审副本

> STDD BUILD／DELIVER 所需的非权威兼容视图（人工评审副本），不是 CLI 自动生成的 Human View，不受 canon hash／body 校验覆盖。历史 Gate 2 已确认方案 A；2026-11-10 修订版 Gate 2 重新确认待完成，状态以 STDD 记录为准。
> 唯一规格源：[Canonical CP](../../canonical/specs/agent/2026-11-06-stdd-default-cr-opt-in.yaml)。评审直接引用该源；本文不设独立预期或逐项同步维护义务。
> 证据：[已确认提案](../../canonical/proposals/2026-11-06-stdd-default-cr-opt-in.yaml) C2–C4、constraints 与成功标准。
> documentation 任务中 CP 即规格；下文仅将同一 CP 展开为便于评审的 GIVEN／WHEN／THEN。action 只能检查静态条款，不能证明实际模型路由。

## REQ-WFR-001 — 只读请求不启动变更

#### Scenario: SC-WFR-001 — 分析与问答

- **CP / TC**：CP-WFR-001 / TC-WFR-001；**Confidence**：high。
- **GIVEN**：请求仅要求分析或问答。
- **WHEN**：Agent 读取根入口并选择应加载的资料。
- **THEN**：SHALL 不创建 STDD change 或 CR。
- **AND**：仍遵守数据完整性和权限底线，不因出现“需求”等词就注册。

## REQ-WFR-002 — 新变更按明确选择或 STDD 默认值处理

#### Scenario: SC-WFR-002 — 未指定流程的新开发

- **CP / TC**：CP-WFR-002 / TC-WFR-002；**Confidence**：high。
- **GIVEN**：请求创建新开发变更，尚无既有流程身份，用户未指定流程。
- **WHEN**：选择工作流入口。
- **THEN**：SHALL 默认使用 STDD。
- **AND**：先确定目标业务仓、绑定、资源根与记录根，再读取当前阶段技能；不假称 slash command 已注册。

#### Scenario: SC-WFR-003 — 显式选择 tools CR

- **CP / TC**：CP-WFR-003 / TC-WFR-003；**Confidence**：high。
- **GIVEN**：请求创建新变更，用户明确选择 tools CR。
- **WHEN**：选择入口并准备注册。
- **THEN**：SHALL 加载现行 CR 合同并通过合法注册入口处理。
- **AND**：不凭 STDD 默认值拒绝 CR，也不手写 CR 账本代替注册。

## REQ-WFR-003 — 已有流程优先且迁移另行确认

#### Scenario: SC-WFR-004 — 接手旧变更或遇到换流程要求

- **CP / TC**：CP-WFR-004 / TC-WFR-004；**Confidence**：high。
- **GIVEN**：已识别出已有 CR 或 STDD change。
- **WHEN**：当前默认值或新请求与原流程冲突。
- **THEN**：SHALL 沿用原流程，并暂停冲突操作，单独确认迁移方案。
- **AND**：不映射状态、不双写任务、不用新流程标识伪造旧变更完成。

## REQ-WFR-004 — 定位不明时失败关闭

#### Scenario: SC-WFR-005 — 无绑定、目标缺失或归属冲突

- **CP / TC**：CP-WFR-005 / TC-WFR-005；**Confidence**：high。
- **GIVEN**：目标业务仓、其绑定或变更归属无法确认。
- **WHEN**：准备进入 STDD。
- **THEN**：SHALL 停止并询问。
- **AND**：不自动 init，不猜 sibling，不回退旧模式，不触碰其他在途变更。
- **AND**：若仅知识库 cwd 无绑定，但明确目标仓绑定有效，应先核实三根并从该业务根执行，而非直接停止或回退。

## REQ-WFR-005 — 确认与操作授权彼此独立

#### Scenario: SC-WFR-006 — 不跨流程互认审批

- **CP / TC**：CP-WFR-006 / TC-WFR-006；**Confidence**：high。
- **GIVEN**：只有某个 STDD Gate 或另一流程的批准。
- **WHEN**：准备推进真实 CR、提交、推送或部署。
- **THEN**：SHALL 独立核对该操作所属流程的合法授权。
- **AND**：两流程不互认审批；当前 Gate 1 不批准 Gate 2 或 BUILD。

## 覆盖与评审边界

5 Requirements、6 Scenarios、6 Canonical CP、6 TC。全部来自已确认提案，high=6、medium=0、low=0。

每个 action 的成功只表示明确条款存在；人工评审还须按 [test-plan.md](../../test-plan.md) 复述流程选择、是否写入和仍需的授权，并检查其他入口是否存在相反规则。
