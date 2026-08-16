---
cr: CR-2026-044
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-17T02:21:34+08:00"
command-digest: 8a2c056ff17a232856a773b26ffc7c7c218ea7305a2ad584f00c8997b702d320
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/merge-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/writeback-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/archive-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/register-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-06.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/upgrade-check.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-07.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 180
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-08.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/workspace-freshness.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-09.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/workspace-resolver.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-10.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/durable-tx.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-11.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/fault-harness.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-12.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/test-cr.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-13.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/contract-scan.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-14.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/check-agents-contract.test.mjs]
    timeout-seconds: 180
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-15.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs]
    timeout-seconds: 180
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-16.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/lint-prompts.test.mjs]
    timeout-seconds: 180
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-17.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/lint-prompts.mjs]
    timeout-seconds: 180
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-18.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/check-skill-matrix.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-19.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/check-agents-contract.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-044/test-evidence/cmd-20.log
---

# 测试报告 · CR-2026-044

<!-- crctl:analysis-below -->
## 分析（模型补充）

### 测试摘要（对应 TASK 验收条件）

- **TASK-01 红测试冻结**：3 组红测试入库时按预期失败（approve publication lag、TTY y|yes、merge preflight），随 TASK-02/03/04 实现逐一转绿；cmd-01/cmd-03 证据含最终绿色断言。
- **TASK-02 TTY y|yes**：cmd-01 覆盖 `Y/y/yes/YES/YeS` 与带空白输入批准、空/`n`/`no`/其他文本走既有 reject 回退（`APPROVAL_DECLINED_ROLLED_BACK`）、非 TTY 仍 `APPROVAL_REQUIRES_HUMAN`、grant/resign 回归不变。
- **TASK-03 release-subjects 本地化**：cmd-01 覆盖 origin 缺失时 healthy committed worktree 构造成功、dirty/wrong-branch/missing 零 snapshot 硬失败、KB 精确白名单六成员逐项放行与白名单外逐项失败（kind 精确 prd/task/code）、remote requirement stale 不阻断 approve-code；artifact kind 优先级保证 PRD/SDD 漂移无条件硬阻断。
- **TASK-04 merge publication preflight**：cmd-03 覆盖 source 缺失/滞后在首次 prepare 前阻断（零 candidate、状态保持 code-approved、recoverCommand 指向 checkpoint）、checkpoint 补齐后重跑进入 prepare/publish/finalize、已有 journal 恢复使用冻结 sourceSha 不采纳移动 ref、本地 code/TASK drift 零 publish 仍唯一 release-drift 回退、PRD/SDD drift 硬阻断。
- **TASK-05 Pipeline/Skill 采用**：cmd-08 覆盖 requirement 7 节点与审批后强制 checkpoint、architecture 删除 `auto_push_after_sdd`、code 审批后 checkpoint abort、architecture/code 入口经 `workspace inspect` 取 authority path；cmd-06 覆盖 inspect 返回 `operationalWorkspace` 且 missing 时结构化错误不猜路径；cmd-07 覆盖 upgrade-check 新兼容分类（code-reviewing→requiresReapproval、零 publish code-approved→safe）与零写入。
- **TASK-06 文档与回归**：ADR-0004（knowledge-base）与 ARCHITECTURE/README（tools）修订提交；cmd-16~21 证明契约/lint 全绿、Pipeline 无算法文本、状态机/gates 零耦合。

### 验证命令与结果解读

- 20 条命令全部 exit 0（attempt 2）。attempt 1 的 cmd-12 引用了基线不存在的 `yaml-subset.test.mjs`（计划编制错误，非产品缺陷），已从计划移除并重跑；21→20 命令，commandDigest 由 `897d454c…` 变为 `8a2c056f…`。
- 覆盖 crctl/checkpoint/merge/writeback/archive/register/upgrade-check/pipeline-structure/workspace-freshness/workspace-resolver/durable-tx/fault-harness/test-cr/contract-scan/check-agents-contract/check-skill-matrix/lint-prompts 全部 17 个既有测试文件 + 3 个契约脚本。
- multica worktree 全程 clean（本 CR 零 multica 改动）。

### TASK 验收覆盖矩阵

| TASK | 验收证据 |
|---|---|
| TASK-01 | cmd-01（TTY 组）、cmd-03（merge 组）最终绿色断言 |
| TASK-02 | cmd-01：`CR-2026-044 TASK-01 ②`、`CR-2026-044 TASK-02` |
| TASK-03 | cmd-01：`TASK-06 ④` 更新 + `CR-2026-044 TASK-01 ①` + 白名单/非 healthy 两组 |
| TASK-04 | cmd-03：`CR-2026-044 TASK-01 ③`、`TASK-04 AC-2`、`TASK-04 AC-5` 及既有 saga 回归 |
| TASK-05 | cmd-06/07/08 + cmd-16~18 契约测试 |
| TASK-06 | 两仓文档提交 + cmd-01~21 全量回归 |

### 新增/修改测试文件

- `test/crctl.test.mjs`：新增 4 组 CR-2026-044 测试；更新 `TASK-06 ④` remote-ref-drift 段为 publication lag 放行。
- `test/merge-tx.test.mjs`：新增 3 组（红测试 ③、AC-2 checkpoint 续跑、AC-5 冻结 sourceSha）。
- `test/register-tx.test.mjs`：新增 inspect authority path 测试。
- `test/upgrade-check.test.mjs`：更新为新兼容分类断言。
- `test/pipeline-structure.test.mjs`：新增 4 组三条 Pipeline 结构与 workspace inspect 断言。

### 未覆盖风险

- **真实网络远端行为**：全部测试使用 bare remote fixture；真实 GitHub lease/fetch 语义依赖既有 checkpoint/merge 回归的同一 Git 调用面，不适用单独网络模拟（说明：fixture 与生产共用 `gitRun/gitMust` argv，风险低）。
- **TTY 交互真机验证**：TTY 判断经 `isTTY` defineProperty 模拟；真实终端 `y|yes` 体验建议人工审批时顺带确认（不适用自动化）。
- **在途 CR 跨版本升级实测**：upgrade-check 分类经 fixture 验证；真实升级演练按 PRD FR-11 在合入后执行一次只读 `upgrade-check` 确认。

### 下一步建议

按用户指令本 CR 不执行 review-code；测试证据 status=pass 已满足 `approve-code` 的 test-report 门禁前置。后续由人工决定代码评审与审批时机。
