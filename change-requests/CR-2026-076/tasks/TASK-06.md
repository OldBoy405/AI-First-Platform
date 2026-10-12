---
id: CR-2026-076-TASK-06
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "合法本地信任贯通与漂移降级 warning 分流"
slug: crctl-local-trust-warnings
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-03]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-05；AC-10／AC-11／AC-12／AC-13；SDD §4.5 + D-04 + SDD-CLOSE-05）：在**合法本地信任**范围内把漂移类失败降级为 `warnings[]`（不撤销批准、不重签、不强制重审），同时保持硬阻断与 server-approve 签名路径严格不变，并让 `gate`／`validate`／`next`／`approve`／`merge` 对同一事实给出同一结论。

背景与输入条件：`dep-18` 结论原文——通过条件只依赖 verdict 与 blockers，warning 天然不影响通过判定（`runGateChecks`／`evaluatePassCondition`／`cmdGate`）；`dep-19` 结论原文——warning 已是可扩展数组 `{code,message}` 形态且不参与通过判定，`validate` 已有可扩展只读维度面（`errors`／`warnings`／`checked`／`notChecked`）；`dep-20` 结论原文——审批入口已分本地与 server-approve 两路，签名路径有 canonical 串与 Ed25519 验签并在重放时做六字段精确比较。

明确不做：不新增计数型字段、不新增提示次数账本、不放宽 server-approve 路径、不新增 `warnings` 以外的新输出面。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`function evaluatePassCondition(ws, cr, stageCfg, gates, evidence)`（:481）、`function runGateChecks(ws, cr, targetStatus, gates, opts = {})`（:575）、`async function cmdGate`（:1009）、`function cmdValidateDimensions(ws, target)`（:1566）、`function cmdValidate(ws, target, gates)`（:1620）、`async function cmdApprove(ws, cr, gates, flags)`（:1224）、`async function cmdMerge(ws, positional, flags)`（:3787）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`、`test/merge-tx.test.mjs`
- 合同文本：`skills/develop/review-code/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/write-test-report/SKILL.md`（仅「按 §4.5 消费 `warnings[]`、仅硬条件失败才 BLOCK」的文本）

## 实现要点

1. **本地信任适用范围（先判定，再降级）**：仅当来源、stage 与归属合法（`approval.yml` 该 section 无 server-approve 签名事实、CR／阶段与当前操作根一致、责任角色匹配）时才按本地批准处理；来源缺失、未知或非法**不得**默认为本地。
2. 降级映射（SDD §2.2 code 枚举，本 TASK 新增 4 个；`BINDING_INHERITED_WARN` 由 TASK-01 产出、`SUITE_COUNT_BELOW_BASELINE_WARN` 由 TASK-11 产出，本 TASK 只统一承载形状）：
   | 情形 | code |
   |---|---|
   | PRD／SDD／PLAN／TASK 正文漂移 | `LOCAL_TRUST_DOC_DRIFT_WARN` |
   | TASK 集合增删 | `LOCAL_TRUST_TASK_SET_DRIFT_WARN` |
   | 工具升级带来的证据定义变化（非内容被改） | `EVIDENCE_DEFINITION_DRIFT_WARN` |
   | 合法存量 PASS 缺 `subject-sha256` | `LEGACY_SUBJECT_MISSING_WARN`（提示继续，**不补造**摘要／新 PASS／新签名） |
3. **仍硬阻断**：必需文件缺失、索引／依赖／记录结构非法、最新真实 BLOCK、blockers 非空、真实测试失败、server-approve 签名／摘要／源绑定不符。
4. 一致性要求：`gate`／`validate`／`next`／`approve`／`merge` 对同一事实同一结论；单独 warning 不触发 `onFail`、不造成失败退出，也不在后续同一漂移上再阻断；有真实错误时仍失败。保持既有字段类型，warning 只用既有可扩展数组形式。
5. `dep-18` 性质必须保留：`evaluatePassCondition` 的通过条件只看 `verdict` 与 `blockers`，warning 不得进入判定。
6. `validate` 新增只读维度 `owner-source-anomalies` 属 TASK-15；本 TASK 只保证 `validate` 的 `warnings[]` 分流口径与 `checked`／`notChecked` 形状不变。

## 验收条件

1. **AC-10（cmd-04 + cmd-07）**：正文／TASK 集合／证据定义漂移时，五个入口均输出 `warnings[]`、退出码 0、批准段保持有效；后续同一漂移不再阻断。`cmd-04` = `crctl.test.mjs` 单文件；`cmd-07` = `merge-tx.test.mjs` + `checkpoint-tx.test.mjs` + `workspace-resolver.test.mjs` 三文件（仅其中与 `cmdMerge` warning 分流相关的用例面）。
2. **AC-11（cmd-04）**：缺 `subject-sha256` 的存量 PASS 得到提示且流程继续，annotation 不被补写。
3. **AC-12（cmd-04）**：必需产物缺失／结构非法／blockers 非空／真实失败的正反两面在同一 cmd 内断言——仅合法变化为 warning，上述四类仍硬阻断。
4. **AC-13（cmd-04）**：server-approve 签名／摘要／归属变化保持严格拒绝（`EVIDENCE_DRIFT` 硬失败、Ed25519 验签与六字段比较路径不变），不转本地批准。
5. 真实执行输出落 `test-evidence/cmd-04.log`、`test-evidence/cmd-07.log`；**不声称**覆盖 `workspace-transactions.mjs` 的其他命令面，不新增 plan 未列命令。

## 完成标志

- 4 个新增 warning code 与 5 个入口的同判口径均有用例覆盖，`cmd-04`、`cmd-07` 真实执行退出码 0 并留证；
- `review-code`／`review-dev-plan`／`write-test-report` 三份 Skill 的 `warnings[]` 消费文本落盘；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-03 口径 + `dep-18`／`dep-19`／`dep-20`，不得缩写）：
- `function evaluatePassCondition(ws, cr, stageCfg, gates, evidence)`（:481）——通过条件只依赖 `verdict` 与 `blockers`，本 TASK 不得把 warning 计入；
- `async function cmdApprove(ws, cr, gates, flags)`（:1224）与 `approveAndAdvance`／`approveWithGrant`／`classifyGrantState`／`assertAdjacentApprove`／`verifyGrantSignature`／`grantCanonicalString`（`dep-20`）——server-approve 路径严格不变。

产出（供 TASK-07／TASK-10／TASK-11／TASK-17 消费，消费方不得缩写）：
- `function runGateChecks(ws, cr, targetStatus, gates, opts = {})`（:575）返回的 `warnings[]` 扩展形式：`{ code: string, message: string, ref?: string }`（E2，禁止计数型字段）；`gate`／`validate`／`next`／`approve`／`merge` 五个入口复用同一形状；
- `cmdNext` 的 `warnings[]`（与 TASK-05 的 `nextReason` 并存，同一数组形状）；
- 新增 code 枚举 4 个（`LOCAL_TRUST_DOC_DRIFT_WARN`、`LOCAL_TRUST_TASK_SET_DRIFT_WARN`、`EVIDENCE_DEFINITION_DRIFT_WARN`、`LEGACY_SUBJECT_MISSING_WARN`）＋统一承载 TASK-01／TASK-11 的两个 code；既有错误码集合不变（§3.2）。
