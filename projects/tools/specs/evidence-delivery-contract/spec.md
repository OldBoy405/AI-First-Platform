# Spec: evidence-delivery-contract

> Change: 2026-10-22-aifi-45-authorized-execution + 2026-11-08-aifi45-trust-anchor-chain + 2026-11-18-defensive-trim-tools (merged) | Auto-generated Human View

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

### Requirement: 注册与归档只能把交付事实写入已验证归属的当前项目。

#### Scenario: SC-TAC-009

- **GIVEN** 平台当前claim已给出CR/project及对应注册或归档授权，daemon证明、原bytes来源、key_id、当前scope/head与实际安装根均匹配；register的registration key与本地候选CR也一致。
- **WHEN** daemon请求register或archive首次业务写入。
- **THEN** SHALL 在任何registry、CR、归档journal或交付事实写入前通过同一控制准入信任缝，再沿既有workspace事务完成注册或归档。
- **AND** register若无法在任何持久化前证明平台CR/claim与本地候选CR一致，SHALL失败关闭而非先注册后补证明。
- **AND** 已提交register/archive重放SHALL只恢复原journal/receipt，不重复准入或生成第二条交付事实。

#### Scenario: SC-TAC-010

- **GIVEN** register或archive使用缺失/跨project/跨安装根复制的证明、改一字的来源、不可信公钥、错误scope、旧head或已撤销授权。
- **WHEN** 逐项请求首次注册或归档写入。
- **THEN** SHALL 全部失败关闭，不占用registration key，不创建CR/worktree/registry记录，不写归档journal、交付记录、Git/index或平台任务。
- **AND** 环境变量、sidecar、同名CR、图路径或有效但属于其他project的签名SHALL不得使交付事实获得当前project归属。

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
