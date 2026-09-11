---
id: CR-2026-063-TASK-04
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: Prompt/文档案位归位与委派合同收紧（multica 4 文件 + tools 6 处）与范围收口核对
slug: prompt-source-overlay-and-scope-closeout
status: pending
estimate: 16h
depends-on: [CR-2026-063-TASK-01, CR-2026-063-TASK-02, CR-2026-063-TASK-03]
created: 2026-09-11T19:30:00+08:00
---

## 1. 任务描述

在 multica 与 tools 两个 CR worktree 完成**文本层原位修订**（FR-1①② / FR-3 / FR-5 / FR-6 / FR-10 / FR-4）并作为收口层承担 FR-11 的反向验收与 AC-11 / AC-12 的核对：

1. **FR-1①**：`multica` `cr-prompts-revised/dev-agent.md` 的 `## 环境与代码边界` 末段（基线 L47）**整段替换**为 canonical resume 口径（见 §3.1），不得「保留旧段 + 段后追加说明」。
2. **FR-1②**：`multica` `cr-prompts-revised/quality-reviewer-agent.md` 的 `## 入口识别与证据` 首段删除 `_context.md` 引用，改为 canonical 证据面（见 §3.2）。
3. **FR-3**：`multica` `CUSTOM.md` #75 行**第 3 列（职责/改动）单元格**原位重写为五要素（见 §3.3）；不新增登记行、不改表结构、不动其它行与其它列。
4. **FR-5**：`multica` `cr-prompts-revised/cr-coordinator-agent.md` 的 `## 委派与评论` / `## 评审闭环` / `## 失败与输出` 三节按来源 §3.3.1/§3.3.2/§3.3.3 **逐字**原位替换/扩写；保留 `## 职责`、`## 事实源与读取`、`## 路由`、`## 平台层权限` 与 frontmatter（不整文件重写、不追加第五节；`## 评审闭环` 的 BLOCK / Suggestions / alignment 责任边界保留）。
5. **FR-6**：`tools` `agents/dev-agent.md` 的 `## 委派路由合同（评审）` 原位收紧为六条要求（见 §3.5）；不新增 R14 或等价委派 lint。
6. **FR-10**：5 处**原位补写** YAML 子集边界说明（见 §3.6）；不改 `lib/yaml-subset.mjs`、不换解析器、不新增字段、不改示例结构。
7. **FR-4 / FR-11 反向验收 + AC-12 收口**：`tools`/`multica` 的 `zero_diff` 文件零改动核对、交付 diff 白名单核对、全量回归运行记录与基线红对照。

输入：已审批 SDD §3.4-B（Prompt 文本契约）、§6 FR-1①②/FR-3/FR-4/FR-5/FR-6/FR-10/FR-11、§6.1 AC-1①②/AC-3/AC-4/AC-5/AC-6/AC-10/AC-11/AC-12、§9（`scope_in`/`scope_out`/`zero_diff`/`follow_up`）+ dep-15 / dep-18 / dep-19 / dep-20 / dep-22 / dep-23 / dep-24；已审批 PRD 修订 0.1.1 §1.3.1（14 行文件表，multica 恰 4 文件）、FR-1①②/FR-3~FR-6/FR-10/FR-11、AC-1/AC-3~AC-6/AC-10~AC-12、§1.5；plan.md §5.3（基线红登记）、§5.4、§6.2（cmd-03…cmd-10）、§7、§8.2（U-5/U-6）。

本 TASK **不**改 `sdd.md`、**不**改 `prd.md`、**不**改平台 DB / `multica/aifirst/agent-import.mjs`（部署由 owner 执行）、**不**改 `pipeline-templates/**`、**不**把 coordinator 加进 `tools/agents/_index.yml`。

> **上游设计修订项（plan §8.2）**：
>
> - **U-5（S-5）**：FR-5 三节目标文本的**权威锚点**（来源 §3.3.1/2/3 的逐字文本或内容哈希）在 SDD 侧未写入；来源文档不在任何 worktree 内，且在 KB 仓为 untracked。本 TASK 按「**逐字复制、不得转述**」实现，工作来源写为「Issue AIFI-24 附件（与主 checkout `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md` 归一后逐字节一致，24585 B、SHA256 `b774e41d…`，PRD §1.4 事实 1）」；最终权威锚点以 SDD 修订结果为准。**逐字校验不在 `crctl test` 计划内**（cmd-07 只覆盖结构/关键词/无步骤复述面），作为本 TASK 的验收条件由评审/审批逐条核对。
> - **U-6（AC-12 口径）**：`../tools` 基线的 5 条既有红见 plan §5.3；本 TASK 的全量回归判据 = 失败集 ⊆ 登记集合、无新增红。

## 2. 涉及文件 / 模块

修改（PRD §1.3.1 第 1、2、3、4、5、12、13 行）：

- `multica` `cr-prompts-revised/dev-agent.md`（`## 环境与代码边界` 末段，基线 L43–49）
- `multica` `cr-prompts-revised/quality-reviewer-agent.md`（`## 入口识别与证据` 首段，基线 L19）
- `multica` `cr-prompts-revised/cr-coordinator-agent.md`（基线 L38 / L45 / L63 三节）
- `multica` `CUSTOM.md`（#75 行，基线 L387）
- `tools` `agents/dev-agent.md`（`## 委派路由合同（评审）`，基线 L31）
- `tools` `skills/shared/crctl/SKILL.md`（`review-record` 行，基线 L34）
- `tools` `skills/requirement/review-requirement/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md`（各自 payload 示例处的原位补写）

只读核对（不改）：`tools/agents/_index.yml`、`tools/agent-skill-matrix.yml`、`multica/cr-prompts-revised/agent-skill-matrix.yml`、`tools/skills/shared/controlled-shell/rules.json`、`tools/skills/shared/crctl/scripts/lib/yaml-subset.mjs`、`tools/skills/shared/crctl/gates.json`、`tools/dir-graph.yaml`、`tools/pipeline-templates/**`、`multica/aifirst/agent-import.mjs`。

## 3. 实现要点（逐字对齐 SDD）

### 3.1 FR-1① 目标段原文（SDD §6 FR-1①，整段替换，保留反引号格式）

> 不得手工修改受控账本、`review-annotations`、`review-loop`、`traceability` 或 `specs/`；对应写入必须经专用 Skill/crctl。恢复或返工时直接读取 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；不得创建或读取 `_context.md` 等上下文副本，也不得让缓存替代状态、评审证据或门禁。

### 3.2 FR-1② 目标内容（SDD §6 FR-1②）

首句保留「不凭评论文字猜阶段」；证据面改为「`dir-graph.yaml` + `crctl status/next` 返回 + 当前 CR canonical 产物 + 该 Skill 指定的证据」，并保留「canonical 事实优先于缓存、评论和执行方自报」。

### 3.3 FR-3 `CUSTOM.md` #75 单元格五要素（SDD §6 FR-3）

同一单元格内重写，含：① 公共 Agent Prompt 唯一事实源 = `tools/agents/`；② `cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；③ 目录内公共 Prompt 副本**不再独立演进**，owner 部署时以 tools 同名文件覆盖平台公共 Agent（原「仓库侧快照」定性被本单元格取代）；④ DB 是部署投影、不是事实源（禁止把 DB/UI 临时编辑反向当规范）；⑤ `cr-coordinator-agent` 不进入 tools agent index。第 4 列（`原因 / 追溯`）与第 5 列（`合并注意`）不改、不新增行、行数不变（492）。

### 3.4 FR-5 三节替换口径（SDD §6 FR-5；**逐字复制、不得转述**）

- `## 委派与评论`（L38）：§3.3.1 文本 → 标准 Pipeline 节点只经既有 Runner 启动；计划外人工委派只传事实清单（CR-ID、节点/Skill 名、`crctl status/next` 返回、workspace/resources **原样值**、canonical feedback 引用、当前责任 Agent）；不复述 Skill/Pipeline 步骤、不内联状态推进或 Git 命令、不把 blocker 正文改写成执行步骤、不声明未来节点已满足；`mention://agent/<id>` 是工作委派不是抄送；一条评论只 mention 一个当前目标；每次触发记录一次 squad activity。
- `## 评审闭环`（L45）：§3.3.2 文本 → **保留**既有 BLOCK / Suggestions / alignment 责任边界，原位改写**标准评审入口**（标准评审由 Pipeline Runner 按 registry 节点启动新的 `quality-reviewer-agent` task/run；协调者不得用评论重建 review Skill 步骤；BLOCK 按 `review-record` 返回的 `repair-target` 与 Pipeline `reviewLoop` 处理；介入条件限定为 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate）。
- `## 失败与输出`（L63）：§3.3.3 文本 → 在既有失败 bullet 内**原位扩写**：评论/Prompt 与当前 Skill/Pipeline 事实冲突时停止该次手工委派并报告 `CONTRACT_DRIFT` 与冲突两侧；crctl 恢复信息只逐字段转发，不改写成协调者自己的 Git/状态序列。
- 交付性质声明（写入 TASK 证据即可，不写进目标文件）：这是 **Prompt 合同缓解**，不宣称平台新增运行时校验；owner 复制该文件到平台后才生效（部署不在本 CR 范围）。

### 3.5 FR-6 六条要求（SDD §6 FR-6；保留三条既有内容）

新增/明确：① 每轮评审使用**新的** reviewer task/run；② 标准节点走 Pipeline Runner；③ 只传 review Skill 已声明的结构化输入与 canonical 引用（CR-ID、权威 workspace、resources 原样值）；④ 不在委派评论中复述 Skill 步骤、门禁命令、`advance` 参数或 blocker 修法；⑤ 只读命令出现零写入 `BAD_ARGS` 时，可按 crctl 明示的恢复方向恢复一次；⑥ 错误命令来自**版本化 Skill/Pipeline** 时，当前 run 可按安全恢复完成，但**必须同时报告 `CONTRACT_DRIFT`**，不得以成功掩盖合同错误。**保留**：作者不得在同一运行中自评；创建路径必须携带可信来源上下文（来源 Issue 或父 task）；不接受时停在 review 节点并提示另开独立会话（不得退化为作者自评）。文本纪律：新段落不得出现 ≥3 个具名状态、不得把 `_backlog.yml` 与状态判断写进同一段、不得出现 guard-deny 文件路径 + 写动词组合（dep-15 R12/R13）。

### 3.6 FR-10 五处原位补写（SDD §6 FR-10）

在**既有 payload 示例处补同一约束注释**（不改示例字段名与层级、不新增字段/维度）：payload 中 `blockers` / `suggestions` 等值必须使用 YAML 子集支持的**单行标量**；**不得使用多行引号标量或折叠块**；依据是既有 `lib/yaml-subset.mjs` 的解析边界（块标量 `|`/`>` 仅保守拼接为文本；锚点/别名/tag/多文档不支持，dep-19）。五处：`skills/shared/crctl/SKILL.md` 的 `review-record` 行 + 4 份 review SKILL 的 payload 示例注释（`requirement/review-requirement`、`develop/review-tech-design`、`develop/review-dev-plan`、`develop/review-code`）。`lib/yaml-subset.mjs` **零改动**。

### 3.7 收口核对（FR-4 / FR-11 / AC-12）

- `zero_diff` 反向验收：`tools/agents/_index.yml`（仍 9 agent）、`tools/agent-skill-matrix.yml`（`cr-coordinator-agent` `kind: system`/`mode: leader` 声明保留）、`multica/cr-prompts-revised/agent-skill-matrix.yml`、`rules.json`、`yaml-subset.mjs`、`gates.json`、`dir-graph.yaml`、`pipeline-templates/**`、`multica/aifirst/agent-import.mjs` 全部**不出现在** cmd-09/cmd-10 的 diff 清单内。
- 交付 diff 白名单：multica 恰 4 文件（§2 前四项）；tools 清单 ⊆ PRD §1.3.1 表内文件（含测试文件），无新增脚本/包/迁移。
- 全量回归运行记录（implement 期）：`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt|TASK-06 ⑤|已知 Skill 越界文本零命中|checkpoint T05 contract|TASK-01 RED-7" skills/shared/crctl/scripts/test/`（cwd = tools worktree）→ 失败集 ⊆ plan §5.3 的 5 条、无新增红。
- multica 台账（纪律 #10）：本 TASK 对 multica 的改动由 `CUSTOM.md#75` 单元格重写覆盖；**无新文件、无 `// AIFIRST:` 挂钩点、不新增登记行**。
- 行尾纪律（AGENTS.md #1）：新增/替换文本 LF；对仓库文件做哈希/跨行处理前统一 `\r\n → \n`，失败硬失败。

## 4. 验收条件

1. **cmd-07**（`node -e "<plan §6.2-B 脚本>"`，cwd = multica worktree）：`multica text-contract failures = 0`（含 dev-agent / quality-reviewer-agent 无 `_context.md`、coordinator 七节结构与三节关键词、无 `--trigger`/`--expect`/`crctl approve --stage`/`git commit`/`git push`、`CUSTOM.md` 492 行且 #75 行含五要素）。
2. **cmd-08**（`node -e "<plan §6.2-C 脚本>"`，cwd = tools worktree）：`tools text-contract failures = 0`（委派合同六条 + 三项保留内容、`lint-prompts.mjs` 无 `R14`、5 处含「单行标量」与「多行引号标量」）。
3. **cmd-09 / cmd-10**（`crctl git diff --name-only <基线> --cwd <被测仓 worktree> --workspace <KB worktree>`）：multica 清单 = §2 的 4 个文件；tools 清单 ⊆ PRD §1.3.1 表且**不含**任何 `zero_diff` 文件。
4. **cmd-03**（`node --test --test-reporter=dot skills/shared/crctl/scripts/test/{contract-scan,pipeline-structure,check-agents-contract,check-skill-matrix}.test.mjs`）与 **cmd-04**（`node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`）：全绿 / exit 0 零 finding（R12/R13 对新增文本无误报）。
5. **人工逐条验收（不可机械替代，U-5）**：`cr-coordinator-agent.md` 三节正文与来源 §3.3.1/§3.3.2/§3.3.3 **逐字一致、无转述压缩**；`## 职责`/`## 事实源与读取`/`## 路由`/`## 平台层权限` 与 frontmatter 与基线逐字一致；`CUSTOM.md` 除 #75 第 3 列外零 diff。
6. **实现期全量回归**：失败集 ⊆ plan §5.3 的 5 条基线红、无新增红（运行命令见 §3.7）。

## 5. 完成标志

- 上述 6 条验收全部通过（第 5 条为人工逐条判据，须在 `write-test-report` 分析段逐条给出结论与证据；第 1/2/3/4/6 条为机器证据）。
- 提交落盘：multica 4 文件改动提交到 multica CR 分支（独立 commit，`[cr] ` 前缀消息）；tools 6 处改动提交到 tools CR 分支（独立 commit）。两仓分别提交、不跨仓混合。
- 任务账本：`crctl task done CR-2026-063 --task CR-2026-063-TASK-04`（仅 `developing` 下可登记）。
- 本 TASK 完成边界为 `developing` 内可被 `crctl task done` 登记的事件（文本落盘 + 证据命令全绿 + diff 白名单/零改动核对结论 + 账本登记），**不含** merge / writeback / archive / code-reviewing / code-approved / 部署（平台 DB 与 importer 由 owner 在本 CR 落地后执行）。
- 台账：`CUSTOM.md#75` 单元格重写覆盖 multica 侧 4 文件的登记义务（无新文件、无挂钩点）；tools 侧无新增自研包，无需登记。

## 6. 接口契约

**消费**（上游 TASK 产出，逐字对齐）：

- CR-2026-063-TASK-01：`cmdGate` 错配错误体（`{error:{code:'BAD_ARGS', contractDrift:true, recoverCommand}}`）与 R7 配对判据 —— 本 TASK 的 cmd-04 以其「零误报」为核对对象（新文本不得令 R1~R13 产生新 finding）。
- CR-2026-063-TASK-02 / TASK-03：`reset` 原子提交、`allowed` 集合删除与退役测试 —— 本 TASK 的 diff 白名单与全量回归核对以其提交为基础。
- `tools` 既有静态守卫：`contract-scan.test.mjs`（canonical 文本零命中）、`pipeline-structure.test.mjs`、`check-agents-contract.test.mjs`、`check-skill-matrix.test.mjs`（读真实仓库文件的契约族）；`lint-prompts.mjs` 的 `walkFiles` 扫描面（`**/SKILL.md` + `*.pipeline.json` + `README.md` + `agents/*.md`，dep-15）。
- 受控 git：`crctl git diff --name-only <sha> --cwd <path> --workspace <path>`（白名单形态 `^--name-only .+$`）、`crctl git diff --unified=3 <sha> -- <path>`（`^--unified=\d+ .+$`，评审侧审计辅助）；`crctl git add -A -- <path>` / `crctl git commit -m "[cr] …"`。

**产出**（交付物，无代码接口）：

- `multica` 4 文件：`cr-prompts-revised/dev-agent.md`（canonical resume 段）、`cr-prompts-revised/quality-reviewer-agent.md`（canonical 证据面段）、`cr-prompts-revised/cr-coordinator-agent.md`（三节逐字替换/扩写）、`CUSTOM.md`（#75 第 3 列五要素）。
- `tools` 6 处：`agents/dev-agent.md` 委派合同的六条要求 + 三条保留；`skills/shared/crctl/SKILL.md` 与 4 份 review SKILL 的「单行标量 / 不得使用多行引号标量或折叠块」边界说明。
- 收口证据：cmd-09/cmd-10 的 diff 清单核对结论（白名单 ∈ / `zero_diff` 零出现）、cmd-07/cmd-08 的文本合同断言日志、实现期全量回归运行记录（失败集 ⊆ plan §5.3 登记集合）。
