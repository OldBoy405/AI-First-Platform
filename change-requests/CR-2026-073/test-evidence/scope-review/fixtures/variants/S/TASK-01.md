---
id: __CR__-TASK-01
type: TASK
cr-ref: __CR__
plan-ref: "change-requests/__CR__/plan.md"
sdd-ref: "change-requests/__CR__/sdd.md"
target-version: 0.46
title: 定向证据范围快照实现
slug: duration-targeted-snapshot
status: pending
estimate: 4h
depends-on: []
created: "__AT__"
---

## 任务描述

FR-1、FR-2 / AC-1、AC-2：新增 `tools/scripts/duration.mjs` 的两个纯函数与其定向用例。

## 涉及文件 / 模块

`tools/scripts/duration.mjs`（新增）、`tools/scripts/duration.test.mjs`（新增）。

## 实现要点

`parseDuration` 解析 `"1h30m"` 形态；`formatDuration` 反向格式化；两者无 I/O、无状态、非法输入不抛异常。

## 验收条件

1. 通过 `cmd-01` 证明 `parseDuration` 的合法/非法输入行为。
2. 通过 `cmd-02` 证明 `formatDuration` 的正常值/负数行为。

## 完成标志

两个函数与用例落盘，`cmd-01`、`cmd-02` 运行结果为 0，且**全量测试通过**后方可标记本 TASK done。

## 接口契约

- 消费：已批准 `sdd.md` §2 的签名与错误面；plan 两张稳定表的 `cmd-NN`。
- 产出：`tools/scripts/duration.mjs` 的两个导出函数，无其他模块改动。
