---
id: CR-2026-051-TASK-07
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: router 无条件订阅 wiring（typed-nil 防护）与飞书未启用形态验收
slug: router-unconditional-subscribe-wiring
status: pending
estimate: 5h
depends-on: [CR-2026-051-TASK-06]
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

在 composition root 把提醒器接上事件总线：构造 + `Register(bus)` 必须落在 `MULTICA_LARK_SECRET_KEY` 条件装配块**之外**（FR-8.3 —— 未启用时也要消费事件并记 `feishu-disabled`，否则该可观测性无从实现），并显式判空以避开 typed-nil 接口陷阱（飞书未启用时 `h.LarkAPIClient` / `h.LarkInstallations` 是 **nil 指针而非 stub**，`router.go:502` 是前者唯一赋值点且在密钥成功分支内）。同时补该形态的端到端断言（AC-11 端到端、AC-12）。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/cmd/server/router.go`（改：约 12 行 wiring，插在 lark 条件块 `if larkKey, err := secretbox.LoadKey("MULTICA_LARK_SECRET_KEY"); err == nil { … } else { slog.Info("lark integration disabled …") }`（`:468` / `:639`）**之后**，带 `// AIFIRST: CR-2026-051 FR-8.3` 注释）
- `server/cmd/server/approval_reminder_wiring_test.go`（新：`package main`，wiring 形态与端到端非阻塞断言）

零改动：`cmd/server/listeners.go`（不改 `SubscribeAll` / `personalEvents` / `internalOnlyPayloadKeys`）、`packages/**`（前端对未知事件类型 no-op）、`handler.New` 的默认值语义。

## 实现要点

1. wiring 形态固定（`pool` 与 `bus` 都在 `NewRouterWithOptions(pool *pgxpool.Pool, hub *realtime.Hub, bus *events.Bus, …)`（`router.go:317`）的作用域内，无需改签名）：

   ```go
   // AIFIRST: CR-2026-051 FR-8.3 — registered unconditionally, OUTSIDE the
   // MULTICA_LARK_SECRET_KEY block: a disabled Lark integration must still
   // consume the event and log a feishu-disabled skip. h.LarkAPIClient /
   // h.LarkInstallations are nil in that case — assign only when non-nil,
   // otherwise the config holds a typed-nil interface that panics on use.
   reminderCfg := lark.ApprovalReminderConfig{
       Pool: pool, AppURL: appURLFromEnv(), Logger: slog.Default(),
   }
   if h.LarkAPIClient != nil {
       reminderCfg.Client = h.LarkAPIClient
   }
   if h.LarkInstallations != nil {
       reminderCfg.Credentials = h.LarkInstallations
   }
   lark.NewApprovalReminder(reminderCfg).Register(bus)
   ```

2. `MaxInFlight` / `EventTimeout` / `RecipientTimeout` **不在 wiring 传值**（走 TASK-05 文档化默认 8 / 60s / 10s）：FR-11 不新增配置项、不新增环境变量、不新增 feature flag。
3. `AppURL` 只能来自既有 `appURLFromEnv()`（`router.go:121`，`MULTICA_APP_URL` → `FRONTEND_ORIGIN` → `""`），不新增解析逻辑。
4. wiring 位置必须在 `h.LarkAPIClient` / `h.LarkInstallations` 可能被赋值之后（即 lark if/else 整块之后），否则未启用与已启用两种形态都会拿到 nil。
5. 注释英文；不引入新 import 之外的改动（`lark` 包已在 `router.go` import）。

## 验收条件

1. **位置断言（静态）**：`grep -n "NewApprovalReminder" server/cmd/server/router.go` 命中 1 处，且其行号 **大于** `grep -n 'lark integration disabled (MULTICA_LARK_SECRET_KEY not set)' router.go` 的行号（证明在条件块之外、之后）。测试内以读源码文件方式做该断言，或用等价的行号比较断言，防止后续重构把它挪回条件块内。
2. **未启用形态（AC-12）**：不设 `MULTICA_LARK_SECRET_KEY` 构造 router（或直接按 wiring 形态构造 `ApprovalReminderConfig{Pool: <零调用 pool 替身或 nil>, AppURL: "https://multica.test"}` 后 `Register(bus)`）→ 发布一条真事件后：进程存活、恰一条 `result=skipped reason=feishu-disabled` 事件级日志、零真实飞书请求、**零收件人查询**（pool 替身调用计数为 0）。
3. **typed-nil 防护**：断言 `reminderCfg.Client` / `reminderCfg.Credentials` 在依赖为 nil 时**保持 nil 接口**（`== nil` 为真），而非持有 typed-nil；把 wiring 片段改成无条件赋值可复现 panic —— 该负向路径以注释形式在测试中说明，不作为断言执行。
4. **AC-11 端到端**：客户端替身在 `SendApprovalReminderCard` 上阻塞至超时的前提下，`SyncService.HandleCREvents` 的响应时延与"未注册提醒器"基线同量级（同一测试内两次测量，差值 < 50ms），CR 投影结果不变、`needs_reconcile` 未被置位、无回滚。该用例可放在 `cmd/server` 包（用 `events.Bus` 直连 governance 与提醒器两侧），无需起完整 HTTP server。
5. `cd server && go build ./... && go vet ./cmd/server/` 零报告；`go test ./cmd/server/ -run 'ApprovalReminder' -v -count=1` 全部 `--- PASS`；`go test ./cmd/server/ -count=1` 整包通过（对照 CUSTOM.md 基线排除既有失败）。
6. `git diff --name-only` 在本 TASK 范围内只有 `cmd/server/router.go` + 新增测试文件；`git diff cmd/server/listeners.go` 为空。

## 完成标志

上述 6 条全通过；`git diff --stat cmd/server/router.go` 净增行数 ≤ 15（wiring + 注释）；`crctl task done CR-2026-051 --task CR-2026-051-TASK-07 --workspace <kb worktree>` 已登记。

## 接口契约

- **消费**（签名固定）：TASK-05 的 `lark.ApprovalReminderConfig{Pool *pgxpool.Pool; Client APIClient; Credentials installationCredentialSource; AppURL string; Logger *slog.Logger; MaxInFlight int; EventTimeout, RecipientTimeout time.Duration}`、`lark.NewApprovalReminder(cfg) *lark.ApprovalReminder`、`(*lark.ApprovalReminder).Register(bus *events.Bus)`；TASK-02 的发布点（端到端用例通过 `governance.NewSyncService(pool, bus)` + `HandleCREvents` 触发）。既有：`appURLFromEnv() string`（`router.go:121`）、`h.LarkAPIClient`、`h.LarkInstallations`（`handler.Handler` 字段，飞书未启用时为 nil）、`NewRouterWithOptions` 作用域内的 `pool` / `bus`。
- **产出**：无导出符号。产出的是**装配事实**：`Register` 在任何配置下都被调用一次（TASK-08 的 AC-8/AC-12 汇总以此为据）。
