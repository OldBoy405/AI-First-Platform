---
id: CR-2026-074-prd
type: PRD
cr-ref: CR-2026-074
title: AI First tools：新 KB 初始化与首次回写兼容方案
target-version: 0.47
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owner-role: requirement
status: draft
created: 2026-09-30T22:01:01+08:00
updated: 2026-09-30T22:18:32+08:00
---

# CR-2026-074 — 新 KB 初始化与首次回写兼容方案

## 1. 概述

### 1.1 问题与目标

新知识库（KB）缺少现有 CR 命令要求的账本，使用手工模板又容易生成不兼容结构；第一次回写缺少 `specs/_index.yml` 会失败。traceability 对整篇 PLAN 扫描 FR/cmd 行，可能误取 readiness 或预算表；按行正则提取仓库 trunk 又无法正确处理带引号或非首键的 id。

本 CR 提供显式初始化入口、缺索引时安全首写、仅消费两张规范表的追溯生成，并同步文档、worktree 自忽略及裸提交祖先判定能力。注册无来源时默认产生 `manual`，与 PRD writer 的非空路径校验冲突，也在本 CR 内作最小修正。

交付版本继承 `cr.md` 的 `0.47`，目标 spec 为 `ai-first-platform`；需求、开发、测试三角色均为 Ray。此版本是 CR 目标版本，不自行推断 tools 的独立包版本号。

### 1.2 事实源、授权与范围修订

输入来源：AIFI-40 当前描述、附件 `ai-first-tools-kb-init-writeback-plan.md` 全文，以及该 Issue 注册线程中的 Ray 裁定；附件不是新写入的 `cr.md.source` 路径。

- 注册线程根：`01a0f280-49c3-7dc3-9b8b-c8029116e601`。注册已完成，不重复注册，不更换 registration key。
- 追加范围：AIFI-40 描述要求受控 shell 放行两个裸提交号的 `merge-base --is-ancestor`，只改对应白名单形态与 Skill 能力说明。
- Ray 裁定：`01a0f294-b526-7392-80c1-7cd5e467ab53`（2026-09-30）：“授权 requirement-writer 按「`manual` = 无外部来源」口径先继续 `write-requirement-prd`，永久修正随 (b)落进本 CR”。(b) 是注册默认 source 由 `manual` 改为空串，不另立 CR。
- **本次执行例外**：现有 `cr.md.source: manual` 保留为注册历史，依上述授权解释为无外部来源，不把 `manual` 当路径校验；不手改 source、摘要或注册指纹，也不补造一个同名文件。
- **范围修订**：原注册摘要中“注册核心不改”由本裁定作唯一窄化例外：只允许修正省略 source 时的默认值及相应证据/说明，注册其余行为不变。其他已确认排除项照常有效。此 PRD 明确记录修订，不以未授权改账本消除历史差异。

修订后的执行摘要：提供显式 `crctl kb init` 初始化新 KB，支持首次回写缺少 `specs/_index.yml` 时安全首写，并修正 traceability 对 PLAN 两张稳定表及 repositories trunk 的读取；同步 worktree 自忽略、使用文档与 controlled-shell 裸提交祖先判定能力；注册省略 source 时改为持久化空串。复用既有事务/CAS，不改变状态机、gates、Pipeline、Agent、注册其他逻辑或 multica 代码，以自动化证据验收并发布 tools 修复版。

### 1.3 当前基线核实

需求编写前在本 CR 的 tools worktree 核实以下事实；附件基准 SHA 仅是历史背景，不当作当前 checkout 身份：

| 事实 | 本次核实位置（相对 tools 根） | 结论 |
| --- | --- | --- |
| 非 help 命令先要求显式 workspace，再检测 KB 目录并加载 gates | `skills/shared/crctl/scripts/crctl.mjs:3570` | 新 KB 初始化必须保留显式根，并有独立的前置入口 |
| source 缺省为 `manual` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs:770` | 与 writer 非空 source 路径合同冲突，需 FR-10 |
| 缺 baseline 索引直接报错 | `skills/writeback/scripts/writeback-prd-sdd.mjs:85` | 缺文件首写尚未支持 |
| 全篇 FR/cmd 扫描、空单元格过滤 | `skills/writeback/scripts/writeback-traceability.mjs:206` | 存在附件指出的诱饵表/错列风险 |
| trunk 提取依赖条目首键和非引号文本 | `skills/writeback/scripts/writeback-traceability.mjs:90` | 与 repositories 的 YAML 解释不一致 |
| merge-base 仅有两种现有 shape | `skills/shared/controlled-shell/rules.json` | 裸提交号到裸提交号未放行 |
| 使用指南仍有四种手工索引模板 | `docs/QODER-使用指南.md:65` 等 | 需换为显式初始化说明 |

上述核实支持附件问题结论；实施期若基线变化，须更新证据并说明结论是否受影响。附件所称 15 份历史 PLAN 的回放结果不作为本轮已通过的测试，须在开发期生成可核查证据。

## 2. 用户故事

| ID | 角色、行为与价值 |
| --- | --- |
| US-1 | 作为 KB 维护者，我先声明仓库与 tools 路径，再显式初始化，使第一笔 CR 可注册而无需手写治理账本。 |
| US-2 | 作为交付 Agent，我在没有 baseline 索引的新 KB 执行首次回写，获得正确索引，且不覆盖并发写入或旧历史。 |
| US-3 | 作为交付/评审 Agent，我只从规范 PLAN 表取交付链与证据，避免表外 FR/cmd 干扰，并正确理解 YAML 仓库声明。 |
| US-4 | 作为受托 Agent，我可通过受控入口判断两个提交的祖先关系，能力仍受明确白名单限制。 |
| US-5 | 作为需求作者，我省略来源路径时得到明确的“无来源”空值，不因注册哨兵被错误路径校验阻断。 |

## 3. 功能需求

### FR-1 — 显式 KB 初始化入口与执行边界

提供 `crctl kb init --workspace <KB 主 checkout>`。人先写 `dir-graph.yaml`，它是唯一业务输入；最低合同为非空 `workspace.tools_package_path` 及恰好一个 active `role: knowledge-base` 仓的 `id/path/trunk/role`。代码仓按既有 repositories 合同补充对应声明，id 不限定为某固定值。

- 不接受或推断 trunk、tools 路径、仓库清单、owner、CR-ID、版本等额外业务输入；不从 cwd 或环境变量猜 workspace。
- 无 TTY 限制，人或受托 Agent 均可显式调用；这不是审批或授权签名入口，操作系统文件权限与 Git 凭据仍照常适用。
- 初始化允许尚无 `change-requests/` 的主 checkout；除本入口外，其他非 help 命令保持显式 workspace 与现有失败关闭规则。
- 不创建 Git 仓库、远端或凭据，不创建 CR/task，不批准、不推进 CR 状态，不发 CR outbox。
- 不新增 Skill、Pipeline 节点、Agent 路由、矩阵条目、模块或导出；具体接线归 SDD。

### FR-2 — 初始化前置检查与错误合同

所有业务前置检查完成后才允许创建账本、暂存、提交或推送。固定检查优先级如下，同一现场存在多个错误时返回最先失败项：

1. 显式非空 workspace 与 `kb init` 调用形态。
2. tools 身份与 repositories 声明，按现有 `resolveToolsRoot`、`resolveRepositories` 的顺序与错误合同原样校验。
3. KB root、install root、传入 workspace 的 realpath 一致，拒绝 linked worktree 或指向其他 checkout。
4. 全部 active 仓均为 Git checkout 根且有 origin；代码仓声明的远端 trunk 必须可只读查询到。inactive 仓按现有 resolver 排除，不新增 fixed-repo 假设。
5. KB 当前分支为声明 trunk；无首个提交的空仓也要满足。工作区/暂存区只允许 `dir-graph.yaml` 和两本初始化账本的变化，不夹带其他文件。
6. 读取远端后，KB 远端 trunk 缺失视为空远端并允许；存在则必须是本地 HEAD 的祖先。若本地无 HEAD 而远端有 trunk，同样拒绝，不 reset/rebase/覆盖。
7. 两本账逐个判定：不存在可建；CRLF 归一为 LF 后逐字等于 FR-3 模板则跳过；否则 `KB_INIT_CONFLICT`，列出冲突路径。已使用 KB 不作“已初始化”绕过。

CLI 无 HTTP 状态。失败统一非零退出，stderr 为既有 `{error:{code,message,...}}` JSON，stdout 不伪报成功。错误闭包按下表约束；不在需求期复制现有 resolver 的完整错误枚举。

| 错误类别 | 唯一判定与错误信息 | 写入/残留边界 | 调用者动作 |
| --- | --- | --- | --- |
| workspace 缺省、空或非字符串 | `WORKSPACE_REQUIRED` | 无账本、审计、候选、journal、暂存、commit、push | 显式补传 workspace |
| 不支持的 kb 子命令/调用形态 | `BAD_ARGS` | 同上 | 修正 argv，使用唯一公开入口 |
| tools 或 repositories 校验失败 | 原 resolver 对该输入的唯一既有码原样透传；例如 `TOOLS_PACKAGE_NOT_FOUND`、`REPO_GRAPH_INVALID`，不改判定优先级 | 同上 | 修正 dir-graph/包安装/仓库路径后重跑 |
| checkout/根路径/origin/代码仓远端 trunk 不合格，或其只读核验不能完成 | `KB_INIT_PRECONDITION`，`reason: repo-invalid` | 无业务文件、暂存、提交、推送 | 修正仓库配置/可达性，不重注册 CR |
| KB 分支不匹配 | `KB_INIT_PRECONDITION`，`reason: trunk-mismatch` | 同上 | 人切到声明 trunk 后重跑 |
| KB 存在范围外变更 | `KB_INIT_PRECONDITION`，`reason: dirty` | 同上 | 人先处理范围外变更 |
| KB 远端核验失败或远端不是 HEAD 祖先 | `KB_INIT_PRECONDITION`，`reason: remote-diverged` | 同上 | 人处理远端/历史问题，不 force |
| 既有账本异内容 | `KB_INIT_CONFLICT`，附冲突路径 | 两本账、提交、远端均不变 | 人确认既有 KB 与目标，不让 init 修复旧账 |
| 检查后文件被并发创建 | `CAS_CONFLICT`，附路径 | 不覆盖并发文件；可能保留本次此前已独占创建的另一本模板账；无后续提交/推送 | 重跑同命令重新核验；异内容转 conflict |
| 创建/本地 I/O 失败 | 既有兜底 `INTERNAL_ERROR` | 复用独占创建失败清理；可保留此前已完整创建的模板账，不产生 journal/锁/task | 修正权限/磁盘问题后重跑同命令 |
| add/commit/push 失败，包括非快进拒绝 | 复用 `TX_GIT_FAILED`，保留失败阶段与 Git 原因，不伪报 pushed | 允许保留合法账本、已暂存内容或本地 init commit；远端不强制覆盖，失败分支不写成功审计 | 修正原因，重跑同命令，禁止 force/旁路补账 |

只读 fetch 可以更新 Git 本地对象/远端跟踪引用；“前置失败零写入”指业务文件、index 暂存、commit、远端 trunk、审计与 CR 状态，不承诺抹掉 fetch 结果。初始化不用 journal、锁或故障点，因此不新增锁/事务失败分支；现有 writeback 的事务错误与恢复合同不变。

### FR-3 — 初始化产物、重入与发布

创建且仅创建以下两本账；末尾保留换行，空列表使用 null 根，不使用 `[]`：

| 路径 | 初始文本 |
| --- | --- |
| `change-requests/_backlog.yml` | `schema: cr-backlog/v2`，下一行 `change-requests:` |
| `change-requests/_index.yml` | 单行 `change-requests:` |

`dir-graph.yaml` 保持人提供的原文，三文件同一初始化提交发布，消息 `kb init`，无 CR trailer。新账本必须独占创建，不能覆写并发内容。只暂存这三文件；有暂存变化才提交，HEAD 尚未出现在远端 trunk 时才普通 push，不 force、不 lease。成功输出 `{op:'kb-init',changed,created,commit,pushed}` 并记录一行成功审计，不产生 outbox。

**幂等合同**：无 registration key、请求指纹或新资源 ID；作用域为 realpath 确认的 KB 主 checkout，业务输入仅该根的 dir-graph。重放判据为两本账规范文本、三文件提交现场和本地/远端 trunk 关系，先完成 FR-2 再决定创建/补提交/补推送/noop。模板文本仅 CRLF→LF 等价，其他空白不自行归一。已写未提交可补提交；已提交未推送可补推送；全部完成重跑 `changed=false`，不新建 commit/push。不同配置仍须重新校验，不能因文件已存在跳过。

这是可重入的文件/Git阶段流程，不承诺跨三文件原子事务或自动 rollback；失败残留仅限 FR-2 明示的完整模板、暂存和本地提交，没有未声明 journal/锁/资源。已使用账本为异内容时硬拒绝。不创建 `specs/_index.yml`、delivery 索引或用户根 `.gitignore`。首次后续 register 仍读取既有两账本、分配 `CR-<YYYY>-001` 并为全部 active 仓建立 worktree。

### FR-4 — worktree 目录自忽略

现有 worktree ensure 建立 `.rayai-worktrees/` 时，按 `.crctl/.gitignore` 的自忽略先例保证 `.rayai-worktrees/.gitignore` 内容为 `*`。根 `.gitignore` 未声明忽略的旧 KB 也适用，不要求人补改根忽略文件。不扩大到其他目录或改用户 `.gitignore`；后续注册生成 worktree 不使主 KB 因运行时目录而变脏。

### FR-5 — baseline 缺索引时安全首写

仅当 `specs/_index.yml` 不存在，baseline candidate 以 `schema: specs-index/v1`、空行、`features:` 为首部，再按现有插入逻辑加入 spec；不新增顶层 updated。

- 既有索引继续累积历史；已存在但缺 `features:` 或目标条目缺 `cr-history` 等仍 `STRUCTURE_MISMATCH`，不重建、不删旧条目。
- generator 只输出 candidate，不直接改 authority。继续复用已有白名单和缺文件 CAS（`beforeSha256=null`），不改 `writeback-apply` 或 durable-tx。
- 生成后、apply 前被他人创建的索引必须在既有 before 校验中拒绝，不覆盖。apply/replay 的错误码和恢复语义完全沿用既有合同；同事务重放不得重复添加 spec。

### FR-6 — traceability 只读取两张规范表

目标表不依赖章节号；trim 后的表头单元格必须逐字等于下列合同，且紧接 Markdown 分隔行，每张恰好一次：

- 交付覆盖：`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`。
- 证据命令：`证据ID | repo | cwd | executable | args | timeout`。

仅表分隔行后连续 `|` 数据行属于该表。其他 readiness、可达性、预算表及表外 FR/cmd 行不纳入链。

- 覆盖行必须恰 5 格，保留空单元格位置，首格以 `FR-\d+` 开头；不能通过丢空格子凑齐列。
- 命令行只新增首格 `^cmd-\d{2}$` 校验；不校验数据行列数，args 内合法 `|` 不被误拒绝。
- 缺表、重复规范表、非法覆盖行或非法命令首格统一 `STRUCTURE_MISMATCH`，硬失败；不静默退回全篇扫描或空集合。
- 不新增重复 FR/cmd 等额外收紧项；其他 TASK/test-report/merge evidence 交叉核验不变。
- 生成失败不写 authority，且在既有成功生成后才建 journal 的边界内不留下本阶段 journal。已批准 PLAN/approval 不为适配解析器而修改。

### FR-7 — YAML repositories 的 trunk 一致解释

traceability 以既有 YAML 解析解释 `dir-graph.yaml#repositories`，按 id 取 trunk；支持带引号的 id 与非条目首键的 id，符合既有 resolver 语义。找不到所需仓库的有效 trunk 仍 `TRUNK_UNKNOWN`，不猜 master/main、不读取 trunk 最新提交替代 merge facts。不修改 dir-graph 声明、merge evidence 或其他仓库算法。

### FR-8 — 文档与命令发现同步

- README 增加指向显式 `crctl kb init` 的简短入口。
- `docs/QODER-使用指南.md` 删除 backlog、CR index、specs index、delivery task index 四个手工模板，改为“写最小必填 dir-graph → kb init”；必须包含 tools 路径、KB role，代码仓 role 说明。其他 docs 索引模板不动。
- requirement-register 失败说明对 `WORKSPACE_NOT_FOUND`、`REPO_GRAPH_NOT_FOUND`、`TOOLS_PACKAGE_NOT_FOUND` 提示先写 dir-graph 并由人运行 kb init，Skill 不自动代跑。
- crctl Skill 子命令表增加 kb init；删除“默认从 cwd 向上探测”旧说法，明确 workspace 必填，除 kb init 外要求已有 `change-requests/`。
- HELP、caller-contract 命令表登记 kb；gate-registry 只调整新增入口对应测试计数，不修改 gate 定义或状态机。

### FR-9 — 受控裸提交祖先判定

controlled-shell 的 merge-base shapes 仅追加 `^--is-ancestor [0-9a-f]{7,40} [0-9a-f]{7,40}$`，保留 `^origin/\S+ HEAD$` 和 `^--is-ancestor \S+ origin/\S+$` 两条，同步 Skill 能力表。

由受控入口允许两个 7–40 位小写十六进制提交号的只读祖先判定。Git 真/假退出语义沿用现状，不能把“非祖先”混同为白名单拒绝；不增加其他 ref、选项或命令形态。`workspace-transactions.mjs` 内部 gitRun 不经该白名单，本项不改变它；不修改 multica gitguard 代码。

### FR-10 — 无来源注册默认空串

新注册省略 source 时持久化 `source: ""`；显式空串同样代表无外部来源，进入 writer 后不做来源路径存在性校验。显式非空路径值与既有 containment/存在性校验不变。

本项仅替换缺省值；不新增 source-set，不将显式 `manual` 全局重新定义为路径例外，不改 Pipeline/Agent/writer 通用校验，不迁移历史账本或改已有注册事务指纹。同 key 的既有事务仍按既有注册指纹判重与冲突规则处理，不通过重归一化历史输入解除 `REGISTRATION_INPUT_MISMATCH`；本 CR 的历史 `manual` 只靠 §1.2 人工裁定放行。SDD 必须验证旧事务重放不被默认值修正意外破坏；不允许绕过冲突强写。

## 4. 非功能需求

- **NFR-1 安全与最小改动**：保留显式根、role/repositories 单一事实源、非快进拒绝、独占创建和 CAS。不得手工修补 AIFI-35 已签字源或 KB 账本；不得夹带未声明文件提交。
- **NFR-2 平台兼容**：沿用 Node ≥18、零新依赖；所有读入后涉及文本比较、哈希或逐行/跨行解析均先 CRLF→LF。对 LF/CRLF 等价夹具结果一致，匹配失败硬报错。
- **NFR-3 兼容性**：既有完整索引、PLAN 链、注册版本/owner/spec/幂等、writeback 事务和状态门禁保持原合同；仅 FR-10 明示改变无 source 新注册默认值。
- **NFR-4 成本**：全自动验收，复用现有 fixture 与定向 FR/AC 证据；不要求四轮人工审批的真实 E2E，不另建 runtime supervisor、锁/journal 或定时重试。初始化网络操作按调用执行，不常驻或轮询。
- **NFR-5 可归因**：证据必须绑定本 CR tools 变更；引用历史样本须给 fixture 出处和对比结果，不把附件陈述当新测试结果。术语“通过”仅来自结构化测试/评审。

## 5. 验收标准

| ID | 对应需求 | 可执行场景与预期 |
| --- | --- | --- |
| AC-01 | FR-1、FR-3 | 沿 register-tx 三仓+bare origin 夹具，只写 dir-graph、KB 无远端 trunk/账本；init 首跑创建精确两账本、三文件同一提交、建立远端 trunk，输出字段完整，无 CR/task/outbox；再跑 noop、无新提交/推送。 |
| AC-02 | FR-2 | workspace 缺省/空、非法调用、tools/graph 非法、根路径不一致/linked worktree、非 Git 根/缺 origin/代码仓缺 trunk、KB 分支错误、范围外 dirty、远端领先/分叉、异内容账本逐项负测。分别断言固定错误及 priority，业务文件/暂存/提交/远端/audit 零变化；仅允许明确声明的 fetch 副作用。 |
| AC-03 | FR-2、FR-3 | 预置“已写未提交”“已提交未推送”现场，重跑同命令补完且不重复资源；合成检查后并发创建、I/O 或 Git 阶段失败，验证不覆写并发文件、仅保留已声明可恢复现场、无成功审计，修正后同命令可续跑；不为测试新增故障点/锁/journal。 |
| AC-04 | FR-3、FR-4 | 初始化后 register 生成 `CR-<YYYY>-001`、全部 active 仓 worktree；根 `.gitignore` 未忽略运行时目录的夹具仍 KB clean，`.rayai-worktrees/.gitignore` 为 `*`；原根忽略文件不变。 |
| AC-05 | FR-5 | 缺 specs index 的 baseline candidate 含新索引且 before=null；apply 创建，事务重放不重复 spec。畸形既有索引原文不变；candidate 后并发新建，apply 拒绝且并发原文不变；已有正常索引旧历史保留。 |
| AC-06 | FR-6 | CR-2026-061（args 含 `|`）和 066（诱饵表）的 PLAN 裁剪夹具在规范数据部分与旧解析结果一致；合成 readiness 四行三列 FR 表+表外 cmd 诱饵，仅两张规范表进入链。章节号变化不影响取表，空单元格不移列。 |
| AC-07 | FR-6、NFR-2 | 缺任一表、重复任一规范表、覆盖行 4/6 格、命令首格非 cmd-NN 逐项 `STRUCTURE_MISMATCH`；不落 authority/本阶段 journal。不新增重复 FR/cmd 限制；LF/CRLF 对应正负夹具得到相同集合或错误。 |
| AC-08 | FR-7 | 引号 id、id 非首键均取到声明 trunk；未知仓库/缺有效 trunk 仍 `TRUNK_UNKNOWN`，无固定 trunk 回退；TASK/test-report/merge evidence 既有负测维持。 |
| AC-09 | FR-8 | 文档四模板移除而其他 docs 索引模板保留；最小 dir-graph、显式根与“Skill 不代跑”说明齐全；HELP/caller-contract/gate-registry 相关定向测试更新并通过，gates/状态机/Pipeline/Agent/矩阵未改。 |
| AC-10 | FR-9 | 7 位、40 位小写裸提交对经 crctl git 白名单放行；祖先/非祖先返回 Git 原语义。两条旧 shape 仍允许；不符合全部三条 shape 的短号、非十六进制、额外 flag/ref 形态仍 `FORBIDDEN_SUBCOMMAND`。Skill 能力表与 rules 一致，其他命令白名单不变。 |
| AC-11 | FR-10 | 新注册省略 source 与显式空 source 都产生空 source、可进入 writer；显式存在/不存在/越界路径维持既有 writer 校验。已有 source、owner/version/spec、CR-ID 分配与指纹冲突合同不变；覆盖历史注册事务重放，确认不重写旧 manual/指纹或重复注册。 |
| AC-12 | FR-5～7、NFR-3 | `makeCodeApprovedFixture` 无 specs index 变体：merge→baseline/tasks/traceability 三阶段→archive 全通过。writing-back 态单独重放 traceability，baseline/tasks 事务及签名源内容哈希不变，不重做前两阶段。哈希比较前规范行尾，不伪造审批。 |

上述 AC 是未来开发验收要求，本 PRD 不声称已经执行。实际任务/命令、错误实现接线、解析算法、恢复证明与测试拆分归 SDD/PLAN；沿用附件优先顺序：追溯解析/trunk → baseline 首写 → init/自忽略/source 默认 → 文档/白名单与对应测试。普通 CR 按本 FR/AC 定向证据验收，不另加全量真实人工 E2E gate。

## 6. 成功指标

1. AC-01～AC-12 有可归因自动化证据，定向负测与兼容回归无未解决 blocker。
2. 新 KB 从唯一 dir-graph 输入经 init 和 register，主 KB clean；不依赖四种手工账本模板。
3. 无 baseline 索引的首次完整回写成功，已有索引历史与并发文件无覆盖；独立追溯重放无上游重做或签名源漂移。
4. 表外 FR/cmd 误收为零；规范 PLAN 的链/命令集合无非预期变化，LF/CRLF 等价。
5. 未提供外部 source 的新注册不再写入 manual 哨兵或被 writer 来源路径校验阻断。
6. 本 CR 按审批、合入、发布流程交付 tools 修复版；安装是否实际使用此版本由目标 KB 的 tools_package_path 核实，不凭 main 合并推断。

## 7. 范围排除

- 不改状态机、`gates.json`、Pipeline、Agent、权限矩阵、tools `dir-graph.yaml` 的 required_roots；测试计数/命令能力说明同步不是 gate 变更。
- 不改 durable-tx、writeback-apply 或注册核心其他行为；**原“注册核心零改动”的排除只对 FR-10 默认值修正撤销**，不得外扩。
- 不改 multica 代码或其 CUSTOM 台账；不新增独立 CR、新 Skill、模块/导出、初始化 journal/锁/故障点；不托管仓库/凭据/审批。
- 不修复或重写既有异内容 KB 账本；不迁移历史 source、不新增 source-set、不强改注册指纹；本 CR cr.md 与注册摘要作为历史事实保留。
- 不修改既有签字 PLAN/approval/merge evidence，不在他项 KB trunk 上直接补账，不把 AIFI-35 恢复纳入本 CR 验收。
- AIFI-35 仅在其 tools 路径确实指向修复版、且确认没有在途 traceability 事务后，由其负责 Agent 按原业务命令恢复节点 4→5；这是交付后的独立运维边界，不是本轮自动化通过的替代证据。
- 不重复注册已归档的 CR-2026-073 或将其并回本项，不自行重新解释“不关联 CR”的 origin 空值。
