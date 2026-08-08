---
cr: CR-2026-025
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-09T03:10:10+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-025/test-evidence/cmd-01.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs", exit: 0, log: "change-requests/CR-2026-025/test-evidence/cmd-02.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs", exit: 0, log: "change-requests/CR-2026-025/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-025/test-evidence/cmd-04.log" }
  - { command: "node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-025/test-evidence/cmd-05.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-025/test-evidence/cmd-06.log" }
---

# 测试报告 · CR-2026-025

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-025/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-025/test-evidence/cmd-01.log |
| 2 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 0 | change-requests/CR-2026-025/test-evidence/cmd-02.log |
| 3 | `node --test skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` | 0 | change-requests/CR-2026-025/test-evidence/cmd-03.log |
| 4 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-025/test-evidence/cmd-04.log |
| 5 | `node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-025/test-evidence/cmd-05.log |
| 6 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-025/test-evidence/cmd-06.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## 测试摘要

- 6 条验证命令全部 exit 0，`status: pass`（FR-22 验证关卡）。
- 测试执行目录：tools 仓（`custom/main`，CR-2026-024 批次一已合入前提满足）。
- 测试文件三件：`crctl.test.mjs` 108 例、`lint-prompts.test.mjs` 19 例、`check-skill-matrix.test.mjs`（新建，8 例），共 135 例全绿。

## TASK 验收覆盖矩阵

| TASK | 验收锚点 | 证据 | 状态 |
|---|---|---|---|
| TASK-01 依赖守卫 | FR-6~FR-8/FR-10，AC-7~AC-10 | crctl.test.mjs 守卫①~⑦（前置未 done/全 done/缺失空数组/悬空/引号等价/SCHEMA_INVALID/环） | pass |
| TASK-02 回显收敛 | FR-11~FR-15，AC-12~AC-15 | crctl.test.mjs 回显①~⑦（超长 blockers 截断/advance message 无原文/equals 零变化/标量路径/空数组通过） | pass |
| TASK-03 三账本一致写 | FR-16~FR-21，AC-19~AC-23 | crctl.test.mjs 投影①~④/路由⑤⑥⑦⑧+回归（三 stage 投影/两轮历史/TD-BL-4 首写/TRACE_SHAPE 原子不落盘/摘要路由 8 态） | pass |
| TASK-04 checker 检查 4 | FR-1~FR-5，AC-1~AC-6 | check-skill-matrix.test.mjs ①~⑧ + 真实仓实跑（AC-5：4 项声明引用点齐全） | pass |
| TASK-05 声明面 | FR-4，AC-4 | 两 checker 实跑全绿（注释不干扰解析） | pass |
| TASK-06 文档/Prompt | FR-9，AC-11 | lint-prompts enforce 0 findings（P-2~P-4 无 CONTRADICTS/STALE）；grep 确认三处不再指导手写投影 | pass |
| TASK-07 验证/登记 | FR-22~FR-24，AC-16/AC-17 | 三件套 + 三测试文件全绿；ARCHITECTURE.md §8 已登记；commit 溯源含 CR 编号；`C:\\Users` 零命中 | pass |

## 新增/修改测试文件

- 新建：`skills/shared/crctl/scripts/test/check-skill-matrix.mjs`（该脚本首个测试，B-13 缺口闭合）。
- 追加：`crctl.test.mjs`（TASK-01 七类 + TASK-02 七类 + TASK-03 九类向量）。

## 未覆盖风险与不适用说明

- **CAS 并发注入（不适用，有兜底）**：FR-21 ④的 CAS 读后改时序黑盒无法构造，沿用 CR-2026-019 先例——`casWriteMulti` 三阶段原子语义已有组件级向量兜底，本 CR 以 TRACE_SHAPE 结构错误覆盖“三文件均不落盘 + payload 保留”。
- **AC-17 的绝对路径检查**：仅对本 CR 四个代码/测试文件 grep 零命中；文档面（SKILL/yml/md）不含路径。
- **openwiki 表述同步**：已顺手同步 3→4 项检查描述（SDD §7 已知缺口，非门禁面）。

## 下一步建议

- 本 CR 代码与文档已全部落地（tools 仓 7 个 commit），CR worktree 待提交 test-report 与 traceability 证据。
- 按用户指示跳过 review-code；后续如需补审，`review-annotations/code.yml` 证据缺失时 `crctl next` 会指向 review-code。
