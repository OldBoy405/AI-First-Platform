# CR-2026-058 上下文加速文件
> 加速器，非事实源。事实以 cr.md / prd.md / sdd.md / plan.md / tasks / 评审账本为准；crctl 不校验本文件。

## 1. 状态（最近一次核对）

- CR-ID: CR-2026-058（CR-2026-057 的 follow-up，tools 仓修复；target-version=0.30）
- status: `task-breakdown`（write-dev-tasks 重放推进提交 `f184df5`；前置 tech-design-reviewed 为架构二次审批后的态）
- next: 待 `review-dev-plan` 复评刷新——crctl next 现仍读首轮 upstream BLOCK 注解（`98485f0`）建议 write-tech-design，B-DP-01 已修并经 tech-design 复评 PASS（`d8c32bc`）+ 架构重批，复评落盘后 next 归位
- reviewLoops: review-requirement=2/3；review-tech-design=cycle2 attempt1/3；review-dev-plan 首轮 BLOCK（upstream 轨未 bump，注解 subject=`db79dc07` 待刷新）
- 权威 worktree: `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`（主仓 master 视图陈旧；crctl 命令带 `--workspace`，crctl git 带 `--cwd <worktree>`）
- 关联: CR-2026-057 保持 `merging` 未动；本 CR 合入主仓后 057 才以 `--target-version 0.30` 继续 writeback

## 2. 产物地图

| 产物 | 路径（worktree 内） | 版本/提交 |
|---|---|---|
| PRD | `change-requests/CR-2026-058/prd.md` | 需求评审 PASS attempt 2（`064cef9`）；US×4 / FR×6 / AC×6；FR-2.1/§7 仅允许两个新错误码 |
| SDD | `change-requests/CR-2026-058/sdd.md` | B-DP-01 回修提交 `6dd7edf`（export seam + 决策 D-5 + §6.2 AC-4 + §9 scope_in）；tech-design 复评 PASS `d8c32bc`（cycle 2） |
| PLAN | `change-requests/CR-2026-058/plan.md` | B-DP-02~04 重建提交 `26b080d`；63h / 7 TASK；TASK-05 依赖 TASK-04；AC-4 正反语义向量；证据落点 KB CR worktree test-evidence/ |
| TASKS | `change-requests/CR-2026-058/tasks/TASK-01~07.md` + `_index.yml` | 同 `26b080d`；本轮 `crctl task init` 重放校验：`changed:false`、7 任务、totalEstimateHours=63（与 plan §5 全等）、frontmatter↔索引全等、依赖拓扑正确 |
| 评审账本 | `change-requests/CR-2026-058/review-annotations/` | requirement.yml PASS；sdd.yml PASS（cycle 2）；dev-plan.yml 首轮 BLOCK（route=upstream，`98485f0`，subject=`db79dc07`）待复评刷新 |
| 工具仓 | `resources[repo=tools].worktreePath` = `.rayai-worktrees/tools/requirement/CR-2026-058`（branch=`requirement/CR-2026-058`，HEAD=`2bb66294`） | 实施期改动落点见 SDD §1.1 |

## 3. 规则指针（只放指针，不复述）

- 拍板范围: prd.md §1.3；SDD §9（仅两个新错误码 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`；同源硬失败复用 `WRITEBACK_STATE_MISMATCH`；`WRITEBACK_AUTHORITY_DRIFT` 零残留）
- 判定表: prd.md FR-1；SDD §2.1/§4.2（guard 返回 `{ok,value,refill,authority}`）
- backlog 预检: prd.md FR-2.1；SDD §2.3/§4.3（四错误码、零写入时序）
- 故障边界: prd.md FR-2.2；SDD §2.4/§4.6；payload.versionRefill 冻结规则 SDD §2.2 + §4.4 第 9 步（found 重试不重算覆写）
- CLI 信封: prd.md FR-6；SDD §3（files 必含两账本路径；失败 extra 扁平）
- 测试 seam: SDD §1.4 + 决策 D-5（planVersionRefill/applyTargetVersionToCrMd/editBacklogEntryTargetVersion export，B-DP-01）
- 测试设计: SDD §6.2（AC-1.1~1.3 冻结向量 = B-DP-03 正反语义证明载体；AC-2.3 含 1b 部分 apply 冻结回归；direct 夹具 status=writing-back + 两账本 unassigned）
- 实施基线: SDD §6.3 七项证据，HEAD=`2bb66294`，branch=`requirement/CR-2026-058`
- 测试命令: plan.md §5.1（cmd-01~03，dot reporter；证据落点 = KB CR worktree `change-requests/CR-2026-058/test-evidence/cmd-NN.log`，B-DP-04）；基线红例外 plan.md §5.3（BR-1/BR-2 与 057 同两条）

## 4. 待办

1. quality-reviewer-agent 复评 `review-dev-plan`（plan/TASK 已重建 `26b080d`，B-DP-02~04 已修；复评落盘刷新 dev-plan.yml 注解与 subject-sha256）
2. PASS → 人工 `approve-dev-start` → developing → implement-code（TASK-01~07 按依赖序；tools 仓）+ write-test-report（TASK-07 收敛）
3. 本 CR 合入主仓后 CR-2026-057 才以 0.30 继续 writeback（本 CR 不推进 057）
