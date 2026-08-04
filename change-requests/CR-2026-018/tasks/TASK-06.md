---
id: CR-2026-018-TASK-06
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: inject-cr-status.mjs 改为读 cr.md（FR-8，PRD 假设修正落地）
slug: inject-cr-status-cr-md
status: pending
estimate: 6h
depends-on: ["CR-2026-018-TASK-02"]
assignee: ""
created: "2026-08-04T16:55:00+08:00"
---

## 1. 任务描述

实现 SDD §4.4。这是 SDD §0 对 PRD 假设的修正项——PRD 原假设"适配器读取路径均经 crctl 子命令"对 `inject-cr-status.mjs`不成立：它为保持轻量、零依赖，直接行扫 `_backlog.yml` 的 `status:` 行（:46-47）。cr.md 成为权威后必须改造，否则所有 CR 会被注入成 `status='?'`。

改造保持其"轻量、零依赖、失败静默放行"的既有定位：行扫 `_backlog.yml` 只取 `id` 清单；逐 id 读 `change-requests/{id}/cr.md` 前 60 行扫 frontmatter `status:` 行（复用其现有退化扫描风格，不引入 YAML parser 依赖）；cr.md 读不到时回退 backlog 行值（兼容旧布局）。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs`

## 3. 实现要点

- 不得引入新依赖（该 hook 明确"不依赖 crctl 主程序"，保持启动开销最小）。
- 注入文案中的数据源说明从"`_backlog.yml` 的实时状态"改为"cr.md 的实时状态"。
- 失败静默放行原则不变：单个 CR 的 cr.md 读取异常不应导致整个 hook 崩溃，跳过该条目继续处理其余 CR。

## 4. 验收条件

- 构造新布局 workspace（backlog 无 status，cr.md 有 status）：hook 输出正确状态列表。
- 构造旧布局 workspace（backlog 有 status，cr.md 也有）：hook 优先输出 cr.md 值。
- 构造某 CR 的 cr.md 损坏（无 frontmatter）：hook 跳过该条目，不崩溃，其余 CR 正常输出。

## 5. 完成标志

hook 改造完成，三种场景验收通过；未引入新依赖；lint 零报错（若该目录有独立 lint 配置）。
