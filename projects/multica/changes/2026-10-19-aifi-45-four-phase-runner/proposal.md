# AIFI-45 四阶段统一 Runner（multica 平台侧）

<!-- source_hash: ba84881d2bf241f2 -->
<!-- generated_at: 2026-10-19T16:04:03.430640 -->
<!-- canonical: canonical/proposals/2026-10-19-aifi-45-four-phase-runner.yaml -->

## Why

注册后的四阶段只有需求、技术设计两段接到 Runner，其余阶段靠协调者转述、作者启动、
approve Skill 尾部 CLI 和 Leader 续接维持，已多次造成非业务阻断：KB 未被采集
（CR not found）、ack 报 leader-missing 拖住同批新记录、KB 缺公钥需人工复制、
设计期 RUNNER_SKILL_MISSING、coding/writeback 有模板投影却未真正接管执行、
一次唤醒失败后长期停住。根因是同一件事有多套推进路径（Runner/Leader/协调者/作者），
而不是缺少某个门禁或检查命令。


## What Changes

- M1 四阶段 Runner 底座：扩展 registry 派发覆盖 requirement-authoring、architecture-design、
code-implementation、feature-writeback；从既有节点执行收敛入队/等待/canonical 结果读取/
节点重入/人工 gate/reviewLoop；按 node_id 生成执行绑定（pipelineOwner + owns/can-call +
独立评审），删除 checkExecutorSkills 与对 executor_agent_id 的派发依赖；绑定与授权纳入既有
导出 digest。范围：internal/governance/runner*.go、registry 生成器、internal/handler/daemon.go
的 claim/carrier、现有任务服务。

- M2 开发期与既有上游设计回修接管：计划、任务、计划评审、finalize、freshness、实现、测试、
代码评审与审批收尾走 Runner；补齐 dev-plan/测试结果/upstream 路由投影；代码评审消费既有
release-subjects（不照搬设计评审的单一 subject_sha256）；review-dev-plan:upstream-design-blocker
走既有 tech-design-review-pending 与 repair-target；平台补齐设计合法重入与开发续接
（不能原样调用只接受 requirement-approved 的旧 StartArchitecture）。

- M3 合入、回写与归档接管：代码批准即授权既有合入/PRD-SDD 回写/任务回写/traceability/归档；
merge 返回 phase=release-drift 时按既有 code-approved → developing 接回开发（不沿旧 grant、
不技术重试 merge）；spec_id/target_version 从 crctl authority 继承；merge 后结束旧 task、
下一节点重新绑定 operational workspace；归档节点从不会被自身清理的安装根启动，
cleanup-pending 属业务成功，archived 事件不抢先关闭 Runner 所属 run。

- M4 统一持久交接：需求批准→设计、设计批准→开发、代码批准→交付，以及合法上游回修与
release-drift 回修，都走 Runner 统一交接；同一数据库事务（同一 pgx.Tx）持久化下游 run
可恢复 context 与上游完成/交接结果，提交并释放锁后再调用下游 Reconcile；入口状态不同的
回修使用已有合法转换；注册后首次接入复用既有 start/resume 内部分派，不新增命令或 flag。

- M5 ack 回归纯投递确认：delivered_at 只表示 grant 已投递；从正常 ack 路径删除
resolveContinuationTarget、EnqueueApprovalContinuation 及只为续接存在的整批回滚；
保留接入认证与 workspace 限定、workspace+record IDs 批量幂等更新；提交后按实际阶段唤醒
对应 Runner，单条失败不撤销其他 ack；终态 CR 不创建新执行，无活动 run 不回退 Leader 续接。

- M6 KB 一次接入：HTTP/WS heartbeat 增加可选 local_directory 资源快照（按 workspace/daemon
替换而非追加，成功空快照表示移除）；WS lease 带入鉴权查询已读到的 runtime daemon_id；
采集、Pipeline 定位、terminal settle、pending 与 ack 共用同一来源，collector 启动不再依赖
环境变量；pending 响应增加 public_key {key_id,pem}，顺序固定为公钥就绪 → grant 完整落盘 →
加入 ack IDs；移除 MULTICA_CR_WORKSPACES 作为根来源，不做新旧双模式。

- M7 周期续接与任务技术恢复：在既有 runtime sweeper 的 30 秒 tick 接入有界 Runner 回调，
限批、超时、隔离单 run 失败；暂态协调错误不立即终止 run，复用锁与活跃去重覆盖丢唤醒/提交后
未派发窗口；failed task 先识别已有 retry child、待补报结果与可恢复技术中断，复用
FailTaskWithTransition / MaybeRetryFailedTask；技术 attempt 与业务 reviewLoop attempt 分离，
不重置评审轮次、不抬高预算。

- 发布与存量（只设计非生产演练与操作顺序，真实部署/停服/存量恢复需另获明确授权）：
短维护窗口先暂停派发/领取/投递/ack，
完成旧执行收尾后再恢复正常领取；存量接管复用 M4 扩展后的同一受控入口，不覆盖 digest、
不做全量自动迁移；恢复后按 O2 重读权威 worktree 的 crctl status/next 接管 AIFI-45
（已完成需求且无设计执行者用既有 multica cr pipeline start 一次性补接）。


### New Capabilities

- **four-phase-runner-dispatch**：四个阶段的节点由 Registry 合同派发并由 Runner 执行，不再是只有投影 run
- **node-execution-binding**：按 node_id 确定的执行绑定（含共享 Skill 与独立 reviewer），不再取调用者
- **persistent-stage-handoff**：上游完成与下游可恢复 context 同事务持久化，阶段交接不依赖模型或协调者转述
- **kb-resource-adoption**：项目目录资源经 heartbeat 下发，采集/定位/投递同源，无需逐 KB 配环境变量
- **public-key-grant-delivery**：签发公钥与 grant 同一通道就绪后 ack，新 KB 不再人工拷 key
- **periodic-runner-resume**：既有 sweeper tick 周期续接活动 run，暂态故障与丢唤醒自行恢复

### Modified Capabilities

- **approval-ack**：ack 只表示投递完成，删除 Leader 解析与审批续接分支
- **dev-phase-runner**：开发 Pipeline 的既有节点与既有回修由 Runner 接管，节点集合以模板为准
- **delivery-runner**：合入、回写、归档由 Runner 接管，release-drift 按既有业务回退接回开发
- **task-recovery**：技术重试与终态补报复用既有机制，与业务 reviewLoop 轮次分离

## Success Criteria

- [ ] 四个 pipeline 的节点由 registry 派发并实际执行：存在 claim、任务、canonical 结果与恢复记录，不是只有投影 run
- [ ] 派发按 node_id 执行绑定决定；共享 Skill 交给已授权阶段 Agent、独立 reviewer 不变；代码中不再有 checkExecutorSkills 与 executor_agent_id 派发依赖
- [ ] 三个既有审批通过后，下一阶段自动分配；并发/重入与交接提交前后注入故障不漏接、不重复派发、不需作者补命令
- [ ] 开发期：任务账本、真实 testCr 执行结果、dev-plan/code 证据被正确消费；普通 BLOCK 按既有 reviewLoop 回修，task completed 不被当业务成功
- [ ] 上游回修：同 CR 先技术复评再必要修订、重审、既有设计审批并恢复开发，不沿旧 PASS、不重置轮次
- [ ] merge 返回 phase=release-drift 且退出 0 时停止交付、接回既有开发回修并重走审批，不沿旧 code grant 合入
- [ ] ack 路径不解析 Leader、不派审批续接；单条 CR 唤醒失败不撤销其他 ack；无活动 run/终态/旧 grant 均不产生假推进
- [ ] KB 接入：资源已指向 KB 时不需另填环境变量；无任务冷启动、目录稍后出现、改路径、删除、断网恢复均收敛；请求 workspace 正确，不串根串批
- [ ] 公钥投递：新 KB 不手拷当前 key；目标 key 与 grant 就绪才 ack；冲突/缺 key/写失败/目标歧义不 ack 且不假成功；已有 key 不被覆盖
- [ ] 自动恢复：注入短暂数据库/网络故障、丢失事件、进程中断后无需手动 start/resume/重启；已有 retry child 与终态补报不被误判为业务终结
- [ ] Agent 重试不增加预算、不重置 reviewLoop；耗尽明确停止；取消不复活；权限/签名/证据冲突不盲重试；人工 gate 不被绕过
- [ ] AIFI-45 存量接管后可从权威 worktree 的 status/next 继续进入设计（不重复审批、不批量改历史、不手改数据库）
