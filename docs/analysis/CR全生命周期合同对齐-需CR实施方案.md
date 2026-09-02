# CR 全生命周期合同对齐：需 CR 实施方案

> 状态：经去重、减重后的单 CR 实施方案
> 日期：2026-09-01
> 实施单位：一个 CR、四个 TASK、一次整体审批与合入
> 适用范围：会改变 tools 包运行时输入、输出、门禁、状态操作、评审标准、写入范围或持久化产物的修改

## 0. 方案边界与总原则

本方案只处理生命周期各阶段之间的**合同对齐**，不重新设计生命周期事务。实施时严格区分两类工作：

- **已经解决的基础设施**：继续作为唯一底座复用，不在本 CR 中再造一套状态、事务、账本或恢复机制；
- **本次应复用的最小改造**：只补齐生产端与消费端之间缺失的字段、校验、评审标准和确定性投影。

实现优先级遵循 ponytail：

```text
复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码
```

全程不新增状态、Pipeline、事务框架、独立 ledger、contract-version、迁移器或 feature flag。只有现有机制无法表达可复现缺口时，才允许扩大范围，并须另行说明原因。

## 1. 已经解决的基础设施：本 CR 不重复建设

以下能力已经由 tools 包及目标 workspace 的目录图、状态机和既有 Skill 提供。本次只调用、复用或在现有入口上增加必要的合同字段，不复制其算法。

| 模块 | 已有能力 | 本 CR 的使用方式 |
|---|---|---|
| `crctl` | 状态机、门禁、CAS、受控账本写入、审计、事务、lease、幂等、受控 Git 操作、原子提交 | 所有状态和账本变化继续走现有 `crctl` 入口；只补合同校验或输入输出，不新建事务层 |
| workspace / repository resolution | 从目标 workspace `dir-graph.yaml#repositories` 解析仓库、trunk、worktree；区分 CR worktree 与 operational workspace | Agent、Pipeline、Skill 都传递并读取解析后的运行时上下文，不拼接固定路径或固定仓库名 |
| CR 账本与 owner 模型 | `cr.md`、`_backlog.yml`、owner roles、owner history、outbox 及状态事件 | `cr.md` 是 CR 业务事实源；账本更新仍由 `crctl` 原子完成 |
| Pipeline 执行框架 | 节点顺序、输入传递、失败中止、reviewLoop、`review_feedback`、checkpoint | 只调整节点合同和 replay 配置，不实现动态流程引擎 |
| writeback 事务原语 | candidate、journal、manifest、发布、冲突检测、恢复命令、merge 与 archive 事务 | generator 产出确定性 candidate，交由既有事务原语提交；失败沿用现有恢复语义 |
| 版本化脚本 | PRD/SDD、TASK、traceability 的确定性转换与校验 | 扩展现有 generator 的输入/输出，不把状态推进或人工审批塞进脚本 |
| 评审与审批边界 | `review-*` 产生 canonical 评审记录；`approve-*` 仅由人通过 `crctl approve` 执行 | 保持作者/reviewer 对称，Agent 不代签，writeback 不重新做上游质量评审 |
| 运行规范与索引 | `AGENTS.md`、`README.md`、各 `_index.yml`、权限矩阵和 JSON pipeline 是既有约束 | 本 CR 只同步受影响的合同说明；README 仍是人读总览，不成为第二可执行事实源 |

因此，以下事项明确排除：自建 transaction manager、第二套状态机、手工编辑 `_backlog.yml`、Pipeline 内手写账本算法、每个错误类型独立错误码，以及为历史 CR 批量迁移产物。

## 2. 模块职责边界

各层只拥有自己应拥有的逻辑，跨层需求通过现有 Skill/`crctl` 契约传递，不越权：

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、步骤编排、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 面向人的流程总览 | 另一份可执行细节事实源 |

### 2.1 本 CR 的最小改造原则

1. **业务判断留在 Skill**：例如 PRD 是否缺产品语义、SDD 是否关闭技术延后项、TASK 是否覆盖 SDD，由对应 writer/reviewer 判断。
2. **确定性转换留在脚本**：例如从冻结 PRD/SDD/PLAN/TASK 生成 baseline、delivery、traceability，由已有 generator 完成。
3. **写入和状态留在 `crctl`**：Skill 不直接修改状态或账本；Pipeline 不绕过 `crctl` 写入事务文件。
4. **跨阶段只传最小上下文**：运行时传 `cr_id` 与 `operational_workspace`；业务字段从 `cr.md` 或当前阶段产物读取，避免 execution context 变成第二事实源。
5. **兼容只保留一条必要旧路径**：以 `cr.md` 是否存在 `target-spec-id` 识别 new/legacy mode，不新增协议版本。

## 3. 全面复核结论

原方案方向正确，但存在重复保护和不必要的运行时扩展。收敛后的最小替代如下：

| 原方案设计 | 问题 | 最小替代 |
|---|---|---|
| 注册 execution_context 返回 owners、target spec/version、全部 resources | 与 `cr.md` 和后续 workspace inspect 重复，形成第二事实源 | requirement Pipeline 只传 `cr_id + operational_workspace`；业务字段读 `cr.md`，后续阶段重新 inspect |
| 注册期解析 source 路径 | 混入 PRD 输入职责 | register 只保存安全 scalar；PRD writer 读取路径时再校验 containment/existence |
| PLAN 三张表 | 与 SDD 交付清单、FR/AC 覆盖矩阵重复 | 合并为一张交付覆盖表；验证命令单独一张表 |
| dev-plan 三轨动态回修 | 为 task-only 问题扩展动态 replay | 保留 plan→tasks→review；PLAN 正确时 writer no-op |
| code 两轨动态回修 | 为 evidence-only 问题扩展动态起点 | 保留 implement-code→test-report→review；纯证据问题 implement-code no-op |
| aggregate evidence digest 与三套 drift 错误 | source revision、log hash、command digest 已足够 | 发布已有 source revision/log hash，统一按 evidence drift 阻断 |
| 每类 PLAN/TASK 缺口一个错误码 | 消费方只需要失败原因 | 复用结构化 validation failure，findings 给原因 |
| CR-aware 独立 schema | 与 writer/reviewer domain 合同重复 | CR PLAN/TASK 不套通用模板；writer 自检 + reviewer 同款检查 |
| 所有 active worktree 必须提交 | 未参与变更的 repo 承担无谓收口成本 | 有变更/测试的 worktree clean committed；其他 repo 无意外 diff |
| 每个 generator 重核 approval digest | merge 已冻结 release subjects | generator 消费 transaction workspace 冻结源并校验 candidate/target |
| archive 重算全部 manifest digest | 与 writeback 深原语重复 | 只断言三阶段 complete、目标引用完整、无 pending event |
| 每个 AC 精确映射到文件级代码 | 计划期无法可靠预知最终文件 | 只做 FR→SDD→TASK→repo@mergeSHA→cmd |
| alignment 强制门禁 | code-approved 后重复质量评审 | alignment 只做按需只读诊断，不进 Pipeline、不推进状态、不写 traceability |

保留的核心只有：作者/reviewer 标准对称、阶段职责单一、测试绑定源码、回写纯投影、人工审批边界不变。

## 4. 为什么采用一个 CR

这些修改不是四个独立能力，而是同一个生命周期合同的生产端和消费端：

- register 产生 target spec/version，writeback 消费；
- PRD 产生产品合同，SDD 关闭技术机制；
- PLAN 产生 TASK 和测试命令，Coding/test/reviewer 消费；
- code-approved 冻结的结果最终由 writeback 投影。

拆成多个 CR 会制造临时半状态，例如 reviewer 已升级但 writer 未升级、测试字段已消费但尚未生产、writeback 已去掉输入但 register 尚未提供目标。采用一个 CR 可让成对合同一次批准、一次合入。

一个 CR 的风险不通过增加状态、协议版本或 feature flag 解决，而通过以下四项控制：

1. 四个 TASK 和独立提交隔离评审面；
2. writer/consumer 成对提交，禁止只合入一半；
3. 以 `cr.md` 是否存在 `target-spec-id` 区分新旧合同；
4. 对旧 CR 兼容读取，对新 CR 严格写入，不迁移历史产物。

## 5. 自升级与兼容策略

本实施 CR 本身由旧 register 创建，`cr.md` 没有 `target-spec-id`，其 PLAN/trace 输入也可能是旧格式。新代码合入后，它仍需完成 writeback 和 archive。因此最终实现保留一个最小双路径：

```text
cr.md 有 target-spec-id：new mode
  spec/version 只从 cr.md 读取
  PLAN 新交付覆盖表生成 traceability
  外部重复输入为空或只能校验相等，不能覆盖

cr.md 无 target-spec-id：legacy mode
  沿用显式 spec/version 与旧 milestone 输入
  只服务合入前已注册的存量 CR
```

唯一判据是已有字段是否存在，不新增 `contract-version`、迁移器、feature flag、状态或当前 CR-ID 特判。

### 5.1 Pipeline 兼容方式

最终 `feature-writeback` 暂时保留 `spec_id/target_version`，但改为可选并明确仅供 legacy mode：

- new mode：不要求输入；若调用方仍提供，只校验与 `cr.md` 相同；
- legacy mode：保持当前必需语义，使本实施 CR 和其他存量 CR 可以归档；
- 不允许任何输入覆盖 `cr.md` 已存在的 target spec/version。

`milestone_file` 同理只在 legacy mode 使用；new mode 由 generator 从 PLAN/TASK/test/merge facts 生成。

待所有缺 `target-spec-id` 的 CR 归档后，是否删除 legacy 分支另行判断；本 CR 不为了未来清理再引入协议版本或自动迁移。

### 5.2 回滚方式

采用“兼容读、严格写”：

- 旧 CR 不补字段、不批量改文件；
- 新 register 只写新格式；
- 新字段均为加法字段；
- writeback 继续使用已有 candidate/journal/manifest；
- 合入前可整体撤回本 CR；合入后出现问题可整体 revert，无反向数据迁移。

## 6. TASK-1：注册合同与单一目标事实

### 6.1 目标

让新注册 CR 提供后续真正需要的信息，并在首个评审前冻结版本；不把 execution_context 做成第二份 `cr.md`。

### 6.2 修改文件

```text
../tools/README.md
../tools/pipeline-templates/requirement-authoring.pipeline.json
../tools/skills/requirement/requirement-register/SKILL.md
../tools/skills/requirement/write-requirement-prd/SKILL.md
../tools/skills/requirement/review-requirement/SKILL.md
../tools/skills/shared/crctl/scripts/crctl.mjs
../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs（仅在既有入口需要接入合同校验时）
../tools/skills/shared/crctl/gates.json（仅同步既有门禁，不新增事务门禁）
../tools/skills/shared/crctl/scripts/test/register-tx.test.mjs
../tools/skills/shared/crctl/scripts/test/version-set.test.mjs
../tools/skills/shared/crctl/scripts/test/writeback-tx.test.mjs
../tools/skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
```

### 6.3 最小变更

1. requirement Pipeline 显式传 `registration_key`、`target_spec_id` 和可选 `origin`；`source` 改为可选；
2. `target-spec-id` 写入 `cr.md/backlog`，限定为稳定小写 ID，禁止路径字符；
3. 输入版本可带 v/V，canonical 去前缀并始终以 YAML/JSON 字符串保存；复用既有 version-set，不新增版本状态；
4. new mode 的 `unassigned` 可用于 drafting，但进入 requirement review 前必须通过既有 `version-set` 固化；已进入评审后不得修改；legacy CR 保持旧兼容；
5. 外部单行字段统一拒绝 CR/LF 并使用同一安全 scalar serializer；source 只作为字符串保存，路径读取校验留给 PRD writer；
6. origin 非空时确认目标 CR 存在且已归档；
7. register 只生成一个注册 timestamp，`cr.md/backlog/owner-history/outbox` 共用；
8. register 完成既有 worktree ensure 后只返回：

```yaml
execution_context:
  cr_id: CR-YYYY-NNN
  operational_workspace: <真实 knowledge-base CR worktree>
registration:
  tx_id: <txId>
  changed: true|false
  commit: <registration commit SHA>
  recover_command: <command>
```

9. PRD 的 title/summary/source/target spec/version/owner 一律从 `cr.md` 读取；架构、计划和代码阶段继续使用现有 `crctl workspace inspect`；
10. 兼容期 writeback 若显式传 spec/version，new mode 必须先校验与 `cr.md` 相同，不能覆盖注册事实。

### 6.4 不做

- 不新增 owner identity 服务；只校验非空、单行稳定 ID；
- 不在注册期收集 priority、scope-in/out、技术上下文或实现仓范围；
- 不新增 target-spec-set 或版本状态；
- 不把 summary 强制下沉为 `crctl` 深原语必填，用户 Pipeline 保持必填即可；
- 不返回供后续长期复用的 resources 快照。

### 6.5 验收

- 同 registration key 同输入重跑仍为同一 CR，输入漂移零写入；
- `v0.30` 在 YAML/JSON 中均为字符串 `0.30`；
- new mode 的 `unassigned` 不能进入 requirement review；
- owner assigned-at 在账本和 outbox 完全相同；
- Pipeline 不生成时间、不拼接 worktree；
- new mode 的 writeback 输入与 `cr.md` 不同会在 candidate 前拒绝；
- legacy CR 仍能读取旧字段并继续流程。

## 7. TASK-2：PRD/SDD 作者与 reviewer 标准对齐

### 7.1 目标

需求评审只关闭产品语义，技术设计关闭实现协议；保留首轮一次查全，不让作者在首评才看到标准。

### 7.2 修改文件

```text
../tools/skills/requirement/write-requirement-prd/SKILL.md
../tools/skills/requirement/review-requirement/SKILL.md
../tools/skills/develop/write-tech-design/SKILL.md
../tools/skills/develop/review-tech-design/SKILL.md
```

### 7.3 最小变更

1. writer/reviewer 共用七项产品检查：调用场景、业务输入、成功结果、权限可见性、失败恢复、兼容范围、场景验收；
2. 权限、数据损失、重复副作用、兼容和产品二选一不得延后；
3. 只有产品结果唯一时，wire schema、精确错误、分页、锁、事务和幂等载体才可进入条件性 `SDD-CLOSE-*`；
4. SDD writer/reviewer 逐项关闭已有 `SDD-CLOSE-*`，并按适用性检查 HTTP 技术契约；
5. SDD 若需改变已批准产品结果，停止并回到需求阶段；
6. target spec 只做 PRD scope 归属核对，不在 requirement review 选择或修改。

### 7.4 不做

- 不新增风险评分、契约文件、ledger、状态或 reviewer 节点；
- 不要求内部 API 在 PRD 写完整 wire contract；
- 没有技术延后项时不创建空章节；
- 不复制一套 HTTP 规范到 Pipeline/README。

### 7.5 验收

- 同一缺口在 writer 自检和 reviewer 中阶段归属一致；
- 产品结果明确且只有技术机制未定时 requirement 可 PASS；
- SDD 未关闭已有延后项时必须 BLOCK；
- 安全、权限和数据完整性问题没有被降级。

## 8. TASK-3：PLAN/TASK、Coding、测试与代码评审对齐

### 8.1 目标

让计划、实现、测试和 reviewer 消费同一 workspace、同一任务合同和同一证据，不扩展动态回修引擎。

### 8.2 修改文件

```text
../tools/pipeline-templates/code-implementation.pipeline.json
../tools/skills/develop/write-dev-plan/SKILL.md
../tools/skills/develop/write-dev-tasks/SKILL.md
../tools/skills/develop/review-dev-plan/SKILL.md
../tools/skills/develop/implement-code/SKILL.md
../tools/skills/develop/coding-discipline/SKILL.md
../tools/skills/develop/write-test-report/SKILL.md
../tools/skills/develop/review-code/SKILL.md
../tools/agents/quality-reviewer-agent.md
../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs（仅在现有状态/事务接口需接入时）
../tools/skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
../tools/skills/shared/crctl/scripts/test/test-cr.test.mjs
```

### 8.3 最小变更

1. plan/tasks/implement/review 参数表与 Pipeline 对齐；过程文档只读 operational workspace，代码事实只读 `resources[].worktreePath`；
2. 删除 Coding Pipeline 的 target_version 第二输入，全部继承 `cr.md`；
3. PLAN 只保留两张稳定表：

```markdown
| FR/关键 AC | SDD 交付项 | 主责/关联 TASK | 验收证据 | 回滚（适用时） |
|---|---|---|---|---|

| 证据 ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
```

4. 每个 in-scope FR 在交付覆盖表出现一次；TASK 使用 PLAN 预分配 ID，核验依赖、范围和接口一致性；
5. 既有事实才查当前代码，计划新增 symbol 不要求预先存在；
6. CR PLAN/TASK 不套旧 engineering-docs 通用模板；使用 writer 自检和 review-dev-plan 同款检查，不新建 schema；
7. 普通 dev-plan blocker 继续重放 plan→tasks→review；若仅 TASK 有问题，plan writer no-op；上游 SDD 问题沿用现有 upstream 路由；
8. implement-code 只读 SDD/PLAN/TASK 和目标仓规范，不把 PRD 作为并列实现依据；有变更/测试的 worktree 必须 clean committed，其他 repo 不得有意外 diff；
9. implement-code 做定向快速验证，write-test-report 执行 PLAN 命令目录的 canonical 门禁；
10. 把 `crctl` 已采集的 `sourceRevision/logSha256` 发布到 test-report 和 traceability tests；review-code 对当前 HEAD 和日志重算，漂移即 blocker；
11. review-code 固定输出 `verdict/blockers/suggestions/dimensions/repair-target`，Pipeline `passCondition` 只解析这些字段；
12. evidence-only 问题沿用 implement-code→test-report→review，implement-code 明确 no-op；
13. quality reviewer 负责 review-record 和 Skill 要求的机械 advance，但不代签人工 approval；
14. 修复 code Pipeline 的 node-3 输出文件冲突。

### 8.4 不做

- 不新增 dev-plan 三轨或 code 两轨动态 replay；
- 不新增 aggregate evidence digest 或三套漂移错误族；
- 不要求所有 active repo 都产生提交；
- 不为每种 TASK 缺口新增错误码；
- 不拆 PLAN/TASK reviewer；
- reviewer 不重跑测试。

### 8.5 验收

- writer/reviewer 使用同一 scope、事实核验和命令证据标准；
- PLAN 证据 ID 到 test-report 日志编号稳定；
- 修改源码或日志后，review-code 机械阻断；
- 纯证据回修没有代码变更；
- Pipeline 输出文件不冲突；
- canonical review、状态和下一步一致。

## 9. TASK-4：回写成为确定性投影

### 9.1 目标

`code-approved` 后不再做业务决策或质量评审，只投影冻结事实并保护事务完整性，同时让本实施 CR 和存量 CR 能按 legacy mode 归档。

### 9.2 修改文件

```text
AGENTS.md
../tools/AGENTS.md
../tools/README.md
../tools/agents/_index.yml
../tools/pipeline-templates/feature-writeback.pipeline.json
../tools/skills/writeback/merge-feature-branch/SKILL.md
../tools/skills/writeback/writeback-prd-sdd/SKILL.md
../tools/skills/writeback/writeback-tasks/SKILL.md
../tools/skills/writeback/writeback-traceability/SKILL.md
../tools/skills/writeback/scripts/writeback-prd-sdd.mjs
../tools/skills/writeback/scripts/writeback-tasks.mjs
../tools/skills/writeback/scripts/writeback-traceability.mjs
../tools/skills/cr/cr-archive/SKILL.md
../tools/skills/review/review-alignment/SKILL.md
../tools/agents/delivery-agent.md
../tools/agents/quality-reviewer-agent.md
../tools/skills/shared/crctl/scripts/crctl.mjs
../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs（仅复用或接入既有原语，不新增框架）
../tools/skills/writeback/scripts/test/writeback.test.mjs
../tools/skills/shared/crctl/scripts/test/writeback-tx.test.mjs
../tools/skills/shared/crctl/scripts/test/trace-semantic.test.mjs
../tools/skills/shared/crctl/scripts/test/trace-outbox.test.mjs
../tools/skills/shared/crctl/scripts/test/archive-tx.test.mjs
```

### 9.3 最小变更

1. feature-writeback 保持五节点；spec/version 输入改为 legacy optional，新模式从 transaction workspace 的 `cr.md` 读取；
2. merge 继续负责 release-subject drift、publication 和跨仓事务，不新增 alignment review；
3. baseline generator 从冻结 PRD/SDD 生成 candidate；相同 CR 内容完全一致才 noop，不同则冲突；复用 candidate/manifest hash，不新增持久 digest；
4. TASK generator 在 candidate 前断言本 CR 全部源 TASK done；任一未完成零写入，不发布 done 子集；delivery 文件和索引统一投影 done；
5. new mode 的 trace generator 从 PLAN 交付覆盖表、TASK、test-report 和 merge-commits 生成 `FR→SDD→TASK→repo@mergeSHA→cmd`；legacy mode 继续接受旧 milestone；
6. trace 只验证引用存在和内容被投影，不重新评价映射质量；
7. archive 只检查 baseline/tasks/trace 三阶段 complete、本 CR milestone/TASK 引用存在、无 pending trace event；
8. review-alignment 改为按需只读诊断：不在 Pipeline、不推进状态、不写 traceability；删除失效的 mtime/backlog merge-commit/fingerprint 事实源；
9. delivery-agent 删除不存在的 alignment reviewLoop 承诺；quality-reviewer-agent 不再把 alignment 当 canonical 状态评审；
10. 同步 AGENTS/README/agents index，删除“所有 writeback 都必须外部输入 spec/version”和 quality reviewer 是 feature-writeback consumer 的旧说明，并写清 legacy/new 双路径。

### 9.4 不做

- 不新增第六个 Pipeline 节点、review annotation、状态或 ledger；
- 不在 writeback 重新检查 PRD/SDD/TASK/代码是否合理；
- 不要求逐 AC 文件级代码映射；
- 不让 archive 重放 generator 或手工补文件；
- 不维护另一套幂等数据库；
- 不自动迁移 legacy CR。

### 9.5 验收

- 本实施 CR 和其他 legacy CR 仍可完成 writeback/archive；
- 新 CR 不需要重新决定 spec/version/milestone；
- new mode 外部输入无法覆盖 `cr.md`；
- 同键同内容 noop，同键不同内容冲突；
- TASK 不完整时零写入，文件和索引状态一致；
- new trace 可从冻结产物重新生成；
- archive 只在三段投影完整后成功；
- 没有 alignment 强制评审。

## 10. 提交与评审组织

一个 CR 内按 TASK 形成四组独立提交：

```text
commit group 1: register + version/spec authority + tests
commit group 2: PRD/SDD writer-reviewer pair
commit group 3: PLAN/TASK/Coding/test/review pair + tests
commit group 4: writeback/archive + legacy compatibility + tests/docs
```

规则：

- 不在四组之间合入 trunk；全部完成后一次整体审批与 merge；
- writer 与 reviewer 必须在同一组；
- 测试字段生产端与消费端必须在同一组；
- generator、manifest 校验和对应测试必须在同一组；
- reviewer 按四组分别给结论，最后只做一次跨组一致性检查；
- 任一组失败只修该组及必要调用方，不顺手重构其他组；
- 修改 `crctl` 或事务库时，只修改现有入口和共享原语的必要合同，不新建平行事务框架。

跨组最终只检查：

1. target spec/version 是否从 register 贯穿 writeback；
2. writer 与 reviewer 是否使用同一标准；
3. PLAN 证据是否被 test-report 和 review-code 同编号消费；
4. source revision/log hash 是否对应当前代码；
5. code-approved 后是否只剩投影；
6. legacy CR 是否仍可归档。

## 11. 最小验证矩阵

### 11.1 两条端到端夹具

```text
Legacy CR：
无 target-spec-id
→ 显式 legacy spec/version/milestone
→ writeback
→ archive

New CR：
register 写 target-spec-id/version
→ PRD/SDD/PLAN/TASK/Coding/test/review
→ writeback 从 cr.md/PLAN 派生
→ archive
```

### 11.2 三个关键负向场景

1. new mode 外部 spec/version 与 `cr.md` 不同：candidate 前零写入失败；
2. 测试后源码或日志变化：review-code 阻断；
3. 任一 TASK 未 done：writeback 零写入。

### 11.3 现有检查

按变更组运行相关测试，最终执行：

```bash
node skills/shared/crctl/scripts/lint-prompts.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node --test skills/shared/crctl/scripts/test/register-tx.test.mjs
node --test skills/shared/crctl/scripts/test/version-set.test.mjs
node --test skills/shared/crctl/scripts/test/test-cr.test.mjs
node --test skills/writeback/scripts/test/writeback.test.mjs
node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs
node --test skills/shared/crctl/scripts/test/trace-semantic.test.mjs
node --test skills/shared/crctl/scripts/test/trace-outbox.test.mjs
node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs
```

不新增测试 runner，不为每项规则建立独立套件。

## 12. 整体完成标准

1. 注册信息足够且没有第二事实源；
2. writer 与 reviewer 标准对称；
3. PRD、SDD、PLAN/TASK、Coding 职责不重叠；
4. 测试证据能证明对应当前代码；
5. `code-approved` 后只有确定性投影；
6. legacy CR 和 new CR 两条路径均可归档；
7. 未增加 Agent、Skill、Pipeline 节点、状态或 ledger；
8. 未新增事务框架，所有受控写入仍经既有 `crctl` 原语；
9. worktree 无本 CR 遗留未提交内容。

## 13. 不应再加回的设计

- 四个独立 CR；
- 独立 contract 文件或风险评分；
- PLAN/TASK 两个 reviewer；
- alignment 强制门禁；
- 动态多轨 replay 引擎；
- aggregate evidence digest；
- 每类校验一个错误码；
- contract-version、迁移器或 feature flag；
- 注册期 resources 快照作为后续长期 authority；
- writeback/归档重复上游质量评审；
- 为历史 CR 自动迁移全部产物；
- 新建与 `crctl` 并行的事务、状态或账本框架。

只有出现可复现缺口且现有最小机制无法覆盖时，才单独立项。
