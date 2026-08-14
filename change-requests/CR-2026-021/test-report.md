---
cr: CR-2026-021
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-05T16:23:52+08:00"
commands:
  - { command: "node --test test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-021/test-evidence/cmd-01.log" }
  - { command: "node --test test/lint-prompts.test.mjs", exit: 0, log: "change-requests/CR-2026-021/test-evidence/cmd-02.log" }
  - { command: "node lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-021/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-021

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-021/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test test/crctl.test.mjs` | 0 | change-requests/CR-2026-021/test-evidence/cmd-01.log |
| 2 | `node --test test/lint-prompts.test.mjs` | 0 | change-requests/CR-2026-021/test-evidence/cmd-02.log |
| 3 | `node lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-021/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## 测试摘要

- **TASK 状态**：TASK-01~22 全部 `done`（见 `tasks/_index.yml`），验收覆盖 **22/22**。
- **crctl 子命令面（S1~S11+inbox-emit）**：`crctl.test.mjs` 82 用例全绿，覆盖 review-record / review-note / checkpoint-add / owner-set / backlog-set / inbox-emit / next-cr-id / cr-init / task allocate / worktree-path / report / cr-metrics / git commit --template / test / attempt 等写口与只读口，含 CAS、前置态守卫、schema 校验、白名单拒绝路径。
- **lint-prompts 漂移防线（R1~R6）**：`lint-prompts.test.mjs` 10 用例全绿；`--mode enforce` 全量扫描 tools 仓 **0 findings**（prompt 与 crctl 无漂移），exit 0 通过——本 CR 核心交付（根治机制）验证成立。

## TASK 验收覆盖矩阵

| TASK | 验收要点 | 验证证据 |
|------|---------|---------|
| 01 | D13 溯源调查结论（不复活） | investigations/d13-schema-validator.md 已落盘 |
| 02~09 | crctl 新子命令 S1~S11+inbox-emit | crctl.test.mjs 对应用例全绿 |
| 10 | 文档 + rules.json git 白名单 | git ls-remote 带分支 shape 用例 |
| 11~12 | lint-prompts + pre-commit/CI 接线 | lint-prompts.test.mjs 全绿；pre-commit 已切 enforce |
| 13~15 | Phase 1（D7 三字段 / approve 折叠 / 裸 git 迁移 / test-report） | crctl.test.mjs 对应用例 + 本报告即产物 |
| 16 | cr-status-set 清退 | 全仓无残留调用 |
| 17~21 | Phase 3 prompt 收敛（S1~S11 改调） | lint-prompts enforce 0 findings |
| 22 | Phase 4 收尾 + enforce 切换 | enforce 首笔提交自举通过（commit 30b952c） |

## 新增 / 修改测试文件

- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增用例，82 全绿）
- `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`（新建，10 全绿）

## 未覆盖风险

- **lint / build 不适用**：crctl 为零依赖 node 单文件 CLI（仅 node 内置模块），tools 仓无 pnpm 工程与构建步骤；`node --test` 即 lint+test+build 三重验证载体，故不另设 lint/build 命令。
- **CI cr-guard 真实触发未验证**：本环境无远端仓库，`.github/workflows/cr-guard.yml` 中 lint-prompts enforce 步骤的 CI 实际执行无法在本环境端到端验证（plan.md 已显式标注）；pre-commit 本地方向已自举验证。

## 下一步建议

测试证据齐备（status=pass），可进入 `review-code` 节点；评审通过后 `crctl advance --to code-reviewing`，等待人工 `approve --stage code`。

