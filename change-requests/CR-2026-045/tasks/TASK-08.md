---
id: CR-2026-045-TASK-08
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: daemon pipeline task carrier
slug: daemon-pipeline-task-carrier
status: pending
estimate: 8h
depends-on:
  - CR-2026-045-TASK-07
created: 2026-08-17T20:39:31+08:00
---

# TASK-08 daemon pipeline task carrier

## 1. 任务描述

让 daemon 能执行 `context.type=pipeline_node` 的任务：claim path 识别并填充 task wire 的 `Pipeline*` 字段，`BuildPrompt` 对 pipeline task 返回固定 `PipelinePrompt`（不进入 issue/chat/quick-create prompt），并把 `crctl workspace inspect` 返回的 operationalWorkspace 作为现有 `PrepareParams.LocalWorkDir`，复用 realpath/path lock/sidecar cleanup。这是 B03 回修的最小落点——绝不降级到 scratch 跨目录写。

## 2. 涉及文件 / 模块

- `server/internal/handler/daemon.go`（claim context hydration：识别 `context.type=pipeline_node` → 填充 Pipeline 字段）
- `server/internal/daemon/{types.go,prompt.go,daemon.go}`（`kindPipeline`、`PipelinePrompt`、slim runtime brief）
- `server/internal/daemon/execenv/{crguard_config.go,runtime_config_kind.go}`（pipeline kind 与 crctl 路径派生）
- 现有 daemon 测试（新增 pipeline kind 断言）

## 3. 实现要点

- slim runtime brief 只保留 workspace context、Agent instructions、已绑定 Skills、受控 shell、通用安全规则；不渲染 Issue Metadata、comment workflow、quick-create 命令。
- 在 `CRWorkspaceRoots` 按 `cr_id` 查唯一 CR root；0 或多于 1 个 fail closed。
- 复用 `MULTICA_CONTROLLED_SHELL_RULES`：按现有 `prepareCRGuard` 同一相对关系从 `rules.json` 派生 `crctl.mjs`，不新增第二路径配置；未配置/文件不存在时仅 pipeline task 返回 `PIPELINE_CRCTL_UNAVAILABLE`，普通任务不变。
- daemon 以 `exec.CommandContext(node, crctl, workspace, inspect, ...)` argv 形态（`shell=false` 语义）对唯一 root 执行 `crctl workspace inspect`，要求全部 resources healthy 且 `operationalWorkspace` 非空、realpath 在 CR root 内。
- `operationalWorkspace` 作为 `PrepareParams.LocalWorkDir`，合成 `localDirectoryAssignment` 后复用 `normalizeLocalPath`、realpath、`localPathLocks.Acquire`、local-directory sidecar/runtime-config cleanup。
- `CRCTL_WORKSPACE` 仍指向唯一 CR root；Agent cwd 为 operational workspace。
- GC 继续用 task-id 查现有 task terminal 状态，不新增 GC 账本。

## 4. 验收条件

1. pipeline context hydration 断言：claim 后 task wire 的 Pipeline 字段正确；prompt 不含 issue/quick-create workflow。
2. CR root 0/1/2 匹配断言：0 或 2 个 fail closed，1 个成功。
3. inspect 非 healthy、rules/crctl 缺失时返回结构化错误（`PIPELINE_CRCTL_UNAVAILABLE`），不降级 scratch 写入。
4. LocalWorkDir 与现有 path lock/cleanup 生效断言；跨平台 `shell:false` 约束保持。

## 5. 完成标志

daemon pipeline kind 落地 + 五类断言通过 + 普通任务路径零回归；在 Multica 根目录 `CUSTOM.md` 登记 CR-2026-045/TASK-08 的 daemon 挂点、生成物和上游贴回策略。

## 6. 接口契约

- 消费：TASK-06 写入的 `context.type=pipeline_node` 与 `cr_id/run_id/node_id/pipeline_id/attempt/prompt`；TASK-07 入队。
- 产出：daemon 对 pipeline task 的 `PipelinePrompt`、`PrepareParams.LocalWorkDir`（=operationalWorkspace）、`CRCTL_WORKSPACE`（=CR root）；TASK-11 的 E2E 依赖真实执行链路。
