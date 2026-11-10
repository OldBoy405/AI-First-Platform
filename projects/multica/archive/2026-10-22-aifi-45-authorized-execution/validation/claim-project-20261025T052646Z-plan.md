# 当前 task claim/project 纵切片

状态：BUILD 实施中；用户原文“继续，非必要不停下来”“继续”。不另等常规实现确认。无 Gate3/提交/推送/部署授权。

## 来源与公开 seam

当前源码核实 `agent_task_queue.project_id` 是已入队的冻结项目列（nullable，删除SET NULL），不是不存在的 `protocol.TaskData`；claim旧响应的project来自live issue/chat等，不可把它当冻结归属。详见 `claim-project-trusted-source-facts.md`。

复用 **GET /api/daemon/tasks/{taskId}/status**，只有显式 `execution_claim=1&runtime_id=<canonical UUID>&dispatched_at=<Postgres microsecond RFC3339>` 请求走新元数据分支；无该query旧polling完全保留。旧服务忽略query只回status，新SDK必须拒绝而非降级。

新分支要求真实MDT路径、非空认证daemon、workspace仅取认证绑定；一个repeatable-read/read-only事务中复用现有sqlc GetAgentTaskInWorkspace / GetAgentRuntime / GetIssueInWorkspace / GetProjectInWorkspace，核 task/runtime/generation/active state、runtime所属daemon+workspace、冻结task.project_id、live issue同项目与project实际属于该workspace。第一片明确支持issue-backed任务；其他来源或NULL/不一致fail closed，不影响legacy。不新增表/迁移/FK/sqlc生成物/endpoint或签名接口。

成功JSON exact八键：`schema=execution-task-claim/v1,workspace_id,project_id,daemon_id,runtime_id,task_id,dispatched_at,status`。当前active状态为dispatched/waiting_local_directory/running；时间按DB实际值UTC回显。它是请求时DB快照，不是持续freshness、CR归属、人类来源、binding签名、receipt或激活。Cache-Control no-store只防缓存。

SDK按可信URL、禁止redirect、1MiB、完整JSON/重复键、exact键读取及ID/代次/scope核验；不改全局scanner或legacy ClaimTask JSON路径。新合同daemon preparation在根准备/授权安装/控制调用前取真实claim，不能让wrapper的project覆盖DB冻结值；后续连接当前资源descriptor。仍以EXECUTION_CONSUMPTION_REQUIRED关闭消费。

## 执行和职责

主会话写产品，balanced在独立新测试文件先写一个真实MDT公开HTTP正例；旧实现缺schema构成行为RED而不是编译错。每新增一段公开RED→最小GREEN，再补漂移/NULL/跨workspace/daemon/代次/终态/旧服务器负例和真实SDK贯通；独立审核后继续下一必要切片，不为普通阶段结束停下。

模型已从M源码根原生CLI重读schema1/configured：balanced Gobao/deepseek-flash/max、strong OpenAIPersonal/gpt-6.1-sol/high，actual无回执unknown。原库HOLD保持，DB权仅主会话；每命令调用版本化scripts/aifi45-db/run.mjs新schema-only库/受限role，先wx原源码manifest，逐条核原库137表/82审批/锁session0、exact资源catalog清理，再下一条。前轮final-readonly确认22对已知对象不存在；本片不假设库已恢复83。旧claim锁序独立续审，不混作本片通过。

## 通过边界

通过组件不勾完整49TC，不关闭5major，不推进C1/Gate3；非必要持续推进。预期CUSTOM新增真实登记；双仓phase/tasks即时记组件证据与未尽项。
