# Gate 1 模板 v2 — 验证计划

> 文档类变更；无代码测试。以下为人工审查清单。
> 状态：Gate 2 已确认（2026-10-20T16:41:41，dialog，user）；不运行合并。
> Gate 3：已确认（2026-10-20T16:50:01，dialog，user）；Phase 4 DELIVER 待定。

## 验证项

| # | 检查 | 通过标准 | 结果 |
|---|---|---|---|
| V1 | §0 完整性 | 条目、基线、状态、格式四维齐全 | PASS |
| V2 | 判定无歧义 | STALE-ENTRIES / UNEXPLAINED / UNKNOWN → BLOCK；仅状态/格式 → PASS-WITH-FIX | PASS（建议 v2.1 补“修正后重跑 §0”） |
| V3 | 命令可执行 | §0 检查命令只读，路径与 CUSTOM 核对口径一致 | PASS |
| V4 | 更新纪律 | 补登/状态刷新在 Gate 1 前；基线行/合并记录在 Gate 3 后 | PASS |
| V5 | 与 CUSTOM 一致 | 不覆盖《合并冲突总则》的优先级和四类处置 | PASS |
| V6 | 不越界 | 不修改 multica 仓库、不修改 STDD 产品、不执行合并 | PASS |
| V7 | 反例覆盖 | 能用 2026-10-20 的三个实测反例解释为什么需要 §0 | PASS |
| V8 | 占位符一致 | `{{sync_id}}`、`{{fork_sha}}`、`{{upstream_sha}}` 等命名一致 | PASS |

逐项证据与 R1–R3 见 [test-report.md](test-report.md)。

## 实测反例核对

| 反例 | 证据 | 模板中的对应处理 |
|---|---|---|
| 《当前状态》停在 2026-10-08 | CUSTOM.md 第 46 行 | §0.1 状态新鲜维度；STALE-STATUS |
| AIFI-45 行“未 commit/push”与 git 不符 | CUSTOM.md 第 155 行；HEAD `0d6b4e9f9` | §0.1 状态新鲜维度；修正记录 |
| 2026-10-20 基线行落在合并记录表 | CUSTOM.md 第 298 行；表头在第 293 行 | §0.1 格式可解析维度；UNPARSEABLE |

## 审查记录

| 项 | 值 |
|---|---|
| 审查人 | user |
| 审查时间 | 2026-10-20T16:41:41 |
| 审查方式 | dialog |
| 结论 | Gate 2 已确认（证据：确认Gate 2） |
