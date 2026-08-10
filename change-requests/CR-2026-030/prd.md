---
id: CR-2026-030-prd
type: PRD
cr-ref: CR-2026-030
title: tools TCA-001～004 最小优化 - 注册、移交、审批驳回与开发计划评审契约收敛
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-11T01:29:00+08:00"
updated: "2026-08-11T01:29:00+08:00"
---

# PRD - tools TCA-001～004 最小优化

## 1. 概述

### 1.1 问题陈述

`docs/analysis/tools-text-contract-audit.md` 识别出的 TCA-001～004，在 `../tools@cab3663e224c7198d954b4d25bee5f4a8803a452`（`custom/main`）和 `../multica@c8c96e56a4bae1a2fb84c5700cffec174631ef74`（`main`）核对基线中均成立。现有测试虽全部通过，但关键入口没有兑现 Skill、Pipeline、状态机与平台审批链已经声明的契约：

1. Registration 声明三角色 Owner，实际 `cr-init` 只接收 requirement Owner 并复制到 development/test；Pipeline 还暴露底层忽略的 `cr_id`。
2. 正式移交描述要求更新 `cr.md`、backlog、历史与通知，实际 `owner-set` 只写 backlog；`resume-from-remote` 又附带 Owner 写入，形成第二业务入口。
3. 平台已经生成并投递 Ed25519 v1 grant，但 `reject` 在归属、证据和签名完整验证前即被拒绝，无法执行状态机已有驳回回退。
4. `review-dev-plan` 使用短 trigger `review-dev-plan:block`，而权威状态机要求精确字面量 `review-dev-plan:block -> write-dev-plan`，运行时必然拒绝；现有 R7 又无法静态发现该错误。

这些问题属于现有入口与现有权威契约不一致，不需要增加新编排层、第二审批协议或通用账本框架。继续补文案而不修入口，会让注册 Owner、正式移交、人工驳回和开发计划评审在真实执行中持续漂移。

### 1.2 目标

本 CR 以最小修改让现有入口兑现既有契约：

1. Registration 一次接收并原子写入三角色 Owner，注册提交成功后才以真实 SHA 产生注册事实。
2. `handover-cr` 成为正式移交唯一业务入口，`owner-set` 成为一致写入、提交和事件投影的受控账本原语。
3. approve/reject 复用现有 v1 签名 grant，reject 完整验证后执行状态机已有回退，并支持紧邻结果状态幂等重放。
4. `review-dev-plan` 独占两个状态命令并使用权威 trigger，Pipeline 仅承担三路路由与既有重放。
5. R7 直接消费权威状态机转移声明，静态拦截可确定的错误 `--to/--trigger` 字面量。

### 1.3 事实基线

| 编号 | 已核实事实 | 依据 |
|---|---|---|
| B-1 | 基线检查为 `lint-prompts 0 findings`、57 个 active Skill 通过、9 Agent contract 通过、Pipeline JSON 通过、crctl 189/189 测试通过 | 优化方案 §3 |
| B-2 | `cr-init` 当前只接收 `--owner-requirement`，并将同一值复制到三个 Owner | crctl 当前实现与本 CR 注册实录 |
| B-3 | `cmdOwnerSet()` 当前只更新 `_backlog.yml`，未兑现双投影、历史、提交和通知契约 | TCA-002 核对 |
| B-4 | 平台已有 Ed25519 v1 grant、默认落点与 `crctl approve --grant`，缺口仅在 reject 验证和回退 | TCA-003 核对 |
| B-5 | 状态机权威 NORMAL trigger 为 `review-dev-plan:block -> write-dev-plan`，`findTransition()` 精确匹配 | tools `dir-graph.yaml` 与 crctl 当前实现 |
| B-6 | 当前 R7 只检查 `advance` 是否带 `--to/--trigger`，不校验字面量是否存在于状态机 | `lint-prompts.mjs` 当前实现 |
| B-7 | 当前没有 Pipeline Runner 保证平台签名 approve/reject 分派到对应 `approve-*` Skill | 优化方案 §6.1 |
| B-8 | Multica 尚未消费 owners/inbox 注册投影，本 CR 不修改 Multica 源码 | `CUSTOM-TODO-003/004/005` 边界 |

### 1.4 契约优先级与版本口径

本 PRD 以 `docs/analysis/tools-tca-001-004-optimization-plan.md` 的已确认实施边界为需求输入；状态机、门禁、权限和 grant v1 结构仍以 tools 仓权威文件为准。PRD、后续 SDD 或实现不得复制一份状态机、grant 协议或 Git 路径算法作为第二事实源。

`target-version: tbd` 表示该变更尚未绑定产品发布版本，不表示允许省略验收或回写版本。后续人工审批可保持 `tbd`，不得为通过门禁虚构产品版本。

## 2. 用户故事

- **US-1** 作为 CR 注册执行者，我希望一次显式提供 requirement、development、test 三个 Owner，使注册结果与 Pipeline 输入一致，即使三者是同一人也没有隐式继承。
- **US-2** 作为后续 Pipeline 节点，我希望只消费原语返回的 Owner、branch、path 和真实提交 SHA，避免模型拼接不存在的执行事实。
- **US-3** 作为 CR 责任移交者，我希望正式移交同时更新权威双投影、唯一责任历史和通知事实，并在远端包含该提交后才宣称完成。
- **US-4** 作为接手远端 CR 的执行者，我希望恢复 worktree 只恢复权威状态，不在恢复过程中隐式改变责任归属。
- **US-5** 作为平台审批人，我希望签名 reject 与 approve 一样经过归属、状态、证据和签名验证，并让合法驳回回到现有回修状态。
- **US-6** 作为 Pipeline 编排者，我希望区分“人工驳回已成功回退”和“技术执行失败”，以便中止当前正向流程而不伪装成系统故障。
- **US-7** 作为开发计划评审执行者，我希望 PASS、NORMAL、UPSTREAM 三路结果稳定对应继续、普通回修和上游设计回退。
- **US-8** 作为 tools 维护者，我希望错误的静态 trigger 在 lint 阶段被发现，且校验直接使用权威状态机声明。

## 3. 功能需求

### FR-1 三角色原子注册

`crctl cr-init` 必须显式要求 `--owner-requirement`、`--owner-development`、`--owner-test`。缺少任一参数时返回参数错误且对 `cr.md`、`_backlog.yml`、`_index.yml` 零写入；不得保留把 requirement Owner 复制给其他角色的兼容路径。

同一次注册必须生成一个时间戳，并复用于三处当前 Owner 与三条 `reason=initial-assignment` 的 `owner-history`。顶层兼容字段 `owner` 恒等于 `owners.requirement.id`。三文件继续由一次 `casWriteMulti()` 原子写入，CR-ID 分配和并发冲突语义保持不变。

`cr-init` 成功返回必须至少包含 `cr`、`status`、完整三角色 `owners` 与三个文件路径。其成功 audit 可记录完整 Owner 投影和三项初始变化；不得记录尚不存在的 branch、worktree、commit SHA 或 outbox 成功事实。`cr-init` 不产生注册 outbox。

### FR-2 注册提交、执行上下文与失败边界

`requirement-register` 在 `cr-init` 后必须调用 `crctl git commit --template register --cr <CR-ID>`。只有 commit 成功后，受控 Git 原语才读取真实 HEAD SHA 与 `cr.md` 权威 Owner，并以同一 SHA 尝试产生：

1. `event_kind=status`：`(new) -> drafting`；
2. `event_kind=owners`：完整三角色当前投影与三项 `reason=initial-assignment` 的 `changes[]`。

commit 失败不得产生注册事件；outbox 失败不得回滚已成功 commit，必须返回 `warnings[]` 并记录 `EMIT_FAILED` audit。

`crctl worktree-path` 必须返回 canonical `branch`、`bucket`、`path`。Skill 只能汇总 `cr-init`、register commit 与 `worktree-path` 的真实返回；不得读取 HEAD、拼 branch/path/SHA 或构造事件。全部 push/worktree 步骤成功后才输出 `execution_context`，至少包含 CR-ID、status、owners、branch、registration commit、knowledge-base worktree 与所有参与仓 worktree 映射。

三文件 CAS 成功即永久占用 CR-ID。后续 commit、push 或 worktree 创建失败时返回 `REGISTRATION_INCOMPLETE`，包含 `cr_id`、`failed_step`、`completed_steps`、`commit_sha`、`created_worktrees`、`warnings`；不得输出成功上下文、回收 CR-ID或再次调用 `cr-init`。单仓 fetch 失败可沿用 `STALE_BASE` warning；真正的 worktree 创建失败必须中止。

### FR-3 Owner 双投影与唯一责任历史

`owner-set <cr_id> --role <requirement|development|test> --id <new-owner> [--note <text>]` 保留命令名，作为本地可信环境中的受控账本原语。写入前必须校验 `cr.md` 与 `_backlog.yml` 的三个当前 Owner 以及顶层兼容 `owner` 一致；任一漂移均返回结构化错误并零写入，不自动修复。

真实变化必须只生成一次时间戳，并复用于两处 `owners.{role}`、requirement 角色的两处顶层 `owner`、`cr.md#owner-history`、backlog 通知事实、audit 和 outbox。`cr.md#owner-history` 是唯一责任历史，只追加一条 `reason=formal-handover` 的 `role/from/to/at` 记录，可选 `note` 仅进入该历史和 inbox 通知事实。`handover-history` 停止新增，仅兼容读取；backlog 不复制责任历史。

候选 `cr.md` 和 `_backlog.yml` 必须由一次 `casWriteMulti()` 写入；backlog 同批追加 `owner-handover` notify-log 与 notify-pending。同值重放在双投影一致且无未提交移交残留时返回 `changed=false`，不得更新时间、历史、通知、audit、commit 或 outbox。

### FR-4 正式移交唯一入口与恢复只读

`handover-cr` 是正式移交唯一业务入口，固定顺序为 `owner-set -> push-progress`。删除 `skip_push`；只有远端包含 Owner 变更提交才算移交完成。push 失败保留本地正式移交 commit，传播现有结构化错误并由 Pipeline 中止。

`resume-from-remote` 必须删除 `new_owner`、`new_owner_role` 及所有 Owner 写入，只负责恢复 worktree、读取权威状态与调用 `crctl next`。`inbox-emit` 继续服务其他通知场景，不删除。

`owner-set` 不使用 `identity(ws)` 伪造“当前 Owner/admin/force”强授权判断；本 CR 只保证本地可信环境中的受控账本一致性，不宣称提供对抗恶意调用者的平台身份认证。

### FR-5 Owner 提交、回滚与事件投影

`owner-set` 对 `cr.md` 与 `_backlog.yml` 的真实变化形成一次正式 commit。只有 commit 成功才记录成功 audit，并以同一真实 SHA 分别尝试：

1. `event_kind=owners`：完整三角色当前投影与本次一个 `reason=formal-handover` 的 change；
2. `event_kind=inbox`：`event=owner-handover`、收件人与结构化移交事实。

`crctl` 不生成 `subject/body` 等展示文案。outbox 失败只返回 warning 并记录 `EMIT_FAILED`，不回滚 commit、也不阻止后续发布；本地写出 outbox 不等于 Multica 已应用 Owner 或完成通知触达。

若 Git add/commit 可观测失败，必须以新内容 hash 为 CAS 前提恢复两个原始快照，并重新暂存恢复后的文件、清除本次 staged 差异。成功恢复返回 `OWNER_COMMIT_FAILED/changed=false/rolled_back=true`；恢复 CAS 或重新暂存失败返回 `OWNER_COMMIT_ROLLBACK_FAILED` 并列出受影响文件。两种结果都必须中止，禁止进入 `push-progress`。

### FR-6 签名 grant 双模式与 reject 完整验证

四个 `approve-*` Skill 必须保留双模式：平台非 TTY 使用默认 grant 落点并调用 `crctl approve <cr> --stage <stage> --grant`；本地独立 CLI 无 grant 时继续要求当前 TTY。Pipeline 不拼 grant 路径、不复制 CLI 算法。grant 缺失、签名错误、归属不符、证据漂移或技术投递失败均为技术失败，必须中止且不得模型代签或直接 advance。

`approveWithGrant()` 对 approve/reject 共用以下前置验证：schema v1 与 decision 枚举、`cr_id/stage` 归属、当前状态或合法紧邻结果状态、当前 evidence digest、key 与 Ed25519 signature。reject 不执行 approve 路径的 passCondition，因为 blocker 是合法驳回原因。

验证成功的 reject 必须复用现有四阶段 `REJECT_ROLLBACK` 与权威状态机 trigger，回退成功后返回结构化非零业务结果 `APPROVAL_DECLINED_ROLLED_BACK`，包含 decision、stage、rolledBackTo、trigger、changed。该结果表示人工决定已捕获且回退成功，必须中止当前正向 Pipeline；不得伪装为 `EXEC_FAILED`、`CAS_CONFLICT` 等技术失败，也不得返回 `rerunHint`、下一 Skill 指令或手写 review annotation 文案。

### FR-7 approve/reject 紧邻结果态幂等

approve 在审批前置态时正常验证并推进；当前状态正好等于该阶段 approve 目标态，且 `approval.yml` 中 `approver/key-id/signature/grant-approved-at/evidence-digest` 与输入完全一致时返回成功 `changed=false`。进入其他状态或持久化字段不一致时返回 `GRANT_STATE_MISMATCH`。

reject 在审批前置态时正常验证并回退；当前状态正好等于该阶段 reject 回退目标态，且 grant 归属、当前 evidence digest 与签名仍有效时再次返回 `APPROVAL_DECLINED_ROLLED_BACK/changed=false`。进入其他状态时返回 `GRANT_STATE_MISMATCH`。

两个幂等分支均不得重复 audit、commit 或 outbox；reject 不新增第二份持久化审批账本，不把未签名 `reject_reason` 写入 Git、Skill 输入或事件。

### FR-8 开发计划评审三路路由

`review-dev-plan` Skill 是两个状态命令的唯一拥有者，并输出三路结构化结果：

1. **PASS**：仅当 `verdict=pass && blockers=[]`，不推进状态，保持 `task-breakdown`，返回 `route=pass`，Pipeline 继续。
2. **NORMAL**：使用 `--to tech-design-reviewed --trigger "review-dev-plan:block -> write-dev-plan" --expect task-breakdown --embedded`，成功后返回 `route=normal`、`verdict=block` 和 `review_feedback`。Pipeline 仅按现有 `maxAttempts=3` 重放 `write-dev-plan -> write-dev-tasks -> review-dev-plan`，耗尽沿用 `LOOP_EXHAUSTED`，不得进入人工审批。
3. **UPSTREAM**：使用 `--to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker --expect task-breakdown --embedded`，成功回退后返回结构化非零业务结果 `UPSTREAM_DESIGN_BLOCKER`，包含 route、verdict、review feedback 和回退状态。当前 coding Pipeline 必须立即中止，不进入 NORMAL reviewLoop，也不增加 NORMAL attempt。

Pipeline prompt 必须删除上述两个具体 `crctl advance` 命令，只保留 PASS/NORMAL/UPSTREAM 路由、`replayNodes` 和失败中止语义。

### FR-9 R7 权威 trigger 字面量校验

现有 `lint-prompts.mjs` R7 必须读取 tools `dir-graph.yaml#change-request-track.state_machine.transitions`。输入先规范化 `\r\n -> \n`；跨行或结构解析失败必须硬失败，禁止退化为空 transitions。

对 Skill 中可静态确定的 `crctl advance --to <literal> --trigger <literal>`，R7 必须验证 `(to, trigger)` 至少匹配一条权威转移。包含模板变量的值跳过；不从自然语言或文件位置推断 `from`，运行时完整合法性继续由 `crctl advance` 裁决。不得复制状态机常量或给旧短 trigger 增加兼容别名。

### FR-10 Skill、Pipeline 与人读契约同步

在不改变节点数量的前提下同步以下当前入口：

- `requirement-register` 使用三 Owner 参数并汇总权威 execution context；`requirement-authoring.pipeline.json` 删除无效 `cr_id` 和命令复制。
- `handover-cr` 收敛为 `owner-set -> push-progress`；`resume-from-remote` 删除 Owner 输入与写入。
- 四个 `approve-*` Skill 区分平台 grant、本地 TTY、业务 reject 与技术失败；相关 Pipeline 只传递决定并在失败时中止。
- `review-dev-plan` 持有两个精确 advance；`code-implementation.pipeline.json` 只保留路由与 replay。
- `README.md`、`AGENTS.md`、`ARCHITECTURE.md` 仅修正失真的当前契约，不新增第二事实源或未交付自动化描述。

Pipeline 节点数量保持不变，不修改 Pipeline `_index.yml#nodes`。本 CR 不修改 CI workflow。

## 4. 非功能需求

- **NFR-1（最小设计）**：不新增 `owner-handover`、注册聚合巨型命令、恢复子命令、Pipeline Runner、数据库、WAL、通用 YAML 框架、grant v2、rejection 文件或 crctl 模块拆分。
- **NFR-2（权威来源）**：状态机、门禁、权限、grant v1 和 Git branch/path 算法继续使用现有权威文件或原语；Skill/Pipeline/README 不复制可执行规则。
- **NFR-3（原子与失败安全）**：受控账本继续使用 CAS；跨行解析失败硬失败；可观测 Git 失败按 FR-5 恢复，禁止静默部分成功。
- **NFR-4（安全边界诚实）**：不把本地 `identity(ws)` 或 Owner 字段描述为强认证身份，不宣称 outbox 写出等于平台投影应用或通知触达。
- **NFR-5（兼容性）**：现有 approve 成功路径、本地 TTY 模式、状态机转移、`inbox-emit` 其他调用方、Pipeline 节点数量和既有 CI 入口不得回归。
- **NFR-6（零新增依赖）**：实现复用 Node 标准库、现有 YAML 解析、Ed25519 grant、`casWriteMulti()`、controlled-shell 与 node:test，不新增第三方依赖或测试框架。
- **NFR-7（行尾纪律）**：读取 YAML 或做跨行正则前统一 `\r\n -> \n`，逐行解析使用 `split(/\r?\n/)`；CRLF 与 LF 行为等价，解析不完整时必须失败并报告原因。

## 5. 验收标准

### 5.1 Registration

- **AC-1（FR-1）**：传入三个不同 Owner 时，`cr.md`、backlog、audit 与返回 JSON 中三角色值一致；顶层 `owner` 仅等于 requirement Owner，三条 initial history 使用同一时间戳。
- **AC-2（FR-1）**：缺任一 Owner 返回参数错误，`cr.md`、backlog、index 与 audit/outbox 均无新增。
- **AC-3（FR-1/FR-2）**：`cr-init` 不发 outbox；register commit 成功后使用真实 HEAD SHA 产生一条 status 与一条 owners 事件，两者 SHA 相同且 owners 事件含三个 change。
- **AC-4（FR-2）**：registration commit 失败不产生事件；outbox 任一写出失败时 commit 仍成功，返回 warning 并存在 `EMIT_FAILED` audit。
- **AC-5（FR-2）**：`worktree-path` 返回 branch/bucket/path；Skill 输出的 execution context 中对应值逐项等于原语返回，Skill/Pipeline 中不存在 branch/path/SHA/event 手工拼接。
- **AC-6（FR-2）**：commit、push 或 worktree 创建失败返回 `REGISTRATION_INCOMPLETE`，不输出成功上下文、不分配第二个 CR-ID，并准确列出完成步骤与已创建 worktree。

### 5.2 正式移交

- **AC-7（FR-3）**：双投影一致时才允许变更或同值幂等；任一角色或顶层兼容 owner 漂移时零写入并返回结构化错误。
- **AC-8（FR-3）**：真实变化只追加一条 `owner-history`，不追加 `handover-history`；requirement 移交同步两处兼容 `owner`，note 只进入 owner-history 与 inbox 事实。
- **AC-9（FR-3）**：Owner、history、notify-log、notify-pending 使用同一时间戳，`cr.md` 与 backlog 由一次 `casWriteMulti()` 提交候选内容。
- **AC-10（FR-3/FR-4）**：同值重放不产生时间、历史、通知、audit、commit 或 outbox，但 `handover-cr` 仍进入 `push-progress` 以发布可能已存在的 commit。
- **AC-11（FR-4）**：`handover-cr` 无 `skip_push`，固定执行 `owner-set -> push-progress`；push 失败保留本地 commit 并明确返回未完成，不能输出移交完成。
- **AC-12（FR-4）**：`resume-from-remote` 的输入、正文和执行路径均无 `new_owner/new_owner_role` 或 Owner 写入；恢复后只读取状态并调用 `crctl next`。
- **AC-13（FR-5）**：commit 成功后以同一真实 SHA 尝试 owners + inbox 两类 outbox；payload 无 `subject/body`，owners payload 含完整三角色投影且仅一个 formal-handover change。
- **AC-14（FR-5）**：outbox 失败不回滚 commit、不阻止发布；Git add/commit 失败时成功恢复原快照与 staged 状态并返回 `OWNER_COMMIT_FAILED`。
- **AC-15（FR-5）**：注入恢复 CAS 冲突或重新暂存失败时返回 `OWNER_COMMIT_ROLLBACK_FAILED` 和受影响文件，且不调用 `push-progress`。

### 5.3 签名审批

- **AC-16（FR-6）**：四个 stage 的 approve grant 均可正常推进；本地无 grant 调用仍要求 TTY，Pipeline 中无 grant 默认路径或 CLI 拼接。
- **AC-17（FR-6）**：四个 stage 的 reject 仅在 schema、decision、归属、状态、evidence digest、key 和签名全部有效后执行权威回退。
- **AC-18（FR-6）**：伪造签名、跨 CR/stage 挪用、证据漂移、错误状态均零写入且返回对应技术错误；不执行回退。
- **AC-19（FR-6）**：合法 reject 返回 `APPROVAL_DECLINED_ROLLED_BACK`，包含目标状态与权威 trigger，无 `rerunHint`、下一 Skill、未签名 reason 或手写 review annotation。
- **AC-20（FR-7）**：approve 在紧邻目标态且持久化字段完全一致时 `changed=false`；reject 在紧邻回退态且 grant/evidence/signature 仍有效时返回 `APPROVAL_DECLINED_ROLLED_BACK/changed=false`。
- **AC-21（FR-7）**：approve/reject 进入其他状态或 approve 持久化字段不一致时返回 `GRANT_STATE_MISMATCH`；幂等分支不重复 audit、commit 或 outbox。

### 5.4 开发计划路由与静态检查

- **AC-22（FR-8）**：PASS 仅在 `verdict=pass && blockers=[]` 成立，保持 `task-breakdown` 并继续后续节点。
- **AC-23（FR-8）**：NORMAL 使用完整 trigger 从 `task-breakdown` 回到 `tech-design-reviewed`，只进入现有三节点 replay，最多三轮；短 trigger 在运行时仍被拒绝。
- **AC-24（FR-8）**：UPSTREAM 使用权威 trigger 回到 `tech-design-review-pending`，返回 `UPSTREAM_DESIGN_BLOCKER` 并中止 coding Pipeline，不进入 NORMAL replay 或增加 NORMAL attempt。
- **AC-25（FR-8/FR-10）**：`review-dev-plan` Skill 中存在两个具体 advance；Pipeline 中不存在这两个命令，只存在 route、replayNodes 与 abort 语义；Pipeline 节点数量不变。
- **AC-26（FR-9）**：R7 对完整 NORMAL trigger 通过，对短 trigger 输出 `CONTRADICTS`；校验从当前 `dir-graph.yaml` transitions 读取，不含复制常量或兼容别名。
- **AC-27（FR-9/NFR-7）**：同一 fixture 的 CRLF/LF 输入结果等价；transitions 跨行或结构解析失败时 lint 硬失败，不允许空数组继续。
- **AC-28（FR-9）**：含模板变量的 `--to/--trigger` 被明确跳过；静态 literal 仅校验 `(to, trigger)` 至少命中一条声明，不从自然语言推断 from。

### 5.5 全量回归

- **AC-29（FR-10）**：相关 Skill、四个 Pipeline 模板和人读契约与本 PRD 一致，不描述 CUSTOM-TODO-001～006 为已交付；Multica 代码 diff 为空，CI workflow 无修改。
- **AC-30（全局）**：以下命令全部通过：

```bash
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));"
```

审批跨接缝测试复用 Multica 现有 Go -> crctl 测试设施增加 reject 向量，不新建集成框架。

## 6. 成功指标

- **注册契约一致性**：三个不同 Owner 在注册双投影、初始历史、audit、结构化返回和注册事件中无差异；注册事件使用真实提交 SHA。
- **正式移交一致性**：任一成功移交只有一条责任历史、一个权威 commit 和同 SHA 的 owners/inbox 投影尝试；不存在恢复流程附带 Owner 写入。
- **审批决定可消费**：四阶段合法签名 reject 均能完成权威回退，伪造/挪用/漂移向量全部零写入；重放不重复副作用。
- **开发计划路由可执行**：PASS、NORMAL、UPSTREAM 三路均有黑盒覆盖，NORMAL 完整 trigger 可执行，短 trigger 在 lint 与运行时均被拦截。
- **治理无新增分叉**：无新状态、无第二 grant 协议、无第二 Owner 历史、无 Runner/WAL/数据库/新依赖；Pipeline 节点数与 CI 入口保持不变。

## 7. 范围排除

- 不新增 `owner-handover` 命令、注册聚合巨型命令或恢复子命令。
- 不新增 Pipeline Runner、数据库、WAL、通用 YAML 框架、grant v2 或 rejection 文件。
- 不实现跨进程自动续跑 incomplete registration；保留 `CUSTOM-TODO-006`。
- 不实现可信 `reject_reason` 传输与 Runner 注入；保留 `CUSTOM-TODO-001/002`。
- 不修改 Multica 源码，不实现 owners/inbox 消费或 registration reconcile；保留 `CUSTOM-TODO-003/004/005`。
- 不宣称 outbox 写出等于平台 Owner 投影已应用或通知已触达。
- 不删除仍被其他流程使用的 `inbox-emit`。
- 不修改 CI workflow，不拆分 `crctl.mjs`。
- 不治理 TCA-005 及之后问题，不扩展为 tools 全量文本契约审计。
- 不为 Owner 字段或本地 `identity(ws)` 增加伪造的强授权语义。
- 不解决 `casWriteMulti()` 逐个 rename 之间进程直接崩溃的极端窗口；后续一致性检查必须暴露脏文件。

## 8. 风险与约束

1. `owner-set` 的 Git add/commit 回滚只覆盖可观测失败，无法覆盖进程在账本写入后直接崩溃；本 CR 以一致性检查暴露该状态，不引入 WAL。
2. grant reject 回退依赖当前状态机与 evidence digest；评审或状态已继续推进后，旧 grant 必须拒绝而不是猜测恢复路径。
3. R7 是静态字面量守卫，只能校验可确定的 `(to, trigger)`；模板变量与完整 from 合法性仍由运行时裁决。
4. outbox 是非阻断投影通道；消费者故障时 Git 仍是权威事实，平台需要后续 reconcile 能力。
5. 当前没有 Pipeline Runner，Skill/Pipeline 文档只能收敛契约，不能宣称平台端自动分派已交付。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-11 | v0.1.0 | Ray | 初始草稿：承接 TCA-001～004 优化方案，形成 10 条 FR、7 条 NFR、30 条 AC |
