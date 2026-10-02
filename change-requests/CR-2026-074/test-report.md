---
cr: CR-2026-074
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-02T19:42:13+08:00"
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

- **本轮 = `write-test-report` 环 cycle 3 / attempt 1 的 canonical 证据轮**（`generated-at 2026-10-02T19:42:13+08:00`，事务 `057f8c3cadf144958a2c1f738306dba8` `phase=complete` / `attempt=1`），由 `crctl test` 单次执行 `plan.md` §6.2 全表 7 条命令。命令表与 `timeout` 逐条原样转录（cmd-04 沿用 720s），`command-digest bb1e0976672d9f73c8ba056218926da87163751879515b212a69269ca0b688ab` 与上一轮全等——未改 PLAN、未新增命令。cycle 2 的 3/3 在 canonical `pass` 下按既有规则自动滚动为 cycle 3 / attempt 1（`TEST_LOOP_EXHAUSTED` 只在非 pass 时抛出），未人工重置额度。
- **机器区 `status: pass`**：7/7 条命令 `exit-code=0`、`started=true`、`skipped=false`、`timed-out=false`。
- **证据↔源码绑定（B-CODE-06 回修轮）**：7 条命令的 `sourceRevision` = tools CR worktree HEAD `9e7612e2b86d3955bcd23a3e6a8edbaa73da03d1`（本轮回修提交）。以该 revision 与七条 `test-evidence/cmd-NN.log` 的 sha256（`1894151773` / `e1d6469130` / `721efbc2c0` / `291571f7a9` / `fd0094f531` / `7ca6bd746b` / `0badead2e8` 前缀）按 `sha256(command-digest + resultMetadata + tester + owner-assigned-at)` 独立重算 `inputDigest = f48fefe22457f7ef0636a09f876fa6602d2e36ab0284c120540b15df476d0a83`，与 journal 全等——被测源码即回修提交本身，无未提交漂移。
- 回修提交在测试**之前**落盘（`9e7612e`），故 `sourceRevision` 可解析到含回修内容的具体提交；KB worktree 在执行时为 `2b351423`（上轮 `review-code` BLOCK 自环状态提交）。

## 验证命令与结果解读（cycle 3 attempt 1 机器区逐条）

| 证据ID | 命令（tools CR worktree 根；机器区 `repo=tools` `cwd=.`） | 机器区结果 | canonical 日志（`test-evidence/`） |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | exit 0，`skipped=false` | 237 pass / 0 fail · 167.8s |
| cmd-02 | `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` | exit 0，`skipped=false` | 30 pass / 0 fail · 218.0s |
| cmd-03 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | exit 0，`skipped=false` | 21 pass / 0 fail · 2.9s |
| cmd-04 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | exit 0，`skipped=false`（上限 720s） | 36 pass / 0 fail · 644.2s |
| cmd-05 | `node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs` | exit 0，`skipped=false` | 13 pass / 0 fail · 0.4s |
| cmd-06 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | exit 0，`skipped=false` | 39 pass / 0 fail · 2.2s |
| cmd-07 | plan §6.2 cmd-07 行原样 argv | exit 0 | `cmd-07 ok: 7 map markers present` |

- **cmd-04 判定**：644.2s < 720s（余量 75.8s，≈10.5%），落在已记录区间 573.5–651.2s 内，未逼近上限。
- **B-CODE-06 回修（本轮唯一 blocker，`repair-target=implement-code`）**：`docs/QODER-使用指南.md` 环境准备节按原顺序执行无法满足新增 `kb init` 的硬前置（缺 origin、分支与声明 trunk 不一致、白名单外文件未提交）。回修只改该说明节（1 文件、+30/−9）：
  - 第 1 步：明确该目录必须是 **KB 主 checkout**（非 linked worktree）、**已配置 `origin`**、**当前分支名 = `dir-graph.yaml` 里声明的 trunk**；给出两条建法（clone 已有远端仓 / `git init -b main` + `git remote add origin` + `git symbolic-ref` 自检）。
  - 第 5 步：把「先提交白名单外文件、再 init」写成显式步骤（`git add -A` + `git commit`，含首次提交身份配置提示与 tools 包自带 `.git` 的去子模块提示），并给出等价替代顺序（tools 包置于 workspace 之外、`tools_package_path` 指向它，先 init 后生成）；补列硬前置与错误码（`repo-invalid` / `trunk-mismatch` / `dirty` / `remote-diverged` / `KB_INIT_CONFLICT`）。
  - 六种 docs 索引模板与四种已删手工治理模板的状态不变（未恢复任何手工账本模板）；未改生产前置、状态机、gates、权限边界，未放宽 `kb init` 白名单。
- **随回修源码顺序的端到端补充验证（不属于 canonical 命令表；本地临时沙箱、裸仓充当 origin、验证后已删除，未触碰三仓）**：
  1. 正序（指南 1a / 5a / 5b）：`git init -b main` + `git remote add origin <本地裸仓>` + `AGENTS.md` / docs 索引 / `tools` 就位 → `git add -A && git commit` → `kb init` ⇒ exit 0、`{"op":"kb-init","changed":true,"created":["change-requests/_backlog.yml","change-requests/_index.yml"],"pushed":true}`，远端 `refs/heads/main` 落定；同命令重跑 ⇒ `changed=false`（幂等）。
  2. 替代序（指南「先初始化、后生成」）：workspace 仅含未提交 `dir-graph.yaml`、unborn HEAD、空远端 ⇒ `kb init` exit 0 且 `changed=true`；随后创建 `AGENTS.md` 与 docs 索引并 `git add -A && git commit` ⇒ 提交正常、工作树干净。
  3. 负控（回修前的旧顺序与两条前置）：`AGENTS.md` 未提交 ⇒ exit 1 `KB_INIT_PRECONDITION reason=dirty path=AGENTS.md`（零写入）；无 origin ⇒ `reason=repo-invalid`（`repo knowledge-base: 缺少 origin 远端`）；分支 `master` 对声明 trunk `main` ⇒ `reason=trunk-mismatch`。
- **TASK-09 的 AC-09 文档断言（在 cmd-05 内，本轮改动后仍 13/0）**：四手工治理模板仍消失、六种 docs 索引模板原文保留、指南含 `kb init` 入口、指南不含本机绝对路径。
- **B-CODE-05 修复仍有效（非 kb 语义回归）**：`Object.create(null)` 旗标袋的 `__proto__` 六向量（有值/无值 × 有根/缺根/空根）与零副作用断言在 cmd-01 内继续全绿；`parseGitArgs` 只写白名单字面键，不经用户键名；`gate` / `advance` 的 `{...flags}` 与 writeback-apply 的 `Object.keys`/`in flags` 判定在 cmd-01 / cmd-04 内回归。
- **cmd-03 跨秒 flake**：本轮 21/0（未复现）。该缺陷在 `writeback.test.mjs`（只 spawn `writeback-*.mjs` 生成器、不调用 `crctl.mjs`），与本次 doc-only 改动无因果，属上轮已披露的范围外既存缺陷。
- 全表耗时合计 ≈1035.9s（逐条相加 + cmd-07），与 `crctl test` 单次执行 wall 1036s（19:24:57 → 19:42:13）一致。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 | 本轮状态 |
|---|---|---|---|
| TASK-01 kb init 入口/前置/发布重入 | 1/2/3 | cmd-01 | ✅ 237/0（含 AC-01/02/03 与 B-CODE-01/02/03/05 定向回归） |
| TASK-02 ensure create 自忽略 | 1/2 | cmd-02 | ✅ 30/0 |
| TASK-03 source 空缺省 + 历史指纹矩阵 | 1/2/3 | cmd-02 | ✅（含 AC-11 四行矩阵） |
| TASK-04 buildIndex 首写 + features 前置 | 1/2/3 | cmd-03 | ✅ 21/0 |
| TASK-05 两规范表提取 | 1/2/3 | cmd-03 | ✅（AC-06/AC-07） |
| TASK-06 YAML trunk 解释 | 1/2 | cmd-03 | ✅（AC-08 五向量 + 交叉负测） |
| TASK-07 merge-base 裸提交 shape | 1/2 | cmd-01 | ✅（AC-10 真实 Git fixture） |
| TASK-08 writeback-tx 集成变体 | 1/2/3 | cmd-04 | ✅ 36/0（三阶段真实全链 + trace 前冻结 + 重放隔离） |
| TASK-09 说明/命令发现/计数同步 | 1/2/3 | cmd-05 + cmd-06 | ✅ 13 + 39；六模板保留/四模板消失/无本机路径断言在改动后仍绿；kb init 前置顺序引导已按 B-CODE-06 补齐 |
| TASK-10 ARCHITECTURE.md 地图维护 | 1/2 | cmd-07 | ✅ 7 判据全命中 |

## 新增/修改测试文件

- **本轮回修提交 tools `9e7612e`（1 文件、+30/−9，doc-only）**：`docs/QODER-使用指南.md` 环境准备节（第 1 步 origin/主 checkout/分支前提，第 5 步 5a/5b 提交与初始化顺序 + 替代顺序 + 硬前置与错误码）。未新增或修改任何测试文件；`git diff --stat ffa0c68..9e7612e` 仅该文件。
- 无生产/测试文件改动：`skills/shared/crctl/scripts/crctl.mjs`、`scripts/test/*`、`ARCHITECTURE.md`、`gates.json`、`rules.json`、`agent-skill-matrix.yml`、Pipeline 均未触碰；测试计数（cmd-01 237、cmd-02 30、cmd-03 21、cmd-04 36、cmd-05 13、cmd-06 39）与 `gate-registry` 登记未变。

## 未覆盖风险（含「不适用」说明）

1. **cmd-03 跨秒 flake 未消除（范围外既存缺陷）**：本轮 canonical 未复现（21/0），但同源码此前单跑 4 次出现 1 次失败，仍有概率性失败可能；成因是 `writeback-prd-sdd.mjs#buildIndex` 对既有条目无条件重写秒精度 `updated`，超出本 CR 批准范围，需后续 CR 单独处理。
2. **端到端补充验证的远端面**：正序/替代序验证用本地裸仓充当 `origin`，托管平台侧的首推认证、分支保护、默认分支命名等差异不在验证面内（指南以「先在托管平台建好空仓库」表述该前提，未标称已在真实托管平台验证）。
3. **额度余量**：cmd-04 644.2s 对 720s 余量 ≈10.5%；本轮 `crctl test` wall 1036s 对 `write-test-report` 节点声明 `timeoutMinutes: 20`（1200s）≈86.3%，仍偏窄。消费方在平台 runner，本仓无实现可验其是否硬性执行。
4. **`write-test-report` 环额度**：cycle 2 已 3/3，本轮按 canonical `pass` 规则自动滚动为 cycle 3 / attempt 1；若后续再需非 pass 的 canonical 轮，须由人工在 TTY 执行 `crctl review-loop reset CR-2026-074 --loop write-test-report --reason <…>`。
5. **cmd-07 只做 ARCHITECTURE.md 字符串命中**：不代替 `review-code` R7 对地图内容的人工检查。
6. **不适用**：lint/build 单列命令（零依赖 CLI，cmd-01～06 即 lint+test 面）；真实人工审批 E2E（SDD scope_out）；`write-requirement-prd` writer 侧非空 source 存在性校验（prompt 合同）。

## 下一步建议

1. 本节点 `status=pass`，本轮唯一 blocker B-CODE-06 已在其 `repair-target=implement-code` 范围内回修落盘（tools `9e7612e`）→ 进入 `workspace-freshness`（gate=review-start，本 run 于证据提交后实测）与 `review-code` 复评（cycle 2 / attempt 1 已被上轮 BLOCK 评审消耗，复评轮次以评审侧 `crctl` 账本为准）。
2. B-CODE-06 关闭判据：指南第 1 步的 origin / 主 checkout / 分支=声明 trunk 前提，第 5 步的「先提交白名单外文件再 init」显式顺序与等价替代顺序、硬前置与错误码列举；辅以本轮补充验证的正序/替代序成功与三条负控（dirty / repo-invalid / trunk-mismatch）实测。
3. 本报告所在 KB worktree 的证据改动（`test-report.md` / `test-evidence/cmd-01～07` / `traceability.yml` / `review-loop.yml`）由本节点在 KB worktree 落盘并**本地提交**；按 `review-code` 合同，block/回修中间态不发布远端，tools `9e7612e` 的远端发布由评审 PASS 分支的 `push-progress` checkpoint 承担。
