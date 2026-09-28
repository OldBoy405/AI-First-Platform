---
spec-id: ai-first-platform
version: "0.44"
id: CR-2026-071-TASK-05
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: 全量验证与交付记录（含 AIFI-35 零改动核验）
slug: full-verification-and-delivery
status: pending
estimate: 2h
depends-on: [CR-2026-071-TASK-02, CR-2026-071-TASK-03, CR-2026-071-TASK-04]
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-05 — 全量验证与交付记录（含 AIFI-35 零改动核验）

## 1. 任务描述

- 目标：跑通 plan §6 证据命令表 cmd-01～cmd-14，完成 plan §5 checklist（cmd 全绿、四份 `agent get` 成品一致、AIFI-35 六证据零变化合取：Issue 三证据 cmd-08～cmd-10 + 文件账本三证据 cmd-11～cmd-13 + 非空阳性对照 cmd-14），形成交付记录说明 P0/P1 实现、所跑测试、线上核验及未覆盖边界（AC-6）。B-03：`crctl checkpoint` 发布是 `review-dev-plan` PASS 分支的职责，不是本 TASK 的完成前置。
- 背景：本 TASK 无新增代码，是 M4 会合验证点；跨仓依赖仅在此会合（multica 与 tools 无共享代码依赖，SDD §1）。
- 输入条件：TASK-02（tools 三文件）、TASK-03（合同 + 回归）、TASK-04（bak + 线上同步）全部完成；`plan.md` §5/§6、`sdd.md` §6 AC 映射与 §9 批准范围。

## 2. 涉及文件 / 模块

- 只读执行（不修改被测文件）：multica CR worktree 根执行 cmd-01；tools CR worktree 根执行 cmd-02、cmd-03。
- 只读核验：四个线上 Agent 的 `agent get` 成品（plan cmd-04～cmd-07；复用 TASK-04 留存原文做一致性比对，不重复更新线上指令）。
- 只读核验：AIFI-35 六证据合取——Issue 面 cmd-08（根 id 集合与基线一致、新根零新增）与 cmd-09（对 cmd-08 输出的每一个根 id 执行模板命令读尾 30 条，无新增评论 id、无 reviewer verdict、无新 reviewer run）与 cmd-10（Issue 对象 `status`/`revision`/`updated_at` 与基线一致），文件账本面 cmd-11（`change-requests/CR-2026-001` 目录 diff 正文空 + 回执绿）与 cmd-12（`_backlog.yml` 统一 diff 正文无 `CR-2026-001` 行 + 回执绿）与 cmd-13（`_history.yml`/`_index.yml` diff 正文空 + 回执绿；判定口径见 plan.md §6 机械判定，含 cmd-14 非空阳性对照）与 cmd-14（无路径限定全量 `--stat` 正文非空且文件集仅本 CR 路径 + `_backlog.yml`）；文件账本面锚定分支-vs-trunk 合并基点（`merge-base origin/master HEAD`），作用域声明同 plan.md §5；本 CR 的 `approval.yml`、`merge-commits.yml`（如有）、checkpoint 元数据为审计事实来源，不进 TASK ledger。
- 本 TASK 落盘物：仅交付记录文本（实现/测试/核验/边界说明），不新建提示词、合同、Pipeline 节点文件，不执行 checkpoint/发布（B-03）。

## 3. 实现要点

- 按 plan §6 证据命令表逐条执行：cmd-01 `node --test cr-prompts-revised/test/delegation-contract.test.mjs`（multica worktree 根，timeout 120）；cmd-02 `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（tools worktree 根，timeout 120）；cmd-03 `node -e "JSON.parse(...requirement-authoring.pipeline.json...)"`（tools worktree 根，timeout 60）；cmd-04～cmd-07 四个线上 `agent get`（任意 cwd，timeout 60）；cmd-08 根扫描 + cmd-09 逐根尾读 + cmd-10 Issue 对象（任意 cwd，timeout 60）；cmd-11～cmd-14 受控 `crctl git` 只读 diff（`executable`/`args` 照抄证据命令表行，不改写算法、不删 `--workspace`/`--cwd` 选址参；表行在 `CRCTL_WORKSPACE` 指向主仓时仍落 KB CR worktree，timeout 60）。`cwd` 为各 worktree 根，executable 直接 spawn，无 shell 内建/管道/重定向。
- AIFI-35 基线（B-02 复评可执行对照）：本 TASK 启动时依次记录——(a) cmd-08 输出的根 id 全集合（含每根 `reply_count`/`last_activity_at`）；(b) 对每个根执行 cmd-09 模板所得尾部评论 id 序列；(c) cmd-10 的 `status`/`revision`/`updated_at`；(d) 文件账本锚定：`crctl git rev-parse origin/master` 与 `crctl git rev-parse HEAD`（KB worktree，40 位审计基线）+ cmd-11/cmd-12/cmd-13 当次输出原文。全部验证完成后复测逐项比对一致才算通过；任一新增（新根、新评论 id、verdict 评论、新 reviewer run、Issue 对象变化、CR-2026-001 目录非空 diff、`_backlog.yml` 出现 `CR-2026-001` 行、`_history.yml`/`_index.yml` 非空 diff）即失败（上报人类，不得静默覆盖）。cmd-08 不得单独用作线程内 verdict 证据；cmd-10 不得单独用作文件级零 diff 证据（判据窄化见 plan.md §6）；cmd-11/cmd-13 按 plan.md §6 机械判定执行（回执绿 ∧ 正文去空白后为空；`exit==0` 本身不证明零差异，raw stdout 永不为空），并须配 cmd-14 全量 `diff --stat origin/master HEAD` 非空阳性对照（表行可执行命令，正文非空且文件集仅本 CR 路径 + `_backlog.yml`，防错路径假空；阳性对照缺失/为空时不得判通过）。若复测时 trunk 前移（(d) 两值变化），如实记录新旧值并以复测时 trunk 为准，不得静默。
- 交付记录列 P0/P1 实现、所跑测试、线上核验原文索引、未覆盖边界（含 SDD §9 follow_up：reviewer 提交禁令二选一、平台未来新增 status 跟进 CR、bak 排除副本重启用须补回归）。

## 4. 验收条件

1. cmd-01～cmd-14 在各自 worktree 根/工作区全部绿灯（全绿输出留存，任一红灯即失败，不静默覆盖；双向引用 plan.md §6 两张稳定表；cmd-09 为逐根模板，每个根一次执行均须绿灯；cmd-11/cmd-13 按 plan.md §6 机械判定通过——回执绿 ∧ 正文空——且附 cmd-14 全量 `--stat` 非空阳性对照）。
2. plan §5 checklist 全闭：cmd 全绿、四份 `agent get` 成品与合同逐字一致（原文留存；与 TASK-04 留存比对一致）、AIFI-35 六证据（cmd-08～cmd-13）与 cmd-14 阳性对照与基线一致且作用域声明已入交付记录。
3. 交付记录已形成，含 P0/P1 实现、所跑测试、线上核验、未覆盖边界四节（含 SDD §9 follow_up：reviewer 提交禁令二选一、平台未来新增 status 跟进 CR、bak 排除副本重启用须补回归；以及本 TASK 的 AIFI-35 作用域声明）；文件侧范围按 plan.md §6 文件侧范围核验标准执行（B-02 复评；禁止原生 git）：启动记 BASE，完成后 `crctl git log --oneline -5` 定位提交 C，`crctl git diff --stat BASE C --cwd <知识库 CR worktree>` 须恰为交付记录文本文件集，`crctl git status --short` 须干净；未修改提示词/合同/Pipeline/测试正文。

## 5. 完成标志

- 十三条证据命令输出已留存（cmd-09 按根数折叠计数），checklist 全闭，交付记录已落盘；验收条件 1～3 全部通过。本 TASK 的完成边界是 `developing` 内可被 `crctl task done` 登记的事件（验证输出留存 + 交付记录形成），B-03：完成前置与完成边界统一，不含 checkpoint/发布/merge/审批的流程控制语义（审计事实以 checkpoint 元数据与 approval.yml 为准，不进 TASK ledger）。

## 6. 接口契约

- 消费：上游 TASK-02 的 Pipeline 节点序列与结构测试绿灯、TASK-03 的 cmd-01 绿灯与合同文本、TASK-04 的四份 `agent get` 成品原文与 bak 审计结论。消费形态为文件文本与命令绿灯结论，无函数签名（SDD §3：判定逻辑是自然语言规则 + 离线回归脚本）。
- 产出：交付记录文本（P0/P1/测试/核验/边界）；无下游 TASK，无新暴露签名。
- 共享契约锁定：本 TASK 不引入新契约；仅复述上游三方的既有契约结论，不转述、不缩略；任一上游结论为红，本 TASK 即失败，不掩盖。
