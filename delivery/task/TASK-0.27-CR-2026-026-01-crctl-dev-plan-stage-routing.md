---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-026-TASK-01
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: crctl dev-plan stage 映射与双轨路由判定
slug: crctl-dev-plan-stage-routing
status: pending
estimate: 12h
depends-on: []
created: "2026-08-09T12:55:00+08:00"
---

# TASK-01 — crctl dev-plan stage 映射与双轨路由判定

## 任务描述

在 `crctl.mjs` 中落地 dev-plan stage 的完整能力：REVIEW_STAGE 四映射扩展、`resolveDevPlanRoute` 路由判定、repair-target schema/枚举校验、bump 前路由与 UPSTREAM 跳过 bump。这是本 CR 双轨路由的地基（M1）。

输入条件：CR-2026-026 处于 task-breakdown；`crctl.mjs` 现有 cmdReviewRecord 通用路径（含 CR-2026-025 三账本一致写）。

## 涉及文件

- `tools/skills/shared/crctl/scripts/crctl.mjs`（唯一改动文件）

## 实现要点（SDD §3.1/§3.2/§2.3）

1. 四映射追加（SDD §3.1）：
   - `REVIEW_STAGE_FILES['dev-plan'] = 'dev-plan.yml'`
   - `REVIEW_STAGE_LOOPS['dev-plan'] = 'review-dev-plan'`
   - `REVIEW_STAGE_EXPECT['dev-plan'] = ['task-breakdown']`
   - `REVIEW_REPAIR_TARGETS['dev-plan'] = 'write-dev-plan'`
2. 新增纯函数 `resolveDevPlanRoute(payload)`（SDD §3.2）：verdict=pass → PASS；verdict=block 且顶层 `repair-target === 'write-tech-design'` → UPSTREAM；其余 → NORMAL。
3. `cmdReviewRecord` 对 `--stage dev-plan` 的 schema 校验增加 `repair-target` 枚举（缺省或 ∈ {`write-dev-plan`, `write-tech-design`}；非法值 `SCHEMA_INVALID` 且三账本不变）。
4. **bump 前路由**（SDD §3.2 步骤 1-4）：读取 payload → schema 校验 → resolveDevPlanRoute → 按轨执行 bump：NORMAL/PASS 走既有 `--bump-attempt`（attempt+1、attempts 追加）；UPSTREAM **跳过 bump**（current-attempt 不变、attempts 不追加），仅写 annotation（repair-target=write-tech-design 落顶层）与 traceability 投影（attempt=当前值）→ casWriteMulti 统一写三账本。
5. 不解析 blockers 字符串（D-13）；行尾纪律：读入 payload/账本先 `\r\n → \n` 规范化。

## 验收条件

1. `node --test crctl.test.mjs` 新增向量 ①-⑤ 通过：dev-plan 映射存在且 task-breakdown 下 review-record 落盘三账本；repair-target 缺省/显式/非法值三态（非法 → SCHEMA_INVALID 且三账本 sha256 不变）；UPSTREAM bump 跳过（review-loop current-attempt 不变、attempts 不追加）；NORMAL/PASS 走既有 bump（attempt+1）；同轮并存时 UPSTREAM 优先（普通项进 suggestions 摘要）。
2. 手工验证：构造 verdict=block + repair-target=write-tech-design 的 payload 执行 `crctl review-record --stage dev-plan --bump-attempt`，输出 route=upstream 且 review-loop current-attempt 未递增。

## 完成标志

crctl.test.mjs 向量 ①-⑤ 全绿；`crctl.mjs` 顶部 import 仍只含 `node:*`（不变量 3）；审计日志含 dev-plan review-record 记录。

## 接口契约

- 消费：无（首个 TASK）。
- 产出：`REVIEW_STAGE_FILES/LOOPS/EXPECT/REPAIR_TARGETS['dev-plan']` 四映射（TASK-05 的 pipeline 节点依赖）；`resolveDevPlanRoute(payload)` 返回 `{ route: 'pass' | 'upstream' | 'normal' }`（TASK-07 测试依赖）；annotation 顶层 `repair-target` 字段（TASK-02 的 passCondition/evidence digest 依赖）。
