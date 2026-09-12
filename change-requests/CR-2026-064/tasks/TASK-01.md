---
id: CR-2026-064-TASK-01
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "生产者迁移：唯一构造器 buildRecovery 与 9 类场景 9 个生产者站点原位改为结构化 recovery"
slug: recovery-producer-migration-build-recovery
status: pending
estimate: 16h
depends-on: []
created: 2026-09-13T00:20:00+08:00
---

# CR-2026-064-TASK-01 —— 生产者迁移与唯一构造器 `buildRecovery`

覆盖 FR：**FR-1、FR-2、FR-3、FR-5、FR-10（代码侧）、FR-13、FR-15、FR-17（构造面）**（SDD §2.1/§3.2/§4.1/§9）；变更组 G1；主责仓：`tools`。

## 1. 任务描述

**目标**：在 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 内新增**唯一**构造器 `buildRecovery`，并把 9 类可恢复场景的 **9 个生产者站点**（register、workspace sync、merge 成功/`release-drift`、merge publication lag、checkpoint、writeback traceability replay、writeback apply 主路径、archive、test）在原位改为返回结构化 `recovery`；同一位置删除旧字段，不并排双写、不留 fallback。（SDD §4.1 表另外两处站点 10/11 位于 `crctl.mjs`，属 CR-2026-064-TASK-02。）

**背景**：当前恢复动作以 shell 命令字符串承载（`recoverCommand`），把「机器执行入口 / 参数边界 / 人类显示文本」混在一个字符串里，用户可控输入（reason、路径、ref）可改变执行语义（PRD §1.1 四类缺陷）。SDD 决定改为唯一结构化数据字段 `recovery`，并由单一构造器保证形状与键序。

**输入条件**：tools CR worktree（`resources[].worktreePath`，分支 `requirement/CR-2026-064`，HEAD `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`）；`crctl workspace freshness CR-2026-064`（gate=implement-start）通过；SDD `a5101d59`（审批绑定 `824cf303…`）与 PRD `4df6f159…` 只读。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | **唯一改动文件**：新增 `CRCTL_SCRIPT_PATH` 常量与导出函数 `buildRecovery`（约 12 行 + 4 条不变量守卫）；`registerCr` / `syncWorkspaceToTrunk` / `mergeCr` / `checkpointCr` / `applyWritebackAtomic` / `archiveCr` / `buildTestResponse` / `testCr` 的 11 个站点原位改为结构化 `recovery`；站点 4 局部名改写 |

**不得触碰**（SDD §9 `zero_diff`）：`skills/shared/crctl/scripts/crctl.mjs`（属 CR-2026-064-TASK-02）、`skills/shared/crctl/scripts/test/**`（属 CR-2026-064-TASK-04）、`README.md` / `openwiki/**` / 4 份消费方 SKILL（属 CR-2026-064-TASK-03）、`ARCHITECTURE.md`、`dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json`、`pipeline-templates/**`、`.github/workflows/**`、`agents/*.md`、`lib/durable-tx.mjs`、`lib/yaml-subset.mjs`。

## 3. 实现要点

1. **构造器（SDD §3.2，逐字落实）**：模块作用域新增

```js
const CRCTL_SCRIPT_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'crctl.mjs');

export function buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] } = {}) {
  // 内部不变量守卫：仅由程序员错误触发，任何合法输入不可达（不改变既有 CLI 合同）
  if (!Array.isArray(args) || args.some((a) => typeof a !== 'string')) throw new TxError('RECOVERY_CONTRACT_INVALID', 'recovery.args 必须是字符串数组');
  if (cwd != null && !path.isAbsolute(cwd)) throw new TxError('RECOVERY_CONTRACT_INVALID', `recovery.cwd 必须是绝对路径: ${cwd}`);
  if (typeof requiresTTY !== 'boolean') throw new TxError('RECOVERY_CONTRACT_INVALID', 'recovery.requiresTTY 必须是 boolean');
  if (!Array.isArray(promptFor) || promptFor.some((v) => typeof v !== 'string')) throw new TxError('RECOVERY_CONTRACT_INVALID', 'recovery.promptFor 必须是字符串数组');
  return {
    executable: 'node',
    args: [CRCTL_SCRIPT_PATH, ...args],
    ...(cwd == null ? {} : { cwd }),
    requiresTTY,
    promptFor,
  };
}
```

   - 键序固定 `executable → args → cwd（存在时）→ requiresTTY → promptFor`（FR-17 指纹与断言稳定性，SDD §2.1 末段）；
   - `executable` 恒为字面量 `'node'`；`args[0]` 恒为脚本绝对路径（FR-3 node 规则）；**不得**使用 `process.execPath`、时间戳、随机数、进程 id 或环境变量（SDD §2.4）；
   - `RECOVERY_CONTRACT_INVALID` 是**内部不变量守卫**，不是消费者可见的第五类错误，不新增对外错误码语义；
   - 构造器落在本文件（D-3，不新建 `lib/recovery.mjs`）；CLI 由 `crctl.mjs` 向下 `import`，lib 不反向依赖 CLI。

2. **六步原位改写（SDD §4.1）**：拆 token → 保顺序 → 保条件（`...(cond ? [a, b] : [])`）→ 定 `cwd`（与原串内插的 workspace 同源，同一变量取两次，不各自计算）→ 提 `promptFor` → 删旧字段（同一位置改为 `recovery: buildRecovery(...)` 或 `extra.recovery`）。**禁止按行号盲改**：定位一律以实时 `rg "recoverCommand|recover_command"` 为准（SDD §4.3 表头口径）。

3. **本 TASK 覆盖的 9 个生产者站点的 `args` 取值（SDD §4.1 表 1–9 行，逐字；`args[0]` 由构造器注入）**：

| # | 场景 | `args`（`args[0]` 之后） | `cwd` | `requiresTTY` | `promptFor` |
|---|---|---|---|---|---|
| 1 | `registerCr` | `register --registration-key <k> --title <t> --owner-requirement <r> --owner-development <d> --owner-test <e> (--summary <s>)? (--source <s>)? (--origin <o>)? (--target-version <v>)? --target-spec-id <id> --workspace <ws>` | `<ws>` = `input.workspace \|\| ctx.installRoot` | `false` | `[]` |
| 2 | `workspace sync` | `workspace sync <cr> --workspace <installRoot>` | `<installRoot>` | `false` | `[]` |
| 3 | `mergeCr`（成功 / `release-drift`） | `merge <cr> --workspace <ws>` | `<ws>` = `input.workspace \|\| ctx.installRoot` | `false` | `[]` |
| 4 | merge publication lag | `checkpoint <cr> --workspace <installRoot>` | `<installRoot>` | `false` | `[]` |
| 5 | `checkpointCr` | `checkpoint <cr> (--message <m>)? --workspace <ws>` | `<ws>` = `workspace \|\| ctx.installRoot` | `false` | `[]` |
| 6 | writeback traceability replay | `writeback-apply <cr> --stage traceability --spec-id <id> --target-version <v> (--milestone-file <f>)? --workspace <ws>` | `<ws>` | `false` | `[]` |
| 7 | writeback apply（主路径） | `writeback-apply <cr> --stage <stage> --spec-id <id> --target-version <v> (--milestone-name <n>)? (--brief <b>)? (--milestone-file <f>)? --workspace <ws>` | `<ws>` | `false` | `[]` |
| 8 | `archiveCr` | `archive <cr> (--spec-id <id>)? --workspace <ws>` | `<ws>` | `false` | `[]` |
| 9 | `testCr` | `test <cr> --workspace <worktree>`（`--plan` 走 `promptFor`） | `<worktree>`（`testCr` 的 `workspace` 入参，即 authority workspace） | `false` | `['plan']` |

   - 站点 1 的可选参数按原串条件展开（`--summary` / `--source` / `--origin` / `--target-version` 各自独立条件），不得丢条件、不得新增条件；
   - 站点 5 `mergeCr` 的 `release-drift` 分支沿用同一 `recovery` 构造（等价迁移，方向修正留给后续 CR——SDD §9 `follow_up`）；
   - 站点 6/7 的 `--stage traceability` 的 `--target-version` 为空串时仍作为合法 string 元素保留（SDD §7.3，交由目标 CLI 既有校验判定）；
   - 站点 9 的 `--plan` 值**不进 `args`**，只进 `promptFor`（原模板串中的 `{TOOLS_ROOT}` / `<plan>` / `<worktree>` 占位符一并消失：`{TOOLS_ROOT}` 由构造器的脚本绝对路径承担，`<worktree>` 变为真实 workspace 值）。

4. **站点 4 局部名归位（SDD §11 依赖项 1）**：`mergeCr` 内的局部名 `checkpointRecoverCommand`（声明与两处取值同址）随结构化一并改写为新合同口径名 `checkpointRecovery`；两处 `TxError` 的 `extra.recoverCommand` 改为 `extra.recovery`，其值由该局部变量（现为 `buildRecovery(...)` 产出的结构化对象）承担。改写后旧局部名在本仓零命中。

5. **消息文本口径（SDD §4.1 第 6 步）**：错误消息中引用旧字段名的措辞（如「先执行 recoverCommand 再重跑 merge」）同步改为「先执行 `recovery` 指向的 checkpoint 再重跑 merge」；消息文本、错误码、退出码、`txId`、`rollback`/`files` 语义**不得**发生其它变化（FR-13）。

## 4. 验收条件

1. **AC-01 形状**：对 8 类恢复路径（register / workspace sync / merge / merge publication lag / checkpoint / writeback replay / writeback apply / archive / test 中本 TASK 覆盖的生产者侧）逐个触发可恢复场景，返回的 `recovery` 恒为 `executable === 'node'`、`args` 为 string 数组且 `args[0]` 为 `crctl.mjs` 绝对路径、`cwd` 为绝对路径且与该站点 `--workspace` 值同源、`requiresTTY` 为 boolean、`promptFor` 为 string 数组；对象键序恒为 `executable, args, cwd, requiresTTY, promptFor`。
2. **AC-01 无备用入口**：`lib/workspace-transactions.mjs` 内不再出现 `recoverCommand` / `recover_command`，也不存在与 `recovery` 等价的 shell 命令字符串（逐站点人工核对 + `plan.md §6.2 cmd-03` 的整树零命中）。
3. **FR-10 原位删除**：同一位置无并排双写、无「若无 `recovery` 则读 `recoverCommand`」形式 fallback、无 deprecated alias、无 migration shim。
4. **站点 4 归位**：`mergeCr` 内两处 `TxError` 的 `extra.recovery` 取改名为 `checkpointRecovery` 的局部值；`rg -n --case-sensitive "checkpointRecoverCommand"` 在 tools CR worktree **零命中**；站点 4 的 `args` 为 `['checkpoint', <cr>, '--workspace', <installRoot>]`（`args[0]` 之后）。
5. **构造器不变量**：`buildRecovery` 对非法入参（`args` 非 string 数组 / `cwd` 非绝对路径 / `requiresTTY` 非 boolean / `promptFor` 非 string 数组）抛 `RECOVERY_CONTRACT_INVALID`；对合法入参零副作用（纯数据、不执行命令、不渲染字符串、不写文件）。
6. **零语义漂移**：本 TASK 改动后 `plan.md §6.2 cmd-01` 全量套件（21 个 `*.test.mjs`）与 `cmd-02`（writeback 单文件）保持通过（结构断言的迁移属 CR-2026-064-TASK-04；本 TASK 只保证既有事务行为与错误码不回归；若因字段改名导致**既有断言**必须同步，交 CR-2026-064-TASK-04 处理，本 TASK 不得改写测试文件）。
7. **范围**：`crctl git diff --name-only dddd0ad63fb79bd7608314b4553f30e8ce7b7289 --cwd <tools worktree>` 的路径集合 ⊆ {`skills/shared/crctl/scripts/lib/workspace-transactions.mjs`}（本 TASK 单文件）。

## 5. 完成标志

- 上述 §4 的 7 条全部实测通过，并留下可复核的命令与输出摘要（命令、cwd、exit、关键断言行）。
- `rg -n "recoverCommand|recover_command" skills/shared/crctl/scripts/lib/workspace-transactions.mjs` **零命中**。
- 本 TASK 产生的文件（含构造器与 11 站点改写）由本 TASK 自行提交：`[cr] CR-2026-064 TASK-01 recovery producer migration`（受控 `crctl git` 形态，`[cr] ` 前缀）。
- `crctl task done CR-2026-064-TASK-01 --workspace <KB worktree>` 登记完成（纪律 #8：做完一个标一个，不积压到回写期）。
- **不**在本 TASK 内改写 `sdd.md` / `prd.md`；**不**修改其它 TASK 的文件（尤其是 `crctl.mjs`、测试文件、文档与提示词）。

## 6. 接口契约

**产出（供下游 TASK 消费，逐字对齐 SDD）**

| 符号 | 精确形态（SDD 落点） |
|---|---|
| `buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] } = {})` | `workspace-transactions.mjs` 的**导出函数**；返回 `{ executable: 'node', args: [CRCTL_SCRIPT_PATH, ...args], ...(cwd == null ? {} : { cwd }), requiresTTY, promptFor }`，键序固定；非法入参抛 `new TxError('RECOVERY_CONTRACT_INVALID', <消息>)`（SDD §3.2）。**消费方：CR-2026-064-TASK-02 的 `cmdGate` 与 `cmdReviewLoopReset`**，以及本 TASK 自身的 11 个站点 |
| `recovery`（生产者返回值字段） | 顶层 `recovery`（成功结果）或 `TxError.extra.recovery`（错误面）；字段集与取值见 §3 第 3 条的 11 行表；不含任何等价 shell string（SDD §3.3） |
| `checkpointRecovery`（局部名） | `mergeCr` 内 `buildRecovery(['checkpoint', <cr>, '--workspace', <installRoot>], { cwd: <installRoot> })` 的求值结果，供两处 `TxError` 的 `extra.recovery` 取用（SDD §11 依赖项 1） |

**消费（上游既有实现，只读复用，SDD §11 依赖项 3/4）**

- `TxError`（`lib/durable-tx.mjs`）：`code` / `message` / `extra` 三字段载体；`extra` 是错误面恢复数据的唯一传递通道。不新增错误码语义（`RECOVERY_CONTRACT_INVALID` 只走既有 `INTERNAL_ERROR` 链路暴露）。
- 既有 argv 先例：`parseTestPlan` / `runTestPlan`（同文件）以 `cmd.executable` + `cmd.args` + `spawnSync(..., { shell: false })` 执行外部命令——`recovery` 沿用同一形态与命名（D-1、SDD §10）。
- 既有内部恢复原语（`recoverWriteSet` / `recoverLedgerTransaction` / `recoverLedgerCommand`）**不改名、不合并**（SDD §2.3 / §10）。
