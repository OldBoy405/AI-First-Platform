# AIFI-45：分层委派恢复 BUILD（2026-10-24）

## 范围与前置

用户原文：“接 ④ AIFI-45”；随后明确“注意：使用stdd模型分层委派任务”。继续已批准的普通 BUILD，不新建 quality-debt change，不重新确认已经采纳的补正方向，不推定 Gate 3、提交、推送、部署或真实 CR 试点授权。

两仓原生状态：`current_phase=build`、`status=active`、`phases.build.status=in_progress`、`long_range.enabled=false/mode=normal`。Gate 1/2 保留原文与时间，无状态推进。业务计划为 T32（AUTH10/RPR12/EVD10）+ M17（RUN10/NTF7）=49 条；**完整 TC 完成仍为 0/49，5 个 major 未关闭**。

本轮最小纵切片：既有 initial 的持久化 current-head 与历史投递分离。实施合同见 [wire-contract §3.1](wire-contract.md#31-build-分段持久化-current-head未开放准入)。不以此代替 revoke/extend、可信 claim、本机/每 repo 当前绑定、不可删除 activation、隔离控制通道或 T 消费事务；未闭合前继续拒绝消费。

## 有效模型与真实委派

在源码即业务项目根 `tools/`、`multica/` 分别调用更新后的 STDD `config models --format json`，经各自 `.stdd/binding.yaml` 解析到知识库 data root，均 exit0、`schema_version=1`、`kind=configured`、`user_defaults_present=true`。三档 model/effort 六参数均为 `user` 来源；design/retry 及 reviewer tier 为 builtin 来源。两仓分别保存 `validation/resume-20261024-config-models.json`（含 cwd/exit/output/provenance），而非由母本空值推断配置。没有修改两仓业务质量配置，也没有回改历史“缺映射而默认回退”的 requested/actual 记录。

| 任务/范围 | requested tier | requested model | requested effort | 子会话 |
|---|---|---|---|---|
| current-head/撤销接缝设计；TDD 实施第一段 current-head（M 唯一 writer） | strong | `OpenAIPersonal/gpt-6.1-sol` | high | `01a16daa-8915-77b9-a3c5-0e9068caaa4c` |
| 专用 DB 身份与真实 Auth 基线、产品独立复跑；随后有界 test-only fixture 修复作者 | balanced | `Gobao/deepseek-flash` | max | `01a16daa-bc55-77b9-a3c5-0e933f98c16c` |
| 包含 fixture 补正的非作者最终组件复跑 | balanced | `Gobao/deepseek-flash` | max | `01a16de4-49d7-77b9-a3c5-0ea43f97175b` |
| Skill 安装入口、TC 计数及文档一致性核查 | economy | `GB-JP/deepseek-flash` | high | `01a16daa-e95e-77b9-a3c5-0e948b070c2f` |

派发通过宿主原生 `Agent.model=provider/model:effort` 指定；未生成代理文件。三档子进程报告的 `PI_PROVIDER/PI_MODEL/PI_REASONING_LEVEL` 分别与所请求三元组一致（strong 见 M `validation/initial-head-report.md`，balanced 见基线 `.meta.json`，economy 见对应可检查子会话）；这仅是 harness 信息，不是后端回执，`actual_provider/model/effort=unknown`。独立 strong 代码评审另用非作者会话 `01a16dc0-e380-77b9-a3c5-0e96526fedda`，请求同 strong 三元组；未把作者自检充作独立评审。

### 核查结果取舍

- economy 首轮错误地把 T 测试计划读成“0 TC 占位”、M 读成“49 TC”，又以时间戳推断 Skill 直用源码；主线程拒绝采纳并要求确定性复核。复核为 **T32/M17，无重复**，与批准合同一致，未据错误报告改 spec/tasks 或补 placeholder。
- `.agents/skills/stdd-{build,spec}/SKILL.md` 是安装期解析三根占位符的**渲染快照**，不是直接源码链接。两仓对应文本与当前源存在预期路径渲染差异；不能以修改时间或 raw hash 不同判断“过期/已重载”。两仓已安装正文中现有模型入口须按内容核查；本轮实际派发由主线程显式读取有效配置并发起，未假称宿主会话自动重载。
- 母本三档参数为空不代表当前有效配置为空：有效配置已实测继承用户级六参数。不得由母本空值建议改项目质量配置。

## 恢复基线（组件，不是完整 TC）

### T

命令：`node --test --test-reporter=tap skills/shared/crctl/scripts/test/execution-authorization.test.mjs skills/shared/crctl/scripts/test/execution-transaction.test.mjs skills/shared/crctl/scripts/test/durable-tx.test.mjs`，在 `tools/` 源码根执行。

结果：exit0，164 项 / 163 PASS / 0 FAIL / 1 SKIP / 0 TODO；墙钟 49,047 ms。唯一 SKIP 为 `EXEC-12 受控文件自身为 symlink：拒绝写入`（Windows EPERM），**未计通过**。原始 TAP：[validation/resume-tiered-20261024-tools-baseline.tap](validation/resume-tiered-20261024-tools-baseline.tap)。第一次执行在保存日志时因 validation 目录不存在而失败，没有作为证据引用；此处是建目录后完整补跑所得。

### M

balanced 在专用 DB 上实际执行现存真实 Auth/投递基线：

`go test ./internal/governance -run '^(TestExecutionAuthorize|TestExecutionAuthorizationRoute|TestDaemonFetchesAndInstallsExecutionAuthorization)' -count=1 -json`

结果：exit0；8 顶层 + 2 子例，共 RUN10/PASS10/FAIL0/SKIP0；墙钟 15,881 ms，Go 包 2.427 s。最初拟用的 `TestDaemonExecutionAuthorization` 源码零匹配，改为已核实实际名称后执行，不把空匹配当成功。

证据位于 M 同 change 的 `validation/20261024T113019Z-aifi45-governance-baseline.{go.jsonl,stderr.log,meta.json}` 与 `...-summary.md`。原始 JSON SHA256=`447597c374ed3d81159b4d75658eb0be348b1fdb3899ff5b77c37dda87bf1072`，stderr 空。

专用环境已核：容器 `stdd-aifi45-20261022-pg`，ID 前缀 `666bfec52ac3`，label `stdd.change=2026-10-22-aifi-45-authorized-execution`，`127.0.0.1:55432`，DB/user=`stdd_aifi45_20261022`/`stdd`，运行中。基线 schema_migrations=670、最新 `641_issue_context_refs_gin`。URL 仅内存构造，`GOPROXY=off`，删除 GitHub/knowledge tokens；没有访问共享库或修改基础设施。

## 配置保护快照

以下为恢复时观测的原 bytes SHA256；结束时用于核对恢复观测后是否发生改变，不声称与仓库 HEAD 或恢复前未知状态一致。不是语义摘要，故不做 EOL 规范化：

| 文件 | SHA256 |
|---|---|
| T `config.d/quality.yaml` | `25380eed278e254dbfb64c9af82f2e5d0bba09bc288dde2e76e3a3b985a6fcf2` |
| T `.stdd/binding.yaml` | `31546e1a36022d955c789a377f0398508fad3da3f9271991f51dea777868cf7b` |
| M `config.d/quality.yaml` | `05a0e3eb7a800962eb957c2edd5e90e0934432276d82416e09e88f8acf0909af` |
| M `.stdd/binding.yaml` | `ae676b9aef73b3274c997a9d47630e50164eb25dd04ae701650d5f4c97186d89` |

## current-head 第一段实现与复核

strong 已完成本段的 17 文件变更（**9 手写 + 8 sqlc 生成物**，以 manifest keys 程序计数为准）：CR 行锁事务内插入历史与独立记录 id 指针；新 DaemonAuth head GET 仅按指针读当前 DB 快照、校验身份/签名/原 payload/source；缺失、漂移、未配置拒绝，历史重放不补 head；实际 router 无 signer 明确503。642 迁移 nullable UUID，无 FK/cascade/default/backfill/index；仅专用隔离库应用至 671/642，重复 up exit0。现有本机 sqlc v1.31.1 离线生成，未安装依赖/手写生成列。

作者证据见 M `validation/initial-head-report.md`、原 manifest 与独立命名 raw/meta。首条旧行为真实 RED 为认证 initial 成功后 head GET404（预期200）；第二条为实际 router 无 signer 的404（预期503）。原窄回归118/118、router4/4、daemon继续拒消费2/2、迁移约定3/3均exit0/0fail/0skip。它们范围有重叠，不累加为独立用例数，更不算完整TC。

### 独立 C1 首轮与 P2 补正

- strong 独立代码审查发现 P2：issuance 接受 source 原 JSON `-0` 并签成 `0`，head 读侧 `UseNumber + reflect.DeepEqual` 却按数字词法判不同，出现 POST201→head409。首轮**未判 PASS**；不是把既有业务未完成冒充本片缺陷。
- balanced 独立打乱复跑原版：governance `-count=2` 共236/236、router4/4、daemon2/2，均exit0/0skip；这些绿色**不覆盖负零问题**。报告 M `validation/20261024T115444Z-aifi45-review-report.md` 保留本轮捕获包装器在 raw 保存后崩溃、meta 从实际原始事件重建的事实，不编造测试重跑或缺失的回执。覆盖意见要求补真实配置化 router200、并发 initial 与丢响应重试。
- economy 文档/Skill 片首轮 PASS；错误的 TC 计数、时间戳推断、`Authorize` 前缀论据均已撤回，不按这些错误建议改源码/配置。其一次清单加法“10+8”未采纳；实际 manifest 为9+8=17。
- 作者补负零真实 HTTP RED：两处 raw `repair_limit:-0` / `sensitive_actions[].limit:-0` 均为 POST201 后 head409、exact replay 仍409（预期200）；父+2子=3FAIL/0PASS/0SKIP/exit1。最小修复后同测试3/3；原签名 payload/source bytes 未改写、不转float64，在严格类型/范围校验后按精确整数值比较。边界新增并不冒称分别曾 RED；一次中间 fixture guard 失败也保留。
- P2 只改3文件（head实现、head HTTP测试、实际router测试），原17文件其余14/14不变。增加真实配置化 `NewRouterWithOptions` POST201→head200、并发同/异raw single head、提交后丢响应重试与精确fixture清理。没有按前缀扫删既存测试历史。
- 作者P2后：head打乱count2=210/210，Auth选择count2=14/14，治理组合count2=344/344，实际router count2=10/10，拒消费2/2；均exit0/0fail/0skip，**各选择有重叠不可相加**。证据 M `validation/initial-head-p2-report.md` / `initial-head-p2-source-manifest.json` / `initial-head-p2-evidence-index.json`，原manifest/失败证据未覆盖。最终专用DB无锁/无其他session，既存38条history逐条hash前后不变，无新增残留。

### P2 后独立复核与精确 fixture 清理

P2 后非作者 strong 静态 PASS（含严格类型/精确整数、并发/lost-response接缝和实际router200）；balanced 第2轮独立复跑治理172/172（top30+sub142）、实际router5/5、拒消费2/2，均exit0/0fail/0skip，明确关闭负零与两个覆盖意见。报告 M `validation/20261024T121609Z-aifi45-review2-report.md`。丢响应证据只是 response-writer `io.ErrClosedPipe`，不是 TCP断线、SIGKILL或分布式exactly-once。

该次组合又暴露4个此前相关fixture留下新的approval历史；38条head旧历史未变，但4条非head测试记录留存。故没有把测试计数绿化等同于清理完整。balanced随后成为这项**仅测试**的作者，在相同change内补共享helper精确清理，不开quality-debt：

- 仅201新建响应、非reused，按exact workspace/CR/stage/decision及response signature/source digest定位唯一approval_record.id并登记t.Cleanup；200/409/既存历史不登记，零行/多行硬报。删除再约束exact id+scope，禁止按workspace/CR前缀扫删。
- 四个原测试使用unique CR；已占用历史硬报，不预删除；外部test包仅经 `_test.go` bridge走相同guard，产品无依赖。
- 真实cleanup RED为子测试201成功后父测试查到该确切id残留count=1（2RUN/1PASS/1FAIL/0SKIP/exit1）；最小GREEN同测试2/2。一次外包看不到未导出helper的编译失败保留，0 events不算RED/GREEN。
- 修复只涉及6测试文件（其中新 `execution_fixture_ownership_test.go`）；与原17文件不重叠，合计本轮源码范围**23文件**，产品P2 manifest仍17/17匹配。CUSTOM #164/M11索引登记。作者4旧测试+head115/115、实际router5/5、拒消费2/2均exit0/0fail/0skip，不与其他组合相加。
- baseline 42条（38+原4）逐条id/hash不变，aggregate SHA256=`a3c26e5cb2927a88b01e74c2b07a0837ceef44daada4e18448db8097f2346f19`，0新增/0删除，不手工抹去旧残留；最终锁/session0。证据 M `validation/20261024T122543Z-aifi45-review3-fix-report.md` 与 `...-source-delta-manifest.json`。
- 非作者strong再次仅对6测试增量静态PASS；此前产品PASS维持。为避免这位balanced作者自检冒充独立结果，另开同档新子会话作最终动态复跑；其第一次到轮次上限只完成准备、未跑测试，明确记INCOMPLETE，不计PASS，随后继续实际执行。

### 非作者最终复跑

新 balanced 会话实际执行后给本片测试 PASS；第一次只准备的 INCOMPLETE 不计结果。证据目录 M `validation/final-tiered-20261024T123249Z/`（每条命令的 raw/meta/stderr、baseline42前后、锁/session/残留、report）：

| 范围（均 count1） | 顶层RUN/PASS | 子例RUN/PASS | 总RUN/PASS | FAIL/SKIP/exit | 墙钟/包耗时 |
|---|---|---|---|---|---|
| 治理组合 `^(TestExecutionAuthoriz\|TestExecutionGrantCheckAgainstRealCrctlCLI\|TestDaemonAuthenticatedDeliveryRunsCrctl\|TestDaemonFetchesAndInstallsExecutionAuthorization)`，shuffle | 31/31 | 143/143 | 174/174 | 0/0/0 | 7.243s / 5.004s |
| 实际 router `^TestExecutionAuthorizationHeadRouter` | 2/2 | 3/3 | 5/5 | 0/0/0 | 4.504s / 1.912s |
| daemon 两项继续拒消费 | 2/2 | 0/0 | 2/2 | 0/0/0 | 4.064s / 1.713s |

组合已实际选中新增 `TestExecutionAuthorizationCreatedRecordCleanupAtSubtestEnd`；raw非零、stderr全空。表内 `\|` 仅为Markdown转义，准确argv在meta。

baseline42（ID+内容摘要PSV）前后完全一致，PSV SHA256=`25a91fe323a424b30af7c74dda56f9acb6305dfcf094e63cb252851ed2d18599`；该序列化口径与前轮JSON aggregate不同，不横向比较两种hash。approval_record总数83→83；排除baseline IDs后新增history0，其他fixture实体新增0。只按created_at cutoff曾误报1条“新增”，实际为baseline里既存未来时间行，已通过ID差集核明；不靠时间戳隐藏/判定残留。锁/session最终0、迁移仍671/642；没有扫删或访问共享库。

强代码审查（产品P2及test-only增量）静态PASS，最终balanced非作者动态PASS，economy最终增量文档PASS（核对23文件、#163–164/M11、174/5/2、baseline42与历史总数83两种口径）。三路可检查会话分别为 `01a16dc0-e380-77b9-a3c5-0e96526fedda`、`01a16de4-49d7-77b9-a3c5-0ea43f97175b`、`01a16daa-e95e-77b9-a3c5-0e948b070c2f`，请求档位与前表一致，actual仍unknown。不把这些局部PASS当BUILD/Gate3通过。

## 实施状态

- 已完成：前置核验、实际分层委派、T/M 组件基线、wire §3.1、持久化 initial head 第一段、642隔离迁移/sqlc生成、真实RED→GREEN与P2补正、test-only精确fixture清理、strong静态与非作者balanced最终动态复核；CUSTOM #163–164/M11索引已登记。本轮源码范围23文件（17+6）。
- 主线程核查：23文件gofmt无输出/exit0，scoped diff --check exit0（仅autocrlf行尾提示）；四项quality/binding原bytes hash仍匹配恢复观测。`M validation/resume-supervisor-final-check.json` 汇总23文件规范化SHA、17/17+6/6匹配、独立原始事件174/174/0F/0S、5/5、2/2和实际exit0；两源码仓main/HEAD未推进、staged_paths=0。末轮economy文档PASS，不代替业务验收。
- 原生 `validate` / `canon verify` 两仓均exit0；verify各2/2是proposal结构检查，不是49TC。AND警告仍T2/M1（文件聚合口径），不修改已批准spec凑绿。
- 仍未完成：签名 revoke/extend 链、可信 claim、每 repo 当前绑定、隔离权限域、不可删 activation、legacy 防降级、T 消费与永久派发、完整49TC/14类失败检查。下一段revoke仅细化设计，尚未实施或扩展T verifier。不得据本轮组件结果勾整片或推进 Gate 3；未commit/push/真实CR试点/部署。
