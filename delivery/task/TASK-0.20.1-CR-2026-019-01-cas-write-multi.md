---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-01
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 新增 casWriteMulti 双文件原子写原语
slug: cas-write-multi
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

在 `crctl.mjs` 现有 `casWrite`（:667）之上新增 `casWriteMulti(writes)`，为 archive-move 的双文件写提供原子性：全部 CAS 校验通过后才写，任一 hash 不符立即 `fail('CAS_CONFLICT', path)` 且不落任何写。输入 `writes: [{path, expectedHash, newText}]`。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（新增 `casWriteMulti` 函数，紧邻 `casWrite`）

## 实现要点（参考 SDD §4.3）

- 三阶段：① 遍历全部 writes 做 `sha256(readFileChecked(path)) === expectedHash` 校验；② 全部写 `path + '.tmp-' + process.pid`；③ 连续 `fs.renameSync(tmp, dst)`。
- 复用现有 `readFileChecked` / `sha256` 工具，不引入新依赖（NFR-4）。
- rename 之间的残余崩溃窗口为**已接受天花板**（SDD §4.3），不加 WAL/两阶段提交。

## 验收条件

1. 两文件 hash 均匹配 → 两文件都被更新为对应 newText。
2. 第二个文件 hash 不匹配 → 抛 `CAS_CONFLICT`，**两文件磁盘内容均无变化**（校验先于任何写）。

## 完成标志

`casWriteMulti` 实现完成，TASK-05 中对应用例（archive-move 正常 / history 侧 CAS 冲突）通过，lint 零报错。
