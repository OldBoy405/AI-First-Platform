---
id: CR-2026-075-effective-version-rerun
type: EVIDENCE
cr-ref: CR-2026-075
source-task: CR-2026-075-TASK-10
target-version: 0.48
updated: 2026-10-06T04:54:42.127Z
---

# FR-15 / AC-B14 生效版本复跑结论（`cmd-08` / `cmd-09` / `cmd-10`）

**判据**（TASK-10 卡验收 4）：三条命令全绿 → 记「实际生效版本一致（覆盖规划/竞品调用方）」；任一红 → 逐条记录目标与两侧 sha256 并报告缺失前置，不标 `pending-deploy` 充作通过、不表述为已生效。

## 1. 本轮复跑（2026-10-06，全部经 plan §6.2 原样 argv / cwd / timeout）

| 证据ID | repo | cwd | exit | 关键计数 | 原始输出 |
|---|---|---|---|---|---|
| `cmd-08` | multica | `.` | ✅ 0 | tests 19 / pass 19 / fail 0 | `cmd-08.txt` |
| `cmd-09` | multica | `.` | ✅ 0 | deployment-copy 4 + imported-skill 14 + agent-in-sync 4；末行 `cmd-09 ok` | `cmd-09.txt` |
| `cmd-10` | tools | `.` | ✅ 0 | skill-in-sync 14（expected 30 文件）+ agent-in-sync 2 + out-of-scope-drift 1（R8 单列）；末行 `cmd-10 ok` | `cmd-10.txt` |

## 2. 与 TASK-09 台账的逐值比对（本文件生成时机器断言，任一不等即硬失败）

台账 = `test-evidence/effective-version.md` §4（人类执行记录）+ §3 C′（30 个 EXPECT 文件的同步后 sha256）。

| # | 目标 | 台账 §4 sha256（同步后） | 本轮 `cmd-09`/`cmd-10` 实测 | 一致 |
|---|---|---|---|---|
| 1 | requirement-writer | `9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08` | `9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08` | ✅ |
| 2 | dev-agent | `4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218` | `4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218` | ✅ |
| 3 | quality-reviewer-agent | `daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c` | `daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c` | ✅ |
| 4 | cr-coordinator-agent | `b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3` | `b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3` | ✅ |
| 5 | product-planning-agent | `317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb` | `317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb` | ✅ |
| 6 | competitive-analyst-agent | `d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366` | `d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366` | ✅ |
| 7 | 14 个 imported Skill / 30 个文件（复合值口径：30 行 `<relPath>:<sha256(LF 正文)>` 升序、LF 连接、末尾 LF） | `c0a1b015ff755698bb973a6379556d426a3114f5e8ed4886a8901dd01c288d45` | `c0a1b015ff755698bb973a6379556d426a3114f5e8ed4886a8901dd01c288d45`（本轮平台现值重算；逐文件 30 项与台账 §3 C′ 逐项相等） | ✅ |

- 逐文件比对：台账 §3 C′ 的 30 项与本轮从平台现值重算的 30 项**逐项相等**（`30 / 30`），且每一项与 tools CR worktree 的仓库目标 LF 全等（`live == target` 逐项断言通过）。
- 四份 CR Agent：本轮 `cmd-09`（`agent-in-sync`）与台账 §4 #1–#4 同值。两个业务调用方 Agent：本轮 `cmd-10`（`agent-in-sync`）与台账 §4 #5–#6 同值。
- `cmd-10` 的 `out-of-scope-drift` 1 行 = R8 范围外既有漂移 4 项（`skills/shared/crctl/scripts/test/{fault-harness,merge-fixture,register-tx,test-cr}.test.mjs`），单列、不计入本 CR 通过判定，也不以现存线上子集声称 AC-B14 一致。

## 3. 结论

**实际生效版本一致（覆盖规划/竞品调用方）**：`cmd-08` 19/19 绿、`cmd-09` exit 0（部署副本收敛 + 14 个 imported Skill 取用路径台账 + 四份 CR Agent 线上 instructions 逐字一致）、`cmd-10` exit 0（本 CR 声明发布集 30 项线上存在且与仓库目标逐字一致 + 规划/竞品两个业务调用方 Agent 一致）；三条命令的每一处取值与 TASK-09 台账（§4 逐目标 sha256 / §3 C′ 逐文件 sha256）**逐值相等**（本文件第 2 节的断言在生成时全部通过，无一处需要人工判定）。

边界：

- 本结论**不覆盖** FR-04 段③（其取证载体 = `caller-replay/` 归档 + `write-test-report` 机器区 + `review-code` 逐条人工核对），也不覆盖 `cmd-11` 的聚合门禁面。
- 本轮 `cmd-11` 为红（`SUITE_FAILURES_UNREGISTERED`，4 例在 `crctl-summary.test.mjs`；基线 `061a12f` 同集复现），**不属 AC-B14 判据集**，但其红项已在 `uncovered-risks.md` R17 如实登记，不得被隐藏或以范围缩小冒充绿。
- 本 TASK **不做平台侧写入**：AC-B14 的平台写权限唯一在人类 owner（台账 §4 已记录 owner Ray 于 2026-10-06 12:27–12:29 +08:00 执行）；本文件只复跑只读比对。
