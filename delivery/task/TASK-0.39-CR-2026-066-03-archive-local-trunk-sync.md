---
spec-id: ai-first-platform
version: "0.39"
id: CR-2026-066-TASK-03
type: TASK
cr-ref: CR-2026-066
plan-ref: "change-requests/CR-2026-066/plan.md"
sdd-ref: "change-requests/CR-2026-066/sdd.md"
target-version: 0.39
title: "归档尾部 trunk 同步：archiveCr 三个成功返回点改经局部包装 + 返回值新增 localTrunkSync + AC-8 六项用例"
slug: archive-local-trunk-sync
status: pending
estimate: 16h
depends-on: []
created: 2026-09-14T15:25:00+08:00
---

# CR-2026-066-TASK-03 归档尾部 trunk 同步（G3，FR-10）

## 1. 任务描述

**目标**：让 `crctl archive` 在终态事务尾部复用既有 `reconcileLocalTrunks(ctx)`，把各仓**主 checkout** ff-only 对齐 origin，并在返回值新增 `localTrunkSync`（与 `recovery` 同级）；同时把 `cr-archive` SKILL 的结果分类表/输出块与该字段同步，并新增 AC-8 六项用例。

**背景**：`reconcileLocalTrunks` 目前唯一调用点是 merge（`workspace-transactions.mjs:1786`）。归档是 CR 最后一个动作，此后无任何节点把主 checkout 对齐 origin。本卡是**最小侵入**：只加第二个调用点与一个返回字段，**不改**该函数的判据、分类与行形状。

**输入条件**：`tools` worktree HEAD = `5d5a4ada…`；`sdd.md` §4.6 已审批（**不得改一字**）；`plan.md` §6.1/§6.3 已冻结。

**范围边界（`zero_diff`，本卡逐条不触碰）**：`crctl.mjs`（全文件）、`rules.json`、`gates.json`、`gate-registry.json`、`emit-registry.mjs`；**`reconcileLocalTrunks(ctx)` 函数体零 diff**（不改判据、不改分类、不改行形状）；`checkpointCr` / `mergeCr` / `applyWriteback` / `registerCr` / `buildRecovery` 的函数签名与内部逻辑零 diff；`archiveCr` 既有返回字段（`commit` / `lastCleanupError` / `remaining` / `preservedRefs` / `recovery` / `warnings`）与 `phase` 分类（`complete` / `cleanup-pending`）、`crctl archive` 退出码零 diff；**不新增错误码**；`delivery-agent.md` 的汇报面句归 TASK-04（本卡不动该文件）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 说明 |
|---|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 改 `archiveCr` 尾部（< 20 行） | 局部包装 `resultWithTrunkSync` + 三个成功返回点改经包装（§3.1） |
| `skills/cr/cr-archive/SKILL.md` | 改 Step 3 结果分类表 + 「输出」块 | 新增 `localTrunkSync`（4 状态 × 6 reason 分类说明 + dirty 的补救指引）；既有字段与 `recovery` 语义逐字不变 |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | **新增 6 条用例** | AC-8①~⑥（§3.3）；复用既有 fixture `makeWritebackFixture`（L17）/ `makeNewModeArchiveFixture`（L86），**不新建夹具、不新增测试文件** |

## 3. 实现要点

### 3.1 `archiveCr` 的最小侵入改动（SDD §4.6.1 逐字）

```text
archiveCr(ctx, input):
  …（既有事务主体：证据门 → journal → 四账本编辑 → commit → lease push → outbox → cleanup；一行不改）…
  + 局部包装（不导出、不新建模块，紧邻既有 result(...) 定义）：
      const resultWithTrunkSync = (phase, changed, warnings, outbox)
        => result(phase, changed, warnings, outbox, reconcileLocalTrunks(ctx));
  + 三个成功返回点改经该包装：
      ① phase===complete 的幂等重放早退（现 L3597 区域）
      ② 末尾 phase=complete（现 L3757 区域）
      ③ 末尾 phase=cleanup-pending（现 L3759 区域）
```

1. **调用点时序**：归档 push 与 cleanup **之后**计算（终态已发布，trunk 事实稳定）；幂等重放路径**单独计算**（不复用上次结果，符合 FR-10.7「按当次实况返回」）。
2. **返回值**：`result()` 结果对象新增 `localTrunkSync` 字段（与 `recovery` 同级），其余字段逐字不变。`result(...)` 的既有签名若为固定形参，按**最小改动**新增一个参数并保持其余调用点不变（其余调用点所在函数在 `zero_diff` 内，**不得**改动它们的调用形态）。
3. **失败不阻断**：`reconcileLocalTrunks` 全程 best-effort（自身对 `fetch`/`merge --ff-only` 局部捕获、不抛错）⇒ 归档退出码与 `phase` 分类不受影响；逐仓失败只反映在行内 `status`/`reason`。
4. **dirty 策略**：主 checkout dirty ⇒ `skipped` + `reason=dirty`，**零改动**本地在途修改；报告给出逐条 `reason` 与人类可执行的补救说明（`fetch --prune origin` + `merge --ff-only origin/{trunk}`）。
5. 只处理 `dir-graph.yaml#repositories` 的**主 checkout**；**永不** `reset`/`clean`/`stash`/强推/改 CR worktree。

### 3.2 `cr-archive/SKILL.md`（FR-10.8）

- Step 3 结果分类表 + 「输出」块新增 `localTrunkSync`，含**4 状态**（`unchanged` / `synced` / `skipped` / `failed`）× **6 reason**（`wrong-branch` / `dirty` / `diverged` / `fetch-failed` / `trunk-unavailable` / `ff-only-failed`）与「`status=unchanged|synced` 时 `reason=null`」的口径；给出 `skipped`/`failed` 的人类补救指引。
- 既有字段（`commit` / `lastCleanupError` / `remaining` / `preservedRefs` / `recovery` / `warnings`）逐字保留；`recovery` 的语义与字段名不变。
- 文本必须通过 `lint-prompts --mode enforce`（不裸写 `git` 写命令、不手写账本、不出现退役字段名）。

### 3.3 AC-8 六项用例（`archive-tx.test.mjs`，**命名必须以 `CR-2026-066 AC-8` 起始**）

| # | 用例名（建议逐字） | 断言内容 |
|---|---|---|
| ① | `CR-2026-066 AC-8① 三个成功返回点均含 localTrunkSync` | 幂等重放早退 / `phase=complete` / `phase=cleanup-pending` 三个返回都含该字段（数组，元素含 `{repo,trunk,before,remote,after,status,reason}` 七键） |
| ② | `CR-2026-066 AC-8② 4 状态 × 6 reason 分类正确` | 逐状态/逐 reason 的赋值路径与函数实际分支一致（`wrong-branch`/`dirty`/`fetch-failed`/`trunk-unavailable`/`diverged`/`ff-only-failed`）；`unchanged|synced ⇒ reason=null` |
| ③ | `CR-2026-066 AC-8③ dirty ⇒ skipped/dirty 且本地逐字节未变` | 主 checkout 写入未提交文件 → 归档后 `status=skipped` ∧ `reason=dirty` ∧ 该仓工作区内容**逐字节未变**（读入前做 `\r\n → \n` 归一，比较前后哈希） |
| ④ | `CR-2026-066 AC-8④ argv 级命令面白名单`（**硬失败**） | 抽 `export function reconcileLocalTrunks` 起至**下一个顶层 `}`** 的函数体文本 → 抽其中全部 `gitRun`/`gitMust` 的**第二实参** argv（实测 **7 个调用点**）→ 归一化签名去重后**恰为** `rev-parse` / `rev-parse --verify` / `symbolic-ref` / `status` / `fetch --prune` / `merge-base --is-ancestor` / `merge --ff-only`（无多无少），且全部 argv 元素不含 `reset`/`clean`/`stash`/`--force`/`push`。**函数体抽不到、argv 解析不到、调用点数 ≠ 7 ⇒ 抛错（红），禁止降级为空串/空集**；判据**只作用于 argv 元素**，**不得**对整段函数体文本做子串匹配（`rows.push(row)` 含 `push`） |
| ⑤ | `CR-2026-066 AC-8⑤ changed=false 重放仍返回且零新 commit` | 归档幂等重放（`changed=false`）时仍返回 `localTrunkSync`（按当次实况）、无新 commit、无第二次清理 |
| ⑥ | `CR-2026-066 AC-8⑥ cr-archive SKILL 分类/输出块含 localTrunkSync` | 文本断言：`skills/cr/cr-archive/SKILL.md` 含 `localTrunkSync` 且含 4 状态 × 6 reason 的分类说明。**delivery 汇报面的一半归 TASK-04**（SDD §4.6.2 的 delivery 汇报面句，落在 `agents/delivery-agent.md` 与 `../multica/cr-prompts-revised/delivery-agent.md`）——分卡是为了让本卡可独立验收：本卡完成后 `cmd-04` 即可绿；交付态的 AC-8⑥ 由 `cmd-04`（SKILL 面）与 `cmd-06`（multica delivery 副本含 `localTrunkSync`）两条命令共同覆盖 |

- **命名约定是硬约束**：`cmd-04`（`--test-name-pattern CR-2026-066`）与 `cmd-05` 的守卫（f）（token `CR-2026-066 AC-8` ≥ 6）都依赖它；本条 run 已实测：用例不存在时 `--test-name-pattern` **空跑 exit 0**（无摘要），且 dot 报告器**不输出用例名与摘要** ⇒ **单靠 `cmd-04` 的退出码（或点号数）不构成存在性证据**，用例名与存在性一律由 `cmd-05` 的源码级守卫（f）承载（plan §6.1 表注⑤）。
- **`test(` 调用数**：基线 28（既有 24 用例）→ 本卡后 ≥ 34；`cmd-05` 的守卫要求 ≥ 30。
- ⑥ 与 TASK-04 的分工：本卡只落 `cr-archive/SKILL.md` 的一半与它自己的文本断言；delivery 汇报面句（tools `agents/delivery-agent.md` + multica 副本）由 TASK-04 落盘，其机器判据在 `cmd-06`（multica 副本含 `localTrunkSync`）。**不得**为让某条命令提前变绿而跨卡落盘。

### 3.4 通用纪律

- 行尾纪律：所有读入先 `\r\n → \n`；解析失败硬失败（工程纪律 #1）。
- 独立验证（本卡的关键判据）：③ 的「逐字节未变」与 ④ 的 argv 判据是**两条独立证据**（一个看副作用面、一个看命令面），不得合并为一条。
- 断言只读：不写账本、不改 `gate-registry.json`（新增用例数不需要登记，`manifest.cases` 是下界）。

## 4. 验收条件（可执行）

1. **`cmd-04`**（plan §6.2，`repo=tools`）：`node --test --test-reporter=dot --test-name-pattern CR-2026-066 skills/shared/crctl/scripts/test/archive-tx.test.mjs` → **exit 0**；用例名清单与存在性**不由本命令的 stdout 承载**（dot 报告器只输出点号，无名字、无摘要；空跑亦 exit 0）——在完成记录中登记：① `cmd-05` 守卫（f）的两行实测值（`archive-tx AC-8 tokens`≥ 6、`test(` count ≥ 30）；② 六项用例名与源码行号对照表；③ `cmd-04` 的 dot 点数（= 命中且通过的用例数，期望 ≥ 6，作为「执行面」辅助计数）。
2. **`cmd-05`** 的 AC-8 存在性守卫：`archive-tx AC-8 tokens ≥ 6` ∧ `test( count ≥ 30` → 该守卫不得出现在失败清单中。
3. **`cmd-01`** 全量套件 → `verdict=pass` / `failures=0` / **`cases_executed ≥ 594`**（588 基线 + 本卡 6 条新用例）。
4. 负控自检（非证据）：临时把某一返回点改回**不带** `localTrunkSync`，或把 `reconcileLocalTrunks` 的某个 `gitRun` argv 换成含 `push` 的元素 → ①/④ **必须红** → 还原 → `crctl git status --short` 干净。
5. `zero_diff` 自查：`crctl git diff --stat -- skills/shared/crctl/scripts/crctl.mjs skills/shared/crctl/gates.json skills/shared/crctl/scripts/test/gate-registry.json` 为空；`workspace-transactions.mjs` 的 hunk 级禁改 token 检查（`cmd-05`）无命中。

## 5. 完成标志

- 3 个文件就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-04` exit 0（dot 点数 ≥ 6，仅作执行面辅助计数）；`cmd-05` 守卫（f）通过（`CR-2026-066 AC-8` token ≥ 6 ∧ `test(` ≥ 30）；`cmd-01` 全量套件绿（无例外）。
- **六项用例 → 用例名（源码 token）→ `cmd-05` 守卫（f）实测计数**三列对照表写入本任务完成记录（另附 `cmd-04` 的 dot 点数）；④ 的**实测调用点数 = 7** 与归一化签名集合逐项留档（硬失败分支的活性亦留一条负控痕迹）。
- `zero_diff` 面零 diff（`crctl.mjs` / 五个函数的签名与内部逻辑 / `reconcileLocalTrunks` 函数体 / `archiveCr` 既有字段与 `phase` 分类 / 退出码）。
- **任务账本登记**：`crctl task done CR-2026-066 --task CR-2026-066-TASK-03`（即时标 `done` 带 `done-at`）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `reconcileLocalTrunks(ctx) -> Array<{repo, trunk, before, remote, after, status, reason}>`（`workspace-transactions.mjs` L1487-1530；**只读复用，零 diff**）：`status ∈ unchanged|synced|skipped|failed`；`reason ∈ wrong-branch|dirty|diverged|fetch-failed|trunk-unavailable|ff-only-failed`（`unchanged|synced` 时 `null`）。
- `archiveCr(ctx, input)` 的既有 `result(...)` 构造与三个成功返回点位置（现 L3597 / L3757 / L3759 区域）；既有返回字段 6 个。
- `gitRun(cwd, args, opts)`（L378）/`gitMust(cwd, args, opts)`（L383）：argv 恒为**第二实参**（AC-8④ 的抽取前提）。
- 既有 fixture `makeWritebackFixture`（L17）/ `makeNewModeArchiveFixture`（L86）——**复用，不新建**。

**产出（下游 TASK 消费方不得缩略）**

- `crctl archive` 返回值新增字段名与行形状 **`localTrunkSync`**（与 `recovery` 同级）——TASK-04 的 `delivery-agent` 汇报面句与 `cr-archive/SKILL.md` 之外的文档面（若有）必须引用同一字段名与同一 4×6 分类，**不得**自造别名。
- `archive-tx.test.mjs` 的 **AC-8 六条用例名**（`CR-2026-066 AC-8①…⑥`）——`test-report.md` 的 TASK 验收覆盖矩阵与 `review-code` 的取证面按这些名字定位。
