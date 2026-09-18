---
id: CR-2026-070-TASK-01
type: TASK
cr-ref: CR-2026-070
plan-ref: "change-requests/CR-2026-070/plan.md"
sdd-ref: "change-requests/CR-2026-070/sdd.md"
target-version: 0.43
title: FR-1 单点规则文本：writeSkills 追加常量 + 既有形状钉子测试增项
slug: fr1-single-point-skills-routing-rule
status: pending
estimate: 6h
depends-on: []
created: 2026-09-18T11:30:00+08:00
---

## 1. 任务描述

**目标**：把 FR-1 的 Agent 行为规则作为**单点常量文本**追加进 Multica 共享 Skills brief 的 `## Skills` 段，并同步扩展既有形状钉子测试，使规则的单点性与 Provider-neutral 可被机械核对。

**背景**：AIFI-32 / CR-2026-069 期间两次质量评审因 Agent 未使用 Runtime 原生发现的 Skill、转而执行 `find /` 式兜底搜索而无限阻塞（`dep-1` §1.1）。SDD DEC-1 已裁决落点＝`writeSkills` 段内单点常量（否决「新建公共 contract 段」与「各 review Skill 复制」）。

**输入条件**：

- multica worktree（`resources[].worktreePath` 原样值）：`server/internal/daemon/execenv/runtime_config_sections.go`（基线上 `writeSkills` L833、段头 L838、列表 L839、调用点 L1058）、`server/internal/daemon/execenv/runtime_config_test.go`（`TestBriefSkillsListIsNamesOnly` L2135）；
- SDD §3.2 的逐字文本、§2.2.1（形状 1）、§4.3（合成与唯一性论证）、§6.4（既有测试面改动清单，全部为「增项」）；
- multica 仓硬规则：新增/修改注释一律英文（`../multica/ARCHITECTURE.md` §5 第 9 条）。

## 2. 涉及文件 / 模块

| 文件 | 动作 |
|---|---|
| `server/internal/daemon/execenv/runtime_config_sections.go` | 新增包内常量 `skillsRoutingRule`（英文注释，一句说明「authoritative entry point, single source, deliberately names-only list above」）＋ 在 `writeSkills` **末尾**（平台 Skill 召回提示之后）追加一次 `b.WriteString` |
| `server/internal/daemon/execenv/runtime_config_test.go` | 在既有 `TestBriefSkillsListIsNamesOnly` 内（或新增 `TestBriefSkills*` 前缀函数）**追加**断言：规则文本出现次数 = 1、多 Provider 逐字一致、不含任一 Provider 目录字面量、断言引用常量符号 |

**零改动**：`dep-6`／`dep-7`／`dep-5` 全部文件、`## Skills` 段的形状与空集早退语义（B-1、Z-7）、`cr-prompts-revised/**` 与 `server/internal/**` 中本 TASK 之外的一切文件（`dep-13`、Z-5）。本 TASK **不**改 `dir-graph.yaml`、**不**改 tools 包、**不**新增 Skill/Locator/索引/manifest。

## 3. 实现要点

1. **逐字文本**（SDD §3.2，contract 面，评审与 AC-1 按此逐字核对；不含任何 Provider 名或私有目录字面量）：

   ```text
   Treat that list as the authoritative entry point for skill selection: the runtime has already discovered those skills for this task, so use the discovered copy directly, before any repository exploration. Do not hunt for a skill on the filesystem — no recursive search for `SKILL.md` (or its shell equivalents) and no reads under guessed runtime-private directories; per-provider paths are deliberately not listed here. If a skill this task expects is not in the list, stop the current node and report the missing capability (skill name, runtime, task) through the existing technical-abort path: do not produce a business verdict, and do not write any CR state or ledger.
   ```

2. **常量与落点**：常量名固定为 `skillsRoutingRule`（包内可见，**不导出**）；插入位置 = `writeSkills` 内既有输出的**最后**（段头 → 列表 → 平台召回提示 → 规则文本），理由见 SDD §3.2（召回提示的指代对象是其紧邻上方的列表）。实现形态为「一个常量 + 一次 `b.WriteString`」，**不新增分支、不新增字段、不新增解析器**。**位置窗口（`cmd-03` 的负向断言面）**：常量声明与 `b.WriteString` 调用都必须落在 `writeSkills` 邻近（`cmd-03` 的规则窗口以锚短语为圆心取 ±1200／2400 字符切片，窗口会连带覆盖相邻代码与注释）——把常量声明放在 `writeSkills` 紧邻上方、`WriteString` 放在函数体末尾，即可让该窗口恰好覆盖规则文本与其紧邻上下文，使负向断言（无 Provider 私有面字面量）的覆盖语义固定可预测；不得把常量声明放到文件远端或另一文件。
3. **空集早退不动**：`if len(skills) == 0 { return }` 保持原位与原语义（B-1：零 Skill 任务整段不注入，规则随之不出现）。
4. **测试增项**（SDD §6.4，全部为「增项」，不改既有断言语义）：
   - `strings.Count(brief, skillsRoutingRule) == 1`（单点性）；
   - 对 ≥3 个 Provider（至少覆盖 `claude`、`codex`、`pi`）生成的 brief 中该常量逐字一致（跨 Provider 相同）；
   - 规则文本窗口内逐字**不含** `.pi/skills`、`.claude`、`.codex`、`.qwen`、`.multica`、`AGENTS.md`、`CLAUDE.md` 等 Provider 私有面字面量（I7 的负向断言）；
   - **不得**把检索锚短语（规则正文首句）内联进测试文件——测试只引用常量符号；否则 AC-1 的落点面会从 1 文件扩为 2 文件（SDD §6.4 明文）。
5. **命名**：本 TASK 新增的断言若另起函数，函数名一律以 `TestBriefSkills` 前缀（`cmd-02` 的 `-run TestBriefSkills` 只按该单一前缀过滤，不引入正则竖线）。
6. **提交**：在 multica worktree 内以 `[cr] ` 前缀提交（`crctl git commit -m '[cr] …'` 或既有提交路径），仅含本 TASK 的两个文件。

## 4. 验收条件

| # | 验收步骤（可执行） | 期望 |
|---|---|---|
| 1 | `node <TOOLS>/skills/shared/crctl/scripts/crctl.mjs git diff --name-only 59b47993810fabd12fcc393c2fa2e46611f9530d --cwd <multica worktree>` | **判据时点 = TASK-01 完成时点（此时 TASK-03 未落地）**：恰好两个路径：`runtime_config_sections.go`、`runtime_config_test.go`。TASK-03 落地后同一基线上的 diff 变为三个路径（多 `CUSTOM.md`）——该三路径形态是 **TASK-03 完成时点**的判据（TASK-03 §4 第 3 条），不得在本 TASK 落地后把三路径形态判成回归 |
| 2 | 在 multica worktree 的 `server/` 下 `go test ./internal/daemon/execenv/ -count=1 -v -run TestBriefSkills` | exit 0；stdout 含 `--- PASS:` 与 7 个 provider 子用例（不得出现 `no tests to run`） |
| 3 | 在 multica worktree 根执行 `cmd-03` 的表内字面命令（plan §6.2） | **计划内红点（分批时点）**：`cmd-03` 的 failures **恰为 1**，且唯一失败项为 `FAIL CUSTOM.md 缺 CR-2026-070 台账行`——该行是 TASK-03 的交付物（`depends-on: [TASK-01, TASK-02]`），故本 TASK **不**要求 `cmd-03` exit 0。除该项外，落点面锚短语命中数 = 1；零复制面（`server/internal/**` 落点两文件之外 + `cr-prompts-revised/**`，实测扫描面 1492 文件）命中数 = 0；测试文件引用 `skillsRoutingRule` 且**未**内联锚短语；规则窗口无 Provider 私有面字面量（落点／零复制／测试三面在本 TASK 落盘后单独转绿；台账面由 TASK-03 收口，`cmd-03` 达到 failures = 0 的时点是 TASK-03 完成时点，见 plan §6.3 的 `cmd-03` 行） |
| 4 | 手动核对既有断言语义未被改写：`git diff` 中 `runtime_config_test.go` 的改动**只含新增行**（`+` 行），既有断言行不得出现 `-` 行 | 既有形状钉子（slug 索引、无描述、无 Provider 分支、空集不注入）逐字保留 |

## 5. 完成标志

1. 上述两条文件已落盘并在 multica worktree 内以 `[cr] ` 前缀提交（工作树 clean，`crctl workspace inspect CR-2026-070` 中 `multica` 仍 `classification=healthy`）；
2. 验收条件 1～4 全部满足（其中 3 由作者 run 内实跑留证：`cmd-03` failures **恰 1**、唯一项为 `CUSTOM.md` 台账行；该残留项**由 TASK-03 收口**，本 TASK 不为其提前落地、也不在标 done 时留未判红项——本 TASK 的完成判据是「failures 恰 1 且失败项归属 TASK-03」）；
3. 本 TASK 已在 `tasks/_index.yml` 登记 `done`（`crctl task done CR-2026-070 --task CR-2026-070-TASK-01`，工程纪律 8）；
4. **完成边界**：仅到「实现已落盘 + 关键测试命令可复跑」为止；**不**包含 `review-code`／`merge`／回写（CR-2026-057 FR-10）。

## 6. 接口契约

**产出**（被 `writeSkills`、测试文件与 `cmd-03` 共同消费；三者引用同一符号，逐字对齐 SDD §3.2）：

```ts
// server/internal/daemon/execenv/runtime_config_sections.go（包内可见，不导出）
const skillsRoutingRule = "Treat that list as the authoritative entry point for skill selection: ... do not write any CR state or ledger."
```

- 类型：`string` 常量；**无参数、无返回值、无错误语义**；对同一 `TaskContextForEnv` 的多次调用逐字相同（brief 在 run 内幂等，SDD §2.2.1 确定性）。
- 出现条件：与 `modelVisibleSkills(ctx.AgentSkills)` 过滤后非空**同条件**（空集时整段不注入，规则不出现，B-1）。
- 出现次数：单次 brief 内恰 1 次（跨 Provider 同文本，不按 Provider 分支）。

**消费**：

| 消费方 | 用法 |
|---|---|
| `writeSkills(b *strings.Builder, ctx TaskContextForEnv)` | 段末尾 `b.WriteString(skillsRoutingRule)`（唯一写入点） |
| `runtime_config_test.go` | 引用常量符号做计数／跨 Provider 一致性／负向字面量断言（**不内联**锚短语） |
| `cmd-03`（plan §6.2） | 以锚短语做「落点面命中 1／零复制面命中 0」同一次检索的两侧核对，并要求常量符号在落点与测试文件均出现 |

**不消费**：本 CR 无任何代码消费者读取该文本（它是下发给人读的 brief 文本，非结构化解码对象）。
