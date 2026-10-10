---
id: CR-2026-076-TASK-13
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "owner 值域校验（user_id）与 register／owner-set 契约同步"
slug: crctl-owner-user-id-validation
status: pending
estimate: 12h
depends-on: []
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-SUP-01、FR-SUP-02；AC-SUP-01／AC-SUP-02；SDD §4.14 + §3.3 + §8）：让 `owners.{requirement,development,test}.id` 的值域收紧为「当前 workspace 成员的 `user_id`」，并在注册与 owner 变更两条受控入口的持久化之前共用同一校验缝；同步合同与示例口径。

背景与输入条件：`dep-31` 结论原文——注册与 owner 变更已有受控事务入口、投影一致性与回滚能力（`cmdRegister`、`buildRegisterResult`、`cmdOwnerSet`、`editCrOwnerProjection`、`editBacklogOwnerProjection`、`rollbackOwnerWrite`），可在其持久化前挂校验而不新增写入通道；`dep-32` 结论原文——成员 `user_id` 查询入口已存在（`multica workspace member list`，返回成员 `user_id`），可作为 owner 值域的唯一来源；仅校验 UUID 形状不足够（`membership ID` 与 `user_id` 同为 UUID 形状）。

明确不做：不引入自动消歧、静态名单或成员缓存；不扩大 reviewer／Agent／Git 审计／mention 身份模型；不新增作者权限；错误语义不得互相冒名（owner-set 的失败不命名为注册失败）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdRegister(ws, flags)`（:3659）、`buildRegisterResult`、`async function cmdOwnerSet(ws, cr, gates, flags)`（:2702）、`editCrOwnerProjection`、`editBacklogOwnerProjection`、`rollbackOwnerWrite`
- `skills/shared/crctl/scripts/test/register-tx.test.mjs`
- 合同与示例：`skills/requirement/requirement-register/SKILL.md`、`pipeline-templates/requirement-authoring.pipeline.json`（owner 输入示例）

## 实现要点

1. 写入前校验缝严格按 SDD §4.14（register 与 owner-set **共用同一校验缝**，顺序不可交换）：
   ```text
   1) 取目标值 → 必须为 UUID 形状（拒绝显示名与错误 ID 类型）
   2) 一次 multica workspace member list 查询 → 按返回的 user_id 命中当前 workspace 成员
   3) 未命中/查询失败 → 技术失败（不伪装"成员不存在"、不猜 ID、不用静态名单兜底）
   4) 同名歧义无法确认 → 停止并要求人工确认，不自动消歧
   5) 通过 → 写入 cr.md 与 _backlog.yml（经既有受控账本通道）
   错误语义：owner-set 的失败命名为 owner-set 失败，register 的失败命名为注册失败，不互相冒名
   ```
2. 一次查询复用三角色（不引入缓存、不做静态名单）；三角色可指向同一成员。
3. 零写入保证：校验失败时经既有回滚能力保证 `cr.md`／`_backlog.yml` 与投影零写入（与 TASK-14 的幂等语义衔接）；**不占用** `registration_key`、不建 worktree（AC-SUP-07 由 TASK-14 主责，本 TASK 保证 owner 侧失败路径同样零写入）。
4. 已有 CR 的 owner 纠正只经 `handover-cr`／`owner-set` 受控流程；保留原始注册参数不等于冻结现任 owner；同值重放不追加固定数量历史记录。
5. 合同同步（§8）：`requirement-register` 参数说明与 Pipeline owner 输入示例改为 `user_id` 口径，**删除**可被误抄为 ID 的 `product-owner`／`dev-owner`／`test-owner` 示例。

## 验收条件

1. **AC-SUP-01（cmd-06 + cmd-04）**：接受成员 `user_id`；拒绝显示名、membership ID、非本 workspace 的 `user_id`、非 UUID 形状；register 与 owner-set 两条入口行为一致（同一校验缝的正反例各两组）。
2. **AC-SUP-02（cmd-06）**：身份查询失败按技术失败停止，不报为「成员不存在」、不猜 ID；断言错误码与消息不出现成员不存在的语义。
3. **AC-SUP-07（本 TASK 侧）**：owner 校验失败时 `cr.md`／`_backlog.yml` 与投影零写入、`registration_key` 未被占用、无 worktree 派生。
4. **合同一致性**：`requirement-register/SKILL.md` 与 `requirement-authoring.pipeline.json` 的 owner 示例均为 `user_id` 口径，且断言全文不再出现 `product-owner`／`dev-owner`／`test-owner` 示例串。
5. 运行范围以 plan §6.2 为唯一事实源：`cmd-06` = `register-tx.test.mjs` + `owner-source-scan.test.mjs`（后者由 TASK-15 新建；本 TASK 只要求 `register-tx.test.mjs` 部分通过，TASK-15 完成前该命令整体不通过属预期）；`cmd-04` = `crctl.test.mjs` 单文件（owner／source 写入前校验缝相关用例面）。真实执行输出落 `test-evidence/cmd-06.log`、`test-evidence/cmd-04.log`，不新增 plan 未列命令。

## 完成标志

- 共用校验缝落地并被 register／owner-set 两条入口消费，正反例与零写入断言通过；`cmd-04` 真实执行退出码 0 并留证（`cmd-06` 的完整通过以 TASK-15 完成为条件）；
- `requirement-register/SKILL.md` 与 Pipeline owner 示例同步为 `user_id` 口径且旧示例已删除；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（既有事实，`dep-31`／`dep-32`，不得缩写）：
- `async function cmdRegister(ws, flags)`（:3659）与 `buildRegisterResult`：注册事务入口与结果构造；
- `async function cmdOwnerSet(ws, cr, gates, flags)`（:2702）与 `editCrOwnerProjection`、`editBacklogOwnerProjection`、`rollbackOwnerWrite`：owner 变更的受控写入与回滚；
- `multica workspace member list` 成员查询（`dep-32`）返回的 `user_id` 为值域唯一来源。

产出（供 TASK-14／TASK-15／TASK-17 消费，消费方不得缩写）：
- 共用校验缝（同文件内的单一实现，register 与 owner-set 均调用）：入参 = 目标值 + 当前 workspace 成员查询结果；出参 = 通过或结构化失败；
- 失败语义（逐字）：注册失败命名为注册失败、owner-set 失败命名为 owner-set 失败；查询失败按技术失败（`ENVIRONMENT_MISMATCH` 类既有技术出口，§3.2），**不**映射为「成员不存在」类输入错误；
- 值域定义（E1，逐字）：`owners.{requirement,development,test}.id` 必须为当前 workspace 成员 `user_id`（UUID）；`assigned-at` 为 RFC3339+08:00；
- 合同文本：`requirement-register/SKILL.md` 与 `requirement-authoring.pipeline.json` 的 owner 示例（`user_id` 口径）是后续 CR 的唯一参照。
