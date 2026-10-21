# 上游同步 Gate 1 模板 v2（台账新鲜度前置）

> 变更 ID：`2026-10-20-upstream-sync-gate1-v2`
> 状态：Gate 1 已确认（2026-10-20T16:38:21）；Gate 2 已确认（2026-10-20T16:41:41）；Gate 3 已确认（2026-10-20T16:50:01）；Phase 3（BUILD）已完成，Phase 4（DELIVER）待定
> 交付物：[upstream-sync-gate1-v2.md](upstream-sync-gate1-v2.md)
> 模板版本：v2（2026-10-20）

## Why

v1 的 Gate 1 模板只做了基线四数和冲突面预测，没有把“台账本身是否新鲜”作为准入条件。实际检查 multica 仓库时发现三个反例：

1. 《当前状态》停在 2026-10-08（[CUSTOM.md:46](file:///C:/Users/GOBAO/Downloads/AI/multica/CUSTOM.md#L46)），而 HEAD 已是 2026-10-20。
2. AIFI-45 的 CR 索引行仍写“Gate 3 未批准、未 commit/push”（[CUSTOM.md:155](file:///C:/Users/GOBAO/Downloads/AI/multica/CUSTOM.md#L155)），但该行已随 HEAD `0d6b4e9f9` 提交，“未 commit/push”与 git 事实不符。
3. 2026-10-20 的基线行落在《合并官方记录》表里（[CUSTOM.md:298](file:///C:/Users/GOBAO/Downloads/AI/multica/CUSTOM.md#L298)），该表表头只有 3 列（[CUSTOM.md:293](file:///C:/Users/GOBAO/Downloads/AI/multica/CUSTOM.md#L293)），行内容却是基线四数；按章节解析会漏。

这些不是代码冲突，但会让 Gate 1 在错误的台账上放行，违反 CUSTOM《合并冲突总则》的“台账唯一事实源、未登记改动先补台账”。

## What Changes

- 在 Gate 1 模板最前面增加《§0 台账新鲜度检查》，覆盖条目、基线、状态、格式四个维度。
- 增加 PASS / PASS-WITH-FIX / BLOCK 三档判定；STALE-ENTRIES、UNEXPLAINED、UNKNOWN 一律 BLOCK。
- 明确更新纪律：补登和状态刷新必须在 Gate 1 前独立提交；历史基线行和合并记录只在 Gate 3 后追加。
- 把“台账新鲜度结论”加入 Gate 1 确认项。

## Non-Goals

- 不执行任何上游合并。
- 不修改 `multica/CUSTOM.md`。
- 不把模板安装到 STDD 产品 `.stdd/templates/`。
- 不在 STDD 配置中正式登记 `upstream-sync` task type；这需要另开配置类变更。
- 不定义 Gate 2 模板；本次只交付 Gate 1 v2。

## Success Criteria

- v2 模板包含 §0，且 §0 的四维、判定规则、检查命令、修正记录、准入结论齐全。
- §0 与 CUSTOM《合并冲突总则》不冲突，并明确“先补台账、再合并”。
- 模板不依赖未落地的 CLI 命令；所有检查命令只读、可手工执行。
- 本变更记录不修改产品或 multica 仓库文件。

## Gate 1 确认项（已确认）

1. 是否接受把台账新鲜度作为 Gate 1 硬前置。
2. 是否接受 STALE-ENTRIES / UNEXPLAINED / UNKNOWN 一律 BLOCK。
3. 是否接受“补登/状态刷新独立提交、历史行 Gate 3 后追加”的纪律。
4. 是否授权将 v2 模板作为后续 upstream-sync 变更的 Gate 1 草案。

| 项 | 值 |
|---|---|
| 确认人 | user |
| 确认时间 | 2026-10-20T16:38:21 |
| 确认方式 | dialog |
| 确认原文 | 确认Gate 1 |
