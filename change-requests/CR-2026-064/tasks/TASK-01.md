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
created: 2026-09-13T22:15:00+08:00
---

# CR-2026-064-TASK-01 —— 生产者迁移与唯一构造器 `buildRecovery`

覆盖 FR：**FR-1、FR-2、FR-3、FR-5、FR-10（生产者侧）、FR-13、FR-15、FR-17（构造面）**（SDD §2.1/§3.2/§4.1/§9）；变更组 **G1**；主责仓：`tools`。

## 1. 任务描述

**目标**：在 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 内新增**唯一**构造器 `buildRecovery`，并把 9 类可恢复场景的 **9 个生产者站点**（register、workspace sync、merge 成功/`release-drift`、merge publication lag、checkpoint、writeback traceability replay、writeback apply 主路径、archive、test）在原位改为返回结构化 `recovery`；**同一位置删除旧字段**，不并排双写、不留 fallback。（SDD §4.1 表的另两处站点 10/11 位于 `crctl.mjs`，属 CR-2026-064-TASK-02。）

**背景**：当前恢复动作以 shell 命令字符串承载（`recoverCommand`），把「机器执行入口 / 参数边界 / 人类显示文本」混在一个字符串里，用户可控输入（reason、路径、ref）可改变执行语义（PRD §1.1 四类缺陷）。SDD 决定改为唯一结构化数据字段 `recovery`，并由单一构造器保证形状与键序（D-2/D-3）。

**输入条件**：tools CR worktree（`execution_context.resources[tools].worktreePath`，分支 `requirement/CR-2026-064`，HEAD `81d31b8b9d4c36cfef24cd076bf9fe635b67b2b6`）；SDD `6c5c9a11`（sha256 `d9f727b6…`，审批绑定 `2d637724…`）与 PRD `4df6f159…` 只读；`crctl workspace freshness CR-2026-064`（gate=implement-start）通过。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 唯一改动文件：新增 `buildRecovery`（约 12 行）+ 站点 1–9 原位结构化 + `mergeCr` 内局部名 `checkpointRecoverCommand` 归位 |

**不得触碰**（SDD §9 `zero_diff`）：`skills/shared/crctl/scripts/crctl.mjs`（属 CR-2026-064-TASK-02）、`skills/shared/crctl/scripts/test/**`（属 CR-2026-064-TASK-04）、`README.md` / `openwiki/**` / 4 份消费方 SKILL（属 CR-2026-064-TASK-03）、`ARCHITECTURE.md`、`dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json`、`pipeline-templates/**`、`.github/workflows/**`、`agents/*.md`、`skills/shared/crctl/scripts/test/gate-registry.json`、`lib/durable-tx.mjs`、`lib/yaml-subset.mjs`。

## 3. 实现要点

实施定位一律以实时 `rg "recoverCommand|recover_command"` 为准（SDD §4.3 的行号是 `tools@dddd0ad6` 上的参考位置，**禁止按行号盲改**）。

1. **构造器与入口常量**（SDD §3.2 逐字）：`CRCTL_SCRIPT_PATH` 由模块位置解析（`path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'crctl.mjs')`），`buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] } = {})` 返回固定键序 `executable` → `args` → `cwd`（存在时）→ `requiresTTY` → `promptFor`；`executable` 恒为字面量 `'node'`；四条入参守卫抛 `TxError('RECOVERY_CONTRACT_INVALID', …)`（内部不变量守卫，不进 §3.5 消费者错误闭包，不改既有错误码/退出码）。
2. **六步原位改写**（SDD §4.1）：拆 token（`--flag` 与值各占一个元素，`JSON.stringify(...)` 包裹的插值改为裸值元素，不得残留引号）→ 保顺序（与目标 CLI 参数顺序逐字一致，含 `--workspace` 位置）→ 保条件（「有才拼」的可选参数保持同一条件，三元展开成 `...(cond ? [a, b] : [])`）→ 定 `cwd`（原串内插的 workspace 路径同源作 `cwd`，绝对路径；`gate`/`reset` 无 workspace 参数，取执行时工作区）→ 提 `promptFor`（`plan` 从 `args` 移除并声明）→ 删旧字段（**同一位置**改为 `recovery: buildRecovery(...)` 或 `extra.recovery`；错误消息文本中引用旧字段名的措辞同步改为「先执行 `recovery` 指向的 checkpoint 再重跑 merge」）。
3. **站点 1–9 的 `args` 取值**逐条按 SDD §4.1 表（`args[0]` 由构造器注入）：`register`（7 个具名 flag + 4 个条件参数）、`workspace sync <cr> --workspace <installRoot>`、`merge <cr> --workspace <ws>`、`checkpoint <cr> --workspace <installRoot>`（publication lag）、`checkpoint <cr> (--message <m>)? --workspace <ws>`、`writeback-apply <cr> --stage traceability --spec-id <id> --target-version <v> (--milestone-file <f>)? --workspace <ws>`、`writeback-apply <cr> --stage <stage> --spec-id <id> --target-version <v> (--milestone-name <n>)? (--brief <b>)? (--milestone-file <f>)? --workspace <ws>`、`archive <cr> (--spec-id <id>)? --workspace <ws>`、`test <cr> --workspace <worktree>`（`promptFor: ['plan']`）。
4. **`cwd` 与 `--workspace` 同源**：同一变量取两次，不各自计算（SDD §10「`cwd`」行）；`input.workspace || ctx.installRoot` 的取值逻辑保持原样，只把结果同时用于 `args` 元素与 `cwd`。
5. **局部名归位**：`mergeCr` 内的 `checkpointRecoverCommand` 改写为新合同口径名（`checkpointRecovery`），站点 4 的两个 `TxError` 的 `extra.recovery` 仍取该局部值（值类型由 shell string 变为 `buildRecovery(...)` 结果）。该局部名不属退役名（大小写敏感的退役名扫描对它零命中），但 SDD §11-1 明示「随站点 4 结构化一并改写名称」。
6. **`buildTestResponse` 增参**：入参加 `workspace`（= `testCr` 的 `workspace` 入参，即 authority workspace），作为 `args` 的 `--workspace` 值与 `cwd`；`testCr` 的 5 个调用点同步传入。
7. **不落盘**（SDD §2.2）：`recovery` 只出现在返回值与 `TxError.extra`；`.crctl/transactions/**` journal payload 字段集零变更；不新增任何持久化写入。

## 4. 验收条件

1. 旧名字符串在本文件零命中（区分大小写，退役名口径）：
   ```bash
   rg -n "recoverCommand|recover_command" skills/shared/crctl/scripts/lib/workspace-transactions.mjs   # 期望：零命中
   rg -n "checkpointRecoverCommand" skills/shared/crctl/scripts/lib/workspace-transactions.mjs          # 期望：零命中
   ```
2. 文件语法可解析：`node --check skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（退出码 0）。
3. `buildRecovery` 的契约逐条成立：单一导出定义（1 处 `export function buildRecovery`）、返回对象键序固定、`executable === 'node'`、`args[0] === CRCTL_SCRIPT_PATH`、`cwd` 省略时对象不含该键、四条守卫抛 `RECOVERY_CONTRACT_INVALID`（由 CR-2026-064-TASK-04 的结构断言与边界向量最终证明）。
4. 9 类场景全部经构造器构造：`rg -c "buildRecovery\(" skills/shared/crctl/scripts/lib/workspace-transactions.mjs` ≥ 10（1 处定义 + 站点 1–9 的调用；站点 10/11 在 `crctl.mjs`，不属本 TASK）。
5. 条件参数未丢：站点 1、5、6、7、8 的可选 flag 仍按原条件出现（逐条对照 SDD §4.1 表括号内的 `(…)?` 项），且 `args` 中不存在任何占位符串（`<cr>` / `{TOOLS_ROOT}` / `<worktree>` 等）。

## 5. 完成标志

- 上列五条验收条件全部通过，且 **本 TASK 触达文件**（`lib/workspace-transactions.mjs`）旧名零命中。
- 9 个站点逐条对照 SDD §4.1 表核对完成（可选参数条件、元素顺序、`cwd` 来源、`promptFor` 三处）。
- 未引入任何 alias / shim / fallback，未并排双写旧字段（同位置替换）。
- 未触碰 §2 的「不得触碰」清单（`git status --porcelain` 只列本文件）。
- 最终机器证据归 CR-2026-064-TASK-04：`cmd-01`（`suite-gate.mjs --run`，含 `merge-tx.test.mjs` / `archive-tx.test.mjs` / `checkpoint-tx.test.mjs` / `workspace-freshness.test.mjs` / `writeback-tx.test.mjs` / `register-tx.test.mjs` / `crctl.test.mjs` 的结构断言）与 `cmd-03`（整树零命中）由 CR-2026-064-TASK-04 迁移测试后统一给出。
- `tasks/_index.yml` 中本 TASK 标记 `done`（做完即标，不积压到回写期）。

## 6. 接口契约

**产出（供下游 TASK 消费，逐字对齐 SDD §3.1/§3.2）**

```js
// skills/shared/crctl/scripts/lib/workspace-transactions.mjs（ESM）
const CRCTL_SCRIPT_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'crctl.mjs');

export function buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] } = {}) {
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

```ts
interface Recovery {
  executable: string;    // 本 CR 恒为 'node'
  args: string[];        // args[0] = <toolsRoot>/skills/shared/crctl/scripts/crctl.mjs 绝对路径
  cwd?: string;          // 绝对路径；本 CR 全部生产者均提供
  requiresTTY: boolean;
  promptFor: string[];   // 逻辑值名，按序；对应 argv 元素不出现在 args
}
```

**消费（上游既有实现，只读复用；SDD §11 依赖项 1/3/4）**

- `lib/durable-tx.mjs` 的 `TxError(code, message, extra)`：`extra` 是错误面恢复数据的唯一传递通道；`recovery` 必须放在 `extra.recovery`，不新增通道、不改 `code`/`message` 语义。
- `lib/workspace-transactions.mjs` 既有 `parseTestPlan` / `runTestPlan` 的 argv 执行先例（`cmd.executable` + `cmd.args` + `spawnSync(..., { shell: false })`，`cr-test-plan/v1`）：`buildRecovery` 沿用同一形态与命名，属仓内既有先例。
- 上游 CR-2026-064-TASK-02 消费的**唯一**生产者输出面：`recovery` 对象（键序固定）+ `extra.recovery`；CR-2026-064-TASK-02 不得在 CLI 层重新拼接任何 shell string，也不得再引入第二个同义字段。
