---
id: CR-2026-001-TASK-01
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: fork Multica、剥离云端专属能力并在内网起全栈
status: done
estimate: 24h
depends-on: []
assignee: ""
created: "2026-07-30T22:43:34+08:00"
---

# TASK-01 fork Multica、剥离云端专属能力并在内网起全栈

## 任务描述

对应 FR-1 / SDD 组件 `selfhost-compose`。以现有本地 clone（`../multica`，含 `CONTRIBUTING.AIFIRST.md` 隔离约定）为基础建立 fork 工作分支，通过配置层剥离云端专属能力，在内网单机把全栈跑起来。

## 涉及文件 / 模块

- fork 仓库的 Docker Compose / Helm / Makefile（`make selfhost` 路径）——只改配置与环境变量，不动 Go 代码
- 环境配置：`DISABLE_WORKSPACE_CREATION=true`、`ALLOWED_EMAIL_DOMAINS`、`mcn_` 凭据留空
- Stripe/计费路由的挂载点（摘除挂载，不删代码）

## 实现要点（SDD §6 FR-1 行）

- `mcn_` 云节点：中间件分支保留、配置为空 → 天然 401，零代码改动
- 多 workspace 注册：用 Multica 现成开关关闭，无代码改动
- 所有改动记入 fork 仓库 `CUSTOM.md` 台账（CONTRIBUTING.AIFIRST 规则二）

## 验收条件

1. 内网执行 `make selfhost`（或等价的 ≤2 条命令）后，后端、前端、Postgres 全部起来，浏览器可访问登录页
2. 访问任一 Stripe/计费路由返回 404（已摘除）；携带空 `mcn_` 凭据访问云节点端点返回 401
3. 尝试注册第二个 workspace 被拒绝（`DISABLE_WORKSPACE_CREATION` 生效）

## 完成标志

三条验收全过 + 启动步骤与环境差异记录进 fork 仓库 `CUSTOM.md`。

## 完成记录（2026-07-30）

- **代码改动**：`server/cmd/server/router.go` 摘除 Stripe webhook 与 `/api/cloud-billing` 两处挂载（handler 保留，`// AIFIRST:` 标记）；`go build` + `go vet` 通过。fork worktree commit（`requirement/CR-2026-001` 分支）。
- **零代码确认**：注册管控（`ALLOW_SIGNUP`/`ALLOWED_EMAIL_DOMAINS`/`DISABLE_WORKSPACE_CREATION`）与 `mcn_` 云节点剥离上游本就支持纯配置实现，记入 `CUSTOM.md` C1–C3 约定。
- **起全栈**：`make selfhost-build COMPOSE=docker-compose.exe`（本机 Docker 装在 D 盘 + compose 用 standalone v5.1.3，故需覆盖 COMPOSE 变量），postgres/backend/frontend 三容器全部启动，`/health` 200、前端 200。
- **验收 1** ✅ 全栈起来可访问（单条 make 命令）。
- **验收 2** ✅ `POST /api/webhooks/stripe` → 404；`GET /api/cloud-billing/balance` → 404；附加验证 `mcn_` 假令牌 → 401 `invalid token`。
- **验收 3** ⚠️ 机制级验证通过：`.env` 置 `DISABLE_WORKSPACE_CREATION=true` 重建 backend 后 `/api/config` 报 `workspace_creation_disabled: true`（上游 `workspace.go` 的服务端 gate 由该配置驱动）；随后按 C2 两阶段约定恢复为空（引导态）。**字面场景"注册第二个 workspace 被拒"未跑**——需要先有真实账号和第一个 workspace，留到首次实际使用时补验，记入 test-report 遗留项。
- **环境坑**：`.env` CRLF→LF 行尾变化导致 Postgres 卷密码不一致（SASL auth failed），`down -v` 重建解决，已记入 `CUSTOM.md` C4。
