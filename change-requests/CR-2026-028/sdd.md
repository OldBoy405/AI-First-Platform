---
id: CR-2026-028-sdd
type: SDD
cr-ref: CR-2026-028
title: tools 流程步骤优化 v2 — 前移优化项独立 CR（tools-root 唯一解析 + Skill 路径统一 + crctl 配置加载修正 + cr-init 注册入口复用）技术设计
status: draft
created: "2026-08-10T17:42:38+08:00"
updated: "2026-08-10T17:42:38+08:00"
---

# SDD — tools 流程步骤优化 v2：前移优化项

## 1. 架构概览

### 1.1 模块边界

本 CR 的目标代码仓是 **tools 方法论包自身**（修改 `crctl.mjs`、Skill/Pipeline 提示词、Adapter 模板、`dir-graph.yaml`），另含 knowledge-base 根 `AGENTS.md` 一处入口文档修改。不引入新模块、新公共库、新子命令；全部改动落在既有单文件 `crctl.mjs` 与既有提示词/模板文件内。

| 层 | 改动 | 边界 |
|---|---|---|
| crctl 配置定位 | 新增 module-scope `resolveToolsRoot()` 单值惰性 resolver；四个 loader 改读 Tools Root | 不拆文件、不新增命令面 |
| crctl workspace 语义 | `detectWorkspace` 之上新增 Installation Workspace 派生；`cmdWorktreePath` 改以 Installation Workspace 为根 | 不新增 `--tools-root` |
| Skill/Pipeline/Adapter | 提示词与模板中的路径表达改为 `{TOOLS_ROOT}/...` | 只改 PRD §3.1 白名单 |
| Registration | `requirement-register` 一次传齐 cr-init 元数据；删二次补 frontmatter | 不改 cr-init 实现 |
| tools `dir-graph.yaml` | 删除 `workspace.target_install_path` | 目标 workspace `tools_package_path` 成为唯一声明 |
| multica | 仅 `CUSTOM.md` 台账（已随注册提交） | 代码零改动 |

### 1.2 双根概念落地

- **Operational Workspace**（OpWS）：`detectWorkspace()` 的返回值——CR 账本文件实际读写位置（主 checkout 或 knowledge-base CR worktree）。
- **Installation Workspace**（InstWS）：Tools Root 相对路径与 `.rayai-worktrees/` 的解析基准。普通 checkout 中 `InstWS = OpWS`；knowledge-base linked worktree 中由 `git rev-parse --git-common-dir` 派生（实测：worktree 内返回主 checkout 的 `.git`，其父目录即主 checkout 根）。

### 1.3 关键流程（改动后）

```text
crctl <cmd> [--workspace <op-ws>]
  → help 提前返回（不解析 workspace）
  → detectWorkspace()            # OpWS（cwd 向上或显式）
  → installRoot = deriveInstallRoot(OpWS)   # git common-dir → 主 checkout；非 git 回退 OpWS
  → resolveToolsRoot(installRoot)           # 读 dir-graph.yaml#workspace.tools_package_path
                                            # 相对 installRoot → realpath → 四标志验证
                                            # 单进程只解析一次（单值缓存）
  → loadStateMachine / loadPipeline / loadGates / loadShellRules 全部读 {toolsRoot}/...
  → 分发子命令（worktree-path 以 installRoot 拼接 .rayai-worktrees/...）
```

### 1.4 依赖方向

不改变 ARCHITECTURE §4 依赖方向：Pipeline → Skill → crctl 单向向下；crctl 仍是最底层执行器。新增的 `git rev-parse --git-common-dir` 只读调用沿用 `identity()` 已有的 `spawnSync('git', ...)` 先例，不引入新依赖。

## 2. 数据模型

### 2.1 新增/变更的配置契约

| 配置 | 位置 | 变更 |
|---|---|---|
| `workspace.tools_package_path` | 目标 workspace `dir-graph.yaml`（已存在，值 `../tools`） | 从“被 crctl 忽略”变为 Tools Root 唯一事实源；相对路径以 InstWS 为基准 |
| `workspace.target_install_path` | tools 包自身 `dir-graph.yaml` | **删除**（无人消费，FR-7）；同文件“固定挂载到 tools/”描述同步修订 |
| `{toolsRoot}/dir-graph.yaml` | tools 包 | 状态机唯一来源（原：OpWS → OpWS/tools → PACKAGE_ROOT 三候选） |
| `{toolsRoot}/pipeline-templates/*.pipeline.json` | tools 包 | Pipeline 唯一来源（原：OpWS/tools → PACKAGE_ROOT 两候选） |
| `{toolsRoot}/skills/shared/crctl/gates.json` | tools 包 | gates 唯一来源（原：执行脚本旁 `GATES_PATH`） |
| `{toolsRoot}/skills/shared/controlled-shell/rules.json` | tools 包 | 默认 controlled-shell rules（原：执行脚本旁）；`CRCTL_RULES_PATH` 显式覆盖保留 |

### 2.2 身份标志（不新增存储）

`resolveToolsRoot` 固定验证四个存在性标志，不校验内容、branch、SHA 或版本：

```text
{toolsRoot}/AGENTS.md
{toolsRoot}/dir-graph.yaml
{toolsRoot}/skills/_index.yml
{toolsRoot}/skills/shared/crctl/scripts/crctl.mjs
```

### 2.3 错误码与 detail 契约（新增）

| 错误码 | 触发 | detail 至少包含 |
|---|---|---|
| `TOOLS_PACKAGE_NOT_FOUND` | 字段缺失/非字符串/空值、解析路径不存在、realpath 失败、四标志任一缺失 | 配置字段名、原始值、解析后路径、缺失标志列表（或 `reason`） |

无新账本文件、无新持久化状态；进程内单值缓存不落盘。

## 3. 接口契约

### 3.1 crctl 内部函数签名（不导出为公共 API）

```ts
// module-scope，单值惰性缓存（先例：loadShellRules 的 _shellRules 三态）
let _toolsRoot: string | null | undefined; // undefined=未解析, null=解析失败, string=成功

function deriveInstallRoot(opWs: string): string
  // git rev-parse --git-common-dir（spawnSync，cwd=opWs）
  // 成功 → resolve(opWs, stdout 首行) 的 dirname 即主 checkout 根
  // 失败/非 git → 返回 opWs（普通 checkout 等价）

function resolveToolsRoot(opWs: string): string
  // 1) 缓存命中直接返回
  // 2) installRoot = deriveInstallRoot(opWs)
  // 3) 读 installRoot/dir-graph.yaml → workspace.tools_package_path
  //    缺失/非字符串/空 → fail('TOOLS_PACKAGE_NOT_FOUND', ...)
  // 4) 相对值 → path.resolve(installRoot, v)；绝对值直接用；fs.realpathSync 归一
  // 5) 四标志逐一存在性校验，任一缺失 → fail(..., {missing: [...]})
  // 6) 成功后写缓存返回
```

### 3.2 loader 契约变更

```ts
loadStateMachine(ws): { sm, source }        // source 恒为 {toolsRoot}/dir-graph.yaml
loadPipeline(ws, id): { doc, source }       // 恒为 {toolsRoot}/pipeline-templates/{id}.pipeline.json
loadGates(): gates                          // 恒为 {toolsRoot}/skills/shared/crctl/gates.json
loadShellRules(): rules                     // 默认 {toolsRoot}/skills/shared/controlled-shell/rules.json；
                                            // CRCTL_RULES_PATH 存在时优先（唯一覆盖入口）
```

`main()` 保持：`help` 在 workspace 解析前返回；其余命令先 `detectWorkspace` 再 eager `loadGates()`（行为不变，仅来源变化）。状态机/Pipeline 目标文件仍由消费者按需校验，沿用 `PIPELINE_NOT_FOUND`、`GATES_NOT_FOUND` 等既有错误码（FR-3 边界）。

### 3.3 worktree-path 契约

```ts
cmdWorktreePath(opWs, cr, repo):
  bucket = repo.role === 'knowledge-base' ? 'knowledge-base' : repo.id   // 不变
  path = join(installRoot, '.rayai-worktrees', bucket, 'requirement', cr) // 根改为 InstWS
```

从 knowledge-base linked worktree 调用不再产生 `<worktree>/.rayai-worktrees/...` 嵌套路径。`push-progress`/`pull-progress`/`resume-from-remote` 继续只消费该命令输出，不自行拼接（FR-2）。

### 3.4 Registration 调用契约

`requirement-register` 的 cr-init 调用改为一次传齐：

```text
crctl cr-init --title "{title}" --owner-requirement {owner}
  [--year Y] --summary "{summary}" --source {source} --target-version {v} --workspace <ws>
```

删除 Skill Step 2 中“建档后直接补全 cr.md frontmatter”的指令；`cr-init` 本身零改动（已支持全部旗标，B-6 核实）。

## 4. 关键算法与流程

### 4.1 Installation Workspace 派生（伪代码）

```text
function deriveInstallRoot(opWs):
  r = spawnSync('git', ['rev-parse', '--git-common-dir'], {cwd: opWs})
  if r.status == 0 and r.stdout 非空:
    commonDir = path.resolve(opWs, r.stdout.trim())   # worktree 场景 = 主 checkout/.git
    return path.dirname(commonDir)                    # = 主 checkout 根
  return opWs                                          # 非 git 目录（测试/独立检出）
```

实测证据：knowledge-base worktree 内 `git rev-parse --git-common-dir` → `<主checkout>/.git`，`dirname` 即主 checkout。multica worktree 的 common-dir 指向 multica 自身 `.git`——因此 tools/multica worktree 必须以 `--workspace <knowledge_base_worktree>` 显式传入，由该路径派生 InstWS，绝不使用 cwd 的 common-dir（FR-2）。

### 4.2 Tools Root 解析（伪代码）

```text
function resolveToolsRoot(opWs):
  if cache 命中: return cache
  inst = deriveInstallRoot(opWs)
  doc = parseYaml(read(inst/dir-graph.yaml))            # CRLF→LF 归一（纪律 #1）
  v = getPath(doc, 'workspace.tools_package_path')
  if typeof v != 'string' || v.trim() == '':
    fail('TOOLS_PACKAGE_NOT_FOUND', {field, reason: 'missing-or-invalid'})
  raw = path.isAbsolute(v) ? v : path.resolve(inst, v)
  real = try realpath(raw) else fail(..., {reason: 'path-not-exists', resolved: raw})
  missing = 四标志中不存在的列表
  if missing.length > 0: fail(..., {reason: 'identity-marker-missing', missing})
  cache = real; return real
```

失败路径绝不回退：不尝试 `opWs/tools`、cwd、`PACKAGE_ROOT`（D-3）。

### 4.3 单值惰性缓存

沿用 `loadShellRules` 既有三态模式（`undefined=未解析 / null=失败 / object=成功`）；`resolveToolsRoot` 同构：`undefined / null / string`。无 Map、无文件缓存、无 telemetry。失败同样缓存（进程内不重复解析），与 `_shellRules` 语义一致。

### 4.4 测试设计（FR-9）

1. **fixture tools 包**：`makeToolsFixture()` 生成最小四标志 + `dir-graph.yaml`（含可辨识 sentinel 转换）、`pipeline-templates/sentinel.pipeline.json`、`gates.json`（sentinel evidence 路径）、`controlled-shell/rules.json`（sentinel git shape）；不修改真实 tools checkout。
2. **makeWorkspace 扩展**：默认写入 `dir-graph.yaml` 并声明 `tools_package_path`（相对值指向 fixture）。
3. **表驱动**：相对/绝对路径、空壳 `tools/`、缺配置、非字符串、路径不存在、四标志逐一缺失。
4. **linked-worktree 黑盒**：临时 git 仓建 worktree，断言 `worktree-path` 与 Tools Root 均以 InstWS 为根、无嵌套 `.rayai-worktrees`。
5. **四类 sentinel 行为断言**（AC-6）：状态机用仅 fixture 存在的合法转换（advance 成功）、Pipeline 用仅 fixture 存在的 nodeRef、gates 用仅 fixture 要求的 evidence、rules 用仅 fixture 允许的 git shape；执行脚本换 checkout 结果不变。
6. **CRCTL_RULES_PATH** 覆盖断言（AC-7）。
7. **cr-init metadata**：复用现有用例，断言 summary/source/target-version 一次写齐（AC-11/AC-12）。
8. **代码审查断言**（AC-8）：四个 loader 调用同一 `resolveToolsRoot`，单值槽无 Map/文件/telemetry。

## 5. 技术选型与替代方案

| 决策点 | 选择 | 替代方案 | 理由 |
|---|---|---|---|
| resolver 归属 | 留在 `crctl.mjs` 单文件内（D-1） | 公共 `scripts/lib/tools-root.mjs` 共享库 | ARCHITECTURE §5 不变量 1/2/3：单文件强内聚写入路径、零依赖；当前只有一个消费者 |
| 配置基准 | Installation Workspace + git common-dir（D-9） | worktree 内复制/改写 dir-graph、创建 symlink/junction、新增 `--tools-root` | 前两者制造 checkout 特例，后者形成第二路径事实源（ADR-0003） |
| 失败行为 | 硬失败 `TOOLS_PACKAGE_NOT_FOUND`（D-3） | 保留 PACKAGE_ROOT 兼容回退 | 回退掩盖配置错误、使实际 tools 取决于启动入口；违反 NFR-2 |
| 版本绑定 | 只验证四标志身份（D-12） | branch/SHA/version pin | 本 CR 目标是路径确定性，不引入兼容矩阵维护面 |
| 配置修复 | 无自动修复（D-11） | installer/watcher/repairer | tools 移动属低频运维事件，重跑安装步骤即可（YAGNI） |
| 测试框架 | 扩展既有 `crctl.test.mjs` 黑盒套件（D-17） | 独立 resolver/Adapter 跨平台矩阵 | 核心风险在路径与 worktree 边界，黑盒 + sentinel 可覆盖；Adapter 无运行时消费者 |
| 静态物化 | Adapter 模板 `{TOOLS_ROOT}`（D-2/D-16） | 运行时解析 / 提交本机绝对路径 | hooks 启动即需路径，安装时物化一次；仓库不提交机器路径 |

## 6. FR 到技术实现映射

| FR | 实现位置 | 关键点 |
|---|---|---|
| FR-1 Tools Root 唯一契约 | `crctl.mjs` 新增 `resolveToolsRoot` + `deriveInstallRoot`；重构 `loadStateMachine`/`loadPipeline`/`loadGates` | 无隐式回退；detail 区分字段缺失/路径不存在/标志缺失 |
| FR-2 双根语义与 worktree 定位 | `deriveInstallRoot` + `cmdWorktreePath` 改根 | git common-dir 派生 InstWS；worktree-path 以 InstWS 拼接；push/pull/resume 消费不变 |
| FR-3 四标志身份验证 | `resolveToolsRoot` 校验段 | 只证明包身份；目标文件继续按需校验（既有错误码） |
| FR-4 crctl 配置来源收敛 | 四个 loader 改读 `{toolsRoot}/...` | `CRCTL_RULES_PATH` 唯一覆盖；help 不解析 workspace；eager gates 不变 |
| FR-5 active 执行入口统一 | PRD §3.1 白名单文件：`crctl/SKILL.md`、3 个 writeback Skill、feature-writeback pipeline、3 个 sync Skill、requirement-register、requirement-authoring pipeline、Adapter 模板、knowledge-base 根 `AGENTS.md` | `{TOOLS_ROOT}` 占位符；七个禁止模式零命中；CI 可设 TOOLS_ROOT 但命令不硬编码 |
| FR-6 Registration 复用 cr-init | `requirement-register/SKILL.md` Step 2 + `requirement-authoring.pipeline.json` node-1 prompt | 一次传齐元数据；删二次补 frontmatter；合并重复建档描述；cr-init 零改动 |
| FR-7 删除第二安装位置声明 | tools `dir-graph.yaml` | 删 `target_install_path`；修订“固定挂载到 tools/”描述 |
| FR-8 multica 延后项登记 | `CUSTOM.md`（已随注册提交 `cb957b73`） | 本 CR 代码零改动 |
| FR-9 最小回归验证 | `crctl.test.mjs` 扩展 | fixture + 表驱动 + linked worktree + 四 sentinel + CRCTL_RULES_PATH + cr-init metadata 复用 |

## 7. 安全与性能考量

### 7.1 安全

- **失败即拒绝**：配置缺失/无效时硬失败，杜绝“空壳 `tools/` 被误读”与静默回退引入的配置漂移（NFR-2/NFR-6）。
- **错误详情不泄露敏感路径**：`TOOLS_PACKAGE_NOT_FOUND` detail 只含配置值与解析路径（运行时输出），仓库内不提交本机绝对路径（NFR-3）。
- **无新命令面**：不新增 crctl 子命令、环境变量（除既有 `CRCTL_RULES_PATH`），guard deny 面不变——不需要更新 `lint-prompts` 判据。
- **受控 shell 语义不变**：rules.json 内容不修改，仅默认来源变为 Tools Root；`SHELL_UNAVAILABLE` 拒绝语义保持。

### 7.2 性能

- 每个 crctl 进程至多一次 `git rev-parse`（common-dir）与一次 realpath + 四标志 stat；单值缓存使同一命令内多 loader 零重复解析。
- 无新增 I/O、无后台任务、无 watcher；`help` 路径保持零 workspace 开销。
- 测试套件新增用例全部走临时目录 fixture，不影响真实仓库。

### 7.3 兼容性

- 现有状态机转换、gate/passCondition、审批、CAS、账本、worktree bucket 语义不变（NFR-4，AC-16）。
- 历史 CR 与既有 worktree 布局（`.rayai-worktrees/{bucket}/requirement/{cr}`）不迁移；`worktree-path` 输出与既有路径一致（主 checkout 视角下不变）。
- `cr-init` 已支持旗标，向后兼容（不传时缺省语义不变）。

## 8. Prompt 采纳影响

本 CR 不新增/扩展 crctl 子命令面（dispatch 分支无新增 case），不修改 `rules.json#protectedPaths.deny`；但 FR-5 会批量变更 Skill/Pipeline/Adapter 提示词中的**路径表达**（`tools/skills/...` → `{TOOLS_ROOT}/skills/...`），`lint-prompts` 只能机械抓“crctl 已接管却仍在 prompt 里手工做”类问题，抓不到“路径表达仍假设 workspace 内安装”。以下为需按 FR-5 更新的采纳清单（= PRD §3.1 白名单，逐项含现状 → 应改为）：

| 文件 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md` | `node tools/skills/...` 示例 | `{TOOLS_ROOT}/skills/...`（动态调用方运行时解析） |
| `skills/writeback/writeback-prd-sdd/SKILL.md` | `node tools/skills/...` | 同上 |
| `skills/writeback/writeback-tasks/SKILL.md` | 同上 | 同上 |
| `skills/writeback/writeback-traceability/SKILL.md` | 同上 | 同上 |
| `skills/writeback/scripts/test/writeback.test.mjs` | 注释中运行命令 | 同步为 `{TOOLS_ROOT}/...` 表达 |
| `pipeline-templates/feature-writeback.pipeline.json` | prompt 内 `tools/skills/writeback/scripts/*.mjs` | 改为 `{TOOLS_ROOT}/skills/writeback/scripts/*.mjs` |
| `skills/sync/push-progress/SKILL.md` 等 3 个 | `crctl worktree-path` 消费（不改） | worktree-path 根基准修正后行为自动一致 |
| `skills/requirement/requirement-register/SKILL.md` | Step 2 建档后补 frontmatter | 一次传齐 cr-init 旗标；删二次补写 |
| `pipeline-templates/requirement-authoring.pipeline.json` | node-1 两段重复 cr-init 描述 | 合并为一段、传齐元数据 |
| `skills/shared/crctl/adapters/**`（claude-code/qoder/cursor/codex/ci） | `$CLAUDE_PROJECT_DIR/tools/`、`{TOOLS}/tools/`、`{WORKSPACE}/tools/`、`node tools/skills/` | 统一字面 `{TOOLS_ROOT}/skills/...`，安装说明注明来源 `workspace.tools_package_path` |
| knowledge-base 根 `AGENTS.md` | `node ../tools/skills/shared/crctl/scripts/crctl.mjs` | 不绑定安装位置的口径表达（如“经 Tools Root 解析的 crctl”） |

`ARCHITECTURE.md` 不进白名单：本 CR 无架构级变更（不新增写入子命令、不改状态机口径、不否决方案），按 §8 维护规则无需修订；其历史否决示例中的 `tools/skills/...` 属允许例外。
