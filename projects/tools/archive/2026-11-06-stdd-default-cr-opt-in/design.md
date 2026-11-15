# 工作区入口精简与 STDD／CR 流程隔离 — 技术设计

> Change：`2026-11-06-stdd-default-cr-opt-in`；已确认提案：`canonical/proposals/2026-11-06-stdd-default-cr-opt-in.yaml`（Gate 1 原文：`确认 Gate 1，standard`）。
> 本文是当前有效设计，按 2026-11-15 的实际状态整体重写；偏离记录见 `pending-adjustments.md`，批准状态以 STDD 记录为准。

## Context

- `documentation` 任务：修改入口文档和说明，不增加运行时代码、路由器、状态机或测试框架。
- 三根：资源根 `../stdd`、业务根 `../tools`、数据根 `projects/tools`（相对知识库根）。STDD CLI 从业务根运行，所有命令显式带本 ID。知识库根没有 `.stdd/binding.yaml`；tools、multica 的绑定分别指向 `projects/tools`、`projects/multica`。
- 实施现状（2026-11-15 实测）：六个目标文件已按提案落地——知识库 `AGENTS.md`（写前 6,287 → 现 2,233 个 LF 字符，这是加载成本，不是请求 token）、`README.md`、`CONTEXT.md`、`dir-graph.yaml` 说明，tools `AGENTS.md` 分层，全局 `~/.pi/agent/APPEND_SYSTEM.md` 第 2 行。
- 知识库 `AGENTS.md` 成品含本 change 之外由用户直接加入或调整的条款（STDD 记账、记录完整性、其他账本等）。本 change 不回退也不追认它们；验收对象是成品全文，写前基线只用来确认保护点没有丢失。
- tools `AGENTS.md` 仍有一段 CR 驳回路由描述与现行 `dir-graph.yaml#change-request-track.state_machine` 不一致：需求审批驳回（AGENTS：在 `requirement-reviewing` 内自环；graph：回到 `drafting`）和开发启动暂缓（AGENTS：`write-dev-tasks` 自环；graph：回到 `tech-design-reviewed`）。见 D5。
- 现行 STDD 事实（2026-11-15 对源码核实）：
  - Gate 1、Gate 2 在 `.stdd.yaml` 中是无输入指纹的历史批准，现行 CLI 视其为“无法证明当前有效”，须用户确认后用 `gate approve --reapprove` 重新冻结（`gate.py` 无指纹须重签并重新冻结）。
  - 证据计划 `stdd-evidence-plan-v1` 支持 `command` 与 `manual`，也支持 `coverage: not_applicable`；change 内的 agent spec 优先于项目级。
  - 冻结输入只接受业务根和数据根内的路径；知识库根顶层文件和用户全局文件无法被冻结。
  - DELIVER 的记录仓提交清单只允许 `projects/<project_id>/` 内路径，知识库顶层文件不在其中。

## 本 change 承诺的保证

| # | 保证 | Capability | 证据 |
|---|---|---|---|
| G1 | 六类输入得到正确的入口决定，Gate、CR 审批与 Git／部署授权互不替代 | workflow-routing | TC-WFR-001（人工，盲评） |
| G2 | 精简后 D2 的保护点没有丢失，README／CONTEXT／tools 入口只有批准范围内的差异 | prompt-governance | TC-PG-001（人工，保护点对照） |
| G3 | `dir-graph.yaml` 业务配置不变；全局文件第 2 行等于批准原文 | prompt-governance | TC-PG-002（命令） |
| G4 | 对 tools `AGENTS.md` 内容有结构依赖的既有测试仍通过 | prompt-governance | TC-PG-003（命令） |

另有一条汇报义务，不单设检查：报告分别写明实际执行、范围和未覆盖；静态检查与人工评审不证明运行时路由、部署、模型实际遵循或 token 占比。

## Decisions

### D1. 只统一入口选择，不统一两个流程的内部状态

| 输入 | 入口决定 | 写入与授权边界 |
|---|---|---|
| 明确只读分析／问答 | 不启动任何新变更 | 只读分析不创建变更；不得因出现“需求”等词自动注册 |
| 接手可识别的已有 STDD／CR | 沿用原流程 | 默认值或一句换流程要求不构成迁移批准；冲突时停下确认 |
| 新开发，未指定流程 | 默认 STDD | 先确定目标业务仓、绑定及三根，再加载当前阶段技能 |
| 用户显式选择 tools CR 的新变更 | 加载 tools 现行 CR 入口 | 走合法注册与节点，不手写状态、审批或任务索引 |
| 身份、目标、绑定或归属冲突／不明 | 停止并询问 | 不猜目录、不回落旧模式、不同时写两个流程 |
| 仅有一个 STDD Gate 或另一流程的批准，却要求推进 CR、提交、推送或部署 | 独立核对所属授权 | 两流程不互认审批；Gate 不授权 Git 或部署 |

**为什么**：一个变更只有一个流程权威；默认值只解决新变更的缺省选择。

**排除的备选**：全局强制 STDD 会误接管旧 CR；两套规则同时常驻会继续冲突；统一路由器或流程字段超出当前需求。

### D2. 根入口保留共同底线，其余按任务和阶段加载

精简时以下保护点不得丢失。按语义判断，不锁定措辞；它们可以在根入口，也可以在根入口引用的权威文件中，但不能缺失。

1. 事实断言先核实；读取目标仓自身规范；multica 英文注释与 CUSTOM 登记要求不因流程变化消失。
2. 执行账本（CR 状态、审批、任务、额度、索引等）只经所属合法入口及入库、可测试的版本化脚本处理；禁止会话内现写脚本；版本化不替代权限、唯一入口、CAS、审计或门禁；无合法入口则不改。
3. 人工记录（设计偏离、STDD 记账）：保留原记录与扩展字段；依据原话或可靠来源区分事实、决定、授权与未决；核对归属、可解析性与差异；`resolved` 如实；归属不明按执行账本处理。精准编辑的授权范围以根入口现行条款为准（Skill 明确要求且无专用入口时），不替代 Gate、验证或阶段推进规则。
4. 记录不等于批准或执行；STDD Gate 与 CR 审批互不替代；Gate 不自动授权 Git 提交、推送或部署。
5. 哈希、跨行正则、逐行解析前规范化 CRLF；解析失败硬失败，不以空集合静默降级。
6. 不覆盖累积发布基线；`docs/product`、`docs/analysis` 不被强行搬入 CR `specs`；历史 CR 与 delivery 保持其目录职责。
7. 不据主 checkout 的陈旧快照猜在途 CR 状态；CR 操作根以 crctl 返回为准，不自行拼 worktree 路径。
8. 定制台账按目标仓现有格式登记；追溯用真实流程标识，不为 STDD 编造 CR 编号；格式不接受时停止并确认。

**为什么**：这些是跨流程的损失预防；CR 的具体命令、状态计数和事故经过不是常驻底线。安全保证优先于字符量，不设 token KPI。

### D3. STDD 定位依赖业务仓绑定，而非知识库 cwd

入口先识别目标业务仓，读取其 `.stdd/binding.yaml`，再按真实安装信息确认资源根、记录根及当前阶段技能。已安装技能优先；未公布 slash command 时读取对应资源技能，不声称命令已注册。无绑定或路径不明时停止，不自动 init、install、upgrade 或回退。知识库根无绑定本身不是失败：目标业务仓明确且其绑定有效时，核实三根后从业务仓执行。知识库根不新增绑定或项目配置。

### D4. tools 包维护与 CR 执行规则分别适用

`../tools/AGENTS.md` 常驻包职责、事实源和工程规范；修改 Agent／Skill／Pipeline 才要求相关矩阵、索引及相邻定义；执行 CR 或修改 CR 流程时读取完整流程及相关 Pipeline／Skill。使用 tools 能力或 OutputGuard 不等于进入 CR。包边界、唯一 owns、Pipeline 引用、lint、受控账本、门禁向前兼容和单一事实源保证全部保留。

### D5. 只修说明，不修改运行语义或事实源结构

| 文件 | 修改 | 明确不改 |
|---|---|---|
| 知识库 `AGENTS.md` | 入口重组；按需加载；修正陈旧说明（已实施） | CR 状态机／参数副本；D2 保护点 |
| 知识库 `README.md` | 新增当前工作流入口及 STDD 记录目录指引（已实施） | 已有产品规格与参考资料 |
| 知识库 `dir-graph.yaml` | 修正顶部回退注释；可更新 docs／tools 两个 repository 的 `description`（已实施） | 其余全部业务配置 |
| 知识库 `CONTEXT.md` | 仅在开头说明术语不自动启用某流程（已实施） | 既有领域定义 |
| tools `AGENTS.md` | 阅读路由与工程／CR 作用域分层（已实施）；**CR 驳回路由段不再复写转换名，改为“驳回必须走显式回退转换、不得停留原状态硬改产物；具体转换以 `dir-graph.yaml#change-request-track.state_machine` 为准”（待实施，tasks B1）** | 索引、矩阵、Pipeline、Skill、gates 与脚本 |
| 全局 `APPEND_SYSTEM.md` | 第 2 行为“安全与数据完整性是底线；在此前提下优先满足用户明确要求。涉及不可逆操作、数据丢失或敏感信息时，先明确影响并取得必要确认。正确性优先于简洁。”（已实施） | 其余行、模型／权限／工具配置 |

`dir-graph.yaml` 的描述字段是展示信息；业务配置比较须排除这两个允许变化的 `description`，不能把整份解析对象不相等误判为业务配置被改，也不能放行其他字段。

**为什么 tools 驳回段在范围内**：它属于提案要消除的“落后于现行契约的 CR 说明”，且位于 C5 已覆盖的同一文件；改成引用权威符合“事实只有一个归属”，不新增复写。

### D6. 验收：四个检查，各自对应一条保证

证据计划见 `test-plan.md`。

- **TC-WFR-001（人工，盲评）**：独立评审者只读知识库入口与 tools 入口，不看 D1 表，对六类输入各答“选哪个流程、是否创建／修改、还需何种授权、何时停止”；主会话与 D1 表逐行比对，并检查入口中没有相反的无条件要求。
- **TC-PG-001（人工）**：对照 D2 八个保护点，在成品中逐项指出所在位置或迁往的权威文件；核对 README／CONTEXT 差异只含批准的入口说明且领域定义未变；核对 tools `AGENTS.md` 的包边界、矩阵／索引要求仍在，且不再含复写的状态转换表或固定计数。
- **TC-PG-002（命令）**：解析 `dir-graph.yaml` 与固定基线提交 `1a409847af4f049dbbd06ed8e86e6d7267d7496a` 的版本比较，除 `ai-first-platform-docs`、`tools` 两个仓库的 `description` 外完全相等；全局文件第 2 行的 SHA-256 等于批准原文的哈希。同次运行打印五个文件的 LF SHA-256。
- **TC-PG-003（命令）**：运行 `skills/shared/crctl/scripts/test/contract-scan.test.mjs`。该文件读取 tools `AGENTS.md` 的 `### 修改 Pipeline` 节并断言其中第 9 条；这是对 `AGENTS.md` 内容有结构依赖的唯一既有测试（对 tools 源码 `git grep` 定位）。

**取舍**：
- 不做“某句话是否存在”的字符串断言（它们钉死措辞，措辞正当变化时反而报错）。
- 不设字符量上限；字符量只在报告里作为测量值。
- tools 全量 `quality.test` 不属于本 change 的保证：被改的 tools 文件只有 `AGENTS.md`，其结构依赖已由 TC-PG-003 覆盖；全量套件含需要受限身份、可能触及宿主的隔离用例，在本机既不安全也不会通过。C2 按“未运行及原因”如实记录，由用户在 Gate 3 确认该处置。
- 知识库四个顶层文件和全局文件无法被 CLI 冻结。TC-PG-002 在同次运行中打印它们的哈希，人工评审的确认语句须引用这些哈希，交付前提交清单确认时再重算核对。这是人工纪律，不是机器保证，报告原样说明。
- 不新增项目级 CP 副本，不写共享报告，不制造 `coverage.json`；覆盖率声明为 `not_applicable`（无产品代码，覆盖采集仅支持 pytest-cov）。

### D7. 交付归属

| 对象 | 归属 | 交付方式 |
|---|---|---|
| tools `AGENTS.md` | tools 业务仓 | STDD 业务提交 + `bind-commit`（它是冻结的 `project` 输入，逐字节核对） |
| 知识库 `AGENTS.md`、`README.md`、`CONTEXT.md`、`dir-graph.yaml` | 知识库仓顶层，不在 `projects/tools/` 内 | 不在 STDD 记录仓提交清单内；由用户另行逐文件授权，在知识库仓普通提交；`AGENTS.md` 含本 change 之外的修改，只能整文件交付；提交前重算哈希并与 test-report 核对 |
| 全局 `APPEND_SYSTEM.md` | 无仓库 | 已生效；只记录，不提交 |
| 本 change 的记录 `projects/tools/**` | 知识库仓 | STDD 记录提交 |

提交、推送与部署仍需独立授权；Gate 确认不是提交授权。

## Architecture

```text
请求 + 已有变更身份 + 目标业务仓
  -> 根入口共同底线和冲突检查
  -> 只读 / 已有流程 / 新变更默认 STDD / 显式 CR / 停止询问
  -> 所选流程原生定位与当前阶段资料
  -> 所属合法入口；Gate、提交与部署授权各自独立判断
```

无新配置、流程字段、命令包装器或状态映射；STDD `.stdd.yaml` 与 CR 账本仍各自唯一。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|---|---|
| 提示词规则不等于运行时强制 | 不声称已部署或已证明模型行为；报告只写静态与评审结果 |
| 两个流程同时出现导致覆盖 | 已有身份优先，冲突先停；禁止映射、双写与审批互认 |
| 知识库 `AGENTS.md` 混有本 change 之外的修改 | 只能整文件交付，由用户在提交清单确认；本 change 不回退它们 |
| 顶层文件与全局文件无法由 CLI 冻结 | 同次运行打印哈希、确认语句引用、交付前重算；报告写明这是人工纪律 |
| 全局文件无版本控制 | 只精确比较第 2 行；其余行没有机器基线，实施时已按写前哈希核对一次（ADJ-001） |
| `tools/CLAUDE.md` 仍要求无条件读取完整 README，与按需加载冲突 | 不在提案范围；不宣称 Claude 入口已闭合，记入范围外发现 |
| DELIVER 在归档后合并 Canonical，可能撞上 STDD 已知的 Guard／归档衔接问题 | 属 STDD 工具问题，不在本 change 范围；遇到即停止并报告，不绕过 |

## 写前基线（用于 TC-PG-001 对照）

| 文件 | 基线 | LF SHA-256 |
|---|---|---|
| 知识库 `README.md` | 知识库提交 `1a409847af4f…` | `49d2a566c78e6188de3a8b3378648eee6efe36f264507c8a5484681c5121a527` |
| 知识库 `dir-graph.yaml` | 同上 | `9de241e6dd02d17f84b6048c88c129944f4ab66f80f17009aa7e8caf4717021b` |
| 知识库 `CONTEXT.md` | 同上 | `32334ba59f4a63c39db68d4662d68e39989e1bf470986c24443ee8cef0d5d8b2` |
| 知识库 `AGENTS.md` | 同一提交的原文加当时未提交的账本条款（重建过程见 ADJ-002） | `74ae121374ae682307ea69b0845ee13b77decb5a64fdc4327ff97078ad7ee2c0` |
| tools `AGENTS.md` | tools 提交 `75ec007395b3…` | `9b98ed84525ea0a875ee18cf0a8b4fd08fbb0a92f18e86b245c50fff1fa5dd88` |
| 全局 `APPEND_SYSTEM.md` | 设计时的文件；实施时发现第 2 行已被用户改动（ADJ-001） | `a761488e765bb29a807e3c50eeafc15622b1cd7b623bf900c50c0590887bf163` |

前三行和 tools 行已对照对应提交实际核对一致（2026-11-15）。基线用来定位保护点原先的位置，不是要求成品与它逐字对应。
