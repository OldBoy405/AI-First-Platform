---
spec-id: ai-first-platform
version: "0.43"
id: CR-2026-070-TASK-02
type: TASK
cr-ref: CR-2026-070
plan-ref: "change-requests/CR-2026-070/plan.md"
sdd-ref: "change-requests/CR-2026-070/sdd.md"
target-version: 0.43
title: Pi bash 默认 300 秒：解析点默认值 + 生效秒数传递 + schema 文案 + 既有测试框架内新增用例与本地构建
slug: pi-bash-default-timeout-300s
status: pending
estimate: 16h
depends-on: []
created: 2026-09-18T11:30:00+08:00
---

## 1. 任务描述

**目标**：在 Pi 包 `@earendil-works/pi-coding-agent` 的**版本化源码**内补齐 bash 内置工具「未显式传 `timeout` 时默认 300 秒」的默认值，并保证默认值生效时的超时错误文本报告**实际生效秒数**、schema 说明文案与默认值一致；同时在该仓既有测试框架内新增可机械核对的用例。

**背景**：现状 `resolveTimeoutMs(timeout)` 在 `timeout === undefined` 时返回 `undefined`，调用方据此不挂 `setTimeout` ⇒ 未显式传 timeout 的调用无上界（`dep-1` §1.4 事实 5、SDD §4.1 现状）。本 TASK 是 SDD 单元 B 的全部落点。

**输入条件**：

- **路线 = R-C、检出已就位**（plan §10）：`checkoutPath = C:\Users\GOBAO\Downloads\AI\pi-mono`，基线 = 上游 tag `v0.85.1` = `d981de1229ef899957bbe968bc8dcda02a21f477`（clone `--depth 1`；`git branch --show-current` 输出为空 = **detached HEAD**，工作树 clean）；
- 工具链已实测可用：`npm ci`（2 m 14 s）、`npm --prefix packages/ai run hydrate-model-data`（4.9 s，`packages/ai/src/providers/data/**` 被 .gitignore，缺失则 vitest 无法导入 model catalog）、`npm run build:offline`（9.7 s）；
- 源码锚点（基线实测）：`packages/coding-agent/src/core/tools/bash.ts` L22 `MAX_TIMEOUT_MS`、L25 `function resolveTimeoutMs(timeout: number | undefined): number | undefined`、L28 非法值错误、L32-33 超上限错误、L38-40 `bashSchema` 的 `timeout` 描述、L83-84 解析调用、L110/L116-118 `killProcessTree` + `setTimeout`、L136 超时信号 `` `timeout:${timeout}` ``、L355 工具层文本拼接；
- 既有测试面：`packages/coding-agent/test/tools.test.ts` 的 `describe('bash tool')`（含 `should respect timeout` 与 stub `operations` 的文本回放用例）；该文件在本机基线为 **77 passed / 4 failed**（4 项均为 Windows 环境类，与本 TASK 无关）⇒ 本 TASK 的用例**必须**落在新增文件内。

## 2. 涉及文件 / 模块

| 文件 | 动作 |
|---|---|
| `<checkout>/packages/coding-agent/src/core/tools/bash.ts` | 新增 `DEFAULT_TIMEOUT_MS = 300_000` 常量；`resolveTimeoutMs` 的 `undefined` 分支返回默认值；超时信号携带实际生效秒数；`timeout` schema 描述文案同步 |
| `<checkout>/packages/coding-agent/test/bash-default-timeout.test.ts` | **新增文件**：AC-5～AC-8 的用例（5 条，见 §4） |
| `change-requests/CR-2026-070/evidence/pi-vitest.log`（KB worktree） | 本 TASK 的用例执行原文（含 `--- stdout ---` / `--- stderr ---` 两段与退出码），供 TASK-04 引用其 sha256 |

**不改动**：`killProcessTree` 及其导入、AbortSignal 分支、`MAX_TIMEOUT_MS` / `MAX_TIMEOUT_SECONDS` 与档 1／2 的错误文本、`BashOperations` 接口签名与「工具入参 → `ops.exec`」的传参（`dep-1` §9 Z-3／Z-4）、`test/tools.test.ts` 等既有测试文件、已安装包目录（`{npm root -g}/@earendil-works/pi-coding-agent/**` 一律**不写**——AC-12 与 `dep-1` §6.2 明令）。

## 3. 实现要点

1. **默认值 owner 只有一处**（NFR-6）：

   ```ts
   const DEFAULT_TIMEOUT_MS = 300_000; // 300 seconds

   function resolveTimeoutMs(timeout: number | undefined): number | undefined {
       if (timeout === undefined) {
           return DEFAULT_TIMEOUT_MS;          // ← 唯一改动：原为 return undefined
       }
       if (!Number.isFinite(timeout) || timeout <= 0) {
           throw new Error("Invalid timeout: must be a finite number of seconds");   // 逐字不变
       }
       const timeoutMs = timeout * 1000;                                            // 逐字不变
       if (timeoutMs > MAX_TIMEOUT_MS) {
           throw new Error(`Invalid timeout: maximum is ${MAX_TIMEOUT_SECONDS} seconds`); // 逐字不变
       }
       return timeoutMs;                                                            // 逐字不变
   }
   ```

   - **保留**返回类型注解 `number | undefined` 与调用点既有的 `if (timeoutMs !== undefined)` 分支（SDD §4.1 性质 2：默认值让该分支对「未传」调用首次可达，正是 AC-6 的取证对象）；不重排判定顺序、不新增分支；
   - `dep-1` §3 FR-2 判定顺序五档与 SDD §3.1 边界值表逐档不变（非法值/超上限判定仍发生在**启动进程之前**）。

2. **超时错误文本的实际生效秒数**（SDD §4.2 A2/DEC-4）：把 L136 的信号值由「调用方原始入参」改为「实际生效值」，**不**在 `ops.exec` 调用点回填（避免把默认值外泄给自定义 operations、避免校验点前移）：

   ```ts
   throw new Error(`timeout:${timeout === undefined ? DEFAULT_TIMEOUT_MS / 1000 : timeout}`);
   ```

   - 显式合法值 v 走**原值本身**（不经 `v * 1000 / 1000` 往返，`dep-1` NFR-1 在全值域字面成立）；未传时文本首次有意义（`Command timed out after 300 seconds`）；工具层 `startsWith("timeout:")` 的解析与文本模板**零 diff**。

3. **schema 文案同步**（`dep-1` AC-5 的 S-4 核对点）：`timeout` 的描述改为与默认值一致的措辞，例如 `Timeout in seconds (optional, defaults to 300 seconds)`；**不得**再出现 `no default timeout`。不改 schema 的类型、不新增字段。
4. **S-6 取舍（不导出模块私有符号）**：`resolveTimeoutMs` 保持**不导出**（`bash.ts` 内私有，`dist/core/tools/bash.d.ts` 零命中）⇒ 测试从**工具入口**取证：`createBashTool(cwd)`（本地执行路径）与 `createBashToolDefinition(cwd)`（schema 面）。**禁止**为了测试而 `export` 该函数或改动 `.d.ts` 构建产物（会改模块公开面，超出本 CR 批准范围）。
5. **用例与假时钟的可行形态（本节点已探针实测，见 plan §0.4）**：
   - 未传 timeout 时本地执行路径**不挂任何计时器**（基线捕获集为空 ⇒ 缺陷本体）；显式 `timeout: 300` 时调度 `300000` ms 计时器，触达后抛 `Command timed out after 300 seconds`；
   - 因此用例以「捕获解析点调度的计时器并触达」为等价于「假时钟推进 300 秒」的观测动作，可直接复用该可行形态（`vi.spyOn(globalThis, 'setTimeout')` 记录 `{delay, fn}` 并保留真实调度 → 轮询到 `delay === 300000` → 手动触达 `fn()` → 断言 rejection 文本）；也可改用 `vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })` + `advanceTimersByTimeAsync(300_000)`，但必须断言**同样两条可观察事实**（调度 300000 ms + 文本 `Command timed out after 300 seconds`）；
   - 长任务子进程用 `process.execPath -e "setInterval(() => {}, 1000)"`（不真实等待 300 秒，`dep-1` §5 补充判定口径）。
   - **夹具必须自带兜底清理（plan R-10）**：长任务夹具及其后代 PID 必须在 `finally`／`afterEach` 内做**有界 kill**（先回收后代再回收父；`tasklist`／`ps` 有界轮询确认不存在，轮询上界 ≤10 s），且**独立于**被测 `killProcessTree()` 是否生效——红灯迭代、断言失败与异常路径上不得把该进程留在原地（残留会使作者 run 的进程树／管道不闭合 ⇒ run 不结算、后续委派排队，本 CR 来源 Issue AIFI-33 已有同类实测）。
6. **提交（落点在既有 detached HEAD 上，本 TASK 不建分支）**：受控 git 入口**不提供任何可创建分支的形态**——`skills/shared/controlled-shell/rules.json` 的 `branch` 只有 `^(-d|-D) \S+$` 与 `^--show-current$`、`checkout` 形态 `^[^-]\S*$`（禁一切 flag，`-b` 不可用）、`-c`／`-C` 在 `forbiddenFlags` 内，且 `crctl git switch` 实测返回 `FORBIDDEN_SUBCOMMAND`；同时 AGENTS.md 与本阶段 Agent 合同禁止原生 git，Pi 检出又不属 CR worktree 集合（DEC-3）⇒ 无受控路径可建分支（评审 B-1）。因此：在检出现有 detached HEAD（tag `v0.85.1` = `d981de12…`）上**直接提交**——`crctl git add <两个文件路径> --cwd <checkoutPath>` 与 `crctl git commit -m '[cr] …' --cwd <checkoutPath>`（两者均为白名单 shape；detached HEAD 上的 commit 合法，提交后 HEAD 前移、不产生分支），提交形态记入 `pi-source.json#branch` = `detached@v0.85.1`（取值口径见 TASK-04 §3.5／§6）。检出非 CR 仓，不进 checkpoint 面（DEC-3）。

## 4. 验收条件

新增文件 `test/bash-default-timeout.test.ts`，`describe('bash default timeout')` 下**恰 5 条**用例（标题逐字如下，`cmd-06` 按 verbose 输出的断言名核对）：

| # | 用例标题（逐字） | 断言（可机械核对） |
|---|---|---|
| 1 | `no timeout uses the 300 second default` | 经 `createBashTool(cwd)` 调 `execute(id, { command })`（**不传 timeout**）⇒ 本地路径调度延迟恰 `300000` ms 的计时器；触达该回调后 rejection 文本恰为 `Command timed out after 300 seconds`（默认值生效＝与显式 `timeout: 300` 同分支同文本，`dep-1` §1.3.3 等价性） |
| 2 | `default timeout reports 300 seconds and kills the process tree` | 命令启动一个**带后代**的子进程（后代 PID 写入临时文件）→ 触达 300000 ms 计时器 → 断言：① rejection 文本含 `Command timed out after 300 seconds`；② 轮询（有界，≤10 s）父 PID 与后代 PID 均**不存在**（Windows：`tasklist /FI "PID eq <N>" /FO CSV`；POSIX：`ps -p <N>`），即复用既有 `killProcessTree(child.pid)`（AC-6，不新增清理代码） |
| 3 | `explicit timeout 1200 is not overridden` | `execute(id, { command: <快速命令>, timeout: 1200 })` ⇒ 调度延迟恰 `1200000` ms（默认值不覆盖显式值）；`timeout: 1200` 超时场景的文本为 `Command timed out after 1200 seconds` |
| 4 | `invalid and over-limit timeouts keep existing errors before spawn` | `0` / `-1` / `NaN` / `Infinity` ⇒ `Invalid timeout: must be a finite number of seconds`；`2147484` ⇒ `Invalid timeout: maximum is 2147483.647 seconds`；两者**均不启动进程**（spawn 计数为 0）；AbortSignal 提前取消 ⇒ `Command aborted`（逐字不变） |
| 5 | `schema description matches the default` | `createBashToolDefinition(cwd).parameters.properties.timeout.description` ⇒ 为字符串、不含 `no default timeout`、且与 300 秒默认值一致（含 `300`） |

**执行命令**（在 `<checkout>/packages/coding-agent` 下）：

```text
node <checkout>/node_modules/vitest/vitest.mjs run test/bash-default-timeout.test.ts --reporter=verbose
```

**通过判据**：exit 0、`Tests 5 passed`、5 条标题逐字出现在 stdout（`cmd-06` 按此 5 条断言名做活体复跑）。

**构建与交付面判据**：

| # | 验收步骤 | 期望 |
|---|---|---|
| 6 | `<checkout>/packages/coding-agent/src/core/tools/bash.ts` 的改动只含 §3 的四处（常量、undefined 分支、信号值、schema 文案），`killProcessTree`／AbortSignal／上限常量／档 1／2 文本零改动 | 逐字核对（AC-8／Z-4） |
| 7 | 根目录 `npm run build:offline` | exit 0，产出 `packages/coding-agent/dist/bundle`（构建产物不进交付 diff） |
| 8 | `git diff --name-only d981de1229ef899957bbe968bc8dcda02a21f477`（`crctl git … --cwd <checkout>`） | 恰好两个路径：`packages/coding-agent/src/core/tools/bash.ts`、`packages/coding-agent/test/bash-default-timeout.test.ts`（AC-12 的文件集合面） |
| 9 | 已安装包未被触碰 | `{npm root -g}/@earendil-works/pi-coding-agent/dist/core/tools/bash.js` 的 sha256 与 plan §0.4 基线一致且仍含 `no default timeout`（AC-12 负向） |

## 5. 完成标志

1. 检出内**存在含上述两个文件的 `[cr] ` 前缀提交**（提交直接在既有 detached HEAD（tag `v0.85.1` = `d981de12…`）上产生，**不建分支**），检出 HEAD = 该提交，工作树 clean（除 gitignored 的 `node_modules`／`dist`／`providers/data`）；
2. 验收条件 1～9 全部满足（1～5 由本 TASK 实跑，`Tests 5 passed`；6～9 逐条核对）；
3. `change-requests/CR-2026-070/evidence/pi-vitest.log` 落盘（用例执行原文：命令、退出码、`--- stdout ---` 段含 5 条断言名、`--- stderr ---` 段），供 TASK-04 记入 `pi-source.json#testLogSha256`；
4. 本 TASK 已在 `tasks/_index.yml` 登记 `done`（工程纪律 8）；
5. **完成边界**：到「源码侧实现落盘 + 用例全绿 + 本地构建成功 + 日志留证据」为止；**不**包含安装/替换运行环境 PATH 上的 `pi`（CR 合并之后，运行环境维护）、**不**包含 fork/PR/发布、**不**包含 `review-code`／`merge`／回写（CR-2026-057 FR-10）。

## 6. 接口契约

**产出**（Pi 包内部契约；逐字对齐 SDD §3.1／§4.1／§4.2）：

```ts
// packages/coding-agent/src/core/tools/bash.ts
const DEFAULT_TIMEOUT_MS = 300_000;                                     // number，唯一 owner
function resolveTimeoutMs(timeout: number | undefined): number | undefined;
//   行为契约：undefined → 300_000 | v 非有限数或 ≤0 → throw Invalid timeout: must be a finite number of seconds
//             | v*1000 > MAX_TIMEOUT_MS(=2_147_483_647) → throw Invalid timeout: maximum is 2147483.647 seconds
//             | 其余 → v*1000；单位为毫秒，秒→毫秒换算只此一处
const bashSchema = Type.Object({ command: Type.String(), timeout: Type.Optional(Type.Number({ description: <含 300 秒默认值的措辞> })), ... }); // 形状不变，仅 description 文案
// 超时信号（工具层解析点零 diff）：throw new Error(`timeout:${<实际生效秒数>}`)
```

**消费**：

| 消费方 | 用法（签名逐字） |
|---|---|
| `createLocalShellOperations(...)` 内的本地执行路径 | `const timeoutMs = resolveTimeoutMs(timeout);` → `if (timeoutMs !== undefined) { timeoutHandle = setTimeout(() => { timedOut = true; if (child.pid) killProcessTree(child.pid); }, timeoutMs); }`（既有调用点，本 TASK 不改其结构） |
| `createBashToolDefinition(cwd, options?)` → `createShellToolDefinition(cwd, bashToolConfig, options)`，`parameters: bashSchema` | 测试经 `createBashTool(cwd)` / `createBashToolDefinition(cwd)` 取证（S-6 取舍：不直接 import 私有函数） |
| 工具层错误文本拼接（`startsWith("timeout:")` 分支） | 逐字不变：`Command timed out after <秒数> seconds` |

**AC-6 的 daemon PID 面子项（显式登记，非静默漏项）**：SDD §6.2 的 AC-6 行把「Multica daemon PID 前后一致」列为可观测结果，但本 TASK 的验收面是 Pi 内置 bash 工具进程（`createBashTool(cwd)` 的本地执行路径），**不启动、不接触任何 daemon**（daemon 与 `bash.ts` 无调用关系）。故该子项在本 TASK 内**不适用（N/A，有据）**：判据落在父/后代 PID 不存在与既有 `killProcessTree(child.pid)` 路径（§4 用例 2，`cmd-06` 活体复跑），daemon 生命周期稳定性由本 CR「不启停／不重启任何共享服务」的边界保证，不为其新增观测设施（I5）。
| PowerShell 内置工具 | 经同一 `resolveTimeoutMs` 与同一 `bashSchema` 共享默认值（DEC-2 的显式后果，`scope_in` 第 5 项；**不**为它另造验收面） |

**不消费**：`BashOperations` 接口与自定义 `operations` 路径（B-2、Z-3）——默认值只在**内置本地执行路径**内解析，传给 `ops.exec` 的仍是工具原始入参。
