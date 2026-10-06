---
spec-id: ai-first-platform
version: "0.48"
id: CR-2026-075-TASK-08
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: 调用登记、命令示例与提示收敛
slug: caller-registration-and-prompt-convergence
status: pending
estimate: 8h
depends-on: [CR-2026-075-TASK-01, CR-2026-075-TASK-02, CR-2026-075-TASK-04, CR-2026-075-TASK-05, CR-2026-075-TASK-06, CR-2026-075-TASK-07]
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

完成调用登记与提示对齐（FR-13、FR-14；SDD §4.6/§4.9、§8）：12 处 `crctl advance` 补显式 `{cr_id}`；两个业务 Agent 的 Skill 级 `crctl` 调用关系定点登记；`crctl SKILL.md` 能力表增补绑定归一与两个业务入口；版本示例统一为 `0.16.0`；在 A 段验证门槛满足后收敛受控 CR 后续节点里重复手填 workspace 的示例（保留 execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根）。本 TASK 同时是 FR-04 三段取证面（plan §4 末第三、四条）的唯一 owner：段① `crctl.test.mjs` 的有效绑定补验、段② `caller-contract.test.mjs` 的调用方合同逐条断言、段③ 在带 `execution_context` 声明的受控调用方节点内实际执行 A/B 两变体并归档 `test-evidence/caller-replay/`。

## 涉及文件 / 模块

- 12 处 `crctl advance`：`skills/cr/cr-review-record/SKILL.md`（`:46`、`:47`）、`skills/develop/review-code/SKILL.md`（`:164`、`:165`）、`skills/develop/review-dev-plan/SKILL.md`（`:156`、`:157`）、`skills/develop/review-tech-design/SKILL.md`（`:150`）、`skills/develop/write-dev-tasks/SKILL.md`（`:131`）、`skills/develop/write-tech-design/SKILL.md`（`:50`、`:141`）、`skills/requirement/review-requirement/SKILL.md`（`:61`、`:152`）——只补位置参数，不删业务参数与阶段说明。
- `skills/shared/crctl/SKILL.md`（能力表 + workspace 说明 + **§4.2.1 的调用方本地纠正约定**：同节点同 run 恰一次、第二次只允许把 `--workspace` 换成已确认显式根而其余 argv 逐字不变（SDD §3.2 契约），并**逐条列出「不构成授权来源」负面清单**——清除或覆盖 task 的可信绑定、切回旧 CLI 版本 / 绕过 launcher 直接换可执行体、伪造 `WORKSPACE_REQUIRED` 或任何错误码、以独立测试或在测试内直接调内部函数冒充真实节点回放、把旧环境快照 / `replay.mode` 标签 / 逐次 env 日志当作执行授权、新增第二执行器或权限框架来制造显式环境；漏写该清单即 FR-04 的授权边界在 Skill 文本层失守。该项属 SDD §9 `scope_in` 明文登记的批准范围（承载 FR-04 可达性口径 AC-B1/AC-B3），**不得**移入 `follow_up`，也**不得**以 `scope_out` 的「不新增执行器/权限框架」为由省略——后者约束机器能力，本项是 Skill 文本的调用契约，两者不冲突；机器侧不需要任何新代码**）、`skills/planning/write-planning-entry/SKILL.md`、`skills/competitive/write-competitive-report/SKILL.md`。
- `agent-skill-matrix.yml`、`agents/product-planning-agent.md`、`agents/competitive-analyst-agent.md`、`agents/_index.yml`。
- `pipeline-templates/architecture-design.pipeline.json`、`pipeline-templates/code-implementation.pipeline.json`（受控 CR 后续节点的重复 workspace 示例）。
- `skills/requirement/requirement-register/SKILL.md`、`pipeline-templates/requirement-authoring.pipeline.json`、`README.md`（版本示例口径）。
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`（新命令的分类登记与白名单，并随 `cmd-05` 扫描调用方合同；段②的 FR-04 调用方纠正约定与六条负面清单逐条文本断言亦落在本文件）。
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（**0.12 补验**：段①的有效绑定场景断言，plan §4 末第四条第 1 项）。本文件与 TASK-01/06 同编辑，属 R9 跨 TASK 共享文件：TASK-01/06 已 `done` 且其提交已落地（tools HEAD `48ad150`），本轮为**顺序追加编辑**——只新增用例、不改写 TASK-01/06 既有断言语义；与 TASK-06 的 validate 分支向量在同文件内互不覆盖。
- `ARCHITECTURE.md` §3（绑定归一入口 + 两个业务写入子命令 + 权限/事务边界；只读引用不变量，不改不变量本身）。

## 实现要点

- 12 处补参（`dep-23` 机械清单）：每处 `crctl advance` 补显式 `{cr_id}` 位置参数；`--workspace` 在绑定环境可省，但业务参数（`--to`/`--trigger`/`--expect`）、阶段说明、职责与发布合同不得删除；`review-requirement` 既有「省略 `--expect`」说明保留（状态机双转换）。
- 两个业务 Skill 改为调用受控入口（SDD §8）：`write-planning-entry` 调 `crctl planning-entry --from <confirmed-payload.json>`，消费回执（`exit=0` + 合法 JSON + `phase=complete` + 正确 `changed` + 匹配 `identity`/`artifacts` + 非空 `commit`），校验按调用方步骤触发；`write-competitive-report` 调 `crctl competitive-report --from …`，冲突策略（覆盖/新日期）在 payload 显式给出，正文与 `(date,title)` 去重由模块负责；两者不再直接写文件/索引。
- 定点登记（`dep-19`/`dep-20`）：`agent-skill-matrix.yml` 为 `product-planning-agent`/`competitive-analyst-agent` 声明各自业务操作的 `crctl` 调用关系（Skill 级，不宣称子命令级授权）；`agents/*.md` 与 `agents/_index.yml` 同步声明，`supported` 能力项与 Skill 名一致。
- 分类登记（`dep-25`）：`caller-contract.test.mjs` 把 `planning-entry`、`competitive-report` 归入 `CR_DATA_FIRST_WORDS`（继续断言显式合法 root 分类），`PROJECTED` 不含新命令（无 summary 投影），必要时补 `NON_EXEC_CR_DATA_HITS` 白名单条目（散文提及不算调用点）；`TWO_WORD` 结构不改（DEC-3：两个单词形子命令）。
- 版本口径（FR-13）：`requirement-register` SKILL 与 `requirement-authoring.pipeline.json` 的示例统一推荐 `0.16.0`，说明 v/V 兼容输入与无前缀持久化；`README.md` 只同步总览与权威链接，不复刻可执行细节；不改 `normalizeTargetVersion` 行为与持久化格式。
- FR-14 收敛（SDD §4.9 门槛，**必须先满足**）：只有 ①A1～A8 向量有实际执行证据（TASK-01 的 `cmd-01` 与 TASK-02 的 `cmd-07` 全绿）②Pipeline 与普通 Issue 两条入口的绑定均覆盖 ③绑定冲突/不完整/异根向量零业务写入——三条全部为真后，才删除受控 CR 后续节点中逐命令重复的 `--workspace <workspace>` 示例；门槛未满足则保留原提示，**不得**借「文字已改」宣称行为已变。保留项：execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根。
- `ARCHITECTURE.md` §3 按 `dep-24` §8 补「绑定归一入口 + 两个业务写入子命令 + 权限/事务边界」，只读引用不变量。
- FR-04 的证据面（plan 0.12 口径 = 已批准 SDD §4.2.1/§5.2 的三段面；本 TASK 是三段的全部 owner，见 plan §4 末「0.12 前提更正与 FR-04 批准验收恢复记录」第三、四条）。三段各有唯一 owner 与载体，**载体互不冒充**，任一段缺失即 FR-04 不通过：
  - **段①（CLI 机器语义，owner = 本 TASK 补验，载体 `cmd-01`）**：M1 真缺参归一成功且全程无错误码；M2 有效绑定下显式传入空串/纯空白/裸旗标 → `bindTaskWorkspace` 不归一并由既有 `requireExplicitWorkspace` 报 `WORKSPACE_REQUIRED`；M3 无绑定声明缺根同码；M4 显式异根 `WORKSPACE_CONTEXT_MISMATCH` 且绑定不可被覆盖；补已确认同根（含合法别名）一次成功 `status=0`；同真实目录/合法别名接受；`BAD_ARGS` 与空串/裸旗标不进本地纠正集合；第二次失败后 `snapshot()` 逐字不变、stdout 无成功回执、stderr 单一 JSON、crctl 侧无自动重试副作用。**0.12 补验义务（§4 末第四条第 1 项，实测缺口）**：tools HEAD `48ad150` 的 `crctl.test.mjs:628-648` 用 `runCrctl(argv)` **无绑定**场景，`fixed` 只断言 `error.code !== 'WORKSPACE_REQUIRED'`、无 `status===0` 断言，空串/纯空白/裸旗标三例（`:641-645`）未传 `bind3`。须在 `crctl.test.mjs` 复用同文件既有 `bind3`/`snapshot` helper（`:490`/`:495`）增补**有效绑定**场景断言：M2 三例 `bind3(...)` 下非零 + `WORKSPACE_REQUIRED`；补同根（含合法别名）一次成功 `status===0` 且 stdout 合法 JSON；补异根非零 + `WORKSPACE_CONTEXT_MISMATCH` + `snapshot()` 逐字不变 + stdout 无成功回执。完成条件 = `cmd-01` 绿**且**上述断言在 `crctl.test.mjs` 中逐条可见。SDD §9 `zero_diff` 声明 FR-04 机器面零改动，段①即 FR-04 全部机器语义的落点，属边界单测，**不冒充调用方行为验收**。
  - **段②（调用方静态合同，owner = 本 TASK，载体 `cmd-05`）**：`skills/shared/crctl/SKILL.md` 的「调用方的本地纠正约定（FR-04）」五项前置、同 run 恰一次、纠正只改 `--workspace` 一个参数、机器侧零改动、审计保留，与六条「不构成授权来源」负面清单**逐条**文本断言。**0.12 补验义务（§4 末第四条第 2 项，实测缺口）**：六个 `cmd-05` 文件当前对 `FR-04`/`本地纠正`/`不构成授权来源`/`第二次` 的专项断言检索计数全为 0（`caller-contract.test.mjs:349-382` 实为 `complete=false`/`--detail`/显式 workspace 三项检查）。须在 `caller-contract.test.mjs`（本 TASK 声明文件）增补上述逐条断言，含六条负面清单逐条：清除或覆盖 task 的可信绑定、切回旧 CLI 版本或绕过 launcher 直接换可执行体、伪造 `WORKSPACE_REQUIRED` 或任何错误码、以独立测试或在测试内直接调内部函数冒充真实节点回放、把旧环境快照/`replay.mode` 标签/逐次 `env` 日志当作执行授权、新增第二执行器或权限框架来制造显式环境。完成条件 = `cmd-05` 绿**且**上述断言逐条可见；**不得**以「SKILL.md 已有该文本」替代断言本身（已落地文本 ≠ 已断言）。本段不证明任何调用方行为，只证明文本合同存在。
  - **段③（实际受控调用方节点的节点日志/回放，owner = 本 TASK 生产 + 归档，载体 = 归档记录，非 `cmd-NN`）**：A 变体（S1/M2）——同节点同 run 首调以不可用 `--workspace` 触发 `WORKSPACE_REQUIRED` 且零业务写入 → 仅把该参数换成该 run 的已确认显式根（等于本 run 的 `CRCTL_OPERATIONAL_WORKSPACE`，与声明的 `execution_context.operational_workspace` 同根、为本机存在目录）→ 一次成功；纠正次数 = 1、无第三次调用、无恢复委派、无版本扫描。B 变体（M4）——有效绑定下把该参数补成异根 → `WORKSPACE_CONTEXT_MISMATCH`、绑定未被覆盖、停止自动纠正、落回原异常路径、stdout 无成功回执。前置「带 `execution_context` 声明的实际调用方节点获得可信绑定」由 SDD §4.2.1 S1 + multica `pipeline_task.go:201-239` 普通委派分支 + `daemon.go:8650` 满足，已由 TASK-02 落地并在 plan 0.12 本 run 实测生效。**归档面**：`change-requests/CR-2026-075/test-evidence/caller-replay/records.json` + `{A,B}.node-record.json`，由该次节点对其两次实际执行原样摘录；记录字段清单（逐条必须可核对）= 两次调用的 `argv`、`exitCode`、stderr 单一 JSON、两次逐次绑定三值、纠正次数、是否发生第三次调用、有无恢复委派/版本扫描、stdout 是否含成功回执、零业务写入的证明。核对 = `write-test-report` 机器区引用 + `review-code` 逐条人工检查（同 AC-B4 口径）。**该段不由任何 `cmd-NN` 断言**（SDD §5.2 B1/B3 落点为「真实节点日志/回放」、§4.2.1 计数口径为「按每条适用节点回放衡量、不宣称跨 run 机器硬保证」）。
  - **段③的逐条守则（SDD §4.2.1 六条负面清单，违反即该段证据无效）**：不清除或覆盖 task 绑定、不切 CLI 版本或绕过 launcher、不伪造 `WORKSPACE_REQUIRED` 或任何错误码、不以独立测试或测试内直调内部函数冒充节点回放、不把旧环境快照/`replay.mode` 标签/逐次 `env` 日志当作执行授权、不新增第二执行器或权限框架来制造显式环境。本 CR **接受**生成 `test-evidence/caller-replay/`，`cmd-01`/`cmd-05` 绿只证明段①②，**不得**冒充段③，也不得表述为「节点回放已由 `cmd-01`/`cmd-05` 通过」。
- S2（M3）在本 CR 内只作字面来源登记：本 CR 三类节点均有可信绑定（`dep-27`/`dep-28`），S2 不在本 CR 节点内产生节点日志，其机器行为由 A6 向量（`cmd-01`）覆盖，**不得**以「造一个无绑定环境」充当 S2 证据。
- 合同一致性：改后 `cmd-05` 全绿（caller-contract/pipeline-structure 在内的六个单文件：调用形态合法、合同/矩阵/Agent 登记一致、提示 lint 通过、Pipeline 模板结构一致）。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-05`（plan §6.2 原样：`caller-contract.test.mjs`、`contract-scan.test.mjs`、`check-skill-matrix.test.mjs`、`check-agents-contract.test.mjs`、`lint-prompts.test.mjs`、`pipeline-structure.test.mjs` 六文件合并运行、timeout=300）全绿：调用方合同与命令示例、合同一致性、矩阵/Agent 登记、提示 lint、Pipeline 模板受控节点结构。真实运行范围 = 六个单文件；不声称 tools 仓全量。
2. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`、timeout=900）全绿：真实调用不在缺位置参数处 `BAD_ARGS`（AC-B11）。
3. 覆盖矩阵断言（逐条对应 AC）：
- AC-B1：三段取证面按 plan §4 末第三、四条逐段闭合。**段①** = `cmd-01` 的有效绑定场景边界向量（M2 显式传入不可用 `--workspace` → 不归一并报 `WORKSPACE_REQUIRED`；M1 真缺参归一成功全程无错误码，二者即「A1 与 B1 区分点」），含本 TASK 补验的 M2 三例 `bind3(...)` 非零 + `WORKSPACE_REQUIRED`、补已确认同根一次成功 `status===0`。**段②** = `cmd-05` 的调用方静态合同面（SKILL.md 的 FR-04 本地纠正约定 + 六条负面清单逐条断言）。**段③** = 「同节点同 run 恰一次纠正」的 A 变体节点日志/回放（首调 M2 面 → 同节点同 run 仅把该参数换成已确认显式根一次成功，纠正次数 = 1、无第三次调用），归档到 `test-evidence/caller-replay/records.json` + `A.node-record.json`。三段载体互不冒充：`cmd-01`/`cmd-05` 绿不证明段③，段③归档不证明段①②；任一段缺失即 AC-B1 不通过、本 TASK 不 done。
- AC-B3：**段①** = `cmd-01` 的 M4 入口向量（显式异根 → `WORKSPACE_CONTEXT_MISMATCH`，绑定不可被覆盖）与「第二次失败不自动重试」、`BAD_ARGS`／权限或路径拒绝／其它上下文冲突／写入或提交结果不明等停止面向量，补验须断言第二次失败后 `snapshot()` 逐字不变 + stdout 无成功回执 + stderr 单一 JSON；**段②** = `cmd-05` 的静态合同面。**段③（B 变体）** = 有效绑定下纠正后取 M4 面、两次逐次绑定三值逐字相等以证绑定未被覆盖、停止自动纠正、落回原异常路径、stdout 无成功回执，归档到 `test-evidence/caller-replay/records.json` + `B.node-record.json`。段③同样不由任何 `cmd-NN` 断言，缺失即 AC-B3 不通过。
   - AC-B11：12 处 `crctl advance` 全部含显式 `{cr_id}`；`cmd-05` 的 caller-contract 调用形态扫描不报缺参。
   - AC-B12：版本输入规范化至无前缀值；`unassigned`/禁止值/prerelease 边界维持（`cmd-05` 的合同/提示扫描覆盖）。
   - AC-B13：grant/TTY、写入前提与现实现一致；除限定业务调用登记外不放宽授权/审批/业务范围。
   - AC-B20：两角色矩阵/Agent/Skill/必要索引一致，限定各自操作；不宣称子命令级机器授权。
   - AC-B4：短提示仍含上下文/CR-ID/业务输入输出/职责/发布合同，显式与 bootstrap 说明未误删。核对面 = `cmd-05` 段②静态文本断言 + `test-evidence/caller-replay/` 段③归档的短提示原文逐字投影与五项保留片段核对 + `review-code` 人工检查项（「保留项未误删」的边界核对，静态断言与归档均不代替该检查）。
4. FR-14 门槛证据：断言收敛动作发生在 `cmd-01` 与 `cmd-07` 全绿之后（本 TASK commit 的提交说明或节点日志中记录门槛结论）；门槛未满足时，本 TASK 只登记不动文本，并在节点输出中标注「提示保留原样」。
5. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的文件集合（12 处 SKILL 文本所在 7 个文件 + `skills/shared/crctl/SKILL.md` + 两个业务 SKILL + `agent-skill-matrix.yml` + 两个 Agent 文档 + `agents/_index.yml` + 两个 pipeline 模板 + `requirement-register/SKILL.md` + `requirement-authoring.pipeline.json` + `README.md` + `caller-contract.test.mjs` + `crctl.test.mjs` + `ARCHITECTURE.md`）。KB 仓侧另有本 TASK 段③归档的 `change-requests/CR-2026-075/test-evidence/caller-replay/`（`records.json` + `{A,B}.node-record.json`），在 KB worktree 根以同一受控入口单列检查，不混入 tools 侧文件集断言。status 仅证明文件集。

## 完成标志

- `cmd-01` 与 `cmd-05` 全绿；12 处补参逐处可见，业务参数与阶段说明零删除。FR-04 三段面逐段闭合且互不冒充：**段①** `cmd-01` 绿且有效绑定补验断言（M2 三例 `bind3(...)` 非零 + `WORKSPACE_REQUIRED`、补同根 `status===0`、异根 `WORKSPACE_CONTEXT_MISMATCH` + `snapshot()` 逐字不变）在 `crctl.test.mjs` 中逐条可见；**段②** `cmd-05` 绿且「调用方的本地纠正约定（FR-04）」与**六条「不构成授权来源」负面清单逐条**断言在 `caller-contract.test.mjs` 中逐条可见（漏写即 FR-04 授权边界在 Skill 文本层失守，已落地文本 ≠ 已断言）；**段③** 本 TASK 在带 `execution_context` 声明的受控调用方节点内实际执行 A/B 两变体，并把两次执行原样摘录归档到 `test-evidence/caller-replay/records.json` + `{A,B}.node-record.json`，字段清单（`argv`/`exitCode`/stderr 单一 JSON/两次逐次绑定三值/纠正次数/有无第三次调用/有无恢复委派或版本扫描/stdout 是否含成功回执）逐条可核对。归档全程未清除或覆盖 task 绑定、未切 CLI 版本、未伪造错误码、未以独立测试或静态断言冒充节点回放、未新增第二执行器或权限框架。
- 两个业务 Skill 的实际调用形态为 `crctl planning-entry --from …` / `crctl competitive-report --from …`（消费回执字段与本 CR 契约一致）；矩阵/Agent/索引登记一致，只声明 Skill 级关系。
- FR-14 收敛以门槛结论为前提：满足则删除重复 workspace 示例并保留全部保留项；未满足则保留原提示，两者都在节点输出中留证。
- `ARCHITECTURE.md` §3 已补记绑定归一与两个业务入口（不改不变量）；版本示例统一 `0.16.0`。
- 产物已落盘并提交，commit 自含其新增/调整测试；不改 multica 仓（部署副本与台账属 TASK-09）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- TASK-01 的 `bindTaskWorkspace` 归一语义与 `WORKSPACE_CONTEXT_MISMATCH` 失败面（用于改写 workspace 说明）。
- TASK-02 的绑定发布面与三条 A 段向量结果（FR-14 门槛证据）。
- TASK-04/05 的命令面与回执契约（`crctl planning-entry`/`crctl competitive-report` 的 `--from`、`identity`/`artifacts`/`commit`/`phase`），两个业务 SKILL 逐字引用，不缩写字段。
- TASK-06 的 validate 触发条件口径（「调用方步骤规定或用户显式请求」）与 `dimensions` 语义。
- `caller-contract.test.mjs` 既有结构：`PROJECTED = ['crctl advance','crctl review-record','crctl status','crctl workspace inspect']`、`TWO_WORD = new Set(['workspace','task','merge','kb'])`、`CR_DATA_FIRST_WORDS`（含 `'task'`、`'validate'`、`'git'`、`'kb'` 等）与 `NON_EXEC_CR_DATA_HITS` 白名单。

**产出**：

- 登记后的命令分类契约：`planning-entry`、`competitive-report` ∈ `CR_DATA_FIRST_WORDS`（显式合法 root 分类），∉ `PROJECTED`；`TWO_WORD` 不变。
- 受控 CR 后续节点的调用形态契约：节点 prompt 保留 execution_context 传递、显式 CR-ID、业务阶段/职责与发布要求与共享权威合同短指针；删除的是逐命令重复的 `--workspace <workspace>` 示例（绑定环境可省），bootstrap/daemon 预检示例保留明确根。
- 业务 Agent 登记契约：`agent-skill-matrix.yml` 与 `agents/{product-planning-agent,competitive-analyst-agent}.md`、`agents/_index.yml` 声明各自业务操作的 `crctl` 调用关系（Skill 级）；下游 TASK-09 的部署副本收敛引用同一份登记口径。
