# _context.md — CR-2026-060 上下文加速文件（本轮快照）

> 加速器不是事实源：事实以 cr.md / prd.md / sdd.md / plan.md / tasks 为准，crctl 不校验本文件。

## 状态（2026-09-02T23:5x+08:00 快照，SDD attempt-2 回修完成）

- status: `tech-design-review-pending`；next 以 `crctl next CR-2026-060` 为准（预期 `review-tech-design`）
- 权威 worktree: `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-060`
- tools CR worktree: `.rayai-worktrees\tools\requirement\CR-2026-060`（HEAD `860288ce`，本 CR 尚未落 tools 代码——实施期）
- reviewLoop: review-requirement=1/PASS，review-tech-design current=1（BLOCK 已回修，attempt 2 待评审），max=3

## 产物地图

| 产物 | 路径 | 版本/状态 |
|---|---|---|
| PRD（契约基线） | `change-requests/CR-2026-060/prd.md` | subject-sha256 `d74ac20a97dc…87737586`；requirement 评审 PASS |
| SDD（本轮产出） | `change-requests/CR-2026-060/sdd.md` | attempt-2 修订版（回修 B-SDD-01..09 全部 blocker，[A2] 标注）；frontmatter `target-version: "0.33"` |
| 状态推进 | `change-requests/CR-2026-060/cr.md` | status 随 attempt-2 提交同批（--embedded） |
| 评审记录 | `review-annotations/requirement.yml`（pass）、`review-annotations/sdd.yml`（attempt 1 verdict=block，blockers=9） | attempt 2 由 quality-reviewer-agent 复评 |
| 人工审批 | `change-requests/CR-2026-060/approval.yml` | requirement 段 via=crctl-approve |

## 规则指针（不整读，按需定位）

- cr.md：target-version=0.33、三角色 owner=Ray、source=AIFI-20；本 CR 为 legacy registration（无 target-spec-id，两账本均缺）
- PRD 关键章节：§3.1 模式裁决表、§3.2 CLI delta 矩阵、§3.3/§3.3.1 Skill 矩阵、§3.4 四 TASK 约束、AC-01..18
- SDD 关键章节（attempt-2）：§2.2 authority 绑定 + strict 解析器、§2.3 错误码唯一裁决、§2.4 registrationAt、§3.1 CLI 映射、§4.1 resolveTargetSpecMode、§4.3 统一结果 builder、§4.4 writeback mode 分支、§4.5 TASK 三步断言、§4.6 pending preflight、§4.7 advance 层 guard、§4.8 new traceability 映射、§5 D-01..D-06、§9 批准范围、§10 依赖清单（SHA 语义已标注：tools=860288ce；kb 269ca7=PRD 审批落盘基线，评审时分支 HEAD=8da5395）
- 回修对照：B-SDD-01→§4.7；B-SDD-02→§4.8+D-04；B-SDD-03→§4.6+D-05；B-SDD-04→§2.4/§4.3；B-SDD-05→§4.3.2；B-SDD-06→§2.2.2-2.2.4；B-SDD-07→§2.3+D-06；B-SDD-08→§3.2/§8/§10；B-SDD-09→§4.5

## 待办

- [ ] `review-tech-design` attempt 2（本轮结束已 @ quality-reviewer-agent 复评）
- [ ] 评审 PASS 后到达 `approve-tech-design` 人工审批（仅 Ray 在交互式终端 `crctl approve CR-2026-060 --stage tech-design`）
- [ ] 之后：`write-dev-plan` + `write-dev-tasks`（task_count_hint=4，§4.5 三步断言）同轮完成 → @ quality-reviewer-agent 评审 dev-plan
- [ ] TASK-1..4 与四变更组一一对应（G1 注册/authority、G2 writer-reviewer、G3 PLAN/TASK/coding/test/review、G4 writeback/archive+legacy）
