# Spec: node-execution-binding

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: JSON nodeId（DB/Go 内部 node_id）唯一决定派发绑定，共享 Skill 不改变授权和独立评审

#### Scenario: M-SC-BINDING-001

- **GIVEN** coding 两个不同 JSON nodeId 复用同一 ref，具有不同节点上下文，DB/Go 内部映射为 node_id
- **WHEN** 两节点分别导出绑定、入队并按需重入
- **THEN** SHALL 按 pipeline 和 JSON nodeId 消费绑定及轮次，不按 ref 合并执行或复用错误结果，不另导出 node_id 同义字段
- **AND** SHALL 每个非 human 节点恰一条 nodePermissions {nodeId,ref,owner,pipelineOwnerCanCall,executor}，由原模板/matrix 派生并纳入 digest；executor 为 actor key、普通节点默认 pipelineOwner、独立 review 可在原节点声明，通过同 workspace agentByName 解析真实 Agent

#### Scenario: M-SC-BINDING-002

- **GIVEN** checkpoint/freshness 是共享 Skill，当前阶段作者和独立 reviewer 均已授权，节点序列另含 human gate
- **WHEN** 派发共享节点、评审节点并到达 human gate
- **THEN** SHALL 共享节点交已授权阶段 Agent，评审节点交独立 reviewer，作者不得自评；human gate 保留但不派 Agent 或创建执行 task
- **AND** SHALL owner 仅为 Skill 维护归属，不等于 executor actor key，不给逻辑 system 新建执行 Agent；executor 必须为真实 kind=agent，并验证 active Skill、唯一 owns、owns/can-call 和 forbidden

### Requirement: 运行时只验证 registry executor actor 绑定，不从调用者或历史 executor_agent_id 回退

#### Scenario: M-SC-BINDING-003

- **GIVEN** 调用者缺其他节点 Skill，旧 run executor_agent_id 与当前节点绑定不同
- **WHEN** StartArchitecture 与 enqueueNode 派发合法绑定节点
- **THEN** SHALL 不要求调用者拥有全部 Skill，不以 executor_agent_id 决定派发，并删除 checkExecutorSkills 路径
- **AND** SHALL 不批量改写旧 run executor_agent_id 字段，也不自动改派旧 queued/running task

#### Scenario: M-SC-BINDING-004

- **GIVEN** 绑定 agent 分别为跨 workspace、已归档、缺 runtime、缺节点能力或未授权，另有可用调用者
- **WHEN** 通过既有 agentByName 和任务约束校验节点执行者
- **THEN** SHALL 对每种非法绑定失败关闭，不回退调用者、Skill owner 或任意可用 agent
- **AND** SHALL 保留认证、来源与独立评审边界

### Requirement: source provenance 与 executor 分离，来源可完成但不可伪造

#### Scenario: M-SC-BINDING-005

- **GIVEN** 已完成 source task 有真实 agent、workspace、issue/project、originator/accountable 和 started_by
- **WHEN** 下游节点经 PipelineTaskSpec 入队
- **THEN** SHALL 保留 SourceTaskID 及原归因，ExecutorAgentID 单独取节点绑定，来源 task 完成不阻断合法交接
- **AND** SHALL 不将节点 owner 伪作来源调用者、协调者或审批人

#### Scenario: M-SC-BINDING-006

- **GIVEN** 来源 source task 缺真实身份、跨 workspace 或与 CR/project 不一致
- **WHEN** 创建或恢复 run 并校验上下文
- **THEN** SHALL 拒绝伪造或跨边界归因，不以绑定正确掩盖 source 非法
- **AND** SHALL 保留原错误供受控恢复，不补造 CR/TASK 编号
