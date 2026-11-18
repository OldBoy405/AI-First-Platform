# 执行准入收缩为单一授权头判定，并让等待原因对人可见

<!-- source_hash: b3018e35e9a6c94c -->
<!-- generated_at: 2026-11-17T22:51:57.837942 -->
<!-- canonical: canonical/proposals/2026-11-17-execution-admission-simplification.yaml -->

## Why

DAYA-5（CR-MES-2026-001）的 requirement 流水线自 11 月 9 日起停在 write-requirement-prd 节点，
8 天内无人发现，review-requirement 从未派发。只读排查（2026-11-17，只读事务、仅限该 issue/CR）确认：
(1) 直接阻塞是 Runner 入队前的准入判定返回 HEAD_UNAVAILABLE（CR 无执行授权头，execution 授权记录为 0），节点无任务；
(2) 即便补上授权头，还有三道串联前置：默认部署不给 server 传入可信契约启动参数（docker/entrypoint.sh 不转发参数，
签发端点返回 503）；CR 的 shell_issue_id 为空，授权所需的 project 无法解析（409 EXECUTION_SCOPE_UNRESOLVED），
该绑定只由显式 CR bind 写入，本 CR 注册后未执行；源任务虽 completed 却没有 consumption 回执与 effect，
准入随后停在 WAIT_CONSUMPTION；
(3) resume 在“已入队”和“因准入等待”两种情况下都返回 200 加 run ID，等待没有对任何人呈现。
这些缺口同源：准入被实现为“授权、送达证明、消耗回执、effect/verdict 链”的串联证明，任何一环没接通都会无声停住；
而该证明链的设计前提是 Agent 为不可信客户端（归档设计 ADJ-AIFI45-M005-TRUST）。


## What Changes

- Runner 的执行准入判定只以 CR 当前执行授权头为依据：头存在、为 approve 记录、且与 workspace 和 CR 同属一个范围。
不再要求源任务当前 generation 的消耗回执与该任务的 effect/verdict 链。四类受保护动作（节点置 passed、人工门通过、
两条派发路径）继续经同一判定点、同一锁，叫停与入队不交错。

- 默认部署无需额外启动参数即可签发人工执行授权。签发仍只接受经认证的人类 owner/admin；
project 范围仍只取自 CR 到同 workspace shell issue 的关系，不取自请求体。

- requirement 流水线的 resume 回执（architecture 若有同类 resume 入口，Phase 2 核实后同样处理），以及一个只读的运行状态读面，如实返回当前状态与等待原因
（已入队含任务标识 / 等待准入含原因 / 其他既有等待原因 / 已完成）。原因取自 Runner 已记录在节点上的等待信息，
不新增表、状态或错误码；原有 run_id、changed 字段保持不变。


### New Capabilities

- **execution-wait-visibility**：流水线等待对人和调用方可见：回执与只读状态读面回显等待原因，等待态不再呈现为已推进。

### Modified Capabilities

- **admission-task-binding**：准入不再把任务 generation 的消耗回执与 effect 作为放行条件；仅判定当前授权头。取代归档变更 2026-11-11-aifi-45-admission-task-binding 的锚点任务规则。
- **authorized-runner**：SC-RUN-003 的放行条件改为当前授权头有效；默认部署可签发人工执行授权；敏感动作人工门、派发幂等与旧证据不推进当前节点保持不变。

## Success Criteria

- [ ] CR 无执行授权头时，四类受保护动作均不放行、不入队，等待原因为 HEAD_UNAVAILABLE，可在回执与状态读面读到。
- [ ] CR 有当前 approve 授权头（同 workspace 与 CR）时，即使源任务没有消耗回执和 effect，四类受保护动作均放行；重复 reconcile 后任务与节点行数不变。
- [ ] 授权头被叫停后不再产生新的派发；叫停与入队并发时，不出现叫停提交后仍入队的结果。
- [ ] 指向其他 workspace 或其他 CR 的授权头按无头处理，不借用其决定。
- [ ] 默认部署（不传任何契约启动参数）下，经认证的 owner/admin 对已有 project 归属的 CR 提交授权请求，返回创建成功并设置授权头；task-token 或非人类来源的请求仍被拒绝；CR 无 project 归属时仍返回 EXECUTION_SCOPE_UNRESOLVED 并带明确说明。
- [ ] resume 回执与只读状态读面在等待准入时返回等待原因，不呈现为已推进；已入队时返回任务标识；原有 run_id、changed 字段不变，缺失新字段的旧调用方不受影响。
- [ ] 既有受影响测试按新语义更新后全部通过，被改写用例对应的保证（无头、有效头、叫停、跨范围、幂等）各至少保留一个；未新增删除即无法解释的跳过。
- [ ] 在获授权的一次性环境中，用与 DAYA-5 同形的 CR（无消耗回执的源任务、人工授权后）完成一次真实验证：writer 节点入队并推进到 review-requirement 的派发；不接触现网数据。
