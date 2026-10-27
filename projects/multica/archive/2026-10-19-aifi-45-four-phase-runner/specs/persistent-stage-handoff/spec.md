# Spec: persistent-stage-handoff

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: 三类批准后的阶段分配由同一持久事务交接完成

#### Scenario: M-SC-HANDOFF-001

- **GIVEN** 需求、设计、代码批准事实分别已合法存在，具备原 source context
- **WHEN** Runner 消费三个批准的参数化夹具
- **THEN** SHALL 分别自动分配设计、开发、交付，使用同一 pgx.Tx 保存下游可恢复 context/run 与上游完成/交接结果
- **AND** SHALL 所有相关查询/upsert/update 均用该 Tx，不在内部回落 r.pool
- **AND** SHALL 不要求作者补命令或 approve Skill 尾部启动

#### Scenario: M-SC-HANDOFF-002

- **GIVEN** 下游 upsert、context 或上游完成结果写入任一步骤在 commit 前失败
- **WHEN** 故障注入使交接事务回滚并再次 Reconcile
- **THEN** SHALL 不出现半份交接，下游不得提前派发，上游保留可续接性且既有批准事实不撤销
- **AND** SHALL 恢复后只产生一个有效下游执行

#### Scenario: M-SC-HANDOFF-003

- **GIVEN** 同一批准被事件、启动扫描和周期续接并发消费，另有同步事件订阅者会调用 Reconcile
- **WHEN** 交接提交并触发下游协调
- **THEN** SHALL 先 commit 并释放事务连接及上游锁，再调用 Reconcile 或发布可递归的同步事件
- **AND** SHALL 复用活跃 run/node/task 去重，不嵌套拿锁、不重复派发
- **AND** SHALL 事务内不派 task、不调用带 Reconcile 的完整公开 starter

### Requirement: 可恢复 context 覆盖提交后崩溃且保持入口权限边界

#### Scenario: M-SC-HANDOFF-004

- **GIVEN** 交接已 commit、锁已释放，但进程在下游 Reconcile 前中断
- **WHEN** 既有扫描或 30 秒周期恢复下游 run
- **THEN** SHALL 从持久 context 恢复四阶段所需 digest/workspace/source/started_by 并完成唯一派发，不需手动 start/resume
- **AND** SHALL 复用 recordRequirementRunContext/restoreRequirementRunTx 模式，不新增交接账本

#### Scenario: M-SC-HANDOFF-005

- **GIVEN** 上游设计复评或 release-drift 已由既有状态转换合法触发，原阶段 run 可能已完成
- **WHEN** 同一内部创建/接管逻辑按该入口状态恢复执行
- **THEN** SHALL 使用合法回修 cycle/context 而非原样调用只接受 requirement-approved 的 StartArchitecture
- **AND** SHALL 不复活历史完成/失败/取消记录，不任意重置评审轮次，不沿旧 PASS/grant

#### Scenario: M-SC-HANDOFF-006

- **GIVEN** 已有下游失败、取消或完成记录且没有合法业务回修，或 digest/context 矛盾
- **WHEN** 普通交接发现没有活动 run
- **THEN** SHALL 不以无活动 run 为由自动重开，保留错误并要求既有受控恢复校验
- **AND** SHALL 不覆盖存量 digest、不扩展普通 start 的任意重启权限

### Requirement: 注册首次接入与人工驳回使用原入口和原业务合同

#### Scenario: M-SC-HANDOFF-007

- **GIVEN** 注册已提交但 Runner 首次接入尚未完成，原注册/source 事实可读取
- **WHEN** 既有接入路径重入
- **THEN** SHALL 确定性复用 start/resume 内部分派且幂等接入，不新增命令/flag 或人工启动待办
- **AND** SHALL 不宣称 Git 和平台 DB 跨库原子，不重做 AIFI-71 注册事务

#### Scenario: M-SC-HANDOFF-008

- **GIVEN** 当前审批返回 APPROVAL_DECLINED_ROLLED_BACK 且原状态机已完成业务回退
- **WHEN** Runner 消费审批结果
- **THEN** SHALL 停止正向交接，遵守原 Pipeline abort/等待输入合同，不技术重试、不沿旧 grant
- **AND** SHALL 不增加驳回后一律自动重写的政策或新增审批

### Requirement: 发布及 AIFI-45 存量接管仅作为另行授权前的演练设计

#### Scenario: M-SC-HANDOFF-009

- **GIVEN** 隔离快照包含旧运行任务、旧续接、权威 worktree requirement-approved、主 checkout 旧快照及有/无设计执行两类记录
- **WHEN** 在非生产夹具演练短维护窗口及 O2 决策，不执行真实部署/停服/恢复
- **THEN** SHALL 先暂停派发/领取/投递/ack 并确认旧执行退出，再核对配套版本和受控 context/digest，最后恢复统一调度
- **AND** SHALL 重读权威 status/next 及投影/run/task，无设计执行才模拟既有 pipeline start 一次补接，有执行用扩展受控入口
- **AND** SHALL 不重复批准、不手改 DB/CR/账本、不覆盖 digest、不全量迁移、不混跑旧 daemon
- **AND** SHALL 全部主线验收后才考虑维护 Issue in_review，真实操作必须另获授权
