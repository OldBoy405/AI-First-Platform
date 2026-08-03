---
id: CR-2026-012-TASK-08
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: 端到端验收：AC-1~8 全场景（含 DC 只读审计与升级 CR 实跑）
slug: e2e-acceptance-ac1-8
status: pending
estimate: 6h
depends-on: [CR-2026-012-TASK-03, CR-2026-012-TASK-06, CR-2026-012-TASK-07]
assignee: ""
created: "2026-08-03T18:45:31+08:00"
---

## 任务描述
按 PRD §5 与 SDD §10 的验证方式跑通 AC-1~8 全场景，产出 test-report 证据。

## 涉及文件
- 无新代码（验收期发现的缺陷回对应 TASK 修复）；证据落 test-report.md + test-evidence/

## 验收场景（依 SDD §10）
1. **AC-1 静默边界**：未配置 DC 项目 + 已配置项目各发普通消息/纯文本含 DC 名字消息 →
   `agent_task_queue` 零增量（DB 级，CR-2026-009 AC-3 口径复验）。
2. **AC-2 激活与可见输出**：@DC → 入队（ask_only=true）→ 完成 → 容器出现 agent comment，
   双浏览器实时；trivial 输出边界用例（DD-4 豁免生效）；审计 work_dir 无写入、checkout 拒。
3. **AC-3 路由**：DC 输出 @团队Agent → chat 容器路由 comment + 任务，Team Agent 面可见
   并执行；满队 → discussion 容器 system comment。
4. **AC-4 合并转发**：多选 N 条 → 预览 → 1 comment + 1 task，claim 的
   TriggerCommentContent 含完整合并结构；取消零副作用；429 预览保留。
5. **AC-5 升级 CR**：register_cr=true → Team Agent 执行 requirement-register →
   knowledge-base 仓出现合规 CR 壳并回报 CR-ID；false/有在途 gate 默认不勾 → 无指令块。
6. **AC-6 解耦锁定**：双重锁定单测 + 既有 chat-input 测试全绿（T05 产物复核）。
7. **AC-7 回填**：附件/仅成员提及/富文本 + 跨项目跨模式隔离真机。
8. **AC-8 回归**：parity；CR-D Discussion / CR-A Team Agent / CR-C Private Ask /
   浮窗全页 chat；presenter 与容量守卫（merge-forward 同链路）；approvalSvc 未配置环境冒烟。

## 完成标志
AC-1~8 全部通过并留证（test-report.md 按 crctl test 骨架，DB 断言/截图/审计输出落
test-evidence/）；发现缺陷全部闭环或降级留痕。
