---
cr: CR-2026-041
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-15T23:39:23+08:00"
commands:
  - { command: "node --check skills/writeback/scripts/writeback-traceability.mjs && node --check skills/shared/crctl/scripts/lib/workspace-transactions.mjs", exit: 0, log: "change-requests/CR-2026-041/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/writeback.test.mjs", exit: 0, log: "change-requests/CR-2026-041/test-evidence/cmd-02.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/contract-scan.test.mjs skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs skills/shared/crctl/scripts/test/check-agents-contract.test.mjs skills/shared/crctl/scripts/test/lint-prompts.test.mjs", exit: 0, log: "change-requests/CR-2026-041/test-evidence/cmd-03.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/pipeline-structure.test.mjs skills/shared/crctl/scripts/test/upgrade-check.test.mjs", exit: 0, log: "change-requests/CR-2026-041/test-evidence/cmd-04.log" }
  - { command: "node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs", exit: 0, log: "change-requests/CR-2026-041/test-evidence/cmd-05.log" }
---

# 测试报告 · CR-2026-041

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-041/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --check skills/writeback/scripts/writeback-traceability.mjs && node --check skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 0 | change-requests/CR-2026-041/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | 0 | change-requests/CR-2026-041/test-evidence/cmd-02.log |
| 3 | `node --test skills/shared/crctl/scripts/test/contract-scan.test.mjs skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs skills/shared/crctl/scripts/test/check-agents-contract.test.mjs skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 0 | change-requests/CR-2026-041/test-evidence/cmd-03.log |
| 4 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/pipeline-structure.test.mjs skills/shared/crctl/scripts/test/upgrade-check.test.mjs` | 0 | change-requests/CR-2026-041/test-evidence/cmd-04.log |
| 5 | `node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 0 | change-requests/CR-2026-041/test-evidence/cmd-05.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## 测试摘要

5 条验证命令全部 exit 0，跨 Tools 仓 requirement/CR-2026-041 worktree 执行。修复后重新验证了 generator、唯一 evidence validator、archive 证据门、退役契约和既有生命周期回归。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 验证证据 | 结果 |
|---|---|---|---|
| TASK-01 generator 注入 evidence 块并删 status | 七项 evidence 注入、固定 path map、无 status、缺证据 EVIDENCE_INVALID 零 candidate | `writeback.test.mjs`：evidence 注入、缺失/状态失败、13 项全通过 | pass |
| TASK-02 唯一 validator + --validate-evidence | 完整证据通过；缺失、重复块/键、路径互换、digest 漂移、verdict 非 pass 硬失败 | `writeback.test.mjs`：`--validate-evidence` 及 `EVIDENCE_DUPLICATE` 回归 | pass |
| TASK-03 事实源修正 | trunk 缺条目 TRUNK_UNKNOWN 硬失败、无 master 回退 | `writeback.test.mjs`：trunk 缺条目测试 | pass |
| TASK-04 archive 证据门适配 | 证据齐全归档成功；漂移/缺失 ARCHIVE_EVIDENCE_* 且零 journal/authority | `archive-tx.test.mjs`：17 项全通过，含两例 CR-2026-041 证据门 | pass |
| TASK-05 milestone-file 契约去 status | 新 milestone 不写瞬时 status | generator fixture 与 `lint-prompts` 回归 | pass |
| TASK-06/07 退役 | active 路径零引用、Skill 目录删除 | `contract-scan`、`check-skill-matrix`、`check-agents-contract` | pass |
| TASK-08 测试与回归 | FR-03 回归和既有生命周期无回归 | `writeback-tx`/`crctl`/`pipeline-structure`/`upgrade-check` 196 项全通过 | pass |

## 评审范围与结论

- 代码基线为 Tools `origin/custom/main` 的 merge-base `077d53a5`；CR 实际代码提交为 `a9012e5`，修复提交将在本次 checkpoint 中一并保存。
- 评审覆盖真实 diff、SDD、TASK-01 至 TASK-08、测试报告和本轮重新执行的验证命令。
- 修复前发现并修正了 evidence 重复结构可被覆盖的问题：validator 现在对重复 `evidence:` 块及重复 `test`/review/approval/merge 键返回 `EVIDENCE_DUPLICATE`。

## 新增/修改测试文件

- `skills/writeback/scripts/test/writeback.test.mjs`（generator evidence 注入、validator、--validate-evidence、TRUNK_UNKNOWN、重复结构）
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`（证据门漂移/缺失零 journal）
- `skills/shared/crctl/scripts/test/contract-scan.test.mjs`（退役静态扫描）
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（traceability 全链路补证据 fixture）

## 未覆盖风险

- **跨平台回归**：本轮在 Windows 验证；SDD §8 要求 Ubuntu/Windows 双平台。Ubuntu 侧未在本机执行（当前环境不适用），实现沿用 Node 标准库、LF 归一和 `shell:false`，无平台专属生产依赖，合并前仍需 CI/人工在 Ubuntu 补跑。
- **archive 证据门的 pre-authority 恢复路径**：已 commit/push 或 cleanup/complete 重放跳过证据门由既有幂等用例间接覆盖；未单独构造 pre-authority journal 存在且失败不改 journal 的直接用例。证据门在 journal 创建前 fail-fast，零 journal 已由缺失用例断言。
- **真实 CR 归档端到端**：本 CR 的 archive 证据门在 fixture 上验证；真实 writing-back CR 的归档仍需后续 merge/writeback 流程触发。

## 下一步建议

代码评审 verdict 已准备提交；通过后状态推进到 `code-reviewing`，等待人工 `approve-code`。
