---
id: CR-2026-063-TASK-03
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: _context.md 活跃合同退役（post-review 白名单删条目 + CR-2026-057 测试原位改为退役合同测试）与活跃引用全量核对
slug: retire-context-md-active-contract
status: pending
estimate: 8h
depends-on: []
created: 2026-09-11T19:30:00+08:00
---

## 1. 任务描述

在 tools CR worktree 完成 `_context.md` 的**活跃合同退役**（FR-1③④）并交付活跃引用全量核对证据（FR-2 / AC-2）：

1. **FR-1③**：删除 post-review path drift 的 `allowed` 集合中的 `_context.md` 条目**及其上方注释**；删除后 `_context.md` 与任意其它非白名单文件同等处理（评审后新增/修改 → `post-review-path-drift` 拒绝）。**不新增** `crProcessCachePath()`、**不放宽** `classifyRepoWorkspace()` 的 dirty 语义。
2. **FR-1④**：把 CR-2026-057 的既有测试（`crctl.test.mjs:4554` 起）**原位改为退役合同测试**（禁止「保留原测试 + 旁边新增反向测试」），断言反转为「`_context.md` 评审后变更 → `RELEASE_SUBJECT_DRIFT` / `reason=post-review-path-drift` 且 `approval.yml` 零写入」，并**保留 `_context2.md` 非白名单断言**（证明不存在前缀式放宽）。
3. **FR-2 / AC-2**：按 PRD §1.5（人工审批已确认口径）与 SDD §4.5 执行检索，交付「检索命令 + 命中清单」：计入集合命中 0；排除集合（`skills/shared/crctl/scripts/test/**`）命中必须全部为「拒绝 `_context.md`」语义，无正例放行残留。

输入：已审批 SDD §4.4（退役后的漂移判定）、§4.5（AC-2 检索核对算法与判定要求）、§6 FR-1③④ / FR-2、§6.1 AC-1③④ / AC-2、§9（`scope_in`/`scope_out`）+ dep-10 / dep-12；已审批 PRD 修订 0.1.1 FR-1③④ / FR-2、§1.5、AC-1 / AC-2；plan.md §6.2（cmd-01 / cmd-06）、§7。

本 TASK **不**改 `sdd.md`、**不**改 `prd.md`、**不**批量迁移历史 CR 目录 / 历史 `traceability.yml` / 归档 delivery 证据（PRD §7）、**不**机械化 AC-2 的语义判定（S-5 范围外：不新增 lint/规则）。

## 2. 涉及文件 / 模块

修改（PRD §1.3.1 第 6、7 行）：

- `tools` `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：post-review `allowed` 集合（基线 L1311–1319）**删除** `// _context.md：工作流上下文加速文件…` 注释（L1317）与 `` `change-requests/${cr}/_context.md`, `` 条目（L1318）。
- `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`：CR-2026-057 白名单测试（基线 L4554–4582）**原位改写**为退役合同测试。

只读引用（不改）：`crctl.test.mjs` 的 `makeCodeStageWorkspace` / `runCodeReviewAndAdvance` / `makeCodeGrant` 夹具（dep-12）；`workspace-transactions.mjs` 的 `unexpected` 判定与 `bad('code',{reason:'post-review-path-drift'})`（dep-10）。

## 3. 实现要点（逐字对齐 SDD）

### 3.1 退役后的漂移判定（SDD §4.4，算法不变）

```text
unexpected = changedPaths(reviewedSha..HEAD) \ (allowed ∪ review-annotations/ 前缀)
unexpected 非空 → bad('code', { reason:'post-review-path-drift', repo, unexpected })
```

`allowed` 删除一条后仍为：`approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`_backlog.yml`（+ `review-annotations/` 前缀）。删除后 `_context.md` 落入 `unexpected` → 与其它非白名单文件同等拒绝。

### 3.2 退役合同测试（FR-1④，原位改写）

把现有测试（`test('CR-2026-057: KB 白名单新增 _context.md…')`）的**同名测试体的 ① 段**由「放行」改为「拒绝」：

- ① 评审后仅 `change-requests/CR-D1/_context.md` 变化并提交 → `runCrctl(['approve','CR-D1','--stage','code','--grant',…])` 断言 `status === 1`、`error.code === 'RELEASE_SUBJECT_DRIFT'`、`error.reason === 'post-review-path-drift'`、`approval.yml` 不存在（零写入）；
- ② 保留既有 `_context2.md`（同类拼写但非白名单）→ 同款拒绝 + 零写入断言（证明不存在前缀式放宽）；
- 测试名保留对 `_context.md` 的字面引用（作为**必须被拒绝的对象**），不得改写为不含该字面量的名称以规避 AC-2 的排除集合口径；不得新增一条并行的反向测试（禁止「旧放行 + 新拒绝」并存）。
- 行尾纪律（AGENTS.md #1）：测试内文本处理与哈希前统一 `\r\n → \n`；读取/解析失败硬失败。

### 3.3 AC-2 检索证据（PRD §1.5 口径，SDD §4.5）

- 机械面（cmd-06，plan §6.2-A 脚本）：计入集合 = tools 的 `agents/`、`skills/`、`pipeline-templates/`（排除 `skills/shared/crctl/scripts/test/**`、`.git`、`node_modules`）+ multica 的 `cr-prompts-revised/` → `_context.md` 命中数必须为 **0**；命令同时列印排除集合命中清单。
- 人工面（逐条，不机械化）：排除集合内每处命中必须能读出「拒绝 `_context.md`」语义；出现任何「放行 `_context.md`」正例断言即判不通过。命中清单与逐条判定结论写入 `write-test-report` 的分析段（`<!-- crctl:analysis-below -->` 以下）。
- **不新增 lint / 规则**实现该判定；`lint-prompts.mjs` 零改动。

## 4. 验收条件

1. **cmd-01**（`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt|TASK-06 ⑤|已知 Skill 越界文本零命中" skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/durable-tx.test.mjs`，cwd = tools worktree）：全绿，含退役合同测试的 ①② 两条断言；其 3 条 skip 为 plan §5.3 登记的基线红（BR-1/BR-3/BR-4）。
2. **cmd-06**（`node -e "<plan §6.2-A 脚本>"`，cwd = tools worktree）：`AC-2 accounted-set hits = 0`、exit 0；日志中排除集合命中清单可读出全部为拒绝语义（模板：退役测试名 + 断言字符串 + 夹具注释）。
3. 人工/评审可核对：`crctl git diff --unified=3 ebdd6290f1523ffb682609b7ad6ab83e7d30245e -- skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 的全部 hunk 仅为该注释 + 条目的**删除**（无新增行、无 `crProcessCachePath`、`classifyRepoWorkspace` 零 diff）。
4. 人工/评审可核对：`crctl git diff --unified=3 ebdd6290f1523ffb682609b7ad6ab83e7d30245e -- skills/shared/crctl/scripts/test/crctl.test.mjs` 中该测试体不存在「旧放行断言」残留（`assert.equal(r.status, 0, \`_context.md 后继应放行…\`)` 必须消失）。

## 5. 完成标志

- 上述 4 条验收全部通过；本 TASK 的提交落盘 tools CR 分支（独立 commit，`[cr] ` 前缀消息），文件面仅 §2 列出的 2 个文件。
- AC-2 的命中清单与逐条判定结论已交付（写入 test-report 分析段），注明检索命令与判定口径（PRD §1.5；排除集合内字面量不计入归零要求）。
- 任务账本：`crctl task done CR-2026-063 --task CR-2026-063-TASK-03`（仅 `developing` 下可登记）。
- 本 TASK 完成边界为 `developing` 内可被 `crctl task done` 登记的事件（实现落盘 + cmd-01/cmd-06 全绿 + 命中清单交付 + 账本登记），**不含** merge / writeback / archive / code-reviewing / code-approved。
- 不登记 multica 侧台账（本 TASK 不碰 multica 仓）；历史 CR 目录与归档证据零改动（PRD §7）。

## 6. 接口契约

**消费**：

- `classifyRepoWorkspace(ctx, repo, cr) -> {classification, worktreePath}`、`repoReviewedSha(r) -> string`、`gitMust(wt, args) -> string`、`gitRun(wt, args) -> {status, stdout, stderr}`（`workspace-transactions.mjs`，post-review 检查段落 L1296–1325）：本 TASK 只删 `allowed` 集合的两行，**不改**上述 helper 与 `dirty` 语义。
- `bad(stage, extra) -> {ok:false, stage, ...extra}`（同文件）与 `crctl` 侧 `fail(code, message, extra)`：退役后拒绝结果为 `RELEASE_SUBJECT_DRIFT` + `reason='post-review-path-drift'` + `unexpected:[…]`（与 AC-1④ 断言一致；`crctl.mjs` 的 `approve` code 分支把 `bad('code', …)` 映射为 `RELEASE_SUBJECT_DRIFT`，基线 L1323 附近）。
- 测试夹具（不改）：`makeCodeStageWorkspace()`、`runCodeReviewAndAdvance(ws)`、`makeCodeGrant(ws, privateKey)`、`runCrctl(args)`、`existsSync`/`writeFileSync`（dep-12）。
- AC-2 检索面的事实来源：PRD §1.4 事实 2/3（tools 侧 6 处、multica 侧 2 处）、dep-10（删除落点）、dep-22（multica 两份副本）。

**产出**：

- post-review `allowed` 集合（KB 仓分支）= `{approval.yml, cr.md, traceability.yml, review-loop.yml, _backlog.yml}`（不含 `_context.md`）；`unexpected` 判定与 `post-review-path-drift` 语义不变。
- 退役合同测试（同一 `test(...)` 条目）：断言集合 = ｛`_context.md` 变更 → `RELEASE_SUBJECT_DRIFT`/`post-review-path-drift` + `approval.yml` 零写入；`_context2.md` 变更 → 同款拒绝 + 零写入｝；测试名保留 `_context.md` 与 `_context2.md` 字面量。
- AC-2 证据 = cmd-06 日志（计入集合 0 命中 + 排除集合命中清单）+ test-report 分析段的逐条判定结论。
