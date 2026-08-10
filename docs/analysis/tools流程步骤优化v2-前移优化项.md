# tools 流程步骤优化 v2：前移优化项

> 文档定位：从 `tools流程步骤优化v2.md` 的 Phase 2～7 候选路线中单独抽出的基础路径与入口契约优化。
>
> 当前状态：**已于 CR-2026-028 质询拍板**。本文件是该 CR 的需求来源；不追溯并入已归档的 CR-2026-027（Phase 0/1），不包含 Runner 或加载框架。

## 1. 前移原则

这些事项满足以下条件：

- 不需要 Pipeline Runner、Skill Runner、installer 或动态加载框架；
- 直接影响 CR、PRD、SDD、回写及 Adapter 找到并使用 tools 包；
- 优先复用现有 `dir-graph.yaml`、`crctl`、`cr-init`、Adapter 模板和 writeback 脚本；
- 不新增第二路径事实源、版本 pin、自动修复器或通用上下文对象；
- 只修改 active executable surfaces，不批量改写历史分析、生成 HTML、OpenWiki 或 inactive 内容。

## 2. 已拍板的路径领域模型

### 2.1 Tools Root

目标 workspace 使用的 tools 包根目录。唯一声明来源为 Installation Workspace 的：

```yaml
workspace:
  tools_package_path: "../tools"
```

规则：

1. 相对路径以 Installation Workspace 为基准；绝对路径直接使用；
2. 解析结果经 `realpath` 归一，消除 `..`、symlink、junction 与路径表示差异；
3. 配置缺失、类型错误、路径不存在或身份标志不完整，统一返回 `TOOLS_PACKAGE_NOT_FOUND`，错误详情列出原因；
4. 不回退到 workspace 内同名空壳 `tools/`、当前目录、调用方 package root 或正在执行的 crctl 所在包；
5. 不校验 tools Git branch、commit SHA 或版本兼容矩阵；
6. 同一 crctl 进程只解析一次，使用单值惰性缓存，不创建 execution context、Map、缓存文件或共享 resolver library。

Tools Root 固定验证以下四个身份标志：

```text
AGENTS.md
dir-graph.yaml
skills/_index.yml
skills/shared/crctl/scripts/crctl.mjs
```

其余资源由实际消费者按需校验，沿用现有 `PIPELINE_NOT_FOUND`、`GATES_NOT_FOUND` 等错误语义。

### 2.2 Operational Workspace 与 Installation Workspace

- **Operational Workspace**：当前实际读写 CR 阶段产物的 knowledge-base checkout，可为主 checkout 或 knowledge-base CR linked worktree。
- **Installation Workspace**：声明并锚定 Tools Root 的 knowledge-base 主 checkout。

普通 checkout 中两者相同。knowledge-base linked worktree 中：

1. CR 文件继续从 Operational Workspace 读写；
2. 通过 Git common-dir 关系找到 Installation Workspace；
3. `tools_package_path` 始终相对于 Installation Workspace 解析；
4. workspace-owned `.rayai-worktrees/` 同样以 Installation Workspace 为根；`crctl worktree-path` 从 knowledge-base linked worktree 调用时不得把 worktree 自身再次作为安装根；
5. `push-progress`、`pull-progress`、`resume-from-remote` 继续只消费 `worktree-path` 返回值，不自行拼路径；
6. 不改写 worktree 内 `dir-graph.yaml`，不创建 symlink/junction，不新增 `--tools-root`。

非 knowledge-base 的 tools/multica worktree 不自动猜对应 CR；调用方复用 `requirement-register.execution_context.knowledge_base_worktree`，显式传入 `--workspace <knowledge_base_worktree>`。

该决定见 `docs/adr/0003-worktree与tools安装基准分离.md`。

### 2.3 动态解析与静态物化

所有调用方共享同一契约，但不强制共享一套运行时代码：

- Agent、Skill、crctl 等动态调用方在执行流程时解析 Tools Root；
- IDE hooks、CI 等静态集成在安装时从同一配置物化 `{TOOLS_ROOT}`；
- tools 移动或配置变更后重新执行现有安装替换，不新增 installer、watcher、repairer 或启动 wrapper；
- 仓库只提交含 `{TOOLS_ROOT}` 的模板；含本机绝对路径的物化结果只进入 local settings，不提交到仓库；
- CI 由流水线维护者独立物化，不复用开发者本机配置。

## 3. 前移实施清单

### 3.1 crctl 的最小 Tools Root resolver

只在现有 `crctl.mjs` 内新增最小 resolver，并由现有 loader 复用；不拆出公共模块。Tools Root 默认统管全部 package-owned 运行配置：

```text
{toolsRoot}/dir-graph.yaml
{toolsRoot}/pipeline-templates/*.pipeline.json
{toolsRoot}/skills/shared/crctl/gates.json
{toolsRoot}/skills/shared/controlled-shell/rules.json
```

具体要求：

1. `loadStateMachine` 不再搜索 Operational Workspace 自身状态机、`<workspace>/tools/` 或 `PACKAGE_ROOT`；状态机来自 Tools Root 的 `dir-graph.yaml`；
2. `loadPipeline` 只从 Tools Root 加载；
3. `loadGates` 从 Tools Root 加载，避免与状态机/Pipeline 分裂到不同 tools checkout；
4. controlled-shell rules 默认从 Tools Root 加载；保留已有显式 `CRCTL_RULES_PATH` 作为部署/测试覆盖；
5. 不新增 gates/rules 的其他环境变量；
6. `help` 保持无需 workspace；其他实际 crctl 子命令沿用现有 eager gates 行为，要求有效 Tools Root，本 CR 不重构全部 command signature。

### 3.2 active Skill、Pipeline 与 Adapter 路径统一

修改范围采用以下确定白名单：

| 类别 | active surface |
|---|---|
| 核心实现与测试 | `dir-graph.yaml`、`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/test/crctl.test.mjs` |
| workspace 当前入口 | knowledge-base 根 `AGENTS.md`（与 tools 包内同名文件区分，属目标 workspace 入口文档） |
| crctl / Registration | `skills/shared/crctl/SKILL.md`、`skills/requirement/requirement-register/SKILL.md`、`pipeline-templates/requirement-authoring.pipeline.json` |
| 生命周期同步 | `skills/sync/push-progress/SKILL.md`、`pull-progress/SKILL.md`、`resume-from-remote/SKILL.md` |
| writeback | `skills/writeback/writeback-prd-sdd/SKILL.md`、`writeback-tasks/SKILL.md`、`writeback-traceability/SKILL.md`、`skills/writeback/scripts/test/writeback.test.mjs`、`pipeline-templates/feature-writeback.pipeline.json` |
| Adapter / CI | `skills/shared/crctl/adapters/**`（现有 Claude Code、Qoder、Cursor、Codex、CI 文件） |

统一规则：

- 不再假设目标 workspace 内存在 `tools/` 子目录；
- 逻辑示例与仓库模板统一使用字面占位符 `{TOOLS_ROOT}/skills/...`，不得保留 `{TOOLS}`、`{WORKSPACE}` 两套同义占位符；
- 静态模板安装时物化，不在运行时重复解析；CI 可把 checkout 目录赋给 `TOOLS_ROOT`，但命令不直接硬编码 `node tools/skills/...`；
- 白名单之外不批量替换。明确允许的非执行引用包括：`ARCHITECTURE.md` 的历史否决示例、`skills/reviewer-panel.yaml` 的包内自路径注释、`skills/shared/engineering-docs/SKILL.md` 的概念性路径、历史分析/审查/生成 HTML/OpenWiki/inactive/old 内容。

定向检索只在上述白名单执行，以下当前命令模式必须清零：

```text
node tools/skills/
node ../tools/skills/
$WORKSPACE/tools/
<workspace>/tools/
$CLAUDE_PROJECT_DIR/tools/
{TOOLS}/tools/
{WORKSPACE}/tools/
```

`node ../tools/skills/` 主要命中 knowledge-base 根 `AGENTS.md` 的 crctl 调用示例，应改为不绑定安装位置的表达。

包内源码用 `import.meta.url` 从自身定位兄弟文件不属于 workspace 安装位置猜测，允许保留。

### 3.3 Registration 直接复用现有 `crctl cr-init`

`crctl cr-init` 已支持：

```text
--title
--owner-requirement
--summary
--source
--target-version
```

本项不修改 cr-init 代码，只修正调用文档与 Pipeline 漂移：

1. `requirement-register` 一次传入全部已有注册参数；
2. 删除建档后由模型直接补写受控 frontmatter 的步骤；
3. 合并 `requirement-authoring.pipeline.json` 中重复的 cr-init 建档描述；
4. `cr.md`、`_backlog.yml`、`_index.yml` 的原子建档继续由 cr-init 负责；
5. worktree 创建继续复用 `worktree-path` 与 `dir-graph.yaml#repositories`；
6. 不新增 `register-preflight`、`registration-check`、`stage-context`、wrapper 或 Registration Runner。

### 3.4 删除第二安装位置声明

删除 tools 包自身 `dir-graph.yaml#workspace.target_install_path: "tools/"`，并修订同文件中“固定挂载到 tools/”的当前描述。目标 workspace 的 `workspace.tools_package_path` 是唯一安装位置事实源。

### 3.5 multica 边界

本 CR 不修改 multica 代码，只更新 `CUSTOM.md` 的“未做”台账。已核实现存跨仓消费点：

- `server/internal/governance/gen/generate-transitions.mjs`；
- `server/internal/governance/gen/generate-gate-nodes.mjs`；
- `server/internal/governance/approval_crosscheck_test.go`；
- `server/pkg/gitguard/gitguard_test.go`。

这些文件当前仍猜测 sibling tools 路径，后续首次修改对应文件时删除猜测：生成器要求显式 tools root，跨工具测试要求显式 `CRCTL_PATH` / rules path。生产环境已有 `MULTICA_CONTROLLED_SHELL_RULES=<绝对路径>` 属安装时物化，继续复用，不在 multica 新增 resolver。

## 4. 验收矩阵

### 4.1 workspace 与路径

| 调用位置 | workspace 确定方式 | 预期 |
|---|---|---|
| Installation Workspace 根目录 | cwd 向上探测 | 成功 |
| Installation Workspace 任意子目录 | cwd 向上探测 | 成功 |
| knowledge-base CR worktree 根目录 | cwd 向上探测 + Git common-dir | 成功 |
| knowledge-base CR worktree任意子目录 | 同上 | 成功 |
| tools CR worktree | 显式 `--workspace <knowledge_base_worktree>` | 成功 |
| multica CR worktree | 显式 `--workspace <knowledge_base_worktree>` | 成功 |
| 不属于 workspace 的目录 | 无显式参数 | `WORKSPACE_NOT_FOUND` |
| workspace 内有空壳 `tools/` | 不作为候选 | 使用声明的 Tools Root |
| 配置缺失、路径无效、标志不完整 | 无回退 | `TOOLS_PACKAGE_NOT_FOUND` |

不承诺从参与仓分支名、CR-ID 或 `.rayai-worktrees/` 扫描结果自动猜 knowledge-base worktree。

### 4.2 配置来源与注册

1. state machine、Pipeline、gates、默认 rules 均来自同一 Tools Root；
2. `CRCTL_RULES_PATH` 显式覆盖仍可用；
3. active Skill/Pipeline/Adapter 不再把 `<workspace>/tools/` 当固定事实；
4. `cr-init` 一次完成注册元数据建档，不产生第二次 frontmatter 旁路写入；
5. 现有状态机、gate、审批、CAS、账本与 worktree 语义不变。

### 4.3 最小验证

复用现有 `skills/shared/crctl/scripts/test/crctl.test.mjs` 黑盒套件：

- `makeWorkspace()` 默认显式绑定隔离的测试 tools fixture；fixture 为四标志与目标配置文件提供最小内容，不修改真实 tools checkout；
- 表驱动覆盖相对/绝对路径、空壳目录、缺配置、缺路径、四标志缺失；
- 增加一个 Git linked-worktree 黑盒场景，同时断言 Tools Root 与 `worktree-path` 都以 Installation Workspace 为根，返回的三仓 worktree 路径不含重复 `.rayai-worktrees/.../.rayai-worktrees`；
- 使用 sentinel fixture 分别改变状态机转换、Pipeline 节点、gate 必需文件与 controlled-shell rules，调用对应公开 CLI，以行为结果证明四类资源均来自声明的 Tools Root；`CRCTL_RULES_PATH` 另测显式覆盖；
- 单值惰性缓存不增加运行时 telemetry：代码评审断言所有四个 loader 只调用同一个 module-scope resolver，resolver 仅有一个成功值槽；黑盒只验证一次命令中需要多个 loader 的行为一致；
- 复用已有 cr-init metadata 测试；
- active 文档/模板按 §3.2 的精确白名单与七个禁止模式执行定向 `rg` 自检；
- 不新增 resolver 测试包、mock filesystem、IDE E2E 或跨平台 Adapter matrix。

## 5. 范围排除

以下内容继续保留在后续候选路线中：

- PRD `prepare/finalize` Runner；
- shared Runner library；
- Requirement Register Runner；
- repo/worktree/base context 的完整持久化输出；
- Authoring、Review、Implement、Test、Merge、Writeback、Archive Runner；
- Pipeline typed outputs；
- retry mode、control-plane SHA pin、scope-change ledger、task reconcile；
- tools 版本 manifest、branch/SHA pin 与兼容矩阵；
- 自动 Adapter installer、配置合并器、路径 watcher/repairer；
- multica 现存跨仓消费者的本轮代码修复；
- 从任意参与仓 worktree 自动反推 knowledge-base worktree。
