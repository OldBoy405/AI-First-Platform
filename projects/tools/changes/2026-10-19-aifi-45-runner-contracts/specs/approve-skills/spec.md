# Spec: approve-skills

> Change: 2026-10-19-aifi-45-runner-contracts | Auto-generated Human View

## Requirements

### Requirement: 保持已有审批Skill只收尾当前审批且不代签的边界。

#### Scenario: SC-T-APP-001

- **GIVEN** 四个approve Skill已没有start/resume尾命令，只做审批收尾及next事实查询。
- **WHEN** 修订四阶段提示词并运行现有合同回归。
- **THEN** SHALL 保持现有正确职责，不引入下一阶段尾启动，不为制造diff无故改写Skill。
- **AND** 人类授权、grant/TTY、签名/证据与workspace隔离不被放宽。
- **AND** 默认路径不恢复dev-start审批卡，历史显式事实可兼容读取。
- **AND** Runner而非审批Agent负责批准后的正常阶段交接。

#### Scenario: SC-T-APP-002

- **GIVEN** 审批幂等重入或返回APPROVAL_DECLINED_ROLLED_BACK。
- **WHEN** 当前节点将权威结果返回给Runner。
- **THEN** SHALL 保留已完成审批事实与人工驳回的业务回退，停止当前正向路径，不沿旧grant继续或转技术retry。
- **AND** 是否修订和续接只依既有路由与输入合同，不新增一律自动重写政策。
- **AND** STDD Gate确认不是对任何真实业务CR的审批授权。
