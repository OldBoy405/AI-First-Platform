---
id: CR-2026-029-TASK-02
type: TASK
cr-ref: CR-2026-029
plan-ref: "change-requests/CR-2026-029/plan.md"
sdd-ref: "change-requests/CR-2026-029/sdd.md"
title: feature-writeback pipeline prompt 同步联调走查
slug: pipeline-prompt-sync
status: pending
estimate: 1h
depends-on: [CR-2026-029-TASK-01]
created: "2026-08-10T20:14:00+08:00"
---

# TASK-02 feature-writeback pipeline prompt 同步

## 1. 任务描述

`pipeline-templates/feature-writeback.pipeline.json` 的 merge-feature-branch 节点 prompt 增加发布联调走查描述（与 SKILL Step 6 一致）：状态推进与 merge-metadata 发布后执行走查、写 merge-verification.md、提交 trunk。

## 2. 涉及文件

- tools：`pipeline-templates/feature-writeback.pipeline.json`

## 3. 实现要点

- 只改 merge-feature-branch 节点 prompt，不改节点结构/onFail/timeout。
- prompt 文本与 SKILL Step 6 术语一致（status/worktree-path/next、CUSTOM 台账、merge-verification.md）。

## 4. 验收条件

1. JSON 可解析；
2. prompt 含联调走查与 merge-verification 产出；
3. 无其他节点变更。

## 5. 接口契约

- **消费**：TASK-01 的步骤定义。
- **产出**：无新 API。
