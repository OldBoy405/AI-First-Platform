---
id: CR-2026-064-sdd
type: SDD
cr-ref: CR-2026-064
title: CR-R：结构化恢复合同原子迁移 — `recoverCommand`/`recover_command` 全量退役为结构化 `recovery` 技术设计
target-version: 0.37
status: draft
created: "2026-09-12T22:48:00+08:00"
updated: "2026-09-12T23:45:00+08:00"
---

# CR-R：结构化恢复合同原子迁移 — 技术设计

> 输入：`change-requests/CR-2026-064/prd.md`（5 US / 17 FR / 14 AC，评审 PASS + 人工审批）。
> 本文只设计「把恢复动作从命令字符串改为结构化 `recovery`」的落点与算法；不改任何既有错误码语义、状态转换、事务边界与业务算法。
> 修订：`review-tech-design` attempt 1/3 判 BLOCK（TD-BL-1 扫描覆盖 / TD-BL-2 OpenWiki 生成闭环 / TD-BL-3 依赖事实与计数口径）后的定点回修；改动限于 §1.1、§4.3、§4.4、D-5、新增 D-7、§6.1–§6.4、§9、§11，方案主体未重写。
> 修订：`review-tech-design` attempt 2/3 判 BLOCK（TD-BL-1 未清：扫描面把「未列目录」默认为非活跃，漏掉 11 个活跃 MJS）后的定点回修；扫描面改为**整树派生 + 两项被断言排除**，改动限于 §1.1、§4.3、§4.4、D-5、§6.1、§6.3 AC-05/AC-06、SDD-CLOSE-05、§9、§11，合同字段、生产者改法、D-1…D-4/D-6/D-7 未重写。
> 修订（`review-tech-design` attempt 3/3 判 BLOCK 后的**新 cycle 定点回修**，`review-annotations/sdd.yml` 评审 commit `f4e6cfd`）：唯一残留点 TD-BL-1 —— 排除面把 `skills/shared/crctl/scripts/test/fixtures/**` 整目录排除，而该目录下三个 canonical digest 向量是活跃测试证据。排除面收窄为**扫描器自身 + `test/fixtures/traceability-191k.yml` 精确路径**两项，`fixtures/digest-vectors/**` 与今后新增夹具默认入面；扫描面 209 → **212**，代表性用例七条 → **八条**。改动限于 §4.4、D-5、§6.1、§6.3 AC-06、SDD-CLOSE-05、§9、§10、§11；合同字段、生产者改法、D-1…D-7 方案面未重写。

## 1. 架构概览

### 1.1 变更边界

| 仓 | 路径 | 变更性质 |
|---|---|---|
| `tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 生产者：9 类可恢复场景原位改为结构化 `recovery`；新增唯一构造器 `buildRecovery` |
| `tools` | `skills/shared/crctl/scripts/crctl.mjs` | 投影层：删除 `recoverCommand`/`recover_command` 双投影，2 处错误恢复改为结构化，注册结果单投影 |
| `tools` | `skills/shared/crctl/scripts/test/*.test.mjs` | 7 个既有测试文件由字符串包含断言改为结构与 argv 断言；`contract-scan.test.mjs` 扩展退役名单与扫描面 |
| `tools` | `skills/shared/crctl/SKILL.md`、`skills/cr/cr-archive/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/writeback/merge-feature-branch/SKILL.md` | 消费方提示词：改读 `recovery.executable/args/cwd/requiresTTY/promptFor` |
| `tools` | `README.md`（手工原位迁移）、`openwiki/operations/crctl-transactions.md`（**生成物**，不手工编辑） | README 原位改读结构化合同；OpenWiki 页面由既有生成步骤从迁移后的权威源码重新生成并核对（D-7），旧合同描述随之消失，不新增第二套描述 |
| `multica` | `cr-prompts-revised/delivery-agent.md` | 交付 Agent 提示词的 owner 可复制版本改读结构化结果（本 CR 不更新平台 DB） |
| 知识库 | `change-requests/CR-2026-064/sdd.md` + 后续 PLAN/TASK | 本 CR 产物 |

**不在本 CR 变更范围**：`tools/ARCHITECTURE.md`（已存在，只读引用；本 CR 不触发其 §8 修订条件）、`dir-graph.yaml`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、`pipeline-templates/**`（无旧字段引用，仅纳入退役扫描面）、`tools/agents/*.md`（无旧字段引用）、Multica 服务端与 importer。

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
| `openwiki/operations/crctl-transactions.md` | frontmatter `invariants[1]`、正文「Durable Transaction Envelope → Recovery」条、「Change-Safety Guidance」第 3 条 | **生成物，不手工编辑**：源码迁移完成后由既有生成步骤（`openwiki code --update`，与 `openwiki-update.yml` 同源）重新生成该页，再核对三处旧合同断言归零（D-7） |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | `TASK-01 RED-1` 标题、`L259`、`L317` | 结构断言（`executable`/`args`/`requiresTTY`/`promptFor`） |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 测试标题、`L224` | 同上 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 成功结果字段集用例、reset 双向量用例、rollback 用例、gate 双向量用例 | 同上；补 6 类 reason 向量与 `promptFor` 断言 |
| `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 测试标题、`L286`、`L301` | 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot |
| `skills/shared/crctl/scripts/test/register-tx.test.mjs` | `L143`、`L164`、`L637` 标题、`L650`（`recover_command`） | 同上；双投影用例改为单投影断言 |
| `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | `L269` | 同上 |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | `L818` 标题、`L831` | 断言 `--target-version` 为独立元素且值正确 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | `FORBIDDEN` / `RETIRED_LEGACY` / `ACTIVE_PATHS`（既有）+ 新增 `RETIRED_RECOVERY`、整树扫描面与排除断言 | 见 §4.4（CR-2026-041 既有断言保持不动） |
| `multica/cr-prompts-revised/delivery-agent.md` | `L27`、`L44` | 「明确 `recoverCommand`」→「明确的结构化 `recovery`（argv）」；失败汇报项改名 |

### 4.4 契约扫描算法（FR-11）

复用**既有**静态合同扫描机制（`contract-scan.test.mjs`，CR-2026-041 FR-06/07 建立），做三处扩展：退役名单、**扫描面**、判定与正反用例。

**1. 退役名单：按名分范围**

| 名单 | 名称 | 扫描范围 |
|---|---|---|
| `RETIRED_RECOVERY`（本 CR 新增） | `recoverCommand`、`recover_command` | 扫描面（§4.4-2） |
| `RETIRED_LEGACY`（CR-2026-041 既有） | `change-impact-analysis`、`feedback-writeback`、`feedback-writeback-done` | 保持既有显式 `ACTIVE_PATHS` 与既有断言，**本 CR 不改其名单与范围** |

分名分范围的事实依据（已在资源 HEAD 上核实，记录见 §11-5）：三个既有退役名在活跃面内**合法存在** —— `skills/shared/crctl/scripts/lint-prompts.mjs`（linter 的禁止名单）、`crctl.test.mjs` / `lint-prompts.test.mjs`（禁止名单的用例样本）、`CUSTOM.md`（台账引述）。把 `RETIRED_LEGACY` 并入整树扫描面会让 CR-2026-041 的断言立刻失败，而迁移这些名单不在本 CR 范围（§9 `zero_diff`）；PRD FR-11 要求加入退役清单的只有两个恢复字段名，故按名分范围。**整树扫描面只适用于两个恢复字段名**：它们在本 HEAD 的 `tools` 仓内除迁移对象与两项排除外零命中（下表的 212 文件扫描面成立），而三个既有退役名在 `docs/` 下的历史报告与历史夹具里合法存在（`rg -l` 本 HEAD 共 8 个文件，§11-5），套用整树扫描会立刻误报。

**2. 扫描面：整树派生 + 两项被断言的排除，不声明「哪些目录/扩展名算活跃」**

| 项 | 规则（唯一事实源） |
|---|---|
| 枚举根 | `tools` 仓库工作树根（`ROOT`）；`readdirSync(dir, { withFileTypes: true, recursive: true })` 递归枚举**全部文件**，只跳过两个被冻结的枚举边界 `.git` 与 `node_modules`（前者是版本库元数据、后者是 `.gitignore` 忽略的依赖目录，均非仓库跟踪内容；`SKIP_DIRS = ['.git', 'node_modules']` 由断言冻结，见 §4.4-3。按**路径段**判定，不区分文件/目录——`tools` 工作树里 `.git` 是文件，同样排除，故枚举数 214 与实现共用同一规则） |
| 扫描面 | 枚举结果 − 下表两项排除；两项排除都是**精确路径**（无目录/扩展名通配）；**不按目录、不按扩展名、不按文件名**推断活跃性 |
| 派生规模（`tools@dddd0ad6` 实测，与实现共用同一枚举） | 枚举 **214** 文件 − 扫描器自身 **1** − 历史 traceability 精确路径 **1** = **扫描面 212 文件** |
| 分类覆盖（同一扫描面内的核对，不缩小面） | active Skill **56**（`skills/_index.yml`）、active Agent **9**（`agents/_index.yml`）、Pipeline **8**（`pipeline-templates/_index.yml` 的 active `path` 去 `tools/` 前缀 ∩ `readdirSync('pipeline-templates')` 的 `*.pipeline.json`，集合必须相等）；`skills/**` + `pipeline-templates/**` 递归 `.mjs` 共 **40**，按路径是否含 `test/` 段二分 → 活跃源码 **16** / 活跃测试 **24**（进入扫描面 **23**，扣除扫描器自身） |

**为什么是整树而不是「活跃目录白名单」**：attempt 2 把活跃源码限定为 `skills/shared/crctl/scripts/**.mjs`、活跃测试限定为该目录 `scripts/test/**`，于是 `tools@dddd0ad6` 上另有 **11 个活跃 MJS 落在面外**——`pipeline-templates/emit-registry.mjs`、`skills/requirement/requirement-register/scripts/promotion-bind.mjs`（+ 其 `scripts/test/promotion-bind.test.mjs`）、`skills/shared/crctl/adapters/{claude-code,cursor}/hooks/*.mjs`（3 个）、`skills/writeback/scripts/{lib,writeback-prd-sdd,writeback-tasks,writeback-traceability}.mjs`（4 个）+ `skills/writeback/scripts/test/writeback.test.mjs`。这 11 个文件在本 HEAD 上对两个退役名零命中（已核实），**不是迁移对象**；纳入面内是防回流。同类盲区还有按 `.mjs` 白名单必然漏掉的 `skills/shared/engineering-docs/scripts/src/**`（16 个 `.ts` 活跃源码）。因此活跃性不再由「是否被列举」定义，而由「是否被显式排除」定义——未被排除即在面内。

**硬失败（不静默降级）**：索引解析出 0 条 active、目录枚举为空、active 索引条目在磁盘上不存在或落在排除项内、Pipeline 索引与目录枚举集合不相等——任一发生即硬失败（`check-skill-matrix.mjs` 已有「空结构守卫」先例，CR-2026-012 教训）。索引与文件读取一律先 `replaceAll('\r\n', '\n')` 再 `split(/\r?\n/)`（仓库行尾纪律）；扫描结果按路径排序输出，保证失败信息可复现。

**3. 可审计排除：恰两项，且被断言固定**

| 排除项 | 命中文件数（本 HEAD） | 理由 | 固定方式 |
|---|---|---|---|
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 1 | 扫描器自身的退役名单 —— 加入两个字段名后该文件必然含被扫字符串 | 断言其仍含退役名单文本、且不在被扫描集合内 |
| `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（**精确路径，不用 `fixtures/**` 目录通配**） | 1 | 历史 traceability 证据，合法保留旧字段名 | 断言该精确路径含旧字段名、且只有它不在扫描面内 |

**为什么排除的夹具是精确路径而不是 `fixtures/**` 目录通配**（`review-tech-design` attempt 3 的 TD-BL-1 残留点，`sdd.yml` commit `f4e6cfd`）：同一目录下的 `digest-vectors/{expected.json,review-annotations-code.yml,test-report.md}` 不是历史证据，而是**活跃测试向量** —— `crctl.test.mjs`（`~L548-556`）直接读取它们做 canonical digest 一致性断言，`crctl.mjs`（`~L87`）把该目录声明为 Go 侧等价实现的固定共享向量（§11-2、§11-6）。它们不属于 PRD FR-11 允许排除的任何一类（历史 CR / 历史 traceability / 归档 delivery 证据 / changelog-migration 文档 / 扫描器自身名单）。目录级通配会把这三个活跃向量以及今后新增的任何活跃 fixture 一并排除，留下可扩张盲区；收窄为精确路径后，`fixtures/` 目录下除 `traceability-191k.yml` 外的全部文件默认在扫描面内（本 HEAD 共 3 个，对两个退役名零命中，见 §4.4-4 第 8 条）。

除上表两项外，扫描面不排除任何路径、目录或扩展名：`tools` 仓在本 HEAD 上没有含旧字段名的 changelog/migration 文档（PRD 允许的这几类排除在 `tools` 仓内只落为上述两项）；历史 CR 产物、历史 traceability 与归档 delivery 证据位于 KB 仓，不在 `tools` 整树枚举范围。

**排除面与枚举边界均被冻结**：`assert.deepEqual(EXCLUDED, [<扫描器自身>, 'skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml'])` 与 `assert.deepEqual(SKIP_DIRS, ['.git', 'node_modules'])`——两项排除都是精确路径、无任何模式匹配，因此**新增 fixture 文件不会被既有的某条排除顺手吞掉，默认入面**；反过来，任何新增排除或跳过目录都必须改测试并被评审看见，不存在「默默少扫一块」。

**4. 判定与正反用例**

- 纯谓词 `retiredHits(text, names)`（先 `\r\n → \n` 规范化，再大小写敏感的 `includes`）；`scanScope(files, names)` 返回命中文件列表。
- **零命中断言**：`scanScope(扫描面, RETIRED_RECOVERY)` 为空。
- **命中即失败的八条代表性用例**（每个派生根一条；取真实路径的真实文本，在内存中追加一行含 `recoverCommand` 的合成行，断言 `scanScope` 对同一路径判为命中）——第 2–6 行即 attempt 2 判 BLOCK 时落在面外的四个根（crctl adapter hook、requirement-register 生产/测试、writeback 生产/测试、`pipeline-templates/**`），第 7 行覆盖提示词面，第 8 行覆盖**本轮判 BLOCK 时被 `fixtures/**` 目录通配排除掉的活跃测试向量根**；既有迁移对象（`workspace-transactions.mjs`、`crctl.mjs`、7 个测试、4 份 SKILL.md）也在同一面内。证明范围不是恒真空断言，任一未列目录、未列扩展名的活跃文件回流旧名即失败：

| # | 派生根 | 代表性路径 |
|---|---|---|
| 1 | crctl 源码（含 `lib/`） | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` |
| 2 | crctl adapter hook | `skills/shared/crctl/adapters/claude-code/hooks/pretooluse-guard.mjs` |
| 3 | requirement-register 生产 | `skills/requirement/requirement-register/scripts/promotion-bind.mjs` |
| 4 | requirement-register 测试 | `skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs` |
| 5 | writeback 生产 + 测试 | `skills/writeback/scripts/writeback-prd-sdd.mjs`、`skills/writeback/scripts/test/writeback.test.mjs` |
| 6 | `pipeline-templates/**` | `pipeline-templates/emit-registry.mjs` |
| 7 | 活跃提示词（active Skill / active Agent） | `skills/cr/cr-archive/SKILL.md`、`agents/delivery-agent.md` |
| 8 | 活跃测试向量（`fixtures/` 内非历史文件） | `skills/shared/crctl/scripts/test/fixtures/digest-vectors/expected.json`、`skills/shared/crctl/scripts/test/fixtures/digest-vectors/review-annotations-code.yml`、`skills/shared/crctl/scripts/test/fixtures/digest-vectors/test-report.md` |

- **允许排除不误报**：唯一被排除的夹具文件（`traceability-191k.yml`）仍合法含旧名，断言 `retiredHits(排除项文本) === true` 且 `scanScope(扫描面)` 不含它；同目录其余三个文件断言相反（在面内且零命中）。两者并置才证明排除是刻意、精确且必要的，而不是「整目录一关了事」。
- **排除不隐形**：断言排除集合恰为上表两项精确路径 —— 新增排除必须改测试并被评审看见。
- **规模口径：报告值 + 结构性断言，不用脆弱等式**：不写 `scanSurface.length === 212`（日后任何新增文件都会造成假失败，反过来诱发「改数字了事」）；规模（212 / 40 / 16 / 24 / 56 / 9 / 8）写进断言消息作覆盖度报告，真实保证由四条结构性断言给出——(1) 三个 active 索引的全部条目存在于磁盘且在扫描面内、Pipeline 索引与目录枚举集合相等（索引条目落入排除项或缺失即硬失败）；(2) 八条代表性路径全部在扫描面内；(3) `EXCLUDED` 与 `SKIP_DIRS` 被 `deepEqual` 冻结（§4.4-3）；(4) 排除项恰为两条精确路径且不含任何通配，`fixtures/` 目录下未被排除的文件（本 HEAD 3 个 digest 向量）全部在扫描面内——**新增 fixture 默认入面，无需改测试即可被扫到**。

**跨仓边界（诚实口径）**：扫描运行在 `tools` 仓测试套件内，只能覆盖 `tools` 仓整树扫描面；`multica` 仓的 `cr-prompts-revised/delivery-agent.md` 与 KB 侧文档不在本扫描范围，其迁移由 §4.3 清单 + FR-14 有界盘点 + 本 CR 评审（`review-tech-design`/`review-code`）覆盖，不由工具机器证明。

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

### D-5 退役扫描复用既有机制 + 整树派生的扫描面（采用）

- **Context**：既有机制是 `node --test` 内的固定路径清单 + `includes` 断言；PRD FR-11 要求扫描范围为「活跃源码、活跃 Skill、活跃 Agent、Pipeline、活跃测试」，并允许排除历史证据/夹具/迁移文档/扫描器自身。该范围**已两次以同一方式咬人**：attempt 1 用手工清单，被「未覆盖其余活跃文件」判 BLOCK；attempt 2 改为按索引与活跃代码根派生，但把活跃源码限定为 crctl 的 7 个 `.mjs`、活跃测试限定为其 `scripts/test/**`，于是 `tools@dddd0ad6` 上另有 11 个活跃 MJS（`pipeline-templates/emit-registry.mjs`、requirement-register 的 production/test、3 个 crctl adapter hook、4 个 writeback production 脚本 + `writeback.test.mjs`）落在面外——「未列目录」被默认当成非活跃，漏项本身不可见。
- **Decision**：两个待退役字段名的扫描面改为**整树派生**（工作树全部文件，跳过 `.git` 与 `node_modules` 路径段）**减去恰两项被断言的精确路径排除**（扫描器自身、历史 traceability `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`），见 §4.4-2/§4.4-3；不再按目录或扩展名声明活跃性——**活跃性由「是否被显式排除」定义**。索引派生的 active Skill/Agent/Pipeline 集合降为一致性断言（条目必须存在于磁盘且落在扫描面内），规模只作覆盖度报告。`RETIRED_LEGACY`（CR-2026-041 的三个退役 Skill 名）保持既有显式范围不变（理由见 §4.4-1）。
- **Alternatives**：① 继续扩张手工清单 —— 已两次咬人，漏项不可见；② 只把代码面从 crctl 扩到 `skills/**/*.mjs` + `pipeline-templates/*.mjs`（评审给出的最小扩面）——仍是以扩展名/目录白名单声明活跃，同类盲区会重演（本仓已有 16 个活跃 `.ts` 不在 `.mjs` 白名单内，日后新增 `.js`/`.ps1` 或新目录同理）；③ 在 CI 里加 grep 步骤 —— 与既有测试机制并行成第二套扫描，违背「复用」。
- **Consequences**：新增活跃文件零成本进入面内，不因未列举而漏；排除用精确路径而非目录通配，故**同目录下的活跃向量与今后新增的 fixture 默认在面内**（这是 attempt 3 的唯一残留点，已收窄）；新增排除是显式且被断言的评审动作；代价是「零命中」从此覆盖整仓——今后若在 `tools` 落历史迁移/changelog 文档，必须显式加入排除表并被评审看见。历史 traceability 证据（精确路径一项）合法保留旧字段名（`RETIRED_LEGACY` 亦保留其显式范围）。

### D-6 消费者侧四类检查落在提示词合同（采用）

- **Context**：本仓没有执行 `recovery` 的代码消费者 —— 消费者是 Skill / Agent / 平台 Prompt（PRD §1.1、US-1）。
- **Decision**：四类缺失检查与固定判定顺序写在 `skills/shared/crctl/SKILL.md` 的「`recovery` 消费合同」小节（单一事实源），四个消费 Skill 与 `delivery-agent.md` 只引用该合同并声明本节点动作；生产者侧由构造器与测试保证形状合法。
- **Alternatives**：新增一个 `validateRecovery()` 生产代码函数 —— 无任何生产调用点（死代码），只为测试存在，与本 CR「不新增通用命令执行框架」的边界相冲。
- **Consequences**：AC-11 的验证方式是「提示词文本逐条核对 + 生产者形状断言 + 旧字段结构上不可回退」，在 §6.3 显式写明，不以伪造的运行期测试冒充证据。

### D-7 OpenWiki 页面由既有生成步骤产出，不手工编辑（采用）

- **Context**：`openwiki/operations/crctl-transactions.md` 是三处旧合同断言的活跃文档，其 frontmatter 的 `openwiki.source_paths` 恰好指向本 CR 迁移的四个源码文件；`tools/AGENTS.md` 的 OpenWiki 段明确「Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate」，`.github/workflows/openwiki-update.yml` 以 `openwiki code --update` 定时生成并开 PR（`add-paths: openwiki/AGENTS.md/CLAUDE.md/workflow`）。
- **Decision**：本 CR **不手工编辑**该页面。源码迁移与页面更新是同一个实施闭环：(1) 先改权威源码（§4.3）；(2) 在 `tools` 工作树内用同一生成命令（`openwiki` + `openwiki code --update`，provider/model 配置同 `openwiki-update.yml`）重新生成；(3) 核对生成结果——两个退役字段名零命中（按 §4.4 整树扫描面口径）+ 恢复合同描述为结构化 `recovery` + 生成 diff 不覆盖页面之外的人工内容；(4) 生成结果随本 CR 分支一并提交，生成命令与核对结论进入 `test-report.md` 证据。该步骤是 TASK 的完成条件；生成环境不可用（无 provider key / 无网络）时以环境阻塞上报，不得回退为手工编辑。
- **Alternatives**：① 手工改生成页 —— 违反 `tools/AGENTS.md` 约束，且下一次生成会覆盖，形成「手工维护 + 生成漂移」双源（本轮评审 BLOCK 的方案）；② 不迁移该页、只留 follow_up —— FR-8 要求文档单一事实源，旧合同描述留在活跃文档等于迁移不完整；③ 在 CI 加页面文本检查步骤 —— 与既有测试机制并行，且不能替代生成。
- **Consequences**：该页面回归「源码 → 生成器」单一回路；文档迁移结论由生成产物本身证明，不再有「手工迁移 + 后续漂移不算门槛」的降级口径；生成器对 `AGENTS.md`/`CLAUDE.md`/workflow 的附带改动不属本 CR 交付物（§9 `zero_diff` 优先，不纳入本 CR）。

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
| FR-8 | §4.3 README 原位迁移 + OpenWiki 生成闭环（D-7，不手工编辑）；同一份源码即生成来源，不新增第二套描述 | `README.md`、`openwiki/operations/crctl-transactions.md`（生成） |
| FR-9 | §4.5 结构断言模板 + 6 类 reason 向量 + 反脆弱快照规则 | 7 个测试文件 |
| FR-10 | §4.1 第 6 步（原位删除、不并排双写）+ §2.3 别名表（无 alias/shim/fallback） | 全量站点 |
| FR-11 | §4.4 扫描算法（分名退役名单 + 整树派生扫描面 + 两项按精确路径冻结的可审计排除 + 八条代表性命中用例） | `contract-scan.test.mjs` |
| FR-12 | §4.5 向量 3/4/5/6（参数边界、6 类用户输入、四类缺失、`executable` 安全） | 测试 + 提示词合同 |
| FR-13 | §2.2 不落盘 + §3.3「其它字段与错误码/exit code/txId/rollback/files 不变」+ §4.2 只改载体 | 全量 diff 约束 |
| FR-14 | §11 既有实现依赖清单即基线盘点；六类归档口径在本表与 §4.3 已落形，正式归档表由 `write-dev-plan` 产出 | `plan.md`（下游节点） |
| FR-15 | §9 `scope_out` 明列「不做双写/不留半迁移」；回滚＝整体回滚（回退上一完整 `tools` 版本或回滚本 CR） | §9 + 流程约束 |
| FR-16 | §1.1 范围表「不更新平台 DB」+ §8 Prompt 采纳影响 | 本 SDD + 交付汇报口径 |
| FR-17 | §2.4 指纹字段集 + §3.5 固定判定顺序与错误闭包 + §3.1 零副作用（纯数据） | `buildRecovery` + 提示词合同 |

### 6.2 复杂度与改动面

- 生产者 9 类 / 站点 11 处；CLI 投影 5 处；消费方提示词 5 个文件；文档 1 个（README 原位）+ 生成页 1 个（OpenWiki，由生成器产出，D-7）；测试 8 个文件。
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
  - 设计落点：§4.3 逐文件改法清单（4 Skill + 1 Agent + 1 文档 + 7 测试）+ D-7 的 OpenWiki 生成闭环。
  - 可观测结果：扫描面内旧字段名零命中（扫描）；生成页由生成器从迁移后的源码产出且三处旧合同断言归零；`multica` overlay 逐条核对；无 alias/shim/fallback。
  - 可达性说明：`multica` 与 KB 侧不在 tools 扫描范围（§4.4 跨仓边界），由 §4.3 清单 + 评审比对 diff 覆盖；生成页的证据是「生成命令 + 生成前后 diff + 页面零命中」三条（D-7）。
- **AC-06**（FR-11）
  - 设计落点：§4.4 扫描算法（退役名单分名分范围、整树派生扫描面 + 两项精确路径排除、索引一致性硬失败、八条代表性命中用例）。
  - 可观测结果：扫描面内命中即测试失败（含 attempt 2 漏掉的 11 个活跃 MJS 与 16 个活跃 `.ts`，以及 attempt 3 被目录通配排除的 3 个 `digest-vectors` 活跃向量）；每个派生根的代表性注入用例证明范围非恒真；唯一被排除的 `traceability-191k.yml` 仍含旧名且被判为排除（不误报），同目录三个活跃向量在面内且零命中；索引/枚举空结构与索引条目缺失硬失败（不静默降级）。
  - 可达性说明：扫描是纯文件读 + 字符串判定，无环境依赖；整树枚举与三个索引均为仓内既有依赖（§11）。
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
  - 设计落点：六类归档口径（producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence）+ §11 清单作为基线盘点；扫描范围本身由 §4.4 的派生规则从索引得出（与盘点口径一致）。
  - 可观测结果：`plan.md` 内存在一次有界搜索的六类归档表，且未新增持续观测机制。
  - 可达性说明：盘点在 `write-dev-plan` 节点执行；本 SDD 已按同一口径完成一次基线盘点（§4.3 + §11，行数/匹配次数口径见 §11 开头）。
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
- **SDD-CLOSE-05（契约扫描实现方式）**：复用既有机制的扩展点、整树派生扫描面（不以目录/扩展名白名单声明活跃）、两项按精确路径冻结的可审计排除（`fixtures/` 目录内只有历史 `traceability-191k.yml` 被排除，其活跃 digest 向量与新增夹具默认入面）、八条命中即失败用例与不误报的正反用例、索引一致性硬失败、分名分范围的既有名单不变式、跨仓边界 → §4.4 关闭。
- **SDD-CLOSE-06（逐文件改法与文案口径）**：11 个生产者站点 + 5 个 CLI/投影点 + 5 个提示词 + 1 个文档（README 原位）+ 1 个生成页（OpenWiki 由生成器产出并核对，D-7）+ 8 个测试的改法；错误消息与展示文案不得引用退役字段名、显示文本只能从 `recovery` 渲染 → §4.3 关闭（含「消息文本去旧名」两条）。

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
- 5 个活跃提示词的消费方式迁移（§8）+ 1 个文档原位迁移（`README.md`）+ 1 个生成页由既有生成步骤产出并核对（`openwiki/operations/crctl-transactions.md`，D-7）+ `skills/shared/crctl/SKILL.md` 新增「`recovery` 消费合同」小节。
- 7 个既有测试文件的结构断言迁移 + `contract-scan.test.mjs` 的退役名单/扫描面/正反用例扩展 + `shell: true`/`Invoke-Expression` 守卫断言。
- FR-1…FR-17、AC-01…AC-14 全部。

### scope_out

- 不新增通用命令执行框架、shell parser、quoting library、跨 shell renderer。
- 不改 `reviewLoop` / `archive` / `merge` / `checkpoint` / `writeback` 业务算法，不改错误码/状态转换/门禁语义。
- 不做双写兼容期、deprecated alias、migration shim、第二个删除 CR。
- 不改写历史 CR、历史 traceability、归档 delivery 证据、历史夹具精确路径 `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（该目录下 `digest-vectors/**` 三个活跃测试向量不在此列：它们在扫描面内，本 CR 不改其内容、只让它们被扫描保护）。
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

## 10. 术语硬化与边界场景验证

| 术语 | 进入哪一层 | 歧义/别名/边界风险 | 边界场景验证（至少一条） | 结论 |
|---|---|---|---|---|
| `recovery`（响应字段） | 接口契约 | 与内部恢复原语 `recoverWriteSet` / `recoverLedgerTransaction` / `recoverLedgerCommand`、与错误码 `TX_RECOVERY_CONFLICT` 同前缀不同层 | 构造器返回对象只含 5 个约定键；内部原语名零改动（`rg "recoverWriteSet"` 不变） | 命名冲突已记录：不合并、不改名；字段名指「恢复动作的结构化载体」 |
| `recoverCommand` → `recovery` | 接口契约 | PRD canonical term 与代码别名映射：旧名退役，无 alias | 活跃面扫描零命中（含 `fixtures/digest-vectors/**` 三个活跃向量）；唯一被排除的 `traceability-191k.yml` 仍含旧名且被判为排除 | 映射记录完毕；旧名为「已退役别名」，不保留读取路径 |
| `cwd` | 接口契约 | 与既有 `--workspace` / `ctx.installRoot` 语义重叠可能被误当作唯一权威 | ① 生产者侧的 `cwd` 与 `--workspace` 值同源（同一变量取两次，不各自计算）；② `buildRecovery` 省略 `cwd` 时对象不含该键（单测覆盖可选性边界） | `--workspace` 是 CLI 的权威解析入口（语义保留），`cwd` 是进程工作目录事实；二者不得出现不同来源 |
| `requiresTTY` | 接口契约 | 与既有错误码 `NOT_TTY` 的关系 | reset 恢复的 `requiresTTY === true`，非 TTY 下 CLI 自身 `NOT_TTY` 拒绝（既有行为不变） | 一致：`requiresTTY` 是「必须在可信交互终端执行」的结构化声明，不新增门禁 |
| `promptFor` | 接口契约 | 值名 vs CLI flag 名的映射歧义（`reason`/`plan`/`CR-ID`） | 三处取值名与目标入口在 §3.4 逐条固定；忽略时撞 `BAD_ARGS`（零副作用） | 规则已硬化：值名是逻辑名，按 §3.4 表映射到既有入口 |
| `executable` | 接口契约 | 与 `cr-test-plan/v1` 的 `executable` 同名词、不同对象 | 两处语义一致（均指非 shell 可执行入口），互为先例；测试计划 schema 零改动 | 同名同义，不构成冲突 |
| `args` | 接口契约 | 与 `cr-test-plan/v1` 的 `args` 同名词 | 同上；`recovery.args[0]` 为脚本路径（node 形态），测试计划 `args` 不含脚本路径 | 语义一致，形态差异在 §3.2 明确 |

**语义冲突裁决**：未发现 PRD canonical 语义与既有代码语义冲突的术语，无需在首次 `crctl advance` 前请求需求负责人澄清（本节点已完成该推进：`requirement-approved → tech-designing`）。

## 11. 既有实现依赖与事实

**计数口径（唯一，三个数字各自对应一条命令）**：在固定 HEAD 的仓库工作树根执行——

| 数字 | 命令 | 语义 |
|---|---|---|
| 文件数 | `rg -l "recoverCommand\|recover_command"` | 含 ≥1 次命中的 distinct 文件 |
| 行数 | `rg -c "recoverCommand\|recover_command"` 逐文件求和 | 含 ≥1 次命中的行（同一行多次命中只计 1） |
| 匹配次数 | `rg -o "recoverCommand\|recover_command"` 计数 | 全部 match 总数（同一行多次命中各计 1） |

口径固定项：大小写敏感（只退役响应字段名 `recoverCommand` / `recover_command`；内部局部变量 `checkpointRecoverCommand`（仅存在于 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 的 `mergeCr` 内，`~L1557`；`~L1570` / `~L1573` 取值）里的 `RecoverCommand` 不属退役名，随站点 4 结构化一并改写名称但不计入本盘点）、不加 `-w`、用 `rg` 默认的 `.git`/`.gitignore` 过滤（不用 `-uu`，不遍历被忽略目录与隐藏文件）。正文凡「X 文件 / Y 行 / Z 次」均按上表三项分别给值，不混用口径。计数文件集为该 commit 的 tracked 内容——在 CR 的 `tools` worktree（HEAD 同上、`git status` clean）上执行即为该集合；工作树内未跟踪文件不属该 commit，不计入（例：主检出里遗留的未跟踪 `skills/shared/crctl/scripts/reference/error-codes.md` 含 2 行 / 2 次，不进 16 / 72 / 87）。

另一套规模口径（§4.4-2 扫描面，同一工作树枚举）：`tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 工作树 214 文件 − 扫描器自身 1 − 历史 traceability 精确路径 `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` 1 = **扫描面 212 文件**；`skills/**` + `pipeline-templates/**` 递归 `.mjs` 共 **40**（活跃源码 16 / 活跃测试 24）；三个 active 索引条目数 **56 / 9 / 8**（条目全部存在于磁盘）；`fixtures/` 目录内 4 个文件中 **3 个在扫描面内**（`digest-vectors/**`，对两个退役名零命中）、**1 个被排除**（历史 `traceability-191k.yml`）。旧字段命中计数仍按上表三项口径，两者不混用。

盘点基线（本节开头口径重跑）：`tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` = **16 文件 / 72 行 / 87 次**；`multica@ab9609483d17db12117cb8e9adb2d896f413917d` = **3 文件 / 6 行 / 6 次**（其中 2 个文件是 `server/internal/governance/testdata/` 历史黄金数据，另 1 个是 `cr-prompts-revised/delivery-agent.md`）。以下为按正文首次出现顺序的依赖清单（D-7 与 §4.4 派生范围的事实源接在既有 17 项之后）：

1. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `registerCr` / `syncWorkspaceToTrunk` / `mergeCr` / `checkpointCr` / `applyWritebackAtomic` / `archiveCr` / `testCr` / `buildTestResponse` 的返回值与 `TxError.extra` 载体（本文件 23 行 / 25 次旧字段命中）；其中 `mergeCr` 内的局部名 `checkpointRecoverCommand`（`~L1557`，`~L1570` / `~L1573` 两个 `TxError` 的 `extra.recoverCommand` 取值来源）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 这些函数是全部恢复动作的生产者，其返回结构与 `extra` 字段名即本 CR 的迁移对象；`buildRecovery` 落在本文件内（D-3），因此本文件同时是唯一构造器的宿主。局部名 `checkpointRecoverCommand` 是站点 4（merge publication lag → `checkpoint`）的既有承载点：大小写敏感的退役名扫描对它零命中（不属退役名、不计入本盘点），但 `~L1570` / `~L1573` 两处 `extra.recoverCommand` 在本 CR 内同批改为 `extra.recovery`，该局部值随之由 shell string 改为 `buildRecovery(...)` 产出的结构化对象，旧名与旧串均不保留（§4.3 `mergeCr` 行同址）。
2. repo: `tools`
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `crIdForRecover`（`~L963`）、`cmdGate` pre-review 错配分支（`~L974`）、`cmdReviewLoopReset` 提交失败分支（`~L1906`）、`buildRegisterResult`（`~L2753`）、`cmdRegister` 输出对象双投影（`~L3304`）；同一文件内 `cmdReviewLoopReset` 的 `NOT_TTY` 前置校验（`~L1840`）与 `fail`/`ok` 输出信封契约（定义位置 `~L43`/`~L49`：错误 `{ error: {...} }` 走 stderr + exit 1，成功对象走 stdout）；`canonicalEvidenceDigest`（`~L87`）把 `test/fixtures/digest-vectors/` 声明为 Go 侧等价实现的固定共享测试向量（§4.4-3 排除收窄的事实依据）
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
   stable symbol/对象: `FORBIDDEN` / `RETIRED` / `ACTIVE_PATHS` 既有静态扫描机制与 `readFileSync + replaceAll('\r\n','\n') + includes` 判定；`skills/_index.yml` / `agents/_index.yml` / `pipeline-templates/_index.yml` 的 active 条目（`status` + `path`）是 §4.4-2 索引一致性断言（条目必须存在于磁盘且落在扫描面内）的事实源
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: FR-11 要求复用既有静态合同扫描机制——该文件即既有机制，本 CR 在其上按名分范围追加 `RETIRED_RECOVERY` 与整树派生扫描面（§4.4），不新建扫描器。既有 `RETIRED_LEGACY` 三个名字在活跃面内**合法存在**（`lint-prompts.mjs` 禁止名单、`crctl.test.mjs` / `lint-prompts.test.mjs` 用例样本、`CUSTOM.md` 台账引述），另有 `docs/` 下两份历史报告与历史夹具亦含这些名字（`rg -l` 本 HEAD 共 8 个文件）——故其范围必须保持既有显式 `ACTIVE_PATHS` 不变（整树扫描会对历史报告误报）。
6. repo: `tools`
   relative path: `skills/shared/crctl/scripts/test/{archive-tx,checkpoint-tx,merge-tx,register-tx,workspace-freshness,writeback-tx,crctl}.test.mjs`
   stable symbol/对象: 旧字段字符串断言（`result.recoverCommand.includes(...)`、`assert.match(r.json.recoverCommand, …)`、`assert.equal(r.stderr.error.recoverCommand, …)`、`recover_command`）；`crctl.test.mjs` 的 digest-vectors 用例（`~L548-556`）直接读取 `test/fixtures/digest-vectors/{expected.json,review-annotations-code.yml,test-report.md}` 三个文件做 canonical digest 一致性断言——这三个文件因此是活跃测试向量而非历史证据（§4.4-3 排除收窄的事实依据）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 这些断言是 FR-9「改为结构断言」的迁移对象；同时它们是 AC-02/AC-03/AC-07 的既有证据通道（恢复路径已可达）。
7. repo: `tools`
   relative path: `skills/shared/crctl/SKILL.md`
   stable symbol/对象: 命令面表格（`merge` / `archive` 行）对恢复字段的消费说明
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 该文件是 crctl 命令面的权威 Skill 文档，也是新增「`recovery` 消费合同」的落点（§8、D-6）。
8. repo: `tools`
   relative path: `skills/cr/cr-archive/SKILL.md`
   stable symbol/对象: Step 2/Step 3 结果分类表、输出模板「恢复」行、错误处置表（6 行 / 7 次旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `archive` 的清理/补发续跑语义依赖恢复动作，提示词必须改读结构化 `recovery`（FR-7）。
9. repo: `tools`
   relative path: `skills/sync/push-progress/SKILL.md`
   stable symbol/对象: Step 2 错误分流与错误处置表（2 行 / 3 次旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `checkpoint` 重跑口径依赖恢复动作（FR-7）。
10. repo: `tools`
    relative path: `skills/writeback/merge-feature-branch/SKILL.md`
    stable symbol/对象: `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` 行（1 行 / 1 次旧字段命中）
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: publication lag 的恢复入口（`extra.recovery`）是该 Skill 的既定分支，字段名变更须同步（FR-7）。
11. repo: `tools`
    relative path: `README.md`（§7「恢复与 `crctl status/next`」第 2 条）
    stable symbol/对象: 「中途失败：按输出的 `recoverCommand` 重跑同一条命令」的合同描述
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 使用方仓库最先读到的恢复合同说明，必须与代码同批迁移且不得新增第二套描述（FR-8）。
12. repo: `tools`
    relative path: `openwiki/operations/crctl-transactions.md`
    stable symbol/对象: frontmatter `invariants[1]`、正文「Durable Transaction Envelope → Recovery」条、「Change-Safety Guidance」第 3 条（3 行 / 3 次旧字段命中）；`openwiki.source_paths` 指向本 CR 迁移的四个 crctl 源码
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 该页面是三处旧合同断言的活跃文档，且是**生成物**：权威输入是 `source_paths` 指向的源码（本 CR 同批迁移），页面按 `.github/workflows/openwiki-update.yml` 的既有生成步骤重新生成后核对（D-7）。本 CR 不手工维护该页，不存在第二套描述。
13. repo: `multica`
    relative path: `cr-prompts-revised/delivery-agent.md`
    stable symbol/对象: 交付纪律段（`L27`「明确 `recoverCommand`」、`L44` 失败汇报项）
    commit SHA: `ab9609483d17db12117cb8e9adb2d896f413917d`
    依赖结论: 交付 Agent 的 owner 可复制提示词是 FR-7 指定的活跃消费者之一；平台 DB 内版本由 owner 另行部署（FR-16）。
14. repo: `tools`
    relative path: `agents/delivery-agent.md` 与 `agents/*.md`
    stable symbol/对象: 方法论包内的 Agent 提示词全集
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 全量检索确认这些文件**不含**旧字段名（故列入 `zero_diff`，不可借机改动）；`agents/dev-agent.md` 的「按 crctl 明示的恢复方向恢复一次」措辞不绑定字段名，语义在新合同下仍成立。
15. repo: `tools`
    relative path: `skills/shared/engineering-docs/templates/SDD-template.md`、`skills/develop/write-tech-design/SKILL.md`
    stable symbol/对象: 本 SDD 的章节与范围章节契约
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 本 SDD 的章节结构、`target-version` 继承与 §9 四字段约束来自该模板与 Skill，落地时必须符合。
16. repo: `tools`
    relative path: `.github/workflows/crctl-ci.yml`
    stable symbol/对象: 全量测试命令 `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`、Pipeline JSON 动态枚举（`readdirSync('pipeline-templates')` + 读 `skills/_index.yml` 求 active Skill 集合）、`writeback` 单测命令
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: AC-07 的验收命令与 §4.4 索引一致性校验的既有先例（按索引求 active + 目录动态枚举）均来自该文件；本 CR 不改 CI 配置。
17. repo: `tools`
    relative path: `ARCHITECTURE.md`
    stable symbol/对象: §3 代码地图（`lib/` 模块枚举与 `crctl.mjs` 职责）、§4 分层规则、§5 不变量（状态单一写者、零依赖、行尾纪律、状态机口径）、§8 维护规则
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 本 CR 的设计必须不违反上述不变量（构造器下沉 lib、CLI 单向依赖、零第三方依赖、行尾规范化、无新状态），且因未触发 §8 修订条件而不修该文档（D-3）。

18. repo: `tools`
    relative path: `AGENTS.md`（`<!-- OPENWIKI:START -->` 段与「单一事实源」表）
    stable symbol/对象: OpenWiki 段约束「scheduled workflow refreshes the repository wiki. Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate」；单一事实源表把 `skills/_index.yml`（Active Skill 清单）、`agents/_index.yml`（Active Agent 清单）、`pipeline-templates/_index.yml`（Active Pipeline 清单）指定为权威
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: D-7 的「不手工编辑生成页 + 由生成器产出并核对」与 §4.4-2 的「active 索引为唯一事实源」一致性断言均建立在该文件的两条约束上。
19. repo: `tools`
    relative path: `.github/workflows/openwiki-update.yml`
    stable symbol/对象: `Install OpenWiki`（`openwiki@0.2.3` + provider/model 环境变量）与 `Run OpenWiki`（`openwiki code --update --print`）两步；`add-paths: openwiki, AGENTS.md, CLAUDE.md, .github/workflows/openwiki-update.yml`
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 既有生成命令即本 CR OpenWiki 页面迁移的实施路径（D-7 第 2 步）；生成范围含 `openwiki/**`（FR-8 的目标页在内），本 CR 只取该范围内的生成结果，`zero_diff` 优先。
20. repo: `tools`
    relative path: `skills/_index.yml`、`agents/_index.yml`、`pipeline-templates/_index.yml`
    stable symbol/对象: 三个索引的 `status: active` 条目及其 `path` 字段（本 HEAD：Skill 56 / Agent 9 / Pipeline 8；Pipeline 索引的 path 带 `tools/` 前缀，派生时去前缀）
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: §4.4-2 索引一致性断言的唯一事实源（本 HEAD 实测 active 条目 56 / 9 / 8，条目全部存在于磁盘）；索引解析出 0 条 active 必须硬失败（不静默降级），Pipeline 索引与目录枚举集合不相等也硬失败。
21. repo: `ai-first-platform-docs`
    relative path: `AGENTS.md`（「tools 包的挂载方式」段与「读取顺序」）
    stable symbol/对象: crctl 规范入口 `node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs …`（Tools Root = `workspace.tools_package_path`，无回退）；「状态推进一律走 crctl」约束
    commit SHA: `7110880af2606d5a923dc99a1f355ceb2db19bc6`（本次修订落盘时的 `ai-first-platform-docs` worktree HEAD）
    依赖结论: D-1 选择 `node` + `args[0]` = 脚本绝对路径的对外依据（裸 `crctl` 不在 PATH，KB 侧规范入口就是 node 形式）；即 `recovery.args[0]` 的形态在知识库侧已有权威约定，不是本 CR 自创。

**旧字段命中分布（按本节开头口径重跑，用于复核上列条目）**：

| repo | path | 行 | 次 | 处置 |
|---|---|---|---|---|
| `tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 23 | 25 | 迁移（生产者 + 构造器宿主） |
| `tools` | `skills/shared/crctl/scripts/crctl.mjs` | 6 | 10 | 迁移（投影 + 错误面） |
| `tools` | `skills/shared/crctl/scripts/test/crctl.test.mjs` | 11 | 13 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/register-tx.test.mjs` | 4 | 4 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 3 | 4 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 3 | 5 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 2 | 2 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | 2 | 4 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | 1 | 1 | 迁移（测试） |
| `tools` | `skills/cr/cr-archive/SKILL.md` | 6 | 7 | 迁移（提示词） |
| `tools` | `skills/sync/push-progress/SKILL.md` | 2 | 3 | 迁移（提示词） |
| `tools` | `skills/writeback/merge-feature-branch/SKILL.md` | 1 | 1 | 迁移（提示词） |
| `tools` | `skills/shared/crctl/SKILL.md` | 2 | 2 | 迁移（提示词 + 新增消费合同） |
| `tools` | `README.md` | 1 | 1 | 迁移（文档，原位） |
| `tools` | `openwiki/operations/crctl-transactions.md` | 3 | 3 | 生成物：由生成器重新生成并核对（D-7） |
| `tools` | `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` | 2 | 2 | 排除（历史 traceability 精确路径，§4.4-3） |
| `multica` | `cr-prompts-revised/delivery-agent.md` | 2 | 2 | 迁移（提示词，owner 可复制版） |
| `multica` | `server/internal/governance/testdata/traceability-golden.yml` | 2 | 2 | 排除（历史黄金数据） |
| `multica` | `server/internal/governance/testdata/traceability-golden.json` | 2 | 2 | 排除（历史黄金数据） |

**待核实依赖**：无（上列各项均已按 repo / path / stable symbol / 结论在对应资源 HEAD 上核对；行数与匹配次数按本节开头的唯一口径重跑）。历史黄金数据 `multica/server/internal/governance/testdata/traceability-golden.{json,yml}` 与 `tools/skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` 属历史证据，按 FR-11 排除范围处理，不计入依赖。
