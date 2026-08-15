---
id: CR-2026-040-sdd
type: SDD
cr-ref: CR-2026-040
title: tools CR 生命周期最小优化 3/5 — 结构化测试闭环技术设计
status: draft
created: 2026-08-15T11:20:00+08:00
updated: 2026-08-15T11:20:00+08:00
---

# 1. 架构概览

## 1.1 当前实现与问题定位

目标代码仓是 Tools，目标基线为当前 Tools Root 的 `custom/main`。该仓的 `ARCHITECTURE.md` 已存在，本 CR 不修改它。当前测试入口位于 `skills/shared/crctl/scripts/crctl.mjs#cmdTest`，实际行为为：

1. 从 `flags.cmdList` 读取一个或多个 shell 命令字符串；
2. 以 `spawnSync(command, { shell: true })` 执行；
3. 逐条写入 `test-evidence/cmd-NN.log` 和 `.crctl/audit.log`；
4. 重新生成 `test-report.md`，覆盖已有机器区和人工分析内容；
5. 以进程 exit code 表达测试是否全部通过。

现有 `skills/shared/crctl/scripts/lib/durable-tx.mjs` 已提供 journal envelope、目录锁、durable write-set、第三值检测和恢复；`workspace-transactions.mjs` 已承载 `register`、`merge`、`checkpoint`、`writeback`、`archive` 等业务事务。当前没有测试业务事务，也没有结构化测试计划或测试结果到 `traceability.yml#tests` 的统一原子发布。

## 1.2 目标架构

```text
Agent
  -> 选择 code-implementation Pipeline / write-test-report / review-code
Pipeline
  -> implement-code
  -> write-test-report
       -> 生成临时 cr-test-plan/v1
       -> 调用一次 crctl test
       -> 只写 test-report marker 后分析区
  -> push-progress
  -> review-code
       -> 只读取最终测试证据，不重新执行测试
  -> post-review push-progress
  -> human approval

crctl CLI
  -> 解析 test 子命令参数
  -> resolve workspace / CR / Tools Root
  -> 调用 workspace-transactions.testCr()
  -> 输出结构化业务结果或技术错误

workspace-transactions.testCr
  -> 只读预检 plan / repo / cwd / owner / state / marker
  -> 运行阶段：spawnSync(executable, args, { shell: false })
  -> 暂存原始日志到非 authority 临时目录
  -> 记录阶段：构造 report machine zone / tests projection / review-loop
  -> 复用 durable-tx 的 test journal + recoverable write-set 一次发布

durable-tx
  -> 提供既有 journal / lock / write-set / recovery 原语
  -> 新增 test payload 槽位和 test 锁 scope
  -> 不理解测试业务、TASK 覆盖或评审结论
```

执行和记录是同一个公共 `crctl test` 接口内部的两个顺序阶段。运行阶段不创建 durable journal、不持有账本写锁；记录阶段才创建既有事务，并将所有机器事实一次性提交。

## 1.3 模块职责与深模块边界

| 模块 | 接口/职责 | 明确不拥有 |
|---|---|---|
| Agent | 根据 `crctl next` 和职责选择 Pipeline/Skill，传递 CR 上下文 | 状态机、Git 算法、测试命令表、受控文件写入 |
| Pipeline | 节点顺序、输入传递、测试/代码 reviewLoop、失败中止 | `spawnSync`、事务、YAML、日志和账本算法 |
| `write-test-report` | 依据 TASK 与实现输出选择正式命令，生成临时 plan，调用 `crctl test`，维护 marker 后业务分析 | machine zone、traceability tests、review-loop、CAS、事务和命令执行 |
| `review-code` | 读取真实 diff、最终报告、digest、日志和 TASK/SDD，作 LLM 评审判断 | 重新执行 lint/test/build、修改测试证据 |
| `crctl.mjs` | 参数解析、状态/owner 前置校验接线、调用深接口、结构化输出 | 测试业务判断、事务内部算法、人工评审结论 |
| `workspace-transactions.mjs` | `testCr` 的 plan 校验、执行、结果建模和原子发布编排 | LLM 判断、Pipeline 路由、独立 CLI、第二事务框架 |
| `durable-tx.mjs` | 既有 test journal、锁、write-set 和恢复 | 测试发现、命令语义、报告内容判断 |
| 版本化脚本 | 本 CR 不新增脚本；后续仅承载确定性文档转换 | 状态推进、测试运行、人工审批 |
| README | 本 CR 不复制执行算法，只保留入口和权威链接 | CLI 参数细节、事务状态机、错误矩阵 |

`workspace-transactions.testCr` 是本 CR 的深模块：调用方只掌握 CR、workspace、临时 plan 和结构化结果；计划解析、worktree containment、argv 执行、日志、机器报告、traceability、review-loop 和可恢复发布均隐藏在其实现中。删除该模块会使上述复杂度重新散落到 Skill、Pipeline 和测试调用者，因此该 seam 有实际 leverage。

## 1.4 改动范围

实现期预期修改：

- `skills/shared/crctl/scripts/crctl.mjs`：保留 `test` 子命令，改为解析 `--plan` 并调用 `testCr`；删除 `--cmd`/shell 字符串执行路径。
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：新增测试计划解析、执行结果建模、marker 解析和 `testCr` 业务事务编排；复用现有 repository resolver、`readCrMdStatus`、hash 和 transaction 原语。
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`：在既有 journal/lock/write-set 模型中增加 `test` op/payload，复用同一恢复实现，不新增事务框架。
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：增加结构化 plan、argv 安全、结果分类、report/digest 和重复执行测试。
- `skills/shared/crctl/scripts/test/fault-harness.test.mjs`：增加 test 记录阶段故障恢复与零半状态测试。
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`：更新测试节点和 reviewLoop 的静态契约断言。
- `skills/shared/crctl/SKILL.md`：登记新的 `crctl test --plan` 输入、输出和失败语义。
- `skills/develop/write-test-report/SKILL.md`：删除 `--cmd`/直接 traceability 写入说明，改为临时 plan + `crctl test` + marker 后分析。
- `skills/develop/review-code/SKILL.md`：删除无条件重新执行测试的第二入口，改为读取 canonical 证据并在缺失/漂移时 blocker。
- `pipeline-templates/code-implementation.pipeline.json`：收缩测试和代码评审节点 prompt，保留既有 replayNodes 与 checkpoint 顺序。

不修改 `dir-graph.yaml` 状态机、`gates.json` 状态门禁、Agent/matrix、README、版本化 writeback 脚本、Multica 或其他生命周期切片。

# 2. 数据模型

## 2.1 结构化测试计划

临时 plan 文件由 `write-test-report` 写入 `.crctl/tmp/test-plan.json`，只作为一次调用输入，不进入 CR authority。`crctl` 读入后立即规范化 CRLF 为 LF，并按固定 schema 校验：

```ts
type CrTestPlan = {
  schema: "cr-test-plan/v1";
  commands: CrTestCommand[]; // non-empty
};

type CrTestCommand = {
  repo: string;           // dir-graph active repository id
  cwd: string;            // repo CR worktree-relative, default "."
  executable: string;     // non-empty executable name/path fragment
  args: string[];         // argv; empty allowed
  timeoutSeconds: number; // positive integer
};
```

计划不得包含 shell 字符串、`command` 字段、环境变量覆盖、pipe、redirect、`continueOnError`、absolute cwd、status、owner、attempt、日志路径或 traceability payload。允许的 `repo` 必须来自当前 workspace `dir-graph.yaml#repositories` active 项，cwd 解析后必须位于该 repo 的 `requirement/{CR-ID}` worktree 内。

## 2.2 Command canonicalization

计划 digest 只绑定规范化的命令集合，不绑定临时文件路径、执行时间、模型、owner、stdout/stderr 或本地绝对路径：

```js
const commandSubject = {
  schema: "cr-test-plan/v1",
  commands: plan.commands.map(({ repo, cwd, executable, args, timeoutSeconds }) => ({
    repo,
    cwd: cwd || ".",
    executable,
    args,
    timeoutSeconds,
  })),
};
const commandDigest = sha256(JSON.stringify(commandSubject));
```

`JSON.stringify` 使用固定对象键序和数组顺序；不对 commands 排序，因为计划顺序就是执行顺序。所有字符串已在 LF 规范化 plan 上解析。报告机器区保存完整规范化 command 对象和 `command-digest`，不另存 canonical `plan.json`。

## 2.3 Command result

每条命令的结果只由 `crctl` 生成：

```ts
type CrTestResult = {
  repo: string;
  cwd: string;             // workspace-relative POSIX path
  executable: string;
  args: string[];
  timeoutSeconds: number;
  exitCode: number | null;
  signal: string | null;
  timedOut: boolean;
  started: boolean;
  log: string;             // CR-relative POSIX path
};
```

`started=false` 只用于技术失败诊断，不进入业务 block 报告；已启动命令的 non-zero/timeout 进入 `status: block`。计划校验、executable 启动、repo/cwd 解析和事务错误不生成新的 canonical attempt。

## 2.4 `test-report.md` machine zone

机器区由 `crctl` 生成，形式固定为：

```yaml
---
cr: CR-2026-040
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-15T..."
command-digest: <64-hex>
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, test/example.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-01.log
---

# 测试报告 · CR-2026-040

<!-- crctl:analysis-below -->
```

上述字段和 marker 之前的全部内容是 crctl authority，实际输出必须使用现有安全 YAML scalar 渲染器生成合法 YAML。marker 之后原样视为 analysis zone。

每次新的完整 attempt 使用固定的 `cmd-NN.log` 目标路径，使报告只引用当前 canonical 结果；旧日志若不在当前 command 集合中不被 traceability 消费。报告不复制完整 stdout/stderr。

## 2.5 Traceability tests projection

`change-requests/{CR-ID}/traceability.yml#tests` 只保存最小机器摘要，完整 command 结果和分析保留在 test report：

```yaml
tests:
  report: change-requests/CR-2026-040/test-report.md
  status: pass
  tester: Ray
  owner-assigned-at: "2026-08-14T19:45:43+08:00"
  generated-at: "2026-08-15T..."
  command-digest: <64-hex>
  review-loop: write-test-report
```

写入时保留 traceability 的其他顶层段；`tests` 缺失时新增，`tests` 不是映射、报告路径不一致或已有机器字段形状无法证明时硬失败。测试命令数组不复制到 traceability，避免第二份事实源。

## 2.6 Review-loop 与 test journal

review-loop 继续使用既有 `change-requests/{CR-ID}/review-loop.yml` schema，`write-test-report` 作为 loop key。一次完整运行完成后才递增当前 cycle 的 attempt；非零测试结果也会记录一次 `block` attempt。

在既有 `durable-tx` journal envelope 中增加 `test` payload 槽位，不新增 journal 格式：

```json
{
  "v": 1,
  "op": "test",
  "cr": "CR-2026-040",
  "phase": "prepared|written|complete",
  "graphDigest": "...",
  "inputDigest": "<plan + result facts>",
  "test": {
    "targetRoot": "<CR worktree>",
    "commandDigest": "...",
    "attempt": 1,
    "entries": ["test-report.md", "test-evidence/cmd-01.log", "traceability.yml", "review-loop.yml"]
  }
}
```

真实内容通过既有 write-set blobs 保存，journal 不保存 stdout/stderr 全文。运行阶段不创建 journal；只在完整计划完成并准备发布时创建。若记录阶段中断，下一次同命令先恢复该 test transaction；若中断发生在运行阶段且没有 journal，临时结果丢弃并重新执行完整计划。

# 3. 接口契约

## 3.1 CLI 外部接口

```text
crctl test <CR-ID> --plan <workspace-relative-or-absolute-temp-json> --workspace <knowledge-base-worktree>
```

`--plan` 只允许指向当前 workspace 内的非 authority 临时目录（推荐 `.crctl/tmp/test-plan.json`）；`--cmd`、`--cwd`、`--timeout` 不再接受。CR-ID、workspace 和 Tools Root 仍由既有 CLI 解析器和 `dir-graph.yaml` resolver 提供。

成功时 stdout 返回 JSON，进程 exit code 为 0，包括业务测试失败：

```ts
type TestResponse = {
  op: "test";
  cr: string;
  status: "pass" | "block";
  commandDigest: string;
  attempt: number;
  commands: CrTestResult[];
  report: string;
  traceability: string;
  reviewLoop: string;
  changed: boolean;
  recoverCommand: string;
};
```

`status:block` 是已完成执行的业务结果，Pipeline 据此路由；schema/path/executable/transaction/CAS 错误通过现有 `fail(code, message, extra)` 输出 stderr JSON、非零退出。技术错误不产生新的 canonical attempt。

## 3.2 内部深模块接口

`workspace-transactions.mjs` 新增一个业务处理器：

```ts
export async function testCr(ctx, {
  cr,
  workspace,
  planPath,
}) -> Promise<TestResponse>
```

该接口内部完成 state/owner 校验、计划加载、repository resolver、执行、机器区构造、traceability/review-loop 投影和 test journal/write-set。CLI 不传入执行器、状态、owner、attempt、logs、digest 或 output paths。

内部纯函数使用最小 seam：

```ts
parseTestPlan(raw, ctx, cr) -> NormalizedPlan
canonicalCommandSubject(plan) -> { subject, digest }
runTestPlan(plan, ctx, cr) -> { results, tempLogs }
parseAnalysisMarker(existingReport) -> { machinePrefix, analysisSuffix }
renderTestMachineReport(input) -> string
renderTestsTraceability(existing, input) -> string
```

这些函数不成为新的公共命令或插件接口；测试通过同一 CLI seam 和少量纯函数直接覆盖。

## 3.3 `write-test-report` Skill 接口

Skill 接收 `cr_id`、`source_node`、`tester` 和可选 `self_repair_attempt`，执行：

1. 读取 CR/PRD/SDD/TASK 和 implement-code 输出；
2. 生成 `.crctl/tmp/test-plan.json`；
3. 调用一次 `crctl test --plan ...`；
4. 根据返回的机器结果在 marker 后更新 TASK 覆盖、未覆盖风险和结果分析；
5. 返回 `status`、`blockers`、`repair-target=implement-code`、attempt 和分析路径。

Skill 不直接编辑 machine zone、traceability tests 或 review-loop。分析区写入失败时返回技术失败，Pipeline 当前节点中止；已发布的机器证据保留，重试时不改变旧 machine zone 直到下一次完整 `crctl test` 成功。

## 3.4 Pipeline contract

`code-implementation.pipeline.json` 保持现有节点数量和 reviewLoop 最大 3 次，仅修改 prompt 的职责描述：

- 测试节点：`implement-code -> write-test-report`，测试 Skill 自己构造 plan 并调用 `crctl test`；`status=block` 回到 implement-code；技术异常 abort。
- 代码评审节点：读取最终 `test-report.md`、日志和 digest，不执行命令；block 时按现有 `[implement-code, write-test-report, push-progress, review-code]` 重放。
- 代码评审 PASS 后仍调用现有 `push-progress`，phase 非 complete 不进入 human approval。

Pipeline 不传 `--cmd`、命令数组、traceability payload、review-loop 数值或 test journal 参数。

## 3.5 错误语义

| 错误/结果 | 类型 | 行为 |
|---|---|---|
| `TEST_PLAN_NOT_FOUND` | 技术错误 | 零 canonical 变化，修复临时 plan 后完整重试 |
| `TEST_PLAN_SCHEMA_INVALID` | 技术错误 | 零 canonical 变化，指出字段和路径 |
| `TEST_REPO_NOT_FOUND` / `TEST_REPO_INACTIVE` | 技术错误 | 拒绝未声明/inactive repo |
| `TEST_CWD_ESCAPE` | 技术错误 | 拒绝 absolute、`..`、跨 worktree 或 symlink escape |
| `TEST_EXECUTABLE_INVALID` | 技术错误 | 命令未启动，零 canonical 变化 |
| `TEST_LOOP_EXHAUSTED` | 技术错误 | 不运行计划，不新增 attempt |
| `TEST_MARKER_INVALID` | 技术错误 | marker 缺失/重复，零 canonical 变化 |
| `TEST_TRANSACTION_CONFLICT` / `CAS_CONFLICT` | 技术错误 | 不覆盖第三值，使用同一入口恢复/重试 |
| 已启动命令 non-zero | 业务结果 | 继续剩余命令，最终原子发布 `status:block` |
| 已启动命令 timeout | 业务结果 | 记录 timeout，继续剩余命令，最终原子发布 `status:block` |
| 全部命令 exit 0 | 业务结果 | 原子发布 `status:pass`，进入后续 checkpoint/review |
| 外部中断 | 技术中断 | 运行阶段不发布；记录阶段依赖既有 journal 恢复，不产生部分 attempt |

# 4. 关键算法与流程

## 4.1 前置校验与计划规范化

```text
loadAndValidatePlan(ctx, cr, planPath):
  assert CR status == developing
  assert owners.test.id and owners.test.assigned-at exist
  assert planPath is inside workspace/.crctl/tmp or allowed non-authority temp root
  raw = readFileChecked(planPath)
  norm = raw.replaceAll("\\r\\n", "\\n")
  doc = parseJson(norm); parse failure -> TEST_PLAN_SCHEMA_INVALID
  assert doc.schema == "cr-test-plan/v1"
  assert non-empty commands array
  for command in commands:
    assert exact field types and no forbidden fields
    repo = getRepository(ctx, command.repo)
    wt = repo.worktreePath/requirement/{cr}
    assert wt exists and branch == requirement/{cr}
    cwd = resolve(wt, command.cwd || ".")
    assert realpath(cwd) remains within realpath(wt)
    normalize command to POSIX-relative cwd
  assert review-loop current attempt < maxAttempts
  return normalized plan + commandDigest
```

任何失败发生在运行前，不能创建 test journal、lock、canonical log、report、traceability 或 review-loop。计划 JSON 解析使用结构化 JSON parser，不使用跨行正则或字符串拆字段。

## 4.2 运行阶段

```text
runTestPlan(plan):
  tempRoot = .crctl/tmp/test/{cr}/{process-random-token}
  for command in plan.commands:
    result = spawnSync(
      command.executable,
      command.args,
      { cwd: command.absoluteCwd, encoding: "utf8", shell: false,
        timeout: command.timeoutSeconds * 1000 }
    )
    write stdout/stderr to tempRoot/cmd-NN.log
    collect exitCode, signal, timedOut, started
    if started and (exitCode != 0 or timedOut): overall = block
  continue until every planned command has a result
  return results, tempRoot, overall
```

`spawnSync` 返回启动失败时视为技术失败并停止，不将未执行命令伪造为业务结果。已启动命令的 non-zero/timeout 不停止后续命令。tempRoot 不在 `test-evidence/` authority 目录下，运行阶段中断只留下可清理临时物，不改变 canonical 文件。

## 4.3 机器区构造与 marker 保护

```text
prepareReport(existingRaw, normalizedPlan, results):
  if missing:
    analysis = ""
  else:
    norm = existingRaw.replaceAll("\\r\\n", "\\n")
    markerMatches = exactMarkerPositions(norm)
    if markerMatches.length != 1: TEST_MARKER_INVALID
    analysis = text after marker, including its content but excluding marker
  machine = renderReportFrontmatterAndBody(normalizedPlan, results, commandDigest)
  return machine + marker + analysis
```

marker 必须是现有唯一 literal `<!-- crctl:analysis-below -->`；不接受旧的带说明文本作为第二种 canonical marker。为兼容已有报告，迁移实现可在一次明确的 reader 规则中识别当前报告中的 marker 前缀，但输出统一使用唯一 literal；缺失、重复和跨行匹配失败均硬失败，禁止猜测分界。

## 4.4 原子记录事务

```text
recordTestResult(ctx, cr, plan, results, tempRoot):
  inputDigest = sha256(commandDigest + canonical result metadata + owner assignment)
  existing = loadExistingJournal({ op: "test", cr, inputDigest })
  if existing incomplete:
    recover/apply existing write-set first
    return recorded response without rerunning commands
  if existing complete:
    return idempotent response changed=false

  read current report/traceability/review-loop and validate marker/shape
  compute next attempt and all four after texts before any authority write
  loadOrCreateJournal({ op: "test", cr, graphDigest, inputDigest })
  entries = [
    test-report.md,
    test-evidence/cmd-01.log ... cmd-NN.log,
    traceability.yml,
    review-loop.yml,
  ] with beforeSha256, afterSha256 and temp content
  applyWriteSet({ root: crWorktree, txId, entries })
  mark test journal complete and clean blobs/tempRoot
  audit one test record with status/attempt/digest; no per-command audit
  return structured response
```

写集建立前重新读取所有 authority 文件并进行 CAS；发生第三值或 marker/traceability 形状异常时不进入 apply。原始日志内容从 tempRoot 进入既有 write-set blob，不先写入 canonical `test-evidence/`。`traceability.yml#tests`、`review-loop.yml` 和 machine report 使用同一 `recordedAt`/attempt 事实。

本 CR 对 `durable-tx` 只做三项最小扩展：

1. `OPS` 与 `PAYLOAD_KEYS` 增加 `test`，复用同一 journal envelope 校验；
2. test scope 复用现有目录锁和 PID/hostname 保守阻断；
3. test transaction 的恢复继续调用已有 `applyWriteSet`/`recoverWriteSet`，不新增 test-specific WAL、saga 或补偿逻辑。

## 4.5 Review-loop 与业务分流

`testCr` 在完整命令结束后读取 code-implementation pipeline 中 `write-test-report.reviewLoop.maxAttempts`，并将下一 attempt 以同一写集投影到 `review-loop.yml`。当前 attempt 已达上限时在运行前返回 `TEST_LOOP_EXHAUSTED`。

- `status=pass`：Pipeline 允许写分析区，随后 push-progress 和 review-code。
- `status=block`：Pipeline 允许写分析区，但不得 checkpoint/review；按 `replayNodes` 返回 implement-code。
- 分析区写入失败：不删除已发布 machine record，当前 Pipeline 节点 abort；下一次流程从既有 report machine zone 读取并重新完成分析。
- `review-code` blocker：完整重放 implement、test、checkpoint、review；不在 review Skill 内直接执行命令。

## 4.6 故障恢复矩阵

| 故障点 | 首次结果 | 同一入口重试 |
|---|---|---|
| plan parse/repo/cwd/schema | 无 journal、无 authority | 修正 plan 后完整运行 |
| executable 无法启动 | 无 canonical attempt | 修正 executable 后完整运行 |
| 运行阶段进程中断 | 无 journal、canonical 旧值 | 完整 plan 重跑 |
| journal 创建后、write-set 前中断 | test journal/incomplete | 读取 journal；若无完整结果则使用持久化 payload 或硬失败要求完整重试 |
| 多文件 rename 间中断 | 可能部分 authority 文件 | `recoverWriteSet` 按 before/after 恢复，第三值硬失败 |
| complete 标记前中断 | 文件均可能为 after | journal/write-set 恢复并标 complete，不重复 attempt |
| 已完成记录后进程退出 | authority 已完整 | 返回 `changed=false`，不重复 attempt |
| 命令 non-zero/timeout | 完整 `block` 业务证据 | 修复代码后新完整 attempt |
| marker 缺失/重复 | 零写入 | 人工修 marker 后重试 |

“运行阶段不建 journal”意味着命令执行过程不能依赖 durable resume；它只保证不会把半次运行误记为 canonical attempt。记录阶段则完全由既有 write-set 恢复。

# 5. 技术选型与替代方案

| 决策 | 采用 | 不采用 | 原因 |
|---|---|---|---|
| 测试接口 | 一个 `crctl test --plan` | `test run` + `test record` 公共双接口 | 保持深接口，避免调用方协调运行/记录事务 |
| 参数传递 | `spawnSync(executable, args, {shell:false})` | shell 字符串、`exec`、`shell:true` | 原生 argv 安全，复用 Node 标准库 |
| 事务落点 | `workspace-transactions.testCr` + 既有 durable-tx | 新 test runner/service/WAL | 与 Tools 现有架构和单一 crctl 写者一致 |
| test journal | 既有 journal envelope 新增 payload slot | 把 test 伪装成 checkpoint/ledger 或新 journal 格式 | 事务恢复语义集中，业务 op 可审计 |
| 原始日志 | 运行阶段临时目录，记录阶段写入现有 test-evidence | 运行阶段直接写 authority | 中断时不会产生半套 canonical 证据 |
| report 更新 | 机器 prefix 重建、marker suffix 保留 | 全文覆盖、宽松首/末 marker | 防止丢失人工分析，异常硬失败 |
| traceability | 最小 tests 投影 | 复制完整 commands/logs | 单一事实源，减小回写和漂移面 |
| loop 投影 | 复用现有 maxAttempts/renderer，和写集同批发布 | Skill 手写 attempt、独立 loop ledger | 保持 crctl 唯一账本写入者 |
| 测试验证 | 现有 Node `node:test` 与 fault harness | 新测试框架/第三方 runner | 零依赖、现有 fixture 可复用 |
| 并发策略 | 运行阶段允许并行尝试，记录阶段锁/CAS 阻止覆盖 | 全程全局锁或自动合并 | 不长时间持锁；冲突显式失败更简单可恢复 |

## 5.1 被否决的过度设计

- 不增加 `test-run`、`test-record`、`test status` 命令。
- 不增加 provider/adapter/plugin registry；当前只有 Node `spawnSync` 一种执行器，尚无第二 adapter。
- 不增加环境变量 allowlist、配额服务、远程日志上传、完整 workspace digest 或数据库。
- 不把测试业务命令发现下沉到 crctl；命令选择仍由 `write-test-report` 负责。
- 不让 `review-code` 重新执行验证命令；证据不可信就 blocker，回到既有闭环。

# 6. FR 到技术实现映射

| PRD FR | 技术实现 | 验证 |
|---|---|---|
| FR-01 单一深接口 | `crctl.mjs` test dispatch + `workspace-transactions.testCr` | `--plan` 成功；`--cmd` 拒绝；不推进 status |
| FR-02 plan contract | `parseTestPlan`、resolver、cwd containment、commandDigest | schema/字段/repo/cwd/CRLF/digest 测试 |
| FR-03 安全执行与结果语义 | `spawnSync(executable,args,{shell:false})`、结果分类 | shell metachar、argv、non-zero、timeout、启动错误 |
| FR-04 原子发布 | durable-tx test payload + `applyWriteSet` | report/logs/traceability/loop 同批；第三值和 fault matrix |
| FR-05 marker 分区 | `parseAnalysisMarker` + machine renderer | 多行保留、缺失/重复/CRLF 硬失败 |
| FR-06 分层采用 | Skill/Pipeline/crctl/review-code prompt 收敛 | lint-prompts、pipeline structure、文本 contract |
| FR-07 评审审批门禁 | 复用现有 `reviewLoop`、`push-progress`、`approve-code` | block 不进 review/approval；PASS 后 checkpoint |
| FR-08 幂等跨平台 | input digest、journal recovery、LF canonicalization | 重试、中断、Windows/Ubuntu、无重复 attempt |

覆盖率：8/8。

# 7. 安全、性能、兼容性与回滚

## 7.1 安全

- 只允许 `dir-graph.yaml` 声明的 active repo；不接受调用方自报仓库路径。
- cwd 先做 lexical normalize，再做 realpath containment，禁止 absolute、`..`、末段 symlink escape 和跨仓访问。
- executable/args 分离传给 `spawnSync`，固定 `shell:false`，不接受 shell 语法开关。
- plan、report、traceability 和 journal 读取均先 CRLF→LF；跨行/marker 失败硬失败。
- machine zone、traceability tests 和 review-loop 只能由 crctl 写入；Skill 只写 analysis suffix。
- stdout/stderr 不进入 audit 或 traceability，避免把敏感输出复制到多个 authority。

## 7.2 性能

若计划含 `n` 条命令、输出总量为 `B`，预检为 `O(plan-size + n)`，执行成本由命令本身决定，记录阶段为 `O(B + n)`。不并行启动命令，不缓存跨 CR 结果，不计算完整工作树 hash。stdout/stderr 已由 `spawnSync` 返回并写入临时日志；实现不得为保存结果再构建第二份 canonical plan。

## 7.3 兼容与迁移

- 旧 `--cmd` 调用不提供永久兼容分支；合入后返回 `BAD_ARGS`，Skill/Pipeline 在同一 CR 内同步迁移。
- 已有 `test-report.md` 若使用当前 marker，重跑保留 marker 后内容；缺失或重复 marker 按新硬失败规则处理，不自动猜测历史分析边界。
- 旧 traceability 无 `tests` 时首次成功 test 创建；已有非映射/冲突 tests 硬失败，不批量迁移历史。
- 不修改状态机、gate 数量、审批接口和既有 checkpoint 语义。

## 7.4 回滚

代码提交按 `crctl.mjs`/workspace transaction、durable-tx、测试、Skill/Pipeline 文档分为可回滚 TASK。回滚实现前必须先停止新 `--plan` 调用并确认没有未完成 test journal；按既有事务恢复清理后再 revert。不得恢复 Skill 手写机器报告、traceability 或 review-loop 的旁路。回滚不删除已生成的合法 test evidence，只恢复 CLI/调用方兼容性需另行审批的历史行为。

# 8. Prompt 采纳影响

本 CR 修改 `skills/shared/crctl/scripts/crctl.mjs` 的既有 `test` dispatch 分支，因此本节按 Skill 契约列出所有必须同步采纳的调用方：

| 文件 | 当前状态 | 必须改为 |
|---|---|---|
| `skills/develop/write-test-report/SKILL.md` | 接受 `--cmd` 字符串，直接描述 traceability/review-loop 写入 | 生成临时 `cr-test-plan/v1`，一次调用 `crctl test --plan`，只写 marker 后分析 |
| `pipeline-templates/code-implementation.pipeline.json` | 测试节点按文字传递命令，代码评审 prompt 要求无条件重跑 lint/test/build | 只传 CR/source node；reviewLoop 重放 `implement-code -> write-test-report`，代码评审只读证据 |
| `skills/develop/review-code/SKILL.md` | 评审阶段重新执行实现期验证命令 | 删除执行入口；将测试缺失、漂移和不可信证据作为 blocker |
| `skills/shared/crctl/SKILL.md` | CLI 表格仍登记 `--cmd` | 更新 `--plan` 输入、结构化输出、业务 block/技术 error 语义 |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 断言旧测试节点 prompt/结构 | 断言节点仍有既有 replayNodes，且 prompt 不含 shell 字符串执行或评审重跑算法 |

Agent、agent-skill-matrix、README、状态机、gates 和 versioned writeback scripts 不需要变化。没有新的 Skill owner、Pipeline 节点或 crctl 公共子命令，因此不新增权限声明。

# 9. 验证计划

全部测试使用 Node 内置 `node:test`/`node:assert` 和现有黑盒 runner；不引入第三方依赖。至少覆盖：

1. 合法 plan 执行、command 顺序、repo/cwd canonicalization、`command-digest` 可复算；
2. `--cmd`、shell metachar、空格、Unicode、引号、pipe、redirect 不被执行为 shell；
3. schema 缺失、字段类型错误、未知/inactive repo、缺失 worktree、absolute/escape cwd、symlink escape、非正 timeout；
4. executable 启动技术失败零 canonical 变化；
5. non-zero 和 timeout 继续剩余命令，并最终原子发布 `block`；
6. 全部成功发布 `pass`；report/status/commands 由 crctl 生成；
7. machine zone command 对象、日志路径和 digest；修改 plan 后旧 digest 不匹配；
8. 新报告 marker、已有 marker 后多行分析保留；marker 缺失/重复/CRLF 边界硬失败；
9. traceability tests、review-loop 和 report 同一 write-set；traceability 其他段保留；
10. `tx-apply-between-rename`、`tx-apply-before-complete` 和已有 recovery 路径下无半状态、第三值阻断、重试不重复 attempt；
11. 运行阶段外部中断不产生 journal/attempt，记录阶段中断可从 test journal 恢复；
12. 同一完成事务重放 `changed=false`，不重复命令账本发布；
13. `write-test-report` 只改 analysis suffix，`review-code` 不执行测试，Pipeline JSON 与 reviewLoop 仍可解析；
14. block 不进入 checkpoint/review/approval；PASS 后 checkpoint 非 complete 不进入人工审批；
15. Ubuntu 与 Windows 的 CRLF/LF、路径和 argv 回归。

验证命令由实现期 `write-test-report` 依据仓库原生测试配置选择；最低定向命令为：

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node --test skills/shared/crctl/scripts/test/fault-harness.test.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
```

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-15 | v0.1.0 | Ray | 初始设计：单一结构化 test 深接口、shell:false、test journal/write-set 原子发布、marker 分区、reviewLoop 和调用方收敛 |
