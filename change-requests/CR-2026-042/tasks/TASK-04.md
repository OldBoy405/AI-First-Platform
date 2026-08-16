---
id: CR-2026-042-TASK-04
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: README 重写与 ARCHITECTURE 定点更新
slug: rewrite-readme-architecture
status: pending
estimate: 4h
depends-on:
  - CR-2026-042-TASK-01
  - CR-2026-042-TASK-02
  - CR-2026-042-TASK-03
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

按 SDD §2.4 将 README 重写为短的人读入口，并做 ARCHITECTURE.md 定点更新。OpenWiki 页面不手工改写，由既有 workflow 刷新。

# 2. 涉及文件 / 模块

- `README.md`
- `ARCHITECTURE.md`

# 3. 实现要点

README 固定 8 节：定位、概念生命周期、Owner 职责、8 条 Pipeline 入口、自动评审与人工审批、checkpoint/merge/operational workspace/archive 人读区别、恢复与 `crctl status/next`、权威事实源链接。

README 不再维护：节点表、完整状态转移、门禁表达式、账本字段、内部算法、完整错误矩阵、动态测试数量、默认值。

ARCHITECTURE.md 在 Pipeline 模块说明中定点声明：reviewer runner 由 Agent/runtime 在进入 Pipeline 前选择，Pipeline 不设额外人工暂停节点；其余架构不变量不改。

# 4. 验收条件

1. README 含 §2.4 的 8 个必需章节，且每节有对应权威链接；
2. `grep -nE '^\|.*\|.*\|.*\|$' README.md` 中不再出现完整状态转移声明（概念阶段图除外）与节点级 prompt 表；
3. README 不再包含完整错误码矩阵、动态测试数量、可执行默认值副本；
4. `grep -n 'review_llm\|选择代码评审 LLM' README.md` 零命中；
5. ARCHITECTURE.md 含 reviewer runner 选择边界的定点声明，且 §5 硬不变量 1-7 原文不变。

# 5. 完成标志

README 收敛为 8 节人读入口且禁止内容零命中；ARCHITECTURE 定点更新完成、不变量不变。

# 6. 接口契约

- 消费：TASK-01 的 Agent 最终职责、TASK-02 的 code Pipeline 16 节点结构与 reviewer 选择边界、TASK-03 的 Skill 最终业务边界。
- 产出：`README.md`（人读入口）、`ARCHITECTURE.md`（reviewer 选择边界一句）；下游 TASK-07 消费「README 必需章节 + 权威链接」做全量验证。
