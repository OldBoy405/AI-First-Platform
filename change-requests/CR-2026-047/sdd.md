---
id: CR-2026-047-sdd
type: SDD
cr-ref: CR-2026-047
title: P3 组织智能 CR-A：AI 成熟度看板（E1 快照 + E2 看板 + E3 周报）技术设计
status: draft
created: 2026-08-20T00:38:27+08:00
updated: 2026-08-20T00:38:27+08:00
---

# SDD — P3 组织智能 CR-A：AI 成熟度看板

> 本文档以 `prd.md` 为输入，描述 CR-A 的模块边界、数据模型、接口契约、关键算法与技术选型。权威架构约束见 multica 仓根目录 `ARCHITECTURE.md`（硬不变量 1–9）与 `CLAUDE.md`（迁移/代码规则）。本 CR 全部新增/修改的代码注释一律英文。

---

## 1. 架构概览

### 1.1 交付物与代码仓归属

| 交付物 | 内容 | 落点仓 | 关键模块 |
|---|---|---|---|
| E1 | 口径配置 + 生成器 + 快照 rollup | 配置声明落 **knowledge-base 本仓**；生成器与快照任务落 **multica** | `maturity-config.yaml`、`server/internal/governance/gen/generate-maturity-config.mjs`、`server/internal/scheduler/jobs_maturity.go`、迁移 375 |
| E2 | 看板前端 + 读侧 API | **multica** | `server/internal/handler/maturity.go`、`server/internal/service/maturity/`、`server/pkg/db/queries/maturity.sql`、`packages/views/dashboard/maturity/` |
| E3 | Org Admin Workspace + 周报 Autopilot | **multica**（报告落盘不经 git） | 内置 Agent/项目、内置 skill `maturity-weekly-report`、`docs/org-admin/maturity-review-{YYYY-Www}.md` |

依赖方向（严格遵守 `ARCHITECTURE.md` §4，不引入反向依赖）：

```text
packages/views/dashboard/maturity/          (共享业务 UI)
  -> packages/core  (maturity API client + zod schema)
  -> packages/ui    (dim-segmented / usage-trend-card / leaderboard 原语)

server/cmd/server/router.go                  (composition root)
  -> server/internal/handler/maturity.go     (HTTP boundary：鉴权/校验/编码)
  -> server/internal/service/maturity/       (聚合 + 计分业务逻辑)
  -> server/pkg/db/queries/maturity.sql      (sqlc，只读查询)
  -> PostgreSQL

server/internal/scheduler/jobs_maturity.go   (JobSpec，复用 sys_cron_executions 租约)
  -> service.NextOccurrencesUTC               (cron 求解，既有)
  -> maturity_snapshot rollup SQL             (advisory lock + 单事务)

server/internal/governance/gen/generate-maturity-config.mjs  (生成器)
  -> 读 knowledge-base 本仓 maturity-config.yaml
  -> 吐只读 Go 副本 maturity_config_gen.go（committed，构建零跨仓依赖）
```

### 1.2 关键流程

1. **快照流程（E1）**：scheduler 每 tick 调 `PlansForScope` hook 枚举 `(lastPlan, dbNow]` 内的 Asia/Shanghai 00:30 桶 → 对每个 plan 执行 `maturity_snapshot` rollup SQL（`pg_try_advisory_xact_lock` + 单事务内 upsert 与 `MAX(bucket_date)` 水位同提交）→ 一个任务内写 org/user/project 三类行。
2. **读流程（E2）**：`GET /api/maturity/*` → handler 鉴权/解析 → service 读 `maturity_snapshot`（分数）+ 读时 join 既有事件表（原始值）→ 计分 → 返回 schema 化 JSON。
3. **周报流程（E3）**：每周 schedule Autopilot → 读最近 `maturity_snapshot` 序列 + 治理板块异常 → 生成诊断 markdown 落盘 `docs/org-admin/maturity-review-{YYYY-Www}.md`（不经 git）→ 经 inbox 通知 Owner → 看板「建议」区渲染目录最新文件。

---

## 2. 数据模型

### 2.1 新增表：`maturity_snapshot`（迁移 375，唯一新表）

```sql
-- 375_maturity_snapshot.up.sql
CREATE TABLE maturity_snapshot (
    bucket_date DATE        NOT NULL,
    scope       TEXT        NOT NULL CHECK (scope IN ('org','user','project')),
    scope_id    TEXT        NOT NULL,           -- org 固定 '·'；user/project 为对应 UUID 文本
    metrics     JSONB       NOT NULL DEFAULT '{}',   -- 8 项子指标原始值（分子/分母/值）
    scores      JSONB       NOT NULL DEFAULT '{}',   -- 8 项子指标 0-100 分；观察期内 '{}'
    config_rev  TEXT        NOT NULL,           -- maturity-config.yaml 所在 commit SHA
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (bucket_date, scope, scope_id)
);
```

- **`metrics` 结构**（每子指标一 key，含可解释的分子/分母）：
  ```json
  {
    "token_intensity":          {"numerator": 123456, "denominator": 8, "value": 15432.0},
    "ai_penetration":           {"numerator": 6,     "denominator": 8, "value": 0.75},
    "cr_throughput_per_capita": {"value": 1.5},
    "project_collab_scale":     {"value": 3},
    "project_active_rate":      {"value": 0.66},
    "prototype_direct_rate":    {"value": 0.80},
    "team_agent_depth":         {"value": 0.40},
    "process_completion_rate":  {"value": 0.90}
  }
  ```
- **`scores` 结构**：`{"token_intensity": 82, "ai_penetration": 60, ...}`，8 项各 0–100；观察期内固定 `{}`。
- **索引**（NFR-1：单独迁移文件、`CREATE INDEX CONCURRENTLY`、禁 FK）：
  - 主键 `(bucket_date, scope, scope_id)` 已覆盖 `bucket_date` 前缀查询（org 趋势、`MAX(bucket_date)` 水位）。
  - 迁移 376：`CREATE INDEX CONCURRENTLY idx_maturity_snapshot_scope_date ON maturity_snapshot (scope, scope_id, bucket_date DESC);` —— 服务项目排名（按 `scope='project'` 取最新桶）与建议区历史序列。

### 2.2 读时聚合依赖的既有表（只读，不新增采集）

| 表 | 迁移 | CR-A 用途 |
|---|---|---|
| `task_usage` | 032 | Token 强度/趋势：`input_tokens`+`output_tokens`+`cache_read_tokens`+`cache_write_tokens`，`created_at` |
| `agent_task_queue` | 001(127) + 117 + 368 + 366 | `initiator_user_id`（按人归因，**不用无 user 维的 `task_usage_hourly`**）、`project_id`（项目聚合）、`cr_id`/`pipeline_node_run_id`（ACM 共享队列归属） |
| `cr` | 362 | SII 归档 CR 数（`status='archived'`）；OFI 协作规模读 `owners`(JSONB) |
| `cr_sync_event` | 362 | 状态推进事件（OFI 项目活跃率）、追溯完整率（治理板块） |
| `approval_record` | 362 | 审批时延 P50/P90（`created_at` 相对对应 CR 到达审批门） |
| `pipeline_run` / `pipeline_node_run` | 366 | EPC 原型直出率（`attempt=1 AND status='passed'`，已由 `governance/gate_projection.go` 写入） |
| `activity_log` | 001(156) | 越权尝试次数（`actor_type/action/details`，P1 D7 事件，gitguard FORBIDDEN 拒绝） |
| `feedback` | 057 | 保留（CR-A 不直接消费，供 CR-D 资产复用率） |

### 2.3 口径声明：`maturity-config.yaml`（knowledge-base 本仓）

承载 5 维 8 项子指标的**权重、`floor`、`target`、观察期**，集中于此不硬编码。生成器吐只读 Go 副本 `maturity_config_gen.go`（`server/internal/governance/`），文件头记源 commit SHA（= `config_rev`）。声明结构（示意，具体字段以实现为准）：

```yaml
version: 1
observation_weeks: 4
dimensions:
  - key: AIF   # AI 采用强度
    metrics: [token_intensity, ai_penetration]
  - key: SII   # 超级个体指数（CR-A 仅人均 CR 吞吐）
    metrics: [cr_throughput_per_capita]
  - key: OFI   # 组织流程智能
    metrics: [project_collab_scale, project_active_rate]
  - key: EPC   # 工程原型直出
    metrics: [prototype_direct_rate]
  - key: ACM   # 智能体协作成熟度
    metrics: [team_agent_depth, process_completion_rate]
metrics:
  token_intensity:          { weight: 0.20, floor: 1000, target: 20000 }
  ai_penetration:           { weight: 0.10, floor: 0.2,  target: 0.8 }
  cr_throughput_per_capita: { weight: 0.10, floor: 0.2,  target: 1.5 }
  project_collab_scale:     { weight: 0.10, floor: 2,    target: 8 }
  project_active_rate:      { weight: 0.10, floor: 0.3,  target: 0.8 }
  prototype_direct_rate:    { weight: 0.15, floor: 0.3,  target: 0.9 }
  team_agent_depth:         { weight: 0.15, floor: 0.1,  target: 0.6 }
  process_completion_rate:  { weight: 0.10, floor: 0.3,  target: 0.95 }
```

> 权重/阈值初值仅作占位示意，最终以 `maturity-config.yaml` 落盘值为准；生成器 `--check` 保证声明与 Go 副本零漂移。

---

## 3. 接口契约

### 3.1 HTTP API（全员可读，workspace 鉴权，`X-Workspace-ID`）

注册于 `server/cmd/server/router.go`（chi.Router，沿 `r.Get("/api/config", ...)` 同区段），handler 落 `server/internal/handler/maturity.go`，业务聚合落 `server/internal/service/maturity/`。所有响应经 `packages/core/api/schema.ts` 的 zod `parseWithFallback` 解析。

| 端点 | 方法 | 契约（示意响应字段） | 说明 |
|---|---|---|---|
| `/api/maturity/overall` | GET | `{ config_rev, observation_active, total_score, dimensions: { AIF:{score, metrics:{...}}, ... } }` | 总分 + 8 项子指标 + 观察期状态 |
| `/api/maturity/token-trend` | GET | `{ dimension: 'project'\|'user'\|'model', series: [{ date, value }] }` | 按日趋势，`?dimension=&range=` 下钻 |
| `/api/maturity/rankings` | GET | `{ scope: 'project', items: [{ scope_id, name, score, ... }] }` | 仅 `scope=project`；`scope=user` 返回 400 `{error:'unsupported_scope'}`，不泄露个人榜 |
| `/api/maturity/suggestions` | GET | `{ latest: { week, path, markdown }, has_history }` | 渲染 `docs/org-admin/` 最新文件；空目录返回空态非错误 |
| `/api/maturity/suggestions/history` | GET | `{ items: [{ week, path }] }` | 按周次返回历史文件序列 |
| `/api/maturity/config` | GET | `{ config_rev, observation_weeks, dimensions, metrics }` | 当前口径，全员可读，无需 Owner 权限 |

- **治理板块数据**：并入 `overall` 响应单独 `governance` 字段（不进 `total_score`）：`{ gate_first_pass_rate, evidence_drift_count, traceability_complete_rate, approval_latency_p50_ms, approval_latency_p90_ms, forbidden_attempts }`。
- **API 兼容**（CLAUDE.md）：新增字段 additive；UI 全部 `optional-chain + default`，zod schema 含 malformed-response 测试。

### 3.2 事件/调度契约

- **快照 JobSpec**（`jobs_maturity.go`，`JobName = "maturity_snapshot"`）：`Cadence: 0`（hook-driven）+ `PlansForScope` 枚举 `(lastPlan, dbNow]` 内 `cron '30 0 * * *'` 经 `service.NextOccurrencesUTC(expr, "Asia/Shanghai", after, now)` 求解 + `CatchUpMode: CatchUpEveryPlan` + `MaxPlansPerTick: 7` + `CatchUpWindow: 7×24h` + `Scopes: StaticScopes(global)`。余项照抄 `jobs_autopilot.go` 的 `AutopilotScheduleDispatchJob`（`RunTimeout/StaleTimeout/HeartbeatInterval/AllowStaleReentry:true/MaxAttempts:3/RetryBackoff`）。
- **周报 schedule**：新增 `kind='schedule'` autopilot trigger（cron 每周一 09:00 Asia/Shanghai），复用 `AutopilotScheduleDispatchJob` 既有调度与幂等（`sys_cron_executions` 唯一键 + `autopilot_trigger` 部分唯一索引），挂内置 skill `maturity-weekly-report`。
- **无新事件种类**：CR-A 不新增采集管道、不新增 outbox/队列抽象（NFR-2）。

---

## 4. 关键算法与流程

### 4.1 计分（`service/maturity/score.go`）

```text
score(x) = clamp(100 * (x - floor) / (target - floor), 0, 100)
total_score = Σ_i weight_i * score_i          // 8 项，权重来自 maturity_config_gen.go
```

### 4.2 八项子指标（读时聚合 SQL 伪码，`service/maturity/`）

- **Token 强度**：`SUM(t.input_tokens+t.output_tokens+t.cache_read_tokens) / 活跃成员数`，`task_usage t JOIN agent_task_queue q ON t.task_id=q.id`，按 `q.initiator_user_id` 归人（**不走无 user 维的 `task_usage_hourly`**，R-1）。
- **AI 渗透率**：`COUNT(DISTINCT q.initiator_user_id WHERE 当期发起≥1 Agent 任务) / 全体成员数`。
- **人均 CR 吞吐**：`COUNT(cr WHERE status='archived') / 活跃成员数`。
- **项目协作规模**：`cr.owners ∪ comment ∪ agent_task_queue` 参与者数（目标区间计分，<2 不加分）。
- **项目活跃率**：`COUNT(DISTINCT project WHERE 近14天有 cr_sync_event 状态推进或 agent_task_queue 任务) / 全部项目`。
- **原型直出率**：`COUNT(pipeline_node_run WHERE attempt=1 AND status='passed') / COUNT(全部 pipeline_node_run)`（读 `governance/gate_projection.go` 已写入的投影，R-6）。
- **Team Agent 使用深度**：`COUNT(agent_task_queue WHERE cr_id IS NOT NULL OR pipeline_node_run_id IS NOT NULL) / 全部任务`（共享队列归属）。
- **流程完整率**：`COUNT(cr WHERE 走完 4 条必跑 pipeline 归档) / COUNT(cr WHERE status='archived')`。

### 4.3 快照 rollup（`service/maturity/rollup.go`）

```text
handler(ctx):
  SELECT pg_try_advisory_xact_lock(<maturity lock key>)   -- 幂等 + 并发互斥
  in ONE transaction:
    watermark = SELECT MAX(bucket_date) FROM maturity_snapshot  -- 水位自带，不复用 task_usage_hourly_rollup_state
    for each day in (watermark, target_date]:                    -- 有界窗口，target=前一日 Asia/Shanghai
        for scope in [org, user, project]:
            metrics = compute_metrics(day, scope)                -- 读时聚合
            scores  = observation_active ? '{}' : score(metrics)
            INSERT ... ON CONFLICT (bucket_date, scope, scope_id) DO NOTHING  -- 或按水位语义
            config_rev = maturity_config_gen.go 记录的原 SHA
  COMMIT
```

- 失败回滚时快照行与 `MAX(bucket_date)` 同事务回滚，**水位不前移**（AC-5）。
- 观察期内 `scores='{}'`、`metrics` 照常（AC-6）。
- `CatchUpEveryPlan` 保证停机 3 天恢复后一个 tick 补 3 桶，最多 7 桶（AC-7）。

### 4.4 周报生成（内置 skill `maturity-weekly-report`）

```text
1. 读最近 N 周 maturity_snapshot(scope='org') 序列 + governance 字段
2. 检测治理异常（evidence_drift>0 / 时延 P90 超阈值 / 越权尝试>0）
3. 按「四收益一成本」模板渲染：个人效率/团队交付/知识复利/风险收益 + 成本 五节
4. 第 4 周追加：基于四周实测分布算 floor≈P10、target≈P75 建议（不写 config，仅提请人审）
5. 落盘 docs/org-admin/maturity-review-{YYYY-Www}.md（Org Admin Workspace 项目工作区，不经 git）
6. 经 inbox 通知 Owner
```

---

## 5. 技术选型与替代方案

| 决策 | 选择 | 替代方案及否决理由 |
|---|---|---|
| 配置生成器 | 照抄 `governance/gen/generate-transitions.mjs`：读 yaml → 吐只读 Go 副本（文件头记源 SHA）→ committed → `--check` 重生成 diff 漂移非零退出 | 运行时读 yaml / 跨仓文件依赖：破坏 NFR-4「构建 multica 不 checkout 本仓」；硬编码散落：无法治理版本化口径 |
| 快照调度 | `JobSpec{Cadence:0, PlansForScope}` hook（照抄 autopilot）| 固定 `Cadence:24h`：无法表达固定本地 00:30 时区语义；`CatchUpLatestOnly`：停机后永久缺桶（NFR-3） |
| 水位 | `MAX(bucket_date)` 自带 | 复用 `task_usage_hourly_rollup_state`：跨任务耦合、观察期语义不同 |
| 存储 | **1 张** `maturity_snapshot`（scope 泛化 + JSONB）| 每 scope 一张表 / 强类型列：8 项指标列会随口径演进漂移 DDL，JSONB + 生成器契约更稳；读时纯聚合：无法保证「当时口径下的分数」历史不可变（唯一建表理由） |
| 读侧原始值 | 读时 join 既有事件表 | 快照表冗余原始值：违反「唯一新表」原则，且 raw 值可按当日口径重算 |
| 越权尝试 | 读 `activity_log`（P1 D7 已落）| 新采集管道：违反「P3 不新增采集」主线 |
| 成本列 | 可编辑 `model-prices.yaml`（不精确，UI 标「估算」）| 精确计价：P3 范围外；硬编码价目：不可维护 |

---

## 6. FR 到技术实现映射

| FR | 技术实现条目 |
|---|---|
| FR-1 | `maturity-config.yaml`（本仓）+ `maturity_config_gen.go`（只读副本），权重/阈值/观察期集中 |
| FR-2 | `generate-maturity-config.mjs`（照抄 generate-transitions.mjs 模式：`--check` + 源 SHA 头 + `\r\n→\n` 规范化） |
| FR-3 | `config_rev = maturity-config.yaml` 所在 commit SHA（生成器用 `git rev-parse HEAD` 取，同 transitions 先例） |
| FR-4 | 迁移 375 `maturity_snapshot`（DDL 见 §2.1）；迁移 376 索引（CONCURRENTLY） |
| FR-5 | `jobs_maturity.go` JobSpec（Cadence:0 + PlansForScope + CatchUpEveryPlan + MaxPlansPerTick:7 + StaticScopes(global)） |
| FR-6 | rollup SQL：`pg_try_advisory_xact_lock` + 有界窗口 + 单事务 upsert/水位同提交，水位 `MAX(bucket_date)` |
| FR-7 | 观察期 `scores='{}'`；历史行不可变，口径变更只影响新行，趋势图标注 `config_rev` 断点 |
| FR-8 | 单任务内遍历 org/user/project 写多行，`Scopes: StaticScopes(global)` 不按 scope 展开调度 |
| FR-9 | `packages/views/dashboard/maturity/` 顶部：日期区间 + Owner mode 标记 + 「每日 00:30 更新前一天」 |
| FR-10 | 统计条（活跃成员/Token 总消耗/可选成本列）；成本读 `model-prices.yaml` 标「估算」 |
| FR-11 | `/api/maturity/token-trend` + 按日趋势图（project/user/model 下钻） |
| FR-12 | `/api/maturity/rankings` 仅 `scope=project`；无个人榜/开关/全员通知 |
| FR-13 | 观察期复用 `dim-segmented` + `usage-trend-card` + `leaderboard` 三组件（`packages/views/dashboard/components/`），无雷达图 |
| FR-14 | `service/maturity/score.go` + 8 项聚合查询（§4.2），`score=clamp(100(x−floor)/(target−floor))` |
| FR-15 | governance 字段（§3.1），不进 total_score |
| FR-16 | UI 层数量/质量成对并排渲染 + 指标定义页 + 页脚立场；指标定义写「已知可刷性」 |
| FR-17 | §3.1 六端点；`rankings?scope=user` 返回 400 不支持 |
| FR-18 | 主应用 route（`packages/views` + `apps/web/app` 与 desktop router 各加 platform wiring），无独立 iframe |
| FR-19 | 内置项目 Org Admin Workspace + 内置 Agent（`system_key='org-admin'`，照抄 `mika_agent.go` `CreateMikaAgent` 幂等模式），初始化幂等 |
| FR-20 | 周 schedule Autopilot（cron 每周一）+ 内置 skill `maturity-weekly-report` 落盘 + inbox 通知 |
| FR-21 | 周报模板「四收益一成本」五节，每节引用对应板块指标 |
| FR-22 | 建议区渲染 `docs/org-admin/` 最新文件；`suggestions/history` 按周次序列 |
| FR-23 | 报告追问走 Team Agent 消息流（既有 chat/inbox），保留报告上下文 |
| FR-24 | 第 4 周报告算 floor≈P10/target≈P75 建议，不写 config |

---

## 7. 安全与性能考量

- **Workspace 隔离**：全部查询经 `workspace_id` 过滤，`X-Workspace-ID` 选工作区，请求体不覆盖鉴权上下文（ARCHITECTURE 不变量 1）。
- **无 FK**：`maturity_snapshot` 不建任何 FOREIGN KEY；跨表关系由应用层校验（CLAUDE.md 迁移硬规则）。
- **索引安全**：新索引一律 `CREATE INDEX CONCURRENTLY`、一个迁移文件一条（不变量 6）；迁移从 375 起，保持 rebase 编号序。
- **性能**：日粒度量级，`maturity_snapshot` 行数 ≈ 天数 × scope 数，7 天 catch-up 上限内；读侧聚合命中既有索引（`task_usage(task_id)`、`agent_task_queue(initiator_user_id/project_id/cr_id)`、`pipeline_node_run(run_id,status)` 等），无全表扫新热点。
- **API 兼容**：响应 schema 化解析（`parseWithFallback`），枚举含 default，desktop 容忍 additive 漂移（不变量 8）。
- **隐私/反 Goodhart**：不提供个人排名 UI/user 排名 API/开启开关（NFR-5）；Token 消耗标注为行为数据、页脚明示不作个人考核。
- **权威边界**：CR-A 只读既有事件表、只写 `maturity_snapshot`（操作态投影，可重建），**绝不写** CR 权威文件/状态机（不变量 4）。
- **代码注释英文**：全部新增/修改注释英文（不变量 9）。

## 8. Prompt 采纳影响

本节按 `write-tech-design` 条件性小节评估：本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（CR-A 只新增 multica 读侧/调度代码与本仓配置，无 crctl 命令面或 guard deny 面变更）。故本节省略。
