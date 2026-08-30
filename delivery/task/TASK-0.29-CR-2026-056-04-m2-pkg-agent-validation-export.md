---
spec-id: ai-first-platform
version: "0.29"
id: CR-2026-056-TASK-04
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M2 pkg/agent 校验导出（单一实现）
slug: m2-pkg-agent-validation-export
status: pending
estimate: 4h
depends-on: [CR-2026-056-TASK-03]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

把会话/任务 chat-config 的领域校验收敛到 `pkg/agent` 单一实现：导出 `ModelIDForCapabilityLookup` / `StaticCatalog` / `ValidateChatConfig`（BLOCK-014）。对应 plan.md M2 第 1 项。

输入条件：TASK-03 完成（主链依赖；本 TASK 本身只动 `pkg/agent`）。

## 涉及文件 / 模块

- `server/pkg/agent/models.go`（`Catalog` / `Model` / `modelIDForCapabilityLookup` 升格 / `claudeContextWindowTagRe`）
- `server/pkg/agent/thinking.go`（`ValidateThinkingLevelWith` 签名不变；新增 `StaticCatalog` / `ValidateChatConfig`）
- 包内既有调用未导出 `modelIDForCapabilityLookup` 的调用点（改调导出符号）

## 实现要点

1. 导出三个符号（签名以 SDD §4.2.1 为准，注释英文）：
   - `func ModelIDForCapabilityLookup(providerType, model string) string`：由既有未导出 `modelIDForCapabilityLookup` 升格（或等名升格），包内原调用点改调导出符号；`claudeContextWindowTagRe` 只留在 `pkg/agent`。
   - `func StaticCatalog(c Catalog) func() (Catalog, error)`：把已加载 `Catalog` 适配为 `ValidateThinkingLevelWith` 所需 loader 形状；无 I/O。禁止把 `Catalog` 直接当 loader 传入。
   - `func ValidateChatConfig(catalog Catalog, providerType, model, thinking string) (ok bool, err error)`。
2. `ValidateChatConfig` 算法（与 `ValidateThinkingLevelWith` 共用同一套规则，不复制）：
   - `thinkingOK, err = ValidateThinkingLevelWith(StaticCatalog(catalog), providerType, model, thinking)`；
   - `model == ""` 时 modelOK = true（空模型是合法 runtime-default 哨兵，不是 catalog 条目，不得要求空串属于 Models）；
   - 否则 `modelOK = ModelIDForCapabilityLookup(providerType, model)` 命中 `catalog.Models[].ID`；
   - 任一失败或 `err != nil` 即 `ok=false`。
3. 既有规则不重写（`ValidateThinkingLevelWith` 语义不动）：`thinking==""` 接受；codex + 空 model + 非空 thinking 拒绝（fail-closed）；其他 provider 空 model 解析到 catalog.Default；Claude 变体经 `ModelIDForCapabilityLookup` 命中能力矩阵。
4. `ValidateThinkingLevelWith` 签名不变（第一参数为 `func() (Catalog, error)`）。

## 验收条件

1. `cd server && go test ./pkg/agent/ -count=1` 绿，含校验矩阵：空 model + 空 thinking 各 provider 通过；空 model + 非空 thinking 在 codex 拒绝；同组合在 claude/opencode 按 `ValidateThinkingLevelWith`；非空未知 model 拒绝；Claude 上下文窗口变体（如带 `[1m]` 后缀）命中基础模型能力。
2. `claudeContextWindowTagRe` 仅在 `pkg/agent` 出现（grep 验证，无第二套归一化）。
3. `cd server && go build ./...` 绿；既有 `ValidateThinkingLevelWith` 调用方行为不变（既有测试全绿）。

## 完成标志

`cd server && go test ./pkg/agent/ -count=1` 全绿并提交。

## 接口契约

- 消费：基线 `pkg/agent` 既有 `Catalog` / `ValidateThinkingLevelWith`（TASK-01 基线事实）。
- 产出（精确签名）：
  - `func agent.ModelIDForCapabilityLookup(providerType, model string) string`
  - `func agent.StaticCatalog(c agent.Catalog) func() (agent.Catalog, error)`
  - `func agent.ValidateChatConfig(catalog agent.Catalog, providerType, model, thinking string) (ok bool, err error)`

  供 TASK-05 的 `service.ValidateResolvedChatConfig` 转发调用。
