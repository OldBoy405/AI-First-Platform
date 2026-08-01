---
id: CR-2026-006-TASK-06
type: TASK
cr-ref: CR-2026-006
plan-ref: "change-requests/CR-2026-006/plan.md"
sdd-ref: "change-requests/CR-2026-006/sdd.md"
title: 端到端验收（AC-1~7）
slug: e2e-acceptance
status: pending
estimate: 5h
depends-on: [CR-2026-006-TASK-02, CR-2026-006-TASK-04, CR-2026-006-TASK-05]
assignee: ""
created: "2026-08-02T01:15:00+08:00"
---

## 任务描述
对真机部署跑 PRD §5 的全部 7 条验收标准，按 SDD §9 的验证方式执行；三条技术评审建议
（TSUG-001/002/003）在各自对应 AC 中显式验证，不单独另立验收项。

## 验收执行清单
- **AC-1**（骨架）Chat tab 进入/切换（devtools 网络面板证零请求）/`?tab=` 深链/草稿刷新保留/
  web+desktop 双端一致。
- **AC-2**（闭环）真机 E2E：发消息→守卫→comment 落库（SELECT 只读核对）→入队→claim→执行卡
  流式渲染→完成回复；**顺带验证 TSUG-002**——构造同一 team agent 下群聊任务与 1:1 chat 任务
  同时排队，claim 顺序体现同优先级（2），无持续插队现象。
- **AC-3**（回放）刷新后 timeline 全量回放（含执行卡）；顶部"暂无更早消息"。
- **AC-4**（满队）`settings.team_agent_queue_limit` 压到 1（D1 配置端点）构造满队：
  普通成员 429+禁用+不落库（SELECT 核对），owner 正常入队；释放后恢复；**顺带验证 TSUG-001**——
  并发发送触发内部 guard 竞态时正确返回 429（而非误报 502），补偿删除的评论不残留。
- **AC-5**（容器隔离）逐入口核对 SDD §6.1 全量清单：列表/看板/泳道/甘特/my-issues/全局搜索
  （含 comment 内容搜索验证不泄漏）/项目统计数；通知侧验证容器 Issue 无订阅推送。
- **AC-6**（回归）locale parity 测试 + 浮窗/全页 chat/Issue 页评论 @提及路径回归 +
  `IssueSurface` 四 modes 目视回归（Tabs 包裹未破坏既有布局）。
- **AC-7**（模型选择器）有 Runtime：下拉与 runtimes 页一致、owner 改模型后 agent 配置生效
  （SELECT 核对）；无 Runtime：引导文案+发送禁用；**顺带验证 TSUG-003**——分别以"有编辑权限"
  与"无编辑权限"两种身份验证文案区分正确（只读徽标 vs 引导文案不混淆）。

## 实现要点
- AC-1 类型验收全部使用只读 SELECT 核对数据库状态，不做任何手工写入（沿全 CR 系列约定）。
- 验收报告写入 `change-requests/CR-2026-006/test-report.md`，逐条 AC 记录通过证据；若发现
  SDD/PRD 未预见的边界（参照 CR-2026-005 AC-1 真机重放发现真实 bug 的先例），需在报告中
  明确记录并评估是否需要 SDD 补丁。
