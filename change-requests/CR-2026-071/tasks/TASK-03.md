---
id: CR-2026-071-TASK-03
type: TASK
cr-ref: CR-2026-071
plan-ref: "change-requests/CR-2026-071/plan.md"
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
title: 共享委派合同源新建与漂移回归检查
slug: delegation-contract-and-regression
status: pending
estimate: 4h
depends-on: [CR-2026-071-TASK-01]
created: 2026-09-27T16:45:00+08:00
---

# CR-2026-071-TASK-03 — 共享委派合同源新建与漂移回归检查

## 1. 任务描述

- 目标：新建唯一规范合同源 `delegation-contract.md`，新增离线回归脚本 `delegation-contract.test.mjs`（`node --test` 零依赖），覆盖枚举对齐、无漂移、场景向量三组断言（FR-3，AC-1/AC-2/AC-4）。
- 背景：SDD §5 SDD-CLOSE-01/02 已关闭选型结论——合同源住 multica 仓、四份提示词内联全文、回归自持于 multica 仓。
- 输入条件：TASK-01 的四份提示词替换落点已就绪（本 TASK 依赖其替换文本做一致性核验）；`sdd.md` §4.1/§4.3、`plan.md` §1/M1 与证据命令表 cmd-01；multica CR worktree 可读。

## 2. 涉及文件 / 模块

multica CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-071`）内：

- 新建：`cr-prompts-revised/delegation-contract.md`（SDD §4.1 合同正文为唯一规范源）
- 新建：`cr-prompts-revised/test/delegation-contract.test.mjs`（三组断言，`node --test`，零第三方依赖；注释一律英文）
- 只读取证（不修改）：`server/internal/handler/admission.go`（dep-1/dep-2）、TASK-01 四份提示词成品、"需维护" bak 副本集合（由 TASK-04 审计定稿，本 TASK 按其集合覆盖）

## 3. 实现要点

- 参考 SDD §4.3：断言组 1 枚举对齐——从 `admission.go` 解析 `DispatchStatus` 字面量，断言合同成功集合 == `{queued,coalesced,deferred}` 且失败集合含 `blocked`；平台新增 status 字面量而合同未同步时失败。
- 断言组 2 无漂移——四份提示词 + "需维护" bak 副本逐文件含规范三元组与按目标/缺失 outcome/human-only 豁免子句，且不含 `enqueued` 成功语义；任一漂移失败。
- 断言组 3 场景向量 7 例 + 2 例否定：`queued` 成功（含 AIFI-35 `status=queued, reason_code=queued` 只读重放）、`coalesced` 成功、`deferred` 成功、`blocked + reason_code=target_unavailable` 失败、`blocked` + 其他 reason 失败、被 mention 目标缺失 outcome 失败、仅 mention 人类成员且评论成功不失败；另加未知 status 不成功、评论写入失败不报成功。判定函数实现即合同伪代码化，与 §4.1 逐字对应。

## 4. 验收条件

1. `node --test cr-prompts-revised/test/delegation-contract.test.mjs`（plan cmd-01）在 multica worktree 根全绿（含三组断言全部通过）。
2. 回归脚本逐字覆盖 SDD §4.1 合同正文：7 例场景向量 + 2 例否定全部通过；AIFI-35 回执重放判成功且零 `DELEGATION_FAILED`、零重复委派。
3. 合同源与 TASK-01 四份提示词判定段落逐字一致（`diff` 无差异）；`git diff --stat` / 新文件清单仅含上述两个新建文件，未触碰提示词正文（那是 TASK-01 的产物）。

## 5. 完成标志

- 上述两个新建文件已落盘，验收条件 1～3 全部通过；`node --test` 全绿输出已留存；本 TASK 实际产生的文件已由本 TASK 落实登记，不预登记 TASK-04 的线上同步记录。

## 6. 接口契约

- 消费：上游 TASK-01 产出的四份提示词判定段落原文（文件路径 + 判定段落全文）；SDD §4.1 合同正文（自然语言规则文本，非代码函数签名）。回归脚本只读三方（合同源、提示词/副本、平台枚举源），不写账本与状态。
- 产出：下游 TASK-04 消费本 TASK 的合同源全文（做线上指令同源同步的唯一输入）与回归脚本的绿灯结论；下游 TASK-05 消费本 TASK 的 cmd-01 全绿证据。产出形态为 Markdown 合同文本 + `node --test` 脚本。
- 共享契约锁定：合同源全文、四份提示词内联全文、回归脚本内嵌的判定函数三者必须逐字对应；任一字差异即漂移，由本 TASK 的无漂移断言捕获。
