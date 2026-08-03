---
id: CR-2026-012
title: P2 三模式聊天 CR-G — D8 DC 协调者 + 讨论转执行（合并转发）
summary: >-
  D8 DC 协调者 + 讨论转执行（交付切分 v2 的 CR-G，自研设计定位，依赖 CR-D/CR-A）：
  ① DC 特殊 Agent——默认静默，@提及或回复激活；只协调不执行（execenv 只读 +
  forbidden 全部写 Skill）；可 EnqueueTaskForMention 路由到 Team Agent。
  ② 合并转发——多选 Discussion 消息合并为带 triggerMessage + chatHistory 汇总
  结构的 Team Agent 任务；无 CR 时可触发 requirement-register 升级为 CR。
  设计阶段必须先定两件事（切分文档 0.3 两处偏差）：DC 输出可见性（本文预设可见
  协调输出，审计要求，与 CodeBanana 静默协调器不同）；合并转发是本平台增量
  （CodeBanana 只有逐条转发），需自行设计多选态与合并预览。
  ③ ChatInput 解耦技术债（方案 A，随本 CR 一并偿还，纯前端）：新增可选 prop
  draftAdapter?: ChatInputDraftAdapter（draftKey/editorKey/draft/attachments +
  四个写方法），未传时落回默认实现（读 useChatStore，/chat 页与浮窗零改动）；
  传入时完全按 adapter 渲染/回写不触碰 useChatStore。回填 Team Agent 面与
  Private Ask 面（补附件/@提及仅成员，接 project-chat-store 的 {projectId}:{mode}
  命名空间）；新增单测锁定"自定义 adapter 时不触碰 useChatStore"。技能选择器
  排除（独立缺口，文档 §7 另议）。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-03T14:55:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-03T14:55:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-03T14:55:00+08:00"
target-version: "0.19"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-G；docs/product/P2-ChatInput组件与全局store解耦-技术债务.md §4.1 方案A"
status: requirement-approved
created: "2026-08-03T14:55:00+08:00"
updated: "2026-08-03T17:45:21+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-03T14:55:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-03T14:55:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-03T14:55:00+08:00"
    reason: initial-assignment
handover-history: []
---
