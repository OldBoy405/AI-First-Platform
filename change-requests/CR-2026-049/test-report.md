---
cr: CR-2026-049
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-21T04:57:21+08:00"
command-digest: f2f0134c778c17171e01d878819463fdc837ee707047ae966dbc24f7d2e4becf
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance/, -run, "TestProjectTimeline|TestTraceIngest", "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./cmd/server/, -run, "^$", "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-02.log
  - repo: multica
    cwd: packages/views
    executable: node
    args: [../../node_modules/vitest/vitest.mjs, run, governance/spec-trace/spec-trace.test.tsx]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-03.log
  - repo: tools
    cwd: skills/shared/crctl/scripts/test
    executable: node
    args: [--test, trace-semantic.test.mjs, trace-outbox.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-04.log
---

# 测试报告 · CR-2026-049

<!-- crctl:analysis-below -->