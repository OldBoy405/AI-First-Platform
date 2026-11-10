# RUN-009 run/node 终态与恢复写者：有限只读盘点

独立 balanced 请求会话 `01a186c8-fc4f-7020-aecc-d2c0878522ea`，actual backend 回执 unknown。仅检索当前 `multica/server/{internal,cmd,pkg}` 的可见非测试 Go、SQL、部分迁移/生成调用，未逐文件审计，不覆盖动态拼表名、所有触发器、server 外写者或实际部署。静态分析不是竞态复现或无竞态证明；未访问 DB/容器、未修改源码。路径相对于 `multica/server/`。

| 写者 | 已观察到的写入和锁 |
|---|---|
| projection complete `internal/governance/gate_projection.go:250-268` | 活跃 run → completed；限 `execution_context.runner` 缺失/空。`crsync.go:136-150,326-328,516-547` 的 workspace+CR mutex 是 SyncService 实例内锁，不是跨进程；投影使用 pool，非与 Runner 同事务。部分投影错误被吞（`gate_projection.go:63-77`）。 |
| projection cancel `gate_projection.go:295-311` | 先活跃 run 的 running node → failed，再活跃 run → cancelled；未按 runner marker 过滤。两个 pool 语句，中途失败可只完成第一步；blocked node 不改。 |
| projection approval/review `gate_projection.go:211-244,356-435` | approval 冲突可改 passed，review status 参数化可写 passed/blocked；冲突更新未按原 node 终态限缩，facts-only 合并 detail。多 pool 语句，不能因 complete 有 marker 谓词假定 node 路径也有。 |
| Runner 通用失败/node `runner.go:1533-1542,1649-1669`；`execution_admission_gate.go:126-149,183-222` | failRun 先 run failed 后修改 node，两句 pool；node passed 在配置 decider 时可在事务内重验授权，blocked/无 decider 路径不同。授权 head 锁不能推出与全部终态写者同域。 |
| Requirement `runner_requirement.go:34-69,88-124,229-290` | 按 run ID session advisory lock；审批/closing/CR 状态满足时完成 run，完成写入仍是 pool，现有注释称 run completion 未覆盖 admission gate。 |
| Architecture `runner.go:719-741,861-924` | 按 architecture run ID session advisory lock；满足 closing、审批与 CR 状态后 node/run 完成，node/run 不同事务；失败可走 failRun。 |
| Code `runner_code.go:30-63,407-456` | 按 code run ID session advisory lock；满足审批、closing 和 CR 状态后执行 writeback handoff 并 complete，handoff 与 code completion 非同事务。 |
| Writeback `runner.go:702-704`、`runner_code.go:317-318,321-405,452` | 从 architecture 锁之前或 code 锁内部直接调用 writeback reconcile；所读函数未自行获取 writeback run advisory lock。merge facts/后续节点收敛后完成，不能笼统认为每次持 writeback 自身 run 锁。 |
| Promotion bind `pkg/db/queries/promotion.sql:78-100`、`internal/service/task.go:9155-9258` | 事务内先 run FOR UPDATE，再 CR 锁及条件更新；匹配 running node 可置 passed。检查具体 lock order；node 更新未写 completed_at，调用方未检查该更新行数。 |
| 手工 requirement resume `runner_requirement_entry.go:155-186,252-286`、`runner_requirement_resume.go:146-165,262-265,370-410,538-570` | 按 workspace+CR session advisory lock 分配；事务中 run FOR UPDATE 并复查 failed，恢复 run/context/node，node 更新无原状态条件；continuation 在提交后另起事务排队。与原有投影/运行器锁不自动同域。 |

候选同步域需逐项覆盖或证明 CAS 足够：projection cancel 的 **node→run** 与 Runner fail 的 **run→node**，projection pass/review 与 Runner node 写，projection complete 与 marker 收编/Runner complete，人工 restore 与自动 reconcile，promotion bind，以及 writeback 直接调用/其他 wake。引入全局锁还要核既有相反写入顺序，避免新死锁。

有限约束：`migrations/585_aifirst_pipeline_runs.up.sql:14-53` 定义状态集合及 `(run_id,node_id,attempt)` 唯一；`590_pipeline_run_architecture_active_unique.up.sql:13-15` 的谓词实际覆盖 CR 非空的所有 pipeline 活跃 run；`640_pipeline_run_promotion_active_unique.up.sql:11-13` 限 requirement workspace+issue 的活跃 run；`591_agent_task_pipeline_node_active_unique.up.sql:14-17` 限活跃 task。约束不能把多语句操作变成一个事务。所有遗漏边与部署版本均为 unknown，真正的同步方案及隔离 DB 证据仍待决定。
