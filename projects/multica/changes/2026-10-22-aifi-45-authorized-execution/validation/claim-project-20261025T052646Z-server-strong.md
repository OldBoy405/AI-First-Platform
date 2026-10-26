# Claim/project server 独立 strong 静态报告

## 结论与限域

限定server静态评审完成，有1项确证P2未关闭；不判通过。

仅审核新增daemon_execution_claim.go、GetTaskStatus的execution_claim分支和legacy分流、八字段protocol及必要认证/事务/generated SQL。未访问DB、未跑测试、未改源码、未启动子代理。本报告wx独占创建，不覆盖其他报告。首次较长报告创建命令因Python语法/传输截断失败，未落盘；此为缩短后的重试，以下成功输出才是落盘依据。

模型provenance：沿宿主原生schema1/configured strong OpenAIPersonal/gpt-6.1-sol/high；actual无后端回执，unknown。未重审旧metadata P2、旧claim锁序、service/task.go业务逻辑或SDKstub，不签全局C1/生产准入。

## 确证 F1 / P2：超长小数秒先被截断，后通过微秒精度检查

位置：`server/internal/handler/daemon_execution_claim.go:45–46`，代次比较81行。

触发条件：真实合法MDT、所属workspace/daemon/runtime匹配、任务active、issue/project全部正常，DB dispatched_at为`2026-10-25T05:30:00.123456Z`（现有首例fixture使用此值）。请求：

```text
GET /api/daemon/tasks/<T>/status?execution_claim=1&runtime_id=<R>&dispatched_at=2026-10-25T05%3A30%3A00.1234560001Z
Authorization: Bearer <该daemon真实mdt>
```

请求第10位小数非零，原始时间不是可精确表示的PostgreSQL微秒值。`time.Parse(RFC3339Nano)`却丢弃第10位及以后，得到123456000纳秒；`Nanosecond()%1000==0`，随后Time.Equal与DB代次相等，其余条件满足即可200。这是源码静态确证，未动态复现。

已定向读取本机Go标准库佐证：`C:/Program Files/Go/src/time/format.go:1026–1033`的Parse走parseRFC3339；`format_rfc3339.go:82–155`先扫描全部小数digits，再调用parseNanoseconds；`format.go:1529–1551`在nbytes>10时截成value[:10]，只保留9位小数。不是把RFC3339Nano误认为自动拒绝超长精度。

影响严格限定为精度输入拒绝被截断绕过，**不是**另一个完整微秒代次、其他runtime/daemon或跨workspace任务可冒充成功的证明，也不构成准入绕过。当前首例只测正常6位，不能覆盖此缺陷。

建议：在有损Parse前检查原始小数精度。明确是否允许多余零，至少拒绝第7位及以后任何非零数字；若合同最多6位，则严格限0–6位并保留合理RFC3339时区策略。补公开HTTP `.1234560001Z`、第7/8/9位非零、超长全零、正常微秒/无小数/合法offset用例。只提出finding，本轮未改源。

## 其余静态接线结论：未发现第二项确证Finding

- 真实生产router的`/api/daemon`组挂DaemonAuth，1693行注册既有status路由。新helper只有GetTaskStatus显式分支调用，另一注册是已读governance测试harness，无新endpoint。
- helper先要求auth path为DaemonAuthPathDaemonToken、trim daemon非空、认证workspace非空；不从header/body取workspace/project。middleware从token哈希DB记录或既有DB派生身份缓存写私有context。伪X-Daemon-ID/X-Workspace-ID不能写这些context；PAT/JWT/cloud-PAT不能因此冒充mdt。角色/context不由测试自报header证明。
- task/runtime UUID须canonical；三个query各一个且execution_claim=1。task.RuntimeID精确匹配、DispatchedAt有效且Equal、status限dispatched/waiting_local_directory/running。F1只涉及有损Parse前的精度拒绝，不取消上述检查。
- GetAgentTaskInWorkspace实际generated SQL经task→agent JOIN并按taskID+agent.workspace过滤；SELECT/Scan包含queue真实ProjectID，不是从live issue推断。foreign/missing task同404。
- GetAgentRuntime使用同tx按ID读，随后核workspace及DB daemon有效且精确等于认证daemon。task.runtime已先匹配，不能自由探测其他runtime；不回显runtime敏感列。
- 首片要求Task.IssueID/ProjectID有效。GetIssueInWorkspace按ID+workspace，live issue.ProjectID与冻结queue.ProjectID不等即409；GetProjectInWorkspace再按冻结ID+workspace确认项目存在。NULL、非issue-backed、删除/reparent不一致均失败关闭。此关联不等同于证明trigger的人类来源/CR身份，不应为了metadata要求完整admission。
- Begin后首个tx SQL为RR READ ONLY，再WithTx。已读db.go确认WithTx返回db=tx；四个generated方法均q.db.QueryRow，不退回池。参数/Scan已核，含task最后的ProjectID扫描。成功Commit后返回，defer Rollback兜底；Commit不是lease或activation。
- task scoped查询无行404；其余缺row/身份不符409；真实DB/Begin/SET/Commit错误500，固定错误文案，无raw row/token/context回显。production TxStarter注入沿前片已核构造器，不重审旧claim事务。
- 无execution_claim键时原status轻查询、workspace权限校验、单字段响应保留，不新增issue/project读取或限制旧polling为issue-backed。protocol只有exact8个非omitempty字符串字段，时间由DB值UTC RFC3339Nano回显；去末尾零是可变小数位RFC3339，不是改代次。no-store不证明持续freshness。

非Finding建议：URL.Query忽略ParseQuery错误可能丢弃畸形pair，可明确400策略；未证实其可绕过新helper的DB/代次/scope检查，或使legacy单字段冒充八字段有效快照，不当第二项漏洞。

## 证据与未验证属性

已完整读governance首例：真实token、DaemonAuth、公开GET handler、DB fixture与exact8字段断言；不是直接注入context，也不是生产NewRouter启动测试。已读RED1/GREEN1 meta及raw stdout定向失败/pass行：RED 1RUN/1FAIL为旧响应只有status；GREEN 1RUN/1PASS/0SKIP，1leaf。不是完整矩阵/49TC，也不是我重跑。

meta所报原库不变、sessions/locks0和资源清理仅为作者证据，本次未连DB证实。读GREEN1 pre-run manifest，未完整复核RED1历史清单/归档链。

动态race、完整auth/header/NULL/代次/终态负例、精度F1公开复现均未验证；第二个balanced新文件/SDKstub不在本片SDK审核。这些不被记通过，也不将已读完的限定静态代码scope泛化成INCOMPLETE。metadata不是持续freshness、签名binding、claim receipt、本机进程证明或admission；EXECUTION_CONSUMPTION_REQUIRED保持，后续根准备前接线未被本报告验收。

## 实际read范围

完整：新handler/protocol、governance首例、claim-project plan、GREEN1 source-manifest。
部分：daemon.go:5490–5552；generated agent.sql.go:4695–4783、runtime.sql.go:552–586、issue.sql.go:1021–1073、project.sql.go:103–135、db.go:15–32、models.go:111–168；SQL agent.sql:842–855；middleware/daemon_auth.go:121–172；router.go:1646–1650及1693注册grep；两份meta和stdout定向证据；上述标准库片段及直接引用搜索。认证完整fallback/context与handler.New沿用此前已读上下文。未读旧service/task业务，仅核hash未改；未重审旧metadata/P2或claim锁序。

## 本次实算SHA对GREEN1预运行manifest

只核下面五项；整文件hash不代表整文件代码评审。若产品项DRIFT，Finding仅针对所读基线。其余未列manifest项不声称逐项核验。

| 文件（业务根相对） | raw SHA-256 | CRLF→LF SHA-256 | 长度及hash |
|---|---|---|---|
| `server/internal/handler/daemon_execution_claim.go` | `7459bc45f8b910adf02376a6ea4c72a0af2dc6a3d729178366642315c68b6acc` | `7459bc45f8b910adf02376a6ea4c72a0af2dc6a3d729178366642315c68b6acc` | MATCH |
| `server/internal/handler/daemon.go` | `c879eb89ab44a4e5b9901262ebf36a66d40f714528671cfff9f0424f2e36144a` | `c879eb89ab44a4e5b9901262ebf36a66d40f714528671cfff9f0424f2e36144a` | MATCH |
| `server/pkg/protocol/execution_task_claim.go` | `59b647ef59bd159adbbad01c6e510b19aa6f6d6f9726c359da3c7201ec61fa41` | `59b647ef59bd159adbbad01c6e510b19aa6f6d6f9726c359da3c7201ec61fa41` | MATCH |
| `server/internal/governance/execution_task_claim_project_test.go` | `d6c3d55b5b10cb9206eb9ef9a9084f30fdbe84a83e7e78b497ff15260c6d395d` | `d6c3d55b5b10cb9206eb9ef9a9084f30fdbe84a83e7e78b497ff15260c6d395d` | DRIFT |
| `server/internal/service/task.go` | `c5e543f880b907059ac1a02f6fda60b1e6e200703a0c70cc9efd967d0b57f118` | `c5e543f880b907059ac1a02f6fda60b1e6e200703a0c70cc9efd967d0b57f118` | MATCH |

结论：1项精度输入P2待修复；没有第二项确证漏洞。不签全局C1、old claim锁序或生产消费。
