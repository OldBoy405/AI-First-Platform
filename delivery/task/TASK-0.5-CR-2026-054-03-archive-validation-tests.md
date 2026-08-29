---
spec-id: ai-first-platform
version: "0.5"
id: CR-2026-054-TASK-03
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "覆盖 archive 校验和 Git 副作用测试"
slug: archive-validation-tests
status: pending
estimate: 6h
depends-on: [CR-2026-054-TASK-02]
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

为 archive 严格校验补齐可归因的单元和事务测试，证明合法候选可归档、无效候选在所有 Git 写入前失败，并覆盖首次构建与 rebuild 两条路径。

# 2. 涉及文件 / 模块

- `tools` worktree 的 `skills/shared/crctl/scripts/test/yaml-subset.test.mjs`
- `tools` worktree 的 `skills/shared/crctl/scripts/test/archive-tx.test.mjs`

# 3. 实现要点

- 复用现有测试入口、fixture 和 Git 事务测试工具，不创建新的验证命令。
- 覆盖 history 缺失 id、缺失 final-status、重复 id、非法终态、目标 CR 计数错误及四候选根结构错误。
- 分别断言 archive 失败后工作区文件、HEAD、stage、commit 和 push 状态不变。
- 对远端变化触发的 rebuild 使用同一候选校验路径，并断言正常既有错误码仍保持。

# 4. 验收条件

对应 PRD 验收标准：AC-1、AC-2。

1. `yaml-subset.test.mjs` 和 `archive-tx.test.mjs` 全部通过，包含首次构建和 rebuild 的无效候选场景。
2. 每类 `ARCHIVE_YAML_INVALID` 断言 file/category/line 及适用 cr/key；纯缺失不变量断言 `line: null`。
3. 失败场景证明没有产生 stage、commit 或 push，且既有生成期错误码没有被改写。

# 5. 完成标志

tools 相关测试通过，测试只读/隔离 fixture 可重复执行，未引入全局 strict 解析或额外账本写入。

# 6. 接口契约

- 消费：TASK-02 通过 archive 公共事务入口提供的候选校验行为，以及 TASK-01 的 strict 错误字段。
- 产出：tools 侧 archive 测试证据，供后续集成测试、`write-test-report` 和 code review 消费；不暴露新的运行时接口。
