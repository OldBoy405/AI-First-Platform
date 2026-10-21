# 上游同步 Gate 1 模板 v2 — 设计说明

## Context

- 目的：把“台账新鲜度”从隐含假设变成 Gate 1 的硬前置。
- 约束：不新增 Gate；不修改 CUSTOM.md；不引入自动改写台账的逻辑。
- 基线：CUSTOM.md @ multica `0d6b4e9f9`（2026-10-20）；STDD 3.0.7。
- Gate 1 / Gate 2 / Gate 3 已确认；本次不执行合并，Phase 4 DELIVER 待定。

## Decisions

### D1：新鲜度检查放在 Gate 1 内部，不新增 Gate 0

STDD 的三道 Gate 是固定流程。新增 Gate 会破坏状态机和确认语义。因此把它作为 Gate 1 的“第 0 节”与准入条件，而不是第四个 Gate。

### D2：四维判定，不用单一日期

| 维度 | 为什么需要 |
|---|---|
| 条目 | CUSTOM 最近被修改，不等于每个代码改动都已登记 |
| 基线 | 四数可能因上游吸收、标记退役或未登记改动而变化 |
| 状态 | 《当前状态》、CR 索引、迁移水位可能滞后于 git/PR |
| 格式 | 表格错位会让自动解析漏行；即使人工读也会误读 |

### D3：三档结论

- PASS：全部 FRESH / EXPLAINABLE。
- PASS-WITH-FIX：仅状态或格式问题，先独立修正再进 Gate 1。
- BLOCK：条目欠债、基线差异无法归因、或证据不足。

### D4：更新纪律

| 类型 | 时机 | 方式 |
|---|---|---|
| 补登未入台账的代码改动 | Gate 1 前 | 独立 commit，先补台账再合并 |
| 状态字段刷新 | Gate 1 前 | 独立 commit，不改历史行 |
| 基线现场实测 | Gate 1 内 | 写入 proposal，不修改历史行 |
| 新基线行 / 合并记录 / 退役标记 | Gate 3 后 | 追加，不重写历史 |
| 归属不明 | 任意时点 | 停止，交用户裁决 |

### D5：为什么不自动更新

自动补台账需要判断“某改动属于哪个 #N、该用哪类处置”，这是裁决，不是格式操作。让 AI 在 Gate 1 自动填会把“欠债”掩盖成“已登记”，所以只允许在证据明确时补登，归属不明必须 BLOCK。

## Evidence（2026-10-20 实测）

- 最后一条 CUSTOM 提交：`0d6b4e9f9`（AIFI-45），之后 0 个 `server/packages/apps` 代码提交。
- 《当前状态》日期：2026-10-08。
- AIFI-45 CR 索引行：写有“Gate 3 未批准、未 commit/push”，但该行已随 `0d6b4e9f9` 提交。
- 2026-10-20 基线行：落在《合并官方记录》表，表头为 3 列，行内容为 7 列（基线四数）。
- 结论：时间维度通过，状态/格式维度不新鲜；条目维度需逐文件复核，不能仅凭日期判定。

## Alternatives Considered

- **只看 CUSTOM.md 修改日期**：会把本次情况误判为 FRESH。
- **新增 Gate 0**：破坏三道 Gate 的状态机。
- **自动补台账**：会掩盖归属不明的欠债。
- **把新鲜度检查放到 Gate 2**：太晚，冲突解决已经开始，补登会和 merge diff 混在一起。

## Risks

- 模板变长，例行同步可能觉得繁琐。缓解：§0 只保留四维表 + 判定 + 命令；其余细节可引用 CUSTOM。
- `task_type: upstream-sync` 尚未登记，CLI 可能按 `code` 处理。缓解：先作为文档模板使用，正式登记另开配置变更。
- 台账格式可能继续漂移。缓解：Gate 1 明确把 UNPARSEABLE 作为 PASS-WITH-FIX 或 BLOCK，并要求修格式。

## Open Questions

1. 是否把 `upstream-sync` 正式登记为 STDD task type？
2. v2 模板最终放在产品 `.stdd/templates/` 还是记录根 `projects/multica/templates/`？
3. Gate 2 是否也需要一次“基线复核”，还是只在 Gate 1 和 Gate 3 做？

## Gate 2 确认

| 项 | 值 |
|---|---|
| 确认人 | user |
| 确认时间 | 2026-10-20T16:41:41 |
| 确认方式 | dialog |
| 确认原文 | 确认Gate 2 |
| 结论 | Gate 2 已确认；进入 Phase 3 BUILD，Gate 3 待确认 |

## Gate 3 确认

| 项 | 值 |
|---|---|
| 确认人 | user |
| 确认时间 | 2026-10-20T16:50:01 |
| 确认方式 | dialog |
| 确认原文 | 确认Gate 3 |
| 结论 | Gate 3 已确认；Phase 3 BUILD 完成，Phase 4 DELIVER 待定 |
