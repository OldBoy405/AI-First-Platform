# CR-2026-058 上下文加速文件
> 加速器，非事实源。事实以 cr.md / prd.md / sdd.md / plan.md / tasks / 评审账本为准；crctl 不校验本文件。

## 1. 状态（最近一次核对）

- CR-ID: CR-2026-058（CR-2026-057 的 follow-up，tools 仓修复；target-version=0.30）
- status: `tech-design-review-pending`（dev-plan 首评 BLOCK route=upstream，crctl 上游回退提交 `88e55f1`）
- next: `review-tech-design`（SDD 已按 B-DP-01 回修，证据刷新后重评；PASS 后走既有 approve-tech-design → tech-design-reviewed → write-dev-tasks → task-breakdown → review-dev-plan 复评）
- attempt: review-tech-design=3/3（max，已耗尽；重评是否 bump 由评审方按 review-record 口径决定）；review-requirement=2/3；review-dev-plan 首轮 BLOCK（upstream 轨未 bump）
- 权威 worktree: `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`（主仓 master 视图陈旧；crctl 命令带 `--workspace`，crctl git 带 `--cwd <worktree>`）
- 关联: CR-2026-057 保持 `merging` 未动；本 CR 合入主仓后 057 才以 `--target-version 0.30` 继续 writeback

## 2. 产物地图

| 产物 | 路径（worktree 内） | 版本/提交 |
|---|---|---|
| PRD | `change-requests/CR-2026-058/prd.md` | 需求评审 PASS attempt 2（`064cef9`）；US×4 / FR×6 / AC×6；FR-2.1/§7 仅允许两个新错误码 |
| SDD | `change-requests/CR-2026-058/sdd.md` | B-DP-01 回修提交 `6dd7edf`（§1.4 可见性 export + 测试 seam 注记、§5 决策 D-5、§6.2 AC-4、§9 scope_in）；含 B-SDD-01~04 全部既有闭合 |
| PLAN | `change-requests/CR-2026-058/plan.md` | B-DP-02~04 重建提交 `26b080d`（TASK-05 依赖 TASK-04；AC-4 正反语义向量；证据落点 KB CR worktree test-evidence/）；63h / 7 TASK；cmd-01~03 §5.1；基线红 BR-1/BR-2 §5.3 |
| TASKS | `change-requests/CR-2026-058/tasks/TASK-01~07.md` + `_index.yml` | 同 `26b080d`；TASK-02/05 可见性=export（B-DP-01）；TASK-04/05 AC-1.1~1.3 冻结向量（B-DP-03）；TASK-07 证据路径（B-DP-04）；_index TASK-05 depends-on 含 TASK-04 |
| 评审账本 | `change-requests/CR-2026-058/review-annotations/` | requirement.yml PASS；sdd.yml PASS（attempt 3/3，subject 已过时待刷新）；dev-plan.yml 首轮 BLOCK（route=upstream，`98485f0`） |
| 工具仓 | `resources[repo=tools].worktreePath` = `.rayai-worktrees/tools/requirement/CR-2026-058`（branch=`requirement/CR-2026-058`，HEAD=`2bb66294`） | 实施期改动落点见 SDD §1.1 |

## 3. 规则指针（只放指针，不复述）

- 拍板范围: prd.md §1.3；SDD §9（仅两个新错误码；同源硬失败复用 `WRITEBACK_STATE_MISMATCH`）
- 判定表: prd.md FR-1；SDD §2.1/§4.2（guard 返回 `{ok,value,refill,authority}`）
- backlog 预检: prd.md FR-2.1；SDD §2.3/§4.3（四错误码、零写入时序）
- 故障边界: prd.md FR-2.2；SDD §2.4/§4.6；payload.versionRefill 冻结规则 SDD §2.2 + §4.4 第 9 步
- CLI 信封: prd.md FR-6；SDD §3（files 必含两账本路径；失败 extra 扁平）
- 测试 seam: SDD §1.4 + 决策 D-5（planVersionRefill/applyTargetVersionToCrMd/editBacklogEntryTargetVersion export，B-DP-01）
- 测试设计: SDD §6.2（AC-1.1~1.3 冻结向量 = B-DP-03 正反语义证明载体；AC-2.3 含 1b 部分 apply 冻结回归；direct 夹具 status=writing-back + 两账本 unassigned）
- 实施基线: SDD §6.3 七项证据，HEAD=`2bb66294`，branch=`requirement/CR-2026-058`
- 测试命令: plan.md §5.1（cmd-01~03，dot reporter；证据落点 = KB CR worktree `change-requests/CR-2026-058/test-evidence/cmd-NN.log`，B-DP-04）；基线红例外 plan.md §5.3（BR-1/BR-2 与 057 同两条）

## 4. 待办

1. quality-reviewer-agent 复评 `review-tech-design`（SDD B-DP-01 回修：export seam 统一）；PASS 后 coordinator 接管 approve-tech-design 人工 gate
2. tech-design-reviewed → write-dev-tasks 重放（plan/TASK 已重建 `26b080d`，tasks/_index.yml 与 frontmatter 全等）→ task-breakdown → `review-dev-plan` 复评（B-DP-02~04 已修）
3. 人工审批通过后 → developing → implement-code（TASK-01~07 按依赖序；tools 仓）+ write-test-report（TASK-07 收敛）
4. 本 CR 合入主仓后 CR-2026-057 才以 0.30 继续 writeback（本 CR 不推进 057）
