# CR-2026-066 工作流导航缓存（`_context.md`）

> 本文件是**导航缓存**，不是 canonical 事实。canonical 事实优先：`cr.md`、`review-loop.yml`、
> `traceability.yml`、`review-annotations/**`、`approval.yml`、`_backlog.yml`、`tasks/_index.yml`。
> 用途：返工与 `/resume` 时快速定位「做到哪、卡在哪、从哪继续」。

## 1. 当前状态（最近一次刷新：`code-implementation` node-1/node-2 **重放回修** run，2026-09-14 15:2x +08:00）

- CR：`CR-2026-066`（AIFI-27；CR-P3「评审 PASS 发布与 checkpoint 委派收敛」）。
- 权威 workspace = `.rayai-worktrees/knowledge-base/requirement/CR-2026-066`；三仓 worktree =
  `.rayai-worktrees/{knowledge-base,multica,tools}/requirement/CR-2026-066`；命令一律带 `--workspace <权威路径>`
  （主 checkout 视图陈旧，AGENTS.md 纪律 #9）。
- 本 run 节点：**`write-dev-plan` → `write-dev-tasks`（`review-dev-plan` cycle 1 / attempt 1 BLOCK 后的普通轨重放）**；
  未进入 `review-dev-plan`（复评由独立 reviewer 新 run 执行）。
- **本 run 落盘**：`change-requests/CR-2026-066/plan.md`（回修后 **438 行 / 78,253 B / 纯 LF**，
  `sha256(LF) e20f7eed7c57cd9a6df7b8f9ca594fe89f57175d808d68d18af3bf655b10ee98`）＋
  `tasks/TASK-01.md` / `TASK-03.md` / `TASK-04.md`（TASK-02 本轮未改）＋ `tasks/_index.yml`
  （`crctl task init --count-hint 4` ⇒ `taskCount=4`、`totalEstimateHours=88`、`changed=false`，即账本无漂移）＋ 本文件。
- 提交：`5d2411d6` `[cr] repair dev plan CR-2026-066 (… B-1 cmd-05 case-name guard + 6 suggestions)` →
  `20ec1e25` `[cr] repair dev tasks CR-2026-066 (TASK-01/03/04 …)` →
  `37376b1b` `[cr] repair dev plan CR-2026-066 (S-4 recount …)` → 状态提交
  `[cr] status CR-2026-066 tech-design-reviewed -> task-breakdown (… + nav cache)`（**均未 push**；
  下一批次由上一条命令的 `push-progress` 承担）。
- `crctl advance CR-2026-066 --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed --embedded`
  ⇒ `advanced=true`（outbox `20260914T072308215Z-CR-2026-066-status-pending1.json`）。
- `crctl status/next` 实测：**`status = task-breakdown`**；`crctl next` 仍显示 **`write-dev-plan`**
  （why「开发计划评审未通过（blockers=1 条），回修 plan/TASK」）——该值是工具按 `review-annotations/dev-plan.yml`
  的既有 block 注解路由的回修入口，**回修已在本 run 执行完毕**；下一步 = **`review-dev-plan` 复评**（独立 reviewer 新 run）。
- 未触碰：`prd.md`、`sdd.md`（**审批冻结，post-approval 改动会触发 `APPROVED_ARTIFACT_DRIFT`**）、
  `approval.yml`、`review-annotations/**`、`review-loop.yml`、`traceability.yml`、`_backlog.yml`；
  tools / multica 两个代码仓本 run **零改动**（`crctl git status --short --cwd .` 干净后提交）。
- 平台绑定：`multica cr bind-current-task CR-2026-066` ⇒ `changed=true`（issue `01a09dc1` / task `01a09ebf-cb82-708e-83e1-0cbe7dec766e`）。

## 2. 本轮回修要点（canonical：`plan.md` §8.E ＋ `review-annotations/dev-plan.yml`）

| 项 | 内容 |
|---|---|
| **B-1（blocker）** | `cmd-03` 的 5 个既有用例名**无存在性守卫**：`--test-name-pattern` 空跑 exit 0、dot 报告器只出点号（10 个、无名字无摘要）⇒ 退出码/点号不构成存在性证据。修法：`cmd-05` 新增**源码级守卫（g）**——3 文件 × 5 token，逐个断言声明形态 `test('<token>` ≥ 1；表注④ 按此重写；TASK-01 §4.2/§5、TASK-03 §4.1/§5 改为「`cmd-05` 守卫同批绿 ＋ 记 token 清单与计数」 |
| S-1 | `RETIRED_RECOVERY` 零命中归属 `cmd-04` → **`cmd-02`**（`contract-scan` 整树扫描；§6.1 FR-3 行、§7 AC-10 行） |
| S-2 | `cmd-07` 正向 token 扫描面**收窄为 §10 区块**（原全文面可被 §6.2.1~§6.2.3 说明行自证：16 个正向 token 中 12 个在 §10 之外有命中）；负向面仍按剔除 `-e` 行后的全文 |
| S-3 | `tasks/TASK-04.md` §5 计数 11 → **13 个文件**（§2 表 10 行展开：5 处文档 ＋ tools 三份 Prompt ＋ multica 四份副本 ＋ `contract-scan.test.mjs`；tools 9 ＋ multica 4） |
| S-4 | `tasks/TASK-01.md` 计数口径统一为**按 SDD §6.4 表格行**：`pipeline-structure` 既有断言 **12 行**（＋1 行新增），四测试文件既有断言改动合计 **15 行**（12＋1＋1＋1）；评审意见的 14 系把该文件按 11 行计，差异已在 §8.E 写明依据 |
| S-5 | SDD §4.7 把 dev-agent 两句旧前提句登记在 tools `agents/dev-agent.md`（实测该文件 70 行零 `checkpoint`），实际只在 multica `cr-prompts-revised/dev-agent.md` L23/L41 ⇒ **登记为 SDD 落点错位**（不改 SDD）；交付面按 multica 落点、`cmd-06` 已按 multica 判据 |
| S-6 | `tasks/TASK-01.md` §3.3 ②「被删的 7 个 id **后缀**零出现」按字面恒假（`…0003`/`…0005` 等后缀在存活节点上仍存在）⇒ 改按**完整节点 id**（7 个逐字列出）断言 |
| 表述澄清 | 「保留用例名」= 保留 **token 前缀**（`CR-2026-042 静态合同` / `checkpoint T05 contract` / `CR-2026-044 AC-13` / `CR-2026-044 AC-14` / `CR-2026-050 AC-12`）；后缀若因新事实失真则同步更新（如 `16 节点` → `12 节点`、`（7 节点）` → `（5 节点）`、`5 节点不变` → `4 节点`），前缀不得改（改前缀即守卫红） |

## 3. 评审反馈与恢复入口（canonical：`review-annotations/*.yml`、`review-loop.yml`）

| 项 | 事实 |
|---|---|
| 上一轮 verdict | `review-dev-plan` cycle 1 / **attempt 1/3 = BLOCK**（8 维中 `acceptance-verifiability` = block，其余 7 维 pass）；1 blocker ＋ 6 suggestions；`repair-target=write-dev-plan`；annotation 提交 `f42a6f90`、状态提交 `28d0d637` |
| 下一节点 | **`review-dev-plan`（复评，新 run、`--bump-attempt` ⇒ attempt 2/3）**；PASS 后由 dev-agent 执行 `push-progress`（`message=计划与任务`）→ 止于**人工 dev-start 审批 gate**（`crctl approve --stage dev-start`，Agent 不代签） |
| BLOCK 路由 | 普通轨（`repair-target=write-dev-plan`）→ `reviewLoop.replayNodes` 重放 `write-dev-plan → write-dev-tasks → review-dev-plan`（≤3 轮）；上游设计缺口走 `review-dev-plan:upstream-design-blocker`（`task-breakdown → tech-design-review-pending`） |
| 已知工具提示 | `task-breakdown` 状态下 `crctl next` 由 `dev-plan.yml` 是否存在于 `review-annotations/` 判定；该 block 注解存续期间 `next` 恒指向回修入口 `write-dev-plan`，回修完成与否以产物与本轮 run 记录为准，路由以 canonical `repair-target` 与 pipeline `reviewLoop` 为准 |
| 本 run 证据（只读实跑） | 新 `cmd-05` 脚本（plan §6.2 逐字转录）在 tools worktree = **exit 1 / 42 failures**（与回修前基线逐项一致；新增 5 项守卫逐行打印 `5/1/2/1/1` 全绿）；新 `cmd-07` = **exit 0**（`section10` 35 行、16 个正向 token 齐备、负向零命中）；守卫谓词负控：临时副本里把 `CR-2026-050 AC-12` 用例改名去掉 token 前缀 ⇒ 该守卫计数 0 且 exit 1（改回即绿）；`cmd-06` 基线与 `_index.yml` 未变 |
| 证据面预算 | `write-test-report` 节点 20 min；预算合计 ≤ 966 s（cmd-01 独占 786 s），顺序把 cmd-01 排第一 |
