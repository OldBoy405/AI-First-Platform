---
id: CR-2026-002-plan
type: PLAN
cr-ref: CR-2026-002
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: P1 治理核心 — 开发计划
target-version: "0.11"
status: draft
created: "2026-07-31T09:30:00+08:00"
updated: "2026-07-31T09:30:00+08:00"
---

# 开发计划 — CR-2026-002

## 1. 里程碑

| 里程碑 | 内容 | 任务 | 估算 |
|---|---|---|---|
| M-A tools 地基 | rules.json 事实源、outbox、digest 统一+grant 验签（全部纯 tools，可并行先行） | T01/T02/T03 | 28h |
| M-B 投影链路 | 迁移+状态机副本 → 服务端 worker+端点 → daemon 采集器 → reconcile | T04→T05→T06/T07 | 44h |
| M-C 签名审批 | 服务端签发+私钥方案+下发，与 T03 的 crctl 侧对接 | T08 | 16h |
| M-D 下沉与审计 | gitguard+execenv → 行为审计+漂移留证 | T09→T10 | 24h |
| M-E 端到端验收 | AC-1..7 串联冒烟与证据记录 | T11 | 8h |
| 合计 | | 11 tasks | **120h** |

## 2. 任务依赖图

```
T01 rules.json ──────────────► T09 gitguard+execenv ──► T10 行为审计
T02 outbox ──────────┐                                    ▲
T03 digest+grant ────┼──► T06 daemon 采集器                │
                     │         ▲                          │
T04 migrations ──► T05 worker+端点 ──► T07 reconcile       │
        └────────────┴──► T08 审批服务端 ──────────────────┘
T05..T10 ──► T11 端到端验收
```
（T01/T02/T03/T04 无前置，可并行开工）

## 3. 风险与回滚

| 风险 | 缓解 | 回滚 |
|---|---|---|
| digest 跨语言不一致（Node/Go） | 共享测试向量 fixture 先行（T03 产出，T08 引用） | 字段可写不校验（读侧容忍缺失） |
| 上游 rebase 冲突面扩大 | 全部新包/新文件，上游文件仅 AIFIRST 挂钩（router 2 处、daemon 主循环 1 处、execenv 3 处） | 挂钩点逐个可注释禁用 |
| 事件乱序造成错误投影 | 合法转移校验 + needs_reconcile + T07 对账 | 投影表可清空重放（git 是权威，无数据丢失） |
| Windows shim 兼容 | git.cmd + bash shim 成对物化（SDD §4.5），本机即混用环境可实测 | shim 缺失仅降级到 hooks+CAS 层，不阻塞任务执行 |
| PAT 前置不就位 | T07 开工条件明示；不阻塞其余任务 | server 模式关闭，daemon 模式兜底 |

## 4. 验收与发布策略

- 每 TASK 完成即在任务文件回填「完成记录」，代码经 push-progress 推 requirement/CR-2026-002 分支。
- M-E（T11）串联全部 AC 后走 write-test-report → review-code → 人工 code 审批 → merge → writeback（specs v0.11）。
- 发布物：tools custom/main 与 multica main 各一次 --no-ff 合并；上游回馈候选（outbox/rules.json/digest 两轨）在归档后单独整理 PR，不阻塞本 CR。
