# Spec: node-execution-binding-contract

> Change: 2026-10-19-aifi-45-runner-contracts | Auto-generated Human View

## Requirements

### Requirement: Skill维护归属与每节点实际执行者分离，nodeId是绑定键。

#### Scenario: SC-T-BIND-001

- **GIVEN** 阶段pipelineOwner已获授权，push-progress或workspace-freshness由逻辑system actor owns。
- **WHEN** emitter导出该共享节点的派发合同。
- **THEN** SHALL 保留维护owner并将executor绑定到已授权的真实阶段Agent，不给system创建执行Agent。
- **AND** 每个非human节点有且仅有一项nodePermissions并含nodeId、ref、owner、executor。
- **AND** 来源task的调用者不参与临时选择executor。

#### Scenario: SC-T-BIND-002

- **GIVEN** 需求、设计或coding的独立评审节点，且作者具有review Skill的can-call。
- **WHEN** 从现有模板声明与matrix解析executor。
- **THEN** SHALL 将review节点绑定到独立reviewer并拒绝作者同人自审。
- **AND** active Skill、唯一owns、kind=agent、owns/can-call和forbidden校验均保留。
- **AND** 无合法绑定时失败关闭，不按可用性/调用者/Skill owner临时回退。

#### Scenario: SC-T-BIND-003

- **GIVEN** coding中两个write-dev-tasks节点和两个workspace-freshness节点ref分别相同但UUID不同。
- **WHEN** 导出并由平台parser消费权限与执行绑定。
- **THEN** SHALL 按nodeId保留所有独立绑定与节点顺序，不以ref唯一索引覆盖或拒绝合法重复节点。
- **AND** 重复nodeId或缺失绑定硬失败，不能静默降级。
- **AND** human_approval保留为等待节点而非可派发Agent任务。
