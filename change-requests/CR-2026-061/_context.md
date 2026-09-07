# CR-2026-061 工作流导航缓存（dev-agent / SDD 节点）
> 仅供返工与 /resume 导航；canonical 事实以 cr.md / sdd.md / review-annotations / crctl 为准。
> 最近刷新：2026-09-08T03:50+08:00（dev-agent：review-tech-design 第 1 轮 BLOCK 回修完成，SDD v1.1 提交并推进 tech-design-review-pending，待第 2 轮复审）

## 当前状态
- status: `tech-design-review-pending`；reviewLoop `review-tech-design` attempt 1/3（第 1 轮 BLOCK 已记账）。
- `next`（crctl）: 以 `crctl next CR-2026-061` 为准（预期 = review-tech-design 独立复评，attempt 2/3）。

## 本 run 已交付（第 1 轮评审回修）
- `change-requests/CR-2026-061/sdd.md` v1.1（与 `_context.md` 同一提交）：
  - §12 按正文首现顺序全量重排为 35 项：8 项漏列事实补入（SweepChatIdempotency、
    CheckIssueCreateCapacity/ResolveIssueCountPolicy、GetMemberByUserAndWorkspace、
    GetProjectInWorkspace、InsertProjectSharedSession、chatMessageAuthorDisplayName、
    issue_properties_gin（迁移 192）、dbid.NewV7）；原 #13 拆分为 handler/service（#16）
    与 agent.sql db queries（#17，LockCrForCrBind L1128 / BindCrShellIssueIfNull L1146）。
  - suggestion-1 已处理：§4.5 新增「违约后果与恢复路径」（投影行占 456 槽位 → 绑定 23505
    冲突 500 CR_BIND_FAILED；恢复 = 定位 issue_id IS NULL 投影行删除后幂等重试）。
  - suggestion-2 已处理：§3.2 错误体形状注记（绑定端点全表 {"error":...} 同族，不经 writeErrorCode）。
  - suggestion-3 已处理：ArchitectureCoreRegistryJSON 并入 §12 #10、CreateActivity 独立条目 #29。
  - 处置台账：§11.1；审查要点速览 #7 同步更新。
- 状态推进：`tech-designing → tech-design-review-pending`（经 crctl advance，未手改账本）。

## 关键设计锚点（返工时先读 sdd.md 对应节）
- 唯一 Issue 写入路径 = `IssueService.createInTx`（自 Create 提取，FR-2/NFR-4）——SDD §4.3/D-7。
- fingerprint（FR-7，含 upgrade_to_cr）与 dedupe_key（FR-6，来源集合）是两个摘要——SDD §4.1。
- 预建 run：`pipeline_run(pipeline_id='requirement-authoring', cr_id=NULL, issue_id, started_by)` + 首节点
  `00000000-0000-0000-0011-000000000001` seq1 running；绑定端点置 passed——SDD §2.3/§4.5。
- 迁移 505（scope CHECK 扩展）/506（promotion run 部分唯一索引）/507（context_refs GIN）——SDD §2.6/§13。
- 绑定端点 `POST /api/crs/{crID}/bind-promotion-run` + `multica cr bind-promotion-run`（task-token 同族；
  二次绑定 409 RUN_CR_CONFLICT；错误体 {"error":...} 同族形状）——SDD §3.2/§3.3。
- 456 部分唯一索引谓词 = cr_id IS NOT NULL AND status IN ('running','waiting_approval')——§12 #31（§4.5 违约推演依据）。

## 恢复入口
1. 独立 reviewer（quality-reviewer-agent，新会话）执行 `review-tech-design` 复评（attempt 2/3，--bump-attempt）：
   - crctl 一律带 `--workspace C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`
   - 评审对象 `change-requests/CR-2026-061/sdd.md`（v1.1）；重点复核 §12 35 项补列/拆分与 §11.1 三条处置结论；
     三仓基线 multica `78e14082` / tools `49c46dd` / docs CR 分支（含本提交）。
2. BLOCK → repair-target 回 `write-tech-design`（作者会话 = dev-agent 本 Agent）：status 回到 `tech-designing`，
   按 blocker 定点回修 sdd.md，再 `crctl advance --to tech-design-review-pending --trigger write-tech-design-complete`，
   重新委派 reviewer 复评。
3. PASS → 停在人工审批（`approve-tech-design`，届时需 Ray 审批）。

## 环境提示
- 三仓 worktree：docs（KB，operational）`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`；
  multica / tools 同名 sibling worktree（`crctl workspace inspect` 为准）。KB worktree 分支 = `requirement/CR-2026-061`。
- 本缓存随 SDD 提交一并纳入（不单独建提交）。
