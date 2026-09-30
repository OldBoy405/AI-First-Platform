# scope-review 证据：**已补齐**（CR-2026-073 TASK-04 / AC-6、AC-7 评审部分）

**更新（2026-09-30，人侧取证完成）**：Ray 在 AIFI-38 对 B-C1 裁决**选 2**（按 FR-A7「无 Multica task context 的本地执行」
评审同一批快照，保持隔离、零平台副作用），并在本机按 `independent-run/README.md` 完成三案（U / S / P）
**三个独立本地 reviewer run**，证据已由 `independent-run/collect-evidence.ps1` 采集落盘（脚本编码修复 `721a9cb4`）。
本文件先前的「三案 verdict 尚未执行、仍不得宣称闭合」结论**已被本轮实测取代**；历史说明保留在文末。

**采集口径与判据冲突声明（供 reviewer 裁定）**：三案的「设计轴与期望」只登记在本目录与 `independent-run/README.md`，
**未写入** reviewer 输入（`prompts/{U,S,P}.md`）——reviewer 只拿到快照本身，不存在按期望诱导判定的提示。

## 1. 已取得的三案证据（逐案入口）

| 案 | CR | 期望（设计判据） | 实测 verdict | `repair-target` | `crctl next` | 证据目录 |
|---|---|---|---|---|---|---|
| U | CR-2026-901 | block + FR/AC + 证据 ID + `write-dev-plan` | **block** | `write-dev-plan` | `write-dev-plan`（回修 plan/TASK） | `independent-run/U/` |
| S | CR-2026-902 | block（子集不得冒充全量） | **block** | `write-dev-plan` | `write-dev-plan`（回修 plan/TASK） | `independent-run/S/` |
| P | CR-2026-903 | 不因缺全仓测试被 block | **pass**（blockers 0） | —（pass 轨省略） | `crctl approve --stage dev-start`（humanApproval=true） | `independent-run/P/` |

每案 6 项证据（`independent-run/{U,S,P}/`）：`reviewer-run.log`（未截断原始会话日志，128838 / 142506 / 50021 bytes）、
`canonical/`（`dev-plan.yml`、`review-loop.yml`、`traceability.yml`、`cr.md` 四份只读副本）、`crctl-next.txt`、
`fixture-head.txt`、`fixture-status.txt`、`MANIFEST.txt`（逐文件 sha256 清单，三个 MANIFEST 均
`canonical_dev_plan_present=True`、`reviewer_run_log_present=True`，无 `MISSING:` 行）。

## 2. 三案 canonical 事实（可核）

| 项 | U（CR-2026-901） | S（CR-2026-902） | P（CR-2026-903） |
|---|---|---|---|
| `verdict` | block | block | pass |
| `blockers` | 1 条：FR-1/AC-1 关键证据被设为全仓 `cmd-01`（`make test`），plan §2/§3/§5 与 TASK-01 完成标志引入未批准的全仓门槛 | 1 条：AC-1/AC-2（FR-1/FR-2）声称全量通过而 `cmd-01`/`cmd-02` 各只跑一个定向用例（子集冒充全量） | `[]`；`acceptance-verifiability: pass` 明确「不触发 CR-2026-073 FR-7 的 blocker」 |
| `repair-target` | `write-dev-plan` | `write-dev-plan` | 省略（pass 轨） |
| `subject-sha256` | `64cc536dd0ab6dc6…` | `2ab660f153bd5b32…` | `c733264659bb7d65…` |
| `reviewed-at` / reviewer | 2026-09-30T19:11:55+08:00 / OldBoy405 | 2026-09-30T19:07:24+08:00 / OldBoy405 | 2026-09-30T19:05:00+08:00 / OldBoy405 |
| `review-loop` attempt | 1 | 1 | 1 |
| reviewer-model（自报） | `Gobao/deepseek-flash（pi runner，reasoning=max）` | `Gobao/deepseek-flash (pi coding agent; local run without Multica task context)` | `Gobao/deepseek-flash（pi runner，reasoning=max）` |
| 夹具 HEAD（`fixture-head.txt`） | `ff5dea8b5c9e0b7b…` | `428b9f68ce7f38bb…` | `54da209548804ef1…` |

**独立复核（dev-agent，只读）**：用版本化夹具 `fixtures/variants/{U,S,P}/{plan.md,TASK-01.md}` +
`fixtures/build-output.json#generatedAt` 按 `crctl` 的 dev-plan composite digest 口径（plan.md + `tasks/TASK-*.md`，LF 规范化后
`sha256(JSON.stringify(entries))`）**重算** `subject-sha256`，三案与 canonical 记录**逐一相等**（U/S/P 全中）——
即 verdict 绑定到本仓库现存夹具内容，而不是无法复现的宿主状态。三案 `canonical/` 四件副本的 sha256 亦与各自 `MANIFEST.txt` 逐条相等。

## 3. 残余偏离（须由 reviewer 裁定，不隐藏）

plan §5 的证据入口含「对应 issue reviewer 评论」。在**零平台副作用**前提下（Ray 的 B-C1 裁决内容之一）
本地 run 没有平台身份、不产出 Multica 评论，本目录以 `reviewer-run.log`（reviewer 自己的原始报告）
替代该形态，`collect-evidence.ps1` 的 `MANIFEST.txt` 记录其 sha256 供核对；如需评论形态，可由人把三案 verdict 摘要
作为**人发评论**贴到 AIFI-38（该写入是人的动作，不涉及 CR 行或 `MULTICA_CR_WORKSPACES`）。
`test-report.md` §5 按此如实标注，未声称该形态偏离已闭合。

## 4. 夹具与被评版本（可核）

| 事实 | 入口 |
|---|---|
| 三个 develop Skill 的文字合同（受评版本） | `tools` 仓 `ab01e2b8`：`skills/develop/write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-dev-plan/SKILL.md` |
| `crctl`（受评版本） | `tools` 仓 `ab01e2b8`：`skills/shared/crctl/scripts/crctl.mjs` |
| 合同级断言（只证明合同，不证明 verdict） | `test-evidence/cmd-06.log`、`cmd-07.log`、`cmd-08.log` |
| U/S/P 快照夹具（三案共用同一 SDD/AC，只换 plan/TASK 证据范围） | `fixtures/`（`shared/`、`variants/{U,S,P}/`、`build-snapshots.mjs`；构建输出 `fixtures/build-output.json`，快照 SHA U `0bf7acb0`/S `01b01d14`/P `310cb266`，其后经合法 crctl 流程推进到 `task-breakdown` 得到上表夹具 HEAD） |
| 夹具可评审状态与路由链路的机制自检 | `MECHANISM.md`、`fixtures/verify-mechanism.log` |
| 人去执行的最小入口 + 必须原样保留的证据清单 | `independent-run/README.md`、`independent-run/prompts/`、`independent-run/collect-evidence.ps1` |

> 不得拿本 CR 自身的 plan 评审当作 U/S 案例（plan §5 明确禁止）。也不得以 `cmd-06`/`cmd-07` 的绿色代替这些 verdict。

## 5. 历史说明（为什么曾经登记为「未闭合」）

平台委派的 reviewer run 会在 `review-dev-plan` Step 3.0 的 `multica cr bind-current-task {cr_id}` 处技术中止：
绑定要求平台侧已存在该 CR 的投影行 `cr(workspace_id, cr_id)`（`server/internal/service/task.go#LockCrForCrBind` →
`CR_NOT_FOUND`/404 零写入），而隔离夹具 CR 没有投影行；两条已排除路径（A 平台可见测试 CR、C 修订验收合同）
与代价逐条见 `MECHANISM.md` §3。故本项按 Ray 的 B-C1 选 2 转为**人在本机以无 task context 的本地 run 执行**，
Agent 不创建、不代跑；2026-09-30 人侧执行完毕，证据见 §1/§2。
