---
cr: CR-2026-028
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-10T19:40:28+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-028/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/writeback.test.mjs", exit: 0, log: "change-requests/CR-2026-028/test-evidence/cmd-02.log" }
  - { command: "node --check skills/shared/crctl/scripts/crctl.mjs", exit: 0, log: "change-requests/CR-2026-028/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-028

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-028/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-028/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | 0 | change-requests/CR-2026-028/test-evidence/cmd-02.log |
| 3 | `node --check skills/shared/crctl/scripts/crctl.mjs` | 0 | change-requests/CR-2026-028/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 回修后验证摘要

- `crctl.test.mjs`：158/158 pass；新增相对/绝对 Tools Root 同 realpath、workspace 空壳零回退、linked-worktree 相对 Tools Root、有效 `CRCTL_RULES_PATH` 优先级场景。
- `writeback.test.mjs`：9/9 pass；`crctl.mjs` 与 hooks 语法检查通过。
- `check-skill-matrix`、`check-agents-contract`、`lint-prompts --mode enforce` 全绿。
- PRD §3.1 七个禁止模式与 `target_install_path` 定向检索均为零命中；两个 pipeline JSON 可解析；`git diff --check` 通过。

### TASK 验收覆盖

TASK-01～TASK-09 的实现与回归证据完整；第 1 轮代码评审的 CODE-BLOCK-001～004 均已通过提交 `a835c42` 修复。TASK-10 的 merge/发布联调仍按生命周期在代码人工审批后执行。

### 新增/修改测试文件

- `skills/shared/crctl/scripts/test/crctl.test.mjs`：累计新增 9 个 CR-2026-028 回归用例（含 AC-8 静态审查断言）。

### 未覆盖风险

- 真实 GitHub Actions 与各 IDE 安装物化仍需发布期联调；本 CR 不新增 installer 或 IDE E2E，符合范围排除。
- 双仓 merge 后主 checkout 走查留待 TASK-10。
