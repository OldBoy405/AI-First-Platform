# Spec: verdict-channel

> Change: 2026-10-29-trusted-verdict-outcome-binding | Auto-generated Human View

## Requirements

### Requirement: 合同级目标（v2 签发已在 S1 实施；真实签发、部署与生产接线仍待上线就绪清单）：可信证明来自批准来源与受控签发主体。

#### Scenario: SC-VT-001

- **GIVEN** 存在获得批准的裁决来源、签发主体、信任根和当前签发权限，且命令绑定及输入符合合同。
- **WHEN** 产生可信裁决证明。
- **THEN** SHALL 只签发该主体有权认证的事实并按批准 wire 保留原始签名字节。

#### Scenario: SC-VT-002

- **GIVEN** 签发主体、来源、manifest、key purpose、scope 或当前权限未知、不可信或不匹配。
- **WHEN** 尝试提供支持新增 effect 的可信证明。
- **THEN** SHALL 拒绝签发可用于新增 effect 的证明，不以有效签名或 caller 自报代替授权。

#### Scenario: SC-VT-003

- **GIVEN** 存在可信 permit，但实际 effect 未发生、未知或只由 caller 声称。
- **WHEN** 产生与实际 effect 有关的证明。
- **THEN** SHALL 不把 permit 本身当成已发生的 effect。

### Requirement: 合同级目标（v2 签发已在 S1 实施；真实签发、部署与生产接线仍待上线就绪清单）：共享合同明确结果、绑定和原始签名语义。

#### Scenario: SC-VT-004

- **GIVEN** payload 包含未知字段、未批准的结果值、错误 purpose 或错误 domain。
- **WHEN** 请求签发或跨仓消费该内容。
- **THEN** SHALL 拒绝未批准结果值、错误 purpose 和错误 domain；v2 字段为闭集，含未知字段的 payload 整体拒绝（[M design 决定 K1](../../../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#决定)）。

#### Scenario: SC-VT-005

- **GIVEN** 命令、权威主体、scope、request 或 chain 相对于可信来源不一致。
- **WHEN** 形成可用于新增 effect 的证明。
- **THEN** SHALL 拒绝不一致输入，不能仅因两个调用方值相等而签发。

#### Scenario: SC-VT-006

- **GIVEN** 已批准合同规定命令、主体及 generation 的权威绑定，且待签输入与该绑定不一致。
- **WHEN** 签发方形成可信证明。
- **THEN** SHALL 阻止签发不符合该绑定的可信证明；接收方的跨命令、主体或代次重放拒绝由 M 侧独立验证。

#### Scenario: SC-VT-007

- **GIVEN** 双方生成经批准的正负原始签名字节、前像及指定 digest 向量，逐项标明各摘要的前像、用途及字段映射；前序链摘要公式由本共享向量冻结（[M design 决定 K4](../../../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#决定)），不一致即停止并走修订。
- **WHEN** Node 与 Go 相互验证并比较指定结果。
- **THEN** SHALL 依获批字段映射正确互验合法向量，拒绝错域、错误主体和篡改向量，不将不同前像无依据互换，且不以重序列化替代原字节验证。

### Requirement: 合同级目标（效果执行和恢复实现归属待人审）：保护一次性效果与未知状态。

#### Scenario: SC-VT-008

- **GIVEN** 同一请求原字节重复提交或重复恢复。
- **WHEN** 已认证结果重放。
- **THEN** SHALL 按批准的幂等合同保持原记录，不能产生第二次业务 effect。

#### Scenario: SC-VT-009

- **GIVEN** journal、frame 与 head 之间出现中断，外部系统返回不确定结果，或服务端报告 no_effect 但该次未发生的证明尚无法认证。本场景排除 unknown+远端含 expected（按祖先关系）、intent+远端 prev、以及 settled_no_effect+unknown+远端 prev；上述组合按本 change 的 SC-MG-015/016 修订处理（[M design 决定 K5](../../../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#决定)）。
- **WHEN** 请求继续执行或恢复。
- **THEN** SHALL 保留可审计证据并按批准合同处理未知状态，不以未经认证的 no_effect 终态虚构该次未发生或盲目重做 effect。
- **AND** 远端恢复组合及其与 SC-VC-012/035 的衔接按本 change specs/trusted-merge-gate 的 SC-MG-015/016 修订处理（[M design 决定 K5](../../../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#决定)）：远端状态是观察，不是结算。

#### Scenario: SC-VT-010

- **GIVEN** 并发写入、回滚或恶意替换使本地 checksum 看似有效，但权威顺序或认证无法证明。
- **WHEN** 尝试将结果用于新增 effect。
- **THEN** SHALL 不把 checksum 或签名形状当成可信签发及防回滚证据。

### Requirement: 合同级目标（部署/消费修复不自动授权）：旧格式与恢复遵守已批准的防降级策略。

#### Scenario: SC-VT-011

- **GIVEN** 存在未知、旧格式、已失效 key 或现存历史裁决，且其当前授权语义不能认证。
- **WHEN** 尝试据此支持新增 effect。
- **THEN** SHALL 失败关闭，不擅自删除、重签或推断历史为空。

#### Scenario: SC-VT-012

- **GIVEN** 升级或回滚涉及 in-flight 请求、no_effect、旧 key 或不兼容的证明格式。
- **WHEN** 操作者按批准策略切换或恢复。
- **THEN** SHALL 防止旧格式被静默赋予新增权限（v1 永不放行新增 effect，[M design 决定 K1](../../../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#决定)），并保留可审计的已发生效果；升级/回滚与在途策略属上线就绪清单，不计本 change 验收。

### Requirement: 合同级目标（实现归属待人审）：可信 no_effect、未知结果和密钥生命周期不得混同。

#### Scenario: SC-VT-013

- **GIVEN** 权威来源认证了 pending、deny、stopped，或过时或撤销的 permit；撤销按既有线性化合同判定。
- **WHEN** 按归档 SC-VC-022 合同处理后续 effect 的产生。
- **THEN** SHALL 按适用合同支持 no_effect 且不得产生该次 effect，不能以 ACK 本身取代认证结果。

#### Scenario: SC-VT-014

- **GIVEN** command 已 issue，结果或外部 effect 未知，或缺乏可信证明。
- **WHEN** 请求恢复或再次执行。
- **THEN** SHALL 按经批准恢复合同处理未知状态并保全证据；在合同未规定其他结算或重试处置时冻结有关 slot，不得仅因未知推断 no_effect 或重新执行。
- **AND** 远端恢复组合及其与 SC-VC-012/035 的衔接按本 change specs/trusted-merge-gate 的 SC-MG-015/016 修订处理（[M design 决定 K5](../../../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md#决定)）：远端状态是观察，不是结算。
- **AND** SC-VC-015 / SC-TR-006 恢复表中原 command 重放与新 effect 判定分别处理，不以冻结措辞禁止其已批准的恢复动作。

#### Scenario: SC-VT-015

- **GIVEN** key 轮换、撤销或泄露，且 key 状态或签发时间不可由权威来源证明。
- **WHEN** 请求签发或消费支持新增 effect 的证明，并查询已提交的历史。
- **THEN** SHALL 不以未固定或状态未知的 key 支持新增 effect，保留原字节；key 生命周期与历史有效性策略属上线就绪清单，不计本 change 验收。
