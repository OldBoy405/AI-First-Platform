# AIFI-45 旧 claim 锁序续审 resume2

## 结论及约束

**INCOMPLETE，不默认 PASS；本片没有确证的新增安全 finding。** 本报告只登记本片新增读取范围和收窄后的剩余符号，不撤销或泛化前报告已经限定完成的 StartTask / claim 外层 / FK / trigger 结论。

- 同一非作者 reviewer 续审，没有新增 reviewer。
- 用户提供的当前原生配置事实：schema1/configured，strong `OpenAIPersonal/gpt-6.1-sol/high`；actual 无回执，`unknown`。本 reviewer 未重新读取配置或秘密。
- 无 DB 权；未连接数据库、运行 SQL、测试、命令、网络、容器或子进程；未修改源码。唯一写入是本报告。没有碰原库 HOLD，也没有跟进 metadata/P2、新 API 或 SDK。
- 用户说明 task.go / handler StartTask 自前报告未变；本片不重复前报告已核函数，不借其他子任务 GREEN 补旧 claim。
- 创建前精确查找确认 resume2 文件不存在，未覆盖前报告。宿主 write 不提供原子 wx/O_EXCL 选项，不声明原子排他创建保证。
- 以下源码路径相对 multica 仓根；行号来自本片当前文件读取。前报告为同目录 `current-bindings-20261025T034807Z-old-claim-strong-report.md`。

## 1. Agent rebind：新增已核片段

当前 `server/internal/handler/agent.go`：

- `:2314-2327`：显式 req.RuntimeID 才新建 bindingTx，并建立该事务的 updateQueries。
- `:2328-2336`：先 LockWorkspaceForChatSessionCreate，再 LockAgentRuntimeForAccessChange；不是在该 bindingTx 段先锁 task/receipt 再申请 runtime。
- `:2337-2345`：持 runtime lock 校验 workspace 与 canUseRuntimeForAgent，写入 RuntimeMode 参数。
- `:2347`：通过同一个 updateQueries 执行 UpdateAgent；`:2369-2371` 进入 bindingTx commit。
- 直接相邻 create 分支 `:1611-1640` 同样是新事务 → workspace fence → runtime access-change lock → CreateAgent。

**限定结论**：已见的普通 Agent 显式 rebind 事务段采用 workspace → runtime → agent UPDATE 顺序，没有在该段形成 receipt/task → runtime 的反向申请。不能把 agent.runtime_id 的真实 UPDATE 错当作 task.runtime_id UPDATE；也没有据此背书 Builder 的不同调用者。Builder rebind 仍明确未尽，见第 4 节。

## 2. Wakeup 管理/注册：新增已核片段与 receipt 风险收窄

当前 `server/internal/service/issue_wakeup.go`：

- `:267-268`：Create 转 Save；`:338-344`：Enable / Save 转 save。
- `:347-359`：save 新事务 → workspace KEY SHARE → LockWakeupIssue。这里不能套用 scheduler dispatch 的 early runtime fence；这是不同事务入口。
- `:520-547`：替换旧订阅时 LockIssueWakeup、校验 owner/revision 后 DiscardWakeupReceipts，再 CancelUnstartedWakeupTasks。
- `:551-562`：若 filterTask 有效，再调用 LockWakeupSourceTask 并验证 agent filter。
- 已完整读到注册尾部 `:565-628`：更新/创建 issue_wakeup；条件分支调用 baselineCondition；记录 wakeup activity；terminal source snapshot 调 RecordWakeupReceipt；once 分支 AdvanceIssueWakeup；最后 commit，然后 publish activities。

**对本轮重点的实际判断**：

1. 已识别 `:544 → :547/:553` 的 **receipt 处理之后再调用 task 操作** 的边，不能把它删掉，也不能凭方法名就断言会等待 StartTask 的同一 task。
2. 本片可见的 save 显式语句和这些调用点中，没有出现 receipt 之后直接 LockAgentRuntime / LockAgentRuntimeForAccessChange / task runtime_id 改写。订阅 UPDATE `:566` 改的是 issue_wakeup，不是 agent_task_queue.runtime_id。
3. `:565-628` 完整尾部本身没有新增 runtime 行锁调用；但 baselineCondition、CreateIssueWakeup、activity/receipt SQL 的隐藏锁与 schema 约束尚未补齐，因此不签“所有 receipt → runtime 反向链不存在”。
4. **尚无可执行的确证死锁路径**：不能将“StartTask 的状态 trigger 会写 receipt”与“注册会写 receipt”两条事实直接拼成 runtime 锁环。必须补出后者在持 receipt 之后确实等待同 runtime 的调用/约束，或确实等待 StartTask 所持 task 的可等待 SQL；本片没有拿到该证明。

这里没有重跑或重复审查前报告已核的 ordinary/system scheduler dispatch early fence；管理/注册分支仍按其真实调用链单独界定。

## 3. Terminal settlement：新增已核 SQL

当前 `server/pkg/db/queries/supplement.sql:161-174` 的完整 `SettleTerminalTaskSupplements`：

- `:166-169` 只 UPDATE task_supplement 的 status、failure_reason、updated_at。
- `:170-174` FROM agent_task_queue 读取 task 身份与 terminal 状态，并限制 supplement 的 pending/delivering 状态。
- 显式 SQL 没有 FOR UPDATE runtime/agent，没有修改 task.runtime_id，也没有 DELETE/cascade。FROM task 不等于额外锁定 runtime；实际 UPDATE 行锁目标是 supplement。

**限定结论**：已关闭“这个 settlement SQL 显式改 task.runtime_id / 直接申请 runtime parent lock”的疑点。不把显式 SQL 无 runtime 操作等同于所有表 trigger/FK、或其他 terminal settlement 方法的尾部均已核完。

## 4. 仍未尽的具体符号与下一段读取边界

1. **Builder**：`RebindAgentBuilderRuntime` 的实际 handler/service 事务调用者，及其 session/agent/task 锁与 LockAgentRuntimeForAccessChange 的先后。普通 `Handler.UpdateAgent` 的上述 bindingTx 段不再列为完全未读。
2. **其余 terminal/system cleanup SQL**：`SettleDelegatedFailureRecoveriesForTask`、`LockChatSessionsBySystemRuntimeAgents`，以及直接 system-agent cleanup SQL；需确认 dependent-row / chat / cascade 不在持 task/receipt 后首次申请同 runtime 锁。`SettleTerminalTaskSupplements` 显式 SQL 已读，不再重复列为未读；它涉及的 task_supplement trigger/FK 尾部仍待按允许的 schema 文件核验。
3. **wakeup save 的直接下游**：`CancelUnstartedWakeupTasks`、`LockWakeupSourceTask` 的当前 SQL（特别是状态选择、NOWAIT/等待行为）；`baselineCondition`；`CreateIssueWakeup`、`RecordWakeupReceipt`、`recordWakeupActivity` 的直接 SQL/约束。关注的是 :544 持 receipt 后是否再取得 runtime/task 锁，而不是泛查全仓。
4. **其他管理入口**：`IssueWakeupService` 的 disable/delete 管理实现（含 issue_wakeup_manage.go 的真实入口），尚未读其完整事务；不得用 Save 的已见尾部代替这些入口。

继续审核不需要用户再次批准，也不需要任何 DB 执行权；只需上述符号及直接调用者的有界源码/既授权 schema 片段。本片先持久化结果，不因预算耗尽改写为 PASS。

## 5. 保留边界

不签 Gate3、整个 C1 或 49TC。legacy 无 generation、防降级与完整 project/resource/admission/每 repo/完整 claim/隔离/授权消费证明均不因本片改变；没有签 receipt 或开放消费。本报告也不是对主会话准备中的可信 claim/project 新读面的审查。
