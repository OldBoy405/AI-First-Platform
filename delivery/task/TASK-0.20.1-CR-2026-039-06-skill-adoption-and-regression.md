---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-039-TASK-06
type: TASK
cr-ref: CR-2026-039
plan-ref: "change-requests/CR-2026-039/plan.md"
sdd-ref: "change-requests/CR-2026-039/sdd.md"
title: Skill 采纳修订与双平台全量回归
slug: skill-adoption-and-regression
status: pending
estimate: 2h
depends-on: [CR-2026-039-TASK-01, CR-2026-039-TASK-02, CR-2026-039-TASK-03, CR-2026-039-TASK-04, CR-2026-039-TASK-05]
created: 2026-08-15T01:31:31+08:00
---

# 任务描述

按 SDD §8 完成既有命令行为变化的 Skill 采纳修订，并执行 Ubuntu/Windows 双平台全量回归，固化本 CR 的测试基线（供后续 crctl test canonical 记录引用）。

# 涉及文件 / 模块

- `skills/shared/crctl/SKILL.md`（review-record 行）
- `skills/develop/review-dev-plan/SKILL.md`（PASS 语义）
- 全量测试套件：`skills/shared/crctl/scripts/test/*.test.mjs`（含 TASK-04/05 新增的 pipeline-structure、contract-scan 测试文件）

# 实现要点（SDD §8、§9.1）

- crctl SKILL.md review-record 行补注：dev-plan 阶段写 plan+TASK composite digest（全部 `TASK-*.md`，canonical JSON entries）；`crctl next` 与 developing 门禁消费 PASS 前重算，漂移/legacy/subject 不完整一律保守路由或阻断。
- review-dev-plan SKILL.md 补注：PASS 绑定 plan+TASK subject digest，正文修订后旧 PASS 自动失效（next 建议重审、approve-dev-start 硬失败）。
- `push-progress SKILL.md` 不改（code Pipeline 新节点只是多一个调用方，契约不变）。
- 全量回归：`node --test skills/shared/crctl/scripts/test/` 全部测试文件；记录测试总数与通过数作为 canonical 测试证据（测试执行本体在开发期按当时流程进行，本 TASK 只要求结果记录进 test-report 证据链）。

# 验收条件

1. crctl SKILL.md 与 review-dev-plan SKILL.md 修订内容与实现行为逐句一致（digest 口径、消费点、失败语义）；不新增实现承诺。
2. 全量测试在本地平台通过（0 失败），测试计数记录在案；CI 双平台验证以合入前 workflow 结果为准。
3. SDD §9.2 用例矩阵逐行映射到既有测试文件与用例名，无遗漏行（在 node 输出中列映射表）。

# 完成标志

两处 SKILL 修订提交 + 全量回归通过记录；提交为一个可回滚 commit。

# 接口契约

- 消费：TASK-01～TASK-05 的全部产出（digest helper/双消费点/updated writer/pipeline 节点/文本收敛）；行为描述以合入时实际代码为唯一事实源，本 TASK 不得反向修改实现。
- 产出：修订后的两个 SKILL.md + 回归测试证据（测试计数、平台、运行命令）。
