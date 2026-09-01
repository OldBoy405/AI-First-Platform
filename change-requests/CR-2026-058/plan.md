---
id: CR-2026-058-plan
type: PLAN
cr-ref: CR-2026-058
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
status: draft
created: 2026-09-01T16:50:00+08:00
updated: 2026-09-01T17:15:00+08:00
---

# 1. 交付里程碑

输入：已审批 PRD（US×4 / FR×6 / AC×6，target-version=`0.30`）与已审批 SDD（tech-design attempt 3/3 PASS）。全部实施改动落在 sibling `../tools/` 仓；`../multica/` 零改动；knowledge-base 只承载本 CR 文档与账本。

| 里程碑 | 交付内容 | 预计工时 | 退出条件 |
|---|---|---:|---|
| M1 守卫与回灌计划 | TASK-01：`resolveWritebackAuthorityPath` 窄只读解析器 + `guardWritebackVersion` 判定表重写（FR-1/FR-3）+ guard 单测向量；TASK-02：`planVersionRefill`（同源绑定 + backlog 预检四错误码 + cr.md 语义复核）+ 两个行级编辑纯函数（FR-2.1）+ plan 单测向量 | 22h | crctl.test.mjs 新增向量绿、既有用例除 BR-1 外绿（§5.3）；tools worktree HEAD=`2bb66294` 基线核对完成 |
| M2 事务集成 | TASK-03：`applyWritebackAtomic` 最小插入（authority 快照绑定复用 `WRITEBACK_STATE_MISMATCH`、`payload.versionRefill` 冻结持久化、entries 合成、baseline cr.md 单条目合成、恢复协议五现场）（FR-2/FR-2.2/FR-6） | 14h | §4.4 插入点清单逐项存在；zero_diff 面零改动；writeback-tx.test.mjs 既有 14 用例仍绿 |
| M3 测试与文案 | TASK-04：`merge-fixture.mjs` 参数化 + `writeback-tx.test.mjs` 改写与新增（AC-1/AC-2/AC-3/AC-6 全夹具，含 direct tasks/traceability 回灌与 1b 部分 apply 冻结回归）；TASK-05：`crctl.test.mjs` 同源断言向量 + AC-4 静态核对（依赖 TASK-04 的 writeback-tx 改写事实，B-DP-02）；TASK-06：README 行 22/行 76 改写 + 静态文案断言（FR-5） | 22h | cmd-02 全绿；cmd-01 全绿（含 README 禁止串零命中断言）；writeback-tx 的 UNASSIGNED 期望仅存在于 AC-1.2/AC-1.3 冻结负向向量（正反语义向量证明，B-DP-03） |
| M4 全量回归与测试报告 | TASK-07：cmd-01～cmd-03 全量运行（`crctl test` 证据由 testCr 原子发布到 KB CR worktree `change-requests/CR-2026-058/test-evidence/cmd-NN.log`，B-DP-04）、`write-test-report` 落盘 test-report.md、覆盖矩阵 cmd-NN 与机器区 commands 下标全等核对 | 5h | 机器区 status=pass（三命令 exit 0 且 skipped=false，§5.3 例外表逐条核对）；test-report.md 存在且证据映射完整 |
| M5 评审与人工审批 | review-dev-plan → approve-dev-start → review-code → approve-code | 流程节点 | 评审 blocker 清零后经人工审批 |

预计总工时：**63h**（TASK-01～TASK-07 合计，1 人天 = 8h，约 7.9 人天）。M1→M2→M3→M4 为主链；TASK-06 与 M1/M2 无代码依赖（只动 README），但 crctl.test.mjs 与 TASK-05 共用文件，串行落盘避免冲突；M5 为流程节点，不建交付 TASK（FR-10）。

# 2. 任务依赖图

```text
TASK-01 窄解析器 + guard 判定表重写（FR-1/FR-3，含 guard 向量）
  ├──> TASK-02 planVersionRefill + 行级编辑（FR-2.1，含 plan 向量）
  │        └──> TASK-03 applyWritebackAtomic 集成（FR-2/FR-2.2/FR-6）
  │               └──> TASK-04 merge-fixture 参数化 + writeback-tx 改写与新增（FR-4）
  │                      ├──> TASK-05 crctl.test.mjs 同源断言 + AC-4 静态核对（B-DP-02：依赖 TASK-04 的 writeback-tx 改写事实）
  │                      │        └──> TASK-06 README 行 22/76 + 静态文案断言（FR-5）
  │                      └──> TASK-07 全量回归与测试报告（cmd-01～cmd-03，依赖 TASK-01～06 全部）
```

TASK-02 依赖 TASK-01（消费 guard 的 authority 快照语义与规范化 value 约定）；TASK-03 依赖 TASK-01（`versionGuard.authority/refill`）与 TASK-02（`refillPlan`）；TASK-04 依赖 TASK-03（集成夹具需要完整接线）；**TASK-05 依赖 TASK-02（向量针对 `planVersionRefill` 签名与 `WRITEBACK_STATE_MISMATCH` 复用位）与 TASK-04（AC-4 静态核对以 writeback-tx.test.mjs 改写后的 UNASSIGNED 冻结向量为对象，B-DP-02）**；TASK-06 依赖 TASK-05（crctl.test.mjs 同文件串行）；TASK-07 依赖 TASK-01～TASK-06 全部。跨任务接口签名见各 TASK「接口契约」节，TASK-07 汇总核对签名一致性。

实施资源（`crctl workspace inspect` 返回，实施期以输出为准不重拼路径）：

- knowledge-base：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-058`，承载 plan/tasks/test-report/账本。
- tools：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-058`，承载全部代码与测试改动。**实施基线 HEAD = `2bb66294db30b116e0d53aea48990611017c75d6`**（= CR-2026-057 merge 提交，branch=`requirement/CR-2026-058`；SDD §6.3 七项证据已在该 HEAD 重核）。
- multica：无实施改动（PRD §7 范围排除，workspace inspect 已 healthy）。

# 3. 资源与分工

| 角色 | 工作内容 | 预计工时 |
|---|---|---:|
| 开发（owners.development=Ray） | TASK-01～TASK-06 全部实现与测试落地 | 58h |
| 测试（owners.test=Ray） | TASK-07 全量回归、test-report.md、证据对齐 | 5h |
| 评审 | review-dev-plan / review-code 由 quality-reviewer-agent 执行（另行委派） | — |
| 人工审批 | approve-dev-start / approve-code 由 Ray 在交互式终端执行 | — |

TASK 工时明细：TASK-01 10h / TASK-02 12h / TASK-03 14h / TASK-04 14h / TASK-05 5h / TASK-06 3h / TASK-07 5h = **63h**。任务完成即时在 `tasks/_index.yml` 标 done（AGENTS.md 纪律 #8），不积压。

# 4. 风险与回滚策略

| 风险 | 影响 | 应对与回滚 |
|---|---|---|
| R1 恢复协议部分 apply 现场构造不可达（SDD §6.2 AC-2.3） | AC-2.3.1b 红 | 按 SDD 可达性说明：direct 夹具 + `CRCTL_FAULT_POINT=tx-apply-between-rename`（既有登记点，零新增）→ manifest=prepared；夹具把 txws `_backlog.yml` 置为 `payload.versionRefill.backlog.afterText` 构造 rename 间现场；merged（status=merging）夹具明确不作 direct 夹具 |
| R2 payload 冻结规则漏实现（found 重试重算覆写） | B-SDD-01 回归红 | TASK-03 严格按 §4.4 第 9 步五现场（manifest 缺失 / prepared / complete / refill=false / 防御）实现；AC-2.3.1b 夹具断言 payload 保持首次落盘值；恢复期重算仅纯读 fail-fast |
| R3 基线红 BR-1/BR-2 被误判为本 CR 引入 | AC-4 误报 | §5.3 例外表逐条登记（与 CR-2026-057 计划同两条，已在基线 `2bb66294` 逐条实测确认）；cmd-01/cmd-03 用 `--test-skip-pattern` 排除，skip-pattern 字面量含用例全名 |
| R4 zero_diff 越界（crctl.mjs / durable-tx.mjs / yaml-subset.mjs / FAULT_POINTS / 状态机 / gates） | SDD §9 zero_diff 违反 | TASK-03 验收含 diff 核对（零改动清单逐项 `git diff --name-only`）；TASK-04 不改 fault-point 名；review-code 按 AC-7 拦截 |
| R5 错误码越界（第三个新码） | B-SDD-04 契约扩大 | TASK-02/03 只用 PRD FR-2.1 允许的两个新码（`WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`）；同源绑定硬失败复用既有 `WRITEBACK_STATE_MISMATCH`；TASK-05 静态核对错误码清单 |
| R6 README 改写漏「唯一更正入口」writeback 事务限定 | AC-5 红 | TASK-06 按 SDD §4.7 原文改写行 22/行 76；静态断言覆盖禁止串零命中与限定行文 |
| R7 行尾/跨行解析纪律（回灌读写） | NFR-3 违反 | TASK-02 行级编辑纯函数先 `\r\n→\n`；替换未命中硬失败（`WRITEBACK_VERSION_INVALID` / `ENTRY_NOT_IN_BACKLOG`），禁止静默返回原文；TASK-04 向量覆盖 |

回滚策略：全部实施改动在 tools CR worktree 分支 `requirement/CR-2026-058`，逐 TASK 单 commit（`[cr] ` 前缀）；局部回滚 = revert 对应 TASK commit，整体回滚 = 分支重置到 `2bb66294`。knowledge-base 侧仅文档/账本（plan/tasks/test-report），账本写入全部经 crctl。无 feature-flag：改动随分支合并生效，不回滚部署面；回灌是 writeback-apply 既有子命令内部行为，不新增 CLI 面。

# 5. 验收与发布策略

## 5.1 测试命令集（cmd-NN 稳定关联，实施期固定顺序，与覆盖矩阵全等）

cwd = tools CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-058`）；`shell:false` 经 `crctl test` 执行。NN = 机器区 `commands` 列表 1-based 下标，与证据文件名 `cmd-NN.log` 全等（FR-16）。**证据落点（B-DP-04）**：`crctl test` 的 testCr（HEAD=`2bb66294` 既有实现）把 `cmd-NN.log` 原子发布到 **knowledge-base CR worktree** 的 `change-requests/CR-2026-058/test-evidence/cmd-NN.log`（`logRel = change-requests/${cr}/test-evidence/cmd-${NN}.log` 写入 `authorityWorkspace` = 本 CR KB worktree，随测试记录 journal/write-set 同一 commit 落盘；tools worktree 不产生 test-evidence 目录）。统一 `--test-reporter=dot`（spec reporter 摘要恒含 `skipped` 字样会误命中 FR-16 模式 4 把命令误标 skipped；dot reporter 仅点字符，五条冻结模式零命中——CR-2026-057 计划 §5.1 已逐条实测）。

| cmd-NN | 命令 | 覆盖 |
|---|---|---|
| cmd-01 | `node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs` | guard 判定表/authority 快照/source 条件向量（FR-1/FR-3，AC-4 单测侧）+ planVersionRefill 语义复核/同源断言/错误码向量（FR-2.1）+ README 静态文案断言（AC-5）+ 既有 crctl 用例回归；BR-1 除外（§5.3） |
| cmd-02 | `node --test --test-reporter=dot skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | writeback 事务 + 回灌正向/冲突/故障点/FR-3 分叉/CLI 信封夹具（AC-1/AC-2/AC-3/AC-6 唯一证据）+ 既有 writeback 回归 |
| cmd-03 | `node --test --test-reporter=dot --test-skip-pattern "(CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引|TASK-01 RED-7：预存确定性 dedup 文件)" skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/archive-tx.test.mjs skills/shared/crctl/scripts/test/register-tx.test.mjs skills/shared/crctl/scripts/test/version-set.test.mjs skills/shared/crctl/scripts/test/test-cr.test.mjs` | NFR-1 全量回归：writeback / archive / register / version-set / test-cr 既有用例不新增失败（AC-4 回归侧）；BR-1/BR-2 除外（§5.3） |

关键测试定义（FR-16）：cmd-02 是 AC-1/AC-2/AC-3/AC-6 的唯一验收证据；cmd-01 是 AC-4/AC-5 的唯一验收证据。若机器区 `skipped: true`，review-code 按 FR-16 处理（不得仅凭 exit 0 视为已验证；唯一证据被 skip → blocker，repair-target=implement-code）。cmd-03 不是任何关键 AC 的唯一证据。

## 5.2 发布前 checklist

1. 覆盖矩阵（§6.1）每条关键 AC 有唯一 TASK owner 与唯一 `cmd-NN`；全部 AC 行可追溯至 TASK。
2. 机器区 status=pass：cmd-01～cmd-03 全部 exit 0 且 `skipped: false`；例外表与 skip-pattern 字面量逐条全等（§5.3）。
3. 错误码清单静态核对：本 CR 新增码仅 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 两个；`WRITEBACK_AUTHORITY_DRIFT` 零残留（B-SDD-04）。
4. zero_diff 面零改动：`crctl.mjs`（cmdWritebackApply/flag 面/callbacks）、`fail()`/`ok()`/`runTxAsync`、`resolveOperationalWorkspace` 签名与抛错契约、`durable-tx.mjs` 全部导出与 `FAULT_POINTS`、`lib/yaml-subset.mjs` 全部导出、writeback 三个 generator 脚本、`guardWritebackVersion` 调用签名、`statusTransition` 既有字段、`verifyReleaseSubjects` 白名单（SDD §9）。
5. 冻结面零改动：`dir-graph.yaml#change-request-track.state_machine`、`gates.json`、`pipeline-templates/`、`controlled-shell/rules.json`。
6. 本 CR 过程文档（cr.md/PRD/SDD/PLAN/TASK）frontmatter `target-version` 全等 `0.30`。
7. 无流程控制交付 TASK（FR-10 自检）：TASK-01～TASK-07 完成边界均为 developing 内可被 `crctl task done` 登记的事件。
8. `_context.md` 于实施期各 run 收尾覆写并独立提交（`[cr] update context`）。

## 5.3 基线红例外登记表与判定规则（R3）

实施前于基线 `2bb66294` 逐条实测确认 **2 条既有失败**（与 CR-2026-057 计划 §5.3 同两条；tools 主仓 trunk 同红，非本 CR 引入）。根因修复不纳入本 CR（SDD §9 follow_up 同类）；按以下机制作为**明确允许、必须逐条登记**的基线红例外携带。

| BR-ID | 所在命令 | 测试文件 | 用例全名 | skip-pattern 字面量 | 基线证据（2bb66294 实测） |
|---|---|---|---|---|---|
| BR-1 | cmd-01 / cmd-03 | `skills/shared/crctl/scripts/test/crctl.test.mjs` | CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引 | `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引` | exit 1；断言 `expected: /crctl task init/` 不命中——`pipeline-templates/code-implementation.pipeline.json` 文本不含 `crctl task init`（CR-2026-050 converge 改写，与本 CR pipeline-templates 零改动约束冲突，修复需另开 CR） |
| BR-2 | cmd-03 | `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖 | `TASK-01 RED-7：预存确定性 dedup 文件` | exit 1；归档 dedup 补记断言与既有实现不符（基线红，根因修复入后续 CR，本 CR 不触碰 archive 路径） |

判定规则：① 机器区 `skipped` 按 FR-16 冻结模式表扫描；dot reporter 下五条模式零命中，`skipped` 恒 false。② skip-pattern 字面量必须包含该用例全名；JSON 侧为独立 args 元素（shell:false，不经 shell，无引号转义）。③ 红计数不增加：本 CR 不引入任何新失败用例；若实施期出现新的非 BR 失败，一律按 reviewLoop 回修闭环处理，不得扩例外表。

# 6. AC/业务闭环覆盖矩阵（FR-8 必填）

## 6.1 关键 AC（唯一 TASK owner + 唯一 cmd-NN 证据）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 FR-1 判定表六行向量（merged 夹具 authority=txws；放行/UNASSIGNED/MISMATCH/INVALID/全等） | §2.1 / §4.2 / §6.2 | CR-2026-058-TASK-04 | cmd-02 |
| AC-2 回灌原子性（2.1 成功回灌 + 2.2 backlog 冲突五向量 + 2.3 三故障点与 1b 部分 apply 冻结回归） | §2.2/§2.3/§2.4 / §4.3/§4.4/§4.6 / §6.2 | CR-2026-058-TASK-04 | cmd-02 |
| AC-3 worktree 与 txws 版本分裂（FR-3：txws 为准只回灌 txws；code-approved 上 MISMATCH 优先） | §4.1 / §4.4 第 5.5 步 / §6.2 | CR-2026-058-TASK-04 | cmd-02 |
| AC-4 测试改写与回归（writeback-tx 的 UNASSIGNED 期望仅存在于 AC-1.2/AC-1.3 冻结负向向量——正反语义向量证明，B-DP-03；crctl.test.mjs 含 FR-1 表正负向量与 plan/同源向量——planVersionRefill 等 export 测试 seam，B-DP-01；`node --test` 通过） | §6.2 AC-4 | CR-2026-058-TASK-05 | cmd-01 |
| AC-5 人读文案（README 与守卫文案与 FR-1 一致；禁止串零命中） | §4.7 / §6.2 AC-5 | CR-2026-058-TASK-06 | cmd-01 |
| AC-6 CLI 信封（exit 0 `phase=complete`/`changed`/`files` 含两账本/`recoverCommand`；失败 exit 1 扁平 error） | §3.1/§3.2 / §6.2 AC-6 | CR-2026-058-TASK-04 | cmd-02 |

## 6.2 非关键 AC 与业务闭环（可合并行，须可追溯至 TASK）

| AC/业务闭环 | SDD 落点 | TASK 追溯 | 验收证据 |
|---|---|---|---|
| US-1 回写执行者：unassigned CR 传真实版本可完成 writeback | §1.3 关键流程 | TASK-03、TASK-04 | cmd-02（AC-1.1 放行向量） |
| US-2 平台维护者：回灌只碰 cr.md/_backlog，冻结产物不动 | §1.3 / §4.3 | TASK-02、TASK-04 | cmd-02（AC-2.1 冻结产物哈希全等断言） |
| US-3 版本事实消费者：读取/回灌与 authority 一致 | §4.1 / §4.4 第 5.5 步 | TASK-01、TASK-03 | cmd-02（AC-3 分叉夹具） |
| US-4 回归守护者：正负向量进两个测试文件 | §6.2 AC-4 | TASK-04、TASK-05 | cmd-01、cmd-02 |
| NFR-1 既有 writeback/archive/register/version-set 回归不新增失败 | §6.2 / §7 | TASK-07 | cmd-03 |
| NFR-6 冻结快照：回灌后 `verifyReleaseSubjects` 按既有白名单通过 | §1.3 / §7 | TASK-03、TASK-04 | cmd-02（AC-2.1 全量回归侧）+ cmd-03 |
| FR-2.2 故障边界三故障点语义（无新注入点） | §2.4 / §4.6 | TASK-03、TASK-04 | cmd-02（AC-2.3） |
| 错误码契约：仅两个新码；authority 绑定复用 `WRITEBACK_STATE_MISMATCH` | §3.2 / §9 | TASK-02、TASK-03、TASK-05 | cmd-01（同源断言向量）+ 静态核对（§5.2 第 3 条） |
| zero_diff 面零改动 | §9 | TASK-03 | `git diff --name-only` 核对（§5.2 第 4 条） |
| 行尾纪律：`\r\n→\n` 与替换未命中硬失败 | §4.3 / NFR-3 | TASK-02 | cmd-01（plan 向量含 INVALID/ENTRY 码）+ 代码评审核对 |
