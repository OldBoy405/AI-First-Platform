# 设计调整汇总（design-adjustments）

> change: 2026-11-25-upstream-sync-22f8c793
> 结论：本轮无 proposal/design/spec 的语义偏离；以下均为实现层调整或按既有规则的执行修正，不改变受审承诺。

## 1. 验证实现调整（未改 Agent Spec 语义）

- helper 增加与锁定断言逐字对齐的汇总行（`assert=...`），值由实际计算结果拼接；不虚构通过。
- 迁移动作新增 `sql_payload_sha256_match`：直接比较 FORK v298 与候选 v337 的 SQL payload 哈希（`b78dfffde2ce…` 一致）。
- 生成物动作把漂移判定从 `git status` 文件名改为 `git diff --binary` 内容比较；新增 Admin 锁 `--lockfile-only --frozen-lockfile` 复验与 CHANGELOG 版本头检查。
- 探针目录改为 `mkdtemp`；所有子命令统一注入隔离 `GBRAIN_HOME` 与 `GBRAIN_TEST_MODE=1`。
- 目标测试批次纳入 4 个合同金标准测试（cli-goldens / export-surface / engine-sql-sql-text / cli-dispatch-phase）。

## 2. 合并实现调整

- 合同金标准按 `CUSTOM.md` 生成物规则以 `regen:all --goldens` 重生成，恢复 fork 合同（graphOverview / inbox ops）；该修复来自 C1 代码评审发现（严重），属规则执行而非设计变更。
- `src/core/rust-engine/members.ts` 增加 `graphOverview: 'graph'` 分类（上游新增的成员注册强制覆盖全部 BrainEngine 成员；fork 的 graphOverview 之前不在该表）。
- `src/commands/status.ts` 的 DreamCycle 记录投影补 `phases: null` 以匹配上游 `CycleRow` 契约；选择语义维持 fork 原行为。
- `src/core/ops/links.ts` 的 fork 行上限改为在 `await worldLinkContexts(...)` 之后截断（上游把可见性过滤改为异步）。

## 3. 证据与台账维护

- `test-plan.md` 的 evidence inputs 增补合同测试/金标准/实现适配文件；candidate-only 路径（v337 迁移文件）替换为 FORK 中存在的 v298 路径，以满足输入存在性校验（v4 Gate 2 允许增补，不重开 Gate）。
- `CUSTOM-LEDGER.md`：#5 与迁移表更新为 v337/v336，对齐点更新为 v0.60.638.0·17b68cef4f，#2 文档说明纠正，补充上游删除/改名核对与 graph_overview 存量提示。

## 4. 未触发修订的项

- 未修改 proposal、spec、test-plan 的 Scenario/TC/CP 语义、Gate 2 锁定字段。
- 未新增定制能力、未改 CI、未动生产 brain、未提交/推送。
