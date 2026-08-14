---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-08
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 执行全量验证与修改白名单审计
slug: full-verification-audit
status: pending
estimate: 4h
depends-on: [CR-2026-030-TASK-06, CR-2026-030-TASK-07]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-08 执行全量验证与修改白名单审计

## 1. 任务描述

按 SDD §7.4～§7.5 对 TASK-01～07 的实际实现执行 AC-1～AC-32 集成验收，记录命令、目录、退出码、测试数、未覆盖风险和 changed-files 审计结果，作为后续 `write-test-report` 的权威输入。此 TASK 不增加功能或绕过失败测试。

## 2. 涉及文件 / 模块

- tools：TASK-01～06 产生的白名单文件（只读验证）
- Multica：TASK-07 产生的两个白名单文件（只读验证）
- knowledge-base：`change-requests/CR-2026-030/test-report.md`（由后续 `write-test-report` Skill 受控生成）

## 3. 实现要点

- 执行 PRD AC-32 六条命令，记录实际测试数量；不得以删除既有测试换绿。
- 显式 `CRCTL_PATH` 执行 Multica 定向跨接缝，并检查 verbose 输出无 skip。
- 对 tools、Multica、knowledge-base 三个 worktree 分别取得 changed-files，与 FR-10.1 精确集合比较。
- 检查 Multica production、CI workflow、`pipeline-templates/_index.yml` 零 diff，四个 Pipeline 节点数不变。
- 检查每个已实现 TASK 已即时标记 `done`，接口签名与依赖消费一致。

## 4. 验收条件

1. lint-prompts、Skill matrix、Agent contract、全部 crctl Node 测试、writeback 测试和 Pipeline JSON parse 均退出 0。
2. Multica grant 跨接缝定向测试通过且无 skip。
3. changed-files 全部在 FR-10.1 白名单；Multica production 与 CI workflow 零 diff。
4. AC-1～AC-32 均能映射到可复现的命令或测试名称；任何失败均阻止 test-report 标 pass。

## 5. 完成标志

全部必跑验证通过，白名单审计无越界，验证证据可供 `write-test-report` 直接消费，`tasks/_index.yml` 中 TASK-08 标记 `done`。

## 6. 接口契约

- **消费**：TASK-06 的 tools 完整产物、TASK-07 的 Multica test-only 产物、SDD AC-1～AC-32。
- **产出**：验证命令与结果证据，供 `write-test-report` 生成 `test-report.md`；不负责状态推进、人工审批或 merge。
