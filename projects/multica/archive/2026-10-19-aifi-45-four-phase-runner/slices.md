# AIFI-45 multica Implementation Plan — 切片执行计划

> **For agentic workers:** 保留已选普通混合策略；按`tasks.md`逐任务执行，不能把本规划回合变成代码/测试执行。本回合仅新增两份计划，未完成任何实施切片。

**Goal:** 将既有五步架构顺序拆成可单独评审、可独立验证的S/M交付缝，完整覆盖本change真实69组SC/TC/CP。
**Architecture:** tools单源导出→multica原生成/parser/节点绑定→同一Runner持久交接/业务执行/技术恢复→最后ack去续接。所有准备性切片都要有局部合同测试，完整Scenario只能在主归属与所有支持节点（含后续跨端收齐节点）全部验证后结束。
**Tech Stack:** Go/pgx/PostgreSQL、既有Node生成链、HTTP/WS、临时Git/KB、现有原生Go测试。
**Spec:** `design.md`、`test-plan.md`、10份真实`canonical/specs/code/*.yaml`及10份同名agent YAML；两份TODO种子排除。授权见[共享策略](../../../tools/changes/2026-10-19-aifi-45-runner-contracts/execution-policy.md)。

## Global Constraints / Review Focus

沿用`tasks.md`的Global Constraints和五项Review Focus，每项已落到对应测试节点。当前CLI为BUILD、thorough、normal/disabled；旧Phase2文档文字不在本回合改写。skill默认的其他计划路径、频繁commit、直接进入Part B均被本次“只写两份文件”边界覆盖。下列命令全部是**未来执行配方，不是已运行记录**，所有CP仍待验证。

## Dependency Graph Summary

### 外部依赖与显式阻塞

| 节点 | 条件 / 状态 | 对multica的约束 |
|---|---|---|
| T-S0 | tools在途worker负责完整基线、5项payload fixture根及1项TxError分类修复；当前未接到完成回执 | 先完整回归再改合同；multica不重复调查、修复或改其文档 |
| T-REG | T-S0后的tools T01–T03四阶段实际导出、模板输入/业务结果/权限/绑定/digest一致性；主会话核对候选源码与生成/parser接口；不包含依赖平台闭环的T04去接力 | M10a及业务实现前置；与T-FINAL区分，避免跨仓循环；固定提交revision仍待另行提交授权 |
| T-FINAL | tools最终候选revision的原完整发现范围（31+3+1文件及新增回归）和合同/质量回归证据 | M52联合验收前置；不得用T-S0旧基线代替合同改造后的全绿 |
| B-DB | 已明确归属、可销毁、已迁移的隔离DB及临时Git/KB/密钥；连接目标经主会话确认 | 未满足不运行任何依赖DB的命令；不能默认.env或猜DSN，改变目标需暂停 |
| B-TRANSPORT | **命名/空值语义已由主会话细化**，见implementation-notes.md I1/I2；local_directory_snapshot，复用资源表示和授权runtime/lease身份 | 设计命名前置解除；M35a实际类型复用/HTTP-WS接线/测试仍pending，不表示实现或测试通过；无新schema/endpoint/第二根源 |
| B-SWEEP | **内部batch/timeout与公平边界仍未定案/隔离测定** | **M42/M43保持blocked**；30秒是既有tick周期，不是臆定的callback timeout，不加用户flag或宣称SLA |

B-TRANSPORT命名细化已在implementation-notes记录，B-SWEEP预算仍待隔离实测；T-S0/T-REG没有被默示验收。当前仅规划与只读事实核实；不得跳过依赖或半套启用。任何改变已批准合同、安全或隔离语义的决定仍按normal策略请求确认。

```text
架构一 test基线       架构二 tools合同          架构三 multica消费
T-S0 ─┬─> M00 <─ B-DB ─┐
      ├─> M01 ──────────┼─> C-READY ─> M10a -> M10b -> M11 -> M12 -> M13 -> M14 -> M15
      └─> T-REG ────────┘

架构四 执行与恢复（以下各链按表中完整依赖，不代表整链可并行）
M15 -> M20 -> M21a -> M21b -> M22 -> M23 -> M24 -> M25 -> M26 -> M27 -> M28
                                                                            |
                        +---------------------------------------------------+
                        |                                                   |
                        v                                                   v
                     M30a -> M30b -> M31 -> M32 -> M33 -> M34              M40 -> M41a
                                                ^                            |      |
                                                +----------------------------+      |
                                                                                    v
                                                      [M33 + M34 + M41a] -> M41b

M15 + B-TRANSPORT -> M35a -> M35b -> M36 -> M37a -> M37b -> M38a -> M38b -> M39
                                           ^
                                           |
                                          M32

[M22 + M41b + M39 + B-SWEEP] -> M42 -> M43

架构五 ack去续接 / 整套闭环
[M43 + M34 + M39] -> M50 -> M51 -> [全部前序 + T-FINAL] -> M52 -> M53
```

C-READY是M00/M01/T-REG证据汇合的图示别名，不是新增runtime状态、CLI门或产品节点。支持切片不逆向依赖最终链路测试，避免“先完整E2E才能写parser”的循环。

**并行化说明（仅两个真正独立的机会组）**：
- **G1：M20 + M35a**，共同依赖M15，且B-TRANSPORT已解除。前者写governance结果解释，后者只写protocol/daemonws lease；接口、源码/测试文件写集合不相交，分别用独立fixture/DB。不是把全部执行/KB链同时启动。
- **G2：M21b + M35b**，分别在M21a/M35a通过后可并行。前者写governance Tx分配，后者写handler heartbeat/身份；两者不调用对方正在改的内部入口。组末重新编译/回归两包并核对既有消息合同。
- 其他默认串行，尤其共享`runner.go`、`daemon.go`、`pipeline_task.go`、`crevents.go`及其测试的节点不并行。G1/G2是机会而非强制调度；若实际改动越界、夹具不能隔离或接口未冻结，退回串行。当前不派新worker，不重复tools在途调查。

## A2–A3：五步分析与排序依据

### A2a 依赖核对

本回合实际只读运行`stdd dependency-graph <本change> --format json`：10 nodes、0 edges、10 zero_dependency、0 cycles。该工具仅从MD GIVEN中的capability名字面抽边，不能推出“10能力实际独立”。上图和执行表按批准design的五步顺序、事务/载体接缝及真实文件写集合补足语义依赖；静态审计另外检查此42节点DAG，无悬空内部依赖/循环。关键汇合点是M15、M22、M32→M37a、M41b、M42、M50、M52；实际最长路径取决于两个设计阻塞和tools回执，不虚构耗时。

### A2b 风险

实际只读`stdd experience list --format json`返回`[]`，不伪造EXP命中或+2经验加分。A2底分1，Scenario>5加1、跨模块加1、MODIFIED接口改变再加1；另将design已明列的授权/事务/签名/持久恢复关键风险作保守工程升级，满分5，升级不是经验库命中。

| Capability | SC | A2结构底分 | 工程评估 | 切片策略 |
|---|---:|---:|---|---|
| four-phase-runner-dispatch | 8 | 3 | 4 高：digest/输入/执行归属 | 生成、parser、carrier、结果、基线/终验拆开 |
| node-execution-binding | 6 | 3 | 4 高：actor授权/作者评审分离 | M12绑定、M13来源，不和parser打包 |
| persistent-stage-handoff | 9 | 3 | 5 高：Tx/锁/崩溃/终态 | context、原子写、postcommit、入口、驳回、桌演拆开 |
| kb-resource-adoption | 8 | 3 | 4 高：双传输/身份/workspace | type/lease、server、consumer、五消费者接线分开 |
| public-key-grant-delivery | 6 | 3 | 5 高：信任锚/唯一目标/ack顺序 | server响应、可信目标、落盘故障分开 |
| periodic-runner-resume | 5 | 2 | 4 高：liveness/预算/公平 | M42 callback、M43竞争/边界；先定B-SWEEP |
| approval-ack | 6 | 4 | 4 高：接口改义/移除旧编排 | M50送达、M51唤醒、M52演练，最后做 |
| dev-phase-runner | 7 | 4 | 4 高：真实证据/业务回修 | server投影、daemon载体、普通loop、upstream拆开 |
| delivery-runner | 7 | 4 | 5 高：切根/归档/ownership | authority/task、drift、archive、settle、ownership拆开 |
| task-recovery | 7 | 4 | 5 高：recovery安全/终态/预算 | 分类、service、队列、Runner跟随child拆开 |

### A2c–A2e 粒度及A3顺序

42个计划节点：**39个代码/测试切片（M）+3个只读验证节点（S）**，无L开发单体；验证节点不冒充新增测试。M按2–3个实际修改文件、至多5个主TC估算，即使只覆盖1–2个TC，只要跨文件接线也按M保守估计。机械生成的2份产物单列M10b；一次需改>3文件/6+主TC时在开工前再拆，不把多包回归当一大坨开发。S验证节点按证据核对工作估计，不承诺全量测试墙钟时间。现有接口文件可作为只读依赖，不因提到路径就都要改。

表中顺序是分组展示，不是直接逐行执行：M40/M41a应在M28之后、M33之前完成；M37a须等M32。按依赖列拓扑调度，P0先行；含两条P1的M37a/M39仍随闭环必做，不可拖到上线后。

## Slice Execution Plan

TC列标“主”表示附录A唯一主归属；“支持”仍须验证，但不重复计算独立TC。P0/P1指本slice承载的原TC，不给69个TC重新定级。路径均相对S=`C:/Users/GOBAO/Downloads/AI/multica/server`。

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|---|---|---|---|---|---|---|
| M00 | P0 | 3 中 | S 验证 | — | 主 TC-MDISPATCH-007 | `runner_contract_test.go`已有真实case/TestMain证据，不改源码 | T-S0, B-DB |
| M01 | P0 | 3 中 | S 验证 | — | 主 TC-MDISPATCH-008 | 只核对tools完整基线/根因修复回执 | T-S0 |
| M10a | P0 | 4 高 | M | — | 支持 TC-MDISPATCH-005 | `gen/generate-gate-nodes.mjs`+`runner_contract_test.go`生成输入合同 | M00, M01, T-REG |
| M10b | P0 | 4 高 | M | — | 主 TC-MDISPATCH-005 | `gate_nodes_gen.go`、`requirement_registry_gen.go`+合同测试；原链同源产物 | M10a |
| M11 | P0 | 4 高 | M | — | 主 TC-MDISPATCH-003 | `runner.go::parseCoreRegistryFrom`、`runner_requirement_registry.go`+合同测试 | M10b |
| M12 | P0 | 4 高 | M | — | 主 TC-MBINDING-001, TC-MBINDING-002, TC-MBINDING-003 | `runner.go`、`runner_requirement.go`+`runner_integration_test.go`；nodeId/actor派发 | M11 |
| M13 | P0 | 4 高 | M | — | 主 TC-MBINDING-004, TC-MBINDING-005, TC-MBINDING-006 | `runner.go/runner_requirement_entry.go`+`runner_integration_test.go`来源校验；复用service既有`PipelineTaskSpec` | M12 |
| M14 | P0 | 4 高 | M | — | 主 TC-MDISPATCH-006 | `internal/handler/daemon.go`+`daemon_test.go`claim归属 | M13 |
| M15 | P0 | 4 高 | M | — | 主 TC-MDISPATCH-004；支持 TC-MDISPATCH-006 | `internal/daemon/pipeline_task.go`+`pipeline_task_test.go`carrier/dirty节点边界 | M14 |
| M20 | P0 | 4 高 | M | G1 | 主 TC-MDISPATCH-002 | `runner.go/runner_requirement.go`+`runner_integration_test.go`canonical结果消费 | M15 |
| M21a | P0 | 4 高 | M | — | 支持 TC-MHANDOFF-004 | `runner_requirement_resume.go`、`runner.go`+`runner_requirement_test.go`context往返 | M20 |
| M21b | P0 | 5 高 | M | G2 | 主 TC-MHANDOFF-001, TC-MHANDOFF-002 | `runner.go/runner_requirement_entry.go`+`runner_integration_test.go`同Tx分配 | M21a |
| M22 | P0 | 5 高 | M | — | 主 TC-MHANDOFF-003, TC-MHANDOFF-004 | `runner.go/runner_requirement_entry.go`+`runner_integration_test.go`解锁/重启去重 | M21b |
| M23 | P0 | 4 高 | M | — | 主 TC-MHANDOFF-005, TC-MHANDOFF-006, TC-MHANDOFF-007 | `runner.go/runner_requirement_entry.go`+`runner_integration_test.go`合法入口/cycle | M22 |
| M24 | P0 | 4 高 | M | — | 主 TC-MDEV-003；支持 TC-MDEV-002 | `gate_projection.go`+`gate_review_test.go/gate_projection_test.go`release-subjects/结果投影 | M23 |
| M25 | P0 | 4 高 | M | — | 主 TC-MDEV-002 | `internal/daemon/crevents.go`+`crevents_test.go`载体与M24对接 | M24 |
| M26 | P0 | 4 高 | M | — | 主 TC-MDEV-001, TC-MDEV-004, TC-MDEV-007 | `runner.go/runner_requirement.go`+`runner_integration_test.go`开发节点/loop/版本 | M25 |
| M27 | P0 | 5 高 | M | — | 主 TC-MDEV-005, TC-MDEV-006 | `runner.go/runner_requirement.go`+`runner_integration_test.go`upstream复评/增量恢复 | M26, M23 |
| M28 | P0 | 4 高 | M | — | 主 TC-MHANDOFF-008 | `runner.go`+`runner_integration_test.go`人工驳回终止正向链 | M27 |
| M30a | P0 | 4 高 | M | — | 主 TC-MDELIVERY-002, TC-MDELIVERY-004 | `pipeline_task.go`+`pipeline_task_test.go`authority参数/新task本机根 | M28 |
| M30b | P0 | 5 高 | M | — | 主 TC-MDELIVERY-001, TC-MDELIVERY-003 | `runner.go`+`runner_integration_test.go`交付链/机器drift业务回退 | M30a, M22 |
| M31 | P0 | 5 高 | M | — | 主 TC-MDELIVERY-005 | `pipeline_task.go`+`pipeline_task_test.go`安装根archive/清后重入 | M30b |
| M32 | P0 | 5 高 | M | — | 主 TC-MDELIVERY-006 | `internal/daemon/daemon.go::settleCREventsForTask`+`crevents_test.go`业务成功/技术settle分离 | M31 |
| M33 | P0 | 5 高 | M | — | 主 TC-MRECOVERY-003, TC-MRECOVERY-004 | `terminal_report_queue.go`、`daemon.go`+`terminal_report_queue_test.go`结构化recovery重放 | M32, M40 |
| M34 | P0 | 5 高 | M | — | 主 TC-MDELIVERY-007 | `gate_projection.go`+`gate_projection_test.go`Runner/projector ownership | M33 |
| M35a | P0 | 4 高 | M | G1 | 支持 TC-MKB-001 | `pkg/protocol/messages.go`、`internal/daemonws/hub.go`+`hub_test.go`原生type/lease | M15, B-TRANSPORT |
| M35b | P0 | 4 高 | M | G2 | 主 TC-MKB-001, TC-MKB-002, TC-MKB-004 | `handler/daemon.go`、`daemon_ws.go`+`daemon_ws_test.go`双传输server/身份/actions | M35a |
| M36 | P0 | 4 高 | M | — | 主 TC-MKB-003, TC-MKB-005, TC-MKB-007；支持 TC-MKB-001, TC-MKB-004 | `internal/daemon/daemon.go`+`wakeup_test.go`共享快照消费/collector生命周期，收齐两端CP | M35b |
| M37a | P0/P1 | 4 高 | M | — | 主 TC-MKB-008；支持 TC-MKB-006 | `pipeline_task.go`、`daemon.go`+`pipeline_task_test.go`定位/settle/采集同源和两处报错 | M36, M32 |
| M37b | P0 | 4 高 | M | — | 主 TC-MKB-006 | `daemon.go/wakeup.go`+`wakeup_test.go`五消费者请求级workspace | M37a |
| M38a | P0 | 4 高 | M | — | 支持 TC-MKEY-001 | `internal/governance/approval.go`+`approval_crosscheck_test.go`pending公钥响应 | M37b |
| M38b | P0 | 5 高 | M | — | 主 TC-MKEY-001, TC-MKEY-002, TC-MKEY-003 | `daemon.go::deliverGrants`+`wakeup_test.go`可信连接/唯一根/key→grant→ID | M38a |
| M39 | P0/P1 | 5 高 | M | — | 主 TC-MKEY-004, TC-MKEY-005, TC-MKEY-006 | `daemon.go`+`wakeup_test.go`原子写/旧锚/临时Git忽略回归 | M38b |
| M40 | P0 | 4 高 | M | — | 主 TC-MRECOVERY-006 | `pkg/taskfailure/classify.go`+`classify_test.go/failure_test.go`安全技术分类 | M28 |
| M41a | P0 | 4 高 | M | — | 主 TC-MRECOVERY-002, TC-MRECOVERY-005 | `internal/service/task.go`+`retry_deferred_test.go`原retry/预算/退避 | M40 |
| M41b | P0 | 5 高 | M | — | 主 TC-MRECOVERY-001, TC-MRECOVERY-007 | `runner.go/runner_requirement.go`+`runner_integration_test.go`先跟child/业务与终态边界 | M41a, M33, M34 |
| M42 | P0 | 5 高 | M | — | 主 TC-MTICK-001, TC-MTICK-002 | `cmd/server/runtime_sweeper.go`+`runtime_sweeper_test.go`原tick有界回调 | M41b, M22, M39, B-SWEEP |
| M43 | P0 | 5 高 | M | — | 主 TC-MTICK-003, TC-MTICK-004, TC-MTICK-005 | `runtime_sweeper_race_test.go`、`runner.go`+`runner_integration_test.go`竞争/暂态/预算 | M42 |
| M50 | P0 | 4 高 | M | — | 主 TC-MACK-001, TC-MACK-002, TC-MACK-004 | `approval.go::HandleGrantsAck`+`approval_continuation_test.go/approval_crosscheck_test.go`纯确认 | M43, M34, M39 |
| M51 | P0 | 4 高 | M | — | 主 TC-MACK-003, TC-MACK-005 | `runner.go::WakeGrant`+`runner_integration_test.go/daemon_workspace_test.go`四阶段隔离唤醒 | M50 |
| M52 | P0 | 5 高 | M | — | 主 TC-MDISPATCH-001, TC-MHANDOFF-009, TC-MACK-006 | `runner_integration_test.go`临时四阶段链；非生产发布/O2/旧续接桌演 | M51, T-FINAL（及全部前序） |
| M53 | P0 | 4 高 | S 验证 | — | 全69项最终核对，0新增主归属 | 分包全回归/生成一致性/tools回执及独立审查，无产品代码 | M52 |

省略目录的governance文件均位于`internal/governance/`，daemon文件位于`internal/daemon/`；路径复用不代表另建同名文件。生成源只改原脚本，不手改生成结果中的节点定义。SQL使用既有`AckApprovalGrants`批量更新，不新增表/协议。

## Rationale — 逐切片独立验收边界

本节与上表共同给出每切片依赖、风险和S/M依据；文件数包括测试，避免把测试写入藏在“很小实现”之外。以下验收是具体输入/强制断言，不是已通过声明。

| Slice | 为什么依赖 / 可独立拒绝的验收结果 | 风险与工作量依据 |
|---|---|---|
| M00 | 先有tools基线及安全DB，才核对本仓真正执行；不可达fixture退出0且无RUN必须被判未验证，正向须已有case实际PASS | 中3；S只核对现有命令证据、0改文件，不修改TestMain掩盖空跑 |
| M01 | 外部worker先交付才审回执；缺任一原发现范围/真实退出码/新回归或意外skip即拒收 | 中3；S只核对回执，不重复业务调查或造新本地case |
| M10a | 固定T-REG输入先行；四schema、CRLF规范及字段导入由原脚本测试，模板变化不能被硬编码忽略 | 高4；M脚本+合同测试2文件，生成输出留下一片 |
| M10b | 有正确生成源后才更新2份机械产物；输入type/required、executor/权限/节点执行声明逐项变化必须改digest，顶层不一致拒绝 | 高4；M两产物+合同测试3文件；不能手写节点表或覆盖旧digest |
| M11 | 固定产物后parser才能解释；四模板不同节点数、完整reviewLoop/replayNodes及交付无loop均按声明，human仍gate | 高4；M两parser文件+测试3文件，只有walker/输入解释缝 |
| M12 | parser保留nodeId后才绑定；同ref两个node不合并，executor actor同workspace解析、作者不自评、human零Agent/task，移除caller全Skill依赖 | 高4；M两Runner文件+测试3文件，不能把owner当executor |
| M13 | 已有合法executor后独立检source；五类绑定非法各拒绝，completed source保真实归因，合法executor不掩盖source跨界 | 高4；M Runner/requirement entry+测试3文件，PipelineTaskSpec只读复用，不批量改历史task |
| M14 | 合法归属先确定再发claim；workspace/digest/node错配逐项拒绝，source和ExecutorAgentID独立往返 | 高4；M handler+测试2文件，完整双端CP仍待M15 |
| M15 | server字段先稳定再daemon消费；不同节点/轮次允许dirty对照clean阻断，carrier不丢归属 | 高4；M daemon pipeline+测试2文件，不修改运行中task env |
| M20 | 先能正确运送任务，再判断业务；仅completed/exit0/模型PASS/文件存在均不得越过缺canonical账本/评审/审批 | 高4；M两Runner+测试3文件，不在Runner复制crctl判据 |
| M21a | 先拆持久事实与副作用，context重建须保digest/workspace/source/started_by；局部round-trip可独立测试，不冒称重启全链通过 | 高4；M resume/Runner+测试3文件，为M21b/M22提供现有context缝 |
| M21b | context可持久化后同Tx写；三批准分配下游，所有查询/upsert/context/上游结果Tx身份一致，逐写点失败不可半提交 | 高5；M两Runner+测试3文件；单连接可见性不能代替独立连接断言 |
| M22 | Tx写正确后验证时序；commit+释放连接/锁才可同步Bus/Reconcile，销毁内存后恢复唯一派发；并发不得重复task/嵌套锁 | 高5；M两Runner+测试3文件；不要用永久sleep伪造时序 |
| M23 | 已有原子交接后才放行特殊入口；合法业务转换新cycle、非法终态不重开、注册后非原子窗口确定性重入分别对照 | 高4；M两Runner+测试3文件，不把无active run当授权 |
| M24 | 合法开发cycle后接投影；server可接受三类结果但错归属/过期拒绝，代码评审按release-subjects而非设计单hash | 高4；M投影+2测试3文件，daemon完整载体另片 |
| M25 | server接收合同稳定后daemon输出；dev-plan/test/upstream三类往返及错CR/node/轮次拒绝，不能吞测试失败/BLOCK | 高4；M crevents+测试2文件，M24/M25两端共同结束DEV投影CP |
| M26 | 载体齐后验证实际开发声明；真实testCr而非报告，普通三类BLOCK各自loop，unassigned等待负责人真实version-set且不耗技术预算 | 高4；M两Runner+测试3文件，不新增dev-start或评审节点 |
| M27 | 普通loop和合法入口都齐后测upstream；必须先tech-design-review-pending复评，BLOCK才编写，重审/原审批后增量恢复 | 高5；M两Runner+测试3文件，原合法transitions作为只读合同，禁止手填生成表 |
| M28 | 回修分类后单独约束人工驳回；APPROVAL_DECLINED_ROLLED_BACK停止正向，不沿旧grant、不当技术重试/一律重写 | 高4；M Runner+测试2文件，业务政策不可扩写 |
| M30a | 开发结果可靠后组交付参数；缺spec/真实版本阻断，不强填legacy，merge后旧task终结/新task本机重绑 | 高4；M pipeline+测试2文件，不server猜绝对路径 |
| M30b | 参数/根合同稳定才接交付；代码批准授权原merge/回写/traceability/archive，无生产部署；release-drift exit0仍回developing重批，部分发布保阻断 | 高5；M Runner+测试2文件，业务路由不走retry merge |
| M31 | merge后新task缝就绪才验证归档cwd；从临时安装根启动，删txws后重入仍解析authority并保audit/outbox/settle | 高5；M pipeline+测试2文件，不借缺txws跳过authority |
| M32 | 安装根稳定后区分cleanup-pending与settle；业务成功但技术settle失败不假收尾、不重归档或另派清理 | 高5；M daemon+测试2文件；结构化队列消费留M33 |
| M33 | settle故障和安全分类先有；队列重启保failure/code/recovery/journal，安全argv幂等消费，文字建议/来源或argv篡改拒绝 | 高5；M队列/daemon+测试3文件，不新增补偿文件/执行器 |
| M34 | 最后结果能恢复后测ownership；先到archived/跨阶段投影只改展示、不抢关Runner，投影自有run合法处理仍保留 | 高5；M projection+测试2文件，不能用事件到达顺序代替汇合 |
| M35a | B-TRANSPORT明确后才编码；现有HTTP/WS原生type和lease可携同一授权runtime daemon_id，无PAT/客户端自报身份 | 高4；M protocol/hub/测试3文件；本片不决定尚未定案的新字段名 |
| M35b | type/lease稳定后server双传输；HTTP手动响应与WS语义一致、按项目/runtime查、无N+1；错误/缺字段不能丢已领取actions | 高4；M两handler+测试3文件；资源查询先复用已有SQL，若需额外生成SQL修改则先再拆片；跨端CP待M36 |
| M36 | server语义稳定后共用consumer；非空替换、成功空清除、缺失/错误保留、退出清投影、冷启动/晚出现识别且无env回流，收齐M35b双端CP | 高4；M daemon+测试2文件，3主TC+2支持TC，collector/投递循环无条件随生命周期启动 |
| M37a | projection和settle两边齐后接根；采集/任务定位/settle必须同源，两处CR not found输出workspace/CR、资源、daemon/runtime和投影线索 | 高4；M daemon/pipeline+测试3文件；P1错误合同仍闭环前做 |
| M37b | 三消费者就绪后连pending/ack；并发两workspace用各自X-Workspace-ID，五消费者同源、IDs不串，不能改共享client全局状态 | 高4；M daemon/wakeup+测试3文件；不加持久根缓存 |
| M38a | workspace请求合同就绪再添同通道公钥；PublicKeyPEM的key_id/pem与原grant一起返回，server不编排续接 | 高4；M approval+测试2文件，只是投递支持缝，不提前改ack |
| M38b | 有可信pending key后daemon选择唯一目标；有效TLS/原回环可装，远程明文拒绝，零/歧义/跨workspace不写不ack，顺序key→完整grant→ID | 高5；M daemon+测试2文件；“任意根成功”不算送达 |
| M39 | 正常投递正确后注入中断；冲突/缺key/任一写失败不ack且无半文件；旧key保留、无旧key旧grant仍pending；临时Git无新dirty | 高5；M daemon+测试2文件；P1只改临时fixture，不能删真实已跟踪信任锚/改真实KB配置 |
| M40 | 人工/业务分类已明确再划技术范围；TX_GIT_FAILED/process_failure不整类白名单，只有明确安全暂态走原恢复，认证/余额/签名冲突拒绝 | 高4；M分类+2测试3文件，不从自由文本推权限 |
| M41a | 安全分类先定再service重试；待补报优先、原预算/退避、attempt与业务loop分离，耗尽明确停，不每tick加attempt | 高4；M task+retry测试2文件，不造第二重试系统 |
| M41b | service、queue、ownership都可靠后Runner跟随child；queued/running/completed child优先且完成仍验canonical，等待不耗重试/终态不复活 | 高5；M两Runner+测试3文件，不先failRun截断恢复 |
| M42 | 无事件时须等整个执行/投递/恢复链就绪，再接原sweeper；在已定内部边界下实测限批/超时、公平和liveness，先测试再最小接回调 | 高5；M sweeper+测试2文件；B-SWEEP未定不实现猜值或保证恢复时限 |
| M43 | callback存在后打竞争屏障；事件/启动/tick最多一有效执行，暂态保持活动，人工/版本等待不越gate，终态/耗尽不复活 | 高5；M Runner+2测试3文件，-race工具链不安全/缺失时阻塞该验证而非静默略过 |
| M50 | 整套执行/恢复/送达已完成才去旧编排；batch delivered_at仅送达，认证/workspace/幂等保留，真提交失败可重投，旧续接调用数为0 | 高4；M approval+2测试3文件；不先删Leader尾续接造成无人接管 |
| M51 | 纯确认提交语义固定后按实际四阶段唤醒；commit后单失败不撤其他ack/唤醒，缺run/终态/旧cycle不新建不假推进 | 高4；M Runner+2测试3文件；失败由持久tick补，无新队列/Leader兜底 |
| M52 | 全前序与tools最终证据齐后独立临时四阶段实跑；正常/回修/中断与发布窗口/O2、旧续接只做夹具/桌演，读权威status/next而非旧主checkout | 高5；M现有集成测试文件+最多2份测试fixture，3主TC；绝不执行真实部署/CR/停服/存量恢复 |
| M53 | 全链证据收齐才最终汇合；完整受影响包回归、原生成check、tools最终全范围、代码/测试/文档独立审查与Issue/PR追溯不能缺项 | 高4；S证据汇合0产品文件；全量命令分包执行，耗时未知，不能冒称Gate3批准 |

## RED / GREEN / REFACTOR 命令与隔离前提

### 运行前必须满足（此回合不执行）

1. 主会话核准隔离测试DSN/迁移版本/对象归属；`MULTICA_ISOLATED_TEST_DSN`只是下列shell片段的会话变量，**不是新增产品环境变量/flag**。不从.env读取、不在计划写密钥；每次换目标都重新确认。各并行worker有独立fixture/库，不共享清理对象。现有TestMain会建governance-tests workspace并清理CR-9%数据，**仅换workspace不算隔离DB**；库须完成与待测revision相匹配的全部既有迁移，不能仅满足旧注释的migration 158。Node/Go/Postgres及-race工具链沿用既有环境，缺依赖不自行安装。
2. 从明确批准的S工作目录执行；先设置会话`DATABASE_URL`为该明确DSN并在**每条**Go命令前显式覆盖。下表每条Go配方均显式设置`DATABASE_URL`并用shell非空展开保护；变量缺失即在启动Go前停止，不能展开为空后回落默认地址。
3. 不使用`make test`，不使用默认.env，不启动真实daemon/server、真实CR深原语或生产服务。测试用假HTTP/WS、临时Git/KB/安装根/密钥、可控时钟/屏障和隔离已迁移DB。声明命令不等于允许忽略这些前置。

```bash
# 未来：仅在已确认隔离对象后，命令自身也拒绝空变量。
cd 'C:/Users/GOBAO/Downloads/AI/multica/server'
: "${MULTICA_ISOLATED_TEST_DSN:?STOP: 主会话须先确认隔离已迁移测试库}"
DATABASE_URL="$MULTICA_ISOLATED_TEST_DSN" go test -count=1 -v ./internal/governance -run '^TestParseCoreRegistryFixedContract$'
```

### TestMain未空跑的证明

- 现有`internal/governance/crsync_test.go::TestMain` DB不可达可`os.Exit(0)`，包括纯函数case都可能未执行。M00正向必须看到`=== RUN   TestParseCoreRegistryFixedContract`和对应`--- PASS`，不是只有包exit0；若旧命名因后续合同调整，必须由已有真实case清单显式替换，不能使用能匹配0项的正则糊过去。
- M00负向只用主会话明确隔离的不可达fixture DSN（不猜端口、不接默认库），同命令产生exit0但无实际RUN应被人工/测试证据审查判**未验证**；负向不是业务GREEN，也不是“库安全可达”的证明。
- 后续每条精确-run命令先新增/确认命中的测试函数存在；GREEN须核对预期root/subtest实际run/pass及case数、skip=0、原始退出码。M10b和M52分别补证目标TestMDispatch005/001确实执行，从而满足原基线TC的最终正向要求。
- root/subtest数量在写入真实测试后按测试源清单确定，不能预造“69个Go函数/69个PASS”；69是独立业务TC数，同TC可能跨包/有多subcase。无tests-to-run、unexpected skip、未结束或0实际case均阻塞。只有本身仅类型声明而确无测试的包可标no-test-files并由对应使用包合同测试覆盖，不能拿它替代任何主TC。
- 不用tail/管道最后命令的退出码冒充go test退出码；-v输出及失败详情直接留既有执行日志/PR摘要，不新增运行时报告。当前没有任何DB连接或业务测试结果。

### 每切片命令表

**通用步骤（39个代码/测试切片逐项执行，不是合并一次）**：①按上述Rationale和原test-plan完整GWT/AND在表列既有测试文件新增断言；②运行表中命令取得与目标行为匹配的RED；③只改该slice目标文件，最小GREEN；④重复原命令与该slice实际修改包的`go test -count=1 -v <完整包>`，不能只跑-run子集；⑤REFACTOR后重复GREEN并核对TC/CP/产物。下表命令在RED与GREEN相同，未给未决接口编造Go签名/字段或实现代码。M00/M01/M53是验证节点，不强造RED/新增测试。实际等价旧覆盖已绿须先证明等价，不删除断言求红。

**注意：以下Go命令已带显式DSN及非空保护，但仍须先核准该DSN确属独立已迁移测试库；TestM名字全为拟新增，不宣称已经存在，M00使用已有TestParseCoreRegistryFixedContract。**

| Slice | RED→GREEN使用同一命令（S目录执行） | 附加完整验收 |
|---|---|---|
| M00 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestParseCoreRegistryFixedContract$'` | 隔离负向无RUN拒绝；正向实际RUN/PASS，最终再核对节点001/005 |
| M01 | 无本地重跑命令；审T-S0 worker的原完整运行回执 | 两类根因先红后修、原范围+新增、真实退出码/耗时/case/skip，不复制worker工作 |
| M10a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDispatch005Generator$'` | 测试只在临时checkout/输入夹具验证原生成器，避免测试写活动源码 |
| M10b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDispatch005$'` | 原生成命令和--check，见下一代码块 |
| M11 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDispatch003$'` | 重跑生成/parser全部合同测试 |
| M12 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMBinding00[123]$'` | 重复ref/独立review/human零task三个case实际执行 |
| M13 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMBinding00[456]$'` | 五类绑定负例、completed source及三类坏source全部subcase |
| M14 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/handler -run '^TestMDispatch006$'` | handler完整包；carrier最终须M15 daemon对照 |
| M15 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMDispatch00[46]$'` | daemon完整包；dirty/clean逐轮次与M14联合 |
| M20 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDispatch002$'` | 三种假成功及缺账本/评审/审批组合 |
| M21a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMHandoff004ContextRoundTrip$'` | 局部context往返，不代替M22完整重启case |
| M21b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMHandoff00[12]$'` | 所有写点故障、独立连接可见性、Tx身份一致 |
| M22 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMHandoff00[34]$'` | 同步Bus/锁屏障及销毁内存Runner后唯一重建 |
| M23 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMHandoff00[567]$'` | 合法/非法cycle、digest/context冲突、注册窗口 |
| M24 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDev00[23]$'` | server投影及release-subjects漂移；完整投影CP待M25 |
| M25 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMDev002$'` | 与M24 server同一批正/负fixture |
| M26 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDev00[147]$'` | 用已验证tools真实testCr临时夹具，不用报告替代；version-set后证据 |
| M27 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDev00[56]$'` | 先复评后编写、必要重审/原人工审批、增量开发 |
| M28 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMHandoff008$'` | 驳回不前进、不技术重试 |
| M30a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMDelivery00[24]$'` | 缺authority输入逐项拒绝，新task本机根 |
| M30b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDelivery00[13]$'` | 原交付序列和drift两种结果；生产副作用为0 |
| M31 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMDelivery005$'` | 临时安装根/删除txws/恢复authority |
| M32 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMDelivery006$'` | cleanup-pending与settle故障分开 |
| M33 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMRecovery00[34]$'` | 队列重开、argv保真、篡改/文字拒绝、幂等 |
| M34 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDelivery007$'` | Runner/投影两种ownership、乱序 |
| M35a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemonws -run '^TestMKb001LeaseContract$'` | protocol经hub使用/编译，按主会话已定原生命名，不发明schema |
| M35b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/handler -run '^TestMKb00[124]$'` | 同fixture HTTP/WS、鉴权daemon_id、查询数、错误时actions；双端收齐等M36 |
| M36 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMKb00[13457]$'` | 两传输共用consumer、失败不丢actions；absent/error/empty、换路径/退出、晚目录、env残留 |
| M37a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMKb00[68]$'` | 两处CR not found、定位/settle/采集同源；五消费者最终等M37b |
| M37b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMKb006$'` | 假服务逐请求核X-Workspace-ID、IDs、共享client未被改 |
| M38a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMKey001PendingKey$'` | PublicKeyPEM原响应通道；不触ack路由 |
| M38b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMKey00[123]$'` | TLS/回环/明文、零/多/跨workspace目标、写/ack时序 |
| M39 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/daemon -run '^TestMKey00[456]$'` | 原子写各故障点、旧锚/缺旧锚、临时Git字节/status |
| M40 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./pkg/taskfailure -run '^TestMRecovery006$'` | 混合类不整体重试、明确暂态合法对照 |
| M41a | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/service -run '^TestMRecovery00[25]$'` | backoff/预算边界、技术attempt不重置loop |
| M41b | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMRecovery00[17]$'` | 两入口child三态、业务/等待/终态 |
| M42 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./cmd/server -run '^TestMTick00[12]$'` | 超一批/单run卡住/公平/liveness；只用已定边界与测量，不填猜值 |
| M43 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./cmd/server ./internal/governance -run '^TestMTick00[345]$'` | 两包分别有实际命中；工具链已确认时同命令加-race验证并发 |
| M50 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMAck00[124]$'` | delivered_at、权限/幂等、真commit失败，旧续接探针=0 |
| M51 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMAck00[35]$'` | commit后四阶段单失败隔离、缺run/终态/旧grant不假推进 |
| M52 | `DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMDispatch001$'`；`DATABASE_URL="${MULTICA_ISOLATED_TEST_DSN:?STOP: isolated DB required}" go test -count=1 -v ./internal/governance -run '^TestMReleaseWindowFixtures$'` | 自动四阶段+独立桌演Handoff/O2/旧续接CP，均临时非生产；不执行真实start/部署命令 |
| M53 | 下面完整包/生成检查命令，另审T-FINAL原始回执 | 独立代码/测试/文档评审，未完成项如实保持pending，不批准Gate3 |

```bash
# 未来M10b：从S沿用原生成器；TOOLS_CHECKOUT须是主会话确认的T-REG实际tools checkout。
: "${TOOLS_CHECKOUT:?STOP: 未确认tools候选checkout/revision}"
node internal/governance/gen/generate-gate-nodes.mjs --tools "$TOOLS_CHECKOUT"
node internal/governance/gen/generate-gate-nodes.mjs --tools "$TOOLS_CHECKOUT" --check

# 未来M53：显式隔离DSN、完整受影响包；不得用精确-run子集代替。
: "${MULTICA_ISOLATED_TEST_DSN:?STOP: 未确认隔离已迁移测试库}"
DATABASE_URL="$MULTICA_ISOLATED_TEST_DSN" go test -count=1 -v -cover ./internal/governance ./internal/service ./internal/handler ./internal/daemonws ./internal/daemon ./pkg/protocol ./pkg/taskfailure ./cmd/server
DATABASE_URL="$MULTICA_ISOLATED_TEST_DSN" go vet ./internal/governance ./internal/service ./internal/handler ./internal/daemonws ./internal/daemon ./pkg/protocol ./pkg/taskfailure ./cmd/server
node internal/governance/gen/generate-gate-nodes.mjs --tools "$TOOLS_CHECKOUT" --check
```

全包命令可按包拆运行以便保存真实退出码/耗时，不能减范围。覆盖率按仓库已有阈值核对，不自造数值；不写coverprofile/新增运行时报告。若未来又改SQL/生成源或其他包，必须追加其原生成一致性/完整包回归及受影响现有用例，不拿本表当排除清单。tools侧只验worker已运行的既有lint-prompts/check-agents-contract/check-skill-matrix、crctl/output-guard/registry完整发现范围及实际改深原语，不在本仓重复开工。既有OUTDATED/Windows失败单列，不能静默豁免。

## 附录A：真实Scenario → 独立TC → agent CP → 唯一主切片

每行直接引用现有canonical定义；TC和CP不新编号，主归属只计一次。所有支持节点以执行表为准；主归属不是完成时序门，尚有后续跨端支持节点未验证时CP仍pending（例如M14→M15、M35b→M36）。人工/桌演TC同样独立，不伪造为已执行Go case。

| Scenario | TC | CP | 主切片 |
|---|---|---|---|
| M-SC-ACK-001 | TC-MACK-001 | M-CP-ACK-001 | M50 |
| M-SC-ACK-002 | TC-MACK-002 | M-CP-ACK-002 | M50 |
| M-SC-ACK-003 | TC-MACK-003 | M-CP-ACK-003 | M51 |
| M-SC-ACK-004 | TC-MACK-004 | M-CP-ACK-004 | M50 |
| M-SC-ACK-005 | TC-MACK-005 | M-CP-ACK-005 | M51 |
| M-SC-ACK-006 | TC-MACK-006 | M-CP-ACK-006 | M52 |
| M-SC-DELIVERY-001 | TC-MDELIVERY-001 | M-CP-DELIVERY-001 | M30b |
| M-SC-DELIVERY-002 | TC-MDELIVERY-002 | M-CP-DELIVERY-002 | M30a |
| M-SC-DELIVERY-003 | TC-MDELIVERY-003 | M-CP-DELIVERY-003 | M30b |
| M-SC-DELIVERY-004 | TC-MDELIVERY-004 | M-CP-DELIVERY-004 | M30a |
| M-SC-DELIVERY-005 | TC-MDELIVERY-005 | M-CP-DELIVERY-005 | M31 |
| M-SC-DELIVERY-006 | TC-MDELIVERY-006 | M-CP-DELIVERY-006 | M32 |
| M-SC-DELIVERY-007 | TC-MDELIVERY-007 | M-CP-DELIVERY-007 | M34 |
| M-SC-DEV-001 | TC-MDEV-001 | M-CP-DEV-001 | M26 |
| M-SC-DEV-002 | TC-MDEV-002 | M-CP-DEV-002 | M25 |
| M-SC-DEV-003 | TC-MDEV-003 | M-CP-DEV-003 | M24 |
| M-SC-DEV-004 | TC-MDEV-004 | M-CP-DEV-004 | M26 |
| M-SC-DEV-005 | TC-MDEV-005 | M-CP-DEV-005 | M27 |
| M-SC-DEV-006 | TC-MDEV-006 | M-CP-DEV-006 | M27 |
| M-SC-DEV-007 | TC-MDEV-007 | M-CP-DEV-007 | M26 |
| M-SC-DISPATCH-001 | TC-MDISPATCH-001 | M-CP-DISPATCH-001 | M52 |
| M-SC-DISPATCH-002 | TC-MDISPATCH-002 | M-CP-DISPATCH-002 | M20 |
| M-SC-DISPATCH-003 | TC-MDISPATCH-003 | M-CP-DISPATCH-003 | M11 |
| M-SC-DISPATCH-004 | TC-MDISPATCH-004 | M-CP-DISPATCH-004 | M15 |
| M-SC-DISPATCH-005 | TC-MDISPATCH-005 | M-CP-DISPATCH-005 | M10b |
| M-SC-DISPATCH-006 | TC-MDISPATCH-006 | M-CP-DISPATCH-006 | M14 |
| M-SC-DISPATCH-007 | TC-MDISPATCH-007 | M-CP-DISPATCH-007 | M00 |
| M-SC-DISPATCH-008 | TC-MDISPATCH-008 | M-CP-DISPATCH-008 | M01 |
| M-SC-KB-001 | TC-MKB-001 | M-CP-KB-001 | M35b |
| M-SC-KB-002 | TC-MKB-002 | M-CP-KB-002 | M35b |
| M-SC-KB-003 | TC-MKB-003 | M-CP-KB-003 | M36 |
| M-SC-KB-004 | TC-MKB-004 | M-CP-KB-004 | M35b |
| M-SC-KB-005 | TC-MKB-005 | M-CP-KB-005 | M36 |
| M-SC-KB-006 | TC-MKB-006 | M-CP-KB-006 | M37b |
| M-SC-KB-007 | TC-MKB-007 | M-CP-KB-007 | M36 |
| M-SC-KB-008 | TC-MKB-008 | M-CP-KB-008 | M37a |
| M-SC-BINDING-001 | TC-MBINDING-001 | M-CP-BINDING-001 | M12 |
| M-SC-BINDING-002 | TC-MBINDING-002 | M-CP-BINDING-002 | M12 |
| M-SC-BINDING-003 | TC-MBINDING-003 | M-CP-BINDING-003 | M12 |
| M-SC-BINDING-004 | TC-MBINDING-004 | M-CP-BINDING-004 | M13 |
| M-SC-BINDING-005 | TC-MBINDING-005 | M-CP-BINDING-005 | M13 |
| M-SC-BINDING-006 | TC-MBINDING-006 | M-CP-BINDING-006 | M13 |
| M-SC-TICK-001 | TC-MTICK-001 | M-CP-TICK-001 | M42 |
| M-SC-TICK-002 | TC-MTICK-002 | M-CP-TICK-002 | M42 |
| M-SC-TICK-003 | TC-MTICK-003 | M-CP-TICK-003 | M43 |
| M-SC-TICK-004 | TC-MTICK-004 | M-CP-TICK-004 | M43 |
| M-SC-TICK-005 | TC-MTICK-005 | M-CP-TICK-005 | M43 |
| M-SC-HANDOFF-001 | TC-MHANDOFF-001 | M-CP-HANDOFF-001 | M21b |
| M-SC-HANDOFF-002 | TC-MHANDOFF-002 | M-CP-HANDOFF-002 | M21b |
| M-SC-HANDOFF-003 | TC-MHANDOFF-003 | M-CP-HANDOFF-003 | M22 |
| M-SC-HANDOFF-004 | TC-MHANDOFF-004 | M-CP-HANDOFF-004 | M22 |
| M-SC-HANDOFF-005 | TC-MHANDOFF-005 | M-CP-HANDOFF-005 | M23 |
| M-SC-HANDOFF-006 | TC-MHANDOFF-006 | M-CP-HANDOFF-006 | M23 |
| M-SC-HANDOFF-007 | TC-MHANDOFF-007 | M-CP-HANDOFF-007 | M23 |
| M-SC-HANDOFF-008 | TC-MHANDOFF-008 | M-CP-HANDOFF-008 | M28 |
| M-SC-HANDOFF-009 | TC-MHANDOFF-009 | M-CP-HANDOFF-009 | M52 |
| M-SC-KEY-001 | TC-MKEY-001 | M-CP-KEY-001 | M38b |
| M-SC-KEY-002 | TC-MKEY-002 | M-CP-KEY-002 | M38b |
| M-SC-KEY-003 | TC-MKEY-003 | M-CP-KEY-003 | M38b |
| M-SC-KEY-004 | TC-MKEY-004 | M-CP-KEY-004 | M39 |
| M-SC-KEY-005 | TC-MKEY-005 | M-CP-KEY-005 | M39 |
| M-SC-KEY-006 | TC-MKEY-006 | M-CP-KEY-006 | M39 |
| M-SC-RECOVERY-001 | TC-MRECOVERY-001 | M-CP-RECOVERY-001 | M41b |
| M-SC-RECOVERY-002 | TC-MRECOVERY-002 | M-CP-RECOVERY-002 | M41a |
| M-SC-RECOVERY-003 | TC-MRECOVERY-003 | M-CP-RECOVERY-003 | M33 |
| M-SC-RECOVERY-004 | TC-MRECOVERY-004 | M-CP-RECOVERY-004 | M33 |
| M-SC-RECOVERY-005 | TC-MRECOVERY-005 | M-CP-RECOVERY-005 | M41a |
| M-SC-RECOVERY-006 | TC-MRECOVERY-006 | M-CP-RECOVERY-006 | M40 |
| M-SC-RECOVERY-007 | TC-MRECOVERY-007 | M-CP-RECOVERY-007 | M41b |

## 计数与静态审计口径

- 基于实际canonical逐项核对：10真实capability / 31 Requirements / 69 Scenario / 69独立TC / 69 CP；P0=67、P1=2。两份TODO种子不参与，CLI state的0计数不作为范围事实，也不在本回合修state。
- 42计划节点（39个M代码/测试切片，3个S验证节点），附录A覆盖69/69，SC/TC/CP各自唯一；无伪造ID、无悬空SC、无重复主归属。4个准备性支持节点M10a/M21a/M35a/M38a没有额外主TC，不凑覆盖数；M53只汇合证据。
- 依赖表必须静态核对42节点全部被tasks引用、内部依赖存在且无环；G1/G2均无组内依赖、目标写集合不交叉。原CLI字面图0边不等于业务无依赖。
- 本回合只读图/经验查询、映射/DAG审计及原CLI结构validate：exit0、0错误，69唯一TC/69 Scenario/69 TC Cases；9项既有整文件AND累计告警原样保留（canonical逐Scenario上限未变），不以改规格或STDD消警。
- **0业务测试执行、0DB连接、0切片实施完成**。新TestM名字是计划，不是现存/通过事实；未运行agent步骤、CLI advance/gate、真实部署或CR操作。
- 仅新增`tasks.md`/`slices.md`，不改proposal/spec/design/test-plan/phase-context/state/索引、tools worker文件、STDD产品或权限。实施与Gate3验收由主会话在共享授权和上述阻塞约束内后续处理。
