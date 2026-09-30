---
id: CR-2026-074-TASK-06
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: YAML trunk 解释
slug: yaml-trunk-parse
status: pending
estimate: 2h
depends-on: [CR-2026-074-TASK-05]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

将 traceability 的 trunk 解析改为读入 dir-graph 的 YAML 解释（SDD §4.5；FR-7；AC-08），不再依赖 dep-11 现状的正则首键与非引号值推断。

## 涉及文件 / 模块

- `skills/writeback/scripts/writeback-traceability.mjs` — `trunkOf`（dep-11）改造为消费 parseYaml 结果。
- `skills/writeback/scripts/test/writeback.test.mjs` — trunk 正负用例（与 TASK-05 同测试文件，顺序编辑）。

## 实现要点

- 导入 `parseYaml`（`skills/shared/crctl/scripts/lib/yaml-subset.mjs`，dep-12，零新依赖）；dir-graph 文本先 LF 归一再解析。
- 从 `doc.repositories` 按字符串 trim 后 id 定位 active 条目；trunk 要求非空字符串。
- 有效目标缺失/不唯一/无有效 trunk → TRUNK_UNKNOWN；绝不回退 master/main。
- 引号由 YAML parser 解码；id 的键序不影响定位。
- 不调用现场 repository resolver 做磁盘检查：trace 输入是冻结的业务根声明，不把代码仓本地 checkout 可达性新增为 generator 前置。
- merge facts 的 sha/branch 构造和 required 校验保持不变。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/writeback/scripts/test/writeback.test.mjs`（证据 cmd-03）全绿，且 AC-08 断言覆盖：引号包裹与非首键 trunk 正确解析；缺有效 trunk（缺失/不唯一/空值）返回 TRUNK_UNKNOWN；不存在 master/main 回退路径。
2. 原 TASK/test-report/merge facts 交叉校验负测保留并通过；仅改测试 graph 文本或交叉输入即可触达 parser，不因状态/缺证据先失败。

## 完成标志

- cmd-03 全绿含 AC-08 断言；`trunkOf` 仅消费 parseYaml 结果，无磁盘 resolver 调用；零新依赖（仅 import 既有 `yaml-subset.mjs`）。
- diff 限 `writeback-traceability.mjs` 与 `writeback.test.mjs`。

## 接口契约

**消费**：dep-12 `parseYaml`（可解析 repositories 的映射/序列及引号标量，供 traceability 直接 import）；dep-11 `trunkOf` 现状（本 TASK 将其正则解释替换为 YAML 解释）。

**产出**：`trunkOf` 新语义——输入 dir-graph 文本与目标仓 id，输出该 active 条目声明的 trunk 字符串或 TRUNK_UNKNOWN。merge facts 构造（sha/branch、required 校验）不变。下游消费方 TASK-08（独立 trace 重放）与既有 validator 引用同一语义，不得缩写。
