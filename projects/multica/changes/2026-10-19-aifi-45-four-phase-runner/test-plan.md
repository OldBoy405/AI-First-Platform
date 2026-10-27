# AIFI-45 Phase 2 测试方案与详细案例（草稿）

> 版本：Phase2 draft-2；日期：2026-10-19。全部**待实现 / 待验证**；Gate2未批准。
> 规格：`canonical/specs/code/*.yaml`的10份真实capability为行为权威，agent同名YAML为验证计划，`specs/<capability>/spec.md`为已有函数渲染的视图。两份stdd new TODO种子保留、不计数。
> 实际文档规模：31 Requirements / 69 Scenarios / 69独立TC / 69 CP；P0 67、P1 2、P2 0。

## 一、测试策略

### 1.1 测试金字塔

目标投入约单元/合同60%、隔离集成30%、非生产链路/桌面演练10%，仅为规划。单元侧重parser、绑定、canonical分类、资源快照、公钥与recovery安全；集成侧重同pgx.Tx、锁/并发去重、HTTP/WS、workspace、任务工作根、终态队列；非生产演练覆盖四阶段闭环、合法回修、发布/O2。单元不能代替事务集成，人工恢复不能代替自动恢复。

### 1.2 原则与安全边界

1. **TDD切片：test基线→tools registry合同→multica消费→执行与恢复→ack去续接。** 全部闭环、完整联合验收后才考虑申请统一窗口，不半套上线、不保留正常Leader兜底。
2. 本文件只列未来计划，本回合不运行业务测试、不连接数据库、不执行真实CR/部署/停服/存量恢复。后续所有测试仅用隔离DB、临时Git/KB/密钥、假HTTP/WS和可控时钟；真实操作另获明确授权。
3. S=`C:/Users/GOBAO/Downloads/AI/multica/server`，T=`C:/Users/GOBAO/Downloads/AI/tools`。以下TestM名称全是**拟新增**，未来基式为在S执行`go test -count=1 -v <包> -run '^<表内用例名>$'`；agent YAML列具体包。实际修改包还需整体回归，不以精确-run子集替代。
4. governance的`crsync_test.go::TestMain`在DB不可达时os.Exit(0)，**整包含纯函数测试都可能未运行**。未来必须显式确认隔离、已迁移测试库及实际case/subcase PASS/数量/skipped，不能回退默认localhost或共享DB。退出0且无实际case即未验证。本次不试连任何DB。
5. **主会话只读诊断实测/用户已确认范围**：用户只确认纳入诊断修复范围；下列数据来自主会话委派的只读诊断Agent，不是人类提供/批准的6失败结论，不需补批Gate1。**crctl整文件358.14s自然exit1，294case＝288pass＋6fail／0skip；短预算与输出延迟不是挂死。** 5项payload fixture根错位＋1项cmdTaskDone已知TxError被总catch改INTERNAL_ERROR，仅tools同次C7修，本回合不改代码。未来先锁定失败回归再修fixture根与错误保真，不在multica绕过，不重新按挂死假说探索，不把诊断完成说成整套通过。
6. tools保留crctl31/output-guard3/registry1及新增回归的完整发现范围，记录原始退出码、耗时、case/skipped；未完成/意外skip阻塞，不排文件/削断言/只延超时，不用tail管道退出码冒充原命令。lint既有OUTDATED/Windows基线失败单列，不静默豁免；CI账单/生产启停不包含在测试授权。
7. 任务completed、exit0、模型PASS或报告存在均不替代账本、真实testCr、release-subjects、审批/签名证据。技术attempt、业务loop、人工等待分别断言，不增加运行时报告、门禁、引擎或补偿系统；证据摘要留既有PR/Issue。
8. 每case独立详细表，ID字段各出现一次；TC采用TC类型前缀和M能力命名空间，以兼容validate正则。Requirement/Scenario/CP保持全局M前缀。关联Spec指同节spec.md的真实Scenario，GIVEN/WHEN/THEN/AND逐项落实canonical，不能靠空ID凑数。
9. 跨仓目标合同按tools design Decisions §1：JSON nodeId映射DB/Go内部node_id，nodePermissions字段为{nodeId,ref,owner,pipelineOwnerCanCall,executor}，executor是actor key；每非human节点恰一项、human不派Agent/task。完整pipeline.inputs和绑定/执行声明进入digest，顶层inputs仅同源兼容列表，不允许双事实源；不能把基线现状输入缺口当目标。

### 1.3 已有资产（只确认入口，不声称新行为已覆盖）

| 文件/入口（相对S，T另标） | 用例数 | 拟复用类型/范围 | 状态 |
|---|---|---|---|
| internal/governance/runner_integration_test.go、runner_contract_test.go | 未统计 | 启动、合同、锁、持久交接 | 待改/待验证，受TestMain前置控制 |
| internal/governance/runner_requirement_test.go、runner_requirement_p2_test.go、runner_attempt_bound_test.go | 未统计 | source、恢复、轮次 | 待改/待验证 |
| internal/governance/gate_review_test.go、gate_projection_test.go、transitions_test.go | 未统计 | 评审、路由、ownership | 待补dev-plan/test/upstream/交付 |
| internal/governance/approval_continuation_test.go、daemon_workspace_test.go、approval_crosscheck_test.go | 未统计 | ack、旧续接、隔离、证据 | 待改为纯确认 |
| internal/handler/daemon_ws_test.go；internal/daemonws/hub_test.go | 未统计 | 身份、heartbeat、lease | 待补两传输同构矩阵 |
| internal/daemon的heartbeat、pipeline_task、crevents、wakeup、terminal_report_queue相关*_test.go | 未统计 | 根、carrier、投递、终态 | 待改/待验证 |
| internal/service/retry_deferred_test.go；pkg/taskfailure相关*_test.go | 未统计 | 预算、退避、分类 | 待补child与recovery |
| cmd/server/runtime_sweeper_test.go、runtime_sweeper_filter_test.go、runtime_sweeper_race_test.go | 未统计 | tick、过滤、竞态 | 待接Runner回调 |
| T原crctl/output-guard/registry测试及Skill/Agent/lint合同 | 文件31/3/1；主会话只读诊断Agent测得crctl 294case | tools C7及跨仓合同 | Agent实测crctl 6fail，用户仅确认范围；修复后完整回归待做，本multica文档回合未重跑 |

## 二、详细测试案例

每个THEN/AND是强制SHALL；所有用例和检查点均待实现/待验证。以下未来验证入口不是本次执行记录。

### 2.1 four-phase-runner-dispatch

对应`specs/four-phase-runner-dispatch/spec.md`；Requirement映射：M-REQ-DISPATCH-001→场景001–002，002→003–004，003→005–006，004→007–008。

#### 2.1.1 四阶段实际执行

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-001 |
| 关联Spec | M-SC-DISPATCH-001 |
| 优先级 | P0 |
| GIVEN | 四阶段各有隔离CR、模板和已授权执行者。 |
| WHEN | 原入口或合法交接触发Reconcile并完成可执行节点。 |
| THEN | SHALL逐阶段产生匹配pipeline/nodeId/digest的claim、真实task、canonical结果和恢复归属；JSON nodeId映射DB/Go内部node_id，不另导出同义字段。 |
| AND | SHALL仅有投影run不算执行，不建独立Runner或节点表。 |
| 验证入口 | TestMDispatch001；governance隔离集成及非生产四阶段链路。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.2 执行终态不冒充业务成功

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-002 |
| 关联Spec | M-SC-DISPATCH-002 |
| 优先级 | P0 |
| GIVEN | task completed、exit0、模型PASS逐项出现，但节点所需账本/评审/审批事实缺失。 |
| WHEN | 消费节点结果。 |
| THEN | SHALL不推进，按原输入/证据错误合同保留可诊断结果。 |
| AND | SHALL不在Runner复制crctl业务判据、不补造证据。 |
| 验证入口 | TestMDispatch002；governance单元/隔离集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.3 声明驱动walker

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-003 |
| 关联Spec | M-SC-DISPATCH-003 |
| 优先级 | P0 |
| GIVEN | 四模板节点数/gate/reviewLoop/replayNodes不同，交付无评审loop。 |
| WHEN | parser解释声明，Runner遇等待或业务BLOCK。 |
| THEN | SHALL按声明入队、等待、重入和重放，不固定四/六节点。 |
| AND | SHALL保留三类人工审批，交付无声明loop不造loop，不恢复默认dev-start卡。 |
| 验证入口 | TestMDispatch003；governance合同。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.4 dirty-start节点边界

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-004 |
| 关联Spec | M-SC-DISPATCH-004 |
| 优先级 | P0 |
| GIVEN | 同一dirty目录供允许/不允许dirty-start节点及不同轮次使用。 |
| WHEN | 校验当前节点输入。 |
| THEN | SHALL仅该节点/轮次原合同允许时接受dirty，要求clean的节点仍阻断。 |
| AND | SHALL不全阶段复制需求例外，不加遗留dirty白名单。 |
| 验证入口 | TestMDispatch004；daemon临时Git/workspace。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.5 原生成链与digest合同

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-005 |
| 关联Spec | M-SC-DISPATCH-005 |
| 优先级 | P0 |
| GIVEN | tools目标导出及平台原生成链，分别改变完整pipeline.inputs类型/required、绑定/授权/节点执行声明，另有顶层inputs不一致负例。 |
| WHEN | 比较四schema、body/digest/生成产物及parser，区分现状与目标。 |
| THEN | SHALL原链同一合同，保留architecture-core-v1/requirement-core-v1，新增code-core-v1/writeback-core-v1（均ai-first.pipeline-registry）；未知/不全失败关闭。 |
| AND | SHALL完整pipeline.inputs、节点执行声明及nodePermissions绑定/授权/executor进入digest，逐项变化改变digest；固定JSON字段顺序、读入先规范CRLF并仍校验输入能力；SHALL顶层inputs仅同源派生兼容key列表，不一致拒绝，不写新生成器/第二事实源、不覆盖存量digest。 |
| 验证入口 | TestMDispatch005；governance及T既有导出/生成一致性测试。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.6 claim/carrier归属往返

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-006 |
| 关联Spec | M-SC-DISPATCH-006 |
| 优先级 | P0 |
| GIVEN | 四阶段source/workspace/pipeline/node-run/attempt/digest/绑定已持久化。 |
| WHEN | claim、daemon carrier与canonical回报往返，注入错workspace/digest/node。 |
| THEN | SHALL保留完整归属，拒绝错配回报。 |
| AND | SHALL历史executor_agent_id不重新决定执行者。 |
| 验证入口 | TestMDispatch006；handler及daemon carrier配套合同。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.7 治理基线拒绝退出0空跑

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-007 |
| 关联Spec | M-SC-DISPATCH-007 |
| 优先级 | P0 |
| GIVEN | TestMain可DB不可达退出0；另备显式隔离已迁移测试库。 |
| WHEN | 未来对照不可达负例及隔离库实际case输出，本次不执行。 |
| THEN | SHALL无实际case整包判未验证，不拿退出0空跑作通过/Gate证据。 |
| AND | SHALL只用显式隔离库，核对目标case/subcase确实执行，不回退默认共享DB；SHALL本Phase2零DB连接/业务测试。 |
| 验证入口 | 独立基线核对流程；正向确认TestMDispatch001/005真实PASS，负例不可达即未验证。 |
| 当前状态 | 待实现/待验证 |

#### 2.1.8 tools已诊断失败的修复基线

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDISPATCH-008 |
| 关联Spec | M-SC-DISPATCH-008 |
| 优先级 | P0 |
| GIVEN | 主会话只读诊断Agent实测358.14s自然exit1、294=288pass+6fail/0skip；非挂死，5项fixture根错位+1项TxError被总catch改INTERNAL_ERROR；用户仅确认诊断修复范围，非人类提供/批准6失败结论。 |
| WHEN | 未来仅tools C7先失败回归再修，按固定五切片联合验收。 |
| THEN | SHALL记为已诊断但整套未通过，6项修复仅tools承担，保留完整发现及退出码/耗时/case/skipped。 |
| AND | SHALL对两类根因分别先红再修，不在multica掩盖；SHALL不排文件/削断言/只延超时、不重启挂死假说、不半套启用；SHALL本回合仅文档不改业务代码。 |
| 验证入口 | T现有完整测试入口及C7修复回归/PR证据审查，保留31+3+1及新增范围。 |
| 当前状态 | 待实现/待验证 |

### 2.2 node-execution-binding

对应`specs/node-execution-binding/spec.md`；Requirement映射：M-REQ-BINDING-001→001–002，002→003–004，003→005–006。

#### 2.2.1 重复ref仍按JSON nodeId绑定

| 字段 | 内容 |
|---|---|
| **ID** | TC-MBINDING-001 |
| 关联Spec | M-SC-BINDING-001 |
| 优先级 | P0 |
| GIVEN | coding两个不同JSON nodeId复用同ref，上下文不同，DB/Go内部映射为node_id。 |
| WHEN | 分别导出绑定、入队并重入。 |
| THEN | SHALL按pipeline+JSON nodeId消费绑定/轮次，不按ref合并/串结果，不另导出node_id同义字段。 |
| AND | SHALL每非human节点一条nodePermissions {nodeId,ref,owner,pipelineOwnerCanCall,executor}，由原模板/matrix派生进digest；executor为actor key，普通默认pipelineOwner，独立review可在原节点声明，同workspace agentByName解析真实Agent。 |
| 验证入口 | TestMBinding001；governance合同。 |
| 当前状态 | 待实现/待验证 |

#### 2.2.2 共享Skill与独立reviewer

| 字段 | 内容 |
|---|---|
| **ID** | TC-MBINDING-002 |
| 关联Spec | M-SC-BINDING-002 |
| 优先级 | P0 |
| GIVEN | checkpoint/freshness共享Skill，作者/reviewer已授权，另含human gate。 |
| WHEN | 派发共享/评审节点并到达human gate。 |
| THEN | SHALL共享交授权阶段Agent、评审独立且作者不自评；human保留gate但Agent/task派发数为0。 |
| AND | SHALLowner仅Skill维护归属、不等于executor actor key，不建system执行Agent；核验active Skill/唯一owns、executor真实kind=agent、owns/can-call及forbidden。 |
| 验证入口 | TestMBinding002；governance单元。 |
| 当前状态 | 待实现/待验证 |

#### 2.2.3 不依赖调用者全技能/历史executor_agent_id

| 字段 | 内容 |
|---|---|
| **ID** | TC-MBINDING-003 |
| 关联Spec | M-SC-BINDING-003 |
| 优先级 | P0 |
| GIVEN | 调用者缺其他节点Skill，历史executor_agent_id与registry executor actor绑定不同。 |
| WHEN | StartArchitecture/enqueueNode派发合法节点。 |
| THEN | SHALL不要求调用者全Skill、不按历史executor_agent_id派发，删除checkExecutorSkills但保留registry executor绑定消费。 |
| AND | SHALL不批改历史executor_agent_id或自动改派旧queued/running任务。 |
| 验证入口 | TestMBinding003及只读源码路径检查；governance。 |
| 当前状态 | 待实现/待验证 |

#### 2.2.4 非法绑定失败关闭

| 字段 | 内容 |
|---|---|
| **ID** | TC-MBINDING-004 |
| 关联Spec | M-SC-BINDING-004 |
| 优先级 | P0 |
| GIVEN | 跨workspace/归档/无runtime/无能力/未授权五类绑定，另有可用caller。 |
| WHEN | agentByName和原任务约束校验。 |
| THEN | SHALL五类逐一失败关闭，不回退caller/Skill owner/可用agent。 |
| AND | SHALL保留认证、来源与独立评审边界。 |
| 验证入口 | TestMBinding004；governance表驱动含合法对照。 |
| 当前状态 | 待实现/待验证 |

#### 2.2.5 completed来源仍保留真实归因

| 字段 | 内容 |
|---|---|
| **ID** | TC-MBINDING-005 |
| 关联Spec | M-SC-BINDING-005 |
| 优先级 | P0 |
| GIVEN | 已完成source含真实agent/workspace/issue/project/originator/accountable/started_by。 |
| WHEN | 下游PipelineTaskSpec入队。 |
| THEN | SHALL保留SourceTaskID和全部原归因，ExecutorAgentID独立取绑定，source完成不阻合法交接。 |
| AND | SHALL不把owner伪作caller/协调者/审批人。 |
| 验证入口 | TestMBinding005；governance隔离集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.2.6 executor合法不能掩盖source非法

| 字段 | 内容 |
|---|---|
| **ID** | TC-MBINDING-006 |
| 关联Spec | M-SC-BINDING-006 |
| 优先级 | P0 |
| GIVEN | source缺真实身份、跨workspace或错CR/project，executor合法。 |
| WHEN | 创建/恢复run并校验context。 |
| THEN | SHALL拒绝伪造/跨界归因，不能因executor合法而放行。 |
| AND | SHALL保留原错误供受控恢复，不造CR/TASK编号。 |
| 验证入口 | TestMBinding006；governance来源负例。 |
| 当前状态 | 待实现/待验证 |

### 2.3 persistent-stage-handoff

对应`specs/persistent-stage-handoff/spec.md`；Requirement映射：M-REQ-HANDOFF-001→001–003，002→004–006，003→007–008，004→009。

#### 2.3.1 三批准同事务分配下游

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-001 |
| 关联Spec | M-SC-HANDOFF-001 |
| 优先级 | P0 |
| GIVEN | 需求/设计/代码批准合法、source完整。 |
| WHEN | 分别消费三批准；追踪Tx身份及独立连接可见性。 |
| THEN | SHALL自动分配设计/开发/交付，同pgx.Tx保存下游context/run及上游完成/交接结果。 |
| AND | SHALL所有相关查询/upsert/update同Tx、不落r.pool；SHALL无作者补命令或Skill尾启动。 |
| 验证入口 | TestMHandoff001；governance隔离DB集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.2 commit前逐点失败

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-002 |
| 关联Spec | M-SC-HANDOFF-002 |
| 优先级 | P0 |
| GIVEN | 下游upsert/context/上游完成各写入点可注入失败。 |
| WHEN | commit前逐点回滚并再次协调。 |
| THEN | SHALL无半交接、无提前派发，上游可续接且已批准事实不撤销。 |
| AND | SHALL恢复后仅一个有效下游执行。 |
| 验证入口 | TestMHandoff002；governance事务故障注入。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.3 commit解锁后协调与同步事件

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-003 |
| 关联Spec | M-SC-HANDOFF-003 |
| 优先级 | P0 |
| GIVEN | 事件/启动/tick并发消费批准，Bus同步回调会Reconcile。 |
| WHEN | 并发交接并触发下游，屏障记录时序。 |
| THEN | SHALL先commit并释放连接/上游锁，再Reconcile或发布可递归同步事件。 |
| AND | SHALL原run/node/task去重，无嵌套锁/重复派发；SHALLTx内无task派发/完整公开starter。 |
| 验证入口 | TestMHandoff003；governance竞态及锁序断言。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.4 commit后崩溃持久恢复

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-004 |
| 关联Spec | M-SC-HANDOFF-004 |
| 优先级 | P0 |
| GIVEN | 交接commit后、Reconcile前中断并销毁内存Runner。 |
| WHEN | 重建Runner，以扫描或tick恢复。 |
| THEN | SHALL四阶段从持久digest/workspace/source/started_by恢复唯一派发，无手动start/resume。 |
| AND | SHALL复用需求context保存/恢复模式，不新建交接账本。 |
| 验证入口 | TestMHandoff004；governance重启夹具。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.5 合法回修新cycle

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-005 |
| 关联Spec | M-SC-HANDOFF-005 |
| 优先级 | P0 |
| GIVEN | 上游复评或drift由合法转换触发，原阶段可能completed。 |
| WHEN | 同一内部创建/接管逻辑处理该入口。 |
| THEN | SHALL用合法回修cycle/context，不原样调仅req-approved的旧StartArchitecture。 |
| AND | SHALL不复活历史终态、不任意重置loop、不沿旧PASS/grant。 |
| 验证入口 | TestMHandoff005；governance合法入口集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.6 无活动run不擅自重开

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-006 |
| 关联Spec | M-SC-HANDOFF-006 |
| 优先级 | P0 |
| GIVEN | 无合法回修，已有失败/取消/完成下游或digest/context矛盾。 |
| WHEN | 普通交接发现无活动run。 |
| THEN | SHALL不自动重开，保留错误走既有受控恢复。 |
| AND | SHALL不覆盖digest、不扩普通start任意重启权限。 |
| 验证入口 | TestMHandoff006；governance表驱动负例。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.7 注册后首次接入窗口

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-007 |
| 关联Spec | M-SC-HANDOFF-007 |
| 优先级 | P0 |
| GIVEN | 注册已提交、首次接入未完成，原注册/source事实可读。 |
| WHEN | 原接入路径重入。 |
| THEN | SHALL确定性复用start/resume内部分派并幂等，无新命令flag或人工启动待办。 |
| AND | SHALL不声称Git/DB跨库原子，不重做AIFI-71。 |
| 验证入口 | TestMHandoff007；governance非原子窗口集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.8 人工驳回非技术重试

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-008 |
| 关联Spec | M-SC-HANDOFF-008 |
| 优先级 | P0 |
| GIVEN | APPROVAL_DECLINED_ROLLED_BACK，原状态机已完成业务回退。 |
| WHEN | Runner消费审批结果。 |
| THEN | SHALL停正向交接、遵原abort/等待输入，不技术重试/沿旧grant。 |
| AND | SHALL不增加一律自动重写政策或新审批。 |
| 验证入口 | TestMHandoff008；governance业务结果断言。 |
| 当前状态 | 待实现/待验证 |

#### 2.3.9 发布与O2仅非生产演练

| 字段 | 内容 |
|---|---|
| **ID** | TC-MHANDOFF-009 |
| 关联Spec | M-SC-HANDOFF-009 |
| 优先级 | P0 |
| GIVEN | 隔离快照含旧task/续接、权威req-approved、旧主checkout及有/无设计执行两类。 |
| WHEN | 桌面演练短窗口/O2，不执行真实部署/停服/恢复命令。 |
| THEN | SHALL先暂停派发/领取/投递/ack、确认旧执行退出，再核对版本/context/digest，最后恢复统一调度。 |
| AND | SHALL重读权威status/next及投影/run/task，无设计才模拟原start一次补接，有执行用扩展受控入口；SHALL不重批/改库/覆digest/全量迁移/混旧daemon；SHALL全部主线验收才考虑维护Issue in_review，真实操作另授权。 |
| 验证入口 | design发布/O2和agent检查；独立非生产桌面流程，无真实处置。 |
| 当前状态 | 待实现/待验证 |

### 2.4 kb-resource-adoption

对应`specs/kb-resource-adoption/spec.md`；Requirement映射：M-REQ-KB-001→001–002，002→003–005，003→006–008。

#### 2.4.1 HTTP/WS共享快照身份

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-001 |
| 关联Spec | M-SC-KB-001 |
| 优先级 | P0 |
| GIVEN | 授权runtime有workspace/daemon_id/目录资源，WS正常导致HTTP跳过。 |
| WHEN | 同输入分别走HTTP手动响应与WS heartbeat/actions消费。 |
| THEN | SHALL两传输返回并消费同一可选快照，WS lease保留鉴权查询runtime daemon_id。 |
| AND | SHALL不依赖PAT daemon ID/客户端自报，不扩大机器认证/撤销承诺。 |
| 验证入口 | TestMKb001；handler及daemon/daemonws配套断言。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.2 资源查询权限与N+1

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-002 |
| 关联Spec | M-SC-KB-002 |
| 优先级 | P0 |
| GIVEN | 多workspace/daemon/项目资源，错身份请求。 |
| WHEN | heartbeat读取资源并统计查询。 |
| THEN | SHALL按授权workspace/daemon/runtime及项目限定，拒跨界资源。 |
| AND | SHALL无项目N+1/新全量endpoint，发现根不扩大普通任务权限。 |
| 验证入口 | TestMKb002；handler身份矩阵/隔离查询。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.3 新/空快照与退出清除

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-003 |
| 关联Spec | M-SC-KB-003 |
| 优先级 | P0 |
| GIVEN | 本workspace/daemon旧路径，其他身份有独立投影。 |
| WHEN | 依次新路径、成功空快照、生命周期退出。 |
| THEN | SHALL先替换再清本身份，不追加旧路径、不影响其他身份。 |
| AND | SHALL退出按原生命周期移除对应投影。 |
| 验证入口 | TestMKb003；daemon投影单元。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.4 absent/error不伪空、不丢actions

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-004 |
| 关联Spec | M-SC-KB-004 |
| 优先级 | P0 |
| GIVEN | 有有效投影，字段缺失/查询失败，本次已领取actions。 |
| WHEN | 双传输处理失败，再收到成功heartbeat。 |
| THEN | SHALL失败/缺字段保留投影并交付actions，后续成功收敛。 |
| AND | SHALL不伪装空、不丢actions、不回env根源。 |
| 验证入口 | TestMKb004；handler/daemon故障合同。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.5 冷启动与资源晚出现

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-005 |
| 关联Spec | M-SC-KB-005 |
| 优先级 | P0 |
| GIVEN | 无任务/无env冷启动、目录/账本晚出现或断网恢复。 |
| WHEN | 启动采集/投递循环，以可控原节拍收到快照。 |
| THEN | SHALL不需认领/重启即可识别合法KB并恢复采集/投递。 |
| AND | SHALL首次失败仅等后续heartbeat、保留kb init、不递归未知嵌套KB。 |
| 验证入口 | TestMKb005；daemon临时根链路。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.6 五消费者同源且请求级隔离

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-006 |
| 关联Spec | M-SC-KB-006 |
| 优先级 | P0 |
| GIVEN | 两workspace不同根并发采集/定位/settle/pending/ack。 |
| WHEN | 读取投影并向假服务发请求。 |
| THEN | SHALL同源根带workspace，X-Workspace-ID按请求分组，ack IDs不串批。 |
| AND | SHALL不改共享client全局workspace，不由任务历史/持久根缓存补源。 |
| 验证入口 | TestMKb006；daemon并发假服务。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.7 旧env与未知根不回流

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-007 |
| 关联Spec | M-SC-KB-007 |
| 优先级 | P0 |
| GIVEN | env残留根、空快照、非法/非KB和未知嵌套KB。 |
| WHEN | 采集器/定位器处理候选根。 |
| THEN | SHALL移除env根来源，原路径/KB验证生效，不补残留、不递归猜根。 |
| AND | SHALL不增加根账本/配置同步/双模式。 |
| 验证入口 | TestMKb007；daemon负例矩阵。 |
| 当前状态 | 待实现/待验证 |

#### 2.4.8 两处CR not found线索

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKB-008 |
| 关联Spec | M-SC-KB-008 |
| 优先级 | P1 |
| GIVEN | 采集和Pipeline定位两入口分别CR not found。 |
| WHEN | 输出原错误/诊断。 |
| THEN | SHALL两处均含workspace/CR、资源、daemon/runtime与投影线索，不以改报错代替接线。 |
| AND | SHALL不新增运行时报告/健康检查/机器认证。 |
| 验证入口 | TestMKb008；daemon错误合同。 |
| 当前状态 | 待实现/待验证 |

### 2.5 public-key-grant-delivery

对应`specs/public-key-grant-delivery/spec.md`；Requirement映射：M-REQ-KEY-001→001–002，002→003–004，003→005–006。

#### 2.5.1 key与grant顺序投递

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKEY-001 |
| 关联Spec | M-SC-KEY-001 |
| 优先级 | P0 |
| GIVEN | 新KB无当前key，可信pending有匹配grant/public_key，目标唯一。 |
| WHEN | 投递并记录落盘/ack时序。 |
| THEN | SHALL复用PublicKeyPEM输出key_id/pem，严格key就绪→完整grant→ID加入ack。 |
| AND | SHALL无需手拷当前key，不改验签/加验钥命令。 |
| 验证入口 | TestMKey001；daemon及handler响应配套合同。 |
| 当前状态 | 待实现/待验证 |

#### 2.5.2 首次安装连接信任

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKEY-002 |
| 关联Spec | M-SC-KEY-002 |
| 优先级 | P0 |
| GIVEN | 有效TLS、允许本地回环、不可信远程明文三类连接。 |
| WHEN | 首次安装key并验证grant。 |
| THEN | SHALL仅原可信边界接受，不把不可信响应的key/grant当彼此自证。 |
| AND | SHALL来源/workspace/签名/证据验证不变。 |
| 验证入口 | TestMKey002；daemon测试TLS/明文负例。 |
| 当前状态 | 待实现/待验证 |

#### 2.5.3 唯一目标不广播

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKEY-003 |
| 关联Spec | M-SC-KEY-003 |
| 优先级 | P0 |
| GIVEN | 本workspace唯一/零/多匹配，另一workspace有同号CR。 |
| WHEN | deliverGrants定位KB。 |
| THEN | SHALL只写本workspace唯一可信根；零/歧义pending，不广播、不以任意根写成功即ack。 |
| AND | SHALL不选其他workspace同号CR，非目标根无写入。 |
| 验证入口 | TestMKey003；daemon临时多根矩阵。 |
| 当前状态 | 待实现/待验证 |

#### 2.5.4 写入故障不ack、不半文件

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKEY-004 |
| 关联Spec | M-SC-KEY-004 |
| 优先级 | P0 |
| GIVEN | key冲突/缺key/key或grant写失败/两次写间中断。 |
| WHEN | 逐点故障后按原pending重投。 |
| THEN | SHALL失败不ack、无半文件、保pending且幂等可重投。 |
| AND | SHALL不覆盖已有key，key与完整grant齐才ack。 |
| 验证入口 | TestMKey004；daemon落盘故障注入。 |
| 当前状态 | 待实现/待验证 |

#### 2.5.5 旧grant与旧可信key

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKEY-005 |
| 关联Spec | M-SC-KEY-005 |
| 优先级 | P0 |
| GIVEN | 旧grant分别有/无可信旧key，pending仅带当前key。 |
| WHEN | 消费旧grant。 |
| THEN | SHALL有旧key沿原验签，无旧key保持pending受控恢复，不以当前key冒充。 |
| AND | SHALL旧key保留，不承诺完整轮换/多daemon副本协议。 |
| 验证入口 | TestMKey005；daemonkey/grant组合矩阵。 |
| 当前状态 | 待实现/待验证 |

#### 2.5.6 运行文件不新增dirty

| 字段 | 内容 |
|---|---|
| **ID** | TC-MKEY-006 |
| 关联Spec | M-SC-KEY-006 |
| 优先级 | P1 |
| GIVEN | 临时Git KB默认*忽略、!keys/**例外和已跟踪锚。 |
| WHEN | 未来仅临时仓安装并演练忽略例外最小收敛。 |
| THEN | SHALLkey/grant不制造新dirty，不删已跟踪锚/覆key/要求逐KB新配置。 |
| AND | SHALL本次仅设计，不改真实KB或配置。 |
| 验证入口 | TestMKey006；daemon临时Git status/锚字节断言。 |
| 当前状态 | 待实现/待验证 |

### 2.6 periodic-runner-resume

对应`specs/periodic-runner-resume/spec.md`；Requirement映射：M-REQ-TICK-001→001–003，002→004–005。

#### 2.6.1 无新事件也由tick续接

| 字段 | 内容 |
|---|---|
| **ID** | TC-MTICK-001 |
| 关联Spec | M-SC-TICK-001 |
| 优先级 | P0 |
| GIVEN | 四阶段活动run丢事件或commit后未派发，无新事件/手动命令。 |
| WHEN | 可控时钟触发原30秒sweeper。 |
| THEN | SHALL按pipeline调用同Reconcile恢复，无手动start/resume/重启。 |
| AND | SHALL不增扫描器/重试表/第二编排。 |
| 验证入口 | TestMTick001；cmd/server隔离回调集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.6.2 batch/timeout/公平与liveness

| 字段 | 内容 |
|---|---|
| **ID** | TC-MTICK-002 |
| 关联Spec | M-SC-TICK-002 |
| 优先级 | P0 |
| GIVEN | run数超一批，某run阻塞/失败，liveness同时待处理。 |
| WHEN | 连续tick并到达回调超时。 |
| THEN | SHALL限批/超时、逐run隔离、后续公平且不阻塞存活检测。 |
| AND | SHALL内部值先隔离实测，不虚构吞吐或精确SLA。 |
| 验证入口 | TestMTick002；cmd/server可控时钟/屏障。 |
| 当前状态 | 待实现/待验证 |

#### 2.6.3 事件/启动/tick竞争

| 字段 | 内容 |
|---|---|
| **ID** | TC-MTICK-003 |
| 关联Spec | M-SC-TICK-003 |
| 优先级 | P0 |
| GIVEN | 同节点同时事件、启动扫描和多tick。 |
| WHEN | 屏障并发协调。 |
| THEN | SHALL复用锁及活跃去重，最多一有效执行，不重放已完评审/审批。 |
| AND | SHALL调度重复不加预算或业务轮次。 |
| 验证入口 | TestMTick003；cmd/server竞态。 |
| 当前状态 | 待实现/待验证 |

#### 2.6.4 暂态协调错误保活动性

| 字段 | 内容 |
|---|---|
| **ID** | TC-MTICK-004 |
| 关联Spec | M-SC-TICK-004 |
| 优先级 | P0 |
| GIVEN | 活动run短暂DB/网络故障后恢复。 |
| WHEN | 当前错误返回及后续tick。 |
| THEN | SHALL不立即failRun，恢复后按持久节点唯一继续。 |
| AND | SHALL保机器错误，不把所有platform类笼统重试。 |
| 验证入口 | TestMTick004；cmd/server故障注入。 |
| 当前状态 | 待实现/待验证 |

#### 2.6.5 tick不越终态/人工/预算

| 字段 | 内容 |
|---|---|
| **ID** | TC-MTICK-005 |
| 关联Spec | M-SC-TICK-005 |
| 优先级 | P0 |
| GIVEN | 取消/失败/完成run、人工或版本等待、预算耗尽。 |
| WHEN | 周期扫描。 |
| THEN | SHALL不复活、不越gate、不猜版本、不调加预算ResumePipelineNodeTask。 |
| AND | SHALL等待不耗技术重试，耗尽明确停并留现场。 |
| 验证入口 | TestMTick005；cmd/server边界矩阵。 |
| 当前状态 | 待实现/待验证 |

### 2.7 approval-ack

对应`specs/approval-ack/spec.md`；Requirement映射：M-REQ-ACK-001→001–002，002→003–004，003→005–006。

#### 2.7.1 delivered_at仅送达

| 字段 | 内容 |
|---|---|
| **ID** | TC-MACK-001 |
| 关联Spec | M-SC-ACK-001 |
| 优先级 | P0 |
| GIVEN | 同批grant已投递，其中一条缺Leader或活动run。 |
| WHEN | HandleGrantsAck提交workspace+IDs。 |
| THEN | SHALL仅批量幂等delivered_at，resolveContinuationTarget/EnqueueApprovalContinuation调用0，无Leader整批回滚。 |
| AND | SHALL送达不等crctl消费/审批收尾/下一阶段开始。 |
| 验证入口 | TestMAck001；governance DB/旧调用探针。 |
| 当前状态 | 待实现/待验证 |

#### 2.7.2 认证、workspace和批量幂等

| 字段 | 内容 |
|---|---|
| **ID** | TC-MACK-002 |
| 关联Spec | M-SC-ACK-002 |
| 优先级 | P0 |
| GIVEN | 有效/重复/跨workspace IDs、未认证请求。 |
| WHEN | ack。 |
| THEN | SHALL认证/workspace限制保留，跨界不更新、重复幂等，无逐条事务系统。 |
| AND | SHALL不重跑业务前置或新增审批已消费状态。 |
| 验证入口 | TestMAck002；governance/daemon_workspace资产。 |
| 当前状态 | 待实现/待验证 |

#### 2.7.3 提交后四阶段隔离唤醒

| 字段 | 内容 |
|---|---|
| **ID** | TC-MACK-003 |
| 关联Spec | M-SC-ACK-003 |
| 优先级 | P0 |
| GIVEN | 同批四阶段活动run，一个WakeGrant失败。 |
| WHEN | ack commit后唤醒各CR。 |
| THEN | SHALL按实际阶段路由，单失败不撤任何ack、不阻其他唤醒。 |
| AND | SHALL失败由持久run tick补，无新续接队列/去重表。 |
| 验证入口 | TestMAck003；governance时序/计数集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.7.4 真DB提交失败可重投

| 字段 | 内容 |
|---|---|
| **ID** | TC-MACK-004 |
| 关联Spec | M-SC-ACK-004 |
| 优先级 | P0 |
| GIVEN | key/grant已写，ack DB提交失败。 |
| WHEN | 返回失败后原pending再投/再ack。 |
| THEN | SHALL不假称提交、不commit前唤醒，原pending幂等重投后确认。 |
| AND | SHALL不绕认证/workspace以消除DB错误。 |
| 验证入口 | TestMAck004；governance提交故障。 |
| 当前状态 | 待实现/待验证 |

#### 2.7.5 终态/缺run/旧grant无假推进

| 字段 | 内容 |
|---|---|
| **ID** | TC-MACK-005 |
| 关联Spec | M-SC-ACK-005 |
| 优先级 | P0 |
| GIVEN | 终态CR、缺活动run、过期subject/cycle。 |
| WHEN | 有效送达ack并尝试唤醒。 |
| THEN | SHALL不建执行/回Leader/把旧ack当指令，无run不谎称推进。 |
| AND | SHALL只消费匹配当前阶段权威证据的grant。 |
| 验证入口 | TestMAck005；governance新run/task为0断言。 |
| 当前状态 | 待实现/待验证 |

#### 2.7.6 旧续接仅受控收尾演练

| 字段 | 内容 |
|---|---|
| **ID** | TC-MACK-006 |
| 关联Spec | M-SC-ACK-006 |
| 优先级 | P0 |
| GIVEN | 非生产快照含旧queued/running续接及历史显式dev-start事实。 |
| WHEN | 桌面演练切换顺序。 |
| THEN | SHALL先收尾旧续接再调度；历史事实兼容只读，不恢复默认卡/正常Leader。 |
| AND | SHALL不抢改真实task，本次仅设计，真实处置另授权。 |
| 验证入口 | design及agent非生产桌面检查，无真实旧任务处置。 |
| 当前状态 | 待实现/待验证 |

### 2.8 dev-phase-runner

对应`specs/dev-phase-runner/spec.md`；Requirement映射：M-REQ-DEV-001→001–003，002→004–006，003→007。

#### 2.8.1 开发全部节点与真实testCr

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-001 |
| 关联Spec | M-SC-DEV-001 |
| 优先级 | P0 |
| GIVEN | 合法设计批准、coding模板节点/loop。 |
| WHEN | 计划/TASK/计划评审/finalize/freshness/实现/testCr/代码评审/审批收尾。 |
| THEN | SHALL实际执行并读账本/真实testCr结果；仅报告存在/task completed不代成功。 |
| AND | SHALL无新业务节点/dev-start卡，不要求评论转述续接。 |
| 验证入口 | TestMDev001；governance及T临时testCr链路，含只存报告负例。 |
| 当前状态 | 待实现/待验证 |

#### 2.8.2 dev-plan/test/upstream载体投影

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-002 |
| 关联Spec | M-SC-DEV-002 |
| 优先级 | P0 |
| GIVEN | 三类结果含匹配与错CR/node/轮次/过期夹具。 |
| WHEN | buildReviewPayload→applyReview。 |
| THEN | SHALL匹配结果及upstream正确投影，错配过期拒绝，不吞测试失败/BLOCK。 |
| AND | SHALLcanonical/证据来源保留，投影不替执行。 |
| 验证入口 | TestMDev002；governance及daemon载体。 |
| 当前状态 | 待实现/待验证 |

#### 2.8.3 代码评审release-subjects

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-003 |
| 关联Spec | M-SC-DEV-003 |
| 优先级 | P0 |
| GIVEN | release-subjects匹配/漂移，但设计subject_sha256可仍相同。 |
| WHEN | 代码评审与审批证据消费。 |
| THEN | SHALL按release-subjects验证，漂移不沿旧PASS、不套设计单hash。 |
| AND | SHALL独立reviewer及人工代码审批不变。 |
| 验证入口 | TestMDev003；governance证据矩阵。 |
| 当前状态 | 待实现/待验证 |

#### 2.8.4 三类普通BLOCK各自loop

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-004 |
| 关联Spec | M-SC-DEV-004 |
| 优先级 | P0 |
| GIVEN | 计划/测试/代码分别普通BLOCK及轮次边界。 |
| WHEN | 解释原loop/replayNodes。 |
| THEN | SHALL各自回修并重放必要证据、保留业务次数，不当技术重试。 |
| AND | SHALL不重置loop/评论接力，不把failed任务当已完节点。 |
| 验证入口 | TestMDev004；governance表驱动。 |
| 当前状态 | 待实现/待验证 |

#### 2.8.5 upstream先复评再编写

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-005 |
| 关联Spec | M-SC-DEV-005 |
| 优先级 | P0 |
| GIVEN | review-dev-plan返回upstream-design-blocker及repair-target。 |
| WHEN | task-breakdown接回设计。 |
| THEN | SHALL先tech-design-review-pending技术复评，确认BLOCK才合法编写，不直跳tech-designing。 |
| AND | SHALL不沿旧PASS直批/新CR或审批/误用旧req-approved starter。 |
| 验证入口 | TestMDev005；governance原transitions/gate_review。 |
| 当前状态 | 待实现/待验证 |

#### 2.8.6 设计回修批准后增量恢复开发

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-006 |
| 关联Spec | M-SC-DEV-006 |
| 优先级 | P0 |
| GIVEN | 同CR必要修订/重审/人工设计批准，开发依原路由等待。 |
| WHEN | 持久交接恢复开发。 |
| THEN | SHALL按增量修PLAN/TASK并继续，不沿旧证据/重置无关loop/复活旧终态。 |
| AND | SHALL无新等待状态，合法新cycle受授权/digest约束。 |
| 验证入口 | TestMDev006；governance回修集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.8.7 版本确认与晚改证据

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDEV-007 |
| 关联Spec | M-SC-DEV-007 |
| 优先级 | P0 |
| GIVEN | unassigned可注册，评审前缺真实版本或晚改改变摘要。 |
| WHEN | 等负责人确认并消费version-set后authority。 |
| THEN | SHALL不猜版本/交付重复填，确认后自动继续，晚改不沿旧评审/grant。 |
| AND | SHALL等待不耗技术重试，无新审批/表单。 |
| 验证入口 | TestMDev007；governance及T版本输出合同。 |
| 当前状态 | 待实现/待验证 |

### 2.9 delivery-runner

对应`specs/delivery-runner/spec.md`；Requirement映射：M-REQ-DELIVERY-001→001–002，002→003–004，003→005–007。

#### 2.9.1 代码批准授权既有交付链

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-001 |
| 关联Spec | M-SC-DELIVERY-001 |
| 优先级 | P0 |
| GIVEN | 当前代码批准匹配、authority元数据可读。 |
| WHEN | 接管feature-writeback。 |
| THEN | SHALL自动既有merge/PRD-SDD-TASK回写/traceability/归档，不另要启动发布指令。 |
| AND | SHALL无新执行器，不含生产部署/安装包/商店。 |
| 验证入口 | TestMDelivery001；governance隔离链路及无部署副作用断言。 |
| 当前状态 | 待实现/待验证 |

#### 2.9.2 authority输入缺值阻断

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-002 |
| 关联Spec | M-SC-DELIVERY-002 |
| 优先级 | P0 |
| GIVEN | 新模式完整/缺spec/缺真实版本，legacy milestone不适用。 |
| WHEN | 模板/Skill/daemon组装深原语参数。 |
| THEN | SHALL仅authority继承spec_id/target_version，缺值阻断，不猜标题/占位/强填milestone。 |
| AND | SHALL不重复要求人填或新增查询命令。 |
| 验证入口 | TestMDelivery002；daemon及T输入合同。 |
| 当前状态 | 待实现/待验证 |

#### 2.9.3 release-drift退出0仍业务回退

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-003 |
| 关联Spec | M-SC-DELIVERY-003 |
| 优先级 | P0 |
| GIVEN | merge exit0但phase=release-drift且advanced表明已回退；另有部分发布后漂移。 |
| WHEN | 消费机器结果。 |
| THEN | SHALL前者停交付，code-approved→developing持久回修/测试/评审/重批；后者保原阻断。 |
| AND | SHALL不沿旧grant/技术重试merge/把exit0误判合并成功。 |
| 验证入口 | TestMDelivery003；governance业务回退矩阵。 |
| 当前状态 | 待实现/待验证 |

#### 2.9.4 merge后新task重绑根

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-004 |
| 关联Spec | M-SC-DELIVERY-004 |
| 优先级 | P0 |
| GIVEN | 正常merge完成，下一节点operational根与旧task不同。 |
| WHEN | preparePipelineTask/inspectPipelineWorkspace准备下一节点。 |
| THEN | SHALL旧task结束后新task，由daemon本机重绑正确operational workspace。 |
| AND | SHALL不改运行中env跨根，不由server猜绝对路径。 |
| 验证入口 | TestMDelivery004；daemon task/根探针。 |
| 当前状态 | 待实现/待验证 |

#### 2.9.5 archive安装根及清后恢复

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-005 |
| 关联Spec | M-SC-DELIVERY-005 |
| 优先级 | P0 |
| GIVEN | archive清理txws，随后需重入/settle。 |
| WHEN | 从临时安装根启动并清后恢复。 |
| THEN | SHALLcwd不被清，crctl仍解析authority，安装根承载audit/outbox/settle。 |
| AND | SHALL不再要求已删txws，也不绕authority。 |
| 验证入口 | TestMDelivery005；daemon临时归档夹具。 |
| 当前状态 | 待实现/待验证 |

#### 2.9.6 cleanup-pending与settle故障分离

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-006 |
| 关联Spec | M-SC-DELIVERY-006 |
| 优先级 | P0 |
| GIVEN | cleanup-pending业务结果，terminal settle暂时失败。 |
| WHEN | 分别消费业务/技术结果并汇合。 |
| THEN | SHALL业务成功、不新清理/重归档，settle失败保技术恢复、不假收尾。 |
| AND | SHALL最终执行完成仍待canonical及task/settle所需结果齐。 |
| 验证入口 | TestMDelivery006；daemon故障恢复。 |
| 当前状态 | 待实现/待验证 |

#### 2.9.7 投影不抢关Runner所有run

| 字段 | 内容 |
|---|---|
| **ID** | TC-MDELIVERY-007 |
| 关联Spec | M-SC-DELIVERY-007 |
| 优先级 | P0 |
| GIVEN | Runner交付待最终结果，archived/跨阶段投影先到，另有投影自有run。 |
| WHEN | projectGateTransitionErr/completeRun及投影消费乱序事件。 |
| THEN | SHALL只更归属CR展示、不抢关Runner；Runner汇合后仅完成自身。 |
| AND | SHALL投影自有run合法更新保留，不跨阶段改ownership。 |
| 验证入口 | TestMDelivery007；governance事件/ownership矩阵。 |
| 当前状态 | 待实现/待验证 |

### 2.10 task-recovery

对应`specs/task-recovery/spec.md`；Requirement映射：M-REQ-RECOVERY-001→001–002，002→003–004，003→005–007。

#### 2.10.1 failed parent先看已有child

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-001 |
| 关联Spec | M-SC-RECOVERY-001 |
| 优先级 | P0 |
| GIVEN | skill/requirement failed parent有queued/running/completed child。 |
| WHEN | 两入口协调节点。 |
| THEN | SHALL先跟随child，不先failRun/重复建child，完成仍验canonical。 |
| AND | SHALL复用原node-run/责任人/权限/审批授权。 |
| 验证入口 | TestMRecovery001；governance隔离集成。 |
| 当前状态 | 待实现/待验证 |

#### 2.10.2 待补报与安全技术中断先分类

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-002 |
| 关联Spec | M-SC-RECOVERY-002 |
| 优先级 | P0 |
| GIVEN | failed task待补报或已证安全幂等无新输入恢复，预算足。 |
| WHEN | Runner/TaskService判断恢复。 |
| THEN | SHALL先分类，复用FailTaskWithTransition/MaybeRetryFailedTask/退避，不先终止run。 |
| AND | SHALL非每tick新attempt，不重复已完评审/审批。 |
| 验证入口 | TestMRecovery002；service retry_deferred及Runner配套次序断言。 |
| 当前状态 | 待实现/待验证 |

#### 2.10.3 终态队列保真并消费crctl recovery

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-003 |
| 关联Spec | M-SC-RECOVERY-003 |
| 优先级 | P0 |
| GIVEN | settle失败，原队列保存failure_reason/code/structured recovery/journal。 |
| WHEN | daemon重启重新打开队列。 |
| THEN | SHALL原权限内安全argv完整消费，不只HTTP重报，不把未settle伪报业务终结。 |
| AND | SHALL重放幂等，无新补偿文件/执行器/重试表。 |
| 验证入口 | TestMRecovery003；daemon队列持久/重放探针。 |
| 当前状态 | 待实现/待验证 |

#### 2.10.4 不按文字或篡改argv恢复

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-004 |
| 关联Spec | M-SC-RECOVERY-004 |
| 优先级 | P0 |
| GIVEN | 合法结构化恢复、仅文字建议、来源/argv篡改。 |
| WHEN | daemon判安全性。 |
| THEN | SHALL仅原权限内无新输入安全幂等恢复，拒文字猜测/身份参数篡改。 |
| AND | SHALL机器错误/recovery留原run/终态记录，不新增运行时报告。 |
| 验证入口 | TestMRecovery004；daemon安全矩阵。 |
| 当前状态 | 待实现/待验证 |

#### 2.10.5 技术budget与业务loop分离

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-005 |
| 关联Spec | M-SC-RECOVERY-005 |
| 优先级 | P0 |
| GIVEN | 独立技术attempt/业务loop，预算可重试或耗尽。 |
| WHEN | 恢复及周期协调。 |
| THEN | SHALL只按原预算/退避增必要技术attempt，不重置loop/自动抬预算，耗尽停并留现场。 |
| AND | SHALL不把人工加预算ResumePipelineNodeTask挂tick。 |
| 验证入口 | TestMRecovery005；service及Runner预算边界。 |
| 当前状态 | 待实现/待验证 |

#### 2.10.6 混合错误不整体白名单

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-006 |
| 关联Spec | M-SC-RECOVERY-006 |
| 优先级 | P0 |
| GIVEN | TX_GIT_FAILED/process_failure混合；认证/余额/权限/签名证据冲突；明确安全暂态子类。 |
| WHEN | 分类failure。 |
| THEN | SHALL混合类不整体重试，只有明确安全暂态走原恢复，其余不盲试。 |
| AND | SHALL模型不按文字猜授权/绕证据。 |
| 验证入口 | TestMRecovery006；pkg/taskfailure表驱动。 |
| 当前状态 | 待实现/待验证 |

#### 2.10.7 业务结果/等待/终态各守边界

| 字段 | 内容 |
|---|---|
| **ID** | TC-MRECOVERY-007 |
| 关联Spec | M-SC-RECOVERY-007 |
| 优先级 | P0 |
| GIVEN | BLOCK/驳回/drift、版本/人工等待、取消/既有失败终态。 |
| WHEN | failed-task判定及tick。 |
| THEN | SHALL业务走原路由，等待不耗重试，终态不复活、人工gate不越过。 |
| AND | SHALL不解释为无限Agent重跑或耗尽后仍全自动保证。 |
| 验证入口 | TestMRecovery007；governance边界矩阵。 |
| 当前状态 | 待实现/待验证 |

## 三、测试执行矩阵

以下全是计划覆盖，不是执行结果。每TC按能力计一次，不因跨层验证重复计数；P1两例也须联合启用前完成。

| 功能 | 单元/合同计划 | 隔离集成计划 | 非生产链路/桌面计划 | TC数 | 状态 |
|---|---|---|---|---:|---|
| four-phase-runner-dispatch | parser/输入/生成/digest | claim/canonical/实际case基线 | 四阶段+tools修复质量基线 | 8 | 待实现/待验证 |
| node-execution-binding | JSON nodeId/内部node_id/actor授权/独立评审 | source/task归属 | 四阶段内验证 | 6 | 待实现/待验证 |
| persistent-stage-handoff | 入口/终态/驳回 | Tx故障/commit窗口/锁去重 | 发布/O2仅演练 | 9 | 待实现/待验证 |
| kb-resource-adoption | 快照/路径/错误 | HTTP/WS/身份/请求workspace | 冷启动/晚出现/断网 | 8 | 待实现/待验证 |
| public-key-grant-delivery | key/目标/原子文件 | 信任/中断/重投 | 临时KB无手拷key | 6 | 待实现/待验证 |
| periodic-runner-resume | 有界/分类/终态 | 时钟/竞争/隔离 | 无事件自动续接 | 5 | 待实现/待验证 |
| approval-ack | 幂等/纯确认/路由 | DB/单run失败隔离 | 旧续接仅快照演练 | 6 | 待实现/待验证 |
| dev-phase-runner | loop/subjects/版本 | carrier/合法回修 | 真实testCr临时链路 | 7 | 待实现/待验证 |
| delivery-runner | 输入/结果/ownership | task切根/archive/settle | drift/完整交付 | 7 | 待实现/待验证 |
| task-recovery | 分类/安全/预算 | child/队列重启 | 中断自动恢复 | 7 | 待实现/待验证 |
| 合计 | — | — | — | 69 | 没有业务测试通过声明 |

未来联合回归包含实际修改的S governance/service/handler/daemonws/daemon/protocol/cmd-server-sweeper/pkg-taskfailure，SQL/registry原生成一致性，以及T既有lint-prompts/check-agents-contract/check-skill-matrix、完整crctl/output-guard/registry及所改深原语。PR/Issue摘要逐项分实际通过、失败、未完成、意外skip和既有基线；不得因文档映射完整就说业务已通过，不加运行时报告文件。

## 四、回归风险矩阵

| 区域 | 拟改动 | 已有保护入口（未运行） | 风险 | 新验证范围（仅场景简称） |
|---|---|---|---|---|
| registry/绑定/digest | 两阶段扩四阶段、JSON nodeId绑定及完整pipeline.inputs/执行声明摘要 | runner_contract/requirement、T registry | 高 | DISPATCH及BINDING |
| Tx/锁/事件 | starter拆分、同Tx context、解锁后协调 | runner_integration/requirement | 高 | HANDOFF、TICK |
| 开发证据/回修 | dev-plan/test/upstream/release-subjects | gate_review/projection/transitions | 高 | DEV、HANDOFF |
| 交付工作根/ownership | 新task、安装根归档、Runner最终汇合 | daemon pipeline_task/crevents、gate_projection | 高 | DELIVERY |
| KB/key/workspace | 快照同源、唯一目标、原子写、请求隔离 | handler daemon_ws、daemon heartbeat/wakeup、hub | 高 | KB、KEY |
| ack/旧续接并行 | 纯确认/四阶段唤醒 | approval_continuation/daemon_workspace/crosscheck | 高 | ACK、发布/O2 |
| 恢复预算/终态 | tick、child、structured recovery | sweeper、retry、terminal_queue、taskfailure | 高 | TICK、RECOVERY |
| 诊断/忽略边界 | 定位线索、keys例外 | daemon错误入口、临时Git | 中 | KB末例、KEY末例 |
| 验收伪绿 | TestMain空跑、tools失败被缩范围 | 退出0不能兜底 | 高 | DISPATCH基线两例、全表实际case核对 |

## 五、建议补充顺序（不授权执行）

1. **test基线**：DISPATCH基线两例；governance显式隔离库/实际case，tools已知5fixture+1TxError仅tools先红再修，修复后完整真实基线。诊断非挂死不等测试通过。
2. **tools registry合同**：四阶段导出/绑定/digest/inputs边界与canonical，原生成链；配合同次tools C1/C2/C3/C7。
3. **multica消费**：去固定walker、调用者全技能和executor派发；claim/carrier/来源权限。此时不得启用半套。
4. **执行与恢复**：正常四阶段、全部HANDOFF/DEV/DELIVERY/KB/KEY/TICK/RECOVERY及dirty/缺证据负例；先正常，再BLOCK/upstream/drift/decline/事务崩溃/技术中断/投递失败；两条P1在本切片末完成，不留到上线后。
5. **ack去续接**：全部ACK，完整受影响包和tools全范围、非生产统一窗口/O2桌面演练；全主线验收后未来才可申请真实部署，不自行执行，也不以AIFI-45单点解阻替代维护完成。

## 六、文档校验边界与Gate2未决

- 真实case采用逐例详细表，每例ID只出现一次，关联69个真实Scenario；不是为check造空ID。摘要/风险/顺序使用能力或场景简称，避免validate把同文本引用误判为重复TC定义。
- `validate.py`将每个spec.md全文的AND累计与5比较，**不等于每Scenario上限**。保留正常canonical每Scenario≤5及完整MD，不为消告警删断言，不修改STDD；该工具局限产生的真实告警应如实列出。
- **本回合实际只读validate结果：exit0，69个TC-ID且69唯一，69个Spec Scenario、69个TC Cases，0错误、9个AND累计告警。** 9项对应ACK(6)、DELIVERY(7)、DEV(7)、DISPATCH(12)、KB(8)、BINDING(6)、HANDOFF(13)、KEY(6)、RECOVERY(7)的整文件AND总数；TICK整文件5项无该告警。canonical每Scenario均≤5，未删任何断言、未改STDD。
- validate仅文档结构校验，不执行agent步骤或业务测试、不批准Gate2。已对齐的L2接口仍待Gate2批准，registry JSON字段/四schema/digest不再有跨仓分歧；快照对象、batch/timeout实测值仍待确认；tools6项修复后完整回归与multica隔离库case仍待实施。
- TODO种子、proposal、.canon-index、.stdd.yaml和审批状态不因校验而更新。
