---
id: CR-2026-002-TASK-01
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: rules.json 白名单单一事实源抽取（crctl/hooks 改读）
status: done
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

## 完成记录（2026-07-31）

- **提交**：tools@af7c2ec（custom/main，已推 origin）。
- **rules.json**：19 条 git 三元组（含 commit/merge 的 `s` 旗标以 `{re, flags}` 对象承载）+ 6 个 forbiddenFlags + protectedPaths（deny×6 / ask×3，来自 pretooluse-guard 原内联正则），全部机械迁移，零语义变更。
- **crctl.mjs**：删除 GIT_WHITELIST/GIT_FORBIDDEN_FLAGS 内联表（grep 确认无残留）；`loadShellRules()` 带缓存加载，支持 `CRCTL_RULES_PATH` env 覆盖（测试用）；缺失/损坏 → `SHELL_UNAVAILABLE` 结构化错误，**fail-closed 不放行**。
- **pretooluse-guard.mjs**：DENY/ASK 常量改读 rules.json#protectedPaths；加载失败时写类操作降级为 `ask`（人工确认，不静默放开）。
- **SKILL.md**：v0.2.0——白名单表降级为解说，声明 rules.json 为唯一事实源；修正 v0.1.0"自称 15 条实际 19 条"的漂移；新增诚实边界段（PATH shim 可绕过，4/5 层兜底）。
- **测试**：11/11 通过（8 既有回归 + 3 新增：缺失→SHELL_UNAVAILABLE、损坏 JSON→SHELL_UNAVAILABLE、加载后禁子命令/禁旗标/形态不匹配语义与原表一致）。验收条件 1/2/3 全满足。
- **备注**：SKILL.md 上有一行本 CR 之前的待提交修改（IDE 适配器行文案，与本任务方向一致）随本提交入库。tools 仓另有一批与本任务无关的未提交改动（openwiki/ 等），未动。
- **消费方进度**：crctl ✅ / hooks ✅ / multica pkg/gitguard → TASK-09。
