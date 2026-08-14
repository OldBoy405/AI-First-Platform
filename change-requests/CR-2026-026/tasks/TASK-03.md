---
id: CR-2026-026-TASK-03
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: 新建 review-dev-plan Skill
slug: review-dev-plan-skill
status: pending
estimate: 4h
depends-on: ["CR-2026-026-TASK-02"]
created: "2026-08-09T12:55:00+08:00"
---

# TASK-03 — 新建 review-dev-plan Skill

## 任务描述

新建 `skills/develop/review-dev-plan/SKILL.md`，定义编码前合并评审节点的完整提示词合约（FR-15）：输入、八类维度、payload 格式、双轨路由落盘规则。

输入条件：TASK-02 已落地状态机两条转换（trigger 名以 TASK-02 实际声明的为准）。

## 涉及文件

- `tools/skills/develop/review-dev-plan/SKILL.md`（新建）

## 实现要点（SDD §3.5 prompt 骨架 + §2.1 + §4.1/§4.2）

1. **前置校验**：CR status=task-breakdown；sdd.md/plan.md/tasks/_index.yml/TASK-*/review-annotations/sdd.yml 存在。
2. **强制输入**（FR-2）：sdd.md（权威）、plan.md、tasks/_index.yml、全部 TASK-*.md、review-annotations/sdd.yml；prd.md 仅按 SDD 引用定位抽查（D-15）。
3. **八类维度**（FR-3）：SDD→plan 覆盖、plan→TASK 覆盖、TASK 可执行性、依赖拓扑、接口契约一致性、验收可验证性、范围与极简性、风险与回滚 + 估算一致性（结构性差异才 blocker）。
4. **payload 格式**（SDD §2.1）：verdict/repair-target（顶层可选，缺省 write-dev-plan，上游疑点写 write-tech-design）/blockers（纯字符串）/dimensions 八键 + suggestion-policy: strict + reviewer-model/suggestions。
5. **落盘**：判断写 `.crctl/tmp/review-dev-plan.yml`，经 `crctl review-record --stage dev-plan --bump-attempt` 落盘（三账本）；模型禁手写 annotation/review-loop。
6. **路由处理**（SDD §3.2 结果消费）：pass → 保持 task-breakdown 等待人工审批；normal → `crctl advance --to tech-design-reviewed --trigger review-dev-plan:block`（embedded）；upstream → `crctl advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker`（embedded）并停止自动重放。
7. 回修轮次说明：普通轨由 reviewLoop 重放 write-dev-plan → write-dev-tasks → review-dev-plan（≤3 轮）；上游疑点轨不消耗普通 attempt。

## 验收条件

1. `lint-prompts.mjs --mode enforce` 通过（无 CONTRADICTS/STALE）。
2. SKILL.md 含八类维度、repair-target 顶层字段写法说明、两条 trigger 名与 TASK-02 dir-graph 声明一致。
3. SKILL.md 不含任何账本手工编辑步骤（不变量 1/2，`grep -rn "手工编辑\|手动改"` 命中为 0 或仅「禁止」措辞）。

## 完成标志

lint-prompts 通过；文档含 payload 模板与双轨路由说明；未引入账本旁路。

## 接口契约

- 消费：TASK-02 的状态机两条 trigger（`review-dev-plan:block` / `review-dev-plan:upstream-design-blocker`）；TASK-01 的 review-record --stage dev-plan 能力。
- 产出：`review-annotations/dev-plan.yml`（TASK-02 的 dev-start passCondition 消费）；`.crctl/tmp/review-dev-plan.yml` 临时 payload 格式约定（TASK-07 测试夹具依赖）。
