---
id: CR-2026-071-prd
type: PRD
cr-ref: CR-2026-071
title: CR Agent 委派回执判定统一与需求 PRD 前 checkpoint 恢复
target-version: 0.44
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owner-role: requirement
status: draft
created: 2026-09-27T13:21:00+08:00
updated: 2026-09-27T13:21:00+08:00
---

# 1. 概述

本 CR 合并两项同一需求期流程的修复：AIFI-36 正文 P0/P1 的 CR Agent 委派回执误判，以及 Ray 在 AIFI-36 线程评论 `01a0e144-b8e5-7454-a895-ff1b39d19854` 指定的 PRD 草稿评审前 checkpoint 恢复。目标 spec 为 `ai-first-platform`；版本依据 `specs/_index.yml` 当前 `0.43` 接续为 `0.44`。项目绑定 Dayan，需求、开发、测试三角色 owner 均为 Ray（以本 CR `cr.md#owners` 为准）。来源 Issue 的原生维护边界已被 Ray 本线程的后续要求覆盖为一个新的 CR；本 CR 不回改 AIFI-35 / CR-2026-001。

AIFI-35 中 dev-agent 委派 SDD 与 plan/TASK 评审的评论均成功写入，目标 reviewer 返回 `trigger_outcomes.status=queued, reason_code=queued`，首次 reviewer 独立 run 确已 PASS，却被提示词当作失败并向协调者报告 `DELEGATION_FAILED`。已核实 `multica/server/internal/handler/admission.go` 公开的 status 为 `queued | coalesced | deferred | blocked`；`enqueued` 不是 status，`target_unavailable` 是 reason_code。`multica/cr-prompts-revised/` 中四份可部署提示词有错误/分散判定；`bak/` 也有部署副本待核实。仅 mention 人类成员的成功评论没有 agent/squad 的 outcome，不能当作委派失败。

另据 Ray 反馈，AIFI-35 的 PRD 撰写后未提交，评审前置条件因此阻断。现行 `tools/pipeline-templates/requirement-authoring.pipeline.json` 在 node-2（`write-requirement-prd`）后直接进入评审；CR-2026-066 删除了原 node `…0003` 草稿 checkpoint。要求**仅恢复这一处评审前提交节点**，不整体回滚 CR-2026-066 的评审 PASS 发布与审批后 checkpoint 退役机制。需求期产物和实现期代码分工仍以各自 Skill 为准。

# 2. 用户故事

- **US-1** 作为需求/开发作者或协调者，我希望在单个 agent/squad mention 返回 `queued`、`coalesced` 或 `deferred` 时准确识别已投递，避免错误上报或重复委派。
- **US-2** 作为 reviewer，我希望 PASS 后仅 @Ray 等人类成员请求人工审批时，即使没有 agent/squad outcome，也不触发 `DELEGATION_FAILED`。
- **US-3** 作为流程维护者，我希望四个 Agent、可部署副本与线上指令共享同一可审查的判定合同，平台枚举变更能被回归检查发现。
- **US-4** 作为需求 reviewer，我希望接到评审前 PRD 已通过 checkpoint 提交、推送；BLOCK 回修后仍能看到本轮已发布的 PRD，免于因未提交产物阻断。

# 3. 功能需求

## FR-1（P0）：委派回执的按目标判定

四个 CR Agent——`requirement-writer`、`dev-agent`、`quality-reviewer-agent`、`cr-coordinator-agent`——在成功发布包含 agent/squad mention 的评论后，仅检查**本次实际 mention 的 agent/squad 目标**对应的 `trigger_outcomes`：`status=queued|coalesced|deferred` 视为投递成功；`status=blocked`（保留 `reason_code`）或该目标缺失 outcome 视为 `DELEGATION_FAILED`。状态字段和原因字段分别解释；`target_unavailable` 不得被当作 status；未知 status 不得误判成功。若一条评论只 mention 人类成员而无 agent/squad 目标，评论发布成功即没有委派失败可报告；若评论发布本身失败，应报告发布错误，不能伪称投递成功。一个目标成功不掩盖另一个被 mention 目标的失败；不可因误判而再次 mention reviewer 或通知协调者。

## FR-2（P0）：源、部署副本与线上一致

修订 `multica/cr-prompts-revised/` 四份提示词，核对并修正 `bak/` 中**仍可作为部署来源**的对应副本，避免旧枚举被重新部署；核实目录用途并记录保留或排除的理由。同步四个线上 Agent instructions，保留既有 Agent ID、绑定和其他协作职责，以 `multica agent get --output json` 对照实际线上内容逐个核验。失败时不得以“文件已改”代替线上交付。AIFI-35 既有评审结果及账本只读，不重复触发其 reviewer。

## FR-3（P1）：单一合同与漂移回归

将 FR-1 的判定规则收敛到一个共享、版本化、可审查的合同源；四份提示词引用同一合同，不再各自手写枚举清单。线上 Agent 若不能直接读取合同源，发布/导入时须从**同一来源**生成或注入完整规则并核验成品，不允许只有运行时无法解析的本地路径引用。增加最小自动化合同/回归检查，并与平台公开的 status 枚举对齐；覆盖 `queued`、`coalesced`、`deferred` 成功，`blocked` + `reason_code`、被 mention 的 agent/squad 目标缺失 outcome 失败，以及仅 mention 人类成员且评论成功不失败；检查四份提示词/需维护的副本/发布产物与合同不漂移。合同位置、生成与部署方式归 SDD 确定，不在 PRD 规定实现算法。

## FR-4（Ray 增量）：恢复 node-2 后评审前 checkpoint

在 `tools/pipeline-templates/requirement-authoring.pipeline.json` 的 `write-requirement-prd`（node-2）**之后、`review-requirement` 之前**恢复独立 checkpoint 节点，调用 `crctl checkpoint`（按原有 `push-progress` Skill 的深原语契约），把本 CR 的 PRD 草稿与所有 active repo 的对应进度提交、推送。该节点失败/未完成不得进入评审；BLOCK 回修修改 PRD 后，再次进入评审前也必须完成相同发布步骤。同步节点数、流程说明与结构回归检查，使 Pipeline 的真实顺序和回修路由一致。评审 PASS 的 reviewer 发布职责仍保留，发布后的人工审批 gate 不变；不得恢复 CR-2026-066 删除的审批后 checkpoint 或其他无关节点。

# 4. 非功能需求

- **兼容/最小变更**：不修改 Multica 平台当前 `queued` 返回值，不引入新的 `status`、账本字段、CR 状态或人工审批旁路；CR-2026-066 除 node-2 后 checkpoint 所需连带路由、索引、回归外的语义不变。
- **安全/审计**：不在评论或提示词中泄露不可见目标信息；失败诊断保留当前可见目标的 `status`、`reason_code` 与目标缺失证据；上线时能追溯共享合同、四份源指令和线上版本。
- **可恢复**：checkpoint 失败遵循 `push-progress` / `crctl checkpoint` 的机器错误和 `recovery` 语义，不手工改状态、账本或绕开 gate；恢复后才继续评审。

# 5. 验收标准

- **AC-1 → FR-1**：将 AIFI-35 回执 `status=queued, reason_code=queued` 作为回归样例，四个 Agent 均判为成功投递、不发 `DELEGATION_FAILED`，不因此重复委派；`coalesced`、`deferred` 同样成功。
- **AC-2 → FR-1**：`blocked` 携 `reason_code=target_unavailable`（及其他 reason）与已 mention 的 agent/squad 目标缺失 outcome 均报失败，诊断区分 `status` 和 `reason_code`；未知 status 不算成功。仅 @Ray 等人类成员、评论已成功时不报委派失败；评论写入失败不报成功。
- **AC-3 → FR-2/FR-3**：源提示词、经核实可部署的 `bak/` 副本、共享合同、回归检查与四个线上 Agent instructions 一致；逐个展示 `multica agent get --output json` 核验结果，不更换 Agent ID/绑定；交付记录列明 P0/P1、测试、线上核验和未覆盖边界。
- **AC-4 → FR-3**：自动回归至少覆盖 AC-1/AC-2 中五类目标场景，另验证共享合同的成功枚举与平台公开 status 一致；任一源/发布物漂移会使检查失败，不依赖人工记忆同步四份枚举清单。
- **AC-5 → FR-4**：Pipeline 顺序确为 node-2 → checkpoint → `review-requirement`，该节点实际调用 `crctl checkpoint`，未成功不得评审；BLOCK 经 `write-requirement-prd` 回修后 checkpoint 重新发布再复评。索引节点数和结构测试通过；评审 PASS 发布与审批后节点配置保持既有机制。
- **AC-6 → FR-1～FR-4**：不重开 AIFI-35 reviewer、不修改其 CR 状态/账本；FR-4 只针对新 CR 的未来需求流程，不用对 AIFI-35 进行补写或代为审批。

# 6. 成功指标

发布前合同/回归检查对上述场景全部通过；四份线上指令与同源生成物逐个一致。以 AIFI-35 的两个历史委派回执做只读重放，错误上报与因误报产生的重复委派均为 0；新 CR 需求评审前 checkpoint 的 `phase=complete` 可被机器核验，PRD 未提交引起的评审前置阻断为 0。记录实际运行的测试、线上核验及尚未覆盖的边界，不以预计结果代替证据。

# 7. 范围排除

不修改平台 admission status 的现有返回值、不写 AIFI-35 / CR-2026-001 账本或重跑其评审、不代签任何人工审批、不扩大到其他 Pipeline 阶段或其他 CR-2026-066 删除的 checkpoint。需求期仅编写/回修本 CR 的 PRD 并依节点推进；四份提示词、合同、测试、pipeline 与线上指令的落地属于审批后的设计/开发与发布工作，不能由需求期提前实施。
