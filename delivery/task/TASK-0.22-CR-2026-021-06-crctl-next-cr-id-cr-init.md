---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-06
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl next-cr-id（只读预览）+ cr-init（原子权威分配，合并实现）
slug: crctl-next-cr-id-cr-init
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-7（SDD §2.3/§4.2，含 SDD-BLOCK-001 修复后的定案语义）：`next-cr-id` 是**纯只读预览**，不写、不参与分配。`cr-init` 是**唯一权威原子分配**——**不取显式 cr-id 入参**，内部读 max → 计算 `CR-{year}-{max+1}` → `casWriteMulti` 一次性写 `cr.md`(新建)+`_backlog`(追加)+`_index`(登记) → 输出返回分配到的 cr-id。二者共享同一注册流程，合并实现与测试。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（2 个新 dispatch case，签名严格按 SDD 0.1.1：`cr-init --title <t> --owner-requirement <id> [--year Y]`，无 `<cr-id>` 位置参数）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

1. **签名核对（本任务最容易踩坑处）**：`cr-init` 不得接受调用方传入的 cr-id；若实现中发现需要，说明设计有偏差，应回到 SDD 而非在代码里静默加回。
2. `casWriteMulti` 三文件：`cr.md` 的 `expectedHash=null`（期望不存在，SDD §4.2）；`_backlog`/`_index` 用读时 sha256。
3. `cr.md` frontmatter 全量生成：owners/owner-history/时间戳全部 crctl 生成（`identity(ws)`/`nowIso()`），`--owner-requirement` 只提供被指派人业务身份。
4. 并发冲突路径**唯一**是 `CAS_CONFLICT`（SDD-BLOCK-001 修复要点），正常路径不触发 `CR_ALREADY_EXISTS`。
5. `next-cr-id` 仅扫 max 返回候选字符串，不接触任何写路径。

## 验收条件

- AC-4（PRD，按 SDD 0.1.1 语义）：并发两次调用 `cr-init`，两次分配到不同 CR-ID；冲突方收到 `CAS_CONFLICT` 后按调用方重跑逻辑（此层由消费方 TASK-19 承接，本任务只需保证冲突正确抛出、三文件均不落盘）。
- CAS 冲突测试采用 SDD §5/§0 定案的**组件级抽函数注入 mismatch hash** 手法（对齐 `crctl.test.mjs:924-961` 既有 `casWriteMulti` 测试范式），不依赖真并发/黑盒时序注入。
- `next-cr-id` 两次连续调用（无写入之间）返回同一候选（验证其非权威、不参与分配的性质）。

## 完成标志

`node --test crctl.test.mjs` 全绿；组件级 CAS 冲突用例通过。
