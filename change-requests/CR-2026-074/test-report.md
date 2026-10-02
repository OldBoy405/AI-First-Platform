---
cr: CR-2026-074
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-02T17:56:54+08:00"
command-digest: bb1e0976672d9f73c8ba056218926da87163751879515b212a69269ca0b688ab
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/register-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/writeback/scripts/test/writeback.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/writeback-tx.test.mjs]
    timeout-seconds: 720
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/caller-contract.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/lint-prompts.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-06.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs');const t=fs.readFileSync('ARCHITECTURE.md','utf8');const need=['kb init','cmdKbInit','requireExplicitWorkspace','detectWorkspace','_backlog.yml','_index.yml','KB_INIT_PRECONDITION'];const miss=need.filter(s=>!t.includes(s));if(miss.length){console.error('cmd-07 FAIL: ARCHITECTURE.md missing: '+miss.join(', '));process.exit(1);}console.log('cmd-07 ok: '+need.length+' map markers present');"]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-074

<!-- crctl:analysis-below -->

## 测试摘要（对应 TASK 验收条件）

- **本轮 = `write-test-report` 环 cycle 2 / attempt 2 的 canonical 证据轮**（`review-loop.yml`：`current-cycle 2 / current-attempt 2`，`generated-at 2026-10-02T17:56:54+08:00`），由 `crctl test` 单次执行 `plan.md` §6.2 全表 7 条命令。逐条转录经只读脚本 `.crctl/tmp/verify-plan.mjs` 机器校验（输出 `OK: 7 条命令逐条全等（含 timeout）`），未在 plan 之外另造命令。
- **机器区 `status: pass`**：7/7 条命令 `exit-code=0`、`started=true`、`skipped=false`、`timed-out=false`；`command-digest bb1e0976672d9f73c8ba056218926da87163751879515b212a69269ca0b688ab`。
- **与上一轮（cycle 2 / attempt 1，`status=block`）的差异只在计划层额度**：`plan.md` §6.2 cmd-04 `timeout` 600 → 720（KB 提交 `11c59987`，依据单跑实测 651.2s 与三轮 573.5 / 628.6 / 637.3s 记录）。本轮 cmd-04 实测 648.4s → 通过，对 720s 余量 71.6s（≈9.9%）。
- **代码侧绑定**：7 条命令均在 tools CR worktree HEAD `a259454` 执行（含 B-CODE-03 修复 `1f9c603` 与 B-CODE-02 覆盖加固 `a259454`），执行前后 `git status --porcelain -uall` 均为空；KB worktree HEAD `19a46e42`。日志与机器区由 crctl 单次发布，本报告只消费、未改写。

## 验证命令与结果解读（cycle 2 attempt 2 机器区逐条）

| 证据ID | 命令（tools CR worktree 根；机器区 `repo=tools` `cwd=.`） | 机器区结果 | canonical 日志（`test-evidence/`） |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | exit 0，`skipped=false` | 237 pass / 0 fail · 170.4s |
| cmd-02 | `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` | exit 0，`skipped=false` | 30 pass / 0 fail · 227.3s |
| cmd-03 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | exit 0，`skipped=false` | 21 pass / 0 fail · 2.8s |
| cmd-04 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | exit 0，`skipped=false`（上限 720s） | 36 pass / 0 fail · 648.4s |
| cmd-05 | `node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs` | exit 0，`skipped=false` | 13 pass / 0 fail · 0.3s |
| cmd-06 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | exit 0，`skipped=false` | 39 pass / 0 fail · 2.2s |
| cmd-07 | plan §6.2 cmd-07 行原样 argv | exit 0 | `cmd-07 ok: 7 map markers present` |

- **cmd-04 判定**：648.4s < 720s（余量 9.9%），落在已记录区间 573.5–651.2s 内；同轮工况控制项（cmd-01 170.4s、cmd-02 227.3s）与上一轮（161.6s / 222.1s）同档，未见异常放大。
- **B-CODE-03 回修证据（本轮 cmd-01 的 `CR-2026-074 AC-02` 用例内）**：`--cmdList x --cmd ignored` 与 `--cmd ignored --cmdList x` 两序 × {有根, 缺根, 空根}。有根 → `BAD_ARGS`（消息命中 `--cmdList`）；缺根/空根 → `WORKSPACE_REQUIRED`；随后断言零副作用（`change-requests/` 未创建、本地 HEAD 未提交、远端 trunk 空、无 audit 行）。用户 `--cmdList` 不再能破坏内部聚合器（`1f9c603` 把聚合器改为局部 `cmdAgg`，`kb init` 额外旗标判定无豁免分支）。非 kb 命令语义由同文件既有用例回归（workspace 守卫、help 无根、caller-contract 经 cmd-05）。
- **cmd-03 跨秒 flake**：本轮 21/0（上一轮同项 21/0，再上一轮 20/1），未复现。
- 全表耗时合计 ≈1051s（cmd-01～06 逐条相加 + cmd-07），与 `crctl test` 单次执行 wall 17m32s 一致。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 | 本轮状态 |
|---|---|---|---|
| TASK-01 kb init 入口/前置/发布重入 | 1/2/3 | cmd-01 | ✅ 237/0（含 AC-01/02/03 与 B-CODE-01/02/03 定向回归） |
| TASK-02 ensure create 自忽略 | 1/2 | cmd-02 | ✅ 30/0 |
| TASK-03 source 空缺省 + 历史指纹矩阵 | 1/2/3 | cmd-02 | ✅（含 AC-11 四行矩阵） |
| TASK-04 buildIndex 首写 + features 前置 | 1/2/3 | cmd-03 | ✅ 21/0 |
| TASK-05 两规范表提取 | 1/2/3 | cmd-03 | ✅（AC-06/AC-07） |
| TASK-06 YAML trunk 解释 | 1/2 | cmd-03 | ✅（AC-08 五向量 + 交叉负测） |
| TASK-07 merge-base 裸提交 shape | 1/2 | cmd-01 | ✅（AC-10 真实 Git fixture） |
| TASK-08 writeback-tx 集成变体 | 1/2/3 | cmd-04 | ✅ 36/0（本轮恢复 canonical 覆盖：三阶段真实全链 + trace 前冻结 + 重放隔离） |
| TASK-09 说明/命令发现/计数同步 | 1/2/3 | cmd-05 + cmd-06 | ✅ 13 + 39；crctl 计数 237 未变 |
| TASK-10 ARCHITECTURE.md 地图维护 | 1/2 | cmd-07 | ✅ 7 判据全命中 |

## 新增/修改测试文件

- **本轮无新增改动**：tools worktree HEAD `a259454`、working tree clean，7 条命令全部在该提交上执行。该提交相对上一轮报告（`1f9c603`）新增的 B-CODE-02 矩阵扩面（两账本父目录 realpath 守卫 6 向量 + 失败零副作用断言）已包含在 cmd-01 的 237 例内。

## 未覆盖风险（含「不适用」说明）

1. **cmd-03 跨秒 flake 未消除**：`writeback-prd-sdd.mjs` 的 `buildIndex` 对既有条目无条件重写秒精度 `updated`，属范围外既存缺陷（20/1 与 21/0 均出现过）。本轮未复现，仍有概率性失败可能。
2. **额度余量偏窄，无第二次上探空间**：cmd-04 648.4s 对 720s 余量 9.9%；`write-test-report` 节点声明 `timeoutMinutes: 20`（1200s），本轮节点实测总量 ≈1051s（≈87.6%）。消费方在平台 runner，本仓无实现可验其是否硬性执行。
3. **cmd-07 只做 ARCHITECTURE.md 字符串命中**：不代替 `review-code` R7 对地图内容的人工检查。
4. **不适用**：lint/build 单列命令（零依赖 CLI，cmd-01～06 即 lint+test 面）；真实人工审批 E2E（SDD scope_out）；`write-requirement-prd` writer 侧非空 source 存在性校验（prompt 合同）。
5. **额度台账**：`write-test-report` cycle 2 已用 2/3（cycle 1 的 attempt 1–3 保留在历史）。

## 下一步建议

1. 本节点 `status=pass` → 进入 `workspace-freshness`（gate=review-start）与 `review-code`。`review-annotations/code.yml` 现仍是上一轮 `verdict=block`（B-CODE-03，`reviewed-source-sha` tools `cccb6625`），其要求的回修实现（`1f9c603`/`a259454`）与本轮 canonical 证据均已就位，待复评刷新。
2. `review-code` 当前 attempt 2/3，下一轮为 cycle 1 / attempt 3；若再次 block 则循环耗尽，需人工在 TTY 执行 `crctl review-loop reset CR-2026-074 --loop review-code --reason <…>` 后才能再评审。
3. 本报告所在 KB worktree 的证据改动（`test-report.md` / `test-evidence/cmd-01～07` / `traceability.yml` / `review-loop.yml`）由本节点落盘并提交，供 `review-code` 前的 `workspace-freshness`（gate=review-start）使用。
