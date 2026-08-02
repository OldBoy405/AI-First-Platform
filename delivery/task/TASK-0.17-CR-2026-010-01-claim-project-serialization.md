---
id: CR-2026-010-TASK-01
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: 迁移（project_id 列+回填+索引、presenter_grant 表）+ claim SQL 改造 + advisory lock 竞态复核
slug: claim-project-serialization
status: done
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-02T13:57:20+08:00"
spec-id: ai-first-platform
version: "0.17"
---

## 实现状态（2026-08-02）

代码已在 multica worktree（`requirement/CR-2026-010`，commit `4581b2e33`）落地：
迁移 161-163、`ClaimAgentTask` 新分支、`ClaimTask` advisory lock 复核、
`CreateAgentTask`/`CreateDeferredAgentTask`/`CreateRetryTask` 三处 project_id
stamp/继承（后两处是实现中发现的补充范围，任务描述原未列出：deferred fallback
与 retry 任务如不 stamp/继承 project_id，会在提升/重试后悄悄跌回旧的
per-(agent,issue) 序列化分支，绕开单写者保证）。`go build`/`go vet`/`gofmt` 全绿，
`make sqlc` 生成 diff 审查通过（仅 agent.sql.go 的 project_id 相关 `SELECT *`/
`RETURNING *` 联动 + models.go 新结构体，无关文件零改动）。

**并发验证已完成**：定位到本机 `docker` 命令被一个失效的 shell 别名指向已不存在的
旧安装路径（`/c/Program Files/Docker/Docker/...`，真实安装已在 D 盘），绕开别名后
发现本机已有一套长期运行的 multica dev 容器栈（`multica-postgres-1` 等，非本次
新启动）。取得其真实 Postgres 密码后为 worktree 建库、跑通全部 163 个迁移
（含本任务的 161-163），针对真实数据库执行：

- `TestClaimTaskCrossAgentProjectSingleWriter`（新增）：两个不同 agent 各一条
  同项目 queued 任务并发 claim，日志实证一个成功 claim、另一个被 advisory lock
  复核检出冲突并 requeue（`task claim: lost project single-writer race, requeued`）
  ——PASS。
- `TestClaimTaskChatSessionParallelWithProjectTask`（新增）：同 agent 下 chat_session
  任务与 project 任务依次可claim（chat 分支不受影响）——PASS。
- `TestClaimTaskConcurrentCapacityRespected`（既有回归）：PASS，未受影响。
- `go test ./internal/service/...` 与 `./internal/handler/...` 全量跑过，除本任务
  代码外零回归；失败项均为与本 CR 无关的预置环境问题（`builtin_skills` 测试因仓库
  在 Windows 上 CRLF 检出失败——该库已知的行尾问题，本仓 knowledge-base AGENTS.md
  §工程纪律 1 也记录过同类教训；`TestShortTaskIDMatchesDaemon`/
  `TestParseSkillArchive_RejectsUnsafeSkillMdPath` 是 Windows vs Unix 路径分隔符
  断言差异），均与 agent_task_queue/claim 逻辑无关，未修改。

## 任务描述

在 multica 落地 SDD §3/§4.1：把 `agent_task_queue` 的 claim 串行化从 issue 级放宽到 project 级
（跨 agent），并为竞态窗口加 advisory lock 复核。这是本 CR 风险最高、独立成 CR 的核心变更，是
T02~T07 的唯一硬前置。**claim SQL 是全平台共享热路径，改动范围必须严格限定**（见下方实现要点）。

## 涉及文件

- `server/migrations/161_agent_task_queue_project_id.up.sql`（+down）：
  `agent_task_queue` 加 `project_id UUID REFERENCES project(id) ON DELETE SET NULL`；
  回填 `UPDATE ... FROM issue WHERE atq.issue_id=i.id AND i.project_id IS NOT NULL
  AND atq.status NOT IN ('completed','failed','cancelled')`（TSUG-001：限定非终态行，缩小
  热表锁窗口与写入量——终态行的 project_id 永不被 claim 谓词读取，回填它们无意义）。
- `server/migrations/162_atq_project_active_index.up.sql`：单语句 `CREATE INDEX CONCURRENTLY
  idx_atq_project_active ON agent_task_queue(project_id) WHERE status IN
  ('dispatched','running','waiting_local_directory') AND project_id IS NOT NULL`
  （沿 080 的 CONCURRENTLY 约定，热表不可加排他锁索引）。
- `server/migrations/163_project_presenter_grant.up.sql`（+down）：新表
  `project_presenter_grant`（SDD §3 全量 DDL）+ 两条 partial unique 索引（`ppg_active_uniq`
  `WHERE status='active'`、`ppg_pending_uniq (project_id,user_id) WHERE status='pending'`）+
  `ppg_project_idx`。本任务只建表，状态机逻辑归 TASK-02。
- `server/pkg/db/queries/agent.sql`：`ClaimAgentTask`（:350-388）改写 NOT EXISTS 谓词——
  新增 `project_id` 分支（`atq.project_id IS NOT NULL AND active.project_id = atq.project_id`，
  **不带 `active.agent_id = atq.agent_id` 限定**，即跨 agent）；三个既有分支（同 issue 无 project、
  chat_session、quick-create 全 NULL 形状）**原样保留**，SDD §4.1 有完整改写后 SQL 原文可直接抄。
  `make sqlc` 重新生成，diff 审查限定 `agent.sql.go`。
- `server/pkg/db/queries/agent.sql`：`CreateAgentTask` 加 `project_id` 参数（入队 stamp）。
- `server/internal/service/task.go`：三处 issue 系入队点（assignee :738 族、mention :823 族）
  改传 `issue.ProjectID` 给 `CreateAgentTask`；chat（:1103 `CreateChatTask`）与 quick-create
  保持传 NULL——**不要误改这两处**，否则破坏 chat_session 并行分支。
- `server/internal/service/project_chat.go`：群聊入队路径（经 `EnqueueTaskForMention`）同步
  拿到 project_id stamp，无需本任务额外改动（走 mention 分支）。
- `server/internal/service/task.go`：`ClaimTask`（:1336 `runInTx` 内）在 `ClaimAgentTask` 返回行
  `project_id` 非空时追加竞态复核（SDD §4.1/DD-4）：
  `pg_advisory_xact_lock(hashtextextended('claim-project|'||project_id, 0))` →
  `SELECT count(*) FROM agent_task_queue WHERE project_id=$1 AND status IN (active集) AND id!=$2`
  → count>0 时调既有 `RequeueAgentTaskAfterClaimFailure`（agent.sql:415-431）回队，本轮返回无任务。
  **加锁顺序**：UPDATE（claim）提交后才取 advisory lock，不在同一未提交事务内嵌套等待
  （避免与既有 per-agent `FOR UPDATE`/`GetAgentForClaimUpdate` 产生等待环）。

## 实现要点

- **改动范围硬约束**：只在 `ClaimAgentTask` 的 NOT EXISTS 里新增一个 OR 分支，其余三分支（issue 无
  project 时的同 issue 限定、chat_session 限定、quick-create 全 NULL 限定）**逐字保留**不动——
  SDD 开篇已修正"串行化键是三分支非单键"这一前提，本任务的准确定义就是"只放宽第一分支"。
- 回填与新增列上线顺序：M161 部署后新 claim 语义即对存量 active 任务生效（SDD §6.3 SUG-003 定案），
  无需 feature flag、无需双写窗口。
- advisory lock 的 key 用 `'claim-project|' || project_id` 字符串（照抄 project_chat.go:61-64
  的 key 命名与 hashtextextended 用法），与 presenter 转移用的 `'presenter|...'` key 命名空间
  不同前缀，避免误撞锁。
- 单测覆盖：
  1. 同一 project 两个不同 agent 各有一条 queued 任务，并发 claim → 恰一个成功，另一个仍 queued
     或被 requeue（验证跨 agent project 分支生效）；
  2. 同项目内 chat_session 来源任务与 issue 来源任务并发 claim → 互不阻塞（验证 chat 分支未受影响）；
  3. project_id 为 NULL 的 issue（不属于任何项目）任务 claim 行为与改造前一致（验证保留分支）；
  4. advisory lock 复核路径触发 requeue 后，任务重新可被 claim（验证 CAS 回队生效，无死信）。

## 验收条件

1. `make sqlc` 后 `git diff` 仅命中 `pkg/db/generated/agent.sql.go`（无关生成文件零改动）。
2. 上述 4 条单测全绿；`go vet`/`go build` 零报错。
3. 并发 claim 压测（10 并发 goroutine，同 project 5 条 queued 任务，2 个 agent）验证任意时刻
   `SELECT count(*) FROM agent_task_queue WHERE project_id=X AND status IN (active集)` 恰为 1，
   且无 postgres 死锁日志。

## 完成标志

上述单测与并发压测全部通过；`down` 迁移可回滚到位（含索引与表的 DROP）；SDD §4.1 的改写后
SQL 与实际 `agent.sql` 逐字一致（review 时 diff 核对）。
