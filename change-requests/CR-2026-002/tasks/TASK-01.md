---
id: CR-2026-002-TASK-01
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: rules.json 白名单单一事实源抽取（crctl/hooks 改读）
status: pending
estimate: 8h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
把 controlled-shell 白名单从 crctl.mjs 硬编码表（:327–347 一带，实际 19 条）抽成 `skills/shared/controlled-shell/rules.json`（schema 见 SDD §2.2 / 源方案 §C.2：git 三元组 + forbiddenFlags + protectedPaths），消除 SKILL.md（自称 15 条）与代码的漂移。仓库：tools。

## 涉及文件
- 新增 `skills/shared/controlled-shell/rules.json`
- 修改 `skills/shared/crctl/scripts/crctl.mjs`（删硬编码表，启动时加载 rules.json；加载失败给结构化错误）
- 修改 Claude Code 适配器 `pretooluse-guard.mjs`（protectedPaths 改读 rules.json）
- 修改 `skills/shared/controlled-shell/SKILL.md`（降级为对 rules.json 的解说，含 PATH shim 可绕过的诚实边界）

## 实现要点
- 19 条规则从现表**机械迁移**，本任务不增删规则语义（语义变更留给后续 CR）。
- rules.json 位置相对 crctl.mjs 稳定（同包内），零依赖解析（JSON.parse 即可）。

## 验收条件
1. crctl 8 个既有测试全通过（AC-5⑤）。
2. 新增测试：rules.json 删除/损坏时 crctl git 返回结构化错误而非崩溃。
3. `git diff` 确认 crctl.mjs 中不再存在内联三元组表。

## 完成标志
tools 测试全绿 + pre-commit/CI 检查通过 + 完成记录回填。
