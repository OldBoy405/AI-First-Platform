---
spec-id: ai-first-platform
version: "0.42"
id: CR-2026-069-TASK-04
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "Claude Adapter：PreToolUse / PostToolUse 映射 + settings.template.json（与 daemon 单写入点合成面的接口一致）"
slug: adapter-claude
status: pending
estimate: 12h
depends-on: [CR-2026-069-TASK-02]
created: 2026-09-17T17:25:00+08:00
---

# CR-2026-069-TASK-04 Claude Adapter（G4，FR-1 第 10~12 项 · 启用顺序第二位）

## 1. 任务描述

**目标**：新增 `output-guard/adapters/claude/`（`pretooluse-guard.mjs` / `posttooluse-guard.mjs` / `settings.template.json` / `README.md`），把 Claude Code 的 `PreToolUse` / `PostToolUse` 事件（后者的结果回填形态为 `hookSpecificOutput.updatedToolOutput`）映射到 OutputGuard Core；并保证**模板形态**与 TASK-09 的 daemon 单写入点合成分支所需的入参形状一致（同一 JSON 对象内、既有 hooks 段在前、OutputGuard 段在后）。

**背景**：claude 是唯一在 daemon 侧**已有** Runtime hooks 写入点的 Runtime（`dep-4` 的 `prepareCRGuard`，写 `{workDir}/.claude/settings.json`），因此它同时承担 Managed scope（TASK-09）与 Project/User scope（人工安装一次）两个面（§1.4.2 三级 scope）。安装形态沿用 `dep-10`（`skills/shared/crctl/adapters/claude-code/{settings.template.json,hooks/pretooluse-guard.mjs,README.md}`）的"模板 + 安装时物化绝对路径"先例，但**模板文件各自独立、不共用事实源**（SDD-CLOSE-01）。

**输入条件**：TASK-02 已完成；`dep-10` 的既有适配器（`skills/shared/crctl/adapters/claude-code/**`）为只读参照，本 CR 对其零 diff。

**范围边界（零越界）**：只新增 `output-guard/adapters/claude/**` 4 文件。**不改** `skills/shared/crctl/adapters/**`（`zero_diff`）、`../multica`（TASK-09）、`core.mjs` / 三份 JSON。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `output-guard/adapters/claude/pretooluse-guard.mjs` | 新增（`PreToolUse` 映射：逃生阀 / 命令族 / block / rewrite） | §3.3 Claude 行、§4.1/§4.2 |
| `output-guard/adapters/claude/posttooluse-guard.mjs` | 新增（`PostToolUse` 映射 → `hookSpecificOutput.updatedToolOutput`） | §3.3、§4.3 |
| `output-guard/adapters/claude/settings.template.json` | 新增（hooks 段模板；`{TOOLS_ROOT}` 安装时物化为绝对路径——与 `dep-10` 同形态、文件独立） | §3.4 |
| `output-guard/adapters/claude/README.md` | 新增（三级 scope 中 Project / User 的安装一次 + 检查命令 + 回滚） | §1.4.2、§3.4 |

## 3. 实现要点

1. **hook 协议面（§3.3）**：Pre 面读 stdin 的 `PreToolUse` payload；Post 面读 `PostToolUse` payload 并以 `hookSpecificOutput.updatedToolOutput` 回填结果（不透明替换之外的字段保持原值）。
2. **可保持性优先**：`toolName` / `toolCallId` / `isError` / `exitCode`（按 `capabilities.claude.preserve.exitCode`）与结果结构必须原样保留；不可保持 ⇒ 不改结果 + 一行 `coverage=unavailable`（§4.2）。
3. **fail-open**：payload 不可解析 / policy 不可读 / 结构不可保持 / 内部异常 ⇒ 输出"无决策"（不写 `updatedToolOutput`、不 deny），stderr 一行 `OUTPUT_GUARD_UNAVAILABLE runtime=claude reason=<四值>`；**不得**输出误伤调用的 deny/block。
4. **与 TASK-09 的接口一致性（关键）**：本 TASK 产出的 `settings.template.json` 的 **hooks 段形状**必须与 TASK-09 的 `crguard_config.go` 单写入点合成所写对象同构（同一 `hooks` 映射、`PreToolUse`/`PostToolUse` 数组元素含 `matcher` 与 `hooks[]` 的 `{type:"command", command:"node <abs>"}`）；两处文件各自独立，**不共用事实源**，但形状必须可被同一 Runtime 配置对象承载。形状不一致即本 TASK 未完成（TASK-09 无法在单写入点内合成）。
5. **不 clobber 判据的边界**：Managed scope 下「目标文件已存在 ⇒ 不写/不合并/不覆盖」的判定住在 TASK-09（daemon 侧）；本 TASK 只提供模板与说明，其 README 必须写明该事实（本地已有配置时手动安装需人工合并，工具不代为合并）。
6. **相对路径与零依赖**：Adapter 只用相对说明符引用同一 Release 的 `core.mjs` 与 `policy.json`（`../..`）；`settings.template.json` 内的 hook 命令用 `node` + 安装时物化的**绝对路径**（模板占位不得在运行期被直接使用，README 写明）。
7. **README 不复刻 policy**：只写路径、安装命令、检查命令（`check-install.mjs`）、回滚动作（从安装配置移除该项 ⇒ 该 Runtime 停用，新会话生效）。
8. **`V-4` 核实**：Claude Code hooks 文档的事件名与结果回填能力必须实测核对；核实失败 ⇒ 由 TASK-02 的 `capabilities.claude.level` 降级并走 scope amendment，本 TASK 不得自行改写 `capabilities.json`。

## 4. 验收条件

1. `node --test --test-reporter=dot output-guard/test/adapters-contract.test.mjs` 中 Claude 的全部向量通过；`coverage` 读数与 `capabilities.claude.level` 一致。
2. `settings.template.json` 的 hooks 段与 TASK-09 写的对象**同构**（逐字段比对 `hooks.PreToolUse[].matcher` / `hooks.PreToolUse[].hooks[].{type,command}` / `PostToolUse` 同形），且不含任何阈值数值或能力矩阵。
3. 真实冒烟（**plan §5.0 的 owner 预部署窗口**，落在 `developing` 内；记录落 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测）：一次真实 Claude 会话内触发拒绝（`find` 无界列举）、裁剪（`cat` 全文）、逃生（首行逃生阀）、损坏降级（临时移走 `policy.json`）四类行为各一次；`hookSpecificOutput.updatedToolOutput` 只在裁剪路径出现。
4. `node output-guard/scripts/check-install.mjs --tools-root .` 中 Claude 行形态正确。
5. 四条负向：逃生阀不绕过 `rules.json` 的 git 白名单 / protected paths / 审批 / 账本写入控制（`adapters-contract.test.mjs` 并列验证）。

## 5. 完成标志

- `output-guard/adapters/claude/**` 4 文件落盘并提交；验收条件 1~5 的实测命令与结果记入 TASK 完成记录（条件 3 的真实冒烟在 **plan §5.0 声明的 owner 预部署窗口**执行，落在 `developing` 内；记录落 TASK-10 的 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测 ⇒ `crctl task done` 在 `developing` 内可达，见 plan §2.1 / §9）。
- 明确登记「模板 hooks 段形状 ↔ TASK-09 合成入参」的逐字段对应关系（供 TASK-09 与 code review 核对）。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：daemon 侧挂载实现（TASK-09）、任何对 `skills/shared/crctl/adapters/**` 的改动。

## 6. 接口契约

**产出（供 TASK-09 合成面 / TASK-10 冒烟消费）**

```text
output-guard/adapters/claude/pretooluse-guard.mjs   ：PreToolUse payload(stdin) → 决策（block/rewrite/passthrough）
output-guard/adapters/claude/posttooluse-guard.mjs  ：PostToolUse payload(stdin) → { hookSpecificOutput: { updatedToolOutput } } | 无决策
output-guard/adapters/claude/settings.template.json ：{ hooks: { PreToolUse: [{ matcher, hooks: [{ type: "command", command: "node <abs>" }] }], PostToolUse: [同形] } }
安装面（Project/User，显式一次）：<project-root>/.claude/settings.json 或 ~/.claude/settings.json
Managed 面（由 TASK-09 的 daemon 单写入点写 {workDir}/.claude/settings.json）
```

**消费（本 TASK 依赖的上游）**

- TASK-02 的八个 Core 导出与三份 JSON（逐字签名见 TASK-02 §6）。
- `dep-10`：既有 Claude 适配器的三件套形态与 `{TOOLS_ROOT}` 物化约定（只读参照，零 diff）。
- `dep-4` / `§4.9`：daemon 侧 claude 写点的单写者事实（本 TASK 只保证模板形状可被其承载）。
- `V-4`：Claude Code hooks 文档事实（事件名、结果回填、配置面、Windows shell 约束）。
