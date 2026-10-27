# AIFI-45 M13–M15 — 来源校验与四阶段 carrier 批次

> 最新状态：**M13–M15 已验收** —— 四根因真实RED→GREEN、双轴终复无hardP；Main 治理/handler 全包通过，daemon 在专属临时 Linux 容器（non-root）中与 HEAD 三文件 baseline 逐项对照**无新增失败**。六动作已勾；未 commit/push/deploy、未真实 CR、未清理 PG。仍不声称四阶段 walker/真实 CR 执行完成。

## Main 联合复核与 B-WIN-DAEMON 环境停点

**最终结果（覆盖本节原 Windows-only 停点）：** 用户批准专属临时 Linux 容器后，仅自建容器 `aifi45-m13-m15-linux`（label `io.aifirst.test-run=aifi45-m13-m15-lxa82e17`，golang:1.26-alpine/go1.26.9，容器内补 git/node/bash 与 /scripts exec 位）内 non-root 跑完整 daemon 候选与 HEAD 三文件 overlay 对照：**candidate 1890PASS/4SKIP/1FAIL，baseline 1889PASS/4SKIP/1FAIL；新增失败集合为空，无 case 删减，唯一差异新 `TestMDispatch004` 通过**。残留 `TestProvisionDshMulticaProfile_CancellationKillsTheWholeTree` 在本容器内双向偶发（4轮中候选与基线都出现过 fail/pass），非候选新增失败。模块仅 bootstrap 联网，测试一律 `GOPROXY=off -mod=readonly GOENV=off GOTOOLCHAIN=local`；容器内独立 HOME/中性 git 身份/非 root，**未修改用户或系统 WSL/git 配置**。证据拷出 OS Temp 后容器已 `podman rm -f -v` 精确删除，前后无残留容器/卷；M10 授权 PG 保留。M13–M15 六动作已勾。

- 治理：native0/37.684668900s，202父+188子PASS/1旧LiveGitHubSKIP，391RUN/391完结/无DBskip。
- handler：native0/73.025826000s，2430父+1861子PASS/47SKIP，4338RUN/4338完结/无DBskip。实际skip完整名称/原因留原生JSON，未用skip换绿。
- daemon Windows完整：native1/33.038011400s，884父PASS/55父FAIL/74父SKIP，847子PASS/1子FAIL/12子SKIP，1873RUN/完结。**不是全包通过。**
- daemon HEAD源对照：仅以Go-overlay将三个changed daemon源/测试替换为HEAD原文，传递依赖仍当前冻结候选；同样独立进程级隔离HOME/USERPROFILE/AppData/中性test Git identity、缓存固定、白名单环境，不修改用户系统设置。不checkout/stash、不改仓文件。native1/33.635382200s、1872RUN；**56个FAIL名称集合、86个SKIP名称集合完全相同，所有共同case终态不变，无删除case；候选唯一新增TestMDispatch004通过。** 不能把此对照冒充整个仓库pristine或Windows全绿。
- Main daemon定向原合同+新TC：3/3PASS、native0/5.286296700s、0skip；gencheck0/0.302614100s、三包vet0/0.732565400s、backendbuild0/3.627785000s。3594server/259tools源稳定，tools073c…与四gen/M11parser70/M12known UUID守卫不变。
- 证据OS Temp `aifi45-m13-m15-main/` 下各包stdout/result、baseline-daemon-overlay.json+HEAD源码、daemon-baseline-comparison.json、daemon-targeted、gen/vet/build。作者旧candidate/RED/review-fixes均保留不覆盖。两reviewer只读未亲跑，不用模型意见替代native结果。
- 只读环境发现（停点已由用户授权解除）：WSL Ubuntu ext4.vhdx 缺失，未修主机；已用专属临时容器完成 Linux 验证并精确清理。M20–M22 合批已交唯一 writer，实现未开始验收。

## M13 — source provenance / executor 分离

- `runner.go::checkSourceTask` 只读校验：source task/agent/workspace；target CR 同 workspace；source `cr_id` 存在必须精确匹配；source issue/project 同 workspace；`cr.shell_issue_id` 与 source issue 双方存在必须精确匹配；source project 与 issue project 双方存在必须精确匹配。
- 补两个同源边界：
  - `source.project_id` 明确而 `issue.project_id` 为 NULL → 拒绝，不再用 `&& issueProjectID.Valid` 跳过。
  - `source.project_id` 为 NULL、`issue.project_id` 非 NULL 时，沿 `issue.project_id` JOIN 校验该 project 同 workspace；跨 WS 的合法 FK 异常数据被拒。
- `runner_requirement_entry.go::StartRequirement` 传入 target CR 复用同一校验；未改 TaskService/SQL/API/DDL。
- completed source 合法；未绑定 `cr.shell_issue_id`/`task.cr_id` 的旧同 WS 信任窗口保持原行为，不声称已证明历史 CR↔issue/project 关系；真实 `CreatePipelineTask` 仍额外要求 source issue/originator/accountable，本 early guard 不替代下游 service 约束。
- `TestMBinding004/005/006`：
  - 004 五类非法绑定 + 合法对照；
  - 005 completed source 全量 provenance + 真实 `EnqueuePipelineTask`，Executor 独立、Issue/Project/CR/originator/accountable/node-run 保留；
  - 006 合法 relation、source agent/CR/issue/project 不符、bound CR + issue-less source，以及新增 project NULL/跨 WS issue project 两个真反例。
- RED：旧 task/agent/workspace-only 查询在 source CR 处失败；新增 project 边界在旧 `&&` 条件下失败（`source project with an issue-less project must fail closed`）。恢复后 GREEN。
- GREEN：`^TestMBinding00[456]$` exit 0；5 RUN = 3 顶层 + 2 子例，6 PASS，0 FAIL/SKIP。相关治理回归 83 RUN/PASS，0 FAIL/SKIP。

## M14 — server claim carrier

- 获批最小 DTO scope：`internal/handler/agent.go::AgentTaskResponse` 与 `internal/daemon/types.go::Task` 新增 `PipelineID`、`PipelineNodeRunID`、`PipelineTemplateDigest`（既有 JSON/omitempty 风格；不含 `pkg/protocol/messages.go`、endpoint/flag/DB/SQL）。
- `handler/daemon.go`：
  - 四阶段 carrier allowlist/受控 bound：architecture/requirement/code/writeback；code/writeback 通过既有 compiled snapshots 读取，不新增 Start/Walker。
  - `hydratePipelineContext` 保留 context 一致性校验并设置 `PipelineID`。
  - 新增 `validateClaimedPipelineCarrier`：以 DB `task.pipeline_node_run_id → pipeline_node_run.run_id → pipeline_run` 和 compiled digest 为权威；校验同 workspace、runID、template nodeID、node-run、attempt、CR、template digest、executor agent active/runtime/同 WS。task.context 仅作一致性副本；任何缺字段/漂移 fail closed 并取消 claim，不降级普通任务。
  - `PipelineNodeRunID`/digest 从 DB 权威派生；旧 `executor_agent_id` 不参与执行人选择。
- `TestMDispatch006`：
  - 四阶段 positive claim roundtrip（architecture/requirement/code/writeback），断言 PipelineID/NodeRunID/RunID/NodeID/Attempt/CrID/Digest/Prompt。
  - 负例：workspace、digest、templateNode、attempt、node-run、executor 归属错均拒绝并取消 claim。
  - 既有 hydrate 合同更新：code/writeback 从“未知拒绝”改为“已批准四阶段接受”，未知 pipeline 仍拒绝；原 architecture/requirement 正负例保留。
- RED：临时移除 validator 调用，四阶段 positive 缺 DB 派生字段、全部负例被放行；恢复后 GREEN。
- GREEN：`TestMDispatch006 + TestHydratePipelineContext*` exit 0；25 RUN（9 顶层 + 16 子例），26 PASS，0 FAIL/SKIP。

## M15 — daemon carrier / dirty-start

- 生产行为已具备按 node+attempt 判定：requirement writer 第 1 轮/checkpoint/review 规则来自 compiled declaration；architecture/code/writeback 等无专属 dirty 例外，保持 clean。未改 `preparePipelineTask`/`inspectPipelineWorkspace` 语义，也未加全局 whitelist 或复制 requirement 例外。
- 新 `TestMDispatch004` 锁定：
  - requirement writer 第 1 轮 clean、repair 轮允许；checkpoint/review 按声明允许；
  - registration、architecture、code、writeback dirty 均拒绝；
  - 允许节点在 wrong branch 的 dirty 仍拒绝；
  - 新 carrier 字段经 `preparePipelineTask` 不改写/不丢失。
- 该测试是对既有已正确行为的等价锁定，未伪造 RED；M15 本切片无生产改动，避免为制造 RED 引入新 dirty 白名单。
- GREEN：`TestMDispatch004 + TestPreparePipelineTaskDirtyGate` exit 0；2 顶层 / 3 PASS，0 FAIL/SKIP。

## 哈希

| 文件 | raw / LF | 行数 |
|---|---|---|
| `governance/runner.go` | `a5ef5709…3110` / `2499b73a…bca5` | 1564 |
| `governance/runner_requirement_entry.go` | `deecbf0b…ad12` / `f4591694…a7a` | 310 |
| `governance/runner_integration_test.go` | `6f8e2f48…b9c7` / `d4e6be35…7de2` | 1326 |
| `handler/agent.go` | `0184b70b…0b96` / `057b83b5…2102` | 3088 |
| `handler/daemon.go` | `73920f79…2819` / `2e332227…b42d` | 6475 |
| `handler/daemon_test.go` | `f58ff5b5…f6bf` / `b384937a…be0a` | 5002 |
| `handler/pipeline_context_test.go` | `d3fd0a8a…3a2d` / `5ca35c5d…d900` | 188 |
| `daemon/types.go` | `2aa64a68…fc70` / `acb856a2…fb877` | 350 |
| `daemon/pipeline_task_test.go` | `02b82a4a…59c5` / `365a579e…1344` | 1868 |

四份 generated、`runner_requirement_registry.go`、`runner_contract_test.go`、M11 parser/427 前缀、tools 073 未改；M12 known-execution UUID guard/旧 queued-running 不改派保留。

## 边界 / 未证明

- M13 的 source 关系只在双方已有值时 exact；未绑定 shell/source CR 的旧同 WS 窗口保持原样，未证明历史关系。真实 service `CreatePipelineTask` 仍要求 issue/originator/accountable，early guard 不声称覆盖其全部约束。
- M14 四阶段 carrier 只做受控识别/校验，没有 StartCode/Writeback route/walker/半套启用；没有 daemon 反查 DB 或客户端自报权威。
- M15 没有生产 diff；行为由既有按节点/轮次合同提供，本切片仅锁定。实际四阶段 walker/恢复仍待 M20+。
- 未改 `pkg/protocol/messages.go`；未新增 DB/SQL/HTTP/CLI/扫描 worker。
- 未勾任务、未 commit/push/deploy、未真实 CR/存量接管/Gate3/权限环境变更、未清 PG。

## 证据

`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m13-m15-evidence\`：
`m13-green.json`、`m13-green-stderr.log`、`m13-related.log`、`m13-edge-red.log`、`m14-green.json`、`m14-green-stderr.log`、`m14-red.log`、`m15-green.json`、`m15-green-stderr.log`、`vet.log`、`build.log`、`summary.json`（目标 PG `127.0.0.1:33551 / aifi45_test / aifi45`，不记录 DSN；未清理）。

**精确停点：** M13/M14/M15 作者侧可交 Main 联合完整回归/两轴复核；若 Main 发现 M15 需要显式生产改动或 M13 source policy 空洞，按当前证据最小定位，不扩大路由/白名单/账本。

---

## Review fixes（第二轮，2026-10-20；旧 candidate/证据保留）

### 1. 旧 public attempt bound 回归（High）
- 撤掉 `runner.go::PipelineReviewMaxAttempts` 的 code/writeback 分支；该函数恢复只接受 architecture/requirement，原有 `TestReviewMaxAttemptsRefusesInvalidDeclarations` 语义不变。
- handler/daemon 仍使用 M11 泛化的 `ReviewMaxAttemptsFromSnapshot` 读取 code/writeback 受控声明，不新增 legacy shim。
- RED：临时恢复旧扩展，`TestReviewMaxAttemptsRefusesInvalidDeclarations` 在 code/writeback 处失败；恢复后 GREEN。

### 2. Server 普通任务降级（P1）
- `validateClaimedPipelineCarrier` 不再以 `resp.PipelinePrompt==""` 提前返回；门控为 **DB `task.pipeline_node_run_id` 有效或 context `type=pipeline_node`**。
- DB pipeline task 的 `{}`、`type=ordinary`、非 object JSON、缺 prompt、坏 context 均 fail closed/cancel；真正无 FK/无 pipeline marker 的 ordinary task 保持兼容。
- RED：临时恢复旧 prompt-empty 短路，`degrade-empty-object`/`degrade-ordinary-marker`/`degrade-non-object-json` 被 claim 放行；恢复后 GREEN。

### 3. Pipeline-node compiled membership（P2）
- `runner.go` 新增受控纯函数 `CompiledPipelineNodeFor(pipelineID,nodeID)`：只选四已知 compiled pair，复用 `parseCoreRegistryFrom`/expected digest，返回 nodeId/kind/ref/digest/maxAttempts；human/非成员/未知 pipeline fail closed；不开放 body、不改原 parser validator/70 tests。
- handler 以 DB run pipeline + nodeID 调该函数，校验 membership、digest、attempt；daemon `preparePipelineTask` 同 helper 校验 membership/digest/attempt 后，才进入既有 `RequirementDirtyStartNode` dirty 判断。
- code run + requirement writer UUID、requirement run + code UUID不再因 DB/context 相等而接受；UUID 前缀/区间不参与判断。
- RED：M15 tamper（missing/cross membership/wrong digest/attempt）在旧 prepare 被放行；server cross-membership 负例在旧 handler 无 membership 时会被接受。恢复后 GREEN。

### 4. M15 真实消费（P1）
- `preparePipelineTask` 生产入口现要求 pipeline marker 存在时完整字段：PipelinePrompt/CR/PipelineID/NodeID/NodeRunID/RunID/TemplateDigest/attempt；UUID 格式、compiled membership、full digest、attempt 合同全部通过后才允许 dirty。缺字段/错字段/Prompt 空不再降级 ordinary。
- NodeRunID 在 daemon 只做格式/同载体一致性 + server transport 信任；DB node-run/run 关系仍由 handler 校验，daemon 不反查 DB、不加 signer。
- code/architecture/writeback clean 合同不变；requirement dirty 例外只在 membership 通过后按原 node+attempt 使用。
- 测试 fixture 增加必要 carrier 字段；未知 node 由“dirty 拒绝”改为 compiled membership fail-closed（更强），未删弱原断言。

### 本轮 GREEN / 证据
- M13 `^TestMBinding00[456]$`：5 RUN = 3 Test + 2 subtest，6 PASS，0 FAIL/SKIP。
- M14 `^TestMDispatch006|TestHydratePipelineContext`：30 RUN = 9 Test + 21 subtest，31 PASS，0 FAIL/SKIP；四阶段 positive + missing/tamper/ordinary degradation 负例。
- M15 `^TestMDispatch004|TestPreparePipelineTaskDirtyGate`：2 RUN/2 Test，3 PASS，0 FAIL/SKIP。
- 原相关回归：治理 83 RUN = 63 Test + 20 subtest，83 PASS；handler claim 83 RUN = 58 Test + 25 subtest，83 PASS；0 FAIL/SKIP。
- `go vet governance+handler+daemon` 0、`go build ./...` 0、`git diff --check` 0。
- 新证据目录：`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m13-m15-evidence\review-fixes\`（分阶段 RED/GREEN、相关回归、`summary-review-fixes.json`）；旧证据未覆盖。
- 计数已区分 Go Test 与 package pass event；旧 summary 的 6P/5RUN 等保留为历史，不作为本轮 Testcase 计数。

### 本轮未证明 / 边界
- M13 未绑定 shell/source CR 的旧同 WS 窗口仍不证明历史关系；真实 service 额外 source issue/originator/accountable 约束仍在 `CreatePipelineTask`。
- M14/M15 只做 claim/carrier 不启动 code/writeback walker；无真实四阶段运行，不把低级 fixture 当运行闭环。
- NodeRunID daemon 侧不证明 DB 关联；该证明在 handler。未新增 signer/DB 反查/新表/协议路径。
- 未勾任务、未 commit/push/deploy、未真实 CR/存量接管/Gate3/权限环境变更、未清 PG。

### Review-fixes 计数修正 / 最终证据
- M14 最终包含 cross-membership 负例与 4 个 degradation 负例：`TestMDispatch006 + TestHydratePipelineContext*` **30 RUN = 9 Test + 21 subtest，31 PASS，0 FAIL/SKIP**。
- M15 最终加入 `TestPreparePipelineTaskHydratesMachineLocalPaths` fixture 修正：**3 RUN = 3 Test，4 PASS，0 FAIL/SKIP**。
- 原相关回归：治理 83 RUN = 63 Test + 20 subtest，83 PASS；handler claim 83 RUN = 58 Test + 25 subtest，83 PASS；0 FAIL/SKIP。
- 最终 RED 日志：`bound-public-red.log`、`m14-degrade-red.log`、`m15-tamper-red.log`、`m13-edge-red.log`。
- 最终 hash/计数：`review-fixes/summary-review-fixes.json`（区分 Test 与 package pass event）；旧 summary 保留。
- 完整 daemon 包受环境缺少原始 Git 全局配置影响出现既有非本切片失败；本轮只以定向 + 相关包证据为准，未把完整 daemon 绿当已验收。
