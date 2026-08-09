---
cr: CR-2026-026
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-09T13:55:00+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-026/test-evidence/cmd-01.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs", exit: 0, log: "change-requests/CR-2026-026/test-evidence/cmd-02.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs", exit: 0, log: "change-requests/CR-2026-026/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-026/test-evidence/cmd-04.log" }
  - { command: "node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-026/test-evidence/cmd-05.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-026/test-evidence/cmd-06.log" }
---

# 测试报告 · CR-2026-026

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-026/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-026/test-evidence/cmd-01.log |
| 2 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 0 | change-requests/CR-2026-026/test-evidence/cmd-02.log |
| 3 | `node --test skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` | 0 | change-requests/CR-2026-026/test-evidence/cmd-03.log |
| 4 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-026/test-evidence/cmd-04.log |
| 5 | `node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-026/test-evidence/cmd-05.log |
| 6 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-026/test-evidence/cmd-06.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## 测试摘要

- 6 条验证命令全部 exit 0，`status: pass`（FR-19 验证关卡）；测试执行目录：tools 仓 `custom/main`（commit 6134b11）。
- 测试文件三件：`crctl.test.mjs` 116 例（含本 CR 新增 dev-plan 向量 5 例）、`lint-prompts.test.mjs` 19 例、`check-skill-matrix.test.mjs` 8 例，共 143 例全绿。

## TASK 验收覆盖矩阵

| TASK | 验收锚点 | 证据 | 状态 |
|---|---|---|---|
| TASK-01 crctl 映射与路由 | FR-4/FR-6/6a/6b/FR-14，AC-7/AC-8/AC-8a/AC-8b | crctl.test.mjs CR-2026-026 ①~⑤（映射落盘/repair-target schema/UPSTREAM bump 跳过/NORMAL 递增/并存优先） | pass |
| TASK-02 gates 与状态机 | FR-10~FR-13，AC-10/AC-11/AC-11a/AC-12 | gates.json 三处 + dir-graph 两条转换；既有 111 例回归全绿（developing 门禁新增条件未破坏 AC-2b/AC-11 等存量用例） | pass |
| TASK-03 review-dev-plan Skill | FR-15，AC-15a | lint-prompts enforce 0 findings（新 SKILL 无漂移）；check-skill-matrix 通过（57 active skill） | pass |
| TASK-04 回修支持 | FR-8/FR-9 | write-dev-plan/write-dev-tasks 含 review_feedback/self_repair_attempt/fixed-blockers；approve-dev-start 含 passCondition 表述；lint-prompts 0 findings | pass |
| TASK-05 pipeline 与登记 | FR-1/FR-16，AC-15a | pipeline JSON 合法（14 节点、UUID 无重复、顺序 write-dev-tasks→review-dev-plan→push-progress）；check-skill-matrix/check-agents-contract 通过 | pass |
| TASK-06 文档同步 | FR-17，AC-15a | README 流程/状态机图/节点表、ARCHITECTURE §8 登记（25→27 声明 / 47→49 展开）、crctl SKILL 用途表、AGENT-SKILL-MATRIX.md 表格均同步 | pass |
| TASK-07 测试与回归 | FR-19，AC-15 | 三测试文件 143 例全绿 + 三件套全绿；状态机口径断言由既有 advance 用例覆盖 | pass |

## 新增/修改测试文件

- 追加：`crctl.test.mjs`（CR-2026-026 ①~⑤ 五例：dev-plan 三账本落盘、repair-target schema、UPSTREAM bump 跳过、NORMAL 递增、并存优先）。
- 说明：dev-start/developing 门禁负向向量（⑥⑦⑧）与 LOOP_EXHAUSTED（⑨）依赖 TTY 人工审批与完整 approval fixture，按 plan.md §5 checklist 由开发启动审批前的人工验收承担（本次开发启动审批在旧门禁下已通过，新门禁随本 CR 生效）。

## 未覆盖风险与不适用说明

- **dev-start/developing 新门禁的黑盒负向向量（不适用，人工验收）**：`crctl approve --stage dev-start` 非 TTY 直接拒绝（不变量 7），黑盒无法构造「评审未通过仍审批」场景；AC-10/AC-11a 的 GATE_BLOCKED/developing 拦截由人工在真实流程验证（plan.md §5 checklist 第 4-6 项）。
- **LOOP_EXHAUSTED 三轮上限（部分覆盖）**：`readAttempts` 的 maxAttempts 读取逻辑由既有 attempt 测试覆盖；dev-plan 三轮耗尽场景与 requirement/code 同构，复用同一 LOOP_EXHAUSTED 路径。
- **AC-17 绝对路径检查**：代码/测试文件 grep `C:\\Users` 零命中。

## 下一步建议

- 按用户指示**跳过代码评审**（review-code），直接进入开发启动后的收尾：提交本 test-report 与 traceability#tests，推送 checkpoint。
- 归档前按 plan.md §5 checklist 在真实流程补验 dev-start 新门禁（随本 CR 生效后首个进入开发启动的 CR 即覆盖）。
