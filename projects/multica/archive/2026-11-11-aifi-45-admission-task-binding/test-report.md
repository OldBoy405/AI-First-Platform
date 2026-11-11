# AIFI-45 admission-task-binding — BUILD 测试报告（C7，2026-11-11）

> 范围：只陈述本轮**实际执行**的检查，未执行的写「未验证」。Gate 3 曾于 17:54 确认；proposal 修订、返修及受审文档勘误后，Gate 1（19:11:30）、Gate 2（19:14:13）已重新确认，Gate 3 待重新确认。未提交、未推送、未部署。

## 一、结论

准入判定已按「任务 + 代次」绑定：每个受保护动作只认自己锚点 task 当前 generation 的回执和该 task 自身的 effect 链，不能借用他 task、旧 generation 或同 CR 的其他回执。首次派发锚在 run 的 source task（不要求节点任务预先消费），节点完成锚在节点自己当前的 task（没有则用 source），人工门锚在 source。真实 consumption 路由提交后不唤醒；两次真实发现后恰好派发一个首节点任务且重复发现不重复。返修后 10 个新增 TC 已通过，整组一次性库回归 23 个选择 **292 PASS / 0 FAIL / 0 skip**。当前输入的同次证据运行 `atb-repair-20261111191701` 为 **11/11**；CI 检查无错误、有一条范围启发式警告（见第八节）。

**上线前置（未验证，必须在部署前做）**：节点任务只有在 node agent 取得 binding proof、daemon 在退出后的 defer 里写入回执时才有回执。本报告没有在真实 daemon + agent 上验证。若生产节点任务从不产生回执，该 run 会停在 `wait_reason=admission`，这是预期的 fail-closed。部署到会跑真实架构/需求 run 的环境前，需用真实 daemon 和 agent 跑一次架构 run，确认节点任务回执出现且节点推进。

## 二、新增 TC 覆盖（planned 10 + 回归 1 / actual 10 + 1）

| TC | Scenario | 入口 | 结果 |
|---|---|---|---|
| TC-ATB-001 | SC-ATB-001 | `TestTC_ATB_001`：TaskID 空/畸形返回 `ErrAdmissionInvalid`；缺任务行、跨 workspace、runtime 或 dispatched_at 为空时返回 `WAIT_CONSUMPTION`，缺行和空 generation 用例先放入完整目标链再破坏单一字段 | PASS（7） |
| TC-ATB-002 | SC-ATB-002 | `TestTC_ATB_002`：他 task、旧 dispatched_at、旧 runtime 或他 CR 的回执不放行；错 CR 用例先放入目标链，再放错 CR 与正确 CR 回执 | PASS（5） |
| TC-ATB-003 | SC-ATB-003 | `TestTC_ATB_003`：锚点 task 自身缺 settlement、verdict、cursor 覆盖或 command 时等待，补齐后放行 | PASS（5） |
| TC-ATB-004 | SC-ATB-004 | `TestTC_ATB_004`：载荷畸形、effect 或 scope 错误、`store_id` 或 `lineage_id` 单独错、command digest 错时等待；缺头、拒绝头与可信正例按各自原因判定 | PASS（10） |
| TC-ATB-005 | SC-ATB-005 | `TestTC_ATB_005`：节点自有 task（架构、需求各一）；source 或他 task 已消费不放行；retry 新 task 不被父 task 回执放行；自己的回执放行，成功后重复调用不改节点整行及任务数 | PASS（11） |
| TC-ATB-006 | SC-ATB-006 | `TestTC_ATB_006`：无自有 task 的节点与人工门锚 source；他 task 已消费不放行；缺/畸形 source 返回 `RUNNER_AUTHORITY_MISMATCH` | PASS（9） |
| TC-ATB-007 | SC-ATB-007 | `TestTC_ATB_007`：架构与需求首次派发；他 task 消费不放行，source 消费后恰好入队一次，且入队 `SourceTaskID` 等于锚点 | PASS（3） |
| TC-ATB-008 | SC-ATB-008 | `TestTC_ATB_008`：真实 `Start*` 建 run、真实 binding+consumption 路由 201、无唤醒时节点任务仍为 0，第一次 `ResumeActiveRuns` 恰 1 个首节点任务，第二次计数和任务 ID 不变 | PASS（3） |
| TC-ATB-009 | SC-ATB-009 | `TestTC_ATB_009`：节点任务运行中经真实路由消费，完成后经发现推进并派发后续节点；对照用例中未消费的完成任务不推进也不派发 | PASS（3） |
| TC-ATB-010 | SC-ATB-010 | `TestTC_ATB_010`：同 generation 重放 200/`changed=false`；新 generation 回执 +1，command/verdict/settlement +0，准入恢复 | PASS（1） |
| TC-RUN-003 | SC-RUN-003（回归，MODIFIED） | `run-routes`：锚点 task 的 effect 未提交前只等待，既有断言保留 | PASS（16） |

## 三、切片验证（B3.4）

| 切片 | TC | 覆盖 | 新增测试 | 备注 |
|---|---|---|---|---|
| 1 | TC-ATB-001～007 + TC-RUN-003 | 8/8 | 50 | decider 草稿 RED/GREEN 由 balanced 子代理完成；调用方迁移后既有 fixture 随之调整（见第五节）；TC-ATB-005～007 在调用方迁移后补写，未单独做 RED，用变异检查证明可判别 |
| 2 | TC-ATB-008～010 | 3/3 | 7 | 真实路由 + 真实发现；节点任务状态由测试直接置为 completed（daemon 回报不在范围） |

两个切片此前已在 `.stdd.yaml` 登记完成。TC-ATB-005 的返修补充断言已先 RED、后 GREEN，并重跑整组选择；当前同次证据覆盖 11/11，CI 确认两个切片均有验证证据。

## 四、回归与构建

返修后整组 `selections.json` 在一个 supervisor 自建的一次性容器中运行，每个选择使用独立数据库；容器为 tmpfs、仅 127.0.0.1，结束后释放 `remaining=0`：

| 选择 | pass / fail / skip |
|---|---|
| atb-001～010 | 7/5/5/10/11/9/3/3/3/1，均 0 fail / 0 skip |
| run-routes | 16 / 0 / 0 |
| run-admission-support | 55 / 0 / 0 |
| run-root-and-dispatch / run-daemon-contract / notice-routing | 11 / 18 / 9，均 0 / 0 |
| channel-migration-up / down / reapply | 19 / 22 / 15，均 0 / 0 |
| channel-protocol | 46 / 0 / 0（需设 `AIFI45_TOOLS_ROOT` 指向 sibling tools；不设会因跨语言向量失败，与本 change 无关） |
| wp4-original-mapping / wp4-concurrent-replay | 1 / 1，均 0 / 0 |
| m005-consumption-effect | 20 / 0 / 0 |
| governance-identity | 2 / 0 / 0 |
| **合计（23 个选择）** | **292 / 0 / 0** |

`go build ./...`、`go vet ./internal/governance ./cmd/server` 退出 0；`run-selection.test.mjs` 5/5、0 skip；新增和改动的 Go 文件 `gofmt -l` 无输出。`cmd/server` 整包另跑一次 659 / 0 / 0。

返修前整包 `go test ./internal/governance`（一次性库）有 **48 个失败**；HEAD 基线（`git archive HEAD` 导出副本、同样的一次性库）失败数也为 48，pass 1258；当时变更后 pass 1326。此次对比没有逐项核实全部失败名称，不能仅凭失败数相同断言失败集合完全相同。

返修后的当前同次证据运行：`stdd agent verify admission-task-binding --change … --run atb-repair-20261111191701` 为 **11 passed, 0 failed**（CP-ATB-001～010 + CP-RUN-003）；同 run 的 `stdd ci check-failures` 为 11/11，独立 `validate_current_evidence` 也返回 11 个 TC、无问题。按用户授权，只重跑这 11 条证据检查，未再次运行全部 23 项。返修前 `atb-evidence-…` 的 11/11 保留为历史结果。`authorized-runner` 是证据计划的从属 spec，应经主 task `admission-task-binding` 一并执行。

## 五、既有 fixture 调整（保留断言）

按 design.md 决策 7，既有准入 fixture 只改「哪个 task 被消费」与真实 task/generation 行：`execution_admission_test.go`（回执改由 task 行派生并校验插入行数，新增 `admissionAnchorTask`）、`execution_admission_{gate,enqueue,requirement_enqueue,human_gate,lock,cleanup}_test.go`、`execution_consumption_effect_test.go`、`cmd/server/execution_run_003_test.go`。没有删除任何队列数、节点状态、等待原因、签名、归因、链行数或幂等断言，没有新增 skip。移除了「`admitPlatformConsumption` + `admitTrustedConsumption` 重复写回执」的双写。

## 六、变异检查（证明测试能抓住错误实现）

每次均先备份并在检查后按哈希恢复，随后复测通过。

| 变异 | 结果 |
|---|---|
| 节点有自有 task 时仍借用 run 的 source 作锚点 | atb-005 0 pass / 11 fail；atb-009 对照用例失败（`unconsumed first node` 被放行） |
| 架构首次派发的锚点改成与入队来源不同的 task | atb-007 2 fail（source 已消费仍等待） |
| decider 不核对任务行/generation、回执 CR、`store_id` 或 `lineage_id`（子代理逐项做；原测试在这些变异下仍通过，加强后的子用例失败） | 全部被新增子用例捕获 |

## 七、三路评审（`stdd config models` 已读，派发前重读）

| 代理 | 档位 | configured | requested | actual |
|---|---|---|---|---|
| code | strong | GB-JP/kimi-k3.1-pro:max | 同左（model 与 effort 均传） | unknown（无运行元数据） |
| test_config | balanced | OpenAIPersonal/gpt-6.1-terra:xhigh | 同左 | unknown |
| docs_skills | economy | Gobao/deepseek-flash:high | 同左 | unknown |

处置：
- **code**：无发现。
- **test_config**：6 条 MAJOR + 1 条 MINOR。已采纳 4 条：原先加强任务/generation、跨 CR 和 scope 的 3 条；另补 SC-ATB-005 成功后重复调用的幂等测试并修复实现。此前误把第 4 条判为范围外，现予更正：原规格和测试计划均要求它。返修测试先 RED（架构与需求两例均重写 `completed_at`），修复后 atb-005 为 11 PASS、0 FAIL、0 skip。其余两条未扩大本次返修：SC-ATB-006 目前只直接测试共享 gate，未逐个运行具体复审/投影调用点；fixture 的跨测试同库隔离未单独验证，整包失败数量比较不能证明失败项完全相同。MINOR 的函数名已勘误。
- **docs_skills**：1 MAJOR + 7 MINOR。已补 `pending-adjustments.yaml` 的更新时间与字段、在本报告记录变异检查；用户同意后，已勘误 `test-plan.md` 的函数名、解析器措辞和测试顺序，标明 `design.md` 未验证项的设计期语境，并修正 canonical 索引的四个 spec 路径。这些受审输入变动后，Gate 2 已重新确认，当前输入的同次证据也已重跑。
- **返修聚焦复评**：code（strong）与 test_config（balanced）均无发现；docs_skills（economy）指出本报告 TC-ATB-001～004 的描述与测试实际映射不符，已据测试修正。复评还指出原 proposal 要求持锁事务内解析锚点，与 Gate 2 后的调用方快照设计不一致；用户授权后已将两处 proposal 表述同步为快照设计，原文保留在 design-adjustments.yaml；Gate 1、Gate 2 已分别重新确认。复评对 atb-005 仅计叶子及顶层而漏计两个 pipeline 父用例；本次 supervisor 实际输出为 11 PASS。
- **返修后范围复核**：主会话对 17 个已跟踪修改和 3 个新测试做 diff 与新增 skip/调试残留扫描；唯一被替换的 fixture 插入错误断言同时增加行数检查。另一次 strong 代理只读检查了除 CUSTOM.md 外的 19 个当前文件，未发现问题；该代理无命令工具，未独立核对 HEAD 删除行，其限制不能当作完整 diff 对照。此前全量评审与本轮代码/测试聚焦评审结果仍保留。

## 八、失败模式检查（C4）

- 当前 run 的 `stdd ci check-failures`：9 PASS、1 WARN、0 SKIP、0 FAIL；CLI 确定性子集覆盖 10/10，TC 当前执行覆盖 11/11，两个切片均有证据。Go 项目已声明无 pytest-cov 覆盖率义务。
- (b) 范围警告：CLI 用 `git diff --stat HEAD~1` 和路径名启发式计出 25 项，并非当前工作树的精确文件数；其中 `instance.mjs`、`instance.real.mjs` 等 7 个仅来自前一个已提交的 supervisor 变更，三份未跟踪新测试又不在该 diff 中。当前业务仓为 17 个已跟踪修改及 3 个未跟踪测试；这些属于本 change 的实现、选择器、fixture 和登记，交付时仍须逐文件隔离并确认。
- 语义复核（与上述 CLI 确定性子集区分）：
  - (a) 路径、函数与选择名称：canonical 四条 spec 索引、TC-ATB-008～010 与 11 条 CP 已对照实际文件；计划预览通过。
  - (b) 范围：已核对当前 20 个业务仓文件及前一提交混入警告的来源；交付清单仍需人工确认。
  - (c) 级联错误：返修聚焦代码复评未发现新增吞错；fixture 的回执插入错误检查保留并增加行数检查。
  - (d) 上下文：原 proposal 与快照设计冲突已修订并经 Gate 1、Gate 2 确认；原文留档。
  - (e) 工具：Gate、证据和 CI 均用现行 STDD 入口；数据库由 supervisor 自建并释放，未使用外部 admin 连接。
  - (f) 运行时：返修后 23 项回归与本次 11 CP 通过；真实 daemon + agent 未验证。
  - (g) 管线：真实路由到 `ResumeActiveRuns` 的路径由 TC-ATB-008/009 验证；不声称生产 daemon 链已验证。
  - (h) 内容：TC-ATB-001～004 报告映射、索引路径及设计期措辞已按实际材料修正。
  - (i) 指令：未新增 skip；首次派发使用 source，未新增 wake 或 schema/路由/daemon/T/crctl 改动。
  - (j) 覆盖：两个 capability 的 11 个 TC 均有当前 run 证据；Go 代码行覆盖率按项目配置不适用。
  - (k) 契约：当前 CI 对两个 capability 的静态契约检查通过；真实跨系统边界见 (n)。
  - (l) 锚定：proposal 非 critical，CLI 判定不要求额外锚定。
  - (m) Agent CP：当前同次执行 11/11 通过，未把预览作为执行。
  - (n) 跨系统：**未验证**真实 daemon + agent 及 T 的端到端交互；T 集成不在本 change 范围，daemon 节点回执列为上线前置。
- 项目经验 EXP-2026-0001～0005 已对照；既有锁边界和一次性资源清理风险均在设计或本报告列明。本轮未将经验提升为 verified，未新增经验条目。

## 九、已知问题与未完成项

| 项 | 原因 | 影响 | 计划 |
|---|---|---|---|
| 生产节点任务回执未在真实 daemon + agent 上验证 | 本轮只用一次性库内的真实路由；未接真实 daemon | 若生产节点任务从不产生回执，run 停在 `wait_reason=admission` | **上线前置**：真实 daemon + agent 跑一次架构 run；DELIVERY 待办 |
| 任务行与头锁不是一个原子边界 | 头锁只保护授权头、回执、effect 链；任务行不在其中（design「头锁保护什么、不保护什么」） | 调用方持有的锚点快照可能略过期；准入时新选任务可能已不同，不能声称选择和准入原子 | 已接受并写入 design 与 proposal；不加 task 行锁、不改锁序 |
| 派发成功后 `wait_reason=admission` 不被清除 | 既有行为（HEAD 同样），spec 未要求清除 | 节点已派发但详情里仍显示 admission | 不处理；如需改，另开 change |
| SC-ATB-005 成功后幂等 | 原实现会重写 `completed_at`；此前错误判为范围外 | 已补整行及任务数断言，并在共享准入更新处修复 | 返修后整组选择和当前同次证据通过；待 Gate 3 确认 |
| 整包 `go test ./internal/governance` 的失败 | 返修前与 HEAD 基线失败数均为 48；未逐项比对失败集合 | 不据相同计数断言失败项完全相同 | fork CI 问题已登记为后续 change；本次完整 selections 另行通过 |
| 代码跑与回写路径只共享 gate 规则，无端到端声明 | 范围外 | 无端到端证据 | 不处理 |
| 周期发现仍不扫描代码 run | 范围外 | 无 | 不处理 |
| 索引及文档勘误（见第七节） | Gate 2 清单内文件已按用户同意修正 | 原批准记录保留；Gate 2 已重新确认 | 待 Gate 3 重新确认 |
| 原 proposal 的持锁解析表述 | Gate 1 原约束与后来确认的调用方快照设计不一致 | 用户授权后已同步两处 proposal 表述，原文保留在 design-adjustments.yaml | Gate 1、Gate 2 已重新确认；待 Gate 3 重新确认 |

## 十、环境与清理

当前 11 CP 各由 `scripts/aifi45-disposable` 创建一次性实例；每条命令退出 0 包含完整 ID 与标签校验后的释放检查。执行前后容器集合均为 `multica-postgres`、`multica-backend`（均已停止），卷集合均为 `multica-pgdata`；未操作这些或任何未知资源。前后快照不能单独证明执行期间没有其他进程瞬时创建并删除资源。被测代码：HEAD `d5b348a17` 加未提交改动。
