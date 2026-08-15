---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-039-TASK-01
type: TASK
cr-ref: CR-2026-039
plan-ref: "change-requests/CR-2026-039/plan.md"
sdd-ref: "change-requests/CR-2026-039/sdd.md"
title: dev-plan composite digest helper 与 review-record 写入
slug: dev-plan-composite-digest-writer
status: pending
estimate: 4h
depends-on: []
created: 2026-08-15T01:31:31+08:00
---

# 任务描述

前置：tools CR worktree 先合入最新 `origin/custom/main`（`162fdf0`）：分支无自身提交时 fast-forward，已有已发布提交时普通 merge commit；禁止 rebase 已发布分支/force push/cherry-pick（SDD §1.3）。

实现 dev-plan composite digest 的唯一权威定义与写入点：`crctl review-record --stage dev-plan` 落盘 annotation 时计算 plan.md + 全部 `TASK-*.md` 的 canonical digest，写入现有 `subject-sha256` 字段；subject 不完整时硬失败 `SUBJECT_NOT_FOUND` 且零账本写入。

# 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（新增内部函数 + review-record dev-plan 分支）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增用例）

# 实现要点（SDD §4.1、§4.2、§2.2）

- canonical 编码：entries = plan.md 第一项 + 全部 TASK，按 workspace-relative POSIX path 字符串升序；每项 `{ path, content }`（键序固定），`content` 为 `\r\n → \n` 规范化全文；`JSON.stringify` 无空白后 UTF-8 sha256。
- TASK 匹配 `/^TASK-.*\.md$/`（PRD 全部 `TASK-*.md` 口径），只扫 `change-requests/{cr}/tasks/` 一层；`tasks/_index.yml` 不进入；禁止用 gates.json 数字前缀 glob 收窄。
- 读取沿用 `readFileChecked`；任一预期缺失返回带 `repairTarget` 的结构化失败，权限/I/O 异常继续抛出，不宽泛 catch、不静默降级。

# 验收条件

1. review-record dev-plan（pass 轨与 block 轨）annotation 均含 `subject-sha256`，且可由测试内独立复算相等。
2. 修改 plan.md / 修改任一 TASK / 增删 TASK 文件均改变 digest；仅改 `tasks/_index.yml` digest 不变；LF 与 CRLF 检出产生相同 digest。
3. plan.md 缺失 → `fail('SUBJECT_NOT_FOUND', why含'plan.md 缺失')`；TASK 集为空 → `SUBJECT_NOT_FOUND`（why 含集合为空）；两种失败均零账本写入（annotation/review-loop/traceability 不变）。
4. 不同 TASK 文件集合（如内容拼接边界情形）不产生相同 digest。

# 完成标志

新增红测先行全部通过 + 既有全量测试不回归；`node --test` 本地绿；提交为一个可回滚 commit。

# 接口契约

- 消费：`readFileChecked`、`sha256`、`fail`（crctl.mjs 既有内部函数，签名不变）。
- 产出（供 TASK-02 消费）：crctl.mjs 内部函数
  ```
  devPlanCompositeDigest(ws: string, cr: string) -> {
    ok: boolean,
    digest?: string,                                    // ok=true 时 64-hex
    repairTarget?: 'write-dev-plan' | 'write-dev-tasks', // ok=false 时
    why?: string                                        // ok=false 时
  }
  ```
  失败语义：plan 缺失→repairTarget=`write-dev-plan`；tasks/ 缺失、TASK 集为空、TASK 文件读取失败→repairTarget=`write-dev-tasks`。
