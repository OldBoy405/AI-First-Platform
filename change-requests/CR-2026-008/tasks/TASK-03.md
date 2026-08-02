---
id: CR-2026-008-TASK-03
type: TASK
cr-ref: CR-2026-008
plan-ref: "change-requests/CR-2026-008/plan.md"
sdd-ref: "change-requests/CR-2026-008/sdd.md"
title: Ask-only 最小强制——ask_only 标记贯穿 enqueue→claim→execenv
slug: ask-only-enforcement
status: pending
estimate: 4h
depends-on: ["CR-2026-008-TASK-01"]
assignee: ""
created: "2026-08-02T11:25:00+08:00"
---

# TASK-03 — Ask-only 最小强制（SDD rev 0.1.1 DD-6 修订的落地）

## 任务描述

SDD-SUG-002 核实结论：chat 任务 brief 带 Repositories 节、`multica repo checkout` 无任务级
只读机制——「Ask-only」需本 CR 实现。范围精确限定 **project_id 非空的会话（Private Ask）**：
既有全局 1:1 chat（project_id 为空）不受限（合法用例）。

## 涉及文件 / 模块

- `server/internal/service/task.go`（EnqueueChatTask 路径：session.project_id 非空 → 任务标记
  ask_only；标记存 task context 或 claim 响应组装处）
- claim 响应结构（daemon 协议：新增**可选**字段 `ask_only`，旧 daemon 忽略=降级到现状）
- `server/internal/daemon/execenv/execenv.go`（TaskContextForEnv 加 AskOnly）
- `server/internal/daemon/execenv/runtime_config_sections.go`（buildMetaSkillContentSlim：
  AskOnly 时省略 writeRepositories）
- daemon 的 `multica repo checkout` 处理路径（AskOnly 任务拒绝，结构化错误
  `read-only chat session`；按 repocache/cache.go 与 CLI 命令处理点定位）

## 实现要点

- 判定源唯一：`chat_session.project_id IS NOT NULL`（T01 已建列），不引入独立配置开关。
- 两道防线缺一不可：brief 省略（引导层，防"被告知可用"）+ checkout 拒绝（强制层，防
  agent 自发尝试——URL 可能来自用户消息）。
- work_dir 不暴露由 T01 保证（创建时不设），本任务不重复处理。
- 协议兼容：字段可选，宽松反序列化；SDD §8 已登记降级行为=弱化约束不破坏功能。
- multica 仓注释英文。

## 验收条件

1. 单测：project 会话任务 claim 响应带 ask_only=true，全局会话任务不带/false。
2. brief 快照测试：AskOnly 任务的 brief 无 Repositories 节；普通 chat 任务保持现状
   （既有 brief 测试回归）。
3. 集成/真机：Private Ask 会话内 agent 执行 `multica repo checkout <url>` 被拒并返回
   结构化错误；同 agent 在全局 1:1 chat 中 checkout 正常。

## 完成标志

单测+brief 快照+集成通过 + 既有 chat brief 测试零回归 + lint 零报错。
