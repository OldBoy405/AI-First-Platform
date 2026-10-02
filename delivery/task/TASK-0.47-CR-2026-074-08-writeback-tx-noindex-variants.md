---
spec-id: ai-first-platform
version: "0.47"
id: CR-2026-074-TASK-08
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: writeback-tx 无索引/证据齐全集成变体
slug: writeback-tx-noindex-variants
status: pending
estimate: 5h
depends-on: [CR-2026-074-TASK-04, CR-2026-074-TASK-05, CR-2026-074-TASK-06]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

构造无 specs 索引与证据齐全的端到端集成变体，覆盖 apply 并发/重放、完整归档与独立 trace 重放（SDD §5.2；FR-5/FR-6/FR-7 集成；AC-05 主责——用户可观察的首写/隔离/幂等端到端面在本卡 writeback-tx apply 层产生，四类结构负例由关联协作 TASK-04 承载并保留于 cmd-03；AC-12）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` — 新增变体用例（dep-18：`makeMergedFixture`/`makeNewModeMergedFixture`/`makeNewModeWritingBackFixture`/`addEvidenceFiles`；从 dep-17 `merge-fixture.mjs` 导入 `makeCodeApprovedFixture`）。
- 仅测试数据：无索引变体通过测试文件内对 fixture 临时仓的数据操作构造（如移除 specs/_index.yml 或裁剪证据）；若确需 fixture 参数扩展，在测试文件内局部包装，不修改 `merge-fixture.mjs` 与生产代码，不新增通用 fixture 框架（SDD §5.2）。

## 实现要点

- 无索引变体主链（AC-12）：dep-17 `makeCodeApprovedFixture`（targetVersion/targetSpecId/enrichedPlan 输入，两张规范 PLAN 表）→ merge → 无 `specs/_index.yml` 的 operationalWorkspace → baseline（消费 TASK-04 首写语义，before=null）→ writing-back（dep-18）→ 三阶段 → archive。
- 证据补齐：`addEvidenceFiles` 补 requirement/sdd 评审和 requirement/tech-design 审批字段（dep-18）；AC-12 使用测试 fixture 构造规范审批证据，不在真实 CR 中代签。
- apply 并发/重放（AC-05 apply 侧）：成功 candidate 后/apply 前注入并发文件创建 → apply 拒绝（before=null CAS，dep-9/dep-10），并发文件原文不变、不写 authority；已完成 after 的重放可识别、不覆盖并发异内容、不重复 spec/CR。
- 独立 trace 重放：重放仍保持 writing-back、不先 archive、不伪造真实审批；写回前后的 PLAN/approval/merge/test-report 规范行尾哈希必须不变。
- 不修改 `durable-tx.mjs`、writeback-apply、CAS 协议（以 dep-8 字节锚点为准）；兼容测试的语义哈希/解析比较先 CRLF→LF。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（证据 cmd-04）全绿，且 AC-12 断言覆盖：无索引 merge→三阶段→archive 全链通过；独立 trace 重放不改 baseline/tasks 事务与签字源规范哈希。
2. AC-05 apply 侧断言覆盖：并发注入后 apply 拒绝且并发文件原文不变、不写 authority；同事务重放不重复 spec/CR。
3. 全部新 Git 配置仅发生在临时测试仓，不触用户全局 Git 身份。

## 完成标志

- cmd-04 全绿含上述断言；diff 限 `writeback-tx.test.mjs`（及测试文件内局部 fixture 包装），生产代码零 diff。
- 与 TASK-04/05/06 联测：generator 三项语义在端到端变体中被真实触达（非仅单测桩）。

## 接口契约

**消费**：dep-17 `makeCodeApprovedFixture`（可传 targetVersion/targetSpecId/enrichedPlan；建立 code-approved 多仓源、两张规范 PLAN 表、TASK/test-report 与 dev-plan/code 评审和 development-start/code 审批证据；非全部 traceability 证据的完整 fixture）；dep-18 `makeMergedFixture`/`makeNewModeMergedFixture`/`makeNewModeWritingBackFixture`/`addEvidenceFiles`（从 merge-fixture.mjs 导入 makeCodeApprovedFixture，merge 后消费 operationalWorkspace，baseline 后进入 writing-back）；TASK-04 buildIndex 首写/features 前置校验语义；TASK-05 fr-chain/命令 ID 集合；TASK-06 trunkOf/TRUNK_UNKNOWN 语义。

**产出**：无新增生产签名（纯测试变体）。测试断言引用的端到端合同——before=null 首写、apply CAS 拒绝、重放幂等、签字源规范行尾哈希不变——与 TASK-04 契约逐字一致。
