---
id: CR-2026-003-sdd
type: SDD
cr-ref: CR-2026-003
title: P1 治理核心修补 — embedded 事件幂等键碰撞 + 归档 CR 失去自愈能力 技术设计
status: draft
created: "2026-07-31T20:45:00+08:00"
updated: "2026-07-31T20:45:00+08:00"
version: v0.1.0
refs:
  upstream: [CR-2026-003-prd]
  downstream: []
components: [crctl-embedded-disambiguator, governance-history-snapshot]
---

# SDD — P1 治理核心修补 技术设计

> 对应 `change-requests/CR-2026-003/prd.md` 的 FR-1/FR-2。本文档在 PRD 诊断的两个症状之上，**用 CR-2026-001/CR-2026-002 两条真实卡住的生产数据逐步追溯出精确的三段式根因链**——PRD 阶段的诊断是方向正确但机制粗粒度的（"幂等键碰撞"+"归档 CR 无法自愈"），SDD 阶段核对代码后发现实际是三个独立缺陷首尾相连才导致了观测到的症状。本节先把根因链讲清楚，再给出对应修复。

## 0. 根因链（先于架构概览，因为修复设计直接建立在这条链上）

以 CR-2026-002 归档过程的真实序列为例（可在生产库 `cr_sync_event` 表逐行核对）：

1. **`crctl advance --to writing-back --embedded`**（11:37:24）→ 发出 `event_kind=status, from=merging, to=writing-back, commit_sha=''`（embedded 模式下 `commit_sha` 恒为空串，见 `crctl.mjs` 的 `commit_sha: committed ? gitHeadSha(ws) : ''`）→ 落 `cr_sync_event` 唯一键 `(CR-2026-002, '', status)` → 首次出现，正常处理 → `cr.status` 正确投影为 `writing-back`。
2. **`crctl advance --to archived --embedded`**（11:57:13 前）→ 同样发出 `event_kind=status, from=writing-back, to=archived, commit_sha=''` → 试图落同一唯一键 `(CR-2026-002, '', status)` —— **与步骤 1 完全相同**（`event_kind` 都是 `"status"`，`commit_sha` 都是空串，`cr_id` 相同）→ `ON CONFLICT (cr_id, commit_sha, event_kind) DO NOTHING` 判定为"重复事件"，`RowsAffected()==0` → **`apply()` 从未被调用，`archived` 转移在主同步通道里被静默吞掉**（`internal/governance/crsync.go` `ingest()` 函数 L181-183）。**这是 FR-1 修复的缺陷（下称"缺陷 A"）。**
3. 归档收尾提交 `[cr] archive CR-2026-002 final-status=archived` 因文案匹配 daemon 的 commit-scan 兜底正则 `crCommitArchiveRe`（`internal/daemon/crevents.go`），被兜底通道**用真实 commit sha 合成为一条独立事件**：`event_kind=archive, commit_sha=6e8e72c3...`（与步骤 2 的键不同，不会被去重）→ 正常落库、正常被 `apply()` 处理。但 `parseCRCommitMessage()` 对 `archive` 类型只提取了 `cr_id`，**从未解析/填充 `FromStatus`/`ToStatus`**（`crevents.go` 对应分支只写 `base.EventKind, base.CRID = "archive", m[1]`）→ 该事件到达 `applyStatus()` 时 `ev.FromStatus == ""`，而当时 `cr.status` 已是 `"writing-back"`（步骤 2 丢失导致），`"writing-back" == ""` 为假 → 落入"乱序/非法转移"分支：只置 `needs_reconcile=TRUE`，**不改写 `status`**。这是一个真实存在但影响较小的次要缺陷（commit-scan 对 archive 类提交的 from/to 解析能力缺失）——**本 CR 不直接修它**，理由见 §5。
4. `needs_reconcile=TRUE` 之后本应由 `reconcile` 下一周期自愈——但 `ApplySnapshot`（`internal/governance/reconcile.go`）**只读 `_backlog.yml`**，而此时 CR-2026-002 已被 `cr-archive` 移出 `_backlog.yml` 进 `_history.yml`，reconcile 的快照里根本不存在这个 CR-ID，**永远不会被自愈**。**这是 FR-2 修复的缺陷（下称"缺陷 C"）。**

CR-2026-001 卡在同一症状（`writing-back`/`needs_reconcile=true`）但触发路径不同：它归档于 T05/T06（同步链路本体）上线之前，其历史投影是后来 commit-scan 全量回填的；它的归档提交文案（`[cr] CR-2026-001: archive — backlog -> history, ...`）**不匹配任何一条 commit-scan 正则**（`crCommitStatusRe` 要求精确的 `[cr] status {cr} {from} -> {to}` 格式），所以连"被兜底通道捕获但解析错误"的机会都没有——**从未有任何事件把它推向 archived**。两条 CR 的**根因不同，但都指向同一个结构性缺口**：git 侧已经是终态（`_history.yml` 记着 `final-status: archived`），但平台侧没有任何路径去读这个终态并收敛。**这正是缺陷 C 的普遍性——修 FR-2 后，无论 live-sync 通道因为什么原因（缺陷 A、缺陷 B、或压根没跑起来）没能正确投影，reconcile 都能从权威（`_history.yml`）兜底收敛，不需要逐一堵住每一条可能出错的 live-sync 支路。**

## 1. 架构概览

### 1.1 模块边界

本 CR 只改动两个既有组件的内部实现，不新增模块、不新增表：

| 组件 | 归属 | 改动性质 |
|---|---|---|
| `crctl-embedded-disambiguator` | tools `skills/shared/crctl/scripts/crctl.mjs` | embedded 状态事件的 `commit_sha` 占位符生成（修缺陷 A） |
| `governance-history-snapshot` | multica `server/internal/governance/{reconcile,reconcile_github}.go`、`server/internal/daemon/crevents.go` | reconcile 快照来源扩展为 `_backlog.yml` ∪ `_history.yml`（修缺陷 C） |

两处改动互相独立、可并行开发，合并时天然无冲突（前者只碰 tools 仓，后者只碰 multica 仓）。

### 1.2 关键流程（修复后）

```
crctl advance --embedded（第 N 次，同一 CR）
  → commit_sha = pendingCommitSha()  # 唯一占位符，不再是恒定的空串
  → emitOutboxEvent(event_kind=status, commit_sha=占位符, ...)
  → daemon 采集 → POST /api/daemon/cr-events
  → cr_sync_event 唯一键 (cr_id, 占位符, status) —— 每次都不同，不再互相碰撞
  → apply() 正常执行 → cr.status 正确投影

reconcile 周期（server 模式 / daemon 模式均适用）
  → 读取 _backlog.yml（在途 CR）
  → 读取 _history.yml（已归档/拒绝/撤回 CR 的 final-status）—— 新增
  → 合并为一份 {cr_id: status} 快照（backlog 优先，理论上不重叠）
  → ApplySnapshot(snapshot)  —— 函数本身不用改，只是喂给它的数据更完整了
  → 任何投影与快照不一致的行（不论是因为缺陷 A、缺陷 B，还是同步链路当时压根没运行）都被健康的权威值覆盖
```

## 2. 数据模型

**无新增表、无新增列。** `cr_sync_event.commit_sha` 列（`TEXT NOT NULL DEFAULT ''`）语义轻微扩展：对 embedded 事件不再是空串，而是形如 `pending:{unix-ms}:{pid}:{seq}` 的占位符字符串——**该列在业务逻辑中只被用作幂等键的一部分（从未被反查语义化），因此这个扩展不影响任何现有读取路径**（`apply()`/`applyStatus()`/`checkpoint` 分支均从内存中的 `OutboxEvent` 结构体读取 `CommitSHA`，不是从表里回查这一列）。

## 3. 接口契约

无新增 HTTP 端点。已有的 `POST /api/daemon/cr-events`（`event_kind=snapshot`）负载 schema 扩展一个字段：

```go
// server/internal/governance/reconcile.go
type snapshotPayload struct {
	HeadSHA string `json:"head_sha"`
	Backlog string `json:"backlog"`
	History string `json:"history"` // 新增：change-requests/_history.yml 原文（daemon 模式）
}
```

字段缺失（旧版 daemon 上报，未带 `history` 字段）时视为空字符串，`ParseHistory("")` 返回空 map，行为与修复前完全一致——**向后兼容，daemon 与 server 可独立升级**。

## 4. 关键算法与流程

### 4.1 FR-1：embedded 事件的 commit_sha 占位符（tools/crctl.mjs）

```js
// 新增：进程内单调计数器，仿 multica pkg/gitguard/spool.go 的 spoolSeq 模式，
// 保证同一毫秒内的多次 embedded 调用也不会产生相同占位符。
let embeddedSeq = 0;
function pendingCommitSha() {
  embeddedSeq += 1;
  return `pending:${Date.now()}:${process.pid}:${embeddedSeq}`;
}
```

调用点（`cmdAdvance` 中原 `commit_sha: committed ? gitHeadSha(ws) : ''` 一行）改为：

```js
commit_sha: committed ? gitHeadSha(ws) : pendingCommitSha(),
```

**为什么不用其他方案**：
- ❌ 改唯一键为 `(cr_id, event_kind, from_status, to_status)`（去掉 `commit_sha`）：会让"同一次转移因网络重试上报两次"从"正常去重"变成"被当作两次不同事件重复处理"——**这是把幂等性本身改坏**，NFR-1 明确禁止。
- ❌ embedded 事件完全不写入 `cr_sync_event`（只更新 `cr` 表）：会丢失 outbox 通道"先记账、再投影、可重放"的审计闭环，且需要绕开 `ingest()` 现有的锁与并发控制路径，改动面远大于收益。
- ✅ 占位符方案：改动仅两行（生成函数 + 调用点），不碰服务端、不碰数据库结构、不改变非 embedded 路径的任何行为。

### 4.2 FR-2：reconcile 快照来源扩展

新增 `ParseHistory`（`server/internal/governance/reconcile.go`，紧邻现有 `ParseBacklog`）：

```go
// ParseHistory extracts {cr_id: final-status} from a raw _history.yml. Same
// EOL/parse-failure discipline as ParseBacklog (AGENTS.md 工程纪律 1)：解析失败
// 必须硬失败，不得静默返回空 map。
func ParseHistory(raw []byte) (map[string]string, error) {
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")
	var doc struct {
		History []struct {
			ID           string `yaml:"id"`
			FinalStatus  string `yaml:"final-status"`
		} `yaml:"history"`
	}
	if err := yaml.Unmarshal([]byte(text), &doc); err != nil {
		return nil, fmt.Errorf("_history.yml parse: %w", err)
	}
	out := make(map[string]string, len(doc.History))
	for _, e := range doc.History {
		if e.ID != "" && e.FinalStatus != "" {
			out[e.ID] = e.FinalStatus
		}
	}
	return out, nil
}
```

合并逻辑（新增小函数 `mergeAuthority`，backlog 优先——两个来源理论上不重叠，`cr-archive` 是原子移动，backlog 优先只是防御性写法）：

```go
func mergeAuthority(backlog, history map[string]string) map[string]string {
	merged := make(map[string]string, len(backlog)+len(history))
	for id, st := range history {
		merged[id] = st
	}
	for id, st := range backlog { // backlog 覆盖 history：在途优先于历史
		merged[id] = st
	}
	return merged
}
```

**server 模式**（`reconcile_github.go` `FetchGitHubSnapshot`）：在已有的"按 HEAD sha 取 `_backlog.yml`"调用之后，同一 sha 再取一次 `_history.yml`（同一次 GitHub API 往返窗口内，无撕裂读风险，历史文件几乎不变但仍锁定同一 commit 保证一致性快照），解析并 `mergeAuthority`。

**daemon 模式**（`crevents.go` `buildSnapshotEvent`）：本地多读一次 `_history.yml` 文件（若不存在则视为空，不报错——新仓库可能还没有归档过任何 CR），塞进 `snapshotPayload.History` 字段。服务端 `ingestSnapshot`（`reconcile.go`）解析该字段并入合并。

**`ApplySnapshot` 本身不需要任何改动**——它已经是"传什么 status 就healed 到什么 status"的通用实现，`archived`/`rejected`/`withdrawn` 都在 `KnownStatuses` 枚举内（`transitions_gen.go` 已声明为终态），传入合并后的快照即可自然工作。这也是选择"扩展数据源而非改协调逻辑"这个方案的核心理由——**改动面最小，且完全复用已经过 T07 完整测试的 `ApplySnapshot`**。

## 5. 技术选型与替代方案

| 决策点 | 选择 | 替代方案与放弃理由 |
|---|---|---|
| 缺陷 A 的键碰撞 | 生成唯一占位符 | 改唯一键结构（放弃：破坏跨通道去重语义）；embedded 事件绕过账本（放弃：丢失审计闭环） |
| 缺陷 C 的历史 CR 自愈 | 扩展 reconcile 快照来源 | 归档时强制立即同步投影、不再依赖异步事件（放弃：`cr-archive` 是纯 git 操作，不应该反过来同步调用平台 API，且离线/平台未启动时归档仍要能进行）；给 `cr` 表加"是否终态"标记跳过对账（放弃：治标不治本，遇到缺陷 A/B 之外的第三种同步失败原因时仍然无法自愈） |
| 缺陷 B（commit-scan 对 archive 提交解析 from/to） | **本 CR 不修** | 见下方"范围排除"说明：缺陷 C 修复后，这条支路的失败不再影响最终收敛结果，专门为它加 from/to 解析的收益接近于零，且需要设计一个新的 commit message 契约（当前 `[cr] archive {cr_id}` 格式压根没有 from/to 位置可解析），改动面不成比例 |

## 6. FR → 技术实现映射

| FR | 组件 | 文件 | 函数/改动点 |
|---|---|---|---|
| FR-1 | crctl-embedded-disambiguator | tools `skills/shared/crctl/scripts/crctl.mjs` | 新增 `pendingCommitSha()`；`cmdAdvance` 中 status 事件的 `commit_sha` 生成表达式 |
| FR-2 | governance-history-snapshot | multica `server/internal/governance/reconcile.go` | 新增 `ParseHistory`、`mergeAuthority`；`snapshotPayload` 加 `History` 字段；`ingestSnapshot` 合并调用 |
| FR-2 | governance-history-snapshot | multica `server/internal/governance/reconcile_github.go` | `FetchGitHubSnapshot` 增加一次 `_history.yml` 拉取 + 合并 |
| FR-2 | governance-history-snapshot | multica `server/internal/daemon/crevents.go` | `buildSnapshotEvent` 增加本地 `_history.yml` 读取 |

## 7. 安全与性能考量

- **安全**：`pendingCommitSha()` 的输出（`pending:{ms}:{pid}:{seq}`）不含任何敏感信息，仅用作幂等键片段，不对外暴露、不进日志脱敏名单（本身就是可安全记录的调试字符串）。`_history.yml` 读取路径与既有 `_backlog.yml` 读取路径权限完全一致（同一只读 GitHub PAT / 同一本地文件系统读权限），不引入新的信任边界。
- **性能**：`_history.yml` 全量解析每对账周期一次——评审阶段已提出这个体量担忧（`review-annotations/requirement.yml` 建议 #2）。当前实际规模（本仓库 2 条历史记录，可预见的未来数量级是"每季度个位数到十位数新增"）下全量解析的开销可忽略。**明确记录为已知的未来优化点，不在本 CR 中解决**：若 `_history.yml` 增长到影响对账周期延迟的量级（数千条以上），后续 CR 可改为增量索引（例如按年月分片，或维护一份 `{cr_id: final-status}` 的旁路缓存文件），现在做属于过度设计。
- **不反向写 git**：与 T07 既有原则一致，reconcile 读取 `_history.yml` 纯只读，不会因为"历史记录里没某个字段"就去改写归档提交。

## 8. 测试设计（对应 AC）

| AC | 测试方式 |
|---|---|
| AC-1 | Go 集成测试（`crctl.mjs` 侧配 JS 单测）：连续两次 `crctl advance --embedded` 同一 CR，断言两次的 `commit_sha` 字段不同；服务端集成测试断言两条 `cr_sync_event` 行均 `processed_at IS NOT NULL` 且都被 `apply()` 处理（用可观察的投影结果间接验证，而非直接断言私有函数被调用） |
| AC-2 | Go 集成测试：构造 `_history.yml` 含一条 `final-status: archived` 的 CR，手工把对应 `cr` 投影行 `status` 设为不一致值，调用 `ApplySnapshot`（喂入合并后的快照）后断言该行收敛为 `archived` 且 `needs_reconcile=false` |
| AC-3 | 验收动作（非新增代码路径）：修复上线后跑过真实 reconcile 周期，直接查询生产 `cr` 表，断言 CR-2026-001 与 CR-2026-002 的 `status` 均为 `archived`、`needs_reconcile` 均为 `false`——过程记录在 TASK 完成记录，不允许手工 `UPDATE` |
