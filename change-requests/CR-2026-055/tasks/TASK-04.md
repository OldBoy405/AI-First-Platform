---
id: CR-2026-055-TASK-04
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "补齐 reviewer 只读取证合同"
slug: reviewer-readonly-evidence
status: pending
estimate: 5h
depends-on: [CR-2026-055-TASK-01, CR-2026-055-TASK-02]
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

更新 `controlled-shell/SKILL.md`，将两个 reviewer 的代码事实核验纳入既有只读取证合同，明确文件读取与只读 Git 命令边界，不扩展白名单。

# 2. 涉及文件 / 模块

- tools worktree 的 `skills/shared/controlled-shell/SKILL.md`
- SDD §3.3、§7.1

# 3. 实现要点

- 声明 `review-tech-design` 和 `review-dev-plan` 可调用既有只读取证能力。
- 允许原生文件读取以及既有 `crctl git` 的 `rev-parse`、必要的 `diff`、`log`、`merge-base`。
- 明确禁止任意 shell、commit、add、push、merge、approve、advance 和账本写入。
- 不修改 `rules.json`、Git 子命令、参数形态或 protected paths。

# 4. 验收条件

对应 PRD AC-8。

1. controlled-shell 文档明确两个 reviewer 的只读取证调用者身份和允许能力。
2. 文档明确禁止范围，且不包含人工终端回退指引。
3. `rules.json` 无变更，现有受控 Git 规则保持不变。

# 5. 完成标志

`controlled-shell/SKILL.md` 更新完成，matrix 和结构检查可确认 reviewer 只读授权边界。

# 6. 接口契约

- 消费：现有 `controlled-shell/rules.json` 和 TASK-01/TASK-02 的事实核验需求。
- 产出：reviewer 只读取证文档合同，供 TASK-05 与 TASK-07 消费；不新增命令接口。
