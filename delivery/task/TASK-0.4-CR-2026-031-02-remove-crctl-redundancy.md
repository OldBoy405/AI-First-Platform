---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-02
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 删除 crctl 死代码与永久兼容分支
slug: remove-crctl-redundancy
status: done
estimate: 6h
depends-on: [CR-2026-031-TASK-01]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

按方案 §4.8 删除无消费者命令、重复算法和 backlog v1 永久兼容，为新 dispatch 腾出明确命令面。不得保留 wrapper 或 feature flag。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `skills/shared/crctl/SKILL.md`
- 相关索引/help/contract fixtures

# 3. 实现要点

- 删除 `writeApprovalSection`、`cr-metrics`、`task allocate` 及关联 helper。
- 删除 `migrate-backlog`、ghost cleanup、v1 fallback/warning；v1 返回 `UNSUPPORTED_BACKLOG_SCHEMA`。
- 暂不删除仍被 active prompt 调用的旧事务入口；其删除与调用迁移在 TASK-10 同一切换完成。
- 保留 YAML 子集解析器和 `evidenceSha16`。

# 4. 验收条件

1. `rg` 对删除符号仅允许命中历史文档，不命中 active dispatch/help/tests/Skill。
2. backlog v1 fixture 返回 `UNSUPPORTED_BACKLOG_SCHEMA` 且零写入；v2 全部既有测试通过。
3. `crctl report` 仍工作，`cr-metrics` 返回未知命令。

# 5. 完成标志

死代码和永久迁移分支删除，现有可用命令无回归，任务状态登记 done。

# 6. 接口契约

消费：TASK-01 `runCrctl(...)`。

产出：`assertSupportedBacklogSchema(text: string): void` 在 v2 返回，在 v1 调用统一错误 `UNSUPPORTED_BACKLOG_SCHEMA`；供 TASK-05/09 所有账本事务复用。
