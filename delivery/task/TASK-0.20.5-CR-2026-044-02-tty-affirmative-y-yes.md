---
spec-id: ai-first-platform
version: "0.20.5"
id: CR-2026-044-TASK-02
type: TASK
cr-ref: CR-2026-044
plan-ref: "change-requests/CR-2026-044/plan.md"
sdd-ref: "change-requests/CR-2026-044/sdd.md"
title: TTY affirmative 扩展与 prompt 更新
slug: tty-affirmative-y-yes
status: pending
estimate: 2h
depends-on: [CR-2026-044-TASK-01]
created: 2026-08-17T00:02:54+08:00
---

# TASK-02 TTY affirmative 扩展与 prompt 更新

## 1. 任务描述

在 `cmdApprove` 共享 TTY 分支把批准判断从 `answer.trim().toLowerCase() !== 'yes'` 改为 `['y', 'yes'].includes(answer.trim().toLowerCase())`，同步更新 prompt 文案，四个审批 stage（requirement/tech-design/dev-start/code）经共享入口同时生效。对应 PRD FR-09、AC-16、AC-17（SDD §6.5）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（`cmdApprove` 一处判断 + 一行 prompt）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（TASK-01 TTY 红测试转绿 + 回归补充）

## 3. 实现要点

- 只改 `rl.question(...)` 回调内一行判断与 prompt 字符串：`以 approver=${approver} 批准该阶段？只有输入 y 或 yes 才会写入 approval.yml [y/N] `。
- 不新增 `isAffirmative` helper、配置或输入字典；`rl.close()`、auditLog、`REJECT_ROLLBACK`、`performAdvance`、`APPROVAL_DECLINED_ROLLED_BACK`、`approveAndAdvance` 调用位置与参数不变。
- TTY 检查（`process.stdin.isTTY`）、grant 分支（`flags.grant`）、`--resign` 分支、`stageCfg.expect` 校验顺序不变。
- 参数化覆盖：`Y`、`y`、`yes`、`YES`、`YeS`、`  y  `（带空白）批准；``（空）、`n`、`N`、`no`、`其他文本` 走既有 reject 回退。

## 4. 验收条件

1. TASK-01 的 TTY 红测试组全部转绿：四个 stage 对 `y/Y/yes/YES/YeS` 与带空白输入进入批准事务并写 approval.yml。
2. 空输入与 `n/N/no/其他` 仍产生 `APPROVAL_DECLINED_ROLLED_BACK` 且状态回退到该 stage 的 `REJECT_ROLLBACK.to`。
3. 非 TTY 无 grant 仍返回 `APPROVAL_REQUIRES_HUMAN`；grant approve/reject 与 `--resign` 既有测试不回归。

## 5. 完成标志

`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿 + 改动仅 `cmdApprove` 两行。

## 6. 接口契约

- 消费：TASK-01 产出的 TTY 红测试集合。
- 产出：无新增导出；`cmdApprove(ws, cr, gates, flags)` 行为扩展（正向判断集合 `{y, yes}`，trim + 大小写不敏感）。
