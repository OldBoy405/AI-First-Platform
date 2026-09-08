# CR-2026-061 工作流导航缓存（dev-agent / code-implementation 计划与任务节点）
> 仅供返工与 /resume 导航；canonical 事实以 cr.md / plan.md / tasks/_index.yml / review-annotations / crctl 为准。
> 最近刷新：2026-09-08T12:04+08:00（dev-agent：write-dev-plan + write-dev-tasks 完成，待独立 review-dev-plan）

## 当前状态
- status: `task-breakdown`（计划与 TASK 拆分完成，经 crctl advance，未手改账本）。
- reviewLoop `review-dev-plan` 未启动（0/3）；`next`（crctl）以 `crctl next CR-2026-061` 为准。

## 本 run 已交付
- `change-requests/CR-2026-061/plan.md`（§0 基线核实 allFresh；§6 两张稳定表：13 FR 交付覆盖表 + 6 条证据命令表 cmd-01..06；§7 AC/业务闭环覆盖矩阵；§8 第 2 轮 3 条 suggestions 处理口径 + zero_diff 基线锁定表；TASK 拆分预分配 4 组）。
- `change-requests/CR-2026-061/tasks/TASK-01..04.md` + `tasks/_index.yml`（crctl task init --count-hint 4）：
  - TASK-01 数据层（12h）：迁移 505/506/507 + promotion.sql 10 查询 + migrate 登记。
  - TASK-02 服务内核（24h）：createInTx 提取 + PromoteDiscussion + 纯函数 + 默认标题描述。
  - TASK-03 HTTP/绑定/CLI（20h）：promotion handler/错误闭包/context_refs 暴露/bind 端点/CLI。
  - TASK-04 前端+tools（16h）：client/schemas/discussion-pane/issue-detail/locales + requirement-register SKILL 绑定步骤与测试。
  - 依赖链：TASK-01 → TASK-02 → TASK-03 → TASK-04（无环）。
- 估算总工时（TASK 账本口径）：72h。

## 关键设计锚点（返工时先读 plan.md 对应节）
- 基线：multica `eafce66b`（trunk 已前移，SDD 锚点 78e14082 → 新基线逐项复核存活，行号微移 4 处见 plan §0）、tools `49c46dd`、docs CR 分支 `731216db`。
- 证据命令表（plan §6.2）：cmd-01 go handler/service；cmd-02 go governance/migrate；cmd-03 pnpm views；cmd-04 pnpm core；cmd-05 node --test promotion-bind；cmd-06 lint-prompts enforce。
- 已审批 SDD 不修订：3 条 suggestions 处理口径在 plan §8（含 zero_diff 基线锁定表）。

## 恢复入口
1. 独立 reviewer（quality-reviewer-agent，新会话）执行 `review-dev-plan`（attempt 1/3）：
   - crctl 一律带 `--workspace C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`
   - 评审对象：`change-requests/CR-2026-061/plan.md` + `tasks/`（TASK-01..04）；重点：批准范围四字段译对、13 FR 交付覆盖表、6 条 cmd 证据面、AC 矩阵唯一 owner、4 TASK 可执行性/接口契约/依赖、§8 suggestions 处理口径、plan §0 基线前移事实。
2. BLOCK → repair-target `write-dev-plan`（作者会话 = dev-agent 本 Agent）：状态回 `tech-design-reviewed`，按 blocker 修订 plan.md（必要时重生成 TASK + `crctl task init --count-hint 4` 刷新），再推进 `task-breakdown` 后重新委派 reviewer 复评。
3. PASS → 停在 `task-breakdown`，进入 push-progress → 开发启动人工审批（`approve-dev-start`，届时需 Ray 确认）。

## 环境提示
- 三仓 worktree：docs（KB，operational）`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`；
  multica / tools 同名 sibling worktree（`crctl workspace inspect` 为准）。KB worktree 分支 = `requirement/CR-2026-061`。
- 本缓存随 plan/tasks 提交一并纳入（不单独建提交）。
