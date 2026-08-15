---
id: CR-2026-041-prd
type: PRD
cr-ref: CR-2026-041
title: tools CR 生命周期最小优化 4/5 — 归档可信化
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-15T16:25:10+08:00
updated: 2026-08-15T16:41:30+08:00
---

# 1. 概述

当前 Tools 包的 CR 生命周期已具备状态机、门禁、CAS、人工审批、durable transaction、跨仓 merge、checkpoint、review-record、candidate-only writeback 和 archive 等深原语。但 `writeback-traceability` 回写的 baseline `traceability.yml` 只记录 `merge-commits` 与 `fr-chain`，**没有兑现 README 和规格中"里程碑含测试、评审、审批与 merge 证据"的承诺**；同时 `crctl archive` 在归档事务产生写入前只校验 tasks done、traceability 落点和 `approval.yml` 存在，**不校验证据是否真实、完整、可复算**，因此一个证据缺失、漂移或状态未通过的 CR 仍可能被归档。此外，`change-impact-analysis` 建立在不存在的 baseline schema（`requirements[].reviews.*.result=stale`）上，`feedback-writeback` 只有 prompt 契约、会直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突的 inbox，二者作为 active 能力存在虚假声明。

本 CR 落实跨 CR 生命周期规格 `docs/analysis/tools-cr-lifecycle-minimal-optimization-spec.md` 的实施切片 4，仅覆盖 FR-11、FR-12、FR-13：

1. **FR-11 最小证据摘要**：`writeback-traceability` generator 为当前 CR 新增 milestone 机械注入测试、评审、审批与 merge 的最小证据摘要；`crctl archive` 复用既有 lock，并在首次发布产生新 journal 或 authority 写入前，以同一确定性校验函数严格校验该证据。
2. **FR-12 事实源修正**：traceability generator 的 trunk 只从 `dir-graph.yaml#repositories` 解析（缺失硬失败，禁止回退 `master`），merge 只从 `change-requests/{CR-ID}/merge-commits.yml` 读取，并清除仍声称来源为 `_backlog.yml` 的注释、变量和错误文案；复用 CR-2026-038 已交付的固定 generator 映射与真实脚本 hash 校验，只补回归确认。
3. **FR-13 退役不支持能力**：删除 `change-impact-analysis` Skill 及其 active 引用，移除 `review-alignment` 对不存在 stale 模型的依赖；退役当前 `feedback-writeback` 的 active 能力声明，保留 `CONTEXT.md` 已敲定的"终态反馈事实"领域模型并按 `CUSTOM.md#CUSTOM-TODO-010` 登记后续建设条件。

本 CR 不建设通用事务管理器、通用 traceability 写入接口、schema registry、错误码注册中心、影响/stale/perspective/change-log 模型、feedback 终态写入链或新的 workflow engine。实现必须遵循 ponytail 优先级：复用既有 `crctl`、durable transaction、review-record、writeback manifest、YAML matcher、Git adapter 和现有测试 fixture；只在现有深接口无法表达且存在真实故障时增加最小代码。

# 2. 目标逻辑架构

本 CR 的全部实现必须遵守以下模块职责边界。该边界是跨 CR 规格 §4 的收敛结果，本 CR 不重复造一套，只按此约束落地。

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览、入口、恢复说明和权威链接 | 另一份可执行细节事实源 |

ponytail 优先级（本 CR 各 FR 的取舍依据，自上而下优先）：

1. 复用现有能力（`crctl`、durable transaction、review-record、writeback manifest、YAML matcher、测试 fixture）；
2. Node 标准库（`fs`、`path`、`crypto`、`child_process`）；
3. 原生 Git/文件 API（现有 controlled Git adapter）；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

## 2.1 已解决基础设施（只复用，不重做）

| 能力 | 当前状态 | 本 CR 处理 |
|---|---|---|
| durable transaction | 已有锁、journal、write-set、故障恢复和只读 `loadExistingJournal` | 复用；证据校验使用既有 archive lock，不引入新事务层 |
| archive 四账本事务 | 已有 backlog/history/index/cr.md 同批 write-set + commit + lease push + cleanup-pending + outbox | 复用事务与清理；首次发布在新 journal/authority 写入前增加当前 CR milestone 的严格证据门 |
| writeback-apply | 已有 manifest 校验、CAS、commit/push、候选路径、`baseline/tasks/traceability` 固定 generator 映射和真实脚本 hash 校验 | 全量复用；本 CR 只做 FR-12 回归确认，不改生产行为 |
| writeback-traceability generator | 已有 candidate-only、header 累积、milestone 段追加、幂等判据、SELF_CHECK | 复用；仅机械注入 `evidence` 块并修正事实源 |
| review-record / review-annotations | 已产出 `requirement.yml`/`sdd.yml`/`dev-plan.yml`/`code.yml` 四份 annotation | 复用为 review 证据的 canonical 事实源，不改其绑定格式 |
| merge-commits.yml | 已有 `schema: merge-commits/v1`，`repositories[]` 含 repo/base-sha/source-sha/merge-sha | 复用为 merge 证据唯一事实源 |
| approval.yml | 已有人工审批四段（requirement/tech-design/development-start/code） | 复用为审批证据唯一事实源 |
| test-report.md | 已有 `crctl test` 生成的机器区（status/digest/日志引用） | 复用为测试证据唯一事实源 |
| CONTEXT.md 终态反馈事实 | 已敲定 `(CR-ID, spec-id)` 领域模型 | 保留领域语义，退役当前 prompt 契约 |
| CUSTOM.md 台账 | 已有 `CUSTOM-TODO-010` 登记 | 本轮只核对/确认登记，不新增实现 |

## 2.2 本次最小改造

| 改造点 | 性质 | 说明 |
|---|---|---|
| `writeback-traceability.mjs` 注入 `evidence` 块 | 版本化脚本确定性转换 | 只加结构，不改既有段字节保留逻辑 |
| 证据确定性校验纯函数 | 新增最小纯函数 | generator 与 archive gate 复用同一函数 |
| `archiveCr` 写入前证据门 | `crctl` 深模块扩展 | 复用既有 archive lock 与 `loadExistingJournal`；仅首次发布在创建新 journal 前硬失败 |
| trunk resolver 去 `master` 回退 | 事实源修正 | 删除一行 fallback |
| backlog 旧注释/变量/错误文案清理 | 删除 | 只改文案与变量名 |
| 两个退役 Skill 删除 + 引用清理 | 删除 | 不保留 stub |

# 3. 用户故事

- **US-01 归档执行者**：希望在 `crctl archive` 首次发布产生新 journal 或 authority 写入前，就能确认当前 CR 的测试、评审、审批与 merge 证据齐全、状态通过、路径合法且 digest 可复算；证据漂移的 CR 不得进入 archived。
- **US-02 版本化脚本维护者**：希望 `writeback-traceability` 机械从 canonical 文件生成证据摘要，不依赖模型手工誊抄状态或 hash；事实源只有 `merge-commits.yml`、`approval.yml`、`review-annotations/*` 与 `test-report.md`，不再声称来自 `_backlog.yml`。
- **US-03 审计/追溯者**：希望 baseline `traceability.yml` 的每个新 milestone 含最小但可复算的发布证据摘要，既有历史 milestone 逐字节不变、不被迁移或补齐。
- **US-04 能力使用者（Agent/runtime）**：希望 Agent/Skill/Pipeline 只负责路由与业务判断，不维护状态机副本、不手写受控账本、不实现 Git 算法；退役能力不再被 README/Agent/矩阵声称为可执行。
- **US-05 Tools 维护者**：希望在 Ubuntu 和 Windows 上复用既有 durable transaction、manifest 校验和测试 fixture，只为"证据门"增加一个确定性校验函数，不引入第二套事务框架、schema registry 或通用 traceability 接口。

# 4. 功能需求

## FR-01 最小证据摘要结构与机械生成（规格 FR-11）

1. `writeback-traceability` generator 在追加当前 CR 的新 milestone 段时，必须机械注入以下 `evidence` 块（key 名固定，结构最小）：

   ```yaml
   evidence:
     test: { status: pass, path: change-requests/CR-.../test-report.md, sha256: ... }
     reviews:
       requirement: { verdict: pass, path: ..., sha256: ... }
       tech-design: { verdict: pass, path: ..., sha256: ... }
       dev-plan: { verdict: pass, path: ..., sha256: ... }
       code: { verdict: pass, path: ..., sha256: ... }
     approval: { status: approved, path: change-requests/CR-.../approval.yml, sha256: ... }
     merge: { status: merged, path: change-requests/CR-.../merge-commits.yml, sha256: ... }
   ```

2. 证据摘要只记录**状态结论、workspace 相对路径、LF canonical SHA-256 digest**，不复制完整测试报告、annotation 正文、approval grant 明细或 merge commit 明细。
3. generator 必须从下列 canonical 文件读取证据，不允许模型手工誊抄状态或 hash：

   | evidence key | canonical 事实源 | 摘要字段 |
   |---|---|---|
   | `test` | `change-requests/{CR-ID}/test-report.md`（机器区） | `status`、`path`、`sha256` |
   | `reviews.requirement` | `change-requests/{CR-ID}/review-annotations/requirement.yml` | `verdict`、`path`、`sha256` |
   | `reviews.tech-design` | `change-requests/{CR-ID}/review-annotations/sdd.yml` | `verdict`、`path`、`sha256` |
   | `reviews.dev-plan` | `change-requests/{CR-ID}/review-annotations/dev-plan.yml` | `verdict`、`path`、`sha256` |
   | `reviews.code` | `change-requests/{CR-ID}/review-annotations/code.yml` | `verdict`、`path`、`sha256` |
   | `approval` | `change-requests/{CR-ID}/approval.yml`（整份） | `status`、`path`、`sha256` |
   | `merge` | `change-requests/{CR-ID}/merge-commits.yml`（整份） | `status`、`path`、`sha256` |

4. review 证据按四份独立 annotation 分项记录，每项 `verdict: pass`；审批证据只聚合整份 `approval.yml` 为 `status: approved`；merge 证据只聚合整份 `merge-commits.yml` 为 `status: merged`。不复制分阶段 grant 摘要或单仓 commit 明细。
5. digest 输入必须先 CRLF→LF 规范化，并使用既有 `sha256` helper 对整份 canonical 文件计算；同一文件在 Windows/Ubuntu 上必须得到相同 digest。
6. 该 `evidence` 块是 milestone 级结构化证据，与 `fr-chain[].evidence`（每条 FR 的人工注释字符串）互不取代；后者保持既有 opaque 语义不变。

## FR-02 证据与 merge 事实源修正（规格 FR-11 / FR-12）

1. trunk 只从 workspace `dir-graph.yaml#repositories` 的 repositories resolver 获取；目标 repository 缺失时硬失败，禁止回退 `master`、禁止从 `_backlog.yml` 或 merge commit message 猜测 trunk。
2. merge 证据只从 `change-requests/{CR-ID}/merge-commits.yml` 读取；`schema` 必须为 `merge-commits/v1`，`repositories[]` 的 `repo`、`merge-sha` 必须齐全。缺失、重复或字段不齐全硬失败，不猜测、不取 trunk 最新提交。
3. generator 的注释、变量名和错误文案不得继续声称 merge 来源为 `_backlog.yml`；当前代码中"从 `_backlog.yml` 定向提取"的注释、`fromBacklog` 变量名以及"milestone-file 内 merge-commits 与 _backlog.yml 提取结果不一致"的错误文案必须删除或改写为 `merge-commits.yml`。
4. 若 milestone-file 自带 `merge-commits`，与 `merge-commits.yml` 提取结果的一致性校验保持不变（防人工誊抄分叉），但文案与变量名同样不得再引用 `_backlog.yml`。
5. 本需求只修正事实源与文案，不改变 `merge-commits.yml` 的 schema，不新增 YAML parser，不新建 merge 提取路径。

## FR-03 generator 身份既有约束回归（规格 FR-12）

1. CR-2026-038 已交付的 `WRITEBACK_GENERATORS` 固定映射、固定脚本执行和真实脚本 hash 校验是本需求的既有实现；stage 固定为 `baseline`、`tasks`、`traceability`，不得与 generator id 混用。
2. 本 CR 不修改该生产路径，只增加或复用回归测试确认：`writeback-apply` 仍对当前 Tools Root 的固定脚本计算真实 hash，不信任 manifest 自报值；hash 不匹配时拒绝 candidate。
3. 调用方仍不得传入 generator 路径；不得新增 generator plugin registry、候选管理器或新的 generator。
4. 若回归测试发现既有实现缺陷，只做直接修复；不得重写 CR-2026-038 已有映射、执行器或校验流程。

## FR-04 archive 前严格证据门（规格 FR-11）

1. `crctl archive` 继续先获取既有 archive lock；lock 只用于串行化并在失败时释放，不是新的 authority 或事务协议。
2. lock 内先复用只读 `loadExistingJournal` 分流：已 commit/push 或进入 cleanup/complete 的 journal 继续既有恢复，不重复校验证据；无 journal，或已有 journal 但尚无 authority 副作用时，必须在创建/修改 journal及任何 write-set/commit/push/outbox/audit 前校验当前 CR milestone 的 `evidence` 块。
3. archive gate 与 generator 复用**同一确定性证据校验函数**，只检查当前 CR milestone，不建立通用 schema registry 或脚本型 gate。证据校验必须同时覆盖：
   - `test.status == pass`、路径合法、digest 可复算；
   - 四份 review annotation 均存在且 `verdict == pass`、路径合法、digest 可复算；
   - `approval.status == approved`、路径合法、digest 可复算，且从该文件验证 `requirement`、`tech-design`、`development-start`、`code` 四个必需 grant 均存在；
   - `merge.status == merged`、路径合法、digest 可复算，且从该文件验证当前 CR 的合并事实存在。
4. 当前 CR milestone 重复、evidence key 重复、证据路径指向其他 CR，以及证据缺失、状态不通过、路径不合法或 digest 不匹配，均硬失败；失败释放 lock，返回结构化错误并指明缺项，不创建或修改 journal，不产生 authority 写入和审计，可补齐后以同一命令重试。
5. 既有 archive 前置校验（tasks 全 done、`specs/{spec}/traceability.yml` 存在、`approval.yml` 存在）保持不动；本证据门是新增的**追加门**，不替换、不放宽既有门禁。
6. rejected/withdrawn 路径没有 writing-back milestone，不执行该证据门；archive 的 writing-back → archived、cleanup-pending、幂等重放与 outbox 补发语义不变。

## FR-05 历史 milestone opaque 与新 milestone 无 status（规格 FR-11）

1. 既有 milestone 段继续作为 opaque 历史段**逐字节保留**；本 CR 不迁移、不补齐、不重写历史 milestone。
2. 历史 milestone 缺少 `evidence` 字段不构成读取错误；归档门与 generator 只校验当前 CR 的新 milestone。
3. 新 milestone 段**不写 `status`**；不得复制瞬时 `writing-back`、提前写 `archived`、或引入状态机之外的 `released`。CR 状态继续只由 `cr.md` 与 `_history.yml` 表达。
4. generator 的既有幂等判据（specs 侧已含 `- cr: {CR-ID}` 段则 noop）与既有段字节保留自检保持不变。
5. 不建立通用 `traceability-record --kind ...` 接口，不建立 traceability 写入 handler，不新增通用 milestone schema registry。

## FR-06 change-impact-analysis 退役（规格 FR-13）

1. 删除 `skills/review/change-impact-analysis/SKILL.md`，并同步删除其全部 active 引用：
   - `skills/_index.yml` 中 `change-impact-analysis` 条目；
   - `agent-skill-matrix.yml` 中 `quality-reviewer-agent` 的 owns 列表项；
   - `AGENT-SKILL-MATRIX.md`、`agents/quality-reviewer-agent.md`、`agents/_index.yml` 中的声明；
   - `dir-graph.yaml` 中 `skill_context.change-impact-analysis` hint；
   - `README.md`、`docs/QODER-使用指南.md`、`openwiki/architecture/agent-skill-matrix.md` 中的能力声明。
2. 删除 `review-alignment` 对不存在 stale 模型的依赖：移除 AL-07（`traceability.requirements[].reviews.*.result != stale`）及任何引用 `change-impact-analysis` 置位的描述；`review-alignment` 其余 AL-01～AL-06 保留，只读职责不变。
3. 不补建 impact/stale/perspective/change-log 模型，不保留 retired stub、占位 Skill 或兼容分支。
4. 只删除 active 契约；历史报告或架构快照中的事实性提及可以保留，不得为字符串清零改写历史记录。
5. Git 历史承担旧 Skill 的审计与恢复；未来需要 impact 分析时按真实需求注册独立 CR。

## FR-07 feedback-writeback 退役与 CUSTOM-TODO-010 登记（规格 FR-13）

1. 删除 `skills/cr/feedback-writeback/SKILL.md`，并同步删除其全部 active 引用：
   - `skills/_index.yml` 中 `feedback-writeback` 条目；
   - `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md` 中的声明；
   - `README.md`、`docs/QODER-使用指南.md`、`openwiki/architecture/agent-skill-matrix.md` 中的能力声明；
   - `skills/cr/inbox-emit/SKILL.md` 的 event allowlist 中 `feedback-writeback-done` 事件名与触发方描述。
2. 保留 `CONTEXT.md` 中"终态反馈事实"的 canonical 领域语义（`(CR-ID, spec-id)` 唯一标识、`_history.yml` 唯一终态、baseline `feedback[]` 正文与 history 输入摘要）；退役的是当前直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突 inbox 的 prompt 契约。
3. feedback-writeback 的后续建设条件以 Tools `CUSTOM.md#CUSTOM-TODO-010` 为准；本轮不新增占位命令、空字段、兼容分支或新事务接口，不创建占位 Skill 满足 Agent 能力声明。
4. `reviewer-panel` 当前存在且有引用，本 CR 不删除、不退役。
5. 不创建 retired stub；删除后不得残留旧事件名 `feedback-writeback-done` 或对已删除 Skill 的 active 引用；`CUSTOM-TODO-010` 与历史事实性记录不属于 active 引用，必须保留。

## FR-08 职责边界与 ponytail 约束（规格 §4 / §13）

1. 本 CR 的全部改动只落在三类对象上，且不得越界：
   - **版本化脚本**：只增加 `evidence` 块的确定性转换与事实源修正，不做状态推进、审批或 Git 发布。
   - **`crctl`**：只增加 archive 写入前证据门；generator 身份路径保持 CR-2026-038 既有实现，只做回归确认；不做业务设计判断、不生成 LLM 评审结论。
   - **退役清理**：只删除 `change-impact-analysis`、`feedback-writeback` 及 active 引用，不新建替代模型。
2. 证据校验优先扩展现有 helper 模块，不新增独立模块；不建 generator registry、traceability handler、evidence writer factory、archive gate plugin 或通用 YAML patch。
3. 复用既有 durable transaction、review-record、writeback manifest、YAML matcher、Git adapter 与测试 fixture；不为证据门引入新的锁、journal、write-set、run-id 或恢复协议。
4. 所有跨行解析、digest 输入和文件读取先做 CRLF→LF 规范化；解析失败硬失败，禁止静默降级（对齐工程纪律第 1 条）。
5. Agent、Pipeline、Skill、README 在本 CR 只做引用收敛（删除退役能力声明），不复制证据算法、状态机副本或受控文件写入逻辑；其更大范围文本收敛由实施 CR 5（CR-2026-042）承担，本 CR 不越界。

# 5. 非功能需求

- **可信性**：baseline 每个新 milestone 的证据摘要必须可复算；archive 只接受证据齐全且 digest 匹配的 CR。
- **原子性**：archive 证据门在既有 lock 内、新建或修改 journal/write-set 之前执行；证据校验失败释放 lock，不创建或修改 journal，零 authority 写入、零审计事件。
- **可恢复性**：证据缺失/漂移返回结构化错误并指明缺项，补齐后以同一 `crctl archive` 命令重试；不允许手改 `_backlog.yml`/`cr.md`/`approval.yml`/`traceability.yml`/journal 绕过。
- **可审计性**：证据只记录状态结论、相对路径与 digest，不复制完整报告/grant/commit 明细；历史 milestone 逐字节保留。
- **跨平台性**：digest 与解析在 Windows/Ubuntu 上对 CRLF/LF 一致；canonical 输出使用 LF。
- **可测试性**：至少覆盖证据生成、四类证据校验、digest 漂移、路径非法、状态不通过、历史段字节不变、master 回退拒绝、generator hash 拒绝和退役引用零残留。
- **极简性**：不新增 schema registry、错误码中心、通用 traceability 接口、事务框架、数据库或强授权字符串模型；不新增 npm 依赖。

# 6. 验收标准

- **AC-01（FR-01）**：`writeback-traceability` 对新 milestone 注入 `evidence` 块，`test`/`reviews`（四份）/`approval`/`merge` 七项齐全；每项含状态结论、相对路径与 LF canonical digest；不存在完整报告/grant/commit 明细复制。
- **AC-02（FR-01/02）**：证据全部从 canonical 文件机械读取；修改任一 canonical 文件后其 digest 必然不匹配；CRLF 与 LF 版本在 Windows/Ubuntu 得到相同 digest。
- **AC-03（FR-02）**：从 `dir-graph.yaml#repositories` 删除 `tools` 条目后，generator 对含 `tools` 的 CR 硬失败，不回退 `master`；`merge-commits.yml` 缺失/重复/字段不全硬失败。
- **AC-04（FR-02）**：generator 源码、注释与错误文案中不再出现"来源为 `_backlog.yml`"的 merge 声明；`fromBacklog` 变量名与旧错误文案已清除。
- **AC-05（FR-03）**：既有 `baseline/tasks/traceability` 固定映射与真实脚本 hash 回归测试通过；manifest 自报 hash 不匹配时 `writeback-apply` 拒绝 candidate；生产代码无变化，除非测试复现既有缺陷。
- **AC-06（FR-04）**：证据齐全且可复算时 `crctl archive` 正常归档；当前 CR milestone/evidence 重复、路径指向其他 CR、缺任一证据、`verdict`/`status` 非通过、路径非法或 digest 漂移时，在既有 lock 内、新建或修改 journal 前硬失败，不创建/修改 journal，不产生 authority 写入和审计。
- **AC-07（FR-04）**：archive 证据门复用 generator 的确定性校验函数（同一函数、同一判据）；approval 门从 `approval.yml` 验证四个必需 grant，merge 门从 `merge-commits.yml` 验证当前 CR 合并事实；rejected/withdrawn 以及已 commit/push 或进入 cleanup/complete 的恢复不执行 writing-back 证据门，pre-authority journal 仍必须校验。
- **AC-08（FR-05）**：既有历史 milestone 段逐字节不变（含 CR-2026-038/039/040 已写入的 `status: writing-back` 段）；历史段缺 `evidence` 不报错；新 milestone 不含 `status` 字段，不含状态机外状态。
- **AC-09（FR-06）**：`skills/review/change-impact-analysis/SKILL.md` 已删除；`skills/_index.yml`、矩阵、Agent、`dir-graph.yaml` hint、README 与当前使用指南中零 active 引用；`review-alignment` 中 AL-07 与 stale 依赖已移除；历史报告/快照无需字符串清零。
- **AC-10（FR-07）**：`skills/cr/feedback-writeback/SKILL.md` 已删除；索引、矩阵、Agent、README、当前使用指南中零 active 引用；`inbox-emit` allowlist 中 `feedback-writeback-done` 已移除；`CONTEXT.md` 终态反馈事实、`CUSTOM.md#CUSTOM-TODO-010` 与历史记录保留，且未新增占位实现。
- **AC-11（FR-08）**：新增代码只落于版本化脚本（确定性转换）与 `crctl`（证据门）；generator 身份路径只做既有回归确认；不存在新独立模块、registry、handler、factory 或第二事务框架。
- **AC-12（工程质量）**：现有 crctl、writeback、merge、checkpoint、archive、review-record 回归测试保持通过；新增证据生成、证据门、digest、master 回退、历史段字节保留与退役引用测试，以及既有 generator hash 回归测试，在 Ubuntu 与 Windows 均通过；不引入新的生产依赖。

# 7. 成功指标

- baseline `traceability.yml` 的每个新 milestone 均含最小且可复算的 test/reviews/approval/merge 证据摘要；历史 milestone 字节不变。
- 证据缺失、漂移或状态未通过的 CR 无法通过 `crctl archive`；归档证据门与 generator 共用同一确定性校验函数。
- traceability generator 不再存在 `master` 回退、`_backlog.yml` 来源声明或 generator 自报 hash 信任。
- `change-impact-analysis` 与 `feedback-writeback` 在 Skills 索引、矩阵、Agent、README、dir-graph hint 与 inbox allowlist 中零 active 引用；`CONTEXT.md` 终态反馈事实领域模型与 `CUSTOM-TODO-010` 保留。
- CR-2026-041 的实现不增加第二套事务框架、状态机、账本模型、schema registry 或通用 traceability 平台。

# 8. 依赖与风险

- **依赖**：Tools 当前 `crctl` 的 durable transaction、archive 四账本事务、writeback-apply manifest/CAS、review-record、`merge-commits.yml`、`approval.yml`、`test-report.md` 机器区与既有测试 fixture；`writeback-traceability.mjs`、`writeback-prd-sdd.mjs`、`writeback-tasks.mjs` 的既有契约；`CONTEXT.md` 终态反馈事实与 `CUSTOM.md#CUSTOM-TODO-010`。
- **风险 R-01：证据门破坏既有归档路径**。证据门在既有 archive lock 内、任何新 journal/authority 写入前检查当前 CR milestone；仅已 commit/push 或进入 cleanup/complete 的恢复，以及无 writeback milestone 的 rejected/withdrawn 路径跳过，pre-authority journal 仍校验且失败时保持不变。
- **风险 R-02：digest 跨平台漂移**。canonical 文件可能含 CRLF；digest 输入必须先规范化 LF，并在 Windows/Ubuntu 双跑断言一致。
- **风险 R-03：退役清理不彻底或误删历史**。静态扫描必须证明索引、矩阵、Agent、README、dir-graph hint、inbox allowlist 与当前使用指南中零 active 引用，同时允许 `CUSTOM-TODO-010` 与历史报告/快照的事实性提及；禁止保留 retired stub 或旧事件名。
- **风险 R-04：新 milestone 无 status 后归档门定位**。证据门必须按 `- cr: {CR-ID}` 定位 milestone，而非依赖 `status` 字段；历史 `status: writing-back` 段仍按 opaque 保留。
- **风险 R-05：误改既有 generator 路径**。CR-2026-038 已实现固定映射与真实脚本 hash 校验；本 CR 仅回归确认，除非复现缺陷不得改写该路径。
- **风险 R-06：feedback 领域模型误删**。退役的是 prompt 契约，不是 `CONTEXT.md` 领域语义；删除 Skill 时不得连带删除 `CUSTOM-TODO-010` 或领域定义。

# 9. 范围排除

- 不建设通用事务管理器、通用 traceability 写入接口、schema registry、错误码注册中心、测试运行平台或 workflow engine。
- 不建立 impact/stale/perspective/change-log 模型；不实现 feedback 终态写入链、占位命令或兼容分支。
- 不建立通用 `traceability-record --kind ...` 接口、generator plugin registry 或 archive gate plugin。
- 不重写历史 traceability milestone，不为历史数据制造伪 run-id、伪 digest 或伪证据。
- 不复制完整测试报告、review annotation、approval grant 或 merge commit 明细进 baseline。
- 不改变 `reviewer-panel`、`review-alignment` 的既有职责（除移除 stale 依赖外），不删除其他 active Skill。
- 不修改 CR-2026-041 之外的生命周期切片：writeback 原子化、证据规范化、结构化测试闭环、职责边界清理与 Phase E 端到端验收均不在本 CR 实施范围。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘在本 CR 的 requirement worktree。

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-15 | v0.1.0 | Ray | 初始草稿：最小证据摘要、事实源修正、generator 身份、archive 证据门、历史段 opaque、双 Skill 退役与职责边界 |
| 2026-08-15 | v0.1.1 | Ray | 按需求评审回修：generator 固定映射/hash 改为复用既有能力；archive 证据门收敛到既有 lock 内、新 journal 前；补重复/跨 CR 路径与 active 引用边界 |
