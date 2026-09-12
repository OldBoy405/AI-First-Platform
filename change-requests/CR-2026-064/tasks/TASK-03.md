---
id: CR-2026-064-TASK-03
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "消费方与文档迁移：4 份 tools SKILL + README 原位改读 recovery、OpenWiki 生成页重生成、multica 交付 Agent 提示词"
slug: recovery-consumer-prompt-and-doc-migration
status: pending
estimate: 12h
depends-on: [CR-2026-064-TASK-01, CR-2026-064-TASK-02]
created: 2026-09-13T00:20:00+08:00
---

# CR-2026-064-TASK-03 —— 消费方提示词、文档迁移与 OpenWiki 生成闭环

覆盖 FR：**FR-7、FR-8、FR-16（采纳口径）、FR-10（文本面）**（SDD §3.5/§4.3/D-6/D-7/§8）；变更组 G3；主责仓：`tools` + `multica`。

## 1. 任务描述

**目标**：把全部活跃消费方（4 份 tools SKILL + multica 交付 Agent 提示词）与文档面（`README.md` 原位迁移 + `openwiki/operations/crctl-transactions.md` 由既有生成步骤重新生成）改为只消费结构化 `recovery`；在 `skills/shared/crctl/SKILL.md` 落地**唯一**的「`recovery` 消费合同」小节（固定 5 步判定 + 四类错误闭包），其余消费方只引用它、不复制第二套规则。

**背景**：本 CR 的消费者是提示词（Skill / Agent），不是本仓代码（SDD D-6）：没有任何代码路径执行 `recovery`。因此消费侧的保证只能落在提示词合同与文档单一事实源上——这也是 AC-05 / AC-11 的可达性依据；OpenWiki 页是生成物，必须由既有生成步骤产出，不得手工编辑（`tools/AGENTS.md`，D-7）。

**输入条件**：tools CR worktree（`requirement/CR-2026-064`）+ multica CR worktree（`requirement/CR-2026-064`）；CR-2026-064-TASK-01 与 CR-2026-064-TASK-02 已完成并登记（源码已迁移，OpenWiki 生成的权威输入就位）；`crctl workspace freshness CR-2026-064`（gate=implement-start）通过。

## 2. 涉及文件 / 模块

| 文件（仓库 / 相对 worktree 路径） | 改动性质 |
|---|---|
| tools `skills/shared/crctl/SKILL.md` | `merge` 行与 `archive` 行的恢复字段改名（`携 checkpoint recovery` / 固定返回字段列表）；**新增「`recovery` 消费合同」小节**（唯一事实源，内容见 §3 第 2 条） |
| tools `skills/cr/cr-archive/SKILL.md` | 步骤 2 说明、结果分类表 3 行、输出模板「恢复」行、错误处置表：改为「按 `recovery`（argv）重跑同一 `crctl archive`」；**唯一续跑入口**表述不变 |
| tools `skills/sync/push-progress/SKILL.md` | Step 2 错误分流行、错误处置表「其它事务错误」行：改为按 `recovery` 重跑同一命令 |
| tools `skills/writeback/merge-feature-branch/SKILL.md` | publication lag 行：改为「按 `error.recovery` 先 checkpoint 再重跑 merge」 |
| tools `README.md` | §7「中途失败」条原位改写：按输出的 `recovery`（结构化 argv）重跑同一命令；**不新增恢复合同章节、不新增第二套描述** |
| tools `openwiki/operations/crctl-transactions.md` | **生成物，不手工编辑**：按 D-7 用既有生成步骤（`openwiki code --update`，provider/model 配置与 `.github/workflows/openwiki-update.yml` 同源）从迁移后的权威源码重新生成并核对 |
| multica `cr-prompts-revised/delivery-agent.md` | 交付纪律段（`L27`）与失败汇报项（`L44`）改读结构化 `recovery`（owner 可复制版本；本 CR 不更新平台 DB） |

**不得触碰**：tools 侧 `skills/shared/crctl/scripts/**`（属 CR-2026-064-TASK-01/02/04）、`agents/*.md`、`ARCHITECTURE.md`、`.github/workflows/**`、`dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json`、`pipeline-templates/**`；multica 侧除 `cr-prompts-revised/delivery-agent.md` 外全部文件（含 `CUSTOM.md`，边界见 plan.md R-11）。

## 3. 实现要点

1. **消费方改法统一规则（SDD §4.3 修改规则）**：把「执行 `recoverCommand`」改为读取 `recovery.executable` / `recovery.args[]` / `recovery.cwd` / `recovery.requiresTTY` / `recovery.promptFor[]`；Agent / Skill **不自行转义或补写参数**；缺少必需字段时报告合同错误，**不猜测恢复命令**；不再出现任何形如「复制 `recoverCommand` 里的命令」的表述。
2. **`skills/shared/crctl/SKILL.md` 新增「`recovery` 消费合同」小节（SDD §3.5，逐字）**——固定顺序、首个不满足项即唯一结论：

| # | 检查 | 不满足时 |
|---|---|---|
| 1 | `executable` 存在、非空 string、满足 FR-3 安全约束（不含空格分隔参数与任何 shell 运算符） | 停止执行 + 报告合同错误 |
| 2 | `args` 是数组且每元素为 string | 同上 |
| 3 | `cwd` 若存在则为绝对路径 | 同上 |
| 4 | `requiresTTY=true` ⇒ 当前环境具备可信 TTY | 停止执行 + 报告所需人类动作（不得在非 TTY 环境执行） |
| 5 | `promptFor` 非空 ⇒ 存在允许的人类/调用方输入入口（取值后方可执行） | 停止执行 + 报告所需人类动作 |

   并把四类错误闭包合成一句：**停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作**；同时写明：不得自动回退旧字段（旧字段已删除、无 alias，结构上不可回退）、不得猜测恢复命令、不得降级为字符串执行、人类界面若需显示命令只能从 `recovery` 渲染且显示结果不得反向作为执行输入、消费方一律使用非 shell 的 argv 执行方式。
3. **`promptFor` 值名 → 目标 CLI 入口（SDD §3.4）**：`reason` → `review-loop reset --reason <text>`（可信 TTY 中由人重新输入，属 reset 恢复时 `requiresTTY=true`）；`plan` → `test --plan <temp-json>`；`CR-ID` → `gate` 错配场景的位置参数 `<cr_id>`。三者均写明「从 `args` 省略」与「忽略时撞目标 CLI 既有 `BAD_ARGS`（零写入，安全失败）」。
4. **OpenWiki 生成闭环（D-7 四步，缺一不可）**：
   ① 先确认权威源码已由 CR-2026-064-TASK-01/02 迁移（本 TASK 不改源码）；
   ② 在 tools CR worktree 内用与 `.github/workflows/openwiki-update.yml` **同一生成命令**（`openwiki code --update`，provider/model 配置同源）重新生成 `openwiki/**`；
   ③ 核对生成结果：两个退役字段名零命中（按 SDD §4.4 整树扫描面口径）、恢复合同描述为结构化 `recovery`（含 `executable` / `args` / `promptFor` 等字段名）、生成 diff 不覆盖页面之外的人工内容；
   ④ 生成结果随本 CR 分支一并提交，生成命令与核对结论进入 `test-report.md` 证据（本 TASK 只把命令与结论交给测试报告节点，不代写 `test-report.md`）。
   - 生成环境不可用（无 provider key / 无网络）时按**环境阻塞**上报（`ENVIRONMENT_MISMATCH`），**不得回退为手工编辑生成页**；生成器对 `AGENTS.md` / `CLAUDE.md` / workflow 的附带改动不属本 CR 交付物（`zero_diff` 优先，不纳入本 TASK 提交）。
5. **文本纪律**：改写只动字段名与消费方式，不重写段落结构、不新增章节（除 §3 第 2 条要求的新增小节）、不引入新的推进命令示例；`README.md` 与生成页各自**不**新增恢复合同的第二套描述。

## 4. 验收条件

1. **tools 提示词与文档零命中**：`plan.md §6.2 cmd-03`（整树 − 两项精确路径）在 surfaces 内**零命中** `recoverCommand` / `recover_command`，其中被覆盖的必含 `README.md`、`openwiki/operations/crctl-transactions.md`、`skills/shared/crctl/SKILL.md`、`skills/cr/cr-archive/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/writeback/merge-feature-branch/SKILL.md`。
2. **消费合同落地**：`skills/shared/crctl/SKILL.md` 含「`recovery` 消费合同」小节，且 5 步判定顺序与四类错误闭包文本可逐条核对（顺序、停止、报告、零副作用、不猜测、不回退旧字段六项均在文中）；其余 4 份消费方 SKILL 只引用该合同，不复制第二套判定表。
3. **文档单一事实源**：`plan.md §6.2 cmd-06` 通过——`README.md` 与 OpenWiki 页旧字段零命中，OpenWiki 页含 `recovery` / `executable` / `args` / `promptFor` 结构化字段名；`README.md` 未新增恢复合同章节。
4. **OpenWiki 生成闭环**：生成命令、生成前后 diff、生成结果核对结论三项证据齐备（记入 `test-report.md` 分析段）；生成 diff 不覆盖页面之外的人工内容；页面三处旧合同断言（frontmatter `invariants[1]`、正文「Durable Transaction Envelope → Recovery」条、「Change-Safety Guidance」第 3 条）归零。
5. **multica 提示词迁移**：`plan.md §6.2 cmd-04` 通过——`cr-prompts-revised/*.md` 旧字段零命中、`delivery-agent.md` 已改读结构化 `recovery`；`multica` 侧 diff 恰为 `cr-prompts-revised/delivery-agent.md` 一个文件（历史黄金数据未被改写）。
6. **范围**：`plan.md §6.2 cmd-05` 的 tools diff 白名单**通过**——本 TASK 的增量路径 ⊆ {4 份 SKILL + `README.md` + `openwiki/operations/crctl-transactions.md`}。

## 5. 完成标志

- 上述 §4 的 6 条全部实测通过，并留下可复核的命令与输出摘要（命令、cwd、exit、关键行）。
- **OpenWiki 生成命令与核对结论**已按 D-7 第 4 步记录（生成环境不可用时以 `ENVIRONMENT_MISMATCH` 上报并停止，不伪造生成结果、不手工编辑该页）。
- 本 TASK 产生的改动由本 TASK 自行提交（两个仓各自提交）：tools 侧 `[cr] CR-2026-064 TASK-03 recovery consumer prompts and docs`、multica 侧 `[cr] CR-2026-064 TASK-03 delivery-agent recovery contract`（受控 `crctl git` 形态，`[cr] ` 前缀）。
- `crctl task done CR-2026-064-TASK-03 --workspace <KB worktree>` 登记完成（纪律 #8）。
- **不**在本 TASK 内改写 `sdd.md` / `prd.md`；**不**改 `scripts/**` 与测试文件；**不**在交付结论中声称平台侧已生效（FR-16）。

## 6. 接口契约

**产出（供下游 TASK 与后续节点消费，逐字对齐 SDD）**

| 符号 / 文本面 | 精确形态（SDD 落点） |
|---|---|
| 「`recovery` 消费合同」小节 | `skills/shared/crctl/SKILL.md` 内的单一事实源小节：固定 5 步判定顺序（§3 第 2 条表）+ 四类错误统一闭包（停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作）+ 三条禁令（不回退旧字段、不猜测、不降级为字符串执行）（SDD §3.5 / D-6 / AC-11） |
| 消费方读取面 | 4 份 SKILL 与 `delivery-agent.md` 只读 `recovery.executable` / `recovery.args[]` / `recovery.cwd` / `recovery.requiresTTY` / `recovery.promptFor[]`（SDD §4.3 修改规则） |
| `promptFor` 映射 | `reason` → `review-loop reset --reason <text>`；`plan` → `test --plan <temp-json>`；`CR-ID` → `gate` 错配的位置参数（SDD §3.4） |
| OpenWiki 页 | 由 `openwiki code --update` 生成的 `openwiki/operations/crctl-transactions.md`：恢复合同描述为结构化 `recovery`，旧字段零命中（SDD §4.3 / D-7） |

**消费（上游产出与既有约束）**

- `recovery` 对象形状与 11 个站点的取值：由 CR-2026-064-TASK-01 / CR-2026-064-TASK-02 产出（本 TASK 只描述消费方式，不重定义形状）。
- `tools/AGENTS.md` 的 OpenWiki 段（不手工编辑生成页）与单一事实源表（三个 `_index.yml` 为 active 清单权威）：本 TASK 的实施约束依据。
- `.github/workflows/openwiki-update.yml` 的两步（`npm install --global openwiki@0.2.3 …` + `openwiki code --update --print`）与 `add-paths`：生成命令的同源依据。
