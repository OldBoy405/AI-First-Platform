---
cr: CR-2026-040
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-15T11:55:01+08:00"
command-digest: c983c8e55a38df46748051072783a06e9e897de18d920de8c4b9c66787099ff1
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/fault-harness.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/lint-prompts.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/lint-prompts.mjs, --mode, enforce]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-05.log
---

# 测试报告 · CR-2026-040

<!-- crctl:analysis-below -->
## 测试摘要

| 命令 | 套件 | 用例 | 失败 | 结果 |
|------|------|------|------|------|
| `node --test test-cr.test.mjs` | 结构化测试闭环 | 14 | 0 | pass |
| `node --test fault-harness.test.mjs` | 故障注入 harness | 7 | 0 | pass |
| `node --test lint-prompts.test.mjs` | prompt 契约 | 29 | 0 | pass |
| `node --test crctl.test.mjs` | crctl 回归 | 169 | 0 | pass |
| `node lint-prompts.mjs --mode enforce` | prompt 漂移 | 0 findings | — | pass |

## TASK 验收覆盖

| TASK | 验收条件 | 证据 |
|------|---------|------|
| TASK-01 durable-tx test op/payload | `OPS`/`PAYLOAD_KEYS` 含 `test`；既有 fault-harness 不回归 | cmd-02、cmd-04 |
| TASK-02 workspace-transactions testCr | `--plan` 成功、`--cmd` 拒绝、幂等 `changed=false`、失败分流 | cmd-01（端到端 7 例） |
| TASK-03 crctl.mjs --plan dispatch | `--plan` 黑盒成功；`--cmd` 返回 `BAD_ARGS` 零 authority | cmd-01 |
| TASK-04 crctl.test.mjs 结构化矩阵 | plan 合同、argv 安全、marker、digest、幂等 | cmd-01（14 例） |
| TASK-05 fault-harness test 故障矩阵 | `tx-apply-between-rename`/`tx-apply-before-complete` 恢复、attempt 不重复 | cmd-02（2 例） |
| TASK-06 Skill/Pipeline 收敛 | lint-prompts enforce 0 findings；pipeline 可解析、节点数 14 | cmd-03、cmd-05 |

## 新增 / 修改测试文件

- 新增 `skills/shared/crctl/scripts/test/test-cr.test.mjs`（14 例）
- 修改 `skills/shared/crctl/scripts/test/fault-harness.test.mjs`（+2 例）

## 未覆盖风险

- **跨平台执行**：测试在 Windows 运行通过；Ubuntu 上的 `spawnSync(executable, args, {shell:false})` 直接启动语义未在 CI 矩阵实测（代码路径为 Node 标准库，理论一致，但缺独立平台回归）。
- **真实多仓 plan**：端到端用例只覆盖 knowledge-base 单仓；`tools`/`multica` 多仓 plan 的 cwd containment 组合未逐仓黑盒覆盖（parseTestPlan 单元测试覆盖了 repo/cwd 校验分支）。
- **超时路径**：`timeoutSeconds` 触发 `ETIMEDOUT` 的业务 block 路径未单独黑盒断言（代码路径与 non-zero 分流共用，但缺独立超时用例）。

以上均不影响本 CR 验收结论（FR-01~FR-08 的 AC 已在 cmd-01~05 覆盖），记录为后续补充项。

## 下一步

- 进入 `push-progress`（统一 checkpoint）与 `review-code`（只读取证，不重跑测试）。
