# CR 生命周期优化方案（最小闭环版）

> 核对对象：`docs/analysis/CR 流程待改进.md` 原始过程记录、工作区 `AGENTS.md`、当前 `dir-graph.yaml`，以及 sibling `../tools/` 的远端 `custom/main` 提交 `7b73204464e136b83d4377ba1447a11c2291e6c6`。
>
> 核对结论：远端 `crctl` 测试套件 294/294 通过；但局部测试通过不等于 CR 生命周期闭环正确。本方案只修已有原语的组合漏洞和契约漂移，不再增加事务框架、状态机副本或通用编排层。

## 1. 目标与边界

本次目标不是把所有历史摩擦都产品化，而是回答三个问题：

1. 原记录中的问题，哪些仍会在当前代码上真实发生？
2. 哪些问题已经被基础设施解决，只需要复用现有入口？
3. 哪些建议会扩大职责、复制能力或引入新账本，应明确拒绝？

采用 ponytail 优先级：复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。

### 1.1 事实源

| 事实 | 唯一来源 |
|---|---|
| 工作区目录与仓库映射 | 本仓库 `dir-graph.yaml` |
| 状态、转移、门禁 | `../tools/dir-graph.yaml`、`../tools/skills/shared/crctl/gates.json` |
| 节点顺序与 reviewLoop | `../tools/pipeline-templates/*.pipeline.json` |
| 业务输入输出和失败语义 | 对应 `skills/**/SKILL.md` |
| 状态/门禁/CAS/受控账本与 Git | `../tools/skills/shared/crctl/` |
| PRD/SDD/TASK/traceability 转换 | `../tools/skills/**/scripts/` |
| 人读流程概览 | `../tools/README.md` |

README、分析文档和历史复盘不能再成为可执行事实源。

### 1.2 严格职责边界

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 算法、手写账本 |
| Skill | 业务判断、步骤编排、输入输出、失败语义 | 原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本、审计、原子提交 | 业务设计判断、LLM 结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 确定性转换 | 状态推进、人工审批 |
| README | 人读总览、入口、边界 | 节点级可执行细节 |

## 2. 已解决的基础设施：只复用，不再重造

以下能力在当前 `tools` 已存在，并由测试覆盖。原记录中对应的“需要再建一套”建议全部撤销：

- `register`、`advance`、`approve`、`next`、`status` 及状态门禁；状态权威为 CR worktree 的 `cr.md`，主工作区只作视图。
- CAS、远端 ref 校验、TTY 人工审批限制、受控 Git commit/push、审计与 outbox。
- durable transaction、锁、journal、write-set、恢复和残留事务检测。
- `checkpoint` 远端快照、首推/重试/幂等、CRLF 规范化、worktree guard、旧读取协议兼容。
- `review-record` 的 annotation + review-loop + traceability 原子落盘和 attempt 记账。
- `release-subjects` 签名快照及 code approve/writeback 前的漂移保护。
- candidate-only 生成器和 writeback 累积脚本；`specs/` 是累积基线，不是最近一次 CR 的副本。
- workspace resolver；Tools Root 由 `dir-graph.yaml#workspace.tools_package_path` 解析，无需回退路径。
- YAML 子集解析与共享的 block matcher；不再新增第二个 parser 或 ledger helper。

原记录中的 #84—#101、#117 主要属于上述基础设施修复；#109 关于“release-subjects 必须只接受 HEAD”是已被当前实现否定的假设，不应据此放宽安全门禁。

## 3. 当前生命周期审计

严重度定义：

- **P0**：会丢状态、阻断合法重试、制造确定性合并冲突，必须先修。
- **P1**：会让已通过的证据失效或造成数据误导，应在 P0 后修。
- **P2**：契约/文档摩擦，不改变状态正确性，集中清理。
- **保留/延期**：当前没有可证明的流程漏洞，或引入的机制超过问题本身。

### 3.1 P0：必须修的组合漏洞

| 编号 | 现象 | 当前证据 | 最小修复 | 归属 |
|---|---|---|---|---|
| P0-1 | baseline 回写先 `writeback-apply`，再独立 `advance --embedded`；下一阶段回写从 origin 重置时，状态提交可能丢失 | `feature-writeback.pipeline.json` 的 baseline 节点；原记录 #122 | `writeback-apply` 接收 Pipeline 已决定的 `--advance-to writing-back --trigger ...`，在同一 txws/commit/push 中完成回写和状态发布；删除后置独立 `advance` | `crctl` 原子提交；Pipeline 传参 |
| P0-2 | 非法 manifest 在 journal 建立后才解析，修正输入会撞上 `TX_INPUT_CONFLICT` | `workspace-transactions.mjs` 先 `loadOrCreateJournal` 后 `validateWritebackManifest`；当前测试 #121 正在期待错误行为 | 在创建 journal、加锁、写文件前完成路径包含、manifest、spec-id、生成器 hash 和目标矩阵校验；非法输入零写入，修正后可直接重试 | `crctl` preflight；测试改断言 |
| P0-3 | checkpoint 将 `latest-checkpoint` 写入目标 CR 的 `_backlog.yml` 条目；trunk 注册新 CR 时，非最后一条 CR 会出现无业务价值的账本冲突 | 当前 `checkpoint` 和 merge 的 `_backlog.yml` 处理；原记录 #112/#119/#122 | merge prepare 对 `_backlog.yml` 采用 trunk 版本，保留 CR 分支的 `cr.md`、产物和 merge 证据；新增非末条 CR + trunk 新注册 CR 回归测试 | `crctl` merge prepare；不新建账本 |
| P0-4 | code review PASS 后没有再次 push，人工 `approve-code` 重核远端时可能 `REMOTE_REF_DRIFT` | `code-implementation.pipeline.json`：`review-code` 后直接 `human_approval`/`approve-code`；原记录 #114 | 在 review PASS 且 blockers 为空后插入现有 `push-progress`；人工审批前远端必须已包含 review annotation；保留 approve 后的现有 push | Pipeline 节点顺序；`crctl` 继续重核 |

### 3.2 P1：证据和状态正确性

| 编号 | 现象 | 最小修复 |
|---|---|---|
| P1-1 | dev-plan 评审只记录 verdict/blockers，plan 或 TASK body 改动后仍可能沿用 PASS | review-record 在 dev-plan 阶段记录 `plan.md + 排序后的 TASK-*.md` digest；`next/approve` 复用现有 digest 校验。不要做通用 freshness 框架 |
| P1-2 | 注册写 `updated:`，`crMdStatusText` 只替换 `updated-at` | 以 `updated` 为当前字段；读取时兼容旧 `updated-at`，写入只产生一个字段 |
| P1-3 | `crctl test` 重建机器区时可能覆盖 marker 后的人类分析 | 只重建 marker 前的机器区，保留 marker 后原文；补一条“人类分析保留”回归测试 |
| P1-4 | review Skill 要求 `repair-instructions`、`fixed-blockers`，canonical annotation 实际只有 `blockers` | 统一合同为 `verdict + blockers + suggestions + dimensions + repair-target`；回修直接消费 canonical blockers，不把临时 fixed 列表写账本 |
| P1-5 | candidate 必须在 txws 内，但 Skill 没有统一目录；残留 candidate 会阻塞 archive | 固定 `{operational_workspace}/.crctl/candidates/{CR-ID}/{stage}`，三个 writeback Skill 只调用 generator 和 `crctl` |

### 3.3 P2：契约和文档收敛

1. CR 的 PRD/SDD/TASK 以对应 write Skill 的最小模板为准，不再同时引用 `engineering-docs` 的旧 schema、`_config.yml`、MCP `owClient`、`_index.yaml` 等失效契约。`engineering-docs` 仍可服务通用知识文档；只有全仓 `rg` 证明无调用后，才另开清理任务。
2. `validate-doc` 当前声明“所有写入 Skill 自动调用”，但 CR write Skill 没有共同调用点。删除这一声明；结构校验留在各自 Skill/评审，不把业务模板校验塞进 `crctl`。
3. `quality-reviewer-agent` 中不存在的 `reviewer-panel.yaml` 引用应删除；不新增 reviewer panel、并行评审协议或 Agent 状态机。
4. 删除 code Pipeline 的 `review_llm` 人工选择暂停。Agent/运行时负责选择可用 reviewer；Pipeline 只传递 reviewer 结果。删除 `suggestion_policy strict|lenient` 和“首轮升格 blocker”的规则，统一为：本 CR 必须处理的是 blocker，其余是 suggestion。
5. write Skill 不再写 commit message、手工 `git add/commit/push` 配方；发布由 `push-progress`/`writeback-apply`/`crctl advance` 负责。
6. README 改为生命周期总览、职责边界、入口命令和链接；删除节点 prompt、默认值、错误矩阵和会漂移的示例。修正 `auto_push_*` 默认值、Tools Root fallback、`writeback-traceability` 旧注释。
7. tools `AGENTS.md` 中与当前状态机不一致的 reject 文案、工作区 `dir-graph.yaml` 中的 fallback 注释一并修正。它们是文档事实源问题，不增加运行时逻辑。

### 3.4 保留、否决或延期

以下建议不进入本次实现：

- CR 级 `depends-on` 门禁、target repo/source scope 新字段：当前依赖链可人工管理，尚无重复事故证据。
- 新 CLI `skill-path`、通用错误码注册表、公共 payload validator、通用维度 schema/规则引擎：会复制现有索引、错误语义或 Skill 业务判断。
- 把 release-subjects 放宽为任意 content diff：会削弱审批安全边界；严格 reviewed SHA ancestor + metadata whitelist 保留。
- `--force-drift-rollback`、merge conflict bypass、新事务 envelope、第二套账本/数据库：现有 `crctl` 状态推进、重新 checkpoint 和恢复语义已经足够。
- title Unicode、Windows shell 示例、日志噪声等：修正示例和文案即可，不改生命周期模型。
- review-loop 与 traceability 的双投影：当前由 `review-record` 原子维护，改动面大；本轮只统一输入输出字段。

## 4. 推荐生命周期

```text
注册
  -> requirement-authoring Pipeline
  -> PRD 生成 / review-requirement loop / 人工 approve
  -> push-progress（审批证据）
  -> architecture-design Pipeline
  -> SDD 生成 / review-tech-design loop / 人工 approve
  -> push-progress
  -> dev-plan 写 plan + TASK / review-dev-plan loop（含 plan+TASK digest）/ 人工 approve
  -> push-progress
  -> code-implementation Pipeline
  -> implement-code / write-test-report / push-progress
  -> review-code loop
  -> push-progress（评审 PASS 后、人工审批前）
  -> approve-code / push-progress
  -> feature-writeback Pipeline
  -> crctl merge
  -> baseline writeback-apply + advance(writing-back) 同一提交
  -> tasks writeback-apply
  -> traceability writeback-apply
  -> crctl archive
```

规则只有三条：

1. 业务节点不直接写状态或 Git；节点只产生业务产物/临时 payload。
2. 任何需要发布到远端、改变状态或写受控账本的动作，调用既有 `crctl` 深原语。
3. 评审 PASS 不是远端发布；PASS 后到人工审批前必须有一次 checkpoint，避免审批证据与远端不一致。

## 5. 详细实施步骤

### Phase 0：冻结事实源和测试基线

1. 固定 `tools` 基线提交，记录当前状态机口径：15 个具名状态 + `(new)`；28 条声明转移、wildcard 展开 50 条。
2. 在远端 `crctl` 运行完整测试，保存 294/294 基线。
3. 对所有 write Skill、Pipeline、README 做 `rg` 清单，列出 `repair-instructions`、`fixed-blockers`、`review_llm`、`suggestion_policy`、`engineering-docs`、`validate-doc`、`manual git` 的调用点。
4. 不修改业务 CR 产物，不手改 `_backlog.yml`/`cr.md` status。

验收：能从 Pipeline → Skill → `crctl` → script 找到唯一写入入口；所有状态推进仍只走 `crctl`。

### Phase 1：修 P0 原子边界

1. 在 `applyWriteback` 中抽出纯只读 preflight，顺序固定为：解析参数 → 解析 candidate → 校验 manifest/schema → 校验路径 containment → 校验 spec-id/generator hash → 检查目标矩阵 → 再获取锁、创建 journal、生成 write-set。
2. 扩展 `writeback-apply` 参数，允许调用方传入 `advance-to`、`trigger`、`expect`；状态转移和门禁仍由 `crctl` 验证，状态文本与回写产物进入同一 write-set。
3. 修改 feature-writeback baseline 节点：一次 `writeback-apply --advance-to writing-back`；移除独立 embedded advance。
4. merge prepare 生成结果树时，对 `change-requests/_backlog.yml` 使用 trunk blob；其他 CR 产物仍来自已验证源树。
5. code Pipeline 在 review-code PASS 后插入已有 `push-progress`；失败或 phase 非 complete 立即中止。

验收用例：

- baseline 回写成功后，下一次 tasks 回写不会因本地 status commit 丢失而回到 `merging`。
- 非法 manifest 首次调用失败后无 journal、无锁、无目标文件；修正 manifest 可成功。
- 目标 CR 不是 backlog 最后一项、trunk 同时新增 CR 时，merge 无 `_backlog.yml` 冲突且 checkpoint 证据仍完整。
- review PASS 后未完成 push 时不能进入 approve；push 成功后 approve 可通过。

### Phase 2：修 P1 证据一致性

1. 复用现有 canonical digest helper，为 dev-plan 增加稳定文件集合：`plan.md`、按路径排序的 `tasks/TASK-*.md`；不把会在实现期变化的 `_index.yml` 放入该 digest。
2. `review-record --stage dev-plan` 写入 digest；`next`/`approve` 在 PASS 消费点重算并拒绝漂移。
3. 修正 `crMdStatusText` 的 `updated` 写入和旧字段读取。
4. 修正 test report marker 保留逻辑，并增加 CRLF/LF 回归。
5. 固定 candidate 目录并在 archive 前由既有 txws 清理逻辑处理，不增加新的 cleanup daemon。

验收：修改 TASK body、旧时间字段或 marker 后人类分析，均有明确可重复的测试结果；不存在静默通过。

### Phase 3：收敛 Skill/Pipeline 契约

1. 将所有 review 输出改为 canonical blockers/suggestions/dimensions/repair-target；更新 review Skill、Pipeline node output 和 `crctl` JSON 返回。
2. 删除 `repair-instructions`、`fixed-blockers` 的持久化要求；回修输入直接引用 review annotation 的 blockers。
3. 删除 `review_llm` human approval 和 `suggestion_policy` 输入；由 Agent/runtime 选择评审器，review Skill 只输出业务结论。
4. 三个 writeback Skill 使用统一 candidate 路径，删除手写 Git 和账本配方。
5. CR write Skill 不再调用旧 `engineering-docs`/`validate-doc` 契约；保留确定性生成器调用。

验收：Pipeline JSON 中不存在上述废弃字段；Skill 不包含 status 字段编辑、YAML 账本拼接、Git commit/push 逻辑。

### Phase 4：文档收敛和死引用清理

1. README 只留下人读流程、职责、入口命令、故障恢复入口和权威链接。
2. 修正 AGENTS、SKILL、dir-graph、writeback-traceability 的事实漂移。
3. 全仓 `rg` 确认 `reviewer-panel.yaml`、`change-requests/_config.yml`、`owClient.writeFile`、`updated-at` 新写入、`repair-instructions` 持久化没有活跃调用方。
4. 只有确认无调用后，才删除历史 `engineering-docs/scripts` 或其他死文件；删除另开提交，不与 P0 混合。

验收：README 与 Pipeline/Skill 的事实不冲突；删除任何死文件前均有引用检查记录。

### Phase 5：端到端验证

按真实生命周期跑一条最小 CR：

1. register → requirement review/approve。
2. architecture review/approve。
3. dev-plan review/approve，验证 TASK digest。
4. implement → test report → checkpoint → code review PASS → checkpoint → code approve。
5. merge → baseline/tasks/traceability writeback → archive。
6. 在每个人工节点前制造一次远端推进，确认 CAS/漂移错误可解释且不会静默覆盖。
7. 用 CRLF 检出内容、重复调用、非法 candidate、非末条 backlog、断电恢复 fixture 各跑一遍。

最终验收不是“单元测试全绿”，而是：状态、远端分支、CR 产物、specs/delivery/traceability/_history 四类投影一致，且失败后可从错误提示继续，不靠手改账本。

## 6. 原记录问题的处理口径

原文的 124 条编号不再逐条作为需求。按本方案归类如下：

| 原记录类别 | 处理 |
|---|---|
| 已被当前基础设施覆盖（含 #84—#101、#117） | 保留为历史证据；不重复实现 |
| 明确误判（#109 等把安全约束当漏洞） | 标注为否决；不放宽门禁 |
| P0 组合漏洞（#112、#114、#121、#122、#123） | 进入 Phase 1，并补跨节点回归 |
| review 合同/证据问题（#14、#16、#20、#21 及同类） | 进入 Phase 2/3；统一现有字段，不新增账本 |
| 模板、README、fallback、旧 MCP、手写 Git 等 | 进入 Phase 3/4；只删失效契约 |
| 依赖图、target repo、scope、错误码注册表、通用 validator 等 | 延期或否决；当前证据不足，且会过度设计 |
| shell/Unicode/日志噪声/单次操作失误 | 修正文案或操作纪律，不改生命周期架构 |

原始过程记录如果需要追溯，使用 Git 历史查看；本文件只保留可执行结论和验收条件，避免“事故日志 = 第二份规格书”。

## 7. 明确不做的架构

本轮禁止出现以下实现：

- Agent 内部状态机、Agent 直接改 status、Agent 直接执行受控 Git。
- Pipeline 复制 `crctl` 的 journal/CAS/账本算法。
- Skill 自己拼 `_backlog.yml`、`traceability.yml`、任务 `_index.yml` 或实现 Git commit。
- `crctl` 解析 LLM 业务结论、决定 PRD/SDD 内容或评审维度语义。
- 新建 transaction manager、workflow engine、ledger database、错误码 registry、schema registry。
- 为“可能以后并行”提前加入 CR 依赖门禁、目标仓库模型、跨仓事务模型。

任何新增抽象必须先证明：现有入口无法表达、存在已复现的真实故障、且新增代码少于复用现有能力的成本；否则不接受。

## 8. 结论

当前 CR 流程不是缺少一套更大的框架，而是已有深原语在四个边界上没有闭合：回写状态发布、回写输入 preflight、checkpoint 账本合并、评审到人工审批的远端发布。先修这四处，再修证据 digest 和字段契约，最后清理文档漂移。

这样可以保留已经投入并验证过的 `crctl` 基础设施，同时把 Agent、Pipeline、Skill、脚本、README 的职责拉回最小边界，避免继续叠加第二套事务框架。
