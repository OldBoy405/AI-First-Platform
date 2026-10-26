# AIFI-45 binding issuance — strong resume1（仅五项复核）

## 结论

**F1/P1 PARTIAL；F2/P1、F3/P2、F4/P2、F5/P2 均 CLOSED（限定源码根因）。** 新增 task_id 不再只是未经核验的 body 身份；服务端按完整 T/R/G/active/workspace/daemon/目标 CR 查 DB，且复核 ID。**但 CR 来源仍有一个已确认的 P1 同根残余 N1：用于新安全判断的 task.cr_id 可以被既有 daemon StartTask 自报覆盖。** 不把 N1 与 F1 重复计数；不判五项全部关闭。

仅复核上一报告的五项修复及 task_id、CR 来源、唯一冲突重读的必要直接影响；没有重做 head、20 字段、migration、runner 或完整 terminal 评审。**没有访问 DB、运行任何测试/vet/编译/生成器、修改源码或测试、使用子代理。** 作者级证据只做只读核验。报告独占创建，不覆盖 `binding-issue-20261025T081500Z-strong.md`。

根目录：`C:/Users/GOBAO/Downloads/AI/multica`；下文源码路径相对此根。唯一 wire 源为 `C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md`。模型背景沿用 configured strong `OpenAIPersonal/gpt-6.1-sol/high`，actual backend unknown；本轮不重新发现 backend。

冻结：`binding-issue-20261025T081500Z-final-freeze-manifest.json`，`2026-10-25T08:15:26.580Z`；`green4-source-manifest.json` 为 `2026-10-25T08:14:52.432Z`。final 所列八个文件的当前 raw SHA-256 均匹配 final 和 green4；这不表示本轮重新审查其全部内容。发布前再次检查冻结。为回答 CR 来源而读取的三个直接 helper 不在该八文件冻结内，单列发布时哈希，不能冒充 green4 对这些路径的覆盖。

## 一、五项逐项判定

| 原项 | 本轮状态 | 当前行号与理由 |
|---|---|---|
| F1/P1 task↔CR 关联 | **PARTIAL** | `server/pkg/db/queries/execution_binding.sql:11–18` 已有 t.id、R/G、t.cr_id=目标 CR、active、W/daemon；`server/internal/governance/execution_binding_issue.go:140–146,185–192` 传入认证 namespace、复核 claim.CrID 与 claim.ID 并核 project。直接使用“另一个 CR 列值”的原负例现在会拒绝。但该列可被既有自报路径覆盖，见 N1，未达到“可信关联来源”闭合。 |
| F2/P1 runtime/代次不能唯一定位 task | **CLOSED（source）** | 请求结构 `execution_binding_issue.go:45–53` 增 TaskID；`:303–316` exact 四键、canonical task UUID；SQL `:11` 以 task 主键精确查找，再 AND runtime/代次/CR/认证 scope；generated `execution_binding.sql.go:66–104` 对应六参数，无聚合、LIMIT/ORDER 任取。即使另一 task 的 R/G 相同，也不能替代指定 t.id。签名 task_id 仍取验证后的 claim.ID（handler `:226–233`），不是未校验字符串。 |
| F3/P2 JSON null→PID 0 | **CLOSED（source）** | handler `:359–368` 对 PID/PPID 在 typed decode 前调用 executionBindingNotNull；`:403–406` 对 raw bytes TrimSpace 后比较 null。exact key-set helper `:410–423` 已保证字段存在。schema 的 null 由固定 schema 比较拒绝，其他 challenge 字符串/数字也有 NotNull 或非空格式检查（`:331–398`）。null 不会再被当作 0 签入；真正数字 0 仍按非负整数合同接受。 |
| F4/P2 runtime canonical | **CLOSED（source）** | handler `:312–319` 对 task/runtime 均要求 ParseUUID 成功且 UUIDToString(parsed)==原字符串；uppercase、32hex、其他可解析非 canonical 表示不能再借 normalize 进入查询。null/空字符串不能通过 UUID 解析，任一失败走 handler 的 400。 |
| F5/P2 unique-conflict 重读占着原 pool 连接 | **CLOSED（source）** | handler `:252–258` 先 `tx.Rollback`，再 `a.pool.QueryRow`。必要直接依赖 pgx v5.11.0 `pgxpool/tx.go:34–44`：Rollback 调底层后无论返回 err 与否都 Release pool connection 并置 nil；因此忽略 rollback err 不会保留此前的同一个 pool checkout，defer 再 rollback 也是安全的。连接取消/网络故障仍可令重读失败，但原“占着自己唯一连接再申请连接”的根因已移除。 |

**CLOSED 是本次限定静态根因判定，不是动态竞态、数据库事实、生产调用或完整安全签字。** F2 的关闭不宣称 daemon 选中的 task 确实对应某个 OS child；F1 的 PARTIAL 也不是仅因没有运行测试，而是存在下面的具体源码残余。

## 二、N1 / P1：把可由 daemon 自报改写的 task.cr_id 提升为签发的可信 CR 依据（F1 同根残余）

### 已确认的直接证据

1. 新签发查询只要求 `t.cr_id = @claim_cr_id`（`execution_binding.sql:15`），handler 二次比较同一列（`execution_binding_issue.go:185`）。没有验证该列来自哪个可信写入路径，也未核对未被改动的 pipeline run/node 或其他权威关联。
2. `server/internal/handler/daemon.go:4531–4547` 的 StartTask body 接受 daemon 的 `cr_id`；正常 start 成功后，`:4595–4603` 调 `TaskService.AttributeTaskToCR(task.ID,req.CRID)`。这是同一认证 daemon 可以调用的现有服务路径，不需要直接 SQL 写权限。
3. `server/internal/service/task.go:4701–4723` 明文称此值来自 daemon workdir branch 自报、用于 gate-node UI，且“self-report is not a security boundary”。helper 调 `SetTaskCRAttributionIfValid`。
4. 对应 SQL `server/pkg/db/queries/agent.sql:1129–1143` 实际是 `UPDATE agent_task_queue atq SET cr_id=$2 ... WHERE atq.id=$1 AND atq.agent_id=a.id AND EXISTS(CR in a.workspace_id)`。**没有 task 原 CR 相等/只允许 NULL→值、task issue 与 CR shell issue 相等、pipeline run 归属或 project 一致的条件**；所以不只可填空，连已有 CR 标记也可被换成同 workspace 内另一个 CR。

### 静态触发链（未动态执行）

同 W/P/daemon 下存在 CR_A、CR_B，B 有合法 head/coordinator；T_A 的真实 pipeline/issue 来源属于 A，且该 daemon 持有 T_A 的有效 R/G：

- 在合法 start 调用中，daemon 提交 T_A 与正确 R/G，却自报 `cr_id=CR_B`；start 的 generation fence 即便通过，后续 attribution UPDATE 仍可把 T_A.cr_id 改成 B。
- 再向 B 的 binding endpoint 提交 **正确且 canonical 的 T_A/R/G**、B head 的 challenge。新的 task_id 主键、R/G、active、W/daemon、project、`t.cr_id=B` 及 handler ID 二次检查都可成立。
- 结果仍能签出 CR_B↔T_A 的关联；这个“DB 事实”实际上是同一个 daemon 在前一步写入的自报值。已存在的 CR_A pipeline context/node 关联不会因该 UPDATE 被同步改变。

**准确分类**：这是本轮新确认的残余触发路径，属于原 F1 的可信 CR 来源根因，不另造一个独立重复 P1。五项修改中的 ID/SQL 等值检查是真修复，不应否认；但不能把“与 advisory 列相等”写成“可信 CR 关联已验证”。不声称无 MDT 的外部用户可利用，也不声称能够消费/启动 Agent；所涉攻击/误报条件仍是同 W/P 中的合法 daemon。

**建议的最小修复方向**：为签发选择明确的权威关联来源，例如经过验证的 pipeline node→run→CR，或与所支持 issue-backed 模式相符的服务端关联；核对该来源与 T/R/G/project 一致。或者先使签发依赖的 CR 列具有可信、受限、不可由普通 attribution 覆盖的写入语义，并对来源做区分。仅再比较一次 task.cr_id、简单加 IS NOT NULL，或只改原负例 fixture，均不能解决这条路径。至少需要 StartTask 自报 sibling CR→binding 的负例，证明不能通过 advisory attribution 洗成可信关系。

## 三、新 task_id 的四个专项问题

### 1. 是否还把 task_id 当作自报事实？

**task_id 本身：否。** 它只是选择器；handler `:140–143` 传入任务主键及其余事实，SQL `:11–18` 同时核 T/R/G/active/CR/agent workspace/runtime workspace/daemon，handler `:185–192` 再核 ID、CR、project；输出 task_id 取 claim.ID。R/G、status、owner 不是靠 body 自证，F2 已关闭。

**CR 来源：仍有自报写入后的间接信任问题。** N1 是 advisory 字段来源，不应与“没有查询 task_id”混为一谈。DB 查询成功只能证明当次 snapshot 列值满足条件，不证明 CR 来源权威、child 身份或持续 freshness。

### 2. NULL-CR 的合法 issue-backed task 会不会被挡？

**会。** `t.cr_id = 非 NULL 参数` 对 NULL 不为 true，直接 409 `EXECUTION_BINDING_CLAIM_UNAVAILABLE`；无 NULL→同 project/同名 CR fallback。`task_without_cr_rejected` 测试 `execution_binding_issue_test.go:409–422` 明确要求这一行为；fixture `:89–92` 还额外 UPDATE task.cr_id 后才跑 happy path。

不是所有合法 issue-backed task 天生就有 CR：所读普通入队路径 `service/task.go:1487–1544` 把 issue/project 等传给 CreateAgentTask，没有 CR；`agent.sql:318` 起的 CreateAgentTask 与既有 attribution 设计允许这些任务随后才归属 CR。相对地，Runner 的 `service/task.go:375–424` 在 EnqueuePipelineTask 中显式传 spec.CrID 与 PipelineNodeRunID。这足以否定“所有生产合法任务必有 cr_id”，但**没有证明某个已正式承诺可用的新 binding 生产来源必然因此坏掉**。

判定：对“只能向有可信明确 CR 关联的任务签发”的窄安全片，拒绝 NULL 是可接受 fail-closed；它不是错误授权。它确实缩小支持集合，普通 issue-backed/归属尚未建立的任务不能签发，不能宣称向后兼容或已覆盖全部 issue-backed 来源。应在协议/支持范围明确要求，或者用权威映射支持合法 NULL 来源；不得自动猜测或让 daemon 自报补列来绕开。未确认新增独立 P2 生产兼容故障，未跑端到端来源验证。

### 3. unique-conflict 重读是否跨 W/CR/challenge？

在所读代码中**没有这样的查询扩大**：`execution_binding_issue.go:255–258` 同时限定认证 workspace UUID、已验证 URL CR、head.GrantDigest、原 challenge，均为参数绑定，rollback 不改这些局部值。普通命中也经 `GetExecutionBindingIssue` 的同四谓词（`execution_binding.sql:20–26`）。新增 task_id 没有进入字符串拼接或替换 namespace。

保留上轮已经披露、并非本轮新缺陷的边界：台账唯一键仍不含 task/runtime；普通命中及冲突重读只返回 winner envelope，不将 stored envelope 的 task/runtime/roots/PID 与本次请求逐字段比对。所以不得把“没有跨 workspace/CR/challenge 查询”扩大成“每次回包必定与新 body task_id 相同”。同 nonce 复用到另一 task、旧版本签发记录、重读时 head/claim 是否仍 current，未新增再验证；这属于既有 nonce-idempotency/历史记录/快照边界，不因 F2 的新建行主键检查而消失。

### 4. 是否新增确证 P0/P1/P2？

- **P0：未确认。**
- **P1：N1，F1 同根残余路径**；不是五项之外重复计数的第二个身份缺陷，也不是本轮创建的新 StartTask 缺陷。新增依赖使既有 advisory 写路径成为本修复必须处理的直接可信来源问题。
- **P2：未确认新的独立项。** 原 F3/F4/F5 已按源码关闭；NULL 支持缩窄、unique error 仍按字符串识别（handler `:473–475`）和旧 winner payload 语义分别列作边界/建议，不偷换为新增认证突破。

## 四、证据强度（只读，非本评审执行）

- 读取 `green4.meta.json` 与 `green4.stdout.jsonl`，独立统计文件事件得到 **16 RUN / 16 PASS / 0 FAIL / 0 SKIP，15 leaf**，与元数据一致；作者记录 migration 已应用、原库 unchanged/released、临时资源 cleaned。没有访问 DB 核实这些运行状态。
- 定向读取新增测试 `execution_binding_issue_test.go:394–516`：覆盖 CR 列不同/NULL、task A ID 搭 task B generation、另一 CR 的 task ID、null process_id、null challenge、大写 runtime。名字 `ambiguous_generation_rejected` 的当前内容是 **不同 generation 的跨 task 错配**（`:424–453`），不是“两个 task 同 R/G 下各自精确选中”的动态用例；源代码 t.id 主键条件仍足以关闭原 F2 的任取根因。
- 该 null/canonical 子例只含所列三种 mutation，不能宣称 parent_process_id null、canonical task 别名、所有十二字段的 null 都各自执行过。源码 guard 是关闭依据，aggregate 绿数不补造覆盖。
- 未见本轮定向测试证明 N1 的 StartTask 自报链被阻断；也没有本评审独立执行 unique-conflict/MaxConns=1/取消交错。F5 静态关闭依赖明确 rollback-before-pool 与 pgxpool 释放语义。
- `final-vet.json`（`2026-10-25T08:15:26.581Z`）记载 vet_exit=0、gofmt_unformatted 空、node_exit=0、9 tests/9 pass。此短 JSON 没有 vet 完整 argv；“五包范围”为用户提供信息，不以该短记录独立证明。未重新运行 vet/gofmt/node 测试。
- wire §3.6 已改为 exact 四键及指定 task 多谓词复核；签名 payload 仍 20 键。只核这一协议增量，没有重读 T 全量、扩展签发为消费或证明 relay 已接通。

## 五、保留边界

本轮是完成的五项限定静态复核，不因没有动态执行而统称 INCOMPLETE；F1 PARTIAL 是有具体残余代码路径，其余 CLOSED 限源码。

未签完整 terminal 链、生产准入、消费、receipt、activation、同 UID 隔离域、全局 C1 或 Gate3；未重新签既往 Fail replay/Complete/server closure，也未重审 append-only/runner 等未变风险。PID/PPID、roots 与 tools_digest 仍为 daemon 转述，服务端不能证明真实 child/OS 进程。事务 snapshot 不代表响应时持续 current；历史 winner 重读不代表重验 payload。

**旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 附：发布前文件身份核对

时间：`2026-10-25T08:19:48.860088+00:00`。八文件均匹配 final/green4；仅复核报告所列必要切面。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| server/internal/governance/execution_binding_issue.go | 19877 | b1c1ee897d5071fe3b3e273f8d43d92a37e7797f05eb1930b9c0e3d8fe32193d |
| server/internal/governance/execution_binding_issue_test.go | 23966 | adf287b4999576486f0f7065c428457991ed84e753b8f19b7ce0331e53797ef4 |
| server/internal/governance/execution_authorization_routes.go | 4029 | 4be183d44cd419660d273a4f7dec6aa503f0c911e1527d7b3288d53253bce5e3 |
| server/pkg/db/queries/execution_binding.sql | 1646 | 2305fc71d51b7c761e5d7c85a2771e04e6b3b30d17c6381aad7bc9863886fd72 |
| server/pkg/db/generated/execution_binding.sql.go | 6944 | 57b9db8a19eaf5464e18b80346a0f9220789e35c9238d979a61525f67fcf373f |
| server/pkg/db/generated/models.go | 98581 | 766ef44b820d94d6248a243e386fe22f2d87ff558dd5e0cab5046754b5a193b2 |
| scripts/aifi45-db/run.mjs | 15409 | 5a156a3b0535597ee01b087b3947b81b5a36346eb44e952fbd2681599cd62ee9 |
| scripts/aifi45-db/run.test.mjs | 7284 | 66fc97edcf121f3cec7c999f77e974e5010fdbd77a93749b663bd39c0436a6ca |

辅助路径发布时取样（非上述已测冻结扩展、非新增全量审查）：

- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/service/task.go` — 412401 bytes；SHA-256 `0406f1276ca3f9e1dd1dfd9845797af5a346c9af52cc22b94f034b3b03ecebf2`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/pkg/db/queries/agent.sql` — 148164 bytes；SHA-256 `6a372e24c77de1233ad3dd2b32b6f151d2bf72658a65d0e32786887b27fd9429`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/handler/daemon.go` — 290639 bytes；SHA-256 `9876436d918622b47117c46c36d8a81de0cfb27d00af6afd054d469a73919330`。
- `C:/Users/GOBAO/go/pkg/mod/github.com/jackc/pgx/v5@v5.11.0/pgxpool/tx.go` — 2854 bytes；SHA-256 `bf7ae13266452db9fd3f947f726f9c9015a947c62147979e66b31a97987eda3a`。
- `C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md` — 35031 bytes；SHA-256 `5d1ed934943b58924d3ba456cc2f32ef30f611f9fb109745ac6300a0e59f9350`。
