---
id: CR-2026-028-TASK-10
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: 发布与联调（M8）
slug: release-and-integration
status: pending
estimate: 4h
depends-on: [CR-2026-028-TASK-09]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-10 发布与联调

## 1. 任务描述

按 plan.md §5 发布顺序执行：tools 仓 `requirement/CR-2026-028` merge → main；knowledge-base 仓 merge；真实 worktree 场景全流程走查（注册 → 需求 → 技术设计 → 任务拆分路径的 crctl 调用）。过渡风险按 R6 缓解。

## 2. 涉及文件 / 模块

- tools 仓：merge 提交
- knowledge-base 仓：merge 提交（AGENTS.md/ADR/分析文档/PRD/SDD/plan/tasks 回写基线随 writeback 流程，不在本 TASK）
- multica 仓：无代码改动，仅随下个 rebase 周期核对台账

## 3. 实现要点

- 发布顺序：tools 先行（新 crctl 语义生效），再 knowledge-base；避免旧 checkout 在新 config 下失配（plan R6）。
- 联调走查：linked worktree 下 `crctl status`/`worktree-path`/`push-progress` 消费；多仓 `--workspace` 显式传入场景。
- 走查发现问题按纪律回写（SDD 修订走 review-tech-design 链路；不手改评审记录）。

## 4. 验收条件

1. 双仓 merge 成功，无冲突残留；tools 主 checkout 上 `crctl status --workspace <主checkout>` 输出正常。
2. 真实 worktree 走查：从 knowledge-base linked worktree 调用 status/worktree-path/next 全链路无 `STATUS_DIVERGED`/嵌套路径异常。
3. multica CUSTOM.md 台账条目与 merge 后实际代码一致（无代码改动，一致性天然成立）。

## 5. 完成标志

双仓 merge + 走查通过 + 本 CR 进入 writeback 阶段。

## 6. 接口契约

- **消费**：TASK-09 全绿结论；全部既有签名。
- **产出**：无新 API；发布后的 Tools Root 语义成为全仓默认。
