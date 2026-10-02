---
spec-id: ai-first-platform
version: "0.47"
id: CR-2026-074-TASK-07
type: TASK
cr-ref: CR-2026-074
plan-ref: "change-requests/CR-2026-074/plan.md"
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
title: rules.json 裸提交 shape + controlled-shell SKILL 同步
slug: merge-base-bare-sha-shape
status: pending
estimate: 1h
depends-on: [CR-2026-074-TASK-01]
created: 2026-10-01T00:55:00+08:00
---

## 任务描述

为 controlled-shell 的 `git merge-base` 追加裸提交对祖先判定 shape，并同步 Skill 能力表（SDD §4.6；FR-9；AC-10），供 Agent 直接做两个提交间的祖先判定。

## 涉及文件 / 模块

- `skills/shared/controlled-shell/rules.json` — `git[sub=merge-base].shapes` 追加一条（dep-13：现状仅允许 origin/trunk 对 HEAD 与 is-ancestor 对 origin/ref 两种形态，裸提交对不在 shape 中）。
- `skills/shared/controlled-shell/SKILL.md` — 命令白名单表 merge-base 行同步（dep-22：该行文档与 rules.json 是不同事实源，需随 shape 同步）。
- `skills/shared/crctl/scripts/test/crctl.test.mjs` — 受控入口真实 Git fixture 用例（与 TASK-01 同测试文件，顺序编辑）。

## 实现要点

- 仅追加 shape `^--is-ancestor [0-9a-f]{7,40} [0-9a-f]{7,40}$`；不改 callers、forbiddenFlags、protectedPaths、其余命令；保留既有两条 shape（`^origin/\S+ HEAD$` 与 `^--is-ancestor \S+ origin/\S+$`）。
- Git exit=0/1 分别表示祖先/非祖先；exit=1 不是 FORBIDDEN_SUBCOMMAND。无效对象可通过 shape 但仍由 Git 自身拒绝，不假报 ancestor。
- SKILL.md 能力表 merge-base 行同步为三 shape 并强调 Git exit 语义；不扩展 protectedPaths。

## 验收条件

1. 在 tools CR worktree 执行 `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`（证据 cmd-01）全绿，且 AC-10 断言覆盖：7 位与 40 位裸提交对通过 shape，真实可解析提交对象 exit=0（祖先）/exit=1（非祖先）原语义；非法形态 FORBIDDEN_SUBCOMMAND，且拒绝样例同时不匹配旧两条 shape。
2. 两条旧 shape 单独回归通过（origin/trunk 对 HEAD、is-ancestor 对 origin/ref），不把旧放行误判回归。

## 完成标志

- cmd-01 全绿含 AC-10 断言；`rules.json` 的 merge-base shapes 恰多一条，其余元素逐字不变。
- `skills/shared/controlled-shell/SKILL.md` merge-base 行与 `rules.json` 三 shape 一致（两事实源同步）；TASK-09 不再改该行。

## 接口契约

**消费**：dep-13 `git[sub=merge-base].shapes` 数组（追加尾部，不改既有元素/callers/forbiddenFlags/protectedPaths）；dep-22 SKILL.md merge-base 行现状。

**产出**：受控放行形态 `git merge-base --is-ancestor <bare-sha> <bare-sha>`（7~40 位十六进制裸提交对）；exit 语义 0=祖先、1=非祖先（1 不是 FORBIDDEN_SUBCOMMAND）。下游消费方 TASK-09（说明同步时引用本行已同步事实）与 TASK-01 的 crctl.test.mjs 编辑基线（顺序编辑）。
