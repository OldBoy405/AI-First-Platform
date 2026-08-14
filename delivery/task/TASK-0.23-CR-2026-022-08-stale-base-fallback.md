---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-08
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2.5 — requirement-register Step 5 fetch 失败 STALE_BASE 降级（FR-14）
slug: stale-base-fallback
status: pending
estimate: 2h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-14（2.4 Step 5，CR-2026-022 注册实录坐实）：requirement-register 错误表补单仓 `fetch` 失败（如 SSL 证书）的降级路径——从本地 trunk 派生 worktree 并标注 `STALE_BASE`，不 abort 也不静默视为成功。

## 涉及文件 / 模块

- `skills/requirement/requirement-register/SKILL.md`：Step 5 错误表（约 :77-94）

## 实现要点

1. 错误表补一行：`fetch` 失败（EXEC_FAILED 之外的证书/网络类）→ 降级为「从本地 trunk 派生 worktree，并在摘要输出中标注 `STALE_BASE`」，同时保持正文"任一 active repo 创建失败不得继续写 PRD"的语义一致——STALE_BASE 不算创建失败，但必须显式提示基线滞后
2. 摘要输出格式补 `STALE_BASE` 标注示例

## 验收条件

1. SKILL 错误表含 fetch 失败降级行与 `STALE_BASE` 标注要求
2. 与正文"不得继续写 PRD"措辞无冲突（降级≠静默成功，基线滞后必须提示）

## 完成标志

验收 1~2 通过 + lint 复扫零违例。
