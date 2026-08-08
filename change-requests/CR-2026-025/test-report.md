---
cr: CR-2026-025
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-09T03:53:17+08:00"
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

- 6 条验证命令全部 exit 0，`status: pass`（FR-22 验证关卡）；测试执行目录：tools 仓 `custom/main`。
- 测试文件三件：`crctl.test.mjs` 111 例、`lint-prompts.test.mjs` 19 例、`check-skill-matrix.test.mjs` 8 例，共 138 例全绿。
- 本报告为**回修轮（代码评审 attempt-1 后）重跑**：修复 4 个 blocker 后重新落盘。

## TASK 验收覆盖矩阵

| TASK | 验收锚点 | 证据 | 状态 |
|---|---|---|---|
| TASK-01 依赖守卫 | FR-6~FR-8/FR-10，AC-7~AC-10 | crctl.test.mjs 守卫①~⑦ + 回修 BL-1（malformed tasks 根 `TASK_INDEX_SHAPE`） | pass |
| TASK-02 回显收敛 | FR-11~FR-15，AC-12~AC-15 | crctl.test.mjs 回显①~⑦ | pass |
| TASK-03 三账本一致写 | FR-16~FR-21，AC-19~AC-23 | crctl.test.mjs 投影①~④/路由⑤⑥⑦⑧+回归 + 回修 BL-2（stage null）/BL-3（重复顶层 reviews） | pass |
| TASK-04 checker 检查 4 | FR-1~FR-5，AC-1~AC-6 | check-skill-matrix.test.mjs ①~⑧ + 真实仓实跑（AC-5） | pass |
| TASK-05 声明面 | FR-4，AC-4 | 两 checker 实跑全绿 | pass |
| TASK-06 文档/Prompt | FR-9，AC-11 | lint-prompts enforce 0 findings | pass |
| TASK-07 验证/登记 | FR-22~FR-24，AC-16/AC-17 | 三件套 + 三测试文件全绿；ARCHITECTURE.md §8 已登记；提交溯源齐全（含回修 BL-4 改写后的 4659fbf） | pass |

## 回修轮（代码评审 attempt-1，4 blocker）

| Blocker | 修复 | 回归向量 |
|---|---|---|
| BL-1（Critical）guardDependsOn 对缺失/非数组 tasks 根静默降级 | 顶层映射与 `tasks` 列表形状硬失败，复用 `TASK_INDEX_SHAPE`，禁止空集合绕过守卫 | 回修 BL-1：两种 malformed 根 → 退出非 0、文件哈希不变 |
| BL-2（Major）`reviews.<stage>: null` 被视同合法首写 | 仅 `undefined` 可首写；null 与非映射形态 → `TRACE_SHAPE` | 回修 BL-2：三账本不变 + payload 保留 |
| BL-3（Major）重复顶层 `reviews:` 段静默编辑首段 | 顶层 `reviews:` 段必须唯一，重复 → `TRACE_SHAPE` 原子拒写 | 回修 BL-3：trace/annotation 均不落盘 |
| BL-4（Major）commit 5e0629e 缺来源溯源 | 脚本化 rebase 改写为 4659fbf，消息含方案 v2.6 §7 + CR-2026-024 SDD 评审实测 + CR-2026-025 需求评审发现；未夹带无关工作区修改 | `git log` 核对消息与变更内容一致 |

## 新增/修改测试文件

- 新建：`skills/shared/crctl/scripts/test/check-skill-matrix.mjs`。
- 追加：`crctl.test.mjs`（TASK-01~03 向量 + 回修 BL-1~BL-3 三个负向向量）。

## 未覆盖风险与不适用说明

- **CAS 并发注入（不适用，有兜底）**：`casWriteMulti` 三阶段原子语义已有 CR-2026-019 组件级向量兜底，本 CR 以 `TRACE_SHAPE` 结构错误覆盖原子拒写。
- **AC-17 绝对路径检查**：代码/测试文件 grep `C:\\Users` 零命中。

## 下一步建议

- 4 blocker 已全部修复并重跑验证；按用户指示由用户本人负责代码评审，评审证据（attempt-1 block）已落盘 `review-annotations/code.yml`。
- 重审时以 `crctl next` 为准（pass 后进入人工审批）。
