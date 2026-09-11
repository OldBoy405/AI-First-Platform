---
id: CR-2026-063
title: CR-P0 流程正确性止血 — `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化
summary: "删除 `_context.md` 全部活跃合同（Prompt、post-review 白名单、既有测试原位退役）；公共 Agent Prompt 事实源归位 `tools/agents/`、coordinator 保留 Multica overlay；收紧 coordinator 与 dev 委派合同（只传事实与 canonical 引用、冲突报 `CONTRACT_DRIFT`）；`gate --mode pre-review` 错配补 stage 专属恢复方向与 `contractDrift`；`review-loop reset` 改原子提交；补清 `review-record` payload 的 YAML 子集边界。不新增 SLO/M1–M8/P50-P90/计数门禁，不新增 R14 委派 lint，不换 YAML 解析器，不改平台 DB 与 `aifirst/agent-import.mjs`。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-11T16:56:24+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-11T16:56:24+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-11T16:56:24+08:00"
target-version: 0.36
target-spec-id: ai-first-platform
source: AIFI-24
origin: ""
status: tech-design-reviewed
created: "2026-09-11T16:56:24+08:00"
updated: "2026-09-11T23:56:39+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-11T16:56:24+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-11T16:56:24+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-11T16:56:24+08:00", reason: initial-assignment }
handover-history: []
---
