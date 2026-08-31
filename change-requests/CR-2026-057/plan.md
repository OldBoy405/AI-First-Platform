---
id: CR-2026-057-plan
type: PLAN
cr-ref: CR-2026-057
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
status: draft
created: 2026-08-31T22:00:00+08:00
updated: 2026-08-31T22:00:00+08:00
---

# 1. 交付里程碑

输入：已审批 PRD（FR-1～FR-17 / NFR-1～NFR-6 / AC-1～AC-18）与已审批 SDD（tech-design attempt 3/3 PASS，批准范围见 SDD §9）。全部实施改动落在 sibling `../tools/` 仓（tools CR worktree）；knowledge-base 只承载本 CR 过程文档与账本；`../multica/` 零改动（PRD §7 范围排除）。本 CR 自身 `target-version: unassigned`（P1-1：人工确定、禁止 tbd、不自动推导），plan/TASK 继承 cr.md 值。

| 里程碑 | 交付内容 | 预计工时 | 退出条件 |
|---|---|---:|---|
| M1 设计冻结 | PRD / SDD / 批准范围（SDD §9）+ tech-design 人工审批 | 0（已发生） | status=tech-design-reviewed；`crctl next`=write-dev-plan |
| M2 计划与任务拆分 | 本 plan.md + TASK-01～TASK-11 + `tasks/_index.yml`（crctl task init）+ 状态推进至 task-breakdown | 0.5 人天 | 覆盖矩阵无空 owner；`crctl next` 指向 review-dev-plan |
| M3 crctl 执行器实现 | TASK-01～TASK-05：版本规范化基元、register 硬校验、writeback 版本守卫、version-set 子命令、`crctl test` 机器区 `skipped` | 46h | 各 TASK 验收条件全过；cmd-02～cmd-05 绿 |
| M4 Skill / 模板 / 文档修订 | TASK-06～TASK-10：四个 review SKILL、五个写作/注册 SKILL、SDD-template、README、ARCHITECTURE.md 一句 | 29h | contract-scan 零命中；lint-prompts 通过；文本夹具核对通过 |
| M5 全量回归与测试报告 | TASK-11：cmd-01～cmd-06 全量运行、test-report.md 落盘、证据与矩阵 cmd-NN 全等 | 9h | cmd-01～06 exit 0 且关键测试 skipped=false；基线红计数不增加 |
| M6 评审与人工审批 | review-dev-plan → approve-dev-start → review-code → approve-code | 流程节点 | 评审 blocker 清零后经人工审批 |
| M7 发布 | merge / writeback / archive | 流程控制节点 | 按状态机既有流程 |

预计总工时：**84h**（TASK-01～TASK-11 合计，1 人天 = 8h，约 10.5 人天）。M3 与 M4 可并行；M5 为收敛点；M6/M7 为流程节点，不建交付 TASK（FR-10）。

# 2. 任务依赖图

```text
TASK-01 版本规范化基元（normalizeTargetVersion / readCrMdTargetVersion）
  ├──> TASK-02 register 硬校验（FR-12）
  ├──> TASK-03 writeback 版本守卫（FR-14）
  ├──> TASK-04 version-set 子命令（FR-15）
  └──> TASK-05 crctl test 机器区 skipped（FR-16）
TASK-06 review-requirement / review-tech-design 契约修订（FR-1～4）
TASK-07 review-dev-plan / review-code / implement-code 契约修订（FR-1～4、FR-7、FR-9、FR-11、FR-16 评审侧）
TASK-08 requirement-register / write-requirement-prd / write-tech-design（FR-13、FR-5/FR-6）
TASK-09 write-dev-plan / write-dev-tasks / write-test-report（FR-8、FR-10、FR-13、FR-16 侧）
TASK-10 SDD-template / README（FR-5、NFR-6）
  以上全部 ──> TASK-11 全量回归、契约扫描与测试报告（AC-18、AC-4、AC-17）
```

TASK-02～TASK-05 依赖 TASK-01（消费规范化纯函数）；TASK-06～TASK-10 相互独立、可与 M3 并行；TASK-11 依赖 TASK-02～TASK-10 全部（全量回归 + 测试报告为收敛点）。跨任务接口签名见各 TASK「接口契约」节，TASK-11 汇总核对签名一致性。

实施资源（`crctl workspace inspect` 返回，实施期以输出为准不重拼路径）：

- knowledge-base：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-057`，承载 plan/tasks/test-report/账本。
- tools：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-057`，承载全部代码/Skill/模板/测试改动。**实施基线 HEAD = `8c0a6db61cca900ff67fd064089c819c4a98acef`**（= SDD §10 记录点 `7ddeeb7` + 1 commit `[cr] promote delivery-agent to feature-writeback pipeline owner`，该 commit 只动 agent 矩阵/agents/delivery-agent.md，不影响 §10 依赖结论；SDD §10 符号行号以 7ddeeb7 记录，实施期以工作区实际文件为准核对）。
- multica：无实施改动（PRD §7 范围排除，workspace inspect 已 healthy）。

# 3. 资源与分工

| 角色 | 工作内容 | 预计工时 |
|---|---|---:|
| 开发（owners.development=Ray） | TASK-01～TASK-10 全部实现与测试落地 | 75h |
| 测试（owners.test=Ray） | TASK-11 全量回归、test-report.md、证据对齐 | 9h |
| 评审 | review-dev-plan / review-code 由 quality-reviewer-agent 执行（另行委派） | — |
| 人工审批 | approve-dev-start / approve-code 由 Ray 在交互式终端执行 | — |

TASK 工时明细：TASK-01 6h / TASK-02 8h / TASK-03 10h / TASK-04 14h / TASK-05 8h / TASK-06 6h / TASK-07 8h / TASK-08 5h / TASK-09 6h / TASK-10 4h / TASK-11 9h = **84h**。任务完成即时在 `tasks/_index.yml` 标 done（AGENTS.md 纪律 #8），不积压。

# 4. 风险与回滚策略

| 风险 | 影响 | 应对与回滚 |
|---|---|---|
| R1 既有夹具适配遗漏（SDD §6.1 五项） | AC-18 红 | TASK-02～TASK-05 各自含夹具适配项；适配清单先行于新向量（§6.1 顺序） |
| R2 version-set 中断重试时序错位（B-SDD-005） | 重试误报 `VERSION_SET_WORKTREE_DIRTY`/`DERIVED_DRIFT` 死循环 | 严格按 §4.4 步骤 1→11 顺序实现；故障注入向量（既有 `tx-apply-between-rename` 注入点，FAULT_POINTS 零新增）先行验证恢复闭环 |
| R3 FR-3 前缀文本泄漏禁止串 | AC-4 红 | TASK-06/07 新文本避开 `fixed-blockers`/`repair-instructions`/`suggestion_policy`/`suggestion-policy` 四串；TASK-11 跑 contract-scan 复核 |
| R4 版本继承分叉（Skill 残留「或 tbd」措辞） | AC-13/AC-12 语义回退 | TASK-08/09 删除 `或 tbd` 与 `?? 'tbd'`；本 plan/TASK frontmatter 均写 `unassigned`；TASK-11 静态 grep 复核 |
| R5 覆盖矩阵 cmd-NN 与 test plan 命令漂移 | FR-16 稳定关联失效 | 命令集 §5.1 六条固定顺序即权威；TASK-11 核对机器区 commands 下标与矩阵全等 |
| R6 流程控制被建成交付 TASK | AC-10 blocker | 本 CR 无 merge/writeback/archive 交付 TASK；TASK-11 完成边界 = test-report.md 落盘（developing 内可登记事件） |
| R7 基线既有红（实施前核实于 8c0a6db） | AC-18「既有用例不失败」口径 | 见 §5.3：两条基线红与本 CR 改动面无关，作为「既有失败」携带（不新增红）；修复建议入 follow_up |
| R8 既有断言文本约束 | TASK-08/09 改 Skill 文本时误触既有静态断言 | TASK-08/09 验收条件内置文本约束（见 TASK 卡「验收条件」） |

回滚策略：全部实施改动在 tools CR worktree 分支 `requirement/CR-2026-057`，逐 TASK 单 commit（`[cr] ` 前缀）；局部回滚 = revert 对应 TASK commit，整体回滚 = 分支重置到 `8c0a6db`。knowledge-base 侧仅文档/账本（plan/tasks/test-report），账本写入全部经 crctl。无 feature-flag：改动随分支合并生效，不回滚部署面。

# 5. 验收与发布策略

## 5.1 测试命令集（cmd-NN 稳定关联，实施期固定顺序，与覆盖矩阵全等）

cwd = tools CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-057`）；`shell:false` 经 `crctl test` 执行。NN = 机器区 `commands` 列表 1-based 下标，与 `test-evidence/cmd-NN.log` 文件名全等（FR-16）。

| cmd-NN | 命令 | 覆盖 |
|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 既有 crctl 用例 + `normalizeTargetVersion` 单测值域表 + `task done` 非 developing 回归（AC-10 侧） |
| cmd-02 | `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` | register 事务 + FR-12 正负向量（AC-12 唯一证据） |
| cmd-03 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | writeback 事务 + FR-14 守卫向量（AC-14 唯一证据） |
| cmd-04 | `node --test skills/shared/crctl/scripts/test/version-set.test.mjs` | FR-15 version-set 正负向量 + 中断重试闭环（AC-15 唯一证据，含 AC-13 全链同步断言） |
| cmd-05 | `node --test skills/shared/crctl/scripts/test/test-cr.test.mjs` | FR-16 skipped 模式表向量 + test-cr 夹具适配回归（AC-16 自动化侧唯一证据） |
| cmd-06 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/register-tx.test.mjs skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/archive-tx.test.mjs skills/shared/crctl/scripts/test/test-cr.test.mjs skills/shared/crctl/scripts/test/version-set.test.mjs` | AC-18 全量回归（crctl.test.mjs 及既有 writeback/archive/register/test-cr 相关测试） |

关键测试定义（FR-16）：cmd-02～cmd-06 是覆盖矩阵中关键 AC 的唯一验收证据。若机器区 `skipped: true`，review-code 按 FR-16 处理（不得仅凭 exit 0 视为已验证；唯一证据被 skip → blocker，repair-target=implement-code）。cmd-01 不是任何关键 AC 的唯一证据。

## 5.2 发布前 checklist

1. 覆盖矩阵（§6）每条关键 AC 有唯一 TASK owner 与唯一 `cmd-NN`；全部 AC 行可追溯至 TASK。
2. cmd-01～cmd-06 全部 exit 0；关键测试（cmd-02～06）`skipped: false`。
3. `contract-scan.test.mjs` 对 3 Pipeline + 11 SKILL 零命中（AC-4）。
4. 本 CR diff 无 P1-3 举例中除 FR-12/14/15/16 以外的新 validator（AC-17）。
5. 冻结面（§7.2）零改动；`gates.json` / `pipeline-templates/` / 状态机零 diff。
6. 本 CR 过程文档（cr.md/PRD/SDD/PLAN/TASK）frontmatter `target-version` 全等 `unassigned`（AC-13 静态侧）。
7. 无流程控制交付 TASK（FR-10 自检）。

## 5.3 基线既有红说明（R7）

实施前于基线 `8c0a6db` 核实，AC-18 相关文件存在 **2 条既有失败**（非本 CR 引入，主仓 trunk 同红）：

1. `crctl.test.mjs`「CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引」——`pipeline-templates/code-implementation.pipeline.json` 文本不含 `crctl task init`（CR-2026-050 converge 改写所致，与本 CR 的 pipeline-templates 零改动约束冲突，修复需另开 CR）。
2. `archive-tx.test.mjs`「TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记」——补记重放时出现 `EMIT_FAILED` warning（archive dedup 重放路径既有缺陷，本 CR 不触 archive）。

AC-18 退出口径：本 CR 引入用例全绿；**红计数不因本 CR 增加**；上述 2 条按「既有失败」记录于 test-report.md 并附根因，修复建议入 follow_up（SDD §9 follow_up 同类）。

## 5.4 估算总工时

**84h**（TASK-01～TASK-11 `estimate` 之和，与 `crctl task init` 返回的 `totalEstimateHours` 一致；FR-23 交叉校验基准）。

# 6. AC/业务闭环覆盖矩阵（FR-8 必填）

## 6.1 关键 AC（唯一 TASK owner + 唯一 cmd-NN 证据）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-12 register 版本校验正负向量与零写入 | §3.1 / §4.2 / §6.2 | CR-2026-057-TASK-02 | cmd-02 |
| AC-14 writeback 版本守卫时序与六项零观察点 | §3.2 / §4.3 / §6.2 | CR-2026-057-TASK-03 | cmd-03 |
| AC-15 version-set 全链同步 / 幂等 / 漂移拒绝 / 中断重试闭环 | §3.3 / §4.4 / §6.2 | CR-2026-057-TASK-04 | cmd-04 |
| AC-16（自动化侧）skipped 字段计算与模式表 | §3.4 / §4.5 / §6.2 | CR-2026-057-TASK-05 | cmd-05 |
| AC-18 全量回归绿（新用例通过、既有用例不新增失败） | §6.1 / §6.2 | CR-2026-057-TASK-11 | cmd-06 |

## 6.2 非关键 AC 与业务闭环（可合并行，须可追溯至 TASK）

| AC/业务闭环 | SDD 落点 | TASK 追溯 | 验收证据 |
|---|---|---|---|
| AC-1 四节点首轮同轮双缺口 | FR-1 / §4.6 / §6.2 夹具 | TASK-06、TASK-07 | 评审执行证据（`review-annotations/*.yml`；本 CR review-dev-plan / review-code 轮按新契约运行，requirement / tech-design 两节点夹具随 TASK-06 落盘后按需复评验证） |
| AC-2 blocker/suggestion 分级 | FR-2 / §4.6 | TASK-06、TASK-07 | 同上（措辞入 suggestions、验收不可达入 blockers 夹具） |
| AC-3 回修机械核对（FR-3 前缀） | FR-3 / §2.6 / §4.6 | TASK-06、TASK-07 | 同上（修 1 留 1 + 范围外夹具；payload 无禁止字段） |
| AC-4 禁止字段零命中 | FR-4 / §6.2 | TASK-06、TASK-07（TASK-11 复核） | contract-scan.test.mjs 零命中 |
| AC-5 批准范围固定章节 | FR-5 / §2.5 / §3.6 | TASK-10（模板）、TASK-08（write-tech-design 契约） | SDD-template.md diff + 本 CR sdd.md §9（已含四字段） |
| AC-6 follow_up 做成 TASK → blocker（双轨） | FR-7 / §4.6 | TASK-07 | 本 CR review-dev-plan 轮按路由表判定（夹具由评审方构造） |
| AC-7 先核对批准范围 + zero_diff 越界 | FR-7 / §4.6 | TASK-07 | 本 CR review-code 轮：diff 触碰 zero_diff → blocker 且 repair-target=implement-code |
| AC-8 plan 含覆盖矩阵 | FR-8 / §3.6 | TASK-09 + 本 plan §6 | 本 plan.md §6 静态存在 |
| AC-9 删 owner → verdict=block | FR-9 / §4.6 | TASK-07 | 本 plan 删 owner 夹具 → review-dev-plan block 且 `crctl next` 不指向 approve-dev-start |
| AC-10 流程控制 TASK 禁止 | FR-10 / FR-11 / §4.6 | TASK-09、TASK-07 | 本 CR 无流程控制交付 TASK（静态）+ `crctl task done` 非 developing 回归（cmd-01 既有断言，不放宽） |
| AC-11 deliveryIndexComplete 不变 | §6.1 item 5 | TASK-11（零改动核对） | gates.json 零 diff + archive 门禁既有测试不新增失败 |
| AC-13 版本继承全链 | FR-13 / §3.1～§3.3 | TASK-08、TASK-09（frontmatter 继承）、TASK-04（全链同步） | 本 CR 过程文档 frontmatter 全等 `unassigned`（静态）+ cmd-04 全链同步断言 |
| AC-16（评审行为侧）skipped → blocker + 「未执行」 | FR-16 / §3.4 / §4.6 | TASK-07 | 本 CR review-code 轮证据（review-annotations/code.yml） |
| AC-17 无未触发新 validator | FR-17 / §6.2 | TASK-11 | 代码评审 diff 审阅（不落 P1-3 举例其余项） |

## 6.3 AC-1～AC-4 四节点参数化矩阵（PRD §5，TASK-06/TASK-07 对齐实现）

| 节点 | 首轮闭合夹具（AC-1） | 分级夹具（AC-2） | 回修夹具（AC-3） |
|---|---|---|---|
| `review-requirement` | 含 HTTP 或 CLI 契约、同一契约域至少两个独立缺口的 PRD | 一条纯措辞问题 + 一条验收不可达 | 上一轮 2 条 blocker 修 1 留 1，另造一条范围外 |
| `review-tech-design` | 含调用者闭包缺口的 SDD（例如缺错误码与缺锁序） | 同上两类 | 同上结构 |
| `review-dev-plan` | 覆盖矩阵同时缺某一关键 AC 的 TASK owner 与缺另一关键 AC 的 `cmd-NN` | 同上两类 | 同上结构 |
| `review-code` | 实际 diff 同时缺一条关键失败路径处理、且触碰一处 `zero_diff` | 同上两类 | 同上结构；block 的 `repair-target` 必须为 `implement-code` |

# 7. 冻结面与自检清单

## 7.1 本 CR 自定规则对齐（coordinator 约束 + PRD）

- **P0-1 一次性完整闭包**：三条 CLI 契约（register / writeback-apply / version-set）各自在本 CR 一次完整实现——错误码、幂等、零写入、负向向量全覆盖（TASK-02/03/04），不分批暴露；`skipped` 模式表冻结一次落地（TASK-05）。
- **FR-3 固定句式**：本 CR 后续各评审轮（review-dev-plan / review-code）的 report/评论一律使用 `已解决：` / `部分解决：` / `未解决：` / `本轮新增：` / `范围外：` 前缀，可机械核对；payload 与 SKILL 正文不含被删 canonical 字段。
- **B-001 不新增状态/转换**：状态机保持 15 具名状态 + 注册前 `(new)`、28 声明 / 50 展开；`version-set` 不改变 CR status（SDD §4.4）。
- **三条 CLI 契约按 SDD 落点执行**：version-set 可恢复优先路径按 B-SDD-005 定稿时序（允许状态校验 → 恢复 → tracked-clean → 漂移检查）；writeback 守卫时序 §4.3（先于 replay/resolve/prepare/journal，守卫值回灌）；FR-16 cmd-NN 证据关联（§5.1/§6.1）。
- **P1-1 版本继承**：本 plan 与全部 TASK frontmatter `target-version: unassigned`，与 cr.md/PRD/SDD 全等；实施期禁止写入 `tbd` 或自行改写。

## 7.2 冻结面（zero_diff，改动即违反本 CR 自身规则）

1. `dir-graph.yaml#change-request-track.state_machine`（tools 与 knowledge-base 均不改）。
2. `skills/shared/crctl/gates.json`（含 `deliveryIndexComplete`）。
3. `crctl task done` 合法状态集（仍仅 `developing`）。
4. `REVIEW_REPAIR_TARGETS` 常量（`code → implement-code`）与 `review-record` schema 必填字段集、attempt 账本。
5. `skills/shared/crctl/scripts/lib/durable-tx.mjs`、`lib/yaml-subset.mjs`。
6. `pipeline-templates/` 三条 CR Pipeline（含 reviewLoop 结构）。
7. `skills/shared/controlled-shell/rules.json` `protectedPaths.deny`。
8. `contract-scan.test.mjs` 的 FORBIDDEN 清单（不增删扫描项）。

## 7.3 FR-10 自检

本 CR 的交付 TASK（TASK-01～TASK-11）不含 merge / writeback / archive /「完成于 merge 的发布准备」；所有 TASK 完成边界均为 developing 内可被 `crctl task done` 登记的事件（实现落盘、测试命令绿、test-report.md 落盘）。merge/writeback/archive 的审计事实以 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准，不进 TASK ledger。
