# U/S/P 三案的独立 reviewer run：人去执行的最小入口与证据清单

> **状态（2026-09-30）**：三案 run 与采集**已由人执行完毕**，真实 verdict 逐案落在 `independent-run/{U,S,P}/`，
> 结论与残余偏离见 `../NOT-CLOSED.md`。以下步骤保留为**已执行的操作记录**与复现入口（复跑会覆盖证据，无必要勿重跑）。

CR-2026-073 TASK-04 / plan §5 的 C 项取证要求：U/S/P 三个隔离快照各由**一个新的独立 `quality-reviewer-agent` run**
按 `review-dev-plan` 给出真实 verdict、subject SHA、canonical review-loop/next 与对应评论。

Ray 在 AIFI-38 对 B-C1 的裁决为**选 2**：按 FR-A7「无 Multica task context 的本地执行」评审同一批快照，
**保持隔离、零平台副作用**——不在真实 KB root 建 CR 行、不动 `MULTICA_CR_WORKSPACES`。

## 1. 平台侧入口核查结论（Agent 已核，2026-09-30）

`multica` CLI 没有创建「无 task context 的 run」的入口：`multica task` 子命令不存在，
run 只能由 issue 指派 / 评论 mention / wakeup 触发（必然携带 task-scoped context），
而带 task context 的 run 会在 `review-dev-plan` Step 3.0 处先 `multica cr bind-current-task`，
隔离夹具 CR 没有平台投影行 → `CR_NOT_FOUND` / 404 技术中止。
**结论：这条 run 只能由人在本机直接启动（不经 Multica），Agent 不创建、不代跑。**

## 2. 前置检查（人）

```powershell
# ① 必须是"干净终端"：下面这条应输出空（无 Multica task context）
Get-ChildItem Env:MULTICA_TASK_ID, Env:MULTICA_TOKEN, Env:MULTICA_TASK_CONFIG_ROOT -ErrorAction SilentlyContinue
# ② node 可用
node --version
# ③ 三案仍处于"待 dev-plan 评审"状态（各自应打印 next=review-dev-plan）
& node "C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-073\skills\shared\crctl\scripts\crctl.mjs" next CR-2026-901 --workspace "C:\Users\GOBAO\Downloads\AI\cr073-scope-fixtures\.rayai-worktrees\knowledge-base\requirement\CR-2026-901"
```

受评版本（必须用它执行，否则不是在测本 CR 的 Skill 文本）：

| 项 | 路径 / 提交 |
|---|---|
| `review-dev-plan` 技能（受评版本） | `…\.rayai-worktrees\tools\requirement\CR-2026-073\skills\develop\review-dev-plan\SKILL.md`（tools worktree `ab01e2b8`） |
| `crctl`（受评版本） | `…\.rayai-worktrees\tools\requirement\CR-2026-073\skills\shared\crctl\scripts\crctl.mjs` |
| reviewer 角色说明（仓库工作副本，非平台已部署文本） | `…\AI\multica\cr-prompts-revised\quality-reviewer-agent.md` |

## 3. 逐案执行（三案三个会话，**不要**在同一会话里连跑）

以 U 案为例（S/P 只需把 `901→902/903`、`U→S/P`）：

```powershell
$ev = 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-073\change-requests\CR-2026-073\test-evidence\scope-review\independent-run\U'
New-Item -ItemType Directory -Force -Path $ev | Out-Null

# 本地 reviewer 会话；原始会话日志完整留档
Start-Transcript -Path "$ev\reviewer-run.log"
Set-Location 'C:\Users\GOBAO\Downloads\AI\cr073-scope-fixtures\.rayai-worktrees\knowledge-base\requirement\CR-2026-901'
claude        # 或 pi / opencode —— 任一本地 harness，均在无 task context 下运行
#   → 把 `prompts\U.md` 全文作为第一条消息粘贴进去
#   → 等它自己调 crctl 落盘、报出 verdict/blockers/dimensions/subject-sha256 与原样 crctl next
#   → 退出（/exit）
Stop-Transcript

# 采集证据（只读夹具、只写本 CR 的 test-evidence）
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-073\change-requests\CR-2026-073\test-evidence\scope-review\independent-run\collect-evidence.ps1' -Case U
```

无头替代（不想开会话时）：`claude -p (Get-Content -Raw '…\prompts\U.md') *>&1 | Tee-Object -FilePath "$ev\reviewer-run.log"`。

## 4. 必须原样保留的证据（每案一份）

| # | 证据 | 落点（`independent-run\<U|S|P>\`） | 说明 |
|---|---|---|---|
| 1 | 本地 run 原始会话日志（未截断） | `reviewer-run.log` | 含所用命令、cwd、模型自报、`crctl` 原样输出 |
| 2 | canonical `review-annotations/dev-plan.yml` | `canonical\…_dev-plan.yml` | 由 `crctl review-record` 写；含 `verdict` / `blockers` / `dimensions` / `repair-target` / `subject-sha256` / `reviewer` / `reviewed-at` |
| 3 | `review-loop.yml`、`traceability.yml` | `canonical\…` | attempt 与投影账本落盘后的原文 |
| 4 | `crctl next <CR>` 原样输出 | `crctl-next.txt` | 路由证据 |
| 5 | 夹具 HEAD 与工作树状态 | `fixture-head.txt` / `fixture-status.txt` | 证明 subject 未被额外改动 |
| 6 | 逐文件 sha256 清单 | `MANIFEST.txt` | `collect-evidence.ps1` 生成 |

三案的**设计轴与期望**（判据登记，**不要**写进 reviewer 输入，避免诱导判定）：

| 案 | 轴 | 期望 |
|---|---|---|
| U（CR-2026-901） | plan 把全仓 `make test` 设为关键 `cmd-01`、TASK 附加全仓绿色，且无已批准的全量要求 | `verdict=block`，带具体 FR/AC 与证据 ID，`repair-target=write-dev-plan` |
| S（CR-2026-902） | 关键 cmd 只跑两个定向用例，plan/TASK 声称全量通过 | `verdict=block`（子集不得冒充全量） |
| P（CR-2026-903） | 定向 `cmd-NN` 覆盖 FR/AC、范围标注一致、不附加全量 | **不因缺全仓测试**被 block（其他 blocker 不得冒充该案结论） |

## 5. 边界（违反即证据作废）

- 不在真实 KB root（`AI First Platform` 仓）建 CR 行、不推进任何业务 CR 状态；
- 不设置、不依赖 `MULTICA_CR_WORKSPACES`；不调用 `multica` CLI 的写命令；
- 不手改受控文件（`dev-plan.yml` / `review-loop.yml` / `traceability.yml` / `cr.md` / `_backlog.yml`）——一律经 crctl；
- 不 `git push`、不 `merge`/`rebase`、不改 multica 代码；
- 每个案一个新的独立会话（不复用会话，也不由 dev-agent 代跑）。

## 6. 已知残余偏离（需由 reviewer 裁决）

plan §5 的证据入口列出了「对应 issue reviewer 评论」。在零平台副作用前提下，
本地 run **不会**产出 Multica 评论（没有平台身份、也没有平台写入）。本目录以
`reviewer-run.log`（reviewer 自己的原始报告）+ canonical 三件替代；
若需要评论形态，可由 Ray 把每案 verdict 摘要（或 `reviewer-run.log` 原文）作为**人发评论**贴到 AIFI-38，
该写入是人的动作、不涉及 CR 行或 `MULTICA_CR_WORKSPACES`。
