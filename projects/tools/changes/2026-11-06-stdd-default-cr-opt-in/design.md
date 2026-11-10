# 工作区入口精简与 STDD／CR 流程隔离 — 技术设计

> Gate 2 曾确认方案 A；本文已按用户 2026-11-10 决定原位修订，修订版 Gate 2 重新确认待完成。当前阶段以 STDD 状态为准；偏离历史见 `pending-adjustments.yaml`，本文不覆盖原批准或执行记录。
> Change：`2026-11-06-stdd-default-cr-opt-in`。
> 已确认提案：`canonical/proposals/2026-11-06-stdd-default-cr-opt-in.yaml`；Gate 1 确认原文：`确认 Gate 1，standard`。

## Context

- 本次是 `documentation` 任务：修改入口文档和说明，不增加运行时代码、路由器、状态机或测试框架。
- 使用现有三根：资源根 `../stdd`、业务根 `../tools`、数据根 `projects/tools`（后者相对知识库根）。STDD CLI 始终从业务根运行，所有 change 命令显式带本 ID，避免选中其他在途变更。
- 根 `AGENTS.md` 当前为 6,287 个 LF 规范化字符，要求所有任务读取 tools 约束、矩阵和 README。那三份文档合计约 22,874 字符；这是加载成本，不是已测量的请求 token。
- 根入口含陈旧 CR 注册、审批、worktree 和 Tools Root 回退叙述。当前注册由 Skill 调用 `crctl register`；默认审批及服务端授权以 tools 现行契约为准；合并后还有事务操作工作区。
- 知识库根无 `.stdd/binding.yaml`。tools 与 multica 的业务仓绑定分别定位本仓库 `projects/tools`、`projects/multica`。不能从知识库根直接假定 STDD CLI 已选对项目。
- 根 `AGENTS.md` 已有用户未提交修改，强化了执行账本与人工设计记录的区分。本次须保留这些保证，而非仅与 Git HEAD 对比后覆盖。
- `projects/tools/specs/` 当前不存在；不为本次创建第二个项目级规范基线。既有 change 和 archive 仅用于参考，不修改其事实。
- 既有约束参考：`projects/tools/archive/2026-10-19-aifi-45-runner-contracts/specs/agent-prompts/spec.md`、同 change 的 `approve-skills/spec.md`，以及在途授权设计中的审批隔离规则。知识库相对路径在本段均以知识库根为基准。

### STDD 执行事实与限制

- Gate 1、Gate 2 已有原生批准记录，当前为 BUILD；Gate 3 pending。`gate status` 实查 Gate 1／2 均为 historical/unfingerprinted：没有输入指纹，CLI 不会自动将本次修订判为 stale，也不能据此认定修订版已获批准。
- `new --task-type documentation` 原生生成 `mode: standard`。现行 CLI 无 `complexity_score` 合法设置入口，因此该字段保持 null；初评约 6/17 已通过 `state --set resume_context=...` 说明，不能声称评分字段已同步。
- `extract-proposal <本ID> --format json` 返回两个 capability、8 项成功标准，但 `impact` 为空；当前提案渲染器未输出该章节。实际影响范围以已确认提案的 C1–C6 和本文文件清单交叉核对，不把空提取结果解释为无影响。
- 本地 `experience list --language javascript --format json` 实际返回 `[]`，匹配经验为 0；不据此断言所有资源或社区经验均为空。数据根无 knowledge graph，本次跳过可选预测，不联网下载。
- `config models --format json` 实际返回 `schema_version=1`、`kind=configured`，design 映射 strong。本次已确认 standard，由主会话设计，不额外升档或派 planner；configured 不等于 actual，实际档位未以运行元数据核验，记为 unknown。

## Decisions

### D1. 只统一入口选择，不统一两个流程的内部状态

**方案**：根入口按下表处理。表是本次入口行为的评审说明，不复制 CR 状态机或 Pipeline 节点映射。

| 输入 | 入口决定 | 写入与授权边界 |
|---|---|---|
| 明确只读分析／问答 | 不启动任何新变更 | 只读分析不创建变更；不得因出现“需求”等词自动注册 |
| 接手可识别的已有 STDD／CR | 已有变更沿用原流程 | 默认值或一句换流程要求不构成迁移批准；冲突时停下确认 |
| 新开发，未指定流程 | 新开发变更默认使用 STDD | 先确定目标业务仓、绑定及三根，再加载当前阶段技能 |
| 用户显式选择 tools CR 的新变更 | 加载 tools 的现行 CR 入口 | 走合法注册与节点，不手写状态、审批或任务索引 |
| 身份、目标、绑定或归属冲突／不明 | 停止并询问 | 不猜目录、不回落到 STDD 旧模式、不同时写两个流程 |

**为什么**：一个变更只有一个流程权威；默认值只解决新变更的缺省选择。

**备选方案及排除原因**：全局强制 STDD 会误接管旧 CR；两套规则同时常驻会继续冲突；新增统一路由器和流程字段不符合当前需求。

### D2. 根入口保留共同底线，其余按任务和阶段加载

**方案**：根 `AGENTS.md` 依次组织为工作区职责、流程选择、权威入口、共同底线。以下保证不可在精简中删除：

1. 事实断言先核实，读取目标仓自身规范；multica 英文注释与 CUSTOM 登记要求不因流程变化消失。
2. CR 状态、审批、任务和其他执行账本只经所属合法入口及入库、可测试的版本化脚本操作；禁止会话内现写脚本处理执行账本，无合法入口时停止。版本化不替代权限、唯一入口、CAS、审计或门禁。
3. 精准编辑的例外仅限于记录设计偏离、供人工审阅的 STDD `pending-adjustments.yaml`，不推广为所有“人工设计记录”；保留原记录和扩展字段，依据原话或可靠来源区分方向、具体决定、执行授权和未决事项。核对所属 change、YAML 解析与类型、必需字段、唯一编号、冲突标记与差异；失败或归属不明时停止，`resolved` 反映真实处理结果。其他 YAML 的归属不明时按执行账本处理。
4. 记录不等于批准或执行；STDD Gate 不替代 CR 审批，CR 审批也不自动确认 STDD。Gate 不自动授权 Git 提交、推送或部署。
5. 哈希、跨行正则和逐行解析前规范化 CRLF；解析失败硬失败，不以空集合静默丢数据。
6. 不覆盖累积发布基线；`docs/product`、`docs/analysis` 不被强行搬入 CR `specs`；历史 CR 与 delivery 保持其目录职责。
7. 不依据主 checkout 的陈旧快照猜在途 CR 状态；CR 操作根以 crctl 返回为准，消费可信上下文，不自行拼 worktree 路径。
8. 定制台账仍按目标仓现有格式登记；追溯使用真实流程的变更／任务标识，不为 STDD 编造 CR 编号。格式不接受该标识时停止并确认，不自行改台账结构。

**为什么**：这些是跨流程损失预防；CR 具体命令、状态计数和事故经过不是常驻底线。

**备选方案及排除原因**：只删历史字数无法修复默认流程；把底线全部搬到选读文档会降低可发现性。安全保证优先于字符目标，不设强迫删减的 token KPI。

### D3. STDD 定位依赖业务仓绑定，而非知识库 cwd

**方案**：入口先识别目标业务仓，读取其 `.stdd/binding.yaml`，再按真实安装信息确认资源根、记录根及当前阶段技能。已有安装技能优先使用；未公布 slash command 时明确读取对应资源技能，不能声称命令已注册。无绑定或资源路径不明时停止，不自动 init、install、upgrade 或回退。

知识库根无绑定并不单独构成失败：若目标业务仓已经明确且其绑定有效，应核实三根并切到该业务根执行 CLI；只有目标、其绑定或归属无法确认时才停止询问，不能从知识库根直接回退旧模式。知识库根不新增绑定或项目配置，不复制 STDD 母本；本次 tools change 从 tools 业务根执行 CLI。

**为什么**：现有三根布局足够，新增绑定可能把共享知识库误当成单一业务项目。

### D4. tools 包维护与 CR 执行规则分别适用

**方案**：`../tools/AGENTS.md` 常驻包职责、事实源和工程规范；修改 Agent／Skill／Pipeline 才要求相关矩阵、索引及相邻定义；执行 CR 或修改 CR 流程时读取完整流程及相关 Pipeline／Skill。

原有包边界、唯一 owns、Pipeline 引用、lint、受控账本、门禁向前兼容和单一事实源保证全部保留。CR 章节明确作用域，不以“维护 tools”或“使用 OutputGuard”等同于启动 CR；不全局删除旧 CR 的 approve 规则。

**为什么**：tools 同时是代码包和 CR 方法论资源，不是当前所有任务的工作流身份。

### D5. 只修说明，不修改运行语义或事实源结构

**方案与精确范围**：

| 文件 | 计划修改 | 明确不改 |
|---|---|---|
| 知识库 `AGENTS.md` | 入口重组；按需加载；修正陈旧说明；保留用户现有保证 | CR 状态机／参数副本、用户原有保护的语义 |
| 知识库 `README.md` | 新增当前工作流入口及 STDD 记录目录指引 | 已有产品规格和参考资料的权威范围 |
| 知识库 `dir-graph.yaml` | 修正顶部回退注释；仅可更新 docs/tools 两个 repository 的 description | schema、workspace、repo 身份／路径／active／trunk／remote／commit_prefixes、required_roots 等所有其他值 |
| 知识库 `CONTEXT.md` | 仅在开头说明领域术语不自动启用某流程，选择规则见 AGENTS | 既有领域定义、CR 合同、在途设计事实 |
| tools `AGENTS.md` | 阅读路由与工程／CR 作用域分层；不复制状态机 | 索引、矩阵、Pipeline、Skill、gates 和脚本 |
| 全局 `~/.pi/agent/APPEND_SYSTEM.md` | 仅将第 2 行改为“安全与数据完整性是底线；在此前提下优先满足用户明确要求。涉及不可逆操作、数据丢失或敏感信息时，先明确影响并取得必要确认。正确性优先于简洁。” | 其余文字、异常处理、模型／权限／工具配置 |

描述字段是展示信息；graph 的业务配置比较须排除上述两个允许变化的 description，不能把整份解析对象不相等误判为业务配置被改，也不能放行其他字段。

### D6. 非代码规格使用原生 CP，并披露当前渲染缺口

**方案**：任务类型保持 documentation。两个 capability 使用 change 内的 canonical agent YAML，不为了自动渲染而伪装为 code 任务或增加运行时代码。

- `canonical/specs/agent/2026-11-06-stdd-default-cr-opt-in.yaml` 对应 workflow-routing，保留 CLI 脚手架已登记的文件位置。
- `canonical/specs/agent/prompt-governance.yaml` 对应 prompt-governance。
- 保留 `specs/*/spec.md` 作为 STDD 所需的非权威兼容视图，不是第二份需同步维护的规格源。评审直接引用 Canonical CP，视图不增加独立预期或逐项同步义务；它们不是 CLI 自动生成，也不在 canon 的 hash／body 漂移校验范围内。`validate.py:24–26,40–41` 仅要求四个根文件并在 specs 存在时检查；`canon.py:910–976` 的 verify 只校验 proposal；`gate.py:241–246` 仅将已存在的 spec.md 纳入输入。CI `ci.py:727–730` 在无 Markdown spec 时告警；SPEC Skill Step 6 要求每个 capability 一个 spec.md，BUILD Skill A1 在无 spec.yaml 时回退读取 spec.md，DELIVER Skill Step 2 明确用它合并规范，故当前不能删除。

**当前实现限制**：CLI 无法把 change 内 agent canonical 渲染为 spec.md。`agent verify --change` 虽有原生证据分支，仍固定读取项目级 canonical，并覆盖 `projects/tools/agent-verification-report.md`；覆盖共享报告可能使其他 change 的证据摘要失效。其冻结输入仅接受业务／数据根，本次知识库根和用户全局文件不在其中，不能据此证明这些输入未变化。本次不调用该入口、不新建项目级验证合同。`new` 生成的 `canonical/.canon-index.yaml` 含缺失 code spec 登记；不手改该受控索引，不补空代码规格掩盖缺陷。提案视图仍由 CLI 生成并 verify。

**Gate 2 边界**：历史方案 A 和用户 2026-11-10 的修订决定均不豁免强制检查。修订涉及已锁定的 D5、CP 和测试预期，按 SPEC Skill Step 6 的“修订文档后重新展示等待确认”和 BUILD Skill B4 的重大偏离规则，修订版仍待 Gate 2 重新确认；本次不执行任何批准或状态变更。CLI 的 historical/unfingerprinted 只保留历史批准，不自动要求重签；`gate.py:341–342,540–549` 对这类历史记录的 `--reapprove` 也会幂等返回，不能声称该命令已经或必能冻结修订版。不得手改状态补指纹。原生证据的实际可用性见 D7；不能把 10 个规格定义当成执行证据。

### D7. 验证区分静态条款、场景语义与真实运行时

文档层验收目标为 Canonical CP 的只读静态检查、文档场景／差异评审和用户对受审文档的明确批准。它只证明条款、文案语义和批准范围，不证明运行时路由、真实模型遵循、部署或代码执行覆盖。每个 TC 的人工评审仍回答选哪套流程、会否创建／修改、还需何种授权及冲突处理；不再给 CP-PG-003 维护并行替代预期。

STDD 已有合法的非运行时验收机制，而非一律要求 pytest：`evidence.py:123–150,429–476` 的证据计划支持 `kind: command/manual`，人工确认绑定当次 run／冻结输入；`evidence.py:563–624` 支持 `coverage: {applicability: not_applicable, reason: ...}`，`ci.py:950–952` 据此免除代码覆盖产物义务。`task_type: documentation` 本身仅影响脚手架／编辑权限，未提供 BUILD 门禁豁免；无 `test_type` 切换入口，action 仍是命令字符串。

但该机制在本 change 的允许范围内不可落地：计划和 runner 固定读取项目级 `canonical/specs/agent/<task>.yaml`（`evidence.py:80–86`、`agent.py:83–89`），当前项目无该目录；runner 固定写共享 `agent-verification-report.md`，验证器也强制引用它（`agent.py:134–139`、`evidence.py:723–727`）。冻结输入仅接受 project/data 相对路径，拒绝绝对路径及 `..`（`evidence.py:29–36`），不能覆盖知识库根和用户全局文件。单填 coverage 不适用也必须先通过完整 `_plan` 校验，不能当作独立开关。Gate 3 和 BUILD→DELIVER 仍要求切片记录（`gate.py:273–279`、`phase.py:151–158`），没有 documentation 例外。

因此这里是“跨根、change-local 文档验收无法闭合”的 STDD 工具缺口，不是文案必须增加运行时代码或伪造覆盖率。当前不启用不可执行的证据计划、不复制 CP 到项目级、不写共享报告、不制造 coverage.json、不手改 `.stdd.yaml`；原生 TC 覆盖及切片记录仍未闭合。记录真实 CI 结果后停止 BUILD，等待另行授权的工具支持和修订版 Gate 2 确认；用户的文档修订决定不等于当前 run 人工验收或 Gate 3 批准。

复用 tools 原生 lint／合同检查，明确它们不扫描根 AGENTS、graph 或全局 APPEND_SYSTEM。默认 lint 为 report，退出 0 不代表无漂移；保留原 quality 命令并另行运行 `--mode enforce`，同时记录 findings。完整测试仍按现有 quality 配置保留；不能因本次是文档任务而关闭检查，未完成或有既有失败均如实记录，不能写成通过。

## Architecture

```text
请求 + 已有变更身份 + 目标业务仓
  -> 根入口共同底线和冲突检查
  -> 只读 / 已有流程 / 新变更默认 STDD / 显式 CR
  -> 所选流程原生定位与当前阶段资料
  -> 所属合法入口；任何 Gate、提交与部署授权均独立判断
```

无新配置、流程字段、命令包装器或状态映射；STDD `.stdd.yaml` 和 CR 账本仍各自唯一。

### 实施顺序（仅 Gate 2 与 BUILD 模式获确认后）

1. **入口任务**：先按 test-plan 记录当前条款缺失，再定点修改知识库 AGENTS／README／CONTEXT 和 graph 说明；检查绑定场景、业务配置不变与已有用户保证。
2. **约束分层任务**：修改 tools AGENTS 和全局优先级一行；检查工程约束、真实 CR 审批和全局其他行完整；运行原生 lint／合同检查。
3. **交叉验收任务**：独立场景评审、字符与加载链比较、既有配置测试及差异核对，形成 test-report 和 Gate 3 材料。状态只经 STDD CLI 更新；不自动提交／推送。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|---|---|
| 提示词规则不等于运行时强制 | 不声明已部署或已证明模型行为；静态与语义结果分列 |
| 两个流程同时出现导致覆盖 | 已有身份优先，冲突先停；禁止映射、双写与审批互认 |
| 非代码 Human View 缺少 CLI 防漂移 | 仅为必需兼容视图，不增加第二来源或同步检查；评审直接引用 Canonical CP，修订版 Gate 2 待确认 |
| 现有大量 dirty 与用户 AGENTS 修改被覆盖 | 写前重读、比对以下基线；仅 Edit 精准替换；不 reset、stash、checkout 或批量格式化 |
| 上游旧说明继续漂移 | 根只留权威入口，不再维护固定数量和状态／节点副本 |
| standard 验证因环境／既有失败不能完成 | 原样报告退出码、时长及未完成项，不扩大修复在途工作，不伪造通过 |

### 修改前基线（UTF-8 内容先 CRLF → LF，再 SHA-256）

| 文件 | SHA-256 |
|---|---|
| 知识库 AGENTS.md | `74ae121374ae682307ea69b0845ee13b77decb5a64fdc4327ff97078ad7ee2c0` |
| 知识库 README.md | `49d2a566c78e6188de3a8b3378648eee6efe36f264507c8a5484681c5121a527` |
| 知识库 dir-graph.yaml | `9de241e6dd02d17f84b6048c88c129944f4ab66f80f17009aa7e8caf4717021b` |
| 知识库 CONTEXT.md | `32334ba59f4a63c39db68d4662d68e39989e1bf470986c24443ee8cef0d5d8b2` |
| tools AGENTS.md | `9b98ed84525ea0a875ee18cf0a8b4fd08fbb0a92f18e86b245c50fff1fa5dd88` |
| 全局 APPEND_SYSTEM.md | `a761488e765bb29a807e3c50eeafc15622b1cd7b623bf900c50c0590887bf163` |

知识库 HEAD：`1a409847af4f049dbbd06ed8e86e6d7267d7496a`；tools HEAD：`75ec007395b384d14554297b686207578668e6ba`。HEAD 不是 dirty 文件的完整基线。若实际内容已变化，先重读与核对，不以本表覆盖后来的合法修改。
