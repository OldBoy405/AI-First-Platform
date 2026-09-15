---
id: CR-2026-067-prd
type: PRD
cr-ref: CR-2026-067
title: CR-P1：评审输入结构与回修闭合
target-version: 0.40
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-15T07:36:00+08:00
updated: 2026-09-15T07:36:00+08:00
---

# 1. 概述

## 1.1 问题陈述

需求来源是 Issue AIFI-29 附件《AIFI-18_SDD到planTASK_原位修订方案.md》（33,478 B，附件 id `01a0a23f-47e4-7663-ab33-b749cc4ff22c`）第 5 节「CR-P1：评审输入结构与回修闭合」（KB 内同文路径 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`）。该节钉出三类**结构性**问题，它们都不是「评审不认真」，而是**合同本身让漂移不可判定**：

1. **既有实现事实被定义两次、且没有稳定标识**：`write-tech-design` 的 Step 2.6 既有实现证据段要求「必须逐项附证据」，紧随其后的 `### 既有实现依赖与事实` 小节又维护一份编号清单；SDD 正文可以、也事实上被允许**重新陈述**「当前代码已经如何工作」。正文与依赖表因此是两份可漂移的事实副本，而每条事实只有**位置序号**（`1.` `2.` `3.`）作为身份——正文增删一条即整体漂移，评审无法用一个稳定 key 交叉核对「正文这条断言对应表里哪条」。
2. **两侧强制性不一致、判据不可判定**：写侧 `commit SHA` 是**必填**（Step 2.6「必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`」），评审侧却写作「每项固定包含 `repo`、`relative path`、`stable symbol/对象` 和"依赖结论"，**并可附** `commit SHA`」（§1.4 事实 4）——同一份合同对同一条事实给出两种强度，作者按写侧写、评审按评侧放宽，闭合无从机械判定。同时评侧判据是「正文同类事实**是否漏列**」这一**集合比较**，缺一条可判定的关系式（「正文引用的 `dep-N` 必须已定义」）。
3. **回修只修被点名的一格，批准范围四字段缺自洽判据**：`write-tech-design` 现有唯一一句回修约束是「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案」（§1.4 事实 2），没有任何「状态链必须整体重证」的要求——AIFI-18 实测中 stop handler、running、空 ID 顺序、失败回流被**拆成多轮**修补，正是该形态（来源 §5.3）。与之并列，`批准范围` 四字段（`scope_in`/`scope_out`/`zero_diff`/`follow_up`）只有「章节与字段必须存在、空字段须写 `无`/`N/A`」的存在性判据，没有自洽判据：`scope_in` 与 `zero_diff` 可能对同一对象同时要求「改」与「不改」、外部治理强制修改可能被藏进 `scope_out`、当前 AC 的必要条件可能被塞进 `follow_up`——这些冲突到 dev-plan 阶段才由 upstream 轨触发，返工代价被推迟放大（来源 §5.4）。

**根因结论（来源 §5，本 PRD 采纳）**：三项的共同根因是**事实与判据都缺一个可判定的承载体**——事实缺稳定标识（`dep-N`）、判据缺两侧同口径的关系式（引用必须已定义 + `commit SHA` 两侧共同必填）、回修与范围缺「什么算闭合」的判据（状态链整体重证 + 范围四字段自洽）。因此本 CR 的三条杠杆全部是**原位把既有 Step 2.x 判据与 SDD 写作合同收紧**，不新增任何结构性载体。

## 1.2 解决方案摘要

按来源 §5.1–§5.5 逐条落地（每组都锚定「仓 + 文件 + 既有段落」，见 §1.3.1 与 §3 各 FR）：

1. **既有实现事实唯一表达**（FR-1）：`write-tech-design` 的 `### 既有实现依赖与事实` 小节原位改为 `dep-N` 固定结构（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论` 五字段，`commit SHA` 为必填 40 位 SHA）；实现事实**只在该表定义一次**，SDD 正文只能写「设计依赖 `dep-N`」、不得重述「当前代码已经如何工作」；无法绑定字段的引用按待核实依赖列出且不得继续作为方案前提；`N/A` 仅在正文与依赖表均无既有实现依赖时可用。
2. **评审侧同口径收口**（FR-2）：`review-tech-design` 的 **Step 2.1** 原位修订——reviewer 核验依赖表五要素；**正文只能引用存在的 `dep-N`**；正文出现未通过 `dep-N` 引用承载的当前实现事实 → blocker；把「**并可附** `commit SHA`」改为与写侧同口径的**必填**。修订只在既有 Step 2.1 内进行，**不重编号任何 Step**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用）。
3. **首轮全量检查保持原样**（FR-3）：`review-tech-design#Step 2.2` 的既有「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束」句**零改动**，只在验收时核对仍存在；**不**在 `tools/agents/quality-reviewer-agent.md` 新建小节或复制第二份判据（来源 §5.2 已删除「`#评审判断` 小节」这一不存在的锚点）。
4. **状态链整体重证**（FR-4）：`write-tech-design` 的既有回修模式句**原位扩写**——blocker 触及状态判定、活动性、事件顺序、空值或失败回流时，必须重证该状态链的完整输入维度、分支、可见动作与对应 AC；不得只修被点名的一格；同一标识符/锚点/testid 全文只有一个裁决；未受该根因影响的已确认方案不得重写（「整体重证」与「不扩散」两个方向同时约束）。
5. **批准范围四字段自洽**（FR-5）：`write-tech-design` 的「批准范围」四字段说明与 `review-tech-design` 的「批准范围前置」段**两侧原位加入同一组判据**——`scope_in` 与 `zero_diff` 不得对同一对象自相矛盾；外部治理规则强制修改时必须在 SDD 阶段纳入 `scope_in`、修订 `zero_diff` 或给出已有合法出口；不得用 `scope_out` 隐藏必须发生的治理修改；`follow_up` 不得承载当前 AC 的必要条件。评侧发现冲突**必须在 SDD 阶段形成 blocker**，不留到 dev-plan 再触发 upstream。
6. **同 CR 测试断言与门禁基线同步**（FR-6）：`pipeline-structure.test.mjs` 的 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例内的两组 term **原位改写**为 `dep-N` 口径（不另写第二个反向用例、用例数不减少），`gate-registry.json#manifest.cases` 与实际顶层用例数同步，`suite-gate --run` 全量绿且**不签任何新例外**。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

收紧 SDD 既有实现事实的表达与评审闭合：写侧把既有实现事实收敛为带稳定 `dep-N` 的唯一依赖表（`commit SHA` 必填），正文只引用不重述；reviewer 侧 `commit SHA` 同为必填并核验 `dep-N` 引用；状态链类 blocker 必须整体重证、批准范围四字段判据在写手与评审两侧一致。同 CR 原位同步 `pipeline-structure.test.mjs` 的 CR-2026-055 依赖清单用例与 `gate-registry.json` 用例数，不新增 annotation dimension、账本字段、评审指标或 Pipeline 节点。

### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> CR-P1 只原位改 review SKILL 既有 Step 2.x 与 SDD/plan 写作合同，不重编号、不碰 crctl 事务层、不新增 annotation dimension / 账本字段 / 评审指标 / Pipeline 节点；`dep-N` 为写侧与评审侧统一语义，`commit SHA` 两侧同为必填。

（该句来自来源 §2 的 CR-P1 边界段；其中「plan 写作合同」的落地归 CR-P2（来源 §6 CR-P2 / `write-dev-plan`、`write-dev-tasks`、`review-dev-plan`），本 CR 的写作合同面 = **SDD 写作合同**，见 FR-7 第 5 条。）

逐条落到「哪个仓的哪个文件、改哪一段」（基线行号与证据见 §1.4）：

| # | 仓 | 文件 | 修订类型（原位） |
|---|---|---|---|
| 1 | `../tools` | `skills/develop/write-tech-design/SKILL.md` | Step 2.6 既有实现证据段的依赖形态改 `dep-N` + 正文只引用；`### 既有实现依赖与事实` 小节固定结构改 `dep-N`；回修模式句扩写状态链整体重证；Step 2 第 9 节「批准范围」加四字段自洽判据 |
| 2 | `../tools` | `skills/develop/review-tech-design/SKILL.md` | Step 2.1 existing dependency 核验段：五要素核验 + 正文只能引用存在的 `dep-N` + 未承载事实成 blocker + `commit SHA` 由「并可附」改必填；Step 2「批准范围前置」段加同一组自洽判据 |
| 3 | `../tools` | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例内两组 term 原位改写为 `dep-N` 口径（不新增反向用例） |
| 4 | `../tools` | `skills/shared/crctl/scripts/test/gate-registry.json` | `manifest.cases["pipeline-structure.test.mjs"]` 与实际顶层用例数同步（条件性，见 FR-6 第 2 条与 §1.5 第 2 条） |

**本 CR 明确零 diff 的面**（评审核对清单）：四个 review SKILL 中除 `review-tech-design` 外的三个；`tools/agents/quality-reviewer-agent.md`；`skills/develop/review-tech-design/SKILL.md` 的 Step 1.0 / Step 2.2 / Step 2.3 / Step 3 / Step 4 / Step 5 / Step 6；`write-tech-design/SKILL.md` 的 Step 1 / Step 2.5 / Step 3 / Step 4 / Step 5；`skills/shared/crctl/scripts/{crctl.mjs,lib/**}`；`pipeline-templates/**`；`agent-skill-matrix.yml`；`skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan}/SKILL.md`。

### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（两个 develop SKILL + 既有测试与门禁登记）。
- knowledge-base 承载本 PRD 与来源文档；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- `../multica/` 本 CR **零 diff**（本 CR 不改任何 Agent Prompt 部署副本、不改 Go/TS 代码）。
- `target-version` 继承 `cr.md` 的 `0.40`（注册阶段确定，`crctl version-set` 之外无改写入口）；`target-spec-id` = `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

### 1.3.3 契约说明（确定性四查适用面）

本 CR **不新增、不修改任何用户可调用契约**，四查（幂等 / 权限 / 错误闭包 / 副作用）对本 CR **N/A**，理由逐条：

- **无 HTTP API**：本 CR 不改任何 endpoint / request / response。
- **无 CLI（crctl）契约变更**：`skills/shared/crctl/scripts/**` 除既有测试文件外零 diff——不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码、调用者约束（不碰事务层，见 FR-7）。
- **无 Skill 契约变更**：`write-tech-design` / `review-tech-design` 的**必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界全部不变**（§1.4 事实 18）。本 CR 改的是两份 SKILL **正文内的 Prompt 判据**：依赖表的表达形态（`dep-N`）、正文引用规则、回修判据、批准范围自洽判据、以及一处强制性口径（`commit SHA` 由评侧可选改必填）。这些是**评审与写作合同**，不是调用契约；它们的验收以「文本合同 + 既有测试断言」形式给出（AC-1~AC-9）。
- **唯一强度变化的说明**：评侧 `commit SHA` 由「并可附」改为必填，会让原本可通过的 SDD 在**新口径**下成为 blocker。该变化不改变任何 crctl 状态转换或错误码，只改变 `review-tech-design` 的 blocker 判定输入；对既有已归档 CR 无追溯效力（评审判据只对评审发生时的 SKILL 版本生效）。

## 1.4 当前事实（落笔前核实）

基线（`crctl register` ensure 的 requirement worktree HEAD）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `0a3253403a2d377a5329db5bb9269fe00e239f17`（register 提交） |
| `../multica` | `5c1880f2125e73733b1a5bfc7501db310ab7f584` |
| `../tools` | `7094e492822594b971699924478ba27ccf612c42`（= tools `main`） |

以下结论均在上述 SHA 上核实（路径相对各自仓根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | 写侧既有实现证据段与依赖小节现状：五要素（含 `commit SHA`）必填、固定结构为**编号列表** `1. repo: …`、排序约束「正文首次出现顺序」、消费口径句 `sdd.explicit_existing_dependencies` | `skills/develop/write-tech-design/SKILL.md` Step 2.6（「必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`」）与紧邻的 `### 既有实现依赖与事实` 小节（```text 1. repo: … relative path: … stable symbol/对象: … commit SHA: <40-character SHA> 依赖结论: … ```） |
| 2 | 写侧当前唯一的回修约束句是「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。」，**无**状态链整体重证要求 | 同文件，`### 既有实现依赖与事实` 小节末（该句位于 SDD-CLOSE 关闭义务段之前） |
| 3 | 写侧「批准范围」现状只要求**存在性与字段完整性**（四字段承载且仅承载四字段；空字段写 `无`/`N/A` 加理由；`approve-tech-design` 后只读；冲突只能经 `review-dev-plan` 双轨回上游）——**无** `scope_in`/`zero_diff` 自洽判据、无「治理强制修改不得藏进 `scope_out`」、无「`follow_up` 不得承载当前 AC 必要条件」 | 同文件 Step 2 章节 9「批准范围（契约必填章节，CR-2026-057 FR-5/FR-6）」全段 |
| 4 | 评侧 `commit SHA` 为**可选**（与写侧必填不一致） | `skills/develop/review-tech-design/SKILL.md` Step 2.1：「每项固定包含 `repo`、`relative path`、`stable symbol/对象` 和"依赖结论"，**并可附** `commit SHA`」 |
| 5 | 评侧已有「不扫描全仓 / 不猜测未写出的依赖」边界与「正文同类事实是否漏列」交叉检查；判据是集合比较，**无**「正文引用的 `dep-N` 必须已定义」这一关系式 | 同文件 Step 2.1 后段（「`sdd.explicit_existing_dependencies` 仅指该清单，不由 reviewer 扫描全仓库或临时猜测；reviewer 还必须交叉检查正文同类事实是否漏列。」） |
| 6 | 首轮全量句**已在库**（CR-2026-055 引入），逐字为「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题，同一轮 blockers 同时包含独立根因。」 | 同文件 Step 2.2 首句 |
| 7 | 评侧「批准范围前置」现状只核对**章节与四字段存在**（缺即 blocker，`本轮新增：`），**无**自洽判据、**无**「冲突必须在 SDD 阶段形成 blocker、不留到 dev-plan upstream」的要求 | 同文件 Step 2 引用块「**批准范围前置（CR-2026-057 FR-5/AC-5）**」 |
| 8 | `quality-reviewer-agent.md` 现有 **7** 个 `##` 小节：角色定位 / 意图与路由 / 独立会话路径（FR-A6）/ 人工决策边界 / 权限事实源 / 发布职责与搭车硬规则（CR-2026-066 FR-1 / FR-7）/ 约束；`## 评审判断` 小节**不存在**，`评审判断` 一词仅出现在 `## 意图与路由` 的一句内 | `tools/agents/quality-reviewer-agent.md`：`grep -n '^##'` 输出 7 行；L24「评审判断写临时 payload，canonical 落盘由 `crctl review-record` 独占」 |
| 9 | 目标用例逐字断言两组 term：写侧 8 项 `['### 既有实现依赖与事实', '正文首次出现顺序', 'repo:', 'relative path:', 'stable symbol/对象:', 'commit SHA:', '依赖结论:', 'sdd.explicit_existing_dependencies']`；评侧 4 项 `['名为"既有实现依赖与事实"的显式小节', '有序清单', 'sdd.explicit_existing_dependencies', '正文同类事实是否漏列']` | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` L616 用例 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` |
| 10 | CR-2026-066 的反向断言只覆盖**四个 review SKILL**（`REVIEW_SKILLS` 常量 L636–641），`write-tech-design` **不在**其中；C 段断言不含 `crctl checkpoint`，D 段断言不含 `push-progress 之后` / `push-progress 之前` / `统一 checkpoint 后` | 同文件 L656 用例（断言 A/B/C/D）与 L636 `REVIEW_SKILLS` 定义 |
| 11 | `write-tech-design/SKILL.md` 现存 **1** 处 `crctl checkpoint`（Step 1 提交口径句「架构审批后由同一批 checkpoint（`crctl checkpoint`）纳入」）；四个 review SKILL 均为 **0** 处 | `grep -c 'crctl checkpoint'`：write-tech-design = 1，四个 review SKILL = 0 且各自四 token 均为 0 |
| 12 | `gate-registry.json#manifest.cases["pipeline-structure.test.mjs"] = 35`，`exceptions: []`；同文件实测**顶层用例 = 36**（TAP `1..36`、`# tests 36`、`# pass 36`、`# fail 0`） | `test/gate-registry.json` 与 `node --test --test-reporter=tap pipeline-structure.test.mjs` 实测输出 |
| 13 | `suite-gate` 的用例数判据是**下限**：`if (f.cases < base) trigger('SUITE_MANIFEST_CASE_DROP')`；`manifest.cases` 只校验「缺基线 / 非正整数」，**不校验实际值大于基线** | `test/suite-gate.mjs` L448–453 与 L123–126 |
| 14 | CI 已是真门禁（Ubuntu + Windows 各跑一遍）：`lint-prompts.mjs --mode enforce` → `check-skill-matrix.mjs` → `check-agents-contract.mjs` → pipeline JSON 结构断言（全模板）→ `suite-gate.mjs --run` → writeback 单测 | `.github/workflows/crctl-ci.yml` 六个 step |
| 15 | `recoverCommand` / `recover_command` 在退役名单里，整树扫描命中即红 | `test/contract-scan.test.mjs` L418 `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']` |
| 16 | 目标用例位置与形态：`pipeline-structure.test.mjs` 顶层用例 `^test(` 共 36 条，其中 CR-2026-055 相关 4 条（L568 / L585 / L602 / L616）、CR-2026-066 相关 1 条（L656）；本 CR 目标用例 = **1 条**，原位改写不改变条数 | 同文件 `grep -c '^test('` = 36 |
| 17 | 评侧 Step 编号现状：Step 1（含 **1.0** clean 前置）、Step 2（含批准范围前置）、Step 2.1、Step 2.2、Step 2.3、Step 3、Step 4、**Step 5**（PASS 发布与对账）、**Step 6**（输出摘要）——Step 5/6 与 Step 1.0 由 CR-2026-066 占用 | `skills/develop/review-tech-design/SKILL.md` 节标题逐条读取 |
| 18 | 两份 SKILL 的参数表、落盘路径、状态转换与写入边界本 CR 不变 | `write-tech-design` 参数 = `cr_id`/`tech_context`/`operational_workspace`/`resources`/`review_feedback`/`self_repair_attempt`，落盘 `change-requests/{cr_id}/sdd.md`，推进 `requirement-approved→tech-designing→tech-design-review-pending`；`review-tech-design` 参数 = `cr_id`/`workspace`/`resources`/`reviewer`/`review_feedback`/`self_repair_attempt`，canonical 落盘 `review-annotations/sdd.yml` + review-loop + traceability（`crctl review-record` 独占） |
| 19 | 串行约束当前成立：CR-2026-063/064/065/066 的 `crctl status` 均为 `archived`；注册前 `change-requests/_backlog.yml` 无在途条目；本次 `crctl register` 返回 `cr_id = CR-2026-067`、`phase = complete`、`targetVersion 0.40`、commit `0a3253403a2d377a5329db5bb9269fe00e239f17`，同一命令幂等重放返回 `changed = false` | `crctl status change-requests/_index.yml` 尾部与 register 两次调用的 JSON 输出 |

## 1.5 对来源文档的事实更正与需人工确认的口径

1. **写侧 `commit SHA` 已经是必填，本 CR 的收口点在评侧（来源 §5.1.1 的措辞会让人以为两侧都要「改成必填」）**：来源 §5.1.1 写「`commit SHA` 在 `dep-N` 中为**必填**，与评审侧口径一致（见 5.1.2）」。实测写侧 Step 2.6 已是「必须逐项附证据：`repo`、`commit SHA`…」，固定结构也已是 `commit SHA: <40-character SHA>`（§1.4 事实 1）；真正不一致的是**评侧**的「并可附 `commit SHA`」（§1.4 事实 4）。本 PRD 的 FR-1/FR-2 按「写侧保持必填并换 `dep-N` 表达、评侧由可选改必填」落笔，两侧终态同为必填——**不改变**来源的目标（两侧同口径），只更正「哪一侧需要收紧」。需人工一并确认。
2. **门禁基线值与实测值的落差（本 PRD 收口裁定，需人工一并确认）**：`gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 登记值 **35**，而该文件实测顶层用例 **36**（§1.4 事实 12、13、16）。`suite-gate` 的判据是 `cases < 登记值` 即红，因此**多出 1 条用例不会触发红灯**——这 1 个用例（CR-2026-066 的 L656 断言）是在 CR-S 登记基线之后追加的。来源 §5.1.1 只要求「保持用例数不减；若用例数发生变化，同 CR 刷新 `manifest.cases`」，而 §5.5 的验收写「`gate-registry.json#manifest.cases` 已同步」。本 PRD 采用**同步口径**：FR-6 第 2 条要求实施后该条目与实际顶层用例数一致（本 CR 原位改写预期不改变用例数，**不新增**用例，故若实施后仍为 36 而登记值仍为 35，则把登记值同步为 36；`suite-gate.mjs` 的判据语义与之无关，**不改**）。该项不改变来源的方案取向。
3. **来源 §5.2 的删除锚点已由本 PRD 独立复核**：`quality-reviewer-agent.md#评审判断` 小节**确实不存在**（§1.4 事实 8），来源「删除原方案中的错误锚点」结论成立；本 CR 因此**零改动**该 Agent Prompt，判据唯一事实源 = `review-tech-design/SKILL.md`。
4. **`dep-N` 的稳定性口径（来源未写明，本 PRD 钉定，需人工一并确认）**：来源只写「每条事实获得稳定 `dep-N`」，未写编号生命周期。本 CR 钉为：**按正文首次出现顺序分配、只增不改、正文增删条目不重编号**（删除的条目留空洞，不复用编号）。若不钉，`dep-N` 只是把「序号漂移」换成另一个编号面，与「稳定标识」的意图相反；同时保留既有「按正文首次出现顺序」的排序约束，使编号顺序与正文顺序一致，评审可按序核对。
5. **反向 token 约束的适用面（避免误删既有文本）**：来源 §2/§5.1.2 要求「四个 review SKILL 的新增文字不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`」。实测这四个 token 在四个 review SKILL 中**已经全为 0**（§1.4 事实 11），该约束对本 CR 是**保持性**约束（新增文字不得重新引入）；而 `write-tech-design/SKILL.md` 现存 1 处 `crctl checkpoint`（提交口径句），它**不在** CR-2026-066 的 `REVIEW_SKILLS` 反向断言面内（§1.4 事实 10），且删除它属于独立的发布口径变更、不在来源 §5 授权面内——本 CR **不删该句**，只保证**本 CR 新增文字**不引入该 token 家族。
6. **评侧 Step 2.3 的「分级」边界对本 CR 的约束**：`review-tech-design` Step 2.3 已明确「不得仅因缺少里程碑、TASK owner、任务拆分、工时、完成标志、`cmd-NN`、cwd/timeout、具体测试文件或完整执行命令而形成 blocker——这些是 PLAN/TASK 粒度」。FR-5 新增的范围自洽判据**不得**把该边界扩大为「范围字段写得不够详细即 blocker」：判据只针对**四字段之间的自相矛盾与必需条件错位**（可判定），不针对详尽程度。
7. **来源 §5.5 的三条验收在语义上重叠**（「两侧 `commit SHA` 同为必填」「正文不再重复定义既有实现事实」「`pipeline-structure.test.mjs` 已原位同步」），本 PRD 把它们拆到 FR-1/FR-2（行为）与 FR-6（证据面）两组 AC，避免同一条不变量在两个 AC 里各自表述成不同强度。

## 1.6 修订记录

- 初稿（2026-09-15）：按来源附件 §5（含 §5.1–§5.5）与注册摘要（`cr.md` summary）起草；基线事实在 §1.4 三个 worktree HEAD 上逐条核实。FR 编号与来源 §5 的小节一一对应（§5.1.1→FR-1、§5.1.2→FR-2、§5.2→FR-3、§5.3→FR-4、§5.4→FR-5、§5.1.1 末段＋§5.5→FR-6、§2 边界→FR-7）；AC-1~AC-8 对应来源 §5.5（未合并判据，只按行为面/证据面分组），**AC-9 为本 PRD 新增**，把来源 §2 的 CR-P1 边界与 §8 的串行约束写成可检查约束。§1.5 记录两处对来源文档的确认（第 1、5 条）、一处删除锚点的复核（第 3 条）与三处本 PRD 钉定的口径（第 2、4、6 条），需在人工审批时一并确认。

# 2. 用户故事

- **US-1 SDD 写手（`write-tech-design` / dev-agent）**：作为写 SDD 的人，我希望既有实现事实**只在一处定义**、每条有稳定 `dep-N`，这样正文只需写「设计依赖 `dep-N`」，回修时不会出现「正文改了、表没改」的第二份事实副本。
- **US-2 SDD 评审者（`review-tech-design` / quality-reviewer-agent）**：作为核对依赖的人，我希望能用一个**稳定 key**（`dep-N`）逐条核对，且两侧对 `commit SHA` 的强制性一致（都必填），这样我不会因为「评侧允许省略 SHA」而把一个写侧严格要求的事实放过去。
- **US-3 提 blocker 的评审者**：作为发现状态链问题的人，我希望回修被要求**整体重证该状态链**（不是只补被点名的那一格），这样同根因问题不会在 stop handler / running / 空 ID / 失败回流之间被拆成多轮修补。
- **US-4 人工审批者（Ray）**：作为批准 SDD 的人，我希望 `批准范围` 四字段在**写侧与评侧使用同一组判据**，`scope_in` 与 `zero_diff` 不会自相矛盾、治理强制修改不会被藏进 `scope_out`、当前 AC 的必要条件不会塞进 `follow_up`，这样我看到的批准范围是自洽的，而不是把冲突推迟到 dev-plan 才暴露。
- **US-5 CR 协调者**：作为路由回修的人，我希望回修与审批范围的问题在 **SDD 阶段**就被评审判据拦下，这样不会出现「dev-plan 阶段才触发 upstream 轨、整轮 plan/TASK 作废」的返工。
- **US-6 维护 tools 的开发者**：作为改 SKILL 的人，我希望既有断言在同一份 diff 内原位同步、`gate-registry.json` 的基线与实际一致、不签任何新例外，这样 CI 不会在中间态变红，也不会留下「测试删了一条没人发现」的静默缺口。
- **US-7 本 CR 的 reviewer**：作为本 CR 的评审者，我希望逐条核对「哪个仓的哪个文件的哪一段被原位改了、哪条断言变了、哪些面必须零 diff」，使得这次收紧不引入第二套判据、不重编号 Step、不新增任何观测负担。

# 3. 功能需求

## FR-1 既有实现事实的唯一表达（`write-tech-design`）〔来源 §5.1.1〕

修订面 = `skills/develop/write-tech-design/SKILL.md` 的 **Step 2.6 既有实现证据段**与紧随其后的 **`### 既有实现依赖与事实` 小节**，两处均**原位修订**（不新增小节、不重排 Step 编号、不改 Step 2.6 的 AC 映射合同）：

1. **覆盖面不缩小**：保留既有的「涉及既有实现（现有仓库、文件路径、稳定符号、配置键、接口/协议、数据库结构、模块行为、调用顺序或责任边界，且是方案成立前置条件）的断言，必须逐项附证据」与五要素清单（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`）；本 CR 不缩小该覆盖面，也不改「核验必须覆盖正文所声称的实际行为，不以『文件或符号存在』代替行为成立」。
2. **稳定标识 `dep-N`**：每条既有实现事实获得稳定标识 `dep-N`（N 为正整数）；编号按**正文首次出现顺序**分配，**只增不改**——正文增删条目不重编号，被删除的条目留下空洞、编号不复用（本 PRD 钉定，见 §1.5 第 4 条）。
3. **固定结构原位改为**（原 `1. repo: …` 编号列表形态退役；小节名 `### 既有实现依赖与事实` 与五个字段名保持不变）：

   ```text
   dep-1
     repo: <repository id>
     relative path: <path from repository root>
     stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>
     commit SHA: <40-character SHA>
     依赖结论: <verified current behavior required by this design>
   ```

4. **实现事实只在该表中定义一次**：SDD 正文**只能**写「设计依赖 `dep-N`」，**不得**在正文重新陈述「当前代码已经如何工作」。这是与 FR-2 第 2~3 条成对的同一条不变量（写侧要求 + 评侧判据），不得只落一侧。
5. **`commit SHA` 必填**：该字段为**必填的 40 位 SHA**（写侧现状已是必填，本 CR 保留并明确 `dep-N` 语境下的必填性），与评侧 FR-2 第 4 条同口径。
6. **待核实依赖**：无法绑定事实字段（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`）的引用按**待核实依赖**列出，且**不得继续作为方案前提**（既有语义保留并强化为「前提资格」约束）。
7. **N/A 的可用条件**：`N/A（本 CR 无既有实现依赖）` **只有在正文与依赖表均无**既有实现依赖时才可用（既有语义保留）。
8. **不改的部分**：Step 2.6 的 AC 逐项映射合同（设计落点 / 可观测结果 / 可达性说明）、AC 反查正文的闭环要求、`sdd.explicit_existing_dependencies` 的消费口径、SDD-CLOSE 关闭义务（CR-2026-060 AC-06）全部不变。

## FR-2 评审侧 `dep-N` 核验与两侧同口径（`review-tech-design`）〔来源 §5.1.2〕

修订面 = `skills/develop/review-tech-design/SKILL.md` 的 **Step 2.1（AC 闭环与既有实现依赖核验）**内的 existing dependency 核验段，**原位修订**：

1. **五要素核验**：reviewer 核验依赖表中每项的 `repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`；取证手段与边界不变——按 `resources` 匹配 `repo`、以受控只读 `crctl git rev-parse HEAD` 取 SHA、核验文件与稳定符号，**不执行** lint/build/test，**不做**全仓库无界扫描，**不猜测**作者未写出的依赖。
2. **正文只能引用存在的 `dep-N`**：正文出现的 `dep-N` 引用必须在依赖表中已定义；引用未定义的编号 = 事实引用无承载，形成 blocker。
3. **未承载的当前实现事实 → blocker**：正文出现**未通过 `dep-N` 引用承载**的当前实现事实时形成 blocker（既有判据「正文存在但未列入依赖清单的同类事实引用形成 blocker」的强化表达：判据从「同类事实是否漏列」的集合比较，升级为「是否由 `dep-N` 引用承载」的关系式）。
4. **`commit SHA` 由可选改为必填**：现基线写作「每项固定包含 `repo`、`relative path`、`stable symbol/对象` 和"依赖结论"，**并可附** `commit SHA`」；本 CR 原位改为与写侧同口径（必填 40 位 SHA；缺失或 SHA 与 `resources` 取证结果不符 → blocker）。旧「并可附」措辞**零残留**。
5. **修订只在 Step 2.1 内**：**不重编号任何 Step**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用，§1.4 事实 17）；本 CR 在 `review-tech-design` 中的新增文字**不得出现** `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（CR-2026-066 反向断言零命中；该约束对本 CR 是保持性约束，见 §1.5 第 5 条）。
6. **诚实边界（明确写出）**：本规则是 **Prompt 合同**，**不宣称** NLP 机械识别全部自由文本事实——「正文事实是否漏列/是否被 `dep-N` 承载」的判定仍是评审判断，不是机械门禁；因此**不得**为它新增 crctl 校验面、lint 规则或 annotation dimension（FR-7）。
7. **不改的部分**：Step 2.1 的 AC 闭环判定伪码（缺少设计落点 / 设计结论与 PRD 契约冲突 / 结果不可观察 / 关键前置条件使 AC 不可达）、「先区分 PRD 的现有实现基线描述与目标契约」要求、Step 2.2 首轮全量句、Step 2.3 分级与前缀、Step 3~Step 6 全部不变。

## FR-3 首轮全量检查保持原样（零改动核对）〔来源 §5.2〕

1. `review-tech-design/SKILL.md#Step 2.2` 的既有句「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题，同一轮 blockers 同时包含独立根因」**逐字保持**（CR-2026-055 引入，§1.4 事实 6）；本 CR 对该句**不做任何修改**，只在验收时核对仍存在（AC-3）。重复写入等于造第二份事实源，违反本方案的原位原则。
2. **不新建 Agent Prompt 小节、不复制第二份判据**：`tools/agents/quality-reviewer-agent.md` **零 diff**——不新增小节（`## 评审判断` 小节不存在，§1.5 第 3 条）、不把首轮全量判据复制进 Agent Prompt；该判据的唯一事实源是 `review-tech-design/SKILL.md`。
3. **来源原方案的三项不做**：不为「首轮漏检」写账本计数；不用 `本轮新增：` 统计流程质量；不对评审轮数作数字承诺。`本轮新增：` 仍只承担 blocker 文本分类（CR-2026-057 FR-3），不承担观测指标。

## FR-4 状态链整体重证（`write-tech-design` 回修模式原位扩写）〔来源 §5.3〕

修订面 = `write-tech-design/SKILL.md` 的现有句「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。」——在该句**原位扩写**（不新增小节、不改 Step 编号、不改 `reviewLoop` 与 `maxAttempts`）：

1. blocker 若触及**状态判定、活动性、事件顺序、空值或失败回流**，必须**重证该状态链的完整输入维度、分支、可见动作与对应 AC**；
2. **不得只修被点名的那一格**；
3. **同一标识符、锚点或 testid 在全文只能有一个裁决**；
4. **未受该根因影响的已确认方案不得重写**（保留既有「不无理由重写已确认方案」的约束）。

扩写后该段必须**同时**表达「整体重证」与「不扩散」两个方向：前者防止只修一格，后者防止借重证之名重写无关设计。该修订直接覆盖 AIFI-18 中 stop handler、running、空 ID 顺序和失败回流被拆成多轮修补的问题形态。本 FR **不新增** blocker 计数、轮数门禁或观测指标。

## FR-5 批准范围四字段自洽（写手与 reviewer 两侧同判据）〔来源 §5.4〕

**写手侧**（修订面 = `write-tech-design/SKILL.md` Step 2 第 9 节「批准范围」的四字段说明，**原位加入**）：

1. `scope_in` 与 `zero_diff` 不得对**同一对象**同时要求「修改」与「不修改」；
2. 外部治理规则强制修改时，必须在 **SDD 阶段**把该对象纳入 `scope_in`、修订 `zero_diff`、或给出**已有**的合法出口；
3. 不得用 `scope_out` 隐藏当前交付**必须发生**的治理修改；
4. `follow_up` 不得承载当前 AC 的**必要条件**。

**reviewer 侧**（修订面 = `review-tech-design/SKILL.md` Step 2 的「批准范围前置」段，**原位加入相同判据**）：四字段自洽判据与写侧**逐条一致**（同一表述、同一四字段名）；发现以下任一情形 → **必须在 SDD 阶段形成 blocker**：`scope_in` 与 `zero_diff` 对同一对象自相矛盾；治理强制修改被藏进 `scope_out`；当前 AC 的必要条件被放进 `follow_up`。**不得**把这些留到 dev-plan 再由 `review-dev-plan` 的 `upstream-design-blocker` 轨触发。

约束：不新增第五个字段、不新增独立 ledger 文件、不新增状态、不新增评审维度名（FR-5 的判据属于既有「批准范围前置」与「PRD↔SDD 对齐」面，不另造维度）；判据只针对四字段之间的**自相矛盾与必需条件错位**，不针对详尽程度（§1.5 第 6 条）。

## FR-6 同 CR 测试断言与门禁基线同步〔来源 §5.1.1 末段、§5.5〕

1. **目标用例原位改写**：`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 的用例 **`CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`**（§1.4 事实 9）：
   - 该用例内**两组 term 原位改写**为 `dep-N` 口径：写侧 term 组覆盖「小节名 + `dep-N` 固定结构 + 五字段名」（现为 8 项，含 `### 既有实现依赖与事实` / `正文首次出现顺序` / 四字段名 + `依赖结论:` / `sdd.explicit_existing_dependencies`）；评侧 term 组覆盖「显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + `sdd.explicit_existing_dependencies` + 正文漏列」。
   - **不另写第二个反向用例**；用例名保持（便于定位）；该文件的**顶层用例数不得减少**（当前 36 条，§1.4 事实 16）。
2. **`manifest.cases` 同步**：实施后 `skills/shared/crctl/scripts/test/gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 必须与 `pipeline-structure.test.mjs` 的**实际顶层用例数一致**（当前登记 35 / 实测 36，§1.5 第 2 条；本 CR 原位改写预期不改变用例数，若实施后仍为 36 而登记值仍为 35，则同 CR 把登记值同步为 36）。
3. **门禁全绿且零例外**：`suite-gate --run` 全量绿；`gate-registry.json#exceptions` 保持**空**（**不得签任何新例外**，CR-S 后全量测试是真门禁）。
4. **不改门禁机制**：不改 `suite-gate.mjs` 的判据语义（`cases < 登记值` 即红）、不新增门禁脚本、不新增 CI step、不新增 lint 规则。
5. **回归面**：CI 六个 step（lint-prompts enforce / skill matrix / agents contract / pipeline JSON 结构断言 / suite-gate --run / writeback 单测，§1.4 事实 14）全绿；`contract-scan` 的 `RETIRED_RECOVERY` 整树零命中（§1.4 事实 15）。

## FR-7 边界与零新增〔来源 §2、§5.5〕

1. **只原位改既有 Step 2.x 判据与 SDD 写作合同**：与 CR-2026-066 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账、Step 6 摘要**零 diff**（不重写、不放宽、不新增反向 token 命中）。
2. **不重编号 Step**：`review-tech-design` 的 Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6 与 `write-tech-design` 的 Step 1 / 2 / 2.5 / 2.6 / 3 / 4 / 5 全部保持编号不变。
3. **不碰 crctl 事务层**：`skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/**`、`gates.json`、状态机声明、`rules.json` 零 diff；不新增/删除子命令、flag、错误码。
4. **不新增 annotation dimension / 账本字段 / 评审指标 / Pipeline 节点**：不改 `pipeline-templates/**`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、traceability / review-loop / backlog 的字段集；不新增观测指标（SLO / 计数门禁 / 评审轮数承诺）。
5. **面不重叠（与 CR-P2 的边界）**：plan/TASK 写作合同（`skills/develop/write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-dev-plan/SKILL.md`）、upstream 增量回修、TASK 依赖闭包、证据命令证明力、环境责任与 readiness、`code-implementation.pipeline.json` 的 dev-start 提示全部归 CR-P2（来源 §6），本 CR **零 diff**。
6. **不复活旧字段名**：不引入 `recoverCommand` / `recover_command`（`contract-scan` 退役名单整树零命中）；结构化 `recovery` 合同（CR-2026-064）不变。
7. **不新增 Skill 契约面**：两份 SKILL 的参数表、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界不变（§1.3.3）。

# 4. 非功能需求

- **NFR-1 兼容性与门禁（最重要）**：`../tools` 全量既有测试与 CI（§1.4 事实 14 的六个 step，Ubuntu + Windows）保持绿；本 CR **不得签任何新例外**，`gate-registry.json#exceptions` 保持空。两份 SKILL 的状态转换、参数、落盘路径与错误码**零变化**。
- **NFR-2 零新增**：不新增 Pipeline 节点、评审维度名、账本字段、观测指标、crctl 子命令 / flag / 错误码、Skill 参数、落盘文件、lint 规则、CI step。
- **NFR-3 原位与单一事实源**：所有修订发生在**既有段落内部**；不得出现「新旧两套判据并存」的形态（尤其：`dep-N` 表与旧编号列表不得同时作为判据；批准范围自洽判据不得在写侧与评侧各自表述成不同强度；首轮全量判据不得在 SKILL 之外再存一份）。
- **NFR-4 判据可机械核对**：新增/改写的判据必须能被既有文本断言覆盖（AC-1~AC-6）；**不得**把不可判定表述（如「足够详细」「合理范围」）写成判据；同时不得把评审判断降级为「只要字面出现某词即通过」——判定责任仍在 reviewer（FR-2 第 6 条）。
- **NFR-5 行尾纪律（工作区纪律 #1）**：本 CR 触及跨行文本断言与 `\r\n` 归一化的测试读取（`readFileSync(...).replaceAll('\r\n','\n')`），读写前必须归一；断言/解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」。测试文件与 SKILL 文件必须保持 LF 检出内容一致（`gate-registry` 与 `suite-gate` 均按 LF 读取）。
- **NFR-6 语言纪律**：`../tools` 文档与 SKILL 正文用中文，代码与测试断言内注释按既有文件语言；本 CR 对 `../multica` 零 diff，不涉及英文注释规则。
- **NFR-7 可回退**：FR-1~FR-5 是 Prompt 判据的原位改动，FR-6 是同一 CR 内的断言同步——两者必须同批交付（否则 CI 红）；回退即同批还原，不产生半套合同。

# 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | §5.5（写侧） | `write-tech-design/SKILL.md`：① `### 既有实现依赖与事实` 小节存在且采用 `dep-N` 固定结构（`dep-N` + `repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论` 五字段齐全）；② 正文规则含「只写设计依赖 `dep-N`、不得重述当前代码行为」与「实现事实只在该表定义一次」；③ `commit SHA` 为必填 40 位 SHA；④ 无法绑定字段的引用列入待核实依赖且不得作为方案前提；⑤ `N/A` 仅在正文与依赖表均无依赖时可用；⑥ 编号稳定口径（按正文首次出现顺序分配、只增不改）已写明。 |
| AC-2 | FR-2 | §5.5（评侧） | `review-tech-design/SKILL.md#Step 2.1`：① 含五要素核验；② 含「正文只能引用存在的 `dep-N`」；③ 含「正文出现未通过 `dep-N` 引用承载的当前实现事实 → blocker」；④ `commit SHA` **必填**，且「并可附 `commit SHA`」措辞零残留；⑤ 保留「不扫描全仓 / 不猜测未写出的依赖」边界并写明「Prompt 合同、不宣称 NLP 机械识别」；⑥ Step 编号未变（Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6 全部存在）；⑦ 本 CR 新增文字不含 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`。 |
| AC-3 | FR-3 | §5.5（零改动核对） | ① `review-tech-design/SKILL.md#Step 2.2` 的首轮全量句**逐字**存在（「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题」）；② `tools/agents/quality-reviewer-agent.md` 相对基线**零 diff**（`##` 小节集合仍为 7 个、无新增小节、无判据副本）；③ 交付物中不存在「首轮漏检」账本计数、「`本轮新增：` 作为流程质量统计」、「评审轮数数字承诺」。 |
| AC-4 | FR-4 | §5.5（状态链） | `write-tech-design/SKILL.md` 回修模式段含四项判据：① 状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流类 blocker → 重证该状态链的完整输入维度、分支、可见动作与对应 AC；② 不得只修被点名的一格；③ 同一标识符 / 锚点 / testid 全文只有一个裁决；④ 未受该根因影响的已确认方案不得重写。 |
| AC-5 | FR-5 | §5.5（范围自洽） | ① **两侧**（`write-tech-design` 批准范围四字段说明 + `review-tech-design` 批准范围前置段）均含四条同判据（`scope_in`↔`zero_diff` 不得对同一对象自相矛盾；治理强制修改必须纳入 `scope_in` / 修订 `zero_diff` / 给出已有出口；不得用 `scope_out` 隐藏必须发生的治理修改；`follow_up` 不得承载当前 AC 必要条件），且表述与字段名一致；② 评侧要求冲突在 **SDD 阶段**形成 blocker、不留到 dev-plan upstream；③ 无第五字段、无新账本文件、无新评审维度名、无新状态。 |
| AC-6 | FR-6 | §5.1.1 末段、§5.5 | ① `pipeline-structure.test.mjs` 的 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例仍在，且其写侧/评侧 term 组已原位改写为 `dep-N` 口径（写侧覆盖小节名 + `dep-N` 固定结构 + 五字段；评侧覆盖显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填）；② 该文件**顶层用例数不减少**（基线 36），**无**第二个反向用例；③ `gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 与该文件实际顶层用例数一致；④ `suite-gate.mjs --run` 全量绿、`gate-registry.json#exceptions` 为空数组（未签新例外）；⑤ `contract-scan` 的 `RETIRED_RECOVERY` 整树零命中。 |
| AC-7 | FR-7 | §5.5（零新增） | ① 交付 diff 只含 §1.3.1 表内文件（`write-tech-design/SKILL.md`、`review-tech-design/SKILL.md`、`pipeline-structure.test.mjs`，以及条件性的 `gate-registry.json`）；② `skills/shared/crctl/scripts/{crctl.mjs,lib/**}`、`gates.json`、`pipeline-templates/**`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`tools/agents/**`、`../multica/**` 零 diff；③ 无新 annotation dimension / 账本字段 / 评审指标 / Pipeline 节点 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件。 |
| AC-8 | FR-1、FR-2、FR-4、FR-7 | §5.5（CR-P3 面零 diff） | CR-2026-066 的既有断言在实施后**仍全绿且未被放宽**：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）逐字保留；四 SKILL 不含 `crctl checkpoint`、不含 `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；四个 review SKILL 的 PASS 分支断言与权限面断言（`REVIEW_SKILLS` 四处载体）零改动。 |
| AC-9 | 全部（边界与串行） | §2、§8（**本 PRD 新增**） | ① **与 CR-P2 面零 diff**：`write-dev-plan` / `write-dev-tasks` / `review-dev-plan` 的 SKILL 与 `code-implementation.pipeline.json` 的 dev-start 提示在交付 diff 中不存在；② **不与其他 CR 并发**：实施与交付期间 `change-requests/_backlog.yml` 的在途条目只有本 CR，CR-2026-063/064/065/066 的 `crctl status` 均为 `archived`；③ **本 CR 只收紧判据、不放宽任何既有门禁**：`review-tech-design` 中不存在被删除或弱化的既有 blocker 判据（Step 2.1 的 AC 闭环伪码、Step 2.3 的分级边界与固定前缀句全部保留）。 |

来源 §5.5 的七条验收与上表一一对应（AC-1~AC-8 未合并判据，只按「行为面 / 证据面 / 零 diff 面」分组排列）；AC-9 是「把 §2 的 CR-P1 边界与 §8 的串行约束写成可检查约束」的落地判据（来源文档没有对应 AC）。

# 6. 成功指标

- SDD 正文重复定义既有实现事实的比例 = 0（正文只出现「设计依赖 `dep-N`」）。
- 正文引用未定义 `dep-N` 的比例 = 0；依赖表五字段（含 40 位 `commit SHA`）完整率 = 100%。
- 两侧 `commit SHA` 强制性一致率 = 100%（写侧必填 = 评侧必填）；评侧因 SHA 缺失而漏判的次数 = 0。
- 状态链类 blocker（状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流）在**一轮**内完成整体重证的比例 = 100%；同根因被拆成多轮修补的次数 = 0。
- 批准范围四字段冲突在 **SDD 阶段**被评审判据拦下的比例 = 100%；因范围冲突触发 `review-dev-plan` 的 `upstream-design-blocker` 的次数 = 0。
- 本 CR 新增的 annotation dimension / 账本字段 / 观测指标 / Pipeline 节点 / crctl 子命令 / flag / 错误码 / Skill 参数 = 0。
- `pipeline-structure.test.mjs` 的顶层用例数（基线 36）= 不减少；`gate-registry.json#manifest.cases` 与该数不一致的条目数 = 0；`gate-registry.json#exceptions` 长度 = 0。
- 既有测试回归数 = 0；CI 新增例外数 = 0；CR-2026-066 的既有断言（clean 前置 / PASS 发布 / 对账 / 权限面）失败数 = 0。

# 7. 范围排除

**来源 §2 的 CR-P1 边界（逐条不做，判据见 AC-7 / AC-9）**

- **不重编号 Step**：`review-tech-design` 的 Step 1.0 / Step 5 / Step 6 与其余既有 Step 号一律保留（CR-2026-066 已占用；本 CR 只在既有 Step 2.1 与 Step 2 的既有段落内原位扩写）。
- **不碰 crctl 事务层**：不改 `crctl.mjs`、`scripts/lib/**`、状态机、`gates.json`、`rules.json`、`review-loop` / `traceability` / `_backlog` 字段集；不新增子命令、flag、错误码。
- **不新增结构承载**：不新增 annotation dimension、账本字段、评审指标（SLO / 计数门禁）、Pipeline 节点、Skill 参数、落盘文件、lint 规则、CI step。
- **不新增观测负担**：不为「首轮漏检」写账本计数；不用 `本轮新增：` 统计流程质量；不对评审轮数作数字承诺。
- **不在 Agent Prompt 造第二份判据**：`tools/agents/quality-reviewer-agent.md` 零 diff；不新建小节、不复制首轮全量判据、不把 `dep-N` 规则写进 Agent Prompt（唯一事实源 = review SKILL）。

**来源 §5 明确交出本 CR 的面**

- plan/TASK 写作合同（`write-dev-plan` / `write-dev-tasks` 的回修与 `crctl task init` 口径）、TASK 依赖闭包重算、证据命令可执行性与证明力、环境责任与即时 readiness、dev-start 提示改写 → **CR-P2**（来源 §6/§6.7）。
- 发布点前移与 checkpoint 委派收敛、四个 review SKILL 的 Step 1.0 clean 前置与 Step 5/6 PASS 发布/对账 → **CR-P3**（CR-2026-066，已归档）。
- 结构化 `recovery` 迁移与 `recoverCommand` 退役 → **CR-R**（CR-2026-064，已归档）；本 CR 不复活旧字段名。
- 测试基线去硬编码与 `suite-gate` 真门禁 → **CR-S**（CR-2026-065，已归档）；本 CR 不签例外、不改 `suite-gate.mjs` 语义。
- `review-requirement` / `review-dev-plan` / `review-code` 三个 review SKILL、`write-dev-*` 全部 SKILL、`skills/requirement/**` → 本 CR 零 diff。

**本次明确不碰的既有资产**

- 本 CR **不要求** reviewer 做全仓扫描、不要求作者猜测未写出的依赖、不宣称对自由文本事实的机械识别——「正文事实是否被 `dep-N` 承载」仍是评审判断。
- 本 CR **不删** `write-tech-design/SKILL.md` Step 1 现存的 `crctl checkpoint` 提交口径句（删除它属独立的发布口径变更，不在来源 §5 授权面内，见 §1.5 第 5 条）。
- CR 状态机、`gates.json`、`rules.json`（controlled-shell 白名单）、CAS 与 durable ledger transaction 框架、`ENVIRONMENT_MISMATCH`、版本化 `cmd-NN` 与 test evidence、`reviewLoop` / `replayNodes` / `maxAttempts`。
- KB 的 `specs/`、`delivery/`；`../multica` 的 `CUSTOM.md`、`cr-prompts-revised/**`、`aifirst/**` 与任何 Go/TS 代码。

**顺序与并发约束（可检查形式见 AC-9）**

- 顺序：CR-P0(063) → CR-R(064) → CR-S(065) → CR-P3(066) → **本 CR(067)** → CR-P2；本 CR 不得早于 CR-P3 执行，也不与 CR-P2 并发（tools 单写者）。
- 任一 CR 失败只回滚本 CR；不得为了保持后续 CR 而保留半套新旧合同。
