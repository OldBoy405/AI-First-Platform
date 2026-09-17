---
spec-id: ai-first-platform
version: "0.42"
id: CR-2026-069-TASK-07
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "Codex Adapter：partial 声明 + hooks.json.template + /hooks 信任步骤 + uncovered 路径逐条列示"
slug: adapter-codex
status: pending
estimate: 12h
depends-on: [CR-2026-069-TASK-02]
created: 2026-09-17T17:28:00+08:00
---

# CR-2026-069-TASK-07 Codex Adapter（G7，FR-1 第 10~12 项 · 启用顺序第五位 / partial）

## 1. 任务描述

**目标**：新增 `output-guard/adapters/codex/`（`pretooluse-guard.mjs` / `posttooluse-guard.mjs` / `hooks.json.template` / `README.md`），按 **partial** 能力落地 Codex 的 hook 映射，并在 README 与模板内**逐条列示 uncovered 路径**（含 hosted `WebSearch`）与 `/hooks` 审查-信任步骤。

**背景**：`dep-12` 钉定 Codex 的安装面 `.codex/hooks.json`（用户级/项目级）与 config.toml `[[hooks]]` 等效、matcher 为正则、非托管 command hook 有 `/hooks` 审查-信任（**按哈希，脚本变更需重新信任**）；Codex 的结果回填不是透明替换，因此 `capabilities.codex.level="partial"`，其 `paths[]` 必须逐条声明 `uncovered: true`（§2.2.2）。

**输入条件**：TASK-02 已完成；`dep-12` 的既有适配器（`skills/shared/crctl/adapters/codex/**`）为只读参照，本 CR 对其零 diff。

**范围边界（零越界）**：只新增 `output-guard/adapters/codex/**` 4 文件。**不改** `../multica`、`skills/shared/crctl/adapters/**`、`core.mjs` / 三份 JSON（`codex` 行的 `level`/`paths`/`uncovered` 由 TASK-02 持有并已声明）。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `output-guard/adapters/codex/pretooluse-guard.mjs` | 新增（managed `PreToolUse`） | §3.3 Codex 行 |
| `output-guard/adapters/codex/posttooluse-guard.mjs` | 新增（`PostToolUse` block/feedback 路径，非透明替换） | §3.3 |
| `output-guard/adapters/codex/hooks.json.template` | 新增（`{ hooks: { PreToolUse: [...], PostToolUse: [...] } }` 等价形态 + matcher 正则） | §3.4、`dep-12` |
| `output-guard/adapters/codex/README.md` | 新增（安装 + **信任步骤** + uncovered 逐条列示 + 回滚） | §2.2.2、`dep-12` |

## 3. 实现要点

1. **partial 的诚实声明**：README 必须逐条列出未覆盖路径（至少含 hosted `WebSearch` 这类不经本地 hook 的路径），并写明"这些路径不生效"；不得暗示全量覆盖。
2. **信任步骤是前置**：README 必须写明 `.codex/hooks.json` 改动后需要 `/hooks` 审查-信任，且**按哈希**——脚本变更后需**重新信任**，否则 hook 不生效（这是 Codex 特有的部署风险，登记进 README 与 TASK-10 的冒烟口径）。
3. **非透明替换**：Post 面按 Codex 的 block/feedback 路径回填；不能完全透明替换的路径不得伪造 `updatedToolOutput` 语义。
4. **matcher 为正则**：模板中的 matcher 使用正则形态（与既有 `dep-12` 模板同风格），不引入 shell 解析。
5. **fail-open / 可保持性 / 相对路径 / 零依赖 / 不复刻 policy**：同 TASK-04 第 2~3、6~7 条。
6. **`V-7` 核实**：Codex hooks 文档的事件名、结果回填能力、配置面与信任前置必须按 `V-7` 的核实命令实测；核实失败 ⇒ 由 TASK-02 降级 `capabilities.codex.level`（`partial` → `unavailable`）并走 scope amendment。
7. **不追求全覆盖**：`dep-2` §6.3 的限制明确如此，本 TASK 只做声明与逐条标记（`follow_up` F-6）。

## 4. 验收条件

1. `node --test --test-reporter=dot output-guard/test/adapters-contract.test.mjs` 中 Codex 的 partial 向量通过；`capabilities.codex.level="partial"` 与 `paths[]` 中每条 `uncovered: true` 路径在 README 中**逐条出现**（逐条比对，可机械核对）。
2. `hooks.json.template` 可 JSON 解析，含 `PreToolUse` / `PostToolUse` 两类与正则 matcher；不含阈值数值与能力矩阵。
3. README 含信任步骤（`/hooks` 审查-信任 + 按哈希 + 脚本变更需重新信任）与回滚动作（移除 hooks 条目 ⇒ 该 Runtime 停用，新会话生效）。
4. 真实冒烟（**plan §5.0 的 owner 预部署窗口**，落在 `developing` 内；记录落 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测）：一次真实 Codex 会话内触发拒绝 / 裁剪 / 逃生 / 损坏降级；**且**至少一条 uncovered 路径（如 hosted `WebSearch`）被实测确认"不生效"并记入 TASK-10 的证据文件。
5. `node output-guard/scripts/check-install.mjs --tools-root .` 中 Codex 行形态正确（`coverage=partial` 或按实读）。

## 5. 完成标志

- `output-guard/adapters/codex/**` 4 文件落盘并提交；验收条件 1~5 的实测命令与结果记入 TASK 完成记录（条件 4 的真实冒烟在 **plan §5.0 声明的 owner 预部署窗口**执行，落在 `developing` 内；记录落 TASK-10 的 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测 ⇒ `crctl task done` 在 `developing` 内可达，见 plan §2.1 / §9）。
- 明确登记「信任步骤 + 按哈希重信任」与「uncovered 路径清单」两项事实（供 TASK-10 的 AC-14 / AC-20 取证使用）。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：把 Codex 提升为 full（那需要 scope amendment）、`capabilities.json` 改写、任何 daemon 写点。

## 6. 接口契约

**产出（供 TASK-10 冒烟与启用顺序消费）**

```text
output-guard/adapters/codex/pretooluse-guard.mjs  ：PreToolUse（managed）payload → 决策
output-guard/adapters/codex/posttooluse-guard.mjs ：PostToolUse block/feedback 路径（非透明替换）| 无决策
output-guard/adapters/codex/hooks.json.template   ：{ hooks: { PreToolUse: [{ matcher, hooks: [...] }], PostToolUse: [同形] } }
安装面（宿主级/项目级，显式一次）：.codex/hooks.json（或 config.toml [[hooks]] 等效）
前置：/hooks 审查-信任（按哈希；脚本变更需重新信任）
能力：level = "partial"；paths[] 内 uncovered 路径逐条列示（含 hosted WebSearch），与 README 清单全等
```

**消费（本 TASK 依赖的上游）**

- TASK-02 的八个 Core 导出与三份 JSON（其中 `capabilities.codex` 的 `level` / `paths[].uncovered` 已由 TASK-02 声明，本 TASK 的 README 清单必须与之一一对应）。
- `dep-12`：Codex 的 `hooks.json` 形态、matcher 正则语义、`/hooks` 信任（按哈希）事实（只读参照）。
- `V-7`：Codex hooks 文档事实（事件名 / 结果回填能力 / 配置面 / 信任前置 / Windows shell 约束）。
