---
id: CR-2026-054-TASK-08
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "完成三域集成验证与 AC 证据映射"
slug: integration-acceptance-evidence
status: pending
estimate: 10h
depends-on: [CR-2026-054-TASK-03, CR-2026-054-TASK-04, CR-2026-054-TASK-07]
created: 2026-08-29T18:32:00+08:00
---

# 1. 任务描述

承接计划 M0/M4 的基线、集成验证和证据映射工作，确认 tools archive、Agent 执行边界和 multica daemon 补投三个业务域均完成实现、测试、范围检查和 PRD AC-1~AC-7 证据关联。

# 2. 涉及文件 / 模块

- 当前 CR worktree 的 `change-requests/CR-2026-054/plan.md`、`sdd.md`、`prd.md`、`tasks/`
- `tools` worktree 的 archive 测试、Agent/Skill/README diff 和真实账本只读验证入口
- `multica` worktree 的 Go 测试、daemon diff 和 `CUSTOM.md`
- 既有 `write-test-report`、`traceability.yml` 和 `review-code` 证据入口

# 3. 实现要点

- 开始时重新执行 `crctl workspace inspect CR-2026-054`，只消费返回的 operationalWorkspace 和 resources；任一 resource 非 healthy 或路径为空时停止并报告环境问题。
- 使用各仓库既有测试入口验证 TASK-01~07 产出；对真实 workspace 的 backlog、history、index 执行一次只读 strict 解析，不写账本。
- 对照 SDD §4.3 将三域实现和测试分别映射到 AC-1~AC-7，检查 plan/TASK/SDD/PRD 链接、TASK index 一致性、CUSTOM.md 和 FR-18 最小 diff。
- 通过既有 `write-test-report` 记录命令、日志、摘要和未覆盖风险；不手工写 test-report、traceability 或状态字段。
- 生成前置于 code review 的结构化证据清单，确保缺少任一域证据时沿既有 reviewLoop 进入 blocker。

# 4. 验收条件

对应 PRD 验收标准：AC-1、AC-2、AC-3、AC-4、AC-5、AC-6、AC-7。

1. `crctl workspace inspect` 返回全部 resources `healthy`，且实际使用其 operationalWorkspace；异常时不继续验证或修改账本。
2. tools、文档和 multica 三域既有测试入口均执行并有可归因结果；真实 backlog/history/index 只读 strict 验证通过。
3. AC-1~AC-7 每条均指向至少一个实现/测试/审查证据，且 checklist 明确 archive hash 前校验、Agent 环境边界、daemon 日志脱敏和 FR-18 最小 diff。
4. `write-test-report` 为 pass，TASK index 与 TASK 卡一致，未引入 Pipeline、状态、账本、权限矩阵、共享服务管理或 feature flag。

# 5. 完成标志

三域测试和只读账本验证完成，AC-1~AC-7 证据映射完整，`write-test-report` 通过，所有待提交证据可由独立 code reviewer 复核。

# 6. 接口契约

- 消费：TASK-03 的 tools 测试证据、TASK-04 的文档契约、TASK-07 的 multica 测试与 CUSTOM.md；`crctl workspace inspect`、既有测试入口、`write-test-report` 和 SDD §4.3。
- 产出：三域集成验证结果、AC-1~AC-7 证据映射和发布前 checklist，供 code review、code approval、writeback 和 archive 门禁消费；不新增运行时接口或账本格式。
