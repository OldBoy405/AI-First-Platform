---
id: CR-2026-076-TASK-12
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "Windows 文档链真实扫描：node:path.basename 与 docCount 断言"
slug: engineering-docs-windows-chain-scan
status: pending
estimate: 8h
depends-on: []
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-13；AC-24 的 Windows 文档链部分；SDD §4.12 + D-05）：修复 Windows 反斜杠路径下文档类型判不出、文档被静默跳过、空扫描假通过的问题，并以 `docCount` 断言 + Windows 原生嵌套路径用例证明真实扫描。

背景与输入条件：`dep-23` 结论原文——`collectDocs` 以 `file.split("/").pop()` 取文件名，在 Windows 反斜杠路径下类型判不出而被 `continue` 跳过，可造成空扫描假通过（`chain.ts:44-46`）。

明确不做：不新增路径助手或依赖、不改 gate 表达式、不扩建文档链类型或规则体系；使用既有测试入口（vitest）。

## 涉及文件 / 模块

- `skills/shared/engineering-docs/scripts/src/validators/chain.ts`：`function collectDocs(rootDir: string): Map<string, DocInfo>`（:41）、`export function chainCheck(rootDir: string): ChainResult`（:74）、`export interface ChainResult { …; docCount: number; … }`（:17）
- `skills/shared/engineering-docs/scripts/src/__tests__/chain.test.ts`（vitest 单文件）

## 实现要点

1. 文件名提取改用 `node:path.basename`（替换 `file.split("/").pop()`），使 `docs\{sub}\x.md` 形态在 Windows 下同样判出文档类型。
2. 断言强化：`docCount` 必须 **> 0**；空扫描不得再「静默通过」。
3. 新增用例：Windows 原生嵌套路径（`docs\{sub}\x.md`）证明真实扫描；用例同时覆盖既有 POSIX 形态（不回归）。
4. 不新增依赖：只用 Node 内置 `node:path`；不改 `evaluateGate` 与文档链注册表（`../registry.js`）。

## 验收条件

1. **AC-24（FR-13 部分，cmd-12）**：Windows 反斜杠与原生嵌套目录下 `docCount > 0` 的真实扫描成立。运行范围以 plan §6.2 为唯一事实源：`cmd-12` = 目录内单文件 `src/__tests__/chain.test.ts`（vitest 单文件，`cwd=skills/shared/engineering-docs/scripts`），前置为该目录内依赖已按 `pnpm-lock.yaml` 安装（plan §5.2，一次性准备，不新增常驻服务）。
2. **反例可观测**：构造反斜杠路径但文件类型合法的输入，断言修复前会被跳过的那类文件在修复后被计入 `docCount`（即断言 `docCount` 与候选文件数一致，而非仅 `> 0`）。
3. **不回归**：既有 POSIX 路径用例保持通过；`gate` 表达式与文档链类型集合未改动。
4. **范围声明**：**不声称** engineering-docs 全部测试通过（generators／validators 不在本 CR 声称面内）。真实执行输出落 `test-evidence/cmd-12.log`，不新增 plan 未列命令。

## 完成标志

- `collectDocs` 用 `node:path.basename`，`docCount > 0` 断言与 Windows 嵌套路径用例落盘，`cmd-12` 真实执行退出码 0 并留证；
- 未新增依赖（`package.json`／`pnpm-lock.yaml` 零改动声明）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（既有事实，`dep-23`，签名不变）：
- `import { loadDocChain, type DocType } from "../registry.js"`；
- `export interface ChainResult { …; docCount: number; … }`（`chain.ts:17`）——`docCount` 是 AC-24 的可观测字段，本 TASK 只补强断言不改字段类型。

产出（供 TASK-17 与后续 CR 消费，消费方不得缩写）：
- `function collectDocs(rootDir: string): Map<string, DocInfo>`（:41）：文件名提取改用 `node:path.basename`，`DocInfo` 结构与 `Map` 键语义不变；
- `export function chainCheck(rootDir: string): ChainResult`（:74）签名不变；`docCount` 语义收紧为「实际参与扫描的文件数」，空目录／全跳过场景必须使上层断言失败而非通过；
- 无新增导出面、无新增依赖。
