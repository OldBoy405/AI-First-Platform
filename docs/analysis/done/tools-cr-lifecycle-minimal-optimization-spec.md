# Tools CR 生命周期最小优化规格

> 文档性质：跨多条实施 CR 的架构治理与需求基线，不是单条 CR 的实施合同；可作为各实施 CR 的 PRD、SDD 和 TASK 拆分依据。  
> 核对基线：`tools@origin/custom/main`，commit `7b73204464e136b83d4377ba1447a11c2291e6c6`。  
> 验证基线：远端快照 `crctl` 测试 294/294 通过。  
> 输入文档：`CR 流程待改进.md`、`tools-archive-checkpoint-test-traceability-optimization-plan.md`、`tools-text-contract-audit.md`。  
> 核心约束：解决真实生命周期漏洞，但不增加第二套事务框架、状态机、账本模型或通用工作流平台。

## 1. 执行摘要

当前 Tools 包已经具备 CR 生命周期所需的大部分基础设施：状态机、门禁、CAS、人工审批、durable transaction、跨仓 merge、checkpoint、review-record、candidate-only writeback 和 archive。当前问题不是基础能力缺失，而是部分深原语之间的组合边界没有闭合，以及 Agent、Pipeline、Skill、README 中仍保留大量重复或过时的文本契约。

本规格只处理以下三类事项：

1. 修复会导致状态丢失、合法重试被阻断、确定性合并冲突或审批证据漂移的真实漏洞。
2. 复用现有深原语，补齐少量缺失的证据摘要和原子写入。
3. 删除重复算法、虚假能力声明和第二事实源，使各层回到既定职责。

本规格明确不建设通用事务管理器、通用 traceability 写入接口、测试运行平台、错误码注册中心、schema registry、Agent 自报授权或新的 workflow engine。

## 2. 事实源与核对范围

### 2.1 权威事实源

| 事项 | 权威来源 |
|---|---|
| 工作区、仓库和 Tools Root | 工作区 `dir-graph.yaml` |
| CR 状态、转移和门禁 | Tools `dir-graph.yaml#change-request-track.state_machine`、`skills/shared/crctl/gates.json` |
| Agent 与 Skill 权限 | `agent-skill-matrix.yml` |
| Pipeline 节点顺序和 reviewLoop | `pipeline-templates/*.pipeline.json` |
| Skill 业务输入、输出和失败语义 | `skills/**/SKILL.md` |
| 状态、账本、CAS、Git、审计和恢复 | `skills/shared/crctl/` |
| PRD/SDD/TASK/traceability 确定性转换 | `skills/**/scripts/` |
| 人读流程总览 | `README.md` |

README、Agent 文档、分析文档和历史复盘不得成为状态转移、门禁或账本结构的第二事实源。

### 2.2 当前基线口径

- 状态机为 15 个具名状态，加注册前 `(new)`。
- 转移为 28 条声明，wildcard 展开后 50 条。
- 当前远端基线已包含 CR-2026-031 durable transaction、CR-2026-032 archive、CR-2026-033 checkpoint。
- 本规格以 `origin/custom/main` 为核对对象，不以落后于远端的本地 checkout 推断能力缺失。

## 3. 目标与非目标

### 3.1 目标

- CR 从注册到归档的状态、远端分支和证据投影保持一致。
- 每个受控写入只有一个权威入口。
- 失败后能够通过同一命令重试或按结构化错误恢复，不依赖手改账本。
- Pipeline 只描述顺序、输入、reviewLoop 和失败中止。
- Skill 只描述业务判断、编排步骤和失败语义。
- 版本化脚本只执行确定性转换。
- README 只提供人读总览、入口和权威链接。
- 所有新增实现都优先复用现有 `crctl`、durable transaction、YAML matcher、Git adapter 和测试 fixture。

### 3.2 非目标

- 不建立 CR 级 `depends-on` 图和跨 CR 调度器。
- 不增加 target repository/source scope 新模型。
- 不建立通用 YAML patch、payload validator、错误码 registry 或 schema registry。
- 不建立 `test run/record` 公共协议、日志平台或通用 binary write-set。
- 不建立通用 `traceability-record --kind ...` 接口。
- 不实现 impact/stale/perspective/change-log 模型。
- 不用 `--caller`、Agent 名称或模型自报字符串模拟强身份认证。
- 不允许 force push、force rollback、merge conflict bypass 或自动补偿 revert。
- 不重写历史 traceability milestone，不为历史数据制造伪 run-id 或伪 digest。

### 3.3 交付切片约束

- 生产改造固定拆为 5 条实施 CR：Writeback 原子化、生命周期证据规范化、结构化测试闭环、归档可信化、职责边界清理；不得以“统一优化”为由合并成一条总包 CR。
- 每条实施 CR 只承诺第 10 节列明的 FR、回归测试和迁移边界，其余切片必须写入非目标。
- Phase E 是跨上述 5 条实施 CR 的最终验收，不单独承载生产改造，也不替代各 CR 自身的评审、审批、回写和归档。
- 仅当实施中出现不能独立评审或回滚的新事实时才允许进一步拆分；不得跨切片扩大单条 CR 的范围。

## 4. 目标逻辑架构

### 4.1 模块职责

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | Skill 完整算法、账本拼接、Git 恢复算法 |
| Skill | 业务判断、步骤编排、输入输出、失败语义 | 原子账本实现、重复实现 `crctl`、手写 commit/push |
| `crctl` | 状态、门禁、CAS、受控账本、审计、原子提交和恢复 | PRD/SDD 内容判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批、Git 发布 |
| README | 流程总览、入口、恢复说明和权威链接 | 节点 prompt、算法步骤、状态机副本 |

### 4.2 深模块原则

`crctl` 是 CR 状态和受控写入的深模块。调用方只需要知道命令接口、前置条件、结果和错误语义，不需要知道 journal、write-set、CAS、Git lease 或恢复实现。

以下设计不应新增独立模块：

- 只有一个实现的 generator registry。
- 只转发 `kind` 参数的 traceability handler。
- 复制现有 `crctl` 参数的 Pipeline helper。
- 只包装一次文件写入的 factory、class 或 adapter。

删除某个模块后，如果复杂度不会重新散落到多个调用方，该模块就是浅模块，应删除而不是继续扩展。

## 5. 已解决基础设施

以下能力已经存在，本次只能复用或做局部修复。

| 能力 | 当前状态 | 本次处理 |
|---|---|---|
| register 与三 Owner 登记 | 已有事务、双投影、commit 和 outbox | 复用 |
| Owner 正式移交 | 已有 CAS、历史、双投影和隔离 commit | 复用；不新增授权字符串 |
| advance/approve/reject | 已有门禁、TTY/签名 grant、审计和状态提交 | 复用 |
| workspace ensure/resume | 已有幂等恢复和权威 worktree 解析 | 复用 |
| merge | 已有多仓 prepare/publish/finalize/recover | 仅修 `_backlog.yml` 语义合并 |
| durable transaction | 已有锁、journal、write-set、故障恢复 | 不再建设事务层 |
| archive | 已有四账本事务、cleanup-pending 和 outbox | 复用事务与清理；实施 CR 4 仅增加当前 CR milestone 的严格证据门 |
| checkpoint | 已有单入口、latest-checkpoint、多仓恢复和测试 | 复用；不重做协议 |
| review-record | 已有 annotation、review-loop、CR traceability 原子写 | 增加 dev-plan subject digest |
| release-subjects | 已有审批和 writeback 漂移保护 | 保留严格门禁 |
| writeback candidate | 已有 generator、manifest、CAS、commit/push | 修 preflight 顺序和 baseline 状态发布 |
| CI | 已有 Ubuntu/Windows 全量测试 | 合并重复 workflow，补触发路径 |

## 6. 问题清单与决策

### 6.1 P0：生命周期正确性

| ID | 问题 | 决策 | 最小实现 |
|---|---|---|---|
| P0-01 | baseline `writeback-apply` 后独立执行 `advance --embedded`，下一阶段从 origin 重置时可能丢失状态 | 采纳 | baseline writeback 固定在同一 write-set/commit/push 中发布 `merging -> writing-back`；不暴露任意复合状态接口 |
| P0-02 | manifest 在 journal 创建后才完整校验，修正输入会撞 `TX_INPUT_CONFLICT` | 采纳 | 所有只读 preflight 在锁和 journal 前完成，非法输入零副作用 |
| P0-03 | checkpoint 修改全局 `_backlog.yml`，trunk 新注册 CR 后 merge 产生无业务意义的文本冲突 | 采纳，裁剪原修法 | 保留 trunk 全部其他条目，只以 source 的目标 CR 条目覆盖 trunk 对应条目 |
| P0-04 | code review PASS 后未 push，人工审批重核远端 release subject 时可能漂移 | 采纳 | review PASS 后插入现有 `push-progress`，成功后才进入 human approval |

### 6.2 P1：证据和状态一致性

| ID | 问题 | 决策 | 最小实现 |
|---|---|---|---|
| P1-01 | dev-plan PASS 未绑定 plan 和 TASK 正文，内容修改后可能沿用旧 PASS | 采纳 | 记录 `plan.md + 排序后的 TASK-*.md` composite digest，在消费点重算 |
| P1-02 | 注册写 `updated`，状态推进只更新 `updated-at` | 采纳 | 兼容读取旧字段，新写统一为 `updated` |
| P1-03 | `crctl test` 覆盖整个报告，marker 后人工分析丢失 | 采纳 | 仅替换机器区，保留 marker 后原文 |
| P1-04 | Pipeline/Skill 使用 canonical annotation 中不存在的 `repair-instructions`、`fixed-blockers` | 采纳 | 统一为 verdict、blockers、suggestions、dimensions、repair-target |
| P1-05 | writeback candidate 路径不统一，残留物难以识别 | 采纳 | 由 `crctl` 固定使用 `.crctl/candidates/{CR-ID}/{stage}`，不向 Skill/Pipeline 暴露路径，不新增 candidate manager |
| P1-06 | 测试命令使用 `shell:true` 且报告、trace、loop 分散写入 | 采纳，裁剪路线图 | 保留一个结构化 test 深接口，使用 `spawnSync(file,args,{shell:false})` 并原子记录 |
| P1-07 | baseline traceability 未兑现测试、评审、审批证据承诺 | 采纳，最小摘要 | milestone 只记录 canonical 状态、路径和摘要，不复制完整过程账本 |

### 6.3 P2：文本契约和层级漂移

| ID | 问题 | 决策 | 最小实现 |
|---|---|---|---|
| P2-01 | CR write Skill 同时引用旧 engineering-docs、`_config.yml`、MCP 或 validate-doc 契约 | 采纳 | 从 CR 路径删除失效引用；仍被通用流程使用的模块不删除 |
| P2-02 | code Pipeline 包含 reviewer 选择暂停和 suggestion 升格策略 | 采纳 | reviewer 选择归 Agent/runtime；Skill 只产出业务结论 |
| P2-03 | Pipeline 复制 merge、checkpoint、writeback 的内部算法 | 采纳 | prompt 收缩为输入、一次深原语调用、结果分类和后续路由 |
| P2-04 | Agent 保存状态链、从 backlog 判断 status 或声明直接写产物 | 采纳 | Agent 只保留路由、职责和 Skill/Pipeline 选择 |
| P2-05 | README 复制可执行细节并与实现漂移 | 采纳 | README 只保留总览、入口、恢复和权威链接 |
| P2-06 | `change-impact-analysis` 建立在不存在的 baseline schema 上 | 裁剪并退役 | 删除 active capability 和引用，不补建 impact/stale 模型 |
| P2-07 | feedback-writeback 没有合法终态写入链和真实消费者 | 退役当前能力并延期建设 | 保留 `CONTEXT.md` 已敲定的“终态反馈事实”领域模型；撤销 active 能力声明，等真实调用方和消费者出现后按 `CUSTOM-TODO-010` 单独实施 |
| P2-08 | 文档声称 reviewer panel 不存在 | 不采纳 | 当前 `skills/reviewer-panel.yaml` 实际存在并有引用；是否退役需独立证据 |
| P2-09 | 重复 CI 和静态 checker 扩张 | 采纳，裁剪实现 | 合并 workflow；只扩展现有 lint 和行为测试，不建通用 Pipeline 解释器 |

## 7. 目标生命周期

```text
register
  -> requirement-authoring
  -> PRD / review-requirement loop / approve-requirement
  -> checkpoint
  -> architecture-design
  -> SDD / review-tech-design loop / approve-tech-design
  -> checkpoint
  -> write-dev-plan / write-dev-tasks
  -> review-dev-plan loop（绑定 plan + TASK digest）
  -> approve-dev-start
  -> checkpoint
  -> implement-code
  -> structured test record（crctl 机器区）
  -> test analysis（write-test-report 分析区）
  -> checkpoint
  -> review-code loop
  -> checkpoint（PASS 后、人工审批前）
  -> approve-code
  -> checkpoint
  -> crctl merge
  -> baseline writeback + writing-back 状态同批发布
  -> tasks writeback
  -> traceability writeback
  -> crctl archive
```

生命周期规则：

1. Pipeline 节点不得直接改状态、账本或执行 Git 算法。
2. Skill 可以生成业务文档或临时 payload，但不得手写受控账本。
3. 评审 PASS 只表示业务结论成立，不表示证据已发布；人工审批前必须 checkpoint。
4. 所有失败必须在当前节点中止，不得带着不完整证据进入 human approval。
5. 所有状态判断以 CR worktree `cr.md` 或 `crctl status/next` 为准，不读主工作区注册快照推断进度。

## 8. 功能需求

### FR-01 Baseline 回写与状态发布

**问题来源**：P0-01、原流程记录 #122、TCA-019 的组合边界。

**需求**：

- `writeback-apply --stage baseline` 在确认 candidate、目标矩阵、origin 和门禁后，将 baseline 文件与 `cr.md` 的 `merging -> writing-back` 变更放入同一 write-set。
- 状态门禁继续读取权威 `gates.json`；仅 `fileExists` 检查可把已通过 schema、containment、hash 和目标矩阵校验的 manifest 精确目标路径视为 planned existing，其他 gate 类型仍只读取当前 authority。
- planned write-set 覆盖是 `runGateChecks` 的只读路径集合参数，不提供虚拟文件内容、不物化 candidate，也不新增 writeback 专用 gate。
- 状态变更、baseline 文件、commit 和 push 必须形成一个可恢复事务。
- 仅在 origin 已确认包含该 write-set 的真实 commit 后，发送一次 `merging -> writing-back` status outbox；事件携带真实 commit SHA，不产生 `pending:` SHA，也不依赖后续 checkpoint 补全。
- outbox 发送成功后在既有 journal 记录 `outboxEmitted`；发送失败只返回 `EMIT_FAILED` warning，不回滚已确认的 Git 权威事实，重放时只补发确定性去重的事件、不新增 commit 或 push。
- `kind: advance` success audit 与 status outbox 使用同一 origin-confirmed 边界；既有 writeback journal 增加 `auditEmitted` 标记，审计写入失败不回滚 Git，重放时只补写审计，不重复 commit、push 或 status outbox。
- Pipeline 不再执行独立 `advance --embedded`。
- 该行为仅适用于 baseline stage，不扩展为任意状态转换接口。
- 重放已完成且 `outboxEmitted=true` 的事务必须返回幂等成功，不重复 commit、push 或 outbox。

**复用路径**：现有 `performAdvance` 的状态候选逻辑、`runGateChecks`、durable write-set、writeback commit/push 流程，以及 archive 事务已有的 origin-confirmed 后发送、journal 标记和失败补发模式。

**验收**：baseline 完成后立即执行 tasks writeback，不得把状态重置回 `merging`；在 write-set、commit、push 各故障点重试均可恢复。

### FR-02 Writeback 只读预检

**问题来源**：P0-02。

**需求**：

- 生产入口不接受调用方传入 `--candidate`、generator 路径或 candidate 输出目录；`crctl` 根据固定 stage 从当前 Tools Root 选择版本化脚本并生成内部 candidate。
- 在获取 writeback lock 和创建 journal 前完成业务参数、固定 generator 执行、candidate 文件、JSON、manifest schema、stage、CR、spec-id、路径 containment、文件 hash、generator hash 和目标矩阵校验。
- baseline 状态门禁在 lock/journal 前执行；传给 `fileExists` 的 planned 路径只能来自上述已完整验证的 manifest，门禁失败仍为零 authority 写入。
- 预检只使用一次读入并规范化后的 manifest 文本，后续事务使用同一文本和 digest。
- 任何预检错误不得创建 journal、lock 残留、目标文件或审计事件。
- candidate 是可丢弃的内部派生物，不是 authority；修正业务源文件或固定 generator 后使用同一业务命令重试，不得出现前次非法输入导致的 `TX_INPUT_CONFLICT`。

**复用路径**：现有 `validateWritebackManifest`、hash helper 和 allowlist，不增加 validator framework。

### FR-03 `_backlog.yml` 目标条目语义合并

**问题来源**：P0-03、checkpoint 非末条 CR 实测问题。

**需求**：

- merge prepare 以 trunk `_backlog.yml` 为整体基底。
- 从已验证 source 树中提取目标 CR 的完整条目。
- 使用现有 YAML block matcher 定向替换 trunk 中同 ID 条目。
- trunk 新增的其他 CR、顺序、注释和未知字段必须保留。
- 目标 CR 的 owners、latest-checkpoint 和其他现有 v2 索引字段不得丢失。
- CR status 的唯一权威仍是 `cr.md`；语义合并不得从 `_backlog.yml` 读取、推导或重建 status，也不为兼容残留增加新分支。
- 条目缺失、重复或无法唯一解析时硬失败，不进行文本猜测。

**禁止实现**：整份采用 trunk、整份采用 source、新建 YAML parser、按字符串行号手工拼接。

### FR-04 代码评审后审批前 checkpoint

**问题来源**：P0-04。

**需求**：

- `review-code` 返回 pass、blockers 为空且 test-report 为 pass 后，Pipeline 必须执行现有 `push-progress`。
- checkpoint phase 非 complete 时立即中止，不进入 human approval。
- 回修循环必须重放 implement-code、test、checkpoint、review-code，并在再次 PASS 后重新 checkpoint。
- approve-code 继续执行现有 release-subjects 远端重核，不放宽门禁。

### FR-05 Dev-plan subject digest

**问题来源**：P1-01、TRA-06。

**需求**：

- `review-record --stage dev-plan` 计算 composite digest。
- 输入固定为 LF 规范化后的 `plan.md` 和按仓库相对路径排序的全部 `tasks/TASK-*.md`。
- digest 必须包含每个相对路径和文件内容，避免不同文件集合产生相同拼接结果。
- digest 写入现有 `subject-sha256` 字段，不新建 freshness ledger。
- 本需求不新增 `input-subjects`、subject registry 或通用多文件绑定 schema；requirement、tech-design 和 code 的既有绑定格式保持不变。
- `crctl next` 和 approve-dev-start 消费 PASS 前必须重算；不一致时要求重新 review-dev-plan。
- `_index.yml` 不进入 digest，因为实现期任务状态会变化；TASK 正文必须进入。

### FR-06 CR 时间字段统一

**问题来源**：P1-02。

**需求**：

- 新注册和所有后续状态写入统一使用 `updated`。
- `updated` 表示 `cr.md` frontmatter 最近一次受控修改；除 register 和状态推进外，Owner 正式移交修改 `cr.md` 时也必须更新。
- PRD/SDD/TASK、评审、测试、checkpoint 或其他文件变化不得触碰 `cr.md#updated`。
- reader 在兼容期接受旧 `updated-at`。
- 任一正常 writer 修改该份 `cr.md` 时，发现旧字段应替换为单一 `updated`，不得同时保留两个字段。
- 不批量迁移历史 CR；在正常写入时渐进收敛。

### FR-07 结构化测试深接口

**问题来源**：P1-03、P1-06、TCA-012、TST-01～07。

**需求**：

- 保留一个测试入口，不公开拆分 `test run` 和 `test record`。
- 单一入口内部保持“测试运行”和“测试记录”两个顺序阶段；运行阶段不创建 durable journal，也不持有受控账本写锁。
- 输入使用 `schema=cr-test-plan/v1` 的 JSON plan；每条命令只包含现有 repository id、repo-relative cwd、executable、args 和 timeout。
- `write-test-report` Skill 根据 TASK 验收条件、仓库原生 lint/test/build 配置和 `implement-code` 输出选择正式命令并生成临时 plan；Pipeline 只传递 `cr_id` 与前序输出，Agent 不保存命令表，`crctl` 不做测试发现。
- `implement-code` 可执行开发期临时检查，但这些结果不能替代随后由 `crctl test` 生成的 canonical 测试记录。
- `crctl` 必须通过 `dir-graph.yaml#repositories` 把 repository id 解析到该 CR 的 worktree；cwd 缺省为仓根，只允许位于该 worktree 内的相对路径，不接受绝对路径、未声明仓库或跨仓路径。
- 使用 Node 标准库 `spawnSync(executable, args, { shell: false })`。
- 禁止接受任意 shell 命令字符串、管道、重定向或命令拼接。
- `test-report.md` 机器区必须完整记录规范化后的 command 对象及其整体 LF canonical digest；不另存一份 canonical `plan.json`。
- 原始 stdout/stderr 继续写入现有 `test-evidence/`，报告中的每条 command 只引用对应日志路径和结果。
- `review-code` 不得直接执行或重新执行 lint/test/build；它只读取真实 diff、最终 `test-report.md`、command digest 和原始日志。证据不足、漂移或不可信时必须产出 blocker，并通过既有 reviewLoop 回到 `implement-code → crctl test → write-test-report` 重建证据。
- 仅在合法开发状态执行，并校验 `owners.test.id` 存在。
- 命令全部结束后，使用现有 durable transaction 同批写入机器日志、`test-report.md` 机器区、CR traceability tests 和 review-loop attempt。
- 测试负责人的 TASK 覆盖、未覆盖风险等业务分析不进入上述事务，由 `write-test-report` Skill 在机器记录成功后只写 marker 后分析区。
- 分析区写入失败时 Pipeline 必须在当前节点中止，不得进入 checkpoint、code review 或人工审批。
- 测试失败是可记录的业务结果；参数、执行器、文件或事务错误才是技术失败。
- plan/schema、repository、cwd containment 或 executable 启动失败属于技术失败：立即中止且 canonical 零变化。
- 已启动命令的非零退出或 timeout 属于业务 block：记录该结果并继续执行剩余命令；全部命令结束后一次性发布完整 block 证据。
- plan 不增加 `continueOnError` 或等价分支配置。
- 中断运行不得覆盖上一轮 canonical report，也不得产生新的 canonical attempt。
- 中断后重试必须重新执行完整 plan，不续用部分日志，不增加 durable run-id、运行恢复 journal 或断点续跑协议。
- 不实现日志服务、binary protocol、配额系统或完整工作树 hashing。

**最小 plan 示例**：

```json
{
  "schema": "cr-test-plan/v1",
  "commands": [
    {
      "repo": "tools",
      "cwd": ".",
      "executable": "node",
      "args": ["--test", "test/example.test.mjs"],
      "timeoutSeconds": 600
    }
  ]
}
```

### FR-08 测试报告人工分析保留

**需求**：

- `<!-- crctl:analysis-below -->` 之前为机器区，由 `crctl` 生成。
- marker 及其后内容为人工/模型分析区，重跑时逐字保留。
- `write-test-report` Skill 只拥有分析区；不得改写机器区、traceability tests 或 review-loop。重跑后应依据最新机器结果更新分析，不能把“已保留”误当作“仍然有效”。
- 若报告不存在，则创建空分析区。
- 若 marker 缺失或重复，硬失败并要求人工修复，不猜测分界。
- LF/CRLF 输入必须产生一致结果。
- `review-code` 与 `approve-code` 继续绑定分析完成后的整份最终报告；不新增独立 analysis ledger。

### FR-09 Review canonical 合同

**需求**：

- 所有 review Skill、Pipeline 输出和 annotation 统一使用：`verdict`、`blockers`、`suggestions`、`dimensions`、可选 `repair-target`。
- `repair-instructions` 不作为持久化 canonical 字段。
- `fixed-blockers` 不作为独立账本；下一轮 review 通过 blockers 差异自然体现修复结果。
- blocker 表示本 CR 必须处理的问题；suggestion 表示本 CR 不处理的改进项。
- 删除 `suggestion_policy strict|lenient` 和首轮 suggestion 升格规则。

### FR-10 Candidate 路径约定

**需求**：

- 三个 writeback generator 统一输出到 `{operational_workspace}/.crctl/candidates/{CR-ID}/{stage}`。
- candidate 路径由 `crctl` 选择并传给固定 generator；Skill、Pipeline 和 Agent 不得传入或消费 `--candidate-out`、manifest 路径或 generator 路径。
- 目录必须位于 operational workspace 内并被 Git ignore。
- manifest 仍由 `writeback-apply` 校验；路径约定不是新的 authority。
- archive 只复用现有 workspace 清理，不增加后台清理器。

### FR-11 Baseline traceability 最小证据

**问题来源**：TRA-03、README 当前承诺。

**需求**：

- 当前 CR 新增 milestone 必须包含测试、评审、审批和 merge 的最小证据摘要。
- generator 从 canonical 文件读取，不允许模型手工誊抄状态或 hash。
- 测试证据记录 `status: pass`、相对路径和 LF canonical digest；review 因来自四份独立 annotation，按 requirement、tech-design、dev-plan、code 分项记录 `verdict: pass`、路径和 digest。
- 审批证据只聚合记录整个 canonical `approval.yml` 的 `status: approved`、路径和 digest；归档门禁从该文件验证四个必需 grant，不在 traceability 复制分阶段 grant 摘要。
- merge 证据只聚合记录整个 canonical `merge-commits.yml` 的 `status: merged`、路径和 digest；归档门禁从该文件验证当前 CR 的合并事实，不复制 commit 明细。
- 任何证据不得复制完整报告、annotation、grant 或 merge commit 明细。
- 既有 milestone 继续作为 opaque 历史段逐字保留。
- 新 milestone 不写 status；不得复制瞬时 `writing-back`、提前写 `archived` 或引入状态机之外的 `released`。CR 状态继续只由 `cr.md` / `_history.yml` 表达。
- 历史 milestone 缺少新字段不构成读取错误，也不批量迁移。
- `crctl archive` 必须在归档事务产生任何写入前校验当前 CR 新增 milestone 的上述证据；缺失、重复、状态不通过、路径不合法或 digest 不匹配均硬失败。
- archive gate 与 generator 复用同一确定性证据校验函数，只检查当前 CR milestone；既有历史 milestone 保持 opaque，不建立通用 schema registry 或脚本型 gate。

固定最小结构：

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

### FR-12 Traceability generator 事实修正

**需求**：

- trunk 只从 repositories resolver 获取；缺失时硬失败，禁止回退 `master`。
- merge 只从 `change-requests/{CR-ID}/merge-commits.yml` 读取。
- 注释、变量和错误文案不得继续声称来源为 backlog。
- candidate generator 身份由 `writeback-apply` 对当前 Tools Root 中固定脚本计算真实 hash，不信任 manifest 自报值。
- `writeback-apply` 只按固定 stage 映射调用版本化脚本；该映射是内部常量，不建设 generator plugin registry。
- 不建立 generator plugin registry。

### FR-13 不支持能力退役

**需求**：

- 删除 `change-impact-analysis` Skill 及其 active Skill、Agent references、matrix 和 README 能力声明。
- 删除 review-alignment 对不存在 stale 模型的依赖。
- feedback-writeback 在缺少受控实现、正式调用方和消费者时不得被 README/Agent 声称为可执行终态能力。
- 保留 `CONTEXT.md` 中“终态反馈事实”的 canonical 语义；退役的是当前直接手写 traceability/tech-notes 并发送 inbox 的 Skill 契约，不删除领域模型。
- feedback-writeback 的后续建设条件以 Tools `CUSTOM.md#CUSTOM-TODO-010` 为准，本轮不增加占位命令、字段或兼容分支。
- 不创建占位 Skill 来满足 Agent 能力声明；删除超前声明。
- reviewer-panel 当前存在且有引用，本规格不删除。
- 删除 `skills/review/change-impact-analysis/SKILL.md` 与 `skills/cr/feedback-writeback/SKILL.md`，并同步删除 `skills/_index.yml`、matrix、Agent、README、dir-graph hint、inbox event allowlist 及其他 active 引用；不得保留 retired stub、占位 Skill 或旧事件名。
- Git 历史承担旧 Skill 的审计与恢复；未来 feedback 能力只能按 `CUSTOM-TODO-010` 注册独立 CR 后重新创建。

### FR-14 Agent、Pipeline 和 Skill 收敛

**需求**：

- Agent 不保存状态表，不从 backlog 推断 status，不描述 Git 或账本写入算法。
- Pipeline 节点 prompt 只保留输入、调用的 Skill/命令、结果分类、reviewLoop 和失败动作。
- Skill 不复制 journal、CAS、merge、checkpoint 或 writeback 算法。
- `review-code` Skill 只做代码与证据质量判断，不拥有测试执行；删除 Pipeline prompt 中“无条件重新执行 lint/test/build”的第二入口。
- `write-test-report` Skill 拥有正式验证范围与分析区，调用一次 `crctl test --plan <temporary-json>` 后补充 marker 后分析；不得直接写机器区或账本投影。
- 每个生产 writeback Skill 只调用一次 `crctl writeback-apply` 并解释结构化结果；固定 generator 调用、candidate 路径、manifest 校验和 stale 后重生成均封装在该深原语内部。
- write Skill 不输出手工 `git add/commit/push` 配方。
- 删除 code Pipeline 的 reviewer LLM 人工选择节点；Agent/runtime 在进入 Pipeline 前完成选择。

### FR-15 README 收敛

**需求**：

- README 保留生命周期总览、Owner 职责、Pipeline/Skill 入口、人工审批方式、恢复命令和权威链接。
- 删除节点级 prompt、内部算法、完整错误矩阵、动态规模数字和会漂移的默认值副本。
- 状态机只展示概念流程，并链接权威 `dir-graph.yaml`，不维护第二份完整声明。
- archive 与 cleanup-pending、checkpoint 与 publish、merge 与 operational workspace 的区别应使用人读语言说明。

### FR-16 静态治理和 CI

**需求**：

- 保留 `crctl-ci.yml` 作为唯一主治理 workflow。
- 删除功能重复的 `check-skill-matrix.yml` workflow；检查脚本本身保留并由主 workflow 调用。
- CI 触发路径补齐 README、AGENT-SKILL-MATRIX、rules、Agent、Skill、Pipeline 和 workflow 自身。
- 复用现有 `lint-prompts` 增加少量确定性规则：废弃命令、非法状态 trigger、受控文件手写、已退役 Skill 引用。
- Pipeline JSON 的结构检查采用 JSON.parse 和固定字段断言，不构建符号执行器或 prompt 语义解释器。
- 所有新行为必须在 Ubuntu 和 Windows 上运行。

## 9. 失败语义

| 场景 | 预期行为 | 是否允许自动重试 |
|---|---|---|
| writeback 内部 manifest 非法 | 零 journal、零 authority 写入、结构化错误 | 修正业务源文件或固定 generator 后以同一命令重试 |
| writeback origin 前进 | txws 回到新 origin，要求重生成 candidate | 是 |
| writeback 已 commit 未 push | 使用既有 journal 续推 | 是 |
| writeback 已确认远端、status outbox 或 success audit 发送失败 | Git 权威事实保持成功，返回明确 warning；重放只补发缺失的确定性投影 | 是 |
| backlog 目标条目缺失或重复 | merge prepare 硬失败，零发布 | 修复账本后重试 |
| review PASS 后 checkpoint 失败 | Pipeline 中止，不进入人工审批 | 是 |
| dev-plan digest 漂移 | 旧 PASS 失效，回到 review-dev-plan | 是 |
| test 非零退出或 timeout | 继续剩余命令，完成后原子记录 block 结果并回到 implement-code | 是，使用新 attempt |
| test plan/repository/cwd 非法或 executable 无法启动 | 立即中止；技术错误，canonical report 不更新 | 修正后完整重试 |
| baseline 证据缺失 | traceability generator 硬失败 | 补齐证据后重试 |
| generator hash 不匹配 | writeback 拒绝 candidate | 使用当前脚本重生成 |
| archive cleanup 失败 | status 保持 archived，返回 cleanup-pending 详情 | 是 |

禁止通过手改 `_backlog.yml`、`cr.md`、approval、traceability 或 journal 绕过失败。

## 10. 实施 CR 切片

### 实施 CR 1：Writeback 原子化

范围：FR-01、FR-02、FR-03、FR-10。

1. 为 writeback preflight 增加失败零副作用红测。
2. 调整 manifest 校验顺序。
3. 将 baseline 固定状态变更并入 writeback write-set。
4. 为 `_backlog.yml` 增加目标 CR 条目替换纯函数及测试。
5. 将该纯函数接入 merge prepare。
6. 统一内部 candidate 目录并补 containment、ignore 和清理测试。
7. 补 commit、push、远端推进和非末条 CR 集成测试。

完成标准：回写的预检、受控写集、状态发布和远端提交形成单一原子边界；语义合并不丢失 trunk 的其他 CR 条目。

### 实施 CR 2：生命周期证据规范化

范围：FR-04、FR-05、FR-06、FR-09。

1. 在 code Pipeline review PASS 后插入现有 push-progress。
2. 复用现有 digest helper 实现 dev-plan composite digest。
3. 在 review-record、next 和 approve-dev-start 接入 digest。
4. 统一 `updated` writer 和旧字段 reader。
5. 收敛 review canonical 字段和 blocker/suggestion 路由。

完成标准：评审结论只绑定已 checkpoint 的受控内容；TASK 集合漂移、时间字段兼容和评审路由均有回归测试。

### 实施 CR 3：结构化测试闭环

范围：FR-07、FR-08。

1. 将 `crctl test` 改为结构化 plan、`shell:false` 和事务记录。
2. 区分计划/启动技术失败与已启动命令的业务失败。
3. 将完整规范化 command 和整体 digest 发布到测试报告机器区。
4. 实现 marker 后人工分析区保留和受控更新。
5. 补 CRLF、超时、中断、失败 attempt、重复执行和原始日志测试。

完成标准：正式测试由一份结构化计划驱动，机器证据原子发布，人工分析可保留且不能绕过 checkpoint、review 或 approval。

### 实施 CR 4：归档可信化

范围：FR-11～FR-13。

1. 在 writeback-traceability generator 中机械注入最小证据摘要。
2. 删除 `master` fallback 和 backlog 旧注释。
3. 校验固定 generator 的真实 hash。
4. 新 milestone 不写状态；CR 状态继续只由 `cr.md` 与 `_history.yml` 表达。
5. 删除 change-impact-analysis Skill 文件、active 引用和 stale 依赖，不保留 retired stub。
6. 删除当前 feedback-writeback Skill 文件及 active/inbox event 引用，保留“终态反馈事实”领域模型，并登记 `CUSTOM-TODO-010`；不实现新事务接口或占位 Skill。
7. 在 `crctl archive` 接入当前 CR milestone 严格证据门，复用 generator 的确定性校验函数。

完成标准：新 milestone 证据齐全，旧 milestone 字节不变；缺失或漂移证据无法进入 archived；不存在 active Skill 引用不存在的数据模型。

### 实施 CR 5：职责边界清理

范围：FR-14～FR-16。

1. 缩短 Agent 文档，删除状态链和写入算法。
2. 缩短 Pipeline prompt，保留节点编排和结果路由。
3. 删除 reviewer 选择暂停、suggestion policy 和过时字段。
4. 清理 CR write Skill 的旧模板、MCP 和 validate-doc 声明。
5. 重写 README 为总览和权威入口。
6. 合并 CI workflow，扩展现有 lint 的确定性规则。
7. 更新 OpenWiki 中仍指向旧命令或旧能力的引用。

完成标准：Agent、Pipeline、Skill、README 中不存在第二份状态机、深原语算法或已退役能力声明。

### Phase E：跨 CR 端到端验收

使用一条新建最小 CR 完成：

1. register、需求评审和审批。
2. 技术设计评审和审批。
3. dev-plan/TASK 评审和审批，并验证 TASK digest 漂移。
4. implement、test、checkpoint、code review、review 后 checkpoint、code approve。
5. merge、baseline/tasks/traceability writeback 和 archive。
6. 在 writeback、checkpoint、merge、approval 前分别制造一次远端推进。
7. 执行非法 manifest、非末条 backlog、CRLF、重复调用和故障恢复场景。

最终验收要求：状态、远端 refs、CR 产物、baseline、delivery、traceability 和 history 投影一致；任一失败都不需要手改账本恢复。

## 11. 测试矩阵

| 需求 | 最小测试 |
|---|---|
| FR-01 | baseline 文件与 writing-back 同 commit；planned `fileExists` 只接受已验证 manifest 精确路径且其他 gate 不受覆盖；origin 确认前零 success audit/status outbox；各 fault point 可恢复；投影失败重放只补发缺失项且携带真实 SHA；幂等重放 |
| FR-02 | 非法 JSON/schema/path/hash/generator 均零 journal；修正后成功 |
| FR-03 | 目标 CR 在首条/中间/末条；trunk 新增前后 CR；注释和未知字段保留 |
| FR-04 | PASS 未 checkpoint 不到审批；checkpoint 后 release subject 校验通过 |
| FR-05 | 修改 plan、任一 TASK、TASK 路径集合均使旧 PASS 失效；只改 `_index.yml` 不失效 |
| FR-06 | register/status/Owner 修改更新时间；其他产物不更新时间；legacy updated-at、双字段异常和 CRLF |
| FR-07 | argv 中空格和 Unicode；shell 元字符不执行；结构化 command 与整体 digest 可复算；无重复 plan 文件；非零/timeout 继续并原子记录 block；启动技术失败和外部中断不覆盖旧报告 |
| FR-08 | marker 后多行内容逐字保留；marker 缺失/重复硬失败 |
| FR-09 | Pipeline/Skill 不再引用废弃字段；blocker/suggestion 路由正确 |
| FR-10 | candidate containment、ignore 和 archive 清理 |
| FR-11 | 四类证据摘要正确；缺失/重复/evidence 状态不通过/路径非法/digest 漂移均阻止 archive；新 milestone 无 status；旧 milestone 不变 |
| FR-12 | 缺 trunk 不回退 master；错误 generator hash 被拒绝 |
| FR-13 | 两个旧 Skill 文件已删除；index、matrix、Agent、README、dir-graph 与 inbox allowlist 无退役能力引用；Git 历史仍可追溯 |
| FR-14/15 | lint 检测手写受控文件、Git 算法和状态机副本 |
| FR-16 | Ubuntu/Windows CI 全绿且仅一个主 workflow 执行治理套件 |

## 12. 延期事项与启动条件

| 延期事项 | 启动条件 |
|---|---|
| 终态反馈事实受控写回 | 出现真实调用方与消费者，并按 Tools `CUSTOM.md#CUSTOM-TODO-010` 注册独立实施 CR；领域语义沿用现有 `CONTEXT.md`，不在本轮重建 |
| 强 Agent/调用者授权 | 平台能够签发并由 crctl 验证短时 execution grant |
| 完整测试工作树 digest | 出现 test-report 与实际被审批代码不一致且现有 code review 重跑未拦截的事故 |
| CR depends-on 和跨 CR 调度 | 出现可复现的并行 CR 依赖阻塞，人工管理已不足 |
| reviewer-panel 退役 | 全仓引用和实际运行取证证明无消费者 |
| focus-briefing 写入治理 | 该能力进入真实产品流程并明确索引写入 Owner |

延期事项不得通过预留接口、空字段、占位 Skill 或兼容分支提前进入实现。

## 13. Ponytail 约束

- `reuse`：优先复用 `crctl`、durable transaction、review-record、writeback manifest、YAML matcher 和现有测试 fixture。
- `native`：命令执行使用 Node `child_process`，文件和 hash 使用 Node 标准库，Git 操作使用现有 controlled Git adapter。
- `delete`：删除 Pipeline 算法副本、Agent 状态副本、README 可执行细节、虚假 capability 和重复 workflow。
- `yagni`：不建立通用 test/traceability 平台、事务框架、registry、数据库或强授权字符串模型。
- `shrink`：任何新增 interface 必须比调用方当前需要掌握的步骤更小；否则直接在现有深模块中修复。

新增抽象必须同时满足：

1. 现有深接口无法表达。
2. 存在已复现且重复发生的真实故障。
3. 删除该抽象会让复杂度重新散落到多个调用方。
4. 新增代码和长期接口成本低于直接复用现有能力。

任一条件不满足，默认不实现。

## 14. 来源问题映射

| 来源 | 本规格处理 |
|---|---|
| `CR 流程待改进.md` P0-1～P0-4 | FR-01～FR-04 |
| `CR 流程待改进.md` P1-1～P1-5 | FR-05、FR-06、FR-08～FR-10 |
| ARC-01/03/04/05 | 已解决基础设施，不重复实施 |
| ARC-02 | FR-11：实施 CR 4 仅对当前 CR milestone 启用严格 archive evidence gate，历史段保持 opaque |
| CKP-01～CKP-07、TCA-011 | 已由 CR-2026-033 解决；仅 FR-03 修组合冲突 |
| TST-01～TST-07、TCA-012 | FR-07、FR-08，裁剪公共 run/record 平台 |
| TRA-01/03/04/05/07/11/12 | FR-11、FR-12 |
| TRA-02、TCA-014 impact 部分 | FR-13 退役，不补模型 |
| TRA-06 | FR-05，直接进入 review-record |
| TRA-08～TRA-10、TCA-013 | 延期 feedback，先停止虚假能力声明 |
| TCA-001、003～010、019 | 已解决基础设施 |
| TCA-002、015 | 数据一致性已修；强授权延期 |
| TCA-016～018 | FR-13～FR-15 |
| TCA-020～024、027 | FR-15、FR-16，裁剪通用 checker |
| TCA-025 | 延期，非本轮 CR 主链 |
| TCA-026 | FR-13，删除超前能力声明 |

## 15. 完成定义

本规格完成不以“新增命令数量”或“文档全部改写”为标准，而以以下事实同时成立为准：

1. 四个 P0 生命周期漏洞均有回归测试并关闭。
2. 所有状态推进、审批、账本和 Git 发布仍只通过 `crctl` 深模块。
3. Pipeline 不再复制深原语算法，Agent 不再维护状态机或写入受控文件。
4. dev-plan 和测试证据能够阻止旧 PASS 被错误复用。
5. baseline traceability 保存足够的发布证据，但不复制完整过程账本。
6. 已解决的 archive、checkpoint、merge 和 transaction 不被重新设计。
7. 所有延期事项均没有预留空接口或占位实现。
8. Ubuntu/Windows CI 和一条真实端到端 CR 均通过。

最终目标是让现有深模块真正承担其职责，并通过删除重复契约降低系统复杂度，而不是为每个历史问题增加一个新命令、新 schema 或新框架。
