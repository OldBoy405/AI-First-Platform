---
id: CR-2026-053-TASK-08
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: CLI 薄包装命令
slug: cli-bind-command
status: pending
estimate: 1h
depends-on: [CR-2026-053-TASK-05]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

Multica CLI 新增薄包装命令：

```bash
multica cr bind-current-task <cr-id>
```

仅把 `mat_` task token 与 CR-ID 发给 `POST /api/crs/{cr_id}/bind-current-task` 接口，透传结构化结果。不做业务判断、不落账本。

## 涉及文件 / 模块

- CLI 命令文件（按既有命名惯例）

## 实现要点

参考 SDD §3.3:
- 命令名按 CLI 命名惯例
- 只透传 token + CR-ID
- 不构造请求体
- 透传响应结果

## 验收条件

1. 命令可执行
2. 错误码透传正确

## 完成标志

- CLI 命令已 commit

## 接口契约

**消费**:
- `POST /api/crs/{cr_id}/bind-current-task` 接口（CR-2026-053-TASK-05）

**产出**:
- 命令行输出接口响应
