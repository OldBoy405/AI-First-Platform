---
cr: CR-2026-060
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-03T04:13:34+08:00"
command-digest: 383d43f22c692465ba581f212318619eca01cd834452ed0fb827a8552949af8a
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/lint-prompts.test.mjs, skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs, skills/shared/crctl/scripts/test/check-agents-contract.test.mjs, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs, skills/shared/crctl/scripts/test/contract-scan.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-060/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/register-tx.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-060/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-skip-pattern, "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引", skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-060/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/writeback-tx.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-060/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-skip-pattern, "TASK-01 RED-7：预存确定性 dedup 文件", skills/shared/crctl/scripts/test/archive-tx.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-060/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/version-set.test.mjs, skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-060/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-060

<!-- crctl:analysis-below -->