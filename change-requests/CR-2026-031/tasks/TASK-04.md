---
id: CR-2026-031-TASK-04
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现 durable journal 锁与 recoverable write-set
slug: durable-transaction-core
status: pending
estimate: 16h
depends-on: [CR-2026-031-TASK-01]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

新增 `durable-tx.mjs`，实现 SDD §3 的公共 envelope、目录锁、durable save、单/多文件 recoverable write-set、fault injection 和 blob cleanup。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/durable-tx.mjs`
- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- 仅 Node 标准库；文件/父目录 fsync，temp 同目录 rename。
- lock owner 校验 token/pid/hostname；EPERM live、ESRCH dead，无 TTL/force unlock。
- write-set 按 before/after/third value 执行 redo/skip/conflict。
- envelope 只允许 op 对应一个 payload；模块不理解业务 phase/Git。

# 4. 验收条件

1. 真实 kill/restart 在每个 rename 前后都得到 redo、skip 或 `TX_RECOVERY_CONFLICT`，不覆盖第三值。
2. live PID、EPERM、ESRCH、PID reuse、foreign host、token mismatch 全矩阵通过。
3. one-entry write-set 替代旧单文件/多文件重复 CAS 算法；journal/blob cleanup 幂等。

# 5. 完成标志

公共持久化原语通过 fault matrix，无业务 runner/class/plugin，任务状态登记 done。

# 6. 接口契约

消费：TASK-01 约定的 `CRCTL_FAULT_POINT`。

产出：`acquireLock({root:string,scope:string,op:string,cr?:string}): Promise<{token:string,release():Promise<void>}>`；`loadOrCreateJournal(args): Promise<object>`；`saveJournal({path:string,journal:object}): Promise<void>`；`recoverWriteSet({root:string}): Promise<{changed:boolean}>`；`applyWriteSet({root:string,txId:string,entries:Array<{path:string,beforeSha256:string|null,afterSha256:string,blob:string}>}): Promise<{changed:boolean}>`；`fault(point:string,context?:object): void`；`cleanupTxBlobs({root:string,txId:string}): Promise<void>`。TASK-05～09 精确消费。
