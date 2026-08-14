---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-026-TASK-06
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: 文档同步（README / ARCHITECTURE / crctl SKILL 用途表）
slug: docs-sync
status: pending
estimate: 4h
depends-on: ["CR-2026-026-TASK-05"]
created: "2026-08-09T12:55:00+08:00"
---

# TASK-06 — 文档同步

## 任务描述

按 SDD §8 采纳清单同步 tools 仓文档：README 节点流程、ARCHITECTURE §8 登记、crctl SKILL 用途表（FR-17）。

输入条件：TASK-05 已插入 pipeline 节点（文档描述的对象已存在）。

## 涉及文件

- `tools/README.md`
- `tools/ARCHITECTURE.md`
- `tools/skills/shared/crctl/SKILL.md`

## 实现要点（SDD §8 采纳清单 + FR-17）

1. **README.md**：code-implementation 流程补充 review-dev-plan 节点（write-dev-tasks 后、push-progress 前）；受控评审 stage 列表加 dev-plan；状态转换说明加两条新 trigger。
2. **ARCHITECTURE.md §8**：登记本 CR——crctl REVIEW_STAGE 扩展（dev-plan stage + 双轨路由 + repair-target 顶层字段）、pipeline 结构变化（code-implementation 插入 review-dev-plan reviewLoop 节点）、状态机口径变化（25→27 声明 / 47→49 展开）、gates.json 变更（dev-start evidence/passCondition、developing 五条件）。按 §8 维护规则追加「已登记」条目，不改 §5/§6 判据。
3. **crctl SKILL.md 用途表**：补 `review-record --stage dev-plan`、两条 trigger（`review-dev-plan:block` / `review-dev-plan:upstream-design-blocker`）、reviewLoops 映射 `review-dev-plan`、`task done` 依赖守卫不变。
4. 全部文档不引入本机绝对路径；中文文档（README/ARCHITECTURE 为本仓中文惯例）。

## 验收条件

1. README 含 review-dev-plan 节点与 dev-plan stage；ARCHITECTURE §8 含本 CR 登记条目（含 27/49 口径）；crctl SKILL 用途表含 dev-plan stage 与两条 trigger。
2. `lint-prompts.mjs --mode enforce` 通过（crctl SKILL 与 crctl 命令面无 STALE）。
3. `grep -r "C:\\\\Users"` 在本次改动中零命中。

## 完成标志

三文件同步完成；lint 全绿；ARCHITECTURE §8 登记与状态机口径一致（27 声明 / 49 展开）。

## 接口契约

- 消费：TASK-05 的 pipeline 结构（README 描述对象）；TASK-02 的状态机/gates 变更（ARCHITECTURE 登记对象）。
- 产出：文档基线（TASK-07 全量回归的检查对象；实现期 lint/check 的对照面）。
