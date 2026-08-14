---
id: CR-2026-037-TASK-03
type: TASK
cr-ref: CR-2026-037
plan-ref: CR-2026-037-plan
sdd-ref: CR-2026-037-sdd
title: 执行回归范围审计与发布恢复准备
status: pending
estimate: 3h
depends-on: [CR-2026-037-TASK-02]
owner: Ray
created: "2026-08-13T10:42:00+08:00"
updated: "2026-08-13T10:42:00+08:00"
---

# TASK-03：执行回归、范围审计与发布恢复准备

## 目标

执行完整工具链验证，证明 task-init 闭环没有破坏 task done、评审/审批或 Prompt 契约；冻结合入后恢复 CR-2026-032 的权威命令，不在候选工具上提前操作该 CR。

## 依赖

- CR-2026-037-TASK-02 已完成，代码、gate 和消费者采纳齐备。

## 实施步骤

1. 运行 crctl 定向与全量测试、Prompt lint、Skill/Agent contract 测试及 Pipeline JSON 解析。
2. 复跑 task done、review-dev-plan、dev-start gate/approval 相关测试。
3. 执行 changed-files 审计，确认只含 SDD 白名单；检查 Multica 三类 diff 全为零。
4. 记录 AC-01～AC-11 证据与剩余发布后 AC-12。
5. 核验但不执行 CR-2026-032 恢复命令：必须从合入后的权威 Tools Root 调 task init，再提交、advance、review。
6. 若验证发现问题，只做满足当前 FR 的最小根因修复并重跑相关测试。

## 产出

- 通过的测试/静态契约结果；
- test-report 所需可追溯证据；
- 合入后 CR-2026-032 恢复步骤。

## 验收标准

- [ ] task-init 全部定向测试通过，无 skip/placeholder。
- [ ] crctl 全量测试通过，现有 task done 与状态/gate 行为无回归。
- [ ] `lint-prompts --mode enforce`、Skill/Agent contract 和 Pipeline JSON parse 通过。
- [ ] tools changed-files 仅为 SDD 六个白名单文件；knowledge-base 仅 CR 证据；Multica 零 diff。
- [ ] 无 README、Agent/matrix、状态机、generic schema/validate、事务模块或依赖变更。
- [ ] AC-01～AC-11 有可复跑命令；AC-12 明确标为合入后发布验收，不伪造提前完成。
- [ ] CR-2026-032 恢复步骤使用权威 Tools Root，未调用候选 worktree crctl。

## 发布后步骤

修复合入 tools `custom/main` 后，在 CR-2026-032 权威 worktree执行：正式 `task init` → controlled Git 提交 → advance task-breakdown → review-dev-plan。该步骤完成 PRD AC-12。
