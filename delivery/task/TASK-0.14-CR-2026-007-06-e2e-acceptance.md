---
id: CR-2026-007-TASK-06
type: TASK
cr-ref: CR-2026-007
plan-ref: "change-requests/CR-2026-007/plan.md"
sdd-ref: "change-requests/CR-2026-007/sdd.md"
title: 端到端验收（AC-1~6）
slug: e2e-acceptance
status: done
estimate: 4h
depends-on: [CR-2026-007-TASK-02, CR-2026-007-TASK-04, CR-2026-007-TASK-05]
assignee: ""
created: "2026-08-02T13:10:00+08:00"
spec-id: ai-first-platform
version: "0.14"
---

## 任务描述
按 PRD 0.1.3 的 AC-1~6 全场景真机验收，产出 test-report.md。验收纪律沿 CR-A：
数据库**只 SELECT**；造数走真实 API；本机无 daemon runtime 时用 synthetic runtime
做 API 级验证并如实标注覆盖边界。

## 验收清单（对 PRD AC 逐条）
1. **AC-1 实时可见**：双浏览器（A=成员、B=另一成员），A 连发两条入队，B 无手动刷新
   看到计数与列表变化（发起人=A）；第一条开跑后计数-1；owner 插队项排前真机核对。
2. **AC-2 撤回三路径**：A 撤自己 queued 项 → 列表移出/计数-1/DB `status='cancelled'`
   行保留（SELECT）；B 对 A 的项无按钮，直接调 API → 403；竞态：对已完成任务调
   cancel → 幂等 200+原状态，前端提示「任务已结束」；**private Team Agent 配置下
   A 撤自己的项 → 200**（T02 靶点，真机核）。
3. **AC-3 停止双权限 + 被停者对账**：A 停自己 running → interrupted 徽标、已生成内容
   保留、下一条自动开始；owner 停 A 的任务 → **在 A 的浏览器**断言：运行卡变
   interrupted、队列条计数/列表同步（无幽灵状态）；普通成员经 API 停他人 → 403。
4. **AC-4 过滤开关**：≥2 轮请求+多工具卡的流；开启 → DOM 无 TimelineView 节点、
   DevTools 无新请求、`result.output` 文本正确；关闭还原；往返多次；刷新后开关保留。
5. **AC-5 兼容与口径**：无参 queue-status 与改动前对拍一致；D1 sidebar 指示、CR-A
   满队 429/恢复回归；Issue 页 @提及入队的任务出现在 items（非群聊来源覆盖）；
   NULL originator 系统任务计入且占位显示。
6. **AC-6 回归**：复制取全文；locale parity 全绿；views/core/server 测试套件全绿；
   浮窗/全页 chat、任务详情页停止入口行为不变。

## 产出
`change-requests/CR-2026-007/test-report.md`（frontmatter status 按 crctl 门禁要求），
每条 AC 附证据（SELECT 结果/断言输出/截图说明），未覆盖段如实标注。
