---
id: CR-2026-018-sdd
type: SDD
cr-ref: CR-2026-018
title: 治理工具链 — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）技术设计
status: draft
created: "2026-08-04T14:00:00+08:00"
updated: "2026-08-04T14:00:00+08:00"
---

# SDD — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（T1-full）

> 输入：`change-requests/CR-2026-018/prd.md`（FR-1~9 / AC-1~10）。
> 本设计基于对 `tools/skills/shared/crctl/scripts/crctl.mjs`（1305 行）与全部 skill 文档的实地盘点，所有行号均为当前 tools 包实测值。

## 0. PRD 事实基线修正（纪律 #4 revision）

PRD §1.3 断言"适配器读取路径均经 crctl 子命令，随 crctl 升级自然切换"。实测**不完全成立**：

- claude-code 适配器的 `adapters/claude-code/hooks/inject-cr-status.mjs` 为保持轻量**不依赖 crctl 主程序**，直接行级扫描 `_backlog.yml` 的 `id`/`status`/`updated-at` 行（该文件 :28-:47）。状态字段撤出 `_backlog.yml` 后此 hook 会将所有 CR 读成 `status='?'`。
- CI 适配器（`adapters/ci/cr-guard.template.yml`）确实全部经 `crctl validate`/`crctl gate`，随 crctl 升级自然切换，无需改动。

**影响**：FR-8 范围从"仅回归验证"扩为"修改 inject-cr-status.mjs + 双适配器回归"。PRD 结论（适配器需同版本发布）不受影响，反而强化。

## 1. 架构概览

### 1.1 现状（改造前）

```
写路径（唯一合法写入 = crctl advance, cmdAdvance :796）
  :814 updateBacklogStatus(:674)  → _backlog.yml 条目 status+updated-at 行   [权威]
  :815 updateCrMdStatus(:708)     → cr.md frontmatter status+updated-at      [尽力写，失败仅返回 {updated:false, why}]

读路径（5 处，全部经 loadBacklogEntry(:334) 取 entry.status）
  cmdStatus  :766   cmdAdvance :800   cmdApprove :857（级联再读 :919）   cmdNext :1140
旁路读（不经 crctl）
  inject-cr-status.mjs 行扫 _backlog.yml
  16 个 skill 文档指示 Agent 读 backlog[].status（清单见 §6 FR-6）
```

### 1.2 目标（改造后）

```
写路径
  cmdAdvance → updateCrMdStatus（升级为硬失败：cr.md 缺失/无 frontmatter → fail CR_MD_WRITE_FAILED）
  updateBacklogStatus() 整函数删除（唯一调用点 :814 移除）

读路径（新增单一收敛点）
  resolveCrState(ws, cr)  ← 5 处 cmd* 统一改调此函数
    ├─ loadBacklogEntry(ws, cr)      # 继续提供注册字段：owners / merge-commits / prd-path …
    └─ readCrMdStatus(ws, cr)        # 新增：cr.md frontmatter status（权威）
       └─ fallback: entry.status + legacySource=true   # 迁移期兼容读（FR-2）

旁路读
  inject-cr-status.mjs：backlog 行扫只取 id 清单 → 逐 CR 读 cr.md frontmatter status（cr.md 缺失时回退 backlog 行值）
  16 个 skill 文档：读 status 的段落改指向 cr.md（§6）
```

**核心不变量**：`_backlog.yml` 文件继续存在（workspace 探测锚点 :289 不动）；状态机语义零变更（NFR-1）；CAS 写保护与审计日志（auditLog :358）不动。

## 2. 数据模型

### 2.1 cr.md frontmatter（权威状态载体，字段不变、权威性升级）

`status` / `updated-at` 语义不变。变化仅在写入契约：`updateCrMdStatus` 从"尽力写"升级为"权威写"——cr.md 不存在、无 frontmatter、CAS 冲突均硬失败，advance 整体中止不写任何文件（保持"任何校验失败都不写文件"的既有承诺）。

### 2.2 `_backlog.yml` 条目 schema v2（注册索引）

```yaml
# 保留（注册与里程碑字段，低频写）
- id, title, summary, owner, owners{...}, owner-history[], handover-history[]
  target-version, source, prd-path, submitter, reviewer, opened,
  created, updated, remote-ref, last-push-at, last-push-by,
  merge-commits[], merge-recovery, archived-at, writeback_spec_id
# 移除（撤出权威地位，由迁移命令物理删除）
- status        # → cr.md frontmatter
- updated-at    # → cr.md frontmatter（每次 advance 都写，是与 status 同级的冲突源）
```

顶层 `schema` 字段从 `cr-backlog/v1`（或缺省）升为 `cr-backlog/v2`，供 `validate` 与兼容读判别布局代际；无 `schema` 或 v1 视为旧布局。

### 2.3 迁移报告（`crctl migrate-backlog` 产物）

```yaml
# change-requests/{workspace 根}/.crctl/migrate-backlog-report.yml（gitignore 内，审计用）
migrated-at: ISO-8601
entries: [{ id, status-at-migration, consistent: true }]
removed-lines: N
schema: cr-backlog/v1 -> cr-backlog/v2
```

## 3. 接口契约

### 3.1 crctl 子命令行为变化

| 子命令 | 变化 | 输出变化 |
|---|---|---|
| `status` | 状态源 cr.md 优先 | `source` 增加 `crMd: <path>`；回退时增加 `legacySource: "_backlog.yml"` 顶层标记 |
| `advance` | 只写 cr.md；前置读走 resolveCrState | `files[]` 只含 cr.md；commit 涉及文件减半 |
| `gate` | 读路径切换，校验逻辑不变 | 无 |
| `approve` | 前置读与级联 advance 随之切换 | 无 |
| `next` | 读路径切换 | 无 |
| `validate` | `_backlog.yml`：v2 条目**不得**含 status/updated-at（含则报 `LEGACY_STATUS_FIELD` 告警）；v1 条目若 status 与 cr.md 不一致报漂移告警（迁移期退出码 0，AC-3） | errors/warnings 分级输出 |
| `migrate-backlog`（新增） | 见 §4.3 | 迁移报告 + 结构化 JSON |

### 3.2 错误码增量

| 错误码 | 触发 | 级别 |
|---|---|---|
| `CR_MD_WRITE_FAILED` | advance 时 cr.md 缺失/无 frontmatter/CAS 冲突 | fatal（原样保留 `CAS_CONFLICT` 细分） |
| `CR_MD_STATUS_MISSING` | 新布局（backlog v2）下 cr.md 也无 status——无处可读 | fatal |
| `LEGACY_STATUS_FIELD` | v2 schema 但条目仍含 status 行 | warning |
| `MIGRATE_STATUS_MISMATCH` | 迁移预检发现 backlog 与 cr.md 状态不一致 | fatal，不写文件 |

### 3.3 兼容读弃用时间线（评审 suggestion #2 落实）

回退路径标记 `deprecated since v0.2.0`；计划 v0.3.0 移除（至少间隔一个完整 CR 生命周期，NFR-4）。移除时 `CR_MD_STATUS_MISSING` 从回退改为直接抛出。

## 4. 关键算法与流程

### 4.1 resolveCrState（新增，5 个读取点的唯一收敛）

```js
function resolveCrState(ws, cr) {
  const snap = loadBacklogEntry(ws, cr);            // 注册字段 + CAS snapshot（保留原样）
  const md = readCrMdFrontmatter(ws, cr);            // 纪律#1：先 \r\n→\n，无 frontmatter 返回 null
  if (md && md.status) return { snap, status: md.status, statusSource: 'cr.md' };
  if (snap.entry.status)                             // 迁移期兼容读（FR-2，deprecated）
    return { snap, status: snap.entry.status, statusSource: '_backlog.yml', legacySource: true };
  fail('CR_MD_STATUS_MISSING', `${cr} 在 cr.md 与 _backlog.yml 中均无 status`);
}
```

冲突裁决：cr.md 与 backlog **都有** status 且不一致时，cr.md 胜（权威），不报错——漂移检测归 `validate`（读路径报错会把只读命令变成门禁，越权）。

### 4.2 advance 写路径（cmdAdvance :810-:816 段改造）

```js
// 删除：updateBacklogStatus(ws, cr, flags.to, snap);
const crmd = updateCrMdStatus(ws, cr, flags.to);     // 升级：内部所有 {updated:false} 分支改为 fail('CR_MD_WRITE_FAILED', why)
// result.files = [crmd.path]；standalone commit 的 add 范围从 'change-requests' 收窄为 'change-requests/{cr}/cr.md'
```

顺带修正：现 standalone 模式 `git add change-requests`（:820）会把工作区内**无关未暂存变更**一起提交——收窄为精确路径，属本次改造的既有隐患修复。

### 4.3 migrate-backlog（新增子命令）

```
1. 读 _backlog.yml（CAS snapshot），逐条目：
   - 读对应 cr.md frontmatter status
   - entry.status 缺失 → 跳过（已迁移）
   - cr.md 无 status 或与 entry.status 不一致 → 收集差异
2. 差异非空 → fail('MIGRATE_STATUS_MISMATCH', 差异清单)，不写任何文件（纪律#1 硬失败，禁止静默取一侧）
3. 全一致 → 行级定点删除各条目 status:/updated-at: 行（复用 updateBacklogStatus 的条目定位算法 :678-:690），
   顶层 schema 升 v2，CAS 写回；写迁移报告；standalone commit "[cr] migrate backlog to v2 (status -> cr.md)"
```

幂等：v2 + 无 status 行时输出 already-migrated，退出码 0。

### 4.4 inject-cr-status.mjs 改造

保持"轻量、零依赖、失败静默放行"定位：行扫 `_backlog.yml` 只取 `id` 清单；逐 id 读 `change-requests/{id}/cr.md` 前 60 行扫 frontmatter `status:` 行（复用其现有退化扫描模式）；cr.md 读不到时回退 backlog 行值（旧布局兼容）；终态过滤逻辑不变。注入文案中的数据源说明从 `_backlog.yml` 改为 `cr.md`。

### 4.5 端到端验证流程（AC-9）

```
fixture workspace → 注册 CR-X（分支）推进 3 次状态 → master 侧注册 CR-Y（写 _backlog 新条目）
→ git merge-tree --write-tree master branch 对 _backlog.yml 零冲突断言（CR-X 的推进只碰 cr.md；CR-Y 的注册在 master 单侧）
```

## 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| 权威状态载体 | cr.md frontmatter | 每 CR 独立 status.yml | cr.md 已有字段 + 写入函数（:708），零新文件零新 schema；status.yml 引入第三个副本 |
| _backlog.yml 去留 | 保留为注册索引 | 删除、改由目录扫描 | workspace 探测锚点（:289）+ owners/merge-commits 等注册字段需要一个索引家；删除波及 31 处文档引用而非 16 处 |
| 冲突消除层 | 数据布局（撤出高频字段） | git union merge driver / .gitattributes | merge driver 平台绑定（每 clone 手工配置、Windows 差异）、YAML 语义盲，且 rebase 场景不完全生效 |
| 状态提交位置 | 保持 CR 分支 | 状态统一在 master 单侧提交 | 门禁证据（review-annotations/test-report）在 worktree 分支上，跨 checkout 读写把单命令事务拆成两仓协调，复杂度不成比例 |
| 兼容策略 | 运行时回退读 + 显式迁移命令 | 一刀切、首次运行自动迁移 | 多 workspace 分批迁移需要窗口期；自动迁移在只读命令里做写操作违反最小惊讶 |

## 6. FR 到技术实现映射

| FR | 实现位点 | 变更类型 |
|---|---|---|
| FR-1 advance 单写 | crctl.mjs :814 删调用、:674-:705 删函数、updateCrMdStatus 硬失败化、:820 add 范围收窄 | 代码 |
| FR-2 兼容读 | 新增 resolveCrState + readCrMdFrontmatter；:766/:800/:857/:919/:1140 五处改调 | 代码 |
| FR-3 注册索引 schema v2 | validate（:1018-:1024 段）条目规则调整 + `LEGACY_STATUS_FIELD` 告警 | 代码 |
| FR-4 探测不变 | :289 无改动（回归断言覆盖） | 仅测试 |
| FR-5 迁移命令 | 新增 cmdMigrateBacklog + CLI 帮助（:1235 段） | 代码 |
| FR-6 skill 文档修订（16 个消费 status；另 15 个仅引用路径不改） | cr-archive（Step 3 条目移动以 cr.md final-status 为准）、cr-dashboard（状态分组改扫 cr.md）、cr-inbox、cr-review-record、cr-status-set（契约描述）、approve-code / approve-dev-start / approve-tech-design / approve-requirement（前置读描述）、analyze-current-product、focus-briefing、requirement-register（**注册时新条目不再写 status/updated-at 字段，status 只落 cr.md**）、review-alignment、crctl SKILL.md、spec-dashboard、merge-feature-branch（Step 5 embedded patch 只落 cr.md，merge-commits[] 仍写 _backlog） | 文档 |
| FR-7 状态机声明 | tools/dir-graph.yaml :210 `scope` 改为 `change-requests/{CR-ID}/cr.md`；gates.json 实测无 backlog 引用，不动 | 文档 |
| FR-8 适配器 | inject-cr-status.mjs 改造（§4.4，PRD 假设修正见 §0）；CI 模板零改动 + 双适配器 fixture 回归 | 代码 + 测试 |
| FR-9 归档流 | cr-archive 移动条目逻辑保持；final-status 读取源改 cr.md（并入 FR-6 文档修订） | 文档 |

测试增量（AC-10）：现有 21 个用例全绿为回归线；新增 ≥6：单写 diff 断言（AC-1）、新旧布局双向读（AC-2）、validate 三态（AC-3）、迁移成功/失败/幂等（AC-5）、merge-tree 零冲突端到端（AC-9）、cr.md 缺失硬失败（CR_MD_WRITE_FAILED）。

## 7. 安全与性能考量

- **原子性**：advance 从双文件写收敛为单文件写 + CAS，部分写入窗口消失；`CR_ARCHIVE_STATUS_SYNC_FAILED` 类双写不一致错误场景整类消亡。
- **单一写入路径不破坏**：迁移命令与 advance 同经 CAS + 审计日志 + controlledGit 白名单提交，不开旁路（与 P2 的 crctl 子命令化方向一致）。
- **性能**：resolveCrState 每次多读一个 cr.md（数 KB），单 CR 命令无感；cr-dashboard 全量扫描从 1 文件变 N+1 文件（N=在途 CR 数，实测 <20），仍为毫秒级。
- **行尾纪律**：readCrMdFrontmatter 与迁移的行级删除全部先 `\r\n→\n` 规范化、`split(/\r?\n/)`、解析失败硬报错（纪律 #1）；updateCrMdStatus 现有实现已合规，沿用。
- **回滚**：改造本身可整体 revert（crctl 单文件 + 文档）；迁移命令产生的 v2 布局回滚 = revert 迁移 commit，无数据丢失（status 在 cr.md 始终存在）。
- **残余风险**：迁移窗口期内新旧 crctl 混用同一 workspace（旧版仍写 backlog）会重新引入双写——迁移后 v2 schema 会让旧版 `updateBacklogStatus` 定位不到 status 行而硬失败（`BACKLOG_SHAPE` :692），风险自限，但发布说明需明示"迁移后必须统一 crctl 版本"。
