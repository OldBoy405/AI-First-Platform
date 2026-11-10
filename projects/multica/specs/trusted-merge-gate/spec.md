# Spec: trusted-merge-gate — AIFI-45 M008 承接增量

> **已确认（Gate 2，2026-11-10T14:39）**；本页是合同条款，不是实施完成或验收结论。原 `verdict-channel` 规格、design 历史及归档条款均保留。
>
> 来源：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/wp4-sc-mg-015-016-paired-amendment-20261104.md` §3–8；验收分组来自同目录 `notification-convergence-plan-20261109.md`「四项验收保证」第 1 项。沿用原 SC/TC 编号，不增加验收分母。

本文件的 Requirements 在 tools 与 multica 载体中保持同文：T 负责恢复决策与发布入口，M 负责权威 settlement、原 mapping 与真实再准入；二者共同遵守以下条件，不以任一 helper 或单侧返回值证明全链安全。与本 change 既有 SC-VT-009/014、SC-VM-009/016/018 配对阅读；本增量细化指定远端恢复分支，不泛化为禁止其他合同下合法的 no_effect 或恢复。

## Requirements

### Requirement: SC-MG-015 区分目标状态与本 attempt 效果归属，不以远端达标伪造结算。

**现有机制不足：** 远端含 expected 只证明目标状态已达成，不能排除他人、先前 attempt 或迟到旧 push，原「不重推并结算成功」将观察误作本次效果证明。

#### Scenario: SC-MG-015（AIFI-45 M008 拟议修订）

- **GIVEN** journal 为 `unknown`，远端包含 expected（等于或其后续）。
- **WHEN** 对原 attempt 恢复或对账。
- **THEN** SHALL 不重推，并在既有 journal／观察事实中记录「目标当前已达成」这一可核观察，不将其直接当作本 attempt 的 effect。
- **AND** 若本 attempt 的 effect 与 no-effect 均无适用合同认可的可信证据，尚未结算的 attempt SHALL NOT 新写任一 settlement；其未决排他约束持续有效，不自动继续下一受保护动作。
- **AND** 若已有适用合同认可、与本 attempt 绑定的可信 no_effect，SHALL 按该合同处理，不因目标由他人达成而否定该证据；新发布仍须独立证明旧执行者不会迟到并满足完整再准入条件。
- **AND** 已有 settlement SHALL 保留原样；人工对账可核查、记录和展示，但人工确认本身不证明效果、不释放未决排他约束，也不授予重推权。
- **AND** `confirmed` 且远端为 expected 后继时保留原「正常前进不动作」；`confirmed` 且远端退回 prev 时保留原「history rewrite 转 uncertain」。分叉时禁止新 publish 的既有分支不变。

### Requirement: SC-MG-016 再尝试须同时具备可信 no_effect、旧执行者不会迟到及完整再准入条件。

**现有机制不足：** `intent`、远端仍为 prev、调用方布尔值或已有 no_effect 终态均不能单独排除旧执行者仍在途，原 not_attempted→attempt+1 路径可能制造重复效果。

#### Scenario: SC-MG-016（AIFI-45 M008 拟议修订）

- **GIVEN** journal 为 `intent` 且远端等于 prev，或服务端已 `settled_no_effect`、journal 为 `unknown` 且远端为 prev。
- **WHEN** 请求结算旧 attempt、递增 attempt、重新 reserve 或 push。
- **THEN** SHALL 不直接 push、不复用旧 attempt；SHALL 按以下分支判定，不以单纯 `intent`、远端 prev 或 caller 自报制造 `not_attempted`。
  - 尚未结算且存在来源可信、绑定本 attempt 的 no_effect：按适用合同处理该事实；只有另外证明旧执行者不会迟到且完整再准入成立，才允许进入受原身份合同约束的新 attempt 流程。
  - effect 和 no-effect 均无可信证明：保持未决 `unknown`，不新写任一 settlement、不递增 attempt、不释放未决排他约束，不新 reserve/push。
  - no-effect 已被可信证明，但旧执行者迟到尚未排除：可按适用合同结算 no-effect，但不得自动进入下一受保护动作；不得声称已结算的数据库 slot 仍被占用。
  - 已 `settled_no_effect`：读取／重放权威原 mapping，不再次以 `not_attempted` 结算，不删除或改写旧 settlement；该终态本身不证明旧执行者不会迟到，也不授予新发布权。只有来源与 attempt 绑定可信、迟到已排除、SC-MG-016 完整条件及 SC-VC-035 身份／重新准入合同均满足时，才允许研究新 attempt；否则保留原 attempt 和已有事实，禁止新 reserve/push 并等待对账。
- **AND** 对已有 `settled_no_effect + unknown + expected`，同样先核权威 settlement 与证据归属，保留原结算和 mapping；目标状态不将原 no_effect 改成 effect，也不放行未证明安全的新动作。
- **AND** 新 attempt 的许可不由 `noEffectAttested=true`、ACK、人工确认或一次远端观察替代；可信 no_effect 的生产／验证与旧执行者迟到排除任一缺失时，自动再尝试保持关闭。

### Requirement: M 侧原 settlement/mapping 不可变，重放结果不等于 T 获得新发布权。

**现有机制不足：** 既有查询把任何 settlement 当作 reservation 已结束，且 reserve 可返回旧 mapping，因此数据库 slot 结束或 HTTP 200 均不足以证明下一次远端效果可安全执行。

#### Scenario: SC-VC-035（AIFI-45 M008 配对增量）

- **GIVEN** 同一 `effect_id` 的同 attempt 原字节重放、前 attempt 已 settled 的新 attempt 请求、无未终结前 attempt、前 attempt 未终结四种既有情形。
- **WHEN** T 按恢复条件请求 reserve，M 按权威身份合同处理。
- **THEN** SHALL 保留原四支返回语义：分别 `200` 原结果、`200` 原 mapping、`201` 新 command、`409 CONFLICT`；已 settled 的原记录及 mapping 不被重开、重结算或覆盖。
- **AND** `200` 原 mapping 不是新 command、新 attempt 已创建或新发布授权；T 不得据此 push。涉及旧 attempt 的新受保护动作必须先满足上文可信 no_effect、排除迟到及原完整门禁；M 须在真实准入入口阻断不满足者，不能仅依赖 T helper。
- **AND** 尚未结算且效果未知的 attempt 保持未决排他约束；已有 settlement 但再尝试条件不足时，保留原行并在真实入口另行阻断新 effect，不虚称已结算 slot 仍被占用。具体互锁、持久观察和混版切换机制仍待配对评审，不在此预设新增状态、终态重开或迁移。
- **AND** SC-VC-012 状态约束、SC-VC-022 合法 no-effect、撤销线性化，以及 SC-VC-015/SC-TR-006 其他恢复表的原适用范围保留；不以本增量改写无冲突分支。

## 沿用验收与生效边界

- 来源：原 `TC-MG-015/016`；补充其未知／可信结果、迟到、并发和混版分支，不另造 TC。M 原 mapping、settlement 与再准入验收仍用原 TC；SC-VC-035/原 mapping 重放不是额外独立计数。
- 两侧已有 `TC-VT-009/014`、`TC-VM-009/016/018` 中对这些归档分支的排除保留为历史测试边界；不能据它们宣称已覆盖 TC-MG-015/016。真实入口、可信 producer、迟到排除及隔离数据库／临时远端的证据归属仍待核定。
- 本轮仅纳入待审文档，不执行测试或 Gate，不修改归档合同、状态投影或 `.stdd.yaml`；局部 helper、原 mapping 重放与内存夹具均不等于配对生产链验收。
