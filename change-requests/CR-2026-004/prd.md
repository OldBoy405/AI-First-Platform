---
id: CR-2026-004-prd
type: PRD
cr-ref: CR-2026-004
title: P2 三模式聊天 D1 — Team Agent 共享队列容量上限（容量校验 · owner/admin 插队 · 排队项撤回）
target-version: "0.12"
owner: Ray
owner-role: requirement
status: draft
created: "2026-07-31T23:35:00+08:00"
updated: "2026-07-31T23:35:00+08:00"
revision: "0.1.0"
---

# PRD — Team Agent 共享队列容量上限

> 本 CR 是 P2 三模式聊天交互设计（`docs/product/P2-三模式聊天交互设计.md`）§11 交付切分中的唯一待建项 D1。P2 的绝大部分交互（presenter 状态机、队列指示、工具执行卡、停止语义、Private Ask/Discussion）均直接骑在 Multica 既有能力上，不产生新 CR 工作量；D1 是设计稿明确标注"待建，非 Multica 既有能力"的业务逻辑层。

## 1. 概述

**问题陈述**：Team Agent 模式是项目级共享 AI 执行层——全体成员的消息进同一条 FIFO 队列，由单一写者语义串行执行。Multica 既有的 `agent_task_queue` 表与 claim SQL（`ORDER BY priority DESC, created_at ASC … FOR UPDATE SKIP LOCKED`，`NOT EXISTS` 串行化，均已核实存在于 `server/migrations/001_init.up.sql` 与 `server/pkg/db/queries/agent.sql`）提供了排队与领取的机制层，但**没有容量上限概念**：任何成员可以无限入队，队列深度不受控，高峰期一个项目可能积压大量任务，既拖垮体验（排在第 80 位的消息毫无时效性）也没有给项目管理者任何治理手段。

同时缺失的还有两个配套动作：
- **插队规则**：owner/admin 作为项目治理者，其消息不应被普通成员的积压阻塞；
- **撤回**：排队中的成员改变主意时，应能撤回自己的排队项释放槽位——且撤回必须留审计痕迹（软删除），不能物理删行。

**解决方案**：在既有 `agent_task_queue` 机制层之上补一层业务逻辑（入队前容量校验 + claim 优先级 + 撤回接口），不改表结构：

1. 入队前按 project 统计在队任务数，达到配置上限（默认 50）时拒绝非 owner/admin 的入队请求；前端输入区随之禁用并提示「Agent 忙，请稍后」。
2. owner/admin 不受上限阻塞，且入队时赋更高 `priority`（复用既有 `priority INT` 字段与 claim SQL 的 `ORDER BY priority DESC`），实现插队优先执行。
3. 上限值按 project 可配置，默认 50，非硬编码。
4. 撤回自己的排队项：复用既有 `status='cancelled'` 枚举做软删除标记（保留行与审计痕迹），槽位释放、后续项前移，排队数经既有 WS `task:{id}` → `workspace:{id}` 广播实时更新到全员。

**前置**：P0 数据模型（`agent_task_queue` + claim SQL + WS 通道，CR-2026-001 基线）；P1 治理核心（CR-2026-002/003）不直接依赖但共享同一代码基线。

## 2. 用户故事

- **US-1** 作为**项目成员**，我希望在 Team Agent 队列已满时立即得到明确反馈（输入区禁用 + 提示），而不是消息石沉大海排在几十位之后，以便改用 Private Ask 或稍后再来。
- **US-2** 作为**项目 owner/admin**，我希望自己的消息在队列拥堵时仍能入队并优先执行，以便紧急治理动作（如叫停跑偏的任务、插入修复指令）不被普通积压阻塞。
- **US-3** 作为**排队中的成员**，我希望能撤回自己尚未开始执行的排队项，以便及时释放共享槽位；同时作为**平台管理员**，我希望撤回留有审计痕迹而非物理删除。
- **US-4** 作为**项目 owner**，我希望按项目实际负载调整队列容量上限，而不是接受全平台统一的硬编码值。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **容量校验**：Team Agent 入队接口在插入前统计该 project 在队任务数（`status='queued'` 口径），达到上限时对非 owner/admin 请求返回结构化拒绝（含当前队列深度与上限值），不落库 | P0 |
| FR-2 | **owner/admin 插队豁免**：owner/admin 的入队请求不受 FR-1 上限阻塞，且赋予高于普通成员的 `priority` 值，使既有 claim SQL 的 `ORDER BY priority DESC, created_at ASC` 自然实现插队优先执行；同优先级内仍按 FIFO | P0 |
| FR-3 | **上限可配置**：容量上限按 project 配置，默认 50；配置读取失败或未配置时回退默认值，不阻塞入队链路 | P1 |
| FR-4 | **排队项撤回**：成员可撤回**自己的**、状态仍为 `queued` 的排队项——置 `status='cancelled'`（软删除，保留行）；已 `dispatched`/`running` 的任务不走本接口（沿用既有停止语义）；撤回后该项不再计入 FR-1 的容量统计 | P0 |
| FR-5 | **实时可见**：入队被拒、入队成功、撤回三类事件后，全员可见的排队数经既有 WS `task:{id}` → `workspace:{id}` 通道实时更新；前端输入区在「满且非 owner/admin」时禁用并提示，队列低于上限后自动恢复 | P1 |

## 4. 非功能需求

- **NFR-1 不改表结构**：全部需求基于既有 `agent_task_queue` 字段（`priority`、`status` 含 `cancelled` 枚举）与既有 claim SQL 实现；不新增迁移改动该表的列定义。项目级上限配置若需落库，允许新增独立配置存储，但不动 `agent_task_queue` 本身。
- **NFR-2 无竞态超卖的界定**：容量校验为"入队前 count 查询"级别的软限制——并发窗口内可能出现短暂超出上限 1~2 项的情况，本 CR 接受该弱一致（队列上限是体验治理阈值而非硬资源约束），不引入额外锁或串行化开销。此界定须写入 SDD 并在验收中明确口径。
- **NFR-3 审计口径**：撤回动作保留完整行数据（谁、何时、撤回了什么），不物理删行；审计记录不含消息正文以外的敏感内容。
- **NFR-4 代码规范**：multica 仓代码注释一律英文（其 CLAUDE.md 硬规则）。

## 5. 验收标准

- **AC-1**（FR-1）队列达到配置上限（默认 50）时：非 owner/admin 入队 → 接口返回结构化拒绝且 `agent_task_queue` 无新行；前端输入区禁用并显示「Agent 忙，请稍后」。
- **AC-2**（FR-2）队列已满时 owner/admin 入队 → 正常落库；且在既有普通成员积压存在的情况下，owner/admin 的任务先于更早创建的普通任务被 claim（验证 `priority` 排序生效）。
- **AC-3**（FR-3）修改某 project 的上限配置为非默认值（如 2）后，FR-1/FR-2 行为按新值生效；未配置的 project 按默认 50。
- **AC-4**（FR-4）成员撤回自己的 `queued` 项 → 该行 `status='cancelled'` 且行保留（软删除审计可查）；容量统计随之减一；尝试撤回他人排队项或非 `queued` 状态项 → 结构化拒绝。
- **AC-5**（FR-5）入队/拒绝/撤回后，另一在线成员的排队数显示经 WS 广播在无手动刷新的情况下更新。

## 6. 成功指标

- 队列满时成员得到即时明确反馈（拒绝响应 + 输入区禁用），不再出现"消息排在 50+ 位无人知晓"的体验黑洞。
- owner/admin 在队列拥堵场景下的指令等待时间显著低于普通排队（插队生效的直接体现）。

## 7. 范围排除

- 不做 org 级统一上限（设计稿允许 project **或** org 配置，本 CR 只落 project 级；org 级留待有真实多项目治理需求时再加）。
- 不改 presenter 单写者状态机、停止语义、Private Ask/Discussion 两模式——均为既有能力或后续交付。
- 不做队列项拖拽重排、预估等待时间等增强体验。
- 不引入硬一致的容量保证（见 NFR-2 弱一致界定）。
- 不涉及计费/用量统计。
