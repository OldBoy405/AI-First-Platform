---
id: CR-2026-054-sdd
type: SDD
cr-ref: CR-2026-054
title: "CR 归档安全、Agent 执行边界与任务终态闭环技术设计"
status: draft
created: 2026-08-29T13:01:19+08:00
updated: 2026-08-29T13:12:56+08:00
---

# 1. 架构概览

## 1.1 设计目标与边界

本设计以三个彼此独立、但在同一 CR 内共同验收的实现轨关闭已确认缺口：

1. **tools / archive 安全轨**：在 `workspace-transactions.mjs#archiveCr()` 的 `buildEntries()` 内，对已生成、尚未计算 write-set 哈希的四个候选执行严格 YAML 子集解析和归档后置条件校验。
2. **tools / Agent 执行边界轨**：收敛 `dev-agent.md`、`implement-code/SKILL.md`、`review-code/SKILL.md` 和 README 的职责与失败语义；不改 Pipeline、`write-test-report`、权限矩阵、`crctl test` schema 或状态机。
3. **multica / 终态补投轨**：在 `server/internal/daemon` 的单一 `reportTerminalTask()` 出口上，为有限重试耗尽后的瞬时 complete/fail 回调提供进程内、低频、幂等的后续补投。

实现严格遵守两个目标仓的架构不变量：tools 仍由 `crctl` 独占状态/账本写入；multica daemon 仍只消费服务端任务契约，不成为第二个服务端状态权威。不会新增 CLI、状态、账本、持久化 outbox、消息队列、HTTP API、数据库迁移、Pipeline 节点或共享服务管理能力。

## 1.2 模块与依赖

```text
tools
  yaml-subset.mjs
    -> parseYaml(text, { strict })
  workspace-transactions.mjs
    -> archiveLedgerEdits + crMdStatusText
    -> validateArchiveCandidates (file-private)
    -> write-set / stage / commit / lease push
  Agent + Skill + README
    -> 职责、验证和评审证据合同（不写账本、不管理共享服务）

multica
  terminalTaskReport (既有统一不可变终态载体)
    -> reportTerminalTask (既有唯一 complete/fail 出口)
    -> terminalReportRetry (新增内存集合、单 worker)
    -> Client.CompleteTask / Client.FailTask (既有幂等端点和有限退避)
```

`yaml-subset.mjs` 不依赖 archive 事务；archive 校验调用解析器而不反向引入事务逻辑。daemon 待重试集合仅持有 `terminalTaskReport` 的值副本，不持有 `Task`、可变 result 或服务端状态。

## 1.3 关键流程

### Archive 候选

```text
archiveLedgerEdits + crMdStatusText
  -> newBacklog / newHistory / newIndex / nextCrMd
  -> validateArchiveCandidates（严格解析 + 根形状 + 不变量）
  -> 计算 entries 的 before/after SHA-256
  -> applyWriteSet -> stage -> commit -> lease push
```

首次构建和远端 trunk 变化后的 rebuild 均调用同一个闭包 `buildEntries()`，因此候选校验在两条路径中天然复用。校验失败发生于 `applyWriteSet`、`git add`、commit 和 push 之前；既有 journal 创建与旧事务 recovery 仍保留原时序。

### 环境不匹配

```text
implement-code 执行一次有界环境检查
  -> 前提可建立：执行任务范围内验证；可归因失败按代码失败处理
  -> 前提不可建立且修复超出任务权限：ENVIRONMENT_MISMATCH
  -> 既有 Pipeline onFail=abort 中止
  -> Agent 报告所需平台/人工动作并结束，不管理共享服务
```

### daemon 终态补投

```text
任务退出 -> reportTerminalTask(report)
  -> Client.CompleteTask / FailTask（既有 6 次、约 124 秒有限重试）
  -> 成功：返回
  -> 最终瞬时错误：将 report 值副本按 task ID 入内存集合，惰性启动重放循环
  -> 每 30 秒单 worker 执行一轮快照：成功删除；永久错误删除；瞬时错误保留并终止本轮
  -> daemon 根 context 取消：停止循环，不额外 drain
```

# 2. 数据模型

## 2.1 严格 YAML 诊断

严格模式保持 `parseYaml(text, { strict: true })` 的可选调用形式。解析器在严格模式下维护仅用于诊断的元数据，不改变默认模式返回值和宽松行为：

```js
{
  category: 'duplicate-key' | 'unconsumed-line' | 'invalid-indentation' | 'invalid-shape',
  line: 1,             // 1-based，候选文本内行号
  firstLine: 1,        // 仅 duplicate-key
  key: 'id'            // 仅适用时
}
```

内部仍使用普通 `Error`，通过自有字段携带上述元数据，不新增错误类或通用 schema 注册中心。严格模式在读入后先将 `\r\n` 规范化为 `\n`；键的重复性使用 `unquote()` 后的文本比较，因此 `id`、`"id"` 与 `'id'` 冲突，大小写不折叠。

## 2.2 Archive 候选与错误详情

`validateArchiveCandidates` 是 `workspace-transactions.mjs` 文件私有函数，输入四份候选文本、目标 `cr` 和 `finalStatus`，不导出测试接口：

```js
validateArchiveCandidates({
  cr,
  finalStatus,
  candidates: {
    backlog: newBacklog,
    history: newHistory,
    index: newIndex,
    crMd: nextCrMd,
  },
})
```

它按如下逻辑文件名组织诊断：`_backlog.yml`、`_history.yml`、`_index.yml`、`cr.md`。前三个文本直接严格解析；`cr.md` 先由既有 `matchFrontmatter()` 定位 frontmatter，再严格解析其 body，并将解析器行号偏移回完整候选文件行号。

校验失败统一由 archive 边界包装为 `TxError('ARCHIVE_YAML_INVALID', ...)`。稳定类别为：

| 类别 | 来源 | 详情字段 |
|---|---|---|
| `duplicate-key` | block/flow map 的等价键重复 | `line`、`firstLine`、`key` |
| `unconsumed-line` | 某层解析未消费属于该层的行 | `line` |
| `invalid-indentation` | tab、根缩进、非法深度或容器切换 | `line` |
| `invalid-shape` | 根结构不符合四候选要求 | `line`（形状所在行） |
| `archive-invariant` | 目标 CR 或 history 全局不变量不满足 | `line`、`cr`、必要时 `key` |

所有 `ARCHIVE_YAML_INVALID` 详情都包含 `file`、`category`、`line` 和相关 `cr`/`key`（适用时）。`line` 的 P2 处理规则固定如下：可由候选文本定位时使用 1-based 行号；例如重复 history ID 使用第二次出现的 ID 行，错误终态使用对应 `final-status` 行。纯“缺失”不变量没有真实候选行，例如目标 CR 不在 history 中时，返回 `line: null` 与目标 `cr`；不得发明 0、文件首行或任意邻近行。错误文本要求操作者修复权威源账本后重跑，不回显全量账本，也不增加修复命令。

## 2.3 daemon 内存待重试集合

新增 `server/internal/daemon/terminal_report_retry.go`，在 daemon 包内定义零值可用的私有组件：

```go
type terminalReportRetry struct {
    mu      sync.Mutex
    pending map[string]terminalTaskReport // task ID -> first accepted immutable report
    once    sync.Once
}
```

`terminalTaskReport` 已是 complete/fail 统一载体，含 task ID、终态种类、output/error、branch/session/workdir、failure reason 和 session rollout 字段。当前字段全部为 Go 值类型（枚举、布尔和字符串）；入队按值复制整个 report，同一 task ID 的相同 report 不改变集合，冲突 report 保留先到值（first-wins）。比较覆盖 report 的全部字段，防止只比较 task ID 而把不同终态 payload 静默视为相同。若未来增加 slice、map、pointer 或其他引用字段，必须在入队和 snapshot 边界执行深复制，或先将字段改为不可变值表示；不得把调用方仍可修改的引用放入 pending map。

初次投递失败通过私有安全包装值返回：

```go
type terminalReportFailure struct {
    cause error
    taskID string
    kind terminalTaskReportKind
    class terminalReportErrorClass
}
```

该类型实现 `error`、`Unwrap() error` 与 `slog.LogValuer`。`Unwrap()` 保留既有 `errors.As` / `isTransientError()` 结构化分类；`Error()` 保留既有 complete 永久拒绝后构造 fail payload 的功能语义；`LogValue()` 只生成 `task_id`、`terminal_kind`、`error_class` 三个脱敏字段，确保现有 `slog` caller 即使继续以 `"error", err` 记录，也不会展开原始 cause。

集合不做持久化、容量限制、背压、claim gate 或并发 worker 调度。进程退出时集合自然丢失，遗留 `running` 任务继续由既有 orphan recovery 收敛。

# 3. 接口契约

## 3.1 `parseYaml` 严格模式

```js
parseYaml(text, { strict: true })
```

默认调用 `parseYaml(text)` 保持原兼容语义。严格模式增加以下契约：

- 根节点必须自第 0 列开始，缩进只能使用空格，子节点必须比父节点深；不强制两个空格。
- block map 与 flow map 的重复键立即失败，错误包含首个及重复键行号。
- 每层解析返回消费位置；任何属于当前层却未消费的行都失败。
- 裸 `-` 必须紧跟实际子节点；`key:` 仍解析为空值以兼容空 backlog。
- 非法容器切换、无法解释行、tab 缩进和 trailing flow 内容均硬失败。

## 3.2 `validateArchiveCandidates`

根形状校验只覆盖 archive 所需最小集合：

| 候选 | 必须满足 |
|---|---|
| `_backlog.yml` | 根对象，`change-requests` 为数组或空值 |
| `_history.yml` | 根对象，`history` 为数组 |
| `_index.yml` | 根对象，`change-requests` 为数组 |
| `cr.md` | frontmatter 严格解析为对象 |

严格解析后，函数执行以下不变量：

- backlog 中目标 CR 为 0 次；
- history 中目标 CR 恰好 1 次；
- index 中目标 CR 恰好 1 次，`status === finalStatus`；
- `cr.md` frontmatter 中目标 `status` 恰好 1 次，值为 `finalStatus`；
- history 的所有 CR ID 全局唯一；
- history 的每个 `final-status` 属于 archive 专用常量 `ARCHIVE_FINAL_STATUSES = new Set(['archived', 'rejected', 'withdrawn'])`。

此常量由原有 archive 状态检查和候选校验共同使用，但不从完整状态机动态推导，也不成为第二份状态机声明。

`archiveLedgerEdits()` 的既有生成期错误发生在验证之前，继续原样暴露 `ENTRY_NOT_IN_BACKLOG`、`ENTRY_ALREADY_IN_HISTORY`、`INDEX_ENTRY_NOT_FOUND`。只有四候选严格解析、根形状或后置不变量失败才映射到 `ARCHIVE_YAML_INVALID`。

## 3.3 Agent 与 Skill 合同

| 文件 | 修改后的唯一职责 |
|---|---|
| `agents/dev-agent.md` | 声明 Agent 仅做路由、职责判断和 Skill 委派；禁止管理共享服务生命周期；技术中止后报告外部动作并结束，不等待或轮询下游任务。 |
| `skills/develop/implement-code/SKILL.md` | 作为有界验证和 `ENVIRONMENT_MISMATCH` 的唯一详细事实源：一次环境检查、任务范围内修正后最多一次重跑、遵守测试计划 timeout、使用既有入口、禁止遗留后台进程。 |
| `skills/develop/review-code/SKILL.md` | 继续读取真实 diff 与规范测试证据；不采信无法可信关联当前变更主体的共享实例输出；明确 `ENVIRONMENT_MISMATCH` 是技术中止而非 blocker。 |
| `README.md` | 仅增加人读原则和到上述文件的链接，不复制判定步骤或状态逻辑。 |

`ENVIRONMENT_MISMATCH` 是 Skill 输出的稳定技术失败标签：当验证前提不可建立且修复要求管理共享服务或改动任务范围外环境时返回。它不写入 crctl 状态、gate、账本、review annotation blocker 或测试证据 schema。若验证环境已经受控建立，测试失败可归因于当前变更，必须按普通代码失败进入既有回修路径。

任务明确要求且由当前步骤创建、验证后清理的临时隔离实例不属于共享服务。共享服务指任务范围外、可能由其他任务共享或需要调整既有生命周期的实例。

## 3.4 terminal report 补投接口

`reportTerminalTask(parentCtx, report)` 保留为唯一终态发送入口。其内部抽出只发送、不入队的私有 helper：

```go
func (d *Daemon) deliverTerminalTaskReport(ctx context.Context, report terminalTaskReport) error
```

- `deliverTerminalTaskReport` 按 `report.kind` 调既有 `Client.CompleteTask` 或 `Client.FailTask`，保持所有原始不可变参数和既有有限重试。
- 常规 `reportTerminalTask` 仍以 `context.WithTimeout(context.WithoutCancel(parentCtx), terminalTaskReportTimeout)` 执行一次完整交付；成功返回 nil。
- 任一失败先包装为 `terminalReportFailure{cause, taskID, kind, class}`：`class` 只能为 `transient` 或 `permanent`。该包装保留 `Unwrap()` 供既有错误分类，保留 `Error()` 供现有 complete→fail fallback 组装服务端 payload，但其 `slog.LogValue()` 只暴露安全字段。
- 仅当最终错误满足既有 `isTransientError(err)` 时，`reportTerminalTask` 调用 `enqueueTerminalReport(report)`；永久错误不入队。两类错误均以安全包装返回，因此所有现有初次投递 caller 的结构化日志不再展开原始 cause。
- 重放循环直接调用 `deliverTerminalTaskReport`，绝不回调 `reportTerminalTask`，避免瞬时失败重放时递归入队或重复启动 worker；其日志通过同一安全值构造函数输出。

首次成功加入集合时，`sync.Once` 用 daemon 根 context 启动单一 goroutine。生产运行使用 `d.rootCtx`；单元测试未经 `Run()` 初始化时沿用既有 `recoveryContext()` 的 `context.Background()` 回退，仅用于构造可测 fixture，不改变生产生命周期。

**终态日志合同覆盖初次投递与重放两条路径，不再排除现有 caller。** 所有可达的终态回调失败日志只能包含固定事件名以及 `task_id`、`terminal_kind`、`error_class`；`error_class` 只能为稳定脱敏值 `transient`、`permanent` 或 `conflict`。禁止向 logger 传入或展开原始 cause、`errorMessage`、`output`、session、workdir、完整 report 或其他 payload 字段。初次 caller 通过 `terminalReportFailure.LogValue()` 自动满足该合同；重放和冲突日志显式复用同一安全属性生成逻辑。该收敛只改变日志表示，不改变返回错误的结构化分类、complete→fail fallback 的服务端 payload 或重试/入队语义。

# 4. 关键算法与流程

## 4.1 严格解析及 archive 校验伪代码

```text
parseYaml(text, options):
  normalized = text.replaceAll(CRLF, LF)
  tokenize non-blank/non-comment lines with raw line number
  parse root at indent 0
  each parseMap/parseSeq returns (value, nextIndex)
  strict mode:
    reject tabs and illegal indentation before descending
    reject duplicate normalized keys while adding every map key
    reject bare '-' without a child node
    if nextIndex != lines.length: fail unconsumed-line at lines[nextIndex].no
  return value

buildEntries(root):
  edits = archiveLedgerEdits(existing files)
  nextCrMd = crMdStatusText(existing cr.md, finalStatus)
  validateArchiveCandidates(edits.newBacklog, edits.newHistory, edits.newIndex, nextCrMd)
  return four entries with raw before hash and LF after hash
```

`validateArchiveCandidates` 先对四候选独立严格解析并执行根形状校验，后执行跨文件不变量。它将任一普通错误规范为有限诊断对象后才抛出；外层仅在该函数范围内捕获并包装，因此不吞没已有编辑阶段错误。

## 4.2 daemon 入队和单轮重放伪代码

```text
reportTerminalTask(parentCtx, report):
  ctx = timeout(withoutCancel(parentCtx), terminalTaskReportTimeout)
  cause = deliverTerminalTaskReport(ctx, report)
  if cause == nil: return nil
  class = isTransientError(cause) ? transient : permanent
  failure = terminalReportFailure(cause, report.taskID, report.kind, class)
  if class == transient:
    enqueueTerminalReport(copyImmutable(report))
  return failure  // LogValue 仅暴露 task_id/terminal_kind/error_class；Unwrap 保留分类

enqueueTerminalReport(report):
  lock pending
  if taskID absent: pending[taskID] = report; accepted = true
  else if pending[taskID] != report: logSafe(taskID, terminalKind, conflict)
  unlock
  if accepted: once.Do(startReplayLoop(rootCtx))

replayOnce(rootCtx):
  snapshot deepCopyIfReferenceFieldsExist(pending) under lock
  for (taskID, report) in snapshot:
    if rootCtx cancelled: return stopped
    cause = deliverTerminalTaskReport(timeout(rootCtx, terminalTaskReportTimeout), report)
    if success: delete taskID only if stored report still equals snapshot report
    else if rootCtx cancelled: return stopped
    else if isTransientError(cause): logSafe(taskID, terminalKind, transient); return retry-later
    else: delete taskID only if stored report still equals snapshot report; logSafe(taskID, terminalKind, permanent)

replayLoop(rootCtx):
  ticker = 30 seconds
  until rootCtx cancelled:
    wait ticker
    replayOnce(rootCtx)
```

删除时重新比较值，避免 future refactor 或并发入队使旧快照删除较新的值。当前 first-wins 语义通常不会替换条目，但该比较使行为在并发边界保持明确。一次重放在遇到第一个瞬时错误时立即停止本轮，防止端点故障时放大请求；下一个固定周期再从完整快照开始。

## 4.3 P2 建议的证据承载矩阵

不新增状态、门禁或证据 schema。三个业务域的完成事实由现有流程承载：

| 业务域 | 实现期证据 | 代码评审承载 | 既有后续门 |
|---|---|---|---|
| archive 严格校验 | `yaml-subset.test.mjs` 与 `archive-tx.test.mjs`，含首次及 rebuild 失败副作用断言 | `review-code` 读取 tools diff、`test-report`、traceability 测试项，缺失/失败为 blocker | 既有 code approval；writeback/归档继续由 crctl 深原语处理 |
| Agent 边界 | 文档 diff、契约/负向场景检查及既有规范测试入口的证据 | `review-code` 检查无 Pipeline/schema/权限矩阵越界，环境不匹配不生成 blocker | 既有 code approval；无新门禁 |
| daemon 补投 | 新增 `terminal_report_retry_test.go` 的 complete/fail、去重、错误和关闭场景 | `review-code` 读取 multica diff、Go 测试报告及 `CUSTOM.md` 登记 | 既有 code approval；归档前现有 tasks-all-done、approval、traceability 检查 |

后续 TASK 必须将上述测试及文档审查映射到 `AC-1` 至 `AC-7`；`write-test-report` 通过既有 `crctl test` 路径记录命令、日志、摘要和未覆盖风险；`review-code` 再根据实际 diff 与规范证据判定。任一域缺实现、测试或可审查证据，评审必须 block，无法达到 code approval；archive 仍额外要求 tasks 全 done、`approval.yml` 与 traceability 存在。这满足 FR-19 而不复制或扩张现有 gate。

# 5. 技术选型与替代方案

| 决策 | 选择 | 未选方案及原因 |
|---|---|---|
| YAML 校验 | 扩展现有零依赖 YAML 子集解析器的可选严格模式 | 第三方完整 YAML 解析器会违反 tools 零依赖与受控文件字段序约束；全局严格化会改变非 archive 调用方行为。 |
| 校验位置 | archive `buildEntries()` 内、hash 前 | 新 CLI、独立预检命令、Skill/Pipeline 副本都会产生第二入口或遗漏远端 rebuild。 |
| 不变量范围 | history 全局唯一/合法终态，其他文件仅检查目标 CR | 通用 schema registry 与全账本业务字段校验超出已确认问题且扩大维护面。 |
| Agent 环境处理 | `ENVIRONMENT_MISMATCH` + 已有 `onFail=abort` | 管理共享服务、增加服务管理 Skill/Pipeline 或创建新的 CR 状态都会越权并重复现有失败编排。 |
| daemon 补投 | daemon 内存 map + 30 秒单 worker + 服务端既有幂等端点 | 持久化 outbox、MQ、DB 表、容量/背压框架会重建不需要的调度系统。 |
| 日志诊断 | 稳定脱敏 `error_class` | 记录原始 Error 或 payload 会与“不泄露 error message/output/session”安全要求冲突。 |

**Decision: 以 nullable 候选行号表达缺失不变量。**

- Context：语法和字段错误有真实行，目标 CR 缺失等跨文件不变量没有真实行。
- Alternatives：伪造 0/1/相邻行；或删除行号字段。
- Consequences：固定输出 `line: null` 可让调用方稳定处理，保留真实诊断精度且不误导操作者。

# 6. FR 到技术实现映射

| FR | 技术实现 | 验证 |
|---|---|---|
| FR-1~FR-3 | `yaml-subset.mjs` 的可选严格模式、行号元数据、CRLF 规范化、完整消费与重复键检查 | 内联 YAML 单元测试，默认模式兼容回归 |
| FR-4~FR-7 | `workspace-transactions.mjs` 文件私有 `validateArchiveCandidates`，接入 `buildEntries()` 的 hash 前位置，`ARCHIVE_YAML_INVALID` 包装 | archive 正常、初次无效、rebuild 无效、旧错误码和零 Git 副作用测试 |
| FR-8 | `agents/dev-agent.md` 只写路由及共享服务禁令/委派结束 | 文档审查 |
| FR-9~FR-10 | `implement-code/SKILL.md` 增有界检查、最多一次重跑、临时实例例外和 `ENVIRONMENT_MISMATCH` 分类 | 文档契约与负向场景审查 |
| FR-11 | `review-code/SKILL.md` 增共享实例证据拒绝和环境不匹配技术中止语义 | 文档契约与评审场景审查 |
| FR-12 | README 增单段原则和指针；不改 Pipeline、测试报告、矩阵或 schema | diff 范围检查 |
| FR-13 | `reportTerminalTask` 的瞬时最终错误入队挂钩；复用现有 client retry/isTransientError | complete/fail 瞬时与永久错误测试 |
| FR-14 | `terminal_report_retry.go` 的 task ID map、全 payload 比较、first-wins、`sync.Once` | 去重、冲突、单 worker 测试 |
| FR-15 | 30 秒 ticker、单轮 snapshot helper、成功/瞬时/永久处理 | 直接调用单轮 helper，零真实 ticker 等待 |
| FR-16~FR-17 | 复用 `deliverTerminalTaskReport` 和服务端幂等接口；root context 停止；`terminalReportFailure.LogValue()` 与 `logSafe` 统一覆盖初次/重放/冲突三类脱敏日志 | payload 保真、关闭、初次与重放日志均不泄露测试 |
| FR-18 | 新 Go 文件/测试、`daemon.go` 两处最小挂钩、`CUSTOM.md` 登记 | diff 范围、台账与 Go 测试审查 |
| FR-19~FR-20 | 本 SDD §4.3 证据矩阵及后续 TASK 映射 | review-code、现有审批和 archive 前置 gate |

# 7. 安全与性能考量

## 7.1 安全与数据泄露

- archive 错误仅携带文件逻辑名、有限类别、行号和相关键/CR ID，不输出候选全文。
- P2 日志决策覆盖所有可达终态回调失败：初次投递通过 `terminalReportFailure.LogValue()`，重放/冲突通过 `logSafe`，两者都只生成 `task_id`、`terminal_kind`、`error_class`。不得向 logger 传入或展开 fail payload 的 `errorMessage`、complete payload 的 `output`、session/workdir、完整 report 或原始 cause。
- `terminalReportFailure.Error()` 仅用于保留现有 complete→fail fallback 的服务端 payload 语义；结构化日志必须经 `slog.LogValuer`，测试锁定当前所有终态 caller，防止未来改为字符串插值绕过脱敏。
- Agent 不操作共享服务，不把不可信共享实例输出用作评审结论；环境不可控时中止而非推测。
- daemon 使用既有服务端终态接口、daemon 认证和幂等语义，不新增 token、HTTP 路由或本地持久化敏感数据。

## 7.2 并发与性能

- 严格解析只在 archive 的四份内存候选上执行，复杂度为候选文本长度；不会增加常规 crctl 调用路径的成本。
- archive 校验在 write-set 前运行，失败不产生 stage/commit/push；rebuild 复用同一纯候选构建逻辑。
- 待重试 map 操作由短临界区 mutex 保护；网络调用在锁外执行。每任务最多一个值，单 worker 每 30 秒最多按快照串行请求；第一个瞬时错误停止本轮。
- 本 CR 不承诺 daemon 重启后的补投持久性、exactly-once 或无限重试。服务端任务在等待时维持既有 `running`，orphan recovery 继续负责进程失联场景。

## 7.3 测试设计

### tools

- 新增 `skills/shared/crctl/scripts/test/yaml-subset.test.mjs`：block/flow 重复键、引号等价键、CRLF、tab、非法缩进/容器切换、未消费行、孤立 `-`、合法空值及默认模式兼容。
- 更新 `archive-tx.test.mjs`：合法 `archived`/`rejected`/`withdrawn`，四候选根形状和目标/全局 history 不变量，初次与 rebuild 的 `ARCHIVE_YAML_INVALID`，以及文件/HEAD/stage/commit/push 不变。
- 实现完成后一次性以只读测试/调用对真实 workspace 的 backlog、history、index 严格解析；不增加常驻校验脚本或新 CLI。

### multica

- 新增 `server/internal/daemon/terminal_report_retry_test.go`，以 `httptest` client 或同包 fixture 驱动单轮 helper，不等待真实 ticker。
- 覆盖 complete/fail 瞬时耗尽后入队、初次永久错误不入队、成功删除、瞬时失败保留并停止本轮、永久失败删除、相同 payload 去重、冲突 first-wins、root context 取消，以及当前值字段的不可变复制。
- 使用捕获 `slog.Handler` 驱动**初次投递失败 caller**与**重放/冲突**两类路径：断言日志只含 `task_id`、`terminal_kind`、`error_class`，并以唯一秘密标记填充 output、errorMessage、session、workdir 和原始 cause，断言日志全文及属性均不含任一秘密值。额外断言 `errors.Unwrap` / `isTransientError` 与 complete→fail fallback 仍获得原始 cause，证明日志脱敏未改变功能语义。
- 不扩张现有大型 `daemon_test.go`；保持 Go 注释英文并按 `CUSTOM.md` 记录所有 fork 定制和验证命令。

# 8. 风险与非目标

| 风险 | 缓解 | 不做 |
|---|---|---|
| 严格解析误拒现有合法账本 | 默认模式不变；以现有真实账本做一次只读验证；测试保留 `key:` 空值 | 全量 YAML 兼容层 |
| rebuild 新路径绕过校验 | 校验位于两条路径共用的 `buildEntries()` | 单独 rebuild 分支副本 |
| 环境标签掩盖代码缺陷 | 仅在前提不可建立且修复越界时允许 `ENVIRONMENT_MISMATCH`；受控环境失败仍为代码失败 | 新 blocker/status 类型 |
| daemon 重放放大故障 | 30 秒、单 worker、首个瞬时错误停止本轮 | 背压/容量/指数退避框架 |
| daemon 崩溃丢失内存项 | 既有 orphan recovery 收敛失联任务 | 持久化 outbox 或跨重启可靠投递 |
| 上游 rebase 冲突 | 新增逻辑放独立 daemon 文件；`daemon.go` 仅增加零值字段和统一 `reportTerminalTask` 包装挂钩，现有 caller 通过 `slog.LogValuer` 自动脱敏；`CUSTOM.md` 留痕 | 修改每个 complete/fail 调用点 |

本轮设计与评审的 authority 基线由 `crctl workspace inspect CR-2026-054` 返回的 healthy resources 确认：tools `8884f599ea3b13ce0cdb53812bf7f20e40d75dd5`，multica `a3fcdd34574779ac0c888698e5999ee9595bdcae`；实现开始前必须再次执行 workspace inspect，若 HEAD 漂移则以新权威 worktree 复核接缝，不把本段 SHA 当作长期配置。

本设计不触及 `crctl.mjs` dispatch 分支或 `controlled-shell/rules.json` deny 面，因此不触发 Prompt 采纳影响小节。后续 SDD 评审应重点核对：严格模式是否保持默认兼容、候选校验是否确在 write-set 前、初次与重放终态日志是否统一脱敏、P2 nullable 行号约定是否落实、以及三域是否都在 §4.3 的既有证据闭环中具备实际产物。
