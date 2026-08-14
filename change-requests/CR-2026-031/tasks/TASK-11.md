---
id: CR-2026-031-TASK-11
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现临时 upgrade-check 与激活门禁
slug: upgrade-preflight
status: pending
estimate: 8h
depends-on: [CR-2026-031-TASK-06, CR-2026-031-TASK-07, CR-2026-031-TASK-08, CR-2026-031-TASK-09]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

实现临时只读 `crctl upgrade-check`，从 origin 权威事实分类新协议激活风险；不创建 workspace、不修改审批或合成 snapshot。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `CUSTOM.md` 的 CUSTOM-TODO-009

# 3. 实现要点

- fetch 后读 knowledge-base origin trunk 与 active repo refs，不读陈旧主 checkout。
- 输出 safe/requiresReapproval/blocksUpgrade/canActivate。
- developing 为 safe；旧 code-approved 零 publish 为 requiresReapproval；partial merge/merging/writing-back/authority unknown 为 blocker。
- 无 blocker exit 0；blocker/不确定 exit 1；全程零写入。

# 4. 验收条件

1. 四类 legacy fixture 分类准确，执行前后 workspace 文件树/refs/审批 hash 不变。
2. 无法证明零 publish 或 authority 时保守 blocksUpgrade。
3. help/dispatch/tests 明确该命令临时性，并有 CUSTOM-TODO-009 删除条件。

# 5. 完成标志

安装切换前有可重复 preflight，零写入断言通过，任务状态登记 done。

# 6. 接口契约

消费：TASK-07 `classifyRemoteCommit` 和 merge trailer，TASK-08/09 commit/trailer 事实。

产出：`checkUpgrade(ctx:object): Promise<{safe:object[],requiresReapproval:object[],blocksUpgrade:object[],canActivate:boolean}>`；CLI exit 为 `canActivate ? 0 : 1`。TASK-12 发布门禁消费。
