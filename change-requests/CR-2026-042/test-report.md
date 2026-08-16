---
cr: CR-2026-042
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-16T17:48:57+08:00"
command-digest: 181f18b130edc3b6da8e55c3b2a361db567b217520836aeb5ed68f3d7ac4ba92
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/lint-prompts.mjs, --mode, enforce]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/check-skill-matrix.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/check-agents-contract.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/lint-prompts.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-06.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/writeback/scripts/test/writeback.test.mjs]
    timeout-seconds: 180
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-042/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-042

<!-- crctl:analysis-below -->

## 测试摘要

7 条验证命令全部通过（exit 0），覆盖本 CR 的全部确定性治理与回归面：

| 命令 | 结果 |
|---|---|
| `lint-prompts.mjs --mode enforce` | 0 findings（R1-R13 无漂移） |
| `check-skill-matrix.mjs` | 56 active skill / 8 actor 一致 |
| `check-agents-contract.mjs` | 9 agent 不变式 1-3 通过 |
| `crctl.test.mjs` | 184 tests pass（含 5 条 CR-2026-042 静态合同） |
| `lint-prompts.test.mjs` | 37 tests pass（含 R10-R13 正反例 + CRLF） |
| `pipeline-structure.test.mjs` | 8 tests pass（16 节点断言） |
| `writeback.test.mjs` | 13 tests pass |

另：全量 crctl 事务套件（`node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`，16 个测试文件）已单独跑通 **399 tests pass / 0 fail**（时长约 12 分钟）；因 `--plan` 的 shell:false 契约不能传 glob，未纳入 `--plan`，证据见本会话输出。

## TASK 验收覆盖矩阵

| TASK | 验收 | 证据 |
|---|---|---|
| TASK-01 Agent/Pipeline 合同收敛 | 16 节点、无 review_llm、无 …0013、replayNodes 顺序、_index nodes=16、agent 无状态链 | crctl.test.mjs 静态合同 + pipeline-structure.test.mjs |
| TASK-02 Skill/README/ARCHITECTURE 收敛 | write-requirement-prd 无 engineering-docs、write-dev-tasks 无 commit 配方、README 8 节、ARCHITECTURE reviewer 边界 | crctl.test.mjs 静态合同 |
| TASK-03 lint R10-R13 + CI + 验证 | R10-R13 正反例/CRLF、CI 合并、paths、双 checker、全量回归 | lint-prompts.test.mjs + crctl.test.mjs |

## 新增/修改测试文件

- `skills/shared/crctl/scripts/lint-prompts.mjs`：walkFiles 扩扫 agents/README，新增 R10-R13，状态集合复用 loadAuthorityTransitions。
- `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`：+8 条 R10-R13 向量（正反例、LF/CRLF、ignore 半径）。
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：+5 条静态合同；既有 17 节点断言改为 16；回修补充 Skill node 缺 `ref` 阻断与 `milestone_file` 业务输入保留断言。
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`：17→16 节点断言与 …0013 前置关系修正。
- `.github/workflows/crctl-ci.yml`：paths 补齐 + Pipeline 固定结构断言步骤。

## 未覆盖风险与不适用说明

- **OpenWiki 刷新**：属合并后发布后置条件（触发 `openwiki-update.yml` 并核验生成 PR 旧引用归零），不在编码期本地验证范围；`openwiki-update.yml` 已确认保留 `workflow_dispatch`。
- **Windows/Ubuntu CI 双平台**：本机为 Windows，Ubuntu 侧由 `crctl-ci.yml` matrix 在 CI 执行；所有文本读取均先 CRLF→LF，已由 lint-prompts CRLF 测试覆盖等价性。
- **Pipeline 固定结构断言**：已在 CI 内联步骤落地，本机以等价脚本跑通 8 模板；本 CR 不引入可执行 Pipeline 解释器。

## 评审回修验证

首轮代码评审的 4 个 findings 已修复：CI 对缺失 Skill `ref` fail-closed；active Pipeline prompt 移除注册/合并/回写/归档/worktree 内部算法；`write-requirement-prd` 删除手工 commit 指令并改用 `crctl validate`。针对性组合回归 `crctl.test.mjs + lint-prompts.test.mjs + pipeline-structure.test.mjs` 为 **229 pass / 0 fail**；本轮正式 `crctl test --plan` 的 7 条命令全部 exit 0。

## 下一步

`crctl next CR-2026-042`：test-report.status=pass，推送 checkpoint 后执行正式代码评审。