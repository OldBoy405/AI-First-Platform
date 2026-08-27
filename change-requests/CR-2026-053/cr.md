---
id: CR-2026-053
title: 独立评审与人工审批命令闭环 — 评审独立路由与审批卡可见性修复
summary: "依据《独立评审与人工审批命令闭环设计》（docs/product v0.4，触发于 CR-2026-052 作者自评逃逸与 CR-2026-051/052 审批卡不可见）注册。一个 CR 覆盖两条独立工作轨：(1) tools 侧——四个 CR 评审 Skill（review-requirement/review-tech-design/review-dev-plan/review-code）唯一 owner 收敛为 quality-reviewer-agent，作者型 Agent（requirement-writer/dev-agent）改为委派路由合同（创建独立 reviewer 任务、只消费 blocker 回修），三条 CR Pipeline 的 review 节点 prompt 明确要求新建独立 quality reviewer 运行；不修改 Pipeline schema、状态机、gates、review-record/approve 协议；(2) Multica 侧——新增 task-scoped 窄接口 bind-current-task-to-cr 在评审时点原子绑定 task→CR→Issue（写 agent_task_queue.cr_id 与 cr.shell_issue_id + activity_log，CAS 不覆盖），前端 gates 改为 pending_stage 非空即渲染唯一 ApprovalCard（提取 ApprovalCard 组件，保留 blocker 与历史节点）；存量 CR-2026-051/052 用同一接口经受控 task 人工绑定，禁用直接 SQL。明确排除：registration-origin 签名、run attestation、新账本、新状态机、can-delegate、Pipeline schema 改造、crctl review 包装命令等。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-27T17:30:20+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-27T17:30:20+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-27T17:30:20+08:00"
target-version: tbd
source: "docs/product/独立评审与人工审批命令闭环设计.md"
origin: ""
status: requirement-approved
created: "2026-08-27T17:30:20+08:00"
updated: "2026-08-27T19:20:10+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-27T17:30:20+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-27T17:30:20+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-27T17:30:20+08:00", reason: initial-assignment }
handover-history: []
---
