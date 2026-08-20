---
id: CR-2026-048-sdd
type: SDD
cr-ref: CR-2026-048
title: P3 组织智能 · 内部 Skill Market 技术设计
status: draft
created: 2026-08-20T13:43:02+08:00
updated: 2026-08-20T14:23:05+08:00
---

# SDD — CR-2026-048 内部 Skill Market 技术设计

> 依据：`change-requests/CR-2026-048/prd.md`（23 FR / 16 AC）、multica `ARCHITECTURE.md`（已存在，直接引用其第 4/5 节依赖方向与硬不变式）。
> 设计取向（用户明确指令）：**复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码**。每处选型按此阶梯决策，新增代码只出现在"没有现成件可用"的接缝上。

## 1. 架构概览

改动全部落在 multica 仓，分六个接缝，每个接缝都钉在既有结构上：

```text
[认领路径] handler/daemon.go buildClaimedTaskResponse（useSkillRefs 分支）
   └─ 已算出的 skillRefs ──> 循环 INSERT skill_usage_event（best-effort，不阻断认领）

[发布路径] handler/skill.go UpdateSkill（唯一写入口，不加新 route）
   └─ visibility private→org 时调 internal/skill.PublishGate（纯函数）
        ├─ ParseSkillMetadata（扩展既有 frontmatter 解析）
        ├─ redact.Findings（扩展既有 patterns，零新正则表）
        └─ 失败 → 422 结构化 findings；成功 → 同一事务更新 skill 行

[申诉] 2 个新端点 POST /api/skills/{id}/appeals[/decide]
   └─ activity_log 记账（复用既有表 + 封闭 action 白名单模式），appeal_id=内容哈希绑定

[Market 读] 1 个新端点 GET /api/skills/market
   └─ 新 sqlc 聚合查询（join agent_task_queue status=completed，按 skill_ref 去重计数）

[数据面] 迁移 380–383（三列 + 一表 + 两索引，各文件一条 CONCURRENTLY 索引）

[前端] packages/views/skills 既有 SkillsPage / SkillDetailPage 扩展（不新增页面/路由）
```

依赖方向遵守 ARCHITECTURE.md 第 4 节：handler → service/queries；`internal/skill` 纯函数包被 handler 调用；`packages/views` 只消费 `packages/core` 的查询方法。不新建事务/队列/outbox 抽象（PRD §7 已排除）。

## 2. 数据模型

### 2.1 迁移（编号从 380 起，CR-2026-047 已占 375–379）

| 迁移 | 内容 | down |
|---|---|---|
| `380_skill_visibility` | `ALTER TABLE skill ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','org')), ADD COLUMN version TEXT NOT NULL DEFAULT '0.1.0', ADD COLUMN owner_actor TEXT` | 三列 DROP |
| `381_skill_usage_event` | 建表（见下，含 `workspace_id` 租户键） | DROP TABLE |
| `382_skill_usage_event_task_id` | `CREATE INDEX CONCURRENTLY skill_usage_event_task_id_idx ON skill_usage_event(task_id)` | DROP INDEX CONCURRENTLY |
| `383_skill_usage_event_scope` | `CREATE INDEX CONCURRENTLY skill_usage_event_scope_idx ON skill_usage_event(workspace_id, skill_ref, used_at)` | DROP INDEX CONCURRENTLY |
| `384_skill_appeal_activity_index` | `CREATE INDEX CONCURRENTLY skill_appeal_activity_idx ON activity_log ((details->>'appeal_id')) WHERE action IN ('skill_appeal_submitted','skill_appeal_approved','skill_appeal_rejected')` | DROP INDEX CONCURRENTLY |

- 382/383/384 各自独立文件、各一条索引语句（仓规约）；并**同步注册** `cmd/migrate/main.go` 的 `concurrentIndexCleanups` 与 `concurrentDownIndexCleanups` 两个 map（CR-2026-047 对 376/378/379 的同款处理，`TestEveryConcurrentUpBuildHasCleanup` 会强制校验）。
- **无外键**：`skill_usage_event.task_id`/`skill_ref` 均无 FK（PRD FR-2，仓硬规则）；`workspace_id` 同样不加 FK。
- **384 的先例**：迁移 089 已在 `activity_log` 上建过 `((details->>'task_id'))` 表达式部分索引，本条照抄同一形制，不发明新存储。

```sql
CREATE TABLE skill_usage_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,     -- 租户键（硬不变式 1）；agent_task_queue 无此列，因此必须自带
    skill_ref TEXT NOT NULL,        -- workspace skill 的 uuid 文本，或 'builtin:<name>'
    task_id UUID,                   -- 无 FK：append-only 审计行，指向已删 Skill 的历史行应保留
    project_id UUID,
    used_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`workspace_id` 的数据来源是现成的：`buildClaimedTaskResponse` 签名已带 `runtimeWorkspaceID string` 形参，直接落列，**零额外查询**。不靠 `agent_task_queue` 反查——该表只有 `agent_id`/`issue_id`/`project_id`（`project_id` 由迁移 368 加入），没有 workspace 列。

### 2.2 申诉账本 = activity_log（不建新表）

`activity_log`（001_init）已有全部所需列（workspace_id/actor_type/actor_id/action/details JSONB）。申诉三种行用三个封闭 action 值：

- `skill_appeal_submitted`（作者提交）——details: `{appeal_id, skill_id, content_hash, file, line, pattern_id}`
- `skill_appeal_approved` / `skill_appeal_rejected`（Owner 逐条决定）——details: `{appeal_id, decided_by, ...}`

`appeal_id = sha256(skill_ref | content_hash | file | line | pattern_id)`（十六进制）。内容哈希复用 `skillbundle.BuildManifest(skill).Hash`（`server/pkg/skillbundle/hash.go:43`，标准库 sha256，上游已用于包变更判定）——不新写哈希。**内容变更自动使旧放行失效**：发布门禁每次对当前内容重算 hash，旧 appeal_id 必然不再命中，无需任何失效代码。

幂等 = 提交前 `SELECT` 已有同 `appeal_id` 行则 no-op；极端并发下的重复行由 activity_log 的 append-only 审计语义容忍（与 `governance.ingestAudit` 注释明示的 crash-window 重复同款先例）。

**查找路径必须走索引**：activity_log 现有索引全部以 `issue_id` 打头（068 的 `idx_activity_log_issue_keyset`、089 的 `idx_activity_log_squad_no_action_task`），而申诉行 `issue_id` 为 NULL——不建专用索引则退化为热表全表扫描。因此迁移 384（§2.1）是本方案的必需项，不是优化项；验收同样用 `EXPLAIN (FORMAT JSON)` 固定 fixture 断言命中。

## 3. 接口契约

### 3.1 UpdateSkillRequest 扩展（发布 = 复用既有更新端点）

```go
type UpdateSkillRequest struct {
    // ...既有字段不动
    Visibility *string `json:"visibility"` // 仅接受 "private" | "org"
    OwnerActor *string `json:"owner_actor"`
    Version    *string `json:"version"`    // 纯展示，不参与内容身份
}
```

`UpdateSkill` sqlc 查询对应加三列 `COALESCE(sqlc.narg(...))`。**门禁触发条件（两条，缺一则有绕过口）**：

1. `skill.Visibility='private'` 且请求置 `org`——发布时首次把关；
2. `skill.Visibility='org'` 且本次请求改变 `content` 或 `files`——**发布后的内容更新重扫**，否则密钥可以在发布之后夹带进组织可见资产（US-2/NFR-4 隐私红线）。

其余情况（org→private、仅改 version/描述、私有 Skill 编辑）零额外行为——私有创建/编辑路径完全不动。**同一条规则适用于 runtime-local 覆盖导入路径**（`canOverwriteSkillByLocalImport`）：该路径也会改写 org Skill 的 content/files，必须调同一个 `PublishGate`（复用同一函数，不新增机制）。

### 3.2 发布门禁失败响应（422）

```json
{
  "code": "skill_publish_blocked",
  "reasons": ["frontmatter_name_missing", "owner_actor_missing", ...],
  "findings": [
    {"file": "SKILL.md", "line": 12, "pattern_id": "github_token",
     "excerpt": "api_key=[REDACTED GITHUB TOKEN]  ← 已经 Text() 脱敏，绝不含明文"}
  ],
  "warnings": ["permission_declaration_touches_protected_paths"]
}
```

### 3.3 新端点（skill 路由组内，鉴权沿用既有 requireWorkspaceRole）

| 端点 | 权限 | 行为 |
|---|---|---|
| `POST /api/skills/{id}/appeals` | canManageSkill（作者或 admin） | body `{file, line, pattern_id}`；计算 appeal_id，幂等写 `skill_appeal_submitted` |
| `POST /api/skills/{id}/appeals/decide` | workspace owner/admin | body `{appeal_id, approve: bool}`；写 `skill_appeal_approved/rejected`；非 owner 403 |
| `GET /api/skills/market` | 工作区成员 | 见下（**只返回调用方当前 workspace 内 `visibility='org'` 的 skill + builtin**） |

Market 响应（一次请求给全排行）：

```ts
type SkillMarketResponse = {
  workspace: { id, name, description, version, owner_actor, visibility, usage_count }[]
  builtin:   { name, description, usage_count }[]   // 来自 TaskService.BuiltinSkills()
}
```

workspace 部分由新 sqlc 聚合查询产生（按认证上下文的 workspace 过滤 + `visibility='org'`）；builtin 部分用 `loadBuiltinSkills()`（既有）列出名称/描述，usage 同样只统计该 workspace 内 `skill_ref='builtin:<name>'` 的行。请求体里的任何 workspace 标识一律不取信（硬不变式 1）。

### 3.4 frontmatter 解析扩展

`internal/skill/frontmatter.go` 现有 `ParseSkillFrontmatter` 已把整个 frontmatter 解进泛型 map（内部 `coerceFrontmatterValue`）。**新增**：

```go
type SkillMetadata struct {
    Name, Description string
    Fields map[string]string // 全部标量字段（元数据卡四字段、source、requirements 等）
}
func ParseSkillMetadata(content string) SkillMetadata
```

`ParseSkillFrontmatter` 保留为薄包装（现有调用方零改动）。四字段（`applicable-scenarios`/`context-dependencies`/`permission-declaration`/`failure-handling`）、`source: session-export` 标记、运行时要求标签全部从 `Fields` 读取——**零新列、零新解析器**。

## 4. 关键算法与流程

### 4.1 认领遥测（buildClaimedTaskResponse，handler/daemon.go:2067）

```text
useSkillRefs 分支内，resp.Agent.SkillRefs = skillRefs 之后：
for _, ref := range skillRefs:
    INSERT skill_usage_event(workspace_id, skill_ref, task_id, project_id)
    ← workspace_id = runtimeWorkspaceID（函数形参，现成）
    ← skill_ref = ref.ID（workspace 为 uuid 文本；builtin 为 "builtin:<name>"，BuildAgentSkillBundles 已合成，零转换）
任何写入错误：slog.Error，不触碰 claim 结果（遥测是观测面，不是门禁）
```

两个调用方都是认领端点（`ClaimTasksByRuntime` 批量 / `ClaimTaskByRuntime` 单条），不存在非认领路径误写。插入点位于 `claimResponseAgentIdentityMatches` 校验**之前**，因此构建后被跳过/取消的任务也会留下遥测行——这类任务永远到不了 `completed`，§4.3 的过滤自然把它们排除，**不要为此加补偿逻辑**。

每 claim 一轮写一次（重试=再 claim=再加行），`used_at` 语义"派发时物化"。查询侧去重（§4.3）保证计数正确。循环单行 INSERT，任务典型 <10 个 Skill，不加批处理框架。

### 4.2 发布门禁（internal/skill/publish_gate.go，新纯函数）

```text
PublishGate(skill 行, 请求增量, 全部 skill_file 内容) → (findings, reasons, warnings)
触发：private→org（首次发布），或 visibility 已是 org 且本次改 content/files（发布后重扫）
1. 有效 content = req.Content ?? skill.Content
2. meta = ParseSkillMetadata(content)
   ├─ meta.Name / meta.Description 空 → reason frontmatter_name_missing / frontmatter_description_missing
   ├─ 四字段任一空 → reason metadata_<field>_missing
   └─ meta.Fields["permission-declaration"] ∩ protectedPaths 非空 → warnings（不阻断）
3. owner = req.OwnerActor ?? skill.OwnerActor；空 → reason owner_actor_missing
4. findings = redact.Findings(content) ∪ ⋃ redact.Findings(each skill_file.content)
   （超集扫描：现有文件全扫 + 请求替换文件全扫，零簿记）
5. findings 非空 → 阻断，返回每处 {file, line, pattern_id, 脱敏 excerpt}
6. 任一 finding 存在 appeal_id 的 skill_appeal_approved 行 → 该条放行（按条，不是整包）
```

`protectedPaths` 以门禁包内常量维护（`change-requests/`、`specs/`、`delivery/`、`docs/`、`dir-graph.yaml`、`AGENTS.md`），注释标明权威源是 tools 仓 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`，以门禁测试与 tools 清单对拍防漂移。服务端进程内没有 tools checkout，不发明跨包读取通道。

### 4.3 使用量聚合（新 sqlc 查询）

```sql
-- MarketSkillUsage :many
SELECT e.skill_ref, COUNT(DISTINCT e.task_id) AS usage_count
FROM skill_usage_event e
JOIN agent_task_queue t ON t.id = e.task_id
WHERE e.workspace_id = $1 AND t.status = 'completed'
GROUP BY e.skill_ref;
```

重复 claim 行按 `task_id` 去重；最终失败任务整体不进计数（join + status 过滤）；跨工作区不混算（`workspace_id` 过滤，硬不变式 1）。走 `(workspace_id, skill_ref, used_at)` 索引；`EXPLAIN (FORMAT JSON)` 固定 fixture 断言（AC-15）。

### 4.4 redact.Findings（server/pkg/redact，扩展而非平行）

- 每个 `secretPattern` 加 `name` 字段（16 条既有 + 新增第 17 条 `personal_path`：`/Users/<x>`、`C:\Users\<x>`、`/home/<x>`）——**同一份 `patterns` 变量**，`Text()` 与新函数共用。
- `Findings(s string) []Finding`：按行切分，逐行跑 patterns 的 `FindStringIndex` 取行号；`excerpt = Text(line)` 截断到 ~120 字符——直接复用 `Text()`，响应天然无明文（NFR-4）。
- 单一定义防平行表：patterns 保持未导出 + 测试断言 17 条且 name 唯一非空（AC-10 的可行形态；"无第二份正则表"同时靠 code review 以 diff 为证）。

## 5. 技术选型与替代方案（按阶梯逐条记录）

| 决策 | 选的 | 否决的替代 | 阶梯位置 |
|---|---|---|---|
| 遥测写入 | claim 路径循环单行 INSERT（sqlc 既有生成模式） | 批处理/COPY/新 outbox 表 | 已有依赖（sqlc）> 最小新增 |
| 遥测表 | 1 张 append-only 表 + 2 索引 | 物化视图/分区表 | YAGNI，数据量按任务×Skill 同阶 |
| 内容哈希 | 复用 `BuildManifest().Hash` | 新写哈希函数 | 复用现有能力 |
| 敏感扫描 | 扩展 `redact` 同份 patterns | 新正则表/引入检测库 | 复用现有能力（新依赖=阶梯最底） |
| 申诉账本 | `activity_log` + 封闭 action + 迁移 384 部分表达式索引（照抄 089） | 新 appeal 表 | 复用现有能力 |
| 遥测租户键 | 表内 `workspace_id` 列（claim 形参现成） | join agent→workspace 反查 | 一列换一次 join，且 agent_task_queue 无 workspace 列 |
| 发布后重扫 | 同一 `PublishGate` 多一个触发条件 | 定时全量扫描/独立扫描服务 | 一个条件判断，零新机制 |
| 发布入口 | 扩展 `UpdateSkill` | 新 /publish 端点 | 复用现有能力 |
| 内容变化使放行失效 | 哈希绑定自然失效 | 失效扫描任务 | 零代码（不做） |
| frontmatter | 扩展既有解析器（泛型 map 已就位） | 新解析库 | 复用现有能力 |
| 排名去重 | 查询侧 `COUNT(DISTINCT task_id)` | 采集侧幂等键/upsert | 一个 WHERE/GROUP BY 换掉跨进程复杂化 |
| 前端 | 扩展既有 SkillsPage/SkillDetailPage | 新 Market 页面/路由 | 复用现有能力 |
| protectedPaths | 门禁包内常量 + 对拍测试 | 读 tools checkout | 服务端无该 checkout，常量是唯一诚实选项 |

**明确不引入**：无新依赖（全部标准库 + 仓内既有件）；无新事务框架；无新表（除 PRD 已批准的 1 张）；无 daemon 协议字段（`TaskCompleteRequest` 零改动，AC-4 以 diff 为证）。

## 6. FR 到技术实现映射（23/23）

| FR | 实现条目 |
|---|---|
| FR-1 | 迁移 380（三列 + 两值 CHECK，无 builtin 枚举） |
| FR-2 | 迁移 381（skill_usage_event，含 workspace_id 租户键，无 FK） |
| FR-3 | claim 写入 ref.ID 原样落库（builtin 合成 id 已有，零转换） |
| FR-4 | version 仅 UpdateSkill 读写；无任何比较逻辑（diff 评审锚点） |
| FR-5 | §4.1 buildClaimedTaskResponse 循环 INSERT，失败仅日志 |
| FR-6 | `TaskCompleteRequest`/`sanitizeTaskCompleteRequest` 不进 diff（AC-4） |
| FR-7 | 表注释（迁移 381 内 `COMMENT ON`）+ §4.3 查询语义 |
| FR-8 | §4.2 门禁整体 fail-closed，可见性翻转在同一事务 |
| FR-9 | meta.Name/Description 非空校验 |
| FR-10 | owner 空 → 拒；单值即可（不要求全局唯一） |
| FR-11 | 四字段逐一校验，错误带字段名 |
| FR-12 | 结构校验 = ParseSkillMetadata 成功 + 必填字段（tools validate-doc 是 CR 文档校验器，不适用于 SKILL.md；不做跨包调用） |
| FR-13 | protectedPaths 常量比对 → warnings（不阻断、不改写声明） |
| FR-14 | 无 is_builtin 特判（builtin 无 skill 行，天然不可达） |
| FR-15 | §4.4 Findings + name 字段 + 单一定义测试 |
| FR-16 | 第 17 条 personal_path 模式 |
| FR-17 | 门禁扫描 content + 全部 skill_file，返回 file/line/pattern_id；**org Skill 的后续内容更新（含 runtime-local 覆盖导入）同样重扫**（§3.1 触发条件 2） |
| FR-18 | §2.2 申诉端点 + appeal_id 哈希 + activity_log 三 action |
| FR-19 | §3.3 market 端点：workspace（当前工作区 + org 可见，含 version）+ builtin 排行 |
| FR-20 | SkillDetailPage 渲染四字段（org workspace Skill） |
| FR-21 | Fields 中 requirements 类字段确定性提取，缺失则无标签不报错 |
| FR-22 | 发布确认框文案（前端） |
| FR-23 | `source` 字段经 ParseSkillMetadata 读取 → 列表筛选，零新列 |

## 7. 安全与性能考量

- **迁移合规**：380 起、无 FK、每文件一条 CONCURRENTLY 索引、cleanup map 双注册（NFR-1/2，AC-1）。
- **工作区隔离**：遥测表自带 `workspace_id`，market 读路径按认证上下文过滤，请求体 workspace 标识不取信（硬不变式 1，与 CR-2026-047 的 `maturity_snapshot` 租户键同口径）。
- **隐私红线**：findings 响应一律经 `Text()` 脱敏（NFR-4）；扫描是默认拦截，放行是逐条留痕例外（AC-11）；**发布不是一锤子买断**——org Skill 的内容每次变更都重跑同一道门禁。
- **权限**：申诉决定仅 owner/admin（403 测试）；发布沿用 canManageSkill；工作区隔离沿用 requireWorkspaceRole（ARCHITECTURE.md 硬不变式 1）。
- **性能**：claim 路径每 Skill 一行 INSERT（同阶 <10 行/任务，NFR-3）；排行聚合走 `(workspace_id, skill_ref, used_at)` 索引、完成过滤走 `task_id` 索引、申诉查找走 384 部分索引（三条均有 EXPLAIN 断言，AC-15）。
- **任务单路径**：遥测挂在既有 claim 装配点，不新增任何任务执行通道（硬不变式 3）。
- **回滚**：380–384 逆序 down 可全回滚；`skill_usage_event` 是纯观测数据，回滚丢弃无业务影响。
- **台账**：全部改动按 NFR-6/AC-17 登记 `../multica/CUSTOM.md`（新增一行：迁移 380–384 + 门禁/遥测/申诉挂钩点 + 验证命令），`make sqlc` 生成物提交生成器真实输出，不手补。
- **残余风险**（实施时留意）：① claim 循环 INSERT 与 claim 事务的关系——若 claim 本体有事务，遥测写入放事务内随它提交，不回滚单独补偿；② sqlc 重生成会带出新列相关 generated diff，按 CUSTOM.md 规则提交生成器真实输出；③ builtin 计数依赖 `buildClaimedTaskResponse` 的 builtin ref 合成规则，需在 skill_bundle 测试中加一条断言锁住（与 `TestBuildAgentSkillBundlesAssignsBuiltinID` 同款）；④ 迁移 384 建在热表 activity_log 上，必须 CONCURRENTLY 且单语句单文件，与 089 同款。

## 8. Prompt 采纳影响

本节按 CR-2026-021 FR-25 条件触发：本 CR **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（§4.2 的门禁包常量是 multica 服务端内部数据，不改变 crctl 命令面或 guard deny 面）。故本节省略。
