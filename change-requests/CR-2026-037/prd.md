---
id: CR-2026-037-prd
type: PRD
cr-ref: CR-2026-037
title: crctl TASK 索引初始化与 task-breakdown 门禁闭环
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-13T10:22:00+08:00
updated: 2026-08-13T10:22:00+08:00
---

# 1. 概述

CR-2026-032 在技术设计审批后生成 Plan/TASK 时暴露流程断点：`write-dev-tasks` 要求生成 `tasks/_index.yml`，但 tools `ARCHITECTURE.md` 将该文件定义为受控账本，禁止 Skill/Agent 手写；当前生产 `crctl task` 只有 developing 阶段的 `done` 子命令，没有首次初始化入口。与此同时，`task-breakdown` gate 只检查 `plan.md` 与 TASK 文件，会在索引缺失时错误放行，而 `review-dev-plan` 和开发启动审批又强制要求索引存在，形成“前一门放行、后一节点必失败”的半完成态。

本 CR 只补一个深原语 `crctl task init`：从 CR worktree 中已经由 `write-dev-tasks` 产生的 `TASK-NN.md` frontmatter 确定性生成/刷新 `_index.yml`，复用现有 YAML 子集解析、CAS、审计和错误出口；同时给 `task-breakdown` gate 增加索引存在性，并让 Skill/Pipeline 调用该原语。Agent 仍只路由，Pipeline 仍只编排，Skill 仍做业务拆解，账本原子写入继续唯一归 crctl。

现有基础设施与本次改造严格分离：不新建事务框架、manifest、账本脚本、YAML 依赖或状态机；不把 Plan/TASK 业务设计判断下沉到 crctl。通用 `crctl validate plan.md/TASK-*.md` 因现有 schema ID（`PLAN-v*`/`TASK-v*`）与实际 CR 文档 ID（`CR-*-plan`/`CR-*-TASK-*`）不一致，明确不在本 CR 顺手接入。

# 2. 用户故事

- **US-01 开发 Agent**：生成 TASK 内容卡后，希望只调用一个 crctl 命令物化受控索引，不手写账本 YAML。
- **US-02 开发计划评审者**：进入 `task-breakdown` 时，希望 Plan、TASK 文件和 `_index.yml` 都已存在，避免下一节点确定性失败。
- **US-03 开发负责人**：开发启动前若 TASK 被评审回修，希望可安全刷新全 pending 索引；一旦已有 done 进度，任何重建都必须拒绝，防止丢账。
- **US-04 tools 维护者**：希望复用既有 parser/CAS/audit/controlled Git，不维护第二套 task 事务、manifest 或生成器协议。
- **US-05 CR-2026-032 交付者**：流程修复合入权威 Tools Root 后，希望用正式命令恢复已提交 Plan/TASK，继续 review-dev-plan，不消费永久例外。

# 3. 功能需求

## FR-01 `crctl task init` 单一入口

新增命令：

```text
crctl task init <CR-ID> --workspace <knowledge-base CR worktree>
```

命令不得接受 TASK 列表、索引 YAML、candidate path、状态或 owner 参数。唯一业务输入是当前 CR 目录中按 `^TASK-\d+.*\.md$` 匹配的 TASK 文件；crctl 读取 frontmatter 后机械生成 `change-requests/{CR-ID}/tasks/_index.yml`。

该命令只负责索引物化，不推进 CR status、不执行人工审批、不提交 Git、不评审 TASK 内容质量。状态推进仍由后续 `crctl advance --to task-breakdown --trigger write-dev-tasks` 完成，提交仍走既有 `crctl git`。

## FR-02 TASK 集合与 frontmatter 硬校验

`task init` 必须在任何写入前完成全量校验：

- 至少一个 TASK 文件，否则 `TASK_SET_EMPTY`；
- 文件名 `TASK-NN.md`、`id={CR-ID}-TASK-NN`、`cr-ref` 与当前 CR 一致；
- `type=TASK`、非空 `title`、`status=pending`、`estimate=<正整数>h`、`depends-on` 为数组；
- TASK ID 和编号唯一；
- 每个依赖都引用本批 TASK，否则复用既有 `DEPENDS_ON_UNKNOWN`；
- 依赖图无环，否则 `TASK_DEPENDENCY_CYCLE`；
- 解析失败或字段不合法统一 `TASK_CARD_INVALID`，detail 必须带文件和字段，不得静默跳过坏卡。

命令不判断任务拆分是否合理、验收条件是否充分、接口契约是否正确；这些继续归 `write-dev-tasks` 和 `review-dev-plan`。

## FR-03 确定性索引投影

索引按 TASK 编号升序生成，固定形态：

```yaml
cr-id: CR-2026-037
tasks:
  - id: CR-2026-037-TASK-01
    title: "..."
    status: pending
    estimate: 4h
    depends-on: []
```

字段只投影 `id/title/status/estimate/depends-on`；不复制正文、slug、plan/sdd ref、文件路径、时间戳或评审结论。字符串使用现有安全标量渲染方式，输出 LF；同一 TASK 集合重复执行必须字节稳定、`changed=false`，不得产生时间漂移。

## FR-04 状态与进度保护

`task init` 仅允许：

- `tech-design-reviewed`：首次生成或 review-dev-plan 普通回修后的刷新；
- `task-breakdown`：开发启动审批前的 TASK 重拆自环刷新。

其他状态返回 `ILLEGAL_LEDGER_STATE`。若现有 `_index.yml` 任一任务已为 `done`、存在 `done-at`，或形状无法证明全部 pending，返回 `TASK_INDEX_HAS_PROGRESS`，原文件不变。不存在索引时 create；索引存在且可刷新时使用读入原始字节 SHA 做 CAS replace。

## FR-05 CAS、审计与幂等

写入必须复用 crctl 既有 `readFileChecked`、CRLF 规范化、`sha256`、`casWrite`/create-only 语义与 `auditLog`，不引入 durable transaction、WAL 或独立版本化账本脚本。

成功返回至少包含：

```json
{
  "op": "task-init",
  "cr": "CR-2026-037",
  "file": ".../tasks/_index.yml",
  "taskCount": 1,
  "totalEstimateHours": 4,
  "changed": true
}
```

失败必须零写入、零审计成功记录；同内容重放返回 `changed=false`。审计记录只含 op、CR、actor、taskCount、changed，不含 TASK 正文。

## FR-06 `task-breakdown` 门禁补齐

`gates.json#statusGates.task-breakdown` 在既有 `plan.md` 与 TASK glob 之外增加：

```text
fileExists change-requests/{cr}/tasks/_index.yml
```

缺索引时 `gate --for task-breakdown` 与 `advance` 必须失败，不得再进入下一节点。状态机与转换数量不变，不新增 gate 类型；索引内容一致性由可信生产入口和随后的 `review-dev-plan` 负责，不在本 CR 新造复杂 gate evaluator。

## FR-07 Skill 与 Pipeline 采用

`write-dev-tasks` 的职责改为：

1. 做业务拆解并写 `TASK-NN.md` 内容文件；
2. 调用 `crctl task init` 生成/刷新 `_index.yml`；
3. 校验 Plan 总估算与命令返回的 `totalEstimateHours`；
4. 调用既有 `crctl advance` 推进 `task-breakdown`；
5. 经 `crctl git` 提交。

Skill 不再指导模型手写 `_index.yml`。`code-implementation.pipeline.json` 节点只描述上述调用顺序、输入传递和失败中止，不复制 frontmatter 校验、DAG、CAS 或 YAML 渲染算法。Agent/matrix 无权限变化，README 不复制命令内部算法；`crctl/SKILL.md` 与 CLI help 只登记接口和失败语义。

## FR-08 Bootstrap 与 CR-2026-032 恢复

由于本 CR 修复的正是索引初始化入口，本 CR 自身在命令合入前没有完全合规的自举路径。允许一次性、显式的人类 bootstrap，仅用于 CR-2026-037 自身的 `_index.yml`：由人类在 Plan/TASK 已完成后审阅精确内容并提交，记录其为 `task init` 上线前的单次治理例外；不得由 Agent 写会话脚本，不得泛化到其他 CR，命令合入后例外立即失效。

CR-2026-032 不使用该例外。修复必须先合入 tools `custom/main`，再从权威 Tools Root 执行 `crctl task init CR-2026-032`、提交索引、推进 `task-breakdown` 并执行 `review-dev-plan`。禁止从 CR-2026-037 候选 worktree 隐藏调用未合入工具治理 CR-2026-032。

## FR-09 范围锁定

本 CR 不实现：

- 通用 `crctl validate plan.md/TASK-*.md`；
- PLAN/TASK engineering-doc schema ID 迁移；
- TASK 正文生成器或 LLM 业务判断；
- 新状态、转换、审批、reviewLoop 或 Agent 权限；
- durable transaction、candidate manifest、独立 task-index 脚本、第三方 YAML 库；
- developing 后的索引重建、done 状态迁移或历史任务兼容器。

# 4. 非功能需求

- **极简性**：实现留在现有 `crctl.mjs` 与 `crctl.test.mjs`，优先复用 parser/CAS/audit；无单实现 interface/factory/plugin。
- **分层**：Agent 只路由；Pipeline 只编排；Skill 做拆解判断；crctl 做机械校验与受控账本写；README 不复制算法。
- **可靠性**：任一 TASK 非法、依赖悬空/成环、状态非法、已有进度或 CAS 冲突时索引零变化。
- **幂等性**：同一 TASK 集合重复 init 字节不变、无新时间戳、`changed=false`。
- **兼容性**：`task done` 现有接口和依赖守卫不变；现有合法 `_index.yml` reader 不需迁移。
- **跨平台性**：LF/CRLF TASK frontmatter 生成同一索引；Windows 路径不得进入索引。
- **性能**：单 CR TASK 数量线性 O(n+e)，不缓存、不并发、不访问网络。
- **可测试性**：使用 Node 标准库与现有 fixture；不新增生产 fault point。

# 5. 验收标准

- **AC-01**：4 张合法 TASK 卡执行 `task init` 后生成按编号排序的 `_index.yml`，字段精确为 FR-03，返回 taskCount=4 与正确总工时。
- **AC-02**：同输入重跑返回 `changed=false`，文件字节、mtime 以外的业务内容和 audit 成功记录数量不漂移。
- **AC-03**：TASK 集合为空、frontmatter 缺失、ID/文件名/CR 不匹配、estimate 非法、depends-on 非数组均在写入前失败并给出文件/字段。
- **AC-04**：悬空依赖返回 `DEPENDS_ON_UNKNOWN`；A→B→A 与 A→A 返回 `TASK_DEPENDENCY_CYCLE`，无索引写入。
- **AC-05**：`tech-design-reviewed` 可首次创建；`task-breakdown` 且全部 pending 可刷新；`developing` 拒绝。
- **AC-06**：现有索引含 done/done-at、未知状态或损坏形状时返回 `TASK_INDEX_HAS_PROGRESS`，原字节不变。
- **AC-07**：并发修改导致 CAS 不匹配时拒绝覆盖；CRLF/LF TASK 集合生成完全相同的 LF 索引。
- **AC-08**：缺 `_index.yml` 时 `gate --for task-breakdown` 和对应 advance 失败；补齐后既有 plan/TASK gate 通过。
- **AC-09**：`write-dev-tasks` 与 Pipeline 不再含“模型直接生成 `_index.yml`”算法，而是调用 `crctl task init`；Pipeline JSON 可解析、节点数不变。
- **AC-10**：现有 `task done`、review-dev-plan、dev-start gate/approval 测试无回归；`lint-prompts --mode enforce`、Skill/Agent contract 和 crctl 测试通过。
- **AC-11**：changed-files 仅落 `crctl.mjs`、`crctl.test.mjs`、`gates.json`、`crctl/SKILL.md`、`write-dev-tasks/SKILL.md`、`code-implementation.pipeline.json`；无需修改 Multica、状态机、README 或版本化脚本。
- **AC-12**：修复合入权威 `custom/main` 后，CR-2026-032 的 4 张已提交 TASK 经正式 `task init` 生成 24h 索引，推进 `task-breakdown` 并可进入 `review-dev-plan`。

# 6. 成功指标

- `tasks/_index.yml` 从首次创建到 done 更新只有 crctl 写入，不再存在 Skill/Agent 直写路径。
- `task-breakdown` 不会在索引缺失时放行。
- TASK 回修在开发前可安全重算，开发进度出现后不可被覆盖。
- CR-2026-032 无需重写 Plan/TASK 即恢复流程。
- 本次净新增只有一个命令和一个既有 gate 条目，不产生第二事务或验证框架。

# 7. 依赖与风险

- **依赖**：现有 `matchFrontmatter`、`parseYaml`、`readFileChecked`、`sha256`、`casWrite`、`auditLog`、`resolveCrState`、`fail/ok`。
- **风险 R-01**：通用 schema 与实际 CR 文档 ID 不一致；本 CR 只验证 task init 所需字段，禁止顺手接 generic validate。
- **风险 R-02**：刷新索引覆盖 done 进度；状态白名单 + progress guard 双重拒绝。
- **风险 R-03**：Pipeline 复制算法后继续漂移；Pipeline 只保留调用顺序，算法唯一在 crctl。
- **风险 R-04**：修复 CR 自举例外被滥用；限定 CR-2026-037、限定单文件首次创建、限定人类执行并在命令合入后失效。
- **风险 R-05**：候选 crctl 被用于治理其他 CR；AC-12 明确要求先合入权威 Tools Root。

# 8. 范围排除

- 不修改 CR-2026-032 的 Archive PRD/SDD/Plan/TASK 内容。
- 不增加 `_index.yml` 的时间戳、hash、schema-version 或 source-file 字段。
- 不让 crctl判断任务标题、正文、验收标准或接口设计是否合理。
- 不修改 `task done` 的 developing-only 与一跳依赖守卫。
- 不把 task init 做成版本化脚本、Pipeline 内联 YAML 或 Agent 工具。
- 不更新 README；CLI help 与 crctl Skill 足以承载命令接口，人读总览无需复制实现细节。

# 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 初始草稿：单一 task init 深原语、索引门禁、Skill/Pipeline 采用、一次性自举边界与 CR-2026-032 恢复路径 |
