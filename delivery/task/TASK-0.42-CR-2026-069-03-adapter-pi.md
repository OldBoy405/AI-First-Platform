---
spec-id: ai-first-platform
version: "0.42"
id: CR-2026-069-TASK-03
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "Pi Adapter：tool_call / tool_result 双面映射 + 宿主级安装 README（首个启用 Runtime）"
slug: adapter-pi
status: pending
estimate: 12h
depends-on: [CR-2026-069-TASK-02]
created: 2026-09-17T17:24:00+08:00
---

# CR-2026-069-TASK-03 Pi Adapter（G3，FR-1 第 10~12 项 · 启用顺序第一位）

## 1. 任务描述

**目标**：新增 `output-guard/adapters/pi/`，把 Pi 扩展的两个事件面（`tool_call` 前置可阻断/可原地改写、`tool_result` 后可修改局部 patch）映射到同一 Release 的 `core.mjs` 与 `policy.json`，并给出**宿主级安装一次**的 README（`~/.pi/agent/settings.json#extensions` 或 `~/.pi/agent/extensions/`）。

**背景**：Pi 是启用顺序的第一位（`dep-1` FR-1 第 11 项：`Pi → Claude → CodeBuddy → Qoder → Codex(partial)`），其前一个 Runtime 的「conformance 通过 + 真实冒烟通过 + 降级验证通过」是后一个的前置（AC-20）。Pi 的 argv 面被 `dep-16`（`pkg/agent/pi.go` 的 `buildPiArgs` / `piBlockedArgs`）封闭 ⇒ **只能走宿主级配置面**，不能靠 argv 注入；该文件在本 CR 零 diff。

**输入条件**：TASK-02 已产出 `core.mjs` / `policy.json` / `capabilities.json` / `conformance.json` / `check-install.mjs`；CR status `developing`。

**范围边界（零越界）**：只新增 `output-guard/adapters/pi/{index.ts,README.md}`。**不改** `core.mjs` / 三份 JSON / 其它 Adapter 目录 / `crctl.mjs` / `.github/workflows/crctl-ci.yml`（TASK-02 已含）；**不引入**构建步骤、`package.json`、第三方依赖或 `.ts` 编译产物；**不**在 `../multica` 新增 Pi 的 daemon 写点（§4.9 第 4 步）。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `output-guard/adapters/pi/index.ts` | 新增（Pi 扩展入口：`tool_call` + `tool_result`） | §3.3 Pi 行、§4.1/§4.2 |
| `output-guard/adapters/pi/README.md` | 新增（宿主级安装一次 + 检查命令 + 禁用即回滚） | §3.4、§7.3 回滚 |

## 3. 实现要点

1. **Pre 面（`tool_call`）**：取「原始命令首行」判定一次性逃生阀（`parseEscapeHatch`）→ `valid` ⇒ `action=passthrough`（跳过封顶，仍受 Runtime 自身权限与既有安全控制约束）；命中命令族且可判定 ⇒ `action=block`（拒绝 + 可执行替代写法）或 `action=rewrite`（施加上限后执行）；不确定（管道/重定向/脚本嵌套）⇒ 放行并进入 Post 面统一封顶（§4.2 的 `determinate=false`）。
2. **Post 面（`tool_result`）**：先做可保持性检查（§4.2 步骤④的三条门），不通过 ⇒ 返回**最小 patch**（不改 `content`）并在 stderr 打一行 `OUTPUT_GUARD_UNAVAILABLE runtime=pi reason=<四值>`；通过且超阈值 ⇒ 用 `evaluateResult` 裁剪并追加一行 trailer；未命中任何规则 ⇒ **不追加任何文本**。
3. **结果回填形态（§3.3）**：返回 `{ content, details?, isError? }` **局部 patch**，省略字段保持原值；`details` 不得被写入被丢弃正文（AC-7）；`isError` 原样保留。
4. **fail-open 契约（§3.3 末段）**：payload 不可解析 / policy 不可读或不可解析 / 结构不可安全保持 / 内部异常四种情况一律输出"无决策"（不写替换字段、不禁用调用），**不得**输出会误伤调用的 deny/block 决策。
5. **同一 Release 相对路径（I2 / §3.3）**：只通过相对说明符 `import` 同一 Release 的 `core.mjs` 与读取同一 Release 的 `policy.json`（`../..` 形式），**不引入**构建步骤或依赖；不使用绝对路径、不使用 `{TOOLS_ROOT}` 占位。
6. **宿主级安装一次（§1.4.2 / §4.9 第 4 步）**：README 写明 Pi 的挂载面是**宿主级** `~/.pi/agent/settings.json#extensions`（或 `~/.pi/agent/extensions/`），安装动作是"把扩展目录写进 `extensions[]`"；**不猜路径、不做 argv 注入**（`dep-16` 封闭）；启用顺序第一位，回滚 = 从 `extensions[]` 移除该条目（新会话生效）。
7. **`capabilities.json` 的 Pi 行不得由本 TASK 改写**（TASK-02 持有该文件的写入权）：`preserve.exitCode` 的取值以 `V-1`/`V-3` 核实为 `absent-by-runtime` 为前提；本 TASK 只按该旁白消费。
8. **不复刻 policy**：README 只写"路径 + 安装命令 + 检查命令"，禁止复制 `policy.json` 阈值或 `capabilities.json` 能力矩阵（AC-13）。

## 4. 验收条件

1. `node --test --test-reporter=dot output-guard/test/adapters-contract.test.mjs` 中 Pi 的全部向量（`escape-hatch` / `decision` / `degradation` / `idempotence`）通过；Pi 行的 `coverage` 读数与 `capabilities.pi.level` 一致。
2. `node output-guard/scripts/check-install.mjs --tools-root .` 中 Pi 行形态正确（`output-guard runtime=pi coverage=full policy=v1` 或按实读降级值）。
3. 端到端真实冒烟（**plan §5.0 的 owner 预部署窗口**，落在 `developing` 内；记录落 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测）：一次真实 Pi 会话内执行 `grep -rn <token> .`，模型可见结果只含唯一文件列表 + 命中数 + 缩小范围写法，且带 `action=truncate complete=false` trailer；被丢弃正文（sentinel）不出现在结果、session 文件与任何新增日志（AC-7 / AC-15）。
4. 逃生阀：首行 `# output-guard: full reason=<单行限长>` 的调用得到完整结果，且**不**影响 `rules.json` 的 git 白名单 / protected paths / 审批 / 账本写入控制（四条负向由 `adapters-contract.test.mjs` 并列验证）。
5. 降级：临时移走 `policy.json`（或注入损坏 payload）后，原调用继续、结果不改，stderr 出现 `OUTPUT_GUARD_UNAVAILABLE runtime=pi reason=POLICY_INVALID`。

## 5. 完成标志

- `output-guard/adapters/pi/{index.ts,README.md}` 落盘并提交；验收条件 1~5 的**实测命令与结果**记入 TASK 完成记录（其中条件 3 的真实冒烟在 **plan §5.0 声明的 owner 预部署窗口**执行 —— 该窗口落在 `developing` 内、**不是**部署后窗口；逐 Runtime 冒烟记录统一落 TASK-10 的 `evidence/ac14-smoke.md`，本卡只登记执行入口与预期观测 ⇒ `crctl task done` 在 `developing` 内可达，见 plan §2.1 / §9）。
- 覆盖 Pi 的启用前置三件（conformance 通过 / 真实冒烟通过 / 降级验证通过）逐条给出证据入口；未完成时如实记「未启用」，不得声明启用。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：把 Pi 加入任何 daemon 写点、改 `pkg/agent/pi.go`、改 `capabilities.json`。

## 6. 接口契约

**产出（供 TASK-09（不写 Pi，仅排除）/ TASK-10 冒烟与启用顺序消费）**

```text
output-guard/adapters/pi/index.ts
  hook 面：tool_call（可阻断；event.input 可原地改写）
           tool_result（可修改；返回 { content, details?, isError? } 局部 patch，省略字段保持原值）
  失败面：stderr 一行  OUTPUT_GUARD_UNAVAILABLE runtime=pi reason=<ADAPTER_MISSING|DISABLED|BUNDLE_INVALID|POLICY_INVALID>
  安装面（宿主级，显式一次）：~/.pi/agent/settings.json#extensions  或  ~/.pi/agent/extensions/
```

**消费（本 TASK 依赖的上游）**

- TASK-02：`core.mjs` 的八个导出（见 TASK-02 §6 逐字签名）与 `policy.json` / `capabilities.json` / `conformance.json`。
- `V-1`：Pi 扩展 API 事实（`tool_call` 可阻断；`tool_result` 返回局部 patch；扩展发现面与 `PI_CODING_AGENT_DIR`）；核实失败 ⇒ `capabilities.pi.level` 降级并走 scope amendment，**不得**在本 TASK 静默补写。
- `dep-16`：Pi 的 argv 面封闭（本 CR 零 diff）——本 TASK 只消费该结论，不触碰该文件。
