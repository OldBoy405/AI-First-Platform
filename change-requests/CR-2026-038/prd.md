---
id: CR-2026-038-prd
type: PRD
cr-ref: CR-2026-038
title: tools CR 生命周期最小优化 1/5 — Writeback 原子化
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-14T20:09:56+08:00
updated: 2026-08-14T20:09:56+08:00
---

# 1. 概述

## 1.1 背景

Tools 包已具备 candidate-only generator、`crctl writeback-apply`、durable transaction、状态门禁、跨仓 merge 和 archive 等基础能力，但 writeback 的组合边界仍未闭合：baseline 文件发布与 `merging -> writing-back` 状态推进由两个独立命令完成；manifest 的完整只读校验晚于事务 journal 创建；merge prepare 对全局 `_backlog.yml` 缺少只替换目标 CR 条目的语义合并；candidate 目录仍由 Skill/Pipeline 调用方选择并通过参数向下传递。

这些缺口会造成四类真实风险：

1. baseline 已发布但状态未进入 `writing-back`，后续阶段从 origin 恢复时丢失状态事实。
2. 非法 manifest 已创建 journal，修正输入后因事务输入摘要变化而阻断合法重试。
3. CR 分支中的 `_backlog.yml` 与持续前进的 trunk 发生无业务意义的整文件冲突，或覆盖其他 CR 条目。
4. 调用方掌握 candidate 路径、generator 路径和 manifest 位置，导致深原语边界外泄并产生路径漂移。

本 CR 落实来源规格 FR-01、FR-02、FR-03、FR-10，只修复上述 writeback 原子边界，不重建事务框架、状态机、账本模型或通用 generator 平台。

## 1.2 事实基线

- 权威来源：`docs/analysis/tools-cr-lifecycle-minimal-optimization-spec.md`。
- 来源文档声明的核对基线为 `tools@origin/custom/main`，commit `7b73204464e136b83d4377ba1447a11c2291e6c6`；本次撰写前已通过受控 Git 读取确认该远端引用仍指向此 SHA。
- 当前 CR 的 tools worktree 从本地 `custom/main@c790b7ea778863c4e95b9e94fd01a7840c1691a9` 派生。对该 worktree 的代码检索仍确认：feature-writeback Pipeline 独立调用 baseline `writeback-apply` 与 `advance writing-back`；`writeback-apply` 仍要求 `--candidate`；三个 generator 仍暴露 `--candidate-out`。因此本地提交差异不改变本 CR 的问题结论与范围。
- 状态机、门禁、仓库图和受控写入分别以 Tools `dir-graph.yaml`、`skills/shared/crctl/gates.json`、工作区 `dir-graph.yaml` 和 `skills/shared/crctl/` 当前实现为准，本 PRD 不复制第二套声明。

## 1.3 目标

- baseline 文件、`merging -> writing-back` 状态、提交和远端发布形成一个可恢复的权威事务边界。
- 所有可在零副作用条件下完成的 writeback 校验都发生在 lock/journal 之前。
- merge prepare 只把目标 CR 的 backlog 条目合入最新 trunk，完整保留其他 CR 条目和未知内容。
- candidate 生成位置与固定 generator 选择由 `crctl` 内部拥有，生产调用方不再传递内部路径。
- 所有失败均可使用同一业务命令重试或按结构化错误修复，不需要手改账本、journal 或 baseline。

## 1.4 解决方案摘要

在现有 `crctl writeback-apply` 深原语内完成最小深化：将 baseline 固定状态变更纳入同一 recoverable write-set；把 generator 执行与 manifest 全量预检前移到事务创建之前；在 merge prepare 中复用现有 YAML block matcher 定向替换目标 CR 条目；把 candidate 根目录固定为 operational workspace 内部路径。Pipeline 与 Skill 只保留业务输入、一次深原语调用、结果分类和后续路由。

# 2. 用户故事

- **US-01 回写执行者**：希望执行一次 baseline writeback 后，baseline 内容和 `writing-back` 状态同时成为远端权威事实，以便后续 tasks/traceability 回写不会从旧状态恢复。
- **US-02 故障恢复执行者**：希望非法 manifest 或门禁失败不创建事务中间态，以便修正业务输入后直接重跑同一命令。
- **US-03 并行 CR 维护者**：希望 merge 当前 CR 时保留 trunk 上其他新注册 CR 的条目、顺序、注释和未知字段，以便并行注册不制造冲突或数据丢失。
- **US-04 Skill/Pipeline 作者**：希望只提供 `cr_id`、`stage`、`spec_id` 等业务输入，不需要选择 generator、candidate 目录或 manifest 路径。
- **US-05 审计与运维人员**：希望状态事件和成功审计只引用 origin 已确认的真实 commit SHA，投影发送失败可单独补发且不反转 Git 权威事实。
- **US-06 Tools 维护者**：希望实现复用现有 durable transaction、gate、YAML matcher、Git adapter 和测试 fixture，不引入第二套事务或插件框架。

# 3. 功能需求

## FR-01 Baseline 回写与状态同批发布

1. `writeback-apply --stage baseline` 必须在 candidate、目标矩阵、origin 和状态门禁全部通过后，把以下内容放入同一 recoverable write-set、同一 commit 和同一次 lease push：
   - manifest 声明的 baseline PRD/SDD 与索引文件；
   - operational workspace 中 `change-requests/{CR-ID}/cr.md` 的 `merging -> writing-back` 状态变更及受控更新时间。
2. 状态转换必须继续读取权威状态机和 `gates.json`，不得在 writeback 内复制转换表或另建专用状态机。
3. 仅 `fileExists` gate 可以接收 planned-existing 路径集合；该集合必须精确来自已通过 schema、stage、CR、spec-id、containment、allowlist、before/after hash、generator hash 和目标矩阵校验的 manifest。其他 gate 类型必须只读取当前 authority，不得读取虚拟文件内容。
4. feature-writeback Pipeline 和 `writeback-prd-sdd` Skill 不得再在 baseline writeback 成功后独立调用 `crctl advance --embedded`。
5. 该复合行为只适用于 `stage=baseline` 的固定 `merging -> writing-back` 转换，不得扩展为调用方可指定任意状态或 trigger 的复合接口。
6. 只有 origin 已确认包含真实 write-set commit 后，才允许：
   - 发送一次 status outbox，commit SHA 必须为真实远端已确认 SHA，不得使用 `pending:` 占位；
   - 写入一次 `kind: advance` success audit；
   - 在既有 writeback journal 标记 `outboxEmitted` 与 `auditEmitted`。
7. outbox 或审计发送失败不得回滚已确认的 Git 权威事实；命令返回明确 warning。重放只能补发缺失投影，不得新增 commit、重复 push 或重复已成功投影。
8. 已完成事务的幂等重放必须返回成功与 `changed=false`，并保持远端 commit、状态事件和审计各自唯一。

## FR-02 Writeback 只读预检与零副作用失败

1. 生产入口不得接受调用方提供 candidate manifest、generator 路径或 candidate 输出目录。`crctl` 必须依据固定 stage 和当前 Tools Root 选择唯一版本化 generator 并在内部生成 candidate。
2. 在获取 writeback lock 或创建 durable journal 之前，必须依次完成以下只读/可丢弃步骤：
   - 业务参数、CR 状态与 spec-id 校验；
   - 固定 generator 执行；
   - candidate 文件及 manifest JSON 读取；
   - manifest schema、stage、CR、spec-id、路径 containment、symlink parent、allowlist、文件 hash、before 磁盘锚点、generator hash、input digest 和目标矩阵校验；
   - baseline 状态门禁校验。
3. manifest 必须只读入一次，读入后先执行 `CRLF -> LF` 规范化；事务使用同一份文本及其 digest，不得在预检和持久化阶段二次读取产生 TOCTOU 语义漂移。
4. 任一预检失败必须满足零 authority 副作用：不创建 durable journal，不遗留 lock，不修改目标文件，不产生 commit/push，不发送 outbox 或 success audit。
5. candidate 是 operational workspace 内可丢弃的派生物，不是 authority。修正业务源文件或固定 generator 后重跑同一业务命令，不得因上一次非法输入产生 `TX_INPUT_CONFLICT`。
6. 预检通过后若 origin 在发布前前进，继续沿用现有 stale/rebuild 语义：Transaction Workspace 回到新 origin，重新生成 candidate 后重试；不得 rebase/cherry-pick 未发布 candidate。

## FR-03 `_backlog.yml` 目标 CR 条目语义合并

1. merge prepare 必须以最新 trunk 的完整 `change-requests/_backlog.yml` 为基底。
2. 从已验证的 CR source tree 中提取目标 CR 的完整 backlog 条目，并复用现有 YAML block matcher 在 trunk 文本中定向替换同 ID 的唯一条目。
3. 合并结果必须逐字保留 trunk 中所有其他 CR 条目及其顺序、注释、空行、未知字段和未来兼容字段。
4. 目标 CR source 条目中的 `owners`、`latest-checkpoint` 及其他现有 v2 注册索引字段必须完整保留。
5. CR status 的唯一权威仍为 `change-requests/{CR-ID}/cr.md`。语义合并不得从 `_backlog.yml` 读取、推导、重建或回填 status，也不得为历史残留 status 增加新的兼容分支。
6. trunk 或 source 中目标条目缺失、重复或无法唯一解析时必须在 prepare 阶段硬失败，且零远端发布；不得按行号、模糊字符串或整文件取舍猜测结果。
7. 实现不得引入新的通用 YAML parser 或 YAML patch 框架；必须使用现有 block matcher 并为目标条目替换提炼最小纯函数。

## FR-04 Candidate 内部路径与固定 generator 约定

1. baseline、tasks、traceability 三个生产 writeback stage 的 candidate 必须统一生成到：

   ```text
   {operational_workspace}/.crctl/candidates/{CR-ID}/{stage}
   ```

2. candidate 根目录必须位于 resolver 确认的 operational workspace 内；真实路径解析后不得越界，不得经过 symlink parent 指向外部路径。
3. `.crctl/candidates/` 必须被 Git 忽略，不得出现在 staged set、commit 或远端 authority 中。
4. stage 到固定 generator 的映射是 `crctl` 内部常量。Skill、Pipeline、Agent 和公共 CLI 不得传入或消费 `--candidate-out`、`--candidate`、manifest 路径或 generator 路径。
5. manifest 仍由 `writeback-apply` 执行全矩阵校验；固定目录只解决内部派生物位置，不成为新的信任边界或事实源。
6. candidate 生命周期复用现有 operational workspace/archive 清理，不新增后台清理器、candidate manager、registry 或公共查询 API。

# 4. 非功能需求

- **NFR-01 原子性**：baseline 文件、状态、commit 和 push 必须共享一个 recoverable write-set；任何 commit 前故障均不得留下部分 authority 文件。
- **NFR-02 可恢复性**：write-set、commit、push、outbox、audit 各故障点均须有 fault-injection 测试；Git authority 已确认后的恢复只允许 roll-forward。
- **NFR-03 幂等性**：同一业务输入重复执行不新增 journal、commit、push、outbox 或 audit；已完成事务返回稳定结果。
- **NFR-04 安全性**：所有路径必须 workspace-relative 且经过 containment、allowlist、symlink parent 与 hash 校验；禁止绝对路径、`..` 和调用方指定 generator。
- **NFR-05 兼容性**：LF/CRLF 输入产生一致语义；解析按 `split(/\r?\n/)` 或等价规范化实现，跨行结构匹配失败必须硬失败。新增行为必须在 Ubuntu 和 Windows 上通过。
- **NFR-06 数据保真**：backlog 语义合并除目标 CR 条目外不得改变任何字节；目标条目的未知字段不得丢失。
- **NFR-07 可审计性**：status outbox 与 success audit 必须绑定同一个 origin-confirmed 真实 commit；补发行为有确定性去重键和 journal 标记。
- **NFR-08 性能**：预检只读取一次 manifest 文本；不得为本 CR 引入全仓数据库扫描、后台服务或额外网络往返协议。
- **NFR-09 复杂度边界**：优先复用现有 `performAdvance` 候选逻辑、`runGateChecks`、durable transaction、writeback manifest、YAML block matcher、Git adapter 和测试 fixture；不新增 npm 依赖、通用事务管理器、generator plugin registry、schema registry 或 YAML patch 平台。

# 5. 验收标准

- **AC-01（FR-01）**：baseline writeback 成功后，远端同一个 commit 同时包含 baseline 目标文件和 `cr.md` 的 `writing-back` 状态；紧接着执行 tasks writeback 不会把状态重置为 `merging`。
- **AC-02（FR-01）**：planned-existing 覆盖只对已完整验证 manifest 中的精确路径参与 `fileExists` gate；修改为其他路径或用于其他 gate 类型时门禁拒绝且零写入。
- **AC-03（FR-01）**：在 write-set、commit、push、origin-confirmed 后 outbox、origin-confirmed 后 audit 各 fault point 中断并重跑，最终最多一个权威 commit、一次 status outbox 和一次 success audit；投影失败只返回 warning 并可补发。
- **AC-04（FR-01）**：feature-writeback Pipeline、`writeback-prd-sdd` Skill 与测试中不再存在 baseline 完成后独立 `advance --to writing-back` 的生产调用；任意状态复合参数不可从公共接口传入。
- **AC-05（FR-02）**：非法 JSON、schema、stage、CR、spec-id、containment、symlink parent、allowlist、before/after hash、generator hash、input digest 或目标矩阵任一失败时，journal、lock、目标文件、commit、push、outbox 和 audit 均无新增。
- **AC-06（FR-02）**：先以非法 manifest 触发失败，再修正同一业务源并重跑，能够成功且不会返回由前次非法输入引起的 `TX_INPUT_CONFLICT`。
- **AC-07（FR-02/FR-04）**：公共 CLI、三个 writeback Skill 和 feature-writeback Pipeline 不再接受或传递 `--candidate`、`--candidate-out`、manifest 路径和 generator 路径；stage 只能选择内部固定 generator。
- **AC-08（FR-03）**：参数化测试覆盖目标 CR 位于 backlog 首条、中间、末条，且 trunk 在目标条目前后各新增 CR；结果只替换目标条目，其他条目、顺序、注释、空行和未知字段逐字不变。
- **AC-09（FR-03）**：目标 CR 条目在 trunk/source 缺失或重复时 merge prepare 硬失败，所有 repo 远端 ref 均不前进；测试证明不回退到整份 trunk、整份 source 或行号拼接。
- **AC-10（FR-03）**：目标条目的 `owners`、`latest-checkpoint` 与未知 v2 字段完整保留，且语义合并代码不读写 backlog status。
- **AC-11（FR-04）**：三个 stage 的 candidate 均只出现在 `.crctl/candidates/{CR-ID}/{stage}`，目录受 containment 约束并被 Git 忽略；archive/workspace 清理后不残留需额外后台任务处理的 candidate。
- **AC-12（整体）**：新增回归测试与现有 crctl/writeback 测试在 Ubuntu、Windows 全绿；不得通过删除测试、放宽门禁或弱化现有断言获得通过。

# 6. 成功指标

- baseline writeback 的远端权威提交与 `writing-back` 状态提交数量比固定为 1:1，不再出现独立状态提交或状态丢失。
- 所有 manifest 业务校验失败均满足零 journal、零 authority 写入，修正输入后同命令重试成功。
- backlog 语义合并矩阵对首/中/末条和 trunk 前后新增 CR 场景全部通过，非目标条目字节变化数为 0。
- active Agent/Skill/Pipeline 的 candidate 路径、generator 路径和 baseline 独立 advance 算法副本数量为 0。
- 本 CR 交付不增加 npm 依赖、通用 registry、第二状态机或第二事务框架。

# 7. 依赖、风险与恢复边界

## 7.1 依赖

- 复用 CR-2026-031 已交付的 durable transaction、Transaction Workspace、candidate manifest 和 `writeback-apply`。
- 复用现有状态候选逻辑、`gates.json`、YAML block matcher、repository resolver、Git lease adapter 和 fault-injection fixture。
- 不建立 CR 级 `depends-on` 图；与 CR-2026-039~042 的范围通过来源规格切片隔离，不在本 CR 中复制其交付。

## 7.2 主要风险与控制

- **planned-existing 放宽门禁过宽**：只允许完整验证 manifest 的精确路径进入 `fileExists` 集合，其他 gate 保持现有 authority 读取。
- **origin-confirmed 后投影失败**：Git 事实不回滚，journal 分别记录 outbox/audit 是否发送，重放只补缺项。
- **backlog 文本保真受 Windows 行尾影响**：读入后先规范化解析，before hash 仍锚定磁盘原字节；跨行解析失败硬失败。
- **candidate 内部化造成旧调用方残留**：通过静态 lint/contract 测试扫描所有 active Pipeline、Skill、CLI help 和测试 fixture，不保留长期双入口。
- **本地 worktree 基线高于远端核对基线**：实现期以目标 CR tools worktree 的真实结构为准；若发现论据变化，必须修订本 PRD/SDD 并明确结论是否受影响。

## 7.3 失败与恢复

- 预检失败：零事务副作用；修正业务输入或固定 generator 后重跑同一业务命令。
- origin 在未发布前前进：按现有 stale 语义重置 Transaction Workspace，重生成 candidate 后重试。
- 已 commit 未 push：复用既有 journal 续推，不重建不同 commit。
- origin 已确认、outbox 或 audit 失败：保持成功 Git 事实，返回 warning；同命令重放只补发缺失投影。
- backlog 条目缺失/重复：prepare 阶段硬失败；修复权威账本后重试，禁止手工绕过 merge 或 force push。

# 8. 范围排除

- 不实施来源规格 FR-04~FR-09、FR-11~FR-16；这些分别属于 CR-2026-039~042。
- 不实施 Phase E 跨 CR 端到端验收；该验收在五条生产 CR 全部完成后使用独立最小 CR 执行。
- 不建立通用事务管理器、任意复合状态接口、generator/candidate manager、plugin registry、schema registry、YAML patch 框架或新的 workflow engine。
- 不建立 CR 依赖图、跨 CR 调度器、target repository/source scope 新模型。
- 不修改测试执行、review canonical、CR 时间字段、baseline traceability 证据模型、archive 严格证据门或 Agent/README/CI 职责文本。
- 不允许 force push、force rollback、自动补偿 revert、merge conflict bypass 或手工修改 `_backlog.yml`、`cr.md`、journal。
- 不重写历史 baseline milestone，不批量迁移历史数据，不为历史事实制造伪 commit、伪 digest 或伪事件。

# 9. 追溯矩阵

| 来源规格 | 本 PRD | 主要验收 |
|---|---|---|
| FR-01 Baseline 回写与状态发布 | FR-01 | AC-01~AC-04 |
| FR-02 Writeback 只读预检 | FR-02 | AC-05~AC-07 |
| FR-03 `_backlog.yml` 目标条目语义合并 | FR-03 | AC-08~AC-10 |
| FR-10 Candidate 路径约定 | FR-04 | AC-07、AC-11 |
| 实施 CR 1 完成标准 | FR-01~FR-04、NFR-01~09 | AC-01~AC-12 |

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 根据 Tools CR 生命周期最小优化规格的实施 CR 1 切片创建初始 PRD |
