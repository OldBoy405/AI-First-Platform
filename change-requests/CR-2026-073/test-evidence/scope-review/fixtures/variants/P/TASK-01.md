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

1. `cmd-01`（`duration parse targeted case`，单用例子集）退出码 0，覆盖合法/非法输入两类断言。
2. `cmd-02`（`duration format targeted case`，单用例子集）退出码 0，覆盖正常值/负数两类断言。

## 完成标志

两个函数与用例落盘，`cmd-01`、`cmd-02` 两条定向证据（范围：两个单元用例，子集）运行结果为 0 后方可标记本 TASK done；本 TASK 不附加全仓命令或「全量通过」前置。

## 接口契约

- 消费：已批准 `sdd.md` §2 的签名与错误面；plan 两张稳定表的 `cmd-NN`，`executable`/`args`/`cwd`/`timeout` 以证据命令表行为唯一事实源。
- 产出：`tools/scripts/duration.mjs` 的两个导出函数，无其他模块改动。
