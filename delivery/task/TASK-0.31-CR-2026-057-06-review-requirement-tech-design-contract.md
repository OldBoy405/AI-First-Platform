---
spec-id: ai-first-platform
version: "0.31"
id: CR-2026-057-TASK-06
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: review-requirement 与 review-tech-design 契约修订（FR-1～FR-4）
slug: review-requirement-tech-design-contract
status: pending
estimate: 6h
depends-on: []
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

修订两个 review Skill 的业务判断与输出约束（FR-1 首轮完整契约域、FR-2 分级、FR-3 固定前缀、FR-4 回修可重验），只改文本契约，**不改**状态机、`review-record` schema 必填字段集、attempt 账本（FR-1 边界）。`review-tech-design` 另增 AC-5 前置：先核对 SDD「批准范围」四字段，缺章节即 blocker。

输入条件：tools CR worktree；本 TASK 为纯文档修订，可与 M3 并行（无代码依赖）。

## 涉及文件 / 模块

- `skills/requirement/review-requirement/SKILL.md`
- `skills/develop/review-tech-design/SKILL.md`

## 实现要点

1. **首轮完整契约域（FR-1）**：首轮必须在生成 verdict 前完成全部适用维度；同一契约域的独立缺口必须同轮出现在 blockers，不得在首个 blocker 处提前结束。补契约域闭合清单（按科目选用，缺适用项显式写 N/A 及原因）：HTTP API 八项（endpoint/request/response/error/权限/幂等/状态/验收观察点）；crctl·CLI 八项（命令与 flag/输入约束/JSON·stdout 输出/错误码/调用者约束/幂等/状态副作用/验收观察点）；Skill 契约五项（必填参数/落盘路径/允许的状态转换/失败码/与 crctl 的唯一写入边界）。`review-requirement`：PRD 定义用户可调用契约（HTTP 或 CLI/Skill）时按上表一次检查；`review-tech-design`：先核对批准范围（见 2），再查真实 symbol、签名、调用者闭包、依赖方向、事务与锁序；保留既有 Step 2.2 首轮全量规则。
2. **AC-5 前置（review-tech-design）**：先核对 SDD「批准范围」固定章节（scope_in/scope_out/zero_diff/follow_up 四字段；空字段须显式写 `无` 或 `N/A` 加理由），缺章节或缺字段 → blocker。
3. **分级（FR-2）**：影响当前实现唯一性或当前验收可达性的缺口 → blocker；只影响表达/未来优化/后续 CR → suggestion；禁止批量升降级。
4. **固定前缀（FR-3）**：blockers/suggestions 每条文本必须使用固定前缀之一（ASCII 全角冒号 `：`）：`已解决：`（suggestions，关闭项不进本轮 blockers）、`部分解决：`/`未解决：`（blockers）、`本轮新增：`（blockers，本轮新发现）、`范围外：`（suggestions）。附机械核对规则（PRD FR-3 四条 + 对照键规则：以 `B-` 开头取到第一个空白或 `]`，否则取原文；上一轮每条 blocker 在本轮 blockers ∪ suggestions 恰好出现一次；首轮全部用 `本轮新增：`）。
5. **回修可重验（FR-4）**：逐条给出旧 blocker 解决状态，禁止只写「已修复」；不得重新引入被删 canonical 字段。
6. **文本约束（R8）**：新增文本不得包含 `fixed-blockers` / `repair-instructions` / `suggestion_policy` / `suggestion-policy`（contract-scan 四串）；不得破坏既有静态断言所依赖的原文措辞（实施前先跑一次 contract-scan/lint-prompts 确认基线断言面）。

## 验收条件

1. 两个 SKILL 均含：契约域闭合清单（三行表 + N/A 规则）、首轮全量规则（同域独立缺口同轮列出）、FR-2 分级判据、FR-3 前缀表与机械核对规则、FR-4 逐条复核规则。
2. `review-tech-design` 前置核对批准范围（AC-5：缺章节 → blocker）。
3. AC-1～AC-4 四节点参数化矩阵（plan §6.3）中 review-requirement / review-tech-design 两行的夹具语义与 SKILL 文本一致（首轮闭合夹具 / 分级夹具 / 回修夹具）。
4. `contract-scan.test.mjs` 零命中（AC-4）；`lint-prompts.mjs` 通过；两文件 diff 仅定点增改不重写结构。

## 完成标志

contract-scan 与 lint-prompts 本地跑通零命中；文本夹具逐条核对通过；提交 `[cr] implement CR-2026-057 TASK-06`。

## 接口契约

- 消费：既有临时 payload + `crctl review-record` 承载（`verdict`/`blockers`/`dimensions`/`suggestions`，schema 必填字段集不变）；既有 `review-annotations/{requirement,sdd}.yml` 落点。
- 产出：两 SKILL 文本契约；不产出新 CLI、新状态、新 schema 字段。
- 前缀强制在 Skill 文本层（决策 D-4），不在 crctl 加内容校验（FR-17）。
