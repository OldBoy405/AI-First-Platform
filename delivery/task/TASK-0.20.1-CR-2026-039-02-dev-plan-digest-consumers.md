---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-039-TASK-02
type: TASK
cr-ref: CR-2026-039
plan-ref: "change-requests/CR-2026-039/plan.md"
sdd-ref: "change-requests/CR-2026-039/sdd.md"
title: next 与 developing 门禁双消费点接入 digest freshness
slug: dev-plan-digest-consumers
status: pending
estimate: 3h
depends-on: [CR-2026-039-TASK-01]
created: 2026-08-15T01:31:31+08:00
---

# 任务描述

在 dev-plan PASS 的两个消费缝接入 freshness 判定：`crctl next` 的 task-breakdown PASS 分支与 `runGateChecks` 的 `passCondition(dev-start)` 分支。旧 PASS 在 plan/TASK 漂移、legacy 无 digest 或 subject 不完整时一律失效；next 给出可执行恢复路由，approve-dev-start（及一切以 developing 为目标的 advance）硬失败且零写入。

# 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（cmdNext task-breakdown 分支、runGateChecks passCondition 分支）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增用例）

# 实现要点（SDD §4.3）

- freshness 判定集中为一个内部函数，两处消费点各一行调用，禁止第二份 digest 比较逻辑。
- cmdNext：PASS 分支先判 freshness；不 fresh 时 `suggest(freshness.repairTarget, why)`——plan 缺失→`write-dev-plan`，TASK 缺失/为空→`write-dev-tasks`，legacy 或 digest 漂移→`review-dev-plan`。block 分支与 annotation 畸形判定不变。
- runGateChecks：`evaluatePassCondition` 返回 pass 且 `check.stage === 'dev-start'` 时追加 freshness；不 fresh → 该 check `ok:false` 并携带 why（复用 gate 失败通道，不新增错误码、不改 gates.json）。
- requirement/tech-design/code 三阶段 passCondition 路径不进入该分支。

# 验收条件

1. PASS+fresh：`crctl next` suggest `crctl approve --stage dev-start`；`crctl approve --stage dev-start` 放行。
2. PASS+drift（改 plan 或任一 TASK 后）：`crctl next` suggest review-dev-plan；approve 硬失败，gateBlockers 含 digest 不一致说明，approval.yml/cr.md 零写入。
3. legacy 无 `subject-sha256` 的 PASS annotation：next suggest review-dev-plan，approve 硬失败。
4. 删除全部 TASK：next suggest write-dev-tasks（结构化路由），不抛裸错误；approve 硬失败且 why 含 subject 不完整。

# 完成标志

新增用例（含 4 类分流）全部通过 + 既有全量测试不回归（requirement/tech-design/code 三阶段 passCondition 行为不变）；提交为一个可回滚 commit。

# 接口契约

- 消费（TASK-01 产出，签名逐字一致）：`devPlanCompositeDigest(ws: string, cr: string) -> { ok: boolean, digest?: string, repairTarget?: 'write-dev-plan' | 'write-dev-tasks', why?: string }`。
- 产出（crctl.mjs 内部函数）：
  ```
  devPlanFreshness(ws: string, cr: string, annData: object | null) -> {
    fresh: boolean,
    repairTarget?: 'review-dev-plan' | 'write-dev-plan' | 'write-dev-tasks', // fresh=false 时
    why?: string                                                              // fresh=false 时
  }
  ```
  规则：annData 无 `subject-sha256` → `review-dev-plan`；digest helper 失败 → 透传其 `repairTarget`；digest 不等 → `review-dev-plan`。
