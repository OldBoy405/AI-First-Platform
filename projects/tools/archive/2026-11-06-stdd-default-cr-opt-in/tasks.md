# 工作区入口精简 — BUILD 任务清单

> Change：`2026-11-06-stdd-default-cr-opt-in`；standard，普通模式。本清单随 design／test-plan 的当前版本重写；勾选不替代 STDD 原生切片记录与证据。

## 0. 同步修订与重签

- [x] 0.1 按当前合同整体重写 design、test-plan、specs、Canonical agent 规格、调整记录、切片、恢复上下文与测试报告（2026-11-15）。
- [x] 0.2 用户审阅完整差异后重签 Gate 1 与 Gate 2（2026-11-15 10:27，`--reapprove --confirmed-by dialog`，证据为用户原话；用户同时对 ADJ-002 表态“已知并接受”）。

## 1. 已实施的入口文案

- [x] 1.1 知识库 `AGENTS.md`：按任务和阶段加载；新 STDD、已有变更、显式 CR、只读及失败关闭。
- [x] 1.2 知识库 `README.md`、`CONTEXT.md`、`dir-graph.yaml` 的批准说明范围。
- [x] 1.3 tools `AGENTS.md` 的阅读路由与工程／CR 作用域分层。
- [x] 1.4 全局 `~/.pi/agent/APPEND_SYSTEM.md` 第 2 行。

## 2. 重签后实施

- [x] 2.1 tools `AGENTS.md`：CR 驳回路由段改为引用权威（design D5）；只替换该一行（CRLF 保留），工作副本其他修改未动（2026-11-15）。

## 3. 验收（按 test-plan 第四节）

- [x] 3.1 三路并行评审（STDD C1：代码=strong、测试配置=balanced、文档=economy）；发现已逐条处置，见 `pending-adjustments.md` ADJ-003。TC-WFR-001 盲评（strong，独立会话）已按改后的入口重做，答案写入 test-report。
- [x] 3.2 取 run id，执行 `agent verify`，完成盲评与保护点对照，取得用户对 TC-WFR-001、TC-PG-001 的确认原文，运行 `ci check-failures`。
- [x] 3.3 失败模式清单逐项注明所用 run 的结果或标注未执行；经验库按流程记录。
- [x] 3.4 写 `test-report.md`（引用该 run）、`design-adjustments.md`；把 `code-structure-delta.md` 改为“无代码结构变更”。
- [x] 3.5 验证全部通过后，按 build.md B3.4 把 `phases.build.slices_completed` 写入 `.stdd.yaml`（Skill 明确要求且无专用入口，用精准编辑；不替代验证）。
- [x] 3.6 请求并取得 Gate 3（须用户确认，含 tools 全量测试“未运行及原因”的处置）；不自动提交、推送或部署。

## 4. 交付前

- [ ] 4.1 重算知识库四个顶层文件与全局 `APPEND_SYSTEM.md` 的 LF SHA-256，并与 test-report 打印的哈希核对；不一致则回到 TC-PG-001 重新对照（C1 test F4；这是人工纪律，不是机器保证）。
