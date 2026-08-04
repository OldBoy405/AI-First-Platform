---
id: CR-2026-018-TASK-03
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: _backlog.yml 升级 schema v2 + validate 规则调整（FR-3）
slug: backlog-schema-v2
status: pending
estimate: 8h
depends-on: ["CR-2026-018-TASK-02"]
assignee: ""
created: "2026-08-04T16:40:00+08:00"
---

## 1. 任务描述

实现 SDD §2.2/§3.1：为 `_backlog.yml` 定义 `cr-backlog/v2` schema（条目不再含权威 `status`/`updated-at`），调整 `cmdValidate`（:986 起，条目段 :1018-1024）：v2 schema 下条目若仍含 `status` 行，输出 `LEGACY_STATUS_FIELD` 告警（非阻断）；v1 schema（无 `schema` 字段或标 v1）下若 `status` 与 cr.md 不一致，输出漂移告警（迁移期退出码 0）。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/crctl.mjs`：`cmdValidate` 条目校验段
- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`：新增用例

## 3. 实现要点

- schema 版本判别：读 `_backlog.yml` 顶层 `schema` 字段，`cr-backlog/v2` 或缺省视具体值判定；未来注册新 CR（TASK-08 中 requirement-register 文档修订对应）产出的条目应天然符合 v2（不写 status）。
- 本任务不改变 workspace 探测逻辑（FR-4，crctl.mjs:289 不动，已由 SDD 标注为仅测试项，此处不重复实现，仅在验收条件中加回归断言）。

## 4. 验收条件

- AC-3：`crctl validate` 对新布局（v2、无 status）workspace 全绿；对 v2 但条目仍含 status 的 workspace 输出 `LEGACY_STATUS_FIELD` 警告且退出码 0；对 v1 且 status 与 cr.md 不一致的 workspace 输出漂移告警且退出码 0。
- 回归断言（FR-4）：`--workspace` 缺省探测在只含 `_backlog.yml`（无论 v1/v2）的目录树中仍能命中。
- 现有 21 个用例全绿。

## 5. 完成标志

`cmdValidate` 新规则落地；AC-3 三种场景测试通过；FR-4 回归断言通过；lint 零报错。
