# 工作区入口精简 — BUILD 任务清单

> Change：`2026-11-06-stdd-default-cr-opt-in`；standard，普通模式；历史 Gate 2 方案 A，2026-11-10 修订版待重新确认。
> STDD 支持 command/manual 和 coverage 不适用声明，但跨根输入／项目级 CP／共享报告限制使本 change 在允许范围内无法闭合验收；切片记录也未闭合。工具缺口见 design D7；不伪造通过，不手改 `.stdd.yaml`。以下不代表阶段完成，当前停止 BUILD 推进。

## 1. workflow-routing（P0）

- [x] 1.1 记录现有 Canonical CP 的只读静态 RED；不创建真实 STDD 或 CR 变更。
- [x] 1.2 精简知识库 `AGENTS.md`，保留共同底线与用户已有修改；明确新 STDD、已有变更、显式 CR、只读及失败关闭。实施方式偏离见 ADJ-002。
- [x] 1.3 修改知识库 `README.md`、`CONTEXT.md`、`dir-graph.yaml` 的批准说明范围；验证 graph 业务值不变。
- [x] 1.4 复核 TC-WFR-001–006 与 TC-PG-001/002 的条款及人工场景；记录静态结果和未覆盖边界。静态和文案评审不等于原生 TC 完成。

## 2. prompt-governance（P0）

- [x] 2.1 分层 `../tools/AGENTS.md` 的阅读路由与 CR 作用范围，保留包工程、权限、状态和门禁纪律。
- [x] 2.2 精准修改 `~/.pi/agent/APPEND_SYSTEM.md` 第 2 行为用户确认的 ADJ-001 合并措辞，其余行不变。
- [x] 2.3 保留 TC-PG-003/004 的历史核对结果，并按用户 2026-11-10 决定原位统一 D5／CP-PG-003／TC-PG-003／spec 为批准措辞，取消并行替代预期；原生执行覆盖未闭合，修订版 Gate 2 重新确认待完成。

## 3. 交叉验证（P0 / P1）

- [ ] 3.1 执行独立语义／差异评审、CP 条款检查及只读 YAML 语义比较；保留用户原有变动。
- [ ] 3.2 运行 `test-plan.md` 中已约定的 tools lint（含 enforce）、合同检查及 quality 测试；如实记录退出码、超时和失败。
- [ ] 3.3 汇总失败模式、设计偏离和 `test-report.md`；原生机器覆盖未闭合时停在 Gate 3 前，不提交、推送或部署。
