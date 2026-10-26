# AIFI-45 binding issue — strong resume2：只复核已有 CR 被自报覆盖这一残余

## 判定与范围

**本轮指定的 F1/N1 残余机制「task 已有 CR_A，StartTask 再自报 CR_B 将其覆盖」：CLOSED（限定静态源码）。** first-writer-wins 已同时进入 SQL 源和生成查询；不同 CR 返回 0 行，不再改已有值。同值重放与 NULL 首次写入保留；0 行不会把 StartTask 打成失败。**未确认本次改动新增独立 P0/P1/P2。**

精确区分：上述 CLOSED 是“已有非 NULL CR 事实不被此 attribution setter 改成另一 CR”，不是“首次自报已经成为可信/人类来源证明”。若把原 F1 理解为完整可信 CR 来源链，仍不能签全部 CLOSED：NULL 首次值来自 daemon 自报这一来源上限未变。该边界在 resume1 已披露，本轮不扩展为新一项 P1，也不拿它否认本次覆盖修复。

仅阅读该 setter、对应 generated SQL、StartTask 调用点、直接 void helper、必要 pipeline/重试入队片段及两个新增测试/现有证据。不重新评审五项全量、head、T、完整 terminal、runner、activation 或全部 CR 写入者。**未访问 DB，未运行测试/vet/编译/生成器，未修改源码/测试，未使用子代理。** 另一代理的 DB 单权未被触碰。

路径根：`C:/Users/GOBAO/Downloads/AI/multica`；以下源码路径相对此根。配置模型背景沿用 `OpenAIPersonal/gpt-6.1-sol/high`；actual backend unknown，本轮不重新核验。

冻结依据：`binding-issue-20261025T081500Z-final2-freeze-manifest.json`，时间 `2026-10-25T08:23:08.600Z`；作者测试 pin `green6-source-manifest.json` 时间 `2026-10-25T08:22:34.170Z`。本轮相关文件已核 raw SHA-256，发布前再次核对。历史报告不覆盖。

## 1. 已有 CR_A 后再报 CR_B，是否真的改不动？

**是，在本次 setter 的正常应用查询路径上改不动。**

- `server/pkg/db/queries/agent.sql:1143–1149`：UPDATE 的同一语句中包含 `AND (atq.cr_id IS NULL OR atq.cr_id = $2)`，并保留 task/agent 关联及 CR 的 workspace EXISTS。
- 当已有 `CR_A`、请求 `CR_B != CR_A`：`IS NULL` 为 false、相等为 false，故该行不命中、RowsAffected=0；不是先 SELECT 再无条件覆盖。
- 生成文件 `server/pkg/db/generated/agent.sql.go:9597–9605` 含相同 guard；`:9625–9630` 正确按 task ID/CR 传参并返回 RowsAffected。不存在“源 SQL 修了、生产生成查询仍无条件写”的落差。
- 相比之下，已有 `BindTaskCrIfNull` 在 `agent.sql:1187–1195` 也使用 NULL 或同值谓词，本次 setter 的这一项语义与其一致；不因此声称两者的认证/来源/事务检查整体等价。
- binding 的直接 claim 查询 `server/pkg/db/queries/execution_binding.sql:11–18` 仍要求指定 T/R/G/active、`t.cr_id=URL CR`、认证 workspace/runtime workspace/daemon。任务保留 CR_A 后，不能仅借本 setter 把它改标 CR_B 再通过该查询。

这是本轮关闭 resume1 所示**已归属任务重标链**的依据。没有声称所有 DB 角色/其他 SQL 写入口都不能改 cr_id，也没有动态验证并发 NULL 首写竞争或数据库实际状态。

## 2. NULL 首次自报与同值重放是否保留？

| 当前列值 / 本次自报 | setter 结果（task/agent 正常、目标 CR 存在且在同 workspace） |
|---|---|
| NULL / CR_A | NULL 分支命中，允许首次赋值，通常 1 affected row |
| CR_A / CR_A | 同值分支命中，UPDATE 仍可成功，通常 1 affected row；逻辑值不变 |
| CR_A / CR_B，A≠B | 不命中，0 affected rows；保留 CR_A |
| NULL 或 CR_A / 不存在或 foreign-workspace CR | workspace EXISTS 不成立，不允许赋值 |

**“唯一可写路径”需要限定语义**：在这个 setter 中，唯一能把 CR 的逻辑值变成另一个值的情形是 NULL→首次有效 CR；同值 UPDATE 仍属于执行成功，不是禁止一切 UPDATE。它并非全仓唯一的 CR 首次写入口：已有 pipeline enqueue、retry 继承和 BindTaskCrIfNull 等路径，不能误报为只有 daemon 自报能够填写 CR。

`service/task.go:4707–4723` 的 helper 仍对空 CR 直接 return，对 0 行只写 debug log；本次 guard 没有封掉合法 NULL→CR、同值重放，也没有额外要求 daemon 提供不存在的新凭据。

**首次写入的来源上限保留**：NULL 首次 CR 仍是 daemon 所报，在该 setter 中只验证 CR 存在且属于同 workspace；没有新增 task issue↔CR shell issue、pipeline run 或人类来源核验。因此：

- first-writer-wins 证明的是后续不能通过这个 setter 改标，**不是第一位写入者一定正确**。
- 未归属任务的错误/恶意首次自报可能被固定下来；不能把这说成首次来源已独立验证或完整 F1 可信来源链已签。
- NULL 尚未赋值时，binding 查询的 `t.cr_id=目标 CR` 仍拒绝；首次赋值后可按所记录的 CR 参与匹配。它不证明真实 child/进程或原始人类意图。
- 本轮接受该机制作为所指定覆盖缺陷的修复，不重新调整既有业务绑定政策，也不将保留的 NULL 来源上限重复计为本次新增 P1。

## 3. pipeline 预填 CR 与 StartTask 的兼容性

**预填同值不会被新 guard 拒绝；不同值仅忽略，不改变 StartTask 成功结果。**

- `agent.sql:617–650` 的 CreatePipelineTask 在 INSERT 字段中包含 cr_id/pipeline_node_run_id，并在 SELECT 中传入 `$5,$6`（`:640,649`）；`agent.sql:568–600` 的 retry 插入带 cr_id 等列并从父 task 继承（`:579,600` 附近）。本轮只核这两个相关片段，不重新审查 Runner 全量。
- enqueue 已写 CR_A 时，StartTask 同报 CR_A 满足相等分支；不会要求必须是 NULL，也不会把同值当冲突。若合法 CR 已删除，EXISTS 可能让 attribution 0 行，但仍不把正常启动改成错误；并不承诺这种状态还能取得 binding。
- `server/internal/handler/daemon.go:4595–4597` 现在仅调用一次 AttributeTaskToCR；原重复调用已删除。`:4599–4612` 继续日志、构造响应并 200，不根据 RowsAffected 分支报错。
- `server/internal/service/task.go:4707–4723` 返回类型是 void；0 行没有 error 返回，SQL error 也仅记录后 return。这意味着**因不同 CR 被忽略而导致的 0 行，不会升级为 StartTask 失败**。任务 start 本身仍可能因过期 claim/不可启动等原有原因失败；这里没有对所有启动条件作新保证。
- 不同值被忽略后，后续为错误目标 CR 请求 binding 仍应拒绝；StartTask 成功不等于该错误 CR 获得签发，更不等于消费/准入。

## 4. 作者 green6 证据的只读核验及局限

只读核对 `green6.meta.json`、`green6.stdout.jsonl`，事件为 **18 RUN / 18 PASS / 0 FAIL / 0 SKIP，17 leaf**，与作者摘要一致；运行选择为 `^(TestExecutionBindingIssue|TestTaskCRAttributionFirstWriterWins)$`。元数据记载 exit0、migration、原库 unchanged/released、临时资源 cleaned。**这些是所提供文件的内容，不是本评审者执行测试或独立访问 DB 确认的事实。** 不借用同时进行中的 independent-governance 运行作为本轮完成证明。

### TestTaskCRAttributionFirstWriterWins

`execution_binding_issue_test.go:716–794` 直接调生成查询并核 affected rows/读回值：NULL→firstCR 为 1、同值 replay 为 1、secondCR 为 0 且原值不变、foreign-workspace CR 为 0 且原值不变。

覆盖边界：不是公开 StartTask HTTP 测试，也不是两个并发首写者竞争测试。foreign-workspace 检查发生在已填 firstCR 之后，不单独隔离“NULL→foreign”分支；不过 SQL 保留 workspace EXISTS，因此本轮源码判定不依赖测试名称扩大覆盖。

### relabelled_task_cannot_borrow_another_cr

`execution_binding_issue_test.go:496–550` 先在原 CR 下 issue，再直接调用 SetTaskCRAttributionIfValid 尝试改标，核 0 行及 DB 列保留原 CR，最后通过真实 MDT 的 binding HTTP 请求另一 CR，预期 409/no-row。

覆盖边界：改标尝试是直接 query，不是走 StartTask HTTP；另一个 CR 的 fixture 没有建立其 execution authorization head，故**不能单独拿最终 409 宣称所有 head/claim 顺序交错或全链都已覆盖**。关键证据是新 SQL/生成谓词及改标后列值不变，HTTP 负例是补充。StartTask 的“不因 0 行失败”在本轮由直接调用/void 返回控制流静态确认，未独立动态执行。

## 5. 新问题及保留结论

- **新增确证 P0：无。新增独立 P1/P2：未确认。** 原已归属任务重标 P1 机制已关；没有发现新 guard 使同值重放失败，或把不同值 no-op 转成启动错误。
- first-writer-wins 不自动证明首次 CR 的权威来源；此上限保留，不重写为完整 F1/人类来源链的 CLOSED，也不补签 NULL 来源的可靠性。
- F2–F5 沿用 resume1 的限定源码 CLOSED，不在本轮重审；其关闭仍不是 OS child/生产调用/动态竞态证明。
- 不复评 legacy terminal、防降级、Fail/Complete/replay 链、外部副作用、runner 或 append-only 权限风险。本轮没有 DB、测试、源码改动。

**本片一行限定结论：F1「已有 CR 被 StartTask 自报覆盖」残余及既审 F2–F5 的源码根因 CLOSED；首次 CR 的可信来源仍未签/OPEN，消费、准入、activation、隔离域仍 OPEN，进程身份仍不可由服务端验证；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 附：发布前相关文件身份

核对时间：`2026-10-25T08:26:25.311909+00:00`；下列六文件均匹配 final2/green6 raw pin，身份核对不等于重新审全部内容。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| server/pkg/db/queries/agent.sql | 148510 | 03f8438d3df6692844422b480d2ddfaff71f8db3acc1793b343307bdca169303 |
| server/pkg/db/generated/agent.sql.go | 393461 | f85d8329927b55f0b3380232749b05f38f0e356890494d06f3bf4e413c49ca23 |
| server/internal/handler/daemon.go | 290400 | c9f353dc62f32d3ef9131ef60a74a1448c083cc390e0859bff6721e3fa9528ca |
| server/internal/governance/execution_binding_issue_test.go | 29235 | 6b99762ef8c3a5b2dafa6a53c09eb7a31a6d9955f00f5ccd00aa76d4211358bb |
| server/pkg/db/queries/execution_binding.sql | 1646 | 2305fc71d51b7c761e5d7c85a2771e04e6b3b30d17c6381aad7bc9863886fd72 |
| server/internal/governance/execution_binding_issue.go | 19877 | b1c1ee897d5071fe3b3e273f8d43d92a37e7797f05eb1930b9c0e3d8fe32193d |

直接 helper 发布时取样（非 final2/green6 覆盖扩展）：`C:/Users/GOBAO/Downloads/AI/multica/server/internal/service/task.go`，412401 bytes，raw SHA-256 `0406f1276ca3f9e1dd1dfd9845797af5a346c9af52cc22b94f034b3b03ecebf2`。
