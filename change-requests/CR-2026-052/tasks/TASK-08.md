---
id: CR-2026-052-TASK-08
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "tools crctl.mjs：comparable() 剥离 payload.detected_at（FR-12）"
slug: tools-comparable-strip-detected-at
status: pending
estimate: 2h
depends-on: []
created: 2026-08-27T10:44:32+08:00
---

# TASK-08：tools comparable 修复

## 1. 任务描述

修正 `skills/shared/crctl/scripts/crctl.mjs` 的 `emitOutboxEvent` 内 `comparable()`：对 payload 浅拷贝后剥离 `detected_at`，使同一漂移在被采集期间二次观测不再 `OUTBOX_DEDUP_CONFLICT` → `EMIT_FAILED`。对应 SDD §4.4/DD-6，FR-12。

## 2. 涉及文件 / 模块

- 修改 `skills/shared/crctl/scripts/crctl.mjs`（`comparable()`，现 :321-329）

## 3. 实现要点（SDD §4.4/DD-6）

现状 `comparable()` 将整个 `payload`（含每次观测重新生成的 `detected_at`，:351 `nowIso()`）序列化进比较；`emitDriftAudit`（:344-352）用确定性 `dedup_name` 落同一文件 → 二次观测必然冲突。

修复（保持比较字段确定性，不削弱守卫）：
```js
const comparable = (value) => JSON.stringify({
  v: value.v, event_kind: value.event_kind, cr_id: value.cr_id,
  from_status: value.from_status, to_status: value.to_status,
  trigger: value.trigger, commit_sha: value.commit_sha,
  actor: value.actor, evidence: value.evidence,
  payload: (() => { const p = { ...(value.payload || {}) }; delete p.detected_at; return p; })(),
});
```

边界（FR-12，禁止扩 scope）：
- 事件文件内容、`dedup_name` 生成规则、`occurred_at` 均不改。
- 摘要字段（`expected_digest`/`actual_digest`/`stage`/`action`）仍在比较内：同名文件内容真实变化（摘要 8 位截断碰撞等极端情形）仍冲突报错，确定性守卫不削弱（AC-12 第三分支）。
- 新事件若引入其它时点字段需同步维护该剥离逻辑——在 `comparable()` 处加注释说明易变字段白名单语义。

## 4. 验收条件

1. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 既有 drift 用例（:776）通过且新增用例见 TASK-09。
2. `grep` 确认 `dedup_name` 生成逻辑与事件文件写入字段未改；`comparable` 仅多一次对象浅拷贝。
3. 漂移被采集删除后再次观测：文件不存在 → 走全新写入路径，按观测窗口再留一份（既有语义保留，AC-12）。

## 5. 完成标志

`comparable()` 一行级修复 + 注释落盘 + 既有测试无回归；详细 drift 断言由 TASK-09 补全。

## 6. 接口契约

- **消费**：无前置（tools 仓独立）。
- **产出**：outbox 事件外部 schema（`v`/`event_kind`/`payload` 结构对采集端不变，NFR-9）；`comparable()` 内部行为变更（剥离 `detected_at`）。供 TASK-09 测试覆盖。
