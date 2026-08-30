---
id: CR-2026-056-TASK-11
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M6 集成验证、CUSTOM.md 登记与测试证据
slug: m6-integration-verification-evidence
status: pending
estimate: 10h
depends-on: [CR-2026-056-TASK-08, CR-2026-056-TASK-09, CR-2026-056-TASK-10, CR-2026-056-TASK-13]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

全量集成验证（三组 `go test` + 前端测试）、§4.14 并发夹具与实施期必过夹具收口、`CUSTOM.md` 台账登记、`write-test-report` 生成测试证据。对应 plan.md M6。

输入条件：TASK-01~10 与 TASK-13 全部完成。

## 涉及文件 / 模块

- multica CR worktree：`server/internal/handler/`、`server/pkg/agent/`、`server/internal/service/` 测试；`packages/core/api/schemas.test.ts`、`packages/views/locales/parity.test.ts`、team-agent / private-ask 组件测
- `CUSTOM.md`（multica 仓，登记）
- knowledge-base CR worktree：`change-requests/CR-2026-056/test-report.md`（`write-test-report` skill 产出）

## 实现要点

1. 测试命令全跑并留档（Go 模块在 `server/go.mod`，命令与 TASK-01 基线同一组，BLOCK-002）：
   - `cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1`
   - `cd server && go test ./internal/service/ -count=1 -run ChatDraftAttachment`
   - `cd server && go build ./...`
   - 前端：`packages/core/api/schemas.test.ts`、locales parity、team-agent / private-ask 组件测。
2. 必过夹具逐项核对（SDD §6.2 实施期清单 + §4.14）：
   - §4.14 夹具 1：GET 收养检查 ∥ 转投 Ensure——结束后至多一行 `project_chat`，不得一转投旧容器 + 一 session 新容器；
   - §4.14 夹具 2：转投创建后首次 Bind——CAS 收养同一 Issue，禁止第二行；
   - §4.14 夹具 3：同 `created_at` 双行 `GetProjectChatIssue` 的 `:one` 固定返回较小 `id`；
   - 升级收养与「升级后未发送即换绑」（§2.1）；换绑双容器唯一性（AC-18）；GET/PATCH 与换绑并发 CAS；首次发送失败回滚五类零残留（AC-15，BLOCK-003）；POST container 校验失败不建 Issue（AC-23/24）；merge-forward `chat_config`（AC-7/10）；sweeper ∥ Bind 竞态（AC-28）；空 model provider 矩阵（AC-9/24）；catalog LiveLoad 超时（AC-24）；Private Ask 跨 workspace 0 行（Hard Invariant 1）；Private Ask 回填/三态/403/发送快照（AC-3/19/25，TASK-13）；Private Ask 新建快照首次 GET（`*_source=session_default`，BLOCK-004）；普通 `chat_session`（`project_id IS NULL`）发送零变化回归（BLOCK-006）；`session_id` UUID 保留与硬降级（BLOCK-007，与 `schemas.test.ts` 对齐）；PATCH `FOR UPDATE` 行锁并发（PATCH∥发送 / PATCH∥PATCH）与失败回滚（BLOCK-008）；project clear ∥ send 与 PATCH ∥ send 事务边界夹具——两顺序逐项断言（`base_*` 单一一致值、快照与事后 GET/DB 一致）、catalog 失败注入 / 入队点失败注入（生产解绑时序 + latch，回填后触发 carrier 守卫）+ 查询边界 INSERT 0 行夹具与事务后零残留（BLOCK-009/010）。
3. AC-1~AC-28 逐条对照，收集可追溯证据（测试名/日志/断言位置）。
4. `CUSTOM.md` 登记：对照当时实际结构，编号顺延 #58 之后；本 CR 新/改文件与 `// AIFIRST:` 挂钩点全覆盖（AGENTS.md 纪律：登记以彼时 CUSTOM.md 现状为准）。
5. `write-test-report` 生成 `test-report.md`；任何测试失败按 reviewLoop 回 `implement-code` 自修复，不手改测试账本。
6. KG-1（转投无 `chat_config` 快照）/ KG-2（换绑后转投仍写旧 Issue）为已知缺口、归属 CR-B/CR-C，test-report 明示，验收不得当本 CR 缺陷。

## 验收条件

1. 三组 `go test` 与 `-run ChatDraftAttachment` 全绿；前端三类测试全绿（输出留档）。
2. 第 2 条必过夹具清单逐项有测试/日志证据。
3. `CUSTOM.md` diff 完成登记（新/改文件 + 挂钩点）。
4. `test-report.md` 结论为 pass，AC-1~AC-28 证据可追溯；KG-1/KG-2 明示归属。

## 完成标志

`write-test-report` 输出 pass 且 `test-report.md` 提交。

## 接口契约

- 消费：TASK-01~10 全部产物（代码、测试、CUSTOM.md 登记素材）。
- 产出：`change-requests/CR-2026-056/test-report.md` + `CUSTOM.md` 登记——供 TASK-12（code review / 人工审批 / 合并）消费。
