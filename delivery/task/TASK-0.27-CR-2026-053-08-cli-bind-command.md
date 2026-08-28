---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-053-TASK-08
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: CLI 薄包装命令 multica cr bind-current-task <cr-id>
slug: cli-bind-command
status: pending
estimate: 1h
depends-on: [CR-2026-053-TASK-05]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

Multica CLI 新增薄包装命令（cobra，沿用 `server/cmd/multica/cmd_*.go` 惯例）：

```bash
multica cr bind-current-task <cr-id>
```

仅把 `mat_` task token 与 CR-ID 发给 `POST /api/crs/{cr_id}/bind-current-task` 接口，透传结构化结果。不做业务判断、不落账本（SDD §3.3，FR-B1）。

## 涉及文件 / 模块

- `server/cmd/multica/cmd_cr.go` — 新增 `cr` 命令组 + `bind-current-task` 子命令
- `server/cmd/multica/main.go` — `rootCmd.AddCommand(crCmd)` 注册
- `server/cmd/multica/cmd_cr_test.go` — 命令单测

## 实现要点

参考 SDD §3.3 与既有 `cmd_repo.go`/`cmd_issue.go` 写法：
- 命令名按 CLI 命名惯例（`cr bind-current-task <cr-id>`）
- 只透传 task token + CR-ID，不构造请求体（身份字段服务端派生）
- 透传响应 `{ cr_id, task_id, issue_id, project_id, changed }` 与七种错误码

## 验收条件

1. `go run ./server/cmd/multica cr bind-current-task --help` 成功，命令注册无 panic
2. `go test ./server/cmd/multica/ -run TestCrBindCurrentTask` 通过（含七种错误码透传断言）

## 完成标志

- CLI 命令与单测已 commit

## 接口契约

**消费**:
- `POST /api/crs/{cr_id}/bind-current-task` 接口（CR-2026-053-TASK-05）

**产出**:
- 命令行输出接口响应
