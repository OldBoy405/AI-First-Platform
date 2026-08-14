---
id: CR-2026-027-TASK-02
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: tools ARCHITECTURE.md 修订（口径 27/49、单文件边界、crctl-Pipeline 依赖、指标基线）
slug: architecture-md-phase0-revision
status: pending
estimate: 4h
depends-on: ["CR-2026-027-TASK-01"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-02 — tools ARCHITECTURE.md 修订（Phase 0 文档层）

## 任务描述

在 tools worktree 内完成 `ARCHITECTURE.md` 的 Phase 0 修订（FR-1/FR-2/FR-3/FR-7）：消除状态机口径前后矛盾（§3 代码地图 25/47、§5 不变量 5 25/47 vs §8 已写 27/49）、确认 crctl 单文件边界、修订 crctl 与 Pipeline 依赖描述、固化优化指标基线。

## 涉及文件 / 模块

- tools `ARCHITECTURE.md`（仅此一文件；改动全部在 `requirement/CR-2026-027` worktree 内提交，禁止直写 custom/main）

## 实现要点

- §3 代码地图 gates.json 段与 §5 不变量 5：25 条声明/47 条展开 → **27 条声明/49 条 wildcard 展开**（与 §8 CR-2026-026 登记一致；口径以 `dir-graph.yaml#change-request-track.state_machine` 为准，SDD §1.1）
- §3 crctl 段：确认并保留「刻意单文件」表述，补一句「本轮不创建 commands/ 模块目录；未来模块化须独立立项并先修订本文档」（FR-2）
- §4 分层依赖：将「crctl 不依赖任何 Skill 或 Pipeline 定义」替换为三句准确描述（FR-3）：crctl 不执行 Skill、不依赖 Skill 自然语言语义；crctl 可读取 dir-graph、gates 与 Pipeline 中的声明式 gate/reviewLoop 配置；Pipeline 不得调用 crctl 之外的账本写入口
- 新增或并入指标基线小节（FR-7）：v2 方案 §16.1 正确性指标 + §16.2 调用量目标表（注册 24→8-12、PRD 9→3、implement-code 63→25-35 等），注明「观测值，不得通过删除 gate/测试/补偿/人工审批达成」
- 本 CR 的 §8 维护登记由 TASK-09 完成（避免本 TASK 与实施提交混杂）

## 验收条件

1. `grep -n "25 条声明\|47 条\|25/47" ARCHITECTURE.md` 无「现状」表述命中（§8 历史登记除外）
2. §4 存在三句准确描述且无「不依赖任何 Skill 或 Pipeline 定义」旧表述
3. §3 存在 crctl 单文件边界说明（含不创建 commands/ 模块目录）
4. 指标基线表格（§16.1/§16.2）已固化且含「不得通过删除 gate/测试/补偿/人工审批达成」约束（AC-7）

## 完成标志

ARCHITECTURE.md 提交至 tools worktree 分支；AC-1/AC-2/AC-3/AC-7 的文档部分通过。

## 接口契约

- 消费：TASK-01 产出的 tools worktree
- 产出：修订后的 `ARCHITECTURE.md`（TASK-09 的 §8 登记与 TASK-10 的 grep 验收基于本产出）
