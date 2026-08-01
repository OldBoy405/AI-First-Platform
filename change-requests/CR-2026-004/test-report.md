---
id: CR-2026-004-test-report
type: TEST-REPORT
cr-ref: CR-2026-004
title: Team Agent 共享队列容量上限 — 端到端验收报告
status: pass
created: "2026-08-01T11:00:00+08:00"
---

# CR-2026-004 端到端验收报告

## 环境

- backend 镜像 `d2c68b46ecc2`（multica worktree@da03782a8 构建，VERSION=dev-cr2026004），迁移 159 由新后端启动时干净应用（`schema_migrations` 首行 `159_project_settings`；此前手工试验列已先 DROP 再交由迁移器执行）。
- 前端镜像 `2f985eebbc7a`（同 worktree 构建）已部署（multica-web:dev）。
- daemon：验收编排需要控制 claim 时机——fixture 造数阶段停止 daemon（任务停留 queued），AC-2 观察阶段重启（原本即在运行，验收后保持运行，状态还原）。
- 验收工作区：`test`（4dc186f0），项目 `CR-2026-004 acceptance`（c9b9391f）。**全程数据库只 SELECT**；造数走真实 API（issue 创建/指派、quick-create、cancel、项目设置、成员邀请全链路），第二个用户（member 角色）经 send-code → SELECT 验证码 → verify-code → 邀请 → accept 全 API 建立。

## 验收结果

### AC-3 上限可配置 ✅
- 未配置项目 `GET /api/projects/{id}/queue-status` → `{"queue_depth":0,"queue_limit":50}`（默认 50）。
- owner `PUT /api/projects/{id}` `{"settings":{"team_agent_queue_limit":2}}` → 200，随后 queue-status → `limit:2`。在两个项目上各验证一次（Ray 工作区草稿项目 + test 工作区正式验收项目）。

### AC-1 满队拒绝 ✅
- 队列 2/2 满时，member 创建第三条 agent 指派 issue → **issue 落库、任务被守卫拒绝**：该 issue 的 `agent_task_queue` 行数 = 0，深度稳定 2/2；backend 日志 `02:51:35 INF task enqueue rejected: project queue full issue_id=be680443… error="project queue full: 2/2"`。
- 评论/指派路径是既有 fire-and-forget 结构（TASK-01 已记录），拒绝不阻断 issue 本体——符合实现期修正后的设计。
- quick-create 429 结构化响应：真机上被 runtime 可用性预检（422 `agent_unavailable`，daemon 停机窗口）先行拦截——**可用性预检先于容量守卫是合理次序**；429 响应体形态由真库集成测试 `TestProjectQueueCapacity_MemberRejected` + handler 直连覆盖（同一生产代码路径）。

### AC-2 owner/admin 插队 ✅
- owner 入队自动带 `priority=100`（两条 fixture 任务 SELECT 证据）且满队不受阻。
- **claim 顺序证明**：member 任务（priority 0，02:51:33 创建）先入队，owner 任务（priority 100，02:53:02 创建，晚 90 秒）后入队；daemon 重启后 dispatched_at：owner 任务 `02:55:10.000005` **先于** member 任务 `02:55:10.020623`——`ORDER BY priority DESC, created_at ASC` 插队语义真机生效。观察到 claim 顺序后立即双双 cancel 止损。

### AC-4 撤回软删除 + 审计 ✅
- member 撤 owner 的 queued 任务 → HTTP 403 `{"code":"not_task_originator", ...}`，行未动（复查仍 queued）。
- originator（owner）撤自己的 queued 任务 → 200；行保留 `status='cancelled'`、`completed_at` 有值（SELECT 证据）；queue-status 深度实时 2→1。
- 验收项目最终留存 4 条 cancelled 审计行（无一物理删除）。

### AC-5 WS 实时可见 ⚠️ 部分（降级说明）
- 服务端广播链路（`broadcastTaskEvent` → `task:queued`/`task:cancelled` → workspace 房间）为既有生产通道，本 CR 零改动。
- 前端失效链路（`task:` 前缀事件 → queue-status query 失效重取）由 core/views 组件测试覆盖（3 个组件测试 + 218/66 回归全绿）。
- **双浏览器人工观察未执行**：验收环境无可用浏览器自动化（in-app preview 未启用）。此项列为人工补验项——预期行为：一侧入队/撤回，另一侧项目详情页队列数无刷新自动更新。风险评估：低（链路两端均已分别验证，中间通道为既有能力）。

## 结论

AC-1/2/3/4 真机全过，AC-5 双端分别验证 + 人工补验项挂账。产线部署动作（镜像构建、迁移应用、daemon 重启）全部完成且环境已还原（agent 可见性、杂项目、daemon 运行状态）。
