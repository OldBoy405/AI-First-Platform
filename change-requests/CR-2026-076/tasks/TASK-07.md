---
id: CR-2026-076-TASK-07
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "默认 coding 取消重复开发启动确认（状态机／门禁／模板／合同同步）"
slug: coding-path-drop-dev-start
status: pending
estimate: 20h
depends-on: [CR-2026-076-TASK-05, CR-2026-076-TASK-06]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-06；AC-14；SDD §4.6、§3.3、§8、SDD-CLOSE-07）：默认编码路径不再插入独立 `human_approval`／`approve-dev-start`，改由 `write-dev-tasks` 的收尾入口（`mode=finalize`）在同一 run 内经既有 `advance` 进入 `developing`；同时**不伪造** development-start 批准。

背景与输入条件：`dep-24` 结论原文——`developing` 门禁当前要求 dev-start 阶段的 `passCondition` 与 `development-start` 审批段；`dep-25` 结论原文——默认 coding 路径当前包含 dev-start 人工确认与收尾节点；`dep-26` 结论原文——状态机当前（实测，非文档转抄）为 15 个具名状态 + 注册前 `(new)`，转移 **31 条声明**、wildcard 展开 53 条，`gate-registry.json#stateMachine` 独立登记 transitions=31／namedStates=15／wildcards.any-active=12，`crctl.test.mjs` 的「推导 ≡ 登记」断言把该规模固定为仓库不变量。

明确不做（§9 `zero_diff`）：不改状态集合（仍 15 个具名状态 + `(new)`）；不删 `approve-dev-start` 转换与旧审批调用（兼容路径保留）；不同步文档侧旧口径（`ARCHITECTURE.md` 硬不变量 5、workspace `AGENTS.md` 工程纪律 2 的 28 条声明／50 条展开）——滞后登记见 §9 `follow_up`；本 CR 自身按执行时合法有效的旧合同运行，不自我减负。

## 涉及文件 / 模块

- `dir-graph.yaml`：`change-request-track.state_machine.transitions` 新增一条 `{ from: task-breakdown, to: developing, trigger: "write-dev-tasks:finalize" }`（触发条件：`review-dev-plan` PASS 且 blockers 空，由收尾节点执行）
- `skills/shared/crctl/gates.json`：`statusGates.developing` 去掉 `passCondition: dev-start` 与 `approval: development-start`（保留 plan／tasks 存在性与 `globNonEmpty`）；`approvalStages.dev-start` 保留（旧调用兼容）
- `pipeline-templates/code-implementation.pipeline.json`：移除 `human_approval`（确认进入代码开发）与 `approve-dev-start` 节点，`review-dev-plan` PASS 后重连到 `write-dev-tasks` 收尾节点（`mode=finalize`），再接续 `workspace-freshness`
- `skills/develop/write-dev-tasks/SKILL.md`：增补收尾职责（`mode=finalize`：`advance --to developing --trigger write-dev-tasks:finalize`；不重跑 TASK 拆分、不重跑 `task init --count-hint`）
- `skills/develop/approve-dev-start/SKILL.md`：改为「仅历史／显式调用」兼容说明
- `skills/cr/inbox-emit/SKILL.md`：增补 `write-dev-tasks:finalize` → `event=developing` 映射来源（`approve-dev-start` 映射保留为兼容路径）
- `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/_index.yml`、`agents/dev-agent.md`、`agents/quality-reviewer-agent.md`、`agents/requirement-writer.md`
- `skills/shared/crctl/scripts/test/gate-registry.json`（`stateMachine.transitions` 31 → 32）与 `test/crctl.test.mjs`（「推导 ≡ 登记」断言常量同步）

## 实现要点

1. 默认编码路径的必经节点（§4.6，节点顺序与 trigger 标识符全文唯一）：设计批准 → PLAN／TASK 完整 → `review-dev-plan` PASS 且 blockers 空 → `write-dev-tasks` 收尾节点（`mode=finalize`）→ 资源与实际 readiness → 经既有 `advance`（trigger `write-dev-tasks:finalize`）进入 `developing`。
2. `mode=finalize` 与拆分入口语义分界固定：**不重跑** TASK 拆分，**不重跑** `crctl task init --count-hint` 的 TASK 集计数校验；只做收尾 `advance --to developing --trigger write-dev-tasks:finalize` 与 readiness 接续。
3. 门禁一致性：`developing` 门禁保留 plan／tasks／`globNonEmpty` 与 readiness；**不写入** `approval.yml#development-start`，不伪造批准事实。
4. 状态机口径：按 `dep-26` 实测（31 条声明／展开 53 条）+ 本 CR 新增 1 条 = **32 条声明**（展开数按实现期实际内容据实更新，并在结果中写明所用口径）；`gate-registry.json#stateMachine` 与 `crctl.test.mjs` 不变量同步，二者不得只改一处。
5. 合同同步的完成判定（§8）：上述文件与 §3.3 的 Pipeline／门禁／状态机变更一致，且 FR-04 要求的「按 CR-ID／cycle 写死的临时例外」已关闭。

## 验收条件

1. **AC-14（cmd-09 + cmd-04）**：默认新合同无需重复 dev-start 人工确认即可经合法转换进入 `developing`，且未伪造批准。`cmd-09` = tools 仓六文件（`pipeline-structure.test.mjs`、`contract-scan.test.mjs`、`check-skill-matrix.test.mjs`、`check-agents-contract.test.mjs`、`lint-prompts.test.mjs`、`skill-scope.test.mjs`），观测 Pipeline 模板结构、Skill／Agent 合同文本与权限矩阵的一致性；`cmd-04` = `crctl.test.mjs` 单文件。
2. **转换与门禁双面钉住**：断言 `task-breakdown → developing` 两条 trigger（`write-dev-tasks:finalize` 与兼容路径 `approve-dev-start`）都合法；断言 `developing` 门禁在 plan／tasks 缺失时仍硬阻断。
3. **口径自证**：`grep -c '^      - { from:' dir-graph.yaml` 实测值与本 TASK 结果声明的「32 条声明」一致；`gate-registry.json#stateMachine` 与「推导 ≡ 登记」断言同值。
4. **兼容性**：旧审批调用（`approve-dev-start`）与历史记录不被破坏，`approve-dev-start` Skill 仍可被显式调用。
5. 真实执行输出落 `test-evidence/cmd-09.log`、`test-evidence/cmd-04.log`；不新增 plan 未列命令、不以文档侧旧口径数字作断言。

## 完成标志

- 状态机 +1 条声明、门禁组合、Pipeline 模板、Skill／矩阵／Agent 合同六类文件同步落盘，`cmd-09`、`cmd-04` 真实执行退出码 0 并留证；
- 结果为「32 条声明」口径给出可复核命令与实测输出，展开数按实现期实际内容据实登记；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-05／TASK-06 产出，不得缩写）：
- `cmdNext` 的 `humanApproval` 判定（TASK-05 产出）：`review-dev-plan` PASS 后不再由 `humanApproval=true` 引导人工审批；
- `runGateChecks` 的 `warnings[]` 形状（TASK-06 产出）：`review-dev-plan` PASS 且 blockers 空是收尾 `advance` 的前置事实。

产出（供 TASK-10／TASK-17 与后续 CR 消费，消费方不得缩写）：
- 状态机新增转换（逐字）：`{ from: task-breakdown, to: developing, trigger: "write-dev-tasks:finalize" }`；既有 `{ from: task-breakdown, to: developing, trigger: "approve-dev-start" }` 保留；
- `skills/develop/write-dev-tasks/SKILL.md` 的 `mode=finalize` 入口契约：入参不含 `task_count_hint`，动作集合 = {收尾 `advance`，readiness 接续}，**不含** TASK 拆分与计数校验；
- `crctl advance` 调用形态（逐字）：`crctl advance {cr_id} --to developing --trigger write-dev-tasks:finalize --workspace <knowledge-base CR worktree>`；
- `gate-registry.json#stateMachine` 新值：`transitions = 32`（`namedStates = 15`、`wildcards.any-active = 12` 不变）。
