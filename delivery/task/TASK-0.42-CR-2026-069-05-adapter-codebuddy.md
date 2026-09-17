---
spec-id: ai-first-platform
version: "0.42"
id: CR-2026-069-TASK-05
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "CodeBuddy Adapter：PreToolUse / PostToolUse 映射 + settings.template.json（显式安装一次，daemon 不写）"
slug: adapter-codebuddy
status: pending
estimate: 12h
depends-on: [CR-2026-069-TASK-02]
created: 2026-09-17T17:26:00+08:00
---

# CR-2026-069-TASK-05 CodeBuddy Adapter（G5，FR-1 第 10~12 项 · 启用顺序第三位）

## 1. 任务描述

**目标**：新增 `output-guard/adapters/codebuddy/`（`pretooluse-guard.mjs` / `posttooluse-guard.mjs` / `settings.template.json` / `README.md`），把 CodeBuddy Code 的 `PreToolUse` / `PostToolUse`（结果回填 `hookSpecificOutput.updatedToolOutput`）映射到 OutputGuard Core，并写明其 **Managed / Project / User 三级的实际落点**。

**背景**：daemon 侧对 codebuddy **只写记忆文件** `{workDir}/CODEBUDDY.md` 与原生 skills 目录（`dep-15`），**没有** hooks 写点（§4.9 第 4 步）；因此 codebuddy 的挂载面是「项目级 / 用户级配置文件 + 显式安装一次」，daemon 不参与（AC-19④ 的三级 scope 在这两个 Runtime 上靠配置面路径区分，不靠 daemon 写入）。

**输入条件**：TASK-02 已完成；`V-5` 已实读的部分（配置面 `<project-root>/.codebuddy/settings.json` / `.codebuddy/settings.local.json` / `~/.codebuddy/settings.json`、多 scope hooks 为**合并**而非覆盖、`PostToolUse` 支持 `updatedToolOutput` 替换与 `additionalContext` 追加、Windows 下 hook command 强制 Git Bash、配置在会话启动时快照改配置需重启）作为落点依据。

**范围边界（零越界）**：只新增 `output-guard/adapters/codebuddy/**` 4 文件。**不改** `../multica`（尤其**不为 codebuddy 新增 daemon 写点**，§4.9 第 4 步、`dep-15`）、`skills/shared/crctl/adapters/**`、`core.mjs` / 三份 JSON。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `output-guard/adapters/codebuddy/pretooluse-guard.mjs` | 新增 | §3.3 CodeBuddy 行 |
| `output-guard/adapters/codebuddy/posttooluse-guard.mjs` | 新增（`updatedToolOutput` 回填） | §3.3 |
| `output-guard/adapters/codebuddy/settings.template.json` | 新增（hooks 段模板） | §3.4 |
| `output-guard/adapters/codebuddy/README.md` | 新增（三级 scope 落点 + 显式安装一次 + 重启生效 + 回滚） | §1.4.2、§4.9 第 4 步 |

## 3. 实现要点

1. **hook 协议面**：与 claude 同一 hook 协议族（`PreToolUse` / `PostToolUse` + `hookSpecificOutput.updatedToolOutput`），复用同一映射实现思路；但**模板与 README 独立**（不嵌套引用 claude 目录）。
2. **多 scope 合并语义**：README 必须写明「项目级 `.codebuddy/settings.json` 可提交、团队共享；`.codebuddy/settings.local.json` 与用户级 `~/.codebuddy/settings.json` 按**合并**语义生效」——安装动作是"把 hooks 段合并进目标配置"，不是覆盖整份文件。
3. **不 clobber**：安装说明必须写明与既有用户 hooks 段取并集、不得覆盖他人配置；工具不做自动合并（无安装框架）。
4. **Windows 约束**：README 明示 hook command 在 Windows 下经 Git Bash 执行，因此模板命令形态必须与既有 `dep-10` 一致的兼容写法（`node "<abs>"`），不依赖 `cmd`/PowerShell 内建。
5. **重启生效**：配置在会话启动时快照 ⇒ README 必须写明"安装/回滚后需重启新会话生效"（与 FR-1 第 12 项的回滚粒度一致）。
6. **fail-open / 可保持性 / 相对路径 / 零依赖**：同 TASK-04 第 2~3、6 条（`reason` 四值闭包、不可保持不改结果、`../..` 相对说明符、无 `package.json`）。
7. **README 不复刻 policy**：只写路径 + 安装命令 + 检查命令 + 回滚。
8. **`V-5` 核实**：未实读的部分（`PreToolUse` 的 `permissionDecision` / `modifiedInput` 精确字段名与 `/hooks` 面板行为）必须按 `V-5` 的核实命令实测；核实失败 ⇒ 由 TASK-02 降级 `capabilities.codebuddy.level` 并走 scope amendment。

## 4. 验收条件

1. `node --test --test-reporter=dot output-guard/test/adapters-contract.test.mjs` 中 CodeBuddy 的全部向量通过；`coverage` 读数与 `capabilities.codebuddy.level` 一致。
2. `settings.template.json` 的 hooks 段不含阈值数值与能力矩阵；README 含三级 scope 落点（`.codebuddy/settings.json` / `.codebuddy/settings.local.json` / `~/.codebuddy/settings.json`）与"合并而非覆盖"一句。
3. 真实冒烟（**plan §5.0 的 owner 预部署窗口**，落在 `developing` 内；记录落 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测）：一次真实 CodeBuddy 会话内触发拒绝 / 裁剪 / 逃生 / 损坏降级四类行为各一次，且安装面**不经 daemon**（`git diff` 对本仓 `../multica` 该面为空可证）。
4. `node output-guard/scripts/check-install.mjs --tools-root .` 中 CodeBuddy 行形态正确。
5. 四条负向：逃生阀不绕过 git 白名单 / protected paths / 审批 / 账本写入控制。

## 5. 完成标志

- `output-guard/adapters/codebuddy/**` 4 文件落盘并提交；验收条件 1~5 的实测命令与结果记入 TASK 完成记录（条件 3 的真实冒烟在 **plan §5.0 声明的 owner 预部署窗口**执行，落在 `developing` 内；记录落 TASK-10 的 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测 ⇒ `crctl task done` 在 `developing` 内可达，见 plan §2.1 / §9）。
- 明确登记「本 Runtime 的 Managed 挂载面 = 项目级配置随仓库提交（daemon 不参与）」的事实句（供 TASK-10 的 AC-19④ 取证与 AC-14 冒烟口径使用）。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：任何 daemon 写点、任何对 `../multica` 的改动。

## 6. 接口契约

**产出（供 TASK-10 冒烟与启用顺序消费）**

```text
output-guard/adapters/codebuddy/pretooluse-guard.mjs   ：PreToolUse payload → 决策（block/rewrite/passthrough）
output-guard/adapters/codebuddy/posttooluse-guard.mjs  ：PostToolUse payload → { hookSpecificOutput: { updatedToolOutput } } | 无决策
output-guard/adapters/codebuddy/settings.template.json ：{ hooks: { PreToolUse: [...], PostToolUse: [...] } }
安装面（显式一次，daemon 不参与）：<project-root>/.codebuddy/settings.json（项目级，可提交）
                                    <project-root>/.codebuddy/settings.local.json（项目本地）
                                    ~/.codebuddy/settings.json（用户级）
多 scope 语义：合并（不是覆盖）；重启生效
Managed 级实现方式：项目级配置随仓库提交、团队共享；daemon 只写 {workDir}/CODEBUDDY.md 与 .codebuddy/skills（dep-15，本 CR 零 diff）
```

**消费（本 TASK 依赖的上游）**

- TASK-02 的八个 Core 导出与三份 JSON。
- `dep-15`：daemon 对 codebuddy 的写入面**不含任何 hooks 配置文件**（本 TASK 的边界依据）。
- `V-5`：CodeBuddy hooks 文档事实（配置面 / 合并语义 / `updatedToolOutput` / Windows Git Bash / 重启生效）。
