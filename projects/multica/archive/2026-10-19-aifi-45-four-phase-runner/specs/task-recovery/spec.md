# Spec: task-recovery

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: failed task 先识别技术恢复事实，再决定 run 终态

#### Scenario: M-SC-RECOVERY-001

- **GIVEN** reconcileSkillTask/reconcileRequirementNode 看到 failed parent，已有 queued/running/completed retry child
- **WHEN** Runner 协调该节点
- **THEN** SHALL 先识别并跟随已有 retry child，不先 failRun、不重复创建 child，完成者仍经 canonical 核验
- **AND** SHALL 复用原 node-run、责任人、权限和审批授权

#### Scenario: M-SC-RECOVERY-002

- **GIVEN** failed task 有待终态补报或可证明幂等且无需新输入的技术恢复，预算尚足
- **WHEN** Runner/TaskService 判定恢复
- **THEN** SHALL 先辨别待补报与恢复分类，再复用 FailTaskWithTransition/MaybeRetryFailedTask 及原退避，不先终止 run
- **AND** SHALL 不为每次 tick 新建 attempt，不重复执行已完成评审/审批

### Requirement: 结构化 recovery 和终态补报在进程中断后仍可安全续接

#### Scenario: M-SC-RECOVERY-003

- **GIVEN** settleCREventsForTask 失败，进程退出前将 failure_reason、crctl 错误码、structured recovery/journal 引用入原终态队列
- **WHEN** daemon 恢复并消费 terminal_report_queue
- **THEN** SHALL 保留并消费原权限内已证明安全的 recovery argv，不只重放 HTTP，不把未 settle 结果伪报业务终结
- **AND** SHALL 重放幂等，不新增补偿文件、执行器或重试表

#### Scenario: M-SC-RECOVERY-004

- **GIVEN** 原结构化恢复受当前权限/签名/证据约束，另有仅自由文本建议或来源/argv 被篡改的载体
- **WHEN** daemon 判断是否执行恢复
- **THEN** SHALL 仅执行原权限内无新输入的安全幂等恢复，拒绝文字猜测、身份或参数篡改
- **AND** SHALL 保留机器错误和 recovery 到既有 run/终态记录，不新增运行时报告

### Requirement: 技术预算与业务评审轮次分离且恢复有停止边界

#### Scenario: M-SC-RECOVERY-005

- **GIVEN** 同一节点有技术 attempt 与业务 reviewLoop attempt，分别处于可重试和预算耗尽情形
- **WHEN** 技术恢复及周期协调
- **THEN** SHALL 仅按原预算/退避增加必要技术 attempt，不重置业务轮次或自动抬预算，耗尽明确停止并保留现场
- **AND** SHALL 不把会加预算的人工 ResumePipelineNodeTask 接到 tick

#### Scenario: M-SC-RECOVERY-006

- **GIVEN** TX_GIT_FAILED/process_failure 混合类，另有认证、余额、权限、签名/证据冲突和明确安全暂态子类
- **WHEN** 分类失败原因
- **THEN** SHALL 不将混合类整体加入重试白名单，只有可证明安全暂态子类走既有恢复，其余不盲重试
- **AND** SHALL 不让模型依据错误文字猜授权或绕过证据

#### Scenario: M-SC-RECOVERY-007

- **GIVEN** 业务 BLOCK、人工驳回、release-drift、版本/人工 gate 等待及显式取消/既有失败终态的夹具
- **WHEN** failed task 判断与周期恢复
- **THEN** SHALL 业务结果走各自既有路由，等待不耗重试，显式取消/失败终态不复活且不越过人工 gate
- **AND** SHALL 不把自动恢复解释为无限 Agent 重跑或已耗尽后仍保证全自动
