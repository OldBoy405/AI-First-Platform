# Spec: evidence-delivery-contract

> Change: 2026-10-22-aifi-45-authorized-execution | Auto-generated Human View

## Requirements

### Requirement: 按内容充分性和长期规则归属验收，不按固定文件套餐或复制机器账本验收。

#### Scenario: SC-EVD-001

- **GIVEN** 新policy变更具有目标、范围、可信授权、结果与证据的最小记录及应有长期规则更新，但没有PRD/SDD/plan固定套餐。
- **WHEN** 执行适用gates和回写。
- **THEN** SHALL 按内容放行，不强制复制文件套餐，不覆写累积基线或搬移平台级文档。

#### Scenario: SC-EVD-002

- **GIVEN** 文件数量齐全，但缺当前授权/验证证据，或长期规则变化未更新其权威源。
- **WHEN** 请求交付。
- **THEN** SHALL 阻断并指出缺失内容，不能以文件存在或报告全文复制替代证据。

### Requirement: 实质变更必须独立核验；机械例外不得涵盖语义变化。

#### Scenario: SC-EVD-003

- **GIVEN** 实质变更只有作者自报PASS或同一真实UUID的review。
- **WHEN** 请求完成交付。
- **THEN** SHALL 拒绝，要求独立身份核验实际diff和当前可运行证据。

#### Scenario: SC-EVD-004

- **GIVEN** 可证明同输入与工具下无语义变化，独立执行者已产生确定性检查证据。
- **WHEN** 申请机械变更例外。
- **THEN** SHALL 仅在该证明完整且匹配当前subject时允许替代Agent评审，并保留证明链。

#### Scenario: SC-EVD-005

- **GIVEN** 生成结果可复现，但生成规则/输入/工具、业务规则、授权或验收发生语义变化。
- **WHEN** 以机械生成为由免审。
- **THEN** SHALL 拒绝例外，仍要求独立评审与适用测试。

### Requirement: 新旧合同显式版本化，迁移保留授权、历史消耗与旧证据。

#### Scenario: SC-EVD-006

- **GIVEN** 在途legacy CR未显式选择新合同。
- **WHEN** 安装新版本tools或校准新policy默认。
- **THEN** SHALL 保持原gates/pin/证据，不被新必需字段追溯阻断，也不自动获得新预算。
- **AND** 对新policy CR，所有旧写入口同样执行新合同；TTY或旧grant不能绕过新规则。
- **AND** 删除本地合同字段不能降级legacy；合同归属从权威已提交注册与迁移历史验证。

#### Scenario: SC-EVD-007

- **GIVEN** tools、生成物、安装Agent/Skill、实际Runner版本或恢复能力有一项未知或不一致。
- **WHEN** 尝试启用新policy或删除旧接力。
- **THEN** SHALL 标记未就绪并保留旧安全恢复路径，不凭本地SHA声称上线完成。

#### Scenario: SC-EVD-008

- **GIVEN** 有权者明确迁移且旧授权、历史消耗和未决任务可核实；另有历史不可核实反例。
- **WHEN** 请求显式迁移。
- **THEN** SHALL 对可核实分支保留历史并计算剩余，对不可核实分支拒绝静默迁移或清零。

### Requirement: 发布与证据适用性独立于范围授权，恢复不重复消费。

#### Scenario: SC-EVD-009

- **GIVEN** 验收已通过但checkpoint/merge/writeback在既有发布事务边界失败。
- **WHEN** 恢复同一发布操作。
- **THEN** SHALL 复用原事务和业务receipt，不重复审批、修复扣额或cycle reset。

#### Scenario: SC-EVD-010

- **GIVEN** scope授权未变，但review后的实际subject/release tree或cycle已变化。
- **WHEN** 使用旧测试/评审证据请求当前交付。
- **THEN** SHALL 拒绝不适用证据并走最小必要重验，保留旧记录而不伪称当前PASS。
