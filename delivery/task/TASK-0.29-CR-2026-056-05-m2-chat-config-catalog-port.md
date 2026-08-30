---
spec-id: ai-first-platform
version: "0.29"
id: CR-2026-056-TASK-05
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M2 service chat_config 与 handler catalog 适配
slug: m2-chat-config-catalog-port
status: pending
estimate: 4h
depends-on: [CR-2026-056-TASK-04]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

新增 `service/chat_config.go`（Resolve + `ChatCatalogPort` + 薄包装校验），handler 侧实现 `ChatCatalogPort`（CacheLoad / LiveLoad），`cmd/server` composition root 注入。对应 plan.md M2 第 2–4 项。

输入条件：TASK-04 已导出 `agent.ValidateChatConfig` / `StaticCatalog` / `ModelIDForCapabilityLookup`。

## 涉及文件 / 模块

- `server/internal/service/chat_config.go`（新）
- `server/internal/handler/runtime_model_catalog.go` 附近（新增 `ChatCatalogPort` 适配器；`ModelCatalogCache` / `cacheableModelCatalog` / `modelCatalogRevalidateAfter` 留在 handler）
- `server/internal/handler/runtime_models.go`（`modelListPendingTimeout=30s` 复用；`InitiateListModels` 保持异步）
- `server/cmd/server/` composition root（注入）

## 实现要点

1. `ResolveChatConfig`（SDD §4.2）：对 `model` 与 `thinking_level` 分别解析，优先级 `override -> base_* -> agent 当前默认（仅历史 Private Ask）-> runtime_default`，输出有效值 + 来源（`model_source` / `thinking_level_source` ∈ `override|session_default|agent_default|runtime_default`）。`base_*` NULL=未快照；空串=已快照「跟随 runtime 默认」。
2. `ChatCatalogPort`（service 拥有，handler 实现，签名以 SDD §4.3 为准）：
   - `CacheLoad(ctx context.Context, runtimeID string) (cat agent.Catalog, ok bool, err error)`：24h last-known-good cacheable 快照；`ok=false` 表示无可用快照；禁止 fallback。
   - `LiveLoad(ctx context.Context, runtimeID string) (agent.Catalog, error)`：一轮同步发现，不得返回 pending/202；超时 30s（即 `modelListPendingTimeout`）；复用 daemon pending-work / ModelListStore 内部；HTTP `InitiateListModels` 对 picker 仍异步（FR-4）。
3. `ValidateResolvedChatConfig`（SDD §4.2.1 service 段，精确签名）：`func ValidateResolvedChatConfig(model, thinking, provider string, catalog agent.Catalog) error`，只转发 `agent.ValidateChatConfig`；失败返回可被 handler 映射为 `400 invalid_model_or_thinking_level` 的错误。禁止复制归一化 / 第二套规则；service 不得 import `internal/handler`。
4. `loadCatalogForChatConfig` 同步判定契约（SDD §4.3，四入口共用同一函数）：`AgentReadiness` Blocked 拒绝；Waitable 仅 `CacheLoad`（禁 LiveLoad），miss/err 即 400 语义；Available 先 cache 快路径（`Age ≥ modelCatalogRevalidateAfter(60s)` 可后台 revalidate，不挡请求），miss 走 `LiveLoad`（30s deadline），失败/非 cacheable 即 400 语义；`cacheable = supported && !fallback && len(models)>0`，成功后按既有规则 Put cache。
5. `cmd/server` 接线：适配器注入持有 `ChatCatalogPort` 的 service；依赖方向仅 handler→service（ARCHITECTURE.md §4）。

## 验收条件

1. `cd server && go build ./...` 绿（Go 模块在 `server/go.mod`）；包依赖检查确认 `internal/service` 未 import `internal/handler`。
2. `ResolveChatConfig` 单测：四层优先级 ×（override / base / agent_default / runtime_default）× model/thinking 分别解析（来源可不同）。
3. LiveLoad 错误语义夹具（SDD §4.3 表）：30s 内 cacheable 继续校验；超时（pending 未完成）400 语义；daemon Fail / empty / fallback 400；Waitable 无 cache 400 且不调用 LiveLoad。
4. 代码检索确认 `ValidateResolvedChatConfig` 为 service 内唯一校验包装（四入口唯一校验入口成立），无第二处调用 `ValidateThinkingLevelWith`。

## 完成标志

`cd server && go build ./...` + service/handler 相关单测绿并提交。

## 接口契约

- 消费：TASK-04 的 `agent.ValidateChatConfig(catalog, providerType, model, thinking) (bool, error)` 与 `agent.Catalog`；基线 `AgentReadiness` / `AgentAvailable` / `AgentWaitable` / `AgentBlocked`（`service/agent_ready.go`）。
- 产出（精确签名）：
  - `type service.ChatCatalogPort interface { CacheLoad(ctx context.Context, runtimeID string) (agent.Catalog, bool, error); LiveLoad(ctx context.Context, runtimeID string) (agent.Catalog, error) }`
  - `service.ValidateResolvedChatConfig(model, thinking, provider string, catalog agent.Catalog) error`
  - `service.ResolveChatConfig`：输入 session override/base 列 + agent 当前默认，输出 model 与 thinking_level 的有效值及来源枚举（语义按 SDD §4.2；Go 形参形状实施期定，语义以本条为准）

  供 TASK-06（GET 展示用 Resolve）、TASK-07（PATCH / messages / container / merge-forward 四入口校验）消费。
