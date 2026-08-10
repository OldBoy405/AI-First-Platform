---
id: CR-2026-028-prd
type: PRD
cr-ref: CR-2026-028
title: tools 流程步骤优化 v2 — 前移优化项独立 CR（tools-root 唯一解析 + Skill 路径统一 + crctl 配置加载修正 + cr-init 注册入口复用）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-10T16:39:11+08:00"
updated: "2026-08-10T17:01:08+08:00"
---

# PRD — tools 流程步骤优化 v2：前移优化项

## 1. 概述

### 1.1 问题陈述

CR-2026-027 已完成 tools 流程优化 Phase 0/1 的基线事实统一与正确性修复，但目标 workspace 如何定位 tools 包仍存在多套隐式规则：当前 `crctl.mjs` 的状态机 loader 会依次尝试 workspace `dir-graph.yaml`、`<workspace>/tools/dir-graph.yaml` 与执行脚本所在 package root；Pipeline loader 会尝试 `<workspace>/tools/pipeline-templates/` 与 package root；gates/default controlled-shell rules 又固定跟随执行脚本所在 checkout。Skill、Pipeline 与 Adapter 中还存在大量 `node tools/skills/...` 或 `$WORKSPACE/tools/...` 当前用法。

在 AI First Platform workspace 中，真实 tools 包位于 sibling `../tools/`，workspace 内同名 `tools/` 是残留空壳。现有行为可能误读空壳目录，或让状态机/Pipeline 与 gates/rules 来自不同 tools checkout。knowledge-base linked worktree 又带来第二个事实：CR 阶段文件应在 worktree 中读写，但 `tools_package_path: "../tools"` 若相对于 worktree checkout 解析会失效。继续依赖 package-root 回退会掩盖配置错误，并使同一项目实际使用哪个 tools 包取决于启动入口。

Registration 侧也存在文档漂移：`crctl cr-init` 已支持一次传入 title、summary、source、target-version 等元数据，但 `requirement-register` 仍描述建档后直接补写受控 frontmatter，Pipeline prompt 还重复描述 cr-init 建档动作。

**问题边界**：本 CR 只修正基础路径与入口契约，复用现有 crctl、cr-init、Adapter 模板和 writeback 脚本；不建设 Runner、installer、自动路径修复器、版本 pin 或跨仓上下文框架。

### 1.2 解决方案摘要

1. 以 Installation Workspace 的 `dir-graph.yaml#workspace.tools_package_path` 为 Tools Root 唯一事实源；相对路径以 Installation Workspace 为基准，绝对路径直接使用，最终 realpath 归一；配置或身份验证失败统一 `TOOLS_PACKAGE_NOT_FOUND`，无隐式回退。
2. 区分 Operational Workspace（CR 文件实际读写 checkout）与 Installation Workspace（knowledge-base 主 checkout、Tools Root 安装基准）；knowledge-base linked worktree 通过 Git common-dir 找到安装基准，非 knowledge-base worktree 显式复用 `execution_context.knowledge_base_worktree`。
3. 在 `crctl.mjs` 内增加最小、单值惰性 resolver，不拆公共库；state machine、Pipeline、gates、默认 controlled-shell rules 统一从 Tools Root 加载，保留已有显式 `CRCTL_RULES_PATH` 覆盖。
4. 只修 active executable surfaces：active Skill/Pipeline、Adapter/CI 模板与安装说明、当前入口文档；静态配置安装时物化 `{TOOLS_ROOT}`，绝对路径只进入本机 local settings。
5. Registration 直接一次调用现有 `cr-init` 写齐元数据，删除模型二次补写 frontmatter 与 Pipeline 重复描述；cr-init 代码零新增能力。
6. 删除 tools 包自身无人消费的 `target_install_path: "tools/"`；multica 本轮只更新 `CUSTOM.md` 记录现存跨仓消费点，代码暂缓。

### 1.3 事实基线

| # | 已核实事实 | 依据 |
|---|---|---|
| B-1 | workspace `dir-graph.yaml#workspace.tools_package_path` 已声明 `../tools`，真实 tools 包为 sibling；workspace 内存在同名空壳目录 | workspace `AGENTS.md`、`dir-graph.yaml` |
| B-2 | `loadStateMachine` 当前搜索 workspace graph、`workspace/tools`、`PACKAGE_ROOT`；`loadPipeline` 搜索 `workspace/tools` 与 `PACKAGE_ROOT` | tools `skills/shared/crctl/scripts/crctl.mjs` |
| B-3 | `gates.json` 与默认 controlled-shell rules 当前跟随执行脚本 checkout，可能与状态机/Pipeline 分裂 | crctl 常量 `GATES_PATH`、`RULES_PATH` |
| B-4 | `main()` 在分发实际子命令前 eager `loadGates()`；`help` 在 workspace 解析前返回 | crctl `main()` |
| B-5 | active writeback Skill/Pipeline、crctl Skill 与 Adapter 模板仍存在 `tools/skills/...`、`$WORKSPACE/tools/...` 当前命令 | tools active Skill/Pipeline/Adapter 定向检索 |
| B-6 | `cr-init` 已支持 `--summary`、`--source`、`--target-version` 且 CR-2026-028 注册已一次写齐 | crctl help、cr-init 现有测试与本 CR 注册实录 |
| B-7 | tools `dir-graph.yaml#workspace.target_install_path: "tools/"` 无代码消费，与目标 workspace 的唯一声明冲突 | tools 定向检索 |
| B-8 | multica 已有生成器/跨工具测试猜测 sibling tools 路径；生产 `MULTICA_CONTROLLED_SHELL_RULES` 已使用显式绝对路径 | multica 现有代码与 `CUSTOM.md` |
| B-9 | 现有 crctl 测试为零依赖 CLI 黑盒套件，公共 `makeWorkspace()` 可承接严格配置 | `crctl.test.mjs` |

### 1.4 质询决策

| # | 决策 | 拍板结果 |
|---|---|---|
| D-1 | 统一对象 | 统一 Tools Root 契约，不强制所有消费者共享运行时代码；当前 resolver 留在 crctl 单文件内 |
| D-2 | 绑定时机 | 动态调用方运行时解析；IDE hooks/CI 安装时物化 |
| D-3 | 缺配置行为 | 硬失败，不保留 package-root 或 workspace/tools 兼容回退 |
| D-4 | 身份标志 | 固定验证 AGENTS.md、dir-graph.yaml、skills/_index.yml、crctl.mjs 四项 |
| D-5 | 修改范围 | active executable surfaces 白名单；历史/生成内容不批量替换 |
| D-6 | multica | 现存消费点登记 CUSTOM“未做”，本轮不改代码，不新增 resolver |
| D-7 | Registration | cr-init 能力已完成，本项只修 Skill/Pipeline 漂移 |
| D-8 | 调用内复用 | 单进程单值惰性缓存，不创建 execution context |
| D-9 | worktree 基准 | Operational/Installation Workspace 分离，Git common-dir 定位安装基准（ADR-0003） |
| D-10 | 路径类型 | 允许相对与绝对路径，realpath 归一；仓库配置推荐相对路径 |
| D-11 | 静态路径变化 | 重新执行安装替换，不建设自动修复器 |
| D-12 | tools 版本 | 只验证包身份，不做 branch/SHA/version pin |
| D-13 | package 配置 | Tools Root 统管 state machine、Pipeline、gates、默认 rules；保留 CRCTL_RULES_PATH |
| D-14 | 自动发现 | 只覆盖 knowledge-base checkout/worktree；其他参与仓显式传 knowledge_base_worktree |
| D-15 | 第二安装声明 | 删除 tools `target_install_path`，不保留默认安装位置字段 |
| D-16 | 静态配置落盘 | 仓库保留 `{TOOLS_ROOT}` 模板；本机绝对路径只进 local settings |
| D-17 | 测试强度 | 扩展现有黑盒套件；不建 resolver/Adapter 独立测试框架 |

### 1.5 契约优先级与版本口径

`cr.md#summary` 是 2026-08-10 15:06 注册时的快照，早于本 CR 的 grilling 拍板，且当前没有允许修改 summary 的 crctl 专用入口；因此不通过模型直接编辑受控 frontmatter。该快照中的以下三点已被本 PRD D-3/D-4/D-9 与同步修订后的 source 明确取代：

1. “相对 workspace root”改为“相对 Installation Workspace”；
2. 三标志验证增加 `dir-graph.yaml`，固定为四标志；
3. 删除“独立运行时回退 crctl package root”，统一为配置错误硬失败。

需求评审、审批、SDD 与实施以本 PRD 和 `docs/analysis/tools流程步骤优化v2-前移优化项.md` 的质询后契约为准；注册快照只保留审计来源，不作为并行实施口径。

`target-version: tbd` 的批准口径：本 CR 是 tools 包内部契约优化，不进入 AI First Platform 产品版本号递增链路；需求审批确认范围即可，不为此虚构产品版本。

## 2. 用户故事

- **US-1** 作为 tools 流程使用者，我希望每个项目只需在 workspace 目录图声明一次 tools 包位置，即可从主 workspace、knowledge-base CR worktree或其子目录稳定使用同一 tools 包。
- **US-2** 作为 CR 执行者，我希望 workspace 内即使存在空壳 `tools/`，crctl 也不会误读或静默回退，而是使用显式声明或给出明确错误。
- **US-3** 作为 tools 维护者，我希望状态机、Pipeline、gates 与默认 controlled-shell rules 来自同一 Tools Root，避免不同 checkout 配置混用。
- **US-4** 作为 Skill/Pipeline/Adapter 使用者，我希望当前执行指令不假设 tools 固定安装在 workspace 的 `tools/` 子目录。
- **US-5** 作为需求注册执行者，我希望一次 `cr-init` 原子写齐注册元数据，不再由模型第二次编辑受控 frontmatter。
- **US-6** 作为维护者，我希望本次修改只覆盖真实 active surface，并复用现有黑盒测试，不引入尚无消费者的 Runner、installer 或共享路径框架。

## 3. 功能需求

- **FR-1（Tools Root 唯一契约）**：Installation Workspace 的 `dir-graph.yaml#workspace.tools_package_path` 是 Tools Root 唯一声明；相对值以 Installation Workspace 为基准，绝对值直接使用，结果经 realpath 归一。配置缺失、非字符串/空值、路径不存在或身份标志不完整统一返回 `TOOLS_PACKAGE_NOT_FOUND`，detail 必须说明配置值、解析路径或缺失标志；不得尝试 workspace 同名 `tools/`、cwd、调用方 package root 或正在执行的 crctl 所在 checkout。
- **FR-2（workspace 双根语义与 worktree 定位）**：Operational Workspace 负责 CR 阶段文件读写；Installation Workspace 负责 Tools Root 路径基准及 workspace-owned `.rayai-worktrees/` 根。普通 checkout 两者相同；knowledge-base linked worktree 通过 Git common-dir 找主 checkout。`crctl worktree-path` 必须以 Installation Workspace 拼接 `.rayai-worktrees/{bucket}/requirement/{cr}`，从 linked worktree 调用不得返回嵌套的第二个 `.rayai-worktrees`；`push-progress`、`pull-progress`、`resume-from-remote` 继续只消费该命令结果，不自行拼路径。不得改写 worktree graph、创建 symlink/junction或新增 `--tools-root`。tools/multica worktree 必须显式使用 requirement-register 已输出的 `knowledge_base_worktree` 作为 `--workspace`，由其 Git common-dir 得到 Installation Workspace；不得按分支名、CR-ID 或目录扫描猜测。
- **FR-3（四标志身份验证）**：resolver 固定验证 `{toolsRoot}/AGENTS.md`、`dir-graph.yaml`、`skills/_index.yml`、`skills/shared/crctl/scripts/crctl.mjs`；这四项只证明 tools 包身份，不验证 Git branch、commit SHA、版本或全部资源完整性。Pipeline、gates 等目标文件继续由消费者按需校验并沿用现有专用错误码。
- **FR-4（crctl 配置来源收敛）**：在现有 `crctl.mjs` 内实现单值惰性 Tools Root resolver，同一进程只解析一次，不拆公共模块。`loadStateMachine` 只读 `{toolsRoot}/dir-graph.yaml`；`loadPipeline` 只读 `{toolsRoot}/pipeline-templates/`；`loadGates` 只读 `{toolsRoot}/skills/shared/crctl/gates.json`；默认 controlled-shell rules 只读 `{toolsRoot}/skills/shared/controlled-shell/rules.json`。保留显式 `CRCTL_RULES_PATH` 覆盖，不新增其他覆盖入口。`help` 保持无需 workspace；其余子命令沿用现有 eager gates 行为。
- **FR-5（active 执行入口统一）**：只修改 §3.1 的 active surface 白名单；其中实际命令改用 `{TOOLS_ROOT}/skills/...` 逻辑路径并明确来源。动态调用方运行时解析；静态模板安装时物化；所有 Adapter 模板统一字面占位符 `{TOOLS_ROOT}`，删除 `{TOOLS}`/`{WORKSPACE}` 同义占位符。仓库不得提交含本机绝对路径的物化 settings；白名单外历史分析、审查报告、生成 HTML、OpenWiki、inactive/old 内容不做全仓替换。
- **FR-6（Registration 复用 cr-init）**：`requirement-register` 调用现有 `crctl cr-init` 时一次传入 title、owner-requirement、summary、source、target-version；删除建档后直接编辑 `cr.md` frontmatter 的步骤；合并 requirement-authoring Pipeline 中重复的 cr-init 建档描述。三文件原子建档、worktree-path 与 repositories 派生语义保持；不修改 cr-init 实现，不新增 wrapper、register-preflight、registration-check、stage-context 或 Registration Runner。
- **FR-7（删除第二安装位置声明）**：删除 tools `dir-graph.yaml#workspace.target_install_path`，并把同文件“固定挂载到 tools/”的当前描述改为由目标 workspace `tools_package_path` 绑定；不新增替代字段。
- **FR-8（multica 延后项登记）**：本 CR 不修改 multica 代码；`CUSTOM.md#未做` 必须列出现存 sibling tools 猜测点及后续修复方式。生成器后续要求显式 tools root，跨工具测试后续要求显式 `CRCTL_PATH`/rules path；生产 `MULTICA_CONTROLLED_SHELL_RULES` 继续作为安装时物化绝对路径，不新增 multica resolver。
- **FR-9（最小回归验证）**：扩展现有 `crctl.test.mjs`：公共 workspace fixture 显式绑定隔离的最小 tools fixture；表驱动覆盖相对/绝对路径、空壳目录、缺配置、无效路径、四标志缺失；增加一个 Git linked-worktree 黑盒场景并同时验证 Tools Root 与 `worktree-path` 的 Installation Workspace 基准；使用四类 sentinel 配置分别通过 CLI 行为证明 state machine、Pipeline、gates、默认 rules 均来自声明的 Tools Root，并验证 `CRCTL_RULES_PATH` 覆盖。单值惰性缓存以“所有 loader 调用同一 module-scope resolver 且只有一个成功值槽”的代码审查断言验收，不新增 telemetry。复用现有 cr-init metadata 测试；active 文档/模板按 §3.1 精确范围与禁止模式定向检索；不新增 resolver 测试包、mock filesystem、IDE E2E 或跨平台 Adapter matrix。

### 3.1 active surface 白名单与检索口径

| 类别 | 本 CR 可修改文件 |
|---|---|
| 核心实现与测试 | `dir-graph.yaml`；`skills/shared/crctl/scripts/crctl.mjs`；`skills/shared/crctl/scripts/test/crctl.test.mjs` |
| crctl / Registration | `skills/shared/crctl/SKILL.md`；`skills/requirement/requirement-register/SKILL.md`；`pipeline-templates/requirement-authoring.pipeline.json` |
| 生命周期同步 | `skills/sync/push-progress/SKILL.md`；`skills/sync/pull-progress/SKILL.md`；`skills/sync/resume-from-remote/SKILL.md` |
| writeback | `skills/writeback/writeback-prd-sdd/SKILL.md`；`writeback-tasks/SKILL.md`；`writeback-traceability/SKILL.md`；`skills/writeback/scripts/test/writeback.test.mjs`；`pipeline-templates/feature-writeback.pipeline.json` |
| Adapter / CI | `skills/shared/crctl/adapters/**` 的现有文件 |

定向检索在上表范围内要求以下当前命令模式零命中：`node tools/skills/`、`$WORKSPACE/tools/`、`<workspace>/tools/`、`$CLAUDE_PROJECT_DIR/tools/`、`{TOOLS}/tools/`、`{WORKSPACE}/tools/`。包内源码使用 `import.meta.url` 定位兄弟文件允许保留；`ARCHITECTURE.md` 历史否决示例、`skills/reviewer-panel.yaml` 自路径注释、`skills/shared/engineering-docs/SKILL.md` 概念引用及历史/生成/inactive 内容明确排除。CI 可以把实际 checkout 目录赋给 `TOOLS_ROOT`，但执行命令不得直接硬编码 `node tools/skills/...`。

## 4. 非功能需求

- **NFR-1（不过度设计）**：不新增 Runner、installer、watcher、repairer、bootstrap launcher、execution context、共享 resolver library、缓存文件或新 crctl 子命令。
- **NFR-2（单一事实源）**：除已有显式 `CRCTL_RULES_PATH` 外，不得出现第二 Tools Root 配置、package-root 兼容回退或 workspace/tools 隐式候选。
- **NFR-3（可移植性）**：仓库中的 workspace 配置推荐相对路径；Adapter 仓库模板保留 `{TOOLS_ROOT}`；不得提交本机绝对路径。Windows 盘符、symlink/junction 由 Node path/realpath 处理，不手写平台分支。
- **NFR-4（兼容业务语义）**：不得修改现有状态机转换、gate/passCondition、审批、CAS、账本、worktree bucket 与 human approval 语义；仅改变 package-owned 配置的定位方式和 prompt 路径表达。
- **NFR-5（零新增依赖）**：实现使用 Node 标准库与现有 YAML 解析能力；测试继续使用 `node:test`、`node:assert` 和现有 Git CLI，不新增 npm 依赖。
- **NFR-6（行尾与失败纪律）**：读取 YAML 后按现有规则兼容 CRLF/LF；解析或结构定位失败必须硬失败，不得以空配置或 package-root fallback 静默继续。
- **NFR-7（可诊断性）**：`TOOLS_PACKAGE_NOT_FOUND` detail 必须足以区分字段缺失、路径不存在与身份标志缺失；成功路径继续通过现有 source path 输出暴露实际加载文件，不新增全局 telemetry。

## 5. 验收标准

- **AC-1（FR-1/FR-3）**：相对 `tools_package_path` 与绝对 `tools_package_path` 均解析到 realpath 后同一目录；四个身份标志齐全时通过。
- **AC-2（FR-1/FR-3）**：字段缺失/空值/非字符串、目标目录不存在、四标志任一缺失均返回 `TOOLS_PACKAGE_NOT_FOUND`，错误 detail 指明具体原因且无其他候选读取。
- **AC-3（FR-1）**：在 workspace 内创建包含同名子路径的空壳 `tools/` 后，crctl 仍只使用声明的 Tools Root；将声明路径破坏后必须失败，不得转读空壳。
- **AC-4（FR-2）**：从 Installation Workspace 根目录及任意子目录调用，解析结果相同；从 knowledge-base linked worktree 根目录及子目录调用，CR 文件来自该 worktree而 Tools Root 相对于主 checkout 解析。对三个 active repo 运行 `worktree-path` 均返回主 checkout 下现有路径，结果不得包含重复的 `.rayai-worktrees/.../.rayai-worktrees`；`push-progress` 的 worktree map 前置校验可据此通过。
- **AC-5（FR-2）**：从 tools/multica worktree 显式传 `--workspace <knowledge_base_worktree>` 可用，并由该 knowledge-base worktree 的 Git common-dir 找到 Installation Workspace；不传时不承诺反推对应 CR，且实现中不存在分支名、CR-ID 或 `.rayai-worktrees` 扫描逻辑。
- **AC-6（FR-4/FR-9）**：隔离 fixture 为四类资源设置可辨识 sentinel：状态机使用仅 fixture 存在的合法转换、Pipeline 使用仅 fixture 存在的 nodeRef/passCondition、gates 使用仅 fixture 要求的证据文件、rules 使用仅 fixture 允许/拒绝的 git shape；分别调用公开 CLI 并断言对应行为，以证明四类资源来自声明的同一 Tools Root。测试不要求新增 source 输出字段；执行脚本来自另一 checkout 时 sentinel 结果不变。
- **AC-7（FR-4）**：设置有效 `CRCTL_RULES_PATH` 时仍使用显式 rules；未设置时使用 Tools Root rules；无新增 gates/rules 覆盖环境变量。
- **AC-8（FR-4）**：代码评审确认 state machine、Pipeline、gates、默认 rules 四个 loader 均调用同一 module-scope resolver，resolver 仅维护一个成功值槽且无 Map/文件缓存/telemetry；一个需要多个 loader 的黑盒命令使用同一 fixture 行为成功。`crctl help` 在无 workspace 时仍成功。
- **AC-9（FR-5）**：§3.1 白名单中的六个禁止模式定向检索零命中；所有 Adapter 模板只使用 `{TOOLS_ROOT}`，安装说明明确其来自 `workspace.tools_package_path`。列明的白名单外允许例外不计失败。
- **AC-10（FR-5/NFR-3）**：版本库 diff 中无新增本机绝对路径；local settings/CI 的物化边界说明清楚，未新增自动安装或修复代码。
- **AC-11（FR-6）**：requirement-register 的一次 cr-init 调用传齐 summary/source/target-version；成功后无模型二次编辑 frontmatter 指令；Pipeline 中 cr-init 三文件建档动作只描述一次。
- **AC-12（FR-6）**：现有 cr-init metadata 黑盒测试通过，`cr.md`、`_backlog.yml`、`_index.yml` 一次建档结果不回归；cr-init 实现无为本 CR 新增的子命令或 wrapper。
- **AC-13（FR-7）**：tools `dir-graph.yaml` 不再含 `target_install_path` 或固定安装到 `tools/` 的当前权威描述；目标 workspace `tools_package_path` 保持唯一安装位置声明。
- **AC-14（FR-8）**：multica 代码 diff 为空；`CUSTOM.md#未做` 准确列出四类现存消费点、显式参数升级路径及 `MULTICA_CONTROLLED_SHELL_RULES` 保留语义。
- **AC-15（FR-9）**：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，包含路径表驱动、四类 sentinel、`CRCTL_RULES_PATH` 覆盖与 linked-worktree/worktree-path 场景；fixture 不修改真实 tools checkout，且没有新增独立 resolver/Adapter 测试框架。
- **AC-16（NFR-4）**：现有状态机、gate、approve、账本、cr-init、worktree-path 相关回归测试全绿；状态机声明数与转换语义无变化。
- **AC-17（全局）**：执行并通过：① `git diff --check`；② `JSON.parse` 校验 `requirement-authoring.pipeline.json` 与 `feature-writeback.pipeline.json`；③ `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`；④ `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`；⑤ 仅按 §3.1 白名单执行六个禁止模式的 `rg`，零命中。不得以全仓替换历史内容来达成⑤。

## 6. 成功指标

- **路径确定性**：给定同一 Installation Workspace，无论从主 checkout、knowledge-base linked worktree或其子目录调用，Tools Root realpath 唯一且可解释。
- **配置一致性**：一次 crctl 调用中 state machine、Pipeline、gates、默认 rules 不再来自不同 tools checkout。
- **旁路清零**：active executable surfaces 中不存在 workspace/tools 或 package-root 隐式回退；空壳目录无法影响执行。
- **注册复用**：Registration 只调用一次现有 cr-init，受控 frontmatter 无模型补写步骤。
- **维护成本**：不增加第三方依赖、公共 Runner/resolver、installer 或跨平台 Adapter harness；修改集中在现有 loader、prompt、模板和测试入口。

## 7. 范围排除

- PRD/SDD/Plan/TASK/Review/Implement/Test/Merge/Writeback/Archive Runner。
- shared Runner library、typed outputs、`.crctl/runs`、完整 repo/worktree/base context 持久化。
- tools branch/SHA/version pin、compatibility matrix、control-plane SHA pin。
- Adapter 自动 installer、settings 无损合并器、路径 watcher/repairer。
- 从任意参与仓 worktree 自动反推 knowledge-base worktree。
- multica 生成器、跨工具测试与生产代码的本轮路径修复；本轮只登记 CUSTOM 延后项。
- 历史分析、审查报告、生成 HTML、OpenWiki、inactive/old 内容的批量路径替换。
- 新增 `--tools-root`、register-preflight、registration-check、stage-context、Registration Runner 或 cr-init wrapper。
- 修改 CR 状态机、gate、审批、CAS、账本或 worktree 业务语义。
- 为 tools 路径变更提供运行时兼容回退或迁移期双读。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初始草稿：承接 `tools流程步骤优化v2-前移优化项.md` 与 grill-with-docs 质询 17 项拍板；9 条 FR、7 条 NFR、17 条 AC |
| 2026-08-10 | v0.2.0 | Ray | 第 1 轮需求评审 BLOCK 回修：声明注册快照优先级与 tbd 口径；将 worktree-path/push-progress 纳入双 workspace 契约；固定 active surface 白名单与六个禁止模式；以四类 sentinel + 代码审查断言替换不可观察的配置来源/缓存验收 |
