# 工作区入口精简 — BUILD 切片计划

## Dependency Graph Summary

```text
slice 1（知识库入口与全局行）─┐
                              ├─> 验收（一次证据 run，覆盖全部 TC）
slice 2（tools 入口）─────────┘
```

两个切片没有数据依赖；它们共同约束入口行为，验收用同一次 run 一并验证，不按切片拆分证据。

## Slice Execution Plan

| # | 优先级 | 风险 | 粒度 | TC 覆盖 | 实现目标 | 状态 |
|---|---|---|---|---|---|---|
| 1 | P0 | 高 | L | WFR-001、PG-001、PG-002 | 知识库 `AGENTS.md`、`README.md`、`CONTEXT.md`、`dir-graph.yaml` 说明；全局 `APPEND_SYSTEM.md` 第 2 行 | 已实施，待验收 |
| 2 | P0 | 中 | S | WFR-001、PG-001、PG-003 | tools `AGENTS.md`：分层；CR 驳回段改为引用权威（tasks 2.1）；状态链与固定计数改为引用权威（ADJ-003） | 已实施，待验收 |

## Rationale

- **Slice 1**：旧 CR、缺绑定和已有账本保护不可丢；这是风险最高的入口，故最先验收保护点（TC-PG-001）。
- **Slice 2**：tools 既是代码包又是 CR 方法论资源；改动只有一个文件，机器消费者由 TC-PG-003 覆盖。

## 状态纪律

`tasks.md` 的勾选不替代 STDD 原生切片证据。验证全部通过后，按 build.md B3.4 写入 `phases.build.slices_completed`；在那之前不写，不以勾选冒充。
