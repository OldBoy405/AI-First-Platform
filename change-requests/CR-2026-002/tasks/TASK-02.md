---
id: CR-2026-002-TASK-02
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: crctl outbox 事件通道（advance/approve/push 三挂点）
status: pending
estimate: 8h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-1/D1：crctl 在 `advance`、`approve`、`git push` 成功后向 `{workspace}/.crctl/outbox/` 原子写事件文件（临时名+rename）。事件 schema v1 见 PRD FR-1 与源方案 §A.2。仓库：tools。

## 涉及文件
- 修改 `skills/shared/crctl/scripts/crctl.mjs`：casWrite 收尾、cmdApprove 成功路径、cmdGit push 成功路径各一个挂点（约 60 行）+ `emitOutboxEvent()` 单函数
- 测试 `skills/shared/crctl/scripts/test/crctl.test.mjs` 追加用例

## 实现要点
- 文件名 `{utc-ts}-{cr_id}-{event_kind}-{short_sha}.json`；utc-ts 用 ISO 紧凑格式保证字典序即时序。
- `--embedded` 时 commit_sha 留空；push 挂点补发含 `rev-parse HEAD` 的事件（源方案 §A.5）。
- outbox 目录复用 `.crctl/` 既有自动 .gitignore 机制。
- 零网络调用——只写文件（NFR-1）。

## 验收条件
1. 测试：advance 成功 → outbox 出现事件文件且字段合 schema（AC-1 前半）。
2. 测试：embedded 模式事件 commit_sha 为空串，push 后出现补全事件。
3. 测试：advance 失败（gate 拒绝）时**不**写事件。

## 完成标志
tools 测试全绿（含新增 ≥3 用例）+ 完成记录回填。
