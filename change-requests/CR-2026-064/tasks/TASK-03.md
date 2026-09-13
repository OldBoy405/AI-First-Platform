---
id: CR-2026-064-TASK-03
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "消费方与文档迁移：4 份 tools SKILL + README 原位改读 recovery、OpenWiki 生成页重生成、multica 交付 Agent 提示词"
slug: consumer-prompt-doc-migration-openwiki
status: pending
estimate: 12h
depends-on: [CR-2026-064-TASK-01, CR-2026-064-TASK-02]
created: 2026-09-13T22:15:00+08:00
---

# CR-2026-064-TASK-03 —— 提示词 / 文档消费者迁移与 OpenWiki 生成闭环

覆盖 FR：**FR-7、FR-8、FR-10（提示词与文档侧）、FR-16（owner 可复制版与部署边界表述）、FR-17（消费合同的文本落点）**（SDD §4.3、§8、D-6、D-7）；变更组 **G3**；主责仓：`tools`（4 SKILL + README + 生成页）+ `multica`（1 个 prompt 文件）。

## 1. 任务描述

**目标**：把全部活跃提示词/文档消费者从「执行 `recoverCommand` 字符串」改为「按结构化 `recovery` 的 argv 边界执行」，并在 `skills/shared/crctl/SKILL.md` 内新增**单一事实源**的「`recovery` 消费合同」小节（固定 5 步判定顺序 + 四类错误闭包）；`openwiki/operations/crctl-transactions.md` 是**生成物**，必须由既有生成步骤从迁移后的权威源码重新生成并核对，**不手工编辑**（D-7）。

**背景**：本 CR 没有执行 `recovery` 的代码消费者——消费者是 Skill / Agent 提示词（PRD §1.1、US-1）。因此四类缺失检查落在提示词合同（D-6），而文档面必须保持「单一事实源」：README 原位迁移，OpenWiki 页由生成器产出，**不得出现第二套合同描述**（FR-8）。

**输入条件**：`tools` CR worktree（HEAD `81d31b8…`）；**CR-2026-064-TASK-01 / CR-2026-064-TASK-02 已完成**（字段名与形状已冻结）；`multica` CR worktree（HEAD `dead9fe0…`）；SDD `6c5c9a11`（sha256 `d9f727b6…`）只读。

## 2. 涉及文件 / 模块

| 文件 | 仓 / 路径（相对 worktree） | 改动性质 |
|---|---|---|
| crctl 命令面 Skill | `tools/skills/shared/crctl/SKILL.md` | `merge`/`archive` 行改「携 `recovery`（指向 checkpoint）」+ 固定返回字段列表改名 + **新增「`recovery` 消费合同」小节**（单一事实源） |
| archive Skill | `tools/skills/cr/cr-archive/SKILL.md` | 步骤 2 说明、结果分类表 3 行、输出模板「恢复」行、错误处置表 → 「按 `recovery`（argv）续跑」；唯一续跑入口表述不变 |
| push Skill | `tools/skills/sync/push-progress/SKILL.md` | Step 2 错误分流行、错误表「其它事务错误」行 → 按 `recovery` 重跑同一命令 |
| merge Skill | `tools/skills/writeback/merge-feature-branch/SKILL.md` | publication lag 行 → 「按 `error.recovery` 先 checkpoint 再重跑 merge」 |
| README | `tools/README.md` | §7「中途失败」条 → 按输出的 `recovery`（结构化 argv）重跑同一命令（**原位改写既有条目，不新增章节**） |
| OpenWiki 页（**生成物**） | `tools/openwiki/operations/crctl-transactions.md` | **不手工编辑**：源码迁移完成后由既有生成步骤重新生成并核对；三处旧合同断言（frontmatter `invariants[1]`、正文「Durable Transaction Envelope → Recovery」条、「Change-Safety Guidance」第 3 条）须归零 |
| 交付 Agent 提示词 | `multica/cr-prompts-revised/delivery-agent.md` | `L27`「明确 `recoverCommand`」→「明确的结构化 `recovery`（argv）」；`L44` 失败汇报项改名（owner 可复制版；**本 CR 不更新平台 DB**） |

**不得触碰**（SDD §9 `zero_diff`）：`tools/ARCHITECTURE.md`、`dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json`、`pipeline-templates/**`、`.github/workflows/**`、`tools/agents/*.md`（含 `agents/delivery-agent.md`——无旧字段引用）、`multica/CUSTOM.md`、`multica/server/**`（含历史黄金数据）。

## 3. 实现要点

1. **消费合同小节（单一事实源，SDD §3.5）**：新增内容必须逐条写明固定 5 步判定顺序（1 `executable` 存在且非空 string 且满足 FR-3 安全约束 → 2 `args` 为数组且每元素 string → 3 `cwd` 若存在则为绝对路径 → 4 `requiresTTY=true` ⇒ 当前环境具备可信 TTY → 5 `promptFor` 非空 ⇒ 存在允许的人类/调用方输入入口），**首个**不满足项即唯一结论（禁止「A 或 B」式并列）；四类错误统一闭合为「停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作」；不得自动回退旧字段（结构上已删除）、不得猜测恢复命令、不得降级为字符串执行；人类界面只能从 `recovery` 渲染，且显示结果不得反向作为执行输入。
2. **四个消费 Skill 只引用、不复制**：`cr-archive` / `push-progress` / `merge-feature-branch` 及 crctl SKILL 自身的命令行只写「按 `recovery` 执行本节点动作」，判定细节引用第 1 条的合同小节，避免同一规则出现两处措辞（D-6）。
3. **`promptFor` 取值口径写进提示词**（SDD §3.4）：`reason` → 可信 TTY 中由人重新输入 `--reason <text>`；`plan` → `--plan <temp-json>`；`CR-ID` → 位置参数。明确「不得从旧错误消息、评论或日志中复用旧值」。
4. **README 原位迁移**：只改既有「中途失败」条的措辞，不新增恢复合同章节、不引入第二套字段说明。
5. **OpenWiki 生成闭环（D-7 四步）**：
   1. 先完成权威源码迁移（CR-2026-064-TASK-01 / CR-2026-064-TASK-02 + 本 TASK 的提示词面）；
   2. 在 `tools` 工作树内用与 `.github/workflows/openwiki-update.yml` 同源的既有命令重新生成（`openwiki` + `openwiki code --update`，provider/model 配置同该 workflow）；
   3. 核对三条：两个退役字段名在该页零命中（按 SDD §4.4 整树扫描面口径）、恢复合同描述为结构化 `recovery`、生成 diff 不覆盖页面之外的人工内容；
   4. 生成结果随本 CR 分支一并提交；生成命令与核对结论写入 `test-report.md` 证据。
   **生成环境不可用（无 provider key / 无网络）时以环境阻塞上报（`ENVIRONMENT_MISMATCH`），不得回退为手工编辑生成页。** 生成器对 `AGENTS.md` / `CLAUDE.md` / `.github/workflows/**` 的附带改动**不属本 CR 交付物**，不得纳入本次提交（§9 `zero_diff` 优先）。
6. **multica 侧最小改动**：只改 `cr-prompts-revised/delivery-agent.md` 的两处，不改 `CUSTOM.md`（R-11）、不改 `server/**`；该文件是 owner 可复制版本，提示词内不得出现「平台 DB 已部署」类声称（FR-16）。

## 4. 验收条件

1. 五处提示词 + README + 生成页旧名零命中：
   ```bash
   rg -n "recoverCommand|recover_command" skills/shared/crctl/SKILL.md skills/cr/cr-archive/SKILL.md skills/sync/push-progress/SKILL.md skills/writeback/merge-feature-branch/SKILL.md README.md openwiki/operations/crctl-transactions.md   # 期望：零命中
   rg -n "recoverCommand|recover_command" cr-prompts-revised/delivery-agent.md   # multica worktree；期望：零命中
   ```
2. 消费合同小节存在且逐条可核（5 步顺序 + 四类闭包 + 不回退/不猜测/不降级/显示与执行分离）。
3. OpenWiki 页含结构化合同字段名（`recovery` / `executable` / `args` / `promptFor`），且三处旧合同断言归零；生成命令与生成前后 diff 已记录（`cmd-06` 提供页面事实面）。
4. README 未新增「恢复合同」章节：`git diff` 中 README 的改动行数有限且全部落在既有「中途失败」条内。
5. `multica` 侧 diff 只含 `cr-prompts-revised/delivery-agent.md`（由 `cmd-04` 断言，基线 `dead9fe0`）。

## 5. 完成标志

- 上列五条验收条件全部通过；本 TASK 触达的 6 个文件（4 SKILL + README + 生成页）与 `multica` 的 1 个 prompt 文件旧名零命中。
- 消费合同小节为**单一事实源**：其余消费 Skill 只引用、不复制判定规则（同一规则不出现第二处措辞）。
- OpenWiki 生成三证据齐备（生成命令、生成前后 diff、页面零命中）；**未手工编辑生成页**；生成器越界的附带改动（`AGENTS.md` / `CLAUDE.md` / `.github/workflows/**`）未被提交。
- 未触碰「不得触碰」清单（`tools` 侧 `git status --porcelain` 只列本 TASK 的 6 个文件 + 生成器产出面；`multica` 侧只列 `cr-prompts-revised/delivery-agent.md`）。
- 最终机器证据：`cmd-03`（整树零命中）、`cmd-04`（multica 面）、`cmd-06`（README/生成页与部署边界口径）。
- `tasks/_index.yml` 中本 TASK 标记 `done`。

## 6. 接口契约

**消费（上游 CR-2026-064-TASK-01 / CR-2026-064-TASK-02 产出的字段与形状；提示词只引用字段名，不引用实现）**

- `recovery`：`{ executable: 'node', args: string[], cwd?: string, requiresTTY: boolean, promptFor: string[] }`（键序固定）。
- 承载位置：成功结果顶层 `recovery`；错误面 `error.recovery`。
- `promptFor` 值名 → 既有 CLI 入口：`reason` → `--reason <text>`；`plan` → `--plan <temp-json>`；`CR-ID` → 位置参数 `<cr_id>`（三者被忽略时撞目标 CLI 既有 `BAD_ARGS`，零写入）。

**产出（供 CR-2026-064-TASK-04 的扫描面与评审逐条核对）**

- `tools/skills/shared/crctl/SKILL.md` 的「`recovery` 消费合同」小节 = 本 CR 消费者侧判定顺序与四类错误闭包的**唯一事实源**；`cr-archive` / `push-progress` / `merge-feature-branch` / `multica/cr-prompts-revised/delivery-agent.md` 只做节点动作声明并引用该小节。
- `openwiki/operations/crctl-transactions.md` 的恢复段描述 = 结构化 `recovery`（由生成器从迁移后的源码产出），不再出现任何 shell 命令字符串形态的恢复动作。
