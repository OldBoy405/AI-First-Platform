---
id: CR-2026-038-TASK-05
type: TASK
cr-ref: CR-2026-038
plan-ref: CR-2026-038-plan
sdd-ref: CR-2026-038-sdd
title: 执行全量回归与交付范围审计
slug: writeback-regression-audit
status: pending
estimate: 6h
depends-on: [CR-2026-038-TASK-04]
owner: Ray
created: "2026-08-14T21:22:00+08:00"
updated: "2026-08-14T21:41:17+08:00"
---

# TASK-05：执行全量回归与交付范围审计

## 1. 任务描述

在全部实现与调用方迁移完成后，运行 SDD §9.5 全量验证，核对 PRD AC-01～AC-12、changed-files 白名单、跨平台行尾与无依赖/无范围扩张约束。只修复本 CR 引入的回归，不新增功能。

输入为 TASK-01～TASK-04 的代码、测试与 Prompt 变更。输出为 implement-code 节点可引用的完整验证命令、结果和剩余风险。

## 2. 涉及文件 / 模块

- TASK-01～TASK-04 已修改的 tools 文件
- 仅在发现本 CR 根因回归时修改对应生产/测试文件
- knowledge-base `change-requests/CR-2026-038/` 后续测试证据（由 write-test-report Skill 负责 canonical 落盘）

## 3. 实现要点

1. 执行 crctl 全套、writeback generator 全套、Skill matrix、Prompt lint 和全部 Pipeline JSON parse。
2. 重跑 writeback/merge 定向 fault matrix，汇总 AC-01～AC-12 到具体测试名或静态命令。
3. 用静态搜索确认 active Agent/Pipeline/Skill/help 无公共 candidate/generator/manifest path，baseline 后无独立 writing-back advance。
4. 检查 `.crctl/candidates` 在三个 stage 均被 ignore 且不在 staged/tree；检查临时 index finally 清理。
5. 检查 `git diff --check`、tools worktree changed-files、依赖清单与 package lock；不得新增 npm 依赖。
6. 检查 knowledge-base 只含 CR 产物/证据，Multica production/test/CUSTOM.md 零 diff。
7. 若 Windows 本机无法直接证明 Ubuntu，记录 CI-required residual risk，不伪造平台结果；确保 CRLF 参数测试本机通过。

## 4. 验收条件

- [ ] `node --test skills/shared/crctl/scripts/test/*.test.mjs` 全绿。
- [ ] `node --test skills/writeback/scripts/test/*.test.mjs` 全绿。
- [ ] `node skills/shared/crctl/scripts/check-skill-matrix.mjs` 与 `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 成功。
- [ ] `pipeline-templates/*.json` 全部可 JSON.parse，`git diff --check` 通过。
- [ ] AC-01～AC-12 每项至少有一个实际测试或静态验证证据，无删除测试、放宽 gate/assertion。
- [ ] changed-files 位于 SDD §1.5；README、Agent、状态机、gates、Multica、package dependency 无范围外变更。
- [ ] 所有已完成 TASK 在各自完成时经 `crctl task done` 登记，`tasks/_index.yml` 逐项含 `status: done` 与 `done-at`；TASK 卡保持不可变的 `status: pending` 描述源，不手改卡片状态。

## 5. 完成标志

全量命令成功并记录真实输出；已知未覆盖风险明确列出；代码与文档 worktree 无未解释改动，可进入 write-test-report 和代码评审。

## 6. 接口契约

**消费 TASK-04**：更新后的生产调用方、测试 fixture 和以下命令面：

```text
crctl writeback-apply <cr> --stage <baseline|tasks|traceability> <business args>
crctl merge <cr> <existing args>
```

**产出给 write-test-report**：

```text
verificationEvidence = Array<{
  command:string, cwd:string, exitCode:number,
  result:"pass"|"fail", coveredAc:string[], notes:string
}>
changedFiles = string[]
residualRisks = string[]
```

不得直接手写 `test-report.md#traceability` 受控投影；由后续 Skill/crctl 按 Pipeline 契约处理。
