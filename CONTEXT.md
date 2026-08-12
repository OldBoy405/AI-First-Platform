# CONTEXT.md — AI First Platform 通用语言（Ubiquitous Language）

本文件只记录已敲定的领域术语及其精确含义，不记录实现细节与决策过程。
术语一经写入即视为规范；新用法与既有定义冲突时，先在此处解决，再改文档。

## 术语表

### CR 角色 Owner（CR role owner）

CR 在 requirement、development、test 三类职责上的当前责任人标识。Owner 表达任务归属与正式移交关系，不是经过认证的平台身份或本地操作者身份；现阶段不得据此宣称具备对抗恶意调用者的强授权能力。CR 注册时三个角色 Owner 必须分别显式提供；即使由同一人承担，也不得通过 requirement Owner 隐式继承。`cr-init` 负责三文件受控写入、初始历史、audit 与结构化返回，不在尚无提交 SHA 时提前发事件；其 audit 包含完整 Owner 投影和三项 `reason=initial-assignment` 的 `changes[]`，不包含尚未发生的 Git/worktree 事实。只有成功的 `crctl git commit --template register --cr <CR-ID>` 才使用同一真实 HEAD SHA 产生 `(new) → drafting` 的 `status` outbox 和完整初始 Owner 投影的 `owners` outbox；commit 失败不发，outbox 失败只返回 warning 并记录 `EMIT_FAILED`，不反转已成功的 commit。所有 `owners` outbox 统一携带完整 `owners` 当前投影与 `changes[]`：注册包含三个 `reason=initial-assignment` 的角色变化，正式移交包含一个 `reason=formal-handover` 的角色变化；移交 `note` 不进入 Owner 投影事件。

### CR 注册（CR registration）

建立唯一 CR 业务身份并进入 `drafting` 生命周期的事实。CR 已注册不等于参与仓工作位置已经全部就绪；工作位置未就绪时不得开始下游阶段产物。
_Avoid_: workspace provisioning、注册执行上下文

### 注册执行上下文（registration execution context）

CR 注册且参与仓工作位置全部就绪后传给后续 Pipeline 节点的权威结果快照，用于标识同一 CR、责任归属及参与仓工作位置。`drafting` 本身不足以证明该上下文可用；注册事务未完成时不得产出成功上下文。
_Avoid_: 注册步骤清单、部分成功 execution context、后续节点自行拼装的上下文

### 正式移交（formal handover）

将某一 CR 角色的责任归属从当前 Owner 明确变更为新 Owner 的业务操作。`handover-cr` 是正式移交的唯一业务入口；它先调用 `owner-set` 形成受控账本提交，再复用 `push-progress` 发布远端，只有远端已包含 Owner 变更才算完成。`owner-set` 在可观测的 Git add/commit 失败路径中，以新内容 hash 为 CAS 前提恢复 `cr.md` 与 `_backlog.yml` 原始快照并重新暂存恢复内容；恢复成功返回 `OWNER_COMMIT_FAILED/changed=false/rolled_back=true`，恢复或重新暂存失败返回 `OWNER_COMMIT_ROLLBACK_FAILED`，两者都必须中止且不得进入 `push-progress`。进程在账本写入与 commit 之间直接崩溃的极端窗口不在本轮引入 WAL，后续一致性检查必须将其暴露，不能将脏文件当作普通同值重放。真实 Owner 变更同时产生面向新 Owner 的 `owner-handover` 通知记录，并仅在 commit 成功后以同一真实 SHA 分别尝试产生 `event_kind=owners` 与 `event_kind=inbox` 的 outbox：前者携带完整当前 Owner 投影和本次变更角色，后者携带收件人与结构化移交事实；`crctl` 不生成 `subject/body` 等展示文案。通知记录与两类 outbox 都不构成责任历史。outbox 是非阻断投影通道，写入失败必须返回明确 warning 并记 audit，但不回滚或阻止权威提交发布。同值幂等重放不更新时间、历史、通知、审计、提交或 outbox。底层 `owner-set` 仅作为本地可信环境中的受控账本原语，负责一致写入、审计和原子提交，不判断调用者是否等于当前 Owner；`push-progress` 失败时移交未完成，由 Skill 传播结构化失败，所在 Pipeline 负责中止。恢复远端工作等其他流程不得附带变更 Owner。

### Owner 变更历史（owner history）

`cr.md#owner-history` 是 CR 角色责任变更的唯一历史事实，覆盖初始指派与正式移交。正式移交记录 `role/from/to/at/reason`，并可携带移交说明 `note`；backlog 中的通知记录只用于协作可见性，`owners`/`inbox` outbox 只用于平台同步与通知投递，均不构成第二份责任历史。`handover-history` 停止新增写入，既有数据仅作兼容读取，不要求迁移。

### 审批驳回（approval rejection）

审批人对当前证据版本作出的不通过决定。驳回是已成功捕获的人工决策，不是 `human_approval` 节点的技术失败；签名决定交付后仍须进入对应 `approve-*` Skill，由 `crctl` 完整验证 grant schema、`cr_id/stage`、当前状态、当前 evidence digest 和签名，再按既有状态机回退并返回结构化非零结果，Pipeline 据此中止正向链；reject 不因 blocker 存在而执行 approve 路径的 pass condition。grant 重放只在紧邻结果状态内幂等：approve 仅当当前状态等于该阶段目标态且 `approval.yml` 的 `approver/key-id/signature/grant-approved-at/evidence-digest` 与输入完全一致时返回成功 `changed=false`；reject 仅当当前状态等于该阶段 reject 回退目标态且 grant 归属、当前证据摘要和签名仍有效时再次返回 `APPROVAL_DECLINED_ROLLED_BACK/changed=false`。两者均不得重复 audit、commit 或 outbox；进入其他状态或持久化审批字段不一致时返回 `GRANT_STATE_MISMATCH`。`crctl` 不选择下一回修 Skill。当前尚无实现该分派语义的 Pipeline Runner；Multica 保存的 `reject_reason` 也尚不能由 tools 自动注入回修节点。这两项均为待实现能力，不得描述为现有 Pipeline 能力。

### Tools Root

目标 workspace 所使用的 tools 包根目录。其唯一声明来源是 Installation Workspace 目录图中的 `workspace.tools_package_path`；相对值以 Installation Workspace 为基准，绝对值直接使用，两者最终归一到真实目录。该声明是使用 tools 流程的前置条件：缺失或无效即表示 workspace 未绑定 tools 包，不从同名目录、当前目录或调用方自身位置推断。

所有调用方共享同一 Tools Root 契约，但绑定时机分为两类：动态调用方在执行流程时解析；IDE hooks、CI 等静态集成在安装配置时物化。统一的是路径事实源与有效性语义，不要求所有调用方共享一个运行时解析模块。

### Operational Workspace

本次 CR 当前阶段唯一允许读写阶段产物的 knowledge-base checkout。merge finalize 前通常是该 CR worktree，finalize 后必须切换为 crctl 管理的 Transaction Workspace；不得根据当前目录或主 checkout 是否干净自行选择。
_Avoid_: Installation Workspace、当前目录、tools checkout

### Transaction Workspace

crctl 为单个已 finalize merge 事务管理的临时 knowledge-base checkout，承接 writeback 到 archive 的唯一写 authority，并与用户主 checkout、CR worktree 隔离。事务失败时保留供续跑，成功归档后受控清理。
_Avoid_: 用户主 checkout、CR worktree、临时目录

### Installation Workspace

声明并锚定 Tools Root 与 workspace-owned `.rayai-worktrees/` 根的 knowledge-base 主 checkout。linked worktree 仍共享该安装基准，不复制或改写自己的 tools 包绑定，也不在自身目录下再派生第二层 `.rayai-worktrees/`。
_Avoid_: Operational Workspace、当前工作目录

### 成熟度 Scope（Maturity Scope）

成熟度快照（`maturity_snapshot`）的聚合层级。**有且仅有三个层级：org / user / project**。

- **org**：全组织聚合，`scope_id` 恒为 `'·'`。
- **project**：Multica 项目，是本平台的天然组织单元——Team Agent、共享队列、CR 归属均以 project 为锚点，"哪个团队用得好"由 project 聚合回答。
- **user**：个人，仅在个人榜开关开启时呈现（见《P3-组织智能设计》§1.5）。

**Department（部门）不是本平台的领域概念**（2026-08-07 敲定）：Multica 无部门模型，
P3 不引入 `department` 表或成员部门归属；曾出现在设计稿中的部门聚合、部门排名、
按部门下钻一律由 project 层级替代。未来若出现真实的多层级管理诉求，再作为独立的
schema 变更引入。

### 观察期（Baseline Calibration Window）

成熟度看板上线后的前 **4 周**（2026-08-07 敲定）。期内快照管道照常每日计算原始
指标值入库，但看板**只呈现原始值与趋势，不呈现雷达图总分**（显示「基线校准中」）。
观察期结束后，用实测分布的分位数规则（floor ≈ P10、target ≈ P75，规则写在
`maturity-config.yaml` 内）自动生成第一版基线，此后正式计分。
含义：**任何成熟度分数都必须有实证基线支撑，禁止拍脑袋初值直接计分**；
口径（`maturity-config.yaml`）变更走 git PR + Owner 审批，`config_rev` 保证可追溯。

### 影子工程 / bypass-commit

绕过 CR 流程直接向 trunk 写代码的行为（2026-08-07 敲定探测口径）。本地执行模式下
平台无法强制所有代码经 CR，但可以让绕过变得**可见**。P3 的探测信号为**前缀层**：

- trunk 提交前缀不在白名单（`wip:` / `[cr] ` / `merge(`）且不属于该仓特许格式
  （如 tools 仓 conventional commits）→ `bypass-commit`，severity `warn`；
- trunk 出现 `wip:` 前缀 → 单独一类提醒（severity `info`），不计入 bypass 计数。

扫描范围 = `dir-graph.yaml#repositories` 声明的全部仓，每仓口径随白名单配置走。
**前缀合规 ≠ 通路合规**（前缀可手写伪造）；通路层对账（controlled-shell 审计行 ↔
trunk 提交）属新采集，显式延后到 P3+，不属于 bypass-commit 的当前语义。

### CR 状态机口径（16 态 vs 15 态）

文档口径与代码口径的换算于 2026-08-11 更新：状态机 = **15 个具名状态
+ 注册前 `(new)`**（口语「16 态」含 (new)）；转移 = **28 条声明，wildcard 展开后 50 条**。
CR-2026-026 在既有 25/47 基线上新增两条开发计划评审转换：
`review-dev-plan:block -> write-dev-plan` 与
`review-dev-plan:upstream-design-blocker`；CR-2026-031 在 27/49 基线上新增一条
发布漂移回退转换：`code-approved -> developing`（trigger=
`merge-feature-branch:release-drift -> implement-code`）。正式断言必须以
`../tools/dir-graph.yaml#change-request-track.state_machine` 的当前内容为准，不得把历史
25/47、27/49 口径继续描述成现状。
multica 代码（`cr-status-badge.tsx`）按 15 态渲染是正确的；PRD §5.2.3 与 P0 文档中
「16 态」的表述指含 (new) 的口语口径，写正式断言时必须写明用的是哪个口径。

### 上游设计疑点（upstream-design blocker）

开发计划与 TASK 评审发现的、只能通过修订已审批 SDD 才能解决的阻断问题。它不属于 plan/TASK 自动回修范围；`review-dev-plan` 先通过权威 trigger 回退到 `tech-design-review-pending`，再返回结构化非零业务结果 `UPSTREAM_DESIGN_BLOCKER`，当前 coding Pipeline 据此中止。该结果与 CAS、执行或平台故障等技术失败使用不同错误码；后续必须回到既有技术设计修订、评审与审批流程处理。
_Avoid_: 普通回修 blocker、TASK blocker

### 状态转换字面量校验 (transition literal validation)

`lint-prompts` 对 Skill 中字面量 `crctl advance --to <to> --trigger <trigger>` 执行的静态一致性检查：直接读取 tools `dir-graph.yaml#change-request-track.state_machine.transitions`，只验证 `(to, trigger)` 是否存在；含模板变量时跳过，不从自然语言推断 `from`。状态机解析失败必须硬失败，运行时合法性仍由 `crctl advance` 裁决。
_Avoid_: linter 状态机副本、Pipeline trigger 校验

### 评审输入绑定（review input binding）

`crctl review-record` 在评审结论落盘时，对该 stage固定输入文件计算 LF规范化 SHA-256并机器注入 annotation的事实快照，用于证明评审消费的是哪一版上游文档。模型 payload不得提供或覆盖该快照；新 annotation使用 `input-subjects`，code阶段继续使用覆盖代码仓与受控文档的 `release-subjects`。旧 `subject-file/subject-sha256` 只作历史读取兼容，缺少足够绑定时对齐结果为 unknown，不用 mtime或时间顺序猜测。
_Avoid_: 测试工作现场摘要、模型自报摘要、评审时间新旧比较

### 评审对齐当前投影（review alignment projection）

由评审输入绑定与当前同路径内容摘要机械比较得到的当前 `aligned / drift / unknown` 事实。检查身份是 `(CR-ID, review-stage)`，稳定 key固定为 `alignment:<CR-ID>:<stage>`，每个 CR/stage最多一个当前 finding。传入 stage时只检查并原子更新该 key；未传 stage时固定检查四个评审阶段，全部机器结果生成后以一次 durable write-set原子更新，任一技术失败四阶段零写，drift/unknown作为可信业务结果照常共同提交。canonical traceability只持久化未解决的 `drift[]`：drift和unknown写当前 finding，aligned不写成功记录并删除该 CR/stage拥有的旧 finding；其他所有者条目不得被删除。finding只包含 crctl生成的 `state`、`changed-subjects`和`missing-subjects`；文档主体为 `kind=artifact`，仓库主体为 `kind=repository`。模型不得提供任何 finding字段。`suggested-skill`、`reason`/message只根据 `(stage, state)`在命令响应中临时生成，不进入 canonical YAML、digest或幂等比较。数组清空时删除整个 `drift`字段。数量只在命令响应中从当前数组计算，不持久化 summary、counter、检查时间或成功历史，也不更新 baseline的 `generated-at`；修复时间线由 Git历史保存。
_Avoid_: alignment业务 payload、impact/stale模型、alignment事件日志、summary.stale、checked-at、last-aligned-at

### 完整 Checkpoint（complete checkpoint）

同一 CR 的全部参与仓在某一时点已经发布并可共同恢复的最新进度事实。只有整组参与仓均被确认且该组事实已对协作者可见时才成立；单仓已推送或事务中间态都不是完整 Checkpoint，历史版本由 Git 保留，不在 CR 账本重复维护。
_Avoid_: 单仓 checkpoint、checkpoint 历史数组、部分成功 checkpoint

### 测试运行（test run）

在 CR 开发期实际启动项目测试、lint、build 或其他验证程序并捕获退出事实的受信代码执行能力。argv、工作目录 containment 与 timeout 只用于防止接口误用，不构成安全沙箱；隔离边界属于 runtime、container 或 OS 身份。测试运行只产生临时执行证据，不直接改变 canonical CR 账本。
_Avoid_: 安全测试沙箱、只读质量检查、测试记录

### 测试记录（test record）

把既有测试运行事实与测试负责人的业务分析原子固化为测试报告、版本化 evidence、traceability tests 和 review-loop 的受控账本操作。测试记录不重新执行测试，也不接受调用方选择 generator、candidate 或 canonical 目标路径。新协议不把缺少 run-id与完整 subject digest的旧报告包装成新 attempt：已有正式 `write-test-report` loop时从其当前轮次继续，不存在时从 attempt 1开始，既有 maxAttempts预算不重置；旧报告和固定日志仅由原路径与 Git历史保留。
_Avoid_: 测试运行、模型直接编辑 test-report、外部 candidate apply、legacy-attempt、伪 run-id

### CR 阶段文档（CR-local artifact）

服务单个 CR 审批与交付过程的 PRD、SDD、Plan、TASK、测试报告和评审记录。其生命周期
随 CR 结束，不等同于跨 CR 累积维护的产品基线文档。

CR 阶段 PRD 与产品区活文档是两个不同概念；不得仅因二者都叫“PRD”就默认使用同一
标识或内容契约。

### specs 基线文档（baseline artifact）

多个已完成 CR 的有效变更逐里程碑累积形成的发布基线，不是任一 CR 阶段文档的副本。不得用单个 CR 文档覆盖整份基线。traceability baseline不因新 milestone结构增强而新增顶层或 milestone级 schema版本字段：既有 milestones作为 opaque历史段逐字节保留，新 generator和 archive gate只严格校验当前 CR新增段，reader不得因旧段缺少新字段而拒绝整份文件。
_Avoid_: 全量重写历史 milestone、用顶层 schema-version宣称历史段同构

### 终态反馈事实（terminal feedback fact）

终态 CR 对单个 spec 记录的一次性实施结论，以 `(CR-ID, spec-id)` 唯一标识。记录前 CR 必须已完成现有 archive 账本移动并在 `_history.yml` 具有唯一 `final-status`；不得从 backlog 或 cr.md 猜测 outcome。业务正文只在目标 baseline traceability 顶层 `feedback[]` 保存 `cr/outcome/deviation/lessons`；`_history.yml` 同一 CR 条目只复用 `final-status`、`writeback-spec-id` 并保存 canonical deviation/lessons 的 `feedback-input-sha256`，用于绑定输入和幂等校验，不重复正文、outcome、时间、摘要或 commit SHA。outcome 只能由 final status 机械派生；相同输入重放不产生新提交，不同输入不得覆盖，修正须另开 CR。该事实不发送 outbox，也不承诺 Multica 实时通知或展示。
_Avoid_: feedback event、终态 inbox 通知、history 中的第二份 feedback 正文、可覆盖 feedback

### CR 目录索引（change-requests/_index.yml）

CR 的全生命周期轻量目录，用于登记身份和基本生命周期摘要。它不是当前状态或历史详情
的权威来源，不复制完整历史记录，也不在归档时删除 CR。

### CR 参与仓（participating repository）

被工作区明确声明为参与 CR 生命周期的仓库。当前模型中，每个参与仓都参与每个 CR，
不存在只写在流程说明里的隐藏仓库，也不存在每 CR 单独选择仓库的第二套参与模型。

### 归档事件（archive event）

正常归档 commit 已由 origin 确认后产生的生命周期投影事件，固定表达 `writing-back → archived`、`trigger=cr-archive` 和真实 archive commit SHA。权威事实仍是同一 Git commit 内的 `_history.yml`；outbox 只负责让 Multica及时投影，发送失败返回 warning并由snapshot reconcile兜底，不反转Git authority。rejected/withdrawn在进入终态时已由status事件表达，后续archive账本移动不重复发送archive/status事件。
_Avoid_: terminal v2、feedback event、把outbox当作归档authority

### CR 终态查询（terminal CR lookup）

对已结束 CR 的状态和下一步进行只读查询。终态没有合法后继；终态查询不会恢复 CR 的
可写性。若活动视图与历史视图同时声称拥有同一 CR，必须视为数据冲突。

### 正常归档与提前终止

- **正常归档（archived）**：完整走过开发、代码审批、合并和回写链路的完成态。按现有
  流程必然产生非空 TASK 集合；缺少任务或存在未完成任务都表示流程不完整。
- **提前终止（rejected / withdrawn）**：可在生命周期任意 active 状态终止，可能尚未
  产生 TASK 或回写产物，不适用正常归档的任务与回写门禁。

未来若需要“无 TASK 但正常完成”的业务流程，必须显式定义，不得以缺失产物作为领域
信号。

### CR 关联 Issue（原「壳 Issue」，已废止）

`cr.shell_issue_id` 指向的 Issue（2026-08-07 敲定，见 ADR-0001）：CR 与项目的
关联锚点，由 crsync 从 `cr.md#origin={type:issue}` 回填。**「壳 Issue」三件套
设计（issue.cr_id 指针 / 7 态看板映射 / 禁拖拽）已正式废止，不再承诺实现**；
「壳 Issue」一词不得再用于新文档。TASK 子 Issue 投影的锚点随之一并悬置。

### origin（修复归因）

cr.md frontmatter 的**可选**字段（2026-08-07 敲定），指向本 CR 所修复的原 CR
（`origin: CR-2026-XXX`）。仅修复类 CR 填写；登记时由 requirement-register 提示。
**变更失败率的唯一归因信号 = 显式 origin**，不用「同 spec_id + 14 天」启发式
（specs 基线是累积文档，同 spec 多 CR 演进是常态，启发式会系统性虚高）。
origin 同时服务跨 CR 追溯：修复链一跳可达。
