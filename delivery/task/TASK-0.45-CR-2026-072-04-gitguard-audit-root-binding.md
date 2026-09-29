---
spec-id: ai-first-platform
version: "0.45"
id: CR-2026-072-TASK-04
type: TASK
cr-ref: CR-2026-072
plan-ref: "change-requests/CR-2026-072/plan.md"
sdd-ref: "change-requests/CR-2026-072/sdd.md"
target-version: 0.45
title: gitguard 拒绝审计归属：独立任务审计根
slug: gitguard-audit-root-binding
status: pending
estimate: 4h
depends-on: ["CR-2026-072-TASK-03"]
created: 2026-09-28T23:52:00+08:00
---

## 1. 任务描述

`server/cmd/multica/cmd_gitguard.go` 的 deny 分支停止以 `os.Getenv("CRCTL_WORKSPACE")` 决定拒绝审计归属：审计根改由 TASK-03 注入的专用内部环境键 `CRCTL_TASK_AUDIT_ROOT` 提供（有可信任务绑定才存在）。gitguard 对被禁 Git 操作的拒绝行为与 `FORBIDDEN_*` 错误码完全不变；有绑定 → `SpoolDenial` 写入本任务项目 outbox；无绑定 → 不写任何 outbox（拒绝动作照常 fail-closed，仅跳过会产生错误归属的审计），审计失败不解除拒绝。

## 2. 涉及文件 / 模块

- `server/cmd/multica/cmd_gitguard.go`（:58）：`_ = gitguard.SpoolDenial(os.Getenv("CRCTL_WORKSPACE"), caller, sub, ge.Code)` 改为仅当 `os.Getenv("CRCTL_TASK_AUDIT_ROOT")` 非空时以该值为根调用 `gitguard.SpoolDenial(root, caller, sub, ge.Code)`；空值时跳过 SpoolDenial
- 对应 Go 测试文件（gitguard deny/审计归属用例）

## 3. 实现要点

- SDD §4.4 / §2 数据模型行 `.crctl/outbox audit`：gitguard 仅有由 daemon 本任务项目资源/Pipeline 预检得到的独立审计根时写入；不再用 `CRCTL_WORKSPACE` 决定审计归属。
- 拒绝优先：先拒绝违规 git，再处理审计；未绑定时拒绝错误码不变（`FORBIDDEN_*` 原样返回），不因缺审计根改变拒绝语义，也不因审计失败放行（保留 `_ =` 容错调用形态）。
- 不扩展事务面（issue 范围第 4 条）：只调整这一个接点。

## 4. 验收条件

1. Go 单测：deny 命令返回的 `FORBIDDEN_*` 错误码与现状逐字一致（有/无审计根两态均拒绝）。
2. Go 单测：设置 `CRCTL_TASK_AUDIT_ROOT` → 拒绝事件写入该根对应项目 outbox；未设置 → 不产生任何 outbox 写入（含不落入其他项目目录）。
3. `go test ./...`（cwd `server`）全量通过。

## 5. 完成标志

cmd_gitguard.go 审计根切换落地；`go test ./...` 全绿；改动以 `[cr] ` 前缀 commit 提交；`CUSTOM.md` 登记（SDD §9 scope_in）。

## 6. 接口契约

- **消费**：TASK-03 产出的 `CRCTL_TASK_AUDIT_ROOT`（daemon agentEnv 最终叠加后写入；Pipeline 任务 = 预检 root，普通任务 = 唯一匹配且验证通过的 local_directory 根，无绑定不存在）；既有 `gitguard.SpoolDenial(root, caller, sub, ge.Code)` 签名与 dep-8 deny 分支语义。
- **产出**：gitguard 审计归属契约 —— 审计根仅来源于 `CRCTL_TASK_AUDIT_ROOT`；`FORBIDDEN_*` 拒绝语义与错误码不变；供 TASK-05 回归覆盖（有根归本项目 / 无根不写两态）。
