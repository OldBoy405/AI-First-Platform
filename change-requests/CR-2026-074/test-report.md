---
cr: CR-2026-074
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-02T19:05:14+08:00"
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

- **本轮 = `write-test-report` 环 cycle 2 / attempt 3 的 canonical 证据轮**（`generated-at 2026-10-02T19:05:14+08:00`，事务 `9aabfc941f4544599e05747b34d8b57a` `phase=complete`），由 `crctl test` 单次执行 `plan.md` §6.2 全表 7 条命令，命令表逐条原样转录（cmd-04 `timeout` 720 沿用 KB 提交 `11c59987` 的判据修订）。
- **机器区 `status: pass`**：7/7 条命令 `exit-code=0`、`started=true`、`skipped=false`、`timed-out=false`；`command-digest bb1e0976672d9f73c8ba056218926da87163751879515b212a69269ca0b688ab`（命令表未变，digest 与上一轮全等）。
- **证据↔源码绑定（B-CODE-05 修复轮）**：7 条命令的 `sourceRevision` = tools CR worktree HEAD `ffa0c68bcad359bc7389103093c64d8ba8f57b9a`（B-CODE-05 修复提交）。以该 revision 与七条 `test-evidence/cmd-NN.log` 的 sha256（`f8436bc970` / `b80fbedfea` / `8bbb2e4d98` / `9aa6fbd2d1` / `77d1d82540` / `3e61a62b87` / `0badead2e8` 前缀）按 `sha256(command-digest + resultMetadata + tester + owner-assigned-at)` 独立重算 `inputDigest = 4313fe37ce885cf6281ad3a532127f72675ae73972f2afc59a107aa749d441d5`，与 journal 全等——被测源码即修复提交本身，无未提交漂移。
- 修复提交在测试**之前**落盘（`ffa0c68`），故 `sourceRevision` 可解析到含修复内容的具体提交；KB worktree 在执行时为 `2cd9a55b`（`review-code` 额度重置提交）。

## 验证命令与结果解读（cycle 2 attempt 3 机器区逐条）

| 证据ID | 命令（tools CR worktree 根；机器区 `repo=tools` `cwd=.`） | 机器区结果 | canonical 日志（`test-evidence/`） |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | exit 0，`skipped=false` | 237 pass / 0 fail · 169.7s |
| cmd-02 | `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` | exit 0，`skipped=false` | 30 pass / 0 fail · 223.1s |
| cmd-03 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | exit 0，`skipped=false` | 21 pass / 0 fail · 2.6s |
| cmd-04 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | exit 0，`skipped=false`（上限 720s） | 36 pass / 0 fail · 634.6s |
| cmd-05 | `node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs` | exit 0，`skipped=false` | 13 pass / 0 fail · 0.4s |
| cmd-06 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | exit 0，`skipped=false` | 39 pass / 0 fail · 2.2s |
| cmd-07 | plan §6.2 cmd-07 行原样 argv | exit 0 | `cmd-07 ok: 7 map markers present` |

- **cmd-04 判定**：634.6s < 720s（余量 85.4s，≈11.9%），落在已记录区间 573.5–651.2s 内。
- **B-CODE-05 回修证据（本轮 cmd-01 的 `CR-2026-074 AC-02` 用例内）**：`kb init` 额外旗标向量的旗标名为 `__proto__`——旧实现 `parseArgs` 的旗标袋为普通 `{}`，`flags['__proto__'] = x` 命中 `Object.prototype` 的访问器 setter，不形成自有可枚举键，`Object.keys(flags)` 只剩 `workspace`，额外旗标拒绝被绕过并继续创建/提交/推送/成功审计（回修前实测：`kb init --workspace <合法 KB> --__proto__ x` exit 0 且完成初始化）。回修把旗标袋改为 `Object.create(null)`（`skills/shared/crctl/scripts/crctl.mjs#parseArgs`），每个用户旗标（含 `__proto__` 等原型名）均为可枚举自有键；新增六向量：`--__proto__` 有值 / 无值 × {有根, 缺根, 空根}，并覆盖有根的两序（旗标在 `--workspace` 之后 / 之前）。断言：有根一律 `BAD_ARGS` 且消息命中 `--__proto__`；缺根/空根一律 `WORKSPACE_REQUIRED`（`requireExplicitWorkspace` 先于 kb 形态校验的优先级不变）；随后零副作用断言（`change-requests/` 未创建、本地 HEAD 未提交、远端 trunk 空、无 audit 行）。修复前同用例先验红（断言 `0 !== 1`），修复后转绿。
- **非 kb 语义回归**：`Object.create(null)` 只改变旗标袋原型，键枚举 / `in` / 展开 / JSON 序列化语义不变；`crctl git` 的 `parseGitArgs` 只写白名单字面键（`--cwd` / `--workspace`），不经用户键名，故不在该向量上。既有非 kb 用例（workspace 守卫、help 无根、`gate` / `advance` 的 `{...flags}` 展开、writeback-apply 的 `Object.keys`/`in flags` 判定）在 cmd-01 / cmd-04 内全绿。
- **cmd-03 跨秒 flake**：本轮 21/0。同源码（未改动）在 canonical 轮之外单跑 4 次为 3 通过 / 1 失败（失败断言仍是 `assert.ok(r3.stdout.includes('"noop": true'))`），且 `writeback.test.mjs` 只 spawn `writeback-*.mjs` 三个生成器、完全不调用 `crctl.mjs`，故与本轮回修无因果——属上一轮报告已披露的范围外既存缺陷（`buildIndex` 对既有条目无条件重写秒精度 `updated`）。
- 全表耗时合计 ≈1032.7s（逐条相加 + cmd-07），与 `crctl test` 单次执行 wall 1033.5s 一致。

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
| TASK-09 说明/命令发现/计数同步 | 1/2/3 | cmd-05 + cmd-06 | ✅ 13 + 39；crctl 计数 237 未变 |
| TASK-10 ARCHITECTURE.md 地图维护 | 1/2 | cmd-07 | ✅ 7 判据全命中 |

## 新增/修改测试文件

- **本轮修复提交 tools `ffa0c68`（2 文件、+35/−5）**：
  - `skills/shared/crctl/scripts/crctl.mjs`：`parseArgs` 旗标袋 `{}` → `Object.create(null)`，附根因注释（B-CODE-05）。
  - `skills/shared/crctl/scripts/test/crctl.test.mjs`：`CR-2026-074 AC-02` 用例内新增 `__proto__` 六向量（有值 / 无值 × 有根 / 缺根 / 空根，有根含两序）并把紧随其后的零副作用断言扩注为同时覆盖该向量。既有 237 例计数与 `gate-registry` 登记未变（新断言并入既有用例，未新增 test 顶层用例）。
- 无其他生产/测试文件改动：`ARCHITECTURE.md`、`gates.json`、`rules.json`、`agent-skill-matrix.yml`、Pipeline 均未触碰。

## 未覆盖风险（含「不适用」说明）

1. **cmd-03 跨秒 flake 未消除（范围外既存缺陷）**：本轮 canonical 未复现（21/0），但同源码单跑 4 次出现 1 次失败，仍有概率性失败可能；成因是 `writeback-prd-sdd.mjs#buildIndex` 对既有条目无条件重写秒精度 `updated`，改变不了本轮批准范围的索引历史语义，需后续 CR 单独处理。
2. **`write-test-report` 环额度已用满**：cycle 2 现为 3/3（cycle 1 的 attempt 1–3 保留在历史）。canonical `status=pass` 时重跑仍被放行（`TEST_LOOP_EXHAUSTED` 只在非 pass 时抛出），但若后续需要新的 canonical 轮且处于非 pass，须由人工在 TTY 执行 `crctl review-loop reset CR-2026-074 --loop write-test-report --reason <…>`。
3. **额度余量仍偏窄**：cmd-04 634.6s 对 720s 余量 ≈11.9%；`write-test-report` 节点声明 `timeoutMinutes: 20`（1200s），本轮节点实测总量 ≈1033s（≈86.1%）。消费方在平台 runner，本仓无实现可验其是否硬性执行。
4. **`__proto__` 向量在非 kb 入口无专项负测**：`Object.create(null)` 使该键在所有入口都成为可枚举自有键，但本 CR 只在 `kb init`（唯一以 `Object.keys(flags)` 做白名单式额外旗标拒绝的入口）上加了向量与断言；`writeback-apply` 的同类判定（`allowedFlags`）与 `workspace` / `merge` 的额外旗标判定在 cmd-01 / cmd-04 的既有用例内回归，未新增专门的原型名向量。
5. **cmd-07 只做 ARCHITECTURE.md 字符串命中**：不代替 `review-code` R7 对地图内容的人工检查。
6. **不适用**：lint/build 单列命令（零依赖 CLI，cmd-01～06 即 lint+test 面）；真实人工审批 E2E（SDD scope_out）；`write-requirement-prd` writer 侧非空 source 存在性校验（prompt 合同）。

## 下一步建议

1. 本节点 `status=pass` → 进入 `workspace-freshness`（gate=review-start，本 run 于证据提交后实测）与 `review-code`（cycle 2 / attempt 1）。`review-annotations/code.yml` 现为 `verdict: block`（`blocker-count: 1`，B-CODE-05，`repair-target: implement-code`），其要求的回修（tools `ffa0c68`）与本轮 canonical 证据已就位，待复评刷新。
2. B-CODE-05 关闭判据：`__proto__` 有值 / 无值 × 有根 / 缺根 / 空根六向量 + 零副作用断言（cmd-01 内），以及 `inputDigest` 以 `ffa0c68` 重算全等（证据↔源码绑定，见「测试摘要」）。
3. 本报告所在 KB worktree 的证据改动（`test-report.md` / `test-evidence/cmd-01～07` / `traceability.yml` / `review-loop.yml`）由本节点在 KB worktree 落盘并**本地提交**；按 `review-code` 合同，block/回修中间态不发布远端，tools `ffa0c68` 的远端发布由评审 PASS 分支的 `push-progress` checkpoint 承担。
