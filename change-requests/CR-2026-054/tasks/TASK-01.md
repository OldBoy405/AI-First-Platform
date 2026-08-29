---
id: CR-2026-054-TASK-01
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "实现 YAML strict 可选解析模式"
slug: yaml-strict-parser
status: pending
estimate: 8h
depends-on: []
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

在 tools 现有零依赖 YAML 子集解析器上增加 `parseYaml(text, { strict: true })` 的可选严格语义，默认 `parseYaml(text)` 行为保持兼容。严格模式只服务 archive 校验，不能变成全局强制解析。

# 2. 涉及文件 / 模块

- `tools` worktree 的 `skills/shared/crctl/scripts/yaml-subset.mjs`
- `tools` worktree 的 `skills/shared/crctl/scripts/test/yaml-subset.test.mjs`

# 3. 实现要点

- 读入后先将 CRLF 规范化为 LF。
- 严格模式拒绝 tab、非法缩进、非法容器切换、未消费行、无子节点的裸 `-` 和 block/flow map 重复键。
- 重复键使用 `unquote()` 后的键比较，并保留首个及重复出现位置。
- 错误通过现有 Error 机制携带 `category`、`line`、适用时的 `firstLine`/`key`；不引入第三方 YAML 依赖或新 schema registry。
- 合法 `key:` 空值和默认宽松调用方保持原行为。

# 4. 验收条件

1. strict 模式测试覆盖 block/flow 重复键、引号等价键、CRLF、tab、非法缩进、容器切换、未消费行、孤立 `-` 和合法空值。
2. 默认模式既有测试全部通过，并证明同一合法输入的默认调用结果没有变化。
3. 错误类别和 1-based 行号与 SDD §2.1/§3.1 一致，解析失败不会静默返回部分结果。

# 5. 完成标志

`yaml-subset.test.mjs` 通过，默认模式回归通过，diff 中没有第三方依赖或 archive 事务代码。

# 6. 接口契约

- 消费：既有 `parseYaml(text)` 解析器及其现有返回值/错误机制。
- 产出：`parseYaml(text, { strict: true })` 的可选严格行为、结构化错误字段，供 CR-2026-054-TASK-02 调用；不新增对外模块接口。
