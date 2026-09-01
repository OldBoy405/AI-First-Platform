# CR-2026-058 上下文加速文件

> 加速器，非事实源。事实以 cr.md / prd.md / sdd.md / plan.md / tasks / 评审账本为准；crctl 不校验本文件。

## 1. 状态（最近一次核对）

- CR-ID: CR-2026-058（CR-2026-057 的 follow-up，tools 仓修复；target-version=0.30）
- status: `developing`（approve-dev-start 已通过，approval 落盘于 13:00:50 +08:00）
- next: `push-progress → review-code`（静态建议文本，code.yml 落盘前恒显示；两项前置本轮已全部完成，剩余动作 = review-code）
- 统一 checkpoint（pipeline node-8）: batchId=`36d14c9c3fa8c30d`，phase=complete，changed=true；repos 全 confirmed 并推送（ai-first-platform-docs=`a2dbac30`、multica=`0843f3a8`、tools=`e984c232`，ref=`requirement/CR-2026-058`）；metadataCommit=`e0b693a5`；`_backlog.yml` 条目已写 latest-checkpoint（last-push-at/by 旧字段按 CR-2026-033 语义由 snapshot 取代）
- workspace-freshness（pipeline node-17, gate=review-start）: `allFresh=true`、syncable=false → route=**continue**（三仓均 fresh、dirty=false）
- reviewLoops: review-requirement=2/3；review-tech-design=cycle2 1/3（PASS）；review-dev-plan=1/3（PASS）；write-test-report=1/3（pass）
- 权威 worktree: `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`（主仓 master 视图陈旧，crctl 命令带 `--workspace`，crctl git 带 `--cwd <worktree>`）
- 关联: CR-2026-057 保持 `merging` 未动；本 CR 合入主仓后 057 才以 0.30 继续 writeback

## 2. 产物地图

| 产物 | 路径（worktree 内） | 版本/提交 |
|---|---|---|
| PRD | `change-requests/CR-2026-058/prd.md` | 需求评审 PASS attempt 2（`064cef9`）；US×4 / FR×6 / AC×6；FR-2.1/§7 仅允许两个新错误码 |
| SDD | `change-requests/CR-2026-058/sdd.md` | tech-design cycle 2 PASS（`d8c32bc`）+ 架构二次审批；B-DP-01 export seam |
| PLAN | `change-requests/CR-2026-058/plan.md` | `26b080d` 重建；7 TASK / 63h；§5.1 cmd-01~03；§5.3 BR-1/BR-2 基线红例外 |
| TASKS | `tasks/TASK-01~07.md` + `_index.yml` | TASK-01~07 全部 `done`（crctl task done，`86e2e7a`） |
| 测试报告 | `change-requests/CR-2026-058/test-report.md` | 机器区 status=pass（command-digest `6cc25bdd…`）+ 分析段 |
| 测试证据 | `change-requests/CR-2026-058/test-evidence/cmd-01~03.log` | 三命令 exit 0 且 skipped=false（B-DP-04 canonical 路径） |
| 评审账本 | `change-requests/CR-2026-058/review-annotations/` | requirement/sdd/dev-plan 均 PASS；code.yml 尚缺（本轮评审将落盘） |
| tools 代码 | `resources[repo=tools].worktreePath` = `.rayai-worktrees/tools/requirement/CR-2026-058`（branch=`requirement/CR-2026-058`） | 实施提交：`bbe0a3f`（TASK-01/02/03）、`a0bab38`（TASK-04）、`e984c23`（TASK-05/06） |

## 3. 规则指针（只放指针，不复述）

- 批准范围: prd.md §1.3；SDD §9（仅两个新错误码 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`；同源硬失败复用 `WRITEBACK_STATE_MISMATCH`；`WRITEBACK_AUTHORITY_DRIFT` 零残留）
- 判定表: prd.md FR-1；SDD §2.1/§4.2（guard 返回 `{ok,value,refill,authority:{path,source}}`）
- backlog 预检: prd.md FR-2.1；SDD §2.3/§4.3（四错误码、零写入时序；payload.versionRefill 冻结规则 SDD §2.2/§4.4 第 9 步）
- CLI 信封: prd.md FR-6；SDD §3（files 必含两账本路径；失败 extra 扁平）
- 测试 seam: SDD §1.4 + 决策 D-5（planVersionRefill/applyTargetVersionToCrMd/editBacklogEntryTargetVersion export）
- 测试设计: SDD §6.2（AC-1.1~1.3 冻结向量 = B-DP-03 正反语义向量证明载体；AC-2.3 1b 部分 apply 冻结回归；direct 夹具 status=writing-back + 两账本 unassigned）
- 实施基线: SDD §6.3 七项证据，HEAD=`2bb66294`，branch=`requirement/CR-2026-058`
- 测试命令: plan.md §5.1（cmd-01~03，dot reporter）；证据落点 = KB CR worktree `test-evidence/cmd-NN.log`（B-DP-04）；基线红例外 plan.md §5.3（BR-1/BR-2）

## 4. 待办

1. quality-reviewer-agent 执行 `review-code`（权威 worktree `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`；主仓 master 视图陈旧请勿采信；代码事实按 `resources[].worktreePath` 取证；评审记录经 `crctl review-record --stage code` 落盘）→ PASS 后由 cr-coordinator-agent 接管人工 `approve-code`。
2. BLOCK 时按 blocker 回修（repair-target=implement-code），重跑受影响命令并刷新 test-evidence，重跑 checkpoint + review-start freshness 后直接 @ 复评。
3. 本 CR 合入主仓后 CR-2026-057 才以 `--target-version 0.30` 继续 writeback（本 CR 不推进 057）。
