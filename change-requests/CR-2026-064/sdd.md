---
id: CR-2026-064-sdd
type: SDD
cr-ref: CR-2026-064
title: CR-R：结构化恢复合同原子迁移 — `recoverCommand`/`recover_command` 全量退役为结构化 `recovery` 技术设计
target-version: 0.37
status: draft
created: "2026-09-12T22:48:00+08:00"
updated: "2026-09-12T22:48:00+08:00"
---

# CR-R：结构化恢复合同原子迁移 — 技术设计

> 输入：`change-requests/CR-2026-064/prd.md`（5 US / 17 FR / 14 AC，评审 PASS + 人工审批）。
> 本文只设计「把恢复动作从命令字符串改为结构化 `recovery`」的落点与算法；不改任何既有错误码语义、状态转换、事务边界与业务算法。

## 1. 架构概览

### 1.1 变更边界

| 仓 | 路径 | 变更性质 |
|---|---|---|
| `tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 生产者：9 类可恢复场景原位改为结构化 `recovery`；新增唯一构造器 `buildRecovery` |
| `tools` | `skills/shared/crctl/scripts/crctl.mjs` | 投影层：删除 `recoverCommand`/`recover_command` 双投影，2 处错误恢复改为结构化，注册结果单投影 |
| `tools` | `skills/shared/crctl/scripts/test/*.test.mjs` | 7 个既有测试文件由字符串包含断言改为结构与 argv 断言；`contract-scan.test.mjs` 扩展退役名单与活跃范围 |
| `tools` | `skills/shared/crctl/SKILL.md`、`skills/cr/cr-archive/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/writeback/merge-feature-branch/SKILL.md` | 消费方提示词：改读 `recovery.executable/args/cwd/requiresTTY/promptFor` |
| `tools` | `README.md`、`openwiki/operations/crctl-transactions.md` | 文档单一事实源改为结构化合同（旧合同描述删除，不新增第二套描述） |
| `multica` | `cr-prompts-revised/delivery-agent.md` | 交付 Agent 提示词的 owner 可复制版本改读结构化结果（本 CR 不更新平台 DB） |
| 知识库 | `change-requests/CR-2026-064/sdd.md` + 后续 PLAN/TASK | 本 CR 产物 |

**不在本 CR 变更范围**：`tools/ARCHITECTURE.md`（已存在，只读引用；本 CR 不触发其 §8 修订条件）、`dir-graph.yaml`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、`pipeline-templates/**`（无旧字段引用，仅纳入退役扫描的活跃范围）、`tools/agents/*.md`（无旧字段引用）、Multica 服务端与 importer。

### 1.2 依赖方向（分层不变）

```
消费方：Skill 提示词 / Agent 提示词 / 平台 Prompt
        │  读取结构化 recovery（prompt 合同，非代码依赖；见 §3.5）
        ▼
crctl CLI：skills/shared/crctl/scripts/crctl.mjs      ← 唯一命令入口与投影层
        │  import（只朝下）
        ▼
lib/workspace-transactions.mjs   ← 生产者 + 唯一构造器 buildRecovery
        │
        ▼
lib/durable-tx.mjs（TxError/journal）、lib/yaml-subset.mjs
```

- `buildRecovery` 落在 **lib**（`workspace-transactions.mjs`）并由 CLI 向下 import；lib 不反向依赖 CLI（`tools/ARCHITECTURE.md` §4 规则、§5 不变量 2 保持）。
- 不新增命令、不新增状态/转换、不新增 Pipeline 节点、不新增账本写入通道；`.crctl/transactions/**` journal schema 不变（§2.2）。

### 1.3 关键流程

1. **生产者构造**：任一可恢复场景（失败或可恢复中间态）由 `buildRecovery(args, { cwd, requiresTTY, promptFor })` 一次性构造出唯一 `recovery` 对象，直接作为返回值字段或 `TxError.extra.recovery`。
2. **CLI 投影**：成功结果把它放在**顶层** `recovery`；错误路径经 `fail(code, message, extra)` 落在 `error.recovery`；不再存在第二个同义字段。
3. **消费方判定**：消费方（Agent / Skill）按 §3.5 的固定 5 步顺序校验，全部满足才以非 shell 的 argv 方式执行；首个不满足即停止并报告合同错误，零执行副作用。

## 2. 数据模型

### 2.1 核心实体：`recovery`

| 字段 | 类型 | 必填 | 规则 | 取值来源 |
|---|---|---|---|---|
| `executable` | string | ✅ | 非空；不含空格分隔参数、管道 `\|`、重定向 `>` `<`、分隔符 `;`、连接符 `&&`、命令替换 `$()`、反引号或任何 shell 展开 | 本 CR 全部生产者恒为字面量 `node`（决策 D-1） |
| `args` | string[] | ✅ | 每元素是**一个完整 argv**；不把多参数拼成单元素；顺序与目标 CLI 参数顺序一致；含空格路径不加引号即可传递 | `args[0]` = `crctl.mjs` 绝对路径（FR-3 node 规则）；其后为原命令 token |
| `cwd` | string（绝对路径） | 可选（本 CR 全量提供） | 仅当恢复动作必须位于特定 workspace 时返回；不得依赖调用方猜测 | 与该恢复动作的 `--workspace` 值同源（`gate`/`reset` 无 `--workspace` flag，取执行该命令时的工作区） |
| `requiresTTY` | boolean | ✅ | 是否必须在可信交互终端执行 | `review-loop reset` 为 `true`（CLI 自身非 TTY 一律 `NOT_TTY` 拒绝，证据见 §11-2）；其余 `false` |
| `promptFor` | string[] | ✅ | 执行时需重新获取的逻辑值名（按序）；这些值**不得**预先出现在 `args[]` 或任何 shell string 中 | 见 §3.4 三处 |

键序固定为 `executable` → `args` → `cwd`（存在时）→ `requiresTTY` → `promptFor`（构造器保序，FR-17 指纹与断言稳定性）。

### 2.2 存储方案：不落盘

`recovery` 是**响应期数据**，仅存在于命令响应与 `TxError.extra` 两类载体中：

- **不入 journal**：`.crctl/transactions/{op}/{key}/{txId}/journal.json` 的 payload 字段集零变更（现有 producer 站点没有任何把恢复数据写入 journal 的代码路径，见 §11-3）；
- **不入账本**：`cr.md` / `_backlog.yml` / `_history.yml` / `_index.yml` / `approval.yml` / `review-annotations/*` / `traceability.yml` 零字段变更；
- **不入 Git 产物**：`specs/`、`delivery/`、`merge-commits.yml`、`test-report.md` 等不受影响。

因此本 CR **无数据迁移、无 schema 兼容窗口、无部分状态语义**（PRD 的 schema/写路径鉴权条件未触发）。

### 2.3 命名与别名

| 名称 | 状态 | 处置 |
|---|---|---|
| `recovery` | 唯一活跃名（PRD canonical term） | 全部生产者/投影/消费方统一使用 |
| `recoverCommand` | 退役 | 本 CR 内删除，禁止 alias/shim/fallback |
| `recover_command` | 退役 | 同上（仅注册结果曾双投影） |

命名冲突记录（Step 2.5）：模块内既有 `recoverWriteSet` / `recoverLedgerTransaction` / `recoverLedgerCommand` 是**事务层内部恢复原语**，与响应字段 `recovery` 不同层、不同名空间，本 CR 不改名、不合并（§10）。
保留的其它 snake_case 镜像（`cr_id` / `tx_id` / `operational_workspace` …）**不在本 CR 变更范围**（`zero_diff`，§9）。

### 2.4 幂等指纹字段集（FR-17）

指纹参与字段固定为：`executable` + `args[]`（有序）+ `cwd`（省略时不参与）+ `requiresTTY` + `promptFor[]`（有序）。构造器全部入参来自确定性事实（CR-ID、绝对路径、传入的业务参数、消息文本），**不含**时间戳、随机数、进程 id、`process.execPath`、环境变量或平台相关可变成分（决策 D-1）。重复求值逐元素相等；重复消费不改变其值，也不改变原事务的幂等结论。

## 3. 接口契约

### 3.1 类型

```ts
interface Recovery {
  executable: string;    // 本 CR 恒为 'node'
  args: string[];        // args[0] = <toolsRoot>/skills/shared/crctl/scripts/crctl.mjs 绝对路径
  cwd?: string;          // 绝对路径；本 CR 全部生产者均提供
  requiresTTY: boolean;
  promptFor: string[];   // 逻辑值名，按序；对应 argv 元素不出现在 args
}
```

### 3.2 唯一构造器

```js
// skills/shared/crctl/scripts/lib/workspace-transactions.mjs
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

契约保证（AC-01/AC-10/AC-11 的生产者侧落点）：

1. `executable` 由构造器恒定，FR-3 的安全约束按构造成立；
2. node 入口的脚本路径恒为 `args[0]`（FR-3 后半、AC-10）；
3. `args` 恒为字符串数组、`cwd` 恒为绝对路径；
4. `requiresTTY` / `promptFor` 由调用点显式声明，`false`/`[]` 也必须显式传入（形状统一，便于结构断言）；
5. 键序固定（§2.1），供 FR-17 指纹与测试断言使用。

`RECOVERY_CONTRACT_INVALID` 是**内部不变量守卫**，不属于消费者可见的四类错误闭包（§3.5），只在未来生产者改错时以 `INTERNAL_ERROR` 链路暴露，不改变任何既有错误码/退出码。

### 3.3 命令面投影

| 命令 / 场景 | 现载体 | 新载体 | 站点 |
|---|---|---|---|
| `register` | 成功结果 `recoverCommand` **且** `recover_command`（双投影） | 成功结果 `recovery`（单投影） | `crctl.mjs#buildRegisterResult` + `cmdRegister` 输出对象 |
| `workspace sync` | 成功结果 `recoverCommand` | 成功结果 `recovery` | `syncWorkspaceToTrunk` 三条 return |
| `merge` | 成功结果 / `phase=release-drift` 结果 `recoverCommand` | 同名位置 → `recovery` | `mergeCr` 三条 return |
| `merge` publication lag（`MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED`） | `error.recoverCommand`（指向 `checkpoint`） | `error.recovery` | `mergeCr` 两个 TxError 的 `extra` |
| `checkpoint` | 成功结果 + 错误 `error.recoverCommand` | 同名位置 → `recovery` | `checkpointCr` 三条 return + catch 包装 |
| `writeback-apply` | 成功结果 `recoverCommand`（主路径 + traceability replay 两条构造） | 同名位置 → `recovery` | `applyWritebackAtomic` replay 两条 return + 主 literal + 主 return |
| `archive` | 成功/待清理/幂等固定返回 `recoverCommand` | 固定返回 `recovery` | `archiveCr` literal + `result()` 闭包 |
| `test` | 成功结果 `recoverCommand`（含 `{TOOLS_ROOT}` / `<plan>` / `<worktree>` 占位符的模板串） | 成功结果 `recovery`（结构化，`plan` 走 `promptFor`） | `buildTestResponse` + `testCr` 5 个调用点 |
| `review-loop reset`（提交失败） | `error.recoverCommand` | `error.recovery` | `crctl.mjs#cmdReviewLoopReset` |
| `gate --mode pre-review` 错配 | `error.recoverCommand` | `error.recovery` | `crctl.mjs#cmdGate` |

成功结果的其它字段与错误码、`exit code`、`txId`、`rollback`/`files` 语义一律不变（FR-13）。

### 3.4 `promptFor` 解析约定

`promptFor` 的元素是**逻辑值名**；消费方须按该值名对应到目标 CLI 的既有入口取新值，且**不得**从旧错误消息、评论或日志中复用旧值：

| 值名 | 场景 | 目标 CLI 入口 | 是否从 `args` 省略 | 若被忽略（不取值直接执行） |
|---|---|---|---|---|
| `reason` | `review-loop reset` 提交失败 | `--reason <text>`（可信 TTY 中由人重新输入） | 是 | `BAD_ARGS`（`review-loop reset 需要 --reason …`），零写入 |
| `plan` | `test` 恢复 | `--plan <temp-json>` | 是 | `BAD_ARGS`（`test 需要 --plan …`），零写入 |
| `CR-ID` | `gate` 错配且位置参数非规范 `CR-YYYY-NNN` | 位置参数 `<cr_id>` | 是 | `BAD_ARGS`（`workspace 需要 CR-ID`），零写入 |

该约定同时给出**安全失败**性质：忽略 `promptFor` 的消费方不会静默执行一条语义不完整的命令，而是撞上目标 CLI 既有的入参校验（零副作用）。

### 3.5 消费方判定顺序与错误闭包（FR-17）

固定顺序，**首个**不满足项即唯一结论（禁止「A 或 B」式并列）：

| # | 检查 | 不满足时 |
|---|---|---|
| 1 | `executable` 存在、非空 string、满足 FR-3 安全约束 | 停止执行 + 报告合同错误 |
| 2 | `args` 是数组且每元素为 string | 同上 |
| 3 | `cwd` 若存在则为绝对路径 | 同上 |
| 4 | `requiresTTY=true` ⇒ 当前环境具备可信 TTY | 停止执行 + 报告所需人类动作（不得在非 TTY 环境执行） |
| 5 | `promptFor` 非空 ⇒ 存在允许的人类/调用方输入入口（取值后方可执行） | 停止执行 + 报告所需人类动作 |

四类错误（合同字段缺失或类型错误 / `executable` 违反安全约束 / TTY 要求不满足 / `promptFor` 无输入入口）统一闭合为：**停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作**；且：

- 不得自动回退旧字段 —— 旧字段已在本 CR 删除且无 alias/shim，**结构上不可回退**（FR-10）；
- 不得猜测恢复命令、不得降级为字符串执行；
- 人类界面若需显示命令，只能从 `recovery` 渲染，且显示结果不得反向作为执行输入。

消费方是提示词（Skill / Agent），不是本仓代码：本 CR 无任何代码路径执行 `recovery`（§10 边界说明、AC-11 映射）。

## 4. 关键算法与流程

### 4.1 生产者迁移算法（FR-5）

对每个既有 `recoverCommand` 模板串，按固定六步原位改写：

1. **拆 token**：把模板串按「一个 token 一个元素」拆开，`--flag` 与它的值各占一个元素；`JSON.stringify(...)` 包裹的插值改为裸值元素（引号不再需要，也不得残留）；
2. **保顺序**：元素顺序与目标 CLI 参数顺序逐字一致（含 `--workspace` 位置）；
3. **保条件**：原串中「有才拼」的可选参数在新代码中保持同一条件（三元展开成 `...(cond ? [a, b] : [])`），不引入新条件也不丢条件；
4. **定 `cwd`**：原串内插的 workspace 路径同时作为 `cwd`（绝对路径）；`gate`/`reset` 无 workspace 参数，取执行时工作区；
5. **提 `promptFor`**：原本以占位符/旧值内插、且执行时必须重新获取的值（`reason`、`plan`、非规范 `CR-ID`）**从 `args` 移除**并列入 `promptFor`；该值不得出现在任何 shell string；
6. **删除旧字段**：在**同一位置**改为 `recovery: buildRecovery(...)` 或 `extra.recovery`；不并排双写、不留 fallback。错误消息文本中引用旧字段名的措辞（如「先执行 recoverCommand 再重跑 merge」）同步改为「先执行 `recovery` 指向的 checkpoint 再重跑 merge」。

逐个生产者的 `args` 取值（`args[0]` 由构造器注入）：

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
| 10 | `gate --mode pre-review` 错配 | `workspace inspect <cr>`（非规范 CR-ID 时省略该元素） | 执行 `gate` 的工作区 | `false` | `[]` 或 `['CR-ID']` |
| 11 | `review-loop reset` 提交失败 | `review-loop reset <cr> --loop <loopRef>`（`--reason` 走 `promptFor`） | 执行 `reset` 的工作区 | `true` | `['reason']`（CR-ID 非规范时并含 `'CR-ID'`） |

站点 10/11 共用一个极小判定：规范 CR-ID（`^CR-\d{4}-\d{3,}$`）⇒ 作为独立 argv 元素；否则省略该元素并声明 `promptFor: ['CR-ID']`。既有 `crIdForRecover`（返回 `<CR-ID>` 占位符串）随之删除——占位符不再进入 `args`（决策 D-4）。

### 4.2 CLI 投影迁移算法（FR-6）

1. `buildRegisterResult` 只保留 `recovery`；`cmdRegister` 输出对象从 `recoverCommand: r.recoverCommand, recover_command: r.recoverCommand` 改为 `recovery: r.recovery`（删除双投影，其它 snake_case 镜像不动）；
2. 各 `ok({ op: '<x>', ...result })` 站点无需改动（展开后字段名自动由 producer 决定），但**必须**核对 producer 侧已改名（`archive`/`checkpoint`/`merge`/`workspace-sync`/`writeback-apply`/`test`）；
3. `gate` 与 `review-loop reset` 的 `fail(..., { recovery })` 用 §4.1 站点 10/11 的构造；
4. CLI 层不得重新拼接任何 shell string：`recovery` 一经构造即透传。

### 4.3 逐文件改法清单

> 行号为 `tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 上的参考位置；实施定位一律以实时 `rg "recoverCommand|recover_command"` 为准（PRD 明文），**禁止按行号盲改**。

| 文件 | 站点 | 改法 |
|---|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `registerCr`（`~L777`、`~L901`） | 引入 `buildRecovery`；literal → 结构化；return 字段改名 |
| 同上 | `syncWorkspaceToTrunk`（`~L1074`、`~L1118`、`~L1128`、`~L1158`） | 一个 `recovery` const 供三条 return 复用 |
| 同上 | `mergeCr`（`~L1512`、`~L1551`、`~L1555` 注释、`~L1557`、`~L1570`、`~L1573`、`~L1760`） | 两条 recovery（merge / checkpoint）；两个消息文本去旧字段名；`extra.recovery` |
| 同上 | `checkpointCr`（`~L1943`、`~L1990`、`~L2226`、`~L2231`） | literal → 结构化；catch 包装 `extra.recovery` |
| 同上 | `applyWritebackAtomic`（`~L2812`、`~L2819`、`~L2880`、`~L3127`） | 三条构造（replay×2 + 主）+ 三条承载 |
| 同上 | `archiveCr`（`~L3458`、`~L3504`） | literal → 结构化；`result()` 闭包字段改名 |
| 同上 | `buildTestResponse`（`~L4178`、`~L4184`）+ `testCr` 5 个调用点（`~L4246`、`~L4259`、`~L4265`、`~L4331` 等） | 入参增加 `workspace`；结构化 recovery + `promptFor: ['plan']` |
| `skills/shared/crctl/scripts/crctl.mjs` | `crIdForRecover`（`~L963`）+ `cmdGate`（`~L974`）+ `cmdReviewLoopReset`（`~L1906`、`~L1912` 注释）+ `buildRegisterResult`（`~L2753`）+ `cmdRegister` 输出（`~L3304`） | 占位符 helper → 规范 CR-ID 判定；两处 fail payload 结构化；单投影 |
| `skills/shared/crctl/SKILL.md` | `merge` 行、`archive` 行 | 「携 checkpoint recoverCommand」→「携 `recovery`（指向 checkpoint）」；固定返回字段列表改名 |
| `skills/cr/cr-archive/SKILL.md` | 步骤 2 说明、结果分类表 3 行、输出模板「恢复」行、错误处置表 | 改为「按 `recovery`（argv）续跑」；唯一续跑入口表述不变 |
| `skills/sync/push-progress/SKILL.md` | Step 2 错误分流行、错误表「其它事务错误」行 | 改为按 `recovery` 重跑同一命令 |
| `skills/writeback/merge-feature-branch/SKILL.md` | publication lag 行 | 「按 extra.recoverCommand 先 checkpoint」→「按 `error.recovery` 先 checkpoint」 |
| `README.md` | §7「中途失败」条 | 改为按输出的 `recovery`（结构化 argv）重跑同一命令 |
| `openwiki/operations/crctl-transactions.md` | frontmatter `invariants[1]`、正文「Recovery」条、「Change-Safety」条 | 改为结构化 `recovery` 描述（生成来源仍是 `openwiki.source_paths` 指向的同一份源码） |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | `TASK-01 RED-1` 标题、`L259`、`L317` | 结构断言（`executable`/`args`/`requiresTTY`/`promptFor`） |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 测试标题、`L224` | 同上 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 成功结果字段集用例、reset 双向量用例、rollback 用例、gate 双向量用例 | 同上；补 6 类 reason 向量与 `promptFor` 断言 |
| `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 测试标题、`L286`、`L301` | 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot |
| `skills/shared/crctl/scripts/test/register-tx.test.mjs` | `L143`、`L164`、`L637` 标题、`L650`（`recover_command`） | 同上；双投影用例改为单投影断言 |
| `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | `L269` | 同上 |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | `L818` 标题、`L831` | 断言 `--target-version` 为独立元素且值正确 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | `RETIRED` / `ACTIVE_PATHS` / 扫描断言 | 见 §4.4 |
| `multica/cr-prompts-revised/delivery-agent.md` | `L27`、`L44` | 「明确 `recoverCommand`」→「明确的结构化 `recovery`（argv）」；失败汇报项改名 |

### 4.4 契约扫描算法（FR-11）

复用**既有**静态合同扫描机制（`contract-scan.test.mjs`，CR-2026-041 FR-06/07 建立），做三处扩展：

1. **退役名单**：`RETIRED` 追加 `'recoverCommand'`、`'recover_command'`（与既有 3 个退役 Skill 名同一名单）；
2. **活跃范围（显式清单 + 动态 Pipeline 段）**：在既有 `ACTIVE_PATHS` 基础上补入本 CR 的活跃面 ——
   `skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/lib/workspace-transactions.mjs`、`skills/shared/crctl/scripts/lib/durable-tx.mjs`、`skills/shared/crctl/scripts/lib/yaml-subset.mjs`、`skills/shared/crctl/SKILL.md`、`skills/cr/cr-archive/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/writeback/merge-feature-branch/SKILL.md`、`openwiki/operations/crctl-transactions.md`、7 个被迁移的测试文件；
   另加一段 **动态 Pipeline 段**：`readdirSync('pipeline-templates')` 过滤 `*.pipeline.json`（与 `crctl-ci.yml` 既有做法同源，避免清单漂移）；
3. **判定与正反用例**：抽出纯谓词 `retiredHits(text, names)`（先 `\r\n → \n` 规范化，再 `includes`），活跃面统一断言 `retiredHits(text, RETIRED)` 为空；并新增两类反例断言：
   - **命中即失败**：合成文本 `'x recoverCommand y'` 必须被同一谓词判为命中（证明扫描有效，非恒真）；
   - **允许排除不误报**：`test/fixtures/traceability-191k.yml` 属于历史证据，仍**合法包含**旧字段名，且不在活跃清单内 —— 用例显式断言「该文件含旧字段名」且「不被扫描」，证明排除是刻意且必要的。

**排除范围**（刻意不扫，与 PRD FR-11 一致）：历史 CR 产物与历史 traceability、归档 delivery 证据、`test/fixtures/**` 历史夹具、迁移/changelog 文档、扫描器自身的禁止名单（其文本含被扫字符串作为模式）。

**跨仓边界（诚实口径）**：扫描运行在 `tools` 仓测试套件内，只能覆盖 `tools` 仓活跃面；`multica` 仓的 `cr-prompts-revised/delivery-agent.md` 与 KB 侧文档不在本扫描范围，其迁移由 §4.3 清单 + FR-14 有界盘点 + 本 CR 评审（`review-tech-design`/`review-code`）覆盖，不由工具机器证明。

### 4.5 测试迁移算法（FR-9 / FR-12）

1. **结构断言模板**（替代 `includes('…')`）：

```js
const CRCTL_JS = path.resolve(import.meta.dirname, '..', 'crctl.mjs');   // 每个测试文件内一行
assert.equal(res.recovery.executable, 'node');
assert.deepEqual(res.recovery.args, [CRCTL_JS, 'checkpoint', cr, '--workspace', ws]);
assert.equal(res.recovery.cwd, ws);
assert.equal(res.recovery.requiresTTY, false);
assert.deepEqual(res.recovery.promptFor, []);
```

2. **不对完整 JSON 做脆弱快照**：只断言 `recovery` 内的确定字段与该生产者相关的其它字段，临时路径按元素与顺序断言；
3. **参数边界向量**（每类生产者至少一条）：CR-ID / workspace / branch-ref 各占独立元素；含空格的临时路径无需引号即正确传递；元素顺序与 CLI 合同一致；
4. **用户输入向量**（`review-loop reset`，6 类）：`normal reason`、含双引号、含分号、含换行、`$(substitution)`、反引号表达式 —— 每类断言：`args` 不含该值、`promptFor` 含 `reason`、`requiresTTY === true`、`JSON.stringify(recovery)` 中该值不出现（数据而非 shell command）；
5. **合同缺失向量**：四类场景（§3.5 表）由消费方提示词合同承接（§8），生产者侧对应保证是「构造器只产出合法形状 + 每类生产者结构断言」，不新增运行期校验代码；
6. **shell 逃逸守卫**：新增断言 `crctl.mjs` / `lib/*.mjs` 内不存在 `shell: true` / `Invoke-Expression`（AC-04），与既有 `spawnSync(..., { shell: false })` 事实一致（§11-4）。

## 5. 技术选型与替代方案

### D-1 `executable: 'node'` + `args[0]` = crctl 绝对路径（采用）

- **Context**：现字符串为两种形态——深原语写 `crctl <sub> …`（裸命令名），`test` 写 `node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs test …`。本机与沙箱实测裸 `crctl` 不在 PATH（KB `AGENTS.md` 规定的正式入口就是 `node <ToolsRoot>/skills/shared/crctl/scripts/crctl.mjs`）。
- **Decision**：统一为 `executable: 'node'`、`args[0]` = 模块相对解析出的 `crctl.mjs` 绝对路径。理由是合同的第一用户是「直接 spawn 的执行方」（US-1），不可执行的入口等于把问题从「字符串拼接」换成「入口不可用」；PRD FR-3 专门为 node 形态规定了 `args[0]` 规则，AC-10 也要求 `node` 形态的断言，说明该形态在批准范围内。
- **Alternatives**：① 保留裸 `crctl` —— 逐字保留现串，但恢复动作在新环境不可执行，且与 KB `AGENTS.md` 的规范入口冲突；② 用 `process.execPath` —— 更省事，但把环境相关值写入 `recovery`，与 FR-17「不得含环境相关的可变成分」冲突。
- **Consequences**：`args[0]` 为安装路径（与 `--workspace` 同类的稳定事实），指纹在单机可复现；消费方无须关心 PATH；测试需按同一规则计算 `CRCTL_JS`。

### D-2 单一构造器 `buildRecovery`（采用）

- **Context**：11 个站点各写一份对象字面量会出现字段缺失、键序不一、`executable` 漂移三类隐患，且 FR-17 的指纹稳定性依赖同一构造规则。
- **Decision**：唯一构造器 + 输入守卫，全部站点经它构造。
- **Alternatives**：站点各自写字面量（少一处抽象，但 11 份形状靠人工保持一致，评审与未来改动成本更高）。
- **Consequences**：新增内部错误码 `RECOVERY_CONTRACT_INVALID`（仅程序员错误可达）；`buildRecovery` 成为合同唯一实现点。

### D-3 构造器落在 `lib/workspace-transactions.mjs`，不新增 `lib/recovery.mjs` 模块（采用）

- **Context**：生产者与 CLI 都需要它；`tools/ARCHITECTURE.md` §3 以显式枚举方式描述 `lib/` 下的模块（`yaml-subset.mjs` / `workspace-transactions.mjs` / `durable-tx.mjs`），而本 CR 对该文档是**只读**（write-tech-design 步骤 1 禁止借道修订，其 §8 修订触发表也不含新增 lib 模块）。
- **Decision**：作为 `workspace-transactions.mjs` 的导出函数（该模块本就是这些恢复结果的产出层），CLI 向下 import。
- **Alternatives**：新建 `lib/recovery.mjs`（职责更纯，但会让 ARCHITECTURE.md 的模块枚举立刻失真，或迫使本 CR 越界改架构文档）。
- **Consequences**：零架构文档漂移；`workspace-transactions.mjs` 多一个小函数（约 12 行）。

### D-4 `promptFor` 取代占位符（采用）

- **Context**：现串有三类不可确定值：`reset --reason`（必须人工重输）、`test --plan`（临时计划文件，调用方给定）、非规范 `CR-ID`（`gate` 错配场景的位置参数）。
- **Decision**：这三类值从 `args` 中移除并声明在 `promptFor`；`CR-ID` 规则同理（规范时作为独立元素，非规范时省略并列入 `promptFor`）。
- **Alternatives**：① 在 `args` 里保留 `<CR-ID>` / `<plan>` 哨兵 —— 与 FR-1「每元素是一个完整 argv」相抵，并把「该值必须重新获取」这一事实降级为字符串约定；② 非规范 CR-ID 场景干脆不返回恢复 —— 会丢失既有恢复方向（FR-13 要求保留原义）。
- **Consequences**：`args` 永不含占位符；忽略 `promptFor` 的消费方撞上目标 CLI 既有 `BAD_ARGS`（零副作用，§3.4）；`crIdForRecover` 的占位符语义被删除。

### D-5 退役扫描复用既有机制 + 显式活跃清单（采用）

- **Context**：既有机制是 `node --test` 内的固定路径清单 + `includes` 断言；PRD 要求「复用既有 contract-scan」「以活跃范围命中为失败」「不得以全仓零命中为唯一实现」。
- **Decision**：扩展既有清单与退役名单、抽出纯谓词用于正反用例；Pipeline 段用 `readdirSync` 动态枚举（CI 已有同源做法）。
- **Alternatives**：① 全仓遍历 + 排除表 —— 覆盖面更宽，但排除面一旦漏项就会对历史证据误报（`test/fixtures/traceability-191k.yml` 即真实反例），且改动面远大于本 CR 目标；② 在 CI 里加 grep 步骤 —— 与既有测试机制并行成第二套扫描，违背「复用」。
- **Consequences**：扫描语义是「活跃清单零命中」，历史证据与夹具合法保留旧字段名；新增活跃文件需显式入清单（评审可见）。

### D-6 消费者侧四类检查落在提示词合同（采用）

- **Context**：本仓没有执行 `recovery` 的代码消费者 —— 消费者是 Skill / Agent / 平台 Prompt（PRD §1.1、US-1）。
- **Decision**：四类缺失检查与固定判定顺序写在 `skills/shared/crctl/SKILL.md` 的「`recovery` 消费合同」小节（单一事实源），四个消费 Skill 与 `delivery-agent.md` 只引用该合同并声明本节点动作；生产者侧由构造器与测试保证形状合法。
- **Alternatives**：新增一个 `validateRecovery()` 生产代码函数 —— 无任何生产调用点（死代码），只为测试存在，与本 CR「不新增通用命令执行框架」的边界相冲。
- **Consequences**：AC-11 的验证方式是「提示词文本逐条核对 + 生产者形状断言 + 旧字段结构上不可回退」，在 §6.3 显式写明，不以伪造的运行期测试冒充证据。

## 6. FR 到技术实现映射

### 6.1 FR 映射

| FR | 技术方案条目 | 落点 |
|---|---|---|
| FR-1 | §2.1 字段表 + §3.1 类型 + §3.2 构造器（键序/可选性/恒定 `executable`） | `workspace-transactions.mjs#buildRecovery` |
| FR-2 | §4.1 拆 token 六步（元素独立、顺序一致、含空格路径免引号、无备用 shell string） | 全部 9 类生产者 |
| FR-3 | §3.2 保证 1–2：`executable` 恒定 `'node'`，脚本路径恒在 `args[0]`；§4.5 守卫断言 | `buildRecovery` + 测试 |
| FR-4 | §3.4 `promptFor` 解析约定 + §4.1 第 5 步（值不进 `args`、`requiresTTY` 独立声明） | `cmdReviewLoopReset`、`testCr`、`cmdGate` |
| FR-5 | §4.1 逐个生产者 args 取值表（11 行，含条件参数保序） | `lib/workspace-transactions.mjs` 9 类场景 |
| FR-6 | §4.2 投影迁移四步（单投影、双投影删除、错误路径结构化、CLI 不拼串） | `crctl.mjs` 5 处 |
| FR-7 | §4.3 消费方四份 SKILL.md + `delivery-agent.md` 改法 | 5 个提示词文件 |
| FR-8 | §4.3 README + openwiki 改法；同一份源码即生成来源，不新增第二套描述 | `README.md`、`openwiki/operations/crctl-transactions.md` |
| FR-9 | §4.5 结构断言模板 + 6 类 reason 向量 + 反脆弱快照规则 | 7 个测试文件 |
| FR-10 | §4.1 第 6 步（原位删除、不并排双写）+ §2.3 别名表（无 alias/shim/fallback） | 全量站点 |
| FR-11 | §4.4 扫描算法（退役名单 + 活跃清单 + 动态 Pipeline 段 + 正反用例 + 排除范围） | `contract-scan.test.mjs` |
| FR-12 | §4.5 向量 3/4/5/6（参数边界、6 类用户输入、四类缺失、`executable` 安全） | 测试 + 提示词合同 |
| FR-13 | §2.2 不落盘 + §3.3「其它字段与错误码/exit code/txId/rollback/files 不变」+ §4.2 只改载体 | 全量 diff 约束 |
| FR-14 | §11 既有实现依赖清单即基线盘点；六类归档口径在本表与 §4.3 已落形，正式归档表由 `write-dev-plan` 产出 | `plan.md`（下游节点） |
| FR-15 | §9 `scope_out` 明列「不做双写/不留半迁移」；回滚＝整体回滚（回退上一完整 `tools` 版本或回滚本 CR） | §9 + 流程约束 |
| FR-16 | §1.1 范围表「不更新平台 DB」+ §8 Prompt 采纳影响 | 本 SDD + 交付汇报口径 |
| FR-17 | §2.4 指纹字段集 + §3.5 固定判定顺序与错误闭包 + §3.1 零副作用（纯数据） | `buildRecovery` + 提示词合同 |

### 6.2 复杂度与改动面

- 生产者 9 类 / 站点 11 处；CLI 投影 5 处；消费方提示词 5 个文件；文档 2 个；测试 8 个文件。
- 净新增生产代码仅 `buildRecovery`（约 12 行）+ 站点改写（等价行数）；无新命令、无新状态、无新持久化。

### 6.3 AC 逐项设计与验收映射

- **AC-01**（FR-1/FR-2）
  - 设计落点：`buildRecovery` + 11 个站点；`args` 元素由 §4.1 表逐条固定。
  - 可观测结果：每个生产者响应/错误中的 `recovery` 字段为固定 5 键、`args` 与 §4.1 表逐元素一致、无 `recoverCommand`/`recover_command`、无等价 shell string 备用入口。
  - 可达性说明：8 类恢复路径在既有测试中均有既有注入点（faultPoint / 预置 staged 变更 / 预提交钩子 / 非法入参），无权限或状态门禁过滤。
- **AC-02**（FR-5/FR-6）
  - 设计落点：`registerCr`、`syncWorkspaceToTrunk`、`mergeCr`、`checkpointCr`、`applyWritebackAtomic`、`archiveCr`、`testCr`、`cmdReviewLoopReset`。
  - 可观测结果：8 类恢复路径对应测试全绿，且断言的是结构化 `recovery`（非字符串包含）。
  - 可达性说明：`review-loop reset` 的失败分支由 `.githooks/pre-commit` 钩子触发（既有手法），其余由既有事务测试与故障注入覆盖。
- **AC-03**（FR-4/FR-12.2）
  - 设计落点：`cmdReviewLoopReset` 的 `recovery` 构造（`promptFor: ['reason']`、`requiresTTY: true`、`--reason` 不入 `args`）。
  - 可观测结果：6 类 reason 向量下 `args` 均不含该文本、`promptFor` 为 `['reason']`、`requiresTTY === true`、序列化结果为数据。
  - 可达性说明：reset 为 TTY 专用入口，测试用既有 `runCrctlInTty` 包装（已有工具函数），不因非 TTY 提前退出而不可达。
- **AC-04**（FR-17 副作用段）
  - 设计落点：全部执行点使用 argv 接口（既有 `spawnSync(..., { shell: false })`）；合同载体为纯数据。
  - 可观测结果：`crctl.mjs` 与 `lib/*.mjs` 内 `shell: true`、`Invoke-Expression` 零命中（新增守卫断言）。
  - 可达性说明：断言对象为活跃源码本身，无运行时前置条件。
- **AC-05**（FR-7/FR-8/FR-9/FR-10）
  - 设计落点：§4.3 逐文件改法清单（含 4 Skill + 1 Agent + 2 文档 + 7 测试）。
  - 可观测结果：活跃范围内旧字段名零命中（扫描）；`multica` overlay 与 tools 侧清单逐条核对；无 alias/shim/fallback。
  - 可达性说明：`multica` 与 KB 侧不在 tools 扫描范围（§4.4 跨仓边界），由 §4.3 清单 + 评审比对 diff 覆盖。
- **AC-06**（FR-11）
  - 设计落点：§4.4 扫描算法（退役名单、活跃清单、动态 Pipeline 段、纯谓词）。
  - 可观测结果：活跃面命中即测试失败；合成命中用例通过；历史夹具仍含旧名且被排除（不误报）。
  - 可达性说明：扫描是纯文件读 + 字符串判定，无环境依赖。
- **AC-07**（FR-13）
  - 设计落点：零语义变更约束（§3.3）。
  - 可观测结果：`node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs` 全绿 + `skills/writeback/scripts/test/*.test.mjs` 全绿。
  - 可达性说明：CI 同一命令（`crctl-ci.yml`），本机可复现。
- **AC-08**（FR-13）
  - 设计落点：diff 仅落在 `recovery` 载体与旧字段名措辞。
  - 可观测结果：既有错误码（`MERGE_SOURCE_MISSING`、`RELEASE_REMOTE_NOT_PUSHED`、`REVIEW_LOOP_RESET_COMMIT_FAILED`、`BAD_ARGS`…）、状态转换、`txId`、`rollback`/`files` 字段与事务测试未变部分全绿。
  - 可达性说明：逐项以既有测试 + `git diff --stat` 对照核对。
- **AC-09**（FR-16）
  - 设计落点：§8 采纳清单仅含 owner 可复制版本；平台 DB 部署在 CR 之外。
  - 可观测结果：本 CR 的 PLAN/TASK/交付汇报与 writeback 产物中无「平台 DB 已部署」表述，且显式记录 owner 部署动作。
  - 可达性说明：口径约束落在下游节点（`write-dev-plan`、交付汇报），节点粒度可见。
- **AC-10**（FR-3/FR-12.3）
  - 设计落点：构造器恒定 `executable: 'node'` + `args[0]` 为脚本路径。
  - 可观测结果：每类生产者的 `executable`/`args[0]` 断言；`executable` 不含空格与 shell 运算符（按构造）。
  - 可达性说明：断言直接读生产者输出，无前置过滤。
- **AC-11**（FR-12.4/FR-17）
  - 设计落点：`skills/shared/crctl/SKILL.md`「`recovery` 消费合同」（固定 5 步 + 四类闭包）为单一事实源；消费 Skill/Agent 引用之；生产者由构造器保证形状。
  - 可观测结果：提示词文本逐条可核对（顺序、停止、报告、零副作用、不猜测、不回退）；生产者输出形状断言全绿；旧字段无 alias ⇒ 回退在结构上不可达。
  - 可达性说明：消费方是提示词而非本仓代码，本 CR 无执行 `recovery` 的代码路径，故以「提示词合同 + 生产者形状断言」验证，不伪造运行期测试（D-6）。
- **AC-12**（FR-14）
  - 设计落点：六类归档口径（producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence）+ §11 清单作为基线盘点。
  - 可观测结果：`plan.md` 内存在一次有界搜索的六类归档表，且未新增持续观测机制。
  - 可达性说明：盘点在 `write-dev-plan` 节点执行；本 SDD 已按同一口径完成一次基线盘点（§4.3 + §11）。
- **AC-13**（FR-15）
  - 设计落点：单发布原子迁移（同 CR 内生产者 + 消费者 + 删除 + 扫描）。
  - 可观测结果：交付分支不存在「部分生产者新合同 / 部分消费者旧合同」；回滚方案为整体回滚（回退上一完整 `tools` 版本，不在当前版本双写）。
  - 可达性说明：由同一 CR 内全量迁移 + 全量测试保证；回滚口径记录在 §9。
- **AC-14**（FR-16）
  - 设计落点：正常 writeback（`specs/`、`delivery/`）在本 CR 流程内。
  - 可观测结果：writeback 产物存在且与 CR 结论一致。
  - 可达性说明：由 `feature-writeback` 节点产出，本 SDD 不预置。

### 6.4 SDD-CLOSE 关闭结论

PRD 显式延后到 SDD 的设计项逐项关闭（覆盖数据生产、存储/传输、响应/schema、消费与兼容降级各层）：

- **SDD-CLOSE-01（恢复合同接口闭包）**：字段集、类型、必填性、键序、`cwd` 语义与可选性、命名冲突 → §2.1/§2.3/§3.1/§3.2 关闭。覆盖：生产（构造器）、传输（JSON 响应）、响应/schema（CLI 输出与 `error.extra`）、消费（提示词）、兼容降级（无 alias/shim，旧字段删除）四层。
- **SDD-CLOSE-02（argv 边界与 executable 规范化）**：token 拆分、顺序、含空格路径、node 形态 `args[0]` → §4.1/§3.2 关闭；同时关闭「`test` 恢复中的 `{TOOLS_ROOT}`/`<worktree>` 占位符」问题（改用真实路径）。
- **SDD-CLOSE-03（`promptFor` 解析约定）**：逻辑值名 → CLI 入口映射、从 `args` 省略、忽略时的安全失败 → §3.4 关闭；覆盖 `reason`/`plan`/`CR-ID` 三处生产点与消费侧取值要求。
- **SDD-CLOSE-04（错误闭包与判定顺序）**：固定 5 步顺序、四类缺失的停止/报告动作、零副作用、不回退旧字段、非 shell 执行 → §3.5 + §8 关闭（消费者侧文本合同 + 生产者侧形状保证 + 旧字段结构性删除）。
- **SDD-CLOSE-05（契约扫描实现方式）**：复用既有机制的扩展点、活跃范围、排除范围、命中即失败与不误报的正反用例、跨仓边界 → §4.4 关闭。
- **SDD-CLOSE-06（逐文件改法与文案口径）**：11 个生产者站点 + 5 个 CLI/投影点 + 5 个提示词 + 2 个文档 + 8 个测试的改法；错误消息与展示文案不得引用退役字段名、显示文本只能从 `recovery` 渲染 → §4.3 关闭（含「消息文本去旧名」两条）。

无未关闭项；无遗留待办。

## 7. 安全与性能考量

### 7.1 安全控制点

| 控制点 | 设计 | 验证 |
|---|---|---|
| 注入面闭合 | 用户可控输入（reason、路径、ref）只以独立 argv 元素承载，不进入任何被 shell 解释的字符串 | 6 类 reason 向量 + 无 shell string 断言 |
| 执行方式 | 消费方与非 shell 接口一致（`spawn`/`execFile` 语义）；`shell: true` / `Invoke-Expression` 零命中 | 守卫断言（AC-04） |
| 入口可信 | `executable` 恒定 `node`，脚本路径由模块位置解析（不接受外部注入） | 构造器 + 断言 |
| 人在环 | `requiresTTY`（reset）与 `promptFor`（reason/plan/CR-ID）只结构化声明既有要求，不削弱也不新增绕过路径 | 提示词合同 + 断言 |
| 显示与执行分离 | 人类可读文本只能从 `recovery` 渲染，且不得反向作为执行输入 | 提示词文本（§4.3） |
| 退役保护 | 旧字段名在活跃面命中即失败，防止回流 | §4.4 扫描 |

### 7.2 性能

- `recovery` 是纯数据构造（对象字面量 + 一次数组拼接），无 I/O、无子进程、无解析；对既有事务路径的开销可忽略。
- 不新增常驻进程、扫描调度或流水线阶段；退役扫描沿用既有静态测试，不新增 CI 步骤（`crctl-ci.yml` 零改动）。

### 7.3 边界条件

- `args` 为空候选值（`--stage traceability` 的 `--target-version` 为空串）仍作为合法 string 元素保留原样，由目标 CLI 既有校验判定（不新增本层校验）。
- 含空格/非 ASCII 的路径与文本（含中文 summary、含换行 reason）遵循同一 argv 规则，无引号处理分支。
- 同一 CR 的 `recovery` 在重复求值时逐元素相等（§2.4）。

## 8. Prompt 采纳影响

本 CR **确实触及** `crctl.mjs` 的结果合同（命令面输出/错误面字段改名），因此按 write-tech-design 步骤 2 第 8 节填写；`skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 未触及。

| Skill / Agent 提示词 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md` | `merge`/`archive` 行描述 `recoverCommand`；无消费合同 | 「携 `recovery`（指向 checkpoint）」+ 新增「`recovery` 消费合同」小节（固定 5 步判定 + 四类闭包，单一事实源） |
| `skills/cr/cr-archive/SKILL.md` | 「只重跑 recoverCommand」 | 「按 `recovery`（argv）重跑同一 `crctl archive`」，唯一续跑入口表述不变 |
| `skills/sync/push-progress/SKILL.md` | 按 `recoverCommand` 分流/重跑 | 按 `recovery` 重跑同一命令 |
| `skills/writeback/merge-feature-branch/SKILL.md` | 「按 extra.recoverCommand 先 checkpoint」 | 「按 `error.recovery` 先 checkpoint 再重跑 merge」 |
| `multica/cr-prompts-revised/delivery-agent.md` | 「明确 `recoverCommand`」 | 「明确的结构化 `recovery`（argv）」；失败汇报项改名 |

**采纳完整性**：以上 5 处即本 CR 全部需要采纳新合同的活跃提示词（由 §11 的全文检索基线盘点确定，`rg "recoverCommand|recover_command"` 命中集合逐条落位）。
**无遗留采纳项**：本 CR 内同批迁移，不存在「crctl 已有新能力但某提示词尚未采纳」的后续项。
**平台部署边界**：`multica/cr-prompts-revised/*.md` 只是 owner 可复制的版本，平台 DB 内提示词由 owner 在 `tools` 发布后另行更新（FR-16）；本 CR 不更新平台 DB，也不声称已部署。

## 9. 批准范围

### scope_in

- 唯一结构化恢复合同 `recovery`（`executable`/`args[]`/`cwd`/`requiresTTY`/`promptFor[]`）与唯一构造器 `buildRecovery`（§3.2）。
- 11 个生产者站点迁移（§4.1 表 1–9）与 5 处 CLI 投影/错误面迁移（§4.2），含 `register` 双投影删除。
- 旧字段 `recoverCommand` / `recover_command` 在本 CR 内删除，无 alias/shim/fallback。
- 5 个活跃提示词的消费方式迁移（§8）+ 2 个文档的事实源迁移（§4.3）+ `skills/shared/crctl/SKILL.md` 新增「`recovery` 消费合同」小节。
- 7 个既有测试文件的结构断言迁移 + `contract-scan.test.mjs` 的退役名单/活跃范围/正反用例扩展 + `shell: true`/`Invoke-Expression` 守卫断言。
- FR-1…FR-17、AC-01…AC-14 全部。

### scope_out

- 不新增通用命令执行框架、shell parser、quoting library、跨 shell renderer。
- 不改 `reviewLoop` / `archive` / `merge` / `checkpoint` / `writeback` 业务算法，不改错误码/状态转换/门禁语义。
- 不做双写兼容期、deprecated alias、migration shim、第二个删除 CR。
- 不改写历史 CR、历史 traceability、归档 delivery 证据、测试夹具 `test/fixtures/**`。
- 不更新 Multica DB/平台 Prompt、不改 Multica API 或 importer（含 `aifirst/agent-import.mjs`）。
- 不新增使用量/失败率/SLO/迁移统计或持续观测机制。
- 不包含 AIFI-18 的 SDD review 规则、`_context.md` 删除、plan/TASK 增量回修、Pipeline 节点调整。
- 不与 CR-P1 / CR-P2 合并为同一发布单元。

### zero_diff

- `tools/ARCHITECTURE.md`、`dir-graph.yaml`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、`pipeline-templates/**`、`.github/workflows/**`：零改动。
- 既有公开错误码、`exit code`、`txId`、`status`/转换语义、`files`/`rollback` 字段、`.crctl/transactions/**` journal schema：零改动。
- 成功结果中除 `recoverCommand`/`recover_command` 外的其它字段（含 `cr_id`/`tx_id`/`operational_workspace` 等 snake_case 镜像）：零改动。
- 既有 `spawnSync(..., { shell: false })` 执行点、`recoverWriteSet`/`recoverLedgerTransaction` 等内部恢复原语名：零改动。
- `tools/agents/*.md`（含 `agents/delivery-agent.md`）：零改动（无旧字段引用，理由见 §11-13）。

### follow_up

- `mergeCr` 的 `phase=release-drift` 结果仍携带「重跑 merge」方向的 `recovery`，但该分支已由深原语自动回退 `code-approved → developing`，重跑 merge 不会成功。本 CR 只做等价迁移（FR-13 零语义变更），方向修正留待后续 CR 评估。
- `tools/agents/delivery-agent.md`（方法论包内的 Agent 基底版）与 `multica/cr-prompts-revised/delivery-agent.md` 内容已不同步；本 CR 只迁移后者（PRD 指定），两者收敛留待后续 CR。
- OpenWiki 页面由定时工作流按 `openwiki.source_paths` 重新生成；若再生成文本与本 CR 的手工迁移文本出现措辞差异，以源码为权威，属文档层收敛，不构成本 CR 的验收门槛。

## 10. 术语硬化与边界场景验证

| 术语 | 进入哪一层 | 歧义/别名/边界风险 | 边界场景验证（至少一条） | 结论 |
|---|---|---|---|---|
| `recovery`（响应字段） | 接口契约 | 与内部恢复原语 `recoverWriteSet` / `recoverLedgerTransaction` / `recoverLedgerCommand`、与错误码 `TX_RECOVERY_CONFLICT` 同前缀不同层 | 构造器返回对象只含 5 个约定键；内部原语名零改动（`rg "recoverWriteSet"` 不变） | 命名冲突已记录：不合并、不改名；字段名指「恢复动作的结构化载体」 |
| `recoverCommand` → `recovery` | 接口契约 | PRD canonical term 与代码别名映射：旧名退役，无 alias | 活跃面扫描零命中；历史夹具仍含旧名且被排除 | 映射记录完毕；旧名为「已退役别名」，不保留读取路径 |
| `cwd` | 接口契约 | 与既有 `--workspace` / `ctx.installRoot` 语义重叠可能被误当作唯一权威 | ① 生产者侧的 `cwd` 与 `--workspace` 值同源（同一变量取两次，不各自计算）；② `buildRecovery` 省略 `cwd` 时对象不含该键（单测覆盖可选性边界） | `--workspace` 是 CLI 的权威解析入口（语义保留），`cwd` 是进程工作目录事实；二者不得出现不同来源 |
| `requiresTTY` | 接口契约 | 与既有错误码 `NOT_TTY` 的关系 | reset 恢复的 `requiresTTY === true`，非 TTY 下 CLI 自身 `NOT_TTY` 拒绝（既有行为不变） | 一致：`requiresTTY` 是「必须在可信交互终端执行」的结构化声明，不新增门禁 |
| `promptFor` | 接口契约 | 值名 vs CLI flag 名的映射歧义（`reason`/`plan`/`CR-ID`） | 三处取值名与目标入口在 §3.4 逐条固定；忽略时撞 `BAD_ARGS`（零副作用） | 规则已硬化：值名是逻辑名，按 §3.4 表映射到既有入口 |
| `executable` | 接口契约 | 与 `cr-test-plan/v1` 的 `executable` 同名词、不同对象 | 两处语义一致（均指非 shell 可执行入口），互为先例；测试计划 schema 零改动 | 同名同义，不构成冲突 |
| `args` | 接口契约 | 与 `cr-test-plan/v1` 的 `args` 同名词 | 同上；`recovery.args[0]` 为脚本路径（node 形态），测试计划 `args` 不含脚本路径 | 语义一致，形态差异在 §3.2 明确 |

**语义冲突裁决**：未发现 PRD canonical 语义与既有代码语义冲突的术语，无需在首次 `crctl advance` 前请求需求负责人澄清（本节点已完成该推进：`requirement-approved → tech-designing`）。

## 11. 既有实现依赖与事实

盘点基线：`rg "recoverCommand|recover_command"`（排除 `.git`、`node_modules`）在 `tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 命中 **16 个文件 / 73 行**，在 `multica@ab9609483d17db12117cb8e9adb2d896f413917d` 命中 **3 个文件 / 6 行**（其中 2 个文件是 `server/internal/governance/testdata/` 历史黄金数据）。以下为按正文首次出现顺序的依赖清单：

1. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `registerCr` / `syncWorkspaceToTrunk` / `mergeCr` / `checkpointCr` / `applyWritebackAtomic` / `archiveCr` / `testCr` / `buildTestResponse` 的返回值与 `TxError.extra` 载体（本文件 24 处旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 这些函数是全部恢复动作的生产者，其返回结构与 `extra` 字段名即本 CR 的迁移对象；`buildRecovery` 落在本文件内（D-3），因此本文件同时是唯一构造器的宿主。
2. repo: `tools`
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `crIdForRecover`（`~L963`）、`cmdGate` pre-review 错配分支（`~L974`）、`cmdReviewLoopReset` 提交失败分支（`~L1906`）、`buildRegisterResult`（`~L2753`）、`cmdRegister` 输出对象双投影（`~L3304`）；同一文件内 `cmdReviewLoopReset` 的 `NOT_TTY` 前置校验（`~L1840`）与 `fail/ok` 输出契约（`~L31`/`~L35`）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: CLI 是唯一投影层；`error.recovery` 与顶层 `recovery` 的落点由 `fail()`/`ok()` 的既有形状决定（见 3）；`NOT_TTY` 校验是 `requiresTTY: true` 的事实依据。
3. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/durable-tx.mjs`
   stable symbol/对象: `TxError`（`code`/`message`/`extra`）与 `loadOrCreateJournal`/`saveJournal` 的 journal payload 结构
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `extra` 是错误面恢复数据的唯一传递通道；journal payload 不含恢复字段，是「不落盘、无 schema 迁移」（§2.2）的事实依据。
4. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `parseTestPlan` / `runTestPlan` 的 argv 执行先例（`cmd.executable` + `cmd.args` + `spawnSync(..., { shell: false })`，`cr-test-plan/v1`）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 本仓既有代码已以 `executable` + `args` + `shell:false` 执行外部命令，`recovery` 合同沿用同一形态与命名，属仓内既有先例而非新范式（D-1、§10）。
5. repo: `tools`
   relative path: `skills/shared/crctl/scripts/test/contract-scan.test.mjs`
   stable symbol/对象: `FORBIDDEN` / `RETIRED` / `ACTIVE_PATHS` 静态扫描机制与 `readFileSync + replaceAll('\r\n','\n') + includes` 判定
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: FR-11 要求复用既有静态合同扫描机制——该文件即既有机制，本 CR 在其上追加退役名与活跃面（§4.4），不新建扫描器。
6. repo: `tools`
   relative path: `skills/shared/crctl/scripts/test/{archive-tx,checkpoint-tx,merge-tx,register-tx,workspace-freshness,writeback-tx,crctl}.test.mjs`
   stable symbol/对象: 旧字段字符串断言（`result.recoverCommand.includes(...)`、`assert.match(r.json.recoverCommand, …)`、`assert.equal(r.stderr.error.recoverCommand, …)`、`recover_command`）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 这些断言是 FR-9「改为结构断言」的迁移对象；同时它们是 AC-02/AC-03/AC-07 的既有证据通道（恢复路径已可达）。
7. repo: `tools`
   relative path: `skills/shared/crctl/SKILL.md`
   stable symbol/对象: 命令面表格（`merge` / `archive` 行）对恢复字段的消费说明
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 该文件是 crctl 命令面的权威 Skill 文档，也是新增「`recovery` 消费合同」的落点（§8、D-6）。
8. repo: `tools`
   relative path: `skills/cr/cr-archive/SKILL.md`
   stable symbol/对象: Step 2/Step 3 结果分类表、输出模板「恢复」行、错误处置表（6 处旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `archive` 的清理/补发续跑语义依赖恢复动作，提示词必须改读结构化 `recovery`（FR-7）。
9. repo: `tools`
   relative path: `skills/sync/push-progress/SKILL.md`
   stable symbol/对象: Step 2 错误分流与错误处置表（2 处旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `checkpoint` 重跑口径依赖恢复动作（FR-7）。
10. repo: `tools`
    relative path: `skills/writeback/merge-feature-branch/SKILL.md`
    stable symbol/对象: `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` 行（1 处旧字段命中）
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: publication lag 的恢复入口（`extra.recovery`）是该 Skill 的既定分支，字段名变更须同步（FR-7）。
11. repo: `tools`
    relative path: `README.md`（§7「恢复与 `crctl status/next`」）与 `openwiki/operations/crctl-transactions.md`（frontmatter `invariants`、Recovery 条、Change-Safety 条）
    stable symbol/对象: 两处文档对恢复合同的描述；openwiki 的 `openwiki.source_paths` 指向同一份 crctl 源码
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 文档必须与代码同批迁移且不得新增第二套描述（FR-8）；openwiki 由定时工作流按 `source_paths` 重新生成（`.github/workflows/openwiki-update.yml`），权威输入是源码本身。
12. repo: `multica`
    relative path: `cr-prompts-revised/delivery-agent.md`
    stable symbol/对象: 交付纪律段（`L27`「明确 `recoverCommand`」、`L44` 失败汇报项）
    commit SHA: `ab9609483d17db12117cb8e9adb2d896f413917d`
    依赖结论: 交付 Agent 的 owner 可复制提示词是 FR-7 指定的活跃消费者之一；平台 DB 内版本由 owner 另行部署（FR-16）。
13. repo: `tools`
    relative path: `agents/delivery-agent.md` 与 `agents/*.md`
    stable symbol/对象: 方法论包内的 Agent 提示词全集
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 全量检索确认这些文件**不含**旧字段名（故列入 `zero_diff`，不可借机改动）；`agents/dev-agent.md` 的「按 crctl 明示的恢复方向恢复一次」措辞不绑定字段名，语义在新合同下仍成立。
14. repo: `tools`
    relative path: `skills/shared/engineering-docs/templates/SDD-template.md`、`skills/develop/write-tech-design/SKILL.md`
    stable symbol/对象: 本 SDD 的章节与范围章节契约
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 本 SDD 的章节结构、`target-version` 继承与 §9 四字段约束来自该模板与 Skill，落地时必须符合。
15. repo: `tools`
    relative path: `.github/workflows/crctl-ci.yml`
    stable symbol/对象: 全量测试命令 `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`、Pipeline JSON 动态枚举（`readdirSync('pipeline-templates')`）、`writeback` 单测命令
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: AC-07 的验收命令与 §4.4 动态 Pipeline 段的既有先例均来自该文件；本 CR 不改 CI 配置。
16. repo: `tools`
    relative path: `ARCHITECTURE.md`
    stable symbol/对象: §3 代码地图（`lib/` 模块枚举与 `crctl.mjs` 职责）、§4 分层规则、§5 不变量（状态单一写者、零依赖、行尾纪律、状态机口径）、§8 维护规则
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 本 CR 的设计必须不违反上述不变量（构造器下沉 lib、CLI 单向依赖、零第三方依赖、行尾规范化、无新状态），且因未触发 §8 修订条件而不修该文档（D-3）。

**待核实依赖**：无（上列各项均已在本 CR 资源 HEAD 上按符号与行为核对；历史黄金数据 `multica/server/internal/governance/testdata/traceability-golden.{json,yml}` 与 `tools/skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` 属历史证据，按 FR-11 排除范围处理，不计入依赖）。
