---
id: CR-2026-070-TASK-03
type: TASK
cr-ref: CR-2026-070
plan-ref: "change-requests/CR-2026-070/plan.md"
sdd-ref: "change-requests/CR-2026-070/sdd.md"
target-version: 0.43
title: CUSTOM.md #96 台账行（原因追溯含 CR-2026-070 与 TASK-01／TASK-02）
slug: multica-custom-ledger-row
status: pending
estimate: 2h
depends-on: [CR-2026-070-TASK-01, CR-2026-070-TASK-02]
created: 2026-09-18T11:30:00+08:00
---

## 1. 任务描述

**目标**：按 `../multica/CUSTOM.md` **其当时实际结构**，为本次 multica 侧定制顺延登记一行台账（稳定行号 **#96**），使双周 rebase 前的 fork 定制核对清单包含本 CR 的两个落点。

**背景**：`AGENTS.md` 工程纪律 10（任何落在 multica 仓的代码改动必须登记 CUSTOM.md）；SDD §9 `scope_in` 第 3 项把该登记列为本 CR 在 multica 仓 diff 的组成部分，且**不受 `zero_diff` 约束**（`dep-9`／`dep-13` 的 carve-out）。

**输入条件**：

- TASK-01 与 TASK-02 已完成的**最终**文件清单与提交（本 TASK 依赖两者：台账行须与最终形态一致，不得登记未落地的路径）；
- `CUSTOM.md` 现状（基线 `59b47993`）：`## 代码改动明细（按 CR 分组）` 下末段章节为 `### CR-2026-066 …`（L487），全表最大稳定行号 **#95**；行模板为六列 `# | 位置 | 改动 | 原因 / 追溯 | 日期 | 合并注意`，且「合并注意」列末尾必须带一条「验证：」最小命令。

## 2. 涉及文件 / 模块

| 文件 | 动作 |
|---|---|
| `<multica worktree>/CUSTOM.md` | 在**其当时实际结构**下新增一行 `| 96 | … |`（如末段章节与本 CR 无关则在同一「按 CR 分组」节内为 CR-2026-070 新增小节并放入该行） |

**零改动**：除该行外的一切内容（既有行号不复用、不改写历史行）；本 TASK 不动任何源码、不动 `dir-graph.yaml`、不动 tools 包。

## 3. 实现要点

1. **行号顺延**：`#96`（`#95` 之后的下一个整数；只增不改；跨行引用用 `#N`）。
2. **位置列**：`server/internal/daemon/execenv/runtime_config_sections.go（writeSkills 末尾追加 skillsRoutingRule 常量）`，并注明 `runtime_config_test.go` 的断言增项。**注**：本次改动**无** `// AIFIRST:` 标记行（规则文本是 brief 文本常量，不是挂钩点）——位置列按台账模板以「文件/函数」写清即可，不要为了凑格式添加标记。
3. **改动列**：一句话说明「在共享 Skills brief 的 `## Skills` 段末尾追加 Provider-neutral 的 Skill 路由权威规则（单点常量，不复制到各 Skill/Prompt）」；如同时登记 TASK-02 的 Pi 侧改动，须明确写出「Pi 侧落点在 `earendil-works/pi-mono` 检出（非本仓文件），本行仅登记 multica 侧改动」，避免把非本仓文件混入本仓定制清单。
4. **原因 / 追溯列**：`AIFI-32/CR-2026-069 两次评审因未用 Runtime 原生发现 Skill 而无限阻塞。CR-2026-070 FR-1（TASK-01；关联 TASK-02）`。
5. **合并注意列**：取四种标准口径中正确的一条（本改动是**加法**：上游不冲突时逐字保留；上游改 `writeSkills` 结构时把追加文本贴回段末尾，并保持「单点、不复制」），末尾附「验证：」最小命令——使用 `cd server && go test ./internal/daemon/execenv/ -count=1 -run TestBriefSkills -v`。
6. **日期**：实施日期（`YYYY-MM-DD`）。

## 4. 验收条件

| # | 验收步骤（可执行） | 期望 |
|---|---|---|
| 1 | 在 multica worktree 根执行 `cmd-03` 的表内字面命令（plan §6.2） | exit 0：其中 `CUSTOM.md` 断言要求文本含 `CR-2026-070` 与 `runtime_config_sections.go`，且 `CUSTOM.md` 读长 ≥ 5000 字符 |
| 2 | 逐行核对台账行 | 六列齐备；行号为 `96`（不重复、不跳号）；「原因 / 追溯」含 `CR-2026-070` 与 `TASK-01`；「合并注意」含「验证：」+ 上述最小命令 |
| 3 | `git diff --name-only 59b47993810fabd12fcc393c2fa2e46611f9530d`（multica worktree） | **判据时点 = TASK-03 完成时点（此时 TASK-01 已落地）**：恰好三个路径：`runtime_config_sections.go`、`runtime_config_test.go`、`CUSTOM.md`（与 plan §6.2 `cmd-04` 的白名单双向相等判据一致）。注：两路径形态是 **TASK-01 完成时点**的判据（TASK-01 §4 第 1 条），本 TASK 落地后必然不再成立——不得据此判 TASK-01 回归 |

## 5. 完成标志

1. `CUSTOM.md` 的台账行已落盘并在 multica worktree 内提交（`[cr] ` 前缀；可与 TASK-01 同批或独立提交，工作树 clean）；
2. 验收条件 1～3 全部满足；
3. 本 TASK 已在 `tasks/_index.yml` 登记 `done`（工程纪律 8）；
4. **完成边界**：到「台账行落盘 + 可复跑核对」为止；**不**包含 `merge`／rebase 动作本身、**不**包含回写（CR-2026-057 FR-10）。

## 6. 接口契约

**产出**（文档面，无代码签名；被 `cmd-03` 与后续 rebase 核对消费）：

```text
| 96 | <位置：文件/函数> | <改动一句话> | <原因 / 追溯：AIFI-32…CR-2026-070 FR-1（TASK-01）> | <YYYY-MM-DD> | <合并注意（四种口径之一）> 验证：cd server && go test ./internal/daemon/execenv/ -count=1 -run TestBriefSkills -v |
```

- **稳定标识**：行号 `#96`（只增不改，跨行引用用 `#N`）。
- **必填六列**：`#`、位置、改动、原因 / 追溯、日期、合并注意（末尾「验证：」）。
- **一致性约束**：位置/改动列描述的文件集必须与 TASK-01（+TASK-02 的说明句）的最终落点逐字一致；不得登记未落地的路径，也不得遗漏已落地的路径。

**消费**：

| 消费方 | 用法 |
|---|---|
| `cmd-03`（plan §6.2） | 断言 `CUSTOM.md` 含 `CR-2026-070` 与 `runtime_config_sections.go`，读长 ≥ 5000 字符（读空即硬失败） |
| 双周 rebase 前核对（CUSTOM.md 文件头口径） | 以本行为本 CR 的 multica 定制入口，逐条核对 `// AIFIRST:` 标记与追加文本存活 |
