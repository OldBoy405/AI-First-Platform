---
id: CR-2026-002-TASK-02
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: crctl outbox 事件通道（advance/approve/push 三挂点）
status: done
estimate: 8h
depends-on: []
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
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

## 完成记录（2026-07-31）

- **提交**：tools@1333226（custom/main，已推 origin）。
- **emitOutboxEvent()**：单函数实现，临时名 + rename 原子写；事件写失败只记 audit（EMIT_FAILED），**不阻塞主操作**——outbox 是投影通道，git 是权威。文件名 `{utc-ts}-{cr}-{kind}-{shortsha|nosha}.json` 字典序即时序。
- **三挂点落位**：
  - advance 成功 → `status` 事件（from/to/trigger/actor；有 commit 时带 HEAD sha，`--embedded`/`--no-commit` 留空）；
  - approve → **不单独发事件**（设计决策）：级联 advance 的那条 status 事件携带 `evidence`（approvalStages 声明的全部证据文件 → 行尾规范化后 sha256），一个 approve 恰好一条事件，避免与去重键 `(cr_id, commit_sha, event_kind)` 双发冲突；
  - `git push` 成功 → `checkpoint` 事件（被推仓 HEAD sha + headMessage + pushed args），CR-ID 从 HEAD 提交信息/分支参数按 `CR-\d{4}-\d{3}` 提取，提不到则不发（非 CR 上下文推送）；`--delete` 分支删除不发。
- **测试 14/14**：新增 3 用例（advance→合 schema 事件+空 sha；非法转换→零事件；真实 bare-origin push→checkpoint 带 40 位 sha 与提取的 CR-ID）。过程中修了一个测试夹具错误：CR-TEST-1 不符合生产 ID 正则，push 用例改用 CR-2026-001 格式。
- **备注**：本工作区此后每次 advance 都会积累 outbox 事件，T06 daemon 采集器上线前无人消费——无害（gitignored），且届时正好是现成的补传测试数据。
