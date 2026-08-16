---
id: CR-2026-042-sdd
type: SDD
cr-ref: CR-2026-042
title: tools CR 生命周期最小优化 5/5 — 职责边界清理技术设计
owner: Ray
owner-role: development
status: draft
created: 2026-08-16T14:03:00+08:00
updated: 2026-08-16T14:03:00+08:00
---

# 1. 架构概览

## 1.1 设计目标

本 CR 只收缩 Tools 包的调用方合同，不改 CR 生命周期执行层。目标是让每层只保留调用者真正需要知道的 interface：

- Agent 只决定路由和职责归属；
- Pipeline 只表达节点顺序、输入传递、reviewLoop 和失败中止；
- Skill 只表达业务判断、编排步骤、公开输入输出和失败语义；
- `crctl` 继续作为状态、门禁、CAS、受控账本、Git 发布、审计和恢复的深模块；
- 版本化脚本继续只做确定性内容转换；
- README 只做面向人的总览和权威入口。

实现以删除重复文本为主，不新增运行时进程、公共命令、账本、schema、依赖或事务层。

## 1.2 现有深模块与 seam

现有外部 seam 保持不变：

```text
Agent/runtime
  -> Pipeline JSON（顺序、输入、reviewLoop）
    -> Skill（业务判断与公开调用）
      -> crctl CLI（状态、账本、Git、事务、审计）
        -> Node 标准库 + 现有 durable/workspace modules
```

`crctl` 的 interface 是公开命令、前置条件、结构化结果和错误语义；journal、write-set、CAS、lease、candidate、manifest、detached workspace 等均属于 implementation。删除调用方中的 implementation 复述后，复杂度不会扩散到其他调用方，反而集中回 `crctl`，因此不需要新增 adapter、factory 或第二个 module。

静态治理继续复用现有 `lint-prompts.mjs` seam：命令保持 `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`，只扩展扫描对象和少量确定性判据。

## 1.3 已解决基础设施与本次边界

| 能力 | 权威实现 | 本次动作 |
|---|---|---|
| 状态机与门禁 | `dir-graph.yaml`、`gates.json`、`crctl status/next/advance` | 不改 |
| 人工审批 | `crctl approve` TTY / 签名 grant | 不改 |
| durable transaction | `durable-tx.mjs`、`workspace-transactions.mjs` | 不改 |
| register/checkpoint/merge/writeback/archive | 现有 `crctl` 深命令 | 只删除调用方算法副本 |
| review canonical 字段 | CR-2026-039 已收敛的 `review-record` 合同 | 只清理残留，不改 schema |
| 结构化测试 | CR-2026-040 的 `crctl test --plan` | 只收缩重复说明 |
| baseline evidence/archive gate | CR-2026-041 的版本化脚本与 `crctl archive` | 只收缩重复说明 |
| Agent/Skill 权限 | `agent-skill-matrix.yml` | Agent 文档改为引用 |
| Pipeline 顺序/reviewLoop | `pipeline-templates/*.pipeline.json` | 除 reviewer 暂停节点外不改行为 |

# 2. 模块设计与依赖

## 2.1 Agent 文档

9 个 active Agent 文档统一收敛为以下最小结构，不新增模板生成器：

1. 角色定位；
2. 可处理意图与路由表；
3. 人工决策边界；
4. 权限事实源链接；
5. 禁止绕过 Skill / `crctl` 的一句约束。

Agent 文档不得包含：

- 三个及以上具体 CR 状态组成的状态链或状态表；
- “从 `_backlog.yml` 读取 status 决定下一步”的说明；
- worktree、commit、push、merge、CAS、journal 或账本字段写入算法；
- 完整 owns/can-call/forbidden 清单副本。

已知重点文件：

| 文件 | 当前问题 | 收敛方式 |
|---|---|---|
| `agents/requirement-writer.md` | 保存 drafting 到 requirement-approved 的流程和 backlog/status 写入描述 | 改为 requirement-authoring 路由 + `crctl next` |
| `agents/dev-agent.md` | 保存 architecture/coding 状态链和逐节点推进说明 | 改为两条 Pipeline 路由 + 评审/审批边界 |
| `agents/quality-reviewer-agent.md` | 保存状态到 review Skill 的映射表 | 只保留评审类型到 Skill 的职责路由 |
| `agents/delivery-agent.md` | 直接判断 code-approved/writeback 状态 | 改为由 feature-writeback 调用的角色说明 |
| 其余 active Agent | 存在落盘步骤、重复能力清单或过长交互脚本时 | 仅删除越界段，保留领域判断 |

`agents/_index.yml` 与 `agent-skill-matrix.yml` 不因文档缩短改变机器可读关系；只有发现当前 brief/reference 与实际删改冲突时才做定点同步。

## 2.2 Pipeline

8 个 active Pipeline 逐节点审计 prompt，统一保留以下字段语义：

```text
输入 -> 调用哪个 Skill/公开命令 -> 结构化结果分类 -> reviewLoop/失败动作
```

删除以下内容：

- journal、write-set、CAS、candidate、manifest、lease、逐仓 Git 和账本拼接算法；
- 直接写受控文件的指令；
- Skill 正文已经拥有的完整业务算法副本；
- 会漂移的内部字段、实现阶段和恢复步骤枚举。

节点的 `id`、`kind`、`ref`、`reviewLoop`、`onFail`、`timeoutMinutes` 除明确列出的 reviewer 节点删除外保持不变。

### 2.2.1 code Pipeline 结构变更

当前 `code-implementation.pipeline.json`：

- inputs 为 `cr_id`、`target_version`、`auto_push_after_task`、`review_llm`；
- nodes 为 17 个；
- node `00000000-0000-0000-0015-000000000013` 是“选择代码评审 LLM”人工暂停；
- `workspace-freshness` 评审前节点为 `...0017`；
- `review-code` 节点为 `...0009`。

目标结构：

```text
inputs: cr_id, target_version, auto_push_after_task

... -> workspace-freshness(...0017)
    -> review-code(...0009)
    -> PASS 后 checkpoint(...0015)
    -> 代码人工审批(...0010)
    -> approve-code(...0011)
```

具体变更：

1. 删除 input `review_llm`；
2. 删除 human approval node `...0013`；
3. `...0017` 后直接进入 `...0009`；
4. `review-code` prompt 改为读取 runtime 当前实际 reviewer，并在临时 payload 的 `dimensions.reviewer-model` 中自报留痕；不新增 Pipeline input、状态字段或 reviewer registry；
5. review-code 的 `reviewLoop.replayNodes` 保持现状，因为当前列表本来就是 implement-code -> write-test-report -> checkpoint -> workspace-freshness -> review-code，不依赖 `...0013`；
6. `pipeline-templates/_index.yml` 的 code-implementation `nodes` 从 17 改为 16；
7. 旧调用方若仍传 `review_llm`，由调用方在进入 Pipeline 前完成 runner 选择；不保留隐藏兼容字段。

合法的需求、架构、开发启动、代码四个人工审批节点全部保留。

## 2.3 Skill

Skill 收缩遵循“业务 interface 保留，深模块 implementation 删除”。首轮已核实的修改对象：

| Skill | 保留 | 删除/收缩 |
|---|---|---|
| `write-requirement-prd` | PRD 输入、章节、frontmatter、回修语义、`backlog-set prd-path` | 失效的 engineering-docs、MCP/owClient、`change-requests/_config.yml`、validate-doc 依赖声明 |
| `write-tech-design` | PRD/ARCHITECTURE 读取、SDD 内容、状态前后置、回修 | 手工 commit 配方；ARCHITECTURE 缺失时的真实懒加载行为保留 |
| `write-dev-tasks` | TASK 内容和 `crctl task init`/状态语义 | 手工 `crctl git commit` 配方 |
| `review-code` | diff 与 canonical 测试证据质量判断、LLM verdict | 任何 lint/test/build 执行入口；reviewer 选择暂停依赖 |
| `write-test-report` | 验证范围选择、临时 plan、一次 `crctl test --plan`、分析区 | 机器区/traceability/review-loop 手写说明 |
| `requirement-register` | 业务参数、一次 `crctl register`、结果分类 | 三账本、journal、write-set、lease 等内部步骤复述 |
| `push-progress` | 一次 `crctl checkpoint`、公开 phase/result | 逐仓提交、lease publish、metadata commit 和 journal 算法复述 |
| `merge-feature-branch` | 一次 `crctl merge`、公开错误分类 | prepare/publish/finalize 内部算法展开 |
| 三个 writeback Skill | 业务参数、一次 `crctl writeback-apply`、公开结果分类 | generator/candidate/manifest/journal/Git 内部路径与步骤 |
| `cr-archive` | 一次 `crctl archive`、complete/cleanup-pending 结果 | 四账本 write-set、commit/push、cleanup 实现步骤 |

`inbox-emit`、`cr-dashboard` 中对 `_config.yml` 的 SLA 读取属于真实业务输入，不因 `write-requirement-prd` 的失效引用一并删除。

规划域的 `repair-instructions` / `fixed-blockers` 是非 CR product-planning 自有合同，本 CR 不将其错误套入 CR review canonical 清理；只在 README 重写时不复制节点级字段。

## 2.4 README 与 ARCHITECTURE

README 重写为短的人读入口，目标章节固定为：

1. Tools 定位；
2. 概念生命周期；
3. Owner 职责；
4. 8 条 Pipeline 入口；
5. 自动评审与人工审批；
6. checkpoint / merge / operational workspace / archive 人读区别；
7. 恢复与 `crctl status/next`；
8. 权威事实源链接。

README 不再维护节点表、完整状态转移、门禁表达式、账本字段、内部算法、完整错误矩阵、动态测试数量或默认值。

`ARCHITECTURE.md` 因 code Pipeline 结构发生变化，做一处定点更新：在 Pipeline 模块说明中声明 reviewer runner 由 Agent/runtime 在进入 Pipeline 前选择，Pipeline 不设置额外人工暂停节点。其余架构不变量不改。

OpenWiki 页面不手工改写。权威源修改后由现有 `openwiki-update.yml` 生成/刷新；实施验收扫描生成结果是否仍引用旧 reviewer 节点或废弃命令。

## 2.5 静态治理与 CI

### 2.5.1 `lint-prompts.mjs`

CLI interface 不变。`walkFiles` 扩展为扫描：

- `skills/**/SKILL.md`；
- `pipeline-templates/*.pipeline.json`；
- `agents/*.md`；
- `README.md`。

现有规则直接复用：

- R1：受控文件手写；
- R2：裸 Git；
- R3：废弃 `cr-status-set`；
- R7：`advance` 参数与权威 trigger；
- R9：CR Skill 下一步映射副本。

新增少量确定性规则，不做自然语言分类：

- **R10 废弃公开 interface**：命中可执行形态的 `cr-init`、`crctl test --cmd/--cwd/--timeout`、Pipeline input `review_llm`；禁止性说明或历史说明只通过现有局部 `lint-prompts:ignore` 豁免。
- **R11 已退役 Skill active 引用**：在 Agent/Skill/Pipeline/README 中命中 `change-impact-analysis` 或 `feedback-writeback` 即阻断；历史 CR、CUSTOM TODO 和 Git 历史不在扫描范围。
- **R12 Agent/README 状态机副本**：从权威 transitions 同次加载得到具名状态集合；同一段出现三个及以上不同状态时阻断。Skill/Pipeline 因需要表达合法前后置状态不适用本规则。
- **R13 Agent backlog 状态推断**：Agent 同段同时出现 `_backlog.yml` 与 status/状态判断时阻断；只读产品上下文说明若不推断 CR 状态不命中。

所有文本先 CRLF -> LF。权威状态机解析继续复用 `loadAuthorityTransitions`，缺失、重复、截断或无法解析保持 `STATE_MACHINE_PARSE_FAILED` 硬失败。

### 2.5.2 Pipeline 固定结构检查

保留 CI 中 Node 标准库的 JSON 检查，扩展当前 `JSON.parse` 步骤为固定断言：

- `id`、`triggerCommand`、`inputs[]`、`nodes[]` 存在；
- node id 唯一；
- Skill node 必须有 active `ref`；
- `reviewLoop.repairNodeId` 和 `replayNodes[].nodeId` 必须指向同 Pipeline 现存节点；
- 不解释 prompt，不模拟状态机，不执行 Pipeline。

code Pipeline 的 16 节点、`review_llm` 缺失和 `...0013` 缺失另由静态回归测试精确断言。

### 2.5.3 Workflow 合并

- 保留 `.github/workflows/crctl-ci.yml`；
- 删除 `.github/workflows/check-skill-matrix.yml`；
- `check-skill-matrix.mjs` 与 `check-agents-contract.mjs` 仍由 `crctl-ci.yml` 调用；
- `openwiki-update.yml` 保留，因其不是治理 workflow；
- push/pull_request paths 增加 `README.md`、`AGENT-SKILL-MATRIX.md`，并明确覆盖 `agent-skill-matrix.yml`、`dir-graph.yaml`、`agents/**`、`skills/**`、`pipeline-templates/**`、`skills/shared/controlled-shell/rules.json` 和 workflow 自身；
- Ubuntu/Windows matrix 与现有测试命令保持不变。

# 3. 数据模型

本 CR 不修改任何持久化账本或业务 schema。

唯一结构变化是 Pipeline JSON：

```text
code-implementation.inputs:
  before: [cr_id, target_version, auto_push_after_task, review_llm]
  after : [cr_id, target_version, auto_push_after_task]

code-implementation.nodes:
  before: 17
  after : 16
```

以下均保持不变：

- `cr.md`、`_backlog.yml`、`_history.yml`、approval、review-loop、traceability；
- review annotation canonical 字段；
- test-report 机器区与分析区；
- writeback candidate/manifest/evidence；
- state machine、gates、reviewLoop passCondition。

# 4. 接口契约

## 4.1 Agent interface

输入：用户意图、工作区上下文、`crctl status/next` 或只读 Skill 结果。

输出：选中的 Pipeline/Skill、必要业务参数、是否需要人工决策。

失败：权限矩阵不允许、所需上下文缺失或 `crctl next` 返回人工节点时停止路由；不得自行写状态或账本。

## 4.2 Pipeline interface

输入：模板 `inputs[]` 和前序节点结构化输出。

输出：下一节点所需业务结果；review 节点输出 canonical verdict/blockers/suggestions/dimensions/repair-target。

失败：`onFail=abort|skip` 与 reviewLoop 负责中止/回修；不得在 prompt 内实现恢复算法。

## 4.3 Skill interface

输入：业务参数与 CR 产物。

输出：业务文档、临时判断 payload 或公开深原语结果摘要。

失败：透传/解释公开结构化错误；不得通过手改 authority 补偿。

## 4.4 `crctl` interface

本 CR 不新增、删除或修改 `crctl` 命令、参数、结果字段和错误码。调用方只依赖当前公开 interface，不依赖内部 transaction phase。

## 4.5 lint interface

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode report|enforce [--root <dir>]
```

命令和退出语义不变；只增加扫描范围与规则编号。`enforce` 命中阻断项仍以 `LINT_DRIFT` 非零退出。

# 5. 关键流程

## 5.1 文本职责收敛

```text
读取权威文件与当前 active 文档
  -> 删除实现副本
  -> 保留业务 interface
  -> lint-prompts enforce
  -> matrix/agent contract
  -> Pipeline JSON 固定断言
```

不进行全仓机械改写；只有命中越界规则或本 SDD 文件映射表的文件才编辑。

## 5.2 reviewer 选择

```text
Agent/runtime 在 Pipeline 启动前选择评审 runner
  -> code Pipeline 正常执行到 review-code
  -> review-code 使用当前 runner
  -> dimensions.reviewer-model 记录实际事实
  -> reviewLoop / PASS checkpoint / 人工代码审批保持不变
```

runner 选择不是 CR 状态，不写账本，不新增 human approval。

## 5.3 CI

```text
相关路径变化
  -> crctl-ci（Ubuntu + Windows）
  -> lint-prompts
  -> check-skill-matrix
  -> check-agents-contract
  -> Pipeline JSON 固定断言
  -> crctl tests
  -> writeback tests
```

重复 workflow 删除后不减少任何检查项。

# 6. 技术选型与替代方案

| 方案 | 结论 | 原因 |
|---|---|---|
| 扩展现有 `lint-prompts.mjs` | 采用 | 已有 CLI、规则结构、CRLF 纪律和测试 fixture，改动最小 |
| 新建通用文档合同引擎 | 拒绝 | 会形成第二套 parser/registry，且需求只需少量确定性规则 |
| 新建 Pipeline 解释器 | 拒绝 | JSON.parse + 固定字段断言已足够，不需要执行语义 |
| 为 reviewer 建 registry/config/input | 拒绝 | runtime 已能选择模型；Pipeline 不应拥有 runner 选择暂停 |
| 修改 `crctl` 承担文档治理 | 拒绝 | `crctl` 不拥有 LLM 文本与业务设计判断 |
| 全量重写所有 Skill | 拒绝 | 只改命中越界的 Skill，避免无关 churn |
| 保留旧 `review_llm` 兼容字段 | 拒绝 | 字段无状态价值且会继续制造第二入口；调用方迁移到 runtime 选择 |
| 手工编辑 OpenWiki 生成页 | 拒绝 | 由既有 workflow 从权威源刷新 |

# 7. FR 到技术实现映射

| PRD FR | 技术实现 |
|---|---|
| FR-01 Agent 文档收敛 | §2.1；`agents/*.md` 定点缩短；R12/R13 防回潮 |
| FR-02 Pipeline prompt/reviewer | §2.2；code Pipeline 删除 input/node；节点数 17 -> 16；固定结构断言 |
| FR-03 Skill 收敛 | §2.3；CR write、review/test、register/checkpoint/merge/writeback/archive Skill 定点清理 |
| FR-04 README | §2.4；README 8 节人读入口；ARCHITECTURE 定点更新；OpenWiki workflow 刷新 |
| FR-05 静态治理/CI | §2.5；lint R10-R13；删除重复 workflow；补 paths 与双平台测试 |
| FR-06 已解决能力保护 | §1.3、§3、§4.4；零 crctl/state/gate/schema 生产改动 |

# 8. 安全、性能与兼容性

- **安全**：不扩大 shell/Git 权限，不修改 `rules.json#protectedPaths.deny`，不增加账本写入口。
- **一致性**：状态和账本仍只由 `crctl` 写；文档收缩不改变 authority。
- **性能**：lint 新增扫描仅覆盖少量 Markdown/JSON，复杂度为文件总字节线性扫描；无需缓存或并发。
- **跨平台**：所有新增文本读取先 CRLF -> LF；CI 在 Ubuntu/Windows 双跑。
- **兼容性**：唯一删除的外部输入是可选 `review_llm`；调用方必须在 Pipeline 前选择 runner，不提供兼容 shim。其余公开命令和 Pipeline 业务输入不变。
- **可审计性**：reviewer 实际身份继续写 `dimensions.reviewer-model`；删除暂停节点不删除评审证据。

# 9. 测试设计

## 9.1 `lint-prompts.test.mjs`

新增最小向量：

1. Agent/README 中受控文件手写与裸 Git 命中现有 R1/R2；
2. `cr-init`、旧 `crctl test` flags、`review_llm` 命中 R10；
3. 两个 retired Skill active 引用命中 R11；
4. Agent/README 同段三个状态命中 R12，两个状态不误报；
5. Agent 从 `_backlog.yml` 推断 status 命中 R13，只读产品上下文不误报；
6. 每条规则 LF/CRLF 结果一致；
7. `lint-prompts:ignore` 仍只覆盖所在行 ±1 行。

## 9.2 `crctl.test.mjs` 静态合同

追加 CR-2026-042 向量：

1. code Pipeline inputs 不含 `review_llm`；
2. node `...0013` 不存在，总节点数为 16；
3. `...0017` 后是 `...0009`；
4. review-code replayNodes 全部指向现存节点，且顺序不变；
5. `_index.yml` nodes=16；
6. `check-skill-matrix.yml` 不存在，`crctl-ci.yml` 仍调用两个 checker；
7. CI paths 覆盖 PRD FR-05.2；
8. README 必需章节/权威链接存在，禁止内容零命中；
9. 已知 Skill 越界文本零命中。

## 9.3 全量验证

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
Pipeline JSON parse + fixed field assertions
```

全部命令在 Ubuntu/Windows CI 运行；不新增 npm 依赖。

# 10. 文件变更矩阵

| 路径 | 动作 |
|---|---|
| `agents/*.md` | 定点缩短 active Agent 文档 |
| `pipeline-templates/*.pipeline.json` | 收缩越界 prompt；code Pipeline 删除 reviewer input/node |
| `pipeline-templates/_index.yml` | code-implementation nodes 17 -> 16 |
| `skills/requirement/**/SKILL.md` | 清理 PRD 失效模板引用和 register 深算法复述 |
| `skills/develop/**/SKILL.md` | 清理 commit 配方、测试第二入口和 reviewer 暂停依赖 |
| `skills/writeback/**/SKILL.md` | 保留一次公开调用，删除内部算法复述 |
| `skills/sync/push-progress/SKILL.md` | 收缩 checkpoint 内部算法 |
| `skills/cr/cr-archive/SKILL.md` | 收缩 archive 内部算法 |
| `README.md` | 重写为人读总览与权威链接 |
| `ARCHITECTURE.md` | 定点记录 reviewer runner 选择边界 |
| `skills/shared/crctl/scripts/lint-prompts.mjs` | 扩扫描范围，新增 R10-R13 |
| `skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 新规则正反例与 CRLF 测试 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | Pipeline/CI/README/Skill 静态合同测试 |
| `.github/workflows/crctl-ci.yml` | paths 与固定结构断言 |
| `.github/workflows/check-skill-matrix.yml` | 删除 |
| `openwiki/**` | 不手工编辑；由现有 workflow 刷新 |

不修改 multica 或 knowledge-base 业务代码；knowledge-base worktree 只新增本 CR SDD 与评审证据。

# 11. 风险与回滚

| 风险 | 控制 |
|---|---|
| 文本缩短删除真实业务判断 | 按“保留 interface、删除 implementation”逐文件评审；FR 映射和现有行为测试兜底 |
| lint 扩面误报 | 新规则限定文件类型/段落/字面形态，提供正反例和局部 ignore |
| reviewer 节点删除破坏 reviewLoop | node ID 顺序和 replayNodes 静态断言；现有 code pipeline 行为测试全量回归 |
| README 过薄 | 固定保留 Owner、入口、审批、恢复、四个关键概念和权威链接 |
| CI 合并减少检查 | 主 workflow 明确保留两个 checker 和全部测试；双平台矩阵不变 |
| OpenWiki 未同步 | 合并后由现有 workflow 刷新，并扫描旧 reviewer/命令引用 |

回滚按普通 Git commit 回滚文档/JSON/lint/workflow 变更即可；本 CR 不迁移数据、不改变状态机或账本，因此无数据回滚和兼容迁移步骤。

# 12. Prompt 采纳影响

本 CR 不修改 `skills/shared/crctl/scripts/crctl.mjs` dispatch，也不修改 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`，因此不需要新增/扩展 crctl 子命令，也不存在“某 Skill 必须改用新命令”的采纳清单。

本 CR 的 Prompt 变化只是在现有公开 interface 上删除重复 implementation 文本，并删除 code Pipeline 的 reviewer 选择暂停。

# 13. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始设计：职责分层、code Pipeline 17->16、Skill/README 收敛、lint R10-R13、CI workflow 合并 |
