---
id: CR-2026-076-TASK-14
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "source 自动绑定、空值语义与注册前／使用前双防线"
slug: crctl-source-autobind-dual-guard
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-13]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-SUP-03、FR-SUP-04；AC-SUP-03／AC-SUP-04／AC-SUP-05，并承接 AC-SUP-07 主责；SDD §4.15 + §3.3）：让创建需求时不再要求手填 `source`——成功上传主来源文档则自动传入知识库内相对路径；未上传或注册前移除则统一持久化为 `""`；上传／读取／保存失败则明确失败并停止注册；并在注册前与**使用前**都保留 containment + 可读性校验。

背景与输入条件：`source` 语义沿用「知识库内来源文件相对路径」，不新增附件引用类型或数组。**待核实依赖（SDD §10，「上传附件 → 知识库 source 桥接（平台侧）」）**：本轮在 multica worktree HEAD `a2046ce34449aaed67df000a1320d73d9976e987` 只读检索未取到「附件 → 知识库文件」写入缝的稳定符号，故**不得**把该桥接断言为既有能力；实施期必须先定点核实实际入口与可读性保证，再按核实结论二选一（复用既有通道 / 新增最小接线），核实前不得按「既有能力」排期。

明确不做：不新建 OCR、通用转换、多文件聚合或附件管理系统；`source` 不扩为数组；不要求删除此前成功上传的原件；保留规划流程／CLI 传入合法知识库来源文件路径的能力（「未上传为空」是本入口默认行为，不等于禁止既有规划报告作为来源）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdRegister(ws, flags)`（:3659）的 `source` 校验缝（与 TASK-13 的 owner 校验缝同批、同事务，持久化前执行）
- `pipeline-templates/requirement-authoring.pipeline.json`：`source` 取消 `required: true`（`dep-29`），与空值语义一致
- `skills/requirement/requirement-register/SKILL.md`：`source` 输入说明与空值／自动绑定／失败停止语义
- `skills/sync/handover-cr/SKILL.md`：错误语义说明
- `skills/shared/crctl/scripts/test/register-tx.test.mjs`

## 实现要点

1. 三态行为严格按 SDD §4.15 表：
   | 创建需求时 | 行为 |
   |---|---|
   | 成功上传一个主来源文档 | 保存到知识库并把相对路径自动传给 `register.source`；**入库通道待核实**，实施期定点核实后二选一（复用既有附件读取／入库通道，或新增最小接线）；无论哪条分支，均须在注册持久化前完成入库，并确保随后派生的 CR worktree 实际可读 |
   | 未上传，或注册前移除 | `source` 缺省或空串统一持久化为 `""`；writer 使用标题、摘要与已确认上下文 |
   | 上传、读取或保存失败 | 明确失败并停止注册，不静默降级为无文档 |
2. 校验缝（注册事务持久化前）：containment（**不得仅凭字符串前缀**，须处理相邻目录前缀与符号链接越界）+ 文件存在／可读 + 目标为后续知识库 worktree 可读路径；writer 保留**使用时**的同一检查防线，不因「入口已校验」删除。
3. 禁止值：附件 ID、下载 URL、Issue 标识、显示名、任务临时路径均不得充当 `source`（含断言）。
4. 零写入与幂等（AC-SUP-07 主责）：校验失败不占 `registration_key`、不建账本与 worktree；重放同一输入按既有事务原语恢复同一操作（复用 TASK-04 的原子闭环口径，不新增幂等账本）。
5. 核实结论必须落盘：核实入口、稳定符号、结论分支（复用既有通道 / 新增最小接线）、以及「CR worktree 实际可读」的验证方式；**取不到稳定符号时按技术失败报告**（不得静默降级、不得把未核实能力写成已具备）。

## 验收条件

1. **AC-SUP-03（cmd-06）**：上传自动绑定成立——`source` 自动填入，且 writer 在 CR worktree 内实际可读（断言 worktree 内 `fs.existsSync` 与可读性，而非仅字符串相等）。
2. **AC-SUP-04（cmd-06）**：无文档与失败分流——未上传／注册前移除时 `source` 持久化为 `""`；上传／读取／入库失败时注册停止且不产生任何账本写入。
3. **AC-SUP-05（cmd-06）**：source 前置门禁——不存在／非文件／不可读／越界（相邻目录前缀与符号链接）均拒绝，且拒绝时零写入。
4. **AC-SUP-07（cmd-06，主责）**：零写入与幂等恢复——校验失败不占 `registration_key`、不建账本与 worktree；同一操作重投幂等（不产生第二次写入）。
5. **使用前防线保留**：断言 writer 侧检查在入口已校验的情况下仍然执行（构造入口通过但使用时不可读的场景，断言 writer 侧失败而非静默继续）。
6. 运行范围以 plan §6.2 为唯一事实源：`cmd-06` = `register-tx.test.mjs` + `owner-source-scan.test.mjs`（后者由 TASK-15 新建）；`cmd-04` = `crctl.test.mjs` 单文件（owner／source 写入前校验缝用例面）。真实执行输出落 `test-evidence/cmd-06.log`、`test-evidence/cmd-04.log`，不新增 plan 未列命令。

## 完成标志

- 三态行为、双防线与零写入／幂等均有断言覆盖；`cmd-04` 真实执行退出码 0 并留证（`cmd-06` 完整通过以 TASK-15 完成为条件）；
- 待核实依赖的核实结论（含入口、符号、分支选择、可读性验证方式）原样写入本 TASK 结果；
- `requirement-authoring.pipeline.json` 的 `source` 不再 `required`，`requirement-register/SKILL.md` 与 `handover-cr/SKILL.md` 文本同步落盘；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-13 产出，不得缩写）：
- 共用校验缝（owner 值域）与其「持久化前失败 → 零写入」语义；
- `async function cmdRegister(ws, flags)`（:3659）的注册事务入口与既有回滚能力（`rollbackOwnerWrite` 同类路径）。

产出（供 TASK-15／TASK-17 消费，消费方不得缩写）：
- `source` 值域（E1，逐字）：`source: "" | "<knowledge-base 内相对路径，注册时可读且 containment 通过>"`；
- 校验缝两处：**注册前**（`cmdRegister` 持久化前）与**使用前**（writer 侧同一检查防线），二者判定口径一致、后者不可被前者取代；
- 失败语义：上传／读取／入库失败与越界／不可读均为明确失败并停止注册（零写入），不静默降级；
- 核实结论记录（写入本 TASK 结果，供 TASK-17 的实际发布生效核对消费）：桥接入口、稳定符号、所选分支、CR worktree 可读性验证方式。
