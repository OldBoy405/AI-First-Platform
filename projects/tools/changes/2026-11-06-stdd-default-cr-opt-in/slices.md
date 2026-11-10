# 工作区入口精简 — BUILD 切片计划

## Dependency Graph Summary

```text
workflow-routing ─┐
                  ├─> 交叉验证 / 报告（不跨 Gate 3）
prompt-governance ┘
```

`stdd dependency-graph <本ID> --format json` 返回两个零依赖节点、无边和无循环。该工具只分析人工 Markdown；最终依赖以已确认 design 和逐 CP 审查为准。虽然两个能力没有数据依赖，二者共同约束入口行为，按下列顺序串行，避免同一工作副本上的并行写入。

## Slice Execution Plan

| # | 优先级 | 风险 | 粒度 | TC 覆盖 | 实现目标 | 依赖 |
|---|---|---|---|---|---|---|
| 1 | P0 | 高 | L | WFR-001–006、PG-001/002 | 知识库 `AGENTS.md`、`README.md`、`CONTEXT.md` 和 `dir-graph.yaml` 指引 | 无 |
| 2 | P0 | 高 | M | PG-001/003/004、WFR-006 | tools `AGENTS.md` 与全局 APPEND_SYSTEM 一行 | 无；为避免契约漂移在 1 后执行 |
| 3 | P0/P1 | 高 | M | 全部 WFR、PG 场景 | 交叉语义、差异、现有 quality 检查和报告 | 1、2 |

## Rationale

### Slice 1：入口与默认路由

- **依赖关系**：先固定共同入口，才能在验收时对照 tools 的适用范围。
- **风险分析**：旧 CR、缺绑定和用户已有账本修改的保护不可丢；本地 javascript 经验查询为空，不推断所有经验库为空。
- **工作量**：涉及 4 份现有文档及 8 个场景，故为 L；不拆出重复的状态机。

### Slice 2：包边界与全局偏好

- **依赖关系**：代码上零依赖；语义上应与 Slice 1 同时审查。ADJ-001 已按用户 2026-11-10 决定原位统一为批准措辞，旧断言失败仅为历史，不再维护并行替代预期；修订版 Gate 2 重新确认待完成，静态复验不等于原生 TC 覆盖。
- **风险分析**：tools 是包又是 CR 方法论；全局优先级一行不得覆盖用户后来内容的其他部分。
- **工作量**：2 份现有文档，为 M。

### Slice 3：交叉验收

- **依赖关系**：必须在前两份可审阅差异后执行。
- **风险分析**：静态字符串不能证明运行时；既有大量 dirty 和原生 TC 证据缺口不能掩盖。
- **工作量**：按已批准测试方案执行，不新建引擎或改变 quality 配置。

## 状态纪律

`tasks.md` 的勾选不替代 STDD 原生切片证据。当前未发现 `phases.build.slices_completed` 的合法写入口，不手改 `.stdd.yaml`；无法满足原生必需证据时如实保留未闭合，不能宣布 BUILD 或 Gate 3 已通过。
