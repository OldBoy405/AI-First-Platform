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
- `skills/shared/crctl/SKILL.md`（能力表 + workspace 说明 + 调用方本地纠正约定）、`skills/planning/write-planning-entry/SKILL.md`、`skills/competitive/write-competitive-report/SKILL.md`。
- `agent-skill-matrix.yml`、`agents/product-planning-agent.md`、`agents/competitive-analyst-agent.md`、`agents/_index.yml`。
- `pipeline-templates/architecture-design.pipeline.json`、`pipeline-templates/code-implementation.pipeline.json`（受控 CR 后续节点的重复 workspace 示例）。
- `skills/requirement/requirement-register/SKILL.md`、`pipeline-templates/requirement-authoring.pipeline.json`、`README.md`（版本示例口径）。
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`（新命令的分类登记与白名单，并随 `cmd-06` 扫描调用方合同）。
- `change-requests/CR-2026-075/test-evidence/caller-replay/records.json`（KB 仓）：实际受控调用方节点的回放记录（schema `cr-caller-replay/v1`，见下方实现要点「FR-04 实际调用方节点回放」）。
- `ARCHITECTURE.md` §3（绑定归一入口 + 两个业务写入子命令 + 权限/事务边界；只读引用不变量，不改不变量本身）。

## 实现要点

- 12 处补参（`dep-23` 机械清单）：每处 `crctl advance` 补显式 `{cr_id}` 位置参数；`--workspace` 在绑定环境可省，但业务参数（`--to`/`--trigger`/`--expect`）、阶段说明、职责与发布合同不得删除；`review-requirement` 既有「省略 `--expect`」说明保留（状态机双转换）。
- 两个业务 Skill 改为调用受控入口（SDD §8）：`write-planning-entry` 调 `crctl planning-entry --from <confirmed-payload.json>`，消费回执（`exit=0` + 合法 JSON + `phase=complete` + 正确 `changed` + 匹配 `identity`/`artifacts` + 非空 `commit`），校验按调用方步骤触发；`write-competitive-report` 调 `crctl competitive-report --from …`，冲突策略（覆盖/新日期）在 payload 显式给出，正文与 `(date,title)` 去重由模块负责；两者不再直接写文件/索引。
- 定点登记（`dep-19`/`dep-20`）：`agent-skill-matrix.yml` 为 `product-planning-agent`/`competitive-analyst-agent` 声明各自业务操作的 `crctl` 调用关系（Skill 级，不宣称子命令级授权）；`agents/*.md` 与 `agents/_index.yml` 同步声明，`supported` 能力项与 Skill 名一致。
- 分类登记（`dep-25`）：`caller-contract.test.mjs` 把 `planning-entry`、`competitive-report` 归入 `CR_DATA_FIRST_WORDS`（继续断言显式合法 root 分类），`PROJECTED` 不含新命令（无 summary 投影），必要时补 `NON_EXEC_CR_DATA_HITS` 白名单条目（散文提及不算调用点）；`TWO_WORD` 结构不改（DEC-3：两个单词形子命令）。
- 版本口径（FR-13）：`requirement-register` SKILL 与 `requirement-authoring.pipeline.json` 的示例统一推荐 `0.16.0`，说明 v/V 兼容输入与无前缀持久化；`README.md` 只同步总览与权威链接，不复刻可执行细节；不改 `normalizeTargetVersion` 行为与持久化格式。
- FR-14 收敛（SDD §4.9 门槛，**必须先满足**）：只有 ①A1～A8 向量有实际执行证据（TASK-01 的 `cmd-01` 与 TASK-02 的 `cmd-08` 全绿）②Pipeline 与普通 Issue 两条入口的绑定均覆盖 ③绑定冲突/不完整/异根向量零业务写入——三条全部为真后，才删除受控 CR 后续节点中逐命令重复的 `--workspace <workspace>` 示例；门槛未满足则保留原提示，**不得**借「文字已改」宣称行为已变。保留项：execution_context 传递、显式 CR-ID、业务阶段与角色职责、写入/检查/发布要求、共享权威合同短指针；bootstrap 与 daemon 预检示例保留明确根。
- `ARCHITECTURE.md` §3 按 `dep-24` §8 补「绑定归一入口 + 两个业务写入子命令 + 权限/事务边界」，只读引用不变量。
- FR-04 实际调用方节点回放（SDD §5.2；不新建重试服务、执行器或测试框架）：以平台**既有节点/任务运行入口**对实际受控调用方节点执行两个受控变体（候选载体 = 本 CR 自身 Pipeline 节点或平台普通 Issue 委派任务，二者均产生可归因 task/run 记录；不新增执行器），并把可归因记录归档到 KB `change-requests/CR-2026-075/test-evidence/caller-replay/records.json`（schema `cr-caller-replay/v1`）。变体 A = 首调缺根失败（预检零业务写入）→ 同节点同 run 仅补参一次成功；变体 B = 纠正后再次失败 → 停止并落回原异常路径。**输入** = 该节点实际收到的 `execution_context`（`cr_id`/`operationalWorkspace`/`resources[].worktreePath`）、task 绑定环境三值（`MULTICA_TASK_ID`/`CRCTL_OPERATIONAL_WORKSPACE`/`CRCTL_TASK_AUDIT_ROOT`）与调用方短提示（`input.promptRetention` 覆盖 CR-ID、阶段说明、职责/产出、发布合同、bootstrap 显式根示例）。**记录来源** = 该次平台运行可归因的 `source.runId`/`source.nodeId`/`source.attempt`/`source.outputNote`，加逐次调用的 `argv`/`exitCode`/`stderrCode`/`businessWrites`（零业务写入必须为 0）。**断言** = 同 run 调用计数 = 2、纠正次数 = 1、无第三次调用、`autoRetry=false`、`crossRunRestart=false`；A 的 `finalStatus=passed`，B 的 `finalStatus` 非 passed 且 `route` 落回原异常/停止路径。CLI 侧「缺根失败/补参成功」只保留为边界单测（TASK-01 的 `cmd-01`），**不得充作调用方行为验收**；本 TASK 负责受控运行、记录归档与合同文本同批落地，不把回放推给 test-report 分析段。
- 合同一致性：改后 `cmd-06` 全绿（caller-contract/pipeline-structure 在内的六个单文件：调用形态合法、合同/矩阵/Agent 登记一致、提示 lint 通过、Pipeline 模板结构一致）。

## 验收条件

1. 在 knowledge-base（ai-first-platform-docs）CR worktree 根执行证据命令 `cmd-05`（plan §6.2 原样：repo=ai-first-platform-docs、cwd=`.`、executable=`node`、args=`["-e", <只读内联脚本>]`、timeout=300）：全绿。真实运行范围 = 只读消费 `change-requests/CR-2026-075/test-evidence/caller-replay/records.json`（**实际受控调用方节点真实运行产生**的可归因记录）并断言：①两个变体的 `source.runId`/`nodeId`/`attempt`/`outputNote` 归因完整，输入记录含 `execution_context`、绑定环境三值与短提示保留项；②首调缺根非零且 `businessWrites=0`；③同 run 调用计数 = 2、纠正 = 1、无第三次调用、`autoRetry=false`、`crossRunRestart=false`；④A 纠正后 `finalStatus=passed`，B 第二次失败 `finalStatus` 非 passed 且 `route` 落回原异常/停止路径。记录缺失、不可归因或字段不全即非零退出（CLI fixture 不可替代）。
2. 在 tools CR worktree 根执行证据命令 `cmd-06`（plan §6.2 原样：`caller-contract.test.mjs`、`contract-scan.test.mjs`、`check-skill-matrix.test.mjs`、`check-agents-contract.test.mjs`、`lint-prompts.test.mjs`、`pipeline-structure.test.mjs` 六文件合并运行、timeout=300）全绿：调用方合同与命令示例、合同一致性、矩阵/Agent 登记、提示 lint、Pipeline 模板受控节点结构。真实运行范围 = 六个单文件；不声称 tools 仓全量。
3. 在 tools CR worktree 根执行证据命令 `cmd-01`（plan §6.2 原样：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`、timeout=900）全绿：真实调用不在缺位置参数处 `BAD_ARGS`（AC-B11）。
4. 覆盖矩阵断言（逐条对应 AC）：
   - AC-B1：实际调用方节点回放变体 A——首次缺根失败（预检零业务写入）后仅补参一次且第二次调用成功，同 run 调用计数恰为 2、纠正次数 1；与 A1 首次归一区分。
   - AC-B3：回放变体 B——第二次失败后停止自动纠正，无第三次调用、无自动重试与跨 run 重启、失败经原异常路径（权限/绑定冲突或写入不明同路由）。
   - AC-B11：12 处 `crctl advance` 全部含显式 `{cr_id}`；`cmd-06` 的 caller-contract 调用形态扫描不报缺参。
   - AC-B12：版本输入规范化至无前缀值；`unassigned`/禁止值/prerelease 边界维持（`cmd-06` 的合同/提示扫描覆盖）。
   - AC-B13：grant/TTY、写入前提与现实现一致；除限定业务调用登记外不放宽授权/审批/业务范围。
   - AC-B20：两角色矩阵/Agent/Skill/必要索引一致，限定各自操作；不宣称子命令级机器授权。
   - AC-B4：短提示仍含上下文/CR-ID/业务输入输出/职责/发布合同，显式与 bootstrap 说明未误删（`cmd-05` 消费的调用方输入记录断言短提示保留项齐备；`cmd-06` 的 caller-contract 静态断言；「保留项未误删」的边界核对保留为 review-code 人工检查项，静态断言不代替该检查）。
5. FR-14 门槛证据：断言收敛动作发生在 `cmd-01` 与 `cmd-08` 全绿之后（本 TASK commit 的提交说明或节点日志中记录门槛结论）；门槛未满足时，本 TASK 只登记不动文本，并在节点输出中标注「提示保留原样」。
6. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的文件集合（12 处 SKILL 文本所在 7 个文件 + `skills/shared/crctl/SKILL.md` + 两个业务 SKILL + `agent-skill-matrix.yml` + 两个 Agent 文档 + `agents/_index.yml` + 两个 pipeline 模板 + `requirement-register/SKILL.md` + `requirement-authoring.pipeline.json` + `README.md` + `caller-contract.test.mjs` + `ARCHITECTURE.md`）。status 仅证明文件集。

## 完成标志

- `cmd-05`、`cmd-06`、`cmd-01` 全绿；12 处补参逐处可见，业务参数与阶段说明零删除；`cmd-05` 消费的**实际调用方节点回放记录**（变体 A/B、同 run 调用计数 = 2、纠正 = 1、无第三次调用、失败路由）逐条可见且归档 `test-evidence/`。
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
- KB `change-requests/CR-2026-075/test-evidence/caller-replay/records.json` 的记录 schema（本 TASK 产出、`cmd-05` 消费）：字段与断言口径见实现要点「FR-04 实际调用方节点回放」；产出时不得省略 `source.*` 归因字段与逐次调用的四字段（`argv`/`exitCode`/`stderrCode`/`businessWrites`）。

**产出**：

- 登记后的命令分类契约：`planning-entry`、`competitive-report` ∈ `CR_DATA_FIRST_WORDS`（显式合法 root 分类），∉ `PROJECTED`；`TWO_WORD` 不变。
- 受控 CR 后续节点的调用形态契约：节点 prompt 保留 execution_context 传递、显式 CR-ID、业务阶段/职责与发布要求与共享权威合同短指针；删除的是逐命令重复的 `--workspace <workspace>` 示例（绑定环境可省），bootstrap/daemon 预检示例保留明确根。
- 业务 Agent 登记契约：`agent-skill-matrix.yml` 与 `agents/{product-planning-agent,competitive-analyst-agent}.md`、`agents/_index.yml` 声明各自业务操作的 `crctl` 调用关系（Skill 级）；下游 TASK-09 的部署副本收敛引用同一份登记口径。
