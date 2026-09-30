# scope-review 证据：**仍未闭合，但已转为「人可一条命即可执行」的待办**（CR-2026-073 TASK-04 / AC-6、AC-7 评审部分）

本目录存放 plan §5 要求的三个独立 reviewer 案例（U / S / P）的真实 verdict 原始证据。

**当前状态（2026-09-30 更新）**：夹具已就绪、机制自检已通过；Ray 已对 B-C1 裁决**选 2**（按 FR-A7「无 Multica task context
的本地执行」评审同一批快照，保持隔离、零平台副作用）；**三案的独立 reviewer run 尚未执行**（该 run 只能由人启动，见下），
因此 AC-6 / AC-7 的评审部分**仍不得宣称闭合**。

## Ray 的裁决与平台侧入口核查

- 裁决（AIFI-38，由 cr-coordinator-agent 转达）：B-C1 **选 2** = 无 task context 的本地执行；**不要**在真实 KB root 建 CR 行、**不要**动 `MULTICA_CR_WORKSPACES`。
- Agent 侧核查结论：`multica` CLI **没有**创建「无 task context run」的入口（无 `multica task` 子命令；run 只能由 issue 指派 / 评论 mention / wakeup 触发，必然携带 task context）。因此这条 run **只能由人在本机直接启动**，Agent 不创建、不代跑。
- 人类入口与证据清单：`independent-run/README.md`；三案可粘贴提示词：`independent-run/prompts/{U,S,P}.md`；采集脚本：`independent-run/collect-evidence.ps1`。

## 已具备（可核查）

| 事实 | 入口 |
|---|---|
| 三个 develop Skill 的文字合同已落盘 | `tools` 仓 `ab01e2b`：`skills/develop/write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-dev-plan/SKILL.md` |
| 合同级断言（只证明合同，不证明 verdict） | `test-evidence/cmd-06.log`、`cmd-07.log`、`cmd-08.log` |
| U/S/P 快照夹具（三案共用同一 SDD/AC，只换 plan/TASK 证据范围） | `fixtures/`（`shared/`、`variants/{U,S,P}/`、`build-snapshots.mjs`） |
| 快照已建起且处于可评审状态（`task-breakdown` → `next=review-dev-plan`，2026-09-30 复核仍成立） | `MECHANISM.md` §1/§2、`fixtures/verify-mechanism.log` |
| canonical 落盘与路由链路自检（合成 payload，非 verdict） | `MECHANISM.md` §2 末行 |
| 人去执行的最小入口 + 必须原样保留的证据清单 | `independent-run/README.md`、`independent-run/prompts/`、`independent-run/collect-evidence.ps1` |

## 缺失（必须补取才能闭合）

| 缺失项 | 需要的动作 | 验收判据（plan §5） |
|---|---|---|
| U / S / P 各自的**独立 `quality-reviewer-agent` run** 真实 verdict（新的独立 run，三案三会话） | 由人在干净终端启动本地 reviewer（`independent-run/README.md` §3）；Agent 不创建该 run | U/S：`verdict=block` + 具体 FR/AC 与 `cmd-NN`、`repair-target=write-dev-plan`；P：不因缺全仓测试被 block（其他 blocker 不得冒充该案结论） |
| 每案的 subject SHA、canonical `review-loop.yml`、`crctl next`、原始 run 日志 | 随 verdict 一并留引用（`independent-run/collect-evidence.ps1` 采集 + sha256 清单） | 测试报告可逐案引用 |
| 「对应 issue reviewer 评论」 | 零平台副作用下本地 run 不产出 Multica 评论；替代为 `reviewer-run.log`，或由人把 verdict 摘要作为人发评论贴到 AIFI-38（残余偏离，由 reviewer 裁决） | `independent-run/README.md` §6 |

## 本轮为何仍未取得（结构性原因，非"未尝试"）

平台委派的 reviewer run 会在 `review-dev-plan` Step 3.0 的 `multica cr bind-current-task {cr_id}` 处技术中止：绑定要求平台侧已存在该 CR 的投影行 `cr(workspace_id, cr_id)`（`server/internal/service/task.go#LockCrForCrBind` → `CR_NOT_FOUND`/404 零写入），而隔离夹具 CR 没有投影行（平台行只由已配置 root 的 outbox 状态事件或 root `_backlog.yml` 快照产生）。两条已排除路径（A 平台可见测试 CR、C 修订验收合同）与代价逐条见 `MECHANISM.md` §3。

> 不得拿本 CR 自身的 plan 评审当作 U/S 案例（plan §5 明确禁止）。也不得以 `cmd-06`/`cmd-07` 的绿色代替这些 verdict。
