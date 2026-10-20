# Phase Context — AIFI-45 四阶段统一 Runner

## 最新接续停点 — M00–M34 已验收；M33/M40 并行实施中（用户要求不停、能并行就并行）

### 并行编排（用户 2026-10-19 指示）
- **Lane A**（`01a154e9-42d6-75ce-a57c-1bb8277722e4`）：daemon 包。当前 M33（终态队列结构化 recovery + argv/身份篡改拒），随后 M35a→M35b→M36→M37a→M37b→M38a→M38b→M39（传输/公钥/投递按依赖顺序）。
- **Lane B**（`01a15720-9426-75ce-a57c-1be57fd53d8c`）：governance 与其他包。M34 已交付并验收；当前 M40（`pkg/taskfailure` 分类回归，不占 DB），随后 M41a/M41b（service/retry，占 DB）。
- **Lane C**（只读 planner）：已完成 M35–M39 事实地图（schema 常量、hub lease、heartbeat/actions、多 workspace header、PublicKeyPEM、grant 投递与原子落盘、key 轮换、`.gitignore` 例外、TestMKb/TestMKey 规范入口），供 Lane A 直接消费。
- **纪律**：同一时刻最多一条 lane 使用 DB 33551（当前 M33/M40 都不连 DB，DB 空闲）；Main 不在 writer 运行期跑同包 Go；两条 lane 文件集合不相交（daemon 包 vs governance/pkg）。
- **B-SWEEP（M-PRE.5）**：用户授权"只做隔离实测后按实测值落定"。将在 M42 前单独做隔离测量（真实 30s tick 边界、批大小、单次超时、公平续扫），记录真实数字后再落值，不新增 flag、不以 tick 当 SLA。

### M35–M39 关键事实（Lane C，摘要）
- M35a：`local_directory_snapshot:{workspace_id,daemon_id,resources}` 已在 implementation-notes 定名；省略/null/读取失败保留，成功 `resources:[]` 清身份，缺 resources 不算空成功；**不新增 schema/endpoint/能力开关**。wire 在 `pkg/protocol/messages.go:121,406–436`，事件常量 `events.go:150–173`；lease 在 `internal/daemonws/hub.go:23–96`（RuntimeLease 无 daemon_id）→ 需复用 runtime.daemon_id 写入 lease。
- M35b：`handler/daemon.go:1373–1541` heartbeat 流程；`1186–1208` HTTP 手工挑字段，新 ack 字段需同步映射；`daemon_ws.go:36–100` + `middleware/daemon_auth.go:119–150` 说明 daemon token 才设机器身份（PAT 不可），**不采信 query/header 自报机器身份**；资源批查需同时约束 workspace，禁 N+1。
- M36：`client.go:730–746` HTTP ack alias 协议 ack，`wakeup.go:360–375` WS ack 进同一 handler；`daemon.go:2192–2193,4600` collector/actions 接缝；`crevents.go:183–225` 静态 roots；`config.go:169–173,677,685–695` 仍解析 `MULTICA_CR_WORKSPACES` 且无残留拒绝 → 需无条件生命周期启动 + 快照替换/空清除 + env 残留拒。
- M37a：采集 `crevents.go:230–250`（字符串 Contains）vs 定位 `pipeline_task.go:622–716`（realpath/项目包含/唯一匹配）vs settle `daemon.go:6342` 三处不同源；两处 not found 指采集入口与定位入口（非服务端 404），需统一携带 workspace/CR/资源/daemon 线索。
- M37b：WS 已多 workspace；server `governance/daemon_workspace.go:28–58` 按 `X-Workspace-ID` 验会员、多会员无 header 即拒；daemon `client.go:97–126,1288–1331` 共享 client 无 workspace → 用请求级 header/context；实际 pending/ack 在 `crevents.go:84–117`，ack 删除需校验属当前批。
- M38a：`approval.go:203–211` 已有 PublicKeyPEM；`489–519` pending 仅 grants → 同响应加 `public_key:{key_id,pem}`（design.md:82），**不提前删 ack 续接**（属 M50）。
- M38b：`crevents.go:122–166` 现在把每条 grant 写向**所有 roots**、任一成功即 ack → 需唯一目标解析（复用 `pipeline_task.go:698–716` 但要先限定 workspace）+ 信任检查（`client.go:127–141` 无远程明文限制、`wakeup.go:507–519` 接受 http/ws）；同一响应 key/grant 不得互相自证。
- M39：`crevents.go:141–166` 直接 `os.WriteFile`，无原子可见性；`pkg/gitguard/spool.go:58–63` 有同目录临时文件→Rename 先例；`approval.go:111–117,498` 服务仅持当前 key、pending 保留历史 grant_json；`crctl.mjs:139–148` 按 grant.key_id 读安装根公钥、缺失 `KEY_NOT_FOUND` 不自动轮换；真实 `.crctl/.gitignore:1–4` 为 `*` + keys 放行；**不覆盖旧 key、不改真实 KB 忽略配置**。

### 历史停点（M00–M31 时）

- 用户裁定（2026-10-19）：① **B-SWEEP 授权只做隔离实测后按实测值落定**（不新增 flag、不以 30s tick 冒充 SLA；M42/M43 前先完成实测并记录真实数据）；② **真实 CR 由用户单独验证**（本会话不执行真实 CR / 存量接管）；③ **Gate 3 审批由用户在其终端执行**，Main 提供 PowerShell 指令（待 BUILD 收口后再跑）；④ **提交/推送由 Main 执行，部署由用户自行完成**（双仓顺序：先 multica 业务、后集中记录；commit message 带 `business=<sha>`；tools CI pin 对齐在提交后做）。
- 进度：41 项动作已验收（截至 M31）。CUSTOM 已补 **#143–#145** 登记 M20–M30b 代码变更，M4 模块行数 22→**25**，索引连续 1–145、CRLF 保持。
- Gate 3 复核指令（用户终端 PowerShell；cwd 必须是**业务仓根**，已实测 `gate status` 解析）：
  - multica：`cd C:\Users\GOBAO\Downloads\AI\multica` → `& "D:/Program Files (x86)/Python/Python313/python.exe" -B C:/Users/GOBAO/Downloads/AI/stdd/bin/stdd gate approve --gate 3 --confirmed-by cli --evidence "<确认原文>" 2026-10-19-aifi-45-four-phase-runner`
  - tools：`cd C:\Users\GOBAO\Downloads\AI\tools` → 同命令，change 名换 `2026-10-19-aifi-45-runner-contracts`
  - 查看：`gate status <change>`；两 change 当前 Gate 1/2 已确认、**Gate 3 pending**。

### 历史停点（M13–M22 验收时）

- **M13–M22 全部验收**（M20/M21a/M21b/M21a/M22 各由 Main 独立整包）：治理包最后一次 **396RUN = 207父+188子PASS/1旧LiveGitHubSKIP/0FAIL/无DBskip，native0/35.091951600s**；handler 4338RUN/4291P/47skip/无DBskip；daemon 在用户批准的专属临时 Linux 容器内 non-root 与 HEAD baseline 对照无新增失败（容器已清）。M11parser70/原427prefix/四gen/tools073/M12UUID/M13–15carrier 均未漂移。
- M20 用 `cr.needs_reconcile` 投影漂移门（I10 裁定，不复制 crctl 判据）；M21a 拆 persist/coordinate；M21b 写路径同 tx + commit 后派发（残留：tx 外只读预检与 handover 查询，留 M23 TOCTOU）；M22 验证 commit→释放→Reconcile 顺序，新增真实 Bus 同步用例与 `Runner.afterCommit`（仅测试注入）崩溃重建，未改 events/未加异步。
- **当前唯一 writer 01a154e9-42d6-75ce-a57c-1bb8277722e4 做 M23**：合法回修新 cycle（旧终态不复活/不覆 digest，cycle 语义按既有 review-loop 声明而非文本猜）、终态拒重开、注册已提交接入幂等；对应 HANDOFF SC/TC005/006/007 与 `TestMHandoff005/006/007`。无 cycle 列/不新增表列状态，`findOrCreateRun` 不得充当授权器。M24/M25 待 M23 交回后放行。
- 用户未回 A/B，按默认 A 继续；CUSTOM #142 已转“已验收未提交”，M4 仍 22 行。PG33551/私密 config 仍仅该 writer 使用，Main 最终精确清理；无提交/部署/真实 CR/存量接管/Gate3。以下为历史。

- M13–M15 已验收（六动作勾）：四根因真RED→GREEN、双轴终复无hardP；Main 治理 391RUN/202父+188子P、handler 4338RUN/2430父+1861子P均 native0 无DBskip；daemon 在用户批准的专属临时 Linux 容器（non-root）与 HEAD 三文件 overlay 逐项对照，新增失败为空、唯一差异新 TC004 通过，残留 DSH 取消用例容器内双向偶发；容器已精确删除无残留，**未改用户/系统 WSL 或 git 配置**。证据 `OS Temp aifi45-m13-m15-main`、`aifi45-m13-m15-evidence`。
- M20 已验收（I10 裁定）：不新增 crctl 业务判据、不改状态机（`drafting→requirement-reviewing` 属 review 触发），改用既有投影新鲜度 `cr.needs_reconcile`；writer/checkpoint completed 但投影漂移时只写 `wait_reason=projection_stale` 等待。Main 整包 392RUN/203父+188子P/1旧skip/无DBskip。
- M21a 已验收：`startRequirementPersist`（只持久化，不 Reconcile）/`coordinateRequirementStart`（只 Reconcile）拆分；Main 整包 393RUN/204父+188子P/1旧skip/无DBskip。
- M21b 阻塞点已由 Main 给出最小切法：`restoreRequirementRunTx` 本已收 tx（只记账不派发），`continueRequirementRun` 自 Begin（含派发）——因此 tx 内只做记账+restore，**commit+解锁+释连接后再** `continueRequirementRun`/Reconcile，即 M22 要求；不重写整套失败恢复。writer 正按此实施 M21b→M22，仍唯一 code/DB。
- 用户未回复 A/B 范围问题；按既定“按建议继续”授权默认 **A（继续全范围）**，M23 以后仍按批推进；如用户选 B 则改为在 M21b/M22 收口后停止并如实登记后续。
- CUSTOM #142 已转为“已验收未提交”，M4 仍 22 行（#139–#142）。PG33551/私密 config 仍仅该 writer 使用，Main 最终精确清理；无提交/部署/真实 CR/存量接管/Gate3。以下为历史。

- 用户批准专属临时 Linux 容器；已自建 `aifi45-m13-m15-linux`（label `io.aifirst.test-run=aifi45-m13-m15-lxa82e17`，golang:1.26-alpine/go1.26.9，容器内补 git/node/bash+/scripts exec）以 non-root 跑完整 daemon 候选与 HEAD 三文件 overlay 对照：candidate 1890P/4skip/1F，baseline 1889P/4skip/1F，**新增失败集合为空**，唯一差异新 TC004 P；残留 DSH cancel 用例在本容器双向偶发（4 轮两边都出现过 fail/pass），非候选回归。模块仅 bootstrap 联网，测试 `GOPROXY=off -mod=readonly GOENV=off GOTOOLCHAIN=local`；进程级隔离 HOME/中性 git 身份，**未改用户/系统 WSL或 git 配置**；证据拷出后容器已 `podman rm -f -v` 删除，无残留容器/卷，M10 PG 保留。
- M13–M15 六动作已勾；仍不声称四阶段 walker/真实 CR 执行完成，M13 未绑定 CR 旧同 WS 窗口明示未证明。Main 证据：governance 391RUN/202父+188子P/1旧skip native0/37.684668900s；handler 4338RUN/2430父+1861子P/47skip native0/73.025826000s；daemon Windows 定向3P/5.286296700s；gencheck0/0.302614100s、三包vet0/0.732565400s、build0/3.627785000s；3594/259源稳定。
- **当前唯一 writer 01a154e9-42d6-75ce-a57c-1bb8277722e4 做 M20–M22**（tasks 103–106）：M20 权威节点结果消费（禁止 task completed/exit0/模型PASS/仅投影推进）；M21a context 支持缝；M21b 同 pgx.Tx 分配/交接不逃逸 r.pool；M22 commit 且释放锁/连接后才 Reconcile，含同步 Bus 递归/锁序与 commit 后崩溃重建。只改 `internal/governance/*.go`+对应 test，必要 events 最小缝先报 Main；不动 M11 parser/四生成/tools073、M12 UUID guard、M13–15 source/carrier、handler/daemon/DDL/新状态/新引擎。Main 不并行 Go，整包留 Main，证据 `OS Temp aifi45-m20-m22-evidence`。
- CUSTOM #142 已登记在途（M4 现 22 行）；M20 完成后仍需 Main 联合 3 包整包 + 两轴复核才勾。PG33551/私密 config 仍仅该 writer 使用，Main 最终精确清理；无提交/部署/真实 CR/存量接管/Gate3。以下为历史。

- 唯一writer及两reviewer本批均已完成交回，无正在跑Go/DB或改代码agent；四根因真实RED→GREEN、最终独立delta无hardP。Main治理391RUN/202父+188子P/1skip native0/37.684668900s；handler4338RUN/2430父+1861子P/47skip native0/73.025826000s；daemon Windows1873RUN/1731P/56F/86skip native1/33.038011400s，完整终态/无DBskip/3594server259tools不漂移，不宣称全包绿。
- 使用同条件独立fixture HOME+USERPROFILE/AppData+中性test .gitconfig（仅本批临时进程，不修改用户设置）Go-overlay把三个daemon源/测试替为HEAD原文，传递依赖仍当前候选；原包1872RUN，**FAIL56与SKIP86名称集合完全相同、共同case终态无变化，仅候选新增TestMDispatch004 PASS**。该方法不冒称整个仓pristine，所有日志/对照JSON/源在OS Temp aifi45-m13-m15-main。Maindaemon targeted3P/5.286296700s、gencheck0/0.302614100s、vet0/0.732565400s、build0/3.627785000s。
- **环境停点 B-WIN-DAEMON：** readonly发现Ubuntu WSL登记但ext4.vhdx缺失，启动ERROR_FILE_NOT_FOUND；未修主机/WSL。已有cached golang:1.26-alpine镜像，go.mod1.26.6需核镜像实际版本；继续Linux完整验证需新增非PG临时测试容器/必要容器内Go-Node-Git，原用户只授权专属PG，故Main正请求新临时测试环境授权，不自作主张拉镜像/安装依赖/创建测试容器。源码只读、测试产物临时卷、无部署/真实CR/接管/提交/Gate3，完后精确清自己容器卷。M13–M15两动作仍未勾，不把baseline失败等同验收绿；M20–M22只读现成事务地图已回，待此环境决策继续合批。已有PG33551与私密config仍保本批等待后续测试，Main负责最终精确cleanup。
- 更多结果/明确边界见M13-M15-build-report最新Main节；其他以下为历史。

- 批次首版作者冻结/定向GREEN后，联合Spec/Standards发现必须修的4项：旧PipelineReviewMaxAttempts对code/writeback拒绝合同被放宽（原assert不准改删，撤新分支）；handler以context/Prompt空跳过DBpipeline任务导致ordinary降级；仅DB/context node相等未核compiled pipeline成员；daemon3新carrier字段只声明、prepare完全没消费，M15“无生产diff等价锁定”结论不成立。**Main未跑已知坏候选full，不把作者GREEN/DTO字段不丢当消费完成，M13/14/15不勾。**
- 现01a154e9-42d6-75ce-a57c-1bb8277722e4继续唯一writer/DB，先上述真实RED再根因修复，四stage合法与缺失/篡改/跨pipeline-node/dirty轮次负例联合GREEN后重新冻全部source交Main。Main补批准handler/pipeline_context_test.go必要fixture合同更新（不可弱原拒绝assert），以及在既有runner.go添加最小纯compiled-node校验/只读合同访问函数供handler/daemon共享，依四known compiled pair+M11parser，不新HTTP/CLI/任意registrybody/事实表/engine。
- server gate依DB PipelineNodeRunID/已有pipeline marker，不依context是否给Prompt；DB task→nodeRun→run绑定为权威。daemon任意pipeline marker都不得Prompt空降级，先full digest+pipeline/node会员/UUID/attempt输入完整性，后dirty判断；其nodeRun ID只能格式/载体一致性与可信transport，DB关系server验证，不能编造daemon反查DB或签名证明。M15会有真实production diff，既有RequirementDirtyStartNode例外仅合法requirement成员才能用。CUSTOM#142已登记在途，M4现22行。旧M13source窗口/M12无authorqueue边界均不扩接管。以下上一轮信息历史。

- M12原P1/known completed execution P2已真实RED→GREEN、原双轴最终delta无新hardP；3父9子selection/12RUN全P、原83邻接P。Main最终完整native0/38.092139600s、199父+186子PASS/1旧LiveGitHubSKIP、386RUN/完结/无DBskip；gencheck0/0.295488300s、vet0/0.487576000s、build0/3.441863300s，3594/259源稳定。tasks M12两动作已勾，CUSTOM#141完成登记（M4现21行）。边界不变：同原selected completed queue证据的known作者UUIDguard，不证明无authorqueue旧adopt历史身份；完整CP/code walker/历史恢复验收仍后续。
- M12最终LF：runner98d7e2c61ea446e896286af7d8a9d603f778668a97c1a3f860266457074f845c、reqb3f350a90dbd0fe34ea88b4c6c725bc5955afacb72a3adbd69b96cca8bf8d407、integration3428f53f814646706a46bd06aa12d1b0e01a36ec2237bea891b271228073cfb9。证据M12-build-report/OS Temp aifi45-m12-main-final与review-fixes-actual。原382/RED/M11四compiler/parser70/producer073均保留。
- **唯一code/DB writer仍01a154e9-42d6-75ce-a57c-1bb8277722e4，现做M13→M14→M15合批**：先按既有source/CR-shell-issue/project关系TDD，再server claim四stage完整membership/digest/context校验，再daemon节点/轮次dirty与clean carrier；一份M13-M15-build-report，分段真实RED/GREEN，完成批次后一次Main联合full+双轴。Main不并行GoDB，不半套启用Code/Writeback/walker。已批准写域runner.go/runner_requirement_entry.go+两runner tests、handler/daemon.go+test、daemon/pipeline_task.go+test；其它服务SQL/protocol新路径必要先报Main授权，不新表/身份字段/flag/政策。未知新注册bootstrap关联不能凭空补造或把同WS叫同CR，不符/缺证据造成正常注册策略冲突须精确报Main。
- M13作者已真RED→GREEN（3父2子新TC/83相关P），source身份/CR/issue/project守卫落runner.go与requirement-entry；不声称证明未绑定CR/issue的旧同WS信任窗口。M14/15在现Task DTO缺3载体字段处提出最小范围请求，**Main已批准handler/agent.go::AgentTaskResponse、daemon/types.go::Task追加PipelineID/PipelineNodeRunID/PipelineTemplateDigest**，只既有响应结构扩展、无新端点/CLIflag/DB/SQL/pkg-protocol接口；server从DB task→nodeRun→run权威核对，不信ctx/客户端echo。当前writer正继续M14→M15，source/project NULL不一致及issue→project跨WS两边界已Mainsteer要求同批反例修复，未勾M13/14/15、未开半套code/writeback/walker。现写域扩展已记录，不必再次请用户常规审批。
- 自建PG33551/private config仍有效仅该writer，白名单env/explicitDSN/CRCTL，GOENVoff/GOTOOLCHAINlocal/GOPROXYoff/-modreadonly；日志OS Temp aifi45-m13-m15-evidence，Main最终精确清理仍未执行。用户催速度，合批减少重复读取/过程文档，不降低安全/审批/断言/真实证据。提交/push/deploy/真实CR/存量接管/Gate3未授权。回访触发：writer报告完成或具体授权问题→Main复核/回归，必要修复不无限追加轮次。以下均历史。

- 用户再次要求继续并明确执行过久；Main已承认重复调查/过细切片开销，后续合并同域实施与验证、复用既读上下文，不降低权限/审批/证据/独立审查，不再为常规动作请示。全量仍数小时级（4–8h低置信规划，不是承诺），M12目标半小时收口或报告具体阻塞。
- M12首版仅runner.go/runner_requirement.go/runner_integration_test.go，3父5子定向/83相关回归P；Main真实完整native0/38.720701800s、199父+182子PASS/1旧LiveGitHubSKIP、382RUN/结束/无DBskip，gencheck0/0.341380600s、vet0/0.492469400s、build0/3.684085400s，源前后稳定。证据OS Temp aifi45-m12-main，首版绿不是验收；Standards无硬P，Spec发现architecture UUID独立性缺口/真实产出身份未证明及TC001只解析未入队。
- 唯一writer01a154e9-42d6-75ce-a57c-1bb8277722e4已修P1：架构/req共用independent-review guard，真实双方runtime/Skill查完再拒sameUUID，code重复ref两个确切nodeId实际enqueue已有证明；当前继续已选中queue记录AgentID的已知执行作者守卫。沿用latestTaskState现成同一record选择与当前run/nodeId/attempt，不新选first/latest-completed/forensic账本；known作者A改名成为reviewerA必须拒，legacy实际自评task不得consume，不改派已有task。
- 无author queue的既有direct-review/projector-adoption正例本轮保持原行为、不扩存量接管，也不声称证明历史产出身份；SC002/四阶段完整证明还需后续实际执行/恢复验收。若正常从registered新run仍能无证据评审，必须报Main具体流，不把legacy边界当通过。M12未勾，CUSTOM#141在途已登记，M4共21行；任何source范围变化先Main授权。
- M13只读已核：实际db.Cr/table cr，无project_id；正式关联cr.shell_issue_id→issue.project_id→project，source queue有cr_id/issue_id/project_id。现BindCurrentTaskToCR已有锁/CAS但有写，不直接当纯validator；首次未绑定CR只有workspace信任缺口，不能靠completed/猜CR编号或新metadata补证。后续M13–15按同域批次实施/统一review，不重复读整套规范。其余以下M11停点历史。

- M11原3P+新REV004已真实RED→GREEN，经原Standards/Spec逐项最终关闭无hardP；首11→50P、review58(50P8F)→58P、loop完整性68(58P10F)→70P，原50/58cases和427raw前缀不弱化，130邻接全P。只同Raw派生presence、不新SSOT/GoSHA/DSL，非空policy可独立出现且不枚举，ordinary无loop/wb无loop保留。
- Main最终M11完整 **native0/36.797773400s，196父PASS+177子PASS/1既有LiveGitHubSKIP、374RUN/374完结、0FAIL/DBskip**；gencheck0/0.345719300s、vet0/0.474851800s、build0/3.433185000s。3594server/259tools源前后稳定，旧354/362与全部RED分开保留。M11动作两checkbox已勾，CUSTOM#140+M4/CR索引同步；完整SC003 walker/CP003/005/007/四阶段运行时验收仍未闭合。
- M11最终LF runner3c7e58d12a6e956bab41bc4c1f16be5a9d0c9533a96b71f2d9e242a8c117ac8f、req-registry27fa7d145e0d8241b2902910ca7ec28788fbdcefd658858d832362594aa5e112、contract5817850ffbcd54961874621d37e74c88f931f679109b4bd262d6d23e192df7a9。tools073c…/四compiled/generator仍冻结。证据M11-review最新节、M11-build-report及OS Temp aifi45-m11-main-final-r2。
- **当前单code/DB writer是M12新会话01a154e9-42d6-75ce-a57c-1bb8277722e4**，原M11作者与reviewers均完成交回。允许runner.go的actor派发/runner_requirement.go相关resolver+enqueue、runner_integration_test.go/runner_requirement_test.go、M12报告；若其它source必要先报Main授权。M11 parser/guards/typedRaw、四生成/producer/handler/daemon/DDL及M20walker不扩。按精确nodeId.Executor key→同WS真实Agent.UUID，去caller全skills/legacy executor决策，human不lookup/task；保新旧queued/running不改派、source归因不伪造，真实UUID独立review反例不得由缺名错误掩盖。作者证据/多终态选择若无法由已批准语义确定先提Main，不新forensic账本/盲first-latest。
- 33551自建专属PG/私密配置仍有效，只指定writer白名单环境使用，无外DB/.env/KB认证；Main不并行Go，最终按确切run-id容器/卷/私密文件精确清理。本批资源尚未清。BUILD normal/in_progress、Gate3/提交/push/deploy/真实CR/存量接管仍未授权，toolsT04/全35最终及C1–C7仍等待后续闭环。以下旧停点均历史。

- M11首版三文件已实现冻结，Main独立整包native0/37.527436800s、196父PASS+157子PASS/1原LiveGitHubSKIP、354RUN/354完结/无DBskip；gencheck0/0.295725900s、vet0/0.482892400s、build0/3.671315300s，源前后无漂移。Standards独立无硬P；Spec提出三候选：req语义ref helper取first（P1）、有repairID可漏repairRef（P2）、passCondition空/非object被收（P2）。不能拿绿覆盖缺口，M11任务仍不勾、M12未开始。
- 两reviewer首轮已完成释放，原单writer01a154b3-3adf-75ce-a57c-1bb640cddd9b现在独占三文件/DB，先真实反例RED，再最小failclosed/定向GREEN、新SHA冻结交Main整包与两路delta审查。generic重复ref仍合法，只有没有NodeID选择能力的req桥接拒歧义；不提前改M20walker，不引入GoSHA/条件DSL。旧首版SHA/Full354结果保留历史，新身份待修复。详M11-review.md；CUSTOM已新增#140并同步M4为20行、索引1–140，状态在途未验收。

- 用户“子代理已经恢复，继续”后内置Agent实际恢复；此前disabled/旧三source失败/中间caller-09失败均保留历史。ADJ-T-004 source机器绑定仅恢复核对不替换cr.md权威，真实RED→GREEN；两路完整独立review/delta及单行窄复核闭合。
- M10最终tools259 manifest073c75924e21f13c973bfeaa7197a33c98959004d00bab8f47fceafa6e034daa，reqdigestf839d28c30ce2dc0eec709589f742abac1f45db96771d80a3ef3ef66a45ea32c，其余三body不变。MainGo完整195父+108子PASS/1原LiveGitHubSKIP、304RUN/完结、0FAIL/DBskip、native0/40.292777400s；tools8完整213/213、native0/7.095790200s，gencheck0/0.345544000s、backendbuild0/8.887457500s。259/3594源前后稳定；M10a/b四动作已勾，SC003/CP005/007完整runtime仍后续。
- 当前唯一code/DB测试writer **01a154b3-3adf-75ce-a57c-1bb640cddd9b（M11）**，允许runner.go（parser/types必要derivedview，不做M12/20）、runner_requirement_registry.go、runner_contract_test.go及M11报告；tools/原generator/四生成产物冻结。先行为RED再共享declaredparser，完整raw/typedinputs/nodeId权限/多loop/no-loop，旧guards不弱化；完成后冻结交Main完整回归和独立审查。Main不并行GoDB，不据M10表声称M11文件未变。
- 新33551独立PG runid aifi45-m10-repair-e4o5e8vm（651迁移）仍仅用于本授权切片，private配置由指定writer读取，严禁旧已删DSN/.env/外DB。当前资源未清，Main最终核标签/名字/卷归属精确删除；不是旧33551之前批次已清理的状态。
- M12只读planner补全：既有resolver/fixture/design已是actor key＝Agent.name的同workspace精确查找，Main决定复用、不引入显示名翻译/新身份字段/fallback或修installer。真实线上命名未核，不能推断线上错误；旧same-agent测试可能只触发缺名，后续须命中真实UUID自评反例。详I8。M12尚未实施。
- BUILD仍in_progress/normal(enabled=false)，不是Gate3，未commit/push/deploy、真实CR、存量接管、新依赖/工具权限/系统变更。B-SWEEP/最终C1–C7/四阶段闭环仍未来；toolsT04须等平台闭环。以下较早停点段落均是历史，不覆盖本节。

## 当前阶段与权限边界

- Change：`2026-10-19-aifi-45-four-phase-runner`。用户审阅 Phase2 后回复原文“确认”，主会话已通过 STDD CLI 登记 **Gate2 已通过**（confirmed_by=dialog，evidence=确认），并重渲染 Human View；未手改状态。
- 用户随后回复“按推荐混合模式”；原生模式记录为normal（enabled=false），已通过CLI推进BUILD，不新增hybrid枚举。授权策略见`../../../tools/changes/2026-10-19-aifi-45-runner-contracts/execution-policy.md`。Gate3、提交/push、生产部署和真实CR操作仍未授权。
- Gate1 沿用原记录；未手改 `.canon-index.yaml` 或 STDD 状态。M00 已实际使用明确授权的专属临时数据库迁移/测试并修复一处测试夹具；未连接既有/共享/生产 DB，未执行真实 CR/部署/停服/存量恢复命令。
- **下文未另注明的“本回合/未批准/待Gate2”是 Phase2 只读起草时的历史上下文，不覆盖本节新的CLI确认事实；当前状态以 `.stdd.yaml` 为准。**
- 本次维护普通 Issue+PR，不另注册 CR；后续实现按现行 CUSTOM.md 登记，追溯维护 Issue，不编造 CR/TASK。

## 最新tools候选与实际阻塞（覆盖下文历史诊断）

- 用户最新授权“按建议继续，需要我参与时再停下来”，承接专属临时 Podman PG 迁移/测试/清理及修既有 fixture 后继续消费端的建议；范围内正常 TDD/回归/独立审查不另设审批门。tools T01–T03 两项 P2 已关闭，冻结候选联合8文件212/212、0fail/skip/todo/cancelled，仍不是最终全35文件新候选套件。
- 候选HEAD仍a5ecb578、明确未提交；内容manifest eb99e18aad2292a614a133b35a9265b6505c852a0bf7897c519e4dbf973d6984固定，四份最终digest及实际6/4/11/5节点/23权限见tools TREG-handoff.md。不以HEAD冒充完整候选，不把四个PipelineIDs或导出成功当平台已接通。
- M-PRE/M01/M-EXT 已接收源合同；10code/10agent、31REQ/69SC/69CP 唯一映射保持，两份TODO种子保留。**M00 开工验证节点已完成，不表示四阶段 CP 已完成**；后续使用既有任务编号 M10a/M10b → M11–M15，不沿用上一回复不准确的“M02–M09”简称，不重编号规格/任务。
- **B-DB 已解除，M00 真实无失败基线已取得。** 首轮临时资源已删；本次续作新建带唯一标签的 Podman 容器及 named volume，专属 aifi45_test 库、127.0.0.1:34131、651 迁移，显式白名单环境/DB/CRCTL_PATH，不读取 `.env` 或继承外部认证。首次夹具失败仍保留：精确根因是公钥写在 worktree 而非安装根（不是“未生成”）；签名 helper +8/-7 修复，所有原安全断言保留，code 两子真实 RED→GREEN，独立 Standards/Spec 无硬问题，CUSTOM #26 已登记。
- 主会话整包实际 native exit0、单调20.688404s、193 父+75 子 PASS、0 FAIL、1 原有实时 GitHub SKIP；269 RUN/269 完结，无 DB 提前跳退，3592 tracked server 文件/259 tools 文件前后哈希不漂移。详 M00-db-baseline.md 及 `%TEMP%/aifi45-m00-repair-izez2oby/governance-full-result.json`。本批资源随后在 M10 整包回归后已按标签/确切名称清理，最终端口关闭，私密连接文件删除；不复用旧 DSN。
- M10a/M10b 六文件已实现并冻结：原生成器四合同、完整 body digest/inputs/绑定、同源 Go 产物与 working-tree BASE 来源头；作者真实定向 10 父+46 子 PASS、0 SKIP，生成/check 通过。Main 接权后唯一整包 native exit1、37.439183s：192 父 PASS/3 FAIL/1 原有 GitHub SKIP、108 子 PASS，304 RUN/304 完结、无 DB skip；3594 tracked+非忽略 untracked server 候选文件及 tools259文件前后哈希不漂移。三个失败为 requirement recorded-source 渲染/采纳/恢复契约，未修复；完整证据/原生计数见 M10-build-report.md 与 `%TEMP%/aifi45-m10-main/`，不把定向绿当整包绿。
- **原子代理权限阻塞已解除。** 用户回复“子代理已经恢复，继续”；Main 已实际成功启动 source 根因修复 writer `01a15431-f3c3-75ce-a57c-1b9d5c663298`、独立 Standards reviewer `01a1547d-2ffc-75ce-a57c-1ba7f2461afe` 与独立 Spec reviewer `01a1547d-300a-75ce-a57c-1ba821d13445`。此前两次 disabled/未启动保留为历史；未由 Main 修改权限、绕过工具或自审替代。当前无需新的人类决定；先 trace/fix 三条 source 回归、实际整包及独立复审，M10 未完成、M11 未开始，不弱化断言或回退旧产物求绿。
- 本批 Podman 容器 `aifi45-m00-repair-izez2oby-pg` 与 named volume `aifi45-m00-repair-izez2oby-data` 均在 finally 验证 run-id 标签/唯一 mount 后精确删除，两 remove exit0、两 exists exit1；首次 TCP 检查暂仍可连，后续复核 127.0.0.1:34131 已关闭，最终 cleanup.complete=true。`private-connection.json` / `pg.env` 已删，没有停止 Podman machine/代理/既有服务或 prune。后续需要时按既有授权重新创建独立临时库，不用旧 DSN。
- 续作新建 `aifi45-m10-repair-e4o5e8vm-pg` / `aifi45-m10-repair-e4o5e8vm-data`，双资源唯一 run-id 标签，专属库 aifi45_test/user aifi45，仅 127.0.0.1:33551，原迁移 native exit0/7.631520s、651条最高621。新私密配置在对应 OS Temp 根 `private-connection.json`，不输出 DSN/口令、不复用已删连接或默认 `.env`。source writer 是唯一 DB 目标测试执行者，主会话待交回后唯一整包；Main 负责用毕核验标签并只清本次资源。
- 旧 M10 六文件两路独立审查现均已完整结束：Standards 独立核六 SHA、原3测试正文不弱化、工具 manifest/格式/入口；Spec 解码四 Go raw JSON 与四原 export 逐字/逐值一致并独立重算四 body SHA；均无硬问题，但不把未跑整包/未完成 runtime 当 PASS。reviewer 会话均已交回。
- source writer 已在新33551库真实复现精确三条 RED（native1、2.681725s、3父FAIL/0skip）；source 实际已持久化，唯一 renderer 只识别 `{{inputs.*}}`，writer 删除 `{{inputs.source}}` 才断开恢复传递；不是生成器丢字段或数据库丢 source。Main 按 minor ADJ-T-004 指定同一 writer 修改仅 tools writer prompt 一个叶值与现 contract-scan 新增回归：恢复 inputs.source 仅作与本次 cr.md 权威值核对，不替换原 Skill source 参数，漂移/读取失败停、显式空与缺值保持区别。Go renderer/恢复/事务/权限不改。
- 因 producer 候选需更正，Main 已明确重开该共享写域；一个 writer 独占两 tools 文件及原生成器派生的四 Go 产物，generator 源码/runner_contract_test.go/其它模板保持冻结；先新合同 RED→GREEN、真实四导出/新259 manifest冻结、原链生成/check，再原3条及source邻接 GREEN，Main 接权后整包及独立差异复审。旧 eb99 和 requirement 8d836f… 仅历史候选，新身份待实测重记，不伪装未变或覆盖旧 run digest。
- CUSTOM #26/#139 已登记，M10 未完成/M11 未开始；B-SWEEP 待实测、CI pin 对齐等未来获准提交，T04 去旧接力仍等平台闭环，最终 C1–C7/T05 未做，Gate3/提交/push/部署/真实CR仍未授权。

## 已读取的权威材料

1. 本 change `proposal.md` 和 `canonical/proposals/2026-10-19-aifi-45-four-phase-runner.yaml` 全篇；以 canonical 的6新+4改共10个 capability 为权威。
2. 集中记录根 `docs/AIFI-45-CR流程减负方案.md` 全篇（M1–M8、发布/O2、验收/非目标）。
3. `C:/Users/GOBAO/Downloads/AI/stdd/.stdd/templates/{design.md,test-plan.md,canonical/spec.yaml,canonical/agent_spec.yaml}` 全篇。
4. 同资源根 `.stdd/skills/spec.md`、共享 version-check.md / confirm-gate.md 全篇；资源/技能版本均3.0.7，无升级操作。当时主会话委派的“只起草、不批准、不改状态”边界优先，不执行技能中的确认、状态更新或Phase3步骤。
5. tools同次change的canonical proposal全篇，C7已纳入测试超时诊断修复；本轮另全文读取其design.md，按Decisions §1统一目标nodePermissions/nodeId/executor、四schema和完整pipeline.inputs的digest范围。当前无匹配经验，不为此写产品或经验库状态。
6. 已知 STDD extract-proposal 返回 capabilities 空，是提取/渲染不一致；本次直接使用权威 YAML，不重做提取或修产品。

## 主会话只读诊断实测（用户已确认范围）

以下为主会话委派的只读诊断Agent实测摘要，不是人类提供或批准的6失败结论：

> crctl整文件358.14s自然exit1，294case=288pass+6fail/0skip；短预算与输出延迟不是挂死；5项payload fixture根错位+1项cmdTaskDone已知TxError被总catch改INTERNAL_ERROR。修复仅归tools，本multica回合仍不改代码。

- 来源：主会话只读诊断Agent实测，本multica文档回合引用而未重跑；用户确认的仅是将诊断修复纳入同次范围。没有人类批准6失败结论，不需补批Gate1，不据此修改审批状态；这些事实也不是6项修复完成或整套测试通过证据。
- 结果分类：**诊断收尾、整套失败、修复/修复后回归待实施**。不继续以挂死假说排查、不仅抬超时；5项fixture根定位及1项已知TxError保真仅由tools同次C7承担，multica不做兜底补丁。
- 保持原发现范围 crctl31/output-guard3/registry1及新增回归；未来先补失败回归再最小修复，记录原命令真实退出码、耗时、case、skipped，未完成/意外skip不能记通过。

> 请保留stdd new的TODO种子（canon Gate2会skip，计数只计真实capability），不要改.canon-index或审批状态；用既有_generate_spec渲染每真实capability草稿即可。

- 两份 `canonical/specs/{code,agent}/2026-10-19-aifi-45-four-phase-runner.yaml` 保留原 TODO 种子语义，不算真实需求或验证规格；真实派发能力另用 `four-phase-runner-dispatch.yaml`。
- 没有调用 Gate2 来验证 skip；已有 canon 实现明确跳过 code TODO 种子。真实规格均按 capability 同名独立存放、显式过滤 TODO 渲染，不修改索引。

## 核查基线与最小源码复核

- 已核实基线：multica b0b60a15b，tools a5ecb57；S=`C:/Users/GOBAO/Downloads/AI/multica/server`，T=`C:/Users/GOBAO/Downloads/AI/tools`。本次只少量符号核实，不重做完整探索、不推断线上已启用。
- **基线现状而非目标**：T emit-registry SCHEMAS仅req/arch；body为pipeline+pipelineOwner+nodePermissions，顶层输入key列表未完整表达pipeline.inputs。目标补齐完整pipeline.inputs和执行/绑定声明并受digest保护；coding重复ref按JSON nodeId绑定，DB/Go内部映射node_id，不导出同义副本。S原生成链生成gate_nodes_gen.go/requirement_registry_gen.go，parser不继续固定四/六节点。
- StartArchitecture/checkExecutorSkills/enqueueNode有调用者/executor耦合；需求resolveRequirementAgents/agentByName已有分离可复用；`internal/service/task.go::PipelineTaskSpec` 的SourceTaskID/ExecutorAgentID分开。
- applyReview/buildReviewPayload缺dev-plan/test/upstream，现有upstream转tech-design-review-pending；旧StartArchitecture只accept requirement-approved，不能直接复评重入。
- daemon preparePipelineTask/inspectPipelineWorkspace每task本机绑定；merge后新task、archive安装根；projectGateTransitionErr/completeRun及archived事件须守ownership。
- starter/upsert混分配和协调，复用需求context持久恢复；同pgx.Tx落交接后释放锁再Reconcile，events.Bus.Publish同步回调不能锁内递归。
- ack原路径逐条Leader续接、批回滚，现有SQL已workspace+IDs幂等；WakeGrant须按实际四阶段，不再除req全落arch。
- heartbeat共用处理但HTTP手动响应遗漏需补，WS鉴权daemon_id需存RuntimeLease，两传输共用消费；deliverGrants不再全根广播/任一成功即ack。
- runtime_sweeper原30秒tick无Runner回调；failed-task需先看retry child和待补报，复用TaskService重试；人工Resume会抬预算不挂tick；终态队列补足structured crctl recovery，settle失败不能假终结。
- `governance/crsync_test.go::TestMain` DB不可达会os.Exit(0)，影响整个包；后续必须显式隔离已迁移库和实际case输出，本次绝不试连默认数据库。

## 关键设计决策（待 Gate2 确认）

1. **唯一编排者**：复用Runner/队列/crctl深原语，不建独立引擎、节点表、扫描器、重试表、运行时报告或账本。三类人工审批、签名与证据、workspace隔离和作者评审分离不变。
2. **目标nodeId/输入/digest合同**：JSON nodePermissions `{nodeId,ref,owner,pipelineOwnerCanCall,executor}`，nodeId对应pipeline.nodes[].id，DB/Go内部映射node_id；每非human节点一项，human不派Agent/task。executor是actor key，普通默认pipelineOwner、独立review可在原节点显式声明，由同workspace agentByName解析Agent，owner非执行者。原模板/matrix为唯一事实源，完整pipeline.inputs及绑定/执行声明进入digest body，顶层inputs仅同源兼容key列表且不一致拒绝；固定JSON顺序/读入规范CRLF。保留architecture-core-v1/requirement-core-v1，新增code-core-v1/writeback-core-v1（ai-first.pipeline-registry）。删除checkExecutorSkills及历史executor_agent_id决策依赖，但继续消费registry executor；source真实归因与executor分离，不回退caller/ref/空闲agent。
3. **canonical业务事实**：开发真实testCr/账本、dev-plan/test/upstream投影、代码release-subjects；task completed/exit0/报告存在/模型PASS不代替成功。dirty-start严格逐节点/轮次。
4. **业务回修非技术重试**：upstream先复评再必要设计修订/重审/批准和增量开发；merge release-drift+advanced即使exit0也停交付、回开发重批；人工驳回尊原abort/等待。不沿旧PASS/grant、不重置loop/复活旧终态。
5. **同事务持久交接**：同一pgx.Tx查询/upsert/context/上游完成结果，无内层r.pool逃逸；commit、释放连接和锁后再Reconcile或同步事件；崩溃由活动run周期续接。原注册/source/start-resume确定性重入，不新命令flag，不声称跨库原子。
6. **task与工作根边界**：merge旧task结束后新task本机重绑；archive安装根启动，清理后不要求已删txws但仍验证authority；cleanup-pending业务成功，最终Runner汇合canonical与终态/settle，投影不抢关。
7. **资源单源**：HTTP/WS可选快照按workspace/daemon替换；成功空清除、absent/error保留且不丢actions；WS lease鉴权daemon_id；采集/定位/settle/pending/ack同源。无任务冷启动、晚出现、路径变更和断网收敛，移除env根来源、不双模式。
8. **公钥/纯ack**：唯一可信目标，key→完整grant→ack IDs；旧key不覆、歧义/冲突/缺key/写失败不ack。请求级workspace不改全局client。ack仅workspace+IDs幂等送达，commit后按实际阶段隔离WakeGrant；无Leader续接/终态建run/缺run假推进。
9. **有界恢复**：既有30秒sweeper，限批/超时/公平/逐run隔离；原retry child/分类/预算/退避/journal/terminal队列，结构化recovery保真；不整体白名单混合错误、不抬预算、不越人工、不复活取消。
10. **实施依赖顺序不等于上线顺序**：test基线→tools registry合同→multica消费→执行与恢复→ack去续接；完整联合验收再考虑统一窗口，不半套启用。真实部署/停服/O2仅设计演练，未来另获授权。

## L2 锚定与未决点

- canonical proposal为cross_system=true、safety/financial=false、L2。完整L2接口约定就在design.md的Architecture表：registry/digest/claim/canonical/Tx/heartbeat/pending/ack/tick的输入输出、不变量和失败恢复；不另写anchor源码、不改proposal锚定字段。
- 待Gate2审查：已与tools对齐的L2及其接口语义仍待批准；registry JSON五字段、nodeId/actor key、四schema和完整输入/digest范围已固定，不再留作跨仓字段分歧。heartbeat快照对象最终拼写及batch/timeout内部实测值仍待Gate2前确认，不猜实施值或恢复SLA。
- 待后续实施验证：四阶段全部实际执行、故障与恢复、真实隔离库case、tools6项失败修复和完整回归。上述都是未决验证，不是Gate2已通过或授权实施。
- 发布/O2只桌面/非生产夹具：先暂停四类入口、确认旧执行/旧续接退出，核对配套版本/context/digest；权威worktree status/next与投影/run/task一致后，才模拟无设计执行的一次start或已有执行的受控恢复。不能重批/改库/覆盖digest/全量迁移，不能本回合改Issue状态。

## 有效产出清单与实际计数

有效草稿33份：`design.md`、`test-plan.md`、本文3份 + 10 code YAML + 10 agent YAML + 10 spec.md。另保留两份TODO种子，不计有效产出或下表统计。完整目录中因此有22份spec YAML（20真实+2种子），并非22个capability。

每个能力文件：`canonical/specs/code/<capability>.yaml`、`canonical/specs/agent/<capability>.yaml`、`specs/<capability>/spec.md`。

| capability | Requirements | Scenarios | 独立TC | CP |
|---|---:|---:|---:|---:|
| four-phase-runner-dispatch | 4 | 8 | 8 | 8 |
| node-execution-binding | 3 | 6 | 6 | 6 |
| persistent-stage-handoff | 4 | 9 | 9 | 9 |
| kb-resource-adoption | 3 | 8 | 8 | 8 |
| public-key-grant-delivery | 3 | 6 | 6 | 6 |
| periodic-runner-resume | 2 | 5 | 5 | 5 |
| approval-ack | 3 | 6 | 6 | 6 |
| dev-phase-runner | 3 | 7 | 7 | 7 |
| delivery-runner | 3 | 7 | 7 | 7 |
| task-recovery | 3 | 7 | 7 | 7 |
| 合计 | 31 | 69 | 69 | 69 |

- Scenario confidence：high62 / medium7 / low0，指需求推断把握，不代表测试覆盖；TC优先级P0 67 / P1 2 / P2 0，P1也在整套启用前补齐。
- 所有真实规格/TC/CP均待实现/待验证，无已覆盖/已通过声明。种子原REQ-001/SC-001只是脚手架，不作为M命名空间定义或真实Requirement统计。

## 本次仅文档静态审查

- 已只读解析canonical、核对10个权威capability、31/69/69/69映射、M前缀全局唯一定义、Requirement/Scenario置信度、evidence选择器确实指向真实proposal/场景、每个THEN有大写SHALL、AND≤5。
- 每个Scenario独立TC并有agent CP；test-plan已按用户补充改为69个独立详细案例表，每表真实ID、关联Spec及GIVEN/WHEN/THEN/AND。TC兼容STDD的TC-[A-Z]+-三位数字正则，能力缩写均M开头，test-plan每个TC仅出现一次；人工发布/基线用例是独立验证流程，不虚构已有自动化测试函数。
- 已通过**现有**`stdd.cli.commands.canon._generate_spec`、显式change输出目录、过滤TODO，为10真实code YAML渲染spec.md；未调用gate/批准、未写新生成器。MD逐场景GIVEN/WHEN/THEN与canonical核对一致。
- **实际运行只读STDD validate（源码CLI main，参数validate本change、-v；Python -B不落pycache）返回exit0**：69个TC-ID/69唯一、69个Spec Scenario/69个TC Cases，0错误、9项AND整文件累计告警。没有调用gate/agent验证步骤或业务测试。
- validate.py的AND检查错误地按每整个spec.md累计>5告警，而非逐Scenario。整文件累计：ACK6、DELIVERY7、DEV7、DISPATCH12、KB8、BINDING6、HANDOFF13、KEY6、RECOVERY7触发9项；TICK5不触发。canonical每场景≤5已独立核对，保留完整MD，不为消警删断言、不改STDD。
- 渲染/validate前后核对proposal、canonical proposal、.canon-index.yaml、.stdd.yaml及两份TODO种子hash不变；真实规格数10组，种子不算第11个capability。
- 本轮跨仓修订实际变更9份文档：design/test-plan/本文3份、dispatch/binding的code及agent YAML各2份、重渲染实际改变的MD视图2份。用既有函数渲染10真实capability，其余8份视图字节未变；31 Requirements/69 Scenarios/69 TC/69 CP不变。
- 已对照tools design目标示例/正文并扫描全部本change真实草稿：JSON五字段/nodeId与内部node_id、actor/human、四schema、完整pipeline.inputs/执行绑定入digest、顶层兼容列表单源及诊断来源归因，**本次检查0冲突**；只读validate重新执行exit0，0错误、同9项整文件AND累计告警。proposal/状态/索引/TODO种子和tools design hash不变，未调用gate、agent步骤或DB。
- 静态文档结构检查不是业务测试；不据此批准Gate2，不将主会话只读诊断Agent测得的tools 288个通过移植为multica覆盖，也不将用户范围确认误当诊断结论批准。

## 下一步（尚未授权）

Gate2及推荐混合策略均已获用户明确确认，当前BUILD。先完成tools测试基线/根因修复，再进入四阶段合同；multica只先做切片规划与快照/预算的只读事实核实，不在依赖未通过前实施。剩余细化须守住已确认L2语义，实质偏离/安全/环境阻塞/连续三轮未收敛必须停；不启用长程全量预授权。Gate3、人类业务审批、提交/push、生产和存量操作仍不由本文隐式授权。
