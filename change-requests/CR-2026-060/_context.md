# _context.md — CR-2026-060 上下文加速文件（本轮快照）

> 加速器不是事实源：事实以 cr.md / prd.md / sdd.md / plan.md / tasks 为准，crctl 不校验本文件。

## 状态（2026-09-03T00:40+08:00）

- status: `task-breakdown`；next = `review-dev-plan`（缺 `review-annotations/dev-plan.yml`）
- 权威 worktree: `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-060`（HEAD `b4d2400`）
- tools CR worktree: `.rayai-worktrees\tools\requirement\CR-2026-060`（HEAD `860288ce`，本 CR 尚未落 tools 代码）
- inspect：三仓 `classification=healthy`；operationalWorkspace = 上述 kb 路径
- reviewLoop: review-requirement=1/PASS，review-tech-design=2/PASS；review-dev-plan 尚未记账
- 本 CR 为 legacy registration（两账本均无 `target-spec-id`，禁止回填）

## 产物地图

| 产物 | 路径 | 版本/状态 |
|---|---|---|
| PRD | `change-requests/CR-2026-060/prd.md` | subject-sha256 `d74ac20a97dc…87737586`；requirement PASS |
| SDD | `change-requests/CR-2026-060/sdd.md` | attempt-2；subject 基线 `24f860a`；tech-design PASS `a567d34` |
| PLAN | `change-requests/CR-2026-060/plan.md` | frontmatter `target-version: "0.33"`；commit `60287af` |
| TASK | `tasks/TASK-01.md`..`04.md` + `_index.yml` | 恰 4 条 pending；totalEstimateHours=54；commit `b4d2400`（含 cr.md `tech-design-reviewed → task-breakdown`） |
| 审批 | `approval.yml` | requirement + tech-design 段 via=crctl-approve |

## 规则指针

- cr.md：target-version=0.33、三角色 owner=Ray、source=AIFI-20、status=`task-breakdown`
- PRD：§3.1 模式裁决、§3.2 CLI 矩阵、§3.3/§3.3.1 Skill 矩阵、§3.4 四 TASK、AC-01..18
- SDD：§1.1 四组、§2.2 authority、§4.5 三步断言、§4.8 new traceability、§9 批准范围、§10 依赖（tools=`860288ce`）
- PLAN：§5.1 证据命令表 cmd-01..06；§5.3 基线红 BR-1/BR-2（860288ce 实测）；§6.1 交付覆盖表（FR 各一次）；§6.2 关键 AC 唯一 owner+cmd-NN
- TASK 组映射：01=G1 注册/authority；02=G2 writer-reviewer+approve；03=G3 PLAN/TASK/coding/test/review + count-hint；04=G4 writeback/archive/trace/Pipeline。依赖：02/03→01；04→01+03
- 账本 id 两位补零 `CR-2026-060-TASK-01`..`04`（对齐 `loadTaskCards`；口语 TASK-1..4 = 本组四个交付 TASK）

## 待办

- [ ] `review-dev-plan` attempt 1（本轮结束已 @ quality-reviewer-agent）
- [ ] 评审 PASS 后到达 `approve-dev-start`（仅 Ray 交互式终端；agent 不代签）
- [ ] BLOCK 时按 repair-target 回修 plan/tasks，不得改 SDD 范围
