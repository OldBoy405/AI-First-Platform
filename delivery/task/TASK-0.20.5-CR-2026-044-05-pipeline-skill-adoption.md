---
spec-id: ai-first-platform
version: "0.20.5"
id: CR-2026-044-TASK-05
type: TASK
cr-ref: CR-2026-044
plan-ref: "change-requests/CR-2026-044/plan.md"
sdd-ref: "change-requests/CR-2026-044/sdd.md"
title: Pipeline/Skill 采用与阶段终点 checkpoint 合同
slug: pipeline-skill-adoption
status: pending
estimate: 6h
depends-on: [CR-2026-044-TASK-02, CR-2026-044-TASK-03, CR-2026-044-TASK-04]
created: 2026-08-17T00:02:54+08:00
---

# TASK-05 Pipeline/Skill 采用与阶段终点 checkpoint 合同

## 1. 任务描述

落地 PRD FR-06~FR-08、FR-10、FR-11：`workspace inspect` 复用 `resolveOperationalWorkspace` 输出 `operationalWorkspace`；三条 Pipeline 传递 authority path、落实审批后强制 checkpoint；同步直接消费 Skill；最小修订既有 `checkUpgrade` 在途 CR 分类。对应 AC-12~AC-15、AC-18、AC-21~AC-23（SDD §6.4、§7、§11）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（`cmdWorkspace` inspect 分支补 `operationalWorkspace`）
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`checkUpgrade` 兼容分类）
- `skills/shared/crctl/scripts/test/upgrade-check.test.mjs`（三类状态参数化断言）
- `pipeline-templates/requirement-authoring.pipeline.json`、`architecture-design.pipeline.json`、`code-implementation.pipeline.json`、`pipeline-templates/_index.yml`
- `skills/develop/review-code/SKILL.md`、`skills/requirement/approve-requirement/SKILL.md`、`skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md`、`skills/shared/crctl/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/sync/workspace-freshness/SKILL.md`、`skills/writeback/merge-feature-branch/SKILL.md`
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`

## 3. 实现要点

- `cmdWorkspace`：`sub==='inspect'` 时调用既有 `resolveOperationalWorkspace(ctx, cr)`，输出追加 `operationalWorkspace: authority.path`；resolver 抛错原样结构化返回；`ensureWorkspace` lib 合同不变。
- requirement-authoring：`approve-requirement` 节点后新增 `push-progress` 节点（message=`需求审批结果`，`onFail=abort`）；草稿 checkpoint 与 `auto_push_after_prd` 保留；`_index.yml` nodes 6→7。
- architecture-design：首节点 prompt 增加“先 `workspace inspect`，要求全部 `resources[].classification=healthy`，消费 `operationalWorkspace`，非 healthy 中止指向 resume”；删除 `auto_push_after_sdd` 输入与 node-5 skip 分支，该节点改无条件执行、`onFail=abort`；nodes 仍为 5。
- code-implementation：首节点同样接入 inspect 与 healthy 断言并传递 `operational_workspace`；审批后 `push-progress` 节点 `onFail` 由 `skip` 改 `abort`；TASK checkpoint 保持可选；freshness 两节点位置不变；nodes 仍为 17。
- Skill 文本按 SDD §7.4 最小修订：消费 TASK-02 的 TTY `y|yes`、TASK-03 的 local drift 与 TASK-04 的 publication lag 合同；不复制算法，只改业务解释。
- `checkUpgrade(ctx)` 保持只读 CLI/返回形状不变：`code-reviewing` 从 safe 改为 `requiresReapproval`（detail=重跑 review-code）；`code-approved` 且无 publish 从 `requiresReapproval` 改为 safe（detail=checkpoint 后 merge，无需重审批）；partial publish 与 merging/writing-back 继续 `blocksUpgrade`。同步修订 `upgrade-check.test.mjs`，不新增分类数组或 CLI。
- pipeline-structure.test.mjs 新增断言：节点数、`onFail`、无 `auto_push_after_sdd`、authority path 传递、Pipeline 无 fetch/SHA/Git/CAS/journal 算法文本。

## 4. 验收条件

1. `workspace inspect` 对 healthy CR 返回与 `resolveOperationalWorkspace` 一致的 `operationalWorkspace`；txws/missing/inconsistent 场景不猜路径。
2. pipeline-structure 测试全绿：requirement 节点数 7 且审批后 checkpoint `onFail=abort`；architecture 无 `auto_push_after_sdd`；code 审批后 checkpoint `onFail=abort`、TASK checkpoint 可选、节点数 17。
3. `upgrade-check.test.mjs` 参数化证明 code-reviewing→requiresReapproval、code-approved 零 publish→safe、partial publish→blocksUpgrade，且命令执行前后业务文件与远端 ref 不变。
4. `check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs` 通过，Skill 修订不引入状态机/账本算法文本。

## 5. 完成标志

三条 Pipeline JSON 可解析 + pipeline/upgrade-check 测试全绿 + 九份 Skill 文本同步且 lint 通过。

## 6. 接口契约

- 消费：TASK-02 的 TTY `y|yes` 合同；TASK-03 的本地 verifier 语义；TASK-04 的 publication lag 与 checkpoint recoverCommand。
- 产出：`crctl workspace inspect` 新增 `operationalWorkspace` 字段；三条 Pipeline 的审批后 checkpoint 合同；`checkUpgrade(ctx)` 保持签名与返回 schema，更新 code-reviewing/code-approved 分类；TASK-06 的两仓文档据此更新。
