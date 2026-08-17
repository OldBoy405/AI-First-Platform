---
id: CR-2026-045-TASK-05
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: 生成 ArchitectureCoreRegistryJSON 与 digest
slug: generate-architecture-core-registry
status: pending
estimate: 4h
depends-on:
  - CR-2026-045-TASK-02
created: 2026-08-17T20:39:31+08:00
---

# TASK-05 生成 ArchitectureCoreRegistryJSON 与 digest

## 1. 任务描述

扩展现有 `server/internal/governance/gen/generate-gate-nodes.mjs`：继续刷新 `ApprovalGateNodes`/`ReviewGateNodes` 并把旧 `0014` UUID 修正为当前 `0016`；在同一 `gate_nodes_gen.go` 中新增 `ArchitectureCoreRegistryJSON` 与其 canonical SHA-256。build/runtime 不读取 tools checkout，只消费已提交生成物；不创建第二个 registry 生成器或运行时模板 loader。

## 2. 涉及文件 / 模块

- `server/internal/governance/gen/generate-gate-nodes.mjs`（扩展，调用 tools `emit-registry.mjs --pipeline architecture-design`）
- `server/internal/governance/gate_nodes_gen.go`（生成物：registry JSON 常量 + digest 常量 + 修正 0014→0016）
- `server/internal/governance/gen/*.test.mjs` 或既有 gen 测试（`--check` 断言）

## 3. 实现要点

- 生成器以 `spawnSync` 等价方式调用 tools worktree 的 `emit-registry.mjs`，输出内嵌为 `ArchitectureCoreRegistryJSON` 常量，digest 为 `sha256:...` 常量。
- `--check` 忽略 source SHA 注释差异，但必须比较节点、prompt、permissions、replayLoop 和 digest；不匹配即非零退出。
- 旧 `0014` 节点 UUID 从 `ApprovalGateNodes`/`ReviewGateNodes` 移除或更新为 `0016`，与 tools 当前 Pipeline 一致。
- 生成物入库，冲突丢弃后重跑生成器（沿用 CUSTOM.md 台账的生成物纪律）。

## 4. 验收条件

1. `generate-gate-nodes.mjs --check` 通过，且 registry digest 与 tools 当前 emit-registry 输出一致。
2. 生成物中 `0016` 是唯一 architecture 节点 UUID 前缀，旧 `0014` 不再出现。
3. 非 Node 环境下 server 编译/测试仍通过（不依赖 tools checkout，只消费生成物）。

## 5. 完成标志

registry JSON + digest 生成物入库 + `--check` 通过 + 0014→0016 修正。

## 6. 接口契约

- 消费：TASK-02 的 `emit-registry.mjs` 输出（`{schema,pipeline,pipelineOwner,nodePermissions,digest}`）。
- 产出：`gate_nodes_gen.go` 中 `ArchitectureCoreRegistryJSON string` 与 `ArchitectureCoreRegistryDigest string`（`sha256:...`）；TASK-07 的 `Reconcile` 用 digest 比对 `execution_context.template_digest`，用 registry 做节点/权限判定。
