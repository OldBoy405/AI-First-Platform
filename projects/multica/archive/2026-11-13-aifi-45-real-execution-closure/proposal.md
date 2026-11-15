# AIFI-45：真实 daemon+agent 授权执行闭环（节点证据、受控停止、删除后终态安全）

<!-- source_hash: 6abc2dc4cdbe4c3f -->
<!-- generated_at: 2026-11-13T20:04:35.837122 -->
<!-- canonical: canonical/proposals/2026-11-13-aifi-45-real-execution-closure.yaml -->

## Why

AIFI-45 的准入、签发、发现、一次性库入口都已在组件级交付，但「一个充分授权的新变更，经真实 daemon 和
真实 agent，能产生节点回执并被推进」从未被真实运行证明。admission-task-binding（2026-11-11，已归档）
把完成类动作锚在节点自己的任务上，并在报告里把「真实 daemon+agent 跑一次架构 run」列为未验证的上线前置；
其 design 称节点证据的生产者修复「属于 daemon/T 的后继 change」，且承认无法从服务端代码证明生产中的节点
agent 一定会请求 binding proof（永久等待是已接受的 fail-closed 风险，不是已验证的发生率）。本变更就是该后继。

本会话只读核对得到的事实（读代码与记录得出，均未运行）：
1) 节点证据的生产链：daemon 对带 CR 的 run 在环境里放一个单次 endpoint（MULTICA_EXECUTION_BINDING_ENDPOINT），
   run 结束时仅当该 endpoint 实际签出过 challenge 才写 consumption 回执（daemon.go 约 8765–8777；
   execution_binding_endpoint.go）。唯一的请求方是 crctl 的 requestExecutionBinding，且只经
   requireControlAdmission 调用，即只有 advance / repair-admit / repair-resume / authorization-bind /
   register / archive 这些控制写会触发（control-admission.mjs:94，crctl.mjs 五个调用点）。
2) 节点注册表提示词直接调用的 crctl 只有只读的 workspace inspect 与 next；控制写由节点 skill 内部的
   crctl advance 触发，且有的 skill 在某些状态下会跳过 advance（例如 write-tech-design 在 status 已为
   tech-designing 时直接续写）。因此回执是否产生取决于该节点 run 是否恰好走到一次门控 advance —— 假设 H1。
3) endpoint 是单次一证：第一个 challenge 获胜，同一 challenge 可重试，不同 challenge 返回 409
   （claim()）；challenge 含每次随机的 32 字节。因此若同一 run 内出现第二次门控 advance，它取不到证明 ——
   假设 H2。目前没有例证：write-dev-tasks 的 split 与 finalize 是互斥模式、各为独立节点，单次执行只有一次
   advance；是否存在其他节点会在一个 run 内做多次门控写，需逐节点核对，核对不到则 H2 作废。
   H1/H2 在现有三份归档设计里都没有记载；均须先由本地探针回答，再谈方案。
4) 生产中只有两个 run 启动入口：StartArchitecture（runner.go:1924）与 StartRequirement
   （runner_requirement_entry.go:362）；周期发现 ResumeActiveRuns（runner.go:1825）按 admission-task-binding
   的核查只覆盖这两类（复核：只调 StartupScan 与 StartupScanRequirement）。没有 code 类 run 的生产启动或派发
   入口：gate 投影会按 CR 状态为 code-implementation 建 run 行（gate_projection.go、crsync.go），但不派发任务，
   ReconcileCode（runner_code.go）没有非测试调用方。所以 SC-RUN-007 所说的「开发、回写」阶段在生产中现有
   入口无法推进；M008（merge 效果恢复）的真实恢复入口依赖回写阶段，随之不可达。
5) 删除 workspace 后：reservation 顺序路径已拒绝（fork-ci 变更 R5），command 半句是用户裁定保留的红灯
   （ADJ-017）；根因是 ApplyControlCommandTx 唯一的生产调用方把消费回执 id 当作 ReservationID 传入
   （execution_control_store_state.go:148），照 reservation 的做法加查找会直接断生产路径，需要另一套边界；
   reservation 的并发窗口也未处理。
6) 登记状态：M007（五项合同裁定）、M008（可信 no-effect 与重新准入）、M010（跨仓投递身份）均为
   successor_change、resolved:false；M008 条款已批准，实现与证据未完成。

已完成、本变更复用不重做：准入按任务+generation 绑定（23 个选择 292 PASS）、consumption effect 签发
（M005）、信任锚链 TAC 系列与 Linux 公钥隔离、周期发现与重启去重（组件级）、一次性库 supervisor。


## What Changes

- 先用不带模型的本地探针在一次性库内回答 H1/H2：逐节点列出（需求、架构两条 run）会走几次门控控制写；单次一证 endpoint 对同 run 第二个不同 challenge 的实际行为。结论写入 design 的已回答事实，再据此在 SPEC 阶段裁定节点证据的生产方式（技能侧保证每节点恰一次门控写，或 daemon 侧为节点任务自取证明）。不预选方案，不放宽验证方（沿用 admission-task-binding Q1：完成类动作仍锚在节点自有任务）。
- 按 C1 裁定的方案补齐节点证据的生产者，使节点任务在推进前有自己当前 generation 的 consumption 回执与自身 effect；复用既有准入、签发、发现入口，不新增 journal、outbox 或第二套账本。
- 真实运行验证：在获授权的一次性环境中，以真实认证入口签发的授权，经真实 daemon+真实 agent 跑 architecture run（需求 run 视成本经 Gate 2 决定是否同跑），含节点交接处一次重启。
- 受控停止：真实运行中撤销授权后，run 不再派发新节点任务、不推进，状态可查询且重启后保持；不删历史。RUN-006 的「额度用尽后最后已准入修复可完成」分支是否纳入见待裁定 Q5。
- workspace 删除后的终态安全：为 command 创建加 workspace 边界且不破坏消费回执契约，使 TestWorkspaceDeletionRefusesNewCommand 由红转绿（断言不放宽）；处理 reservation 创建与 workspace 删除的并发窗口。不含 command/cursor 收敛转移，不删保留的历史证据。
- 按 CUSTOM.md 现行结构登记定制；全组既有 selections 在一次性库上回归；STDD 追溯用 change id，不编造 CR 编号；若触及 daemon.go，顺带校正 recordConsumptionAfterDelivery 的陈旧注释（注释称生产为 false，New() 实际设为 true）。

### New Capabilities

- **real-execution-closure**：充分授权的新变更经真实 daemon+agent：授权来源可核实、节点证据由生产者产生、推进由发现路径驱动、重启不重复、撤销后不推进；节点证据的生产方式在本变更内裁定。

### Modified Capabilities

- **authorized-runner**：SC-RUN-001 的真实入口、SC-RUN-007 的真实发现与重启恢复范围收敛到 requirement 与 architecture 两类 run；SC-RUN-006 取撤销后不推进的最小闭合，其余分支见 Q5。
- **workspace-delete-execution-tables**：SC-WSD-005 的 command 半句由已声明红灯转为满足，并补 reservation 并发窗口。

## Success Criteria

- [ ] 真实链路：在获授权的一次性环境中，真实 daemon + 真实 agent 对一个新 CR 完成一次 architecture run；每个被推进的节点，在推进前都有该节点任务当前 generation 的 consumption 回执与自身 effect，没有借用 source 或他任务的消费事实；run 到达架构人工门。
- [ ] 真实来源：同一次运行使用的授权由真实认证的 owner/admin 请求签发，而非 fixture 签名；T 侧从原请求字节独立重提取的来源与之一致；对同一授权改一个来源字段而不改签名，T 侧拒绝。
- [ ] 重启与去重：在节点交接处重启 daemon/服务一次后，发现路径使每个节点恰有一个任务（无重复、无遗漏），已推进的节点不回退。
- [ ] 受控停止：运行中撤销授权后，run 不再派发新节点任务、不推进节点，状态可被查询为 fail-closed，重启后保持；已有历史行未删除。
- [ ] 终态安全：workspace 删除后，创建 command 被拒（TestWorkspaceDeletionRefusesNewCommand 由红转绿，断言未放宽）；reservation 创建与 workspace 删除并发时不留下删除后的新行（一个并发探针）；消费回执契约与保留的历史行不变。
- [ ] 不回归：既有 selections 全组在一次性库上 0 FAIL、0 skip；diff 内没有无关改动，没有第二套账本；首次真实运行若失败，停在止损点并记录失败节点与原因，不继续宣称后续保证。
