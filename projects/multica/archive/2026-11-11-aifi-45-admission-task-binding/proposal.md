# AIFI-45：准入按任务／generation 绑定消费事实，并以真实 consumption 路由与发现路径验证推进

<!-- source_hash: 345d3ccdfc51c7b3 -->
<!-- generated_at: 2026-11-11T19:11:29.422202 -->
<!-- canonical: canonical/proposals/2026-11-11-aifi-45-admission-task-binding.yaml -->

## Why

准入决策器 DecideAdmission 是 CR 级判定：只要该 CR 下有任意一条 consumption 回执，且任意一个 task 的
effect 结算通过校验，所有受保护动作（节点 markNode(passed)、人工门 passHumanApprovalNode、
enqueueNodeFor / enqueueRequirementNode 派发）都被放行。AdmissionRequest.TaskID 是预留接缝，
不参与任何判定。后果是消费事实可被借用：
- TC-RUN-003 用一个随机 UUID 的"消费 task"（既不是 run 的 source 任务，也不是任何节点任务）的回执、
  结算和 verdict，在最后一个阶段开放了派发；
- 回执按 (workspace, cr, runtime, task, dispatched_at) 即 generation 记录，effect 按 task 只签一次
  （M005 已批准），但准入既不比较 generation，也不要求回执对应受保护动作所涉任务；
- 取"CR 内最近一条 effect"验证，被验证的 verdict 与被计数的回执不一定是同一个 task。
M005 起平台按 task 签发 effect（request_id = task id），任务级绑定第一次有了可依赖的事实载体。
SC-RUN-003 原文即为"对应 task 的平台 consumption effect 提交后才推进"，现实现只做到"CR 内有某个"。

只读核查得到的、决定设计边界的事实（读代码得出，未运行）：
1) 首个任务不是 Runner 创建的。run 由 StartArchitecture / StartRequirement 在一个已存在的 source 任务
   （task-token 的 X-Task-ID）下登记，随即首次 Reconcile；checkSourceTask 允许 source 的 cr_id 为 NULL。
2) 只有触发评论里声明 context.execution.contract 的任务才走 daemon 的 strict preflight，在 agent 启动前
   消费；这是授权入口任务（即典型的 source 任务）。Runner 入队的节点任务触发内容为空、不走 strict，其
   consumption 只有在 agent 经 binding endpoint 取得证明后由 daemon 在运行结束时延迟写入。
   因此：a) 派发前不可能存在 run 内节点任务的消费——首次派发若要求节点任务的消费就是循环依赖；
   b) 节点任务在生产中是否都会产生 consumption，本次核查没有证据（取舍见 risk_areas 第一项）。
3) consumption 提交不发布任何事件或 wake；执行 ACK 与 binding 签发同样不唤醒。等待→推进只能依赖既有
   事件（CR 更新、节点任务完成／失败、非执行类 ACK）或周期发现 ResumeActiveRuns（启动扫描 + 30s sweeper）。
   该发现路径只覆盖 architecture 与 requirement 两类 run，不覆盖 code 类 run，且未找到 code run 的生产启动入口。
4) 任务 generation = (task id, runtime_id, dispatched_at)：同一 task id 被重新认领会刷新 dispatched_at；
   技术重试则新建 task 行（retry_of / parent 保留），不是同 id。


## What Changes

- 准入请求用 TaskID 命名它所依赖的锚点任务；DecideAdmission 只认该 task：(a) 回执 CR 等于请求 CR 且 task 等于锚点；(b) 回执的 runtime_id + dispatched_at 等于锚点 task 行当前的 generation；(c) 以该 task 自己的 effect 结算及其 verdict 走既有链校验，不再取 CR 内「最近一条」。锚点缺失、无当前 generation 的回执一律等待（WAIT_CONSUMPTION），无 effect／verdict 校验不过等待（WAIT_TRUSTED_T_COMMIT）；TaskID 为空是调用方缺陷（ErrAdmissionInvalid）。判定原因的稳定字符串集合不扩大。
- 确定受保护动作到锚点任务的映射并落到调用点：完成一个有自有任务的节点（markNode(passed)）→ 该节点当前选中的任务；无自有任务的动作（两条派发路径、人工门、被跳过而无任务的节点）→ 该 run 的授权入口 source 任务（execution_context.source_task_id）。不使用「CR 内任意／最近任务」。映射表写入 design，并有逐动作用例。
- 首次派发锚在 run 的 source 任务：不要求任何 run 内节点任务的消费，避免循环依赖；source 无当前 generation 回执时只等待、不放行（失败关闭）。
- 不新增 wake。等待→推进的验证走真实 consumption 路由提交回执，再由系统实际的发现路径（ResumeActiveRuns）推进；断言提交后、发现前没有任务入队，重复发现不重复派发。
- 测试：把依赖「CR 内任意 task 的消费事实」的既有 fixture（TC-RUN-003 的随机消费 task 等）改成命名锚点任务；新增任务／generation 错配、合法重放、真实路由到发现推进的串联用例，在获授权的一次性库上跑 selections 全组回归。
- 校正 execution_admission.go 里「TaskID 预留接缝」「按 CR 计数」的陈旧注释；按 CUSTOM.md 现行结构登记定制。

### New Capabilities

- **admission-task-binding**：每个受保护动作的准入只依赖一个明确的锚点任务及其当前 generation 的消费回执和该任务自己的 effect；错配拒绝，合法重放不改变结论。

### Modified Capabilities

- **authorized-runner**：SC-RUN-003 的「对应 task 的 consumption effect」落实为锚点任务规则；首次派发的锚点为 source 任务；其余场景不变。

## Success Criteria

- [ ] 同一 CR 里，仅有另一个 task（含与该 run 无关的 task）的回执与 effect 时，四类受保护动作均不放行：节点不置 passed、不入队、人工门不通过，原因为 WAIT_CONSUMPTION；TC-RUN-003 对应阶段改为命名锚点后仍成立。
- [ ] 锚点任务有其当前 generation 的回执、自己的 effect 与通过校验的 verdict 时，该动作放行；锚点任务只有旧 generation 回执（任务被重新认领，dispatched_at 已变）时为 WAIT_CONSUMPTION；同 task 新 generation 经真实路由提交回执后放行，且该 task 的 command／verdict／settlement 仍各为 1 条。
- [ ] design 给出受保护动作到锚点的映射表，测试对每个动作至少覆盖一个「借用他任务的消费事实被拒」和一个「用对任务放行」用例。
- [ ] 首次派发：run 的 source 任务有当前 generation 回执与 effect 时成功派发，不需要任何节点任务的回执；source 无回执时只等待。
- [ ] 真实串联（一次性库）：经真实 consumption 路由提交 source 回执（201）后，在发现路径运行前没有任务入队；ResumeActiveRuns 一次后恰有 1 个首节点任务；再运行一次 ResumeActiveRuns，任务行与节点行数量不变。
- [ ] 合法重放：同 generation 回执重放（200，changed=false）后准入结论不变，且不新增回执、command、verdict、settlement。
- [ ] 既有 selections.json 全部选择在一次性库上 0 FAIL、0 skip；diff 内无迁移文件、无新路由、无 daemon 或 T 文件改动。
