---
spec-id: ai-first-platform
version: "0.42"
id: CR-2026-069-TASK-09
type: TASK
cr-ref: CR-2026-069
plan-ref: "change-requests/CR-2026-069/plan.md"
sdd-ref: "change-requests/CR-2026-069/sdd.md"
target-version: 0.42
title: "Multica Managed 挂载：crguard_config.go 单写入点合成（仅 claude）+ outputguard_config.go + 同包回归测试 + CUSTOM.md #95"
slug: multica-managed-mount
status: pending
estimate: 14h
depends-on: [CR-2026-069-TASK-03, CR-2026-069-TASK-04, CR-2026-069-TASK-05, CR-2026-069-TASK-06, CR-2026-069-TASK-07]
created: 2026-09-17T17:32:00+08:00
---

# CR-2026-069-TASK-09 Multica Managed 挂载（G9，FR-1 第 10 项 · Managed scope）

## 1. 任务描述

**目标**：在 `../multica` 仓实现 Managed scope 的 OutputGuard 挂载——新增 `server/internal/daemon/execenv/outputguard_config.go`（挂载解析 + claude 合成入参），并在既有 `crguard_config.go` 的**单写入点内**完成 hooks 合成（**仅 `provider == "claude"` 分支**）；同批新增同包回归测试并按其现状登记 `CUSTOM.md`。

**背景**：daemon 侧 Runtime hooks 写点**只有 claude 一个**（`dep-4` 的 `prepareCRGuard` 写 `{workDir}/.claude/settings.json`）；codebuddy / qoder 的每任务写入面只有记忆文件与 skills 发现目录（`dep-15`），**没有** hooks 写点。因此 codebuddy / qoder / pi / codex **不写**（显式设计而非"暂无实现"，§4.9 第 4 步），它们的 Managed 面是各自原生配置面的显式安装一次（TASK-05/06/03/07）。给它们新开 daemon 写点等于在平台层再造一个 Runtime hooks 配置面，超出 FR-1 的挂载范围（D-7 的范围澄清）。

**输入条件**：TASK-03~TASK-07 已完成（本 TASK 的合成对象是五个 Adapter 的产出面）；`../multica` worktree HEAD（本节开工时）`947386318d52ecdb026a017f76220cde2ef7b94e`；`MULTICA_CONTROLLED_SHELL_RULES` 未配置时行为必须与上游逐字一致。

**范围边界（零越界）**：改动面 = `server/internal/daemon/execenv/{crguard_config.go,outputguard_config.go,outputguard_config_test.go}` + `CUSTOM.md`。**逐条零 diff**：`server/internal/daemon/tool_output_preview.go`（`dep-17`，AC-12）、`server/internal/governance/runner.go` 与 Provider 事件归一化实现（AC-12）、`server/pkg/agent/pi.go`（`dep-16` 的 argv 白名单面）、`server/internal/daemon/execenv/runtime_config.go`（`dep-15`）、`execenv.go`（`prepareCRGuard` 签名逐字不变、唯一调用点无需改动，见 §6；挂载输入在函数内经 `prepareOutputGuard(...)` 取得）；不新增远程开关、不新增安装框架、不在 CR 过程中安装任何东西、不放开任何被阻断的 argv。

## 2. 涉及文件 / 模块

| 文件 | 动作 | SDD 落点 |
|---|---|---|
| `server/internal/daemon/execenv/outputguard_config.go` | 新增（挂载解析；只写路径引用，**不复制 policy**；`// AIFIRST:` 标记 + `CR-2026-069` 追溯） | §4.9 A9 第 1~3 步 |
| `server/internal/daemon/execenv/crguard_config.go` | 改（**签名逐字不变**；在既有 claude 分支的单写入点内消费 `prepareOutputGuard(...)` 的可空产出并合成 OutputGuard hooks；挂载不可得时行为逐字不变） | §4.9 A9 第 3/5 步 |
| `server/internal/daemon/execenv/outputguard_config_test.go` | 新增（同包回归：≥4 个 `TestOutputGuard*` 函数） | §6.4 改动清单 |
| `CUSTOM.md` | 改（《代码改动明细》新增稳定 ID **#95** 行：`crguard_config.go` 单写入点内合成 OutputGuard hooks（挂载输入经 `prepareOutputGuard(...)` 取得）+ `outputguard_config.go` 新文件；含「合并注意」与「验证：」最小命令） | `dep-18`、AGENTS.md 纪律 10 |

## 3. 实现要点

1. **A9 五步逐条**（§4.9）：① 读本地安装配置（一个显式环境变量指向 Tools Release 根；**未配置 ⇒ 本次挂载整体跳过、既有行为逐字不变**）；② 解析 `output-guard/adapters/<provider>/` 下的 hook 入口绝对路径与 policy 读取面（**只写路径引用**）；③ provider 分支表（写入者唯一 = daemon）；④ `codebuddy` / `qoder` / `pi` / `codex` 一律**不写**（显式设计）；⑤ claude 分支：目标 `{workDir}/.claude/settings.json`，与该 provider 既有的 crctl 守卫 hooks **在同一个配置对象内合成**——同一 JSON 只写一次，hooks 数组按"既有段在前、OutputGuard 段在后"追加。
2. **不 clobber 判据（沿用既有语义）**：目标 `.claude/settings.json` **已存在**（用户自带配置 / `local_directory` 流）⇒ 不写、不合并、不覆盖，沿用 `dep-4` 的"存在即跳过并告警"；该次挂载记为未完成，由安装期检查（`check-install.mjs`）显式报告（AC-19③，不静默假装生效）。
3. **挂载不可得 ⇒ 既有输出逐字不变**：Tools Release 根未配置（`prepareOutputGuard` 返回 `ok=false`）时，`prepareCRGuard` 写出内容与改造前**逐字相同**（含 JSON 缩进与末尾换行）；新增测试必须逐字断言这一点。此即 SDD §1.2「新增可空入参」的可读落实——可空的是**挂载输入**（`outputGuardMount` + `ok` 位），不是调用方要传的形参：Go 无默认参数，加形参会强制改调用点 `execenv.go`，而 SDD §1.2 的 multica 落点清单未包含该文件（§4.9 第 1 步的输入恰为 `envRoot`/`workDir`/`provider`）。
4. **唯一 hooks 写入分支**：`crguard_config.go` 内 `provider ==` 的比较**恰出现一次**且是 `"claude"`（机械判据）；不得为其它 provider 新增写点。
5. **不复制 policy**：`outputguard_config.go` 不得出现 `resultTokensCap` / `lineWindow` / `maxHits` / `headLines` / `tailLines` 任一阈值名或任何阈值数值；只引用 `output-guard/policy.json` 的**路径**与 adapter 入口路径。
6. **错误与降级**：读既有配置失败时按"存在即不 clobber"处理并告警，**不写半成品文件**；不新增远程开关；不动 `dep-16` 的 argv 面；不碰 `dep-17` 的 preview/transcript 层。
7. **测试命名约定（硬）**：新增测试函数一律以 `TestOutputGuard` 前缀命名（`cmd-06` 的 `-run TestOutputGuard` 与 `cmd-07` 的存在性守卫按此前缀取值），且**至少 4 个**，分别覆盖：claude 单写入点合成（既有段在前 + OutputGuard 段在后 + 单次写）/ 目标文件已存在不 clobber / Tools Release 根未配置 ⇒ 既有输出逐字不变（含 JSON 缩进与末尾换行）/ `provider` ∉ {`claude`} ⇒ 零 hooks 写入且既有行为逐字不变。
8. **CUSTOM.md 登记（纪律 10）**：按其**当时实际结构**登记（编号顺延 = #95；不新造列、不改表头）；「原因 / 追溯」含 CR 编号与 TASK；「合并注意」取四种标准口径之一（本行属"贴回挂钩（改上游既有文件）"）；末尾「验证：」给最小命令 `cd server && go test ./internal/daemon/execenv/ -count=1 -v -run TestOutputGuard`。

## 4. 验收条件

1. `cd server && go test ./internal/daemon/execenv/ -count=1 -v -run TestOutputGuard` exit 0 且 stdout 含 `--- PASS:` 行（≥4 个用例名）。
2. `go test ./internal/daemon/execenv/ -count=1` 不因本 TASK 引入**新的**失败（该包本机基线非全绿，见 plan §0.4：既有 24 项与本改动面无关的失败不计入本条件，但**新增失败必须为 0**；判定口径 = 与基线失败清单逐条比对）。
3. `crctl git diff --name-only <multica base> --cwd <multica worktree>` 的路径集 ⊆ {`CUSTOM.md`, `crguard_config.go`, `outputguard_config.go`, `outputguard_config_test.go`}，且四个文件全部在集合内；`tool_output_preview.go` / `governance/runner.go` / `pkg/agent/pi.go` / `runtime_config.go` / **`execenv.go`** 零 diff。**两约束可同时成立的前提**：`execenv.go` 同时落在 `plan §6.2 cmd-05` 的 `M_ZERO` 面，因此 `prepareCRGuard` 的签名必须逐字不变（新增形参会强制改 `execenv.go:731` 的调用点，使本条件与 §6 互斥且 `cmd-05` 硬失败）——本条件与 §6 的签名形态**必须同批复核**。
4. `crguard_config.go` 内 `provider ==` 恰 1 次且为 `"claude"`；含 `prepareOutputGuard` 调用；既有不 clobber 告警句逐字保留。
5. `outputguard_config.go` 含 `// AIFIRST:` 与 `CR-2026-069`，且**不含**任何阈值名或阈值数值。
6. `CUSTOM.md` 含 #95 行（含 `CR-2026-069`、两个文件、`go test` 与「验证：」）。

## 5. 完成标志

- 4 个文件落盘并提交（multica 仓，注释一律**英文**——multica `CLAUDE.md` 硬规则）；验收条件 1~6 的实测命令与结果记入 TASK 完成记录。
- 明确登记「codebuddy / qoder / pi / codex 不写」是**显式设计**（引 §4.9 第 4 步与 D-7 范围澄清），并给出 `crguard_config.go` 的 `provider ==` 计数证据。
- `tasks/_index.yml` 本 TASK 标 `done`。
- **不**包含：为其它 Runtime 新开 daemon 写点；改 `execenv.go`（含其唯一调用点，逐字零 diff）——`prepareCRGuard` 签名不变、挂载输入在函数内经 `prepareOutputGuard(...)` 取得；任何平台 Prompt / 生成物改动（R-15 由 owner 部署窗口承担）；任何共享服务启停。

## 6. 接口契约

**产出（供 TASK-10 冒烟 / AC-12 / AC-19 消费）**

```go
// server/internal/daemon/execenv/outputguard_config.go（新文件；包 execenv；注释英文）
// 挂载解析：从显式环境变量指向的 Tools Release 根解析 output-guard/adapters/<provider>/ 的 hook 入口绝对路径与 policy 路径。
// 只产出「路径引用 + hooks 段对象」，不复制 policy、不读 policy 内容。
func prepareOutputGuard(toolsRoot, provider string) (outputGuardMount, bool)
// 返回 (mount, ok)：ok=false ⇒ 未配置 Tools Release 根或该 provider 不写（显式设计，不报错）

// server/internal/daemon/execenv/crguard_config.go（既有文件；**签名逐字不变**）
// 逐字对照既有形态（multica@94738631 `server/internal/daemon/execenv/crguard_config.go:42`）：
//   func prepareCRGuard(envRoot, workDir, provider, agentCaller string, logger *slog.Logger) (CRGuardResult, error)
// 全仓唯一调用点 = execenv.go:731 的 prepareCRGuard(envRoot, workDir, params.Provider, params.AgentName, logger)
//   ⇒ 本 TASK 不改签名、不改调用点（execenv.go 保持 zero_diff，plan §6.2 cmd-05 的 M_EXACT/M_ZERO 同批成立）
func prepareCRGuard(envRoot, workDir, provider, agentCaller string, logger *slog.Logger) (CRGuardResult, error)
// 函数内取得可空挂载输入：og, ok := prepareOutputGuard(toolsRootFromEnv(), provider)；ok == false ⇒ 空挂载
// ok == false ⇒ 既有行为逐字不变（含 {workDir}/.claude/settings.json 的 JSON 缩进与末尾换行）
// ok == true ∧ provider == "claude" ⇒ 在同一个 settings 对象内合成：既有 hooks 段在前、OutputGuard 段在后，单次写入
// ok == true ∧ provider != "claude" ⇒ 不写任何 hooks 配置（provider == 比较在函数内恰出现 1 次）
// 目标文件已存在 ⇒ 不写/不合并/不覆盖，沿用既有告警句，挂载记为未完成
```

```text
CUSTOM.md《代码改动明细》新增稳定 ID #95（不新造列、不改表头）
  位置：server/internal/daemon/execenv/crguard_config.go（单写入点内合成 OutputGuard hooks，// AIFIRST: 标记）+ outputguard_config.go（新文件；挂载解析）
  验证：cd server && go test ./internal/daemon/execenv/ -count=1 -v -run TestOutputGuard
```

**消费（本 TASK 依赖的上游）**

- TASK-03~TASK-07：五个 Adapter 的 hook 入口路径与模板形状（claude 的 `settings.template.json` 与本文件的合成对象必须同构，见 TASK-04 §3.4）。
- `dep-4`：`prepareCRGuard` 的既有形态与"存在即跳过并告警"语义（只读参照；本 CR **不改其签名**、不改调用点）。
- `dep-15`：每任务写入面不含 hooks 配置文件（本 TASK 的边界依据）。
- `dep-18`：`CUSTOM.md` 的台账结构（按其现状登记，本 TASK 不复制其格式）。
