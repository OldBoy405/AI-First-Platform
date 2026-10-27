# Spec: dev-phase-runner

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: 开发既有节点由 Runner 执行且消费真实账本/测试/评审证据

#### Scenario: M-SC-DEV-001

- **GIVEN** 合法设计批准交接到 code-implementation，模板提供开发节点和 loop
- **WHEN** Runner 推进计划、TASK、计划评审、finalize、freshness、实现、testCr、代码评审及审批收尾
- **THEN** SHALL 执行既有节点并读取账本和 testCr 真实执行结果，不用报告存在或 task completed 替代业务成功
- **AND** SHALL 不新增业务节点/默认 dev-start 卡，不把协调者转述当续接条件

#### Scenario: M-SC-DEV-002

- **GIVEN** dev-plan、test 及 upstream 结果通过 daemon crevents 回传到 gate projection
- **WHEN** buildReviewPayload/applyReview 消费匹配和不匹配 CR/节点/轮次的结果
- **THEN** SHALL 正确投影匹配结果与 upstream 路由，并拒绝错归属/过期结果，不吞掉测试失败或业务 BLOCK
- **AND** SHALL 保留原 canonical 与证据来源，不以投影替代执行

#### Scenario: M-SC-DEV-003

- **GIVEN** 代码评审有匹配和漂移的 release-subjects，单一设计 subject_sha256 即使相同
- **WHEN** Runner 消费代码评审及后续审批证据
- **THEN** SHALL 按既有 release-subjects 核验当前代码证据，漂移不沿用旧 PASS，不套用设计单 subject 判定
- **AND** SHALL 保留独立 reviewer 和人工代码审批

### Requirement: 普通 BLOCK 和上游设计 blocker 按各自既有业务链处理

#### Scenario: M-SC-DEV-004

- **GIVEN** 计划、测试或代码结果分别返回普通 BLOCK
- **WHEN** Runner 解释模板 reviewLoop/replayNodes 和当前轮次
- **THEN** SHALL 按各自 loop 回修并重放必要证据，保留业务次数，不把 BLOCK 作为技术任务重试
- **AND** SHALL 不重置轮次、不让协调者评论接力，不因 failed task 提前假完成节点

#### Scenario: M-SC-DEV-005

- **GIVEN** review-dev-plan 返回 upstream-design-blocker 及 repair-target
- **WHEN** 从 task-breakdown 接回上游设计
- **THEN** SHALL 走既有 tech-design-review-pending 先技术复评，确认 BLOCK 后才合法转编写，不直接跳 tech-designing
- **AND** SHALL 不沿旧 PASS 直接审批、不新建 CR/审批节点，不原样调用仅接受 requirement-approved 的旧 StartArchitecture

#### Scenario: M-SC-DEV-006

- **GIVEN** 同 CR 上游设计已必要修订、独立重审并获既有人工设计批准，开发 run 正按原路由等待
- **WHEN** 持久交接恢复开发
- **THEN** SHALL 按原增量规则修订计划/TASK 并继续开发，不沿旧证据、不重置无关业务轮次或复活旧终态 run
- **AND** SHALL 不新增回修等待业务状态，合法新设计 cycle 仍受原授权和 digest 校验

### Requirement: 真实版本和元数据输入等待只沿既有业务输入流程

#### Scenario: M-SC-DEV-007

- **GIVEN** 注册允许 unassigned，但需求评审前真实版本缺失，或后续版本修改导致证据摘要改变
- **WHEN** Runner 等待负责人确认并消费既有 version-set 后的 authority
- **THEN** SHALL 不猜版本、不让用户重复填交付元数据，确认后自动继续且晚改版本不得沿旧评审/grant
- **AND** SHALL 等待人类输入不消耗技术重试、不新加审批或表单
