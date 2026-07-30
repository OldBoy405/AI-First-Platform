---
id: CR-2026-001-TASK-01
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: fork Multica、剥离云端专属能力并在内网起全栈
status: in-progress
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
