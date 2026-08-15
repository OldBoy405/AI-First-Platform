---
cr: CR-2026-040
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-15T15:21:34+08:00"
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
| `node --test test-cr.test.mjs` | 结构化测试闭环 | 24 | 0 | pass |
| `node --test fault-harness.test.mjs` | 故障注入 harness | 7 | 0 | pass |
| `node --test lint-prompts.test.mjs` | prompt 契约 | 29 | 0 | pass |
| `node --test crctl.test.mjs` | crctl 回归 | 169 | 0 | pass |
| `node lint-prompts.mjs --mode enforce` | prompt 漂移 | 0 findings | - | pass |

正式计划共执行 229 个测试，全部通过。测试输入绑定 Tools 提交 `cb34001`（merge `6196121c` 吸收 trunk 后的合并提交）；参与仓 HEAD 改变后 input digest 变化，生成新 attempt——本次为 write-test-report cycle 3 / attempt 1。

## 合并验证（吸收 trunk CR-2026-039）

本 CR 开发基于 merge-base `c790b7e`（CR-2026-032 合入后），与已合入 trunk 的 CR-2026-039 在 `pipeline-templates/code-implementation.pipeline.json`、`crctl/SKILL.md`、`crctl.mjs`、`durable-tx.mjs`、`crctl.test.mjs` 上存在并发改动冲突。已在 requirement 分支完成 trunk 合并（commit `cb34001`）并解决冲突：

- 保留 039 的 `checkpoint` op / `loadExistingJournal` 与 `...0015` 评审后 checkpoint 节点；保留 040 的 `test` op / `createAfterComplete` 语义与结构化测试闭环。
- 按 039 契约收敛：`code-implementation.pipeline.json` 与 11 个 SKILL 对 `suggestion_policy` / `repair-instructions` / `fixed-blockers` 零命中（contract-scan 白名单外的 planning/README 残留引用不受约束）。
- 合并后本地全量验证：crctl 套件 **347/347**（含 039 的 checkpoint/writeback/upgrade-check/contract-scan）+ writeback 单测 **10/10** + `lint-prompts enforce` **0 findings**；以上均通过 GitHub Actions 双平台复验。

## TASK 与回修覆盖

| 范围 | 验收条件 | 证据 |
|------|---------|------|
| TASK-01 durable-tx | `test` payload 复用现有 lock/journal/write-set；新 complete transaction 不删除旧事实 | cmd-01、cmd-02、cmd-04 |
| TASK-02 `testCr` | 记录阶段 test scope lock、input digest 绑定 HEAD/日志 hash、幂等新 attempt | cmd-01（锁竞争、source revision、complete journal） |
| TASK-03 CLI / plan 边界 | `--plan` 只接受 `.crctl/tmp`；authority、traversal 和 symlink escape 硬失败 | cmd-01 |
| TASK-04 结构化矩阵 | LF/CRLF digest、timeout、marker 字节保留、cwd `..`/symlink、账本形状硬失败、PASS 后新 cycle | cmd-01（24 例） |
| TASK-05 故障恢复 | rename 间隙和 complete 前中断恢复，attempt 不重复 | cmd-02（7 例） |
| TASK-06 Skill/Pipeline | prompt 契约 29/29；enforce 0 findings；039 契约词零命中 | cmd-03、cmd-05 |
| 既有 crctl 回归 | 状态、门禁、review-loop、checkpoint、approval 等保持通过 | cmd-04（169 例） |

## 新增 / 修改测试

- 扩展 `skills/shared/crctl/scripts/test/test-cr.test.mjs` 至 24 例。
- 保留并通过 `skills/shared/crctl/scripts/test/fault-harness.test.mjs` 7 例。
- 新增真实 timeout、CRLF、marker CRLF 字节保留、source HEAD 变化、plan/cwd symlink escape、test scope lock、非法 journal/review-loop/pipeline/traceability 形状，以及 PASS 后新 cycle / BLOCK 到上限停止测试。

## 双平台 CI

GitHub Actions run [`31871639855`](https://github.com/OldBoy405/AI-First-tools/actions/runs/31871639855) 绑定 Tools `cb34001`（合并后），两个 matrix job 均成功：

- [`contracts (ubuntu-latest)`](https://github.com/OldBoy405/AI-First-tools/actions/runs/31871639855/job/94981094359)：success。
- [`contracts (windows-latest)`](https://github.com/OldBoy405/AI-First-tools/actions/runs/31871639855/job/94981094377)：success。

两个平台均执行 prompt lint、Skill matrix、Agent contract、全部 Pipeline JSON、crctl 全量测试和 writeback 单测。AC-16 的 Ubuntu/Windows 独立执行证据已闭合。

## 未覆盖风险

- **多仓组合规模**：resolver、逐仓 branch/cwd containment 和 source revision 已覆盖；尚未为所有仓库排列组合建立笛卡尔积用例。该风险不改变单命令逐仓执行语义，保留为非阻塞扩展项。

## 下一步

- 双平台 CI 与合并验证完成；tools requirement 分支已推送 `cb34001`，进入只读代码重审（release-subjects 需重新绑定合并后 HEAD 并重新审批）。
