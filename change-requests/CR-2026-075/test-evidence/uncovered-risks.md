---
id: CR-2026-075-uncovered-risks
type: EVIDENCE
cr-ref: CR-2026-075
source-task: CR-2026-075-TASK-10
target-version: 0.48
updated: 2026-10-06T04:56:00.000+00:00
---

# CR-2026-075 未覆盖风险清单与观测面边界

**口径**：逐条写明「观测面 < 声称面」的边界；本文件**只登记边界、复跑结论与不覆盖项**，不产出新的 pass/fail 结论，不代替 `test-report`。文中「本轮实测」= 2026-10-06 本轮 `cmd-01`～`cmd-11`（原始输出见 `test-evidence/cmd-NN.txt`，命令记录见 `command-records.md`）；文中标注为**诊断探针**的两条命令（R10、R12 取证）不属 `plan.md` §6.2 证据命令集，不新增证据 ID、不计入本 CR 通过判定。

| 项 | 内容 | 观测面 | 声称面上限（不得声称） | 本轮结论 |
|---|---|---|---|---|
| **R10** | multica `./internal/daemon/` 包内 `TestRegisterTaskReposAllowsProjectOnlyURL` 在本机 Windows 因临时仓路径超 MAX_PATH 失败，与实现无关 | 诊断探针（本轮实测）：`go test ./internal/daemon/ -count=1 -run TestRegisterTaskReposAllowsProjectOnlyURL` → exit 1，原文：`--- FAIL: TestRegisterTaskReposAllowsProjectOnlyURL (5.11s)` / `daemon_test.go:4716: expected repo to be cached after registerTaskRepos, but Lookup returned empty`，前置日志 `fatal: cannot stat '…/hooks/applypatch-msg.sample': Filename too long: exit status 128` | `cmd-07` 是**定向 `-run` 名集**，故不得被读作 `./internal/daemon/` 包全量通过；本 CR 证据面不含该用例 | 与实现无关（Windows 路径长度），不回滚 |
| **R11** | `delegation-contract.test.mjs` 在本轮基线即红（上游 `steered` 漂移），被误当本 CR 引入或反向绕过 | 本轮实测 `cmd-08`：`tests 19 / pass 19 / fail 0`（原始输出见 `cmd-08.txt`） | 该结论只覆盖「合同正文 + 四份提示词 + `bak/` 维护副本的枚举对齐」这一监督面，不得读作 CR Agent 全部行为已验证 | 已由 TASK-09 的文本收敛（成功集合补 `steered`）闭合，本轮转绿 |
| **R12** | `engineering-docs` 的 `chain.test.ts` 2 例 trunk 自带失败被误当本 CR 回归，或被反向绕过而掩盖真缺陷 | 本轮实测 `cmd-06`：vitest 定向文件集 `2 passed (2) / 21 passed (21)`，观测面 = 本 CR 声明的 `src/__tests__/{generators,validators}.test.ts`；诊断探针（本轮实测，同包）：`node node_modules/vitest/vitest.mjs run src/__tests__/chain.test.ts` → `Tests 2 failed | 1 passed (3)`，原文：`× chain-check > PRD 为 draft 时创建 SDD 应被拒`、`× chain-check > SDD 缺少上游 PRD 应报错`，均 `AssertionError: expected true to be false // Object.is equality`；零改动判据：`git diff --stat 061a12f..HEAD -- …/src/validators/chain.ts …/src/__tests__/chain.test.ts` 为空、`git log 061a12f..HEAD --` 两文件为空 | `cmd-06` 不得被读作该 TS 包全量绿，更不得读作 tools 仓全量；被排除的 `chain.test.ts` 2 例（基线 `061a12f` 同样 2 failed，见 `plan.md` §4 R12）**不在本 CR 的观测面内** | 缺陷本体**不由本 CR 修**（要改 SDD §9 `scope_in` 外的文件 = 批准范围扩张），另开独立 CR 跟踪；本 CR 任何产物不得表述为已处理 |
| **R13** | FR-04 机器语义（S1/M2 = 有效绑定 + 显式传入不可用 `--workspace`）依赖 `bindTaskWorkspace` 的「显式不可用不归一」既有分支；该分支漂移会使 M2 消失、有效绑定下 `WORKSPACE_REQUIRED` 不可达 | 本轮实测 `cmd-01`（`crctl.test.mjs`）：`pass 247 / fail 0`，其中段①补验用例 `CR-2026-075 TASK-08 FR-04 段①` 断言 M2 三例（空串 / 纯空白 / 裸旗标）→ `WORKSPACE_REQUIRED` + stdout 空、M1 同根别名一次成功、M4 异根 `WORKSPACE_CONTEXT_MISMATCH` + 零业务写入 | 该用例钉住的是**机器语义**，不得被读作 FR-04 段③（实际调用方节点回放）已验证 | 未发现漂移（分支与本 CR SDD §9 `zero_diff` 声明一致）；若后续发现漂移，须逐字记录并回到 SDD 正式修订，**不得**在本 CR 内顺手改该分支 |
| **R14** | FR-04 三段验收面被**分层冒充**：用段①②的绿冒充段③已验收 / 用段③归档冒充 CLI 机器语义已钉住 / 把已撤销的 FU-1 口径当作现行批准范围 | 三段各自的载体见下节；`cmd-01`（段①）、`cmd-05`（段②）、`test-evidence/caller-replay/`（段③）互不替代 | 任一段不得以另一段的绿冒充；三段缺一即 FR-04 不通过 | 段③归档经本 TASK 核对（存在 + 字段逐项可核对，见 `command-records.md` 末节），未以 `cmd-01`/`cmd-05` 绿冒充 |
| **R17**（本轮新发现；编号取 R17：`plan.md` §4 现有风险行为 R10～R15，§1 正文另有一处对「R16」的引用但无对应行） | `cmd-11` 聚合门禁本轮 **红**：`verdict=block` / `check_failed=SUITE_FAILURES_UNREGISTERED`，4 例失败全在 `crctl-summary.test.mjs`（`summary-03`～`summary-06`） | 本轮实测 `cmd-11`：`files_executed 28 / cases_executed 693 / failures 4`；**基线复现**：`git archive 061a12f skills/shared/crctl` 抽出基线副本到干净目录独立复跑 `crctl-summary.test.mjs` → `tests 8 / pass 4 / fail 4`，失败用例集与本轮 HEAD 完全同集（`summary-03`～`summary-06`）；根因：该测试用 `os.tmpdir()` 造夹具并以 `--workspace <tmp>` 驱动 CLI，而任务环境已注入 `CRCTL_OPERATIONAL_WORKSPACE`（CR-2026-072 TASK-03 / CR-2026-075 TASK-02 的绑定发布）→ 显式异根被 `WORKSPACE_CONTEXT_MISMATCH` 拒绝、stdout 为空 → `SyntaxError: Unexpected end of JSON input` | `cmd-11` 是 tools `skills/shared/crctl/scripts/test/` **测试文件集合**（28 文件）的逐文件子进程门禁，不得被读作多仓全量；其红项**不得**被读作 CR-2026-075 引入的回归（基线同集复现）；也**不得**被读作已修复或已登记例外（`gate-registry.json#exceptions` 项数 = 0） | 本 TASK 只记录、不在 TASK-10 内修实现（TASK-10 卡明文）；修与不修、以及是否阻塞代码审批，属 `review-code` / 人工审批的判定面。本 CR 的声明文件集**不含** `crctl-summary.test.mjs` |

## FR-04 段③ 边界（`cmd-01`～`cmd-11` 不覆盖）

- `cmd-01`～`cmd-11` **不覆盖** FR-04 段③（实际受控调用方节点的节点日志/回放）：FR-04 的机器面 = `cmd-01` 段①（有效绑定场景）、合同面 = `cmd-05` 段②（调用方合同逐条文本断言）；**段③不由任何 `cmd-NN` 断言**。
- 段③的取证载体 = `test-evidence/caller-replay/records.json` + `{A,B}.node-record.json`（由 `CR-2026-075-TASK-08` 生产并归档，本 TASK 只核对存在与字段可核对，未重跑、未改写）+ `write-test-report` 机器区 + `review-code` 逐条人工核对。
- `cmd-01`～`cmd-11` 全绿**不得被读作段③已验证**；段③缺失或归档字段不可核对即 **FR-04 不通过**（R14 的防误读边界同此）。本轮段③归档字段核对结论见 `command-records.md` 末节。
- 本轮 `cmd-11` 为红（R17），故不存在「十一条全绿」这一表述可用；该红项不改变段③的取证载体与判定口径。

## §5.2 中不由本 CR `cmd-*` 机器断言的边界

- **B4 保留项（FR-14 收敛时不得误删的内容）**：属**人工检查边界**——观测面 = `review-code` 逐条人工核对收敛前后的保留项集合（业务参数、阶段说明、职责/产出、发布合同、bootstrap 显式根示例、「不构成授权来源」清单），不由 `cmd-NN` 断言；`cmd-05` 的 `caller-14`/`caller-15` 只覆盖调用方合同侧的五项前置、恰一次纠正与六条负面清单文本，不覆盖全部保留项。
- **S2/M3（无绑定声明下缺根报 `WORKSPACE_REQUIRED`）**：只作**字面来源登记**——该场景在本 CR 的节点执行环境内不产生（本节点自身处于绑定环境），其机器行为由 **A6 向量**（`cmd-01`，`CR-2026-075 A6` 用例）覆盖，**不得**表述为本 CR 节点内已回放。
- **`cmd-11` 的范围**：只写 tools `skills/shared/crctl/scripts/test/` 测试文件集合（磁盘集合 ≡ `manifest.files`），不把定向运行或该集合表述为多仓全量。

## FR-15 / AC-B14 的复跑结论

见同目录 `effective-version-rerun.md`（`cmd-08`/`cmd-09`/`cmd-10` 与本 CR TASK-09 台账逐值一致时记「实际生效版本一致（覆盖规划/竞品调用方）」）。该判定与 R17 的 `cmd-11` 红项**互不影响**：`cmd-11` 不在 AC-B14 的判据集内，但其红项不得被隐藏。

## 与 `plan.md` §4 风险表的对应

R10、R11、R12、R13、R14 逐条对应 `plan.md` §4 同名风险行；本 TASK 的补充是**复跑结论**与 R17。R15（plan 与 TASK 卡的 FU-1 口径回写面）属 `write-dev-tasks`/plan 内部一致性问题，不是证据面边界，不在本清单的判定范围。
