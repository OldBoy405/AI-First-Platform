---
id: CR-2026-075-TASK-09
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: 部署副本收敛、合同对齐与生效版本台账
slug: deployment-copies-contract-and-effective-version-ledger
status: pending
estimate: 4h
depends-on: [CR-2026-075-TASK-07, CR-2026-075-TASK-08]
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

收敛 multica 侧部署副本、完成合同对齐与生效版本核对（FR-15；SDD §4.8、SDD-CLOSE-10）。三件事：①四份部署副本短提示与 tools 侧一致（无逐命令 `--workspace <workspace>` 示例、显式 CR-ID 保留）；②`delegation-contract.md` 与维护副本的成功集合对齐平台现有枚举（补 `steered`），让 `delegation-contract.test.mjs` 转绿；③`CUSTOM.md` 按现有结构登记本轮 daemon 改动，并完成实际生效版本核对。**平台侧同步由有权限的人类 owner（Ray）执行，是本 TASK 验收的前置**：仓库侧收敛完成后，人类 owner 按本卡「同步清单」把仓库目标文本推送到平台，再由本 TASK 以只读的 `cmd-09`/`cmd-10` 断言线上内容与仓库目标逐字一致。agent 不写平台配置（SDD §9 `scope_in` 未含平台侧写入），也不把 `pending-deploy`、来源路径/ref 一致或「仓库已改」当作 AC-B14 通过；本 TASK 的验收不依赖 merge/writeback。

## 涉及文件 / 模块

- `cr-prompts-revised/{requirement-writer,dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` — 短提示收敛与显式 CR-ID 保留（同步清单中的四份 CR Agent 源文件）。
- `cr-prompts-revised/bak/{cr-coordinator-agent,quality-reviewer-agent}.md` — 维护副本按合同全文同等修正（`bak/README.md` 的 `maintainedBak()` 口径）；`bak/` 中「排除」副本不动。
- `cr-prompts-revised/delegation-contract.md` — 成功集合 `status=queued|coalesced|deferred` 对齐为含 `steered` 的平台现状。
- `cr-prompts-revised/CHANGES.md` — 如需登记本次部署副本修订，按现有章节顺延（不新造结构）。
- `CUSTOM.md` — 按现有三表结构（《代码改动明细》按功能模块分组、行号 `#N` 只增不改 + 《模块索引》+ 《CR 索引》）登记 TASK-02 的 daemon 改动；文件头 `AIFIRST` 计数只升不降。
- `change-requests/CR-2026-075/test-evidence/effective-version.md`（KB 仓）— 同步清单、人类 owner 的同步执行记录（执行人/时间/逐条目标 id 与 sha256）与 `cmd-09`/`cmd-10` 的实际生效版本比对结果。
- 只读消费的平台面（不属仓库文件）：`multica agent list`、`multica skill list`、`multica skill get <id> --with-content`。

## 实现要点

- 部署副本收敛：四份 `cr-prompts-revised/*.md` 的受控 CR 后续节点不再含逐命令 `--workspace <workspace>` 示例（绑定环境可省），但保留 execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根。收敛口径与 TASK-08 的 tools 侧一致，不引入第二套写法。
- 合同对齐（R11，本轮只读实测基线 19 用例 / 18 pass / 1 fail）：`delegation-contract.md` 的成功集合补 `steered`，与平台 `server/internal/handler/admission.go` 的 `DispatchStatus` 现状（`blocked,coalesced,deferred,queued,steered`）一致；维护副本（`bak/cr-coordinator-agent.md`、`bak/quality-reviewer-agent.md`）内联正文同步修正。**只改文本声明**：不改 `admission.go`、不新增平台 status、不改合同判定语义之外的内容。
- `CUSTOM.md` 登记：TASK-02 的 daemon 改动（`pipeline_task.go`/`daemon.go` + 同包测试）按《台账行模板》逐列填写（位置 / 改动 / 原因追溯含 CR-2026-075 与 TASK / 日期 / 合并注意）；《模块索引》《CR 索引》与正文行号三者一致；文件头同步实测 `AIFIRST` 计数基线（只升不降）。
- **同步清单与人类前置（FR-15 第③步）**：仓库侧收敛完成并提交后，本 TASK 输出可直接执行、逐条对照的同步清单（命令算法写在 `test-evidence/effective-version.md` 与本卡，不在别处另立第二套）：
  - 目标与源文件：四份 CR Agent（`multica agent list --output json` 取 id）← `cr-prompts-revised/<name>.md` 的 LF 正文；规划/竞品两个业务调用方 Agent（`product-planning-agent`、`competitive-analyst-agent`）← tools CR worktree `agents/<name>.md`（TASK-08 的登记文本）；本 CR 涉及 14 个 imported Skill（`multica skill list --output json` 取 id 与 `origin.path`）← tools CR worktree 下该 Skill 的**本 CR 改动文件**（SKILL.md 及其附带文件，如 `engineering-docs/scripts/**`、`crctl/scripts/**` 的改动面，逐条按各 TASK 文件集清单列出；`origin.path` 决定仓库根）。
  - 命令形态：Agent 用 `multica agent update <agent-id> --instructions <目标正文>`（单值字符串参数；人类 owner 按所用 shell 传入文件 LF 正文）；Skill 根正文用 `multica skill update <skill-id> --content-file <SKILL.md 路径>`，技能内其他文件用 `multica skill files upsert <skill-id> --path <技能内相对路径> --content-file <仓库文件>`。
  - 责任与边界：执行人 = 人类 owner（Ray，平台管理员，`cr.md owners.development`）；本 TASK 不代执行、不写平台配置、不伪造同步记录；清单中逐个目标附目标 sha256（由本 TASK 从源文件算出），供同步后核对。
- **生效版本比对（FR-15 第④步，只读）**：①`cmd-09` 读取四份 CR Agent 的线上 instructions，与 `cr-prompts-revised/*.md` 逐字比对（LF 规范化后全等，不一致即非零退出并打印两侧 sha256），同时校验 14 个 imported Skill 的取用路径台账；②`cmd-10` 以本 CR 各 TASK 声明的发布文件集为期望，先逐个断言该文件在线上存在，再与仓库目标逐字比对（LF 全等；缺文件/不一致即红），并核对规划/竞品两个业务调用方 Agent 的线上 instructions（同上判定口径），范围外既有线上漂移单列。③两条命令的原始输出与人类同步记录一起落 `test-evidence/effective-version.md`。
- 前置未完成或比对仍红时：本 TASK 不 done，按缺失环境前提报告所需人工动作（同步清单哪几条未执行/哪几条 sha256 仍不一致）；**不得**以 `pending-deploy`、来源路径/ref 一致或「仓库已改」充作 AC-B14 通过，也不得把该前置挂到 merge/writeback。
- 环境边界：只做只读查询与文本修订；不启停服务、不写平台配置、不代人类执行同步。

## 验收条件

1. 在 multica CR worktree 根执行证据命令 `cmd-08`（plan §6.2 原样：repo=multica、cwd=`.`、executable=`node`、args=`["--test","cr-prompts-revised/test/delegation-contract.test.mjs"]`、timeout=300）：转绿 19/19（本轮基线为 18 pass / 1 fail——失败项即成功集合缺 `steered`，见 R11）。真实运行范围 = 单文件（按 `admission.go` 枚举源与 `bak/README.md` 的维护集合解析）；观测面 = 合同正文与四份提示词/维护副本的逐字一致与枚举对齐，**不声称覆盖 CR Agent 全部行为**。
2. 在 multica CR worktree 根执行证据命令 `cmd-09`（plan §6.2 原样：repo=multica、cwd=`.`、executable=`node`、`-e` 内联只读脚本、timeout=300）：assert 全通过，即①四份部署副本存在、非空、短提示已收敛（无 `--workspace <workspace>` 示例）且未误删显式 CR-ID，并输出各副本 LF `sha256`；②14 个 imported Skill 的 `origin.repo`/`origin.ref`/`origin.path` 与声明一致；③四份 CR Agent 的**线上 instructions 与部署副本逐字一致（LF 规范化后全等）**。任一不一致即非零退出。该命令只读，不写平台、不写仓库。
3. 在 tools CR worktree 根执行证据命令 `cmd-10`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、`-e` 内联只读脚本、timeout=600）：assert 全通过，即①以**本 CR 各 TASK 声明的发布文件集为期望**（`EXPECT` 逐项 = 各 TASK「涉及文件 / 模块」清单中位于该 Skill 目录下的文件并集 ∪ 该 Skill 的 SKILL.md 根正文，共 30 项：crctl 12 项 = SKILL.md + `scripts/crctl.mjs` + `scripts/lib/durable-tx.mjs` + 新增 `scripts/lib/planning-entry.mjs`/`scripts/lib/competitive-report.mjs` + `scripts/test/{crctl,durable-tx,caller-contract}.test.mjs` + 新增 `scripts/test/{planning-entry,competitive-report}.test.mjs` + `scripts/test/gate-registry.json`（TASK-01/03/04/05/06/08 声明）与既有同套件入口 `scripts/test/pipeline-structure.test.mjs`（本 CR 未声明改动）；engineering-docs 6 项 = SKILL.md + `scripts/src/utils/slug.ts`/`generators/base.ts`/`validators/index-sync.ts` + **本 CR 声明改动的 `scripts/src/__tests__/generators.test.ts`/`scripts/src/__tests__/validators.test.ts`**（TASK-07）；其余 12 个 Skill 各 SKILL.md（`validate-doc` 由 TASK-06 声明、10 个由 TASK-08 声明、`planning-draft` 为本 CR 未声明改动的既有同面项）），**先断言每个期望文件在线上存在**（`content`/`files[]`），**再**逐文件与仓库目标 LF 全等比对，缺文件/不一致/仓库目标缺失一律非零退出；本 CR 声明改动但未纳入 `EXPECT` 的文件属期望集缺失（engineering-docs 的 `scripts/src/__tests__/generators.test.ts`/`validators.test.ts` 即本轮补入的这一类），必须补入而非归为范围外；②与仓库目标不一致且**本 CR 未声明改动**的线上文件单列为 `out-of-scope-drift`（R8 口径，单列不计入本 CR 通过判定，也不以现存线上子集声称 AC-B14 一致）；③规划/竞品两个业务调用方 Agent（`product-planning-agent`、`competitive-analyst-agent`）的线上 instructions 与 `agents/*.md` 逐字一致（LF 规范化后全等）。该命令只读，不写平台、不写仓库。
4. AC-B14 闭合：平台侧同步（本卡「同步清单」，人类 owner 前置）已执行并记录（执行人、时间、逐条目标 id 与同步后 sha256）到 `test-evidence/effective-version.md`；`cmd-08` + `cmd-09` + `cmd-10` 三条全绿。前置未完成时本 TASK 不 done，报告所需人工动作；不得以 `pending-deploy` 或路径/ref 一致充作通过，不得把 merge/writeback 设为该条验收的前置。
5. 文件集检查经受控入口（argv 固定），cwd = multica CR worktree 根；`<tools-worktree>` 取 Pipeline `resources[]` 中 repo=`tools` 的 `worktreePath` 原样值，`<multica-worktree>` 同理取 repo=`multica` 的 `worktreePath`，`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node <tools-worktree>/skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <multica-worktree> --workspace <operational-workspace>`

   `--cwd` 只决定 Git 子进程目录（multica），`--workspace` 必须是本节点传入的 KB operational workspace（multica worktree 不含 `change-requests/`，`detectWorkspace` 不向上探测；绑定生效后显式异根会先报 `WORKSPACE_CONTEXT_MISMATCH`）——不得另设回退，不得修改 `detectWorkspace`。

   断言输出仅含本 TASK 在 multica 侧声明的文件（四份部署副本、两份维护副本、`delegation-contract.md`、必要时 `CHANGES.md`、`CUSTOM.md`）。KB 侧 `test-evidence/` 台账文件在 KB worktree 的文件集检查中体现（`change-requests/CR-2026-075/test-evidence/`）。status 仅证明文件集。

## 完成标志

- `cmd-08` 19/19 绿、`cmd-09`/`cmd-10` assert 全通过（`cmd-10` 对本 CR 声明发布集（30 项）逐个断言线上存在 + LF 全等，含新增两个 `lib/`、新增两个 crctl 测试、engineering-docs 的两个 in-scope TS 测试与 `gate-registry.json`；仅本 CR 未声明改动的既有漂移按 R8 单列；规划/竞品 2 个业务调用方 Agent 与 `agents/*.md` 一致）；`test-evidence/effective-version.md` 含同步清单、人类执行记录与比对结果（含 sha256），未闭合项按缺失环境前提报告而非标 `pending-deploy` 充作通过。
- 部署副本收敛口径与 TASK-08 一致；显式 CR-ID 与保留项未误删。
- `CUSTOM.md` 三表一致（正文行 / 《模块索引》/ 《CR 索引》），原因追溯含 CR-2026-075 与 TASK，`AIFIRST` 计数只升不降。
- `admission.go` 零改动；不新增平台 status；agent 不做平台侧写入；本 TASK 验收不依赖 merge/writeback。
- 产物已落盘并提交，commit 自含其文本修订；已收集的证据以只读复跑方式留档，未修改 KB 台账以外的受控账本。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- TASK-02 产出的 daemon 改动面（`resolveTaskWorkspaceBinding`/`parseExecutionContext`/`injectTaskCRWorkspaceEnv`/`configureTaskGitEnvironment`/`installCrctlLauncher`）：`CUSTOM.md` 登记的对象。
- TASK-08 产出的收敛口径（受控 CR 后续节点保留项集合）与业务 Agent 登记（`agent-skill-matrix.yml`/`agents/*.md`/`agents/_index.yml`）：部署副本收敛与同步清单引用同一份口径；两个业务调用方 Agent 的同步源文件即 TASK-08 定稿的 `agents/{product-planning-agent,competitive-analyst-agent}.md`。
- `cr-prompts-revised/test/delegation-contract.test.mjs` 的 `maintainedBak()` 解析口径与 `bak/README.md` 的维护集合表：本 TASK 只改「维护」集合内的副本。
- `multica agent list --output json`、`multica skill list --output json`、`multica skill get <id> --with-content --output json`（平台只读查询通道）：同步清单的 id 解析与 `cmd-09`/`cmd-10` 的比对证据来源；只读、不写平台。

**产出**：

- 部署副本与维护副本的收敛文本：成功集合含 `steered`（`status=queued|coalesced|deferred|steered` 视为投递成功）；短提示无逐命令 `--workspace <workspace>` 示例；显式 CR-ID 保留。
- `CUSTOM.md` 台账行（编号顺延）与《模块索引》/《CR 索引》条目。
- 同步清单（四份 CR Agent + 两个业务调用方 Agent + 14 个 imported Skill：目标 id、**逐文件**源文件路径、目标 sha256、命令形态；Skill 侧必须按 `cmd-10` 的 `EXPECT` 逐项列出本 CR 声明发布的 30 个文件——crctl 12、engineering-docs 6、其余 12 个各 SKILL.md，不得只列 SKILL.md）与 `test-evidence/effective-version.md` 台账（人类执行记录 + `cmd-09`/`cmd-10` 比对结果）。
- 下游引用：TASK-10 复跑 `cmd-08`/`cmd-09`/`cmd-10` 作为 FR-15 证据；test-report 的 FR-15/AC-B14 行引用同一份台账，只有在三条命令转绿时才可表述为「实际生效版本一致」，否则报缺失前置。
