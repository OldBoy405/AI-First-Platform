---
id: CR-2026-042-TASK-07
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: 全量验证
slug: full-validation
status: pending
estimate: 3h
depends-on:
  - CR-2026-042-TASK-01
  - CR-2026-042-TASK-02
  - CR-2026-042-TASK-03
  - CR-2026-042-TASK-04
  - CR-2026-042-TASK-05
  - CR-2026-042-TASK-06
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

对全部 TASK 产出执行 plan.md §5 的发布前 checklist，记录验证命令与结果，确认本 CR 未引入回归、未改动 `crctl` 生产行为、状态机/账本/schema 无变化。

# 2. 涉及文件 / 模块

- 无新增文件；执行验证并产出证据（结果写入节点输出，正式测试证据由 write-test-report 阶段统一采集）。

# 3. 实现要点

执行并在输出中记录：

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
for f in pipeline-templates/*.pipeline.json; do node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))"; done
node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
```

# 4. 验收条件

1. lint-prompts enforce 退出 0；
2. check-skill-matrix.mjs 与 check-agents-contract.mjs 退出 0；
3. 全部 Pipeline JSON 可解析且固定断言通过；
4. crctl 全量测试与 writeback 单测全绿；
5. `crctl.mjs`、状态机、gates、approval、test-report 机器区、writeback/archive 语义无行为改动（diff 零触及生产算法）；
6. 三个参与仓 worktree 干净，CR 产物齐全（cr.md/prd.md/sdd.md/plan.md/tasks/）。

# 5. 完成标志

上述 6 条全绿；验证命令与结果记录在案，可支撑后续 write-test-report。

# 6. 接口契约

- 消费：TASK-01~06 全部产出。
- 产出：验证证据（命令输出）；下游无 TASK，本 TASK 是全量验证收口。
