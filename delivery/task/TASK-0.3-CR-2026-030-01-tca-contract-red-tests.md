---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-01
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 建立 TCA-001～004 失败优先测试基线
slug: tca-contract-red-tests
status: pending
estimate: 8h
depends-on: []
created: "2026-08-11T02:34:00+08:00"
---

# TASK-01 建立 TCA-001～004 失败优先测试基线

## 1. 任务描述

按 SDD §7.1～§7.2 在既有 Node 测试文件中增加失败优先向量，覆盖 Registration、Owner 正式移交、grant reject/幂等、review-dev-plan 三路与 R7 权威字面量校验。输入是已审批 SDD v0.1.1 与现有 `runCrctlWrapped()`/fixture builder；输出是可稳定复现缺失行为的测试，不新增测试框架或 production API。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`
- tools：`skills/shared/crctl/scripts/test/lint-prompts.test.mjs`

## 3. 实现要点

- 读取文本先规范化 `\r\n -> \n`，逐行解析使用 `/\r?\n/`。
- 真实 Git fixture 覆盖 staged-only、unstaged-only、同/异路径 mixed、untracked-only 和 clean success。
- grant 表驱动覆盖四 stage approve/reject、错误 grant、commit-failure→replay 和邻接幂等。
- lint fixture 写最小合法 `dir-graph.yaml` transitions，并覆盖 LF/CRLF、缺失、空、截断、畸形与模板变量跳过。
- 不删除或放宽既有 189 项 crctl 测试。

## 4. 验收条件

1. 新增测试精确覆盖 SDD AC-1～AC-28 中的 crctl/lint 行为，并在对应 production 实现前按预期失败。
2. fixture 能断言 audit、outbox、HEAD、index/worktree 分层和账本内容，而非只检查退出码。
3. `lint-prompts.test.mjs` 对 malformed/empty transitions 期望 `STATE_MACHINE_PARSE_FAILED`，不允许空集合通过。

## 5. 完成标志

测试文件可独立解析运行；新增向量的失败原因与 SDD 缺口一致；既有测试无删除；`tasks/_index.yml` 中 TASK-01 标记 `done`。

## 6. 接口契约

- **消费**：现有 `runCrctlWrapped()`、crctl fixture helper、lint fixture builder。
- **产出**：供 TASK-02～05 实现转绿的黑盒断言；不导出 production 函数。
