# scope-review 证据：**未闭合**（CR-2026-073 TASK-04 / AC-6、AC-7 评审部分）

本目录存放 plan §5 要求的三个独立 reviewer 案例（U / S / P）的真实 verdict 原始证据。
**当前状态：夹具已就绪并跑通机制自检，但三案的独立 reviewer verdict 仍未取得 → 不得据此宣称 AC-6 / AC-7 的评审部分闭合。**

## 已具备（可核查）

| 事实 | 入口 |
|---|---|
| 三个 develop Skill 的文字合同已落盘 | `tools` 仓 `ab01e2b`：`skills/develop/write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-dev-plan/SKILL.md` |
| 合同级断言（只证明合同，不证明 verdict） | `test-evidence/cmd-06.log`、`cmd-07.log`、`cmd-08.log` |
| U/S/P 快照夹具（三案共用同一 SDD/AC，只换 plan/TASK 证据范围） | `fixtures/`（`shared/`、`variants/{U,S,P}/`、`build-snapshots.mjs`） |
| 快照已建起且处于可评审状态（`task-breakdown` → `next=review-dev-plan`） | `MECHANISM.md` §1/§2、`fixtures/verify-mechanism.log` |
| canonical 落盘与路由链路自检（合成 payload，非 verdict） | `MECHANISM.md` §2 末行 |

## 缺失（必须补取才能闭合）

| 缺失项 | 需要的动作 | 验收判据（plan §5） |
|---|---|---|
| U / S / P 各自的**独立 `quality-reviewer-agent` run** 真实 verdict | 见 `MECHANISM.md` §3 的路径 A / B / C（需人工或平台决定） | U/S：`verdict=block` + 具体 FR/AC、`cmd-NN`、`repair-target=write-dev-plan`；P：不因缺全仓测试被 block |
| 每案的 reviewer 评论 | 随 verdict 一并留引用 | 测试报告可逐案引用 |

## 本轮为何仍未取得（结构性原因，非"未尝试"）

平台委派的 reviewer run 会在 `review-dev-plan` Step 3.0 的 `multica cr bind-current-task {cr_id}` 处技术中止：绑定要求平台侧已存在该 CR 的投影行 `cr(workspace_id, cr_id)`（`server/internal/service/task.go#LockCrForCrBind` → `CR_NOT_FOUND`/404 零写入），而隔离夹具 CR 没有投影行（平台行只由已配置 root 的 outbox 状态事件或 root `_backlog.yml` 快照产生）。三条可行路径与其代价逐条见 `MECHANISM.md` §3。

> 不得拿本 CR 自身的 plan 评审当作 U/S 案例（plan §5 明确禁止）。
