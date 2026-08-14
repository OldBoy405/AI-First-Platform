---
id: CR-2026-032-prd
type: PRD
cr-ref: CR-2026-032
title: tools Archive 独立小修：cleanup 回显、正常归档 outbox、README 语义（TCA-010 收尾）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-13T08:53:30+08:00
updated: 2026-08-13T08:53:30+08:00
---

# 1. 概述

CR-2026-031 已将 archive 主链收敛为 `crctl archive` 单一深原语：四账本通过 recoverable write-set 同批修改，archive commit 经 lease push 发布后再清理 Transaction Workspace、CR worktree 与分支。当前剩余三个相互独立但影响可恢复性和平台实时投影的问题：cleanup 异常已写入 journal 却未返回调用者；正常 `writing-back -> archived` 归档未发出 Multica 已支持的 `archive` outbox；README 仍容易让使用者误以为归档发布和资源清理是同一个全成全败动作。

本 CR 按来源方案交付分组 A（T02）完成 ARC-03、ARC-04、ARC-05。实现复用现有 `archiveCr()`、outbox schema、Multica archive 消费链和幂等键，不新增 archive 命令、事件类型、协议版本或事务层。严格 traceability 结构门禁 ARC-02 明确留给后续 Traceability/feedback CR，在 baseline generator 能生成完整证据前不得提前启用。

# 2. 用户故事

- **US-01 CR 运维者**：当归档事实已发布但 cleanup 异常时，希望命令直接返回错误详情、剩余资源和恢复命令，以便处理现场后续跑，而不是读取内部 journal 猜测原因。
- **US-02 平台使用者**：希望正常归档完成后 Multica 及时收到合法的 `writing-back -> archived` 事件，以便 CR 状态和 feature-writeback pipeline run 不必等待周期 snapshot reconcile 才收敛。
- **US-03 tools 维护者**：希望 archive 返回结构在 complete、cleanup-pending 和幂等重放时保持固定，以便 Skill、Pipeline 和测试只消费一套字段。
- **US-04 流程维护者**：希望 README 清楚区分“终态事实已发布”和“本地资源仍待清理”，以避免使用者因 `cleanup-pending` 手工删除尚未验证安全的资源。
- **US-05 后续 traceability 交付者**：希望本次小修不提前收紧 archive traceability gate，以免当前 generator 尚未产出的 tests/reviews/approval 结构阻断正常归档。

# 3. 功能需求

## FR-01 Archive 返回契约固定化

`crctl archive` 在 `phase=complete`、`phase=cleanup-pending` 以及已完成事务的幂等重放中，必须固定返回以下字段：

- `commit`：已由 origin 确认的真实 archive commit SHA；
- `lastCleanupError`：最近一次 cleanup 异常的结构化错误码；无异常时为 `null`；
- `remaining`：仍未清理且被保守保留的资源列表；无剩余时为空数组；
- `preservedRefs`：按既有规则保留的远端 requirement ref；无保留时为空数组；
- `recoverCommand`：可直接重跑的同一 `crctl archive` 命令。

返回字段必须取自现有 archive journal/事务结果，不建立第二份状态或错误账本。`commit` 必须随远端前进后的 rebuild 更新为最终被 origin 确认的 commit，不得返回已被替代的本地候选 SHA。

## FR-02 Cleanup 异常可见且可续跑

当 cleanup 抛出异常时，`archiveCr()` 必须保留既有语义：archive commit 已发布、CR status 已是终态、命令以业务结果 `phase=cleanup-pending` 返回且不回滚 authority。返回中的 `lastCleanupError` 必须暴露 journal 已记录的错误码；`recoverCommand` 必须可用于同一事务续跑。

当 cleanup 只因 dirty、unknown、未证明已合入等保守条件留下资源，而未抛出异常时，`remaining` 必须表达现场，`lastCleanupError` 为 `null`。调用者必须能区分“有待处理资源”和“cleanup 执行本身异常”两类 pending 原因。

## FR-03 正常归档发送既有 Archive Outbox

仅当 archive 的原始状态为 `writing-back`，且 archive commit 已被 origin 确认后，`cmdArchive()` 必须复用现有 outbox schema 发送一次事件：

- `event_kind=archive`；
- `cr_id=<当前 CR-ID>`；
- `from_status=writing-back`；
- `to_status=archived`；
- `trigger=cr-archive`；
- `commit_sha=<真实、最终、已确认的 archive commit SHA>`；
- `actor` 与 `occurred_at` 继续由现有 crctl identity/time 机制生成。

不得新增 `terminal` 事件、topic、schema v2 或 archive 专用 transport。事件继续使用 Multica 现有 `(cr_id, commit_sha, event_kind)` 幂等键；相同 archive 事务幂等重放不得生成第二个 archive outbox 文件。

## FR-04 Outbox 失败不反转 Git Authority

archive outbox 是可重建投影通道，Git commit 与 `_history.yml` 才是权威事实。outbox 写入失败时：

- 不得回滚、重建或重复发布 archive commit；
- archive 命令仍返回 `phase=complete` 或 `phase=cleanup-pending`；
- 返回 `warnings[]`，其中至少包含 `code=EMIT_FAILED` 与 `event_kind=archive`；
- 后续 snapshot reconcile 继续作为最终兜底。

outbox 发送必须发生在 origin 已确认之后，禁止用未发布或占位 commit SHA 生成 archive 事件。

## FR-05 提前终止状态不得重复发 Archive 事件

当 CR 原始状态为 `rejected` 或 `withdrawn` 时，archive 只执行现有账本搬移和安全 cleanup，不发送 `archive` 或第二个 `status` outbox。对应终态转换已由 `crctl advance` 发出完整 status 事件；归档阶段不得伪造 `writing-back -> archived`，也不得产生重复终态投影。

## FR-06 Multica 既有消费契约验证

Multica 侧只允许增加契约测试和必要的 CUSTOM 台账登记，不修改生产事件协议。测试必须证明现有消费者能够接收 FR-03 的事件，并完成以下行为：

- `archive` 被识别为已知 event kind；
- 以 `writing-back -> archived`、`trigger=cr-archive` 通过既有合法转换校验；
- CR 投影状态更新为 `archived`；
- feature-writeback 的活动 pipeline run 被结束；
- 同一 `(cr_id, commit_sha, event_kind)` 重放保持幂等。

若 Multica 生产代码无需修改，不得为测试方便新增 archive 分支或兼容层。任何 Multica 测试文件改动必须按该仓当时实际 `CUSTOM.md` 结构登记 CR-2026-032/TASK 追溯。

## FR-07 README 语义澄清

`../tools/README.md` 的 feature-writeback/archive 说明必须明确：

1. `archive` 先发布终态权威事实，再尝试安全清理本地和远端资源；
2. `cleanup-pending` 表示 status 已是终态，未完成的仅是资源清理；
3. 处理返回的 `remaining` / `lastCleanupError` 后，只能重跑同一 `recoverCommand`；
4. 不得手工删除 dirty、unknown、未证明已合入或被列入 `preservedRefs` 的资源。

README 只描述上述业务语义，不复制 worktree/ref 分类、ancestry 判断、lease push、journal phase 或 cleanup 算法。

## FR-08 范围与依赖锁定

本 CR 只实现来源方案的 ARC-03、ARC-04、ARC-05 和 T02。ARC-02 严格 traceability gate 必须保持现状：archive 仍只检查当前既有前置，不要求尚未由 baseline generator 生成的 tests/reviews/approval milestone 结构。后续只有在 TRA-03 generator 增强完成并以真实产物通过集成测试后，才能由独立 T10A/Traceability CR 启用严格 gate。

# 4. 非功能需求

- **幂等性**：同一 archive 事务首次成功可产生至多一个 `archive` outbox；幂等重放不得产生新 commit、事件或时间戳漂移。
- **可靠性**：archive authority 一经 origin 确认不得因 cleanup 或 outbox 失败回退；所有 pending 结果必须带真实 commit 与可执行恢复命令。
- **兼容性**：保持现有 `event_kind=archive` schema、Multica consumer、状态机和 `(cr_id, commit_sha, event_kind)` 幂等键；不要求数据库迁移。
- **可观测性**：cleanup 异常通过 `lastCleanupError` 返回，资源保留通过 `remaining/preservedRefs` 返回，投影通道失败通过 `warnings[]` 返回。
- **安全性**：继续遵守 clean 才删、unknown/dirty/未合入则保留的既有 cleanup 规则；本 CR 不放宽任何删除条件。
- **可测试性**：测试必须覆盖真实 archive commit SHA、cleanup fault、dirty pending、outbox 失败、正常归档发送、提前终止不发送和幂等重放。
- **复杂度边界**：复用现有 `emitOutboxEvent()`、archive journal 与事务模块；不新增依赖、通用事件发布器、第二套 archive 状态机或新事务模块。
- **跨平台性**：tools 的 archive/crctl 测试保持 Windows 与 Ubuntu CI 可运行；涉及文本读取继续按仓库规则规范化 CRLF。

# 5. 验收标准

- **AC-01**：正常归档首次执行返回 `phase=complete` 时，同时包含 `commit`、`lastCleanupError=null`、`remaining=[]`、`preservedRefs=[]` 和可执行 `recoverCommand`；返回的 `commit` 等于 origin trunk 中带 `AI-First-Op: archive` trailer 的真实 SHA。
- **AC-02**：注入 `archive-during-cleanup` fault 后，命令返回 `phase=cleanup-pending`、`status=archived`、非空 `lastCleanupError`、真实 `commit` 与 `recoverCommand`；重跑后只续 cleanup，不新增 archive commit。
- **AC-03**：制造 dirty CR worktree 时，命令返回 `cleanup-pending`，对应资源出现在 `remaining`，`lastCleanupError=null` 且现场未被删除；清理 dirty 内容后重跑可完成。
- **AC-04**：正常 `writing-back -> archived` 归档在 origin 确认后产生一个 outbox JSON，字段精确满足 FR-03，`commit_sha` 等于最终 archive commit SHA；同事务重跑 outbox 文件数量不增加。
- **AC-05**：模拟 outbox 写入失败时，origin archive commit 与四账本终态保持已发布，命令结果含 `warnings[{code: EMIT_FAILED, event_kind: archive}]`，且不新增补偿 commit。
- **AC-06**：`rejected` 与 `withdrawn` 归档均不产生 `event_kind=archive` 或第二个终态 status 事件，现有 `preservedRefs` 行为不变。
- **AC-07**：Multica 契约测试使用 FR-03 事件证明 CR 由 `writing-back` 投影为 `archived`，feature-writeback run 被结束；同一幂等键重复上报只处理一次。
- **AC-08**：README 明确“终态发布成功、cleanup 可 pending、处理后重跑同命令”，且未复制 cleanup 分类算法或建议手工删资源。
- **AC-09**：archive 前置仍未启用 ARC-02 严格 traceability 结构校验；仅有当前合法 traceability 文件的既有 fixture 和可归档 CR 不因本次改动被阻断。
- **AC-10**：现有 archive、crctl、Multica governance/daemon 相关测试不通过放宽断言获得绿灯；tools 的 `lint-prompts --mode enforce`、Skill/Agent contract、Pipeline JSON parse 和相关测试全部通过。
- **AC-11**：若 Multica 仅增加契约测试，则其 production code diff 为空；所有 Multica 改动按 `CUSTOM.md` 当前表格登记 CR-2026-032 与对应 TASK。

# 6. 成功指标

- 所有 `cleanup-pending` 结果都能仅凭命令 JSON 判断是资源保留还是 cleanup 异常，并获得同一事务恢复命令。
- 正常归档不再依赖周期 snapshot reconcile 才在 Multica 中显示 `archived`；archive outbox 可直接结束 feature-writeback pipeline run。
- archive/outbox/cleanup 任一失败路径均不产生重复 commit、重复终态事件或 authority 回退。
- README 中不再存在将 archive 发布与 cleanup 描述为单一全成全败动作的表述。
- 当前可归档 CR 的通过率不因尚未交付的严格 traceability schema 而下降。

# 7. 依赖与风险

- **依赖**：tools 当前 `archiveCr()` durable transaction、`emitOutboxEvent()` schema v1、Multica `knownEventKinds/archive -> applyStatus` 消费链、状态机合法转换 `writing-back -> archived`。
- **风险 R-01**：若 outbox 在 cleanup 后才发送，knowledge-base worktree 可能已删除。实现必须从 archive 事务结果和 installation workspace 发事件，不依赖已清理的 CR worktree。
- **风险 R-02**：若只用 `changed=true` 判断是否发事件，cleanup-pending 续跑可能重复发送。实现必须依据原始 archive 状态和持久化发送结果/确定性文件名保证首次发布后至多一次。
- **风险 R-03**：远端前进导致 archive commit rebuild 时，事件必须使用最终 confirmed SHA，否则 Multica 幂等账本会记录无权威对应的旧 SHA。
- **风险 R-04**：commit fallback 当前 archive subject 不匹配既有 `[cr] archive ...` 正则。本 CR 的正确路径是显式 outbox，不以改 commit subject 或依赖 fallback 代替 FR-03。
- **风险 R-05**：Multica 数据库测试在数据库不可达时可能整包 skip。契约测试结果必须确认目标测试真实执行，不得仅凭 `go test` exit 0 判定通过。

# 8. 范围排除

- 不实施 ARC-02，不校验 baseline traceability 当前 CR milestone、tests、reviews、approval 或 merge 的完整结构。
- 不修改 `writeback-traceability.mjs`、feedback、alignment、checkpoint 或 test record 链路。
- 不新增 `terminal`/`feedback` outbox、消息队列、topic、schema 版本、数据库迁移或新消费者。
- 不修改 rejected/withdrawn 的终态转换和既有 status outbox；不为其发送 archive 事件。
- 不改变 archive 四账本内容、commit trailer、lease push、远端 rebuild、clean/dirty/unknown 分类或 ref 保留规则。
- 不把 outbox 失败升级为 archive 失败，不自动回滚、revert 或重新打开 CR。
- 不重构 `crctl.mjs` 为通用事件发布框架，不新增 interface/factory/plugin。

# 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-13 | v0.1.0 | Ray | 初始草稿：冻结 ARC-03/04/05、T02 范围与验收，明确排除 ARC-02 |
