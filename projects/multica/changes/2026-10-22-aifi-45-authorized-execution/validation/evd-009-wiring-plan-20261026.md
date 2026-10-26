# EVD-009 接线方案（规范授权的接缝）

> **状态（2026-10-26）：`merge` 路径已实施并验证（三轮：初版 → 零发布死锁修正 → 远端事实判据）；`checkpoint` / `writeback` 未接判定函数（按构造复用冻结快照，无重新决策面）。**
> 下方“计划改动”保留为实施前草案，其中两处已被实测推翻，更正见文末「实施结果与方案更正」。

## 规范依据

SC-EVD-009：given「验收已通过但 **checkpoint/merge/writeback** 在既有发布事务边界失败」；when「恢复同一发布操作」；then「复用原事务和业务 receipt，不重复审批、修复扣额或 cycle reset」。

⇒ 接缝由规范点名在 merge/writeback 的发布事务恢复路径，不是我发明的。

## 已核实的真实接缝

- `lib/workspace-transactions.mjs:1968 export async function mergeCr(ctx, input)`
  - `:1981` `loadOrCreateJournal({op:'merge', key:cr, ...})` → `journal.merge` 持久载荷
  - `:1984` **`const wasComplete = payload.phase === 'complete'`** ← 已存在的"重放"判定
  - `:1993` `recoverWriteSet(...)` roll-forward
  - `:2002-2003` 从 `approval.yml#code.release-subjects` 读快照，缺失即 `RELEASE_SUBJECT_DRIFT`
  - `:2008` `verifyReleaseSubjects(...)` 校验快照
  - `:2230` 返回 `changed: did && !wasComplete`
- `lib/release-recovery.mjs:12 evaluateReleaseRecovery({recorded, current, replayed})`，四类拒绝码：
  `EVIDENCE_RELEASE_REPLAY_NOT_REUSED` / `_REAPPROVED` / `_RECHARGED` / `_FACTS_RESET`；缺字段时跳过比较。

## 计划改动（最小、只影响重放路径）

1. `workspace-transactions.mjs` 顶部 import `evaluateReleaseRecovery`。
2. 在 `:2008` 快照校验通过后计算 `releaseFactsDigest = sha256(JSON.stringify(snapshot))`。
3. **重放守卫**：当 `wasComplete` 且 `payload.releaseFactsDigest` 存在时，调用
   `evaluateReleaseRecovery({recorded:{receipt_digest, business_facts_digest} = payload.releaseFactsDigest, current:{business_facts_digest: releaseFactsDigest}, replayed:true})`；
   `!allowed` → `throw new TxError(findings[0].code, ...)`，fail-closed。
4. 随后把 `payload.releaseFactsDigest = releaseFactsDigest` 写回（首次合并即落盘，供下次重放比对）。

## 为什么这样不越权

- 只比较**已经存在**的事实（已验签的 release-subjects 快照摘要）。`approval_id` / `repair_charge` 目前没有稳定来源，**不编造**；`evaluateReleaseRecovery` 对缺字段本就跳过比较，等有来源再补。
- `payload.releaseFactsDigest` 不存在的**历史 journal** 不参与守卫——存量为空journal无此字段，避免把旧事务一夜变红。这是真实限制，必须写进台账。
- 首次合并（`wasComplete=false`）行为完全不变。

## 必须先做 RED

`test/merge-tx.test.mjs`：让一次 merge 完成、改掉 `approval.yml#code.release-subjects`、再恢复同一 merge →
**必须** `EVIDENCE_RELEASE_FACTS_RESET`。未接线时该用例应"静默成功"，这就是 RED。

## 与另外两条的关系

EVD-007（组件就绪闸门）与 EVD-008（显式迁移入口）见 `decisions-pending-20261025T153000Z.md` D7/D8：前者等"闸门归哪层"的决定，后者等"是否迁移 legacy"的策略决定。都不阻塞本条。

## 实施结果与方案更正（2026-10-26）

**已实施**：`lib/workspace-transactions.mjs::mergeCr` 在 `verifyReleaseSubjects` 之后、任何 prepare/publish 之前，用 `releaseReceiptOf(doc.code, snapshot)` 生成发布 receipt（审批身份 + 已批准发布主体），并：
- **远端尚未包含本事务 mergeSha 时**（真正零发布）→ 记入/刷新 journal 的 receipt 并继续；此时重跑属于“对尚未落地的发布重新决定”，**允许**采纳新审批；
- **远端已包含 mergeSha 时**（已发生不可逆发布）→ 以 `replayed:true` 调 `evaluateReleaseRecovery`，`!allowed` 即抛 `first.code`（fail-closed），拒绝按新审批续发。

发布事实**不看本地 `rec.pushed`**：`push` 与 `save('pushed-…')` 之间有崩溃窗口，且 `classifyRemoteCommit='confirmed'` 只置 `confirmed`。判据与 `classifyRemoteCommit` 同口径：逐仓 `git merge-base --is-ancestor <mergeSha> origin/<trunk>`。

**两处草案判断被实测推翻**：
1. **重放标记不是 `phase==='complete'`**（草案写作 `wasComplete`)。真实的部分发布现场 `status` 仍为 `code-approved`、`phase` 停在 `pushed-<repo>`，`wasComplete` 恒为 false。真正的重放判据是「journal 已持久化本次发布 receipt」，即任何时候重入已开始的同一发布事务都算恢复。
2. **不能在 worktree 原地改 `approval.yml`**。这样会让知识仓 workspace 变 dirty，`verifyReleaseSubjects` 先返回 `RELEASE_SUBJECT_DRIFT`（`classification: dirty`），根本到不了本条判定。有效的反例夹具是「把重做的审批提交到 requirement 分支」：知识仓允许面已含 `change-requests/{cr}/approval.yml`，且只要求 reviewed SHA 为 HEAD 祖先，因此该改动能通过既有校验——证明缝在现代码里真实存在。

**证据**：`validation/evd-009-wiring-20261026/meta-current.json` + `green-current.tap` + 两条变异 RED（`red-drop-remote-published.tap` / `red-drop-pinned-guard.tap`）+ `regression-*-v3.tap`。旧 `red.tap`/`green.tap`/`meta.json`（2 例、锚点 `if (payload.releaseReceipt) {`、源码 `ae5ad1c8…`）对应已被取代的中间版本，保留仅作历史，不得再用作当前证据。当前源码：`lib/workspace-transactions.mjs` `37d3818a…`、测试 4 例。
**仍未解决（不得冒称）**：
- `checkpoint` / `writeback-apply` 两条恢复路径**没有接** `evaluateReleaseRecovery`。但这不等于同一缺陷还在：
  - `applyWritebackAtomic` 只在 `if (!found)`（首次尝试）读 `approval.yml` 并验快照；重放直接用冻结的 prepared candidate，并用 `businessInputDigest` / manifest digest 拒绝输入变化。按构造就不会采纳重做的审批。
  - `checkpointCr` 全路径不读 `approval.yml`；`journal.checkpoint` 首次 `save('start')` 后冻结，注释明写“found 重试禁止重算/覆写”。
  - 因此 SC-EVD-009 的真实暴露面只有 `merge`（它每次重入都重读审批并会采纳新值）。上面两条的“重放复用”已有**既有测试**覆盖（本轮已跑绿）：`writeback-tx.test.mjs` 的「journal-created 恢复冻结 transitionAt，业务参数漂移硬阻断」与「writeback-after-commit fault 经同一业务命令续跑不重复 commit」；`checkpoint-tx.test.mjs` 的「source commit 后 fault + 新增变化：重跑更新 sourceSha 并完成」与 metadata 恢复窗口两例。
  - 上述测试**不**直接断言“审批被重做时仍按原 receipt 重放”（因为这两条路径重放时根本不读审批，该断言无处可挂）；它们证明的是“重放沿用冻结值/不重复提交”。本轮特意不补近乎重复的测试。
- 既存量 journal 无 `releaseReceipt` 时不回溯，首次重入会把当时的审批补记为 receipt（历史事务不受保护）。
- `approval_id` 取 `approver/approved-at/evidence-digest` 三元摘要；`repair_charge` 无稳定来源，未编造（判定侧本就跳过缺字段）。
- 未在真实 tools+multica 双仓 CR 上执行，只在三 bare remote 夹具内验证；未动 DB。
