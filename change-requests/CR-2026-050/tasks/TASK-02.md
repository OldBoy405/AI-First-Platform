---
id: CR-2026-050-TASK-02
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: FR-05 四个 approve 节点收敛 + approve-* SKILL 命令补 --approver
slug: converge-approve-nodes-and-approver
status: pending
estimate: 3h
depends-on: [CR-2026-050-TASK-01]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

收敛 approve-requirement / approve-tech-design / approve-dev-start / approve-code 四个节点为「传 cr_id、消费结构化结果、下一步以 crctl next 为准」，并按 SDD §3.4 为四个 approve-* SKILL.md 的 Step 命令补 `--approver`，使 Pipeline 停传 approver 后本地 TTY 路径仍落角色 owner。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: pipeline-templates/requirement-authoring.pipeline.json`（approve-requirement 节点）
- `repo=tools: pipeline-templates/architecture-design.pipeline.json`（approve-tech-design 节点；**保留 workspace inspect 入口**，SDD §3.0）
- `repo=tools: pipeline-templates/code-implementation.pipeline.json`（approve-dev-start、approve-code 两节点；**保留 inspect / execution_context 契约**）
- `repo=tools: skills/requirement/approve-requirement/SKILL.md`、`skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md`（Step 命令补 `--approver {cr.md owners.{角色}.id}`）
- `repo=tools: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（AC-05 改判口径负向断言）

## 实现要点

1. 四节点删除：`crctl approve --stage ...` 命令细节、TTY 审批路径、`approval.yml`、grant/CAS/状态级联、reject 结果码文本。
2. 保留：完整 `cr_id` 传递；architecture/code 节点的 §3.0 inspect 入口与 authority path 契约；下一步统一「以 `crctl next {cr_id}` 为准」。
3. 四个 SKILL.md 的 Step 命令改为 `crctl approve {cr_id} --stage {X} --approver {cr.md owners.{角色}.id}`（grant 与 TTY 两条路径都补）；参数表 owners 回退说明与命令保持一致。
4. 负向断言：四节点 prompt 不含 `crctl approve` 命令字面量、不含 owners 解析/approver 拼接、不含写死的下一条 pipeline 名。

## 验收条件

1. 四节点 prompt 均含完整 `cr_id`，且 `grep "crctl approve"` 零命中（pipeline 内）。
2. 四个 SKILL.md 的 Step 命令均含 `--approver {cr.md owners.{角色}.id}`。
3. AC-05 改判口径负向断言通过；`pipeline-structure.test.mjs` 全绿（含 :165-183 保留断言）。
4. `lint-prompts.mjs` 无新增触发。

## 完成标志

上述 4 条验收全部通过；本 TASK 落地的 AC-05 改判口径在回写期须以 revision 修订 PRD FR-05.2/AC-05（SDD §3.4 偏离记录）。

## 接口契约

- 消费：SDD §3.4（approver 机制与 AC-05 改判口径）、SDD §3.0（inspect 保留项）、approve-* SKILL.md 现有参数表。
- 产出：四节点收敛版 prompt + 四 SKILL 命令含 `--approver`；下游 TASK-07/09/10 在同一 JSON 上继续收敛其他节点，不得回改本 TASK 的 approve 节点与 SKILL 命令。
