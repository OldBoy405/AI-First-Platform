# AIFI-18 / CR-2026-062：SDD→plan/TASK 原位修订方案

> **文档性质**：AIFI-18 派生 CR 的需求与修订边界（CR-P0 / CR-R 已归档，CR-P1 / CR-P2 未开始）。
> **修订原则**：实际落地时，所有优化都修改对应事实源的原文、既有函数、既有 Skill 段落或既有测试；不在文件末尾追加“补丁说明”，不复制第二套流程，不新增观测指标。
> **依据**：AIFI-18 issue 全链路执行记录、`AIFI-18_SDD到planTASK完整复盘报告.md`、`tools/` 与 `multica/cr-prompts-revised/` 盘上实读。
> **当前基线**：`tools` main 已合并 CR-2026-063(CR-P0) / 064(CR-R) / 065(CR-S) / 066(CR-P3)。CR-P1、CR-P2 的一切原位修订以该基线的**现行原文与现行测试**为准；本文件中与该基线不符的旧口径已就地更新，不另立说明章节。

---

## 1. 最终架构决定

### 1.1 Prompt 事实源

采用“公共源 + 平台 overlay”，不再把任何完整镜像目录声明为全部 Agent 的唯一事实源：

| 内容 | 唯一事实源 | 部署关系 |
|---|---|---|
| 公共 Agent Prompt（requirement/dev/reviewer/delivery 等） | `tools/agents/` | tools 校验通过后，由 owner 更新到 Multica DB |
| Multica 专属 coordinator Prompt | `multica/cr-prompts-revised/cr-coordinator-agent.md` | 由 owner 复制到 Multica 平台 |
| Agent/Skill 公共权限矩阵 | `tools/agent-skill-matrix.yml` | 平台消费；其中可登记平台 system actor，但不要求 tools 存在其 prompt 文件 |
| Multica DB Prompt | 部署投影，不是事实源 | 禁止把 DB/UI 的临时编辑反向当规范 |

`tools/agents/_index.yml` **不新增** `cr-coordinator-agent`；该 Agent 是 Multica 专属 overlay。`tools/agent-skill-matrix.yml` 已包含其 system actor 权限声明，矩阵不因 prompt 文件不在 tools 而另造第二份。

现有 `multica/aifirst/agent-import.mjs` 只创建不存在的 Agent；遇到同名 Agent会 `skip`，不能用于更新已有 Prompt。本方案不修改 importer，也不更新平台 DB。各 CR 落地后，owner 使用 `multica agent update <id> --instructions ...` 或平台等价受控入口部署。

### 1.2 `_context.md` 决策

删除 `change-requests/{CR-ID}/_context.md` 这一第三事实副本，不迁移到 `.crctl/`，不新增生成器。

理由：

- 它被定义为可重建导航缓存；
- canonical 事实优先；
- 门禁和评审不应读取它；
- `/resume` 已能读取 `crctl status`、`crctl next`、`cr.md`、`review-loop.yml` 与 canonical review annotations；
- tools 没有确定性生成器或必要消费者；
- 为该缓存增加 dirty 豁免、提交时序和白名单会把缓存升级成治理负担。

历史 CR 中已有的 `_context.md` 不批量迁移、不重写历史，随 CR 自然归档。

### 1.3 委派决定

- 标准 Pipeline 评审走既有 Multica governance Runner；Runner 已传递固定 `PipelinePrompt`、attempt、source task、executor 和 canonical feedback JSON。
- 跨人工 gate 的第一份委派必须携带上一阶段尚未闭合的发布动作（同 run 执行、只回报），禁止为单个 `push-progress` / checkpoint 单开委派——该硬规则由 CR-P3（CR-2026-066）落地，CR-P1/CR-P2 的委派文字直接遵守，不重述、不改写。
- 不新增平台委派 schema。
- 公共 Agent 与 Multica coordinator 不复制 Skill/Pipeline 步骤，只传事实和 canonical 引用。
- Prompt 约束属于合同缓解，不宣称运行时机械校验。
- 删除原方案中无法检查真实运行期评论的 R14 委派 lint。

### 1.4 不增加观测指标

本方案不新增以下任何内容：

- review SLO；
- M1～M8 指标；
- P50/P90；
- 连续 N 个 CR 统计；
- 为复盘计数增加的账本字段或 Prompt 要求；
- “评审轮数必须降到某个数”的门禁。

本方案保留的测试与批次退出条件属于实施验收，不是运行期观测。

---

## 2. 四个 CR 与边界

| 顺序 | CR | 状态 | 只负责 | 明确不负责 |
|---|---|---|---|---|
| 1 | **CR-P0：流程正确性止血**（CR-2026-063） | 已归档 | 删除 `_context.md`；Prompt 源/overlay 归位；coordinator 与 dev 委派合同；stage 专属 BAD_ARGS；reset 原子提交；YAML 子集说明 | 评审内容重构、plan/TASK 增量回修、全局 recovery 迁移、平台 DB 更新 |
| 2 | **CR-R：结构化恢复合同原子迁移**（CR-2026-064） | 已归档 | 全局 `recoverCommand` → `recovery`；迁移全部生产者/消费者并同 CR 删除旧字段 | 双写兼容期、第二删除 CR、AIFI-18 评审规则 |
| 3 | **CR-S：测试基线与门禁可信化**（CR-2026-065，AIFI-26） | 已归档 | 断言去硬编码；4 条漂移转绿 + RED-7 构造改对；`suite-gate` 全量真门禁（`test/gate-registry.json` 登记 `manifest.cases`，用例数 `<` 登记值即红）；例外须带 owner + 到期 | AIFI-18 的评审内容修订 |
| 4 | **CR-P3：评审 PASS 发布与 checkpoint 委派收敛**（CR-2026-066，AIFI-27） | 已归档 | 发布点前移到评审 PASS（4 个 review SKILL 加 clean 前置 + 发布 + 对账）；审批后 checkpoint 节点退役（节点数 5/4/12）；搭车硬规则；归档后 trunk ff-only | Step 2.x 评审判据、plan/TASK 写作合同（留给 CR-P1/CR-P2） |
| 5 | **CR-P1：评审输入结构与回修闭合** | 未开始 | 事实依赖单一表达；状态链整体重证；批准范围自洽 | crctl 事务、环境 readiness、upstream plan/TASK 成本 |
| 6 | **CR-P2：plan/TASK 返工成本与执行前提** | 未开始 | upstream 增量回修；TASK 依赖闭包重算；证据证明力；环境责任与即时 preflight | 新 Pipeline 环境节点、动态环境人工门禁、评审观测指标 |

各 CR 分别评审、审批、回滚；不得合并为一个发布单元。CR-R 的完整需求在独立文档 `crctl_recoverCommand结构化恢复合同_原子迁移方案.md`，CR-S / CR-P3 的完整需求分别在 AIFI-26 / AIFI-27。

**CR-P1 / CR-P2 与已落地 CR 的边界（块级不重叠，已逐条盘上核对）**：CR-P3 只动 4 个 review SKILL 的 Step 1.0（clean 前置）与末尾发布/对账步骤、pipeline 节点集与权限矩阵；CR-P1 / CR-P2 只动 Step 2.x 评审判据与 plan/TASK 写作合同。两侧不得互相重编号：`review-tech-design` / `review-dev-plan` 的 **Step 5 / Step 6 已被 CR-2026-066 占用**，CR-P1 / CR-P2 只在既有 Step 2.x 内原位扩写；且四个 review SKILL 的新增文字不得出现 `crctl checkpoint`、`push-progress 之后`、`push-progress 之前`、`统一 checkpoint 后`（CR-2026-066 反向断言零命中）。

---

## 3. CR-P0：流程正确性止血

## 3.1 删除 `_context.md` 全部活跃合同

### 3.1.1 `multica/cr-prompts-revised/dev-agent.md`

**原文位置**：`## 环境与代码边界` 最后一段，其中声明每个 run 收尾维护 `_context.md`。

**原位修订**：用 canonical resume 口径替换整段 `_context.md` 规则，不在段后追加新说明：

```text
不得手工修改受控账本、`review-annotations`、`review-loop`、`traceability` 或 `specs/`；对应写入必须经专用 Skill/crctl。恢复或返工时直接读取 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；不得创建或读取 `_context.md` 等上下文副本，也不得让缓存替代状态、评审证据或门禁。
```

该文件不是公共 Prompt 事实源；本处只记录旧 Multica 副本的退役口径。公共 dev-agent 的正式修改在 `tools/agents/dev-agent.md`。

### 3.1.2 `multica/cr-prompts-revised/quality-reviewer-agent.md`

**原文位置**：`## 入口识别与证据` 首段：

```text
评审前读取目标 workspace `dir-graph.yaml`、必要的 `_context.md`（仅导航）、当前 CR 产物和该 Skill 指定的证据……
```

**原位修订**：删除 `_context.md` 引用，改成：

```text
评审前读取目标 workspace `dir-graph.yaml`、`crctl status/next` 返回、当前 CR canonical 产物和该 Skill 指定的证据；canonical 事实优先于评论和执行方自报。
```

公共 reviewer 正式来源仍是 `tools/agents/quality-reviewer-agent.md`；本处避免 owner 后续误复制旧缓存合同。

### 3.1.3 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`

**原文位置**：post-review path drift 的 `allowed` 集合（当前约 1311～1319 行）。

**原位修订**：从既有数组删除：

```js
// _context.md：工作流上下文加速文件……
`change-requests/${cr}/_context.md`,
```

不增加 `crProcessCachePath()`，不放宽 `classifyRepoWorkspace()` 的 dirty 语义。删除后：任何未跟踪/已修改 `_context.md` 与其它非白名单文件同样处理。

### 3.1.4 `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`

**原文位置**：现有 `CR-2026-057: KB 白名单新增 _context.md……` 测试。

**原位修订**：把该测试改成退役合同测试，而不是在旁边新增反向补丁测试：

```text
_context.md 不再属于 post-review allowed paths；评审后新增或修改该文件必须按普通 unexpected path 拒绝。
```

测试同时保留 `_context2.md` 非白名单断言，证明不存在前缀式放宽。

### 3.1.5 Prompt 与文档全量核对

在 CR-P0 的变更范围内，对活跃 `agents/`、`skills/`、`pipeline-templates/` 执行 `_context.md` 搜索，结果必须为 0。历史 CR、历史 traceability、归档 delivery 证据不改。

## 3.2 公共 Prompt 与 Multica overlay 归位

### 3.2.1 `multica/CUSTOM.md` #75

**原文问题**：把 `cr-prompts-revised/` 整体描述为快照，同时规定与 tools 分叉时以 tools 为准；但目录中又混有 Multica 专属 coordinator 和四个公共 Agent 副本。

**原位重写同一表格行的职责单元格**：

- 公共 Agent Prompt 唯一事实源为 `tools/agents/`；
- `cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；
- 目录中的公共 Prompt 副本不再独立演进；owner 部署时以 tools 同名文件覆盖平台公共 Agent；
- DB 是部署投影；
- `cr-coordinator-agent` 不进入 tools agent index。

不新增登记行，不在 CUSTOM.md 后追加另一份事实源说明。

### 3.2.2 不修改的矩阵与索引

- `tools/agents/_index.yml`：不新增 coordinator。
- `tools/agent-skill-matrix.yml`：保留已存在的 `cr-coordinator-agent` system actor 权限声明；该声明是平台 actor 的公共权限边界，不要求存在 tools prompt。
- `multica/cr-prompts-revised/agent-skill-matrix.yml`：不作为公共矩阵独立演进。

## 3.3 原位重写 Multica coordinator overlay

目标文件：`multica/cr-prompts-revised/cr-coordinator-agent.md`。

保留当前正确的 `职责`、`事实源与读取`、`路由`、`平台层权限` 与只读约束；不整文件推倒重写。原位替换以下三个位置。

### 3.3.1 `## 委派与评论`

替换为：

```text
## 委派与评论

标准 Pipeline 节点只通过平台已有 Runner 启动目标 Agent；Runner 提供的固定 PipelinePrompt、canonical feedback、attempt、source task 与 executor 是该次委派的权威输入，本 Agent 不在评论中复制它们的执行算法。

计划外人工委派只传以下事实：CR-ID、当前 Pipeline 节点或 Skill 名、`crctl status/next` 的当前返回、权威 workspace/resources 原样值、canonical feedback 路径或对象引用、当前责任 Agent。不得复述 Skill/Pipeline 步骤，不得内联状态推进或 Git 命令，不得把 blocker 正文改写成新的执行步骤，不得声明未来节点已经满足。

`mention://agent/<id>` 是立即创建/唤醒目标 task/run 的工作委派，不是抄送。串行交接的一条评论只 mention 一个当前目标；下一节点或复评者只作纯文本说明，不提前触发。每次触发后记录一次 squad activity，避免重复委派和轮询。
```

### 3.3.2 `## 评审闭环`

保留现有 BLOCK、Suggestions、alignment 责任边界，原位改写标准评审入口：

```text
标准 Pipeline 评审由 Pipeline Runner 按 registry 节点启动新的 quality-reviewer-agent task/run；协调者不得用评论重建 review Skill 的步骤。评审 BLOCK 按 review-record 返回的 repair-target 与 Pipeline reviewLoop 处理；协调者只在 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate 时介入。
```

### 3.3.3 `## 失败与输出`

在原有失败 bullet 内原位扩写：

```text
当评论、Agent Prompt 与当前 Skill/Pipeline 事实发生冲突时，停止该次手工委派，报告 `CONTRACT_DRIFT` 与冲突两侧，不自行选择一套步骤继续。来自 crctl 的恢复信息只逐字段转发，不改写为协调者自己的 Git/状态序列。
```

本修改是 Prompt 合同缓解，不宣称平台已新增运行时委派校验。owner 将该文件复制到平台后才生效。

## 3.4 公共 dev-agent 委派合同

目标文件：`tools/agents/dev-agent.md`。

**原文位置**：`## 委派路由合同（评审）`。

原位修改为：

- 每轮评审使用新的 reviewer task/run；
- 标准节点走 Pipeline Runner；
- 仅传 review Skill 已声明的结构化输入和 canonical 引用；
- 不在委派评论中复述 Skill 步骤、门禁命令、advance 参数或 blocker 修法；
- 若 Agent 临时生成的只读命令出现零写入 BAD_ARGS，可按 crctl 明示恢复一次；
- 若错误命令来自版本化 Skill/Pipeline，当前 run 可按安全恢复完成，但必须同时报告 `CONTRACT_DRIFT`，不得以成功掩盖合同错误。

不增加无法扫描真实运行期评论的 R14 lint。

## 3.5 stage 专属 BAD_ARGS 可操作化

### 3.5.1 `tools/skills/shared/crctl/scripts/crctl.mjs`

**原文位置**：`cmdGate()` 中 `--mode pre-review` 的 BAD_ARGS（当前约 960 行）。

**原文语义**：仅说明该 mode 只支持 requirement，没有当前 stage 的正确下一步。

**原位修订语义**：

- 保留 `BAD_ARGS` 和零写入；
- 明确 `--mode pre-review` 仅支持 `--for requirement-reviewing`；
- 对其它 stage 返回安全恢复方向 `crctl workspace inspect <cr>`；
- 返回 `contractDrift: true`，提示调用方检查权威 Skill/Pipeline；
- 恢复方向以结构化 `recovery`（`executable` + `args[]` + `cwd`，`shell:false`）返回；CR-R（CR-2026-064）已完成迁移并整树退役 `recoverCommand` / `recover_command`（`contract-scan` 禁止清单），后续任何 CR 的新文本不得复活旧字段名。

### 3.5.2 `tools/skills/shared/crctl/scripts/lint-prompts.mjs`

在既有 R7 crctl 参数形态规则中原位加入配对检查：出现 `gate --mode pre-review` 时必须同时出现 `--for requirement-reviewing`。

该规则只防版本化 Prompt 漂移；不用于声称真实运行期评论已被机械限制。

## 3.6 `review-loop reset` 原子提交

目标：`tools/skills/shared/crctl/scripts/crctl.mjs#cmdReviewLoopReset`。

**原文问题**：函数直接 `fs.writeFileSync(review-loop.yml)` 后返回，留下已写未提交中间态。

**原位修订**：

1. 函数改为 async；dispatcher 保持 `return cmdReviewLoopReset(...)`，由既有 async `main()` 接管。
2. 在读取 attempts 状态时取得目标文件 expected hash。
3. 复用现有：
   - `recoverLedgerCommand`
   - `ledgerTxKey`
   - `beginLedgerCommand`
   - `controlledGit add/commit`
   - `abortLedgerTransaction`
   - `finishLedgerTransaction`
4. commit 只包含 `review-loop.yml`，提交消息保留 `[cr]` 前缀并带 transaction id。
5. add/commit 失败时回滚文件与 index，写审计并返回失败；不得留下 dirty 中间态。
6. 失败结果返回结构化 `recovery`（CR-R 已落地），且 `recovery.args[]` **不得包含用户输入的 reason**；TTY 重试时重新输入 reason。
7. 不新写事务框架，不把 reset 并入 checkpoint，不放宽 controlled-shell 全局规则。

## 3.7 YAML 子集合同

目标：`tools/skills/shared/crctl/SKILL.md` 的既有 `review-record` 行，以及 review Skill 现有 payload 注释。

原位补清楚现有解析边界：blocker/suggestion 值必须使用 YAML 子集支持的单行标量；不得使用多行引号标量或折叠块。该修改只说明既有事实，不换 YAML 解析器。

## 3.8 CR-P0 验收

- 活跃 Agent/Skill/Pipeline 不再引用 `_context.md`；
- post-review 白名单不再包含 `_context.md`；
- 旧 CR-2026-057 测试已原位改为退役测试；
- tools 不新增 coordinator prompt；
- coordinator overlay 不包含手写 Skill/Pipeline 步骤；
- `gate --mode pre-review` 错配由既有 lint 抓住；
- reset 成功后工作区 clean；add/commit 故障时文件与 index 回滚；
- 结构化 `recovery.args[]` 不包含用户 reason，且旧字段名（`recoverCommand` / `recover_command`）全树零命中；
- 全量既有 crctl、ledger、prompt 与 pipeline 测试通过。

---

## 4. CR-R：结构化恢复合同原子迁移

CR-R 与 AIFI-18 内容质量修订解耦，只负责横向恢复合同。它在一个 CR 内迁移全部已知生产者和消费者，并直接删除 `recoverCommand` / `recover_command`；没有外部消费者，因此不设置双写期和第二删除 CR。

**落地状态**：已作为 CR-2026-064 归档；旧字段名进入 `contract-scan` 退役清单并整树扫描，CR-P1 / CR-P2 的任何新文本（含评审报告、Skill 正文、测试断言）不得重新引入。

完整文件清单、目标 JSON 合同、迁移顺序和验收见：

`docs/analysis/crctl_recoverCommand结构化恢复合同_原子迁移方案.md`

CR-P0 的 reset 兼容止血在 CR-R 落地后由结构化 `recovery` 原位替换。

---

## 5. CR-P1：评审输入结构与回修闭合

## 5.1 既有实现事实只定义一次

### 5.1.1 `tools/skills/develop/write-tech-design/SKILL.md`

**原文位置**：Step 2.6 的既有实现断言段与“既有实现依赖与事实”小节。

**原位修订**：

- repo/path/symbol/SHA/conclusion 的既有清单保留；
- 每条事实获得稳定 `dep-N`；
- 实现事实只在该表中定义一次；
- SDD 正文只能写“设计依赖 `dep-N`”，不得重新陈述“当前代码已经如何工作”；
- 无法绑定事实字段时写为待核实依赖，不得继续作为方案前提；
- N/A 只有在正文与依赖表均无既有实现依赖时可用；
- `commit SHA` 在 `dep-N` 中为**必填**，与评审侧口径一致（见 5.1.2）。

固定结构原位改为：

```text
dep-1
  repo: <repository id>
  relative path: <path>
  stable symbol/对象: <symbol/object>
  commit SHA: <40-character SHA>
  依赖结论: <verified current behavior required by this design>
```

这不是在正文和表中各维护一份事实；表是唯一事实定义，正文只持引用。

**同 CR 必须原位同步的现行断言**（本项不可缺，否则 CI 必红）：`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 的 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例逐字断言写侧含 `### 既有实现依赖与事实` / `正文首次出现顺序` / `repo:` / `relative path:` / `stable symbol/对象:` / `commit SHA:` / `依赖结论:` / `sdd.explicit_existing_dependencies`，评审侧含 `名为“既有实现依赖与事实”的显式小节` / `有序清单` / `正文同类事实是否漏列`。改成 `dep-N` 后必须：

- 在**该用例内原位改写**这两组 term（小节名与 `dep-N` 字段名），不另写第二个反向用例；
- 保持用例数不减；若用例数发生变化，同 CR 刷新 `skills/shared/crctl/scripts/test/gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]`（CR-S 落地后用例数 `<` 登记值即红）；
- 不得为该改动申请 `suite-gate` 例外。

### 5.1.2 `tools/skills/develop/review-tech-design/SKILL.md`

**原文位置**：Step 2.1 的 existing dependency 核验段。

**原位修订**：

- reviewer 核验依赖表中的 repo/SHA/path/symbol/conclusion；
- 正文只能引用存在的 `dep-N`；
- 正文出现未通过 dep 引用承载的当前实现事实时形成 blocker；
- 原文现有“并**可附** `commit SHA`”的弱口径必须同时改为必填，与 5.1.1 写侧对齐（现基线上写侧必填 40 位 SHA、评审侧可选，两侧强制性不一致，本 CR 一并收口）；
- 修订只在 Step 2.1 内原位进行：**不得重编 Step 号**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用），新增文字不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；
- 不要求 reviewer 全仓扫描或猜测作者未写出的依赖；
- 该规则把事实定义收敛到结构化表，但仍是 Prompt 合同，不宣称 NLP 机械识别所有自由文本事实。

## 5.2 首轮完整检查（已在库，本 CR 零改动）

目标：`review-tech-design/SKILL.md#Step 2.2`。

**现状核对结论**：该句已在基线上落地（CR-2026-055 引入）——“首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题”。因此本 CR 对该句**不做任何修改**，只在验收时核对其仍存在；重复写入等于造第二份事实源，违反本方案的原位原则。

**删除原方案中的错误锚点**：`quality-reviewer-agent.md#评审判断` 小节**不存在**。现行 `tools/agents/quality-reviewer-agent.md` 只有 `角色定位` / `意图与路由` / `独立会话路径` / `人工决策边界` / `权限事实源` / `发布职责与搭车硬规则`（CR-2026-066）/ `约束` 六七个小节，“评审判断”只是路由节下“写临时 payload”的一句话。不得为本规则在 Agent Prompt 里新建小节或复制第二份判据；该判据的唯一事实源是 review SKILL。

同时删除原方案中：

- 为“首轮漏检”写账本计数；
- 使用 `本轮新增：` 统计流程质量；
- 对评审轮数作数字承诺。

`本轮新增：` 仍只承担 blocker 文本分类，不承担观测指标。

## 5.3 状态链整体重证

目标：`write-tech-design/SKILL.md` 现有“回修模式只按 blocker 和本轮变化定点修订”句。

在该句原位扩写：

- blocker 若触及状态判定、活动性、事件顺序、空值或失败回流，必须重证该状态链的完整输入维度、分支、可见动作与对应 AC；
- 不得只修被点名的一格；
- 同一标识符、锚点或 testid 在全文只能有一个裁决；
- 未受该根因影响的已确认方案不得重写。

该修订直接覆盖 AIFI-18 中 stop handler、running、空 ID 顺序和失败回流被拆成多轮修补的问题形态。

## 5.4 批准范围内部一致性

### 写手侧

目标：`write-tech-design/SKILL.md` 现有 `批准范围` 四字段说明。

原位加入：

- `scope_in` 与 `zero_diff` 不得对同一对象同时要求修改和不修改；
- 外部治理规则强制修改时，必须在 SDD 阶段把对象纳入 scope_in、修订 zero_diff 或给出已有合法出口；
- 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；
- `follow_up` 不得承载当前 AC 的必要条件。

### reviewer 侧

目标：`review-tech-design/SKILL.md` 现有 `批准范围前置` 段。

原位加入相同判据；发现冲突必须在 SDD 阶段形成 blocker，不留到 dev-plan 再触发 upstream。

## 5.5 CR-P1 验收

- 写手和 reviewer 使用同一 `dep-N` 语义，且两侧对 `commit SHA` 同为必填；
- 正文不再重复定义既有实现事实；
- 状态链回修要求完整重证但不扩散到无关设计；
- scope 四字段判据在写手与 reviewer 两侧一致；
- `review-tech-design` 的首轮全量句保持原样（零改动核对），`quality-reviewer-agent.md` 未新增任何小节；
- 不新增 annotation dimension、账本字段、评审指标或 Pipeline 节点；CR-2026-066 的 clean 前置 / PASS 发布 / 对账四要素与 Step 编号未被改动；
- `pipeline-structure.test.mjs` 的 CR-2026-055 依赖清单用例已原位同步到 `dep-N` 口径；
- `suite-gate --run` 全量绿且 `gate-registry.json#manifest.cases` 已同步，**未签任何新例外**（CR-S 后全量测试是真门禁）。

---

## 6. CR-P2：plan/TASK 返工成本与执行前提

## 6.1 upstream 后 plan 增量回修

目标：`tools/skills/develop/write-dev-plan/SKILL.md#Step 2a`。

**原文问题**：回修模式只说明普通轨 feedback；upstream 返回后 coordinator 把现有 plan/TASK 当作整轮作废并全量重建。

**原位修订**：

- 普通轨仍逐条处理 canonical blockers；
- upstream SDD 重新批准后，以新旧批准 SDD 的变更 delta 和同轮未闭合 plan blockers 为输入；
- 在同一份 plan 上只重算受影响章节、稳定表行、证据与回滚；
- 未受影响内容保留；
- coordinator 只传 subject/delta/canonical feedback 引用，不指定具体行如何修改；
- 不修改 review-route 枚举，不把 repair-target 改成多值。

## 6.2 TASK 及依赖闭包重算

目标：`tools/skills/develop/write-dev-tasks/SKILL.md` 现有回修模式，以及 code-implementation 既有 `write-dev-plan → write-dev-tasks` 节点顺序。

原位明确：

1. `write-dev-plan` 完成 SDD→plan delta；
2. `write-dev-tasks` 必须继续执行 plan→TASK delta；
3. 重算直接受影响 TASK 及其下游依赖闭包；
4. 同步更新受影响 TASK 的输入、输出、接口、命令、depends-on、完成标志和回滚；
5. 未受影响 TASK 保留；
6. 禁止只修 plan、让旧 TASK 留给下一轮评审发现。

**必须原位改写的相反现行文字**：`write-dev-tasks/SKILL.md#Step 2a` 现写作“逐条消费 blockers，**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK”，与上述 delta 重算直接矛盾。本 CR 必须在**该段内**把“重新生成”改写为“delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留，`crctl task init` 只用于刷新 `_index.yml` 索引”，不得在别处另写一段增量规则与它并存。

节点层无需改动：`code-implementation.pipeline.json` 现为 12 节点（CR-2026-066 已删 `…0003/…0008/…0015/…0012`），`write-dev-plan(…0001) → write-dev-tasks(…0002)` 顺序完整，`review-dev-plan(…0014).reviewLoop.replayNodes` 已含两个 authoring 节点。其中 `purpose: regenerate-tasks` 是标签，本 CR 只在 SKILL 内明确其语义为“delta 重算”，**不改节点集、不改节点数（保持 5/4/12）、不改 replayNodes 条目**，以免撞 CR-2026-066 的节点数与 `_index.yml` 断言。

## 6.3 证据命令的可执行性与证明力

### `write-dev-plan/SKILL.md`

在既有交付覆盖表与证据命令表说明中原位加入：

- 每个 `cmd-NN` 必须能观测该表行声称的 AC 结果；
- `--list` 不能证明浏览器行为；
- 文件级 `--name-only` 不能证明符号级不变量；
- 子集测试不能声称全量；
- 涉及 Git 的命令必须使用 `rules.json` 已允许的受控入口；
- 不再通过委派评论补写命令算法。

### `review-dev-plan/SKILL.md`

在既有 `acceptance-verifiability` 维度原位加入同一判据：观测面窄于声称面即 blocker；命令形态越受控边界即 blocker，不留到 implement 阶段才暴露。

不新增新的评审维度名或证据账本。修订只在该维度段内原位扩写：**不得重编 Step 号**（`review-dev-plan` 的 Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用），且新增文字不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（CR-2026-066 反向断言零命中）。

## 6.4 回滚单元是依赖闭包

目标：`write-dev-plan/SKILL.md` 交付覆盖表既有 `回滚` bullet。

原位明确：被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者，并与风险节中的逆拓扑顺序一致；单点 revert 会破坏下游时不得声明为单点回滚。

## 6.5 环境责任与即时 readiness

### plan 侧

目标：`write-dev-plan/SKILL.md` 既有 `验收与发布策略` 项，不新增第八节。

原位扩写为：若证据依赖常驻服务、浏览器或数据库，必须在该节写明：

- 环境 owner；
- 建立方式；
- 可获得性；
- readiness 证据：**必须复用该环境所保障的那一行 FR 的既有 `cmd-NN`**，不得为 readiness 单独申请新 `cmd-NN`。原因：两张稳定表的“验收证据 ↔ 证据ID”双向唯一映射（CR-2026-060 AC-07，`review-dev-plan` 覆盖矩阵节机械核对）不允许存在不被交付覆盖表引用的命令行；若进证据命令表而不被引用即 blocker，若不进表则不是合法 `cmd-NN`（无 executable/args/timeout 与 `crctl test` 机器区下标）。确实无法复用时，该诉求超出本 CR 边界，另立 CR 修改稳定表合同与对应评审判据，**本 CR 不放宽该映射**；
- 缺失时的 `ENVIRONMENT_MISMATCH` 处置。

### dev-start 侧

目标：`code-implementation.pipeline.json` 既有 `确认进入代码开发` approvalPrompt（节点 `…0004`，CR-2026-066 未改动它，也未向其中加入任何 checkpoint 前提）。

原位改为只确认 owner、建立方式和可获得性；不要求审批时所有服务在线，不把动态健康状态写成人工长期事实。改写文本必须满足现行 `pipeline-structure.test.mjs` 断言：节点 prompt/approvalPrompt **不得出现 `git` / `journal` 字样**（因此环境建立方式只写责任人与获得途径，不写命令），必须保留 approve/reject 结构化决定，不得残留 `review-annotations` 路径与 `reject_reason` 引导。

### implement 侧

目标：`implement-code/SKILL.md` 既有环境前置/ENVIRONMENT_MISMATCH 段。

原位加入：在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`；失败则按既有 ENVIRONMENT_MISMATCH 中止并报告建立动作。环境无关 TASK 不被提前阻断。

不新增环境 Pipeline 节点，不让 coordinator 启停共享服务。

## 6.6 不修改 upstream attempts 账本

删除原方案中“把 upstream block 追加到 `attempts[]` 且 current 不递增”的修改。该设计会产生 attempt 0 或重复 `(cycle,attempt)`，混淆“评审事件”和“预算 attempt”。

本 CR 不新增 review-events、不改 traceability schema、不做聚合指标。既有 canonical annotation 与 audit 保留 upstream 事实。

## 6.7 CR-P2 验收

- upstream 后 plan 与受影响 TASK 同步更新；
- 未受影响内容不被全量重写；
- 受影响依赖闭包不残留旧接口/命令；
- 证据命令可执行且观测面足以证明 AC；
- readiness 复用既有 `cmd-NN`，两张稳定表的双向唯一映射未被破坏；
- dev-start 不要求动态环境在线，且 `…0004` approvalPrompt 仍无 `git`/`journal` 字样、保留 approve/reject；
- 环境依赖 TASK 执行前即时 readiness；
- `write-dev-tasks/SKILL.md#Step 2a` 的“重新生成”已原位改写为 delta 重算，文件内不存在两套并存的回修规则；
- 不新增 Pipeline 节点、账本字段、评审维度或观测指标；节点数保持 5/4/12、`_index.yml` 计数一致；
- `suite-gate --run` 全量绿且 `gate-registry.json#manifest.cases` 已同步，**未签任何新例外**。

---

## 7. 已解决基础设施与本次最小修改的分界

继续复用、不再造：

- crctl 状态机、gate、CAS、durable ledger transaction；
- review-record 判断/写入分离；
- reviewLoop、replayNodes、maxAttempts；
- 批准物 digest 与旧审批失效；
- controlled-shell 与 rules.json；
- ENVIRONMENT_MISMATCH；
- Pipeline Runner 的结构化节点输入；
- 版本化 cmd-NN 与 test evidence；
- 结构化 `recovery` 合同（CR-R）；
- `suite-gate` 全量真门禁与 `gate-registry.json` 登记面、带 owner/到期 的例外治理（CR-S）；
- 评审 PASS 发布点、clean 前置、发布对账与搭车硬规则（CR-P3）。

本方案不做：

- 新事务框架；
- 新委派平台 API；
- 新 context 生成器；
- 新 Pipeline 节点；
- 新评审维度或观测指标；
- coordinator 进入 tools；
- importer create-or-update；
- rules.json 为 context commit 放宽；
- README 复制可执行步骤事实源。

---

## 8. 实施顺序与独立回滚

1. （已完成）CR-P0 = CR-2026-063：删除冲突缓存并修复流程原子性；owner 随后部署 tools 公共 Prompt 与 coordinator overlay。
2. （已完成）CR-R = CR-2026-064：原子迁移恢复合同；active contract 中旧字段为零。
3. （已完成）CR-S = CR-2026-065：测试基线转绿与全量门禁可信化；此后每个 CR 均不得签新例外。
4. （已完成）CR-P3 = CR-2026-066：发布点前移至评审 PASS、审批后 checkpoint 节点退役、搭车硬规则。
5. CR-P1 只收紧 SDD 写作与评审闭合，不接触事务层；同 CR 原位同步 CR-2026-055 依赖清单用例与 `gate-registry.json`。
6. CR-P2 最后降低 upstream 返工成本并提前声明执行前提。

任一 CR 失败只回滚本 CR；不得为了保持后续 CR 而保留半套新旧合同。CR-P1 与 CR-P2 不与其他 CR 并发（tools 单写者）。
