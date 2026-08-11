---
id: CR-2026-031-prd
type: PRD
cr-ref: CR-2026-031
title: crctl 执行层职责边界与 merge/workspace/writeback/archive 事务化（TCA-005/009/015/016 合并落地）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-11T17:17:53+08:00
updated: 2026-08-11T17:17:53+08:00
---

# 1. 概述

当前 CR 注册、workspace 创建/恢复/清理、跨仓 merge、merge finalize、writeback 和 archive 的关键 Git、账本与恢复步骤分散在 Pipeline、Skill 和 `crctl.mjs` 中。文本算法重复导致事实源漂移，进程中断后没有统一事务身份，部分远端发布无法可靠续跑，post-merge writeback 还可能落到错误 checkout。

本 CR 将这些执行职责收敛到 crctl：Agent 只路由意图，Pipeline 只编排节点，Skill 只做业务前置和一次深原语调用，版本化脚本只生成确定性 candidate。实现作为一个完整 CR 交付，约 12 个 TASK 在同一 requirement branch 内完成；本 CR 自身使用旧流程完成 merge/writeback/archive，下一 CR 起启用新协议。

# 2. 用户故事

- **US-01 执行平台维护者**：希望所有状态、账本、Git/workspace 和恢复动作由一个可测试入口拥有，以便修复一次即可覆盖所有 Pipeline/Skill 调用。
- **US-02 需求/开发负责人**：希望注册、merge、writeback、archive 重跑时自动识别已完成副作用，以便进程崩溃或单仓失败后继续而不重复分配 CR-ID 或覆盖不属于本事务的资源。
- **US-03 代码审批人**：希望审批绑定明确的 source SHA 和 PRD/SDD/TASK 内容摘要，以便 merge/writeback 不会消费审批后漂移的内容。
- **US-04 平台运营者**：希望 post-merge 写入固定 Transaction Workspace，并能看到 archive cleanup-pending，以便业务终态与运维清理状态分离且可追踪。
- **US-05 工具开发者**：希望事务公共能力保持小而具体，以便在没有真实复杂度证据前不引入通用 saga、插件系统或第三方依赖。

# 3. 功能需求

## FR-01 职责边界与公共入口

crctl 必须独占状态/gate、CAS、账本写入、审计、Git/workspace 事务和恢复；Pipeline/Skill 不得复制这些算法。对外提供幂等深原语 `register`、`merge`、`workspace ensure/inspect/cleanup`、`writeback-apply`、`archive`，并删除已被替代的 `cr-init`、`worktree-path`、`merge-metadata`、`archive-move` 和确认无消费者的冗余命令。不得新增 npm 依赖、数据库、消息队列、分布式锁或通用事务框架。

## FR-02 durable transaction 基础能力

新增最多两个内部模块：`durable-tx.mjs` 和 `workspace-transactions.mjs`。前者提供公共 journal envelope、原子目录锁、recoverable write-set、fsync/rename、fault injection、blob 清理；后者保留 `registerCr`、`ensureWorkspace`、`mergeCr`、`applyWriteback`、`archiveCr` 等具体函数。公共 envelope 必须带 `v/txId/op/cr/phase/graphDigest/inputDigest/sideEffects/commit/lastError`，并按 Git trailer 支持 journal 丢失后的恢复。

## FR-03 注册和 workspace 幂等

`crctl register` 必须以 `registration_key` 幂等：同 key 重跑复用 CR-ID 和 txId，不同 key 可创建相同业务输入的不同 CR；输入摘要变化返回 `REGISTRATION_INPUT_MISMATCH`。注册失败 roll-forward，保留健康资源并只补齐缺失仓。workspace 按 `missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered` 分类，未知或 dirty 资源不得自动删除。

## FR-04 跨仓 merge 可恢复

`crctl merge` 必须先零副作用 prepare，再按单仓 ref CAS 发布，远端副作用后持久化 intent/observation，并通过 `confirmed|pushable|rebuild|history-rewritten` 分类续跑。merge source 必须读取 signed release snapshot 的 approved SHA。部分发布保持 `code-approved` 并暴露 txId、sideEffects 和 recoverCommand，不自动 revert、reset 或 force。

## FR-05 merge finalize 与 authority handoff

所有参与仓确认后，crctl 在固定 knowledge-base Transaction Workspace 生成一次 finalize commit，原子包含 `cr.md` 状态、完整 merge metadata、机器生成的 `merge-verification.md` 和必要事件。origin 确认后将该 detached workspace 作为 `operational_workspace` 交给 writeback；CR worktree 只读，用户主 checkout 不参与 authority 选择。

## FR-06 release snapshot

`crctl review-record --stage code` 必须从真实已推送 ref/worktree 注入不可由模型 payload 覆盖的 `code.yml#release-subjects`：逐仓 reviewed source SHA，以及 CRLF 规范化、路径排序后的 PRD/SDD/plan/TASK 集合 digest。approve-code 重新核对 ref/HEAD/artifact，一致后原样复制到 signed `approval.yml#code.release-subjects`；漂移返回 `RELEASE_SUBJECT_DRIFT` 且零写入。merge/writeback 只消费 signed snapshot。

## FR-07 writeback candidate/apply

固定 stage 脚本只生成 candidate manifest 和 content-addressed blobs，不直接修改 baseline。`writeback-apply` 只接受 `baseline|tasks|traceability`，校验 signed snapshot、inputDigest、generator SHA、allowlist、before/after/blob hash 和精确 staged set。manifest v1 仅支持受控 create/replace，不支持 delete/rename/chmod/executable bit；origin trunk 在未发布前进时重新生成 candidate，不 rebase/cherry-pick。

## FR-08 archive 与 cleanup

`crctl archive` 是唯一归档入口，自动续跑状态转换、四账本/archive event、commit/lease push 和资源清理。archive commit 经 origin 确认后 `archived` 不回退；cleanup 失败返回 `CR_ARCHIVE_CLEANUP_PENDING`，同一命令只续跑 cleanup。成功 archived 只删除已证明合入 trunk 的 clean worktree/ref；rejected/withdrawn 保留未合并远端 ref，并输出 `preservedRefs`。删除 Skill 的 `cleanup_branch` 开关和模型生成 cleanup report。

## FR-09 安全与路径约束

删除伪造 caller 授权承诺和公开 `--caller`；所有 destructive 操作由 crctl 按 graph containment、realpath、固定 ref/路径和操作前置校验。锁使用本机原子目录 + token/pid/hostname，无 TTL/force unlock；foreign hostname 或无法证明 owner 时保守阻断。Installation Workspace 不承诺跨主机共享锁。

## FR-10 升级边界

新增临时只读 `crctl upgrade-check`，从 origin trunk 和 active repo remote refs 分类 `safe/requiresReapproval/blocksUpgrade`。没有 release snapshot 且已 partial merge/merging/writing-back 的旧 CR 阻止激活新协议；零 publish 的旧 code-approved 可回退 developing 重审。所有新协议 CR 必须有 signed snapshot。协议切换后删除 upgrade-check 及对应测试。

# 4. 非功能需求

- **可靠性**：在 rename、commit、push、finalize、cleanup 任一 fault point 强制退出后，重启必须能 confirmed、continue 或 hard block，不得静默当作成功。
- **幂等性**：重复 register/merge/writeback/archive 不重复 CR-ID、事件、metadata、commit 或 outbox；已确认阶段返回 `changed=false` 或 cleanup continuation。
- **安全性**：所有路径 workspace-relative 且受 containment；manifest 禁止绝对路径、`..`、symlink parent、任意 blob 和未声明文件。
- **可审计性**：事务 commit 带 `AI-First-Op/Tx/CR` trailer；journal 丢失时可结合 remote refs、ancestry、release snapshot 重建；冲突不得猜测。
- **兼容性**：目标账本最低版本为 `cr-backlog/v2`；v1 只返回 `UNSUPPORTED_BACKLOG_SCHEMA`。关键 fault vectors 覆盖 Windows 与 Ubuntu。
- **复杂度边界**：不引入通用 saga/phase engine/handler registry/plugin；只有至少三个真实处理器出现同一非平凡控制逻辑或相同恢复缺陷时，才评估从 `durable-tx.mjs` 提炼最小 runner，并登记 CUSTOM-TODO-008。

# 5. 验收标准

- **AC-01**：静态 contract 检查证明 Agent/Pipeline/Skill 不再拥有 Git、账本、workspace 或恢复算法；所有 active 调用通过指定 crctl 深原语。
- **AC-02**：三仓真实 bare remote 测试覆盖 prepare 冲突、第二仓 push 失败、push 后 kill、finalize stale 和重跑；结果均包含 txId、phase、sideEffects 和 recoverCommand。
- **AC-03**：同 registration key 在 CR-ID 分配、commit、push、任意第 N 个 worktree 失败后重跑，复用原 CR-ID 并只补齐缺失资源；输入变化硬失败。
- **AC-04**：真实 rename 前后 kill + restart 的 write-set 测试证明 after/before/第三值分别 redo、跳过或 `TX_RECOVERY_CONFLICT`，不会误覆盖第三方修改。
- **AC-05**：代码评审记录后、approve 前任一 ref/artifact 漂移返回 `RELEASE_SUBJECT_DRIFT`，approval.yml/cr.md 零写入；审批后的 source/TASK drift按统一回退规则处理，PRD/SDD drift返回 `APPROVED_ARTIFACT_DRIFT`。
- **AC-06**：candidate manifest 对 absolute/`..`/反斜杠/乱序重复 path、symlink、tx 外 blob、hash mismatch、delete/rename/chmod 均 hard fail 且 staged set 为空。
- **AC-07**：writeback candidate 准备后 trunk 前进时，未发布 stage 从新 detached HEAD 重新生成；已发布 commit 从远端历史消失返回 `WRITEBACK_REMOTE_HISTORY_REWRITTEN`。
- **AC-08**：archive commit 发布确认后 cleanup 失败保持 `archived`，返回 `CR_ARCHIVE_CLEANUP_PENDING`；重跑不重复账本/事件；rejected/withdrawn 未合并远端 ref 在 `preservedRefs` 中保留。
- **AC-09**：lock 测试覆盖存活进程、同机崩溃、PID 复用、foreign hostname、token mismatch；无 TTL 和 force unlock。
- **AC-10**：`upgrade-check` 零写入并正确区分 safe/requiresReapproval/blocksUpgrade；协议切换后可删除该临时命令及测试。
- **AC-11**：`lint-prompts --mode enforce`、skill/agent/pipeline contract、crctl tests、writeback tests 和 JSON parse 全部通过；CI 同时覆盖 Ubuntu/Windows 关键事务向量。
- **AC-12**：本 CR 以单一 requirement branch 交付，约 12 个 TASK 即时登记 done；不使用 feature flag、compat wrapper 或双写，本 CR 自身由旧流程完成 merge/writeback/archive。

# 6. 成功指标

- merge、register、writeback、archive 的失败现场均可由机器输出恢复命令和结构化副作用，不再依赖模型读取文本推断。
- active Pipeline/Skill 中 Git/worktree/账本算法复制为零；`crctl.mjs` 删除冗余入口和旧兼容代码后净缩短。
- 重跑成功率以真实 fault-injection matrix 衡量：所有承诺的零副作用、roll-forward、hard-block 场景均有可执行测试。
- post-merge writeback 错误 checkout 和状态/metadata 分裂提交在 contract/integration 测试中为零。

# 7. 范围排除

- 不实现跨多个 remote 的真正原子提交；只实现单仓 ref CAS 和跨仓可恢复 saga。
- 不引入数据库、队列、分布式锁、通用 saga、插件系统、第三个事务模块或新的 YAML 账本。
- 不在本 CR 中实现未来 rejected/withdrawn 远端 ref 删除管理命令。
- 不把 PRD/SDD 内容判断、LLM review、CUSTOM.md 语义判断下沉到 crctl。
- 不自动 reset/stash 用户 checkout，不删除无法证明归属的 worktree/ref。
- 不为 backlog v1 保留永久迁移兼容；旧 workspace 由旧 tools 迁移后再升级。
