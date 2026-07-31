---
id: CR-2026-002
title: P1 治理核心 — crctl 接入（同步协议 · 签名审批 · controlled-shell 下沉）
summary: 基于 P0 权威域划分（git 权威 / PG 投影），落地 CR 事件从 git 到 Multica 投影表的三层同步链路（crctl outbox + commit 扫描兜底 + reconcile 对账）、Ed25519 签名审批替代 TTY（强度不降级，含 EVIDENCE_DRIFT 两轨统一与留证）、controlled-shell 白名单下沉 daemon execenv（rules.json 单一事实源 + pkg/gitguard + AI 行为审计），交付 D1-D7 七项。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-07-31T07:17:01+08:00"
  development:
    id: Ray
    assigned-at: "2026-07-31T07:17:01+08:00"
  test:
    id: Ray
    assigned-at: "2026-07-31T07:17:01+08:00"
target-version: "0.11"
source: docs/product/P1-crctl接入设计.md
status: tech-design-review-pending
created: "2026-07-31T07:17:01+08:00"
updated: "2026-07-31T07:17:01+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-07-31T07:17:01+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-07-31T07:17:01+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-07-31T07:17:01+08:00"
    reason: initial-assignment
handover-history: []
---

# CR-2026-002 — P1 治理核心

来源方案：[docs/product/P1-crctl接入设计.md](../../docs/product/P1-crctl接入设计.md)（前置：P0-数据模型映射表.md，已随 CR-2026-001/M0 验证过 Agent 导入半边）

## 范围（对应源方案 §D 交付切分）

| 序 | 交付物 | 依赖 |
|---|---|---|
| D1 | crctl outbox（advance/approve/git push 三挂点） | — |
| D2 | daemon crevents.go + POST /api/daemon/cr-events + 服务端 worker | D1 |
| D3 | reconcile 对账（server / daemon 两模式） | D2 |
| D4 | 签名审批：approval_record + grant 签发 API + crctl approve --grant + 私钥存储落地 | D2 |
| D5 | rules.json 抽取 + pkg/gitguard + execenv 四处改造 | 独立可并行 |
| D6 | AI 行为审计（gitguard 拒绝事件上报 + 工具调用摘要持久化） | D5 |
| D7 | EVIDENCE_DRIFT 留证（TTY 路径统一 evidence-digest 字段 + 漂移事件落 activity_log） | D4 |

## 备注

- 上游回馈候选：D1（outbox）、rules.json 抽取、EVIDENCE_DRIFT/server-approve 扩展属 tools 通用增强；gitguard 与 execenv 改造留在 multica fork。
- 已知前置缺口：三仓均无可用远端（push 无落点），A.5 reconcile 的 server 模式依赖内网 git 远端凭据——需求编写期需明确远端选型或降级为 daemon 模式。
