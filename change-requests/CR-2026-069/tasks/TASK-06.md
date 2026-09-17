---
id: CR-2026-069-TASK-06
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "Qoder Adapter：同协议族复用 + .lingma/settings.json 安装面 + startRecord=none 的覆盖度诚实"
slug: adapter-qoder
status: pending
estimate: 10h
depends-on: [CR-2026-069-TASK-02]
created: 2026-09-17T17:27:00+08:00
---

# CR-2026-069-TASK-06 Qoder Adapter（G6，FR-1 第 10~12 项 · 启用顺序第四位）

## 1. 任务描述

**目标**：新增 `output-guard/adapters/qoder/`（`pretooluse-guard.mjs` / `posttooluse-guard.mjs` / `settings.template.json` / `README.md`），把 Qoder 的 hooks（格式与 Claude 一致、**无 SessionStart**）映射到 OutputGuard Core，并如实登记「无会话启动记录」对 FR-8 覆盖度派生精度的影响。

**背景**：`dep-11` 钉定 Qoder 的配置面 `.lingma/settings.json` 三级（用户级 / 项目级 / 项目本地）、格式与 Claude 一致、**无 SessionStart**（注入挂 `UserPromptSubmit`）、改配置需重启；因此 `capabilities.qoder.startRecord` 只能是 `none`（SDD §2.2.2 / `follow_up` F-2）。daemon 侧不写 Qoder 的 hooks（`dep-15` 只写 `AGENTS.md` 与 `.qoder/skills`）。

**输入条件**：TASK-02 已完成；`dep-11` 的既有适配器（`skills/shared/crctl/adapters/qoder/**`）为只读参照，本 CR 对其零 diff。

**范围边界（零越界）**：只新增 `output-guard/adapters/qoder/**` 4 文件。**不改** `../multica`（不为 qoder 新增 daemon 写点）、`skills/shared/crctl/adapters/**`、`core.mjs` / 三份 JSON。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `output-guard/adapters/qoder/pretooluse-guard.mjs` | 新增 | §3.3 Qoder 行 |
| `output-guard/adapters/qoder/posttooluse-guard.mjs` | 新增（同 Claude 的 `updatedToolOutput` 映射实现） | §3.3 |
| `output-guard/adapters/qoder/settings.template.json` | 新增 | §3.4、`dep-11` |
| `output-guard/adapters/qoder/README.md` | 新增（三级 `.lingma/settings.json` 安装 + 无 SessionStart 的口径 + 重启生效 + 回滚） | §1.4.2、§4.9 第 4 步 |

## 3. 实现要点

1. **同协议族复用**：Qoder 的 hook 协议族与 Claude 一致（`PreToolUse` / `PostToolUse` + `hookSpecificOutput.updatedToolOutput`），映射实现可复用同一思路；**模板与 README 独立存在**，不跨目录 import claude 的模板。
2. **无 SessionStart 的诚实口径**：`capabilities.qoder.startRecord="none"`；README 必须写明"本 Runtime 不产生会话启动记录，FR-8 侧只能由 trailer 与安装期检查读数派生覆盖度"——不得伪造启动记录、不得用 `UserPromptSubmit` 冒充 SessionStart。
3. **安装面三级**：`~/.lingma/settings.json`（用户级）/ `<project-root>/.lingma/settings.json`（项目级）/ 项目本地；安装动作 = 把 hooks 段合并进目标配置；改配置需重启生效（README 明示）。
4. **不 clobber**：与既有用户 hooks 段取并集，不覆盖整份文件；工具不做自动合并。
5. **fail-open / 可保持性 / 相对路径 / 零依赖 / 不复刻 policy**：同 TASK-04 第 2~3、6~7 条。
6. **`V-6` 核实**：Qoder hooks 文档的事件名、结果回填能力与配置面必须按 `V-6` 的核实命令实测；核实失败 ⇒ 由 TASK-02 降级 `capabilities.qoder.level` 并走 scope amendment。
7. **`exitCode` 口径**：按 `capabilities.qoder.preserve.exitCode` 判定（`present` 必保留 / `absent-by-runtime` 不作要求，不因此降级）；本 TASK 不改写该文件。

## 4. 验收条件

1. `node --test --test-reporter=dot output-guard/test/adapters-contract.test.mjs` 中 Qoder 的全部向量通过；`coverage` 读数与 `capabilities.qoder.level` 一致，且**不存在**伪造的启动记录断言。
2. README 含三级 `.lingma/settings.json` 落点、`startRecord=none` 的口径说明、重启生效与回滚动作；模板不含阈值数值与能力矩阵。
3. 真实冒烟（owner 部署窗口）：一次真实 Qoder 会话内触发拒绝 / 裁剪 / 逃生 / 损坏降级四类行为各一次；安装面不经 daemon。
4. `node output-guard/scripts/check-install.mjs --tools-root .` 中 Qoder 行形态正确（`coverage` 取值按实读）。
5. 四条负向：逃生阀不绕过 git 白名单 / protected paths / 审批 / 账本写入控制。

## 5. 完成标志

- `output-guard/adapters/qoder/**` 4 文件落盘并提交；验收条件 1~5 的实测命令与结果记入 TASK 完成记录（3 需在部署窗口执行）。
- 明确登记「无会话启动记录」（`startRecord=none`）与 FR-8 覆盖度派生精度的影响事实（供 TASK-10 的 `coverage` 派生取证使用）。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：daemon 写点、任何对 `../multica` 的改动、任何 `capabilities.json` 改写。

## 6. 接口契约

**产出（供 TASK-10 冒烟与启用顺序消费）**

```text
output-guard/adapters/qoder/pretooluse-guard.mjs   ：PreToolUse payload → 决策
output-guard/adapters/qoder/posttooluse-guard.mjs  ：PostToolUse payload → { hookSpecificOutput: { updatedToolOutput } } | 无决策
output-guard/adapters/qoder/settings.template.json ：{ hooks: { PreToolUse: [...], PostToolUse: [...] } }
安装面（显式一次，daemon 不参与）：~/.lingma/settings.json 或 <project-root>/.lingma/settings.json（+ 项目本地）
覆盖度口径：capabilities.qoder.startRecord = "none"（无 SessionStart；FR-8 只报覆盖度与裁剪量）
```

**消费（本 TASK 依赖的上游）**

- TASK-02 的八个 Core 导出与三份 JSON。
- `dep-11`：Qoder 的三级配置面、格式与 Claude 一致、无 SessionStart 的事实（只读参照）。
- `dep-15`：daemon 对 qoder 只写 `AGENTS.md` 与 `.qoder/skills`，**不写 hooks 配置**。
- `V-6`：Qoder hooks 文档事实（事件名 / 结果回填 / 配置面 / 信任或重启前置）。
