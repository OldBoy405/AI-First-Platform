---
cr: CR-2026-031
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-12T16:33:34+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-02.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-04.log" }
  - { command: "node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-05.log" }
  - { command: "node ../../../multica/requirement/CR-2026-031/server/internal/governance/gen/generate-transitions.mjs --tools . --check", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-06.log" }
  - { command: "go -C ../../../multica/requirement/CR-2026-031/server test ./internal/governance/ -run Transition -count=1", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-07.log" }
  - { command: "go -C ../../../multica/requirement/CR-2026-031/server test ./internal/governance/ -run ActionConstants -count=1", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-08.log" }
  - { command: "go -C ../../../multica/requirement/CR-2026-031/server test ./pkg/gitguard/ -count=1", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-09.log" }
---

# 测试报告 · CR-2026-031

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-031/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-02.log |
| 3 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-031/test-evidence/cmd-03.log |
| 4 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-04.log |
| 5 | `node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-05.log |
| 6 | `node ../../../multica/requirement/CR-2026-031/server/internal/governance/gen/generate-transitions.mjs --tools . --check` | 0 | change-requests/CR-2026-031/test-evidence/cmd-06.log |
| 7 | `go -C ../../../multica/requirement/CR-2026-031/server test ./internal/governance/ -run Transition -count=1` | 0 | change-requests/CR-2026-031/test-evidence/cmd-07.log |
| 8 | `go -C ../../../multica/requirement/CR-2026-031/server test ./internal/governance/ -run ActionConstants -count=1` | 0 | change-requests/CR-2026-031/test-evidence/cmd-08.log |
| 9 | `go -C ../../../multica/requirement/CR-2026-031/server test ./pkg/gitguard/ -count=1` | 0 | change-requests/CR-2026-031/test-evidence/cmd-09.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 第二轮回修验证摘要

- crctl 全量：253/253 通过；writeback：10/10 通过。
- prompt lint：0 findings；skill matrix（57 active skill / 8 actor）、agent contract（9 agent）通过。
- multica transition generator `--check` 通过（source tools@c264157，28 条声明 / 50 条展开）。
- governance Transition/ActionConstants 与 `pkg/gitguard` Go 测试通过。

### 本轮关闭的最后 blocker

1. `approve`、`review-record`、`owner-set` 的多文件写已迁入 `durable-tx.mjs` 的 command-level ledger transaction，共用 journal envelope、目录锁和 recoverable write-set。
2. commit 前中断使用持久化 before snapshots 整组回滚并恢复 Git index；commit 后中断使用 `AI-First-Tx` trailer 确认 authority，只清理 journal，不重复 commit、不反向回滚。
3. 新增三个真实 CLI seam 的 rename 间隙 kill/restart 回归，以及 approve commit 后崩溃、commit 失败回滚、owner rollback 失败等边界测试。
4. 删除 `casWriteMulti`、`tryCasWriteMulti`、`ledger-cas-multi-between-rename` 和旧半状态红基线；静态测试锁定其不得回归。
5. controlled-shell 仅新增恢复所需的 scoped `git add -A -- <paths>` 与只读 `git log --format=%B -1` 形态，multica gitguard 已复验。

### 剩余外部验证

- GitHub Actions 双平台结果需 push 后确认；本地验证及 bare remote 事务矩阵均已通过。
