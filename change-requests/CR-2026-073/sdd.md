---
id: CR-2026-073-sdd
type: SDD
cr-ref: CR-2026-073
title: crctl test 长输出与审计归属修复、普通 CR 验收范围约束 技术设计
target-version: 0.46
status: draft
created: 2026-09-30T12:44:14+08:00
updated: 2026-09-30T12:44:14+08:00
---

# CR-2026-073 技术设计

## 1. 架构概览

目标仓为 `tools`；遵守其 `ARCHITECTURE.md` 的 Skill → crctl → durable transaction 依赖方向。设计依赖 dep-1 / dep-2 的测试执行与发布边界、dep-3 / dep-4 的安装根与终态 adapter、dep-5 / dep-6 / dep-7 的 Skill 契约。A、B 是 crctl 的独立修复，C 只改三个开发期 Skill 契约；不进入 multica 代码。事务内 merge/writeback/archive 算法不动。

```text
cr-test-plan/v1 → runTestPlan [有界 spawnSync → 完整结果或技术错误]
                → testCr [只有完整结果进入报告/证据/原子发布]
--workspace → resolveRepositories → ctx.installRoot ─┐
                                     authority worktree/txws → merge/writeback/archive
                                     └→ 稳定审计根 + 事前 actor → audit.log
批准 PRD/SDD → write-dev-plan 的 FR/AC 定向证据 → write-dev-tasks 同范围继承
                                              └→ review-dev-plan 检查证据能力/声称范围
```

术语边界：`ENOBUFS` 是输出容量技术错误，不是进程的真实非零退出；`canonical` 指 `test-report.md`、`test-evidence/`、`traceability.yml`、`review-loop.yml` 的权威文件及 attempt 投影，临时诊断片段不属于它。`audit actor` 是命令执行人的身份，不等于写入根；install-root 是当前机器的本地权威，不是远端持久化。三组范围独立，C 不借 A 或 B 扩展机器门禁。

## 2. 数据模型

- A：不改 `cr-test-plan/v1` 字段、不改成功路径 `commands[]` 机器区和 log 的 stdout/stderr 标记。固定 `TEST_MAX_BUFFER_BYTES = 10 * 1024 * 1024`（字节），作为单次 `spawnSync` 的显式 `maxBuffer`。成功/真实失败记录仍含 `exitCode`、`signal`、`timedOut`、`started`、`skipped`、`logSha256`；溢出不产生完整 `resultFacts`，诊断错误 `extra` 含 `errCode: ENOBUFS`、`maxBufferBytes: 10485760`、`exitCode: null` 与捕获片段的**诊断**标识，不产生可用于验收的 `cmd-NN.log`。保留临时日志供排障可选，但不得复制进 `test-evidence/` 或计算为完整 log 哈希。
- B：不更改 `.crctl/audit.log` JSONL 现有字段语义；`root=ctx.installRoot`、`actor` 为两个独立值。已有 `advance:{cr}:{commit}` 去重键保持原样，只改变 `auditLogOnce` 的文件根。终态事件如需要防重放附加确定性 `dedup_key`（`{op}:{cr}:{txId}:{stage|phase}`，按实际稳定 journal 标识选择），重复调用不重复写同一**业务事件**，不删除/修改旧条目。不同阶段、事务或 release-drift 与成功不得误合并；不重建历史缺失项。
- C：不新增 plan、TASK、测试计划 schema 字段。仍用 plan 两张稳定表 `验收证据 cmd-NN` / `证据命令表`、TASK 验收条件、既有评审 blockers 表达“已批准验收面、命令实际观测面、是否要求全量”三者关系。

## 3. 接口契约

### 3.1 A：`runTestPlan(plan, ctx, cr)` / `testCr(ctx, { cr, workspace, planPath })`

入口保持原签名与 `shell:false`、`encoding:'utf8'`、cwd/env、超时配置；仅给 `spawnSync` 增加 `maxBuffer: TEST_MAX_BUFFER_BYTES`。每条命令执行后先按 `r.error?.code` 分流：

| 结果 | 返回/失败合同 |
|---|---|
| 无 `r.error`、`status=0` | 原有成功或 skip 判定；分别保存完整 stdout/stderr、sha256、真实 status/signal |
| 无 `r.error`、`status≠0` | 原有 `overall=block`，保留真实 exit/status、日志与 sha256 |
| `ETIMEDOUT` | 原有超时路径、`timedOut=true` / `overall=block`，不误判缓冲溢出 |
| `ENOBUFS` | 在解析 skip、保存完整证据及构造 canonical 结果**之前**抛独立 `TxError('TEST_OUTPUT_EXCEEDED', ...)`；消息和 `extra` 明示 `ENOBUFS`、`10485760 bytes`、`exitCode:null`；stdout/stderr 若保留只能标诊断截断片段，不能推断真正的进程退出、成功、失败或 skip |
| 其它 `r.error` | 保持 `TEST_EXECUTABLE_INVALID` 启动失败分类；保留原错误码，不当成 test block |

溢出错误由 CLI 既有 `TxError` → 非零退出路径输出；`testCr` 不收到 `runTestPlan` 成功返回便不进入记录阶段，不创建 journal / attempt、不改 canonical 四类文件。不要在 `r.error=ENOBUFS` 时先从截断 log 做 `extractStdioSections` 或赋 `resultFacts.logSha256`。多命令计划前面的命令可能已有临时片段，但整体不得发布伪完整证据。`spawnSync` 的阈值不承诺 10 MiB 是 stdout 与 stderr **总量**还是各管道独立容量；验收对低于上限的每段与超过上限的单段构造确定性输入。

### 3.2 B：终态命令 adapter

不改 `mergeCr` / `applyWriteback` / `archiveCr` 的入参、锁、journal 与操作顺序。`cmdMerge` 的成功及 release-drift 两分支、`cmdWritebackApply` 的 `emitAdvanceAudit`/终态记录、`cmdArchive` 的终态记录均以**一次** `resolveRepositories(ws)` 的 `ctx.installRoot` 作为 `auditLog` / `auditLogOnce` 参数；不能在事务结束后调用 `deriveInstallRoot(ws)` 重新推根。内部 audit helper 签名保持不变。

进入可清理 authority 的事务前解析本次 actor：优先调用入口可用时的 `identity(ws)`，否则使用 `identity(ctx.installRoot)` 的本机稳定身份；如果两者均不可证明，不要写 `unknown` 假身份，应在副作用前报明确技术错误供身份配置修复。将此值用于审计记录及对应 outbox callback，而不是归档后读已删除的 ws。重放从仍存在的 install-root 进入；已删除路径不能作为合法 CLI `--workspace`，不得为了审计重建它。调用方根、实际 operational authority 与 actor 分离；actor 前置解析不触碰账本、审批、merge 事务算法。

设计依赖 dep-4 的 `auditLogOnce` 在 install-root 读取同一 JSONL 来判断 dedup，writeback 的 `advance:{cr}:{commit}` 保持既有键；merge/writeback/archive 成功业务事件可用稳定 tx ID/阶段键避免 `changed=false` 的幂等重放追加重复记录。普通失败不伪装成成功事件；release-drift 分支的独立结果按当前审计语义单独标识。重放的纯观察若需要诊断，不能复用同一业务事件键产生另一条“成功”。仅 append，不迁移、改写或倒填旧 worktree/txws 中的 audit。

### 3.3 C：Skill 契约

- `skills/develop/write-dev-plan/SKILL.md`：在现有两张稳定表和 §5 增加判据——每个 in-scope FR/关键 AC 的关键 `cmd-NN` 选择能观测其实际结果的最窄可执行命令，说明真实运行范围；默认不把全仓测试当普通 CR 门槛。只有批准的 SDD/AC 明确要求全量时才纳入全仓命令；范围小的证据不宣称全量通过。命令形态保持表中 `executable/args/cwd/timeout` 唯一事实源。
- `skills/develop/write-dev-tasks/SKILL.md`：验收条件与完成标志逐项继承 plan 的证据 ID、实际范围与声明；不得从“运行某子集”推导为“全量通过”，也不得额外新增全仓通过前置。
- `skills/develop/review-dev-plan/SKILL.md`：沿用既有 SDD→plan→TASK 评审维度，将“未批准却把全仓命令设为普通 CR 必过”和“plan/TASK 的声称面宽于关键 cmd 的实际观测面”判 blocker，明确返回具体 FR/AC、证据ID、repair-target=`write-dev-plan`（涉及批准的 SDD 范围冲突则按原 upstream-design-blocker 路由），修订后复评；不新增维度、状态或门禁。

上游同步是单独场景，按目标 fork 的 `CUSTOM.md` 执行全量；Windows 已知失败保留原始输出和基线对比，不把局部成功冒充全量验收。批准验收明确要求全量绿色但不可达时，先修复或正式修订 SDD/AC，不跳过 `crctl test`。

## 4. 关键算法与验证流程

1. A：以 `test-cr.test.mjs` 的真实 CR 夹具跑 1 MiB < 输出 < 10 MiB 的 stdout/stderr 分区；分别检验 status=0 与真实非零。构造单段 > 10 MiB，校验错误 JSON 中 `TEST_OUTPUT_EXCEEDED` / ENOBUFS / 字节阈值 / null exit；前后逐字节比较 canonical 四类文件，不把诊断 log 发布。再回归超时、启动失败、skip、SHA256、幂等和多命令失败。命令只读/临时路径可重复执行，不把 >10 MiB 输出直接回显终端。
2. B：使用 `merge-fixture.mjs`、`writeback-tx.test.mjs`、`archive-tx.test.mjs` 的临时仓夹具，分别从 KB 主 checkout / CR worktree / txws 中**合法且对应阶段可用**的入口执行终态命令；断言同一个 install-root audit.log 中的 kind、真实 actor、阶段、dedup key，原临时 authority 被清理后没有因追加审计重建。重放从仍存在的入口执行，计数同一业务事件不增加；merge 若已不可合法重入，则按既有状态机检查拒绝且无新成功审计。模拟失败/恢复时不改 journal 或 Git 证据。
3. C：对普通 CR 的“误设全仓”以及“子集命令宣称全量”各构造 plan/TASK 评审案例，应 BLOCK；修订为覆盖 FR/AC 的定向 `cmd-NN` 后 plan 与 TASK 声称范围一致，应不因全量缺失而 BLOCK。再核对上游同步案例：保留全量运行及 Windows 基线失败原文，不作为该普通 CR 的绿色关键 `cmd-NN`；已批准全量绿色则不能替代。

目标测试仅覆盖本次变更关联的 crctl / Skill 合同测试，并执行 `lint-prompts`、`check-skill-matrix` 等现有文档校验；计划期选命令要按实际覆盖面，不把已知失败的全量套件作为本 CR 默认验收条件。

## 5. 技术选型与替代方案

- **有界同步收集**：10 MiB 固定容量与现行 `spawnSync`、临时日志和原子发布最小兼容；流式收集改变执行/证据生命周期、无界 buffer 可拖垮进程，均不选。阈值实际容量以 `maxBuffer` 字节为准，诊断必须曝光同一数值。
- **根由 resolver 提供、身份事前冻结**：`ctx.installRoot` 已由运行时解析；重新派生根会在目录删除时失效。保留 authority 对事务和 Git 的作用，仅审计改根，避免为了修 B 重写 merge/writeback 算法。install-root 日志仍是本机忽略目录，跨机器保障需另案。
- **Skill 约束而非机器字段**：C 是评审语义与证据选择问题；沿用现有表/评审回修，不为普通 CR 新开 schema、全量门禁或 pipeline 节点。

## 6. FR 与 AC 逐项设计和验收映射

| FR | 设计落点 / 验收承诺 |
|---|---|
| FR-1 | §2、§3.1 固定 10 MiB 有界同步缓冲，完整分区日志和真实元数据 |
| FR-2 | §3.1 非零/超时/启动失败各走既有结果分类 |
| FR-3 | §3.1 ENOBUFS 专用技术错误，在 canonical 发布之前硬失败 |
| FR-4 | §3.2 三命令 adapter 统一根、actor 事前冻结，writeback advance 同根 |
| FR-5 | §2、§3.2 三入口、清理及 journal 幂等审计，禁止补造旧事实 |
| FR-6 | §3.3 plan 的关键 cmd 与批准验收面双向对齐 |
| FR-7 | §3.3 TASK 继承与 review blocker / 合法回修 |
| FR-8 | §3.3 上游全量保留原始失败与基线对照；无新机器字段 |

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §3.1 / §4.1 | >1 MiB <10 MiB 运行的完整 stdout/stderr、真实 exit/signal/skip/timeout、log SHA | 单段低于新阈值，非超时命令可到记录阶段 |
| AC-2 | §3.1 / §4.1 | 真实非零→block，超时→旧超时类，启动失败→旧技术类 | 三种条件用独立输入；不被 ENOBUFS 分支吞掉 |
| AC-3 | §3.1 / §4.1 | >10 MiB 出 ENOBUFS、阈值、exitCode:null、非零技术退出；canonical 字节不变 | 单段输出超过阈值；在 skip 和结果写入前触发 |
| AC-4 | §3.2 / §4.2 | 三合法入口的三种审计归同一根、真实 actor、无已删目录重建 | 每条命令只在其合法阶段入口调用；身份在清理前固定 |
| AC-5 | §2 / §3.2 / §4.2 | 同一 tx/阶段重放不增加同一业务事件；无历史倒填 | 回放从存活 install-root 发起，复用 journal 稳定标识 |
| AC-6 | §3.3 / §4.3 | 普通 CR 误设全仓 BLOCK；定向 cmd 与 TASK 继承一致、不声称全量 | 无批准全量 AC 的正常 CR 案例，review 能读取两张表 |
| AC-7 | §3.3 / §4.3 | 子集冒充全量 BLOCK；上游仍全量并保留 Windows 原始失败+基线 | 分开构造普通 CR 与上游同步；批准全量的例外不降级 |

## 7. 安全与性能考量

`maxBuffer` 是每子进程有界内存而非日志无限累积；10 MiB 长输出回归控制 fixture 日志尺寸与终端回显。发生 ENOBUFS 即停止本轮证据发布，防止误读不完整输出。审计仍沿用本机 Git 忽略 `.crctl/`、原 JSONL append、非法 JSONL 拒绝去重写入；不把 Git 身份名等同服务端强鉴权身份，不向未知 actor 写可误导的事实。测试不触碰共享服务或业务数据库。

### 既有实现依赖与事实

以下依据 `resources[].worktreePath` 中的 tools HEAD `668a9f62141e0fb9310aa40df0ff17ca86e0abfd` 和 multica HEAD `820bb5a11a53463486383c4c1f5e9c17c5a9a43e` 核对；编号顺序为正文首次引用，正文设计引用下列 `dep-N`，不从其他 checkout 混取：

- dep-1
  - repo: tools
  - relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
  - stable symbol/对象: runTestPlan
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: `spawnSync` 配置已有 cwd/encoding/shell:false/timeout/env 但无 maxBuffer；在 `r.error` 分类前写临时分区 log、计算 skip 和 log SHA；非超时 error 分类为 `TEST_EXECUTABLE_INVALID`，非零/超时归 block。
- dep-2
  - repo: tools
  - relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
  - stable symbol/对象: testCr
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: `runTestPlan` 先于 test 的 journal/锁/机器报告与 trace/attempt 写入调用；抛 `TxError` 不能进入 canonical 发布。
- dep-3
  - repo: tools
  - relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
  - stable symbol/对象: deriveInstallRoot / resolveRepositories
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: 前者用 git common-dir 解析安装根，git 查询失败回退传入 opWs；后者对合法 workspace 返回 `ctx.installRoot`。
- dep-4
  - repo: tools
  - relative path: skills/shared/crctl/scripts/crctl.mjs
  - stable symbol/对象: identity / auditLog / auditLogOnce / cmdMerge / cmdWritebackApply / cmdArchive
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: `identity(ws)` 先读该目录 `.crctl/config.json` 后查 git user.name，否则 unknown；merge 审计用 authWs，writeback advance 和终态、archive 终态用 ws；auditLogOnce 只按传入根的 audit.log 去重；archive 调用完事务才调用 identity(ws)。当前 merge/writeback/archive 的普通终态 auditLog 均非去重，需在本 CR 范围内补足 AC-5，而非假称原已具备。
- dep-5
  - repo: tools
  - relative path: skills/develop/write-dev-plan/SKILL.md
  - stable symbol/对象: 两张稳定表 / 验收证据 cmd-NN / AC 业务闭环覆盖矩阵
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: 已要求关键 AC 绑定唯一 cmd-NN 且观测面不窄于声称面，并列子集测试不可声称全量；尚无普通 CR 默认不设全仓门槛的明示口径。
- dep-6
  - repo: tools
  - relative path: skills/develop/write-dev-tasks/SKILL.md
  - stable symbol/对象: TASK 验收条件 / 完成标志
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: TASK 目前按 plan 拆分，含验收条件和完成标志；尚未显式禁止无批准依据的额外全量通过条件。
- dep-7
  - repo: tools
  - relative path: skills/develop/review-dev-plan/SKILL.md
  - stable symbol/对象: plan/TASK 八类评审 / blocker 双轨回修
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: 评审已有证据ID/实际观测与声称验收面检查及 BLOCK 回修入口；普通 CR 无批准全仓要求却设为必过时的 blocker 尚需明示。
- dep-8
  - repo: multica
  - relative path: CUSTOM.md
  - stable symbol/对象: 合并冲突总则 / 合并后必跑 / 已知测试失败基线
  - commit SHA: 820bb5a11a53463486383c4c1f5e9c17c5a9a43e
  - 依赖结论: 上游同步时全量执行 `pnpm typecheck`、`pnpm test`、`make test`（或 `make check`），Windows/已知失败基线要对照，不得将普通 CR 的定向验收替代该规则。
- dep-9
  - repo: tools
  - relative path: skills/shared/crctl/scripts/test/merge-fixture.mjs
  - stable symbol/对象: makeCodeApprovedFixture / runCrctl
  - commit SHA: 668a9f62141e0fb9310aa40df0ff17ca86e0abfd
  - 依赖结论: 提供三仓 bare origin 的临时 git 夹具与执行 CLI 的测试 helper，可隔离合并/回写/归档审计测试而不触碰真实 CR。

设计依赖 dep-1 / dep-2 规定 A 的分类与发布边界；dep-3 / dep-4 规定 B 的解析、身份与去重修复点；dep-5 / dep-6 / dep-7 / dep-8 规定 C 的提示词与上游例外；dep-9 仅为验证夹具。无待核实依赖。

## 8. 批准范围

- `scope_in`：A：FR-1～FR-3 / AC-1～AC-3，在 tools `runTestPlan` 加 10 MiB 有界 buffer、ENOBUFS 技术分类及定向回归；B：FR-4～FR-5 / AC-4～AC-5，在 tools 三终态 CLI adapter 将审计根统一为 `ctx.installRoot`、事前绑定 actor、必要的终态业务审计去重与三入口/清理/重放回归；C：FR-6～FR-8 / AC-6～AC-7，修订 tools 三个 develop Skill 的定向证据、TASK 继承、评审 blocker 口径并验证正常 CR / 上游同步案例。
- `scope_out`：不改状态机、gate、ledger schema、merge/writeback/archive 事务算法；不新增 plan/test-plan 字段、机器门禁、Pipeline 节点或 HTTP API；不修改 multica 代码/CUSTOM.md（仅按其上游同步规则取证）、不伪造历史审计，不提供跨机器/服务端持久审计。
- `zero_diff`：`skills/shared/controlled-shell/rules.json` deny/allow 配置、`pipeline-templates/`、`skills/shared/crctl/gates.json`、`tools/dir-graph.yaml` 状态机及 `lib/durable-tx.mjs` 的事务协议均不修改；不修改 `runTestPlan` / `testCr` 与三终态 CLI adapter 的对外签名，不手改受控账本。`crctl.mjs` 内部审计调用点**允许**修改，不列入 zero_diff。
- `follow_up`：如需要跨机器或服务端审计保证，另案设计 outbox 投影及服务端验收；本 CR 的 AC 不依赖该能力。旧 070/071/072 审计缺失仅留历史，不回填。

本 CR 仅修改 `crctl.mjs` 的既有命令 adapter 内部审计调用，不新增/改变 dispatch 分支，不触碰 controlled-shell deny；因此不触发 Prompt 采纳影响必填条件。无数据库 schema、数据迁移或写路径鉴权变更。
