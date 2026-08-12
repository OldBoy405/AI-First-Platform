---
cr: CR-2026-031
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-12T15:56:26+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-02.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-04.log" }
  - { command: "node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-05.log" }
  - { command: "node ../../../multica/requirement/CR-2026-031/server/internal/governance/gen/generate-transitions.mjs --tools . --check", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-06.log" }
  - { command: "go -C ../../../multica/requirement/CR-2026-031/server test ./internal/governance/ -run Transition -count=1", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-07.log" }
  - { command: "go -C ../../../multica/requirement/CR-2026-031/server test ./internal/governance/ -run ActionConstants -count=1", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-08.log" }
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

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 回修验证摘要

- crctl 全量：250/250 通过；新增跨事务恢复隔离、authority、register 用户改动保护、writeback manifest 绑定/containment、archive ancestry 回归。
- writeback generator：10/10 通过。
- prompt lint：0 findings；skill matrix（57 active skill / 8 actor）、agent contract（9 agent）、pipeline JSON 均通过。
- multica：transition generator `--check` 通过（source tools@2f26e0b，展开口径 50）；governance Transition/ActionConstants 定向 Go 测试通过。

### 已验证的评审修复

1. write-set 恢复收敛为显式 `txId`，manifest 绑定绝对 `targetRoot`，不再把其他事务写集重放到调用者 checkout。
2. release artifacts/status/approval 从 knowledge-base CR worktree 读取；post-review 仅允许受控 review/approval/status/trace 元数据提交。
3. register remote-stale 路径在 reset 前重新检查 checkout，事务期间出现用户改动即硬阻断且保留文件。
4. writeback journal 绑定 manifest bytes，并验证 candidate 位于 txws、版本化 generator SHA 与 signed release-subjects。
5. archive 仅在 requirement source 已证明为 origin trunk 祖先时删除 ref；否则返回 cleanup-pending 并保留现场。
6. resume Skill、CI paths、ARCHITECTURE、skills index 与 multica 28/50 生成产物/CUSTOM 台账已收敛。

### 剩余风险

- 旧账本 `casWriteMulti` 及 `ledger-cas-multi-between-rename` 红基线仍存在，尚未迁入 durable transaction envelope；因此本轮虽测试全绿，代码评审仍不应判 PASS，也不应推进 `code-reviewing`。
- GitHub Actions 双平台结果仍需 push 后确认；本地 bare remote 覆盖 Git lease/history 分类，不覆盖网络故障本身。
