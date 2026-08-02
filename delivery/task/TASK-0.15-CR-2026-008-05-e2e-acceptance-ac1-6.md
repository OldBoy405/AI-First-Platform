---
id: CR-2026-008-TASK-05
type: TASK
cr-ref: CR-2026-008
plan-ref: "change-requests/CR-2026-008/plan.md"
sdd-ref: "change-requests/CR-2026-008/sdd.md"
title: 端到端验收 AC-1~6（隐私抓包首要）
slug: e2e-acceptance-ac1-6
status: done
estimate: 5h
depends-on: ["CR-2026-008-TASK-02", "CR-2026-008-TASK-03", "CR-2026-008-TASK-04"]
assignee: ""
created: "2026-08-02T11:25:00+08:00"
spec-id: ai-first-platform
version: "0.15"
---

# TASK-05 — 端到端验收

## 任务描述

按 PRD §5 / SDD §9 跑全量 AC，产出 test-report.md。AC-1 隐私抓包是本 CR 首要验收对象。

## 验收条件（= PRD AC，验证方式按 SDD §9）

1. **AC-1 隐私（首要）**：双浏览器 A/B 同项目，A 走 Private Ask 全流程，B 端 devtools WS 帧
   逐条核对无任何 A 会话相关帧（chat:message/chat:done/task:*）；A 第二设备正常收到；
   **加测 Team Agent 任务并行场景**（task:message 路径，SUG-001 清单的兜底验证）。
2. **AC-2 并行**：Team Agent 长任务运行中 Private Ask 正常问答；D1 满队（limit=1）不影响
   Private Ask；两面状态互不串扰。
3. **AC-3 Ask-only 真机**：Private Ask 要求 agent 改项目文件/checkout repo → checkout 被拒、
   无 worktree 写入、git status 干净；UI 无切换控件；全局 1:1 chat checkout 不受限（对照组）。
4. **AC-4 三处隔离**：项目 X / 项目 Y / 全局 chat 三处会话互不出现、上下文互不串、
   刷新后多轮延续（SELECT project_id 核对归属）。
5. **AC-5 迁移回归**：存量库 M1 up/down；浮窗/全页 chat 全量回归（含 TASK-02 回归清单）；
   Team Agent 面回归。
6. **AC-6 输入区/状态/双端/四语**：SDD §6.3 TaskStatusPill 检查单①-④（pill 流转/停止保留
   内容/无越权入口/无 Runtime 引导）+ 附件/@提及 + web/desktop + parity。

## 完成标志

test-report.md 落盘（含 AC 逐项结果、抓包证据摘要、回归清单勾选），全部 AC 通过或残余项
经需求 owner 书面豁免。
