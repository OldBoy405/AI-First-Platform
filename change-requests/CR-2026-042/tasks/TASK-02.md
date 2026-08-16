---
id: CR-2026-042-TASK-02
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: 收敛 Skill 与人读文档
slug: converge-skills-human-docs
status: pending
estimate: 12h
depends-on:
  - CR-2026-042-TASK-01
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

收缩 CR 生命周期 Skill 的深原语实现复述和失效引用；将 README 重写为短的人读入口；在 ARCHITECTURE.md 定点声明 reviewer runner 由 Agent/runtime 在进入 Pipeline 前选择。

# 2. 涉及文件 / 模块

- `skills/requirement/write-requirement-prd/SKILL.md`、`requirement-register/SKILL.md`
- `skills/develop/write-tech-design/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-code/SKILL.md`、`write-test-report/SKILL.md`
- `skills/writeback/merge-feature-branch/SKILL.md`、`writeback-prd-sdd/SKILL.md`、`writeback-tasks/SKILL.md`、`writeback-traceability/SKILL.md`
- `skills/sync/push-progress/SKILL.md`、`skills/cr/cr-archive/SKILL.md`
- `README.md`、`ARCHITECTURE.md`

# 3. 实现要点

- Skill 保留业务前置、业务判断、一次公开深原语调用、公开结果分类、失败语义和状态前后置；删除 journal/write-set/CAS/candidate/manifest/lease/逐仓 Git/账本字段拼接；
- `write-requirement-prd` 删除 engineering-docs/MCP/owClient/`_config.yml`/validate-doc 失效引用；`inbox-emit` 与 `cr-dashboard` 的真实 SLA 输入不改；
- `review-code` 不再执行 lint/test/build；`write-test-report` 只调用一次 `crctl test --plan`；三个 writeback Skill 各只调用一次 `crctl writeback-apply`；
- README 固定保留定位、概念生命周期、Owner、8 条 Pipeline、自动评审/人工审批、checkpoint/merge/operational workspace/archive、恢复、权威事实源八类内容，不复制可执行事实；
- ARCHITECTURE.md 只补 reviewer runner 边界，硬不变量 1-7 不变。

# 4. 验收条件

1. `write-requirement-prd/SKILL.md` 中 `engineering-docs|MCP|owClient|_config.yml|validate-doc` 零命中；
2. `agents/` 与 `skills/` 中 `git add|git commit|git push` 可执行配方零命中（测试描述除外），不为 `crctl git` 设置豁免；
3. `review-code` 无 lint/test/build 第二入口，`write-test-report` 只有一次 `crctl test --plan`；
4. 三个 writeback Skill 各只有一次 `crctl writeback-apply`，且不暴露 candidate/manifest/generator 内部路径；
5. README 八类内容及权威链接齐全，无完整状态转移、节点 prompt、门禁表达式、账本字段、内部算法、完整错误矩阵、动态测试数量和默认值副本；
6. README 无 `review_llm`/reviewer 选择暂停；ARCHITECTURE.md 含 runtime reviewer 边界且硬不变量 1-7 不变。

# 5. 完成标志

上述 6 条通过；改动作为一个 tools 仓 TASK commit；随后通过 `crctl task done CR-2026-042 CR-2026-042-TASK-02` 即时登记完成。

# 6. 接口契约

- 消费：TASK-01 产出的 `{ reviewerSelection: runtime }` 和最终 Agent/Pipeline 职责。
- 产出：收敛后的 Skill interface 文本、README 八类人读入口、ARCHITECTURE reviewer 边界；TASK-03 将其作为 R10-R13、静态合同与 OpenWiki 生成源输入。
