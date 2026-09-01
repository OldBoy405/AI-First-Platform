# CR-2026-058 上下文加速文件
> 加速器，非事实源。事实以 cr.md / prd.md / sdd.md / plan.md / tasks / 评审账本为准；crctl 不校验本文件。

## 1. 状态（最近一次核对）

- CR-ID: CR-2026-058（CR-2026-057 的 follow-up，tools 仓修复；target-version=0.30）
- status: `task-breakdown`（本 run 经 crctl advance `tech-design-reviewed → task-breakdown`，trigger=write-dev-tasks）
- next: `review-dev-plan`（评审闭环：dev-agent 直接 @ quality-reviewer-agent，不经 cr-coordinator 委派）
- attempt: review-dev-plan 首轮（reviewLoop max=3）；review-requirement=2/3、review-tech-design=3/3 已闭环
- 权威 worktree: `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`（主仓 master 视图陈旧，一切 crctl 操作带 `--workspace` 或 cd 进 worktree）
- 关联: CR-2026-057 保持 `merging` 未动；本 CR 合入主仓后 057 才以 `--target-version 0.30` 继续 writeback

## 2. 产物地图

| 产物 | 路径（worktree 内） | 版本/提交 |
|---|---|---|
| PRD | `change-requests/CR-2026-058/prd.md` | 需求评审 PASS attempt 2（`064cef9`）；US×4 / FR×6 / AC×6；FR-2.1/§7 仅允许两个新错误码 |
| SDD | `change-requests/CR-2026-058/sdd.md` | tech-design 第 3 轮 PASS（`7bca761`）；B-SDD-01~04 已闭合；批准范围 §9（scope_in/out/zero_diff/follow_up） |
| PLAN | `change-requests/CR-2026-058/plan.md` | 本 run 落盘（`66b0c2e`）；63h / 7 TASK；cmd-01~03 命令集 §5.1；基线红 BR-1/BR-2 例外表 §5.3 |
| TASKS | `change-requests/CR-2026-058/tasks/TASK-01~07.md` + `_index.yml` | 本 run 落盘（task init `_index.yml` taskCount=7 / 63h）；覆盖矩阵 §6.1（AC-1/2/3/6→TASK-04+cmd-02；AC-4→TASK-05+cmd-01；AC-5→TASK-06+cmd-01） |
| 评审账本 | `change-requests/CR-2026-058/review-annotations/` | requirement.yml PASS；sdd.yml PASS（attempt 3/3） |
| 工具仓 | `resources[repo=tools].worktreePath` = `.rayai-worktrees/tools/requirement/CR-2026-058`（branch=`requirement/CR-2026-058`，HEAD=`2bb66294`） | 实施期改动落点见 SDD §1.1 |

## 3. 规则指针（只放指针，不复述）

- 拍板范围: prd.md §1.3；SDD §9（仅两个新错误码；同源硬失败复用 `WRITEBACK_STATE_MISMATCH`，B-SDD-04）
- 判定表: prd.md FR-1；SDD §2.1/§4.2（guard 返回 `{ok,value,refill,authority}`）
- backlog 预检: prd.md FR-2.1；SDD §2.3/§4.3（四错误码、零写入时序）
- 故障边界: prd.md FR-2.2；SDD §2.4/§4.6；**payload.versionRefill 冻结规则: SDD §2.2 + §4.4 第 9 步（manifest 缺失/prepared/complete/refill=false/防御五现场）**
- CLI 信封: prd.md FR-6；SDD §3（files 必含两账本路径；失败 extra 扁平）
- 测试设计: SDD §6.2（AC-2.3 含 1b 部分 apply 冻结回归；direct 夹具 status=writing-back + 两账本 unassigned）
- 实施基线: SDD §6.3 七项证据，HEAD=`2bb66294`，branch=`requirement/CR-2026-058`
- 测试命令: plan.md §5.1（cmd-01~03 固定顺序，dot reporter）；基线红例外 plan.md §5.3（BR-1/BR-2 与 057 同两条）
- 评审要求: review-dev-plan 八类维度 + 覆盖矩阵 FR-8（cmd-NN 稳定标识）+ FR-9 唯一 owner + FR-10 无流程控制 TASK

## 4. 待办

1. quality-reviewer-agent 执行 `review-dev-plan`（PASS → 保持 task-breakdown，进人工 approve-dev-start；BLOCK → 双轨：`write-dev-plan` 普通回修或 `write-tech-design` upstream）
2. 人工审批通过后 → developing → implement-code（TASK-01~07 按依赖序；tools 仓）+ write-test-report（TASK-07 收敛）
3. 本 CR 合入主仓后 CR-2026-057 才以 0.30 继续 writeback（本 CR 不推进 057）
