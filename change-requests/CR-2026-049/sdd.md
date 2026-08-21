---
id: CR-2026-049-sdd
type: SDD
cr-ref: CR-2026-049
title: P3 组织智能 CR-C：跨 CR 追溯与漂移检测 技术设计
status: draft
created: 2026-08-20T20:32:10+08:00
updated: 2026-08-20T20:50:39+08:00
---

# SDD — P3 组织智能 CR-C：跨 CR 追溯与漂移检测

> 对应 PRD FR-1~FR-16。E4 复用 crctl outbox → `cr_sync_event`；E5 使用服务端确定性 `sys_cron` job。Git/crctl 继续是 CR 权威；Multica 只保存投影与治理 finding；不建 `spec_trace`，不新增 Agent/LLM/daemon 扫描。

## 0. 第 1 轮评审回修摘要

| Blocker | 回修结论 |
|---|---|
| TD-B1 canonical payload 被改写 | 恢复批准的 `{spec_id, traceability}`；traceability generator 产出受 candidate digest 保护的完整语义对象，crctl 不做第二次自由解析 |
| TD-B2 pending 在归档后可能丢失 | writeback journal 保存完整 trace intent；`writeback-apply` complete replay 前置；archive 在任何 authority/cleanup 前强制补发，失败硬阻断并保留现场 |
| TD-B3 冲突重投误 ack | `trace` 使用事务内 insert-or-load + `FOR UPDATE` + processed 标记；只有 committed processed 行才 ack |
| TD-B4 workspace 回填/切换不确定 | 显式多归属/孤儿 preflight；维护窗口下按 new-index-before-old-drop 切换；覆盖 ingest、lock、processed、runner、maturity、approval 全 seam；完整编号 385–397 |
| TD-B5 per-workspace repo access 未闭环 | 三仓 remote 已核实；generated declaration 与 `workspace.repos` 精确绑定；复用 workspace GitHub installation + `ghsnapshot.Client`，缺绑定/权限即 FAILED |
| TD-B6 GitHub 增量不能证明不漏扫 | 固定本轮 HEAD=B，以 `sha=B` 分页直到精确 A；任何截断/未命中/限流失败均不推进 cursor |
| TD-B7 API/测试契约不足 | 补版本化 DTO、错误码、keyset、状态 CAS、malformed fallback、权限矩阵及 AC-1~AC-15 分层测试矩阵 |

## 1. 架构概览

### 1.1 三仓职责

| 仓 | 职责 | 主要产物 |
|---|---|---|
| knowledge-base | 产品级仓库声明单一事实源 | `dir-graph.yaml#repositories[].remote/commit_prefixes` |
| tools | trace semantic candidate、writeback journal/outbox、archive pending gate | `writeback-traceability.mjs`、`yaml-subset.mjs`、`workspace-transactions.mjs`、`crctl.mjs` callback adapter、两个 writeback/archive Skill 契约 |
| multica | trace tenant-safe ledger/读侧、commit scan、finding/API/UI | migrations 385–397、governance/commitprefix/drift/scheduler、core schema/client、views |

目标代码仓根目录 `ARCHITECTURE.md` 均已存在并已核对：tools 保持 crctl CLI→lib 单向依赖和零第三方依赖；multica 保持 handler→service/query、workspace 隔离、generated file 不手改、索引独立 `CONCURRENTLY` migration。

### 1.2 E4 trace 写入流

```text
writeback-traceability.mjs
  生成 LF traceability.yml
  → 用加固后的版本化 YAML subset parser 解析完整受控文档
  → validateTraceSemantic（spec-id、cr-ref、milestones、当前 CR 唯一段、段数）
  → candidate manifest v2.event = {kind:'trace', payload:{spec_id, traceability}, payload_sha256}
  → manifest inputDigest 覆盖 event
        │
crctl writeback-apply --stage traceability
  validate manifest/event → commit/push
  → journal.traceOutbox={state:'pending',commit,dedupName,payload,payloadSha256}
  → 通过 cmdWritebackApply 注入的 emitTraceEvent callback 写 outbox
  → 成功 state=emitted；失败 warning + 保持 pending
        │
daemon collector（既有，at-least-once）
        │ POST /api/daemon/cr-events
server governance.crsync
  workspace 来自 daemon auth（不信任 body）
  → trace payload schema 校验
  → transaction: insert-or-load → row lock → processed_at → commit
  → committed processed 后才 Accepted
        │
cr_sync_event(workspace_id,event_kind='trace',payload canonical JSON)
        │
trace API / spec 详情页 / 全局搜索
```

`workspace-transactions.mjs` 不反向 import CLI：`cmdWritebackApply` 与 `cmdArchive` 分别注入 `emitTraceEvent`/`replayTraceEvent` callback，均复用 `crctl.mjs#emitOutboxEvent`。

### 1.3 E4 pending 生命周期（最终交付门禁）

1. trace commit 确认后，journal 先保存完整 canonical payload/commit/dedupName，再尝试 outbox；因此 txws/candidate 不是补发所需输入。
2. `applyWritebackAtomic` 在 `resolveOperationalWorkspace` 和 candidate 读取**之前**先读取 `{cr}-traceability` writeback journal；若 `phase=complete && state=pending`，仅用 journal intent 补发，成功置 `emitted` 后返回，不要求 txws 仍存在。
3. `archiveCr` 在创建 archive journal、写 authority commit、清理任何 worktree **之前**读取同一 writeback journal：
   - `emitted`：继续；
   - `pending`：调用 `replayTraceEvent`；成功持久化 `emitted` 后继续；
   - 仍失败：抛 `ARCHIVE_TRACE_PENDING`，零 archive 写入、零 cleanup，保留可恢复现场；
   - journal 缺失/commit 或 payload digest 不完整：`ARCHIVE_TRACE_FACT_MISSING` 硬失败。
4. `writeback-traceability` Skill 必须把 `EMIT_FAILED(event_kind=trace)` 输出为“writeback 已完成、trace pending”；`cr-archive` Skill 对 `ARCHIVE_TRACE_PENDING` 只提示重跑同一 archive，不绕门。collector 只负责已落盘文件重试。

### 1.4 E5 扫描流与 workspace 绑定

```text
knowledge-base dir-graph.yaml
  repositories[].{id,remote,trunk,commit_prefixes}
      │ generator --source / --check
      v
multica server/internal/commitprefix/config_gen.go
  {repo_id, canonical_url, owner, repo, trunk, prefixes, config_rev}
      │
workspace scope provider：枚举 workspace；workspace.repos 含 knowledge-base canonical URL 才 eligible
      │
RepositoryBindingResolver
  generated repo canonical_url 必须逐一存在于 workspace.repos
  → workspace GitHub installations 中解析出对 owner/repo 有 Contents:Read 的唯一 installation
  → ghsnapshot.Client mint/cache installation token
      │
commit_prefix_scan（每小时、scope=workspace/{uuid}）
  固定各仓 HEAD B → 从 B 分页到上一成功 cursor A → 分类 → upsert findings
  → 全仓成功才让 scheduler success result 写新 scan_cursors/config_rev/repository_ids
      │
/api/drift/* + maturity 治理卡 + finding 下钻页
```

0.23 只支持生成声明中的 GitHub HTTPS remote；SSH URL 在 `workspace.repos` 先 canonicalize 为同一 owner/repo；非 GitHub provider 返回 `repository_provider_unsupported` 并令 plan FAILED，不静默跳仓。扫描仍是服务端纯 Go，无 daemon/LLM。

### 1.5 Multica 模块边界

- `internal/governance`：事件 ingestion/projection + `trace.go` 读服务；`trace` ledger-only，不改变 `cr.status`。
- `internal/commitprefix`：声明 DTO、generated file、严格 generator；不运行时读取 knowledge-base 文件。
- `internal/integrations/ghsnapshot`：复用 App JWT/installation token 缓存，扩展 `ResolveRepositoryAccess`/`ListCommits`，不记录 token。
- `internal/drift`：finding repository、状态 CAS、overview/health pure functions。
- `internal/scheduler/jobs_commit_prefix.go`：每 workspace job orchestration；不承载 HTTP DTO。
- `internal/handler`：workspace membership + 参数/DTO/error envelope。
- `packages/core`：Zod schema、`parseWithFallback` client；`packages/views`：spec trace、global search result、drift card/list。

## 2. 数据模型与迁移

### 2.1 `drift_finding`

```sql
CREATE TABLE drift_finding (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL,
  repository_id TEXT NOT NULL,
  spec_id TEXT,
  cr_id TEXT,
  kind TEXT NOT NULL CHECK (kind IN ('alignment-drift','impact-stale','bypass-commit','wip-on-trunk')),
  severity TEXT NOT NULL CHECK (severity IN ('info','warn','block')),
  summary TEXT NOT NULL,
  evidence JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved','wontfix')),
  found_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  CHECK (
    kind NOT IN ('bypass-commit','wip-on-trunk') OR
    (COALESCE(evidence->>'repository_id','') <> '' AND
     COALESCE(evidence->>'trunk','') <> '' AND
     COALESCE(evidence->>'commit_sha','') <> '' AND
     COALESCE(evidence->>'commit_subject','') <> '' AND
     COALESCE(evidence->>'scanned_at','') <> '')
  )
);
```

E5 行固定 `spec_id=NULL, cr_id=NULL`；应用层先做同样 evidence 校验，DB CHECK 是最后防线。无 FK。

### 2.2 `cr_sync_event` / approval workspace contract

- `cr_sync_event.workspace_id UUID NOT NULL` 由 daemon auth context 注入；event body 不含可信 workspace。
- 事件唯一键：`(workspace_id, cr_id, commit_sha, event_kind)`。
- trace 查询索引：`(workspace_id,(payload->>'spec_id'),occurred_at,id) WHERE event_kind='trace'`。
- unprocessed 索引改为 `(workspace_id,cr_id,received_at) WHERE processed_at IS NULL`。
- approval approve 幂等索引改为 `(workspace_id,cr_id,stage,evidence_digest) WHERE decision='approve'`；所有 conflict/select 都加 workspace。
- in-process mutex key 改为 `workspaceID + "\x00" + crID`，避免两个租户同名 CR 串行/互扰。

### 2.3 迁移清单（当前最大 384，完整编号）

| 编号 | 内容 |
|---|---|
| 385 | 建 `drift_finding` 表（无 inline PK/FK/index） |
| 386 | `CREATE UNIQUE INDEX CONCURRENTLY drift_finding_id_uidx ...` |
| 387 | `ADD CONSTRAINT drift_finding_pkey PRIMARY KEY USING INDEX ...` |
| 388 | PRD 固定 `drift_finding_dedup_idx`（CONCURRENTLY） |
| 389 | finding keyset：`CREATE INDEX CONCURRENTLY ... (workspace_id,status,found_at DESC,id DESC)` |
| 390 | `cr_sync_event` 加 nullable `workspace_id`；先 preflight，再确定性回填、零 NULL 断言、SET NOT NULL |
| 391 | 新 workspace event unique index（CONCURRENTLY） |
| 392 | trace spec expression index（CONCURRENTLY） |
| 393 | workspace unprocessed index（CONCURRENTLY） |
| 394 | 删除旧 `cr_sync_event_cr_id_commit_sha_event_kind_key`（新 unique 已存在） |
| 395 | `DROP INDEX CONCURRENTLY idx_cr_sync_event_unprocessed` |
| 396 | 新 approval workspace approve unique index（CONCURRENTLY） |
| 397 | `DROP INDEX CONCURRENTLY approval_record_approve_uniq` |

每个 CREATE/DROP INDEX migration 只有一条索引语句；386/388/389/391/392/393/396 均在 `cmd/migrate` concurrent invalid-index cleanup registry 登记并由现有 migration test 扫描。down migration 反向恢复时也遵守先建旧 index、再删新 index 的可用顺序。

### 2.4 workspace 回填的确定性 preflight

迁移 390 在 UPDATE 前执行：

```sql
DO $$
BEGIN
  IF EXISTS (
    SELECT e.cr_id
    FROM cr_sync_event e
    LEFT JOIN cr c ON c.cr_id=e.cr_id
    GROUP BY e.cr_id
    HAVING count(DISTINCT c.workspace_id) <> 1
  ) THEN RAISE EXCEPTION 'cr_sync_event workspace backfill is ambiguous or orphaned';
  END IF;
END $$;

UPDATE cr_sync_event e
SET workspace_id=(SELECT c.workspace_id FROM cr c WHERE c.cr_id=e.cr_id);

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cr_sync_event WHERE workspace_id IS NULL)
  THEN RAISE EXCEPTION 'cr_sync_event workspace backfill left null rows'; END IF;
END $$;
ALTER TABLE cr_sync_event ALTER COLUMN workspace_id SET NOT NULL;
```

`count != 1` 同时阻断孤儿（0）与多归属（>1），不会由 `UPDATE ... FROM` 任意选行。

### 2.5 schema/code 切换顺序

这是一次短维护窗口切换（未要求零停机）：

1. 暂停旧 server 的 `/api/daemon/cr-events` 与 approval 写入口；daemon outbox 保留文件，不丢事实。
2. 执行 385–397：新 index 始终先于旧 index/constraint 删除；390 任一断言失败则停止且不启动新代码。
3. 启动已切到 workspace conflict target 的新 server；运行启动 smoke：两个 workspace 同名 CR、trace ingest、approval idempotency。
4. 恢复入口，daemon at-least-once 重投。

受影响 seam 全量清单：`crsync.go` INSERT/ON CONFLICT/processed UPDATE/mutex；`runner.go` checkpoint join；`maturity.sql` 全部七处 event join；`approval.go` latestEvidence、approve conflict/idempotent select；governance/maturity/runner 测试 fixture；daemon commit-scan/reconcile 若写 event 也必须传 auth workspace。未列出的 `cr_id` 单键 event 查询由静态 grep contract test 阻断。

### 2.6 trace canonical payload 与 candidate manifest v2

批准的 event payload 不变：

```json
{
  "spec_id": "ai-first-platform",
  "traceability": {
    "spec-id": "ai-first-platform",
    "cr-ref": "CR-2026-049",
    "cr-history": ["CR-2026-001", "CR-2026-049"],
    "target-version": "0.23",
    "baseline-since": "0.10",
    "generated-at": "2026-08-20T20:00:00+08:00",
    "milestones": []
  }
}
```

实现契约：

- `yaml-subset.mjs` 修正“以 `{` 开头但不是合法 flow map 的 plain scalar”并将无法解释的结构硬失败；fixture 覆盖当前 191KB 累积 traceability、CRLF、plain scalar、flow map/seq、嵌套 milestones。
- generator 对 `newText` 解析后运行 `validateTraceSemantic`：顶层键、`spec-id==specId`、`cr-ref==cr`、milestones 为数组、YAML 中 `- cr:` 数量等于对象数组长度、当前 CR 恰一段、该段含 `frs|fr-chain` 与 evidence。
- traceability candidate 使用 manifest v2；`event.kind/event.payload/event.payloadSha256` 纳入 canonical `inputDigest`。baseline/tasks 继续接受 v1；traceability stage 必须 v2，validator 重新计算 payload SHA 并校验 `payload.spec_id==payload.traceability['spec-id']`。
- journal 保存 manifest 已验证 payload，不从发布后的文件重新自由解析。

## 3. 事件、调度与 API 契约

### 3.1 outbox / server trace schema

- v1 顶层沿用：`event_kind='trace'`、`cr_id`、writeback `commit_sha`、`actor`、`occurred_at`；`dedup_name=trace-{cr_id}-{commit_sha}.json`。
- `knownEventKinds` 增加 trace；`ledgerlessKinds` 不增加 trace；`apply()` 对 trace 不调用状态转换。
- payload 校验失败返回 rejected `{file,code:'BAD_TRACE_PAYLOAD'}`，文件保留；最大 payload 2 MiB，超过返回 `TRACE_PAYLOAD_TOO_LARGE`（当前基线约 192 KiB）。
- trace transaction：
  1. `BEGIN`；`INSERT ... ON CONFLICT (workspace_id,cr_id,commit_sha,event_kind) DO NOTHING`；
  2. `SELECT id,processed_at,payload FROM cr_sync_event WHERE workspace_id=$1 ... FOR UPDATE`；
  3. 已 processed 且数据库 JSONB `payload = incoming::jsonb` 语义相等 → commit 幂等成功；payload 不同 → `EVENT_IDEMPOTENCY_CONFLICT`、rollback/reject（不依赖 JSON 对象键顺序）；
  4. 未 processed → schema validate + `UPDATE ... SET processed_at=now()`；commit；
  5. `HandleCREvents` 仅在 commit 后加入 Accepted。

### 3.2 `commit_prefix_scan` JobSpec

```text
Name              commit_prefix_scan
Cadence           1h
ScheduleDelay     0
CatchUpMode       CatchUpLatestOnly
Scopes            activePlatformWorkspaceScopes(pool)
RunTimeout        10m
StaleTimeout      15m
HeartbeatInterval 30s（每一 GitHub page 后显式 Heartbeat）
AllowStaleReentry true（finding insert 幂等，cursor 只在 SUCCESS result 中推进）
MaxAttempts       3
RetryBackoff      1m, 5m, 15m
```

scope provider 枚举 workspace，解析 `workspace.repos`；含 canonical knowledge-base URL 的 workspace 才进入 scope。没有平台 repo 配置的普通 Multica workspace 不制造失败计划，治理页显示 `uninitialized/not_configured`。进入 scope 后三仓必须全部绑定成功，否则 plan FAILED。

成功 result v1：

```json
{
  "v": 1,
  "config_rev": "<dir-graph source commit sha>",
  "repository_ids": ["ai-first-platform-docs", "multica", "tools"],
  "scan_cursors": {
    "ai-first-platform-docs": "sha",
    "multica": "sha",
    "tools": "sha"
  },
  "finding_count": 2
}
```

### 3.3 repo binding 与真实初始声明

已用 `git remote -v` 核实：

| repo id | canonical remote | trunk |
|---|---|---|
| ai-first-platform-docs | `https://github.com/OldBoy405/AI-First-Platform.git` | `master` |
| multica | `https://github.com/OldBoy405/AI-First-multica.git` | `main` |
| tools | `https://github.com/OldBoy405/AI-First-tools.git` | `custom/main` |

初始 `commit_prefixes` 使用大小写敏感 `strings.HasPrefix`；值含分隔符，禁止用裸 `feat` 误匹配 `feature`：

```yaml
# knowledge-base
commit_prefixes: ["[cr] ", "register ", "archive ", "writeback ", "merge ", "Merge ", "feat(", "fix(", "docs(", "chore(", "test(", "refactor(", "perf("]
# multica（含上游 MUL-123: 格式）
commit_prefixes: ["MUL-", "Merge ", "merge ", "feat(", "fix(", "docs(", "chore(", "test(", "refactor(", "perf(", "build(", "ci(", "style(", "revert:", "[cr] "]
# tools
commit_prefixes: ["[cr] ", "Merge ", "merge ", "feat(", "feat:", "fix(", "fix:", "docs(", "docs:", "chore(", "chore:", "test(", "test:", "refactor(", "perf("]
```

`wip:` 是优先分类保留字，不进入合法白名单；classifier 在白名单判断前产生 `wip-on-trunk`。generator 以各仓 trunk 最近 200 条 subject 运行 coverage fixture；任何当前 subject 未匹配必须在提交声明前被人工分类（新增白名单或作为预期 finding），AC-10 不靠猜测。普通 Multica build 只编译已提交的 Go 副本、不 checkout knowledge-base；独立 generator-sync CI job 显式 checkout knowledge-base 源 SHA 后运行 `--check`，pre-commit 则由开发工作区传 `--source`。

绑定算法：generated canonical URL 与 `workspace.repos[].url` 规范化后精确相等；现有持久化契约只有 URL/description，因此 trunk 只取 generated declaration，不虚构 `workspace.repos.ref`。加载当前 workspace 的 `github_installation`，用 `ghsnapshot.Client` 对 owner/repo 检查 Contents:Read；零个可用 installation → `repository_access_missing`，多于一个 → `repository_access_ambiguous`。token 只在 client 内存缓存且从不落日志/result。

### 3.4 精确增量算法

对每仓：

1. `GET /repos/{owner}/{repo}/commits?sha=<url.Values 编码的 trunk>&per_page=1`，固定响应首 SHA 为 B；`custom/main` 仅作为 query value 编码，不拼 path。
2. 首次（无 A）：仅设置 candidate cursor=B，不生成 finding。
3. 非首次：从 `GET .../commits?sha=B&per_page=100&page=1` 起分页；分页根固定 SHA B，因此扫描期间 trunk 前进不进入本轮。
4. 按 API 顺序收集，直到**精确 SHA==A**；分类 A 之前的 `[B..A)`；同一页也保持新→旧顺序，写 finding 与顺序无关。
5. 每页 heartbeat；403/429/5xx、timeout、malformed JSON、空页未命中 A、100 页（10,000 commit）仍未命中均返回明确 error，plan FAILED、cursor 不推进。429/403 的 rate-limit 元数据只进结构化 error，不记录 token。
6. cursor 未命中视为历史重写/非祖先，不自动 baseline；人工修复后才可清 cursor。
7. 全仓 walk 成功后，在 DB transaction 中 `INSERT ... ON CONFLICT DO NOTHING` findings；handler 返回 candidate cursors。若 insert 后、scheduler success 更新前崩溃，下次从旧 A 重读，唯一索引去重且不漏提交。

分类先判断 `strings.HasPrefix(subject,"wip:")` → `wip-on-trunk/info`；否则任一白名单前缀命中为合法；否则 `bypass-commit/warn`。subject 为 commit message LF 规范化后的第一行。

### 3.5 trace API（v1）

所有端点使用 `X-Workspace-ID` + `workspaceMember`；body/query workspace 不取信。

#### `GET /api/cr/specs/{spec_id}/trace`

```json
{
  "v": 1,
  "workspace_id": "uuid",
  "spec_id": "ai-first-platform",
  "events": [{
    "event_id": 123,
    "cr_id": "CR-2026-049",
    "commit_sha": "abc",
    "occurred_at": "RFC3339",
    "state": "ok",
    "milestone": {
      "cr": "CR-2026-049",
      "frs": [],
      "merge_commits": [],
      "evidence": {}
    }
  }]
}
```

查询按 `(occurred_at,id)` 升序加载事件，并用**最新有效完整 snapshot** 的全部 milestones 作为展示集合，不能只取当前事件 CR（首个 trace 必须把 CR-C 之前的累积历史带入）。投影规则：以 `(milestone.cr,milestone.milestone)` 去重；将所有有效 trace event 的 `cr_id→(occurred_at,id)` 映射回对应 milestone；有事件的条目按 `(occurred_at,id)` 排序，首个 snapshot 导入但没有独立 trace event 的历史条目标记 `source='baseline-imported'` 并保持文档顺序、排在事件条目前。`frs` 与历史 `fr-chain` 统一规范为响应字段 `frs`；同 key 在两个 snapshot 的语义 hash 不同则该条标记 `trace_snapshot_conflict`，不静默覆盖。新事件 ingestion 仍要求 `event.cr_id` 在 payload 中恰一段。历史坏行不泄漏 raw payload，返回该 event `state='malformed', error_code='trace_payload_invalid'`，其余时间线仍可读。evidence 缺失返回显式 `null/missing`，不回退 trunk HEAD。

commit 跳转 DTO 包含 `{repo,trunk,sha,repository_url}`；证据跳转包含 `{path,sha256,commit_sha}`。前端仅用这些字段构造 GitHub commit/blob 或内部 evidence 链接。

#### `GET /api/cr/spec-search?q=&owner=&limit=&cursor=`

```json
{"v":1,"specs":[{"spec_id":"ai-first-platform","latest_cr_id":"CR-2026-049","owners":["Ray"],"updated_at":"RFC3339"}],"next_cursor":null}
```

- `owner` 对 `jsonb_each(cr.owners).value->>'id'` 做大小写不敏感**精确**匹配；owner 是 crctl free-text identity，不宣称等同 Multica user UUID。
- `q` 对 spec_id 与 owner id 做转义后的 ILIKE；结果由 workspace-scoped trace events 与 `cr` 按 `(workspace_id,cr_id)` join。
- 全局 `packages/views/search/search-command.tsx` 与 issue/project 请求并行调用 `searchSpecs`，增加“Specs”分组；选择后进入 `/{slug}/governance/specs/{specId}`。spec 详情页与搜索复用同一 trace API。

### 3.6 drift API（v1）

#### `GET /api/drift/overview`

```json
{
  "v":1,
  "scan_health":"ok",
  "last_plan_status":"SUCCESS",
  "last_success_at":"RFC3339",
  "repository_ids":["ai-first-platform-docs","multica","tools"],
  "bypass_count":1,
  "wip_on_trunk_count":2,
  "resolve_latency_ms":{"sample_count":3,"p50":1000,"p90":5000}
}
```

`scan_health`：无平台 repo 配置=`not_configured`；有配置无成功=`uninitialized`；最新 plan FAILED=`failed`；最新成功超过 2h、`config_rev` 不等于当前或 cursor 未覆盖全部 repo=`stale`；否则 `ok`。只有 `ok && unresolved finding=0` 显示“无漂移”。计数含 `open|acknowledged`；解决时延只取 `resolved` 且 `resolved_at` 非空的 `resolved_at-found_at`，空样本 p50/p90=`null`。

#### `GET /api/drift/findings?status=&kind=&repository_id=&limit=&cursor=`

limit 1..100，默认 50；排序 `(status_rank ASC, found_at DESC, id DESC)`，rank=`open 0, acknowledged 1, resolved 2, wontfix 3`；cursor 是 base64url JSON `{rank,found_at,id}` 并经 schema/长度校验。响应：

```json
{"v":1,"findings":[{"id":"uuid","repository_id":"tools","spec_id":null,"cr_id":null,"kind":"bypass-commit","severity":"warn","summary":"...","evidence":{},"status":"open","found_at":"RFC3339","resolved_at":null}],"next_cursor":null}
```

#### `PATCH /api/drift/findings/{id}`

request `{ "from_status":"open", "to_status":"acknowledged" }`。允许：

- open → acknowledged | resolved | wontfix
- acknowledged → resolved | wontfix
- resolved/wontfix 为终态；同状态重放 200 幂等；其他 409 `invalid_transition`

单 SQL CAS：`WHERE id=$id AND workspace_id=$ws AND status=$from`；零行时重读区分 404/409。进入 resolved 写 `resolved_at=now()`；wontfix 保持 NULL。所有 workspace member 可读/流转（对应 QA user story）；跨 workspace id 恒 404。

### 3.7 统一错误与前端兼容

错误 envelope：`{"error":"code","message":"safe text","request_id":"uuid"}`。400=`invalid_query|invalid_cursor|invalid_payload`，401/403=认证/成员失败，404=`not_found`，409=`invalid_transition|state_conflict`，500=`internal_error`。

`packages/core` 为 Trace/SpecSearch/Drift DTO 建 Zod schema；network client 全部 `parseWithFallback`。前端 enum 额外接受 `unknown` fallback，未知 `scan_health/kind/status/severity` 不 crash；malformed response 返回空安全 envelope并上报 endpoint tag。web/desktop 共享 `packages/views` 页面，不复制业务状态。

## 4. 查询、健康与幂等流程

### 4.1 finding 幂等

E5 不先查再插：

```sql
INSERT INTO drift_finding (...)
VALUES (...)
ON CONFLICT DO NOTHING;
```

DB CHECK 保证 E5 commit_sha 非空，使 expression unique index 不会被 NULL 绕过。同 workspace/repository/kind/commit 24h 重扫仍一行；不同 workspace/repository 分开。

### 4.2 health 查询事实源

只读 `sys_cron_executions`：先取最新 plan（任何状态），再取最新 SUCCESS result。最新 FAILED 优先显示 failed；旧 success 不能掩盖新失败。成功 result 的 `config_rev/repository_ids/scan_cursors` 一起验证，声明增仓后旧 result 自动 stale。

### 4.3 owner/spec 与 timeline 去重

trace event 是完整累计 snapshot；读侧取最新有效 snapshot 的全部 milestones，再用事件元数据赋时并按 `(cr,milestone)` 去重，历史 baseline 不因缺独立 trace event 而丢失。unique key 防同 commit 重复。owner/spec 查询通过同 workspace 的 `cr` 连接，不从 milestone 文本猜 owner。表达式索引先定位 spec，再按 event id/occurred_at 排序。

## 5. 技术选型与替代方案

| 决策 | 选择 | 原因 / 否决替代 |
|---|---|---|
| canonical trace object | generator + manifest v2 | 保持 PRD payload，不让 CLI/读 API重解释；否决 raw YAML transport |
| YAML | 加固现有 zero-dep subset + 当前累积 fixture | tools 继续零第三方依赖；任何未知结构硬失败 |
| trace retry | journal intent + writeback complete replay + archive gate | collector 看不到未落盘 pending，单靠人工重跑不足 |
| trace ingest | 专用事务 insert-or-load/processed | ledger-only 无状态投影，最小范围消除 INSERT 后故障缝隙 |
| workspace migration | 维护窗口，new index before old drop | 不要求零停机；daemon outbox天然缓存；避免双版本 conflict target 不兼容 |
| repo access | workspace.repos + GitHub installation + ghsnapshot | 复用现有 workspace access；否决全局 PAT/reconcile 单 remote、否决 server bare clone |
| cursor | SUCCESS result.scan_cursors | 复用 scheduler 审计/lease；否决平行 scan_state 表 |
| scan upper bound | 固定 HEAD SHA B | trunk 扫描中前进不会改变本轮集合 |
| API pagination | keyset | finding 流持续写入时 offset 会漂移 |

## 6. FR → 实现映射

| FR | 技术落点 |
|---|---|
| FR-1 | tools trace generator semantic object + manifest v2 + emit callback |
| FR-2 | multica `crsync.go` trace schema/transaction/processed；daemon schema fixture |
| FR-3 | journal trace intent、complete replay、archive pre-gate、deterministic file |
| FR-4 | migrations 390–397；crsync/runner/maturity/approval 全 workspace seam |
| FR-5 | migration 392 + governance trace query；无 spec_trace |
| FR-6 | 当前 CR milestone 投影 + spec detail route |
| FR-7 | evidence/merge DTO，缺失显式显示，不猜 HEAD |
| FR-8 | spec-search + global search Specs 分组 + free-text owner 语义 |
| FR-9 | JobSpec + workspace scope/binding resolver |
| FR-10 | case-sensitive prefix classifier；wip 优先；完整 evidence |
| FR-11 | dir-graph 真实 remote/prefixes + generator/config_gen.go/--check |
| FR-12 | migration 385–387 + evidence CHECK |
| FR-13 | migration 388 + ON CONFLICT DO NOTHING |
| FR-14 | 固定 B、分页至 A、SUCCESS result cursor |
| FR-15 | overview health + maturity drift card |
| FR-16 | finding keyset list + PATCH CAS 状态流 |

FR 覆盖率：**16/16**。

## 7. 安全、性能与可测试性

### 7.1 安全/性能不变量

- 所有 event/finding/query/unique/CAS 都以 auth workspace 为第一条件；跨 workspace finding id 返回 404。
- `cr_sync_event` payload 最大 2 MiB；trace 索引按 workspace/spec/order 覆盖；finding keyset 有 389 索引。
- GitHub token 由 `ghsnapshot.Client` 内存缓存，日志/result/error 不含 token；扫描只读 SHA + subject。
- 每页 heartbeat，10m timeout、10k commit fail-safe；失败不推进 cursor，不伪装“零 finding”。
- Git 仍为 CR 权威；trace ledger-only；扫描只读远端。
- multica 新源码注释英文；generated Go 不手改；改 multica 必登记当时 `CUSTOM.md`。

### 7.2 AC 分层测试矩阵

| AC | 测试层与关键断言 |
|---|---|
| AC-1 | tools generator fixture：191KB full semantic JSON；跨语言 golden 由 Go `yaml.v3` 解析同一 YAML 后与 Node event payload 深比较；multica governance DB：trace accepted/processed、status 不变 |
| AC-2 | tools fault injection：outbox mkdir/write fail、journal pending、complete replay、archive gate fail/recover、重复文件/ledger 一行 |
| AC-3 | migration PG test：唯一回填成功、孤儿/多 workspace 同名回填非零；两 workspace 同名 CR ledger 隔离 |
| AC-4 | schema grep/migration test：无 spec_trace；EXPLAIN trace expression index |
| AC-5 | handler/service：首个完整 snapshot 导入历史 milestones，后续两个同 spec trace 以 `(cr,milestone)` 去重并按事件赋时；稳定时序、跨 workspace 不泄漏 |
| AC-6 | view：merge/test/review/approval link；缺 evidence 显式 missing、不取 latest trunk |
| AC-7 | spec-search handler + search-command：owner exact、spec query、跨 workspace；owner free-text 不误当 user UUID |
| AC-8 | scheduler fake DB/GitHub：per-workspace hourly、missing repo FAILED、首次三仓 baseline 零 finding |
| AC-9 | classifier table test：wip 优先、合法 prefix、bypass；evidence DB CHECK |
| AC-10 | generator fixture：三仓非空、最近 200 subject coverage、source SHA、dirty source/--check drift 非零 |
| AC-11 | PG migration introspection：字段/check/default、NULL spec/cr、无 FK、PK/dedup concurrent migration + cleanup hook |
| AC-12 | fake GitHub：100+ 多页 A→B、HEAD 中途前进、cursor missing、page 429/500、heartbeat、中断重试不漏 |
| AC-13 | PG integration：24 次重复一行；workspace/repo 不同各一行；静态检查无 select-before-insert |
| AC-14 | health pure/DB tests：not_configured/uninitialized/failed/stale/config drift/ok+zero；counts/latency 空样本 |
| AC-15 | handler CAS matrix：合法流转、同状态幂等、并发 409、resolved_at、wontfix NULL、跨 workspace 404；view 下钻同步 |

横切测试：

- `crsync` fault point 在 INSERT 后/processed 前中断，重投必须最终一行且 processed；payload 同 key 不同 digest 必须 reject。
- `runner.go`、`maturity.sql`、`approval.go` contract grep/SQL tests 禁止 `cr_sync_event` join 缺 workspace。
- `packages/core` 每个新 endpoint 都有 valid、malformed response、unknown enum fallback；views 覆盖 web/desktop 共用组件。
- migrations 386/388/389/391/392/393/396 通过 invalid concurrent index retry registry test。

### 7.3 残余风险

- 前缀可伪造，仍只是可见性信号；通路层对账按 PRD 延后。
- 单次 >10k 新提交会 fail-safe，不自动跳过；运维需人工确认后重建 baseline。
- 当前 trace baseline 会继续增长；达到 2 MiB 前需另立压缩/归档 CR，本 CR 不引入第二投影。

## 8. Prompt 采纳影响

条件性检查结论：本 CR 不新增/修改 `crctl.mjs` dispatch 子命令，也不改 `controlled-shell/rules.json#protectedPaths.deny`，因此不存在“新增命令未被 Skill 采用”的 blocker。

但 TD-B2 要求既有流程识别新增生命周期结果，作为普通行为契约同步：

| Skill / Pipeline | 修改 |
|---|---|
| `writeback-traceability/SKILL.md` 与 feature-writeback 对应 prompt | 输出 `EMIT_FAILED(trace)` 为 pending，不宣称 trace 已交付；允许 archive gate 做确定性补发 |
| `cr-archive/SKILL.md` 与对应 prompt | `ARCHIVE_TRACE_PENDING` 时仅重跑同一 archive；禁止跳门/手工清 journal |

以上只采纳既有 `writeback-apply`/`archive` 深原语的新结果，不新增 CLI 命令面。
