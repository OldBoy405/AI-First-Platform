# Spec: periodic-runner-resume

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: 既有 30 秒 sweeper 有界续接活动 run，与事件/启动扫描共用协调逻辑

#### Scenario: M-SC-TICK-001

- **GIVEN** 四阶段活动 run 的唤醒事件丢失，或交接提交后尚未派发，没有新事件和手动命令
- **WHEN** 以可控时钟触发既有 runtime sweeper 的 30 秒周期
- **THEN** SHALL 按 pipeline 调用同一 Runner Reconcile 恢复持久执行，不需手动 start/resume/重启
- **AND** SHALL 不新增扫描服务、重试表或第二套编排

#### Scenario: M-SC-TICK-002

- **GIVEN** 活动 run 多于一批且某个 run 协调阻塞/失败，liveness 同时需处理
- **WHEN** 连续触发多个周期并到达回调超时
- **THEN** SHALL 限批、超时并隔离单 run 失败，后续 run 公平获得续接且不阻塞既有存活检测
- **AND** SHALL 批量/超时值先经隔离实测确认，文档不虚构吞吐或精确恢复 SLA

#### Scenario: M-SC-TICK-003

- **GIVEN** 同一活动节点同时收到事件、启动扫描和多个 tick
- **WHEN** 三种触发并发协调
- **THEN** SHALL 复用原锁与活跃 run/node/task 去重，最多创建一个有效执行，不重放已完成评审/审批
- **AND** SHALL 不因调度重复而增加技术预算或业务轮次

### Requirement: 暂态协调错误保留活动性，终态与业务等待不被越过

#### Scenario: M-SC-TICK-004

- **GIVEN** 活动 run 遇到短暂 DB/网络错误后基础设施恢复
- **WHEN** 当前 Reconcile 返回错误且后续周期再次执行
- **THEN** SHALL 暂态协调错误不立即 failRun，基础设施恢复后按持久节点继续且不重复派发
- **AND** SHALL 保留机器可读错误，非笼统把所有 platform 错误标可重试

#### Scenario: M-SC-TICK-005

- **GIVEN** 取消/失败/完成 run、人工 gate 或真实版本等待、技术预算耗尽的参数化夹具
- **WHEN** 周期扫描与协调
- **THEN** SHALL 不复活终态、不越人工 gate、不猜版本、不调用会抬预算的 ResumePipelineNodeTask
- **AND** SHALL 等待输入不消耗技术重试，预算耗尽明确停止并保留现场
