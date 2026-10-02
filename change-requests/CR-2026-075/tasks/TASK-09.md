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

收敛 multica 侧部署副本并完成合同对齐与生效版本台账（FR-15；SDD §4.8、SDD-CLOSE-10）。三件事：①四份部署副本短提示与 tools 侧一致（无逐命令 `--workspace <workspace>` 示例、显式 CR-ID 保留）；②`delegation-contract.md` 与维护副本的成功集合对齐平台现有枚举（补 `steered`），让 `delegation-contract.test.mjs` 转绿；③`CUSTOM.md` 按现有结构登记本轮 daemon 改动，并把生效版本比对结果写入 `test-evidence/` 台账（不一致的 in-scope 变更面标记 `pending-deploy`，不表述为已生效）。**平台侧写入不在本 TASK 内**（SDD §9 `scope_in` 未含平台侧写入与平台配置变更）。

## 涉及文件 / 模块

- `cr-prompts-revised/{requirement-writer,dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` — 短提示收敛与显式 CR-ID 保留。
- `cr-prompts-revised/bak/{cr-coordinator-agent,quality-reviewer-agent}.md` — 维护副本按合同全文同等修正（`bak/README.md` 的 `maintainedBak()` 口径）；`bak/` 中「排除」副本不动。
- `cr-prompts-revised/delegation-contract.md` — 成功集合 `status=queued|coalesced|deferred` 对齐为含 `steered` 的平台现状。
- `cr-prompts-revised/CHANGES.md` — 如需登记本次部署副本修订，按现有章节顺延（不新造结构）。
- `CUSTOM.md` — 按现有三表结构（《代码改动明细》按功能模块分组、行号 `#N` 只增不改 + 《模块索引》+ 《CR 索引》）登记 TASK-02 的 daemon 改动；文件头 `AIFIRST` 计数只升不降。
- `change-requests/CR-2026-075/test-evidence/`（KB 仓）— 生效版本台账与比对结果。

## 实现要点

- 部署副本收敛：四份 `cr-prompts-revised/*.md` 的受控 CR 后续节点不再含逐命令 `--workspace <workspace>` 示例（绑定环境可省），但保留 execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根。收敛口径与 TASK-08 的 tools 侧一致，不引入第二套写法。
- 合同对齐（R11，本轮只读实测基线 19 用例 / 18 pass / 1 fail）：`delegation-contract.md` 的成功集合补 `steered`，与平台 `server/internal/handler/admission.go` 的 `DispatchStatus` 现状（`blocked,coalesced,deferred,queued,steered`）一致；维护副本（`bak/cr-coordinator-agent.md`、`bak/quality-reviewer-agent.md`）内联正文同步修正。**只改文本声明**：不改 `admission.go`、不新增平台 status、不改合同判定语义之外的内容。
- `CUSTOM.md` 登记：TASK-02 的 daemon 改动（`pipeline_task.go`/`daemon.go` + 同包测试）按《台账行模板》逐列填写（位置 / 改动 / 原因追溯含 CR-2026-075 与 TASK / 日期 / 合并注意）；《模块索引》《CR 索引》与正文行号三者一致；文件头同步实测 `AIFIRST` 计数基线（只升不降）。
- 生效版本台账（SDD-CLOSE-10 最小证据）：①四份部署副本的 LF `sha256` 与仓库文件逐字节比对结果；②`multica skill list --output json` 输出的本 CR 涉及 imported Skills 取用路径列表（断言 `origin.repo=AI-First-tools`/`origin.ref=main`/`origin.path` 与声明一致）；③`multica agent list --output json` 的四份线上 Agent instructions 的 `sha256` 基线（只记录、不判定）。台账落 `test-evidence/`；FR-15 第③④步的平台侧部署动作未执行，未闭合差异一律标记 `pending-deploy` 并附目标指纹，**不得**表述为已生效。
- 环境边界：只做只读查询与文本修订；不启停服务、不写平台配置；不执行平台侧 imported Skills 同步或 Agent instructions 覆盖。

## 验收条件

1. 在 multica CR worktree 根执行证据命令 `cmd-09`（plan §6.2 原样：repo=multica、cwd=`.`、executable=`node`、args=`["--test","cr-prompts-revised/test/delegation-contract.test.mjs"]`、timeout=300）：转绿 19/19（本轮基线为 18 pass / 1 fail——失败项即成功集合缺 `steered`，见 R11）。真实运行范围 = 单文件（按 `admission.go` 枚举源与 `bak/README.md` 的维护集合解析）；观测面 = 合同正文与四份提示词/维护副本的逐字一致与枚举对齐，**不声称覆盖 CR Agent 全部行为**。
2. 在 multica CR worktree 根执行证据命令 `cmd-10`（plan §6.2 原样：repo=multica、cwd=`.`、executable=`node`、`-e` 内联只读脚本、timeout=300）：assert 全通过，即①四份部署副本存在、非空、短提示已收敛（无 `--workspace <workspace>` 示例）且未误删显式 CR-ID，并输出各副本 LF `sha256`；②14 个 imported Skill 的 `origin.repo`/`origin.ref`/`origin.path` 与声明一致；③四份线上 Agent instructions 的 `sha256` 台账输出成功。该命令只读，不写平台、不写仓库。
3. AC-B14 覆盖：仓库、维护部署副本、实际 imported Skills 与 Agent instructions 的生效版本比对结果全部落 `test-evidence/`；未执行平台侧部署的差异标记 `pending-deploy`；`cmd-09`+`cmd-10` 作为 AC-B14 的验收证据。
4. 文件集检查经受控入口（argv 固定），cwd = multica CR worktree 根；`<tools-worktree>` 取 Pipeline `resources[]` 中 repo=`tools` 的 `worktreePath` 原样值：

   `node <tools-worktree>/skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <multica-worktree> --workspace <multica-worktree>`

   断言输出仅含本 TASK 在 multica 侧声明的文件（四份部署副本、两份维护副本、`delegation-contract.md`、必要时 `CHANGES.md`、`CUSTOM.md`）。KB 侧 `test-evidence/` 台账文件在 KB worktree 的文件集检查中体现（`change-requests/CR-2026-075/test-evidence/`）。status 仅证明文件集。

## 完成标志

- `cmd-09` 19/19 绿、`cmd-10` 断言全通过；生效版本台账已落 `test-evidence/`，未闭合项标 `pending-deploy`。
- 部署副本收敛口径与 TASK-08 一致；显式 CR-ID 与保留项未误删。
- `CUSTOM.md` 三表一致（正文行 / 《模块索引》/ 《CR 索引》），原因追溯含 CR-2026-075 与 TASK，`AIFIRST` 计数只升不降。
- `admission.go` 零改动；不新增平台 status；不做平台侧写入（FR-15 第③④步不表述为已完成）。
- 产物已落盘并提交，commit 自含其文本修订；已收集的证据以只读复跑方式留档，未修改 KB 台账以外的受控账本。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- TASK-02 产出的 daemon 改动面（`resolveTaskWorkspaceBinding`/`parseExecutionContext`/`injectTaskCRWorkspaceEnv`/`configureTaskGitEnvironment`/`installCrctlLauncher`）：`CUSTOM.md` 登记的对象。
- TASK-08 产出的收敛口径（受控 CR 后续节点保留项集合）与业务 Agent 登记（`agent-skill-matrix.yml`/`agents/*.md`/`agents/_index.yml`）：部署副本收敛与台账引用同一份口径。
- `cr-prompts-revised/test/delegation-contract.test.mjs` 的 `maintainedBak()` 解析口径与 `bak/README.md` 的维护集合表：本 TASK 只改「维护」集合内的副本。
- `multica skill list --output json`、`multica agent list --output json`（平台只读查询通道）：台账的证据来源；只读、不写平台。

**产出**：

- 部署副本与维护副本的收敛文本：成功集合含 `steered`（`status=queued|coalesced|deferred|steered` 视为投递成功）；短提示无逐命令 `--workspace <workspace>` 示例；显式 CR-ID 保留。
- `CUSTOM.md` 台账行（编号顺延）与《模块索引》/《CR 索引》条目。
- 生效版本台账（`test-evidence/`）：四份部署副本 LF `sha256` + imported Skills 取用路径列表 + 四份线上 Agent instructions `sha256` 基线 + `pending-deploy` 标记清单。
- 下游引用：TASK-10 复跑 `cmd-09`/`cmd-10` 作为 FR-15 证据；test-report 的 FR-15/AC-B14 行引用同一份台账与 `pending-deploy` 口径，均不得表述为「已部署/已生效」。
