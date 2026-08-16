---
id: CR-2026-042-prd
type: PRD
cr-ref: CR-2026-042
title: tools CR 生命周期最小优化 5/5 — 职责边界清理
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-16T12:03:00+08:00
updated: 2026-08-16T12:03:00+08:00
---

# 1. 概述

本 CR 是《tools-cr-lifecycle-minimal-optimization-spec.md》固定拆分的第 5 条实施 CR，只落实规格 FR-14、FR-15、FR-16。当前 Tools 包已经具备 CR 生命周期所需的状态机、门禁、CAS、人工审批、durable transaction、跨仓 merge、checkpoint、review-record、结构化测试、candidate-only writeback 和 archive；问题不是缺少执行基础设施，而是 Agent、Pipeline、Skill、README 与 CI 中仍保留重复、过时或越界的文本契约。

本 CR 通过删除和收缩完成治理，不新增事务框架、状态机、账本模型、通用 Pipeline 解释器或 workflow engine。所有实现决策按以下 ponytail 优先级选择：

1. 复用现有能力；
2. 标准库；
3. 原生 Git/文件 API；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

# 2. 目标逻辑架构

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览、入口、恢复说明和权威链接 | 另一份可执行细节事实源 |

## 2.1 已解决基础设施（只复用，不重做）

| 能力 | 当前状态 | 本 CR 处理 |
|---|---|---|
| 状态、门禁、CAS 与人工审批 | `crctl status/next/advance/approve` 已有权威实现 | 复用；不改状态机、gates 或审批算法 |
| durable transaction | 已有 lock、journal、write-set、commit/push 与恢复 | 复用；不新增事务层 |
| register / workspace / checkpoint / merge / writeback / archive | 已有单一深原语和结构化恢复语义 | 只删除调用方中的算法副本，不改生产实现 |
| review canonical 合同 | CR-2026-039 已统一为 `verdict`、`blockers`、`suggestions`、`dimensions`、可选 `repair-target` | 只清理残留引用，不重做字段模型 |
| 结构化测试 | CR-2026-040 已由 `crctl test --plan` 负责机器证据，`write-test-report` 负责分析区 | 只收缩重复说明；不新增测试入口 |
| baseline 最小证据与 archive 证据门 | CR-2026-041 已由版本化脚本和 `crctl archive` 承担 | 只收缩重复说明；不改证据结构 |
| Agent/Skill 权限 | `agent-skill-matrix.yml` 已是机器可读事实源 | Agent 文档只引用，不复制权限表 |
| Pipeline 顺序与 reviewLoop | `pipeline-templates/*.pipeline.json` 已是机器可读事实源 | 保留编排；不建立解释器 |
| 治理脚本 | 已有 `lint-prompts.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs` 和测试 fixture | 原地扩展少量确定性规则 |

## 2.2 本次最小改造

| 改造点 | 最小处理 |
|---|---|
| Agent 文档越界 | 删除状态链、backlog 状态推断、Git/账本写入算法；保留定位、路由、职责与权限引用 |
| Pipeline prompt 越界 | 收缩为输入、一次 Skill/命令调用、结构化结果分类、reviewLoop 与失败动作 |
| Skill 越界 | 删除 journal/CAS/Git 深算法副本、手工 commit/push 配方和 CR write Skill 的失效 engineering-docs/MCP/validate-doc 引用 |
| 代码评审模型选择 | 删除 code Pipeline 的 `review_llm` 输入和“选择代码评审 LLM”人工暂停节点；由 Agent/runtime 在进入 Pipeline 前选择 runner |
| README 漂移 | 重写为人读总览、入口、Owner、审批、恢复和权威链接 |
| CI 重复 | 保留 `crctl-ci.yml`，删除重复的 `check-skill-matrix.yml` workflow；检查脚本继续由主 workflow 调用 |
| 防回潮 | 在现有 lint 与测试中增加少量确定性规则；Pipeline 只做 JSON.parse 与固定字段断言 |
| OpenWiki | 修改权威源后由现有 OpenWiki workflow 刷新引用；不手工维护另一套执行合同 |

# 3. 用户故事

- **US-01 Agent 维护者**：希望 Agent 文档只说明“何时路由到哪个 Pipeline/Skill”，不再复制状态机、Git 或受控账本算法。
- **US-02 Pipeline 维护者**：希望节点 prompt 只表达编排和失败路由，深原语内部变化不需要同步修改多份算法文本。
- **US-03 Skill 维护者**：希望 Skill 聚焦业务判断和输入输出，原子写入、提交、发布与恢复统一交给 `crctl`。
- **US-04 CR 执行者**：希望代码评审 runner 在进入 Pipeline 前由 Agent/runtime 选择，不因额外的人工暂停节点中断自动闭环。
- **US-05 Tools 使用者**：希望 README 能快速说明入口、Owner、人工审批与恢复方法，并明确指向权威事实源，而不是复制会漂移的实现细节。
- **US-06 Tools 维护者**：希望单一跨平台 CI 在相关契约变化时运行既有检查，并用小而确定的 lint 阻止越界文本回潮。

# 4. 功能需求

## FR-01 Agent 文档收敛（规格 FR-14）

1. active Agent 文档只保留角色定位、可处理意图、Pipeline/Skill 路由、人工决策边界和对 `agent-skill-matrix.yml` 的引用。
2. Agent 不保存完整或局部状态链，不从 `_backlog.yml` 推断 CR status；CR 当前状态与下一步统一调用 `crctl status/next` 或对应只读 Skill。
3. Agent 不描述 Git worktree、commit、push、merge、CAS、journal、受控账本字段拼接或受控文件落盘算法。
4. Agent 不声称直接写 `cr.md`、`_backlog.yml`、approval、review annotation、review-loop、traceability、specs 或 delivery 账本；写入必须路由到已登记 Skill / `crctl` 深原语。
5. 不在 Agent 文档复制矩阵的完整 owns/can-call/forbidden 清单；唯一权限事实源仍是 `agent-skill-matrix.yml`。
6. 不为追求统一格式新增 Agent 基类、模板引擎或生成器；仅编辑存在越界或过时文本的文档。

## FR-02 Pipeline prompt 收敛与 reviewer 暂停删除（规格 FR-14）

1. active Pipeline 的 Skill 节点 prompt 只保留：业务输入、调用的 Skill/公开命令、结构化结果分类、reviewLoop 输入/输出和失败中止/路由。
2. Pipeline 不展开 journal、CAS、write-set、candidate、manifest、lease、逐仓 Git、账本拼接或恢复算法；调用深原语时只传公开业务参数并消费公开结构化结果。
3. Pipeline 不手写受控文件内容，不要求模型直接编辑 `_backlog.yml`、`cr.md`、approval、review annotation、review-loop、traceability、specs 或 delivery 索引。
4. `code-implementation.pipeline.json` 删除 `review_llm` 输入和“选择代码评审 LLM”`human_approval` 节点；review runner 由 Agent/runtime 在进入 Pipeline 前选择，`review-code` 仍可在评审 `dimensions` 中记录实际 runner/model 作为事实。
5. 删除节点后保持原有 reviewLoop、PASS 后 checkpoint、代码人工审批和失败中止语义；同步 `pipeline-templates/_index.yml#nodes` 的实际节点数。
6. 不修改其他合法人工审批节点，不把 reviewer 选择改造成新 Skill、配置中心、runner registry 或状态字段。
7. Pipeline JSON 结构校验只使用 `JSON.parse` 与固定字段断言；不实现 prompt 语义解释器、通用 workflow runner 或符号执行器。

## FR-03 Skill 职责收敛（规格 FR-14）

1. CR 生命周期 Skill 只保留业务前置、业务判断、一次公开深原语调用、输入输出和失败语义；删除对 journal、CAS、merge、checkpoint、writeback、archive 内部算法的复述。
2. `review-code` 只读取真实 diff 与 canonical 测试证据并形成 LLM 评审结论，不执行或重新执行 lint/test/build；正式测试仍只有 `write-test-report -> crctl test --plan` 一条入口。
3. `write-test-report` 负责选择正式验证范围、生成临时结构化 plan、调用一次 `crctl test --plan` 并更新 marker 后分析区；不得直接写机器区、traceability tests 或 review-loop。
4. 三个生产 writeback Skill 各只调用一次 `crctl writeback-apply` 并解释结构化结果；不暴露或消费 generator、candidate、manifest、journal 或 Git 内部路径。
5. CR write Skill 删除失效的 engineering-docs、MCP、owClient、`_config.yml` 与 validate-doc 依赖声明；文档结构和 frontmatter 以各 Skill 当前明确合同为准。
6. write Skill 不输出手工 `git add/commit/push` 配方；需要提交或发布时调用现有 `crctl` 公开入口。
7. 不删除仍被规划等非 CR 流程真实使用的 `engineering-docs` 或 `validate-doc` Skill；本 CR 只删除 CR write 路径中的失效引用。

## FR-04 README 收敛为人读入口（规格 FR-15）

1. README 只保留：产品定位、概念生命周期、Owner 职责、8 条 active Pipeline/Skill 入口、人工审批方式、checkpoint/merge/archive 的人读区别、恢复命令和权威链接。
2. README 不复制完整状态转移表、节点 prompt、门禁表达式、账本字段、内部算法、完整错误码矩阵、动态测试数量或会漂移的默认值。
3. 状态机只展示概念阶段并链接 `dir-graph.yaml#change-request-track.state_machine`；Pipeline 节点和 reviewLoop 链接 `pipeline-templates/*.pipeline.json`；权限链接 `agent-skill-matrix.yml`。
4. README 用人读语言解释：checkpoint 是进度发布、merge 是多仓发布、operational workspace 是回写期工作区、`cleanup-pending` 表示终态已发布但资源清理未完成。
5. README 不成为执行入口的替代品；具体参数、结果字段和恢复错误以对应 Skill / `crctl` 合同为准。
6. 不在 README 维护 Agent/Skill 的完整权限矩阵、完整节点表或代码实现说明。

## FR-05 静态治理与 CI 收敛（规格 FR-16）

1. `.github/workflows/crctl-ci.yml` 保持唯一主治理 workflow；删除功能重复的 `.github/workflows/check-skill-matrix.yml`，但保留并继续调用 `check-skill-matrix.mjs` 和 `check-agents-contract.mjs`。
2. `crctl-ci.yml` 的 push/pull_request paths 至少覆盖：`README.md`、`AGENT-SKILL-MATRIX.md`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`agents/**`、`skills/**`、`pipeline-templates/**`、`skills/shared/controlled-shell/rules.json` 和 workflow 自身。
3. 主 workflow 在 Ubuntu 与 Windows 上继续执行现有 crctl/writeback 测试、`lint-prompts`、Skill matrix、Agent contract 和 Pipeline JSON 检查。
4. 复用现有 `lint-prompts.mjs` 增加少量确定性规则，至少检测：已废弃公开命令/参数、与权威状态机不一致的字面量 trigger、受控文件手写指令、已退役 Skill 的 active 引用。
5. lint 读取文本后必须统一 CRLF→LF；权威状态机跨行解析失败必须硬失败，不得降级为空规则或静默跳过。
6. 新规则须有最小正/反例测试；不得建立通用 AST、schema registry、错误码 registry、Pipeline 解释器或自然语言语义分类器。
7. OpenWiki 引用更新通过现有 source + workflow 链路完成；`openwiki-update.yml` 不是治理 workflow，不在删除范围。

## FR-06 已解决能力保护与范围边界

1. CR-2026-038～041 已交付的生产行为只做回归保护，不在本 CR 重写或迁移。
2. review canonical 字段以 CR-2026-039 已有实现为准；只删除残留的废弃字段引用，不新增 ledger 或 schema。
3. 不修改 `crctl` 的状态、门禁、CAS、审批、事务、Git、测试、writeback 或 archive 生产算法；若静态治理需要读取权威声明，只通过既有 resolver/helper。
4. 不修改状态机数量、转移、gates、approval grant、reviewLoop 业务语义、traceability evidence 结构或 candidate 路径。
5. 不新增依赖；优先通过删除文本、复用现有检查器和 Node 标准库完成。

# 5. 非功能需求

- **NFR-01 极简性**：净效果以删除重复合同为主；不新增框架、registry、数据库、通用解释器、公共协议或占位能力。
- **NFR-02 单一事实源**：状态、权限、Pipeline、Skill、执行层和 README 的事实源边界与本 PRD第 2 节一致。
- **NFR-03 跨平台**：治理 workflow 与新增测试在 Ubuntu、Windows 上均通过；文本扫描对 LF/CRLF 等价。
- **NFR-04 可验证性**：每项收敛均有确定性扫描、JSON 固定断言或既有行为测试支撑，不依赖“人工看起来更短”。
- **NFR-05 兼容性**：删除重复说明不得改变现有公开命令、合法人工审批、reviewLoop 与深原语结构化结果。
- **NFR-06 可维护性**：README 和 Agent/Pipeline/Skill 通过链接权威文件减少同步面，不复制动态规模数字或实现细节。

# 6. 验收标准

- **AC-01（FR-01）**：active Agent 文档中不存在完整状态链、从 `_backlog.yml` 推断 status 的指令、Git 算法或受控账本手写算法；每个 Agent 仍能从角色、意图和矩阵引用确定合法路由。
- **AC-02（FR-02）**：active Pipeline prompt 中不存在 journal/CAS/write-set/candidate/manifest/lease/逐仓 Git 或受控账本拼接算法；节点仍明确输入、调用、结果分类、reviewLoop 与失败动作。
- **AC-03（FR-02）**：code Pipeline 不再声明 `review_llm` 输入或“选择代码评审 LLM”暂停节点；其节点数与 `_index.yml` 一致，reviewLoop、PASS 后 checkpoint、代码人工审批顺序保持成立。
- **AC-04（FR-03）**：`review-code` 零测试执行入口；`write-test-report` 只调用一次 `crctl test --plan` 并只拥有分析区；三个 writeback Skill 各只有一次公开 `writeback-apply` 调用且不暴露内部路径。
- **AC-05（FR-03）**：CR write Skill 中失效的 engineering-docs/MCP/owClient/`_config.yml`/validate-doc 引用和手工 `git add/commit/push` 配方为零；非 CR 流程仍在真实使用的通用 Skill 保留。
- **AC-06（FR-04）**：README 包含生命周期概念总览、Owner、入口、审批、恢复和权威链接；不含完整状态转移声明、节点 prompt、门禁表达式、内部算法、完整错误矩阵、动态测试数量或默认值副本。
- **AC-07（FR-04）**：README 对 checkpoint、merge、operational workspace、archive 与 cleanup-pending 的说明可由非实现维护者理解，且每项都链接到对应权威合同。
- **AC-08（FR-05）**：仓库只剩 `crctl-ci.yml` 一个主治理 workflow；`check-skill-matrix.yml` 已删除，两个检查脚本仍由主 workflow 调用；`openwiki-update.yml` 保留。
- **AC-09（FR-05）**：主 workflow 的 paths 覆盖 FR-05.2 全部路径，并在 Ubuntu/Windows 执行既有治理与测试套件。
- **AC-10（FR-05）**：新增 lint 正/反例证明废弃命令/参数、非法 trigger、受控文件手写和退役 Skill active 引用会被阻断，合法公开调用与历史事实性记录不误报；LF/CRLF 结果一致。
- **AC-11（FR-05）**：任一 Pipeline JSON 不可解析或缺固定必填字段时检查失败；实现中不存在通用解释器、符号执行或 prompt 语义分析。
- **AC-12（FR-06）**：`crctl` 生产算法、状态机、gates、approval、review canonical schema、test-report 机器区、writeback candidate/evidence/archive 语义无行为改动；相关既有测试全绿。
- **AC-13（全量）**：Agent、Pipeline、Skill、`crctl`、版本化脚本与 README 的实际改动分别落在第 2 节规定的职责内；全仓 active 合同不存在第二套事务框架、状态机、账本模型或 workflow engine。

# 7. 成功指标

- Agent、Pipeline、Skill 与 README 中重复状态机、Git/账本算法和深原语内部步骤的 active 文本引用降为 0。
- code Pipeline 少一个 reviewer 选择人工暂停节点，不影响 reviewLoop、checkpoint 或代码审批。
- 治理 CI 只有一个主 workflow，相关契约改动不会因 paths 漏项跳过检查。
- 新增防回潮仅扩展既有 lint/测试，不增加生产依赖、公共命令或长期接口。
- CR-2026-038～041 已解决的生产能力保持原实现与回归测试，不被本 CR 重新设计。

# 8. 依赖与风险

- **依赖**：CR-2026-038～041 已合入的 writeback、证据、测试与 archive 行为；现有 `agent-skill-matrix.yml`、Pipeline JSON、Skill 合同、`crctl`、lint 和 CI fixture。
- **风险 R-01 过度删除**：文本收缩可能删掉真实业务判断。处理方式是只删除执行层算法副本，保留业务前置、输入输出、结构化错误分类与 reviewLoop。
- **风险 R-02 lint 误报**：历史文档和反例可能包含禁用词。新规则限定 active Agent/Skill/Pipeline/README/CI 范围并沿用局部 `lint-prompts:ignore`，每条规则必须有合法反例测试。
- **风险 R-03 Pipeline 顺序回归**：删除 reviewer 节点会改变 node index。验收以 `node.ref` 和 kind 顺序断言，不依赖旧数组下标；同步 `_index.yml` 节点数。
- **风险 R-04 README 过薄**：删除细节后可能难以上手。必须保留入口、Owner、审批、恢复与四个关键概念的短说明，并链接权威合同。
- **风险 R-05 OpenWiki 漂移**：不手改生成页承载新事实；先改权威源，再由现有 workflow 刷新并检查旧命令/能力引用。

# 9. 范围排除

- 不实现来源规格 FR-01～FR-13；这些属于 CR-2026-038～041，当前只做回归保护。
- 不执行 Phase E 跨 CR 端到端验收；Phase E 是五条实施 CR 完成后的独立验收活动。
- 不改 `crctl` 状态机、门禁、事务、审批、Git、测试、writeback、archive 或账本 schema。
- 不新建通用事务管理器、workflow engine、Pipeline 解释器、runner registry、schema/error-code registry、数据库或权限服务。
- 不删除 `engineering-docs`、`validate-doc`、reviewer-panel 或 OpenWiki workflow；只清理本 CR 范围内失效或重复的 active 引用。
- 不批量改写历史 CR、历史 traceability、历史评审记录或 OpenWiki 历史快照。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘于 CR-2026-042 knowledge-base worktree。

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始草稿：职责边界、已解决基础设施、本次最小改造、README/CI/lint 收敛与 reviewer 暂停删除 |
