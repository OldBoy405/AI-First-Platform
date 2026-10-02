## AI First tools：新 KB 初始化与首次回写兼容方案

**实施口径**：单独一笔 tools CR，不并入 CR-2026-073；待 CR-2026-073 归档后注册，注册参数（title、registration key、三角色 owner、target-version、target-spec-id）由人在注册时提供。三个验收面：显式 KB 初始化（`crctl kb init`）、节点 2 缺 `specs/_index.yml` 时首写、节点 4 只解析 plan 的两张稳定表。[AIFI-38（已并入 AIFI-39）](mention://issue/01a0eb3b-a21b-70fd-bbec-8fee58b0a8d2) 由 CR-2026-073 独立承接，本文不替代它。不得在 AIFI-35 的已审批业务源或 KB 账本上绕过授权直接修补。

### 0. 现状核实（基准：tools `668a9f6`、KB `4a285472`）

**缺口**

- 新 KB 进不了 crctl：`crctl.mjs#main()` 分发前执行 `detectWorkspace`（要求 `change-requests/`）与 `loadGates`（要求 `dir-graph.yaml#workspace.tools_package_path`）。
- 节点 2：`writeback-prd-sdd.mjs#buildIndex()` 缺 `specs/_index.yml` 即 `STRUCTURE_MISMATCH`，是唯一"缺文件就失败"的首写者。
- 节点 4：`writeback-traceability.mjs#buildNewMilestone()` 全篇扫描 `| FR-` / `| cmd-` 行，会误收其他表（AIFI-35：§5 readiness 的四行三列 FR 表触发 `cells.length < 4` 失败）。同文件 `trunkOf` 逐行正则匹配 `- id:`，带引号的 id 或 id 非条目首键时取不到 trunk，回写末期报 `TRUNK_UNKNOWN`。
- `tools/docs/QODER-使用指南.md` 第 1–2 步的手工模板与 crctl 不兼容：`backlog: []`（无 `cr-backlog/v2`）、`change-requests: []` 与 `tasks: []`（追加条目后 YAML 损坏）、`specs: []`（无 `features:`）、dir-graph 示例缺 `tools_package_path` 与代码仓 `role: code`。照此建的 KB 必坏。
- `skills/shared/crctl/SKILL.md` 仍写"默认从 cwd 向上探测 `change-requests/_backlog.yml`"，CR-2026-072 起已不成立。

**已解决、直接复用（不改）**

- 缺文件 CAS：baseline 白名单（`writebackAllowlist`）已含 `specs/_index.yml`；缺文件 `beforeSha256=null`，`readPreparedCandidate` 做 before 校验，`applyWriteSet` 三分类（=after 跳过 / =before 重做 / 第三值 `TX_RECOVERY_CONFLICT`），并发新建不会被覆盖。
- 首写者自建先例：节点 3 `delivery/task/_index.yaml`（缺则以 `tasks:` 起头）、节点 5 `_history.yml`（缺则以 `history:` 起头）。
- register：空账本编号从 `001` 起；最小可注册 KB 即 `register-tx.test.mjs` 夹具形态（`dir-graph.yaml` + 两本账），不需要 `specs/_index.yml`；archive 显式接受空 backlog 的 null 根。
- crctl 按 `role` 识别 KB（恰 1 个 `role: knowledge-base`），worktree 桶按 role 派生；仓库 id 的取值无任何代码依赖。
- 现成函数：`resolveToolsRoot`（含四个身份标志）、`resolveRepositories`、`parseYaml`（writeback `lib.mjs` 已引入）、`createFileExclusive`、`auditLog`（首次写入即建立 `.crctl/.gitignore`）。
- `writing-back` / `archived` 门禁不引用 `specs/_index.yml`；writeback journal 在 generator 成功之后才创建，节点 4 生成失败不留事务快照。

**不改**：状态机、`gates.json`、Pipeline、Agent、`agent-skill-matrix.yml`、durable-tx、`writeback-apply`、register 核心逻辑、tools `dir-graph.yaml`（不新增必备文件合同，`required_roots` 保持说明性）。multica 仓零改动，无需登记其 CUSTOM.md。

### 1. 显式初始化：`crctl kb init --workspace <KB 主 checkout>`

**前提**：人先写 `dir-graph.yaml`——它是唯一业务输入，也是 repositories 的唯一事实源。最小必填：

```yaml
workspace:
  tools_package_path: "../tools"
repositories:
  - id: knowledge-base   # id 取值不限；crctl 按 role 识别 KB
    path: "."
    trunk: main
    role: knowledge-base
```

每个代码仓追加 `id / path / trunk / role: code`。命令不接受、也不推断 trunk、tools 路径、仓库等业务参数；不创建托管仓库、不配置远端凭据、不批准 CR、不推进状态机。

**入口**：`main()` 在 `requireExplicitWorkspace` 之后、`detectWorkspace` / `loadGates` 之前分发 `kb init`；其他命令的入口规则不变，仍失败关闭。实现为 `crctl.mjs#cmdKbInit`，复用上列函数；不新建模块、不新增导出、不用 journal / 锁 / 故障点。

**校验（全部先于任何写入，失败零写入）**

1. `resolveToolsRoot`、`resolveRepositories` 原样读盘校验。
2. KB 条目 rootPath、install root、`--workspace` 三者 realpath 相同（排除 linked worktree 与 path 非本 checkout）。
3. 每个 active 仓是 Git checkout 根且配置了 `origin`；代码仓 `git ls-remote --exit-code --heads origin <trunk>` 成功（只读）。这一条在首个 CR 前拦住半注册状态：否则 register 推送注册提交后才发现代码仓 trunk 错误，改 dir-graph 重跑又触发 `GRAPH_CHANGED_DURING_TRANSACTION`。
4. KB HEAD 在声明的 trunk 分支上（尚无提交的空仓同样适用）；`git status --porcelain -uall` 只允许出现 `dir-graph.yaml` 与两本账。
5. `fetch origin` 后：远端 trunk 不存在即空远端，允许；存在则必须是 HEAD 的祖先，否则失败，不 reset / rebase / 覆盖。
6. 两本账逐个判定：缺失 → 新建；LF 归一后等于模板 → 跳过；其他 → `KB_INIT_CONFLICT`（列出路径）。已在使用的 KB 重跑也落在此处，不做"已初始化"特判。

**写入与发布**

7. 新建用 `createFileExclusive`（`wx` 独占创建；检查后被并发创建 → `CAS_CONFLICT`）。
8. 只 `git add` `dir-graph.yaml` 与两本账；有暂存才 commit（消息 `kb init`，无 trailer）；HEAD 不在远端时才普通 `git push origin HEAD:refs/heads/<trunk>`，不 force、不 lease，非快进由 Git 原生拒绝。

**重入**：每次运行按 1–8 从现场重算：已写未提交则补提交，已提交未推送则补推送，全部完成为 noop。

**产出**

| 路径 | 内容 |
| --- | --- |
| `change-requests/_backlog.yml` | `schema: cr-backlog/v2` 加单独一行 `change-requests:` |
| `change-requests/_index.yml` | `change-requests:` |

两本账与人写的 `dir-graph.yaml` 同一提交发布。成功后写一行审计；输出 `{op: 'kb-init', changed, created, commit, pushed}`；无 outbox（尚无 CR）。不创建 `specs/_index.yml`（由节点 2 首写），不修改用户 `.gitignore`。

**错误码**：新增 `KB_INIT_CONFLICT`（已有文件内容与模板不同）与 `KB_INIT_PRECONDITION`（`reason`：dirty / trunk-mismatch / remote-diverged / repo-invalid）；其余复用现有码。

**`.rayai-worktrees/` 自忽略**：`ensureRepoWorkspace` 建目录时写 `.rayai-worktrees/.gitignore`（内容 `*`），与 `.crctl/.gitignore` 同一做法；根 `.gitignore` 漏配该规则的旧 KB 也随之覆盖。

**调用面**：人或受托 Agent 直接运行；无 TTY 限制（非审批、输入显式、遇异内容即拒）；不新增 Skill、Pipeline 节点、Agent 路由或矩阵条目。

**与注册的边界**：`registerCr` 不变，仍只读既有 `_backlog.yml` / `_index.yml`；`specs/_index.yml` 不是注册前置。

### 2. 节点 2：缺索引时首写

`writeback-prd-sdd.mjs#buildIndex()` 仅在文件**不存在**时以下列首部起头，复用现有"在 `features:` 行后插入条目"逻辑：

```yaml
schema: specs-index/v1

features:
```

不写顶层 `updated`（无代码读写它，本仓顶层值已长期陈旧）。已存在但缺 `features:`、条目缺 `cr-history` 等仍以 `STRUCTURE_MISMATCH` 失败，不重建整张索引、不删历史条目。生成器仍只输出 candidate；crctl 侧（白名单、`beforeSha256=null`、CAS）零改动。

### 3. 节点 4：只解析两张稳定表

`writeback-traceability.mjs#buildNewMilestone()`：

1. 表头单元格 trim 后逐字等于规范表头、且下一行是分隔行，才是目标表：交付覆盖表 `FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`，证据命令表 `证据ID | repo | cwd | executable | args | timeout`。每张恰好 1 次，缺失或重复 → `STRUCTURE_MISMATCH`。不依赖"§6"编号。
2. 数据行 = 分隔行之后连续的 `|` 行。
3. 交付覆盖表行：只剥外侧 `|`（不再 `filter(Boolean)`，它在空单元格时静默错列），必须恰 5 格且首格 `FR-\d+`，否则失败。
4. 证据命令表行：只校验首格 `^cmd-\d{2}$`，不校验列数（`args` 的 JSON 可合法含 `|`）。
5. 不新增重复 FR / cmd 等收紧项。
6. `trunkOf` 改为用 `parseYaml` 解析 dir-graph，按 id 从 `repositories` 取 trunk，替换逐行正则，与 `resolveRepositories` 同一解释。

其余 TASK、test-report、merge evidence 交叉核对不变；不改已签字 `plan.md` / `approval.yml`，不编辑 KB trunk。

**样本依据**：本仓 CR-2026-059～073 共 15 份含稳定表的 plan——两张规范表头各恰 1 次、无变体；覆盖表数据行全部 `FR-N` 开头、无重复；063～070 共 8 份另有以 `证据ID` 开头、行首为 `cmd-NN` 的"可达性/预算"表（真实诱饵）；059、061、063、072 共 4 份的命令表 `args` 含 `|`（严格列数会误判）。按上述规则回放 15 份，fr-chain 与 cmd-id 集合与旧解析器逐项一致。

### 4. 文档

- README：一行指向 `crctl kb init`。
- `tools/docs/QODER-使用指南.md`：删除 `_backlog.yml`、`change-requests/_index.yml`、`specs/_index.yml`、`delivery/task/_index.yaml` 四个手工模板，改为"写最小 dir-graph（仅必填字段）→ `crctl kb init`"；其他 docs 索引模板不动。
- `skills/requirement/requirement-register/SKILL.md` 失败表加一行：`WORKSPACE_NOT_FOUND` / `REPO_GRAPH_NOT_FOUND` / `TOOLS_PACKAGE_NOT_FOUND` → KB 未初始化，提示人先写 dir-graph 再运行 `crctl kb init`，Skill 不代跑。
- `skills/shared/crctl/SKILL.md`：子命令表加 `kb init`；"默认从 cwd 向上探测"一句改为"`--workspace` 必填；除 `kb init` 外还要求目录含 `change-requests/`"。
- HELP 与 caller-contract 命令表登记 `kb`；gate-registry 更新测试计数。

### 验收与回归

全自动，复用现有夹具；不做需要四次人工审批的真实端到端。

- **T1 kb init**（沿用 `register-tx` 建仓方式：三仓 + bare origin，KB 远端为空，只写 dir-graph）：首跑建两本账、一次提交并创建远端 trunk；再跑为 noop；"已写未提交""已提交未推送"两种中断现场重跑后补完；随后 `register` 分配 `CR-<YYYY>-001` 并为全部 active 仓建 worktree，KB 工作区干净；§1 校验 1–6 的各失败项逐一断言错误码，且文件、提交、远端均不变。
- **T2 节点 2**：writeback 夹具去掉 `specs/_index.yml`——baseline candidate 含该文件且 `beforeSha256=null`，apply 创建，重跑不重复添加 spec；已存在但畸形的索引原文不变；生成后、apply 前被并发创建 → before 校验拒绝，不覆盖。
- **T3 节点 4**：CR-2026-061（args 含 `|`）、CR-2026-066（诱饵表）的 plan 裁剪副本，结果与旧解析器一致；合成 AIFI-35 形态（§5 readiness 四行三列 FR 表 + 表外 `cmd-NN` 诱饵）只取两张稳定表；缺表、重复表、覆盖表 4 格或 6 格、命令表首格非 `cmd-NN` 分别失败；`trunkOf` 对带引号 id、非首键 id 取对 trunk。
- **T4 链路**：`makeCodeApprovedFixture` 增加无 `specs/_index.yml` 变体，merge → 回写三阶段 → archive 全通过；writing-back 态单独重跑 `writeback-apply --stage traceability`，baseline / tasks 事务与已签名源文件哈希不变，节点 2/3 不重做。

### 交付与 AIFI-35 恢复

CR-2026-073 归档后注册本 CR，其 worktree 直接基于含 073 的 trunk（无需 sync，无 release-drift）；073 的"普通 CR 按 FR/AC 定向证据验收"规则适用于本 CR 的 plan。任务顺序：节点 4 解析器与 `trunkOf` → 节点 2 首写 → `kb init` 与 `.rayai-worktrees/` 自忽略 → 文档；随 CR 合并发布 tools 包。

AIFI-35 恢复不属于本 CR 验收：待其 KB 的 `workspace.tools_package_path` 实际解析到已发布修复版，且确认无在途 traceability 事务（节点 4 生成失败不建 journal，预期为无），再按同一业务命令恢复节点 4→5；不凭"tools main 已合并"假定安装版本已更新。
