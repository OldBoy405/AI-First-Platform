---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-050-TASK-06
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: 阶段一正确性 gate：自检三命令 + AC-01~05 断言清单
slug: phase-1-correctness-gate
status: pending
estimate: 2h
depends-on: [CR-2026-050-TASK-01, CR-2026-050-TASK-02, CR-2026-050-TASK-03, CR-2026-050-TASK-04, CR-2026-050-TASK-05]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段一（FR-01～FR-05）完成后的正确性 gate：跑三条自检命令并核对 AC-01～AC-05 断言清单，全部通过后形成 checkpoint 证据，才允许进入阶段二（SDD §4.4 / PRD AC-14 的证据形态 = 本 TASK 完成记录早于 TASK-07 首个实现 commit）。

## 涉及文件 / 模块

- 无代码改动；运行验证 + knowledge-base worktree 提交记录（本 TASK 完成标志即 AC-14 时序证据）

## 实现要点

1. 在 tools 根目录运行：
   - `node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"`
   - `node skills/shared/crctl/scripts/lint-prompts.mjs`
   - `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`
2. 逐条核对：AC-01（受保护账本指引为 0）、AC-02（topic/三必填/回修输入/跨文档写入删除）、AC-03（context/intent/mode/无 source 伪造）、AC-04（参数映射/reportDraft/node-5 顺序）、AC-05（改判口径：cr_id 完整、无命令细节、无 owners 拼接、Skill 含 --approver）。
3. 记录每条命令输出与核对结论；随后执行 `crctl task done CR-2026-050 --task CR-2026-050-TASK-06 --workspace {execution_context.operational_workspace}`。
4. 执行 `crctl checkpoint CR-2026-050 --message "阶段一正确性 gate 完成" --workspace {execution_context.operational_workspace}`；要求 `phase=complete`、`changed=true`、`batchId` 非空、全部 `repositories[].confirmed=true`，并记录各仓 sourceSha。

## 验收条件

1. 三条命令全部退出 0。
2. AC-01～AC-05 核对结论全部为「通过」，且与 TASK-01～05 各自的完成标志一致。
3. 无因阶段一改动引入的 `_index.yml`/`agent-skill-matrix.yml` 漂移。
4. checkpoint 返回 `phase=complete`、非空 `batchId`、全部参与仓 `confirmed=true`；该 batch 时间/提交早于 TASK-07 首个实现提交。

## 完成标志

验收 4 条全部通过；完整 TASK ID 已经 `crctl task done` 登记，且真实 checkpoint batch 已形成 AC-14 时序证据。

## 接口契约

- 消费：TASK-01～05 的产物与各自验收结论。
- 产出：阶段一 gate 完成证据（AC-14 时序锚点）；TASK-07～13 以本 TASK 完成为依赖前提。
