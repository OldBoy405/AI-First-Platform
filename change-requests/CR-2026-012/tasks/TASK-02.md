---
id: CR-2026-012-TASK-02
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: 触发过滤改造：discussion 分支两类并集 + exemption 测试扩展
slug: dc-trigger-filter-two-classes
status: pending
estimate: 4h
depends-on: [CR-2026-012-TASK-01]
assignee: ""
created: "2026-08-03T18:45:31+08:00"
---

## 任务描述
落地 SDD §4.1（含 SDD-BLOCK-001 修正后的两类并集）：`computeCommentAgentTriggers` 的
`project_discussion` 短路从"全拒"改为"未配置 DC 全拒；已配置则计算后过滤保留两类并集"。

## 涉及文件
- `server/internal/handler/comment.go`（:1579-1590）：短路块改造——读
  `projectDiscussionCoordinatorID`（T01）；未配置 → `return nil` 原样；已配置 →
  正常计算 triggers 后过滤：①目标为 DC 的触发（激活）∪ ②作者为 DC 且目标为项目
  `team_agent_id` 的显式提及触发（路由，交 T03 消费）；DC @DC 自触发（作者=目标）排除
- `server/internal/handler/discussion_trigger_exemption_test.go`：既有 5 用例全量保留
  （未配置 DC 场景）+ 新增 6 分支：@DC 放行 / 成员 @第三方 agent 拒 / 正文纯文本 DC
  名字不触发 / DC 作者 @团队Agent 放行 / DC 作者 @第三方 agent 拒 / DC @DC 拒

## 实现要点
- 4 个调用点（comment.go:1150/1358/2294、daemon.go:2730）自动继承，不逐点改。
- @DC 激活仍过既有 `canInvokeAgent`（comment.go:1696），不新增鉴权逻辑。
- `team_agent_id` 读取与 DC id 读取同一次 project settings 取数（性能注意，SDD §8）。

## 验收条件
1. exemption 测试 11 分支（5 旧 + 6 新）全绿。
2. 普通 Issue 的 comment 触发单测全量回归零变化（分支外零改动自证）。

## 完成标志
测试全绿 + lint 零报错 + 改动 diff 确认限定在 discussion 分支与新增过滤函数内。
