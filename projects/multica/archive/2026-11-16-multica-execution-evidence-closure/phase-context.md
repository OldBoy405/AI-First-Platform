# Phase Context - SPEC

## 确认与阶段状态

- Change：2026-11-16-multica-execution-evidence-closure；业务仓 multica，记录项目 projects/multica，模式 standard。
- Gate 2 经用户原话「批准 Gate 2，继续推进」确认，CLI 回执时间 2026-11-16T01:41:24。SPEC completed；BUILD pending，进入前按 Skill 选择执行模式。
- Gate 确认不授权 Git 提交、push、部署、真实 agent、依赖安装、权限调整或未知运行资源操作；tools BUILD 仍暂停。

## 已锁定的关键决策

- 三个恢复入口在原 run 锁内重读活动对象并核对 ID；对象消失或切换时本次无效果返回，下一次既有唤醒取新 run 锁后推进。不新建嵌套锁、无限重试或生产测试 hook。
- 复用一个真实库 selection：两个原锁测试、一个三入口身份矩阵、TestMTick003，完整四项 expected；新增顶层测试用普通循环，保持池4、串行、取消及一次派发保证。
- 事件边界只接受已核实的 OutputType/FailedBuild 元数据；未知形状、失败、skip、截断和缺测仍拒绝，不改无 expected 的既有行为。
- 单一已发布 tools pin 固定为 7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1；rules.json 加入现有必需文件检查，backend job 明确引用同一 checkout。生成器只 --check，漂移停止报告。
- 一次真实 CI 验证最终业务 SHA、既有 Test/对账/admin 步、六个固定快照测试及真实 rules.json 日志；旧提交、本地或 fixture 通过、skipped 和旧 N/A 不能替代。
- CUSTOM 只追加本次真实追溯与当前前三数；保留历史、CRLF 和稳定编号。第四数明确未决，本轮不猜口径，不要求数字单调增长。

## 用户关注点与证据边界

- 用尽可能少且职责清晰的检查支撑有限可验证保证，不逐异常补兜底或新造检查框架。
- 7个需求/7个场景，5高置信度、2中置信度；4个TC（P0三项、P1一项），2个命令CP及2个required manual。
- validate、proposal validate、canon verify、agent verify --dry-run通过；23个业务输入均可定位。独立文档审查未发现确定遗留缺陷。
- (l)锚定L3>=L1通过；全量只读失败模式检查仍显示执行证据0/4，不能宣称产品验收通过。
- SPEC未执行产品测试或真实CI、未修改业务代码。实际CI仍可能受账单/凭据/独立发布授权阻塞；部署规则副本在仓外，不在本次覆盖范围。

## 产出物

- design.md、test-plan.md（含同次执行证据计划）。
- canonical/proposals/2026-11-16-multica-execution-evidence-closure.yaml。
- canonical/specs/code/2026-11-16-multica-execution-evidence-closure.yaml（capability为governance-runner-run-lock）、selection-reconciliation.yaml、ci-backend-environment.yaml。
- canonical/specs/agent/2026-11-16-multica-execution-evidence-closure.yaml；task与证据计划一致。
- Gate 2由CLI生成specs/governance-runner-run-lock/spec.md、specs/selection-reconciliation/spec.md、specs/ci-backend-environment/spec.md；不手改Human View。
- .stdd.yaml的Gate与阶段记录由CLI更新，不手改、不代签Gate3。

## BUILD 进展与暂停边界（2026-11-16）

- SPEC 阶段记录原样保留；现已由 CLI 进入 BUILD。用户选择全自动长程并确认范围内预授权，仅当前 change 的 long_range 字段有精准 Edit 例外，未改 Qoder/Claude 权限。
- 切片1（TC-MEC-002）完成：执行代理报告 RED 96/4/0，GREEN 101/0/0；主会话审查八文件实际 diff 并独立复跑 CP-MEC-002，101 PASS、0 FAIL、0 SKIP，git diff --check 通过。三个新增可运行检查为两个命名顶层测试及既有缺文件矩阵中的 rules.json 分支。
- SC-MEC-003：旧六字段和合法 OutputType 通过；非法类型/值/位置、未知键、FailedBuild/fail/skip、截断/无包终态/错顺序保持 blocked，结果不泄漏合成秘密。SC-MEC-004：完整四测试 pass=4；逐个移除整项测试事件时，即使 exit=0/pass=3 仍 blocked=SELECTION_MISMATCH。SC-MEC-005：两个消费者同 pin、backend 同 checkout 的规则路径、诊断/完整性/生成检查顺序被钉住。
- 固定 tools HEAD 与 pin 都是 7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1；真实完整性检查4文件通过，transitions --check=54 条，gate-nodes/四registry --check 通过。这是本地合同验证，不是真实 CI。
- CLI 已登记切片1：tc_coverage=1/1、new_tests=3、verified_at=2026-11-16T02:06:45.731334。其余切片未完成，不手改切片状态。
- 切片2前置阻塞：Go 1.27.1 windows/amd64、CGO_ENABLED=0、PATH 无 gcc；实际 go test -race 在测试运行前 exit=2，报 requires cgo。未安装依赖、未用非 race 替代，未创建测试库/容器、未改三个 Go 入口或编写未验证身份矩阵。
- governance-run-lock 已要求完整四项，但 TestReconcileRunIdentity 尚未实现；当前真实选择组不能报通过。当前成果是未提交的在途改动，不是可交付完整闭环。
- CUSTOM 已登记 #343、M31 索引/标题 21 行、当前 change 索引行与 2026-11-16 测量行；前三数实测 629/1718/785，第四数未决。CRLF 1124/裸 LF 0，#343 六单元格；工作树计数不含 scripts/.github 修改及未跟踪文件，人工 TC 尚未确认。既有 #338 竖线形状与 HEAD 相同，未顺手修。
- 真实 CI、required manual、全量质量及三路最终技术评审未完成；未生成独立同次验收 run，不展示 Gate3。提交/push/实际 CI/部署未授权，tools BUILD 继续暂停；仓外部署规则副本未覆盖。
- 已写 pending-adjustments.md（race/真实 CI 阻塞与第四数未决）与 test-report.md（BUILD 暂停快照，非 Gate3 报告）；agent verify --dry-run 通过，23 输入中 9 个相对 HEAD 有差异，均为本轮业务文件。

## BUILD 切片2完成（2026-11-16，cgo/race 与发布/CI 已获用户授权）

- 用户原话「授权 cgo/race 环境，以及独立的发布/CI」解除切片2/4 的环境与发布阻塞。已建立 cgo/race：mingw-w64 gcc 16.2.0、CGO_ENABLED=1，go test -race -c 编译通过；tools HEAD 与 pin 一致 7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1。上文切片2 cgo 阻塞已解除。
- 切片2（TC-MEC-001，SC-MEC-001/002）完成。三个生产守卫落在 runner.go/runner_requirement.go/runner_code.go：锁内重读活动 run 改名 current，保留 ErrNoRows 无效果返回与其余错误传播，current.ID != run.ID 时本次返回，digest/reconcile 仅对同 ID 执行；withRunLock 原语未改。
- 新增 TestReconcileRunIdentity（runner_run_lock_test.go）：普通表循环，三入口×unchanged/changed/no-active 共九例，无子测试事件；独占池 MaxConns=4，AcquireCount 增量 architecture≥3、requirement/code≥2 证明到达取锁边界；changed 以明确 created_at 顺序造 B、持 B 锁再释放 A，断言第一次唤醒 B 任务=0 且状态 running，下一次唤醒推进 B 恰好一次。复用既有合法 fixture 与假 enqueuer，不加生产 hook。
- TDD：先 RED（git apply -R 撤销守卫，非 race 下 architecture changed 报「first wake advanced B under A's lock (1 tasks), want 0」），再恢复守卫 GREEN。GREEN 期间修两处夹具缺陷（requirement inputs 补 source 空串；跨入口 quality-reviewer-agent 同名不同 id 冲突，按 setupRequirement 既有 clearAgentNameCollisions 防御在每例 setup 前清名），生产守卫未因夹具修复改动。
- CP-MEC-001 经既有 run-selection 一次性库执行 -race -count=1：PASS governance-run-lock pass=4 fail=0 skip=0，NODE_EXIT=0，复跑两次一致；完整四项 expected 对账 matched。四个顶层测试为两个原锁测试、TestReconcileRunIdentity、TestMTick003。
- CLI 已登记切片2：tc_coverage=1/1、new_tests=1。业务 diff 仅四个 Go 文件 +241/-11；未改任何受审 Gate2 文档，spec 指纹未过期。
- 边界：本地仅证明锁/身份/池4 这一 selection；governance 全量与 backend 回归由切片4 真实 CI 权威验证，不在本地冒称。required manual（TC-MEC-003/004）、三路最终评审、独立同次验收 run 与 Gate3 仍未完成，不代签。

## BUILD 切片3台账完成（2026-11-16，MEC-09/10）

- CUSTOM 复登（MEC-09）：切片2 的三入口锁身份守卫属 M4「Runner 与 registry 生成物」（主冲突面 runner*.go，与 #342 withRunLock 同模块），新增稳定 ID #344，不改写已归档的 #342。M4 模块索引与明细标题 29→30 行；CR 索引行更新为 #343–#344、状态「切片 1/2 已验证」、模块 M31+M4；#343 追加后续指针更正「TestReconcileRunIdentity 与守卫尚未实现」为已实现并经 race GREEN。历史行、稳定编号、CRLF 全保留。
- 计数复测（MEC-10）：按《核对命令》在已跟踪工作树实测 629 文件 / 1722 命中行 / 789 AIFIRST 行；HEAD 294d793a91c8f1dce2f97a549b41cf468e562b1a 未变，5816 个跟踪五类文件无增减；测量时间 2026-11-16T03:08:39.005+08:00。相对上一行（629/1718/785）+0 文件 / +4 命中行 / +4 AIFIRST，逐项落在四个 Go 文件各 1 条 // AIFIRST: 守卫标记；切片1 八个离线文件在 scripts/.github 计数范围外，增量 0。第四数 packages/ 仍未决、不沿用 314。新测量行已落 CUSTOM 表尾，未 stage。
- 台账形状核验：CRLF 1126 / 裸 LF 0，git diff --check 通过；#344 六单元格（7 竖线）、测量行七单元格（8 竖线）、CR 索引八单元格（9 竖线）；CUSTOM 累计 diff（含切片1）+12/-5，删除行仅 M4/M31 索引与标题、backend-tests-green CR 行（后者为切片1前既有更新），无历史明细行被删。
- 人工确认边界（MEC-11）：TC-MEC-004（台账事实）与 TC-MEC-003（真实 CI）同为 required manual；stdd agent confirm 计划级全有或全无一次性，故两项须在切片4 真实 CI 完成后合并为一次用户确认，再一并 CLI 登记切片3/4。当前不单独确认、不代签、不提前登记切片3。
- 切片4 授权：用户「授权 cgo/race 环境，以及独立的发布/CI」已授予提交/push/真实 CI（MEC-12）；Gate3 与人工确认仍须用户原话。下一步进入切片4 与 Part C 质量验证。

## BUILD 切片4 与 Part C（2026-11-16，提交/push 完成；真实 CI 账单阻塞）

- 提交/push（MEC-12/13）：13 个业务文件按名 stage（非 git add -A），提交 `f8a23564a0b33ffb36cb535de27d4b515447e255`（+430/-24，conventional commit＋STDD 尾注），push `294d793a9..f8a23564a main->main` 成功。工作树提交后干净。C3 逐文件 diff 审查通过：无调试残留/死代码/注释旧逻辑，与 spec 一致。
- 真实 CI（TC-MEC-003 权威）：run **43752944966**（headSha=f8a23564a，event push）conclusion=failure。**根因＝GitHub 托管 runner 无法分配（账单/额度），非代码失败**：changes job runner_id=0/runner_name=""/steps=[]/2 秒 failure，backend/frontend 门控同样零步骤，backend-tests/transitions-contract-check/frontend-*/sqlc-check 全 skipped，--log-failed 报 log not found。ci.yml:9-10 台账 #113 记载私有库免费 2000 min/月、实测需 3652 min/月；近期 916f57318 06:33Z success 其后全部 instant-failure 佐证额度耗尽。六测试/真实 rules.json/backend/admin/对账/两个生成 --check 均未执行，SC-MEC-006 未验证。AI 无权改支付/额度，未尝试；待用户解除后对同一 SHA 重跑。
- Part C 本地质量（run **2d5d4330-6347-4df8-aa7d-602b0269c651**）：C1 三路评审（代码 strong/测试 balanced/文档 economy）均 NON-BLOCKING，pending-adjustments 陈旧指针已补、test-report 已刷新；C2 agent verify 两命令 CP PASS（CP-MEC-001 一次性库 -race pass=4/0/0、实例 4f619816c1c1 已释放；CP-MEC-002 离线 fail0/skipped0＋两新测试），ci check-failures 同 run 8 通过/1 错误（TC 覆盖 2/4，缺两 manual）；C4 a–n 全量（CLI 9/9＋人工 b/c/e/h/i/m/n）；C5 无新失败模式（MaxConns=4 池死锁经验被设计预防而非命中）；C6 design-adjustments.md（无受审承诺偏离）；C7 test-report.md 如实刷新。23 输入指纹冻结与提交态一致。
- 当前覆盖：必需 command 2/2（TC-MEC-001/002）；required manual 0/2（TC-MEC-003 账单阻塞未验证、TC-MEC-004 台账已备待确认）。切片1/2 已 CLI 登记；切片3/4 未登记（待人工接受）。
- 暂停边界：TC-MEC-003 为 required manual 且真实 CI 为必需证据，账单阻塞下证据未齐备，Gate3 不具备批准条件，不展示「就绪」框、不代签、不自动批准。已向用户如实报告账单阻塞与本地已验证项，待用户决定（解除额度重跑 CI，或对 TC-MEC-003 验收处置——后者若改 required-manual 地位须按 revision-rules 重审 Gate）。仓外部署 rules 副本未覆盖；tools BUILD 继续暂停；未部署。

## BUILD 延期修订与收口（2026-11-16，用户裁定延期 TC-MEC-003，重审 Gate 1+2）

- 用户裁定（原话「修订计划延期 TC-MEC-003」）：真实 CI 账单/额度短期无法恢复，本轮把 TC-MEC-003 必需证据延期为 not_applicable（接受风险），先收口其余已验证项。这改变受审承诺，按 revision-rules 一轮同步修订 proposal.yaml/md、ci-backend-environment.yaml（REQ-MEC-006 + SC-MEC-006 第三 and）及 spec.md、design.md、test-plan.md（TC-MEC-003 改 not_applicable+reason、矩阵/风险/顺序/第六节计划）；agent spec 核实未变。完整差异一次性展示。上文切片4「待用户决定验收处置」已由本裁定收口。
- 重审 Gate（用户原话「确认重签Gate 1+2」）：Gate 1 confirmed 2026-11-16T10:23:55、Gate 2 confirmed 2026-11-16T10:25:47（dialog）。Gate 2 先因 ci-backend-environment 的 spec.md Human View 漂移拒绝（canonical SHA 95a34ad5 vs 旧视图 7540bc59），删除该派生视图后经 CLI missing→render 重生并确认；canonical YAML 为修订真源，proposal.md 经 canon generate 重生（source_hash 2c674f1250c9d490）。
- 旧证据重跑（新 run **0ccb7130-dbe0-4c0c-b7f4-28aeca9a38a6**）：受审字节变化使旧 run 2d5d4330 冻结修订前 test-plan，作废。agent verify 2 passed/0 failed——CP-MEC-001 一次性库 -race -count=1 PASS governance-run-lock pass=4/0/0、实例 4166e2ba8508 已释放；CP-MEC-002 离线 fail0/skipped0＋event matrix/CI wiring 全断言。23 输入指纹冻结与提交态一致。
- TC-MEC-004 人工确认：用户原话「执行 confirm 并继续后续流程」经 `stdd agent confirm … --run 0ccb7130… --statement` 记录 TC-MEC-004/custom-trace（subject b8d904d4…），AI 未代写结论。台账事实经交付树 f8a23564a 实测复核：前三数 629/1722/789、5816 跟踪五类文件、+0/+4/+4 归因经 commit diff（parent 294d793a）核实四个 Go 文件各 +1 AIFIRST 守卫标记、CRLF 1126/0、第四数未决。切片3 CLI 登记 done：tc 1/1、new_tests 0、verified_at=2026-11-16T11:01:56.826748。
- ci check-failures（同 run 0ccb7130，confirm 后）：9/9 执行、9 通过/0 错误；TC 机械覆盖 4/4。**TC-MEC-003 not_applicable 计入分子是处置完整性，不是执行通过；权威 CI 验证仍未完成，报告/Gate3 显式标延期/未验证/接受风险。** tc-evidence.json：001 pass、002 pass、003 not_applicable（reason 账单阻塞＋用户延期）、004 manual-pass。
- 切片4 不登记 done：TC-MEC-003 延期 not_applicable，沿用前驱惯例（backend-tests-green 含 not_applicable 真实 CI 的 slice 7 未登记，仅 1–6 done），收口经 Gate3 而非把未验证切片标 done。当前 slices_completed=1/2/3。
- 过程文档已收口：test-report.md（新 run、延期、4/4 诚实标注、切片状态、C4 9/0）、design-adjustments.md（§0 记录用户裁定延期＋Gate 重审，原「无偏离」结论保留供追溯）、pending-adjustments.md（BLOCK-MEC-02 延期指针、NOTE-MEC-01 确认更新）、tasks.md（MEC-11 完成、MEC-13 保持未完成/延期、MEC-14/15/16 刷新）。
- CUSTOM 快照时效性：用户裁定 A——第203行与 #343/#344 写作时快照（「未提交、未推送」等）于 DELIVER 回填，不产生额外 commit、不改交付 SHA、计数中性（CUSTOM.md 在仓根不在五类范围）。
- 当前状态：Gate3 确认框待展示，须用户原话批准（--run 0ccb7130），AI 不代签。延期项 TC-MEC-003 权威 CI 验证仍未完成，额度恢复后对最终 SHA 另行验证满足 SC-MEC-006 全部 SHALL；第四数口径未决；仓外 rules 副本未覆盖；tools BUILD 暂停；未部署。
