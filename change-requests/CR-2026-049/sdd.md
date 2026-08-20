---
id: CR-2026-049-sdd
type: SDD
cr-ref: CR-2026-049
title: P3 组织智能 CR-C：跨 CR 追溯与漂移检测 技术设计
status: draft
created: 2026-08-20T20:32:10+08:00
updated: 2026-08-20T20:32:10+08:00
---

# SDD — P3 组织智能 CR-C：跨 CR 追溯与漂移检测

> 对应 PRD `change-requests/CR-2026-049/prd.md` 的 FR-1~FR-16。设计主线不变：E4 走既有 crctl outbox → `cr_sync_event` 投影通道（加 `trace` event_kind，零 CHECK 迁移）；E5 只做服务端确定性前缀扫描（无 Agent、无 LLM、无 daemon）。本文新增的 workspace 维度/key 修正是 `cr_sync_event` 租户安全的必要闭环，不新增 `spec_trace` 表。

## 1. 架构概览

### 1.1 三仓职责划分

| 仓 | 本 CR 的职责 | 产物 |
|---|---|---|
| knowledge-base | 声明层：`dir-graph.yaml#repositories[].commit_prefixes` 与 `remote`（单一事实源） | 声明变更 + 初始白名单 |
| multica | 服务端 + 前端：`cr_sync_event` workspace/key、trace 入账与读 API、`commit_prefix_scan` 调度 job、`drift_finding` 表与读/写、前缀生成器、治理板块 drift 卡与下钻列表、spec 追溯视图 | Go + 迁移 + 前端 |
| tools | crctl 深原语：`writeback-apply --stage traceability` 落盘后发 `trace` outbox 事件（含可恢复 pending/emitted） | `crctl.mjs` / `workspace-transactions.mjs` |

本 CR **不改** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 命令面，也不改 `controlled-shell/rules.json` 的 `protectedPaths.deny`——trace 发射是既有 `writeback-apply` 深原语内部的副作用，因此 SDD 第 8 节（Prompt 采纳影响）不适用，予以省略。

### 1.2 E4 数据流（trace 追溯）

```text
writeback-traceability (crctl writeback-apply --stage traceability)
  ① 写入 specs/{spec_id}/traceability.yml（既有，不变）
  ② commit + lease push 成功
  ③ 读回该 traceability.yml 原始文本（LF 归一）
  ④ emitOutboxEvent(event_kind='trace', payload={spec_id, traceability_yaml}, dedup_name=trace-{cr}-{commit}.json)
      └ journal 记录 trace-outbox: pending|emitted（可恢复）
        v
daemon collector（crevents.go，既有）扫描 .crctl/outbox/*.json
        v
POST /api/daemon/cr-events（server）
        v
governance/crsync.go：validateEvent 接受 'trace' → ingest 入 cr_sync_event（workspace_id 注入）
        v
apply('trace') = ledger-only：写 processed_at，不推进 cr.status
        v
读 API（server/internal/governance/trace.go）：按 workspace 过滤，payload->>'spec_id' 命中
        v
spec 追溯视图 / 全局搜索（packages/views）
```

### 1.3 E5 数据流（前缀扫描 + drift_finding）

```text
knowledge-base dir-graph.yaml#repositories[].commit_prefixes + .remote
        |（声明，git 权威）
        v
multica 生成器 server/internal/commitprefix/gen/generate-prefixes.mjs
  读声明 → 吐只读 Go 副本 server/internal/commitprefix/config_gen.go（文件头记源 SHA）
  --check 在 CI/pre-commit 重生成 diff，漂移非零退出（照抄 maturity/generate-config.mjs 模式）
        v
scheduler job commit_prefix_scan（server/internal/scheduler/jobs_commit_prefix.go）
  每小时，scope=workspace_id，CatchUpLatestOnly
  → 经 GitHub 权威读取（复用 reconcile_github.go 的 fetcher 模式）取各仓 trunk 提交
  → 读取上一成功 plan 的 result.scan_cursors 作为起始游标（首次=建立 baseline）
  → 逐提交比对 commit_prefixes 白名单 → bypass-commit / wip-on-trunk
  → upsert drift_finding（唯一索引去重）
  → 原子写新 scan_cursors 回 sys_cron_executions.result
        v
治理板块（maturity 治理卡 + /api/drift/*）读 drift_finding + sys_cron_executions 健康
```

### 1.4 模块边界与依赖方向

- `server/internal/governance`（既有）：`cr_sync_event` 入账/投影。本 CR 在其上增加 `trace` kind 与 workspace 绑定，**不**新增第二套事件入账。
- `server/internal/commitprefix`（新）：前缀声明类型 + 生成器产物的 Go 消费面（`GeneratedPrefixes()` / `GeneratedConfigRev()`），只依赖生成文件，不依赖 knowledge-base 运行时文件。
- `server/internal/scheduler`（既有）：新增 `commit_prefix_scan` job，复用 `sys_cron_executions` lease/retry/audit。
- `server/internal/drift`（新）：`drift_finding` 的读/写/状态流转与健康聚合，仅被 scheduler job 与 handler 消费。
- `server/internal/governance/trace.go`（新，仍属 governance 包）：trace 读 API，只读 `cr_sync_event` + `cr`。
- 依赖方向遵守 multica `ARCHITECTURE.md`：handler → service → db queries；generated Go 由生成器产出、不得手改；前端 `packages/views` 消费 `packages/core` 的 API client，不镜像服务端状态。

## 2. 数据模型

### 2.1 `drift_finding`（新表，迁移从 385 起）

```sql
-- 385_drift_finding.up.sql（单文件只建表，无 inline 索引、无 FK）
CREATE TABLE drift_finding (
    id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    workspace_id  UUID        NOT NULL,
    repository_id TEXT        NOT NULL,          -- dir-graph.yaml repositories[].id
    spec_id       TEXT,                          -- 本 CR 的 bypass/wip 行为 NULL（仓库级）
    cr_id         TEXT,                          -- 同上，本 CR 为 NULL
    kind          TEXT        NOT NULL CHECK (kind IN ('alignment-drift','impact-stale','bypass-commit','wip-on-trunk')),
    severity      TEXT        NOT NULL CHECK (severity IN ('info','warn','block')),
    summary       TEXT        NOT NULL,
    evidence      JSONB       NOT NULL DEFAULT '{}',
    status        TEXT        NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved','wontfix')),
    found_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at   TIMESTAMPTZ
);
```

后续迁移（每文件一条索引语句，均 `CONCURRENTLY`）：

```text
386: CREATE UNIQUE INDEX CONCURRENTLY drift_finding_id_uidx ON drift_finding (id);
387: ALTER TABLE drift_finding ADD CONSTRAINT drift_finding_pkey PRIMARY KEY USING INDEX drift_finding_id_uidx;
388: CREATE UNIQUE INDEX CONCURRENTLY drift_finding_dedup_idx
       ON drift_finding (workspace_id, repository_id, kind, COALESCE(spec_id, ''), (evidence->>'commit_sha'));
```

- `id` 不 inline `PRIMARY KEY`（内联会隐式建索引，违反「索引必 CONCURRENTLY 且一文件一条」的 `CLAUDE.md` 硬规则）。
- 幂等键含 `workspace_id` + `repository_id` + `COALESCE(spec_id,'')` + `evidence.commit_sha`：不同 workspace/仓库的同名 commit 不冲突；`spec_id` 可空通过 `COALESCE` 归一。
- E5 写入要求 `evidence.commit_sha` 非空（PRD FR-13）。

### 2.2 `cr_sync_event` workspace 维度 + 唯一键（迁移）

`cr_id` 仅在 `cr.workspace_id` 内唯一（`approval.go#latestEvidence` 已有注释确认），`cr_sync_event` 现缺 workspace 维度，导致跨 workspace 同名 CR 的事件/evidence 冲突。迁移序列：

```text
389: ALTER TABLE cr_sync_event ADD COLUMN workspace_id UUID;
390: 数据回填：UPDATE cr_sync_event SET workspace_id = cr.workspace_id
       FROM cr WHERE cr.cr_id = cr_sync_event.cr_id;   -- 回填后仍有 NULL 行（孤儿/多归属）则硬失败
391: ALTER TABLE cr_sync_event ALTER COLUMN workspace_id SET NOT NULL;
392: ALTER TABLE cr_sync_event DROP CONSTRAINT cr_sync_event_cr_id_commit_sha_event_kind_key;  -- 迁移 362 的旧唯一键
393: CREATE UNIQUE INDEX CONCURRENTLY cr_sync_event_ws_cr_commit_kind_uidx
       ON cr_sync_event (workspace_id, cr_id, commit_sha, event_kind);
```

约束：回填遇到「一个 cr_id 映射到多个 workspace」或「映射不到 cr」的历史行必须**非零失败**，不猜测（PRD AC-3）。`trace` event_kind 本身因 `event_kind TEXT` 无 CHECK 而不需要枚举迁移。

### 2.3 前缀白名单声明（knowledge-base `dir-graph.yaml`）

本 CR 为三个参与仓新增 `commit_prefixes` 与 `remote`（GitHub 坐标，供服务端读取）：

```yaml
repositories:
  - id: ai-first-platform-docs
    trunk: master
    remote: "OldBoy405/AI-First-ai-first-platform-docs"   # 示例，以实际为准
    commit_prefixes:
      - "register"
      - "archive"
      - "writeback"
      - "merge"
      - "docs(CR-"
      - "[cr]"
      - "wip:"           # wip: 独立分类（FR-10），不进 bypass
  - id: multica
    trunk: main
    remote: "OldBoy405/AI-First-multica"
    commit_prefixes: ["feat", "fix", "chore", "docs", "test", "refactor", "perf", "Merge", "wip:", "[cr]", "merge"]
  - id: tools
    trunk: custom/main
    remote: "<tools 实际 remote>"
    commit_prefixes: ["feat", "fix", "docs", "test", "chore", "merge", "Merge", "wip:", "[cr]"]
```

初始白名单必须覆盖三个仓**当前 trunk 已确认存在的合法提交格式**（PRD FR-11 / AC-10）；`remote` 若当前未知，SDD 保留字段、以实施期核实值为准填入（不猜测）。`wip:` 单独归类为 `wip-on-trunk`，不计入 bypass。

### 2.4 trace 事件 payload（canonical envelope）

```json
{
  "spec_id": "ai-first-platform",
  "traceability_yaml": "# specs/...traceability.yml ...\nspec-id: ai-first-platform\n..."
}
```

- `spec_id`：稳定别名（供表达式索引 `(payload->>'spec_id') WHERE event_kind='trace'`）。
- `traceability_yaml`：`specs/{spec_id}/traceability.yml` 的 **LF 规范化原始文本**（crctl 零依赖，只 `fs.readFileSync` + `replaceAll('\r\n','\n')`，不做全量 YAML 解析）。
- 语义对象在**读路径**由 server（`gopkg.in/yaml.v3`，`crevents.go` 已在用）解析 `traceability_yaml` 后物化，读 API 返回 `traceability` 对象——满足 PRD AC-1「`payload.traceability` 语义相等」在读取层的判定。

## 3. 接口契约

### 3.1 trace 事件（outbox → cr_sync_event）

- outbox v1 顶层字段沿用：`event_kind='trace'`、`cr_id`、`commit_sha`（writeback commit SHA）、`occurred_at`、`actor`。
- `dedup_name = trace-{cr_id}-{commit_sha}.json`（确定性，同一事实待采集期间只留一份）。
- server `knownEventKinds` 增加 `"trace": true`；`validateEvent` 要求 `cr_id` 形如 `CR-\d{4}-\d{3}`（trace 有 CR 绑定）；`apply()` 增加 `case "trace": return s.applyTrace(...)`，只写 `processed_at`，不触碰 `cr.status`。

### 3.2 生成器 CLI（multica）

```text
node server/internal/commitprefix/gen/generate-prefixes.mjs [--source <knowledge-base worktree>] [--check]
```

- 读 `--source` 下的 `dir-graph.yaml`，只解析 `repositories[].id/trunk/remote/commit_prefixes`；行级解析，非注释/非空白且不匹配预期模式 → 硬错误（禁止静默降级，纪律 #1）。
- 要求源文件相对 HEAD clean；取 `git log -1 --format=%H -- dir-graph.yaml` 作为源 SHA，写入生成文件头。
- 产出 `server/internal/commitprefix/config_gen.go`：`GeneratedConfigRev() string` + `GeneratedPrefixes() map[string]RepoPrefixDecl`（key=repo id，含 trunk、github owner/repo、prefixes 切片，`wip:` 单列）。
- `--check`：重生成产物与磁盘文件不一致 → 退出非 0；供 CI/pre-commit 挂接。

### 3.3 `commit_prefix_scan` job（scheduler）

```text
Name: "commit_prefix_scan"
Cadence: 1h；ScheduleDelay: 0
CatchUpMode: CatchUpLatestOnly（cursor 增量，晚跑一次即可追上）
Scopes: 动态 workspace 枚举（scope_kind="workspace", scope_id=workspace_id）
MaxPlansPerTick: 1（每 workspace 每 tick 一个 plan）
RunTimeout/StaleTimeout/RetryBackoff：对齐 jobs_maturity.go
Handler: 见 §4.2
```

注册点：`server/cmd/server/main.go`，与 `MaturitySnapshotJob`/`ReconcileJob` 并列。workspace 无声明仓或全部仓访问失败时 handler 返回 error → plan=FAILED（不写「无 finding」成功态）。

### 3.4 drift 读/写 API（multica）

| 方法/路径 | 语义 |
|---|---|
| `GET /api/drift/overview` | workspace-scoped：`scan_health`（uninitialized|ok|stale|failed）、`bypass_count`、`wip_on_trunk_count`、`resolve_latency`（P50/P90）、每仓最新 cursor 摘要 |
| `GET /api/drift/findings?status=&kind=&repository_id=&limit=&cursor=` | finding 分页列表，`open` 优先 |
| `PATCH /api/drift/findings/{id}` | `{status}` 流转：`open→acknowledged→resolved`（写 `resolved_at`）或 `wontfix`；校验当前 workspace 归属 |

路由挂载在 `router.go` 的 governance/workspace 区，handler 复用 `X-Workspace-ID` 上下文（同 maturity 六个端点）。

### 3.5 trace 读 API（multica）

| 方法/路径 | 语义 |
|---|---|
| `GET /api/cr/trace?spec_id=` | 当前 workspace 内该 spec 的 trace 事件时间线：按 `occurred_at` 升序，返回解析后的 `traceability` 对象 + commit/merge/evidence 跳转数据 |
| `GET /api/cr/owner-specs?owner=` | 当前 workspace 内该 owner 经手过的 spec 列表（join `cr.owners`，只读当前 workspace） |

两者都直接读 `cr_sync_event`（`payload->>'spec_id'`）+ `cr`，不得以 `cr_id` 单独隔离（PRD FR-5/FR-8）。

## 4. 关键算法与流程

### 4.1 trace 发射与可恢复重试（tools crctl）

在 `applyWritebackAtomic` 的 traceability 阶段，commit+push 成功后：

```text
payload.traceOutboxEmitted == false:
  text = readFile(specs/{spec_id}/traceability.yml).replaceAll('\r\n','\n')
  name = emitOutboxEvent(ws, { event_kind:'trace', cr_id:cr, commit_sha:commit,
                               dedup_name:`trace-${cr}-${commit}.json`,
                               payload:{ spec_id:specId, traceability_yaml:text } })
  name != null → payload.traceOutboxEmitted = true; save(journal.phase)
  name == null → warnings += EMIT_FAILED（不阻断 writeback 完成，保留 pending）
```

- 幂等重放：journal `phase=complete` 但 `traceOutboxEmitted` 未置位时，重跑同一 `writeback-apply --stage traceability` 会补发（复用 `emitArchiveIfNeeded` 同构的「complete 后补发」模式，见 `applyWritebackAtomic` 既有 baseline outbox 逻辑）。
- 确定性 `dedup_name` 保证同一事实待采集期间只留一份；server 唯一键 `(workspace_id, cr_id, commit_sha, event_kind)` 兜底最终去重。

### 4.2 前缀扫描（server commit_prefix_scan）

```text
handler(plan):
  decls = commitprefix.GeneratedPrefixes()          # 生成产物，含 remote/trunk/prefixes
  last = 最近成功 plan 的 result.scan_cursors        # map[repo_id]SHA；首次为 null
  for repo in decls:
    head = githubHeadSha(repo)                       # 复用 reconcile_github.go fetcher
    commits = githubCommits(repo.trunk, until=last[repo] ?? none)
    if last[repo] == null:                           # 首次 → baseline，只记录不判分
       cursors[repo] = head; continue
    if last[repo] 不在 commits 历史: → plan FAILED（不猜测重置）
    for c in commits（新→旧，止于 last[repo]，不含）:
      classify(c.subject, repo.prefixes) → finding(bypass-commit|wip-on-trunk)
  upsert findings（ON CONFLICT DO NOTHING，唯一索引去重）
  全部仓成功 → result = { scan_cursors: cursors, ... }（原子写入成功 plan）
  任一仓失败/中断 → 不写新 cursors，plan FAILED，下次从旧 cursor 续跑
```

- 判定：`wip:` 前缀优先判为 `wip-on-trunk(info)`；其余不在白名单 → `bypass-commit(warn)`（PRD FR-10）。
- finding `evidence = { repository_id, trunk, commit_sha, commit_subject, scanned_at }`，`spec_id/cr_id` 为 NULL。
- 游标只推进「完整成功」：中途失败保留旧 cursor，重试允许重复读取但靠唯一索引去重，不丢提交（PRD FR-14）。

### 4.3 健康状态判定（治理板块）

```text
最新成功 plan 的 result.scan_cursors 覆盖全部声明仓 且 finished_at 距 now ≤ 2h → ok
无成功记录 → uninitialized
最新 plan = FAILED 或 finished_at > 2h → failed/stale
只有 ok 且 findings 为空 → 「无漂移」
```

健康事实源复用 `sys_cron_executions`（job_name=`commit_prefix_scan`），不新建平行状态表。

## 5. 技术选型与替代方案

| 决策 | 选择 | 理由 / 替代 |
|---|---|---|
| trace payload 传输形态 | `{spec_id, traceability_yaml}` 原始文本 | crctl 零依赖、仅子集 YAML 解析器；全量语义对象由 server（gopkg.in/yaml.v3）在读路径物化。替代：crctl 全量解析——需引入完整 YAML 依赖，违背 crctl 零依赖约束 |
| `cr_sync_event` 租户安全 | 加 `workspace_id` + 回填 + 换唯一键 | 既有 `latestEvidence` 已靠 `JOIN cr` 兜 workspace；不加则 trace/finding 跨 workspace 串数据。替代：不加列、读侧全部 JOIN cr——无法约束事件唯一键，且每个查询都绕 |
| 扫描游标落点 | `sys_cron_executions.result.scan_cursors` | 复用既有 job 审计/lease 表，不新建状态表。替代：新 `scan_state` 表——多一份要清理的状态，违背 NFR-2 |
| 仓库读取 | GitHub commits API（复用 reconcile fetcher 模式） | server 只读远端提交 subject+SHA，无需 checkout 三仓。替代：server 维护 bare clone 缓存——新增一套服务器端仓库生命周期；否决 |
| 生成器 | 照抄 `generate-config.mjs` | 已证明的「声明→Go 副本→--check」模式；构建 multica 不需 checkout 本仓。无替代 |
| 迁移编号 | 385 起（当前最大 384） | 2026-08-20 核实 375–379=CR-A、380–384=CR-B |
| 索引布局 | 每文件一条 `CONCURRENTLY` + `USING INDEX` 建 PK | multica `CLAUDE.md` 硬规则；`maturity_snapshot` 375–377 已用同一模式 |

## 6. FR 到技术实现映射

| FR | 实现落点 |
|---|---|
| FR-1 trace 发射 | tools `workspace-transactions.mjs#applyWritebackAtomic`（traceability 阶段）+ `crctl.mjs#emitOutboxEvent` 复用 |
| FR-2 server 接受 trace（ledger-only） | multica `governance/crsync.go`：`knownEventKinds` + `validateEvent` + `apply("trace")` 写 `processed_at` |
| FR-3 trace 可恢复 outbox | tools journal `traceOutboxEmitted` + 确定性 `dedup_name` + complete 后补发 |
| FR-4 `cr_sync_event` workspace/key | multica 迁移 389–393 + `crsync.go#ingest` 注入 `workspace_id` + `approval.go#latestEvidence` 等读侧去 JOIN 兜底（改用新列直取） |
| FR-5 trace 查询 + 表达式索引 | multica 迁移（独立 `CONCURRENTLY` 表达式索引）+ `governance/trace.go` |
| FR-6 spec 时间线 | multica `governance/trace.go` + `packages/views` spec 追溯视图 |
| FR-7 一跳直达 | 读 API 返回 traceability evidence 路径/SHA；前端按证据渲染链接 |
| FR-8 全局搜索按 owner 反查 | `governance/trace.go` owner-specs（join `cr.owners`，workspace 过滤） |
| FR-9 `commit_prefix_scan` job | multica `scheduler/jobs_commit_prefix.go` + `main.go` 注册 |
| FR-10 判定口径 | `scheduler/jobs_commit_prefix.go#classify`（wip 优先，bypass 兜底） |
| FR-11 白名单 + 生成器 | knowledge-base `dir-graph.yaml` + multica `commitprefix/gen/generate-prefixes.mjs` → `config_gen.go` |
| FR-12 `drift_finding` 表 | multica 迁移 385（表）+ 386–388（索引/PK/dedup） |
| FR-13 幂等键 | 迁移 388 唯一索引 + `ON CONFLICT DO NOTHING` |
| FR-14 增量游标 | `jobs_commit_prefix.go` handler（§4.2） |
| FR-15 健康状态进治理板块 | `drift` 读 API + maturity 治理卡前端 |
| FR-16 finding 流列表页 + 状态流转 | `drift` 读/写 API + `packages/views` 列表页 |

FR 覆盖率：**16 / 16**。

## 7. 安全与性能考量

- **租户隔离（硬不变量 1）**：`drift_finding`、`cr_sync_event` 全部写入带 `workspace_id`；读 API 一律以鉴权上下文 workspace 过滤，绝不信任请求体 workspace；trace/finding 查询不得以 `cr_id`/`spec_id` 单独隔离。
- **Git 权威（硬不变量 4）**：本 CR 不新增 crctl 状态写者；trace 只是投影事件，`cr.status` 仍由 crctl 独有。
- **迁移安全（硬不变量 6）**：无新 FK；所有新索引 `CONCURRENTLY` 一文件一条；`cr_sync_event` 回填不确定即失败，绝不静默。
- **扫描旁路只读**：`commit_prefix_scan` 只读远端 commit subject/SHA，不写被扫仓，不阻塞提交；仓不可访问 → plan FAILED（失败可见，不伪装零漂移）。
- **性能**：trace 查询走表达式索引 `(payload->>'spec_id') WHERE event_kind='trace'`；finding 列表按 `(workspace_id, status)` 查询，量级极小（每日/每小时逐 commit 一行）；`sys_cron_executions` 复用既有保留/重试策略，`result` 保持小体量（仅游标 map）。
- **敏感面**：扫描仅取 commit subject（公开元数据），不取 diff/文件内容；PAT 内存持有、不落日志（沿用 reconcile 纪律）。
- **英文注释（硬不变量 9）**：multica 新增源码注释一律英文；knowledge-base/tools 文档与 CR 产物用中文。

## 8. Prompt 采纳影响

本节按 `write-tech-design` Skill 的触发条件判断：本 CR 不新增/变更 `crctl.mjs` 的 dispatch 子命令分支，也不改 `controlled-shell/rules.json#protectedPaths.deny`，因此**本节省略**。trace 发射是 `writeback-apply` 深原语内部副作用，`writeback-traceability` Skill 仍只调用一次 `crctl writeback-apply`，无需改 prompt。
