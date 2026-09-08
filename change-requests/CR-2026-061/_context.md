# CR-2026-061 工作流导航缓存（dev-agent / code-implementation 实现与测试节点）
> 仅供返工与 /resume 导航；canonical 事实以 cr.md / plan.md / tasks/_index.yml / review-annotations / crctl 为准。
> 最近刷新：2026-09-08（dev-agent，review-code attempt 1/3 BLOCK（B-CODE-01）回修完成，待委派 attempt 2/3 复评）

## 当前状态

- status: `developing`（review-code:block → implement-code 回修路径；修复后不回退状态，`crctl next` = `implement-code`，待复评 PASS 后进 `code-reviewing`）。
- reviewLoop `review-code` = 1/3（attempt 1 BLOCK 由 quality-reviewer-agent 落盘，提交 `ae666bd`）；TASK-01..04 全部 done。
- test-report.status=block 已经 Ray 人工核定（3 项上游 Windows 既有失败 + cmd-05 skipped 误报，选项 ①），不构成本轮代码 blocker。

## B-CODE-01 回修（本轮完成，待评审）

- 问题：查重命中补建 run 时，Go 侧把整个 `issue.context_refs` 解码为 `[]promotionContextRefEntry` 再整体 marshal + UPDATE，非 promotion 条目与未知扩展字段被静默清空（违反 SDD v1.1 §2.1 追加语义）。
- 修复（multica CR 分支）：
  - `server/pkg/db/queries/promotion.sql`：`SetIssueContextRefPipelineRun`（整数组覆盖）→ **`MergeIssueContextRefPipelineRun`**（`:one`，UPDATE … RETURNING）：`jsonb_agg` + 元素级 `||` 只对 `kind='discussion_promotion' AND dedupe_key=@dedupe_key` 的元素合并 `pipeline_run_id`，其余元素与未知字段原样保留；`COALESCE(..., context_refs)` 兜底；sqlc 重生（`make sqlc`，未手改生成物）。
  - `server/internal/service/promotion.go`：backfill 分支改调合并查询，RETURNING 后 fail-closed 校验（matched 元素 `pipeline_run_id` 落位，否则回滚）；`promotionContextRefEntry` 注释改为只读视图口径。
  - `server/internal/service/promotion_test.go`：新增 `TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs`（真库回归：异构 legacy 条目 + 匹配条目未知扩展字段 + 不同 dedupe 的第二 promotion 条目，升级后三者原样保留、仅匹配元素合入 run id）。
  - `CUSTOM.md` #78/#79 台账更新（查询改名 + 合并语义 + 回归测试 + 合并注意 ⑤/④）。
- 验证证据（本机真库，DATABASE_URL 取主克隆 `.env`）：service promotion 12 项全 PASS（含新回归）；handler promotion/bind 5 项 PASS；governance projection PASS；`gofmt` clean。
- 提交：multica CR 分支 commit（`[cr] CR-2026-061 fix: ...`）+ checkpoint 推送；KB 仓本文件随提交。

## 交付与提交（checkpoint batch `22e65d6f7e72cf69`，三仓 confirmed 并推送）

- multica `requirement/CR-2026-061` @ `a622e0ab3`（B-CODE-01 修复前 HEAD）：TASK-01 `2c73e6a43` / TASK-02 `1240647eb` / TASK-03 `b306fc867` / fix `50898d205` / TASK-04 `a622e0ab3`。
- tools `requirement/CR-2026-061` @ `6fbc5c82`：requirement-register SKILL Step 2.5 promotion 绑定 + `scripts/promotion-bind.mjs` + `scripts/test/promotion-bind.test.mjs`。
- docs/KB `requirement/CR-2026-061`：metadata + write-test-report 证据提交 + review-code 评审记录（`ae666bd`）。

## 环境提示（本机复现用）

- DB：主克隆 `C:\Users\GOBAO\Downloads\AI\multica\.env` 的 `DATABASE_URL`（真密码）→ 本机 5432 直连可用；dev 库 `schema_migrations` 已按 CUSTOM.md 第 3 条修复并应用 505–507。
- 受控 git 一律 `crctl git <sub> … --cwd <worktree>`；commit 消息必须以 `wip: `/`[cr] `/`merge(` 开头。
- `crctl test` 的 `pnpm` 需 PATH 前置 `C:\temp\pnpm-shim\pnpm.exe`；cmd-01 三项 `TestLoadAgentSkills_*` 上游失败基线已登记 CUSTOM.md。

## 恢复入口

1. 本轮收尾：只 mention `quality-reviewer-agent` 发起 `review-code` attempt 2/3 独立复评（新 reviewer 会话，`--bump-attempt`；crctl 一律带 `--workspace C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`；评审对象 = multica CR 分支新 HEAD + B-CODE-01 回修 diff + 新回归测试）。
2. 若复评再 BLOCK：repair-target `implement-code`，按 `review-annotations/code.yml` blockers 定点修（作者会话 = dev-agent 本 Agent）。
3. 复评 PASS：保持 CR 状态推进至 `code-reviewing`，停在该 gate 待人工 `approve-code`（approval.yml 仅 crctl approve 写入）。
