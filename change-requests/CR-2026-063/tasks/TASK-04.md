---
id: CR-2026-063-TASK-04
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: "Prompt/文档案位归位与委派合同收紧（multica 4 文件 + tools 6 处）与范围收口核对"
slug: prompt-source-placement-and-delegation-contract
status: pending
estimate: 16h
depends-on: [CR-2026-063-TASK-01, CR-2026-063-TASK-02, CR-2026-063-TASK-03]
created: 2026-09-11T22:54:10+08:00
---

# CR-2026-063-TASK-04 —— Prompt/文档案位归位与委派合同收紧、范围收口

覆盖 FR：**FR-1①②、FR-3、FR-4、FR-5、FR-6、FR-10、FR-11**（SDD §6 FR-1①②/FR-3/FR-4/FR-5/FR-6/FR-10/FR-11）；变更组 G4；主责仓：`multica` + `tools`。

## 1. 任务描述

**目标**：① 两份 multica 部署副本的 `_context.md` 合同段落原位退役为 canonical resume 口径；② `CUSTOM.md#75` 职责单元格原位重写为「公共 Prompt 事实源 = `tools/agents/`、coordinator = Multica 专属 overlay、DB 是部署投影」；③ coordinator overlay 三节按 SDD §6.2 逐字替换；④ `tools/agents/dev-agent.md` 的委派路由合同收紧为六条；⑤ `skills/shared/crctl/SKILL.md` + 4 份 review SKILL 补写 YAML 子集（单行标量）边界说明；⑥ 反向验收（AC-4）与交付 diff 白名单核对（AC-11）。

**背景**：旧副本与 DB 投影被当成第二事实源、委派链把 Skill 步骤复述进评论、payload 的 YAML 子集边界未写在 SKILL 里——这些都是「流程正确性」的根因（PRD §1.1）。

**输入条件**：`CR-2026-063-TASK-01/02/03` 已完成；`crctl workspace freshness CR-2026-063`（gate=implement-start）通过；SDD `ce51c168…` 与 PRD `9247c107…` 只读。

## 2. 涉及文件 / 模块

| 文件 | 仓 / 相对路径 | 改动性质 |
|---|---|---|
| multica 部署副本 1 | `cr-prompts-revised/dev-agent.md`（`## 环境与代码边界` 末段，基线 L47） | **整段替换**（不得「保留旧段 + 段后追加说明」） |
| multica 部署副本 2 | `cr-prompts-revised/quality-reviewer-agent.md`（`## 入口识别与证据` 首段，基线 L19） | 段内删除 `_context.md` 引用并改写为 canonical 证据面 |
| multica overlay | `cr-prompts-revised/cr-coordinator-agent.md`（`## 委派与评论`、`## 评审闭环` 标准入口段、`## 失败与输出` 第 1 条 bullet） | 三处按 SDD §6.2 **逐字替换**（块 1 整节含标题行；块 2 仅标准入口段；块 3 两行替换块） |
| multica 台账 | `CUSTOM.md`（第 75 行第 3 列单元格，基线 L387） | 同一单元格内重写（五要素）；不新增行、不改表结构、不动其它行 |
| tools 公共 Prompt | `agents/dev-agent.md`（`## 委派路由合同（评审）`，基线 L31） | 节内原位收紧为六条要求，保留三条既有内容 |
| tools SKILL 文档 | `skills/shared/crctl/SKILL.md`（`review-record` 行，基线 L34）+ `skills/requirement/review-requirement/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md` | 既有 payload 示例处**原位补写**同一约束注释；不新增字段、不改示例结构 |

**不得触碰**（SDD §9 `zero_diff` / `scope_out`）：`tools/agents/_index.yml`、`tools/agent-skill-matrix.yml`、`multica/cr-prompts-revised/agent-skill-matrix.yml`（AC-4 反向验收对象）；`multica/aifirst/agent-import.mjs`、平台 DB；`lib/yaml-subset.mjs`；`rules.json`；`pipeline-templates/**`；`write-requirement-prd/SKILL.md`；除上表 4 个 multica 文件外的任何 multica 文件。

## 3. 实现要点

1. **FR-1① 替换段落（本 TASK 的措辞裁决，见 R-13）**：目标段落内**不得出现 `_context.md` 文件名指称**（SDD §6.1 AC-1① 与 §4.5 计入集合要求该文件命中 0；PRD §1.5「两份部署副本归零」）。规定文本：
   ```text
   不得手工修改受控账本、`review-annotations`、`review-loop`、`traceability` 或 `specs/`；对应写入必须经专用 Skill/crctl。恢复或返工时直接读取 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；不得创建或读取工作流上下文缓存副本，也不得让缓存替代状态、评审证据或门禁。
   ```
   （与来源 §3.1.1 / PRD FR-1① 的唯一差别 = 禁止句不写出文件名，语义不变、口径自洽；否则 AC-1①/AC-2 的机械判据必然失败。）
2. **FR-1② 段落**（来源 §3.1.2 目标文本）：
   ```text
   评审前读取目标 workspace `dir-graph.yaml`、`crctl status/next` 返回、当前 CR canonical 产物和该 Skill 指定的证据；canonical 事实优先于缓存、评论和执行方自报。
   ```
   （首句「不凭评论文字猜阶段」等原文保留；段内不得出现 `_context.md`。）
3. **FR-5 三节替换**：目标文本、替换边界、逐块 `sha256`、块 3 的两行替换块形态与整文件派生哈希**全部以 SDD §6.2 为唯一锚点**（本计划不复述）：块 1 = `## 委派与评论` 整节（含标题行，按 §6.2 边界到该节最后一个非空内容行）；块 2 = `## 评审闭环` 内首个非空段（单行）；块 3 = `## 失败与输出` 第 1 条既有 bullet 后插入「两个半角空格 + 插入段正文」（旧 bullet 行逐字保留、不得换成其它列表标记）。三块**逐字复制、不得转述**；除替换边界外不得改动标点、空格、换行或反引号；保留 `## 职责`、`## 事实源与读取`、`## 路由`、`## 平台层权限` 四节与 frontmatter 原样，不追加第五节。
4. **FR-3 `CUSTOM.md#75` 单元格**：同一单元格内写全五要素——①公共 Agent Prompt 唯一事实源 = `tools/agents/`；②`cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；③目录内公共 Prompt 副本**不再独立演进**（owner 部署时以 tools 同名文件覆盖平台公共 Agent）；④DB 是部署**投影**、不是事实源；⑤`cr-coordinator-agent` 不进入 tools **agent index**。**不新增登记行**、不改表头与其它行、不动第 4 列历史 provenance。
5. **FR-6 `tools/agents/dev-agent.md`**：`## 委派路由合同（评审）` 节内保留既有三条（作者不得自评／创建路径必须携带可信来源上下文／不支持时停在 review 节点提示另开独立会话，不得退化为作者自评），并写入六条要求：①每轮评审使用**新的** reviewer `task/run`；②标准节点走 Pipeline `Runner`；③只传 review Skill 已声明的结构化输入与 `canonical` 引用（CR-ID、权威 workspace、resources 原样值）；④不在委派评论中复述 Skill 步骤、门禁命令、`advance` 参数或 blocker 修法；⑤只读命令出现零写入 `BAD_ARGS` 时可按 crctl 明示的恢复方向恢复一次；⑥错误命令来自版本化 Skill/Pipeline 时须同时报告 `CONTRACT_DRIFT`。**不新增** R14 或等价委派 lint。文本纪律：新段落不得出现 ≥3 个具名状态同段、不得把 `_backlog.yml` 与状态判断写进同一段、不出现 guard-deny 文件路径 + 写动词组合。
6. **FR-10 五处 SKILL 边界说明**：5 处既有 payload 示例处各补写同一约束——`blockers`/`suggestions` 等值必须使用 YAML 子集支持的**单行标量**，**不得使用多行引号标量或折叠块**（依据 `lib/yaml-subset.mjs` 的既有解析边界）。不新增字段、不改示例结构。
7. **反向验收与收口（FR-4 / FR-11）**：落地后按 `plan.md §6.2 cmd-03`（tools 白名单机器判据）、`cmd-04`（multica 恰 4 文件）、`cmd-05`/`cmd-06`（原始 diff 清单）核对；三个反向验收对象不得出现在任何清单中。

## 4. 验收条件

1. **FR-1①② + AC-1①②**：`plan.md §6.2 cmd-04` 输出 `AC-2 multica accounted-set hits = 0`、两条「不再含 `_context.md`」断言通过、两份副本的 canonical 关键词齐全；`cmd-03` 输出 `AC-2 tools accounted-set hits = 0`。
2. **FR-5 + AC-5**：`cmd-04` 的块 1/块 2/块 3（两行替换块）与整文件派生 `sha256` 全部等于 SDD §6.2 的目标值，且旧块 `de2554c9…` 不单独出现；三块新文本不含 `--trigger`/`--expect`/`crctl approve --stage`/`git commit`/`git push`。
3. **FR-3 + AC-3**：`cmd-04` 的 `CUSTOM.md` 行数 = 492 且 `| 75 |` 行含五要素关键词；`cmd-06` 的 multica 清单**恰等于** 4 个文件。
4. **FR-6 + AC-6**：`cmd-03` 的六条要求关键词与三条既有内容断言通过、`lint-prompts.mjs` 无 `R14`；`cmd-02` 真实仓库 `0 findings`（含 R1~R13）。
5. **FR-10 + AC-10**：`cmd-03` 的 5 处「单行标量」「多行引号标量」断言通过；`cmd-02` 无新增 finding；`lib/yaml-subset.mjs` 不出现在 `cmd-03`/`cmd-05` 的 diff 清单中。
6. **FR-4 + FR-11 + AC-4/AC-11**：`cmd-03`（tools diff ∈ PRD §1.3.1 白名单）与 `cmd-04`（multica diff 恰 4 文件）均通过；`agents/_index.yml`、两仓 `agent-skill-matrix.yml`、`rules.json`、`gates.json`、`dir-graph.yaml`、`pipeline-templates/**`、`aifirst/agent-import.mjs` 零改动。
7. **全量回归（AC-12）**：`plan.md §6.2 cmd-01` exit 0、`skipped=false`（21 个 `*.test.mjs` 全部真实执行、失败集恰等于 SDD §6.3 登记的 5 条基线红）。
8. **结构完好**：被改的 multica 文件 Markdown 结构（表格列数、frontmatter 分隔符、`##` 标题层级）完好，无语法/结构破损。

## 5. 完成标志

- 上述 §4 的 8 条全部实测通过，并留下可复核的命令与输出摘要（含 `cmd-03`/`cmd-04` 的完整命中清单：计入集合归零、排除集合逐条语义判定——该人工判定同时抄入 `write-test-report` 的分析段）。
- tools diff 与 multica diff 均落在白名单内（`cmd-03`/`cmd-04` 机器判据 + `cmd-05`/`cmd-06` 原始清单）。
- 本 TASK 触及的文件恰为 §2 的 10 个（tools 6 处 + multica 4 个）；不夹带任何其它文件。
- 按 `../multica/CUSTOM.md` 的**当时实际结构**登记本 CR 对 multica 的 4 个文件改动（纪律 #10；若该表已含等价行则只更新对应单元格，不新增重复行）。
- 本 TASK 自行提交（按仓分别提交，受控 `crctl git` 形态、`[cr] ` 前缀），例如 `[cr] CR-2026-063 TASK-04 prompt placement and delegation contract`。
- `crctl task done CR-2026-063-TASK-04 --workspace <KB worktree>` 登记完成。
- **不**改写 `sdd.md` / `prd.md`；**不**修改 TASK-01/02/03 的文件。

## 6. 接口契约

**消费（上游 TASK 与既有实现）**

| 输入 | 精确形态与来源 |
|---|---|
| SDD §6.2 三块逐字目标文本与替换边界 | SDD `ce51c168…` §6.2（含块 1 `833517ff…`、块 2 `dcd3b8e4…`、块 3 插入段 `ed1941…`、块 3 两行替换块 `fc247a12…`、整文件派生 `872457e6…`、旧块 `de2554c9…`）；本计划不复述，只引用 |
| `cr-prompts-revised/cr-coordinator-agent.md` 基线结构 | SDD dep-23：`## 职责` L11 / `## 事实源与读取` L15 / `## 路由` L24 / `## 委派与评论` L38 / `## 评审闭环` L45 / `## 平台层权限` L55 / `## 失败与输出` L63 |
| `cr-prompts-revised/{dev-agent,quality-reviewer-agent}.md` 落点 | SDD dep-22：dev-agent.md `## 环境与代码边界` 末段 L47；quality-reviewer-agent.md `## 入口识别与证据` 首段 L19 |
| `CUSTOM.md` #75 落点 | SDD dep-24：第 75 行第 3 列；表头 `| # | 位置 | 改动 | 原因 / 追溯 | 日期 | 合并注意 |` |
| `tools/agents/dev-agent.md` 委派合同节 | SDD dep-20：`## 委派路由合同（评审）` L31；`agents/_index.yml` 9 个 agent；`agent-skill-matrix.yml:25–29` 的 `cr-coordinator-agent`（`kind: system` / `mode: leader`） |
| 五处 SKILL payload 落点 | SDD dep-18/dep-19：`crctl/SKILL.md` 的 `review-record` 行（L34）+ 四份 review SKILL 的 payload 示例；`lib/yaml-subset.mjs` L1–5 的解析边界 |
| CR-2026-063-TASK-03 的 AC-2 机械证据面 | 同一 `cmd-03`/`cmd-04` 命令（本 TASK 的收口核对共用，不另造命令） |

**产出（供 `write-test-report` / `review-code` / writeback 消费）**

| 产出 | 精确形态 |
|---|---|
| multica 4 文件的新正文 | ① `cr-prompts-revised/dev-agent.md`：`## 环境与代码边界` 末段为上述 canonical resume 段落（无 `_context.md` 指称）；② `cr-prompts-revised/quality-reviewer-agent.md`：首段 canonical 证据面（无 `_context.md`）；③ `cr-prompts-revised/cr-coordinator-agent.md`：三节按 SDD §6.2 逐字替换（`##` 标题集合与顺序不变、frontmatter 不变）；④ `CUSTOM.md`：第 75 行第 3 列含五要素、行数 492 |
| tools 6 处新正文 | `agents/dev-agent.md` 委派合同节六条要求 + 三条既有内容；5 份 SKILL 各含「单行标量」与「多行引号标量」边界说明 |
| AC-2 语义判定证据 | `cmd-03` 日志中的排除集合命中清单 + 逐条「拒绝语义」判定（写入 `write-test-report` 分析段） |
| AC-11 机器判据 | `cmd-03`（tools 白名单）+ `cmd-04`（multica 恰 4 文件）+ `cmd-05`/`cmd-06`（原始清单）的日志 |
