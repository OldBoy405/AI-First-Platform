---
id: CR-2026-075-TASK-06
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: validate 维度报告层与触发条件对齐
slug: validate-dimension-report-and-trigger
status: pending
estimate: 4h
depends-on: []
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

为 `crctl validate` 新增「维度报告层」并把 validate-doc/AGENTS 的触发条件从 blanket 自动调用改为「调用方步骤规定或用户显式请求」（FR-05；SDD §3.4/§4.6）。既有 artifact/schema 分支（`cr.md`、`_backlog.yml`、评审 YAML 及同名 basename、`test-report.md`、`approval.yml`、`traceability.yml`）的判据、错误码与退出语义逐字不变；`UNKNOWN_ARTIFACT` 纠正集合不扩大。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs` — `cmdValidate(ws, target, gates)`（`crctl.mjs:1517`）的统一外壳（判定目标类型 → 读取声明 → 合并报告）。
- `skills/shared/crctl/scripts/test/crctl.test.mjs` — validate 分支三态向量（B5～B7）。
- `skills/shared/validate-doc/SKILL.md` — 触发条件改写 + WARN/未检查维度语义说明。
- `AGENTS.md` — 第 125 行「写入型 Skill 必须说明如何调用 `validate-doc` 或等价校验」改为「validate-doc 或调用方规定的等价检查」，不新增通用校验闸门。

## 实现要点

- 落点（SDD §3.4）：新增层位于 `cmdValidate` 分支派发之外的统一外壳；既有分支内部零改动。输出在既有 `file`/`valid`/`errors`/`warnings` 之外**新增** `dimensions` 键，既有键与退出码不变（调用方按新增键容错消费）。
- 声明输入：目标项目根 `dir-graph.yaml#knowledge-docs.subdirs.<kind>.{naming,locations}`；`kind` 用既有分支的同一判定；`dir-graph.yaml` 不存在 → 视为未声明。
- 判据四态：
  - 未声明维度 → WARN + `dimensions.notChecked` 显式列出，不进 `errors`，`valid:true` 并继续其他适用维度。
  - 声明存在且文件违反 → 与既有 violations 同一路径进 `errors`、`valid:false`、非零退出。
  - 声明存在但配置畸形（`dir-graph.yaml` 不可解析、`knowledge-docs`/`subdirs`/字段类型错）→ FAIL，复用既有 `SCHEMA_INVALID` 码，不用 WARN 豁免。
  - 既有分支结果逐字不变（含 `prd.md`/`sdd.md` 仍 `UNKNOWN_ARTIFACT`）。
- 当前基线（KB 未声明 `knowledge-docs`）实际可观测的是未声明 WARN 分支；声明违反与声明畸形两个分支必须同样落地（不由 WARN 替代），由三态向量覆盖。
- 触发条件改写：`skills/shared/validate-doc/SKILL.md` 的「任何文档写入/修订完成后；或用户明确要求」→「调用方步骤规定或用户显式请求」，并说明 WARN/未检查维度语义；`AGENTS.md` 同步为「validate-doc 或调用方规定的等价检查」；不新增通用校验闸门、不把校验写成任意写入的强制前置。
- 工程纪律 #1：新增向量读入后先 `\r\n → \n` 规范化，跨行匹配失败硬失败。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["--test","skills/shared/crctl/scripts/test/crctl.test.mjs"]`、timeout=900）全绿。真实运行范围 = 单文件 `crctl.test.mjs`；**不声称覆盖 crctl 全部子命令行为**。新增/调整用例覆盖：
   - AC-B5/B7：合法既有评审 YAML 分支有效；`prd.md`/`sdd.md` 仍 `UNKNOWN_ARTIFACT`；`UNKNOWN_ARTIFACT` 纠正集合未扩大。
   - AC-B6：未声明维度 → WARN + `dimensions.notChecked` 且 `valid:true`；声明存在且违反 → `errors` + 非零；声明存在但配置畸形 → `SCHEMA_INVALID` 非零。三态向量各一条。
   - AC-B2：额外 `validate prd.md` 的 `UNKNOWN_ARTIFACT` 后仍能完成原 PRD 重读自检及后续登记/发布（CLI 侧可观测边界）；调用方一次本地纠正的同 run 计数与失败路由由 TASK-08 的 `cmd-05` 节点回放向量覆盖（见 plan §6.1 FR-04 观测面说明），本 TASK 不另立回放。
2. 在 tools CR worktree 根执行证据命令 `cmd-06`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["--test","skills/shared/crctl/scripts/test/contract-scan.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/lint-prompts.test.mjs"]`、timeout=300）全绿：证明 `AGENTS.md`/`validate-doc` 文本修订未破坏合同一致性、矩阵/Agent 登记与提示 lint。真实运行范围 = 四个单文件合并运行；不声称 tools 仓全量。
3. 输出形状断言：新增 `dimensions` 键只在统一外壳上出现；既有 `file`/`valid`/`errors`/`warnings` 键与退出码在四种场景下逐字保持（含未声明场景 `valid:true`）。
4. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的四个文件。status 仅证明文件集。

## 完成标志

- `cmd-01` 与 `cmd-06` 全绿；三态向量（未声明/违反/畸形）与既有分支回归逐条可见。
- 既有 artifact/schema 分支内部 diff 为零（只改统一外壳与文本）；`SCHEMA_INVALID` 复用而非新增错误码。
- `AGENTS.md` 与 `skills/shared/validate-doc/SKILL.md` 不再出现 blanket 自动调用承诺，也没有新增通用校验闸门。
- 产物已落盘并提交，commit 自含其新增测试；不夹带 TASK-01/03/04/05 对 `crctl.mjs` 的改动（R9 顺序编辑）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- `cmdValidate(ws, target, gates)`（`crctl.mjs:1517`）既有实现：`readFileChecked(p)`、`path.basename(p)` 的 artifact 判定、`errors`/`warnings` 数组与 `fail`/`ok` 出口（`crctl.mjs:1608/1611` 输出 `{file, valid, errors?, warnings?}`）。
- `main()` 的 `validate` 分支（`crctl.mjs:3800-3803`）：`if (!positional[0]) fail('BAD_ARGS', ...)` 后调用 `cmdValidate(ws, positional[0], gates)`，形态不变。
- `detectWorkspace(flags.workspace)`、`loadGates(ws)`：`validate` 仍要求显式合法 root（`CR_DATA_FIRST_WORDS` 既有分类）。

**产出**：

```json
{ "file": "…", "valid": true,
  "dimensions": { "checked": ["frontmatter"],
                  "notChecked": [ { "dimension": "naming", "reason": "not-declared" },
                                  { "dimension": "locations", "reason": "not-declared" } ] },
  "warnings": ["naming：dir-graph 未声明该类型规则，本次未检查"] }
```

- `dimensions` 键为既有输出的**新增**字段；`checked`/`notChecked` 数组元素形状如上（`notChecked` 元素含 `dimension` 与 `reason`）。
- 错误面：声明违反走既有 `errors` 路径（`valid:false` + 非零退出）；配置畸形复用 `SCHEMA_INVALID`；不新增错误码。
- 下游引用同一份契约：TASK-08 的提示收敛引用本 TASK 的触发条件口径（「调用方步骤规定或用户显式请求」）；TASK-10 复跑 `cmd-01`/`cmd-06` 作为 FR-05 证据。
