---
spec-id: ai-first-platform
version: "0.45"
id: CR-2026-072-TASK-05
type: TASK
cr-ref: CR-2026-072
plan-ref: "change-requests/CR-2026-072/plan.md"
sdd-ref: "change-requests/CR-2026-072/sdd.md"
target-version: 0.45
title: 全量回归与证据：四类测试、调用点清单、同批交付核验
slug: regression-evidence-checklist
status: pending
estimate: 4h
depends-on: ["CR-2026-072-TASK-01", "CR-2026-072-TASK-02", "CR-2026-072-TASK-03", "CR-2026-072-TASK-04"]
created: 2026-09-28T23:52:00+08:00
---

## 1. 任务描述

在 TASK-01～04 全部完成后，于对应 CR worktree 运行 plan.md 证据命令表四条命令（cmd-01～cmd-04），将真实结果经 `crctl test --plan <cr-test-plan/v1>` 落盘 `test-report.md` 机器区与 `test-evidence/cmd-NN.log`；汇总 TASK-01 的受影响调用点清单为最终版（覆盖四 Agent Prompt、共享 crctl 合同、Pipeline 模板、Skill/脚本、push-progress、注入 hook、README 及扫描面外 CI/workflow，逐项标注迁移结果）；核验 CLI 强校验与 daemon 行为在同一交付批次内（调用方先迁移、强校验后启用，无单独上线的破坏性 CLI 改动）。

## 2. 涉及文件 / 模块

- `change-requests/CR-2026-072/test-report.md`（机器区，由 `crctl test` 原子发布）
- `change-requests/CR-2026-072/test-evidence/cmd-01.log` ～ `cmd-04.log`
- `change-requests/CR-2026-072/review-loop.yml` / `traceability.yml#tests`（由 `crctl test` 同批投影写入，不手工编辑）
- 证据命令（算法唯一事实源 = plan.md 证据命令表，此处只引用）：
  - cmd-01：tools 仓 `skills/shared/crctl/scripts`，`node --test test/crctl.test.mjs`
  - cmd-02：tools 仓同 cwd，`node --test test/caller-contract.test.mjs`
  - cmd-03：tools 仓同 cwd，`node lint-prompts.mjs --mode enforce`
  - cmd-04：multica 仓 `server`，`go test ./...`

## 3. 实现要点

- SDD §4.5 回归矩阵核对：A/B 同名 CR 隔离（cmd-01 用例）、多根歧义、Pipeline/普通任务带/不带绑定、operational env 错配、gitguard 拒绝及有/无归属审计（cmd-04 用例）。
- 测试计划 JSON 形态遵循 `crctl test --plan` 既有 `cr-test-plan/v1` schema（`spawnSync(executable, args, {shell:false})`）；业务 non-zero/timeout 记 `status=block`，schema/技术错误非零退出。
- 四条命令 cwd 相对各仓 CR worktree 根，与 plan.md 稳定表逐字一致，不改写命令算法。

## 4. 验收条件

1. cmd-01～cmd-04 四条命令在对应 CR worktree 实际运行，`test-report.md` 机器区 `commands` 四条全 pass（或明确 block 记录与原因），`test-evidence/cmd-NN.log` 与之一一对应。
2. 受影响调用点清单终版交付：覆盖 FR-1 全部清点面，逐项含文件路径、命令形态、是否扫描面外、迁移结果；可执行 CR 数据命令显式 workspace 覆盖率 100%。
3. `crctl next CR-2026-072` 不再返回 dev-plan 侧 blocker（评审入口就绪）。

## 5. 完成标志

四类测试真实结果 + 最终调用点清单落盘（`crctl test` 发布的机器区为准）；同批交付核验记录（调用方迁移 commit 先于 CLI 强校验 commit 的批次顺序）写入测试报告证据部分。

## 6. 接口契约

- **消费**：
  - TASK-01：caller-contract 断言清单 + 调用点清单草稿（终版化的唯一输入）。
  - TASK-02：`WORKSPACE_REQUIRED`/`WORKSPACE_NOT_FOUND` 错误契约与 `authorityWorkspace` 失败关闭语义（cmd-01 断言面）。
  - TASK-03：`CRCTL_TASK_AUDIT_ROOT` 注入契约与删除首根回退后的 agentEnv 形态（cmd-04 断言面）。
  - TASK-04：gitguard 审计归属契约（cmd-04 断言面）。
- **产出**：`test-report.md` 机器区 + `test-evidence/cmd-01..04.log` + 最终调用点清单 —— 供 `review-code`、`write-test-report` 与代码人工审批消费的证据面。
