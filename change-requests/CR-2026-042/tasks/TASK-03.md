---
id: CR-2026-042-TASK-03
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: Skill 职责收敛
slug: converge-skill-scope
status: pending
estimate: 8h
depends-on: []
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

按 SDD §2.3 收缩 CR 生命周期 Skill：保留业务 interface，删除深原语 implementation 复述、手工 Git 配方和失效模板引用。

# 2. 涉及文件 / 模块

- `skills/requirement/write-requirement-prd/SKILL.md`（删 engineering-docs/MCP/owClient/`_config.yml`/validate-doc 失效引用）
- `skills/requirement/requirement-register/SKILL.md`（删三账本/journal/write-set/lease 内部步骤复述）
- `skills/develop/write-tech-design/SKILL.md`（删手工 commit 配方）
- `skills/develop/write-dev-tasks/SKILL.md`（删手工 commit 配方）
- `skills/develop/review-code/SKILL.md`（删 lint/test/build 执行入口和 reviewer 选择暂停依赖）
- `skills/develop/write-test-report/SKILL.md`（只保留一次 `crctl test --plan` + 分析区）
- `skills/writeback/merge-feature-branch/SKILL.md`（删 prepare/publish/finalize 内部算法展开）
- `skills/writeback/writeback-prd-sdd/SKILL.md`、`writeback-tasks/SKILL.md`、`writeback-traceability/SKILL.md`（各一次 `crctl writeback-apply`，删内部路径）
- `skills/sync/push-progress/SKILL.md`（删逐仓 commit/lease/metadata 算法）
- `skills/cr/cr-archive/SKILL.md`（删四账本 write-set/commit/push/cleanup 实现步骤）

# 3. 实现要点

- 保留：业务前置、业务判断、一次公开深原语调用、公开结果分类、失败语义、状态前后置；
- 删除：journal、write-set、CAS、candidate、manifest、lease、逐仓 Git、账本字段拼接、内部恢复步骤；
- `inbox-emit`、`cr-dashboard` 读 `_config.yml` 的 SLA 是真实业务输入，不删除；
- 规划域 `repair-instructions`/`fixed-blockers` 是 product-planning 自有合同，不误套入 CR canonical 清理。

# 4. 验收条件

1. `grep -nE 'engineering-docs|MCP|owClient|_config\.yml|validate-doc' skills/requirement/write-requirement-prd/SKILL.md` 零命中；
2. `grep -nE 'git (add|commit|push)' skills/{requirement,develop,writeback,sync,cr}/*/SKILL.md` 在 write/develop 组零命中（经 crctl git 的正确形态除外）；
3. `review-code/SKILL.md` 无「重新执行 lint/test/build」的第二入口；`write-test-report/SKILL.md` 只有一次 `crctl test --plan`；
4. 三个 writeback Skill 各只有一次 `crctl writeback-apply` 调用，且无 `candidate|manifest|generator` 路径暴露；
5. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode report` 对 R1/R2 零新增命中（TASK-05 前以现有规则为准）。

# 5. 完成标志

命中清单中的 Skill 全部收缩；lint-prompts 现有 R1/R2 规则零新增命中。

# 6. 接口契约

- 消费：无上游 TASK 产出；只读 SDD §2.3 文件映射表与现有 `crctl` 公开命令。
- 产出：收敛后的 SKILL.md（无机器接口）；下游 TASK-04 消费「各 Skill 最终业务边界」文本。
