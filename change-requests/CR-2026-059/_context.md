---
cr: CR-2026-059
pipeline-node: write-dev-plan + write-dev-tasks（code-implementation 第 1/2 节点完成，待独立 review-dev-plan）
status: task-breakdown
updated: 2026-09-04T16:45:00+08:00
owner-agent: dev-agent
---

# CR-2026-059 工作流导航缓存（_context.md）

> 导航缓存，非 canonical。canonical 事实以 `cr.md` / `review-loop.yml` / `traceability.yml` / `review-annotations/*` 为准。

## 当前状态

- 架构期已闭环：sdd.md cycle 3 复评 PASS（canonical 落盘，attempt 3/3），人工 `approve --stage tech-design` 已于 2026-09-04 批准（approval.yml approver=OldBoy405）。
- 本轮 = code-implementation 起点：`write-dev-plan`（plan.md）+ `write-dev-tasks`（TASK-01..04 + `crctl task init --count-hint 4`），status 已推进 `task-breakdown`。
- 下一步：独立 `quality-reviewer-agent` 执行 `review-dev-plan`（dev-plan 评审环首轮，attempt 1/3）。

## 本轮产物

- `change-requests/CR-2026-059/plan.md`：里程碑 M0–M4、任务依赖图 T-01→T-02→T-03→T-04、风险与回滚、两张稳定表（交付覆盖表 26 FR 行 + 证据命令表 cmd-01..06）、AC 覆盖矩阵 32 行。target-version=0.32（继承 cr.md）。
- `change-requests/CR-2026-059/tasks/TASK-01..04.md` + `_index.yml`（crctl task init 生成，totalEstimateHours=72h，与 plan §3/§5 一致）：
  - TASK-01 迁移与数据层（16h）：481–490 迁移 + down 全集 + 钩子登记（up=483/485/488/490，down 仅 484.down）+ sqlc 查询 + CUSTOM.md。
  - TASK-02 服务层（24h）：discussion_session.go（ensure/send/trigger/投影/幂等）+ sweeper + merge-forward 渲染 + 转投适配；`sendProjectChatCore` zero_diff。
  - TASK-03 处理层与实时（20h）：handler kind 分流 + 错误码矩阵 + 事件 kind + DisconnectWorkspaceUser + 附件门禁 + sweeper 接线。
  - TASK-04 前端（12h）：schemas 硬降级 + DiscussionPane session 身份 + 作者展示 + 四语文案。
- 证据命令表（cr-test-plan/v1 机器区 commands 1-based 对应）：cmd-01 migrate / cmd-02 handler+service / cmd-03 handler+agent / cmd-04 realtime / cmd-05 core schemas / cmd-06 views parity。

## 评审入口（给 reviewer / 恢复会话）

1. 权威 worktree：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-059`（分支 `requirement/CR-2026-059`）。
2. 评审对象：`plan.md` + `tasks/TASK-01..04.md` + `tasks/_index.yml`，对照已审批 `sdd.md`（`prd.md` 仅按 SDD 引用抽查）。evidence 基线 = multica CR worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（三仓 healthy）。
3. 前置：`multica cr bind-current-task CR-2026-059` → `crctl gate CR-2026-059 --for dev-plan-reviewing`（若 gate 名有变以 `crctl next` 为准）→ `crctl review-record CR-2026-059 --stage dev-plan --bump-attempt`（attempt 1；无论 PASS/BLOCK 都落盘 canonical；**落盘后请随即提交并推送三账本**——review-record 只写文件不提交）。
4. PASS：落盘后回报；人工 `approve --stage dev-start` 由 coordinator 发布。BLOCK：按 repair-target 直连 @ dev-agent 回修（`review-dev-plan:block -> write-dev-plan` 回退重放；upstream 才走 write-tech-design）。

## 已核实事实基线（沿用 sdd §10）

- 三仓 `workspace inspect` healthy/dirty=false；multica CR worktree HEAD `be6426a7c`（还原提交，树=main e8b25259）；tools `8b1e352`。
- 测试基建：`server/go.mod`（go test 各包）；`packages/core`、`packages/views` 均 `vitest run`；`packages/core/api/schemas.test.ts`、`packages/views/locales/parity.test.ts` 存在。
- `crctl task init` 前置态 = tech-design-reviewed/task-breakdown；`crctl task done` 仅 `developing`；TASK 卡 estimate 格式 `^[1-9]\d*h$`。
