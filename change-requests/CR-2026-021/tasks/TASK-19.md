---
id: CR-2026-021-TASK-19
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 3 — requirement-register 全量改造（S6 预览 + S8 cr-init + S9 worktree-path + S10 commit template）
slug: phase3-requirement-register-migrate
status: pending
estimate: 5h
depends-on: ["CR-2026-021-TASK-06", "CR-2026-021-TASK-08", "CR-2026-021-TASK-09"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

P3-08/P3-10/P3-11（部分）/P3-12（部分）：`requirement-register/SKILL.md` 是本轮四个新子命令的最大单一消费者，一次性改完：
- `:48` 手算 CR-ID max+1 无 CAS → 用 `crctl next-cr-id` 预览（仅展示，非登记依据）。
- `:53-97` 手写整份 cr.md 初始 frontmatter → `crctl cr-init`（**注意 SDD 0.1.1 定案：不显式传 cr-id，cr-init 内部分配并返回**，SKILL 需按此改写调用方式，不能沿用旧设计里"先拿号再建档"的两步式）。
- `:114` 手拼 commit message → `crctl git commit --template register`。
- `:127-133` 手工拼接 worktree bucket/path → `crctl worktree-path`。

## 涉及文件 / 模块

- `skills/requirement/requirement-register/SKILL.md`

## 实现要点

**本任务最容易踩的坑**：若沿用 SDD 修复前的旧直觉（"先调 next-cr-id 拿号，再传给 cr-init 建档"），会与 TASK-06 落地的签名（`cr-init` 无 `<cr-id>` 入参）不匹配。正确流程是：直接调 `cr-init --title ... --owner-requirement ...`，从其输出读取分配到的 cr-id；`next-cr-id` 只用于 SKILL 内如需"预告下一个号"这类展示场景（若无此需求可不调用）。

## 验收条件

- AC-11（PRD，部分）+ AC-4 的消费方验证：`requirement-register` 改造后不再向 `cr-init` 传入显式 cr-id；worktree/commit message 均改调对应新命令。

## 完成标志

SKILL.md 修订完成，实测跑一次注册流程（临时 workspace）验证 cr-init 返回的 id 被正确用于后续 worktree 创建。
