# AIFI-45 四项建议落地计划（2026-10-30）

> **状态：执行中；不是 Gate 审批。** 用户此前采纳 2026-10-30 的四项建议并要求实施；本次 §3 的 EVD 确认仅是方向与移交，不扩大该实施授权。状态投影仅传错误不足以可靠重放；discussion 没有 terminal CAS，旧 Composio fence 也未移走所有事务前 POST；拆分不解除原 Gate3 依赖。分别见本文 §2.2、§2.3、§3 和 `composio-pretransaction-static-20261029.md`。独立复核请求 strong：`GBClaude/claude-opus-5-5:high`；会话环境记录的配置一致，实际 backend unknown。

**目标：** 推进可信结果合同、独立测试环境与证据交付完整性，闭合可证明的失败处理，并在同一源码快照上对 AIFI-45 现有规格验收。

**架构与输入：** 源码根为 sibling `multica/` 与 `tools/`；本工作区 `projects/` 仅承载 STDD 记录。以 AIFI-45 的 canonical、`tasks.md`、`test-plan.md`、`slices.md`、`pending-adjustments.yaml` 与最新专项证据为准；跨仓协议还须读 tools 侧 `wire-contract.md`。可信结果合同由 `2026-10-29-trusted-verdict-outcome-binding` 两侧 change 负责；Ray 是该案负责人，并非已核实的签发者或信任根。

**本轮只读状态复核：** multica、tools 两侧的 `stdd status 2026-10-22-aifi-45-authorized-execution` 均为 BUILD/in_progress、普通模式；两侧 `stdd canon verify 2026-10-22-aifi-45-authorized-execution --dry-run` 均 exit 0、2/2。该结果仅证明状态和 Canonical 静态一致性，不代表业务测试、隔离能力或 Gate3 通过。

## 全局约束

- 保留现有未提交改动；不得代替人类确认 Gate、提交、推送、部署或操作真实 CR。拆分仅改变工作归属，不修改 AIFI-45 现有 canonical/TC 和 Gate3 要求。
- 历史事故库继续 HOLD；仅在明确授权且确认身份、所有权和隔离边界的新可丢弃环境中运行数据库测试。禁止直接运行 governance 包 TestMain、裸 `make test` 或未经安全评审的 PATH 复现。
- 所有业务验收分别记录真实 RED/GREEN、源码快照、测试命令、退出码、实际 PASS/SKIP 和独立复核；局部通过不标整个 TC 完成。
- 故障恢复、重放及外部副作用须与失败处理一起设计；没有提交、锁或对端幂等/查询能力的证据时，不宣称原子性或 exactly-once。

## 关键风险与验证焦点

1. 签名原字节、调用者自报的 `settlement.kind` 和 task ID 均不独立证明可信许可、身份或 generation。
2. `applyStatus` 先写 CR，再 best-effort 投影；仅返回投影错误会在重放时命中不同分支，不保证补投影。daemon 合成事件 rejected 当前也可能被忽略。
3. Discussion 的 Composio overlay 可能在事务前按 coordinator A 创建，而事务内按 B 授权；远端 POST 与数据库不可简单通过移动到 CAS 后实现原子。
4. 本地合同字段缺失不能证明合法 legacy；严格 YAML 子集不等于完整 YAML 或可信证据来源。
5. RUN-009 的早到、晚到、ACK、可恢复 pending、终态竞争和当前授权须分别验证；平台外评审的待核回退不能替代完整绑定协议。
6. EVD-009 中远端祖先关系只能证明当前目标状态，不能证明是哪次 attempt 造成的；保存前崩溃窗口可能重建 candidate，主体漂移路径可能只看本地标志。既有 receipt 不含真实修复消费或 cycle 依据，helper 测试不能代替事务恢复。
7. EVD-008 的输入对象中有历史摘要不等于历史真实、完整或仍有效；迁移核验后发生撤销、新消费或未决任务变化时，旧核验结果不能直接提交。

## 工作包

### 1. 可信 verdict 合同：Gate1 已确认，SPEC 草案进行中

- **位置：** `projects/{multica,tools}/changes/2026-10-29-trusted-verdict-outcome-binding/`；输入为两侧 `canonical/proposals/` 和本 change 的 `validation/verdict-outcome-contract-20261029.md`。
- [x] 使用指定 change 的原生 `stdd canon generate --type proposal` 生成两侧 Human View；不推进或批准状态。
- [x] 用户直接审阅两侧 proposal/canonical 并回复“审阅确认”；两侧已用 STDD 原生命令记录 dialog Gate1，阶段推进至 SPEC，Gate2/3 仍 pending。Ray 仍是草案列明的负责人，不能据此推断真实签发者或信任根。
- [x] 补请用户确认两侧执行模式：用户回复“确认采用 thorough，全自动长程模式”，两侧已登记 `thorough`；此前的 `standard` 只是初始默认。初步评分、用户原话与只读事实见 `validation/verdict-outcome-pre-spec-evidence-20261030.md`。长程意向不替代 Gate2 和既有 HOLD 约束。
- [x] 两侧已生成 thorough SPEC 设计、行为规格与测试方案草案并经独立只读复核；用户随后采纳隔离裁决、保护名单、效果分离及优先核旧协议四条方向，原文及边界见 `validation/verdict-authority-acceptance-20261030.md`。两侧草案已按方向修订；原 `validation/verdict-outcome-spec-review-20261030.md` 的 SHA 是修订前快照。这不代表 Gate2 准备完成：两侧 agent-spec 仍为 TODO，TC 全部未执行。
- [x] 只读完成一轮既有签名合同可复用性评估，见 `validation/verdict-contract-reuse-assessment-20261030.md`：有部分验签/链绑定构件，现有证据尚不足证明完整业务授权合同；不据此断言无其他生产格式或必须 v2。
- [x] 继续静态核对远端恢复入口、同输入重放及不同摘要，列出候选方案：`validation/verdict-recovery-digest-decision-20261030.md`。用户同意按目标达成但本次待核方向准备修订；候选合同、存量与部署风险见 `validation/remote-merge-recovery-amendment-proposal-20261030.md`。SC-MG-015/016 如修改须先按原合同变更流程审议；假设接线与当前静态函数结果均不是现网事实。两侧 design 风险条目已同步，旧审阅 SHA 为历史快照。
- [x] 用户已确认原 AIFI-45 两侧的限定长程授权，原文和被确认清单摘要见 `validation/aifi45-long-range-auth-confirmation-20261030.md`；两侧根目录 `long-range-auth.md` 均留有指针。原生 STDD 3.0.7 未定义 BUILD 中途启用、CLI 无模式切换命令且 Guard 不允许手改状态；用户明确不另起中途切换变更，因此两侧仍为 normal，未冒称 full_auto。可在原普通模式和限定清单的交集继续；新的 verdict change 仍在 SPEC，不受这份清单覆盖。
- [ ] 生产者、实际签发者、信任根、验证者、命令/主体/generation 关联、旧格式与恢复仍须以权威来源核实；逐条协调已批准的远端恢复合同和实际调用链。范围、计数及发布策略须人审；补齐完整产物并经人类确认 Gate2 后再做涉及合同的实现。
- [ ] AIFI-45 实现和验证默认拒绝的消费侧、readiness 与真实入口；不能用组件签名测试代替 RUN 验收。
- **注意：** 当前生成器的 Human View 未展示 canonical 中的 `constraints`、`non_goals`、`stakeholders`；评审必须同时阅读 canonical，不能把 Human View 当完整合同。

### 2. 失败处理与测试环境

#### 2.1 TMPDIR/PATH

- **文件：** `multica/scripts/test-go.sh`、`go-test-with-agent-cli-guard.sh`、`test-go.test.sh`；事实与安全边界见 `validation/test-go-tmpdir-path-static-20261030.md`。
- [ ] 用户已授权评估/创建独立沙箱；取得独立认可的 OS 级私有隔离、可信 fake Go/CLI、受控 mktemp/rm 与安全清理能力，未知资源保留。隔离能力未获证明前旧脚本复现仍 BLOCK。一次 P1 在启动前因网络配置组合断言 BLOCK，本次专用容器已核归属后清理，受保护资源集合和状态未变；两个只读复核及证据局限见 `validation/tmpdir-sandbox-p1-review.md`。未运行旧脚本或容器内探针，不得将 P1 计为通过。后续只创建不启动的 P1a 草稿及容器内 P1b 草稿仍锁定且未运行，独立审阅均 BLOCK；复核与证据局限见 `validation/tmpdir-sandbox-p1a-recheck.md`、`tmpdir-sandbox-p1b-review.md`。
- [ ] 本轮只读复核发现 P1/P1a 方案仍绑定旧引擎及受保护容器，不能在当前 HOLD 下继续运行；P1b 仅能作容器内辅助观察，不能单独证明宿主隔离。后续应评估不依赖旧容器和旧引擎的隔离机制及本次自建资源清理，不预设宿主已有 VM、网络禁用或镜像；具体资源/命令须另审，无法证明则保持 BLOCK。本轮只查询两个固定系统路径的文件元数据：`C:/Windows/System32/WindowsSandbox.exe` 未找到，`C:/Windows/System32/vmcompute.exe` 是普通文件；没有启动程序、读取系统配置或探测网络。这既不能证明 Windows Sandbox 不可用，也不能证明虚拟化功能、权限或隔离可用。隔离内的 `rm -rf` 边界和 POSIX/Git Bash 的差异仍须各自验证。只读调查 session `01a18d81-1a9d-7468-8217-4aba2d69211d` 请求 `GBClaude/claude-opus-5-5:high`，actual backend 无回执记 unknown。
- [ ] **统一隔离候选（仅设计）**：评估自建、可按本次完整身份销毁的离线 VM，供本节和 EVD-009 使用；不使用旧容器/引擎、宿主目录共享、用户目录、凭据、DB/socket、网络适配器或远程服务。通过只读载体导入经审核的最小源码与测试工具，独立核原字节清单和工具链；禁止随载体夹带 `.git`、真实 CR、宿主配置或未经审计的链接，guest 写入仅限本次独占工作区。隔离证明须由宿主侧与 guest 侧分别提供，验证进程树所有权、真实断网、读取边界、输入身份、异常残留和精确清理；任何前提不明即停止、保留现场。每个测试的命令、派生进程、目标和清理另行授权；不得以环境白名单或容器内自查代替 OS 边界。VM 功能、只读载体和具体创建方式均未知，这不是批准、可运行环境或对网络/硬件断电的测试；EVD-009 的 Git fixture 及其源文件清单仍须专门审核，PG 另按 §2.3 处理。Microsoft 的 [Windows Sandbox 配置文档](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)指出默认启用网络、剪贴板及音频输入，不能把默认实例当成上述隔离环境；禁用配置、载体注入和宿主侧证明均仍未知。[Get-WindowsOptionalFeature 文档](https://learn.microsoft.com/en-us/powershell/module/dism/get-windowsoptionalfeature?view=windowsserver2025-ps)表明 `-Online` 指本机运行中的系统，其默认 DISM 日志可能轮转并覆盖 `.bak`，因此不能将默认功能查询视为无写入操作；本轮未运行该查询。
- [ ] 在隔离环境先取得真实旧行为 RED 和无冒号正控；之后在 Go/list 或临时目录创建前修复三个入口，保留空 TMPDIR 的原有 `/tmp` 回退，并验证 Git Bash 路径与坏路径。
- [ ] 独立复核并登记 `multica/CUSTOM.md`；字符串检查只解决指定 PATH 歧义，不宣称修复路径替换或恶意工具。

#### 2.2 状态投影与 ACK

- **文件：** `multica/server/internal/governance/crsync.go`、`gate_projection.go`、`daemon/crevents.go` 及对应测试；原 best-effort 合同亦须核对。
- [ ] 对 CR 状态、完整门禁投影、事件去重/processed 标记、广播与每 CR 序列化设计可证明的事务和重放边界，盘点原合同兼容与历史已 ACK 事件的恢复。当前源码已对未 processed 的重复事件重试 apply，并对部分 status/evidence 做补强，但 status 的 gate 投影仍吞错，不能把普通重复投递或 accepted 视为全部投影完成。详见 `validation/cr-events-projection-current-static.md`；仅静态核查，未执行回归。
- [ ] 覆盖投影中途失败、DB 回滚与重试、并发重复、合成 rejected/cursor、同批后续事件及死信恢复；审批影响范围后实施，禁止仅改一处返回值即宣称修复。
- [ ] 在获准隔离 PG 中验证真实事务/并发；daemon 测试只运行经安全审查的选择器和环境，登记 CUSTOM。

#### 2.3 Composio 外部副作用

- **文件：** `multica/server/internal/service/discussion_session.go`、`task.go`、`internal/integrations/composio/dispatch.go`；完整静态范围见 `validation/composio-pretransaction-static-20261029.md`。
- [ ] 先确定 discussion 与 retry 两条路径的所属范围、权限和预期失败语义；前者没有 terminal generation CAS，后者的旧修复仅提前拒绝已知 stale，并未把所有 POST 移到 CAS 后。
- [ ] 设计 fact binding、可恢复持久意图、任务 claim 前准备栅栏、撤销线性化、并发 worker fencing、对端超时/幂等/补偿及原子消息语义；不得在业务锁事务内等待外部网络。
- [ ] 使用无真实凭据的 fake Composio 和获准隔离 PG，验证 A→B、同 ID 改配置、撤销、重放、远端成功后本地失败及 crash/retry。设计获批且验证完毕后才修改业务代码。

#### 2.4 可丢弃 PG

- [x] 用户确认 A 设计方向（转述）：通过正式迁移从空库建立全新独立测试库，不读取历史事故库；不以证明与旧库完全等价为目标或前置，也不声称等价。此前对创建新实例和清理本轮可证明归属资源的原则授权保留。方向确认不批准具体设计、资源或执行计划。
- [ ] 按 A 准备适用原生设计调整和独立资源计划，保持原 TC、断言和验收强度；核本轮实例身份、角色、DB 归属、迁移完整性及多初态、清理与失败保全。现有 `multica/scripts/aifi45-db/run.mjs` 绑定并读取历史事故库，继续 HOLD，不得运行或改向；现行 test-plan 的 RUN-003 补充回归段指定该入口，其是否属于 Gate2 原始批准快照及此前登记状态未核实。原 Gate2 无已核实的 BUILD 中途重开入口，替代须走 B4 重大偏离、具体变更决策及后续 Gate3；账本中存在 `ADJ-AIFI45-M006`，但此前直接编辑与工作区 `AGENTS.md` 第 7 条冲突，写入方式的合规处理待核定；`stdd validate` exit 0 不证明写入方式合规，条目存在也不等于批准具体方案。详见 `validation/new-disposable-pg-gate2-draft.md` 和 `validation/new-disposable-pg-schema-static-recheck.md`。未批准、未创建实例、未执行数据库测试。
- [ ] 单执行者按获准选择器运行并逐次核对保护对象、锁和资源清理回执；出现漂移或不确定状态即停止并保全。

#### 2.5 通知守卫 TAB 局部切片

- [ ] 已在 `noticeguard_test/execution_notice_test.go` 增加单个表驱动测试并登记 `multica/CUSTOM.md` #285；生产守卫未改。完整依赖 init 安全尚未证明，真实测试 RED/GREEN 均未运行；仅 gofmt 解析通过。独立复核和安全限制见 `validation/notice-tab-guard-static-review.md`、`notice-tab-guard-slice-plan.md`。
- [ ] 安全证明后在真实独立子包先执行 RED，再最小修复并运行 GREEN/回归；局部成功不计完整 TC-NTF-003 或 Gate3。潜在真实入口、兼容风险和 X6 仍须另验。

#### 2.6 通知生产载荷与重投

- [ ] 独立静态复核发现当前源码的通知写入及 loader 未提供前端新策略所需的 `execution_notification_key`，现有测试手工提供该字段；生产调用者及部署可达性尚未证明。已批准设计的 Inbox details 与独立通知表、project/recipient 去重身份之间亦有待解决的偏离。详见 `validation/ntf-replay-payload-cache-static-20261030.md`。已列两条 Vitest 命令的安全前置另见 `validation/ntf-vitest-entry-safety-static.md`：当前测试名称不命中，默认 Vite 加载路径可能读取 env 文件，不能执行，也不能用退出码或组件 fixture 充当完整 TC。
- [ ] 另核有 key 时客户端标记的条件性 GC、desktop 主进程 gate 与恢复并发，不把再次发起显示请求当作用户实际重复看到；经批准的隔离环境、真实载荷、非零筛选及 RED/GREEN 齐备前，NTF-005/007 不得标记通过。

### 3. 分拆但保留 AIFI-45 验收依赖

- [x] 原生新建 multica `2026-10-30-aifi-45-ci-disposable-db-supervisor`，仅起草 canonical proposal 与 Human View；design、spec 和 test-plan 尚为模板，仍处 understand/pending。
- [x] 原生新建 tools `2026-10-30-aifi-45-evidence-delivery-integrity`，仅起草 canonical proposal 与 Human View；design、spec 和 test-plan 尚为模板，仍处 understand/pending。
- [ ] 两个新 change 分别完成人类 Gate1、设计及 Gate2；组件通过后提交可追溯证据给 AIFI-45。AIFI-45 现行 test-plan 的 RUN-003 补充回归段指定 `scripts/aifi45-db/run.mjs`，该段的原始 Gate2 快照归属尚未核实；该入口当前受 HOLD 禁止运行。已选 A 方向下的替代入口须按 BUILD B4 登记重大偏离并取得具体变更决定，最终随 Gate3 审议，不伪称重开 Gate2；入口落在原 change 还是已有 CI supervisor change 尚未决定，该组件产出不替代原 change 的 B4 登记。
- [ ] 证据 change 先确定权威合同注册/迁移历史、strict 语法和现场兼容；再覆盖新合同未知字段/重复键/非 mapping/字段删除，以及历史合法 legacy 和报告 fence。机械例外包装器、组件 not-applicable 版本/来源与 unknown 作者/Cf 策略亦须评审，完成前保留在 AIFI-45 pending。tools-marker 具体版本不比较、缺 version/digest 声明亦可能 ready 的静态分析及存量兼容待决见 `projects/tools/changes/2026-10-22-aifi-45-authorized-execution/validation/component-not-applicable-scope-20261029/COMPATIBILITY-RECHECK-20261030.md`；未证明生产可达性，不静默更改既有合同。未经审核的 CLI fixture 禁止向上发现真实仓库。
- [x] 用户确认“采纳建议，修订。EVD-008保留显式迁移要求”：优先验证 EVD-009 的真实恢复窗口，先观察原 candidate 而不重推，建议未知/漂移时阻断并将 receipt 字段另审；EVD-008 保留显式迁移正反例。用户随后明确本期不实现存量迁移，并表示目前仅有一个已开发完成但未归档的 CR；该陈述未核实具体 CR 身份、权威状态及所用合同，不据此修改、推进或归档任何 CR，也不关闭 M004。未知/漂移处理若改变 X5 或 SC-MG，是待审方向而非已生效合同；方向确认不等于已批准具体接口、持久化字段、测试命令、合同变更或真实存量操作。
- [ ] **EVD-009 表征优先**：在获批隔离的临时 Git/bare-remote 夹具中，设计并经安全审查后执行精确测试：① 原 candidate 已持久化、远端已包含而 `pushed/confirmed` 未保存，审批不变时不生成第二个发布提交、不重推、不覆写冻结 candidate；② 同窗口叠加受外层 gate、审批信任及 drift 类型约束的主体漂移，核查不把已发布误判为零发布；③ 多仓部分发布、远端历史改写、查询错误及晚到 effect。在 merge journal 与 SC-MG 条款映射获审前，GREEN 仅断言该窗口内不重复发布、不覆写冻结 candidate、不采纳新审批；结算状态和是否继续 finalize/writeback 按现行行为表征，不能把候选收紧当作已批准 GREEN。其他 unknown、重试与历史改写情形须逐项核合同，不笼统假定全部禁止重试；receipt 不含真实修复消费/cycle 来源，不能仅凭①证明无重复扣额或 cycle reset。手改 journal 只能表征状态；真实崩溃试验须另审故障点、进程终止和退出前是否落盘，异常回调不自动等于进程崩溃。候选做法是仅在测试子进程注入拦截器：转发本地 Git、确认指定 push 成功后暂停其返回，由父进程核对远端和 journal 再硬终止真实 CLI；不修改产品逻辑或伪造 push 成功，但插桩扩大了窗口、不能冒称无插桩崩溃或断电实验。独立静态审查指出 OS 隔离、正确 Git 目标、进程树/锁归属与 fixture 异常清理均尚未证明，目标 Node 版本与 preload 命中亦 unknown；精确命令和所有子进程副作用还须另获授权，当前仍 BLOCK，尚未编写或运行。表征准备不以 S4/3.1 已完成为前提，完整 TC 仍依赖原 S4 和 M 调度。不得触及真实 CR/远端；测试命令不在白名单内，需先追加并获确认，无隔离证明不运行。
- [ ] **EVD-009 合同内修复与候选收紧分开**：先取得有效 RED，再依据现行 SC-EVD-009 和适用的 SC-MG 条款修复已证窗口：按仓冻结并识别原 candidate、先观察后 prepare，对已包含原 candidate 的目标不覆写或重复推送；核查 drift 分支不会只据本地 `pushed` 将已发布误判为零发布。先核现有 journal 与配置如何按仓绑定目标、ref、提交及父树身份，一仓观察不能结算其他仓；并发恢复、KB 特殊路径和 Git 配置改写须独立验证，不能输出携带凭据的目标地址。若需新增 journal/receipt 字段、改变 `inputDigest` 或引入远端身份认证，先按 X8 与适用变更流程审议，不能当作合同内修复；消费引用、cycle 和旧 journal 兼容另审。checkpoint、merge、writeback 分别验证原事务、receipt、审批、扣额、cycle 及不重复业务事实，merge 测试不代证其他链路。改变 X5、SC-MG-015/016 或其他批准合同的未知状态处理另走变更流程，不能将候选收紧直接当作合同内修复。见 `projects/tools/changes/2026-10-22-aifi-45-authorized-execution/validation/evd-009-release-recovery-current-static.md`。
- [ ] **EVD-008 保留要求并移交**：用户确认保留 SC-EVD-008 的显式迁移正反例；既有 D8=A、D9 选项 b 与 M004 未被此次方向确认撤销：本期不提供 legacy 业务历史迁移、不新增迁移动词/入口，`TC-EVD-008` 保持 MISSING 并作为 Gate3 偏差；旧 run 保留原合同与恢复路径。候选后续方案须明确目标 CR、新旧版本和有权发起者，按权威事实核验授权、历史消费及未决任务；缺证、矛盾或竞态拒绝，不清零、不丢历史，正确计算剩余，并设计核验/提交绑定、可恢复 receipt、同操作重放与异义冲突、防双派及旧入口封闭。工具侧可写文件或调用方自报不能独立构成可信事实；具体权威持有者、接口、锁域和格式待审。授权/消费历史与证据合同注册历史属于不同问题，不能互相代证。该能力已登记后续占位 change `2026-10-29-legacy-execution-migration`（Ray），仍为 understand/pending 且不在现有长程授权内；不得提前实现或运行其测试。若考虑改为本期实施，须另由用户明确决定并按 B4/适用 Gate 处理。未来仅在获批隔离的临时 CR 验证正反例、并发、中断及 RUN-008 未决任务/防双派，真实存量须专项授权；helper 或算术通过不能代证真实入口。
- [ ] SC-EVD-006/007、EVD-009 和其他 P0/P1 按原 AIFI-45 规则验收；EVD-008 原要求保留、M004 偏差和 MISSING 明确带入 Gate3。当前先推动 EVD-009 的安全表征；EVD-008 后续按占位 change 的启动条件和自身 Gate 评审承接，不以本轮采纳方向越权启动。

### 4. RUN-009 和最终重验

- [x] 记录用户确认的回退方向：平台外人工评审仅作待核材料、不自动推进；未经认证的声称不获取阻塞资格，不把缺绑定一律视作历史。原位更新 `validation/run009-option-a-decision-table.md`，不批准尚未决定的人工确认入口。
- [x] 静态排查入口：tools `cmdReviewNote` 已写本地 `supplemental-reviews` 并发出 outbox，但 payload 只有 stage/status、不含正文；multica `knownEventKinds` 不接收 `review-note`，也没有可信平台本人确认入口。不能复用会影响 Runner 的 `review` 投影。
- [ ] 由人类决定是否需要平台外材料接收、采用经真人认证的独立上传候选或其他方案；现有 PAT 与同 UID Agent 的边界尚不能证明真人。`validation/run009-pending-review-slice-draft.md` 经独立复核可交人决策，但不是 Gate 批准；不预设 spool、dead-letter 或其他复杂机制。须单独处理 `review-note` 拒收可能将原本 completed 的任务报为 blocked 与 #284 严格 settle 的冲突。原 AIFI-45 的重大设计或测试入口变化须先走 B4 登记并由用户决定，最终随 Gate3 审议；新 change 另走其自身 Gate。无合格结果时不计 RUN-009。
- [ ] 完成权威 run/cycle、持久接收和 ACK、可信早到与旧轮、闭合、限流、锁域、恢复、外部 effect 和 legacy 的决策与评审；原 change 若发生重大设计偏离须走 B4、用户决定及 Gate3，不得以回退方向自动视为完整方案批准。
- [ ] 当前源码快照上统一 TC 口径，区分单测/隔离数据库/真实入口、独立复核和跳过项，整合未关闭 major、残余风险及 EVD-008 M004 偏差 / EVD-009 未完成证据；待人类审议 Gate3。不得复用历史 42/43/44 作为当前进度。

## 当前停止条件与待人类输入

1. 用户要求直接审阅 outcome-binding 两侧 canonical 与 proposal，随后回复“审阅确认”；两侧已按原生 STDD 的 dialog 记录 Gate1，审阅快照与审计见 `validation/verdict-outcome-ray-review-request-20261030.md`（保留历史文件名）。生产者、签发者和信任根仍待权威事实核实；此确认不扩展为 Gate2/3 或实施批准。
2. 用户已选择正式迁移创建全新独立测试库的 A 方向，并此前授权仅清理本次创建且可证明归属的资源；旧库和旧 runner 继续 HOLD。须先核实并获准版本化脚本来登记 B4 重大偏离，再由人决定具体变更和资源执行计划；原 Gate2 不可假称重开，方向确认不能代替这些步骤。
3. 用户已授权评估/创建旧 PATH 复现的独立 OS 沙箱；执行前仍须独立证明隔离和安全清理。环境变量白名单不构成该隔离。
4. 需要确认是否将 discussion Composio 与改变状态投影 best-effort 合同分别纳入新的需求/设计评审；在确认范围和真实 Gate 前，不直接按原口头建议改代码。
5. 既往安全评审的敏感信息暴露已告知用户并记录 `validation/container-inspect-credential-exposure.md`；用户表示无需再跟进，不推定凭据已轮换。不得读取或输出凭据，也不得擅自操作既有数据库、服务或会话记录。
6. **恢复合同待决，禁止静默替换**：原已归档的 SC-MG-015 在 `unknown` 且远端包含 expected 时规定不重推并结算成功；候选“目标达成、本次待核、不自动继续受保护动作”会改变该结算。SC-MG-016 的重试前提和迟到排除也待审。既有 X5=a 的原决定为“未发生不可逆发布时可刷新 receipt，维持现状”（见 `validation/backlog-b-disposition-20261026.md`）；何时足以证明这一前提、是否收紧当前未观察即刷新的实现仍待审，不得将候选收紧写成既定 X5。此前建议中“这套处理不改变 SC-MG-015/016”的表述不准确；归档原文不改，若需修订，按 `validation/remote-merge-recovery-amendment-proposal-20261030.md` 的配对 M/T change 及自身 Gate 审议。原行为和候选行为不得静默互换；SC-MG 条款对 crctl `mergeCr` journal 的适用性、状态映射及真实接线尚未证明，须先评审确认。
7. EVD-008 保留原要求，但 M004/D9 本期偏差及后续 change 范围不因本次确认自动撤销；任何提前实施须由用户明确决定并走适用流程。EVD-009 的新增测试命令与隔离未获核准前不运行。

本计划不证明测试、生产授权或 Gate3 已完成。
