---
id: CR-2026-018-TASK-01
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: 新增 resolveCrState，收敛 5 处状态读取点（FR-2）
slug: resolve-cr-state
status: pending
estimate: 12h
depends-on: []
assignee: ""
created: "2026-08-04T16:30:00+08:00"
---

## 1. 任务描述

在 `crctl.mjs` 新增 `resolveCrState(ws, cr)` 函数，实现 SDD §4.1 的算法：优先读 `cr.md` frontmatter status，缺失时回退读 `_backlog.yml` 条目（迁移期兼容读，FR-2），并输出混版检测告警（`MIXED_LAYOUT_WARN`，SDD §3.1/§3.2）。将现有 5 处直接调用 `loadBacklogEntry(...).entry.status` 的读取点改为经由 `resolveCrState`。

背景：这是 T1-full 的读路径基础设施，后续 TASK-02（advance 单写）依赖本任务的读路径先行落地，保证切换写路径时读路径已能正确处理"cr.md 有值/无值"两种情况。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/crctl.mjs`：新增 `resolveCrState`、`readCrMdFrontmatter`；改造 `cmdStatus`（:766）、`cmdAdvance`（:800）、`cmdApprove`（:857 及 :919 级联读）、`cmdNext`（:1140）共 5 处
- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`：新增用例（见验收条件）

## 3. 实现要点

- `readCrMdFrontmatter` 遵守纪律 #1：读入先 `\r\n → \n` 规范化，frontmatter 正则解析失败必须硬失败，不得静默返回 null 当作"无 status"处理（区分"文件损坏"与"字段不存在"两种情况）。
- `resolveCrState` 返回结构：`{ snap, status, statusSource: 'cr.md' | '_backlog.yml', legacySource?: true, warnings?: ['MIXED_LAYOUT_WARN'] }`。
- 冲突裁决：cr.md 与 backlog 都有 status 且不一致时，cr.md 值胜出，同时置 `MIXED_LAYOUT_WARN`（不视为错误，只读命令不因此非零退出）。
- 本任务**不改**写路径（`updateBacklogStatus` 仍在，advance 仍双写）——TASK-02 才处理写路径切换，保持任务粒度单一。

## 4. 验收条件

- 新增单元测试：cr.md 有 status、backlog 无 status（纯 v2）→ 返回 cr.md 值，无告警。
- 新增单元测试：cr.md 无 status、backlog 有 status（纯 v1）→ 返回 backlog 值，`legacySource: true`。
- 新增单元测试：cr.md 与 backlog 均有 status 且不一致（混版）→ 返回 cr.md 值，`warnings` 含 `MIXED_LAYOUT_WARN`。
- 现有 21 个用例全绿（回归线不破）。

## 5. 完成标志

`resolveCrState` 落地且 5 处读取点全部改调；新增 3 个单元测试通过；`node scripts/test/crctl.test.mjs`（或等价测试命令）全绿；lint 零报错。
