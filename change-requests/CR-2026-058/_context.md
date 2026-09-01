# CR-2026-058 上下文加速文件

> 加速器，非事实源。事实以 cr.md / prd.md / sdd.md / 评审账本为准；crctl 不校验本文件。

## 1. 状态（最近一次核对）

- CR-ID: CR-2026-058（CR-2026-057 的 follow-up，tools 仓修复；target-version=0.30）
- status: `tech-design-review-pending`（本 run 经 crctl advance 推进，embedded）
- next: `review-tech-design`（评审闭环：dev-agent 直接 @ quality-reviewer-agent，不经 cr-coordinator 委派）
- attempt: SDD 评审 attempt 2 BLOCK 三项（B-SDD-01 部分/B-SDD-03 部分/B-SDD-04 新增）已回修，待第 3 轮复评（reviewLoop max=3，本轮为最后一轮）
- 权威 worktree: `.rayai-worktrees/knowledge-base/requirement/CR-2026-058`（主仓 master 视图陈旧，一切 crctl 操作带 `--workspace` 或 cd 进 worktree）
- 关联: CR-2026-057 保持 `merging` 等待本 CR 合入后以 `--target-version 0.30` 续跑 writeback

## 2. 产物地图

| 产物 | 路径（worktree 内） | 版本/提交 |
|---|---|---|
| PRD | `change-requests/CR-2026-058/prd.md` | 需求评审 PASS attempt 2（`064cef9`）；US×4 / FR×6 / AC×6；NFR-2/§7 只允许 FR-2.1 两个新错误码 |
| SDD | `change-requests/CR-2026-058/sdd.md` | attempt-2 回修版（本 run）：B-SDD-01 payload 冻结 + manifest/phase 恢复 + direct 夹具改 status=writing-back；B-SDD-03 resource branch 改 `requirement/CR-2026-058`；B-SDD-04 删除 `WRITEBACK_AUTHORITY_DRIFT`，同源硬失败复用既有 `WRITEBACK_STATE_MISMATCH` |
| 评审账本 | `change-requests/CR-2026-058/review-annotations/` | requirement.yml PASS；sdd.yml attempt-2 BLOCK（canonical `047e277`，repairTarget=write-tech-design） |
| 工具仓 | `resources[repo=tools].worktreePath` = `.rayai-worktrees/tools/requirement/CR-2026-058`（branch=`requirement/CR-2026-058`，HEAD=`2bb66294`） | 实施期改动落点见 SDD §1.1 |

## 3. 规则指针（只放指针，不复述）

- 拍板范围: prd.md §1.3；SDD §9（批准范围：仅两个新错误码）
- 判定表: prd.md FR-1（六行）；SDD §2.1/§4.2
- backlog 预检: prd.md FR-2.1；SDD §2.3/§4.3
- 故障边界: prd.md FR-2.2（三 fault point 表）；SDD §2.4/§4.6；**versionRefill 冻结规则: SDD §2.2 + §4.4 第 9 步（manifest 缺失/prepared/complete 三现场）**
- CLI 信封: prd.md FR-6；SDD §3（STATE_MISMATCH 新 throw 位 extra 保持 `{cr, phase}`）
- 测试设计: SDD §6.2（AC-2.3 含 1b 部分 apply 冻结回归；direct tasks/traceability 夹具 status=writing-back + 两账本 unassigned）
- 既有实现证据: SDD §6.3（七项，HEAD=`2bb66294`，branch=`requirement/CR-2026-058`）
- 架构基线: `../tools/ARCHITECTURE.md`（已存在，只读引用）
- 评审要求: review-annotations/sdd.yml（attempt-2 三项 blockers 原文）

## 4. 待办

1. quality-reviewer-agent 复评 `review-tech-design`（第 3 轮，max=3：BLOCK 则 reviewLoop 耗尽需协调处置；PASS → 人工 approve-tech-design）
2. 人工审批通过后 → write-dev-plan/write-dev-tasks（同一轮）→ 代码实施（tools 仓）→ write-test-report → 代码评审
3. 合入主仓后 CR-2026-057 才以 0.30 继续 writeback（本 CR 不推进 057）
