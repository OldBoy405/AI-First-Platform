---
id: CR-2026-055-TASK-07
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "完成结构回归与发布前验证"
slug: structure-regression-validation
status: pending
estimate: 10h
depends-on: [CR-2026-055-TASK-01, CR-2026-055-TASK-02, CR-2026-055-TASK-03, CR-2026-055-TASK-04, CR-2026-055-TASK-05, CR-2026-055-TASK-06]
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

扩展现有 `pipeline-structure.test.mjs`，验证本 CR 的输入合同、资源来源、权限边界、节点/reviewLoop 不变和禁止范围，并执行 tools 侧全部发布前静态检查。

# 2. 涉及文件 / 模块

- tools worktree 的 `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`
- tools worktree 的 lint、matrix 和 Pipeline JSON 检查入口
- knowledge-base CR worktree 的变更文件清单

# 3. 实现要点

- 增加两个 reviewer Skill 的合同和 resources 约束断言。
- 增加 architecture/code reviewer prompt 的 resources 来源、feedback、attempt 断言。
- 增加 controlled-shell 权限关系和禁止范围负向断言。
- 保留 architecture 5 节点、code 16 节点、既有 replayNodes、UPSTREAM 和 maxAttempts=3。
- 执行 prompt lint、Skill matrix、结构测试、Pipeline JSON 解析和实际存在的相关回归测试；读取文本时遵守 CRLF 到 LF 规范化纪律。

# 4. 验收条件

对应 PRD AC-3、AC-7、AC-8、AC-9、AC-10、AC-11。

1. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 通过。
2. `node skills/shared/crctl/scripts/check-skill-matrix.mjs` 通过。
3. `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 通过。
4. 两个 Pipeline JSON 解析通过，相关 lint/matrix 测试按实际路径通过。
5. `git diff --check` 通过，变更文件仅为 SDD 批准的 8 个 tools 文件加本 CR 的 plan/TASK 产物；无状态机、crctl、gates、rules 或业务仓变更。

# 5. 完成标志

所有静态检查和结构回归通过，变更清单、TASK index、plan/TASK/SDD 引用一致，结果可供独立 code reviewer 复核。

# 6. 接口契约

- 消费：TASK-01 至 TASK-06 的产物、现有 Pipeline JSON、agent-skill-matrix、controlled-shell 规则和 SDD/PRD。
- 产出：结构回归测试与验证结果，供后续 `write-test-report`、`review-code` 和人工 code approval 消费；不新增运行时接口或账本格式。
