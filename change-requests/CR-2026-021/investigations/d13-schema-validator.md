---
id: CR-2026-021-investigation-d13
type: INVESTIGATION
cr-ref: CR-2026-021
task-ref: CR-2026-021-TASK-01
title: D13 溯源调查 — engineering-docs schema validator v0.4.0 下线原因
status: concluded
conclusion: not-revive
created: "2026-08-05T12:00:00+08:00"
---

# D13 溯源调查：engineering-docs schema validator 下线原因

> 结论先行：**不复活**（原因仍成立，且存在契约不匹配与依赖不变量冲突两个新增否决理由）。TASK-21 的 validate-doc 处理范围 = 保持现状，不改。

## 1. 下线原因（溯源）

证据：`skills/shared/engineering-docs/SKILL.md`：

- `:14`（v0.4.0 变更声明）："从 MCP server 模式降级为常规 Skill。所有生成逻辑由调用方 Agent 按步骤执行，不再依赖 `@openwork/engineering-docs-mcp` 或 CLI 脚本。"
- `:129-130`（弃用历史）："v0.3.0 及以前：提供 `@openwork/engineering-docs-mcp` MCP server + CLI `engdocs_gen`；v0.4.0：**去 MCP 化**，仅保留 SKILL.md 步骤 + templates + schemas；`scripts/` 目录保留但不再被 Skill 引用，仅供历史参考。"

**结论**：validator 下线是**刻意的架构简化（去运行时依赖）**，不是已知 bug、不是被更大改造取代、也不是性能问题。`scripts/`（含 `validators/frontmatter.ts` 的 `validateFrontmatter`、`validators/naming.ts`）与 `schemas/*.schema.json` 均仍留在仓内，只是不再被 SKILL 调用。

## 2. 否决复活的三条理由

### 2.1 架构方向冲突
v0.4.0 的核心决策就是"去 MCP 化 / 去 CLI 化"——把生成与校验逻辑交给 Agent 按 SKILL 步骤执行。复活 CLI validator 等于回滚该架构决策，需要先推翻 v0.4.0 的变更理由（仓内无任何记录表明该决策被重新审视）。

### 2.2 契约不匹配（实锤，纪律 #4 已核实）
engineering-docs 的 schema 面向**其模板生成的文档**，与 CR 产物是两套契约：

| 字段 | engineering-docs `prd.schema.json` | CR 产物 `change-requests/{cr}/prd.md` |
|---|---|---|
| `id` | `^PRD-\d{3}$`（如 `PRD-001`） | `CR-2026-021-prd`（**不匹配 pattern**） |
| `type` | `const: PRD` | `PRD`（匹配） |
| `cr-ref` | schema 未声明 | `CR-2026-021`（CR 侧独有） |

即使复活 `validateFrontmatter`，对 CR 产物执行也会因 id pattern 不匹配而**必然误报失败**；要让它可用必须另造一套 CR 侧 schema——那等于新写 validator，不是"复活"。

### 2.3 依赖与不变量冲突
`validators/frontmatter.ts` 运行时依赖 `ajv` + `gray-matter`（npm 第三方包，`scripts/package.json` 声明）；tools 包根无 `node_modules`、工程不变量 ③ 为零第三方依赖。接入即破坏不变量，需引入安装/构建链路。

## 3. 现状覆盖评估（不复活后 validate-doc 仍成立）

- `crctl validate`（crctl.mjs `cmdValidate`）已覆盖 CR 产物侧校验：`cr.md`（frontmatter/id/status/owners）、`_backlog.yml`（v1/v2 布局/owners）、`review-annotations/*.yml`（verdict/blockers）、`test-report.md`（status/tester）、`approval.yml`（段结构/via/摘要）、`traceability.yml`。
- `validate-doc/SKILL.md` 现状为 agent 按 engineering-docs `schemas/*.schema.json` 目检——对 engineering-docs 模板产物（如 specs/ 落点）仍可用；对 CR 产物应改指 `crctl validate`（TASK-21 按此分支处理，不改 validate-doc 的 engineering-docs 部分）。

## 4. 给 TASK-21 的执行指引

- validate-doc 处理范围：**不改动** engineering-docs 相关部分；若 TASK-21 顺带修订 validate-doc 的 CR 产物校验描述，应指向 `crctl validate`（已存在），不引入新命令（本调查结论：不开 `crctl validate --doc-type`）。
- SDD §1.7 路线 (a)/(b) 均不启用，无需新增设计小节。

## 5. 调查方法记录

- 阅读 `engineering-docs/SKILL.md` 全文（v0.4.0 变更声明 + 弃用历史）
- 核对 `schemas/prd.schema.json`（id pattern/type const）与 CR-2026-021 实际产物 frontmatter 对比
- 核对 `scripts/src/validators/frontmatter.ts` 依赖（ajv/gray-matter）与 tools 包根无 node_modules 事实
- git log 确认 engineering-docs 目录在 tools 仓内无本地 v0.4.0 专项 commit（3 个 commit 均来自上游基线），版本决策以 SKILL.md 声明为准
