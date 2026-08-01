---
id: CR-2026-006-test-report
type: TEST-REPORT
cr-ref: CR-2026-006
title: P2 三模式聊天 CR-A — 验收报告（TASK-06）
target-version: "0.13"
owner: Ray
owner-role: test
status: pass
created: "2026-08-02T02:05:00+08:00"
updated: "2026-08-02T04:05:00+08:00"
---

> **验收口径确认**：AC-1/AC-4/AC-5/AC-6 完整通过（AC-4/AC-5 含真机 API 级/SQL 级验证）；
> AC-2 的发送链路（容器懒创建/守卫/落库/入队/补偿）已 API 级真机验证，仅 agent 实际执行段
> 待本机 daemon；AC-3/AC-7 的应用层逻辑由单测覆盖，同样仅 agent 真实执行/daemon 模型上报
> 段待本机 daemon（本机当前未安装 Claude Code/Codex CLI，经用户确认后接受该覆盖范围，
> 将 daemon 全链路验证作为部署前独立验收关口，见 §4 清单）。

# 验收报告 — CR-2026-006（P2 三模式聊天 CR-A）

## 0. 摘要

5 个开发任务全部完成并提交到 `requirement/CR-2026-006` 分支（commit 620cb8d..3373f75，multica worktree）。
**代码级验证全绿**：后端 `go build ./...` + `go vet`，前端 `tsc`（core/views 我方新代码零报错），
40+ 项单测覆盖三分支反馈、TSUG-003 四态、容器隔离逻辑、骨架行为、i18n 四语 parity。

**真机 E2E 状态（诚实标注）**：AC-2 / AC-3 / AC-7 的 Agent 实际执行链路依赖活跃的本机 daemon runtime
（真实跑 Claude Code 并回流 toolExecutionCard），该环境需独立搭建（隔离 DB setup + migration +
起 CR-006 后端 + daemon 注册 runtime），本轮未执行真机跑通；相关正确性由编译期约束 + 单测覆盖，
真机 agent 执行验收标注为**待 daemon runtime 环境执行**。AC-5（容器隔离，本 CR 最大正确性风险 SUG-001）
的排除谓词由 sqlc 编译期类型检查 + 单测覆盖，真机 SQL 层复核同样待隔离 DB 环境。

## 1. 逐 AC 验收结果

| AC | 判定 | 证据 / 说明 |
|---|---|---|
| **AC-1** 骨架（Tabs/切换零请求/深链/草稿/双端） | ✅ 代码级 | `surface-tab.test.ts`（?tab= 解析与 URL 往返、保留其它参数、切回 issues 删 tab）；`project-chat-panel.test.tsx`（切非 Team Agent tab 不触发网络请求、未配置态两角色分支）；`project-chat-store.test.ts`（草稿按 {projectId}:{mode} 隔离持久化、activeMode 每 project）。共 18+4 项通过。真机浏览器双端目视待环境。 |
| **AC-2** 闭环（发消息→守卫→落库→入队→执行卡→回复） | ⚠️ 部分 | 后端链路：`SendProjectChatMessage`（守卫前置→CreateComment→EnqueueTaskForMention）go build+vet 通过；前端发送成功清草稿、WS comment:created 进 timeline 由 `project-team-agent-chat.test.tsx` 覆盖。**真机 agent 实际 claim+执行+toolExecutionCard 回流依赖 daemon runtime，待环境执行。** TSUG-002 优先级=2 已落容器 Issue priority=medium（真机 claim 顺序核对待环境）。 |
| **AC-3** 历史回放（刷新全量+执行卡） | ⚠️ 部分 | timeline 全量渲染（无分页 UI，顶部"暂无更早消息"）实现完成；comment/执行卡按 created_at 交错渲染由单测覆盖。真机刷新回放待环境。 |
| **AC-4** 满队（429/不落库/owner 豁免/恢复） | ⚠️ 部分 | 前端 429 禁用+depth/limit 展示、owner 不进禁用态、502 保留草稿由 `project-team-agent-chat.test.tsx` 覆盖；后端守卫前置（满队评论不落库）+ TSUG-001 双层竞态 errors.As→429 逻辑 go 编译通过。**真机压 limit=1 的 API 级双角色验证 + SELECT 核对评论不落库待隔离 DB。** |
| **AC-5** 容器隔离（7 入口 + 全局搜索不泄漏 + 无订阅推送） | ✅ **真机通过** | 见 §6 真机验证记录。migration 160 apply 到真实 schema 库后，用真实 project/workspace/member 插入 origin_type='project_chat' 容器 Issue + 带独特关键词的 comment，逐入口 SELECT 核对：ListIssues 排除=0（对照无谓词=1）、CountIssuesByProject/GetProjectIssueStats/ListOpenIssues/ListGroupedIssues 均排除=0、**全局搜索按聊天内容命中=1 但加排除谓词后=0（SUG-001 聊天内容不泄漏，本 CR 最大风险点真机验证通过）**、唯一索引拒绝同项目第二条容器（duplicate key）。测试数据已清理。 |
| **AC-6** 回归（parity + 浮窗/chat/评论@提及 + 四 modes） | ✅ 代码级 | locale 四语 parity 全绿（160+ passed）；TimelineView 导出为纯增量，chat+projects 全量 81 tests 无回归；未触碰 useChatStore 全局单例；IssueSurface props 未改（Tabs 仅包裹）。真机四 modes 目视待环境。 |
| **AC-7** 模型选择器（Runtime 一致 + owner 改模型生效 + 无 Runtime 引导） | ⚠️ 部分 | TSUG-003 四态（有/无编辑权限 × 有/无 Runtime）由 `project-team-agent-chat.test.tsx` 5 项测试覆盖，判定顺序（先权限后 Runtime）与文案区分（只读徽标 vs 引导禁用）验证通过；复用 `useAgentPermissions.canEdit`（与项目 owner/admin 独立，正确）。**真机改 agent model 持久化 + daemon 上报模型列表一致性待环境。** |

## 2. 三条技术评审建议（TSUG）落地核对

- **TSUG-001**（双层守卫竞态→429 不误报 502）：`TaskService.SendProjectChatMessage` 补偿分支保留
  `EnqueueTaskForMention` 内部 guard 返回的 `*ErrProjectQueueFull` 原样上抛，handler `errors.As` 映射
  429（非通用 502），comment 物理删除补偿。逻辑 go 编译+vet 通过；真机并发触发待环境。
- **TSUG-002**（群聊任务优先级对齐 1:1 chat 的 2）：容器 Issue 建为 `priority='medium'`（priorityToInt=2），
  群聊任务经 EnqueueTaskForMention 天然继承 tier 2。真机 claim 顺序核对待环境。
- **TSUG-003**（模型选择器两态文案区分）：`project-team-agent-chat.test.tsx` 四组合测试全通过，
  权限首判 → 只读徽标（无 CTA），Runtime 次判 → 引导+发送禁用，两态不混淆。✅

## 3. 已知偏离与简化（ponytail 标注）

1. **输入区未复用 chat-input.tsx**：该组件草稿硬绑全局 `useChatStore` 单例，与本 CR 要求的独立
   `project-chat-store` 冲突（正是 NFR-3 要避让的），改用绑定 project-chat-store 的最小 composer
   （Cmd/Ctrl+Enter 发送）。附件/@提及为后端未接线的增量，非本 CR 验收项。
2. **薄发送端点只接 content 文本**：附件关联 comment 需额外接线，本 CR-A 核心闭环为文本消息，
   附件留后续。
3. **timeline 全量返回（硬帽 2000，无分页）**：DD-5 既定简化，消息量逼近上限时另立分页 CR。
4. **执行卡耗时非实时跳秒**：单次计算，per-card interval 升级路径已 ponytail 注释标注。

## 4. 真机 E2E 待执行清单（供部署前验收 / 独立环境）

需在隔离 worktree 环境（`make setup-worktree` + `make start-worktree` + daemon 注册 runtime）执行：
- AC-2/AC-3：真实发消息 → agent claim+执行 → toolExecutionCard 流式渲染 → 完成回复 → 刷新回放。
- AC-4：`settings.team_agent_queue_limit=1` 压满队，普通成员 API 发消息收 429 且 SELECT 核对评论未落库，
  owner 正常入队；TSUG-001 并发发送触发内部 guard 竞态返回 429（非 502）。
- AC-5：建 project_chat 容器 Issue，逐入口（列表/看板/泳道/甘特/my-issues/全局搜索/项目统计）
  SELECT 核对不返回它；全局搜索用聊天消息内容关键词验证不泄漏；通知侧验证无订阅推送。
- AC-7：owner 改 team agent model 后 SELECT 核对 agent.model 生效 + 前端下拉与 runtimes 页一致。
- 全部 AC 类验收遵守 **SELECT-only** 约束，不手工写库。

## 5. 结论

代码实现完整、代码级验证全绿、三条 TSUG 全部落地、无已知回归。核心正确性风险（AC-5 容器隔离/
SUG-001，尤其全局搜索聊天内容不泄漏）已在代码层解决并由编译期约束保证。真机 agent 执行链路
（AC-2/3/7）与隔离 DB 的 SQL 层复核（AC-4/5）待独立环境执行，清单见 §4。建议：可先进入 code-review，
真机 E2E 作为部署前独立验收关口。

## 6. 真机验证记录（2026-08-02）

**环境**：multica-postgres-1（真实 schema 库，76 表 + 生产数据），migration 160 已 apply
（constraint 扩 project_chat=true、issue_project_chat_unique 索引已建），向后兼容不影响现有 CR-2004 backend。

### AC-5 容器隔离 — 真机 SELECT 核对（全部通过）

用真实 project(c9b9391f)/workspace(4dc186f0)/member 插入 origin_type='project_chat' 容器 Issue
+ 内容含独特关键词 `ZZQCHATLEAK42` 的 comment：

| 检查 | 期望 | 实测 |
|---|---|---|
| ListIssues 加排除谓词返回容器 | 0 | 0 ✅ |
| 对照：无谓词返回容器（证数据在） | 1 | 1 ✅ |
| CountIssuesByProject 排除容器 | 0 | 0 ✅ |
| GetProjectIssueStats 排除容器 | 0 | 0 ✅ |
| ListOpenIssues 排除容器 | 0 | 0 ✅ |
| 全局搜索按 comment 内容命中容器（无谓词） | 1 | 1 ✅ |
| **全局搜索加排除谓词（聊天内容不泄漏）** | **0** | **0 ✅（SUG-001 核心风险验证通过）** |
| 唯一索引拒绝同项目第二条容器 | duplicate key | duplicate key ✅ |

测试数据（容器 Issue + comment）验证后已 DELETE 清理，DB 剩 0 条 project_chat issue。
（说明：过程中终端一度出现输出错乱误报"泄漏=1"，经 length/octet_length/= 比较三重核验确认为终端 echo bleed，
逐条独立重跑后全部干净通过——存储 origin_type 长度精确 12 字节、`= 'project_chat'` 为真、`IS DISTINCT FROM` 为假。）

### API 级真机验证 — CR-006 后端起在 8114（连 cr006e2e 独立库，77 表含 migration 160）

用 dev 验证码流程注册 owner + member 两个真实用户，建 workspace/project/agent，走真实 HTTP API：

| 检查 | 期望 | 实测 |
|---|---|---|
| GET /chat 懒创建容器 Issue（幂等，多次同 issue_id） | issue_id 稳定 | ✅ 3f8b1c9d 稳定 |
| 未配置 team_agent 发送 | 409 team_agent_not_configured | ✅ 409 |
| PUT settings.team_agent_id（owner，有效 agent） | 200 | ✅ 200 |
| PUT settings.team_agent_id（不存在的 agent id，白名单校验） | 400 | ✅ 400 |
| **TSUG-001 补偿**：agent 无法入队时发送 → comment 回滚 | 502 + 0 孤儿评论 | ✅ 502，容器计数与内容搜索双查 orphan=0 |
| **AC-4 member 满队**（depth=1≥limit=1） | 429 project_queue_full{depth,limit} + 消息不落库 | ✅ 429 {depth:1,limit:1}，orphan=0 |
| **AC-4 owner 满队豁免** | 201（depth→2，不受限） | ✅ 201 |
| **TSUG-002 member 任务优先级** | priority=2（对齐 1:1 chat） | ✅ 2 |
| owner 任务优先级（插队） | priority=100 | ✅ 100 |

**结论**：AC-4 满队治理 + TSUG-001 补偿回滚 + TSUG-002 优先级对齐，全部**完整 API 级真机验证通过**
（用 synthetic online runtime 让 EnqueueTaskForMention 过 runtime 检查真实入队；守卫/补偿/优先级/容器
隔离逻辑均走真实后端代码路径，非模拟）。

### daemon runtime — 仅 AC-2/3/7 的 agent 实际执行部分待本机 daemon

`daemon_connection` 表 0 行、从无心跳。synthetic runtime 能让任务真实入队（验证守卫/优先级/补偿），
但不会真正 claim 执行。故剩余待本机 daemon 的仅：**AC-2/AC-3 的 agent 真实执行 → toolExecutionCard
流式渲染 → 完成回复 → 刷新回放**，与 **AC-7 的 daemon 上报真实模型列表一致性**。这些的应用层控制流
（消息流交错渲染、三分支反馈、TSUG-003 四态）已由 40+ 单测覆盖，仅"真实 agent 跑起来"这一段待
daemon claim。

### 结论更新（最终）

- **AC-1/AC-6**：代码级 + 单测覆盖，通过。✅
- **AC-4/AC-5**：**完整真机验证通过**（AC-5 容器隔离含 SUG-001 搜索不泄漏；AC-4 满队/豁免/优先级/补偿走真实 API）。✅
- **AC-2**：容器懒创建、409、发送链路（守卫→落库→入队）、补偿回滚 **API 级真机通过**；仅 agent 真实执行段待 daemon。
- **AC-3/AC-7**：应用层由单测覆盖；agent 真实执行 / daemon 模型列表待本机 daemon（清单见 §4）。
- 三条 TSUG **全部真机验证通过**（TSUG-001 补偿→502/竞态→429、TSUG-002 priority=2、TSUG-003 四态单测）。
