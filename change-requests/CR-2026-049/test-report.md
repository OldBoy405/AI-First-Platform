---
cr: CR-2026-049
status: block
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-21T02:20:48+08:00"
command-digest: fff42d63f0ebd5ce8a03fb019d785c6c35193e545518a163cc564fe554202d37
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./cmd/migrate/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/drift/, ./internal/scheduler/, ./internal/integrations/ghsnapshot/, ./internal/commitprefix/, -run, "TestResolveBindings|TestCommitPrefixScan|TestListCommits|TestResolveRepositoryAccess|TestHeadAndPage|TestGeneratedPrefixes|TestGeneratedConfigRev|TestHealthState|TestDecodeResult|TestOverviewLivePG|TestListFindings|TestPatchStatus|TestFindingUpsert", "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/service/, -run, "TestScanRepo|TestClassify", "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-04.log
  - repo: tools
    cwd: skills/shared/crctl/scripts/test
    executable: node
    args: [--test, trace-semantic.test.mjs, trace-outbox.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-05.log
  - repo: tools
    cwd: skills/shared/crctl/scripts/test
    executable: node
    args: [--test, writeback-tx.test.mjs, archive-tx.test.mjs]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-06.log
  - repo: multica
    cwd: .
    executable: node
    args: [node_modules/typescript/bin/tsc, --noEmit, -p, packages/core/tsconfig.json]
    timeout-seconds: 600
    exit-code: 2
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-07.log
  - repo: multica
    cwd: packages/core
    executable: node
    args: [../../node_modules/vitest/vitest.mjs, run, api/drift-trace-schemas.test.ts, paths]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-08.log
  - repo: multica
    cwd: packages/views
    executable: node
    args: [../../node_modules/vitest/vitest.mjs, run, governance/spec-trace, dashboard/drift, search/search-command.test.tsx, dashboard/maturity]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-09.log
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-049/test-evidence/cmd-10.log
---

# 测试报告 · CR-2026-049

<!-- crctl:analysis-below -->