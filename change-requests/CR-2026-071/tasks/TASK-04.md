---
id: CR-2026-071-TASK-04
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: bak 副本审计与四个线上 Agent 指令同源同步
slug: bak-audit-and-agent-sync
status: pending
estimate: 2h
depends-on: [CR-2026-071-TASK-01, CR-2026-071-TASK-03]
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-04 — bak 副本审计与四个线上 Agent 指令同源同步

## 1. 任务描述

- 目标：审计 `bak/` 目录用途并修正仍可部署副本的同类漂移（或留排除理由），以合同源全文为唯一输入同步四个线上 Agent instructions 并逐个 `agent get` 核验（FR-2，AC-3）。
- 背景：dep-4 确认 `bak/cr-coordinator-agent.md:45` 与 `bak/quality-reviewer-agent.md:67` 含同类漂移、其余 bak 文件无委派子句；线上 dev-agent 与 cr-coordinator-agent 已取证含 `enqueued` 语义。
- 输入条件：TASK-01 四份提示词成品、TASK-03 合同源全文（**文本**；B-01：不以 TASK-03 的 cmd-01 全绿为前置，bak 漂移由本 TASK 修复）；`sdd.md` §4.1 bak 段落与 §4.2、`plan.md` §1/M3 与证据命令表 cmd-01/cmd-04～cmd-07；multica CR worktree 可读写；执行线上同步的身份具备 `multica agent update/get` 权限（owner Ray）。

## 2. 涉及文件 / 模块

- multica CR worktree 内修改/留痕：`cr-prompts-revised/bak/` 下全部文件——仍可作为部署来源的副本按 SDD §4.1 全文同等修正；确认不再部署的副本在该目录留一行排除理由（不删文件保历史可追溯）。
- 线上（只读核验 + 定向更新，不更换 ID/绑定）：`requirement-writer`（`6317495b…`）、`dev-agent`（`ff6fcbb6…`）、`quality-reviewer-agent`（`2ed1a9de…`）、`cr-coordinator-agent`（`87ca2271…`）四个 Agent 的 instructions，仅替换委派判定段落。
- 本 CR 知识库 worktree 内新建（回滚快照，B-04）：`change-requests/CR-2026-071/agent-snapshots/<agent>-before.json`（4 个文件：requirement-writer/dev-agent/quality-reviewer-agent/cr-coordinator-agent 更新前 `agent get` 全文），随本 TASK 文件侧改动同批受控提交，是线上故障取证输入；恢复源按 §3 分级（首选合同正文，快照仅清洁时可用），快照不默认等于安全回滚目标（B-04 复评）。
- 只读取证：AIFI-35 评审结果与账本（zero_diff 兜底，不触发其 reviewer）。

## 3. 实现要点

- 参考 SDD §4.2：更新任一线上 Agent 之前，先 `multica agent get <id> --output json` 取更新前全文落盘快照（§2 4 个文件）；再以合同源全文为唯一输入，经 `multica agent update <id>` 更新四个线上 Agent instructions，仅替换委派判定段落，其余职责、绑定、skill 列表原样保留，不更换 ID。
- 逐个执行 plan cmd-04～cmd-07（`multica agent get <id> --output json`）核验成品含规范三元组且无 `enqueued` 成功语义、无 `target_unavailable` status 语义；任一不符即失败，不得以"文件已改"代替线上交付。
- bak 审计结论落盘（保留/排除理由）；更新范围限定判定段落原文替换。
- 在线回滚（B-04；复评 2/3 深化，`git revert` 不能恢复线上指令）：回滚线上侧不用 revert，按 plan.md §4 R2 分级执行——(a) 首选向前恢复到合同正文（`multica agent update <id>` 写入 TASK-03 合同判定段落）再用对应 cmd-04～cmd-07 重验，绿灯方可继续；(b) 快照（§2 4 文件）仅在其自身已过清洁判据时可用作恢复源；(c) 若快照本身含 `enqueued` 成功语义（复评实测当前 dev-agent 与 cr-coordinator-agent 即属此类），写回即重现故障，定义为故障中止：停止、不进 TASK-05、停用受影响 Agent 的后续委派验证、在交付记录留名并报告 `status`/`reason_code` 两侧事实，由 Ray 确认处置。责任 dev-agent 执行、Ray（Agent owner）确认。文件侧回滚经受控 `crctl git revert --no-edit <commit>`（禁止原生 git），文件侧 revert 永不触碰线上 instructions。完整策略见 plan.md §4 R2。

## 4. 验收条件

1. "需维护" bak 集合中每个文件均通过回归的无漂移断言（含规范三元组与豁免子句、无 `enqueued` 成功语义）；排除副本各有留痕的一行排除理由。
2. plan cmd-01 在 multica worktree 根全绿（含 bak 集合；本 TASK 修正 bak 后达成——B-01 的全绿门禁落点，双向引用 plan.md §6 FR-2/FR-3 行）。
3. plan cmd-04～cmd-07 四个线上 Agent 的 `agent get` 成品原文均与合同源逐字一致（`enqueued` 成功语义与 `target_unavailable` status 语义双清零），四份原文留存交付记录备查。
4. 更新前快照 4 文件（§2 `agent-snapshots/`）已落盘并随本 TASK 同批受控提交；AIFI-35 前置只读确认执行 plan cmd-08（新根零新增）+ 对既有每根执行 cmd-09 模板（尾 30 条零新增 verdict）+ cmd-10（Issue 对象记录基线供 TASK-05 比对）+ 文件账本面 cmd-11（CR-2026-001 目录 `--stat` 空）+ cmd-12（`_backlog.yml` 统一 diff 无 `CR-2026-001` 行）+ cmd-13（`_history.yml`/`_index.yml` `--stat` 空）；文件账本面锚定分支-vs-trunk 合并基点（`merge-base origin/master HEAD`，三仓远端无 CR-2026-001 live 分支故不对 live 工作区比对，作用域声明同 plan.md §5）；不触发委派；完整合取验收归 TASK-05 cmd-08～cmd-13，本 TASK 只做前置只读确认。
5. 文件侧范围核验按 plan.md §6 文件侧范围核验标准执行（B-02 复评；禁止原生 git；双向引用 plan.md §6 FR-2/FR-3 行）：multica 侧启动记 BASE（`crctl git rev-parse HEAD --cwd <multica CR worktree>`），完成后 `crctl git log --oneline -5` 定位提交 C，`crctl git diff --stat BASE C --cwd <multica CR worktree>` 文件集须恰为 bak 修正/排除留痕集合；知识库侧同三步，文件集须恰为 4 个快照文件；两侧 `crctl git status --short` 均须干净。

## 5. 完成标志

- bak 修正/排除理由已落盘，更新前快照 4 文件已提交，四份线上指令已同步且 cmd-01/cmd-04～cmd-07 核验通过，验收条件 1～5 全部通过；线上核验原文已留存交付记录；本 TASK 实际产生的文件修改与线上同步记录已由本 TASK 落实登记，不预登记 TASK-05 的全量验证记录。

## 6. 接口契约

- 消费：上游 TASK-01 的四份提示词判定段落原文、上游 TASK-03 的合同源全文（线上同步唯一输入）与回归绿灯结论。消费形态为 Markdown 文本，不涉及函数签名（SDD §3：线上同步经既有 `multica agent update/get` 通道，无新接口）。
- 产出：下游 TASK-05 消费本 TASK 的四份 `agent get` 成品原文（AC-3 证据）与 bak 审计结论；产出形态为线上指令文本 + 交付记录，不暴露函数签名。
- 共享契约锁定：线上四份判定段落、源四份提示词、合同源三方必须逐字一致；任一字差异即为交付失败，不得以"文件已改"代替。
