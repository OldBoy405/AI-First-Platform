---
spec-id: ai-first-platform
version: "0.37"
id: CR-2026-064-TASK-02
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "CLI 投影迁移：register 单投影、gate 错配与 reset 失败分支结构化、删除占位符 helper"
slug: cli-projection-migration-single-projection
status: pending
estimate: 8h
depends-on: [CR-2026-064-TASK-01]
created: 2026-09-13T22:15:00+08:00
---

# CR-2026-064-TASK-02 —— CLI 投影与错误面迁移

覆盖 FR：**FR-4、FR-6、FR-10（投影侧）、FR-13、FR-17（判定顺序与错误闭包的生产侧）**（SDD §3.3/§3.4/§4.2）；变更组 **G2**；主责仓：`tools`。

## 1. 任务描述

**目标**：在 `tools/skills/shared/crctl/scripts/crctl.mjs` 原位完成 5 处迁移：`buildRegisterResult` 单投影、`cmdRegister` 输出字段改名、`cmdGate` pre-review 错配分支结构化、`cmdReviewLoopReset` 提交失败分支结构化（`promptFor: ['reason']` + `requiresTTY: true`）、以及 `crIdForRecover` 占位符 helper 的删除（改为规范 CR-ID 判定）。**CLI 层不得重新拼接任何 shell string**：`recovery` 一经构造即透传（SDD §4.2 第 4 步）。

**背景**：CLI 是唯一命令入口与投影层；现状在 `register` 处同时投影 `recoverCommand` 与 `recover_command` 两个同义字段（PRD §1.1 第 3 类缺陷的现存实例），错误面另有两处把恢复动作作为字符串返回。本 TASK 把这些载体换成结构化 `recovery`，并保持错误码、退出码、`txId`、`rollback`/`files` 语义不变（FR-13）。

**输入条件**：tools CR worktree（`execution_context.resources[tools].worktreePath`，HEAD `81d31b8…`）；**CR-2026-064-TASK-01 已完成**（`buildRecovery` 已导出、可 import）；SDD `6c5c9a11`（sha256 `d9f727b6…`）只读。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | 唯一改动文件：`crIdForRecover`（删除/替换）、`cmdGate`、`cmdReviewLoopReset`、`buildRegisterResult`、`cmdRegister` 输出对象 5 处 |

**不得触碰**（SDD §9 `zero_diff`）：`lib/workspace-transactions.mjs`（属 CR-2026-064-TASK-01）、`skills/shared/crctl/scripts/test/**`（属 CR-2026-064-TASK-04）、`lib/durable-tx.mjs`、`lib/yaml-subset.mjs`、`README.md` / `openwiki/**` / 4 份消费方 SKILL（属 CR-2026-064-TASK-03）、`gates.json`、`controlled-shell/rules.json`、`pipeline-templates/**`、`.github/workflows/**`、`gate-registry.json`。

## 3. 实现要点

1. **单投影**（SDD §4.2 第 1 步）：`buildRegisterResult` 只保留 `recovery`；`cmdRegister` 的输出对象由 `recoverCommand: r.recoverCommand, recover_command: r.recoverCommand` 改为 `recovery: r.recovery`。其它 snake_case 镜像（`cr_id` / `tx_id` / `operational_workspace` …）**不动**（SDD §9 `zero_diff`）。
2. **透传核对**（§4.2 第 2 步）：各 `ok({ op: '<x>', ...result })` 站点本身不改，但必须逐一核对 producer 侧已改名（`archive` / `checkpoint` / `merge` / `workspace-sync` / `writeback-apply` / `test` 六类）——发现遗漏立即回到 CR-2026-064-TASK-01 的文件修正，**不得在 CLI 层补拼**。
3. **站点 10（`gate --mode pre-review` 错配）**：`fail(..., { recovery })`，其 `args` 为 `workspace inspect <cr>`；规范 CR-ID 判定 `^CR-\d{4}-\d{3,}$` 成立时把 CR-ID 作为独立 argv 元素，否则**省略该元素**并声明 `promptFor: ['CR-ID']`；`cwd` 取执行 `gate` 的工作区；`requiresTTY: false`。既有 `crIdForRecover`（返回 `<CR-ID>` 占位符串）随之删除——占位符不再进入 `args`（决策 D-4）。
4. **站点 11（`review-loop reset` 提交失败）**：`fail(..., { recovery })`，其 `args` 为 `review-loop reset <cr> --loop <loopRef>`，`--reason` **不进 `args`**，声明 `promptFor: ['reason']`（CR-ID 非规范时按站点 10 同一判定并入 `'CR-ID'`）、`requiresTTY: true`、`cwd` 取执行 `reset` 的工作区；`~L1912` 的注释同步改写（不得残留旧字段名）。既有 `NOT_TTY` 前置校验（`~L1840`）零改动。
5. **错误信封不变**（§11-2）：错误仍走 `fail(code, message, extra)`（stderr + exit 1），成功对象仍走 stdout；`error.recovery` 与顶层 `recovery` 的落点由既有 `fail`/`ok` 形状决定，不新增信封字段。
6. **无 shell 拼接**：本文件内不得出现把 `recovery` 渲染成字符串后执行的路径；不得引入 `shell: true`。

## 4. 验收条件

1. 旧名零命中 + 占位符 helper 已消失：
   ```bash
   rg -n "recoverCommand|recover_command" skills/shared/crctl/scripts/crctl.mjs   # 期望：零命中
   rg -n "crIdForRecover" skills/shared/crctl/scripts/crctl.mjs                   # 期望：零命中
   ```
2. 语法可解析：`node --check skills/shared/crctl/scripts/crctl.mjs`（退出码 0）。
3. 两处错误分支的结构化形状可读：`cmdGate` 错配分支与 `cmdReviewLoopReset` 失败分支均构造 `recovery`（后者含 `requiresTTY: true`、`promptFor` 含 `'reason'`、`args` 不含 reason 文本），由 CR-2026-064-TASK-04 的结构断言与 6 类 reason 向量最终证明。
4. `register` 单投影：结果字段集**含** `recovery`、**不含** `recoverCommand` / `recover_command`（由 `register-tx.test.mjs` 的单投影断言证明，归 CR-2026-064-TASK-04）。
5. 语义零漂移：`MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` / `REVIEW_LOOP_RESET_COMMIT_FAILED` / `BAD_ARGS` / `NOT_TTY` 的错误码字面与 `exit code` 未变（`rg -n "REVIEW_LOOP_RESET_COMMIT_FAILED|NOT_TTY" skills/shared/crctl/scripts/crctl.mjs` 命中位置与基线一致）。

## 5. 完成标志

- 上列五条验收条件全部通过，且本 TASK 触达文件（`crctl.mjs`）旧名零命中。
- 5 处站点逐条对照 SDD §3.3 命令面投影表核对完成（含 `register` 双投影删除、两处 `error.recovery`、占位符 helper 删除）。
- 未引入 alias / shim / fallback；未在 CLI 层重新拼接 shell string；未触碰「不得触碰」清单（`git status --porcelain` 只列本文件）。
- 最终机器证据归 CR-2026-064-TASK-04：`cmd-01`（`crctl.test.mjs` 的 reset / gate / 成功结果字段集用例、`register-tx.test.mjs` 单投影断言）与 `cmd-05`（`shell: true` / `Invoke-Expression` 零命中、diff 面白名单）。
- `tasks/_index.yml` 中本 TASK 标记 `done`。

## 6. 接口契约

**消费（上游 CR-2026-064-TASK-01 产出，逐字对齐 SDD §3.2）**

```js
import { buildRecovery } from './lib/workspace-transactions.mjs';
// buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] }) → Recovery
// Recovery = { executable: 'node', args: [CRCTL_SCRIPT_PATH, ...args], cwd?, requiresTTY, promptFor }
```

**产出（供 CR-2026-064-TASK-03 的提示词合同与 CR-2026-064-TASK-04 的断言消费；逐字对齐 SDD §3.3/§3.4）**

| 命令 / 场景 | 新载体 | `args`（`args[0]` 之后） | `cwd` | `requiresTTY` | `promptFor` |
|---|---|---|---|---|---|
| `register` | 成功结果 `recovery`（**单投影**） | `register --registration-key <k> --title <t> --owner-requirement <r> --owner-development <d> --owner-test <e> (--summary <s>)? (--source <s>)? (--origin <o>)? (--target-version <v>)? --target-spec-id <id> --workspace <ws>` | `<ws>` | `false` | `[]` |
| `gate --mode pre-review` 错配 | `error.recovery` | `workspace inspect <cr>`（非规范 CR-ID 时省略该元素） | 执行 `gate` 的工作区 | `false` | `[]` 或 `['CR-ID']` |
| `review-loop reset` 提交失败 | `error.recovery` | `review-loop reset <cr> --loop <loopRef>`（`--reason` 走 `promptFor`） | 执行 `reset` 的工作区 | `true` | `['reason']`（CR-ID 非规范时并含 `'CR-ID'`） |

契约不变量（下游可依赖）：`recovery` 满足 SDD §3.1 的 `Recovery` 接口；`args` 每元素是一个完整 argv；错误面载体恒为 `error.recovery`、成功面载体恒为顶层 `recovery`；`promptFor` 中的值**不出现在** `args` 或任何 shell string 中（SDD §3.4 三处映射：`reason` → `--reason <text>`、`plan` → `--plan <temp-json>`、`CR-ID` → 位置参数；被忽略时撞目标 CLI 既有 `BAD_ARGS`，零写入）。
