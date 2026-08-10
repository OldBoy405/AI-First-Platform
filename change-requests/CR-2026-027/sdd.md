---
id: CR-2026-027-sdd
type: SDD
cr-ref: CR-2026-027
title: tools 流程优化 Phase 0+1 — 基线事实统一与正确性修复 技术设计
status: draft
created: "2026-08-09T22:50:00+08:00"
updated: "2026-08-09T22:50:00+08:00"
---

# SDD — CR-2026-027：tools 流程优化 Phase 0+1

## 1. 架构概览

### 1.1 改动面分层

本 CR 的目标代码仓是 **tools 仓自身**（修改 `crctl.mjs`、Skills、`ARCHITECTURE.md`）与 workspace 声明层，按 v2 方案 §5.2/§6 的最小修改集合落地：

```text
workspace 声明层（ai-first-platform-docs 仓）
  AGENTS.md                  # 状态机口径 25/47 → 27/49（工程纪律 #2 同步）
  dir-graph.yaml             # repositories 新增 tools（FR-5/FR-15 bootstrap 第一步）
  docs/analysis/tools流程步骤优化v2.md  # 删除旧方案 command module 与通用上下文命令描述（FR-6）
  CONTEXT.md                 # 已随注册前置提交修正，本 CR 复核不动

tools 文档层（tools 仓）
  ARCHITECTURE.md            # §3/§5 状态机口径 27/49；§4 crctl-Pipeline 依赖描述修订（FR-3）；
                             # §3 确认 crctl 单文件（FR-2）；§8 登记本 CR；指标基线固化（FR-7）

tools 执行层（tools 仓 crctl.mjs + crctl.test.mjs）
  approve 原子提交（FR-8）        # 内部 helper，不新增子命令
  archived TASK 门禁修复（FR-9）  # 修复 deliveryIndexComplete checker 实现，不改 gates.json
  幽灵条目迁移清理（FR-10）      # 扩展 cmdMigrateBacklog，不新增独立脚本目录
  archive-move 原子化（FR-11/FR-12 账本面）  # 事件 + 三账本同一 CAS
  终态只读 resolver（FR-12 查询面）          # status/next 专用
  review-record 输出深化（FR-13） # 返回 files/attempt/route/repairTarget
  inbox-emit 空 to 硬失败（FR-11）# BAD_ARGS

tools Skill 提示词层（tools 仓）
  merge-feature-branch/SKILL.md  # 删除 tools 隐藏特例（FR-5）
  四个 review Skill               # 删除 traceability 二次读取（FR-13）
  cr-archive/SKILL.md            # 同步 archive-move 三账本契约（FR-4/FR-11）
```

### 1.2 关键流程变更（前后对比）

| 流程 | 现状 | 目标 |
|---|---|---|
| approve | 写 approval.yml（一提交）→ cmdAdvance 只 stage cr.md（另一提交）；失败可能单文件半状态 | 预检 → 内存生成两文件 → casWriteMulti → 单次 commit → 成功后发 status outbox（FR-8） |
| 归档 | embedded advance 到 archived → inbox-emit 独立发事件（中文 JSON 转义失败即永久丢失）→ archive-move 只写 backlog/history | embedded advance → archive-move 内存构造事件 + backlog/history/index 三文本 → 同一 casWriteMulti → 成功后发 archive outbox（FR-11） |
| 归档查询 | resolveCrState 强制读 backlog → CR_STATUS_NOT_FOUND | status/next 在 active 未命中时走终态只读 resolver（history final-status 权威，FR-12） |
| TASK 门禁 | deliveryIndexComplete 空 doneIds 放行 | 五步校验：index 存在 → tasks 非空 → 全 done → delivery index → 缺/空不得解释为 no-task（FR-9） |

### 1.3 执行顺序（实施期依赖）

1. **bootstrap（FR-15）**：workspace `dir-graph.yaml` 先加入 tools repo → 在 `../tools` 仓从 `custom/main` 创建 `requirement/CR-2026-027` worktree（`.rayai-worktrees/tools/requirement/CR-2026-027`，bucket = repo.id）→ 此后全部 tools 改动在该 worktree 提交，禁止直写 custom/main。**调用根固定**：`crctl worktree-path` 一律以 **AI First Platform 主工作区**为 `--workspace` 解析（不从 knowledge-base CR worktree 以 `--workspace .` 调用，避免得到嵌套 `.rayai-worktrees` 路径）；**基线固定**：worktree 创建时记录 `bootstrap-base-sha`（= custom/main HEAD），写入实施记录与 AC-22 验收断言，避免创建与后续 fetch 之间基线含义漂移。
2. Phase 0 文档统一（FR-1~FR-7）→ 3. Phase 1 执行层（FR-8~FR-14）→ 4. 五项最小验证（FR-14/AC-19）。

## 2. 数据模型

### 2.1 `_index.yml` 终态字段（FR-4/FR-11）

`archive-move` 更新 CR 对应条目，只写三个字段（D-2，全生命周期轻量目录）：

```yaml
status: archived | rejected | withdrawn
archived-at: "<ISO8601+08:00>"
writeback-spec-id: "<spec-id>"   # 有则写，无则不写
```

不复制 history 详情、不新增 `history-ref`、不删除条目；查询事实源不变（仍为 `_backlog.yml + _history.yml` + cr.md）。

### 2.2 archive event 载荷（FR-11）

归档事件与归档移动是同一业务事实，随三账本 CAS 同批写入。事件条目写入 **history 条目**的 notify-log（CR 已移出 backlog，backlog 无宿主条目），复用 `editInboxEmit` 的日志行格式（提取为共享行生成函数）：

```yaml
- at: "<ISO8601+08:00>"
  event: archived | rejected | withdrawn
  to: ["<owners.requirement.id>", "<owners.development.id>", "<owners.test.id>"]  # 去重后
  payload:
    final-status: archived
    archive-reason: "<reason>"          # 中文原文，不经 Shell 转义
    writeback-spec-id: "<spec-id>"      # 可选
    archived-at: "<ISO8601+08:00>"
```

收件人规则（D-10）：优先 `owners.{requirement,development,test}.id` 去重；条目缺 `owners` 时回退顶层 `owner`；最终为空 → CAS 前 `ARCHIVE_RECIPIENTS_MISSING`。不新增 submitter/reviewer 字段。

### 2.3 终态查询最小契约（FR-12）

`status`/`next` 对终态 CR 的输出：

```json
{
  "cr": "CR-2026-XXX",
  "status": "archived",
  "terminal": true,
  "source": { "history": "change-requests/_history.yml" },
  "legalNext": [],
  "reviewLoops": {},
  "gateBlockers": {},
  "next": null
}
```

`_history.yml` 条目以 `final-status` 为终态权威；history 重复条目或缺 `final-status` 硬失败（`HISTORY_DUPLICATE_ENTRY` / `HISTORY_FINAL_STATUS_MISSING`）；backlog/history 同存同 CR → `CR_LOCATION_CONFLICT`；cr.md 与 history 不一致时以 history 为准并输出 warning。不新增 archive reason/spec-id 等非必要字段，不新增 `archive-status` 命令。

### 2.4 review cycle 兼容扩展（FR-16/D-14）

`maxAttempts=3` 按审查 cycle 计数。已 PASS 后发生 upstream 设计修订时开启新 cycle，旧 attempts 不删除：

```yaml
loops:
  review-tech-design:
    current-cycle: 2
    current-attempt: 1
    attempts:
      - { cycle: 1, attempt: 1, at: "...", by: "..." }
      - { cycle: 1, attempt: 2, at: "...", by: "..." }
      - { cycle: 1, attempt: 3, at: "...", by: "..." }
      - { cycle: 2, attempt: 1, at: "...", by: "..." }
```

- legacy `current-cycle` 缺失、attempt 缺 `cycle` 时均按 cycle=1 解释；
- traceability 的技术评审 attempts 同步增加 `cycle`，保留所有历史；
- `current-attempt` 只表示当前 cycle 的轮次，`attemptsWithinLimit` 只检查当前 cycle；
- 不新增账本类型或 crctl 子命令，不允许手工重置 review-loop。

## 3. 接口契约

### 3.1 内部 helper：approve-and-advance（FR-8，不新增子命令）

TTY 路径（`cmdApprove` 主流程）与 `--grant` 路径（`approveWithGrant`）收敛到同一 helper：

```
approveAndAdvance(ws, cr, gates, stage, stageCfg, { grant, signature, ... })
  1. 预检：current state / transition 合法性 / evidence（stageCfg.requireFiles）/ 签名（grant 验签）/
     passCondition / requireFiles → 任一失败 fail()，零文件写入
  2. 在内存生成 approval.yml 文本（复用 writeApprovalSection 行级生成逻辑）与
     cr.md 新文本（frontmatter status → 目标态）
  3. 按候选 approval 复核目标 gate：runGateChecks 以内存候选文本为证据源（见下 evidence override seam）
  4. casWriteMulti([approval.yml, cr.md])   # 两文件同一 CAS：全校验→全 temp→连续 rename
  5. controlledGit add 两文件
  6. controlledGit commit（单次提交，message 含 CR 号与 stage）
  7. commit 成功后 emitOutboxEvent(status) → auditLog
```

**候选证据 override seam（TD-BL-4 修订，实现零写入的前提）**：`readEvidenceDoc(ws, cr, rel, overrides)` 增加可选第 4 参 `overrides`（`{ [relPath]: { text } }`），命中时用内存文本走同一解析路径（frontmatter/YAML 解析复用现有逻辑），不落盘、不改磁盘读的默认行为。**key 匹配时点（TD2-S1 采纳）**：overrides 的 key 一律使用含 `{cr}` 占位符的规范相对路径（如 `change-requests/{cr}/approval.yml`），匹配发生在路径展开前——调用方与读取方都用占位符形式，避免一处展开一处不展开导致 miss。`runGateChecks(ws, cr, targetStatus, gates, opts)` 的 `opts` 增加 `evidence` 字段，内部把 `opts.evidence` 透传给所有 `readEvidenceDoc` 调用点（approval 文档 checker、passCondition checker 等）。`approveAndAdvance` 第 3 步调用形态：

```
runGateChecks(ws, cr, 目标态, gates, {
  specId,  // 按 stage 需要
  evidence: {
    'change-requests/{cr}/approval.yml': { text: approvalText },
  },
})
```

**候选 cr.md 独立 invariant 校验（TD2-BL-2 修订）**：现有目标态 gate（如 tech-design-reviewed）没有任何 checker 读取 cr.md，`runGateChecks` 只以 targetStatus 选择门禁，因此不得假设 gate 会验证候选 cr.md。新增内部 helper `assertCandidateStatus(crMdText, expectStatus)`：解析 `crMdText` 的 frontmatter `status`，不等于 `stageCfg.to`（目标态）→ `CANDIDATE_STATUS_MISMATCH` 硬失败（零写入），等于则通过。调用顺序固定为：内存生成候选两文件 → `runGateChecks`（evidence 仅 approval.yml）复核目标 gate → `assertCandidateStatus` 校验候选 cr.md → 全部通过才 `casWriteMulti`。

回归测试（§7.3 同步）：候选 approval 缺 `via`/签名 → `GATE_BLOCKED` 且零文件写入；候选 cr.md status ≠ 目标态 → `CANDIDATE_STATUS_MISMATCH` 且零文件写入（AC-9 用例扩展）。

边界：gate/签名预检失败零写入；CAS 冲突两文件均不写；commit 失败两文件共同留在工作区，返回结构化恢复信息（含 `next` 建议），不发 status outbox；拒绝路径不写批准段，继续走既有 reject 转换（REJECT_ROLLBACK 映射不动）。

**受控历史审批迁移 `approve --resign <reason>`（代码评审二轮 b10，不新增子命令）**：gates.json evidence 定义变更（如 dev-start 剔除 task-index）后，既有 approval 段仍按旧证据集签发 digest，门禁复算不一致报 EVIDENCE_DRIFT——这是定义变更而非内容篡改，提供受控迁移路径：

```
approveResign(ws, cr, gates, stage, stageCfg, { reason })
  1. TTY 人类在环硬检查（同 approve，无旁路）；非 TTY 一律 APPROVAL_REQUIRES_HUMAN
  2. 审批段必须已存在且曾由 crctl approve 写入（approver/approved-at/via 齐备）→ 否则 RESIGN_NO_PRIOR_APPROVAL；仅 `via=crctl-approve` 可迁移，`via=server-approve` → RESIGN_SERVER_APPROVAL_UNSUPPORTED（原签名绑定旧 digest，须服务端重签 grant）
  3. 按当前 gates.json evidence 定义重算 canonicalEvidenceDigest；缺失证据文件 → RESIGN_DIGEST_UNAVAILABLE
  4. 新 digest == 旧 digest → ok({ changed: false, reason: 'digest-already-current' }) 幂等返回
  5. 不一致 → 展示旧/新 digest 与原因，人工确认（只有 yes 才写）
  6. 确认后：resignApprovalSectionText 只替换该段 evidence-digest 行（保留 approver/approved-at/via/target-status），
     追加 resign 审计子块（at/by/from-digest/reason）；全部动态字符串经统一 YAML 标量序列化（覆盖双引号、反斜杠、换行）；幂等：先清旧 resign 子块再重建
  7. casWrite（单文件 CAS）→ auditLog(kind: approve-resign) → 单次 commit（不动 cr.md status，不新增子命令）
```

设计约束：① 仅限 TTY，人类在环，无旁路（治理⑤）；② 只迁移本地 `crctl-approve`，服务端签名审批必须重新签发 grant；③ 不改审批本体字段（approver/approved-at 保持历史事实），只迁移 digest 绑定；④ 每次迁移落 resign 审计子块与 audit 事件，可追溯；⑤ 重复 resign 幂等（digest 已一致则 no-op；文本变换先清旧 resign 块）。

### 3.2 `archive-move`（FR-11/FR-12 账本面）

```
crctl archive-move CR --final-status <archived|rejected|withdrawn> [--archive-reason <s>] [--spec-id <s>]
```

- 前置态放宽：`resolveCrState` 当前 status ∈ {archived, rejected, withdrawn}，且 `--final-status` 必须与当前 status 完全一致，否则 `FINAL_STATUS_MISMATCH` 硬失败（D-8）。
- 重复调用语义（TD-BL-3 拍板，替换「重复归档幂等」的模糊表述）：CR 已移出 backlog 后再次调用时，archive-move 走**受控只读 history 检测**（专用逻辑，不扩大为通用终态可写）：
  - history 存在同 CR 且 `final-status` === `--final-status` → 幂等返回 `{ op: 'archive-move', cr, result: 'already-archived', finalStatus: 'archived' }`（TD2-S2 采纳：携带 finalStatus 便于调用方审计命中哪个终态），零写入、不发 outbox；
  - history 存在同 CR 但 `final-status` ≠ `--final-status` → `FINAL_STATUS_MISMATCH` 硬失败；
  - history 无该 CR → `CR_STATUS_NOT_FOUND`。
  status/next 的终态 fallback（§3.4）与写命令的 active-only 约束不变：archive-move 的 history 检测是其账本移动职责的一部分，不新增其他写命令的终态可写性。
- 流程：读 backlog + history + index 三文本 → 内存构造 archive event 候选条目 → 生成三份新文本（backlog 移除条目、history 追加终态条目+notify-log、index 更新三字段）→ 收件人解析（缺则 `ARCHIVE_RECIPIENTS_MISSING`）→ `casWriteMulti` 三文件 → CAS 成功后 `emitOutboxEvent(archive)` → audit。
- 任一 event/文件结构错误或 CAS 冲突：事件与三份账本均不写。
- 不新增 `inbox-emit --payload-file`、archive 专用幂等键或新命令；普通通知继续用 `inbox-emit`。

### 3.3 `inbox-emit` 校验修正（FR-11）

`cmdInboxEmit` 增加 `--to` 校验：缺失、解析后非列表、去重后为空 → `BAD_ARGS`，不写无收件人 notify-log（与 Skill 契约对齐，B-13）。

### 3.4 终态只读 resolver（FR-12，仅供 status/next）

新增 `resolveTerminalCrState(ws, cr)`：仅从 `_history.yml` 读取；`cmdStatus`/`cmdNext` 在 active resolver 报 `CR_STATUS_NOT_FOUND` 时 fallback 调用；写命令（advance/approve/checkpoint-add/owner-set/backlog-set/inbox-emit/merge-metadata/review-record 等）**不** fallback，终态写入维持拒绝。

### 3.4a `cmdNext` active 路由与 freshness（FR-16）

`task-breakdown` 分支不再只检查 plan/tasks：

```text
读取 dev-plan.yml
  缺失/解析失败/缺 verdict 或 blockers → review-dev-plan
  PASS + blockers=[]                 → crctl approve --stage dev-start
  BLOCK                              → resolveDevPlanRoute(annotation)
    repair                           → write-dev-plan
    upstream                         → write-tech-design
  BLOCK 且当前 cycle exhausted       → next=null, humanApproval=true, why=LOOP_EXHAUSTED
```

route 必须从 canonical annotation 的顶层 `repair-target` 重算，不读取 `review-record` 的瞬时返回对象。

`tech-design-review-pending` 分支新增 freshness：

1. 读取 `sdd.yml#subject-sha256`，与当前 `sdd.md` LF 规范化 SHA-256 比较；
2. 读取 dev-plan annotation；若 `verdict=block`、`repair-target=write-tech-design` 且其 `reviewed-at` 晚于 sdd 技术评审 `reviewed-at`，视为 upstream stale；
3. digest 不一致或 upstream stale → `review-tech-design`；
4. 仅 fresh 且 PASS/无 blocker → `crctl approve --stage tech-design`。

legacy sdd annotation 无 subject digest 时：存在较新 upstream blocker 必须重审；否则保持旧兼容行为，不批量迁移历史 CR。

### 3.5 `review-record` 输出（FR-13）

保持 `file`、`trace` 兼容，返回对象新增：

```json
{
  "files": ["change-requests/{cr}/review-annotations/{stage-file}", "change-requests/{cr}/traceability.yml"],
  "attempt": { "current": 1, "max": 3, "bumped": false },
  "route": "pass | repair | upstream",
  "repairTarget": "write-requirement-prd | write-tech-design | write-dev-plan | implement-code | null"
}
```

- `files`：只列本次实际写入（annotation + traceability；bumped 时才含 review-loop.yml）。
- `attempt`：从 review-loop 当前轮次读取（复用既有 attempt 记账，bumped 表示本轮是否递增）。
- `tech-design` annotation 新增 `subject-file: change-requests/{cr}/sdd.md` 与 LF 规范化 `subject-sha256`，供 `cmdNext` freshness 判断。
- `route`/`repairTarget` 按**按 stage 判定的真值表**（TD-BL-2 修订，替换原「block 且 repairTarget=write-tech-design → upstream」的统一映射）：

| stage | verdict | 顶层 repairTarget | route | repairTarget 返回 |
|---|---|---|---|---|
| 任意 stage | pass（verdict=pass 且 blockers=[]） | — | `pass` | `null` |
| 任意非 dev-plan stage | block | 任意 | `repair` | `REVIEW_REPAIR_TARGETS[stage]`（既有默认修复目标） |
| dev-plan | block | `write-dev-plan`（默认） | `repair` | `write-dev-plan` |
| dev-plan | block | `write-tech-design`（显式上游设计疑点，resolveDevPlanRoute 既有判定） | `upstream` | `write-tech-design` |

  `upstream` 只适用于 dev-plan 顶层 `repair-target=write-tech-design` 的显式上游设计疑点；review-tech-design 自身的正常 blocker 属 `repair`（回放 `write-tech-design`），不得错分为上游轨。
- `--bump-attempt` 在写入 tech-design 评审前调用 `detectNewTechDesignCycle`：上一 annotation 为 PASS、存在较新的 dev-plan upstream blocker，且当前 SDD digest 与上一 `subject-sha256` 不同（legacy 无 digest 时以上游时间关系兜底）→ `current-cycle+1`、本 cycle attempt=1；旧 attempts 仅补 legacy `cycle=1` 后保留。普通 block→repair 仍在当前 cycle 内计数，达到 3 次继续 `LOOP_EXHAUSTED`。
- 不返回 `verified`（与退出码/CAS 成功重复）、subject digest（内部 freshness 用）、`next`（唯一由 `crctl next` 计算）。

### 3.6 `migrate-backlog` 扩展（FR-10）

扩展现有 `cmdMigrateBacklog`（v1→v2 布局迁移）增加幽灵条目清理阶段，**不新增子命令**、**不新增独立脚本**：

- 检测：解析 `_backlog.yml`，识别「无 `- id:`/`cr-id:` 归属的续行块」（B-12 形态：列表项字段缩进块后紧跟同缩进但无列表标记的 title 行）。
- 删除依据：`_history.yml` 中存在同 title 的完整归档条目（防误删在途 CR）。
- 执行：删除幽灵块（从幽灵 `title:` 行到块尾），CR-2026-017 条目自动恢复完整。
- 幂等：无幽灵块 → `{ migrated: false, reason: 'already-clean' }`，文件哈希不变。
- 删除依据不满足（history 无对应归档）→ 硬失败 `GHOST_ENTRY_ORPHANED`，不静默删除。
- 审计时序（代码评审二轮 b10）：幽灵清理的 `migrate-backlog-ghost removed:true` 审计事件**不得**在 `migrateGhostCleanup` 内预写——必须先 `casWrite` 成功、后由调用方调 `auditGhostCleanup` 补记。CAS_CONFLICT 时 `_backlog.yml` 保持不变且 audit.log 零成功记录（FR-10 一致性边界：状态机 + CAS + audit 统一写入路径）。

> 实现落点拍板（2026-08-09 用户决策，同步修订 PRD FR-10/D-11）：PRD FR-10 原写 `../tools/skills/shared/scripts/`，但 ARCHITECTURE §6 明确否决「独立账本操作脚本库（如 `tools/skills/shared/scripts/`）」（CR-2026-012 复盘 + CR-2026-020 范围澄清），`_backlog.yml` 属账本四类文件，清理必须经 crctl（CAS + audit）。因此落点定为 crctl.mjs 内 migrate 命令扩展，与既有 `cmdMigrateBacklog` 同路径。**结论不受影响**：清理语义、幂等与验收（AC-14）不变；PRD FR-10 文字已同步为同一落点，PRD/SDD 冲突已消除。

## 4. 关键算法与流程

### 4.1 archived TASK 门禁（FR-9，修复 `deliveryIndexComplete`）

在 crctl.mjs 的门禁 checker 实现中，将 `deliveryIndexComplete`（及 archived 目标态校验路径）改为五步判定：

```
1. tasks/_index.yml 不存在 → TASK_INDEX_MISSING（fail）
2. tasks[] 为空数组 → TASK_LIST_EMPTY（fail）        # 不得解释为 no-task
3. 任一 TASK status != done → TASK_STATUS_INCOMPLETE（fail，列出未完成 TASK-ID）
4. 全部 done 后：delivery/task/_index.yaml 缺失或空 → DELIVERY_INDEX_MISSING（fail）
5. 全部通过 → 放行
```

gates.json 的 archived 门禁声明结构不动（D-9：不改 gates.json），只修执行层 checker。`rejected`/`withdrawn` 不走 archived 门禁（提前终止语义，D-8）。不新增 no-task 标志与永久 `task reconcile` 命令。

### 4.2 幽灵条目清理算法（FR-10）

```
normalize CRLF → 逐行解析（复用 parseYaml 的行模型）
定位：在 change-requests 序列中，找到最后一个 id 字段缺失的块起点
      （= 某列表项 map 解析结束后，出现 indent ≥ 列表项字段缩进且非 '- ' 开头的第一行）
判定归属：取该块 title → 在 _history.yml 中检索同名归档条目（final-status 存在）
删除：从该行到 EOF（或到下一个 '  - id:' 前）
校验：删除后重新 parse，CR-2026-017 条目的 title/summary/owners 等字段恢复为归档前形态
审计（b10 时序）：migrateGhostCleanup 只检测不写审计；调用方在 casWrite 成功后调 auditGhostCleanup 补记
      （CAS_CONFLICT → casWrite 抛错终止，audit 不可达 → 零成功审计记录）
```

### 4.3 终态查询 fallback（FR-12）

```
cmdStatus/cmdNext:
  try { state = resolveCrState(ws, cr) }            # active 路径
  catch (CR_STATUS_NOT_FOUND) { state = resolveTerminalCrState(ws, cr) }
  写命令（cmdAdvance/cmdApprove/...）: 不 catch，维持 CR_STATUS_NOT_FOUND
```

### 4.4 approve 原子提交流程

见 §3.1 helper 流程；git 提交走 `controlledGit`（与既有 `crctl git` 同一受控通道），单次 commit 保证 approval/status 原子可见；outbox 事件在 commit 成功后发送（git 是权威、outbox 只是投影，ARCHITECTURE §5 不变量 6）。

## 5. 技术选型与替代方案

| 决策点 | 选型 | 否决的替代方案与理由 |
|---|---|---|
| approve 原子性 | 两文件内存生成 + `casWriteMulti` + 单次 commit（D-4） | WAL/两阶段提交：ARCHITECTURE §6 已否决（单写者下窗口足够小，YAGNI） |
| 归档原子性 | archive event 进 archive-move 同一 CAS（D-5） | 独立 inbox-emit + `--payload-file` + 幂等键：接口更多且留下 emit 成功/archive 失败的重复通知窗口 |
| 终态查询 | status/next 内 fallback resolver（D-6） | 新增 `archive-status` 命令：命令面膨胀；仅 status/next 有真实消费者 |
| 幽灵清理落点 | crctl `migrate-backlog` 扩展（已拍板 2026-08-09） | `skills/shared/scripts/` 独立脚本：违反 ARCHITECTURE §6 账本脚本库否决（见 §3.6 拍板说明） |
| review-record 深化 | 只加真实消费者字段（D-7） | 返回整份账本/verified/subject digest：与退出码和 CAS 成功重复 |
| TASK 门禁 | 修 crctl.mjs checker 实现 | 改 gates.json 结构：D-9 约束不改 gates；声明已含 deliveryIndexComplete，缺口在执行 |
| bootstrap | 声明入 repositories 后补建 tools worktree（D-12） | 直写 custom/main：绕过 CR worktree 治理；新增每 CR 仓库选择字段：第二套参与模型（Q3 否决） |

## 6. FR 到技术实现映射

| FR | 实现条目 | 落点 |
|---|---|---|
| FR-1 | 状态机口径 27/49 全量统一 | workspace AGENTS.md；tools ARCHITECTURE.md §3/§5；docs/analysis 复核 |
| FR-2 | crctl 单文件边界 + 删除 command module 描述 | tools ARCHITECTURE.md §3；v2 方案文档 |
| FR-3 | crctl-Pipeline 依赖三句准确描述 | tools ARCHITECTURE.md §4（替换「crctl 不依赖任何 Skill 或 Pipeline 定义」表述） |
| FR-4 | `_index.yml` 生命周期语义固化 | ARCHITECTURE.md + cr-archive SKILL.md；行为实现见 FR-11 |
| FR-5 | tools 入 repositories + merge Skill 特例删除 | workspace dir-graph.yaml；merge-feature-branch SKILL.md |
| FR-6 | 删除旧方案 command module/通用上下文命令描述 | docs/analysis/tools流程步骤优化v2.md |
| FR-7 | 指标基线固化（§16.1/§16.2） | ARCHITECTURE.md 或独立文档表格 |
| FR-8 | approveAndAdvance helper + TTY/grant 收敛 | crctl.mjs cmdApprove/approveWithGrant |
| FR-9 | deliveryIndexComplete 五步判定 | crctl.mjs checker 实现 |
| FR-10 | migrate-backlog 幽灵清理阶段（幂等） | crctl.mjs cmdMigrateBacklog + crctl.test.mjs |
| FR-11 | archive-move 三账本 CAS + archive event + inbox-emit 校验 | crctl.mjs cmdArchiveMove/cmdInboxEmit + 测试 |
| FR-12 | resolveTerminalCrState + status/next fallback | crctl.mjs resolveCrState 侧 + cmdStatus/cmdNext + 测试 |
| FR-13 | review-record 输出 files/attempt/route/repairTarget；review Skill 删二次读取 | crctl.mjs cmdReviewRecord；四个 review SKILL.md |
| FR-14 | 五项最小验证清单 | 实施收尾（见 §7.2） |
| FR-15 | tools worktree bootstrap | workspace dir-graph.yaml 先行 + ../tools 仓 worktree add |
| FR-16 | next freshness/上游重入：task-breakdown 从 dev-plan annotation 重算 route；tech-design-review-pending 校验 SDD subject digest/upstream blocker；review-record 自动开启 post-PASS 新 tech-design cycle | crctl.mjs cmdNext/cmdReviewRecord/readAttempts + crctl.test.mjs |

## 7. 安全与性能考量

### 7.1 一致性边界

- 两文件/三文件写入全部经 `casWriteMulti`：全校验 → 全 temp → 连续 rename；任一文件 CAS 冲突则全部不写。
- 事件发送严格在 CAS 成功后；commit 失败不发 outbox（FR-8）；CAS 失败不发 archive outbox（FR-11）。
- 终态查询只读不改；写命令对终态维持拒绝（不因 fallback 引入可写性）。

### 7.2 验证清单（FR-14，五项最小）

1. `git diff --check`（行尾/空白告警零）；
2. `JSON.parse(pipeline-templates/feature-writeback.pipeline.json)`；
3. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含新增：approve 原子提交、archived 门禁、archive-move 三账本、终态查询、review-record 输出、inbox-emit 空 to、migrate 幽灵清理）；
4. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 零发现；
5. grep 按 AC-1 判定方式确认 tools 隐藏特例与 25/47「现状」表述清零。

不预跑 agent-skill matrix 检查族、agents contract 检查族、writeback scripts 测试、engineering-docs 测试；实施实际触及再按「改了什么测什么」追加。

### 7.3 测试设计（crctl.test.mjs 新增用例）

- approve：四 stage 一次提交断言；gate 失败零写入；**候选 approval 缺 via/签名 → GATE_BLOCKED 零写入；候选 cr.md status ≠ 目标态 → CANDIDATE_STATUS_MISMATCH 零写入**（TD2-BL-2）；CAS 冲突两文件均不写；commit 失败两文件共存且无 status outbox（以受控环境模拟）；TTY/grant 同 helper 断言；reject 路径保持。
- archived 门禁：index 缺失 / 空列表 / 全 pending / 部分 done / delivery 缺失五类失败；全 done 放行；rejected/withdrawn 不适用。
- archive-move：三种终态 + final-status 不一致硬失败；中文 reason；收件人去重/legacy 回退/空收件人；可选 spec-id；**重复归档：CR 已移出 backlog 后再次调用 → `already-archived` 幂等返回（零写入）；history 存在但 final-status 不一致 → `FINAL_STATUS_MISMATCH`；history 无 → `CR_STATUS_NOT_FOUND`**（TD-BL-3 拍板）；outbox 时序；CRLF 规范化。
- 终态查询：三种终态 next:null；CR_LOCATION_CONFLICT；history 重复/缺 final-status 硬失败；cr.md 漂移 warning；active 回归。
- next 路由（FR-16/AC-23）：task-breakdown 无/畸形 dev-plan → review-dev-plan；PASS → approve dev-start；repair BLOCK → write-dev-plan；upstream BLOCK → write-tech-design；exhausted BLOCK → next:null + 人工处理。tech-design-review-pending 的 SDD digest 不一致/较新 upstream blocker → review-tech-design，fresh PASS 才允许审批。
- review cycle：legacy cycle=1 兼容；旧 cycle 3/3 PASS 后 SDD upstream revision → cycle=2/attempt=1；旧 attempts 保留；cycle=2 内第 4 次 block 仍 LOOP_EXHAUSTED。
- review-record：files 只列实际写入（未 bump 无 review-loop.yml）；attempt/route/repairTarget 正确性。
- inbox-emit：--to 缺失/非列表/空 → BAD_ARGS。
- migrate-backlog：幽灵块删除 + CR-2026-017 恢复 + already-clean 幂等 + history 无归档时 GHOST_ENTRY_ORPHANED。
- 代码评审 b10/三轮回归：黑盒注入读后并发改写，真实触发幽灵清理 `CAS_CONFLICT`，断言 backlog 除竞争写入外不变且零成功审计；dev-start 本地审批 digest 漂移通过真实 `approve --resign` TTY 路径完成 CAS、审计、受控提交并使 gate 复绿；reason/approver 含双引号、反斜杠、换行时仍为单一 YAML 标量；`server-approve` 明确拒绝本地 resign；非 TTY 一律 APPROVAL_REQUIRES_HUMAN。

## 8. Prompt 采纳影响（必填：本 CR 触及 crctl.mjs dispatch 与命令面）

| Skill 路径 | 现状 | 应改为 |
|---|---|---|
| `skills/cr/cr-archive/SKILL.md` | 描述 archive-move 同步 `_index.yml`（承诺未兑现）；独立 inbox-emit 发归档事件 | 对齐 FR-11：归档事件与三账本同批 CAS；`--final-status` 必须等于 cr.md 当前终态；收件人复用 owners |
| `skills/writeback/merge-feature-branch/SKILL.md` | prose 硬编码 tools 仓特例 | 删除特例，合并/同步只遍历 `dir-graph.yaml#repositories`（FR-5） |
| `skills/requirement/review-requirement/SKILL.md` | review-record 成功后重新读取 traceability 核对投影 | 删除二次读取，按返回 `files`/`route` 组织提交与分流，最后调用 `crctl next`（FR-13） |
| `skills/develop/review-tech-design/SKILL.md`（TD-BL-5 修订：原稿误写 `skills/architecture/`，实测真实路径为 develop 域） | 同上 | 同上 |
| `skills/develop/review-dev-plan/SKILL.md` | 同上（含 route/repairTarget 消费） | 同上 |
| `skills/develop/review-code/SKILL.md` | 同上 | 同上 |
| 四个 approve Skill（requirement/tech-design/dev-start/code） | 只描述「调用 crctl approve 后写审批并级联推进」稳定行为 | **不改**（D-9：分提交细节不在 prompt 中，原子化对它们透明） |
| 普通通知类 Skill（inbox-emit 调用方） | `--to` 契约已要求必填 | **不改**（crctl 校验与契约对齐，行为无变化） |

> 本 CR 不新增 crctl 子命令（NFR-1）：approve 原子化、archive-move 扩展、终态 resolver、review-record 深化、migrate-backlog 幽灵清理均收敛在既有命令内部。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于 PRD v0.2.0 与 v2 方案 §5/§6；FR 全覆盖 15/15；含 FR-10 落点修订说明——幽灵清理从 skills/shared/scripts/ 改为 crctl migrate-backlog 扩展，依据 ARCHITECTURE §6 否决，结论不受影响） |
| 2026-08-09 | v0.2.0 | Ray | 拍板（用户决策）：FR-10 采用本 SDD 方案（crctl migrate-backlog 扩展），§3.6 修订说明升级为拍板，§5 选型表同步；PRD FR-10/D-11 已同步修订，冲突消除 |
| 2026-08-09 | v0.3.0 | Ray | 修订（review-tech-design BLOCK 回修，TD-BL-2~5）：§3.5 真值表按 stage 判定（upstream 仅限 dev-plan 显式上游疑点，pass 时 repairTarget=null）；§3.2 重复归档语义拍板（already-archived 幂等 / FINAL_STATUS_MISMATCH / CR_STATUS_NOT_FOUND，§7.3 同步）；§3.1 新增候选证据 override seam（readEvidenceDoc 第 4 参 + runGateChecks opts.evidence，含调用形态与回归测试）；§8 修正 review-tech-design 路径为 skills/develop/；§1.3 采纳 suggestion（worktree-path 以主工作区解析 + bootstrap-base-sha 固定）；TD-BL-1 已由 PRD v0.3.0 闭环 |
| 2026-08-09 | v0.4.0 | Ray | 修订（review-tech-design 二轮 BLOCK 回修，TD2-BL-2）：候选 cr.md 校验改为独立 invariant helper `assertCandidateStatus`（错误码 CANDIDATE_STATUS_MISMATCH，CAS 前执行），不依赖 gate checker 消费 cr.md；evidence override 仅含 approval.yml；采纳 TD2-S1（override key 占位符匹配时点）、TD2-S2（already-archived 携带 finalStatus）；§7.3 测试同步；PRD AC-14 已由 PRD v0.4.0 闭环（TD2-BL-1） |
| 2026-08-09 | v0.5.0 | Ray | 范围确认（用户决策）：FR-16 纳入——cmdNext task-breakdown 分支补 dev-plan.yml 检查（CR-2026-026 遗留路由缺口，实测无评审记录时误报 approve dev-start）；FR 映射表与 §7.3 测试设计同步；归属 TASK-07 |
| 2026-08-09 | v0.6.0 | Ray | 上游回修（review-dev-plan DP-UP-1/2 + 回退后复验）：§2.4 增加兼容 review cycle；§3.4a 补 task-breakdown canonical route、SDD digest/upstream freshness；§3.5 tech-design subject hash + 自动新 cycle；§6/§7.3 同步 FR-16/AC-23 测试 |
| 2026-08-10 | v0.6.1 | Ray | 代码评审二轮 BLOCK 回修（b10）：§3.1 新增受控历史审批迁移 `approve --resign <reason>`（TTY 人类在环、只重签 digest、保留审批本体、resign 审计子块、幂等）；§3.6/§4.2 幽灵审计时序修正（审计必须在 casWrite 成功后，CAS_CONFLICT 零成功记录）；§7.3 补 b10 回归用例 |
| 2026-08-10 | v0.6.2 | Ray | 代码评审三轮 BLOCK 回修：`server-approve` 禁止本地 resign，改由服务端重签；resign 动态字段统一 YAML 标量序列化；测试改为真实 TTY 成功路径与真实 CAS_CONFLICT 运行时注入，覆盖 CAS/审计/提交/字段保留。 |
