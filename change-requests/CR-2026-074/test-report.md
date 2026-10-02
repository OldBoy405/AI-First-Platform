---
cr: CR-2026-074
status: block
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-02T11:36:53+08:00"
command-digest: c7e74fc0e056f6d45576944e7dca7370b724ec9999c6a55224c8d13ffdeeb5a5
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
    exit-code: 1
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-074/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/writeback-tx.test.mjs]
    timeout-seconds: 600
    exit-code: null
    signal: SIGTERM
    timed-out: true
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

全部 10 个 TASK（CR-2026-074-TASK-01 ～ TASK-10）已实现、登记 done 并提交（tools commit 3eda3ee）；本报告为 **review-code BLOCK（attempt 2/3，blocker=B-CODE-03）后的第二次回修轮证据**（write-test-report 环 attempt 3）。本轮回修内容：`parseArgs` 的 `--cmd` 聚合器搬到独立槽位（B-CODE-03），详见下节。

**机器区 `status: block`**：七条证据命令中 cmd-03 exit 1、cmd-04 超时，两处失败均**不归因于本轮回修**（下述实测证据）；cmd-01/02/05/06/07 全 exit 0。因 write-test-report 环已 3/3 耗尽且本报告 block，`crctl test` 现返回 `TEST_LOOP_EXHAUSTED`，本轮无法再发布 green 规范证据，处置需 owner 决策（见「下一步建议」）。

## B-CODE-03 回修内容（唯一代码改动）

**根因（单一入口，非 kb 专属）**：`parseArgs` 以 `const flags = { cmdList: [] }` 预置聚合器，同时通用分支又写 `flags[key]`，两写者共用 `cmdList` 槽位。用户 `--cmdList x` 先把数组覆盖为字符串，随后 `--cmd` 命中 `String.prototype.push` 抛 `TypeError` → 经 `main().catch` 变 `INTERNAL_ERROR`，在 `requireExplicitWorkspace` 之前抛出，于是缺根组合丢失 `WORKSPACE_REQUIRED` 优先级、有根组合无法到达 `cmdKbInit` 的 `BAD_ARGS`（违反 SDD §3.1「先验证 workspace 非空字符串，再验证 kb 形态；缺根不会被 BAD_ARGS 掩盖」与 §3.2 序号 1）。

**修法（一处根因修复，全部调用方共用）**：`parseArgs` 内部聚合器改用独立局部 `cmdAgg`，`flags` 不再预置 `cmdList`；仅当 `cmdAgg.length` 非空时回写 `flags.cmdList`。解析期对旗标组合不再抛错，`WORKSPACE_REQUIRED` 优先级由既有 `main` → `requireExplicitWorkspace`（先于 kb 派发）保证；两旗标共现时聚合器为准，键存在即非空 → 下游按额外旗标拒绝，不静默丢弃。`cmdKbInit` 的 `extraFlags` 随之收敛为 `k !== 'workspace'`（原「内部空数组豁免」分支在新不变量下不可达，删除，不留死代码）。

**红→绿实测**（HEAD cccb662 原文与修复后工作树同机对照，两序 + 有根/缺根/空根）：

| 向量 | 修复前（HEAD 原文） | 修复后 |
|---|---|---|
| `kb init --cmdList x --cmd ignored` | `INTERNAL_ERROR` `TypeError: flags.cmdList.push is not a function` @parseArgs:3738 | `WORKSPACE_REQUIRED` |
| `kb init --workspace <任意> --cmdList x --cmd ignored` | 同上 `INTERNAL_ERROR` | `BAD_ARGS`（不接受额外旗标: --cmdList） |
| 反序 `--cmd ignored --cmdList x`（两向量） | 同上 `INTERNAL_ERROR` | 同上（缺根 `WORKSPACE_REQUIRED` / 有根 `BAD_ARGS`） |
| 显式空根 `--workspace ""` + 两序组合 | 同上 `INTERNAL_ERROR` | `WORKSPACE_REQUIRED` |

定向回归新增到既有 AC-02 用例（未新增 `test()`，gate-registry 计数保持 237）：两序 ×（有根/缺根/空根）六向量，均断言 code 与「先于文件/index/HEAD/remote/audit 副作用」（`change-requests/` 不存在、HEAD 仍 unborn、远端仍空、无 audit 行）。cmd-01 机器记录 exit=0、started=true、skipped=false。

## 验证命令与结果解读（attempt 3 机器区逐条）

| 证据ID | 命令（tools worktree 根） | 机器区结果 | 覆盖解读 |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | exit 0，237 pass / 0 fail | TASK-01 kb init（AC-01/02/03 + 守卫回归）、TASK-07 裸提交（AC-10）、B-CODE-01/02 回归及既有全套回归；**含本轮 B-CODE-03 两序六向量** |
| cmd-02 | `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` | exit 0，30 pass / 0 fail | TASK-02 ensure 自忽略（AC-04）、TASK-03 source 空缺省与历史指纹矩阵（AC-11）及回归 |
| cmd-03 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | **exit 1**，20 pass / 1 fail | 失败项 `prd-sdd: 增量追加（既有内容保留 + H 级 +1）+ 重跑 noop`（writeback.test.mjs:128，断言 `r3.stdout.includes('"noop": true')`）。**范围外既存缺陷、不由本轮引入**：该用例直接执行 `writeback-prd-sdd.mjs`（调用链无 crctl，与本轮 parseArgs 改动无交集），属 attempt 2 报告已登记「风险 1」的跨秒边界 noop 误判形态；同机重跑实测 21 pass / 0 fail（2.5s）。 |
| cmd-04 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | **exit null，timed-out true（600s 上限）** | **超时预算不足，非本轮引入**（见下节量化）。同机单跑实测 36 pass / 0 fail，耗时 **628.6s > 600s**，即本机当前性能下该命令无法在上限内完成；attempt 2 同命令耗时 573.5s（已占上限 95.6%）。 |
| cmd-05 | `node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs` | exit 0，13 pass / 0 fail | caller 契约、文档入口一致（AC-09）及回归；缺根/空根 WORKSPACE_REQUIRED 契约不受本轮改动影响 |
| cmd-06 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | exit 0，39 pass / 0 fail | 说明与可执行命令一致、skill matrix / prompt lint 0 findings（gate-registry 计数 crctl 237 未变） |
| cmd-07 | plan §6.2 cmd-07 行原样 argv | exit 0，`7 map markers present` | TASK-10 ARCHITECTURE.md 地图锚点可机器观测（语义由 review-code R7 人工检查承载） |

执行上下文：tools CR worktree（`workspace freshness` 四仓 allFresh、classification=healthy）；Node v24.15.0。**本轮回修改动（crctl.mjs、crctl.test.mjs）仍在工作树未提交**——按 Pipeline，源码提交属 checkpoint/push-progress 批次，而该批次以 test-report pass 为前提，本轮为 block 故未提交、未推送（无 out-of-pipeline 步骤）。因此本报告命令日志与 command-digest 对应的实现内容为工作树状态，其 HEAD 仍为 cccb662（与 B-CODE-03 评审所据 reviewed-source-sha 一致）。

## cmd-03 / cmd-04 失败不归因于本轮回修的量化依据

- **cmd-03**：失败用例的调用链为测试进程 → `writeback-prd-sdd.mjs` 子进程，不含 `crctl.mjs`；本轮改动仅存在于 `parseArgs`。同机重跑该文件 21/21 pass。该形态在 attempt 2 报告中已作为「范围外既存缺陷（selfCheck / 索引无变化跳过推送的跨秒边界误报）」登记并建议后续 CR 单独治理。
- **cmd-04**：对 attempt 2 与本轮单跑日志逐用例比对（36 用例同名对齐）：总耗时 573.4s → 628.6s（×1.0961）；**全部 36 用例一致变慢**（中位比 1.093，最小 1.015，最大 1.150），包含与本 CR 无任何调用关系的既有用例 → 本机整体约 +9.6% 的工况性变慢，非代码路径变慢。600s 上限相对 573.5s 基线仅 4.4% 余量，任何 >4.4% 的工况波动即超时，属 plan/SDD 层证据命令超时额度问题。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 |
|---|---|---|
| TASK-01 kb init 入口/前置/发布重入 | 1/2/3 | cmd-01（AC-01/02/03 定向 + 守卫负测 + B-CODE-01/02/03 回修定向回归，含两序 × 有根/缺根/空根） |
| TASK-02 ensure create 自忽略 | 1/2 | cmd-02（AC-04 联测：init→register 首 CR→重入） |
| TASK-03 source 空缺省 + 历史指纹矩阵 | 1/2/3 | cmd-02（矩阵四行 + 空/显式空串 + 非空合同） |
| TASK-04 buildIndex 首写 + features 前置 | 1/2/3 | cmd-03（四类负例/首写正例/历史保留；本轮该文件 20/21，唯一失败项为范围外既存 flake，见上） |
| TASK-05 两规范表提取 | 1/2/3 | cmd-03（AC-06/AC-07 + 061/066 片段 fixture） |
| TASK-06 YAML trunk 解释 | 1/2 | cmd-03（AC-08 五向量 + 交叉负测） |
| TASK-07 merge-base 裸提交 shape | 1/2 | cmd-01（AC-10 真实 Git fixture） |
| TASK-08 writeback-tx 集成变体 | 1/2/3 | cmd-04（AC-12 三阶段全链 + trace 前冻结 + AC-05 apply 侧；本轮机器区超时，同机单跑 36/36 pass 628.6s） |
| TASK-09 说明/命令发现/计数同步 | 1/2/3 | cmd-05（13）+ cmd-06（39）；crctl 计数 237 未变（本轮未新增 test()） |
| TASK-10 ARCHITECTURE.md 地图维护 | 1/2 | cmd-07（7 判据全命中） |

## 新增/修改测试文件

- `skills/shared/crctl/scripts/test/crctl.test.mjs`：**无新增 `test()`**，在既有 `CR-2026-074 AC-02` 用例内新增 B-CODE-03 两序 ×（有根/缺根/空根）六向量断言与「先于文件/index/HEAD/remote/audit 副作用」断言，故 gate-registry 的 crctl.test.mjs 计数保持 237、lint-prompts 计数一致（cmd-06 通过）。
- 生产改动仅 `skills/shared/crctl/scripts/crctl.mjs`：`parseArgs` 聚合器独立槽位 + `cmdKbInit` 额外旗标过滤收敛（+11/−10 行，无新增导出、无新依赖、无行为面扩张）。

## 未覆盖风险与不适用说明

- **本轮 block 的两个成因未修（均超出本次回修批准范围）**：cmd-03 的跨秒边界 noop flake（既有 trunk 测试，改动它属范围外且需独立评审）；cmd-04 的 600s 超时额度（plan.md §6.2 / SDD §5.2 已批准证据表值，本地调小/调大属计划层变更）。
- **不适用**：lint/build 单列命令（零依赖 CLI，cmd-01～06 即 lint+test 面）；真实人工审批 E2E（SDD scope_out）；`write-requirement-prd` writer 侧非空 source 存在性校验（prompt 合同）。
- **残留风险**：本报告机器区对应的实现在工作树未提交（block 态不进入 checkpoint 批次），owner 决策后如重置环重跑，需以当时工作树状态为准。

## 下一步建议

`status=block` 且 **write-test-report 环 3/3 已耗尽**（实测 `crctl test` → `TEST_LOOP_EXHAUSTED: write-test-report 已达 maxAttempts=3，不得继续自修复`；`crctl next` → `implement-code`，why=`test-report.status=block，按 replayNodes 回修`）。按派单约束，本节点不得自重置 attempt、不跳门禁，现停在本节点并上报，需 owner/协调侧两项决策：

1. **环重置（治理动作）**：`crctl review-loop reset CR-2026-074 --loop write-test-report --reason <...>`——本轮 block 由两处不可归因失败造成，不消耗真实自修复额度，重置后方可再次生成规范证据。
2. **cmd-04 超时额度（计划层动作，重置的前置条件）**：plan.md §6.2 / SDD §5.2 的 cmd-04 `timeout=600` 相对实测 628.6s（attempt 2 基线 573.5s，余量 4.4%）已不足，需上调（建议 ≥900s）或按 SDD 变更流程修订，否则重置后必然重现超时。

完成上述两项后，回修代码与本轮证据可由同一 checkpoint 批次提交推送，再按 pipeline 送 `review-code`（评审前 `workspace-freshness` gate=review-start）。
