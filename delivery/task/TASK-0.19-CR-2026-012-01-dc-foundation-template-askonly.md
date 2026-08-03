---
id: CR-2026-012-TASK-01
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: DC 基座：agenttmpl 模板 + settings 读取 + AskOnly claim 规则 + trivial 抑制豁免
slug: dc-foundation-template-askonly
status: done
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-03T18:45:31+08:00"
spec-id: ai-first-platform
version: "0.19"
---

## 任务描述
落地 SDD DD-1/DD-3/DD-4 的 DC 基座四件：模板、绑定读取、只读沙箱规则、输出保真豁免。
零 migration（绑定走 project.settings JSONB 新 key）。

## 涉及文件
- `server/internal/agenttmpl/templates/discussion-coordinator.json`（新）：沿既有 25 模板
  schema（Slug/Name/Description/Category/Icon/Accent/Instructions/Skills）；Instructions
  按"只协调不执行 + 输出实质性总结 + 路由用显式 @{team agent} 提及"编写；Skills 仅
  `mentioning`（builtin）
- `server/internal/service/project_chat.go` 或 handler 侧对应位置：新函数
  `projectDiscussionCoordinatorID(ctx, projectID)` —— settings JSONB 读 key
  `discussion_coordinator_agent_id`，读法照抄 task_queue_capacity.go:100-114
  （非法 UUID/缺失 → 零值 = 未配置，fail-safe）
- issue 任务 claim 组装处（handler/agent.go:312-329 响应体对应 handler）：任务 issue
  `origin_type == 'project_discussion'` → `resp.AskOnly = true`（chat session 路径
  daemon.go:1846 的既有判定不动）
- `server/internal/service/task.go`（:1951 附近）：`isTrivialDoneOutput` 抑制对
  discussion 容器任务豁免（一行容器判定，需 issue origin 可得；取现场已有 issue 或
  单行 GetIssue）

## 实现要点
- 模板创建后是普通 agent 行；绑定 `permission_mode=public_to` + workspace target 由
  创建流程/文档说明（canInvokeAgent 才放行全员 @）。
- AskOnly 规则按**容器**而非按 agent（SDD §4.4：discussion 容器上任何任务只读）。
- 豁免的语义注释：保证"DC 激活必有可见输出"是机制而非 prompt 约定（评审 TSUG-002）。

## 验收条件
1. 单测：settings 含合法 UUID → 返回该 id；缺失/非法 → 零值；不 panic。
2. 单测：discussion 容器 issue 任务 claim 响应 `ask_only=true`；普通 issue 任务不受影响；
   checkout 拒绝路径沿 health_test.go:437 形态补 discussion 容器用例。
3. 单测：discussion 容器任务 CompleteTask 输出为 trivial（如 "done"）仍落 agent comment；
   普通 issue 任务 trivial 抑制行为不变。

## 完成标志
上述单测全绿 + 既有 agenttmpl 加载测试通过（新模板 JSON schema 合法）+ lint 零报错。
