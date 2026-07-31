---
id: CR-2026-002-sdd
type: SDD
cr-ref: CR-2026-002
title: P1 治理核心 — crctl 接入（同步协议 · 签名审批 · controlled-shell 下沉）技术设计
status: draft
created: "2026-07-31T09:00:46+08:00"
updated: "2026-07-31T09:18:00+08:00"
revision: "0.1.1 — 落地技术评审建议 SDD-SUG-001/002/003"
---

# SDD — P1 治理核心：crctl 接入

> 输入：[prd.md](prd.md)（0.1.1）＋源方案 [P1-crctl接入设计.md](../../docs/product/P1-crctl接入设计.md)。
> 代码锚点沿用 M0 核实结果：multica fork（main@0980f3bfc 起）、tools（custom/main@5a52cd4 起）。
> fork 隔离约束：自研 Go 代码入新目录（CONTRIBUTING.AIFIRST.md 规则一），上游文件只留 `// AIFIRST:` 标记的最小挂钩。

## 1. 架构概览

### 1.1 组件与归属

| # | 组件 | 落点（仓/路径） | 新增/修改 | 职责 |
|---|------|----------------|-----------|------|
| C1 | crctl outbox 挂点 | tools `skills/shared/crctl/scripts/crctl.mjs` | 修改（casWrite 收尾 + cmdApprove + cmdGit push 后，约 60 行） | advance/approve/push 成功后原子写 `.crctl/outbox/*.json` |
| C2 | crctl grant 验签 | tools 同上 | 修改（cmdApprove 增 `--grant` 分支；gate/validate 统一摘要比对） | 非 TTY 审批放行；EVIDENCE_DRIFT 两轨检测 |
| C3 | rules.json 单一事实源 | tools `skills/shared/controlled-shell/rules.json` | 新增；crctl.mjs 删硬编码表改加载；hooks 改读 | 19 条三元组 + forbiddenFlags + protectedPaths |
| C4 | daemon CR 事件收集器 | multica `server/internal/daemon/crevents.go` | 新增文件（主循环挂钩一处，AIFIRST 标记） | outbox 扫描 + commit 兜底扫描 + 批量上报 + 确认删除 |
| C5 | 服务端投影 worker | multica `server/internal/governance/crsync.go` | 新增（新包，规则一） | 事件入库/幂等/有序消费/投影更新/WS 广播 |
| C6 | 签名审批服务 | multica `server/internal/governance/approval.go` | 新增（新包） | RequireHumanActor + 证据比对 + Ed25519 签发 grant + approval_record |
| C7 | reconcile 对账 | multica `server/internal/governance/reconcile.go` | 新增（新包，复用 sys_cron_executions 调度） | projected_commit vs origin HEAD；needs_reconcile 自愈 |
| C8 | gitguard | multica `server/pkg/gitguard/` | 新增包（~300 行） | rules.json 的 Go 消费方：Check/Run |
| C9 | execenv 铸造改造 | multica `server/internal/daemon/execenv/{execenv,git,runtime_config_sections}.go` + `crguard_config.go`（新） | 3 处修改（AIFIRST 标记）+ 1 新文件 | PATH shim / daemon 自守白名单 / 上下文注入 / hooks 物化 |
| C10 | 路由挂载 | multica `server/cmd/server/router.go` | 修改 2 行级（AIFIRST 标记，同 M0 模式） | `/api/daemon/cr-events`、审批 API 挂载 |

### 1.2 关键流程（事件主链路）

```
crctl advance/approve/push（用户机）
  └─ C1 原子写 .crctl/outbox/{ts}-{cr}-{kind}-{sha}.json
daemon 主循环（heartbeat 同周期）
  ├─ C4 outbox 扫描（全部已知 worktree + 主 workspace）
  ├─ C4 commit 兜底扫描（knowledge-base，.crctl/.scan-cursor 游标增量）
  ├─ 合并去重 (cr_id, commit_sha, event_kind)
  └─ POST /api/daemon/cr-events（≤100/批，mdt_）→ accepted 才删文件
server
  ├─ C5 入库 cr_sync_event（幂等键冲突=已处理）
  ├─ C5 per-CR 串行：合法转移→更新 cr 行+壳 Issue 7 态；非法→needs_reconcile
  ├─ C5 events.Bus → WS workspace:{id} / issue:{id}
  └─ C7 定时对账：projected_commit ≠ origin HEAD → 重放修复
```

审批链路（grant）：Web 点击批准 → C6 校验（人类身份/证据摘要/角色）→ 签名生成 grant → daemon 落盘 `.crctl/grants/` → `crctl approve --grant` 验签+重算摘要 → 写 approval.yml → 级联 advance → 回到事件主链路。

## 2. 数据模型

### 2.1 新表（PG，multica migrations 追加；P0 映射表已定权威域：**git 权威，PG 只是投影**）

```sql
-- cr 投影表（P0 已定义，本 CR 落地）
CREATE TABLE cr (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspace(id),
  cr_id         TEXT NOT NULL,                 -- "CR-2026-002"
  title         TEXT NOT NULL DEFAULT '',
  status        TEXT NOT NULL,                 -- 16 态之一（状态机只读副本校验）
  owners        JSONB NOT NULL DEFAULT '{}',
  target_version TEXT NOT NULL DEFAULT '',
  projected_commit TEXT NOT NULL DEFAULT '',   -- 投影所至的 knowledge-base SHA
  needs_reconcile  BOOLEAN NOT NULL DEFAULT FALSE,
  shell_issue_id   UUID REFERENCES issue(id),  -- 壳 Issue（7 态映射目标）
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, cr_id)
);

CREATE TABLE cr_sync_event (
  id           BIGSERIAL PRIMARY KEY,
  cr_id        TEXT NOT NULL,
  commit_sha   TEXT NOT NULL DEFAULT '',       -- embedded 补全前可空串
  event_kind   TEXT NOT NULL,                  -- status|owners|checkpoint|merge|archive|inbox
  payload      JSONB NOT NULL,
  actor        TEXT NOT NULL DEFAULT '',
  occurred_at  TIMESTAMPTZ NOT NULL,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  UNIQUE (cr_id, commit_sha, event_kind)
);

CREATE TABLE approval_record (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cr_id           TEXT NOT NULL,
  stage           TEXT NOT NULL,               -- gates.json#approvalStages 四键
  decision        TEXT NOT NULL,               -- approve|reject
  approver_user_id UUID NOT NULL REFERENCES "user"(id),
  evidence_digest TEXT NOT NULL,
  key_id          TEXT NOT NULL,
  signature       TEXT NOT NULL,               -- base64
  reject_reason   TEXT NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- approve 幂等、reject 允许多条留痕：同一版证据先 reject 后 approve 不得撞键（SDD-SUG-001）
CREATE UNIQUE INDEX approval_record_approve_uniq
  ON approval_record (cr_id, stage, evidence_digest) WHERE decision = 'approve';
```

`cr.workspace_id` 的解析（SDD-SUG-002）：事件体**不携带、不信任** workspace 标识；C5 从 DaemonAuth 上下文取该 daemon 配对时绑定的 workspace（`workspace_root_hash` 仅用于 daemon 侧多 workspace 区分与日志关联，不作为服务端信任输入）。

`activity_log`：不建新表，新增 action 枚举值 `aifirst.gitguard_denied`、`aifirst.evidence_drift`（Go 侧常量 + 校验放开；表结构不动）。工具调用摘要随任务完成回调入既有 `task` 详情 JSONB（与 `skills_used[]` 同层），不新建表。

### 2.2 文件侧 schema（git / 本地，权威侧）

| 文件 | 归属 | 说明 |
|---|---|---|
| `.crctl/outbox/{utc-ts}-{cr}-{kind}-{shortsha}.json` | workspace 本地，不入 git | 事件 schema v1（PRD FR-1 字段表）；写临时名再 rename |
| `.crctl/outbox/dead/` | 同上 | rejected×3 的坏事件停靠 |
| `.crctl/.scan-cursor` | knowledge-base worktree 本地 | 上次 commit 扫描 SHA |
| `.crctl/grants/{cr}-{stage}.grant.json` | workspace 本地，不入 git | grant schema v1（源方案 §B.2） |
| `.crctl/keys/{key_id}.pub` | **提交进 knowledge-base 仓** | Ed25519 公钥，换钥有审计痕迹 |
| `skills/shared/controlled-shell/rules.json` | tools 仓 | 白名单单一事实源 v1 |
| `approval.yml` 各段 | knowledge-base 仓 | 新统一字段 `evidence-digest`（替代 `evidence-sha256-16`） |

## 3. 接口契约

### 3.1 daemon → server（挂既有 DaemonAuth 组，mdt_ 令牌）

```
POST /api/daemon/cr-events
Req : { workspace_root_hash: string, events: OutboxEvent[] }   // ≤100
Resp: 200 { accepted: string[], rejected: [{file, code}] }     // code: BAD_EVENT|UNKNOWN_KIND|SCHEMA
GET  /api/daemon/approvals/pending?workspace_root_hash=…
Resp: 200 { grants: [{ cr_id, stage, grant: GrantFile }] }
POST /api/daemon/approvals/ack        // grant 已落盘确认，服务端标记 delivered
```

### 3.2 人类审批（挂既有用户会话鉴权；**RequireHumanActor：mat_ 任务令牌一律 403**）

```
GET  /api/workspaces/{wid}/crs                     // 看板列表（cr 投影表）
GET  /api/workspaces/{wid}/crs/{cr_id}/approval    // 审批卡片：证据摘要+digest 指纹
POST /api/workspaces/{wid}/crs/{cr_id}/approve
Req : { stage, decision: "approve"|"reject", reject_reason? }
Resp: 200 { grant: GrantFile }                      // 409=证据漂移, 403=验签/身份
```

### 3.3 crctl CLI（tools）

```
crctl approve <cr> --stage <s> --grant <path>   # 非 TTY 放行：验签+重算 digest
crctl approve <cr> --stage <s>                  # TTY 路径不变，但改写 evidence-digest 统一字段
```

### 3.4 WS 事件（复用 events.Bus → Hub）

`{ scope: "workspace:{id}"|"issue:{id}", type: "cr.updated", cr_id, status, needs_reconcile }`

## 4. 关键算法与流程

### 4.1 canonical evidence digest（唯一实现，AC-7⑤）

```
digest = sha256( concat( for f in sort(approvalStages[stage].evidence):
                           sha256(normalizeEol(read(f))) ) )      // hex 拼接后再 sha256
```
- `normalizeEol` 复用 M0 的 `evidenceSha16` 行尾规范化经验（\r\n→\n），避免 autocrlf 误报。
- crctl 内**仅此一个函数**；TTY 写入、--grant 验证、gate/validate 重算三处调用同一函数。Go 侧 C6 持等价实现，跨语言一致性用共享测试向量固定（tools 测试与 Go 测试引用同一组 fixture：同输入文件集 → 同 digest hex）。

### 4.2 grant 验签（crctl，Node ≥18 原生）

```
canonical = `v1|${cr_id}|${stage}|${decision}|${approver}|${approved_at}|${evidence_digest}`
crypto.verify('ed25519', Buffer.from(canonical), pubKey(.crctl/keys/{key_id}.pub), signature)
&& recompute_digest() === grant.evidence_digest        // 否则 EVIDENCE_DRIFT
&& grant.cr_id === 当前 CR && grant.stage === 当前 stage // 防挪用（签名已绑定，此为友好报错）
```

### 4.3 commit 兜底扫描正则（稳定契约，NFR-3）

```
^\[cr\] status (CR-\S+) (\S+) -> (\S+)$      → status
^\[cr\] merge metadata (CR-\S+)              → merge（payload 读该 commit 的 _backlog.yml diff）
^\[cr\] archive (CR-\S+)                     → archive
^\[cr\] inbox-emit (CR-\S+) event=(\S+)      → inbox
```

### 4.4 投影消费（C5）

```
tx: INSERT cr_sync_event ON CONFLICT DO NOTHING → 冲突则 return（已处理）
per-CR 互斥（sync.Map[cr_id]*sync.Mutex；多节点后备：PG advisory lock hashtext(cr_id)）
if isLegalTransition(cur.status, ev.to_status)：更新 cr 行 + projected_commit + 壳 Issue 7 态映射
else：cr.needs_reconcile = true（不强行应用）
commit_sha == "" 的事件：延迟 60s 处理，等 push 补全事件合并（源方案 §A.5）
```
状态机 23 条转移表只读副本：从 tools `dir-graph.yaml` 生成 Go 常量文件 `transitions_gen.go` 并**提交入库**（文件头注释记录来源 tools commit SHA）；CI 只校验"重新生成 == 已入库"（漂移即红），multica 构建本身不跨仓依赖 tools checkout（SDD-SUG-003）。

### 4.5 execenv 铸造（C9）

```
每任务 workdir 铸造:
  写 {workdir}/.bin/git → "exec {daemonSelfPath} gitguard-exec git \"$@\" --caller={agent_id}"
  child env: PATH = {workdir}/.bin + PATHSEP + 原 PATH；CRCTL_WORKSPACE=工作区根
  Claude 后端: 物化 per-task .claude/settings.json（PreToolUse: pretooluse-guard.mjs, inject-cr-status.mjs）
             permission.bash=deny → ExecOptions.ExtraArgs += ["--disallowedTools","Bash"]
  其他后端: 仅 shim + 上下文注入（诚实降级）
Windows 注意：.bin/git 需成对物化 git.cmd（cmd/PowerShell）与 git（bash shim），M0 已证本机开发环境为 Git Bash + PowerShell 混用。
```

## 5. 技术选型与替代方案

| 决策 | 选择 | 被否方案与理由 |
|---|---|---|
| crctl→server 通道 | 本地 outbox 文件 + daemon 上报 | crctl 直连 HTTP：破坏零依赖/离线原则；且 token 管理进 crctl 属职责越界 |
| 事件可靠性 | at-least-once + 幂等键去重 | exactly-once：分布式代价不值；去重键天然幂等 |
| 兜底通道 | commit message 正则扫描 | 仅 outbox：覆盖不了旧版 crctl/人工 git/编排器直 commit 三旁路 |
| 签名算法 | Ed25519（Node/Go 原生） | HMAC：对称密钥无法公开验证，公钥进 git 的审计模式不成立；RSA：无必要 |
| 审批下发 | grant 文件落盘 worktree | 长连接在线审批：断网即瘫；文件模式与 outbox 对称，离线补投 |
| 白名单事实源 | rules.json 数据文件三方共读 | 各自维护：M0 已实测漂移（15 vs 19 条）；代码生成：过重 |
| 投影更新范围 | server 持状态机只读副本做合法性校验 | 无校验直写：乱序/漏事件会产生错误投影且无法察觉 |
| 自研代码落点 | `internal/governance/` 新包（规则一） | 源方案原文 `internal/service/`：multica 无此包，且违反 fork 隔离规则——**本 SDD 修正源方案该处路径** |

## 6. FR → 技术实现映射

| FR | 组件 | 落点仓 | 交付物 |
|---|---|---|---|
| FR-1 | C1 | tools | crctl.mjs outbox 挂点 + 事件 schema + 单测（断网 advance→文件；embedded 空 SHA） |
| FR-2 | C4+C5+C10 | multica | crevents.go、governance/crsync.go、cr-events 端点、migrations（cr、cr_sync_event）、双通道去重测试 |
| FR-3 | C7 | multica | governance/reconcile.go、REMOTE_RECONCILE_MODE 配置、篡改自愈测试（server 模式对 GitHub origin 实测，PAT 前置见 AC-3） |
| FR-4 | C6+C2 | multica+tools | governance/approval.go、approval_record 迁移、grant 签发 API、crctl --grant、密钥 smoke test、三拒绝路径单测 |
| FR-5 | C3+C8+C9 | tools+multica | rules.json、gitguard 包、execenv 四处、crctl 硬编码表删除（8 测试回归） |
| FR-6 | C8+C4 | multica | gitguard 拒绝事件→任务回调→activity_log；工具摘要随完成回调持久化 |
| FR-7 | C2 | tools+multica | evidence-digest 统一字段、gate/validate 两轨比对、漂移事件上报 activity_log |

## 7. 安全与性能考量

- **私钥**（源方案 §B.5 全采纳）：文件 0400 或 `APPROVAL_SIGNING_KEY` env base64 二选一；启动公私钥互验 smoke test 失败即拒绝启动；签名单点收口在 governance/approval.go；日志只出 key_id。
- **防重放**：签名绑定 `cr_id+stage+evidence_digest`；approval_record 幂等键同三元组。
- **人类身份**：审批 API 中间件级拒绝 `mat_`；grant 内 approver 来自会话用户，不信 crctl `--caller` 自报。
- **审计最小化**：gitguard 拒绝事件不含参数正文；工具摘要不含输入输出正文；漂移事件不含证据内容。
- **性能**：事件采集搭 heartbeat 便车（无新轮询）；单批 ≤100；outbox 文件名含时序天然有序；WS 推送替代看板轮询。
- **诚实边界**（NFR-5 落文档）：PATH shim 可被绝对路径绕过——写入 rules.json 解说与 SKILL.md；第 4 层（CAS+gate）与第 5 层（CI cr-guard）为兜底事实。
- **升级兼容**：旧 approval.yml 的 `evidence-sha256-16` 读到即视为"无摘要"，不报错不阻塞（NFR-3）；`[cr] ` commit 格式冻结。

## 8. 测试设计（对应 AC）

| AC | 验证方式 |
|---|---|
| AC-1 | tools 单测：mock 断网（outbox 写成功即可，无网络调用）+ 文件 schema 断言 + embedded 空 SHA 补全用例 |
| AC-2 | Go 集成测试：同事件双通道注入 → 断言单行；乱序注入 → needs_reconcile；WS 收流断言 |
| AC-3 | 手工+脚本：UPDATE cr SET status='x' → 等对账周期 → 断言恢复；两模式各跑一次 |
| AC-4 | Go 单测三拒绝路径 + tools 三 grant 用例 + 端到端一次（无 TTY 环境实跑） |
| AC-5 | gitguard 表驱动测试（force push/-c/绝对路径声明）+ hook deny 手测 + crctl 8 测试回归 |
| AC-6 | 端到端：任务内故意触发 FORBIDDEN_* → 查 activity_log 行 + 字段断言（无参数正文） |
| AC-7 | tools 测试：TTY 审批→篡改→status/validate 检出；旧字段兼容用例；digest 单一函数由代码评审核查 |
