# scope-review 证据：**未闭合**（CR-2026-073 TASK-04 / AC-6、AC-7 评审部分）

本目录用于存放 plan §5 要求的三个独立 reviewer 案例（U / S / P）的真实 verdict 原始证据。
**当前为空缺：未取得，不得据此宣称 AC-6 / AC-7 的评审部分闭合。**

## 已具备（可核查）

| 事实 | 入口 |
|---|---|
| 三个 develop Skill 的文字合同已落盘 | `tools` 仓 `ab01e2b`：`skills/develop/write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-dev-plan/SKILL.md` |
| 合同级断言（只证明合同，不证明 verdict） | `test-evidence/cmd-06.log`（定向证据）、`cmd-07.log`（误设全仓/子集冒充全量判 blocker 口径）、`cmd-08.log`（上游全量例外文字合同） |

## 缺失（必须补取才能闭合）

| 缺失项 | 需要的动作 | 验收判据（plan §5） |
|---|---|---|
| U 快照（无批准全量却把全仓测试列为关键 cmd + TASK 附加全仓绿色）的独立 verdict | 在隔离测试 CR worktree 准备快照，交**新的独立 `quality-reviewer-agent` task/run** 按 `review-dev-plan` 评审 | `verdict=block`、给出具体 FR/AC 与证据 ID、`repair-target=write-dev-plan` |
| S 快照（关键 cmd 只跑子集、plan/TASK 声称全量通过）的独立 verdict | 同上 | `verdict=block`、给出 FR/AC、cmd、`repair-target=write-dev-plan` |
| P 快照（改为覆盖 FR/AC 的定向 cmd 且范围标注一致）的独立 verdict | 同上 | 不因缺全仓测试而 BLOCK |
| 每案的 subject SHA、源 CR/workspace、canonical `review-annotations/dev-plan.yml`、`review-loop.yml`、`crctl next` 与 reviewer 评论 | 随 verdict 一并留只读副本/可核查引用于本目录 | 测试报告可逐案引用 |

## 为什么本次未取得

三个案例各自需要一次独立的 reviewer run（异步、多 run），且需先在隔离 workspace 用版本化夹具/合法 crctl 流程建立可评审状态（本 CR 不手改任何业务 CR 的受控 status 或 canonical review）。
本轮（`implement-code → write-test-report`）已完成的是一次有界实现与本地证据发布；未在未准备快照的情况下发起 reviewer run（避免产生无有效输入的失败 run）。

> 不得拿本 CR 自身的 plan 评审当作 U/S 案例（plan §5 明确禁止）。
