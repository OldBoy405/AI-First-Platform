---
id: CR-2026-041-sdd
type: SDD
cr-ref: CR-2026-041
title: tools CR 生命周期最小优化 4/5 — 归档可信化技术设计
status: draft
created: 2026-08-15T16:54:04+08:00
updated: 2026-08-15T16:54:04+08:00
---

# 1. 架构概览

## 1.1 当前实现与问题定位

目标代码仓是 Tools（`dir-graph.yaml#repositories.tools`，`trunk: custom/main`）。本 CR 只改该仓的方法论包代码，故其 `ARCHITECTURE.md` 是正确的架构基线（已存在，只读引用，不改）。

当前 `specs/{spec}/traceability.yml` 的新 milestone 段由 `skills/writeback/scripts/writeback-traceability.mjs`（candidate-only 固定 generator）构造，只含 `merge-commits`（从 `merge-commits.yml` 提取）与 `fr-chain`（从 milestone-file 读取），**没有测试/评审/审批/merge 的最小证据摘要**。`crctl archive` 在 `archiveCr` 的 writing-back 前置只校验 tasks 全 done、`specs/{spec}/traceability.yml` 存在、`approval.yml` 存在，**不校验证据真实、完整、可复算**。由此产生两类生命周期漏洞：

1. **证据投影缺失**：baseline 承诺"里程碑含测试、评审、审批证据"，但 generator 从未生成，archive 也不拦。
2. **事实源与文案漂移**：generator 的 trunk 提取仍带 `|| 'master'` 回退（`writeback-traceability.mjs:79`），头注释、`fromBacklog` 变量名与错误文案仍声称 merge 来源为 `_backlog.yml`（实际自 TASK-08 起已改读 `merge-commits.yml`）。
3. **虚假能力声明**：`change-impact-analysis` 建立在不存在的 `requirements[].reviews.*.result=stale` schema 上；`feedback-writeback` 只有 prompt 契约、直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突的 inbox。二者作为 active Skill 存在于索引/矩阵/Agent/README/dir-graph hint/inbox allowlist 中。

## 1.2 目标架构

```text
writeback-traceability.mjs（版本化脚本，确定性转换）
  -> 读 milestone-file（业务正文）
  -> 读 merge-commits.yml（merge 事实，trunk 硬失败无 master 回退）
  -> 读 7 份 canonical 证据文件（test/reviews/approval/merge）
  -> validateEvidenceInputs 自检通过
  -> buildSegment 注入 evidence 块、不写 status
  -> candidate-only 输出（复用既有 writeCandidate / manifest / SELF_CHECK）

archiveCr（crctl 深模块）
  -> acquireLock（既有 archive lock）
  -> loadExistingJournal 只读分流：
       已 commit/push 或 cleanup/complete -> 既有恢复，跳过证据门
       无 journal / pre-authority journal -> validateMilestoneEvidence 硬门
  -> 通过后 loadOrCreateJournal + 四账本 write-set + commit + lease push + cleanup
```

generator 与 archive gate 共享同一份**确定性证据契约**（key 名、digest 规范化、status/verdict 派生规则），但按仓库既有 `computeInputDigest`/`writebackInputDigest` 先例采用"两侧独立内联 + 测试交叉验证防漂移"，不新建共享模块（PRD FR-08 / ponytail）。

## 1.3 模块职责与深模块边界

| 模块 | 职责/接口 | 明确不拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | Skill 完整算法、账本拼接、Git 恢复 |
| `writeback-traceability` Skill | 起草 milestone 业务正文，调用一次 `crctl writeback-apply` | 证据算法、digest、账本/CAS/事务 |
| `writeback-traceability.mjs`（版本化脚本） | milestone 段确定性构造 + evidence 注入 + 事实源修正 | 状态推进、审批、Git 发布 |
| `crctl.mjs` | 参数解析、`archive` 子命令接线、结构化输出 | 证据业务判断、事务内部算法 |
| `workspace-transactions.mjs` | `archiveCr` 证据门 + `validateMilestoneEvidence` | LLM 评审结论、里程碑业务内容 |
| `durable-tx.mjs` | 既有 journal/锁/write-set/恢复 | 证据语义、Git、状态机 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

本 CR 的深模块是 `archiveCr` 的证据门：调用方（`crctl archive`）只掌握 CR、spec-id 与结构化错误；证据定位、digest 重算、grant/merge 校验、pre-authority 分流都隐藏在 `archiveCr` 内。不新增 `traceability-record`、evidence registry、archive gate plugin 或第二事务框架。

## 1.4 已解决基础设施（只复用，不重做）

| 能力 | 现有实现 | 本 CR 处理 |
|---|---|---|
| durable transaction | `durable-tx.mjs`：journal envelope、目录锁、recoverable write-set、`loadExistingJournal`/`loadOrCreateJournal` | 全量复用；证据门在锁内、新 journal 前 |
| archive 四账本事务 | `archiveCr`：backlog/history/index/cr.md 同批 write-set + commit + lease push + cleanup-pending + outbox | 复用；只插入 pre-authority 证据门 |
| writeback-apply | `applyWritebackAtomic`：固定 generator、manifest 全矩阵校验、真实 generator hash、CAS、commit/push | 全量复用；本 CR 不做生产改动，只补回归 |
| 固定 generator 映射/hash | `WRITEBACK_GENERATORS`（`baseline/tasks/traceability`）+ `actualGeneratorSha` 比对 | 复用；FR-03 只回归确认 |
| review-record | 四份 `review-annotations/{requirement,sdd,dev-plan,code}.yml` | 复用为 review 证据事实源 |
| merge/approval/test 事实源 | `merge-commits.yml`、`approval.yml`、`test-report.md` 机器区 | 复用为证据事实源 |
| `parseYaml`/`matchEntryBlock`/`sha256`/`readHashRaw` | `yaml-subset.mjs`、`lib.mjs` | 复用为解析与 digest 原语 |
| CONTEXT.md / CUSTOM.md | 终态反馈事实 + `CUSTOM-TODO-010` | 保留，不新建实现 |

## 1.5 本次最小改造

| 改造点 | 文件 | 性质 |
|---|---|---|
| 注入 `evidence` 块 + 不写 status | `skills/writeback/scripts/writeback-traceability.mjs` | 版本化脚本确定性转换 |
| trunk 去 `master` 回退 + backlog 文案清理 | 同上 | 事实源修正（删一行 fallback + 改文案） |
| 证据门 + `validateMilestoneEvidence` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `crctl` 深模块扩展 |
| milestone-file 契约去掉 `status: writing-back` | `skills/writeback/writeback-traceability/SKILL.md` | 文本契约同步 |
| 删除两个退役 Skill + 清理 active 引用 | 见 §6 | 删除 |

# 2. 数据模型

## 2.1 evidence 块 schema（milestone 级，canonical 契约）

```yaml
evidence:
  test: { status: pass, path: change-requests/CR-.../test-report.md, sha256: ... }
  reviews:
    requirement: { verdict: pass, path: change-requests/CR-.../review-annotations/requirement.yml, sha256: ... }
    tech-design: { verdict: pass, path: change-requests/CR-.../review-annotations/sdd.yml, sha256: ... }
    dev-plan: { verdict: pass, path: change-requests/CR-.../review-annotations/dev-plan.yml, sha256: ... }
    code: { verdict: pass, path: change-requests/CR-.../review-annotations/code.yml, sha256: ... }
  approval: { status: approved, path: change-requests/CR-.../approval.yml, sha256: ... }
  merge: { status: merged, path: change-requests/CR-.../merge-commits.yml, sha256: ... }
```

字段语义（固定，不允许模型誊抄）：

| key | `status`/`verdict` 派生 | 门禁附加校验 |
|---|---|---|
| `test` | `test-report.md` frontmatter `status` | 必须 `pass` |
| `reviews.requirement` | `requirement.yml` `verdict` | 必须 `pass` |
| `reviews.tech-design` | `sdd.yml` `verdict` | 必须 `pass` |
| `reviews.dev-plan` | `dev-plan.yml` `verdict` | 必须 `pass` |
| `reviews.code` | `code.yml` `verdict` | 必须 `pass` |
| `approval` | 派生 `approved`（四段齐全） | `requirement/tech-design/development-start/code` 四段均存在且 `via ∈ {crctl-approve, server-approve}` |
| `merge` | 派生 `merged`（合并事实存在） | `schema=merge-commits/v1` 且 `repositories[]` 非空、每项含 `repo`+`merge-sha` |

## 2.2 digest 规范化（与 CAS 锚点区分）

- **证据 `sha256`**：`sha256(normalize(fileBytesUtf8))`，`normalize` 只做 `\r\n -> \n`。跨平台（Windows/Ubuntu）对同一语义内容得到相同值。
- **before/after CAS 锚点**：沿用既有 `readHashRaw`（磁盘字节哈希，不 CRLF 归一）。二者语义不同，不得混用：证据 digest 是跨平台可比的内容摘要，CAS 锚点是本地磁盘字节锚点。

## 2.3 milestone 段变化

- 新 milestone 段结构 = `cr` + `milestone` + `target-version` + `merge-commits` + `frs` + `evidence`（追加在 `frs` 之后）。
- **删除 `status` 字段**（FR-05）：新 milestone 不写瞬时 `writing-back`、不提前写 `archived`。CR 状态继续只由 `cr.md`/`_history.yml` 表达。
- 既有历史 milestone 段（含 CR-2026-038/039/040 已写入的 `status: writing-back`）作为 opaque 段逐字节保留。

# 3. 接口契约

## 3.1 generator 侧（`writeback-traceability.mjs`）

- 新增内部纯函数 `readEvidenceInputs(crDir)` -> `{ test, reviews, approval, merge }`（含 digest）。
- 新增内部纯函数 `validateEvidenceInputs(crDir)`：任一输入缺失/状态不通过/结构非法 → `fail('EVIDENCE_INVALID', ...)`，零 candidate 输出。
- `buildSegment()` 在 `frs` 后追加 `evidence:` 块；不再输出 `status` 行。
- trunk 提取：`trunkOf(repo)` 返回 `null` 时 `fail('TRUNK_UNKNOWN', ...)`，删除 `|| 'master'`。
- 文案清理：头注释、`fromBacklog` 变量、`MERGE_COMMITS_MISSING` 相关错误文案中的 `_backlog.yml` 全部改为 `merge-commits.yml`。
- SELF_CHECK 增加断言：candidate 内 `evidence:` 块恰好出现一次、`test/reviews(4)/approval/merge` 七项齐全、无 `\r`、既有段字节不变。

## 3.2 archive gate 侧（`workspace-transactions.mjs`）

新增导出纯函数：

```text
validateMilestoneEvidence({ traceText, cr, specId, editRoot }) -> { ok: true } | throw TxError
```

行为：

1. 定位 `traceText` 中当前 CR 的 milestone 段（按 `- cr: {cr}`，不依赖 `status`）。
2. 解析 `evidence` 块；缺失/重复/milestone 重复/evidence key 重复 → `ARCHIVE_EVIDENCE_MISSING`/`ARCHIVE_EVIDENCE_DUPLICATE`。
3. 每条证据路径必须位于 `change-requests/{cr}/` 下（防跨 CR 指向），否则 `ARCHIVE_EVIDENCE_PATH_INVALID`。
4. 从 `editRoot` 重读 canonical 文件，LF 归一后重算 digest，与 evidence `sha256` 比对；不一致 → `ARCHIVE_EVIDENCE_DRIFT`。
5. 校验 status/verdict/四 grant/merge 事实，不通过 → `ARCHIVE_EVIDENCE_STATE`（带缺失项明细）。
6. 全部通过 → `{ ok: true }`。

## 3.3 `archiveCr` 插入点（pre-authority 分流）

在 `acquireLock` 之后、`loadOrCreateJournal` 之前插入只读分流：

```text
existing = loadExistingJournal({ op: 'archive', key: cr, inputDigest })
p = existing?.journal?.archive
needsEvidence = !existing
  || !(p && (p.committed || p.pushed || p.phase === 'cleanup-pending' || p.phase === 'complete'))
if needsEvidence:
    opWs = resolveOperationalWorkspace(ctx, cr)   # 只读
    if opWs.phase === 'writing-back':
        if !specId -> TxError ARCHIVE_SPEC_REQUIRED
        validateMilestoneEvidence({ traceText: read(specs/{specId}/traceability.yml), cr, specId, editRoot: opWs.path })
    # rejected/withdrawn：无 writing-back milestone，跳过
# 之后沿用既有 loadOrCreateJournal + 四账本流程（其内部 status 判定不变，重复 resolve 只读幂等）
```

失败语义：证据门失败释放 lock，不创建/不修改 journal，零 authority 写入、零审计，可补齐后同一命令重试。已 commit/push 或 cleanup/complete 的恢复路径跳过证据门，避免 cleanup 续跑时 CR worktree 已删导致解析失败。

## 3.4 错误码

| 错误码 | 触发 | 层 |
|---|---|---|
| `EVIDENCE_INVALID` | generator 侧输入状态不通过/缺失 | 版本化脚本 |
| `TRUNK_UNKNOWN` | trunk resolver 缺条目 | 版本化脚本 |
| `ARCHIVE_EVIDENCE_MISSING` | 当前 CR milestone/evidence 缺失 | crctl |
| `ARCHIVE_EVIDENCE_DUPLICATE` | milestone/evidence key 重复 | crctl |
| `ARCHIVE_EVIDENCE_PATH_INVALID` | 路径越界/跨 CR/非本 CR 前缀 | crctl |
| `ARCHIVE_EVIDENCE_DRIFT` | digest 重算不一致 | crctl |
| `ARCHIVE_EVIDENCE_STATE` | verdict/status/grant/merge 事实不通过 | crctl |

既有 `ARCHIVE_TASKS_PENDING`/`ARCHIVE_TRACEABILITY_MISSING`/`ARCHIVE_APPROVAL_MISSING` 保持不变。

# 4. 关键算法与流程

## 4.1 证据生成（generator）

```text
crDir = workspace/change-requests/{cr}
test    = readFrontmatter(crDir/test-report.md).status            # 必须 'pass'
reviews = for file in [requirement, sdd, dev-plan, code]:
            verdict = parseYaml(crDir/review-annotations/{file}.yml).verdict   # 必须 'pass'
approval= parseYaml(crDir/approval.yml)                            # 四段齐全 => 'approved'
merge   = parseYaml(crDir/merge-commits.yml)                       # repositories[] 有 merge-sha => 'merged'
evidence = { test: {status, path, sha256(归一内容)}, reviews: {...}, approval: {...}, merge: {...} }
buildSegment 追加 evidence 块
```

digest 用 `sha256(normalize(readFile(p)))`；路径为 workspace 相对 POSIX 路径 `change-requests/{cr}/...`。

## 4.2 证据校验（archive gate）

与 §4.1 同规则，但方向相反：从 `traceText` 读 evidence 块 → 重读 canonical 文件 → 重算 → 逐项比对。generator 与 gate 两侧实现同一契约，测试交叉验证防漂移（同 `inputDigest` 先例，见 §5）。

## 4.3 archive pre-authority 分流

```text
lock(archive-{cr})
existing = loadExistingJournal(...)
if 无 journal 或 pre-authority journal:
    if writing-back: validateMilestoneEvidence(...)   # 失败 -> 释放 lock, 零写入
    # rejected/withdrawn: 跳过
loadOrCreateJournal(...)     # 通过后才创建/修改 journal
recoverWriteSet / 四账本编辑 / commit / lease push / cleanup   # 既有流程不变
```

# 5. 技术选型与替代方案

| 决策 | 选择 | 理由 / 弃用 |
|---|---|---|
| 共享证据契约的实现方式 | 两侧独立内联 + 交叉验证测试（沿用 `computeInputDigest`/`writebackInputDigest` 先例） | 弃用新建共享模块/registry：跨"版本化脚本"与"crctl 深模块"两个可执行体，无低耦合共享点；先例已证明内联+测试可行且 ponytail 最小 |
| 证据门位置 | archive lock 内、`loadOrCreateJournal` 前 | 弃用锁外预检：锁外无法串行化 journal 竞态；弃用新建"事务前置层"：只需把只读 `resolveOperationalWorkspace` 提前一次 |
| digest 语义 | LF 归一内容哈希 | 弃用 raw-bytes 哈希：证据要跨平台可比；raw 保留给 CAS 锚点 |
| 历史 milestone | opaque 逐字节保留，不迁移 | 弃用批量回填/伪 digest |
| 退役 | 删除文件 + active 引用，Git 历史兜底 | 弃用 retired stub / 占位 Skill |

# 6. FR 到技术实现映射

| FR | 实现条目 | 落点 |
|---|---|---|
| FR-01 最小证据摘要 | `readEvidenceInputs` + `buildSegment` 注入 `evidence` 块 | `writeback-traceability.mjs` |
| FR-02 事实源修正 | `trunkOf` 硬失败删 `master` 回退；`fromBacklog`→`fromMergeCommits`；注释/错误文案改 `merge-commits.yml` | `writeback-traceability.mjs` |
| FR-03 generator 身份既有回归 | 不改生产；补回归测试断言 `WRITEBACK_GENERATORS` 与 `actualGeneratorSha` | `test/` |
| FR-04 archive 证据门 | `validateMilestoneEvidence` + `archiveCr` pre-authority 分流 | `workspace-transactions.mjs` |
| FR-05 历史 opaque / 无 status | `buildSegment` 删 `status` 行；历史段字节保留断言不变；SKILL.md 去 `status: writing-back` | `writeback-traceability.mjs` + 其 SKILL.md |
| FR-06 change-impact 退役 | 删 `skills/review/change-impact-analysis/SKILL.md`；清 `skills/_index.yml`、`agent-skill-matrix.yml`（quality-reviewer owns）、`AGENT-SKILL-MATRIX.md`、`agents/quality-reviewer-agent.md`、`agents/_index.yml`、`dir-graph.yaml#skill_context.change-impact-analysis`、`README.md`、`docs/QODER-使用指南.md`、`openwiki/architecture/agent-skill-matrix.md`；`review-alignment/SKILL.md` 删 AL-07 与"与其他 Skill 关系"中的 change-impact 行 | 删除+编辑 |
| FR-07 feedback 退役 | 删 `skills/cr/feedback-writeback/SKILL.md`；清 `skills/_index.yml`、矩阵/Agent/README/docs/openwiki；`inbox-emit/SKILL.md` 删 `feedback-writeback-done` allowlist 项；保留 `CUSTOM.md#CUSTOM-TODO-010` 与 CONTEXT.md | 删除+编辑 |
| FR-08 职责边界 | 不新增模块；改动只落版本化脚本与 `crctl` 深模块 | 全仓约束 |

退役引用边界：`docs/二开修改报告_v2.html`、`docs/AI-First-研发协同平台-架构讲解.html` 属历史报告/快照，保留不改（PRD FR-06.4/FR-07.5）。

# 7. 安全与性能考量

- **零副作用失败**：证据门在 journal 创建/修改前执行，失败释放 lock，无 journal/authority/审计残留。
- **路径 containment**：证据路径必须是 `change-requests/{cr}/` 前缀的相对 POSIX 路径，拒绝绝对路径、`..`、反斜杠与跨 CR 前缀。
- **digest 不可伪造**：digest 由代码重算，不信任 milestone-file/manifest 自报；generator hash 由 `writeback-apply` 对固定脚本计算。
- **CRLF 纪律**：所有解析与 digest 输入先 LF 归一；跨行正则/解析失败硬失败（对齐工程纪律第 1 条）。
- **性能**：证据门为 7 个小文件的常数次读+hash，不引入额外持久化模型或后台任务；不缓存、不并行。
- **极简**：不新增 npm 依赖、schema registry、错误码中心、通用 traceability 接口、事务框架或强授权字符串模型。

# 8. 测试设计（与 §12 测试矩阵对齐）

- generator：证据七项齐全、digest 可复算、CRLF/LF 同 digest、trunk 缺条目硬失败、merge 缺字段硬失败、新 milestone 无 status、历史段字节不变、SELF_CHECK。
- archive gate：证据齐全归档成功；milestone/evidence 重复、跨 CR 路径、digest 漂移、verdict/status 非 pass、approval 缺 grant、merge 缺事实均硬失败且零 journal/authority 写入。
- pre-authority 分流：无 journal 校验；pre-authority journal 校验且失败不改 journal；已 commit/push 与 cleanup/complete 恢复跳过；rejected/withdrawn 跳过。
- FR-03 回归：`WRITEBACK_GENERATORS` 与 `actualGeneratorSha` 既有测试保持通过。
- 退役：静态扫描证明 active 路径零 `change-impact-analysis`/`feedback-writeback`/`feedback-writeback-done` 引用，且 `CUSTOM-TODO-010` 保留。
- 跨平台：Ubuntu/Windows 全量通过，不引入新生产依赖。

# 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-15 | v0.1.0 | Ray | 初始草稿：evidence 注入、archive 证据门、事实源修正、双 Skill 退役、职责边界 |
