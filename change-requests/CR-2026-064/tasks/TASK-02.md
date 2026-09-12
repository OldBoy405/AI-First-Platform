---
id: CR-2026-064-TASK-02
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "CLI 投影迁移：register 单投影、gate 错配与 reset 失败分支结构化、删除占位符 helper"
slug: recovery-cli-projection-migration
status: pending
estimate: 8h
depends-on: [CR-2026-064-TASK-01]
created: 2026-09-13T00:20:00+08:00
---

# CR-2026-064-TASK-02 —— CLI 投影迁移与错误面结构化

覆盖 FR：**FR-4、FR-6、FR-10（CLI 侧）、FR-13**（SDD §3.3/§3.4/§4.2）；变更组 G2；主责仓：`tools`。

## 1. 任务描述

**目标**：在 `tools/skills/shared/crctl/scripts/crctl.mjs` 内原位完成四件事：① `register` 结果从 `recoverCommand` + `recover_command` **双投影**改为单投影 `recovery`；② `gate --mode pre-review` 错配分支的 `error.recoverCommand` 改为结构化 `error.recovery`；③ `review-loop reset` 提交失败分支的 `error.recoverCommand` 改为结构化 `error.recovery`（`promptFor: ['reason']`、`requiresTTY: true`）；④ 删除占位符 helper `crIdForRecover`（`<CR-ID>` 哨兵不再进入 `args`）。CLI 层**不得**重新拼接任何 shell string，`recovery` 一经构造即透传。

**背景**：`recoverCommand` 的最后一个「两个同义字段并存」的位置就在注册结果里（PRD §1.1 第 4 类缺陷的现存实例）；`gate` 错配与 `reset` 提交失败是 CLI 侧仅有的两处错误面恢复动作，二者都需要「人重新输入」或「CR-ID 规范化」的显式声明（SDD D-4）。

**输入条件**：tools CR worktree（`requirement/CR-2026-064`）；CR-2026-064-TASK-01 已完成并经 `crctl task done` 登记（`buildRecovery` 已在 `lib/workspace-transactions.mjs` 导出）；`crctl workspace freshness CR-2026-064`（gate=implement-start）通过。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | **唯一改动文件**：`buildRegisterResult`（`recovery` 单字段）、`cmdRegister` 输出对象（删双投影）、`cmdGate` 的 `--mode pre-review` 错配分支（`fail(..., { recovery })`）、`cmdReviewLoopReset` 提交失败分支（`fail(..., { recovery })`）、`crIdForRecover` helper 删除 + 规范 CR-ID 判定（两站点共用一份） |

**不得触碰**（SDD §9 `zero_diff`）：`skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（属 CR-2026-064-TASK-01，只读 import）、`test/**`（属 CR-2026-064-TASK-04）、`README.md` / `openwiki/**` / 4 份消费方 SKILL（属 CR-2026-064-TASK-03）、`gates.json`、`controlled-shell/rules.json`、`dir-graph.yaml`、`.github/workflows/**`；`crctl.mjs` 中上述 5 处之外的段落（含 `fail()` / `ok()` 信封、`NOT_TTY` 前置校验、其它命令分支）逐字不动。

## 3. 实现要点

1. **`import` 方向（SDD §1.2）**：从 `./lib/workspace-transactions.mjs` 引入 `buildRecovery`（CLI 单向依赖 lib，lib 不反向依赖 CLI）。
2. **规范 CR-ID 判定（SDD §4.1 站点 10/11 共用的极小判定）**：在模块作用域定义一次
   `const RECOVERY_CR_DIR_RE = /^CR-\d{4}-\d{3,}$/;`（与 `lib` 的 `CR_DIR_RE` 同语法、与既有 `archive` / `version-set` 的校验形态一致），并以一处极小 helper 或内联三元完成「规范 ⇒ 作为独立 argv 元素；非规范 ⇒ 省略该元素并声明 `promptFor: ['CR-ID']`」。**删除** `crIdForRecover`（返回 `<CR-ID>` 占位符串的 helper）——占位符不再进入 `args`（D-4）。
3. **站点 10：`cmdGate` 的 `--mode pre-review` 错配分支（SDD §3.4 / §4.1 站点 10）**：
   - `args` = `['workspace', 'inspect', <cr>]`（`<cr>` 仅在规范 CR-ID 时占一位；非规范时省略该元素）；
   - `cwd` = 执行 `gate` 的工作区（绝对路径）；`requiresTTY` = `false`；`promptFor` = `[]` 或 `['CR-ID']`；
   - 错误码、消息文本与「分支在任何写路径之前、零写入」的结构不变（FR-13）。
4. **站点 11：`cmdReviewLoopReset` 提交失败分支（SDD §3.4 / §4.1 站点 11）**：
   - `args` = `['review-loop', 'reset', <cr>, '--loop', <loopRef>]`（`<cr>` 规则同站点 10）；
   - `cwd` = 执行 `reset` 的工作区；`requiresTTY` = `true`（与既有 `NOT_TTY` 前置校验一致，SDD §11 依赖项 2）；`promptFor` = `['reason']`（CR-ID 非规范时并含 `'CR-ID'`，顺序按 SDD §2.1「按序」）；
   - **`--reason` 的值不进 `args`、不进任何 shell string**；失败结果的原错误码（`REVIEW_LOOP_RESET_COMMIT_FAILED` 等）与 `rollback` 语义不变。
5. **注册投影（SDD §4.2 第 1 步）**：`buildRegisterResult` 只保留 `recovery`（其余字段逐字不动）；`cmdRegister` 输出对象从 `recoverCommand: r.recoverCommand, recover_command: r.recoverCommand` 改为 `recovery: r.recovery`——**删除双投影，其它 snake_case 镜像（`cr_id` / `tx_id` / `operational_workspace` …）不动**。
6. **其它 `ok({ op: '<x>', ...result })` 站点**：字段名自动由 producer 决定，无需改动，但必须核对 producer 侧改名已由 CR-2026-064-TASK-01 落地（`archive` / `checkpoint` / `merge` / `workspace-sync` / `writeback-apply` / `test`）。
7. **禁止在 CLI 层重新拼串**：不得出现字符串模板拼接恢复命令、不得引入 `shell: true` / `Invoke-Expression`（AC-04 守卫断言由 CR-2026-064-TASK-04 落盘）。

## 4. 验收条件

1. **注册单投影**：`crctl register …` 的成功结果包含顶层 `recovery`（形状同 CR-2026-064-TASK-01 §6 契约），且**不含** `recoverCommand` 与 `recover_command`；其余成功字段与改造前逐字一致。
2. **`gate` 错配双向量**：`crctl gate CR-2026-064 --for tech-design-review-pending --mode pre-review` 的 stderr JSON 满足 `error.code === 'BAD_ARGS'`、`error.recovery.executable === 'node'`、`error.recovery.args` 的元素（`args[0]` 之后）为 `['workspace', 'inspect', 'CR-2026-064']`、`error.recovery.promptFor` 为 `[]`；位置参数改为非规范形态（如 `CR-X`）时断言 `args`（`args[0]` 之后）为 `['workspace', 'inspect']` 且 `promptFor === ['CR-ID']`；两次调用均零写入、退出码非 0。
3. **`reset` 失败向量**：在既有故障注入下（提交失败），stderr JSON 的 `error.recovery` 满足 `requiresTTY === true`、`promptFor === ['reason']`、`args` 内不含 `--reason` 也不含任何 reason 文本；`cwd` 为绝对路径且与执行工作区同源；原错误码与 `rollback` 字段语义不变。
4. **占位符退场**：`crctl.mjs` 内不再存在 `crIdForRecover`，且运行期不再产出含 `<CR-ID>` 的字符串（`rg -n "<CR-ID>" skills/shared/crctl/scripts/crctl.mjs` 零命中）。
5. **无备用入口**：`crctl.mjs` 内 `recoverCommand` / `recover_command` 零命中；无 deprecated alias / fallback / 双写。
6. **回归**：`plan.md §6.2 cmd-01` 全量套件与 `cmd-02` 在本 TASK 后保持通过（`register-tx.test.mjs` 的**双投影既有用例**若因字段集变化必须同步，交 CR-2026-064-TASK-04 处理；本 TASK 不得改写测试文件）。
7. **范围**：`crctl git diff --name-only dddd0ad63fb79bd7608314b4553f30e8ce7b7289 --cwd <tools worktree>` 的本 TASK 增量路径集合 = {`skills/shared/crctl/scripts/crctl.mjs`}（相对 CR-2026-064-TASK-01 的增量）。

## 5. 完成标志

- 上述 §4 的 7 条全部实测通过，并留下可复核的命令与输出摘要（命令、cwd、exit、关键断言行）。
- `rg -n "recoverCommand|recover_command|crIdForRecover" skills/shared/crctl/scripts/crctl.mjs` **零命中**。
- 本 TASK 产生的改动由本 TASK 自行提交：`[cr] CR-2026-064 TASK-02 recovery CLI projection migration`（受控 `crctl git` 形态，`[cr] ` 前缀）。
- `crctl task done CR-2026-064-TASK-02 --workspace <KB worktree>` 登记完成（纪律 #8）。
- **不**在本 TASK 内改写 `sdd.md` / `prd.md`；**不**修改 CR-2026-064-TASK-01 的文件（`lib/workspace-transactions.mjs` 只读 import）。

## 6. 接口契约

**产出（供下游 TASK 消费，逐字对齐 SDD）**

| 符号 | 精确形态（SDD 落点） |
|---|---|
| 成功结果的顶层 `recovery` | `register`（以及经 `ok({ op, ...result })` 透传的 archive / checkpoint / merge / workspace-sync / writeback-apply / test）的 `recovery` 即 CR-2026-064-TASK-01 构造器产出对象，**单投影、无同义字段**（SDD §3.3 站点表 + §4.2 第 1–2 步） |
| `error.recovery`（`gate` 错配） | `{ executable: 'node', args: [<crctl.mjs 绝对路径>, 'workspace', 'inspect', <cr>?], cwd: <执行 gate 的工作区>, requiresTTY: false, promptFor: [] \| ['CR-ID'] }`，随 `BAD_ARGS` 落在 `error.recovery`（SDD §4.1 站点 10） |
| `error.recovery`（`reset` 提交失败） | `{ executable: 'node', args: [<crctl.mjs 绝对路径>, 'review-loop', 'reset', <cr>?, '--loop', <loopRef>], cwd: <执行 reset 的工作区>, requiresTTY: true, promptFor: ['reason'] (+ 'CR-ID' 非规范时) }`（SDD §4.1 站点 11） |
| 规范 CR-ID 判定 | 单一定义：`^CR-\d{4}-\d{3,}$`；命中 ⇒ 独立 argv 元素；否则 ⇒ 省略该元素 + `promptFor` 含 `'CR-ID'`（SDD §4.1 站点 10/11 共用判定、D-4） |

**消费（上游产出与既有实现）**

- `buildRecovery(args, { cwd, requiresTTY, promptFor })`：由 CR-2026-064-TASK-01 在 `lib/workspace-transactions.mjs` 导出；本 TASK 只调用，不复制实现、不改其形状。
- 既有 `fail(code, message, extra)` / `ok(obj)` 输出信封（错误 `{ error: {...} }` → stderr + exit 1；成功对象 → stdout）：只改 `extra` 内的字段名，信封形态逐字不变（SDD §11 依赖项 2）。
- 既有 `NOT_TTY` 前置校验：`requiresTTY: true` 的事实依据；本 TASK 不改其行为（FR-13）。
