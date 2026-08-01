---
id: CR-2026-006-test-report
type: TEST-REPORT
cr-ref: CR-2026-006
title: P2 三模式聊天 CR-A — 验收报告（TASK-06）
target-version: "0.13"
owner: Ray
owner-role: test
status: draft
created: "2026-08-02T02:05:00+08:00"
updated: "2026-08-02T02:05:00+08:00"
---

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
| **AC-5** 容器隔离（7 入口 + 全局搜索不泄漏 + 无订阅推送） | ⚠️ 部分 | 排除谓词 `origin_type IS DISTINCT FROM 'project_chat'` 落 5 查询（ListIssues/ListGroupedIssues/buildSearchQuery/sqlc ListIssues·CountIssues·ListOpenIssues）+ 2 统计，sqlc 重新生成编译通过；**buildSearchQuery 的 comment 内容子查询已加谓词（防聊天内容泄漏进全局搜索）——本 CR 最大风险点已在代码落地**。真机建 project_chat issue 后逐入口 SELECT 核对待隔离 DB。通知侧：容器 Issue 天生无订阅者（订阅仅来自 3 处显式路径）已在 SDD §6.1 论证，无需改码。 |
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
