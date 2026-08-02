---
id: CR-2026-011-sdd
type: SDD
cr-ref: CR-2026-011
title: P2 三模式聊天 CR-F — 技术设计（D7 门禁接合：B4 迁移 + 审批卡/blocker/CR 徽标）
target-version: "0.18"
owner: Ray
owner-role: development
status: draft
created: "2026-08-02T12:10:00+08:00"
updated: "2026-08-02T12:10:00+08:00"
revision: "0.1.0"
prd-ref: "change-requests/CR-2026-011/prd.md"
---

# SDD — P2 三模式聊天 CR-F：D7 门禁接合

> 本 SDD 基于 multica main（含已合并的 CR-2026-002/003/004/006）实地代码调查编写，
> 文件路径/行号均已核实；治理侧契约以累积基线 SDD §3（审批 API / WS / grant）与
> `tools/skills/shared/crctl/gates.json`（approvalStages 四键：requirement / tech-design /
> dev-start / code）为准。需求评审 3 条建议（REQ-SUG-001/002/003）的定案见 §6。

## 1. 设计总览

D7 是"接合"不是"新建"：审批强度链路（Ed25519 grant / RequireHumanActor / EVIDENCE_DRIFT 409）
CR-2026-002 已全部交付且不动；聊天窗口与消息流 CR-2026-006 已交付。本 CR 补三块：
**① 数据地基**（B4 两列 + pipeline 两表 + 门禁节点投影器），**② 首个审批消费面 UI**
（审批卡 / blocker / attempt / 16 态徽标——审批 API 至今零前端调用方，client 层全新），
**③ 已交付面的两个缺口闭合**（`cr:updated` 前端半边缺失；`HandleApprove` 缺角色策略，
现状任何 workspace 成员均可批）。

```
git 权威（crctl advance/approve/review commits）
  → daemon crevents.go（outbox + commit 扫描；本 CR 增第 5 类 review 正则）
  → POST /api/daemon/cr-events → crsync worker
       ├─ cr 投影（既有）→ WS cr:updated（既有，本 CR 补前端半边）
       └─ 门禁节点投影器（新）→ pipeline_run / pipeline_node_run（新表）
前端 project-chat-panel
  ├─ 模式 TabsList 右侧：CrStatusBadge（16 态徽标 + 多 CR popover）
  └─ TeamAgentStreamView 合并循环：CrGateCard（审批卡/blocked/attempt 变体）
       批准/驳回 → POST /api/workspaces/{wid}/crs/{crID}/approve（既有）
       → grant → daemon 落盘 → crctl --grant 验签推进 → 事件回流 → 卡片闭环
```

## 2. 关键设计决策

| # | 决策 | 依据 |
|---|---|---|
| DD-1 | **pipeline 两表首期定位 = 治理事件投影**，写者是 crsync worker 的门禁节点投影器，不是编排器；只投影门禁相关节点（human_approval + 5 个 review 节点），全节点覆盖归 CR-H Runner（届时 Runner 成为第二写者，schema 已就位） | 无 Runner 前唯一真实数据源是 crctl 事件流；投影器 ~150 行挂进既有 `applyStatus`（crsync.go:267），复用幂等/串行/广播全部机制 |
| DD-2 | **审批卡可见性判定 = `cr.status ∈ approvalStages[stage].expect`**（requirement-reviewing / tech-design-review-pending / task-breakdown / code-reviewing 四态各对应一段），node_run 行只做增强（attempt/blockers/历史），不做显示前提 | gates.json 语义原样；即使投影器漏事件，审批卡仍随 cr 投影出现——降级安全 |
| DD-3 | **blocked 评审的平台可见通道 = daemon commit 扫描增第 5 类正则** `^\[cr\] review-(requirement\|tech-design\|code) (CR-\S+): verdict=(\S+)` + `git show <sha>:review-annotations/{stage}.yml` 解析 {verdict, blockers[], current-attempt} 作 payload（新 event_kind=`review`）；**tools/crctl 零改动** | review 被 block 时无 advance → 无 outbox 事件 → 平台今天完全看不见 block；扫描通道是 fork 侧 daemon 代码（crevents.go），复用游标/幂等/at-least-once 全套 |
| DD-4 | **cr_id 归因走 StartTask 回调**：daemon 从任务 workdir 的 git 分支（`requirement/CR-*` 命名约定）派生 cr_id 随 start 上报；服务端**校验 cr 表存在同 workspace 行才落列**（不信 daemon 自报——沿 CompleteTask 对 ToolCalls 清零重算的既有信任原则，daemon.go:2537-2546）。`pipeline_node_run_id` 本期**无写者、恒 NULL**（收窄 PRD FR-2，论证见 §6.1） | 入队七路（task.go:745/847/896/1031/1117/2125、autopilot.go:572）全无 CR 概念，入队时点拿不到归因；开跑时点 workdir 已定，归因真实且零猜测 |
| DD-5 | **审批权限收口单函数** `canApprove(userID, cr, stage)`：workspace owner/admin ∨ `cr.owners` 对应角色（requirement→requirement，tech-design/dev-start/code→development，test 角色留策略扩展）；`GET gates` 透出 `can_approve`，`HandleApprove` 强制同函数 → 403 | 现状 HandleApprove 仅 requireHumanActor（approval.go:156-166），**无角色校验**——PRD FR-4 的"有权限者"语义现状不成立，必须补；单函数防 GET/POST 判定漂移 |
| DD-6 | **WS 零新增事件类型**：review 投影更新也 publish 既有 `cr:updated`（payload 不变）；前端补齐缺失的半边——protocol/events.go 常量 + `packages/core/types/events.ts` union/payload map + gates query 失效 handler | `cr:updated` 目前只存在于 governance 包局部常量（crsync.go:35），TS 侧 union/payload/handler 三处全缺（调查报告 §3 gaps）；一个事件类型驱动"徽标+卡片"两个 query 失效已足够 |
| DD-7 | **徽标挂点 = 模式 TabsList 右侧**（project-chat-panel.tsx:74-93）；多 CR 取值 = `updated_at` 最新的非终态 CR，点击 popover 列出该项目全部在途 CR（各带 16 态徽标） | chat header 本体不存在（调查 §5：面板内最近似物即模式 tab 条）；REQ-SUG-002 定案 |
| DD-8 | **审批/门禁全部端点挂在 `approvalSvc != nil` 既有条件组**；前端 gates 探测 404 → 静默隐藏全部门禁 UI | APPROVAL_SIGNING_KEY 未配置时路由整组不挂载（router.go:723,786），404 而非 503——UI 必须按功能未启用降级 |

## 3. 数据模型与迁移（1 个 migration：`161_aifirst_pipeline_runs`）

编号 161（160 为当前最大；146-148 处于 lint 冻结区不可用，migrations_lint_test.go:96）。
四段，down 对称回滚，CUSTOM.md 登记（沿 158 的 AIFIRST fork 条目模式）：

1. `CREATE TABLE pipeline_run`：照抄 P0 §3.4（workspace_id / pipeline_id / cr_id / issue_id /
   status 5 值 CHECK / inputs / execution_context / started_by / 时间戳）。
2. `CREATE TABLE pipeline_node_run`：照抄 P0 §3.4（run_id CASCADE / node_id / ref / kind 3 值 /
   seq / status 6 值 / attempt / approval_id → approval_record / output_note / 时间戳 /
   `UNIQUE(run_id, node_id, attempt)`），**增补一列 `detail JSONB NOT NULL DEFAULT '{}'`**
   ——存 review 事件的 {verdict, blockers[], reviewer, reviewed_at}（P0 schema 无处放 blocker
   明细；这是对 P0 §3.4 的单列增补，回写 specs 时登记）。
3. `ALTER TABLE agent_task_queue ADD COLUMN cr_id TEXT NULL, ADD COLUMN pipeline_node_run_id
   UUID NULL REFERENCES pipeline_node_run(id) ON DELETE SET NULL` + 两个部分索引（P0 §2.2 原样）。
4. **`CreateRetryTask` 显式列清单补两列**（queries/agent.sql:239 的 INSERT…SELECT 克隆——
   不补则重试任务静默丢归因）+ `make sqlc`。

**Claim 谓词不动**：`ClaimAgentTask`（agent.sql:350-388）的 NOT EXISTS 串行化键与"四 FK 全空"
互斥类均不感知新列——本期新列由回调后置写入（DD-4），claim 时恒 NULL，语义零变化。
CR-H 引入 Runner 入队时必须重新审视该谓词（已写入后续规划文档 §1）。

## 4. 后端设计

### 4.1 门禁节点投影器（`internal/governance/crsync.go` 扩展）

挂在 `applyStatus` 成功路径与新的 `applyReview` 分支。静态映射表（Go 常量，与状态机 23 条
转移表同源置于 governance 包）：

| cr.status 进入 | pipeline_run（按 (cr_id, pipeline_id) lazy upsert） | node_run upsert |
|---|---|---|
| requirement-reviewing | requirement-authoring | human_approval(requirement) → running |
| requirement-approved | 同上（run completed） | 同节点 → passed，链接 approval_id（按 (cr_id,stage) 最新 approve 行） |
| tech-designing / tech-design-review-pending / tech-design-reviewed | architecture-design | 同构：human_approval(tech-design) running → passed |
| task-breakdown / developing | code-implementation | human_approval(dev-start) running → passed |
| code-reviewing / code-approved | code-implementation | human_approval(code) running → passed |
| merging / writing-back / archived | feature-writeback（run completed on archived） | — |
| rejected / withdrawn | 当前非终态 run → cancelled | 当前 running 节点 → failed |
| review 事件 verdict=block | 对应 pipeline | review 节点 → blocked，attempt=yml current-attempt，detail=payload |
| review 事件 verdict=pass | 同上 | review 节点 → passed（同 attempt） |

- `node_id`：pipeline 模板节点若无稳定 UUID（任务期核实 tools 模板），用
  UUIDv5(ns, `{pipeline_id}|{node_ref}`) 确定性派生——投影可重放幂等的前提。
- run 状态机：有 running human_approval 节点 → `waiting_approval`，否则 `running`。
- attempt 权威在 git `review-loop.yml`，投影只读展示；**不做 PG→git 回写**（那是 CR-H 的
  Runner reviewLoop 职责，本 CR 不碰唯一反向流动）。
- 每次投影变更后 publish `cr:updated`（DD-6，复用 crsync.go:303 的 publish）。

### 4.2 review 事件兜底扫描（`internal/daemon/crevents.go` 扩展）

第 5 类正则（DD-3）命中后 `git show <sha>:change-requests/{cr}/review-annotations/{stage}.yml`
解析 verdict/blockers/current-attempt 为 payload，event_kind=`review`；服务端 `HandleCREvents`
的 kind 白名单放行 `review`。幂等键 `(cr_id, commit_sha, event_kind)` 照旧；yml 解析失败 →
该事件 BAD_EVENT 进 dead（不阻塞批次）。commit message 措辞是仓库约定非稳定契约——正则
只锚定 `[cr] review-{stage} {CR-ID}: verdict={v}` 前缀段，后缀自由文本忽略（风险登记 §8）。

### 4.3 `GET /api/projects/{projectID}/gates`（新，governance 包）

挂 approvalSvc 条件组 + 项目成员鉴权。raw pgxpool（沿 crsync.go:9-11 的"fork 不碰 sqlc"约定）：
`cr JOIN issue ON cr.shell_issue_id=issue.id AND issue.project_id=$1` 取非终态 CR，每条带：
16 态 status、needs_reconcile、`can_approve`（DD-5）、当前 pending 审批段（DD-2 推导）+
approval 卡数据（evidence 摘要 + evidence_digest + key_id，内联 `latestEvidence` 逻辑,
approval.go:169-182，省一次往返）、该 CR 各 gate node_run（status/attempt/detail）。
响应一把返回，徽标与卡片共用一个 query。

### 4.4 `HandleApprove` 补角色策略（DD-5）

`canApprove` 不过 → 403 `{"error":"FORBIDDEN_APPROVER","required_role":…}`（结构化，前端可呈现）。
既有 requireHumanActor / EVIDENCE_DRIFT 409 / 幂等 grant 语义全部不动。

### 4.5 StartTask 归因（DD-4）

`StartTask`（daemon.go:2376）请求体增可选 `cr_id`；daemon 侧从 workdir `git rev-parse
--abbrev-ref HEAD` 匹配 `requirement/CR-*` 派生。服务端校验：cr 行存在且 workspace 与任务
一致 → `UPDATE agent_task_queue SET cr_id=$1 WHERE id=$2`；校验不过静默忽略（归因是增强
不是门禁，不因此 fail 任务）。

## 5. 前端设计

### 5.1 client 层（全新，`packages/core`）

- api：`getProjectGates(projectId)`、`approveCr(wid, crId, {stage, decision, reject_reason,
  evidence_digest})`；query key 根 `projectGates(projectId)`。
- WS 闭环（DD-6）：`server/pkg/protocol/events.go` 增 `cr:updated` 常量（governance 局部常量
  改引它）；`packages/core/types/events.ts` union + `WSEventPayloadMap` 增
  `{cr_id, status, needs_reconcile}`；`use-realtime-sync.ts` 增 handler → invalidate
  `projectGates` 根（workspace 级广播，按需失效足够，消息频度极低）。
- 降级（DD-8）：gates 请求 404 → query 置 disabled 标记，门禁 UI 整体不渲染，不重试不报错。

### 5.2 `CrGateCard`（新组件，插入 TeamAgentStreamView 合并循环 project-team-agent-chat.tsx:99-118）

门禁项作为第三类时间线元素（排序键 = node_run started_at / cr 事件时间）参与既有
comment/task 双源合并。三个变体：

- **审批卡**（human_approval running + DD-2 判定为 pending）：CR-ID + 段名 + 证据摘要
  （evidence 文件清单 + sha256 前 12 位指纹 + digest 指纹）+ needs_reconcile 警示条（如真）。
  `can_approve` → 「批准」/「驳回」（驳回展开必填 reason textarea）；否则只读"等待 {角色} 审批"。
  提交带 `evidence_digest`（取自 gates 响应）→ 409 EVIDENCE_DRIFT 呈现 expected/current 指纹
  + 「证据已变更，请刷新后重审」；403 呈现 FORBIDDEN_APPROVER/human-actor 原因。成功后乐观置
  「已批准，等待 crctl 推进」中间态，`cr:updated` 到达后转终态（卡片折叠为单行历史条）。
- **blocked 卡**（review 节点 blocked）：blocker 列表（id/location/issue/suggestion，
  detail JSONB 直渲）+ 「reviewLoop attempt N/3」进度点 + repair-target 说明。
- **历史条**（passed/failed 节点）：单行折叠（"✓ requirement 审批通过 · alice · 2h 前"），
  可展开看当时证据指纹。

任务执行卡锚点（FR-3 任务侧）：`TaskExecutionCard` 头部当 `task.cr_id` 非空且该 CR 有活跃
门禁时显示迷你门禁条（点击滚动到对应 CrGateCard）。

### 5.3 `CrStatusBadge`（DD-7）

模式 TabsList 右侧；16 态 → 颜色分组沿 P0 §4.1 的 7 桶（todo 灰 / in_progress 蓝 /
in_review 琥珀 / done 绿 / cancelled 红），徽标文本 = 16 态四语文案；多 CR popover 全列。
只读（禁止反向约束：不提供任何状态操作）。

### 5.4 locale

新增文案（16 态名 ×4 语、卡片/徽标/按钮/409/403 提示）入 `projects.json` 新 `governance`
子袋（不开新 namespace——parity 测试与 index.ts 四处登记成本不值，调查 §7）。

## 6. 需求评审建议落地

### 6.1 REQ-SUG-001（归因数据级断言）+ FR-2 收窄论证

**收窄**：PRD FR-2 要求"入队时写 cr_id + pipeline_node_run_id"，本设计改为
**cr_id 于 StartTask 后置写入、pipeline_node_run_id 本期恒 NULL**。理由：① 七路入队点
全无 CR 上下文，入队时点归因只能靠调用方自报或猜测；workdir→分支派生发生在开跑时点，
是唯一零猜测来源；② 投影器产生的 gate node_run（human_approval/review）本质上没有对应的
队列任务（审批不是 agent 任务），强行 1:1 关联是虚假数据；真实的 skill 节点任务→node_run
关联只有 Runner 入队时才存在（CR-H）。PRD 技术前提第 3 条已授权"写入挂点 SDD 定案"，
此收窄在授权范围内，验收 AC-1 全链路不受影响（审批链路不依赖队列归因，DD-2）。
**数据级断言**（补测试）：① 集成测试——CR worktree 任务 start 后 SELECT 断言 cr_id 已落、
非 CR 任务恒 NULL；② `pipeline_node_run_id` 全表恒 NULL 断言（防本期出现意外写者）；
③ 与 AC-5 的 NULL 侧对称。

### 6.2 REQ-SUG-002（多 CR 徽标）

定案 = DD-7（最新活跃非终态 CR + popover 全列）。AC-4 验证方式补边界：同项目造 2 条在途
CR，断言徽标取 `updated_at` 较新者，popover 两条齐全、状态各自正确。

### 6.3 REQ-SUG-003（attempt/blocker 数据来路）

定案 = DD-3 review 事件通道 + `pipeline_node_run.detail` JSONB + 投影器（§4.1/§4.2）。
三候选中弃用另两个：cr 投影扩列（review 明细是节点级不是 CR 级，放 cr 行语义错位）、
审批 API 透出（approval card 只有 digest 指纹没有 blocker 正文，服务端无 git 内容可读）。
唯一能拿到 blocker 正文的位置是 daemon（有 worktree），故走扫描通道随事件上报。

## 7. FR → 设计映射

| FR | 落点 |
|---|---|
| FR-1 B4 迁移 | §3（migration 161 四段 + retry 克隆清单 + claim 不动声明） |
| FR-2 最小归因 | DD-4 + §4.5 + §6.1（收窄论证） |
| FR-3 门禁状态条 | §5.2（CrGateCard 时间线元素 + TaskExecutionCard 迷你条） |
| FR-4 审批卡 | DD-2/DD-5 + §4.3/§4.4 + §5.2 审批变体 |
| FR-5 blocker/reviewLoop | DD-3 + §4.1/§4.2 + §5.2 blocked 变体 |
| FR-6 16 态徽标 | DD-7 + §4.3 + §5.3 |

## 8. 风险与回归面

| 风险 | 缓解 |
|---|---|
| review commit message 措辞漂移致扫描 miss | 正则只锚前缀段；miss 的后果 = blocked 卡缺失但审批卡不受影响（DD-2 独立）；本仓 commit 约定已在 AGENTS.md 固化，后续可升稳定契约 |
| 并行 CR-B~E 同期抢 migration 161 编号 | 合并序重号（lint 测试强制唯一，冲突编译期即爆）；CUSTOM.md 登记时间即认领 |
| `git show` 读 yml 失败（编码/路径） | BAD_EVENT 进 dead 不阻塞批次；投影缺失仅降级增强信息 |
| approvalSvc 未配置环境（404） | DD-8 降级路径 + 单测覆盖 disabled 分支 |
| HandleApprove 加角色策略影响已交付 API 行为 | 语义收紧是 PRD FR-4 明确要求；对既有调用方零影响（前端调用方本就不存在，daemon 不调该端点）；grant/409/幂等语义回归单测 |
| 投影器与 Runner（CR-H）未来双写者冲突 | UNIQUE(run_id,node_id,attempt) upsert 幂等；CR-H 接手时投影器按事件源优先级让位（已写入后续规划文档） |
| StartTask 归因误判（非 CR 分支命名撞车） | 服务端 cr 表存在性校验兜底；校验不过静默忽略 |

## 9. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 核心链路 | 真机 E2E：本 workspace 真实 CR 走 requirement 段——review pass → advance → 事件回流 → 聊天窗口出现审批卡 → 网页批准 → grant 签发（approval_record SELECT）→ daemon 落盘 .crctl/grants → `crctl approve --grant` 验签级联 advance → cr:updated → 卡片转历史条；全程无 TTY |
| AC-2 驳回 | 网页驳回填 reason → grant(decision=reject) → 状态回退转移 → review_feedback 注入修复节点（worktree 文件核对）→ 修复后重审 attempt 递增（blocked 卡 N/3 变化） |
| AC-3 blocker | 构造 verdict=block 的 review commit → 扫描 → 投影 → blocked 卡 blocker 列表与 review-annotations yml 逐字段一致 |
| AC-4 徽标 | crctl advance 后徽标 WS 实时变化（无刷新）；16 态逐态截图核对；多 CR 边界按 §6.2 |
| AC-5 迁移回归 | 七路入队 + claim + 撤回 + 容量守卫回归全绿；存量/非 CR 任务两列 NULL（SELECT）；retry 克隆保留 cr_id；ON DELETE SET NULL 实测 |
| AC-6 安全回归 | mat_ 令牌 POST approve → 403（既有单测保持绿）；篡改证据后批准 → 409 呈现指纹对比；非授权成员 gates 响应 can_approve=false 且 UI 无按钮、直接 POST → 403 FORBIDDEN_APPROVER |
| AC-7 双端/locale | web + desktop 目视回归；parity 测试全绿 |
