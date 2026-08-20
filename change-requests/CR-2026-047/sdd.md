---
id: CR-2026-047-sdd
type: SDD
cr-ref: CR-2026-047
title: P3 组织智能 CR-A：AI 成熟度看板（E1 快照 + E2 看板 + E3 周报）技术设计
status: draft
created: 2026-08-20T00:38:27+08:00
updated: 2026-08-20T02:25:29+08:00
---

# SDD — P3 组织智能 CR-A：AI 成熟度看板

> 本文档以 `prd.md` 为输入，描述 CR-A 的模块边界、数据模型、接口契约、关键算法、测试方案与技术选型。权威约束见 multica 根目录 `ARCHITECTURE.md`（硬不变量 1–9）与 `CLAUDE.md`（迁移/代码规则）。本 CR 修改 multica 自研代码时同步登记 `CUSTOM.md`；代码注释一律英文。
>
> **首轮评审回修**：本文已消费 `review-annotations/sdd.yml` attempt 1 的 B1–B6：迁移并发索引、历史快照边界、8 项公式、治理三态、完整 API 类型、daemon→server 周报回传与测试矩阵。

---

## 1. 架构概览

### 1.1 交付物、仓与模块边界

| 交付物 | 内容 | 落点仓 | 关键模块 |
|---|---|---|---|
| E1 | 口径配置 + 生成器 + 日快照 rollup | 声明落 **knowledge-base 本仓**；生成器与任务落 **multica** | `maturity-config.yaml`、可选 `model-prices.yaml`、`server/internal/maturity/gen/generate-config.mjs`、`server/internal/maturity/config_gen.go`、`server/internal/scheduler/jobs_maturity.go`、迁移 375–379 |
| E2 | 看板读 API + 共享视图 + Web/Desktop 接线 | **multica** | `server/internal/handler/maturity.go`、`server/internal/service/maturity*.go`、`server/pkg/db/queries/maturity.sql`、`packages/core` schema/client、`packages/views/dashboard/maturity/` |
| E3 | Org Admin Workspace + 周报 Autopilot | **multica**；报告原文落 daemon 绑定目录、不经 git | `server/internal/service/org_admin_*.go`、内置 skill `multica-maturity-weekly-report`、`agent_task_queue.result` 报告回执、`docs/org-admin/maturity-review-{YYYY-Www}.md` |

依赖方向（不引入反向依赖）：

```text
packages/views/dashboard/maturity/
  -> packages/views/dashboard/components/  # 复用 sibling 组件 dim-segmented / usage-trend-card / leaderboard
  -> packages/core                         # API client、query keys、zod schema
  -> packages/ui                           # 上述 views 组件内部使用的 UI 原语

server/cmd/server/router.go                # composition root
  -> server/internal/handler/maturity.go   # auth / request validation / response encoding
  -> server/internal/service/maturity*.go  # workspace-scoped business logic
  -> server/internal/maturity/             # 纯类型、生成配置、计分函数；不访问 DB
  -> server/pkg/db/queries/maturity.sql    # sqlc
  -> PostgreSQL

server/internal/scheduler/jobs_maturity.go
  -> scheduler/service.NextOccurrencesUTC  # 既有 cron 求解
  -> service.RollupMaturitySnapshot         # advisory lock + 单事务

server/internal/maturity/gen/generate-config.mjs
  -> knowledge-base maturity-config.yaml (+ optional model-prices.yaml)
  -> server/internal/maturity/config_gen.go # committed generated source；构建不读 sibling repo
```

### 1.2 三条运行链路

1. **E1 快照**：scheduler 用 `PlansForScope` 枚举 Asia/Shanghai 每日 00:30 plan → handler 以 `PlanTime` 唯一推导前一自然日 `bucket_date` → 一次事务内按 org/user/project 写 `maturity_snapshot`。8 项原始值、治理护栏、8 项分/5 维分/总分都在 rollup 时固化；观察期或基线未批准时只写 `metrics`，`scores={}`。
2. **E2 读取**：`GET /api/maturity/*` → workspace 鉴权 → 读已存 snapshot 返回 overall/项目排名/项目与用户趋势。**不得从原始事件重算历史分数**；只有不参与成熟度分数的 model Token 明细可按范围读 `task_usage`。
3. **E3 周报**：既有 schedule Autopilot 在绑定 Org Admin 项目的 daemon `local_directory` 内写 markdown；同一任务完成时把结构化 report envelope 放进既有 `agent_task_queue.result` 并产生既有 assistant chat message。server API 只读数据库里的 envelope，**不跨进程直读 daemon 文件系统**；目录文件是原文历史，result/chat 是可查询投影与追问入口。

### 1.3 权威与投影边界

- `maturity-config.yaml` 是口径声明权威；`config_gen.go` 是 committed 只读副本。
- `maturity_snapshot` 是可重建的操作态投影，但每行代表**该日、该 `config_rev` 下已固化的历史事实**；常规查询不得重算覆盖。
- CR 状态权威仍是 knowledge-base 的 `_backlog.yml`/`cr.md`/审批证据；CR-A 只读 multica 中的 `cr`/pipeline 投影，绝不反写 CR 状态。
- 周报原文权威是 Org Admin 项目目录文件；`agent_task_queue.result`/chat message 是 server 可见投影，按 `report_key` 去重展示。

---

## 2. 数据模型

### 2.1 `maturity_snapshot`：唯一新表，迁移 375–379

PRD 的业务键 `(bucket_date, scope, scope_id)` 在多 workspace 架构下会让所有 org 行以 `scope_id='·'` 冲突；SDD 增补必需租户键 `workspace_id`，物理主键为 `(workspace_id, bucket_date, scope, scope_id)`。这是对 FR-4 的租户隔离细化，不新增业务实体、无 FK。

```sql
-- 375_maturity_snapshot_table.up.sql：仅建表，不在 CREATE TABLE 内隐式建任何索引
CREATE TABLE maturity_snapshot (
    workspace_id UUID        NOT NULL,
    bucket_date  DATE        NOT NULL,
    scope        TEXT        NOT NULL CHECK (scope IN ('org','user','project')),
    scope_id     TEXT        NOT NULL,
    metrics      JSONB       NOT NULL DEFAULT '{}',
    scores       JSONB       NOT NULL DEFAULT '{}',
    config_rev   TEXT        NOT NULL CHECK (config_rev ~ '^[0-9a-f]{40}$'),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
      (scope = 'org' AND scope_id = '·') OR
      (scope IN ('user','project') AND scope_id <> '·')
    )
);
```

迁移严格遵守“每个索引 CONCURRENTLY、单文件一语句，包括新表”：

```sql
-- 376_maturity_snapshot_identity.up.sql
CREATE UNIQUE INDEX CONCURRENTLY maturity_snapshot_identity_uidx
ON maturity_snapshot (workspace_id, bucket_date, scope, scope_id);

-- 377_maturity_snapshot_primary_key.up.sql
ALTER TABLE maturity_snapshot
ADD CONSTRAINT maturity_snapshot_pkey
PRIMARY KEY USING INDEX maturity_snapshot_identity_uidx;

-- 378_maturity_snapshot_scope_date.up.sql
CREATE INDEX CONCURRENTLY maturity_snapshot_scope_date_idx
ON maturity_snapshot (workspace_id, scope, scope_id, bucket_date DESC);

-- 379_maturity_report_history.up.sql：既有 369 仅覆盖 active project task，不能服务 completed report history
CREATE INDEX CONCURRENTLY idx_atq_maturity_report_history
ON agent_task_queue (project_id, completed_at DESC, id DESC)
WHERE status = 'completed'
  AND project_id IS NOT NULL
  AND result->>'schema' = 'ai-first.maturity-report/v1';
```

Down 顺序：379 `DROP INDEX CONCURRENTLY` → 378 `DROP INDEX CONCURRENTLY` → 377 `DROP CONSTRAINT`（同步移除其 index）→ 376 `DROP INDEX CONCURRENTLY IF EXISTS` → 375 `DROP TABLE`。每个 migration 仍只有一条 statement；所有文件先过现有 migration lint，再在真实 PostgreSQL 执行 up/down/up。

### 2.2 JSON 契约

`metrics` 固化 8 项原始值和治理护栏；`scores` 固化 8 项分、5 维分与总分。键集合由生成配置与 Go 类型共同约束，写入前 service 校验，不接收外部任意 JSON。

```ts
type DataStatus = 'ready' | 'empty' | 'unavailable' | 'not_applicable'
type MetricValue = {
  value: number | null
  numerator: number | null
  denominator: number | null
  unit: 'tokens_per_member_day' | 'ratio' | 'cr_per_member' | 'members_per_cr'
      | 'count' | 'milliseconds'
  data_status: DataStatus
  reason: string | null
  attribution: {
    attributed_count: number
    unattributed_count: number
    coverage: number | null
  } | null
}

type SnapshotMetricsV1 = {
  schema: 'ai-first.maturity-metrics/v1'
  headline: {
    active_members: number
    total_tokens: number
    cost_usd: number | null
    cost_status: 'authoritative' | 'mixed' | 'estimated' | 'unavailable'
  }
  metric_values: Record<MetricKey, MetricValue> // 8 个固定 MetricKey，完整不缺键
  governance: Record<GovernanceMetricKey, MetricValue> // 6 个固定 key
}

type SnapshotScoresV1 = {
  schema: 'ai-first.maturity-scores/v1'
  metric_scores: Record<MetricKey, number>       // 8 项，0..100
  dimension_scores: Record<DimensionKey, number> // AIF/SII/OFI/EPC/ACM，0..100
  total_score: number                            // 0..100
}
```

- **观察期/未校准**：`metrics` 正常写全；`scores` 必须为 JSON 对象 `{}`，不是带 `null` 的伪分数。
- **治理未测量**：`metrics.governance.<key>` 仍有完整键，但 `value=null,data_status='unavailable',reason=<machine-readable reason>`；“未测量”绝不伪装成 0。
- **scope 适用性**：org/project 固化可计算指标；user 仅用于 Token/任务趋势，CR-A 不暴露 user ranking 或 user score，非适用指标写 `not_applicable`，`scores={}`。CR-D 若启用个人榜必须另行设计/审批，不复用 CR-A API 偷开能力。

### 2.3 既有数据源与 join 键

| 数据源 | CR-A 使用方式 |
|---|---|
| `member(workspace_id,user_id)` | v1 “活跃成员”定义为 rollup 时仍存在的 member 行；表无 active/status 历史，离组即删除。该限制写入指标定义页；快照固化后不追溯重算 |
| `task_usage` + `agent_task_queue` + `agent` | `task_usage.task_id=agent_task_queue.id`；队列表本身无 `workspace_id`，必须 `agent_task_queue.agent_id=agent.id AND agent.workspace_id=:workspace` 限租户；四列 Token 全计；`initiator_user_id` 归人；`project_id` 或 `issue_id→issue.project_id` 归项目 |
| `project` / `issue` / `comment` | CR 项目归属：`cr.shell_issue_id→issue.project_id`；评论者：`comment.issue_id=cr.shell_issue_id` 且 `author_type='member'`；Org Admin 系统项目通过 `project.settings.system_key` 排除业务项目分母 |
| `cr` + `cr_sync_event` | 先 `cr.workspace_id=:workspace`，再以 `cr.cr_id=cr_sync_event.cr_id` 读归档/状态时间；不可只按无 workspace_id 的 `cr_sync_event.cr_id` 裸查。`cr.owners` 当前是 crctl 自报的 free-text JSON；CR-A 不做名称匹配、不强转 UUID、不引入身份桥，只检测 unresolved owner 并按 §4.2.4 传播 unavailable |
| `pipeline_run` / `pipeline_node_run` | 以 `pipeline_run.workspace_id=:workspace AND pipeline_run.cr_id=cr.cr_id` 限租户；Review gate 与 4 pipeline 完成情况 |
| `approval_record` | 以 `workspace_id+cr_id+stage` join 审批；只计 `decision='approve'` |
| `activity_log` | `workspace_id` 限租户；`action='aifirst.evidence_drift'` 和 `action='aifirst.gitguard_denied'` |
| `agent_task_queue.result` + chat | E3 report envelope/server 查询投影与追问入口；不新增报告表 |

### 2.4 配置声明与生成器

`maturity-config.yaml` 的精确类型如下；SDD 不发明实现阈值，具体数值只能由该声明文件提供：

```ts
type MetricConfig = { weight: number; floor: number; target: number }
type MaturityConfigV1 = {
  schema: 'ai-first.maturity-config/v1'
  observation_weeks: 4
  calibration_status: 'observing' | 'calibrated' // CR-D 人审后才能改 calibrated
  dimensions: {
    AIF: ['token_intensity', 'ai_penetration']
    SII: ['cr_throughput_per_capita']
    OFI: ['project_collab_scale', 'project_active_rate']
    EPC: ['prototype_direct_rate']
    ACM: ['team_agent_depth', 'process_completion_rate']
  }
  metrics: Record<MetricKey, MetricConfig> // 恰好覆盖 8 个固定 MetricKey
}
```

生成器硬校验：8 key 齐全且无未知 key；每项 `0<weight<=1`；`sum(weights)=1`（允许 `1e-9` 浮点误差）；`target>floor`；`observation_weeks=4`；`calibration_status∈{observing,calibrated}`。读取文本先 `\r\n→\n`；解析不到必填块直接 hard fail，不得降级为空；`--check` 重生成后字节 diff 非零退出。`config_rev` 由 `git -C <source-repo> rev-parse HEAD` 取得，若源文件相对 HEAD dirty/untracked 则生成器拒绝，避免 SHA 与内容不匹配。

成本优先使用既有 `task_usage.cost_usd_ticks`（provider-reported，单位 `1e-10 USD`）；仅对该列为 NULL 的 usage 行，用可选 `model-prices.yaml` 估算。该文件与 config 同仓、同生成器生成只读 price map；未知模型或文件缺失时未计价部分保持 `cost_usd=null,data_status='unavailable'`，UI 显示“估算不可用”，不得猜价格。最终成本 = authoritative ticks 换算值 + 仅针对 uncosted Token 的估算，严禁对已带 authoritative cost 的 Token 二次计价。改价目表同样走 CR + 生成副本。

---

## 3. 接口契约

### 3.1 通用类型

所有端点注册在 `server/cmd/server/router.go` 的 **Auth + RequireWorkspaceMember** 受保护路由组内，位置靠近既有 `/api/dashboard`；不得注册到 `/api/config` 所在 public 区。请求用户必须属于 `X-Workspace-ID` 指定 workspace；query key 必含 `workspaceId`。日期为 Asia/Shanghai 自然日的 ISO `YYYY-MM-DD`；日期范围两端含、默认最近 28 天、最大 366 天。响应由 `packages/core/api/schema.ts` zod schema 解析，`parseWithFallback` 覆盖 malformed payload。

```ts
type MetricKey =
  | 'token_intensity' | 'ai_penetration' | 'cr_throughput_per_capita'
  | 'project_collab_scale' | 'project_active_rate' | 'prototype_direct_rate'
  | 'team_agent_depth' | 'process_completion_rate'
type DimensionKey = 'AIF' | 'SII' | 'OFI' | 'EPC' | 'ACM'
type GovernanceMetricKey =
  | 'gate_first_pass_rate' | 'evidence_drift_count' | 'traceability_complete_rate'
  | 'approval_latency_p50_ms' | 'approval_latency_p90_ms' | 'forbidden_attempt_count'
type Observation = {
  active: boolean
  calibration_status: 'observing' | 'calibrated'
  observation_weeks: 4
  first_bucket_date: string
  elapsed_days: number
}
type ApiError = { error: string; message: string; request_id: string }
```

通用错误：`401 unauthenticated`、`403 workspace_forbidden`、`500 internal_error`。空数据是 200 + 结构化 empty，不用 404。

### 3.2 `GET /api/maturity/overall`

Query：`date?: YYYY-MM-DD`（缺省取该 workspace 最新 org bucket）。

```ts
type MaturityOverallResponse = {
  bucket_date: string | null
  config_rev: string | null
  observation: Observation | null
  headline: {
    active_members: number
    total_tokens: number
    cost_usd: number | null
    cost_status: 'authoritative' | 'mixed' | 'estimated' | 'unavailable'
  } | null
  total_score: number | null
  dimensions: Array<{
    key: DimensionKey
    score: number | null
    data_status: DataStatus
    metrics: Array<{ key: MetricKey; raw: MetricValue; score: number | null }>
  }>
  governance: Array<{ key: GovernanceMetricKey; datum: MetricValue }>
  data_status: 'ready' | 'empty'
}
```

观察期、`calibration_status!='calibrated'`，或任一计分 raw 非 ready/null（包括 unresolved owner）时 `total_score=null`、所有 score=null、raw 正常；不得临时重算或部分权重重归一化。

### 3.3 `GET /api/maturity/token-trend`

Query：`dimension=project|user|model`，`dimension_id?: UUID|string`，`from?`，`to?`，`include_cost?: boolean`。project 可指定 id 或返回项目系列；**user 必须 `dimension_id=self`，未传或传任意用户 UUID 均返回 400 `unsupported_user_dimension`，绝不返回 all-user 系列**；model 可选具体 model。project/self-user 读 snapshot raw；model 明细按范围读 `task_usage`，只算 Token/成本，不生成成熟度分。

```ts
type TokenTrendResponse = {
  dimension: 'project' | 'user' | 'model'
  from: string
  to: string
  series: Array<{
    id: string
    label: string
    points: Array<{
      date: string
      tokens: number
      cost_usd: number | null
      cost_status: 'authoritative' | 'mixed' | 'estimated' | 'unavailable'
    }>
  }>
  data_status: 'ready' | 'empty'
}
```

无效日期/范围/维度返回 400 `invalid_query`；user 非 self 查询返回 400 `unsupported_user_dimension`。服务端测试断言任何响应都不能枚举、排序或返回其他用户 ID/姓名。

### 3.4 `GET /api/maturity/rankings`

Query：`scope=project`（唯一合法值）、`date?`、`metric?: MetricKey|'total'`、`limit?:1..100`（默认20）、`cursor?: opaque`。观察期 UI 默认按选中 raw metric 排名；`metric=total` 且 scores 为空时 200 返回 item `value=null,data_status='unavailable'`，不伪造总分。

```ts
type ProjectRankingsResponse = {
  scope: 'project'
  bucket_date: string | null
  metric: MetricKey | 'total'
  items: Array<{
    rank: number
    project_id: string
    project_name: string
    value: number | null
    data_status: DataStatus
  }>
  next_cursor: string | null
  data_status: 'ready' | 'empty'
}
```

`scope=user` 或任意其他值返回 400 `ApiError{error:'unsupported_scope',message:'only project rankings are available'}`，`request_id` 填当前请求 ID；服务层没有 user rankings query，不能只靠 UI 隐藏。

### 3.5 `GET /api/maturity/suggestions` 与 `/history`

server 查询完成态 `agent_task_queue.result` 中 `schema='ai-first.maturity-report/v1'` 的 envelope，不读取 daemon path。

```ts
type MaturityReport = {
  report_key: string                 // `${workspace_id}:${YYYY-Www}`
  week: string                       // ISO YYYY-Www
  generated_at: string               // RFC3339
  relative_path: string              // docs/org-admin/maturity-review-{YYYY-Www}.md
  markdown: string                   // 与落盘内容同 SHA-256
  content_sha256: string
  source_task_id: string
  chat_session_id: string            // “追问”跳转既有 Team Agent 对话
  config_revs: string[]
}
type SuggestionResponse = { latest: MaturityReport | null; data_status: 'ready'|'empty' }
type SuggestionHistoryResponse = {
  items: MaturityReport[]
  next_cursor: string | null
  data_status: 'ready'|'empty'
}
```

history query：`limit?:1..52`（默认12）、`cursor?:opaque`。重复 `report_key` 取 `completed_at` 最新且 SHA 有效的一条；目录文件仍保留，数据库不新增唯一约束。

### 3.6 `GET /api/maturity/config`

```ts
type MaturityConfigResponse = {
  config_rev: string
  observation_weeks: 4
  calibration_status: 'observing' | 'calibrated'
  dimensions: Array<{ key: DimensionKey; metrics: MetricKey[] }>
  metrics: Array<{
    key: MetricKey
    weight: number
    floor: number
    target: number
    unit: MetricValue['unit']
    known_gameability: string
  }>
  price_config_rev: string | null
}
```

全员可读，无 Owner-only 分支；无 user ranking 开关字段。

### 3.7 调度与报告 envelope 契约

- **快照 JobSpec**：`Name='maturity_snapshot'`、`Cadence:0`、`PlansForScope=maturityPlansForScope`、`MaxPlansPerTick:7`、`StaticScopes(global)`；timeout/retry/heartbeat 照抄 `AutopilotScheduleDispatchJob`。虽然声明保留 `CatchUpMode:CatchUpEveryPlan` 与 `CatchUpWindow:7*24h` 以表达业务意图，`scheduler.JobSpec` 明确规定：一旦设置 `PlansForScope`，这两字段**不参与规划**；真实补偿逻辑必须完全实现在 hook 内，不能把正确性归因给被忽略字段。
- **Hook 算法**：先用新增 sqlc 只读查询从既有 `sys_cron_executions` 取窗口内所有 retry-eligible 行：`job_name='maturity_snapshot' AND scope_kind='global' AND scope_id='global' AND status='FAILED' AND attempt<max_attempts AND next_retry_at<=now AND plan_time>now-7d`，oldest-first、limit 7；`latest.RetryEligible(now)` 必须包含在该集合（单测钉死）。再令 `after=latest.PlanTime`；若从无执行记录，则 `after=now-24h`，使首次部署只生成最近一个已到期 plan、不伪造上线前观察期；已有记录时令 `after=max(after,now-7d)`。调用 `NextOccurrencesUTC('30 0 * * *','Asia/Shanghai',after,now)` 得到新 occurrence；把 retry plan 与新 plan 去重合并、oldest-first，截到 7 个返回。这样同 tick 的较新 plan 成功后，较老 FAILED 也不会因不再是 latest 而永久搁浅。hook 直接返回 canonical UTC，不做 latest-only collapse。
- **PlanTime 语义**：每个 plan 只负责 `plan_time.In(Asia/Shanghai)` 所在本地日的**前一日** bucket；handler 不再从水位循环到“当前日”，避免 hook 与 handler 双重补偿。`MAX(bucket_date WHERE workspace_id=:workspace)` 仅作 target 已存在 no-op 判断；缺口由 hook 自己的 7 日枚举补齐。
- **周报 schedule**：Org Admin 项目每周一 09:00 Asia/Shanghai 触发（运营可在既有 Autopilot UI 改 cron）；复用 `sys_cron_executions(job_name,scope_kind,scope_id,plan_time)` 幂等。
- **Report result**：schedule enqueue 必须把 `agent_task_queue.project_id` 设为 Org Admin 项目 ID，并绑定该项目的 `chat_session_id`；任务结束返回 `result={schema,report_key,week,generated_at,relative_path,markdown,content_sha256,chat_session_id,config_revs}`。daemon 先原子写临时文件并 rename，再完成任务；server 验证 SHA 后持久化 result/chat。重试使用同一 `report_key`，API 以 `project_id + schema + completed_at/id` 查询并去重。

---

## 4. 关键算法与流程

### 4.1 时间窗、租户与空分母统一规则

- `bucket_date=d`：Asia/Shanghai `[d 00:00, d+1 00:00)`，SQL 参数预先转换成 UTC `[from_utc,to_utc)`，所有 timestamp 过滤左闭右开。
- 每个 SQL 必须先建立租户边界：有 `workspace_id` 的表直接谓词过滤；无该列的 `agent_task_queue` 必须先 join `agent.workspace_id=:workspace`，无该列的 `cr_sync_event` 必须先 join 已限定 workspace 的 `cr`。
- “活跃成员数”v1 = rollup 时 `member` 当前行数（表无历史 active 字段）；“全体成员数”同义。`0` 分母返回 `value=null,data_status='empty'`，不做除零、不把 null 当 0。
- `agent_task_queue.initiator_user_id` 是 nullable/best-effort：NULL 行仍计入组织总 Token 和全部任务分母，但不归给任何 user，也不进入 distinct initiator 分子；每个相关 `MetricValue.attribution` 记录 attributed/unattributed/coverage。覆盖率低于 95% 时，所有依赖发起人归因的 user breakdown、AI 渗透率和协作参与人数均标 `data_status='unavailable'`；org Token 总量仍可 ready，不得用低覆盖数据输出看似精确的个人值。历史 terminal task 的 `project_id` 可能未回填，项目归属先 `q.project_id`、再 `q.issue_id→issue.project_id`；两者皆空则只计 org、不计 project。
- `cr.owners` 的 `owners.*.id` 在当前投影中来自 crctl `--caller`，是 free-text 而非可验证的 `member.user_id`。CR-A 不按名称匹配、不尝试 UUID 强转，也不新建跨仓身份桥。对窗口内归档 CR：存在非空 owner id 即记为 unresolved；`project_collab_scale` 的对应 scope/date 写 `value=null,data_status='unavailable',reason='cr_owner_identity_unresolved'`，评论者和任务发起者集合仍可作为诊断数据返回但不得填补该指标；org scope 受任一 unresolved owner 影响，project scope 只受该 project 的 unresolved CR 影响。该样本不进入基线分位数。
- 项目集合 = 该 workspace `project.status!='cancelled'` 且 `settings->>'system_key' IS NULL` 的业务项目；Org Admin 系统项目不进入成熟度分母。
- CR 项目归属 = `cr.shell_issue_id→issue.project_id`；无法归属的 CR 只计 org，不计 project。

### 4.2 八项子指标（rollup 时计算并固化）

1. **Token 强度**：本地日内 `SUM(input_tokens+output_tokens+cache_read_tokens+cache_write_tokens) / member_count / 1天`；`task_usage.task_id=agent_task_queue.id`，并经 `agent_task_queue.agent_id=agent.id AND agent.workspace_id=:workspace` 限租户；按 `initiator_user_id` 归人、按 `COALESCE(agent_task_queue.project_id,issue.project_id)` 归项目；不读无 user 维的 `task_usage_hourly`。
2. **AI 渗透率**：同样先经 `agent.workspace_id=:workspace` 限租户；本地日内 `COUNT(DISTINCT initiator_user_id) / member_count`；“发起过”按 task `created_at`，不以最终成功状态过滤。
3. **人均 CR 吞吐**：本地日内首次进入 `archived` 的 distinct CR 数 / member_count；从 `cr_sync_event.event_kind='status' AND payload->>'to_status'='archived'` 取 `occurred_at`，先 join workspace-scoped `cr` 去重。
4. **项目协作规模**：对窗口内归档 CR 分别取 canonical user 集合并求人数，再平均：可验证的 owner user id（当前 CR-A 不存在该身份桥，故不填入）∪ `comment.author_id`（member only）∪ `agent_task_queue.initiator_user_id`（`q.cr_id=cr.cr_id OR q.issue_id=cr.shell_issue_id`）。project scope 再按 canonical `cr→issue.project_id` 过滤；人数 `<2` 的 raw 仍存，计分由配置 floor/target 使其不加分。若该 scope/date 的归档 CR 存在非空 `cr.owners.*.id`，因 owner 身份 unresolved，整个该 scope/date 的 `MetricValue` 固化为 `value=null,data_status='unavailable',reason='cr_owner_identity_unresolved'`，不得以评论者/任务发起者子集伪造完整值；org scope 任一归档 CR 命中即 unavailable，project scope 按所属 project 独立传播。
5. **项目活跃率**：近 14 个本地自然日内存在 task `created_at` 或 CR status `occurred_at` 的 distinct 业务 project / 全部业务 project；任务项目优先 `q.project_id`，缺失时 `q.issue_id→issue.project_id`；CR 项目走 shell issue。
6. **原型直出率**：当期归档 CR 中，**全部已投影 review gate**（`requirement`、`tech-design`、`code`，对应 `governance.ReviewGateNodes`）均在 `attempt=1,status='passed'` 的 CR 数 / 当期归档 CR 数。不是 passed node/全部 node；缺任一必需 review gate 即不计一次通过。
7. **Team Agent 使用深度**：先以 `agent.workspace_id=:workspace` 限租户；当期 `agent_task_queue` 中 `(cr_id IS NOT NULL OR issue_id IS NOT NULL)` 的任务数 / 全部任务数；按共享队列来源键，**不用 `pipeline_node_run_id` 替代 `issue_id`**。
8. **流程完整率**：当期归档 CR 中同时存在 status=`completed` 的 4 个 `pipeline_run.pipeline_id`：`requirement-authoring`、`architecture-design`、`code-implementation`、`feature-writeback` 的 CR 数 / 当期归档 CR 数。

### 4.3 治理护栏（存入 org snapshot，不进总分）

| key | 口径 | 可用性 |
|---|---|---|
| `gate_first_pass_rate` | 当期 completed review gate 中 attempt=1 且 passed / 当期 completed review gate 数 | 当前 ready |
| `evidence_drift_count` | `activity_log.workspace_id=:ws AND action='aifirst.evidence_drift' AND created_at∈window` | 当前 ready |
| `traceability_complete_rate` | `traceability.yml` 五段齐全的归档 CR / 归档 CR | **CR-C trace event 通道未交付前 unavailable**，reason=`trace_channel_pending_cr_c`；CR-A 不扫描 daemon/git、不实现 CR-C |
| `approval_latency_p50_ms` / `p90` | 对当期 approval：对应 stage review node `completed_at` → `approval_record.created_at` 的正时长分位数 | 当前 ready；无样本 empty |
| `forbidden_attempt_count` | `activity_log.workspace_id=:ws AND action='aifirst.gitguard_denied' AND created_at∈window` | 当前 ready |

UI 始终渲染 6 个字段（审批时延 P50/P90 可合并一张卡）；unavailable 显示“未测量/数据通道待 CR-C”，不显示 0，不影响 `total_score`。

### 4.4 计分与观察期

```text
metric_score_i = clamp(100 * (x_i - floor_i) / (target_i - floor_i), 0, 100)
dimension_score_d = Σ(metric_score_i * metric_weight_i) / Σ(metric_weight_i in dimension d)
total_score = Σ(metric_score_i * metric_weight_i)  # 全局 weight 和=1
```

`observation_active = elapsed_days < 28 OR calibration_status != 'calibrated'`。只要为 true，rollup 写 `scores={}`。校准后若某 scope/date 的任一计分指标不是 `ready` 或其 value 为 null（包括 `project_collab_scale` 的 unresolved owner），该 scope/date 仍保留完整 raw metrics，但整体写 `scores={}`，不做部分权重重归一化。第 4 周基线对每个 MetricKey 只取**首个连续 28 个 org snapshot 的 ready raw value**，忽略 null/empty/unavailable；样本少于 21 个时该指标建议为 unavailable。样本充足时用 PostgreSQL `percentile_cont(0.10)` 与 `percentile_cont(0.75)`（线性插值）分别得到 floor/target 建议；若 `P75<=P10` 则标记 degenerate_distribution、不得给可写值。建议只进报告，不写 config。CR-D 人审配置改为 calibrated 后，**仅新 bucket** 写分数；旧行保持 `{}`，趋势跨 `config_rev` 标断点。

### 4.5 Rollup 事务与幂等

```text
GlobalHandler(planTime):
  list active workspaces in stable ID order
  for each workspace call RollupWorkspace(planTime, workspace)
  # 每 workspace 独立事务；前序成功、后序失败时任务整体报错，重试对前序 workspace 按水位 no-op

RollupWorkspace(planTime, workspace):
  target = previousLocalDate(planTime, Asia/Shanghai)
  BEGIN
  pg_try_advisory_xact_lock(hash('maturity_snapshot', workspace)) or return retryable-busy
  if MAX(bucket_date WHERE workspace_id=workspace) >= target: COMMIT no-op
  compute all org/user/project SnapshotMetricsV1 for target
  validate metric keys/status/config_rev
  scores = observation_active || anyScoringMetricUnavailable(metrics) ? {} : Score(metrics, generatedConfig)
  INSERT rows with ON CONFLICT (workspace_id,bucket_date,scope,scope_id) DO NOTHING
  assert org row inserted-or-existed and all planned scope rows are valid
  COMMIT
```

- 同一 workspace+target 的所有 scope 行在一个事务；任一 SQL/JSON 校验失败则该 workspace 全部回滚，`MAX(bucket_date)` 不前移。不同 workspace 不做跨租户大事务；任务重试靠已成功 workspace 的水位 no-op 收敛。
- handler 每 plan 只写一个 target；停机 3 天由 scheduler 枚举 3 个 plan，最多 7 个，不在 handler 二次扩窗。
- 历史不可变：常规路径禁止 `DO UPDATE`；配置变化只影响后续行。

### 4.6 Org Admin 初始化与周报闭环

- `project.settings.system_key='org-admin-workspace'` 作为逻辑幂等键；初始化事务按 workspace 取 advisory lock，SELECT 后 INSERT，避免标题重名误认。项目无新增列/索引。
- Agent `system_key='org-admin'`，复用 `CreateMikaAgent` 的 `(workspace,owner,runtime,system_key)` 幂等语义；项目 lead 指向该 Agent。
- 部署/首次使用通过既有 project-resource API 为项目绑定 `type='local_directory'`（daemon_id + local_path）。未绑定时周报状态为 unavailable 并在 UI 给出现有绑定入口，不假装已生成。
- schedule task 写 `docs/org-admin/maturity-review-{YYYY-Www}.md`，模板固定为个人效率/团队交付/知识复利/风险收益/成本五节；第 4 周附 8 项 P10/P75 建议。
- 完成 envelope 进入 `agent_task_queue.result` 与 assistant chat；建议 API 从 result 读，追问按钮用 `chat_session_id` 进入既有 Team Agent 消息流。

---

## 5. 技术选型与替代方案

| 决策 | 选择 | 否决方案与原因 |
|---|---|---|
| 配置消费 | knowledge-base yaml → 零依赖生成器 → committed Go（CRLF 规范化、hard fail、dirty guard、`--check`） | runtime 读 sibling repo：破坏独立构建；手维版本号：易漂移 |
| 快照主键 | 375 表、376 unique concurrent、377 PK using index、378 query index | inline PRIMARY KEY：隐式非 concurrent index，违反 CLAUDE.md |
| 调度 | `Cadence:0 + PlansForScope`；hook 自己实现 retry-eligible + 7日 oldest-first 枚举，manager 以 MaxPlansPerTick=7 截断；每 plan 一日 | 依赖 CatchUpEveryPlan/CatchUpWindow：设置 hook 后两字段被 scheduler 忽略；固定24h：本地时区漂移；LatestOnly：永久缺桶；handler再循环：双重补偿 |
| 历史读取 | rollup 固化 metrics/scores；overall/ranking/report 读 snapshot | 读时重算分数：口径变更会改写历史，是建快照表要解决的问题 |
| 报告跨进程 | daemon 写文件 + 既有 task result/chat 回传；API 读 DB envelope | server 直读 daemon `local_directory`：跨进程/跨机器不可达；新增报告表：违反唯一新表 |
| 治理追溯 | CR-C 前显式 unavailable | CR-A 扫 git/新增 trace event：侵入 CR-C 边界且重复建设 |
| 成本 | provider `task_usage.cost_usd_ticks` 优先；仅 NULL 行用 knowledge-base `model-prices.yaml` 生成价目估算，未知=null | 对全部Token统一估算：会覆盖/重复计算权威成本；硬编码/猜价：不可治理且误导 |
| CR owner 归因 | 不匹配名称、不强转 UUID；检测 free-text owner 并将受影响 `project_collab_scale` scope/date 标 `unavailable`，样本跳过基线 | 在 CR-A 新建 owner→member 身份桥：扩大 crctl 事件协议、历史回填和跨仓治理边界，应另立 CR |

---

## 6. FR 到技术实现映射

| FR | 技术实现 |
|---|---|
| FR-1 | §2.4 `maturity-config.yaml` schema + generated Go；权重/阈值/观察期集中 |
| FR-2 | `server/internal/maturity/gen/generate-config.mjs`：CRLF→LF、结构 hard fail、dirty guard、`--check` |
| FR-3 | source repo clean HEAD SHA 写 `config_rev`；每行固化 |
| FR-4 | §2.1 迁移 375–379；技术补充 `workspace_id` 租户键；无 FK；379 为E3 completed report history索引 |
| FR-5 | §3.7 JobSpec + hook 精确算法：retry-eligible、7日 oldest-first、MaxPlansPerTick=7、Asia/Shanghai、global scope；不依赖被忽略的 CatchUpMode/Window |
| FR-6 | §4.5 workspace advisory lock、单日 bounded plan、单事务、`MAX(bucket_date)` no-op 水位 |
| FR-7 | §1.3/§4.4 历史不可变、观察期 `{}`、config 断点 |
| FR-8 | 一 plan 一事务，内部遍历 org/user/project，调度器不展开用户 scope |
| FR-9 | 看板头部显示范围、Owner mode、`每日00:30更新前一日`、data_status |
| FR-10 | 统计条读 snapshot；authoritative cost 优先、可选 prices 只估算 uncosted Token，未知 cost=null/“估算不可用” |
| FR-11 | §3.3 project/user snapshot 趋势 + model raw Token 明细；不重算分数 |
| FR-12 | §3.4 仅 project query，user scope 服务端 400 |
| FR-13 | maturity view 复用 `packages/views/dashboard/components/` 三件式；观察期无雷达 |
| FR-14 | §4.2 精确 8 公式、字段、窗口、空分母、项目映射；`cr.owners` unresolved 时 project_collab_scale 按 scope/date 固化 unavailable；§4.4 计分 |
| FR-15 | §4.3 6 字段三态治理护栏，trace CR-C 前 unavailable，全部不进总分 |
| FR-16 | 数量/质量成对布局、定义页公开 v1 member 口径与可刷性、页脚反 Goodhart |
| FR-17 | §3.2–§3.6 精确 request/response/error/empty 合同 |
| FR-18 | `packages/views` 共享 route + Web/Desktop platform wiring；无 iframe/新写通路 |
| FR-19 | §4.6 project.settings system key + Agent system_key 幂等初始化、local_directory 绑定 |
| FR-20 | §3.7/§4.6 周 schedule、文件落盘、result/chat 回传、inbox 通知 |
| FR-21 | §4.6 五节模板，每节引用 snapshot/governance 指标 |
| FR-22 | §3.5 从 result envelope 渲染最新/历史，目录文件为原文 |
| FR-23 | report envelope 返回 chat_session_id，追问进入既有 Team Agent 对话 |
| FR-24 | 第4周按8项四周分布算 P10/P75，仅报告建议、不写 config |

FR 覆盖率：**24/24**。

---

## 7. 安全、性能与测试设计

### 7.1 安全与性能

- **租户隔离**：snapshot 物理键含 `workspace_id`；全部原始表 query 先限定 workspace；`cr_sync_event` 必须经已限定的 `cr` join；query key 含 workspaceId。
- **隐私/反 Goodhart**：无 user ranking SQL/API/UI/开关；Token 为行为数据非绩效；user snapshot 不暴露个人 score。
- **数据库安全**：无新 FK；每索引 CONCURRENTLY 单文件；advisory lock 按 workspace，避免不同 workspace 相互阻塞。
- **查询成本**：overall/ranking 只读日快照；report history 用 migration 379 的 `(project_id,completed_at DESC,id DESC)` partial index，不能误用仅覆盖 active task 的 migration 369 索引；原始表大范围聚合只在每日 rollup 和 model 明细发生。API 日期最多 366 天、ranking limit≤100、history limit≤52。
- **成本完整性**：`cost_status=authoritative` 表示全部 usage 有 provider ticks；`mixed` 表示一部分 authoritative、其余全部被价目覆盖；`estimated` 表示无 authoritative 但全部可估；只要仍有未知模型的 uncosted Token，`cost_status=unavailable` 且 `cost_usd=null`，不展示不完整小计。
- **兼容性**：新增响应 additive；zod enum 有 fallback；desktop 对未知字段容忍；空/不可用是显式状态。
- **代码治理**：所有注释英文；实现涉及 migration、scheduler、handler/service、builtin skill、前端 route/组件、生成器，逐项登记 multica `CUSTOM.md`，编号/表格格式以实施时文件现状为准。

### 7.2 可执行测试矩阵

| 范围 | 测试落点/方式 | 必须证明 |
|---|---|---|
| 配置生成器 | Node 单测 + `--check` CLI fixture | LF/CRLF 同输出；缺块/未知key/weight和≠1/target≤floor hard fail；dirty source 拒绝；漂移非零；clean source SHA 入头 |
| 迁移 | `server/internal/migrations` lint + 真实 PostgreSQL up/down/up + EXPLAIN | 375 无隐式 index；376 unique concurrent；377 PK using index；378 snapshot query index；379 completed report partial index；无 FK；org sentinel CHECK；重复逻辑键失败；history query命中379而非369 active index |
| 计分纯函数 | `server/internal/maturity/score_test.go` table-driven | floor/target/夹断/浮点边界；8→5→total；observing 返回空 scores；缺 key 或任一计分 raw 非 ready/null 时拒绝，rollup 固化空 scores |
| 8 项 SQL | `server/internal/service/maturity_test.go` PostgreSQL fixtures | 四类 Token 含 cache_write；workspace 隔离；member=0 空态；CR→project join；EPC 三 review gate attempt=1；Team Agent 用 cr_id/issue_id；4 pipeline 完整率；free-text owner 不做名称匹配/UUID 强转，命中时 project_collab_scale 按 org/project scope 写 unavailable |
| 治理 | DB fixtures | 两个 activity action 精确计数；审批 P50/P90；CR-C 前 trace unavailable≠0；治理不改变 total |
| Scheduler | fixed DB clock/Asia-Shanghai + sys_cron fixtures | latest失败返回同plan；较老FAILED+较新SUCCESS仍重试老plan；首次仅最近一个已到期plan；停3天合并返回3plan；超7天仅窗口内最多7个；00:30→前一日；同plan no-op；断言CatchUpMode/Window不参与hook规划 |
| Rollup | 真实 PG 并发/故障注入 | 同 workspace 双执行只一组行；不同 workspace 并行；中途失败全回滚；重跑不改历史；配置变更仅新行 rev 变化 |
| API | handler/service tests | 完整 schema；401/403；invalid range 400；user rankings 400；观察期 total null；empty 200；cursor/limit；任何 query 不跨 workspace |
| Core schema | Vitest zod malformed fixtures | 每个端点正常/缺字段/错误枚举/新增字段；`parseWithFallback` 不崩溃 |
| UI | views component tests | loading/empty/error/unavailable；观察期无雷达；项目排名无个人入口；数量与治理同屏；跨 config_rev 断点 |
| E3 | service + daemon integration | 未绑 local_directory 显式 unavailable；同 ISO week 重试 API 仅一报告；落盘 SHA= result markdown SHA；周报4/4；第4周8项建议且 config 零写入；chat_session_id 可追问 |
| CUSTOM | repo test/人工 diff gate | 所有 `// AIFIRST:` 挂钩点、新 migration/生成器/自研模块在 `CUSTOM.md` 可追溯 CR-2026-047/TASK |

### 7.3 AC 到验证项映射

| AC | 验证项 |
|---|---|
| AC-1 | 配置类型/8 key/weight/floor/target/观察期校验；`config_rev` 等于 clean source HEAD SHA |
| AC-2 | 生成器 `--check` 一致为 0、漂移非 0；生成文件头含源 SHA |
| AC-3 | 迁移 375–379 真实 PG up/down/up；仅新增 snapshot 表、无 FK、所有索引 concurrent 单文件；租户前缀后的业务键满足 FR-4；EXPLAIN证明report history命中379 |
| AC-4 | fixed clock 跨 00:30 仅产生前一日 global plan；事务内写三 scope，cron scope 不按用户/项目增长 |
| AC-5 | 同桶重跑/双并发/故障注入，验证唯一行、advisory lock 与全事务回滚 |
| AC-6 | 连续 3 天 metrics 完整/scores 空；改 config 后只新行 rev 变化；历史摘要不变且 API 返回 revision 断点 |
| AC-7 | hook fixed-clock：首次仅最近plan；停机3天补3plan；超过7天只补窗口内最多7plan；latest/非latest retry-eligible FAILED 均返回原PlanTime |
| AC-8 | 首屏断言日期/Owner mode/更新说明/成员/Token；provider成本标authoritative，混合成本标mixed，纯估算标estimated，未知价空态 |
| AC-9 | project/self-user snapshot 与 model raw 三组 fixture，日期总量守恒；user非self/全量枚举均400且响应不含他人ID |
| AC-10 | route、DOM、API/service 均无 user ranking/开关/通知；user scope 400 |
| AC-11 | observing fixture 断言无雷达，仅三件式组件 |
| AC-12 | 8 公式逐项 DB fixture + score 0/100/线性边界 + total 只含 8 项；owner unresolved fixture 断言 org/project 协作规模不可用且不进入 baseline |
| AC-13 | 5 类治理卡（6 字段）ready/empty/unavailable；修改治理值不改变 total |
| AC-14 | Token 与质量护栏同屏；定义页含 8 项可刷性；页脚含非绩效声明 |
| AC-15 | 6 个 HTTP 合约的 schema/status/auth/empty 测试；config 全员可读；user rankings 不泄露 |
| AC-16 | Web/Desktop route smoke test；复用 views；无 iframe/独立域名 |
| AC-17 | 初始化两次后 project.settings system key 与 Agent system_key 各唯一一行 |
| AC-18 | 周任务生成同周唯一 report_key/文件/result/inbox；文件未进入 git |
| AC-19 | 报告五节均存在并各引用对应指标 key |
| AC-20 | suggestions 最新/历史按 ISO week 排序；无报告 200 empty |
| AC-21 | report chat_session_id 连续两轮追问仍带报告上下文 |
| AC-22 | 首28个org日样本按ready过滤，≥21时 percentile_cont P10/P75、退化分布显式不可用；8项建议生成前后 config 字节与 HEAD SHA 不变 |

无未映射 AC。

## 8. Prompt 采纳影响

本 CR 不触及 `skills/shared/crctl/scripts/crctl.mjs` dispatch 或 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`，无需列 skill prompt 采纳清单；本维度按条件跳过。
