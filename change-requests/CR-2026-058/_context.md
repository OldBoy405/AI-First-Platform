# CR-2026-058 上下文加速文件

> 加速器，非事实源。事实以 cr.md / prd.md / sdd.md / 评审账本为准；crctl 不校验本文件。

## 1. 状态（最近一次核对）

- CR-ID: CR-2026-058（CR-2026-057 的 follow-up，tools 仓修复；target-version=0.30）
- status: `tech-design-review-pending`
- next: `review-tech-design`（评审闭环：dev-agent 直接 @ quality-reviewer-agent，不经 cr-coordinator 委派）
- attempt: 首次 SDD（尚无 sdd review verdict）
- 权威 worktree: `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`
  （主仓 master 视图陈旧，一切 crctl 操作带 `--workspace` 或 cd 进 worktree）
- 关联: CR-2026-057 保持 `merging` 等待本 CR 合入后以 `--target-version 0.30` 续跑 writeback

## 2. 产物地图

| 产物 | 路径（worktree 内） | 版本/提交 |
|---|---|---|
| PRD | `change-requests/CR-2026-058/prd.md` | 需求评审 PASS attempt 2（`064cef9`）；US×4 / FR×6 / AC×6 |
| SDD | `change-requests/CR-2026-058/sdd.md` | 本 run 落盘（`12e3dd0`），待 review-tech-design |
| 评审账本 | `change-requests/CR-2026-058/review-annotations/` | requirement.yml 已 PASS；sdd.yml 尚无 |
| 工具包 | `../tools/`（本 CR 目标仓；分支 `requirement/CR-2026-058` @ `1ec6bad`） | 实施期改动落点见 SDD §1.1 |

## 3. 规则指针（只放指针，不复述）

- 拍板范围: prd.md §1.3（已拍板范围）；SDD §9（批准范围四字段）
- 判定表: prd.md FR-1（六行）；SDD §2.1
- backlog 预检: prd.md FR-2.1（两表四码）；SDD §2.3/§4.3
- 故障边界: prd.md FR-2.2（三 fault point 表）；SDD §2.4/§4.6
- CLI 信封: prd.md FR-6（成功/失败表）；SDD §3
- 测试设计: SDD §6.2（AC-1~AC-6 落点）；prd.md FR-4（两测试文件改写清单）
- 既有实现证据: SDD §6.3（7 项，SHA=`1ec6bad4518f030c6b98ce74e8eea17a92181849`）
- 架构基线: `../tools/ARCHITECTURE.md`（已存在，只读引用，本 CR 不修订）

## 4. 待办

1. quality-reviewer-agent 评审 `review-tech-design`（BLOCK → 回修 SDD；PASS → 人工 approve-tech-design）
2. 人工审批通过后 → write-dev-plan/write-dev-tasks → 代码实施（tools 仓）→ write-test-report → 代码评审
3. 合入主仓后 CR-2026-057 才以 0.30 继续 writeback（本 CR 不推进 057）
