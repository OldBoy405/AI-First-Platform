---
spec-id: ai-first-platform
version: "0.29"
id: CR-2026-056-TASK-12
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M7 评审与发布（code review / 审批 / 合并 / writeback）
slug: m7-review-and-release
status: pending
estimate: 8h
depends-on: [CR-2026-056-TASK-11]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

流程收尾：独立 code review、人工 code approval、统一 checkpoint、合并、writeback、archive。对应 plan.md M7（1.0 人天）。本 TASK 为流程任务，执行者为 `quality-reviewer-agent`（独立评审）与人工（审批/确认），按既有 Pipeline 与 `crctl` 状态机推进；不新增代码（评审发现的问题回 `implement-code` 自修复，计入既有 TASK 的修复轮次）。

输入条件：TASK-11 完成（三域测试全绿、`test-report.md` pass、`CUSTOM.md` 登记完成）。

## 涉及文件 / 模块

- knowledge-base CR worktree：`review-annotations/code.yml`（`crctl review-record` 落盘）、`approval.yml`（`crctl approve` 落盘）、`_backlog.yml` / `cr.md`（`crctl advance` 推进）
- multica CR worktree：合并前最终代码状态
- `specs/` / `delivery/`（writeback skill 产物，需人工确认）

## 实现要点

1. **独立 code review**（`review-code` skill）：读代码 diff、验证日志、`sdd.md`、`tasks/*`、`test-report.md`；blocker 非零则回 `implement-code` 自修复后复评；通过后推进 `code-reviewing`。
2. **统一 `crctl checkpoint`**：各资源 CR worktree 进度一并提交推送（含 multica 代码与 knowledge-base 账本）。
3. **人工 code approval**：仅人工在交互式终端执行 `crctl approve CR-2026-056 --stage code`（或平台审批落 grant 后经 `--grant` 消费）；推进 `code-approved`。
4. **合并**：`code-approved` 后合并 multica CR worktree 分支（发布顺序见 plan §6：无 feature flag，一次性生效；回滚按 down 文件逆序 + commit 粒度，不留半启用状态）。
5. **writeback 与 archive**：`feature-writeback` pipeline（`specs/` 累积文档、`delivery/` 任务索引，脚本化回写），人工确认后归档。

## 验收条件

1. code review blocker 清零（`review-annotations/code.yml` 通过记录在案）。
2. `crctl approve --stage code` 通过，状态推进 `code-approved`（账本由 `crctl` 写，无手改）。
3. 合并完成；writeback 产物（`specs/` / `delivery/`）落盘且人工确认；CR archive。

## 完成标志

CR 归档（`archived`），writeback 产物提交。

## 接口契约

- 消费：TASK-11 的 `test-report.md`、`CUSTOM.md` 登记、全量代码与测试证据。
- 产出：`review-annotations/code.yml` 结论、`approval.yml` code 审批记录、合并后的主干代码、`specs/` / `delivery/` 回写产物。
