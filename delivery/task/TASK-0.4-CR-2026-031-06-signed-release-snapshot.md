---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-06
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现 signed release snapshot 与漂移回退
slug: signed-release-snapshot
status: pending
estimate: 14h
depends-on: [CR-2026-031-TASK-02, CR-2026-031-TASK-03, CR-2026-031-TASK-04]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

扩展 code review/approval，机器注入并签入逐仓 source SHA 与受控 artifact digest；新增统一 release-drift 状态转换和零写入漂移处理。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/gates.json`
- `dir-graph.yaml`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- `review-record --stage code` 从真实 pushed ref/worktree 注入，拒绝 payload 覆盖。
- artifact 路径排序，内容 CRLF→LF 后 SHA-256；approve TTY/grant 均重核并原样复制。
- 新增 `code-approved -> developing`，trigger 精确为 `merge-feature-branch:release-drift -> implement-code`；口径同步为 28/50。
- PRD/SDD drift 返回 `APPROVED_ARTIFACT_DRIFT`；publish 后任何 drift hard block。

# 4. 验收条件

1. payload 伪造 release-subjects 被拒；review/approve 前 ref、HEAD、TASK/artifact 任一漂移均有对应零写入断言。
2. TTY 与 Ed25519 approval 复制的 release-subjects 字节语义一致并被 approval digest 签入。
3. code/source/TASK 零 publish 漂移只走单一回退转换；状态机声明/展开断言为 28/50。

# 5. 完成标志

signed snapshot 成为 merge/writeback 唯一输入，漂移测试通过，任务状态登记 done。

# 6. 接口契约

消费：TASK-03 `resolveRepositories`、TASK-04 recoverable writes。

产出：`buildReleaseSubjects(ctx: object,cr:string): Promise<{version:1,repositories:Array<{repo:string,remoteRef:string,reviewedSourceSha:string}>,artifacts:{algorithm:'sha256',canonicalization:string,files:Array<{path:string,sha256:string}>,digest:string}}>`；`verifyReleaseSubjects(ctx: object,cr:string,snapshot:object): Promise<{ok:true}|{ok:false,kind:'code'|'task'|'prd'|'sdd',details:object}>`。TASK-07/08 精确消费。
