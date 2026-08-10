---
id: CR-2026-027-prd
type: PRD
cr-ref: CR-2026-027
title: tools 流程优化 Phase 0+1 — 基线事实统一与正确性修复（状态机口径 27/49、approve 原子提交、TASK 归档门禁、archive 原子化、终态查询、review-record 深化）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-09T22:20:00+08:00"
updated: "2026-08-09T22:20:00+08:00"
---

# PRD — tools 流程优化 Phase 0+1：基线事实统一与正确性修复

## 1. 概述

### 1.1 问题陈述

CR-2026-026 对 tools 全生命周期实际演练后，操作记录暴露的共性问题不是 LLM 语义能力不足，而是 LLM 同时承担了过多确定性职责（搜索 Skill/仓库路径、解析 worktree/trunk/Git 历史、拼接 Shell 命令、手工生成 frontmatter/索引/账本投影、推进状态、重复核对 crctl 刚写入的证据、根据历史 CR 猜测 schema、临时编写补丁脚本）。`docs/analysis/tools流程步骤优化v2.md`（下称 v2 方案）据此定义了从基线统一到 Merge/Writeback/Archive 的候选演进路线。

**当前必须先解决的基线冲突与真实故障**：

1. 状态机口径冲突：`../tools/dir-graph.yaml` 实测 27 条声明转换（wildcard 展开 49 条），但 workspace `AGENTS.md`、`../tools/ARCHITECTURE.md` 前文仍写 25/47 旧口径；`ARCHITECTURE.md` 内部前后矛盾（§8 维护记录已写 27/49）。
2. `crctl approve` 的 approval 与 status 被拆成不同 Git 提交，可能留下单文件半状态（CR-2026-026 实测）。
3. 归档无 TASK 的 CR 会被 `deliveryIndexComplete` 误判为「无任务」放行归档。
4. CR-2026-026 实测：`inbox-emit` 因中文 JSON Shell 转义失败后，后续归档继续执行，事件永久丢失。
5. `archive-move` 已承诺但遗漏 `_index.yml` 更新（CR-2026-024~026 归档后 `_index.yml` 仍显示 `drafting`）；且 `_backlog.yml` 遗留 CR-2026-024 缺 `- id:` 行的幽灵条目（静默污染 CR-2026-017 条目字段，本 CR 注册期实测确认）。
6. 归档后 `resolveCrState` 强制从 backlog 找 CR，`status/next` 返回 `CR_STATUS_NOT_FOUND`。
7. review Skill 在 `review-record` 成功后重新读取 traceability 核对刚写入的投影；dev-plan 需要 route/repair-target 但命令未返回。
8. `merge-feature-branch` 通过 prose 硬编码 tools 仓特例，违反「所有参与仓来自机器可读声明」（tools 已参与 10 个历史归档 CR，但 workspace `repositories` 只声明 docs 与 multica）。

**问题边界**：本 CR 只做基线统一与正确性修复，不引入 Runner 框架，不实施 Phase 2+ 任何候选路线。

### 1.2 解决方案摘要

按 v2 方案分两阶段实施：

- **Phase 0 基线统一**：状态机口径全量统一为 27 声明/49 wildcard 展开；确认 crctl 保持单文件；修订 crctl 与 Pipeline 依赖描述；拍板并落地 archive `_index.yml` 全生命周期轻量目录语义；将 tools 声明为 workspace active repository 并删除 merge Skill 隐藏特例；删除旧方案中的 command module 与通用上下文命令描述；建立优化指标基线。**实施首步为 tools 仓一次性 bootstrap（D-12/FR-15）**：tools 声明入 repositories 后从 custom/main 补建 `requirement/CR-2026-027` worktree，全部 `../tools` 改动落在该分支，禁止直写 custom/main。
- **Phase 1 正确性修复**：`crctl approve` 两文件 CAS + 单次提交原子化；archived TASK 完成门禁（禁止隐式 no-task）；archive 事件与 backlog/history/index 同一 CAS 原子移动（收件人复用 owners，普通 `inbox-emit` 空 `--to` 硬失败）；归档残留幽灵条目的版本化迁移清理；终态只读 status/next 查询；review-record 输出 files/attempt/route/repairTarget 并删除 review Skill 的 traceability 二次读取。
- **验证**：按 v2 方案 §6.6 五项最小清单执行，不预跑无关测试族。

### 1.3 事实基线（来源：v2 方案与质询记录，均已核实）

| # | 事实 | 依据 |
|---|---|---|
| B-1 | `../tools/dir-graph.yaml` 当前 15 个具名状态 + 注册前 `(new)`；27 条声明转换；wildcard 展开后 49 条 | v2 §2.1；本 CR 注册期 grep 复核 |
| B-2 | workspace `AGENTS.md`、`../tools/ARCHITECTURE.md` §3/§5 仍为 25/47 旧口径；ARCHITECTURE §8 已写 27/49（前后矛盾） | v2 §2.1；质询记录 §1.1 |
| B-3 | workspace `CONTEXT.md` 状态机口径已修正为 27/49 并新增 7 个相关术语（CR 阶段文档、specs 基线、CR 目录索引、CR 参与仓、归档事件、CR 终态查询、正常归档与提前终止） | 质询记录 §1.1（已随 CR-2026-027 注册前置提交入库） |
| B-4 | `ARCHITECTURE.md` 规定 crctl.mjs 刻意保持单文件；旧版优化方案提出 `crctl/scripts/commands/*.mjs` | v2 §2.2 |
| B-5 | `ARCHITECTURE.md` 声称 crctl 不依赖 Pipeline，但实现已通过 Pipeline 的 reviewLoop/passCondition 执行 gate | v2 §2.3 |
| B-6 | `cmdArchiveMove` 只原子写 `_backlog.yml` 与 `_history.yml`，未同步 `_index.yml`；cr-archive Skill 声称会同步（承诺未兑现） | 质询记录 §1.6 |
| B-7 | `_index.yml` 保留全部历史 CR 条目，早期归档条目标记 `status: archived`、`archived-at`、`writeback-spec-id`；`cr-query`/`cr-show`/`cr-dashboard` 均以 `_backlog.yml + _history.yml` 为查询事实源，不从 `_index.yml` 读状态；Multica 无读取 `_index.yml` 的运行时代码 | 质询记录 §1.6 |
| B-8 | `resolveCrState` 强制先从 backlog 加载条目，归档后 status/next 均返回 `CR_STATUS_NOT_FOUND` | 质询记录 Q6 |
| B-9 | `cmdApprove` 先写 approval 再调用 `cmdAdvance`；`cmdAdvance` 普通提交只 stage `cr.md`，approval/status 分提交 | 质询记录 Q4 |
| B-10 | `deliveryIndexComplete` 在 task index 缺失或所有 TASK pending 时得到空 doneIds 并放行；状态机证明正常 archived 必经 task-breakdown/developing，developing 已要求 task index + 非空 TASK；20 个现有归档 CR 全部有任务 | 质询记录 Q8 |
| B-11 | `merge-feature-branch` 明文承认 tools 不在 workspace repositories 声明范围，却以 `custom/main` 特例参与；tools 已参与 10 个历史归档 CR | 质询记录 Q3；workspace `dir-graph.yaml` 实测 |
| B-12 | `_backlog.yml` 尾部存在 CR-2026-024 幽灵条目（缺 `- id:` 行，HEAD 即存在）；crctl 自研 YAML 解析器对重复 key 静默覆盖，该条目被解析为 CR-2026-017 的续行字段，覆盖其 title/summary/owners/created/updated；`_history.yml` 中 CR-2026-024 有完整归档条目 | 本 CR 注册期实测 |
| B-13 | `inbox-emit` 当前允许缺失或空 `--to` 写入 notify-log，与 Skill 契约（`to` 必填）不一致；历史 21 条归档记录均有三角色 owners | 质询记录 Q10 |
| B-14 | 四个 review Skill 在 review-record 成功后重新读取 traceability 核对刚写入投影；dev-plan 需要 route/repair-target 但当前命令未返回 | v2 §6.5 |
| B-15 | `../tools/skills/writeback/scripts/lib.mjs` 已提供 LF 规范化、结构化输出、hash/diff、frontmatter 定点处理、参数解析和账本路径保护，有回归测试；engineering-docs 历史 validator 依赖 Ajv/gray-matter/yaml 且 schema 与 CR 阶段 PRD 不兼容 | 质询记录 §1.3/§1.4 |
| B-16 | Multica 尚无真正 Pipeline Runner；`pipeline_node_run` 只是 crctl 事件流投影；typed outputs 与 `.crctl/runs` 协议本轮不定义 | 质询记录 §1.5 |

### 1.4 决策点（质询记录 Q1~Q10 已拍板，本 PRD 承接为实施约束）

| # | 决策点 | 拍板结果 | 理由 |
|---|---|---|---|
| D-1 | Phase 2~6 承诺强度 | 全部为**候选路线**；本 CR 只承诺 Phase 0/1；PRD Runner 试点需 Phase 0/1 完成后重新确认并另写 Spec | Q1：按证据逐项晋升，不预先批准文件布局/JSON schema/公共 API/retry mode |
| D-2 | archive `_index.yml` 语义 | **全生命周期轻量目录**；归档时由 `archive-move` 与 backlog/history 同一 `casWriteMulti` 更新条目（只写 `status`/`archived-at`/可选 `writeback-spec-id`）；不复制 history 详情、不新增 `history-ref`、不删除条目、不升级为查询事实源 | Q2：现有证据（历史条目保留+已标终态、消费者不读 index）最支持 |
| D-3 | 可写仓来源 | **所有 active repo 参与每个 CR，全部来自 repositories 声明**；tools 加入 workspace repositories（`path: "../tools"`、`trunk: custom/main`、`role: code`）；删除 merge Skill tools 特例；本轮不新增每 CR 仓库选择字段 | Q3：先消除隐藏特例，不建第二套参与模型 |
| D-4 | approve 原子性边界 | **两文件 CAS + 单次 commit**：预检后在内存生成 approval.yml 与目标 status cr.md → casWriteMulti → crctl git add 两文件 → 单次 commit → 成功后发 status outbox；TTY/grant 共用内部 approve-and-advance helper；gate/CAS 失败零写入；commit 失败两文件共同留存不发 outbox；拒绝路径复用现有合法 reject 转换 | Q4：复用现有 CAS，不新增事务框架/WAL |
| D-5 | 归档事件原子性边界 | **archive event 进入 archive-move CAS**：embedded advance 到终态后，archive-move 在内存构造事件（复用 editInboxEmit），与 backlog/history/index 同一 `casWriteMulti`；CAS 成功后发 archive outbox；不新增 `--payload-file`、幂等键或新命令 | Q5：事件与归档要么同生要么同灭 |
| D-6 | 归档 CR 只读查询 | **新增仅供 status/next 的终态只读 resolver**：history `final-status` 为权威；输出 `terminal:true`、`legalNext:[]`、`next:null`；写命令继续用 active resolver；backlog/history 同存同 CR 报 `CR_LOCATION_CONFLICT`；history 重复或缺 final-status 硬失败；cr.md 漂移仅告警；不新增命令与归档字段 | Q6：最小只读契约 |
| D-7 | review-record 返回契约 | 新增 `files[]`、`attempt.{current,max,bumped}`、`route`、`repairTarget`；保留 `file`/`trace` 兼容；files 只列实际写入；删除 review Skill traceability 二次读取；不返回 verified/subject digest/next | Q7：只补真实消费者字段 |
| D-8 | TASK 归档门禁 | **正常归档不允许隐式 no-task**：index 必须存在、tasks 非空、任一非 done → `TASK_STATUS_INCOMPLETE`、全 done 后校验 delivery index；rejected/withdrawn 不走 archived 门禁；archive-move `--final-status` 必须与 cr.md 当前 status 完全一致；不新增 no-task 标志与 task reconcile；历史数据修复用一次性版本化迁移脚本 | Q8：缺文件/空数组不得解释为 no-task |
| D-9 | Phase 0/1 最小修改与验证集合 | 修改核心 = workspace dir-graph/AGENTS、tools ARCHITECTURE、crctl.mjs 与 crctl.test.mjs；只修改确有过时指令的 merge/archive/review Skill 与 feature-writeback pipeline；不改 gates、matrix/index、approve Skill、engineering-docs、writeback scripts 或检查器本身；只运行 diff-check、pipeline JSON parse、crctl tests、lint-prompts enforce 与两项 grep | Q9：改什么测什么，不预跑无关测试族 |
| D-10 | 归档事件收件人 | 取 requirement/development/test owner ID 去重；legacy 缺 owners 回退顶层 owner；最终为空 → CAS 前 `ARCHIVE_RECIPIENTS_MISSING`；普通 `inbox-emit` 缺失/非列表/空 `--to` 一律 `BAD_ARGS`；不新增身份字段 | Q10：复用 owners 模型 |
| D-11 | 幽灵条目清理 | 本 CR 内以**一次性版本化迁移命令**清理 `_backlog.yml` 尾部缺 `- id:` 条目（CR-2026-024 已归档于 `_history.yml`）：扩展既有 `crctl migrate-backlog` 增加幽灵块检测/删除（幂等，`already-clean`），不新增独立脚本目录（ARCHITECTURE §6 否决账本操作脚本库）；修复未来归档行为仍由 D-5 的 archive-move CAS 保证 | B-12 实测 + v2 §6.2 历史数据修复口径；落点拍板 2026-08-09（SDD v0.2.0 方案） |
| D-12 | tools 仓 bootstrap | **注册后一次性补偿**：tools 加入 repositories 声明后，从 custom/main 为本 CR 创建 `requirement/CR-2026-027` worktree，此后全部 `../tools` 改动落在该分支，禁止直写 custom/main；该补偿不等同于每 CR 仓库选择模型，不新增注册字段 | 需求评审 Blocker：本 CR 注册时 tools 未声明，但必须修改 `../tools` 文件（ARCHITECTURE、crctl、merge/archive/review Skill、迁移脚本与测试） |
| D-13 | target-version 口径 | **维持 `tbd` 并声明批准口径**：本 CR 属 tools 正确性修复，不绑定产品发布版本号序列；target-version 在需求审批时确认，不进入产品版本号递增链路 | 需求评审 Suggestion：避免 tbd 无解释 |
| D-14 | post-PASS 设计修订与 next freshness | reviewLoop 的 `maxAttempts=3` 约束单个审查周期内的 block→repair；已 PASS 后因 dev-plan upstream blocker 修订 SDD 时自动开启新 cycle（不新增命令）：保留旧 attempts 审计、`current-cycle+1`、新 cycle 从 attempt=1 开始。`crctl next` 必须检查 SDD subject digest 与较新的 upstream blocker，旧 PASS 不得直接建议审批 | review-dev-plan 上游回退实测：SDD v0.5.0 晚于旧 PASS/审批，next 仍误报 approve-tech-design，且旧 cycle 已 3/3 |

## 2. 用户故事

- **US-1** 作为 tools 包维护者，当我读任何权威文档时，状态机口径（27 声明/49 展开）全库一致，不再需要自己辨别哪个是现状。
- **US-2** 作为 CR 流程执行者，当我在 TTY 或经 `--grant` 审批时，approval 与状态推进落在同一个提交里，任何失败都不会留下「审批已写但状态未动」的半状态。
- **US-3** 作为归档执行者，归档时事件、backlog/history/index 三账本同批原子写入，不会出现「事件已发但未归档」或「已归档但事件丢失」；`_index.yml` 不再停在 `drafting`。
- **US-4** 作为归档执行者，归档已结束的 CR 后仍能查询其 status/next（终态只读），不会得到 `CR_STATUS_NOT_FOUND`。
- **US-5** 作为归档审批方，任何 TASK 未完成的 CR 都无法以 `archived` 结束；「没有 TASK」不再被误读为「无任务可查」。
- **US-6** 作为 review Skill 调用方，`review-record` 一次返回实际写入文件、attempt 与 route/repairTarget，我不再需要重新读取 traceability 核对刚写入的结果。
- **US-7** 作为参与仓消费者，所有可写仓（含 tools）都来自 `dir-graph.yaml#repositories` 机器可读声明，不存在只写在 prose 里的隐藏特例。

## 3. 功能需求

### Phase 0 — 基线统一

- **FR-1（状态机口径统一）**：状态机事实以 `../tools/dir-graph.yaml` 为准；修正 workspace `AGENTS.md` 与 `../tools/ARCHITECTURE.md` 前文中的 25/47 旧表述为 27 条声明/49 条 wildcard 展开；统一后所有文档、断言、测试注释引用状态机数量时必须写明 declared 或 wildcard-expanded 口径；统一完成前新代码不得硬编码转换数量。
- **FR-2（crctl 单文件边界确认）**：`ARCHITECTURE.md` 明确本轮维持 crctl.mjs 单文件，不创建 `crctl/scripts/commands/` 模块目录；删除旧版优化方案中的 command module 描述；若未来需要模块化必须独立立项并先修改 ARCHITECTURE。
- **FR-3（crctl 与 Pipeline 依赖描述修订）**：`ARCHITECTURE.md` 按以下准确描述修订：crctl 不执行 Skill、不依赖 Skill 自然语言语义；crctl 可读取 dir-graph、gates 与 Pipeline 中的声明式 gate/reviewLoop 配置；Pipeline 不得调用 crctl 之外的账本写入口。
- **FR-4（archive `_index.yml` 生命周期语义落地）**：在 `ARCHITECTURE.md` 与相关文档固化 D-2 语义（全生命周期轻量目录：归档时同批 CAS 更新 `status`/`archived-at`/可选 `writeback-spec-id`；不复制 history 详情、不新增 `history-ref`、不删除条目、不成为查询或状态事实源）；该语义与 §6.3a 行为实现一致。
- **FR-5（tools 声明为参与仓）**：workspace `dir-graph.yaml#repositories` 新增 `{id: tools, path: "../tools", trunk: custom/main, role: code, active: true}`；删除 `merge-feature-branch` Skill 中「tools 不在声明但特殊参与」的 prose 与实现分支；注册、同步、合并、清理只遍历 repositories。
- **FR-6（删除旧方案遗留描述）**：`docs/analysis/tools流程步骤优化v2.md` 中删除旧方案的 command module 目录描述与通用上下文 crctl 命令（`patch`/`run-workflow`/`stage-context`/`registration-check`/`register-preflight`）的描述，确保方案文档与拍板边界一致。
- **FR-7（优化指标基线）**：将 v2 方案 §16.2 的外部调用量目标表（注册 24→8-12、PRD 编写 9→3、implement-code 63→25-35 等）与 §16.1 正确性指标固化为 `ARCHITECTURE.md` 或文档中的基线记录，供 Phase 2+ 候选路线实施前对照；指标是观测值，不得通过删除 gate、测试、补偿或人工审批达成。
- **FR-15（tools worktree bootstrap）**：本 CR 实施的第一项动作：将 tools 加入 workspace `dir-graph.yaml#repositories`（D-3/FR-5）后，从 `../tools` 仓 custom/main 为本 CR 创建同名分支 worktree `requirement/CR-2026-027`（复用 `crctl worktree-path` 路径规则，bucket = `tools`）；fetch 失败按注册期 `STALE_BASE` 降级规则处理并在实施记录标注基线滞后；此后本 CR 对 `../tools` 的全部改动（ARCHITECTURE.md、crctl.mjs、crctl.test.mjs、merge/archive/review Skill、迁移脚本）一律落在该 worktree 分支，禁止直接在 custom/main 提交实施改动；merge/cleanup 阶段 tools 作为 active repo 走正常 merge-feature-branch 与 cr-archive 流程（含 tools 的 merge-commits 记录与 worktree 清理）。该 bootstrap 是注册时序（tools 当时未声明）的一次性补偿，不等同于新增每 CR 仓库选择模型。

### Phase 1 — 正确性修复

- **FR-8（approve 原子提交）**：`crctl approve` 改为预检（current state/transition/evidence/signature/passCondition/requireFiles）→ 内存生成 approval.yml 与目标 status 的 cr.md → 按候选 approval 复核目标 gate → `casWriteMulti(approval.yml, cr.md)` → `crctl git add` 两文件 → 单次 commit → commit 成功后发送 status outbox → audit 记录最终结果。TTY approve 与 `--grant` 共用内部 approve-and-advance helper；gate/签名/证据预检失败零文件写入；CAS 冲突两文件均不写；commit 失败两文件共同留在工作区并返回结构化恢复信息，不发 status outbox；拒绝路径不写批准段，继续复用现有合法 reject 转换；不新增 crctl 子命令、WAL 或通用事务框架。**受控历史审批迁移（代码评审二轮 b10、三轮回修）**：新增 `crctl approve --resign <reason>`（仅限交互式终端、人类在环无旁路）——gates.json evidence 定义变更（如 dev-start 剔除 task-index）导致既有 `via=crctl-approve` 审批段 digest 漂移报 EVIDENCE_DRIFT 时，按当前定义重算 digest 并只改写该段（保留 approver/approved-at/via/target-status），追加 resign 审计子块与 audit 事件，幂等（digest 已一致则 no-op）；`via=server-approve` 的签名绑定原 digest，本地 `--resign` 必须返回 `RESIGN_SERVER_APPROVAL_UNSUPPORTED`，由服务端按新 digest 重新签发 grant；不新增子命令，不改审批本体字段。
- **FR-9（archived TASK 完成门禁）**：`advance --to archived` 的任务门禁依次校验：① `tasks/_index.yml` 必须存在；② `tasks[]` 必须非空；③ 任一 TASK 非 done → `TASK_STATUS_INCOMPLETE`；④ 全部 done 后校验 `delivery/task/_index.yaml`；⑤ 缺文件、空数组不得被解释为 no-task。`rejected`/`withdrawn` 属提前终止，可在无 TASK/writeback 时进入 history，不走 archived 门禁；`archive-move` 接受当前状态 `archived|rejected|withdrawn`，且 `--final-status` 必须与当前 `cr.md` status 完全一致否则硬失败；不新增永久 `task reconcile` 命令与 no-task 标志。
- **FR-10（归档残留幽灵条目迁移清理）**：扩展既有 `crctl migrate-backlog` 子命令增加幽灵条目清理阶段（不新增独立脚本、不新增子命令）：删除 `_backlog.yml` 尾部缺 `- id:` 行的 CR-2026-024 幽灵条目块；删除依据为 `_history.yml` 中存在 CR-2026-024 完整归档条目（无对应归档时硬失败 `GHOST_ENTRY_ORPHANED`，不静默删除）；运行后 CR-2026-017 条目字段恢复完整；命令幂等（已清理时返回 `already-clean`），再次运行不得重复修改；行为纳入 crctl 测试覆盖（B-12 场景回归）。落点采用 SDD v0.2.0 方案（2026-08-09 拍板）：清理必须经 crctl（CAS + audit），因 ARCHITECTURE §6 否决 `skills/shared/scripts/` 账本操作脚本库。**审计时序（代码评审二轮 b10）**：幽灵清理的 `migrate-backlog-ghost removed:true` 审计事件必须在 casWrite 成功之后记录（先写盘、后审计），CAS_CONFLICT 时 `_backlog.yml` 保持不变且 audit.log 零成功记录。
- **FR-11（archive event 与账本移动原子化）**：`archive-move` 在内存构造 archive event（复用现有 editInboxEmit 逻辑写候选条目，富化 `final-status`/`archive-reason`/`writeback-spec-id`/`archived-at`），与 backlog→history 移动 + index 终态更新经同一 `casWriteMulti` 写入，CAS 成功后发送 archive outbox；任一 event/文件结构错误或 CAS 冲突时事件与三份账本均不写。收件人 `to = unique(owners.requirement.id, owners.development.id, owners.test.id)`；旧条目缺 owners 回退顶层 `owner`；最终为空则 CAS 前返回 `ARCHIVE_RECIPIENTS_MISSING`；不新增 submitter/reviewer 字段。普通 `inbox-emit` 同步修正：`--to` 缺失、解析后非列表或去重后为空均返回 `BAD_ARGS`，不得写入无收件人 notify-log。不新增 `inbox-emit --payload-file`、archive 专用幂等键或新命令。
- **FR-12（archived status 终态只读查询）**：新增仅供 `status`/`next` 使用的终态只读 resolver：active CR 继续从 cr.md/backlog 读取；archived/rejected/withdrawn 从 `_history.yml` 的 `final-status` 读取；输出最小契约含 `cr`/`status`/`terminal:true`/`source`/`legalNext:[]`/`reviewLoops:{}`/`gateBlockers:{}`/`next:null`；`crctl next` 对终态返回 `next:null` 不报错；写命令继续使用现有 active resolver，不允许终态写入；backlog/history 同时存在同一 CR 时 `CR_LOCATION_CONFLICT`；history 重复条目或缺 final-status 硬失败；cr.md 与 history 不一致时以 history 为准并输出 warning；不新增 archive reason/spec-id 等非必要返回字段，不新增 `archive-status` 命令。
- **FR-13（review-record 输出深化）**：`review-record` 保持现有 `file`、`trace` 字段兼容，并增加：`files[]`（只列本次实际写入文件，未 bump 时不得虚列 review-loop.yml）、`attempt.{current,max,bumped}`、`route`（`pass|repair|upstream`）、`repairTarget`（`write-requirement-prd|write-tech-design|write-dev-plan|implement-code|null`）；不返回 `verified`、subject digest、`next`（`next` 仍由 `crctl next` 唯一计算）。删除四个 review Skill 的「重新读取 traceability 核对刚写入结果」步骤，命令成功即表示三账本同批写入完成，调用方按 `files` 组织提交、按 `route` 分流、最后调用 `crctl next`。
- **FR-14（配置文件最小验证清单）**：Phase 0/1 实施完成的验证清单固定为五项：① `git diff --check`；② `JSON.parse(feature-writeback.pipeline.json)`；③ `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`；④ `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`；⑤ grep 核对 tools 隐藏特例与 25/47 旧表述已清零。不修改、不运行 agent-skill matrix 检查族、agents contract 检查族、writeback scripts 测试、engineering-docs 测试及新的 validate-config/schema/Runner；实施实际触及上述权威文件或代码时，按「改了什么测什么」追加对应检查。
- **FR-16（next 路由 freshness 与上游重入修复，CR-2026-026 遗留）**：
  1. `task-breakdown`：读取 canonical `review-annotations/dev-plan.yml`；缺失或 schema 不完整 → `next=review-dev-plan`；PASS（`verdict=pass && blockers=[]`）→ `next=crctl approve --stage dev-start`；BLOCK 时从 annotation 的 `verdict`/`blockers`/顶层 `repair-target` 调用共享 `resolveDevPlanRoute` 确定性重算，repair→`write-dev-plan`、upstream→`write-tech-design`，不得依赖上一条 `review-record` 命令的瞬时返回值；block 且本 cycle 已 `LOOP_EXHAUSTED` → `next=null`、`humanApproval=true` 并输出人工处理原因。
  2. `tech-design-review-pending`：`review-record --stage tech-design` 必须记录 `subject-file=sdd.md` 与 LF 规范化 `subject-sha256`；若当前 SDD digest 与 annotation 不一致，或存在 `reviewed-at` 晚于技术评审记录的 dev-plan upstream blocker，则 `next=review-tech-design`，不得按旧 PASS 建议 approve-tech-design。
  3. post-PASS 设计 revision：`review-record --stage tech-design --bump-attempt` 在“上一技术评审 PASS + 较新 dev-plan upstream blocker + SDD 已修订”时自动开启新 review cycle；`review-loop.yml`/traceability 在原 attempts 上增加 `cycle`，保留历史审计，新 cycle 从 attempt=1 计数。legacy attempt 无 `cycle` 视为 cycle=1；不新增子命令、不手改 review-loop。

## 4. 非功能需求

- **NFR-1（最小改造）**：不新增 CR 具名状态、审批 stage、独立账本类型、crctl 子命令、WAL 或通用事务框架；不创建 `commands/` 模块目录与 `skills/shared/runner/` 公共库。
- **NFR-2（确定性写入）**：approval/status、archive event/三账本的每次写入要么全部发生要么全部不发生；任一前置校验或 CAS 失败不得产生部分写入；commit 失败不得发送对应 outbox 事件。
- **NFR-3（行尾纪律）**：所有哈希、跨行正则、逐行解析与定点编辑先做 CRLF→LF 规范化；结构无法唯一定位时硬失败，禁止静默降级。
- **NFR-4（复用与不复制）**：不复制 `../tools/skills/writeback/scripts/lib.mjs` 已有能力（LF 规范化、结构化输出、hash/diff、frontmatter 定点处理、账本路径保护）；不恢复 engineering-docs MCP/CLI 与历史 Ajv/gray-matter/yaml validator；Phase 2+ 的共享 Runner 库晋升条件（两个真实 Runner + 语义相同重复 + 接口更少更稳 + 不复制 writeback 能力 + 调用方测试）不在本 CR 实施。
- **NFR-5（零新增第三方依赖）**：全部使用 `node:` 内置模块；测试仅用 `node:test`/`node:assert`。
- **NFR-6（兼容性）**：历史 CR 不要求新增证据文件（不批量迁移旧 approval/archive 形态）；rejected/withdrawn 的提前终止路径行为保持；`_index.yml` 不成为新查询事实源。
- **NFR-7（可审计）**：approve 原子路径与 archive-move 原子路径记录 audit 与 outbox 事件；失败路径输出结构化错误码（含恢复指引），不输出「请在终端运行」类手工指引。
- **NFR-8（不过度设计）**：不新增 typed outputs、`.crctl/runs` 协议、scope-change.yml、checkpoint kind 扩展、branch-base-set、register-preflight、registration-check、stage-context；所有 Phase 2+ 机制等待真实案例触发（v2 §12）。

## 5. 验收标准

### Phase 0

- **AC-1**（FR-1）：按固定范围与判定执行 grep 清零核对：范围 = workspace 根（AGENTS.md、CONTEXT.md、dir-graph.yaml）+ `../tools` 包（ARCHITECTURE.md、AGENTS.md、README.md、skills/、pipeline-templates/），排除 `docs/analysis/` 下明确标注「历史口径/CR-2026-022 后、CR-2026-026 前」的复盘类文档引用；判定 = 模式 `25\s*条声明|25/47|47\s*条` 的命中若上下文为「当前/现状」表述则计未清零，仅作历史注脚的命中不违规；全部状态机数量断言注明 declared/wildcard 口径。
- **AC-2**（FR-2）：`ARCHITECTURE.md` 与 v2 方案文档中不存在 `crctl/scripts/commands/` 或等价模块目录描述；crctl.mjs 仍为单文件。
- **AC-3**（FR-3）：`ARCHITECTURE.md` 的 crctl-Pipeline 依赖描述与实现一致（三句准确描述到位，无「不依赖 Pipeline」旧表述残留）。
- **AC-4**（FR-4/FR-11）：`ARCHITECTURE.md` 与 cr-archive 相关文档的 `_index.yml` 语义描述与实现一致（全生命周期轻量目录、三字段更新、不复制 history、不删除条目）。
- **AC-5**（FR-5）：workspace `dir-graph.yaml#repositories` 含 tools（path/trunk/role/active 四字段齐全）；`merge-feature-branch` Skill 及其实现中不存在 tools 硬编码特例分支；合并/同步路径只遍历 repositories。
- **AC-6**（FR-6）：v2 方案文档中不存在 command module 目录与五条通用上下文命令（patch/run-workflow/stage-context/registration-check/register-preflight）的实现描述。
- **AC-7**（FR-7）：优化指标基线（§16.1/§16.2）以表格形式固化于文档，含「不得通过删除 gate/测试/补偿/人工审批达成」约束。

### Phase 1

- **AC-8**（FR-8）：四个 stage 的 TTY approve 与 `--grant` 均一次提交（approval.yml 与 cr.md 同 commit），历史「下一阶段补提交 approval」行为消失。
- **AC-9**（FR-8）：gate/签名/证据预检失败时零文件写入；CAS 冲突时 approval.yml 与 cr.md 均不写；commit 失败时两文件共同保留在工作区且不发 status outbox。**AC-9b（代码评审二轮 b10）**：幽灵清理 CAS 冲突时零成功 `migrate-backlog-ghost` 审计记录（审计时序：先 casWrite 成功、后 auditLog）。
- **AC-10**（FR-8）：拒绝路径不写批准段，仍走现有合法 reject 转换（如 `approve-requirement:reject -> write-requirement-prd`）。**AC-10b（代码评审二轮 b10、三轮回修）**：`approve --resign` 非交互式调用一律 `APPROVAL_REQUIRES_HUMAN`（无旁路）；无既有审批段 → `RESIGN_NO_PRIOR_APPROVAL`；`server-approve` → `RESIGN_SERVER_APPROVAL_UNSUPPORTED` 且原段不变；本地审批 digest 已一致 → 幂等 no-op；本地审批真实 TTY 迁移后 gate 复绿，reason/approver 特殊字符保持单一 YAML 标量，且 CAS、审计与受控提交均有运行时证据。
- **AC-11**（FR-9）：构造「task index 存在但全部 pending」的 CR 执行 `advance --to archived`，返回 `TASK_STATUS_INCOMPLETE` 且不归档；构造「task index 缺失」同样被拦截，不得解释为 no-task。
- **AC-12**（FR-9）：TASK 全 done 但 `delivery/task/_index.yaml` 缺失时被拦截；全部就绪后正常归档；rejected/withdrawn 无 TASK 时可进入 history。
- **AC-13**（FR-9）：`archive-move --final-status` 与 cr.md 当前 status 不一致时硬失败。
- **AC-14**（FR-10）：运行 `crctl migrate-backlog` 后 `_backlog.yml` 幽灵条目消失、CR-2026-017 条目完整（title/summary/owners/created/updated 恢复）；再次运行返回 `already-clean` 且文件哈希不变。
- **AC-15**（FR-11）：归档时 inbox 事件与三账本同批写入；CAS 冲突或事件结构错误时事件与三账本均不写；中文 archive reason 不因 Shell 转义丢失；三角色收件人去重、legacy 顶层 owner 回退、空收件人 `ARCHIVE_RECIPIENTS_MISSING`、可选 spec-id、重复归档均按契约处理。
- **AC-16**（FR-11）：普通 `inbox-emit` 在 `--to` 缺失、非列表、去重后为空时返回 `BAD_ARGS`，不写无收件人 notify-log。
- **AC-17**（FR-12）：archived/rejected/withdrawn 三种终态 `crctl status` 返回终态与 `source: history`，`crctl next` 返回 `next:null` 不报错；backlog/history 同存同 CR 报 `CR_LOCATION_CONFLICT`；history 重复或缺 final-status 硬失败；cr.md 漂移输出 warning 且以 history 为准；active CR 查询行为不回归。
- **AC-18**（FR-13）：`review-record` 输出含 `files[]`/`attempt`/`route`/`repairTarget` 且与本次实际写入一致（未 bump 不虚列 review-loop.yml）；四个 review Skill 不再重新读取 traceability 核对刚写入结果；`next` 仍由 `crctl next` 唯一计算。
- **AC-19**（FR-14）：五项最小验证全部通过：① `git diff --check` 无告警；② `JSON.parse(feature-writeback.pipeline.json)` 通过；③ `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿；④ `lint-prompts.mjs --mode enforce` 零发现；⑤ 按 AC-1 的搜索范围与判定方式 grep 确认 tools 隐藏特例与 25/47「现状」表述已清零。
- **AC-22**（FR-15）：实施首步完成后：`../tools` 仓存在 `requirement/CR-2026-027` 分支与对应 worktree（基线 = custom/main HEAD）；`git log` 确认 custom/main 无本 CR 直接提交的实施改动；CR-2026-027 在 tools 的 merge-commits 记录与 docs/multica 同批生成（merge 阶段验收）；归档清理覆盖 tools worktree。
- **AC-23**（FR-16）：
  - `task-breakdown`：无/畸形 `dev-plan.yml` → `review-dev-plan`；PASS → `crctl approve --stage dev-start`；repair BLOCK → `write-dev-plan`；顶层 `repair-target=write-tech-design` → `write-tech-design`；block 且 cycle exhausted → `next:null` + 人工处理，不返回审批。
  - `tech-design-review-pending`：SDD digest 与旧 annotation 不一致，或较新的 dev-plan upstream blocker 存在 → `review-tech-design`；fresh PASS 才返回 `crctl approve --stage tech-design`。
  - 技术评审旧 cycle 已 3/3 且上一轮 PASS 时，post-PASS SDD revision 的首次 `--bump-attempt` 自动生成 cycle=2/attempt=1；旧 cycle attempts 完整保留，后续 cycle 内仍最多 3 次。
- **AC-20**（NFR-1/NFR-4/NFR-5）：不新增第三方依赖与公共 Runner 库；无通用 patch/workflow 实现；crctl.mjs 保持单文件；writeback scripts 未被复制。
- **AC-21**（NFR-6）：历史 CR 查询/归档行为兼容（旧 approval/archive 形态不要求迁移）；`_index.yml` 查询链路不变。

## 6. 成功指标

- **正确性**（§16.1）：状态和账本无旁路；approval 与 status 同一提交；TASK pending 不可回写/归档；archive event 不丢失；archived CR 可查询；所有参与仓来自机器可读声明；候选工具不通过隐藏路径治理当前 CR。
- **效率基线**（§16.2 观测值，不在本 CR 内考核达成）：以 v2 方案表格固化各阶段当前外部调用量（注册 24、PRD 编写 9、implement-code 63 等）与目标值（8-12、3、25-35 等），作为 Phase 2+ 候选路线的对照基线；不得通过删除 gate、测试、补偿或人工审批达成。
- **维护性**：已证明需要 Runner 的语义 Skill 最多 prepare/finalize 两个入口（本 CR 不引入）；无基于历史 CR 的 schema 推断；无会话临时账本脚本；现有 writeback scripts 得到复用。
- **数据健康**：`_backlog.yml` 无幽灵条目；归档 CR 的 `_index.yml` 终态字段与 history 一致。

## 7. 范围排除

**本 CR 包含**：Phase 0 文档/声明修改（workspace AGENTS.md、dir-graph.yaml、CONTEXT.md 复核、v2 方案文档、tools ARCHITECTURE.md、merge-feature-branch SKILL.md 特例删除）；**tools 仓 bootstrap worktree 派生与实施落地（D-12/FR-15/AC-22）**；Phase 1 crctl.mjs 与 crctl.test.mjs 修改（approve 原子化、TASK 门禁、archive-move 原子化、终态 resolver、review-record 输出）；migrate-backlog 扩展与幽灵条目清理（FR-10/D-11）；四个 review Skill 的 traceability 二次读取删除；按 §6.6 的五项最小验证。

**本 CR 不包含**（Phase 2+ 全部候选路线，须分别重新确认并另写 Spec）：
- PRD Runner 垂直试点（prepare/finalize、create/repair 双模式、CR PRD 最小确定性校验、typed outputs）。
- 最小公共能力与 Registration（`skills/shared/runner/lib.mjs`、requirement-register run.mjs、tools root 解析、repo context、checkpoint kind 扩展）。
- 其余 Authoring/Review Runner（requirement review、SDD、tech review、Plan/TASK、dev-plan review）。
- Implement/Test/Code Review Runner（implement prepare/finalize、`crctl test --plan`、test-report Runner、code review Runner、scope-change ledger）。
- Merge/Writeback/Archive Runner（merge run.mjs、writeback run.mjs、traceability prepare/finalize、archive run.mjs、cleanup-report、`merge-metadata --from result.json`）。
- 可选高级机制（control-plane SHA pin、永久 scope-change ledger、永久 task reconcile、writeback plan artifact、crctl 模块化、并行 remote push）。
- 不重新设计 CR 状态机业务流程、不删除 reviewLoop、不跳过人工审批、不引入数据库账本、不引入 YAML 第三方库、不建立通用 Workflow Engine、不自动实施 review suggestions、不一次性重写全部 Skills、不附带拆分 crctl.mjs。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于 v2 方案 §5-§6 与质询记录 Q1~Q10 转写；14 条 FR、8 条 NFR、21 条 AC；幽灵条目清理入范围 D-11/FR-10/AC-14） |
| 2026-08-09 | v0.2.0 | Ray | 修订（需求评审 BLOCK 回修，blocker=FR-5/AC-5 tools 仓引导缺失）：新增 D-12/FR-15/AC-22（tools worktree bootstrap——声明入 repositories 后从 custom/main 补建 requirement/CR-2026-027 分支，禁止直写 custom/main，merge/cleanup 走正常流程）；新增 D-13（target-version 维持 tbd 的批准口径说明）；按 suggestions 固定 AC-1/AC-19 的 grep 搜索范围与判定方式（历史注脚引用不违规）；§1.2/§7 同步 |
| 2026-08-09 | v0.3.0 | Ray | 拍板同步（用户决策 2026-08-09）：FR-10/D-11 落点从 skills/shared/scripts/ 迁移脚本改为 crctl migrate-backlog 扩展（SDD v0.2.0 方案），消除 PRD/SDD 冲突；AC-14 验收语义不变 |
| 2026-08-09 | v0.4.0 | Ray | 修订（review-tech-design 二轮 BLOCK 回修，TD2-BL-1）：AC-14 字面同步为“运行 `crctl migrate-backlog` 后”，清除“迁移脚本”残留（验收语义不变） |
| 2026-08-09 | v0.5.0 | Ray | 范围确认（用户决策 2026-08-09）：纳入 CR-2026-026 遗留缺陷——next task-breakdown 路由缺 dev-plan.yml 检查（实测导致无评审记录时误报 approve dev-start）；新增 FR-16/AC-23，归属 TASK-07 |
| 2026-08-09 | v0.6.0 | Ray | 上游回修（review-dev-plan UPSTREAM BLOCK）：扩展 D-14/FR-16/AC-23，补 task-breakdown route 的 canonical 来源、tech-design SDD freshness、upstream 重入与 post-PASS 新 review cycle；旧 cycle attempts 保留审计，不新增子命令 |
| 2026-08-10 | v0.6.1 | Ray | 代码评审二轮 BLOCK 回修（b10）：FR-8/AC-10b 新增受控历史审批迁移 `approve --resign <reason>`（TTY 人类在环、只重签 digest、保留审批本体、resign 审计子块、幂等）；FR-10/AC-9b 幽灵清理审计时序修正（先 casWrite 成功、后 auditLog，CAS_CONFLICT 零成功记录）；SDD v0.6.1 同步 |
| 2026-08-10 | v0.6.2 | Ray | 代码评审三轮 BLOCK 回修：FR-8/AC-10b 收紧为只迁移 `crctl-approve`；`server-approve` 必须服务端重签；补 YAML 安全标量、真实 TTY 成功路径与真实 CAS_CONFLICT 运行时验收。 |
