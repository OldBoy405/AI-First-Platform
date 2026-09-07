# CR-2026-061 工作流导航缓存（dev-agent / SDD 节点）
> 仅供返工与 /resume 导航；canonical 事实以 cr.md / sdd.md / review-annotations / crctl 为准。
> 最近刷新：2026-09-08（dev-agent：write-tech-design SDD 落盘并推进至 tech-design-review-pending）

## 当前状态
- status: `tech-design-review-pending`；reviewLoop `review-tech-design` attempt 0/3。
- `next`（crctl）: 以 `crctl next CR-2026-061` 为准（预期 = review-tech-design 独立评审）。

## 本 run 已交付
- `change-requests/CR-2026-061/sdd.md`（本文件提交同事务）：覆盖 13 FR + HTTP 契约 + AC-1~AC-13 合同；
  3 条第 3 轮 suggestions 全部「已处理」（SDD §11）；SDD-CLOSE-01~09 全部关闭（§10）。
- 状态推进：`requirement-approved → tech-designing → tech-design-review-pending`（均经 crctl advance，未手改账本）。

## 关键设计锚点（返工时先读 sdd.md 对应节）
- 唯一 Issue 写入路径 = `IssueService.createInTx`（自 Create 提取，FR-2/NFR-4）——SDD §4.3/D-7。
- fingerprint（FR-7，含 upgrade_to_cr）与 dedupe_key（FR-6，来源集合）是两个摘要——SDD §4.1。
- 预建 run：`pipeline_run(pipeline_id='requirement-authoring', cr_id=NULL, issue_id, started_by)` + 首节点
  `00000000-0000-0000-0011-000000000001` seq1 running；绑定端点置 passed——SDD §2.3/§4.5。
- 迁移 505（scope CHECK 扩展）/506（promotion run 部分唯一索引）/507（context_refs GIN）——SDD §2.6/§13。
- 绑定端点 `POST /api/crs/{crID}/bind-promotion-run` + `multica cr bind-promotion-run`（task-token 同族；
  二次绑定 409 RUN_CR_CONFLICT）——SDD §3.2/§3.3。

## 恢复入口
1. 独立 reviewer（quality-reviewer-agent，新会话）执行 `review-tech-design`：
   - crctl 一律带 `--workspace C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`
   - 评审对象 `change-requests/CR-2026-061/sdd.md`；三仓基线 multica `78e14082` / tools `49c46dd` / docs CR 分支（含本提交）。
2. BLOCK → repair-target 回 `write-tech-design`（作者会话 = dev-agent 本 Agent）：status 回到 `tech-designing`，
   按 blocker 定点回修 sdd.md，再 `crctl advance --to tech-design-review-pending --trigger write-tech-design-complete`，
   重新委派 reviewer 复评。
3. PASS → 停在人工审批（`approve-tech-design`，届时需 Ray 审批）。

## 环境提示
- 三仓 worktree：docs（KB，operational）`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`；
  multica / tools 同名 sibling worktree（`crctl workspace inspect` 为准）。
- 本缓存随 SDD 提交一并纳入（不单独建提交）。
