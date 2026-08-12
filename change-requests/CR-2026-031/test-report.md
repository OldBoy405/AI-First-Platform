---
cr: CR-2026-031
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-12T14:39:29+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/writeback.test.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-02.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-04.log" }
  - { command: "node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-031/test-evidence/cmd-05.log" }
---

# 测试报告 · CR-2026-031

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-031/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-02.log |
| 3 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-031/test-evidence/cmd-03.log |
| 4 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-04.log |
| 5 | `node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-031/test-evidence/cmd-05.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 测试摘要

CR-2026-031（漂移治理 v2）全部 12 个 TASK 已实现并登记 done。验证分五组命令，全部 exit 0：

1. **crctl 全量测试套件**（`node --test skills/shared/crctl/scripts/test/*.test.mjs`）：246 用例全绿（tests 246 / pass 246 / fail 0）。覆盖 TASK-01 故障注入、TASK-02 死代码删除静态断言、TASK-03 workspace resolver、TASK-04 durable-tx 事务原语、TASK-05 register/workspace 事务、TASK-06 signed release snapshot（伪造拒绝/六类漂移零写入/TTY 路径）、TASK-07~09 三 bare remote 事务矩阵、TASK-10 契约收敛静态断言、TASK-11 upgrade-check 分类矩阵。
2. **writeback 单测套件**（`node --test skills/writeback/scripts/test/writeback.test.mjs`）：10 用例全绿（candidate-only 零写、manifest 排序/inputDigest 交叉验证、幂等）。
3. **lint-prompts**（`--mode enforce`）：0 findings，prompt 与 crctl 无漂移。
4. **skill matrix**：57 active skill / 8 actor 一致性通过。
5. **agent contract**：9 个 agent 不变式 1-3 覆盖通过。

### TASK 验收覆盖矩阵

| TASK | 验证载体 | 结果 |
|------|---------|------|
| TASK-01 故障注入契约 | fault-harness.test.mjs + FAULT_POINTS 注册表（22 点） | ✅ |
| TASK-02 死代码删除 | crctl.test.mjs 静态断言（无 cr-init 等旧命令） | ✅ |
| TASK-03 resolver/authority | workspace-resolver.test.mjs + resolveOperationalWorkspace 修正 | ✅ |
| TASK-04 durable-tx | durable-tx.test.mjs（journal/lock/write-set/envelope） | ✅ |
| TASK-05 register/workspace | register-tx.test.mjs（幂等/输入漂移/worktree 矩阵） | ✅ |
| TASK-06 signed snapshot | crctl.test.mjs ①-⑥（伪造拒绝/注入一致性/grant 签入/六类漂移/TTY） | ✅ |
| TASK-07 merge saga | merge-tx.test.mjs 9 场景（happy/conflict/fault/rebuild/history-rewrite/drift 回退） | ✅ |
| TASK-08 candidate writeback | writeback.test.mjs 10 + writeback-tx.test.mjs 6（15 类恶意 manifest 矩阵零写入） | ✅ |
| TASK-09 archive | archive-tx.test.mjs 4（四账本/cleanup-pending/dirty 保留/rejected preservedRefs） | ✅ |
| TASK-10 契约收敛 | lint-prompts 0 findings + skill matrix + agent contract + pipeline JSON parse | ✅ |
| TASK-11 upgrade-check | upgrade-check.test.mjs 2（分类准确/零写入/exit 码）+ 主工作区实跑 canActivate=true | ✅ |
| TASK-12 协议切换 | 双平台 CI workflow + 状态机口径 28/50 全仓唯一（tools/multica/AGENTS.md） | ✅ |

### 新增/修改测试文件

- `test/fault-harness.test.mjs`、`test/workspace-resolver.test.mjs`、`test/durable-tx.test.mjs`、`test/register-tx.test.mjs`、`test/merge-tx.test.mjs`、`test/merge-fixture.mjs`（共享 fixture）、`test/writeback-tx.test.mjs`、`test/archive-tx.test.mjs`、`test/upgrade-check.test.mjs`（新增）
- `test/crctl.test.mjs`（TASK-06 ①-⑥ 追加 + TASK-10 静态断言收敛）
- `skills/writeback/scripts/test/writeback.test.mjs`（candidate-only 断言重写）

### 未覆盖风险

- **multica 仓**：`transitions_gen.go` 已重生成（28/50）但未跑 governance Go 测试（需要真库，CI 覆盖受限）；跨工具接缝（Go 签发 grant → crctl approve --grant）未在本 CR 重跑——沿用 CR-2026-002 既有 crosscheck 套件，本 CR 未改审批路径。
- **真实远端**：三仓事务矩阵使用本地 bare remote 模拟，未对真实 GitHub origin 做端到端演练（fetch/push 语义一致，网络层差异不在本 CR 验证范围）。
- **双平台 CI**：`.github/workflows/crctl-ci.yml` 已提交，但 runner 实际执行结果需等 push 后 GitHub Actions 确认（本机仅验证 ubuntu 等价路径）。

### 下一步建议

按收尾流程：代码评审（review-record --stage code）→ 人工 approve-code → crctl merge → writeback 三阶段 → crctl archive。
