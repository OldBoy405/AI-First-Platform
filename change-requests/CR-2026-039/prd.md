---
id: CR-2026-039-prd
type: PRD
cr-ref: CR-2026-039
title: tools CR 生命周期最小优化 2/5 — 生命周期证据规范化
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-15T00:21:07+08:00
updated: 2026-08-15T00:21:07+08:00
---

# 1. 概述

《tools-cr-lifecycle-minimal-optimization-spec.md》（下称"规格"）将 tools 包的生命周期治理拆为 5 条实施 CR。本 CR 是第 2 条"生命周期证据规范化"，落实规格 FR-04、FR-05、FR-06、FR-09，解决四类"评审/审批证据与实际受控内容脱节"的真实漏洞：

1. **代码评审 PASS 后、人工审批前无 checkpoint（规格 FR-04 / P0-04）**：`code-implementation.pipeline.json` 现状是 write-test-report → push-progress（node-8）→ review-code（node-9）→ 直接进入 approve-code 人工审批，review-code PASS 与审批之间没有 checkpoint。评审结论只证明"评审时刻"的代码合格；PASS 后未 push 的窗口内，人工审批按 release-subjects 重核远端时可能看到与评审结论不一致的内容。
2. **dev-plan PASS 未绑定被评审正文（规格 FR-05 / P1-01 / TRA-06）**：`crctl review-record` 已为 requirement（prd.md）与 tech-design（sdd.md）写入单文件 `subject-sha256`，但 dev-plan 阶段不写 digest，`crctl next` 对 dev-plan 仅有 upstream-blocker 时间戳逻辑——plan.md 或任一 TASK-*.md 在 PASS 后被修改，旧 PASS 仍可被 approve-dev-start 消费。
3. **cr.md 时间字段双轨（规格 FR-06 / P1-02）**：注册写 `updated`（workspace-transactions.mjs），状态推进的 `crMdStatusText` 只替换**已存在**的 `updated-at` 行——新格式 CR 推进后时间字段实际不刷新，且读侧面对两个语义相同的字段。
4. **review canonical 合同漂移（规格 FR-09 / P1-04）**：`crctl review-record` 实际产出的 canonical 字段是 verdict/blockers/suggestions/dimensions（+ dev-plan block 轨的 repair-target），但四个 pipeline 模板与多个 Skill 引用 canonical annotation 中不存在的 `repair-instructions`、`fixed-blockers`，并存在 `suggestion_policy strict|lenient` 与首轮 suggestion 升格规则——这些文本契约没有实现支撑。

**解法**：全部复用现有深原语，不新建任何账本、schema 或框架——

- 在 code Pipeline review-code PASS 后插入现有 `push-progress`（即一次 `crctl checkpoint` 调用，CR-2026-033 已收敛为单一深原语），phase 非 complete 即中止，不进入人工审批；
- `review-record --stage dev-plan` 复用现有 digest helper 计算 plan.md + 排序 TASK-*.md 的 composite digest，写入现有 `subject-sha256` 字段；`crctl next` 与 approve-dev-start 消费 PASS 前重算；
- cr.md 时间字段 writer 统一写 `updated`，reader 兼容期接受旧 `updated-at`，正常写入时渐进收敛，不批量迁移；
- review canonical 字段收敛为 verdict/blockers/suggestions/dimensions/可选 repair-target，删除 `repair-instructions`、`fixed-blockers`、`suggestion_policy` 的全部文本契约与升格规则。

**依赖与顺序**：复用 CR-2026-031 durable transaction 与 CR-2026-033 checkpoint 深原语（均已合入本规格核对基线 `tools@origin/custom/main` `7b73204`）；与 CR-2026-038（Writeback 原子化，规格 FR-01/02/03/10）无文件交叠，可独立评审与回滚。本 CR 实施期自身的进度保存继续使用现有 checkpoint 流程。

# 2. 用户故事

- **US-01 代码审批人**：希望进入 approve-code 时，远端受控内容就是代码评审 PASS 时的那一份——评审 PASS 后必须先 checkpoint，审批重核不会看到漂移内容。
- **US-02 开发启动审批人 / dev-plan 消费方**：希望 plan.md / TASK 正文在评审 PASS 后被改动时，旧 PASS 自动失效并回到 review-dev-plan，而不是带着过期结论进入开发。
- **US-03 跨会话接续者**：希望 `cr.md` 的时间字段只有一个、语义明确（最近一次受控修改），任何 reader 不因 `updated` / `updated-at` 双轨读错"最后活动时间"。
- **US-04 Pipeline / Skill 作者**：希望 review 输出合同只有一套字段（verdict/blockers/suggestions/dimensions/repair-target），不再引用实现里不存在的 `repair-instructions`、`fixed-blockers`，也不必维护 suggestion 升格策略。

# 3. 功能需求

## FR-01 代码评审 PASS 后、人工审批前强制 checkpoint（规格 FR-04）

- `code-implementation.pipeline.json` 在 review-code 节点返回 verdict=pass、blockers 为空且 test-report.md status=pass 后，必须执行现有 `push-progress`（一次 `crctl checkpoint` 深原语调用），然后才允许进入 approve-code 人工审批节点。
- checkpoint phase 非 complete（含 `CHECKPOINT_SENSITIVE_PATH`、`CHECKPOINT_REMOTE_ADVANCED` 等任一失败分类）时 Pipeline 立即在当前节点中止，不进入人工审批，不带不完整证据前进。
- 回修循环必须完整重放 implement-code → write-test-report → push-progress → review-code，并在再次 PASS 后重新执行本 FR 的 PASS 后 checkpoint；不允许复用上一轮 checkpoint 结论。
- approve-code 继续执行现有 release-subjects 远端重核，门禁不放宽；本 FR 只在审批前补一次受控发布，不改动 approve/reject 语义。
- 不新增 checkpoint 协议、命令或状态；状态机（15 个具名状态 + 注册前 `(new)`；28 条声明、wildcard 展开 50 条转移）不变。

## FR-02 dev-plan composite subject digest（规格 FR-05）

- `crctl review-record --stage dev-plan` 在落盘 annotation 时计算 composite digest，写入现有 `subject-sha256` 字段（与 requirement/tech-design 同字段），并记 `subject-file` 指向 plan.md；不新建 freshness ledger、不新增 `input-subjects` 或通用多文件绑定 schema。
- digest 输入固定为 LF 规范化后的 `change-requests/{CR-ID}/plan.md` 与按仓库相对路径排序的全部 `change-requests/{CR-ID}/tasks/TASK-*.md`；digest 必须同时纳入每个相对路径与文件内容（防止不同文件集合拼接出相同结果）。
- `tasks/_index.yml` 不进入 digest——实现期任务状态会正常变化，不应使旧 PASS 失效；TASK 正文必须进入。
- `crctl next` 与 `approve-dev-start` 在消费 dev-plan PASS 前必须重算 composite digest；与 annotation 记录不一致时判定旧 PASS 失效，路由回 review-dev-plan（`crctl next` 给出重审建议，`approve-dev-start` 硬失败拒绝放行）。
- 历史 annotation 缺少 `subject-sha256`（legacy）时沿用现有"无 digest → 重审"的保守判定，不批量迁移历史数据。
- requirement、tech-design、code 三个阶段的既有绑定格式与消费逻辑保持不变。

## FR-03 cr.md 时间字段统一为 `updated`（规格 FR-06）

- 新注册与所有后续受控状态写入统一使用 `updated`；其语义为 `cr.md` frontmatter 最近一次受控修改时间。
- 受控 writer 收敛为三类：register、状态推进（advance/approve/reject 的 cr.md 状态文本生成）、Owner 正式移交；三者修改 `cr.md` 时均必须刷新 `updated`。
- PRD/SDD/TASK、评审、测试、checkpoint 或其他 CR 产物变化不得触碰 `cr.md#updated`。
- reader 在兼容期接受旧 `updated-at`；任一正常 writer 修改该份 `cr.md` 时，发现旧字段应替换为单一 `updated`，不得同时保留两个字段。
- 不批量迁移历史 CR；只在下一次正常写入时渐进收敛。LF/CRLF 输入必须产生一致结果（读入后 `\r\n → \n` 规范化）。

## FR-04 review canonical 合同收敛（规格 FR-09）

- 所有 review Skill、Pipeline 输出与 annotation 统一使用：`verdict`、`blockers`、`suggestions`、`dimensions`、可选 `repair-target`——与 `crctl review-record` 当前实际产出对齐。
- `repair-instructions` 不再作为持久化 canonical 字段：从四个 pipeline 模板（requirement-authoring、architecture-design、code-implementation、product-planning）与引用它的 Skill（review-requirement、review-tech-design、review-dev-plan、review-code、write-test-report 相关节点等）中删除。
- `fixed-blockers` 不作为独立账本或节点输出义务：下一轮 review 通过 blockers 差异自然体现修复结果；删除 implement-code 等节点 prompt 中的 fixed-blockers 产出要求。
- blocker 表示本 CR 必须处理的问题；suggestion 表示本 CR 不处理的改进项。
- 删除 `suggestion_policy strict|lenient` 触发参数与"首轮 attempt=1 非阻塞发现升格为 blocker"的规则；dimensions 不再记录 suggestion-policy。
- reviewLoop 回修传递的 review_feedback 只含 canonical 字段（blockers、suggestions、dimensions、repair-target）；各 Skill 的自修复模式按 blockers 定点修复的行为语义不变。
- 不新增错误码注册中心或 payload validator 框架；字段收敛以文本契约修订 + 既有 lint/行为测试保障。

# 4. 非功能需求

- **NFR-01 复用优先**：只复用现有 `crctl checkpoint`、digest helper（sha256 + LF 规范化）、YAML block matcher、CAS 写入与既有测试 fixture；不新增模块、命令或账本。
- **NFR-02 行尾纪律**：所有 digest 计算与 frontmatter 解析先做 `\r\n → \n` 规范化；跨行正则解析失败必须硬失败，禁止静默降级为空结果。
- **NFR-03 跨平台**：全部新行为在 Ubuntu 与 Windows 上通过既有 CI 测试套件。
- **NFR-04 零状态机变更**：本 CR 不增删状态或转移；涉及状态判断的断言以 `../tools/dir-graph.yaml#change-request-track.state_machine` 当前内容为唯一事实源。
- **NFR-05 向后兼容**：legacy 无 digest 的 dev-plan annotation、旧 `updated-at` 字段的存量 CR 均不构成读取错误，按保守路径处理。

# 5. 验收标准

- **AC-01**（FR-01）：review-code PASS 且未执行 PASS 后 checkpoint 时，Pipeline 无法进入 approve-code 人工审批节点；checkpoint phase=complete 后 release-subjects 远端重核通过。
- **AC-02**（FR-01）：PASS 后 checkpoint 失败（phase 非 complete）时 Pipeline 在当前节点中止；按回修循环重放后再次 PASS，重新 checkpoint 成功才可进入审批。
- **AC-03**（FR-02）：PASS 后修改 plan.md、修改任一 TASK-*.md、增删 TASK 文件（路径集合变化）三种操作均使旧 PASS 失效——`crctl next` 建议重审、`approve-dev-start` 硬失败；只修改 `tasks/_index.yml` 不使旧 PASS 失效。
- **AC-04**（FR-02）：composite digest 可由 plan.md + 排序 TASK 集合（相对路径 + LF 内容）独立复算；CRLF 与 LF 工作区检出产生相同 digest；不同 TASK 文件集合不会产生相同 digest。
- **AC-05**（FR-03）：register、状态推进、Owner 正式移交三类写入均刷新 `updated`；PRD/SDD/TASK/评审/测试/checkpoint 等产物变化不触碰 `updated`。
- **AC-06**（FR-03）：legacy `updated-at` 兼容读取正确；writer 在含旧字段的 cr.md 上写入后只剩单一 `updated`（无双字段共存）；CRLF frontmatter 处理一致。
- **AC-07**（FR-04）：四个 pipeline 模板与全部 review 相关 Skill 中不再出现 `repair-instructions`、`fixed-blockers`、`suggestion_policy` 引用；静态检查（grep/lint）零命中。
- **AC-08**（FR-04）：blocker/suggestion 路由正确——block 轨 verdict=block 且 blockers 非空时按 reviewLoop 回修，pass 轨 suggestions 不阻断推进；既有 294/294 crctl 测试基线在修订后保持全绿。
- **AC-09**（全量）：本 CR 自身按规格第 10 节"实施 CR 2"的五步清单完成：code Pipeline 插入 PASS 后 push-progress、composite digest 实现并接入 review-record/next/approve-dev-start、`updated` writer 与旧字段 reader 统一、canonical 字段与 blocker/suggestion 路由收敛。

# 6. 成功指标

- 上线后不再出现"review PASS 后内容漂移仍被人工审批消费"与"plan/TASK 修改后旧 PASS 被 approve-dev-start 沿用"两类事故（此前为规格 P0-04、TRA-06 记录在案的问题）。
- `crctl status/next` 对任一 CR 的时间字段读取不再因 `updated`/`updated-at` 双轨产生歧义；新写入 CR 中双字段共存数为 0。
- 全仓（pipeline-templates、skills、agents、README）对废弃 review 字段的引用数降为 0，并由 CI 静态规则防回潮（静态规则本体归实施 CR 5，本 CR 只保证删除后不回引）。

# 7. 范围排除

- **Writeback 原子化**（规格 FR-01、FR-02、FR-03、FR-10）归 CR-2026-038（实施 CR 1）。
- **结构化测试闭环**（规格 FR-07、FR-08：`crctl test` 结构化 plan、机器区/分析区、shell:false）归实施 CR 3；本 CR 不改动 write-test-report 的测试执行语义与 test-report.md 结构，仅按 FR-04 删除其中对 `repair-instructions`/`fixed-blockers` 的文本引用。
- **归档可信化**（规格 FR-11～FR-13：traceability 最小证据、generator 事实修正、change-impact-analysis/feedback-writeback 退役）归实施 CR 4。
- **职责边界清理**（规格 FR-14～FR-16：Agent/Pipeline/README 收敛、CI workflow 合并、lint 规则扩张）归实施 CR 5；本 CR 只做 review 字段收敛所必需的文本修订，不做整体职责重写。
- 不新增 checkpoint 协议、durable run-id、freshness ledger、subject registry、错误码 registry、schema registry 或通用 traceability 写入接口。
- 不批量迁移历史 CR 的 digest 与时间字段；不重写历史 traceability milestone。
- reviewer-panel 与 `crctl next` 对 requirement/tech-design 的既有 freshness 逻辑不在本 CR 改动范围。
