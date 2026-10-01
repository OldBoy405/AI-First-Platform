---
cr: CR-2026-074
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-02T00:01:57+08:00"
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
    timeout-seconds: 600
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

全部 10 个 TASK（CR-2026-074-TASK-01 ～ TASK-10）已实现、登记 done 并提交（tools 仓 `requirement/CR-2026-074` HEAD `3eda3eedd4fe5b6497647b3f6d02829e80187c51`，17 files，+1480/−69）。七条证据命令（plan.md §6.2 稳定表逐条转录，cmd-01～cmd-07）全部 exit 0、skipped=false、无超时，机器区 `status: pass`。

## 验证命令与结果解读

| 证据ID | 命令（tools worktree 根） | 结果 | 覆盖解读 |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | exit 0，235 pass / 0 fail | TASK-01 kb init（AC-01 happy/noop、AC-02 前置优先级与零写入、AC-03 wx/写失败/Git 三阶段注入与续跑、守卫回归）、TASK-07 merge-base 裸提交对（AC-10：7/40 位放行、exit 0/1 原语义、非法形态 FORBIDDEN_SUBCOMMAND、旧两 shape 回归）及既有全套回归 |
| cmd-02 | `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` | exit 0，30 pass / 0 fail | TASK-02 ensure create 自忽略（AC-04：init→首 CR→主 KB clean→runtime ignore=`*`→根 .gitignore 不变→重入无重复 CR）、TASK-03 source 空缺省与历史指纹矩阵（AC-11 四行 + 验收 2/3）及既有全套回归 |
| cmd-03 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | exit 0，21 pass / 0 fail | TASK-04 buildIndex 缺文件首写 + features 前置校验（AC-05 四类结构负例/正例/历史保留）、TASK-05 两规范表提取（AC-06 正例/061 管道 args/066 预算诱饵排除、AC-07 结构负例与 LF/CRLF 等价）、TASK-06 YAML trunk（AC-08 引号/非首键/inactive/缺失/不唯一/空值）及既有回归 |
| cmd-04 | `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | exit 0，36 pass / 0 fail | TASK-08 无索引/证据齐全集成变体（AC-12 无索引 merge→baseline 首写→trace→archive 全链、签字源规范行尾哈希不变、trace 重放保持 writing-back 不先 archive；AC-05 apply 侧：journal 后并发创建索引 → before=null CAS 拒绝、并发内容保留、authority 不写、恢复续跑幂等）及既有回归 |
| cmd-05 | `node --test skills/shared/crctl/scripts/test/caller-contract.test.mjs` | exit 0，13 pass / 0 fail | TASK-09 caller-13：kb 缺根/空根 WORKSPACE_REQUIRED、TWO_WORD/CR_DATA_FIRST_WORDS 含 kb、代码入口契约（cmdKbInit 特判派发先于 detectWorkspace）、crctl SKILL/requirement-register/README/QODER 文档入口一致、AC-09 QODER 四手工模板消失六 docs 模板保留；caller-01～12 回归（含 caller-09 白名单补登记：write-dev-plan/SKILL.md:61 与 skill-scope.test.mjs:87/136 的 `crctl test` 散文/断言提及，为 trunk 既存未登记项，非本次引入） |
| cmd-06 | `node --test skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | exit 0，39 pass / 0 fail | 说明与可执行命令一致、skill matrix / agents contract / prompt lint enforce 0 findings |
| cmd-07 | plan §6.2 cmd-07 行原样 argv | exit 0，7 map markers present | TASK-10 ARCHITECTURE.md 地图条目锚点可机器观测（语义正确性由 review-code R7 人工内容检查承载，非 cmd-07 代替） |

执行上下文：tools CR worktree（`workspace inspect` classification=healthy、dirty=false，提交后复核 clean）；Node v24.15.0、Git 2.54.0.windows.1；全部命令 shell:false、无 fault 注入、无背景进程残留。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 |
|---|---|---|
| TASK-01 kb init 入口/前置/发布重入 | 1/2/3 | cmd-01（AC-01/02/03 定向用例 + 守卫负测）；文件集经受控 `crctl git status --porcelain`（提交前实测，实现产物恰为本卡两文件，最终提交文件集见下） |
| TASK-02 ensure create 自忽略 | 1/2 | cmd-02（AC-04 联测：init→register 首 CR→重入） |
| TASK-03 source 空缺省 + 历史指纹矩阵 | 1/2/3 | cmd-02（矩阵四行 + 空/显式空串 + 非空合同） |
| TASK-04 buildIndex 首写 + features 前置 | 1/2/3 | cmd-03（四类负例/首写正例/历史保留） |
| TASK-05 两规范表提取 | 1/2/3 | cmd-03（AC-06/AC-07 + 061/066 片段 fixture，来源 commit 与 LF SHA 记录于 fixture 注释） |
| TASK-06 YAML trunk 解释 | 1/2 | cmd-03（AC-08 五向量 + 交叉负测保留） |
| TASK-07 merge-base 裸提交 shape | 1/2 | cmd-01（AC-10 真实 Git fixture） |
| TASK-08 writeback-tx 集成变体 | 1/2/3 | cmd-04（AC-12 全链 + AC-05 apply 侧；临时测试仓内 Git 配置，零触全局身份） |
| TASK-09 说明/命令发现/计数同步 | 1/2/3 | cmd-05（caller-13）/cmd-06（gate-registry 计数同步：crctl 235、caller-contract 13、lint-prompts 39、register-tx 30、writeback-tx 36） |
| TASK-10 ARCHITECTURE.md 地图维护 | 1/2 | cmd-07（7 判据全命中）；文件集经受控 status（本卡变更仅 ARCHITECTURE.md） |

实现产物提交文件集（受控 `crctl git status --porcelain` 实测 17 文件，恰为各卡声明文件并集，无夹带）：crctl.mjs、workspace-transactions.mjs、writeback-prd-sdd.mjs、writeback-traceability.mjs、rules.json、controlled-shell/SKILL.md、crctl/SKILL.md、requirement-register/SKILL.md、README.md、docs/QODER-使用指南.md、ARCHITECTURE.md、crctl.test.mjs、register-tx.test.mjs、writeback.test.mjs、writeback-tx.test.mjs、caller-contract.test.mjs、gate-registry.json。

## 新增/修改测试文件

- `skills/shared/crctl/scripts/test/crctl.test.mjs`：+5 用例（TASK-01 四用例 + TASK-07 一用例），dep-16 局部裁剪 fixture `makeKbInitFixture`、测试专用注入 shim（--require preload 等价 PATH shim，仅隔离子进程）。
- `skills/shared/crctl/scripts/test/register-tx.test.mjs`：+4 用例（TASK-02 AC-04 联测 + TASK-03 矩阵三用例），fixture `makeKbInitRegisterFixture`。
- `skills/writeback/scripts/test/writeback.test.mjs`：+5 用例（TASK-04 三 + TASK-05 三 + TASK-06 一；AC-07 内含多向量），历史片段 fixture（061/066 来源 SHA 注释内登记）。
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`：+2 用例（TASK-08），`makeNoIndexMergedFixture` 局部包装（不改 merge-fixture.mjs）。
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`：+1 用例（caller-13）+ 两集合加 kb + 白名单补 2 文件 3 条既存提及登记。

## 未覆盖风险与不适用说明

- **不适用**：lint/build 单列命令（本 CR 为零依赖 CLI，cmd-01～06 即 lint+test 面；pre-commit 钩子实跑 skill-matrix/agents-contract/lint-prompts enforce 全过，见提交输出）；真实人工审批 E2E（SDD scope_out）；`write-requirement-prd` writer 侧非空 source 存在性校验（prompt 合同，CLI 不代执行，测试以产物空值断言）。
- **风险 1（范围外既存缺陷，未修）**：generator 的 selfCheck 与「索引无变化时跳过推送」在跨秒边界 + 半应用（仅复制索引、未复制 PRD/SDD）状态下会误报 SELF_CHECK_FAILED——复现需同秒双跑且人为半应用，属 writeback-prd-sdd.mjs 既有交互（本 CR scope 未触及 selfCheck，zero_diff），已按确定性形态改写 TASK-04 验收 3 断言避开；建议后续 CR 单独治理。
- **风险 2**：Windows 下 spawnSync 无法以 .cmd 做 PATH git shim，Git 阶段故障注入采用 `--require` preload 等价实现（仅隔离子进程、不新增生产 faultPoint），语义与 SDD §5.2 描述等价，已在测试注释登记。
- **风险 3**：cmd-01/02/04 用例数与 gate-registry 登记值同步为实测值；登记面为下限口径（suite-gate `<` 即红），后续新增用例无需回改。

## 下一步建议

`status=pass`：按 pipeline 进入 `review-code`（评审前先跑 workspace-freshness gate=review-start）；tools 仓提交 `3eda3ee` 未推送，发布归 checkpoint/merge 深原语（reviewer PASS 分支一次闭合）。