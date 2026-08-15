---
id: CR-2026-040-TASK-06
type: TASK
cr-ref: CR-2026-040
plan-ref: "change-requests/CR-2026-040/plan.md"
sdd-ref: "change-requests/CR-2026-040/sdd.md"
title: Skill/Pipeline 文案与静态契约收敛
slug: skill-pipeline-contract-converge
status: pending
estimate: 4h
depends-on:
  - CR-2026-040-TASK-03
created: 2026-08-15T12:00:00+08:00
---

## 任务描述

同步 `write-test-report`、`review-code`、`crctl` Skill 与 `code-implementation.pipeline.json` 的提示词契约，删除 shell 字符串执行、直接 traceability/review-loop 写入和代码评审重新执行测试的文本，并更新 `pipeline-structure.test.mjs` 静态断言。

## 涉及文件 / 模块

- `skills/develop/write-test-report/SKILL.md`
- `skills/develop/review-code/SKILL.md`
- `skills/shared/crctl/SKILL.md`
- `pipeline-templates/code-implementation.pipeline.json`
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`

## 实现要点

- `write-test-report`：改为生成 `.crctl/tmp/test-plan.json` → 一次 `crctl test --plan` → 只写 marker 后分析；删除 `--cmd` 与直接 traceability/review-loop 步骤。
- `review-code`：删除无条件重跑 lint/test/build 第二入口；将缺失报告、status 非 pass、digest/日志漂移或分析不完整记为 blocker。
- `crctl/SKILL.md`：`test` 子命令表更新为 `--plan` 输入、结构化输出、业务 block/技术 error 语义。
- `code-implementation.pipeline.json`：测试与代码评审节点 prompt 只保留输入、调用顺序、结果分流、reviewLoop 和失败中止；保留既有 `replayNodes` 与 checkpoint 顺序。
- `pipeline-structure.test.mjs`：断言 reviewLoop 结构不变，且 prompt 不含 shell 字符串执行/评审重跑算法。

## 验收条件

- `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 通过，无 CONTRADICTS/STALE。
- `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 全绿；Pipeline JSON 可解析、节点数不变。

## 完成标志

- 上述文件 `git diff` 仅触及本 TASK 列出范围；无 `--cmd`、`shell:true`、评审重跑测试或 Skill 手写受控账本残留。

## 接口契约

- 消费：TASK-03 产出的 `crctl test --plan` CLI 契约；`write-test-report`/`review-code` 在 Pipeline 中的既有节点 id。
- 产出：`write-test-report` 对外步骤为「生成临时 plan → 调用 `crctl test` → 写 marker 后分析」；`review-code` 只读证据产出评审 payload；不新增函数签名。
