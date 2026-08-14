---
id: CR-2026-039-TASK-05
type: TASK
cr-ref: CR-2026-039
plan-ref: "change-requests/CR-2026-039/plan.md"
sdd-ref: "change-requests/CR-2026-039/sdd.md"
title: review canonical 文本契约收敛（三个 CR Pipeline + 相关 Skill）
slug: review-canonical-text-convergence
status: pending
estimate: 4h
depends-on: []
created: 2026-08-15T01:31:31+08:00
---

# 任务描述

按 SDD §4.5 清单删除三个 CR 生命周期 Pipeline 与相关 Skill 中对不存在 canonical 字段的引用（`repair-instructions`、`fixed-blockers`、`suggestion_policy` 及首轮升格规则）；可执行回修说明并入 blocker 文本，reviewLoop 结构与 passCondition 不变。零 crctl 代码变更。

# 涉及文件 / 模块

- `pipeline-templates/requirement-authoring.pipeline.json`、`pipeline-templates/architecture-design.pipeline.json`、`pipeline-templates/code-implementation.pipeline.json`（prompt 文本修订；suggestion_policy 输入删除归 TASK-04，本 TASK 只删 review-code prompt 内的策略段与废弃字段引用）
- `skills/requirement/{write-requirement-prd,review-requirement}/SKILL.md`
- `skills/develop/{write-tech-design,review-tech-design,write-dev-plan,write-dev-tasks,review-dev-plan,implement-code,review-code,write-test-report,coding-discipline}/SKILL.md`
- `skills/shared/crctl/scripts/test/contract-scan.test.mjs`（新建，`node --test`）

# 实现要点（SDD §4.5）

- 修订模式（逐文件）：删 `repair-instructions`/`fixed-blockers` 引用 → 回修语义改为"逐条消费 review_feedback.blockers（blocker 字符串内含可执行修复说明）"；review-code prompt 删 suggestion_policy 全段（strict/lenient、升格判据、dimensions 记录），保留 blocker/suggestion 语义句；coding-discipline 保留 root-cause 要求、去掉与 fixed-blockers 的并列表述。
- 明确不动：`product-planning.pipeline.json`、`skills/planning/*`、Agent 文档与 README（归实施 CR 5）。
- 每个文件修订后语义自检：review_feedback 合同只剩 `blockers/suggestions/dimensions/repair-target`（SDD §3.4）。

# 验收条件

1. 扫描测试：三个 CR Pipeline JSON 全文零命中 `repair-instructions`/`fixed-blockers`/`suggestion_policy`；清单内 11 个 SKILL.md 同口径零命中；`product-planning.pipeline.json` 显式不在扫描断言范围（测试内白名单注释）。
2. 三个 Pipeline 的 `reviewLoop` 结构（repairNodeId/repairRef/replayNodes/passCondition）与修订前逐字段一致（扫描测试内结构快照断言）。
3. 既有 review-record schema 校验用例（SCHEMA_INVALID、dev-plan repair-target 枚举等）保持全绿——canonical 落盘行为零变化。

# 完成标志

扫描测试与既有全量测试全部通过；提交为一个可回滚 commit。

# 接口契约

- 消费：无上游 TASK 产出（纯文本契约；`canonical 字段集 = verdict/blockers/suggestions/dimensions/可选 repair-target` 以 `crctl review-record` 现有 schema 校验为准绳）。
- 产出：修订后的清单文件 + `test/contract-scan.test.mjs`（供 TASK-06 回归运行）。
