---
id: CR-2026-003-prd
type: PRD
cr-ref: CR-2026-003
title: P1 治理核心修补 — embedded 事件幂等键碰撞 + 归档 CR 失去自愈能力
target-version: "0.11.1"
owner: Ray
owner-role: requirement
status: draft
created: "2026-07-31T20:30:00+08:00"
updated: "2026-07-31T20:30:00+08:00"
revision: "0.1.0"
---

# PRD — P1 治理核心修补

> 本 CR 是 CR-2026-002 交付后归档收尾核对时发现的两个真实缺陷的修补，问题已在诊断阶段完全定位（根因、复现路径、影响范围均已确认），不涉及新功能设计，PRD 按最小必要篇幅编写，聚焦"缺陷是什么、修复到什么程度算完成"。

## 1. 概述

**问题陈述**：CR-2026-002 归档后核对投影状态时，发现两条平台自身的治理链路缺陷：

1. **embedded 事件幂等键碰撞**：`cr_sync_event` 表的幂等键是 `(cr_id, commit_sha, event_kind)`。`crctl advance --embedded` 模式下 `commit_sha` 留空（约定由后续 `git push` 的 checkpoint 事件补全），但当同一个 CR 在整个生命周期内多次使用 `--embedded` 模式推进状态（如 writeback 阶段的 `writing-back`、`archived` 两次状态推进），**每一次的空 commit_sha 都落在同一个幂等键上**，第二次及之后的 embedded status 事件会被 `INSERT ... ON CONFLICT DO NOTHING` 当作"重复事件"静默丢弃，投影状态永久停留在第一次 embedded 事件的状态。
2. **归档 CR 失去对账自愈能力**：`reconcile` 的自愈逻辑（`ApplySnapshot`）只读取 `change-requests/_backlog.yml` 中的在途 CR 列表；`_backlog.yml` 中的 CR 一旦被 `cr-archive` 移入 `_history.yml`，就再也不会出现在 reconcile 每个周期读取的快照里。若这个 CR 恰好在归档前因缺陷 1 卡在错误的投影状态，它就**永久**卡住——没有任何机制能再次自愈，因为对账的权威来源（backlog）已经不包含它了。

两个缺陷叠加的实测后果：CR-2026-001 与 CR-2026-002 归档后，Multica 平台看板上目前都显示 `status: writing-back`、`needs_reconcile: true`，而它们在知识库仓的真实状态是 `archived`——治理链路对"已完结的 CR"给出了错误的展示状态，且没有自我修复的路径。

**解决方案**：
1. embedded 事件不再共用空字符串作为幂等键的一部分——改为在事件生成时附带单调递增的本地序号（或等价的确定性 disambiguator），确保同一 CR 连续多次 embedded 事件不会互相覆盖。
2. reconcile 的快照来源扩展为 `_backlog.yml`（在途 CR）∪ `_history.yml`（已归档 CR，只读最终态用于终局校验），使归档 CR 的投影也能被最后一次校准到位。
3. 用本 CR 的修复逻辑，把 CR-2026-001 与 CR-2026-002 两条历史脏投影行收敛为正确的 `archived` 状态（作为验收的一部分，而非手工 UPDATE）。

**前置**：CR-2026-002 已归档交付，是本 CR 修复对象所在的代码基线（`internal/governance/{crsync,reconcile}.go`）。

## 2. 用户故事

- **US-1** 作为**平台管理员**，我希望已归档 CR 在看板上准确显示 `archived` 状态，而不是卡在回写中间态，以便通过看板就能信任治理链路的当前状态，不必去查 git log 交叉验证。
- **US-2** 作为**维护治理链路的工程师**，我希望同一个 CR 在生命周期内可以任意多次使用 `--embedded` 模式推进状态而不丢事件，以便 writeback/archive 阶段的多步骤状态推进保持可靠。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | embedded 模式发出的 outbox 事件不再因空 `commit_sha` 与同 CR 的其他 embedded 事件在幂等键上碰撞；同一 CR 连续 N 次 embedded advance，`cr_sync_event` 中应有 N 条不同的 status 行被正确处理（而非被去重丢弃） | P0 |
| FR-2 | reconcile 的对账快照覆盖 `_history.yml` 中已归档的 CR：对状态为 `archived`/`rejected`/`withdrawn` 的历史记录，若其当前投影行状态与历史记录的 `final-status` 不一致，也应被下一次对账周期自愈 | P0 |

## 4. 非功能需求

- **NFR-1 不破坏现有幂等语义**：修复后，非 embedded 路径（有真实 `commit_sha` 的事件）的去重行为必须保持不变——不能因为给 embedded 事件加了 disambiguator 就连带影响正常事件的幂等判断。
- **NFR-2 对账周期无感知**：FR-2 的历史 CR 校准不应引入额外的独立轮询或显著增加单次对账周期的开销（`_history.yml` 条目数量级与 backlog 相当，一次性读取可接受）。
- **NFR-3 不反向写 git**：与既有 reconcile 设计保持一致——修复后的自愈逻辑仍然只读 git 侧的 `_backlog.yml`/`_history.yml`，不会创建新的 git 提交去"修正"历史记录本身。

## 5. 验收标准

- **AC-1**（FR-1）构造同一 CR 连续两次 `crctl advance --embedded` 场景（模拟 writing-back → archived），断言 `cr_sync_event` 表中出现两条不同的 status 行且均被正确应用到 `cr` 投影表，而非第二条被静默丢弃。
- **AC-2**（FR-2）reconcile 快照校准覆盖已归档 CR：手工使某已归档 CR 的投影行状态与 `_history.yml` 中的 `final-status` 不一致，下一个对账周期后该行应自愈为一致状态。
- **AC-3**（历史数据收敛，验收动作非新增代码）：修复上线并跑过至少一个对账周期后，CR-2026-001 与 CR-2026-002 在 `cr` 投影表中的 `status` 均应变为 `archived`、`needs_reconcile` 均应为 `false`——通过本 CR 自身交付的修复自然收敛，不允许手工 UPDATE 数据库。

## 6. 成功指标

- 修复上线后，任意归档 CR 的投影状态与其 `_history.yml` 记录的 `final-status` 在一个对账周期内保持一致，不再需要人工核对或干预。

## 7. 范围排除

- 不重新设计 embedded 事件的整体 schema 或幂等策略，只修复空 `commit_sha` 导致的碰撞这一具体缺口。
- 不追加"CR 归档后不可逆"之外的新治理规则；本 CR 只是让既有"git 是权威、投影应收敛到权威"这条设计原则对归档 CR 同样生效。
- 不涉及 P2/P3 阶段的任何功能。
