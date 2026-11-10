# Spec: verdict-channel

> Change: 2026-10-29-trusted-verdict-outcome-binding | Auto-generated Human View

## Requirements

### Requirement: 合同级目标（消费侧实施属 AIFI-45）：只将可信裁决用于新增 effect 的准入。

#### Scenario: SC-VM-001

- **GIVEN** 对前一命令的 permit 和该命令对应 effect 已按批准合同在提交边界完成认证及结算，且后续请求具备匹配绑定与原门禁所需条件。
- **WHEN** 消费方判断后续独立 task-start 或其他 effect 的准入。
- **THEN** SHALL 将已结算的可信前序事实作为必要条件之一，并按后续操作的原有 AIFI-45 门禁判断，不以此保证后续 effect 已发生。

#### Scenario: SC-VM-002

- **GIVEN** 新请求尚未创建或 command 已 issue；裁决缺失、不可验签、来源或 key 用途不可信、可信名单来源无法证明、过期、结果未知或读取失败。
- **WHEN** 尝试据此授权新增 effect。
- **THEN** SHALL 拒绝尚未创建的无效新请求并不得创建 effect；对已 issue 且事实未知者按适用批准合同处理，在合同未规定其他处置时冻结有关 slot，不能降级到调用方自报或旧格式放行。
- **AND** SC-DR-006 的 deployment access/launch 路径对 STOP_NEW 或过期后的原 issued 请求要求精确恢复原 command/receipt bytes；不移除 cutoff/pin/generation 校验。换代只能拒绝或加载原已批准固定快照，新候选、换 origin、created 未 issued 不能恢复；其过期与本场景的过期是否为同一对象待核。
- **AND** SC-VC-027 所述条件下的终态安全收尾不因 STOP_NEW 或授权过期而阻止；不得把该条件推广为无条件放行。
- **AND** 过期与 SC-VC-022 的过时条件之关系待合同审定，不据此新增效果未发生的前提。

#### Scenario: SC-VM-003

- **GIVEN** 具有效签名但结果不是经批准可授权 permit 的裁决，或仅有未经认证的 caller effect。
- **WHEN** 判断能否新增 effect。
- **THEN** SHALL 不得将签名存在或 caller kind 当作可信 permit。

### Requirement: 合同级目标（消费侧实施属 AIFI-45）：权威验证可信裁决与冻结命令、主体、链及代次的绑定。

#### Scenario: SC-VM-004

- **GIVEN** 合法裁决被用于不同 request、scope、主体、store 或 lineage。
- **WHEN** 消费方检查绑定。
- **THEN** SHALL 拒绝新增 effect，即使该签名本身有效。

#### Scenario: SC-VM-005

- **GIVEN** 尚未创建的新请求或已 issue 的 command，其裁决与权威冻结命令、摘要原像或代次不一致，或者该权威关系不可读取。
- **WHEN** 消费方检查命令和 generation。
- **THEN** SHALL 拒绝尚未创建的无效新请求；对已 issue 且绑定不符或权威事实未知者冻结有关 slot，不得仅比较调用方提供的两个相等值。

#### Scenario: SC-VM-006

- **GIVEN** epoch、sequence、前序摘要或其域与可信链位置不匹配。
- **WHEN** 受保护帧入账或作为授权依据。
- **THEN** SHALL 拒绝该帧用于新增 effect，并保持已提交链不被该输入推进。

### Requirement: 合同级目标（各写入口实现归属待人审）：结算与真实 effect 证据一致，覆盖每个可达写入路径。

#### Scenario: SC-VM-007

- **GIVEN** permit 已认证，但事务内效果尚未提交或远端效果证据不存在、不可信、属于其他命令或结果未知。
- **WHEN** 结算入口尝试声称效果已发生并用该结算支持后续 effect。
- **THEN** SHALL 不将未提交或无法证明的效果作为已发生的可信结算；不得阻止按批准事务先执行并原子结算其本次效果。

#### Scenario: SC-VM-008

- **GIVEN** 每个可能写 settlement 的入口分别接收该入口适用的不可信权威对象或不匹配绑定；verdict、grant 和 head 不假定为同一种对象。
- **WHEN** 执行各入口。
- **THEN** SHALL 在各入口均阻止不可信结算促成新增 effect，不得依赖仅一个 helper 的检查。

#### Scenario: SC-VM-009

- **GIVEN** 外部副作用调用超时或回执丢失，无法确认 effect 是否发生；或服务端报告 no_effect，但该次未发生的证明尚无法认证。本场景排除 unknown+远端含 expected（按祖先关系）、intent+远端 prev、以及 settled_no_effect+unknown+远端 prev；上述组合按本 change 的 SC-MG-015/016 修订处理（design#K5）。
- **WHEN** 尝试结算或重试。
- **THEN** SHALL 按经批准恢复合同处理未知结果，不以未经认证的 no_effect 终态虚构该次未发生或盲目重复执行。
- **AND** 远端恢复组合及其与 SC-VC-012/035 的衔接按本 change specs/trusted-merge-gate 的 SC-MG-015/016 修订处理（design#K5）：远端状态是观察，不是结算。

### Requirement: 合同级目标（消费侧实施属 AIFI-45）：撤销、head、代次及结算顺序遵守批准规则。

#### Scenario: SC-VM-010

- **GIVEN** 撤销与 effect 提交以不同顺序竞争。
- **WHEN** 按既有锁序完成事务。
- **THEN** SHALL 依批准合同区分撤销先提交与 effect 先提交，不追溯改写已提交事实。

#### Scenario: SC-VM-011

- **GIVEN** 权威 selection、授权 head 或其关系缺失、未知或读取失败。
- **WHEN** 结算或准入需要判断当前授权。
- **THEN** SHALL 不将缺失或未知当作已确认仍授权以产生新增 effect。

### Requirement: 合同级目标（实施及验证归属待人审）：重放、历史与协议互操作不能制造新权限或额外效果。

#### Scenario: SC-VM-012

- **GIVEN** 同一已认证请求与原始签名字节重复投递，或发生中断后重试。
- **WHEN** 按批准恢复合同处理。
- **THEN** SHALL 不制造第二次 effect，并保持可核验原字节和原有已提交结果。

#### Scenario: SC-VM-013

- **GIVEN** 存在未知格式、历史 verdict 或旧 key 的记录，且兼容或恢复策略未能认证其当前适用性。
- **WHEN** 据此请求新增 effect。
- **THEN** SHALL 失败关闭，不得静默改写历史或推断无存量。

#### Scenario: SC-VM-014

- **GIVEN** 双方按获批合同产生覆盖命令、主体、链及结果的正负向量，逐项标明各摘要的前像、用途及字段映射；前序链摘要公式由本共享向量冻结（design#K4），不一致即停止并走修订。
- **WHEN** Go 与 Node 交叉处理原始签名字节及指定 digest。
- **THEN** SHALL 依获批字段映射正确接受合法向量并拒绝篡改或错域向量，不将不同前像无依据互换，且基础验签结果不替代真实入口验收。

### Requirement: 合同级目标（实施归属待人审）：no_effect、未知状态、密钥事件和回滚遵守合同并可审计。

#### Scenario: SC-VM-015

- **GIVEN** 权威来源认证的 pending、deny、stopped，或过时或撤销的 permit；撤销按既有线性化合同判定。
- **WHEN** 按归档 SC-VC-022 合同处理后续 effect 的产生。
- **THEN** SHALL 按适用合同结算 no_effect，不产生该次 effect，并按合同而非单凭 ACK 处理 slot。

#### Scenario: SC-VM-016

- **GIVEN** command 已 issue，结果或外部 effect 未知，或结果认证无法建立。
- **WHEN** 接收方处理失败或恢复请求。
- **THEN** SHALL 按经批准恢复合同处理未知状态；在合同未规定其他结算或重试处置时冻结相关 slot，不能仅因缺失可信证据推断 no_effect 或释放 slot。
- **AND** 远端恢复组合及其与 SC-VC-012/035 的衔接按本 change specs/trusted-merge-gate 的 SC-MG-015/016 修订处理（design#K5）：远端状态是观察，不是结算。
- **AND** SC-VC-015 / SC-TR-006 恢复表中原 command 重放与新 effect 判定分别处理，不以冻结措辞禁止其已批准的恢复动作。

#### Scenario: SC-VM-017

- **GIVEN** 签发 key 轮换、撤销或泄露，且真实 key 状态或签发时间不能被权威证明。
- **WHEN** 使用新旧签名请求新增 effect 或查询已提交记录。
- **THEN** SHALL 拒绝以未固定或状态未知的 key 支持新增 effect，保留历史原字节，不预设历史全部失效；历史有效性策略属上线就绪清单（design#范围），不计本 change 验收。

#### Scenario: SC-VM-018

- **GIVEN** 无效请求分别发生在尚未创建、created 未 issue、issued、result_ready、settled 或 uncertain 状态。
- **WHEN** 处理输入错误、已知结果或恢复请求。
- **THEN** SHALL 按批准状态表分别拒绝未创建请求、只按既有合同取消从未 issue 的 created；issued、uncertain 和 result_ready 按适用合同处理已认证结果与未知状态，在合同未规定其他结算或重试处置时冻结未知状态；settled 重放原记录，但不以此推定下列待核组合的结算或重试结果；不得凭 ACK 释放 slot。
- **AND** SC-VC-022 的过时或撤销 permit 处理仍适用，按 SC-VM-015 验证。
- **AND** 远端恢复组合及其与 SC-VC-012/035 的衔接按本 change specs/trusted-merge-gate 的 SC-MG-015/016 修订处理（design#K5）：远端状态是观察，不是结算。
- **AND** SC-VC-015 / SC-TR-006 恢复表中原 command 重放与新 effect 判定分别处理，不以冻结措辞禁止其已批准的恢复动作。

#### Scenario: SC-VM-019

- **GIVEN** 回滚候选二进制或旧结算路径会把调用方自报 kind 当作新增 effect 的可信依据。
- **WHEN** 操作者尝试回退、切流或恢复在途请求。
- **THEN** SHALL 阻止该防线降级：无论是否回退，caller 自报 kind 与 v1 裁决均不得放行新增 effect（design#K1）；回滚机制属上线就绪清单，不改写已发生的历史。
