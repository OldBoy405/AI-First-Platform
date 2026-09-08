# CR-2026-061 工作流导航缓存（dev-agent / code-implementation 计划与任务节点）
> 仅供返工与 /resume 导航；canonical 事实以 cr.md / plan.md / tasks/_index.yml / review-annotations / crctl 为准。
> 最近刷新：2026-09-08T12:39+08:00（dev-agent：review-dev-plan 第 1 轮 BLOCK 回修完成，待独立复评 attempt 2/3）

## 当前状态
- status: `task-breakdown`（第 1 轮 BLOCK 回修后经 crctl advance 推进；回修前为 `tech-design-reviewed` 回退态）。
- reviewLoop `review-dev-plan` = 1/3（attempt 未消耗；第 2 轮复评由 reviewer 记账 `--bump-attempt`）；`next` 以 `crctl next CR-2026-061` 为准（应为 `review-dev-plan`）。

## 第 1 轮 review-dev-plan BLOCK 与回修（本 run）
- BLOCK 落盘：`review-annotations/dev-plan.yml`（verdict=block，2 blockers，attempt 1/3，提交 `f264377`）；状态经 crctl 回退 `tech-design-reviewed`（提交 `e0d35ab`，trigger `review-dev-plan:block -> write-dev-plan`）。
- 回修对象仅 `plan.md`（§7 矩阵 + §8 理由文本 + §0 快照注记），TASK 卡/§6.1 未改，无需重跑 `crctl task init`：
  - **Blocker-1（AC-7 唯一 owner）**：AC-7 合并为恰一行，唯一 owner=CR-2026-061-TASK-04（证据 cmd-03）；「API 响应解析面」（TASK-03，cmd-01）与「client schema 兼容面」（TASK-04，cmd-04）改列「业务闭环」行。
  - **Blocker-2（AC-13 唯一 owner）**：AC-13 合并为恰一行，唯一 owner=CR-2026-061-TASK-03（证据 cmd-01 / cmd-02）；「AC-13 tools 面」改列「业务闭环」行（TASK-04，cmd-05），与 prompt 漂移防护行（cmd-06）并列；表后注记改为 AC-7/AC-13 双唯一 owner 机械可判说明。
  - **Suggestion-1（已处理）**：§8 第 1 条保留理由文本更正——真实理由=已审批 SDD 冻结不动（subject-sha256 `310434e7…` 保持）；正文首现顺序事实以 SDD 原文为准（#31 先于 #30，原 suggestion 方向正确）。
  - **Suggestion-2（已处理）**：§0 基线表 docs 行加「落笔时快照」注记（`731216db` 为落笔时值，随每次 CR 提交前移，实施期以 `crctl workspace freshness` 为准）。
  - **Suggestion-3（已处理）**：AC-5 行 SDD 落点注明「缺 key 三码属 handler 面，关联 TASK-03」；AC-11 行注明「前端保留选择/提示重试子句关联 TASK-04，证据面 cmd-03」。

## 本 CR 已交付（累计）
- `change-requests/CR-2026-061/plan.md`（§0 基线核实 allFresh + docs 落笔时快照注记；§6 两张稳定表：13 FR 交付覆盖表 + 6 条证据命令表 cmd-01..06；§7 AC/业务闭环覆盖矩阵（关键 AC 唯一 owner 机械可判）；§8 第 2 轮 3 条 suggestions 处理口径 + zero_diff 基线锁定表；TASK 拆分预分配 4 组）。
- `change-requests/CR-2026-061/tasks/TASK-01..04.md` + `tasks/_index.yml`（crctl task init --count-hint 4）：
  - TASK-01 数据层（12h）：迁移 505/506/507 + promotion.sql 10 查询 + migrate 登记。
  - TASK-02 服务内核（24h）：createInTx 提取 + PromoteDiscussion + 纯函数 + 默认标题描述。
  - TASK-03 HTTP/绑定/CLI（20h）：promotion handler/错误闭包/context_refs 暴露/bind 端点/CLI。
  - TASK-04 前端+tools（16h）：client/schemas/discussion-pane/issue-detail/locales + requirement-register SKILL 绑定步骤与测试。
  - 依赖链：TASK-01 → TASK-02 → TASK-03 → TASK-04（无环）。
- 估算总工时（TASK 账本口径）：72h。

## 关键设计锚点（返工时先读 plan.md 对应节）
- 基线：multica `eafce66b`（trunk 已前移，SDD 锚点 78e14082 → 新基线逐项复核存活，行号微移 4 处见 plan §0）、tools `49c46dd`、docs CR 分支为移动目标（落笔时快照，勿按固定 SHA 对照）。
- 证据命令表（plan §6.2）：cmd-01 go handler/service；cmd-02 go governance/migrate；cmd-03 pnpm views；cmd-04 pnpm core；cmd-05 node --test promotion-bind；cmd-06 lint-prompts enforce。
- 已审批 SDD 不修订：3 条 suggestions 处理口径在 plan §8（含 zero_diff 基线锁定表）。

## 恢复入口
1. 独立 reviewer（quality-reviewer-agent，新会话）执行 `review-dev-plan`（attempt 2/3，review-record 带 `--bump-attempt`）：
   - crctl 一律带 `--workspace C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`
   - 评审对象：`change-requests/CR-2026-061/plan.md`（第 1 轮 BLOCK 回修版）+ `tasks/`（TASK-01..04）；重点复核：§7 AC-7/AC-13 唯一 owner 重构、§8 第 1 条理由更正、§0 快照注记、AC-5/AC-11 关联 TASK 注记。
2. 再 BLOCK → repair-target `write-dev-plan`（作者会话 = dev-agent 本 Agent）：状态回 `tech-design-reviewed`，按 blocker 修订 plan.md（必要时重生成 TASK + `crctl task init --count-hint 4` 刷新），再推进 `task-breakdown` 后重新委派 reviewer 复评。
3. PASS → 停在 `task-breakdown`，进入 push-progress → 开发启动人工审批（`approve-dev-start`，届时需 Ray 确认）。

## 环境提示
- 三仓 worktree：docs（KB，operational）`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-061`；
  multica / tools 同名 sibling worktree（`crctl workspace inspect` 为准）。KB worktree 分支 = `requirement/CR-2026-061`。
- 本缓存随 plan.md 提交一并纳入（不单独建提交）。
