---
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

完成调用登记与提示对齐（FR-13、FR-14；SDD §4.6/§4.9、§8）：12 处 `crctl advance` 补显式 `{cr_id}`；两个业务 Agent 的 Skill 级 `crctl` 调用关系定点登记；`crctl SKILL.md` 能力表增补绑定归一与两个业务入口；版本示例统一为 `0.16.0`；在 A 段验证门槛满足后收敛受控 CR 后续节点里重复手填 workspace 的示例（保留 execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根）。

## 涉及文件 / 模块

- 12 处 `crctl advance`：`skills/cr/cr-review-record/SKILL.md`（`:46`、`:47`）、`skills/develop/review-code/SKILL.md`（`:164`、`:165`）、`skills/develop/review-dev-plan/SKILL.md`（`:156`、`:157`）、`skills/develop/review-tech-design/SKILL.md`（`:150`）、`skills/develop/write-dev-tasks/SKILL.md`（`:131`）、`skills/develop/write-tech-design/SKILL.md`（`:50`、`:141`）、`skills/requirement/review-requirement/SKILL.md`（`:61`、`:152`）——只补位置参数，不删业务参数与阶段说明。
- `skills/shared/crctl/SKILL.md`（能力表 + workspace 说明 + **§4.2.1 的调用方本地纠正约定**：同节点同 run 恰一次、第二次只允许把 `--workspace` 换成已确认显式根而其余 argv 逐字不变（SDD §3.2 契约），并**逐条列出「不构成授权来源」负面清单**——清除或覆盖 task 的可信绑定、切回旧 CLI 版本 / 绕过 launcher 直接换可执行体、伪造 `WORKSPACE_REQUIRED` 或任何错误码、以独立测试或在测试内直接调内部函数冒充真实节点回放、把旧环境快照 / `replay.mode` 标签 / 逐次 env 日志当作执行授权、新增第二执行器或权限框架来制造显式环境；漏写该清单即 FR-04 的授权边界在 Skill 文本层失守。该项属 SDD §9 `scope_in` 明文登记的批准范围（承载 FR-04 可达性口径 AC-B1/AC-B3），**不得**移入 `follow_up`，也**不得**以 `scope_out` 的「不新增执行器/权限框架」为由省略——后者约束机器能力，本项是 Skill 文本的调用契约，两者不冲突；机器侧不需要任何新代码**）、`skills/planning/write-planning-entry/SKILL.md`、`skills/competitive/write-competitive-report/SKILL.md`。
- `agent-skill-matrix.yml`、`agents/product-planning-agent.md`、`agents/competitive-analyst-agent.md`、`agents/_index.yml`。
- `pipeline-templates/architecture-design.pipeline.json`、`pipeline-templates/code-implementation.pipeline.json`（受控 CR 后续节点的重复 workspace 示例）。
- `skills/requirement/requirement-register/SKILL.md`、`pipeline-templates/requirement-authoring.pipeline.json`、`README.md`（版本示例口径）。
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`（新命令的分类登记与白名单，并随 `cmd-05` 扫描调用方合同）。
- `ARCHITECTURE.md` §3（绑定归一入口 + 两个业务写入子命令 + 权限/事务边界；只读引用不变量，不改不变量本身）。

## 实现要点

- 12 处补参（`dep-23` 机械清单）：每处 `crctl advance` 补显式 `{cr_id}` 位置参数；`--workspace` 在绑定环境可省，但业务参数（`--to`/`--trigger`/`--expect`）、阶段说明、职责与发布合同不得删除；`review-requirement` 既有「省略 `--expect`」说明保留（状态机双转换）。
- 两个业务 Skill 改为调用受控入口（SDD §8）：`write-planning-entry` 调 `crctl planning-entry --from <confirmed-payload.json>`，消费回执（`exit=0` + 合法 JSON + `phase=complete` + 正确 `changed` + 匹配 `identity`/`artifacts` + 非空 `commit`），校验按调用方步骤触发；`write-competitive-report` 调 `crctl competitive-report --from …`，冲突策略（覆盖/新日期）在 payload 显式给出，正文与 `(date,title)` 去重由模块负责；两者不再直接写文件/索引。
- 定点登记（`dep-19`/`dep-20`）：`agent-skill-matrix.yml` 为 `product-planning-agent`/`competitive-analyst-agent` 声明各自业务操作的 `crctl` 调用关系（Skill 级，不宣称子命令级授权）；`agents/*.md` 与 `agents/_index.yml` 同步声明，`supported` 能力项与 Skill 名一致。
- 分类登记（`dep-25`）：`caller-contract.test.mjs` 把 `planning-entry`、`competitive-report` 归入 `CR_DATA_FIRST_WORDS`（继续断言显式合法 root 分类），`PROJECTED` 不含新命令（无 summary 投影），必要时补 `NON_EXEC_CR_DATA_HITS` 白名单条目（散文提及不算调用点）；`TWO_WORD` 结构不改（DEC-3：两个单词形子命令）。
- 版本口径（FR-13）：`requirement-register` SKILL 与 `requirement-authoring.pipeline.json` 的示例统一推荐 `0.16.0`，说明 v/V 兼容输入与无前缀持久化；`README.md` 只同步总览与权威链接，不复刻可执行细节；不改 `normalizeTargetVersion` 行为与持久化格式。
- FR-14 收敛（SDD §4.9 门槛，**必须先满足**）：只有 ①A1～A8 向量有实际执行证据（TASK-01 的 `cmd-01` 与 TASK-02 的 `cmd-07` 全绿）②Pipeline 与普通 Issue 两条入口的绑定均覆盖 ③绑定冲突/不完整/异根向量零业务写入——三条全部为真后，才删除受控 CR 后续节点中逐命令重复的 `--workspace <workspace>` 示例；门槛未满足则保留原提示，**不得**借「文字已改」宣称行为已变。保留项：execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根。
- `ARCHITECTURE.md` §3 按 `dep-24` §8 补「绑定归一入口 + 两个业务写入子命令 + 权限/事务边界」，只读引用不变量。
- FR-04 的证据面（plan 0.11 口径）：本 CR 内 FR-04 的可观测面收敛为两段——①`cmd-01` 的 CLI 侧边界向量（M2 显式传入空串/纯空白/裸旗标 → `bindTaskWorkspace` 不归一并由既有 `requireExplicitWorkspace` 报 `WORKSPACE_REQUIRED`；M1 真缺参归一成功且全程无错误码；M3 无绑定声明缺根同码；M4 显式异根 `WORKSPACE_CONTEXT_MISMATCH` 且绑定不可被覆盖；`BAD_ARGS` 与空串/裸旗标不进本地纠正集合；第二次失败不自动重试；属边界单测，不冒充调用方行为验收）；②`cmd-05` 的调用方静态合同面（`skills/shared/crctl/SKILL.md` 的「调用方的本地纠正约定（FR-04）」与六条「不构成授权来源」负面清单的文本断言）。**实际受控调用方节点的回放消费面（A、B 两变体的平台原始记录与索引）已按 plan §4 末 follow_up FU-1 整体移出本 CR 验收**：其归因字段（`source.nodeId`、平台节点/run 原始导出、SDD §2.2 形状 `execution_context`、逐次 `argv`/`env`/`exitCode`/`entryResolved`）在当前平台构建的任何可用载体上都没有来源（三条依据见 plan §4 末）。本 CR 内不生成 `change-requests/CR-2026-075/test-evidence/caller-replay/` 的任何记录，**不得**以手工 CLI 调用、平台 run 导出面、旧环境快照、`replay.mode` 标签或逐次 `env` 日志冒充回放证据（SDD §4.2.1/§7 负面清单），也不得表述为「节点回放已通过」；FU-1 的未覆盖事实（观测面 < 声称面）由 TASK-10 记入 `test-evidence/uncovered-risks.md`。
- 合同一致性：改后 `cmd-05` 全绿（caller-contract/pipeline-structure 在内的六个单文件：调用形态合法、合同/矩阵/Agent 登记一致、提示 lint 通过、Pipeline 模板结构一致）。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-05`（plan §6.2 原样：`caller-contract.test.mjs`、`contract-scan.test.mjs`、`check-skill-matrix.test.mjs`、`check-agents-contract.test.mjs`、`lint-prompts.test.mjs`、`pipeline-structure.test.mjs` 六文件合并运行、timeout=300）全绿：调用方合同与命令示例、合同一致性、矩阵/Agent 登记、提示 lint、Pipeline 模板受控节点结构。真实运行范围 = 六个单文件；不声称 tools 仓全量。
2. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`、timeout=900）全绿：真实调用不在缺位置参数处 `BAD_ARGS`（AC-B11）。
3. 覆盖矩阵断言（逐条对应 AC）：
- AC-B1：本 CR 内取证面 = `cmd-01` 的 M2 CLI 侧边界向量（有效绑定下显式传入不可用 `--workspace` → 不归一并报 `WORKSPACE_REQUIRED`；M1 真缺参归一成功全程无错误码，二者即「A1 与 B1 区分点」）与 `cmd-05` 的调用方静态合同面；「同节点同 run 恰一次纠正」的调用方节点回放面（A 变体：首调 M2 面 → 同节点同 run 仅把该参数换成已确认显式根一次成功）**已按 plan FU-1 移出本 CR 验收**，不作为本 TASK 的完成前置，也不得以任何替代物补齐。
- AC-B3：本 CR 内取证面 = `cmd-01` 的 M4 入口向量（显式异根 → `WORKSPACE_CONTEXT_MISMATCH`，绑定不可被覆盖）与「第二次失败不自动重试」、`BAD_ARGS`／权限或路径拒绝／其它上下文冲突／写入或提交结果不明等停止面向量，以及 `cmd-05` 的静态合同面；B 变体的节点回放面（有效绑定下纠正后取 M4 面、两次逐次环境逐字相等以证绑定未被覆盖、落回原异常路径）**已按 plan FU-1 移出本 CR 验收**。
   - AC-B11：12 处 `crctl advance` 全部含显式 `{cr_id}`；`cmd-05` 的 caller-contract 调用形态扫描不报缺参。
   - AC-B12：版本输入规范化至无前缀值；`unassigned`/禁止值/prerelease 边界维持（`cmd-05` 的合同/提示扫描覆盖）。
   - AC-B13：grant/TTY、写入前提与现实现一致；除限定业务调用登记外不放宽授权/审批/业务范围。
   - AC-B20：两角色矩阵/Agent/Skill/必要索引一致，限定各自操作；不宣称子命令级机器授权。
   - AC-B4：短提示仍含上下文/CR-ID/业务输入输出/职责/发布合同，显式与 bootstrap 说明未误删（`cmd-05` 的 caller-contract 静态断言面；短提示原文逐字投影与五项保留片段核对属 FU-1 的回放面，不在本 CR 取证；「保留项未误删」的边界核对保留为 review-code 人工检查项，静态断言不代替该检查）。
4. FR-14 门槛证据：断言收敛动作发生在 `cmd-01` 与 `cmd-07` 全绿之后（本 TASK commit 的提交说明或节点日志中记录门槛结论）；门槛未满足时，本 TASK 只登记不动文本，并在节点输出中标注「提示保留原样」。
5. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的文件集合（12 处 SKILL 文本所在 7 个文件 + `skills/shared/crctl/SKILL.md` + 两个业务 SKILL + `agent-skill-matrix.yml` + 两个 Agent 文档 + `agents/_index.yml` + 两个 pipeline 模板 + `requirement-register/SKILL.md` + `requirement-authoring.pipeline.json` + `README.md` + `caller-contract.test.mjs` + `ARCHITECTURE.md`）。status 仅证明文件集。

## 完成标志

- `cmd-01` 与 `cmd-05` 全绿；12 处补参逐处可见，业务参数与阶段说明零删除；`cmd-05` 的 caller-contract 静态断言面（`skills/shared/crctl/SKILL.md` 的「调用方的本地纠正约定（FR-04）」与**逐条六条「不构成授权来源」负面清单**）逐条可见（漏写即 FR-04 授权边界在 Skill 文本层失守）；FR-04 的节点回放消费面按 plan FU-1 不在本 CR 取证，本 TASK 不产出任何 `test-evidence/caller-replay/` 记录，未清除或覆盖 task 绑定、未切 CLI 版本、未伪造错误码、未以独立测试冒充节点、未新增第二执行器或权限框架。
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
