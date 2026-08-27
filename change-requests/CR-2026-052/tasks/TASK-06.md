---
id: CR-2026-052-TASK-06
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "multica 集成测试：approval_continuation_test + prompt_test + deliverGrants fake"
slug: multica-approval-continuation-tests
status: pending
estimate: 10h
depends-on: ["CR-2026-052-TASK-05"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-06：multica 集成测试

## 1. 任务描述

新增/扩展 DB 集成测试，覆盖 PRD AC-1~AC-10 与 SDD §7.4 全部关键断言（含 TD-BL-5/8/10/11/12 的回归守卫）。对应 SDD §7.4。

## 2. 涉及文件 / 模块

- 新建 `server/internal/governance/approval_continuation_test.go`
- 修改 `server/internal/daemon/prompt_test.go`（合并 handoff 进 opening prompt 断言）
- 复用 `server/internal/daemon/` 既有 deliverGrants fake fetcher（AC-4）

## 3. 实现要点（SDD §7.4）

### approval_continuation_test.go（新）

- **AC-1**：同 approval_record 两次 ACK → `kind=approval_continuation` 且 `ref_id=record.id` 任务恰 1 条；第二次幂等返回。
- **AC-2**：四 stage（requirement/tech-design/dev-start/code）各 approve+reject → 各 1 条任务，上下文含 stage/decision；reject 不产生"中断"状态。
- **AC-3**：注入 tx 错误 → `delivered_at` NULL + HTTP 5xx；修复后下一周期成功。
- **AC-5a~f**：阶梯 1/2/3 各路径；`slot-deferred` deferred 行进 257 谓词外、`PromoteDueDeferredTasksForRuntime` 槽释放后翻 queued。
- **AC-5g（claim-vs-append 可执行时序）**：claim 先提交 → 行已 dispatched，ACK 不更新它，创建恰 1 条 deferred 新后继，旧 claim response 不含新 record；ACK 锁读先持锁 → claim 阻塞，合并提交后 claim response/opening prompt 含两条记录四字段。
- **AC-5i（dispatched/waiting_local_directory）**：先取 claim response（停在两状态），再 ACK 新审批；旧 response/daemon Task 快照不变、旧 DB handoff 不追加；新 queued/deferred 后继独立承载新 record，前驱完成后 claim 的 opening prompt 才含四字段。不得以"旧任务读 grants"替代此 prompt 断言。
- **AC-6**：无 shell issue/squad/leader deleted 三情形 → 保持未 ACK + 原因码，不派发。
- **AC-6b/6c（FOR SHARE race，TD-BL-5/8）**：并发 `issue.assignee_id` 重指派 / `cr.shell_issue_id` 投影写（FOR NO KEY UPDATE）被阻塞到 ACK 提交；含"FOR KEY SHARE 下不成立"的锁级回归守卫。
- **AC-6d（TD-BL-10 同名 CR 跨 workspace 并发隔离）**：workspace A/B 各建 `CR-2026-052`，并发 ACK → 各 1 条 `approval_workspace_id` 与本 tenant 相等后继，471 不跨 tenant 冲突；A 发第二审批只合并 A 行，B 行 approvals[]/handoff/updated_at 不变；用 A 的 ws 调 record/CR fallback 查 B 的 id/cr 均 0 行。
- **AC-7**：历史 `delivered_at` 非空行不产生任务，无回填迁移。
- **AC-8**：上下文无"状态→下一步"映射；Runner 关闭时相关路径零调用（日志/覆盖断言），ACK 仍生效。
- **AC-9a~d（TD-BL-12）**：`SetGrantAckHandler` 收到与 approval_record 一致的 GrantAckEvent；error→5xx/回滚/`delivered_at` NULL；handler 零副作用可被 daemon 重放；`SetGrantAckCommittedHandler`/WakeGrant error 发生在 COMMIT 后仅日志且 HTTP 2xx；router 开启时按 `ValidateGrantAck→SetGrantAckHandler`、`WakeGrant→SetGrantAckCommittedHandler` 接线，关闭时两钩空但 continuation 入队仍成功。
- **AC-10**：不新增执行状态列；续跑任务完成后进度在既有任务/issue 展示面可见。

### prompt_test.go（扩展）

仅对未 claim 的 queued/deferred 后继断言合并 handoff 逐字进入 opening prompt；dispatched/waiting 用 AC-5i 双任务时序断言，不再断言已快照 prompt 会变化。

### deliverGrants fake（AC-4）

ACK 5xx → grants 保持 pending → 下一 15s 周期重投递成功。

## 4. 验收条件

1. `(cd server && go test ./internal/governance/... ./internal/daemon/...)` 全 PASS（不含 pre-existing 无关失败）。
2. AC-1~AC-10 逐项有对应 test case；AC-5g/5i/6b/6c/6d/9a~d 守卫存在且断言方向正确（含 FOR KEY SHARE 下不成立的回归）。
3. 无断言依赖"运行中任务读 grants 目录"替代 prompt 可达性。

## 5. 完成标志

测试文件落盘 + `go test` 通过 + AC 覆盖矩阵可逐条回指（plan §5.1）；预存失败须与本次改动无关并注明。

## 6. 接口契约

- **消费**：TASK-05 全链（经传递依赖含 TASK-03/04）；既有 deliverGrants fake。
- **产出**：无（测试不暴露生产接口）。
