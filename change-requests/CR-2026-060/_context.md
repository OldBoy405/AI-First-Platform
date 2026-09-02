# _context.md — CR-2026-060 上下文加速文件（本轮快照）

> 加速器不是事实源：事实以 cr.md / prd.md / sdd.md / plan.md / tasks 为准，crctl 不校验本文件。

## 状态（2026-09-02T20:44+08:00 快照）

- status: `tech-design-review-pending`；next 以 `crctl next CR-2026-060` 为准（预期 `review-tech-design`）
- 入口已复核：`requirement-approved` → `tech-designing` → `tech-design-review-pending`，attempt=1
- 权威 worktree: `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-060`
- 各仓 CR 分支：knowledge-base / multica / tools 均 `requirement/CR-2026-060`，inspect=healthy clean

## 产物地图

| 产物 | 路径 | 版本/状态 |
|---|---|---|
| PRD（契约基线） | `change-requests/CR-2026-060/prd.md` | subject-sha256 `d74ac20a97dc…87737586`；requirement 评审 PASS |
| SDD（本轮产出） | `change-requests/CR-2026-060/sdd.md` | frontmatter `target-version: "0.33"`；commit `acb0095` |
| 状态推进 | `change-requests/CR-2026-060/cr.md` | 两笔 `[cr] status` commit（→tech-designing、→tech-design-review-pending） |
| 需求评审记录 | `change-requests/CR-2026-060/review-annotations/requirement.yml` | verdict=pass，blockers=[]，suggestions 1 条已解决 |
| 人工审批 | `change-requests/CR-2026-060/approval.yml` | requirement 段 via=crctl-approve |

## 规则指针（不整读，按需定位）

- cr.md：本 CR 的 target-version=0.33、三角色 owner=Ray、source=AIFI-20
- PRD 关键章节：§3.1 模式裁决表（new/legacy 唯一判据）、§3.2 CLI delta 矩阵（register/gate pre-review/version-set/writeback-apply/archive）、§3.3/§3.3.1 Skill delta 矩阵、§3.4 四 TASK 约束、AC-01..18
- SDD 关键章节：§2 数据模型（target-spec-id/mode 判定）、§3 接口契约映射、§4 算法（resolveTargetSpecMode/pre-review/writeback mode 分支）、§6.2 AC 级输出合同、§9 批准范围（scope_in/out/zero_diff/follow_up）、§10 既有实现依赖证据
- 评审账本：`review-annotations/{requirement,sdd,dev-plan,code}.yml`；BLOCK 回修以触发评论 blockers 为准
- 上游契约文档：PRD（本 CR 只读基线）；SDD 被评审时以 `sdd.yml` verdict 为准

## 待办

- [ ] `review-tech-design` 评审（由 quality-reviewer-agent 执行，本轮结束已 @ 发起）
- [ ] 评审 PASS 后到达 `approve-tech-design` 人工审批（仅 Ray 在交互式终端 `crctl approve CR-2026-060 --stage tech-design`）
- [ ] 之后：`write-dev-plan` + `write-dev-tasks`（task_count_hint=4）同轮完成 → @ quality-reviewer-agent 评审 dev-plan
- [ ] TASK-1..4 与四变更组一一对应（G1 注册/authority、G2 writer-reviewer、G3 PLAN/TASK/coding/test/review、G4 writeback/archive+legacy）
