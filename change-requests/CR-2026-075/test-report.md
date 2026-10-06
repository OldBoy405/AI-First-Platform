---
cr: CR-2026-075
status: block
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-06T13:18:19+08:00"
command-digest: 4e29e60e40e65b4fa04615e604aff27ee4398aa1b8c8ff4fbd133fab92bf1725
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
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/planning-entry.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/competitive-report.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/durable-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/caller-contract.test.mjs, skills/shared/crctl/scripts/test/contract-scan.test.mjs, skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs, skills/shared/crctl/scripts/test/check-agents-contract.test.mjs, skills/shared/crctl/scripts/test/lint-prompts.test.mjs, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-05.log
  - repo: tools
    cwd: skills/shared/engineering-docs/scripts
    executable: node
    args: [node_modules/vitest/vitest.mjs, run, src/__tests__/generators.test.ts, src/__tests__/validators.test.ts]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-06.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/, "-count=1", -v, -run, "Test(InjectTaskCRWorkspaceEnv|DaemonEnvBuildHasNoConfigFirstRootFallback|PreparePipelineTaskHydratesMachineLocalPaths|ConfigurePipelineGitEnvironment|ConfigureTaskGitEnvironment|InstallPipelineCrctlLauncher|InstallCrctlLauncher|ResolveTaskWorkspaceBinding|ParseExecutionContext|TaskWorkspaceBinding)"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-07.log
  - repo: multica
    cwd: .
    executable: node
    args: [--test, cr-prompts-revised/test/delegation-contract.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-08.log
  - repo: multica
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CRLF=String.fromCharCode(13,10);const LD=p=>fs.readFileSync(p,'utf8').split(CRLF).join(NL);const H=t=>cr.createHash('sha256').update(t).digest('hex');const TR=x=>x.replace(new RegExp(NL+'+$'),'');const bad=[];const PROMPTS=['requirement-writer','dev-agent','quality-reviewer-agent','cr-coordinator-agent'];for(const n of PROMPTS){const p='cr-prompts-revised/'+n+'.md';if(!fs.existsSync(p)){bad.push('部署副本缺失: '+p);continue;}const t=LD(p);if(t.split('--workspace <workspace>').length>1)bad.push('短提示未收敛（仍含逐命令 workspace 示例）: '+p);if(t.length<800)bad.push('部署副本疑似被截断: '+p);if(t.indexOf('CR-ID')<0)bad.push('收敛误删显式 CR-ID: '+p);console.log('deployment-copy '+n+' sha256='+H(t));}const SK={'crctl':'skills/shared/crctl','validate-doc':'skills/shared/validate-doc','engineering-docs':'skills/shared/engineering-docs','cr-review-record':'skills/cr/cr-review-record','review-code':'skills/develop/review-code','review-dev-plan':'skills/develop/review-dev-plan','review-tech-design':'skills/develop/review-tech-design','write-dev-tasks':'skills/develop/write-dev-tasks','write-tech-design':'skills/develop/write-tech-design','review-requirement':'skills/requirement/review-requirement','write-planning-entry':'skills/planning/write-planning-entry','planning-draft':'skills/planning/planning-draft','write-competitive-report':'skills/competitive/write-competitive-report','requirement-register':'skills/requirement/requirement-register'};const list=JSON.parse(cp.execFileSync('multica',['skill','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of Object.keys(SK)){const e=list.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 imported Skill: '+n);continue;}const o=(e.config&&e.config.origin)||{};if(o.repo!=='AI-First-tools'||o.ref!=='main'||o.path!==SK[n])bad.push('取用路径漂移: '+n+' '+JSON.stringify(o));else console.log('imported-skill '+n+' AI-First-tools@main/'+o.path);}const ag=JSON.parse(cp.execFileSync('multica',['agent','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of PROMPTS){const e=ag.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 Agent: '+n);continue;}const live=String(e.instructions||'').split(CRLF).join(NL);const t=LD('cr-prompts-revised/'+n+'.md');if(TR(live)!==TR(t))bad.push('线上 instructions 与部署副本不一致: '+n+' live='+H(live)+' target='+H(t));else console.log('agent-in-sync '+n+' sha256='+H(live));}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-09 ok: 部署副本收敛与 imported Skills 取用路径零漂移；四份 CR Agent 线上 instructions 与部署副本逐字一致（LF）');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-09.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CRLF=String.fromCharCode(13,10);const LD=p=>fs.readFileSync(p,'utf8').split(CRLF).join(NL);const H=t=>cr.createHash('sha256').update(t).digest('hex');const TR=x=>x.replace(new RegExp(NL+'+$'),'');const bad=[];const SK={'crctl':'skills/shared/crctl','validate-doc':'skills/shared/validate-doc','engineering-docs':'skills/shared/engineering-docs','cr-review-record':'skills/cr/cr-review-record','review-code':'skills/develop/review-code','review-dev-plan':'skills/develop/review-dev-plan','review-tech-design':'skills/develop/review-tech-design','write-dev-tasks':'skills/develop/write-dev-tasks','write-tech-design':'skills/develop/write-tech-design','review-requirement':'skills/requirement/review-requirement','write-planning-entry':'skills/planning/write-planning-entry','planning-draft':'skills/planning/planning-draft','write-competitive-report':'skills/competitive/write-competitive-report','requirement-register':'skills/requirement/requirement-register'};const EXPECT={'crctl':['SKILL.md','scripts/crctl.mjs','scripts/lib/durable-tx.mjs','scripts/lib/planning-entry.mjs','scripts/lib/competitive-report.mjs','scripts/test/crctl.test.mjs','scripts/test/planning-entry.test.mjs','scripts/test/competitive-report.test.mjs','scripts/test/caller-contract.test.mjs','scripts/test/pipeline-structure.test.mjs','scripts/test/durable-tx.test.mjs','scripts/test/gate-registry.json'],'engineering-docs':['SKILL.md','scripts/src/utils/slug.ts','scripts/src/generators/base.ts','scripts/src/validators/index-sync.ts','scripts/src/__tests__/generators.test.ts','scripts/src/__tests__/validators.test.ts']};const list=JSON.parse(cp.execFileSync('multica',['skill','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));let expTotal=0,driftTotal=0;for(const n of Object.keys(SK)){const e=list.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 imported Skill: '+n);continue;}const g=JSON.parse(cp.execFileSync('multica',['skill','get',e.id,'--with-content','--output','json'],{encoding:'utf8',maxBuffer:512*1024*1024}));const online={'SKILL.md':String(g.content||'')};for(const f of (g.files||[]))online[f.path]=String(f.content||'');const exp=EXPECT[n]||['SKILL.md'];expTotal+=exp.length;let nBad=0;for(const p of exp){if(!Object.prototype.hasOwnProperty.call(online,p)){bad.push('本 CR 声明发布文件线上缺失: '+SK[n]+'/'+p);nBad++;continue;}const t=SK[n]+'/'+p;if(!fs.existsSync(t)){bad.push('仓库目标缺失: '+t);nBad++;continue;}if(TR(online[p].split(CRLF).join(NL))!==TR(LD(t))){bad.push('线上内容与仓库目标不一致: '+t);nBad++;}}const drift=[];for(const p of Object.keys(online)){if(exp.indexOf(p)>=0)continue;const t=SK[n]+'/'+p;if(!fs.existsSync(t)||TR(online[p].split(CRLF).join(NL))!==TR(LD(t)))drift.push(p);}if(drift.length){driftTotal+=drift.length;console.log('out-of-scope-drift '+n+' N='+drift.length+'（R8 范围外既有漂移，单列、不参与本 CR 通过判定）: '+drift.join(','));}if(!nBad)console.log('skill-in-sync '+n+' expected='+exp.length+' online='+Object.keys(online).length+' sha256='+H(exp.map(p=>p+':'+H(online[p].split(CRLF).join(NL))).join(NL)));}const AG={'product-planning-agent':'agents/product-planning-agent.md','competitive-analyst-agent':'agents/competitive-analyst-agent.md'};const ag=JSON.parse(cp.execFileSync('multica',['agent','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of Object.keys(AG)){const e=ag.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 Agent: '+n);continue;}const live=String(e.instructions||'').split(CRLF).join(NL);const t=LD(AG[n]);if(TR(live)!==TR(t))bad.push('线上 instructions 与仓库目标不一致: '+n+' live='+H(live)+' target='+H(t));else console.log('agent-in-sync '+n+' sha256='+H(live));}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-10 ok: 本 CR 声明发布集全覆盖（expected='+expTotal+' 个文件线上存在且与仓库目标逐字一致，LF）；范围外既有漂移单列 '+driftTotal+' 项不计入通过判定（R8）；规划/竞品两个业务调用方 Agent instructions 与仓库目标逐字一致');"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-10.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/test/suite-gate.mjs, --run]
    timeout-seconds: 3600
    exit-code: 1
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-075/test-evidence/cmd-11.log
---

# 测试报告 · CR-2026-075

<!-- crctl:analysis-below -->

## 1. 测试摘要

- **结论：`status=block`**（机器区 `generated-by: crctl-test`、`attempt=1`、`command-digest=4e29e60e40e65b4fa04615e604aff27ee4398aa1b8c8ff4fbd133fab92bf1725`、`generated-at=2026-10-06T13:18:19+08:00`，由单次 `crctl test` 生成，本文件只在其下补分析段）。
- 11 条 canonical 证据命令（逐条转录自 `plan.md` 证据命令表，`cmd-01`～`cmd-11`）中：**10 条 exit 0，`cmd-11` exit 1**；无 `timeout`、无 `signal`，11 条 `started=true` / `skipped=false`。
- 阻塞项 = `cmd-11`（聚合门禁 `suite-gate.mjs --run`）：`verdict=block` / `check_failed=SUITE_FAILURES_UNREGISTERED`，`files_executed 28 / cases_executed 693 / failures 4`，4 例全在 `crctl-summary.test.mjs`（`summary-03`～`summary-06`），`registry.exceptions_count=0`。详见 §5 R17。
- TASK 账本 `tasks/_index.yml` 10/10 `done`；每条 TASK 的验收证据命令见 §3，无「缺证据」TASK（每条命令均有日志与退出码）。

## 2. 验证命令与结果解读

| 命令 | 命令面（`plan.md` 证据命令表原样） | exit | 关键结果（本轮 `test-evidence/cmd-NN.log` 原文） |
|---|---|---|---|
| `cmd-01` | tools · `node --test test/crctl.test.mjs` | 0 | `pass 247 / fail 0`（`duration_ms 143671.95`） |
| `cmd-02` | tools · `node --test test/planning-entry.test.mjs` | 0 | `pass 10 / fail 0` |
| `cmd-03` | tools · `node --test test/competitive-report.test.mjs` | 0 | `pass 15 / fail 0` |
| `cmd-04` | tools · `node --test test/durable-tx.test.mjs` | 0 | `pass 16 / fail 0` |
| `cmd-05` | tools · `node --test`（`caller-contract` + `contract-scan` + `check-skill-matrix` + `check-agents-contract` + `lint-prompts` + `pipeline-structure`） | 0 | `pass 125 / fail 0` |
| `cmd-06` | tools · `skills/shared/engineering-docs/scripts` · vitest（`generators.test.ts` + `validators.test.ts`） | 0 | 2 文件通过，`21 tests` 通过、0 失败（12 + 9） |
| `cmd-07` | multica · `server` · `go test ./internal/daemon/ -count=1 -v -run "Test(InjectTaskCRWorkspaceEnv\|…\|TaskWorkspaceBinding)"` | 0 | 定向名集全部 `--- PASS`，`ok github.com/multica-ai/multica` |
| `cmd-08` | multica · `node --test cr-prompts-revised/test/delegation-contract.test.mjs` | 0 | `pass 19 / fail 0` |
| `cmd-09` | multica · 生效内容比对（平台只读查询 `multica` CLI） | 0 | 逐项 `agent-in-sync` / `imported-skill` 一致 |
| `cmd-10` | tools · 生效内容比对（技能/Agent 文件头基线） | 0 | 逐项 `skill-in-sync expected=1 online=1` |
| `cmd-11` | tools · `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` | **1** | `verdict=block`，`failures=4`（`summary-03`～`summary-06`） |

解读边界（不得互相冒充）：

- `cmd-01`～`cmd-10` 是**定向文件集**，`cmd-11` 是 `skills/shared/crctl/scripts/test/` **28 文件集合门禁**；前十条全绿**不得**被读作 `cmd-11` 通过，反之 `cmd-11` 的红也不改变前十条各自的定向结论。
- `cmd-11` 的红项**不得**被读作本 CR 引入的回归：`crctl-summary.test.mjs` 不在本 CR `sdd.md` §9 `scope_in` 的声明文件集内；基线复现（诊断探针，不属证据命令集、不新增证据 ID；**本轮独立复跑确认**）：以 `git archive 061a12f skills/shared/crctl` 抽出基线副本独立复跑该文件 → `tests 8 / pass 4 / fail 4`（exit 1），失败用例集与本轮 HEAD 同集（`summary-03`～`summary-06`），失败签名 `SyntaxError: Unexpected end of JSON input`。本轮实测 `061a12f` = tools 分支与 `main` 的 merge-base，即本 CR 基线。
- 根因（本轮实测环境事实）：该测试用 `os.tmpdir()` 造夹具并以 `--workspace <tmp>` 驱动 CLI，而任务环境已注入绑定变量（本轮实测 `CRCTL_OPERATIONAL_WORKSPACE=C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-075`）→ 显式异根被 `WORKSPACE_CONTEXT_MISMATCH` 拒绝、stdout 为空 → `SyntaxError: Unexpected end of JSON input`。同一来源已在 `uncovered-risks.md` 登记为 R17。
- `cmd-09` / `cmd-10` 是**读取平台现状与仓库副本比对**的观测面（比对成功即一致），不构成对 Agent/Skill 运行时行为的验证。
- 证据绑定口径的诚实边界：`write-test-report` SKILL 文本称「机器区 `resultFacts` 发布每条命令的 `sourceRevision` 与日志哈希」，本轮机器区实测**不含**这两个字段（`renderTestMachineReport` 只输出 repo/cwd/executable/args/timeout-seconds/exit-code/signal/timed-out/started/skipped/log）；逐值比对基线 `061a12f` 的同一渲染函数，代码与本轮 HEAD 逐字相同（该文件本 CR 未改）→ 属**既有 SKILL 文本与该实现的表述差**，非本 CR 回归，也不改变本节点 pass/block 判定。本轮证据以 `test-evidence/cmd-NN.log` 原文 + 机器区 `exit-code` 为准。

## 3. TASK 验收覆盖矩阵

| TASK | 标题 | 验收证据命令 | 本轮结果 |
|---|---|---|---|
| `CR-2026-075-TASK-01` | crctl 绑定归一与失败关闭 | `cmd-01`、`cmd-05`、`cmd-07` | 全绿（247 / 125 / 定向 go PASS） |
| `CR-2026-075-TASK-02` | daemon 绑定解析与三元组成对发布 | `cmd-07`、`cmd-09` | 全绿 |
| `CR-2026-075-TASK-03` | 共享恢复原语锁内比对与取样 | `cmd-01`、`cmd-04` | 全绿（247 / 16） |
| `CR-2026-075-TASK-04` | 规划业务入口与确定性转换 | `cmd-01`、`cmd-02`、`cmd-03`、`cmd-11` | `cmd-01`/`02`/`03` 绿；`cmd-11` 红（R17） |
| `CR-2026-075-TASK-05` | 竞品业务入口与确定性转换 | `cmd-01`、`cmd-02`、`cmd-03`、`cmd-11` | 同上 |
| `CR-2026-075-TASK-06` | validate 维度报告层与触发条件对齐 | `cmd-01`、`cmd-05` | 全绿（247 / 125） |
| `CR-2026-075-TASK-07` | engineering-docs 合同与北京时间日期 | `cmd-02`、`cmd-03`、`cmd-05`、`cmd-06`、`cmd-07`、`cmd-10` | 全绿 |
| `CR-2026-075-TASK-08` | 调用登记、命令示例与提示收敛 | `cmd-01`、`cmd-05`、`cmd-07` | 全绿；FR-04 段①②断言在 `cmd-01`/`cmd-05` 内 |
| `CR-2026-075-TASK-09` | 部署副本收敛、合同对齐与生效版本台账 | `cmd-08`、`cmd-09`、`cmd-10` | 全绿 |
| `CR-2026-075-TASK-10` | 全量证据回归与未覆盖风险清单 | `cmd-01`～`cmd-11` | 10 绿 1 红（`cmd-11`，R17），清单见 `uncovered-risks.md` |

`cmd-11` 的红项与 `TASK-04`/`TASK-05`/`TASK-10` 的关联仅在于它们引用了该命令作为证据来源；红项的观测对象是 `crctl-summary.test.mjs`（非本 CR 声明文件集），**不得**据此判定这三个 TASK 的交付面未通过。

## 4. 新增 / 修改测试文件（vs 基线 `061a12f`）

- 新增：`skills/shared/crctl/scripts/test/planning-entry.test.mjs`、`skills/shared/crctl/scripts/test/competitive-report.test.mjs`。
- 修改：`crctl.test.mjs`（+394）、`durable-tx.test.mjs`（+199）、`caller-contract.test.mjs`（+87）、`fault-harness.test.mjs`、`register-tx.test.mjs`、`test-cr.test.mjs`、`merge-fixture.mjs`、`gate-registry.json`；`skills/shared/engineering-docs/scripts/src/__tests__/generators.test.ts`、`.../validators.test.ts`。
- `gate-registry.json` 的本轮改动只在 `manifest.cases` 计数面：`exceptions` 仍为显式空数组（`registry.exceptions_count=0`），**不得**被读作已登记例外。

## 5. 未覆盖风险（`test-evidence/uncovered-risks.md` 为权威载体）

- **R17（本轮阻塞项）**：`cmd-11` 红，4 例全在 `crctl-summary.test.mjs`；基线同集复现、`exceptions_count=0`。本节点**只登记与如实转录**，不在本节点修该文件（不在 `sdd.md` §9 `scope_in` 内）。
- R10（`cmd-07` 为定向 `-run` 名集，不读作 `./internal/daemon/` 全量）、R11（`cmd-08` 只覆盖合同/提示/维护副本枚举对齐）、R12（`cmd-06` 只覆盖 `generators`/`validators` 两文件；`chain.test.ts` 2 例基线红，另开 CR）、R13（`cmd-01` 钉住的是机器语义，不读作 FR-04 段③）、R14（FR-04 三段互不冒充）：逐条与 `uncovered-risks.md` 一致。
- 不适用 / 边界说明（不得空白通过）：FR-04 段③（实际受控调用方节点回放）**不由任何 `cmd-NN` 断言**，载体 = `test-evidence/caller-replay/` 归档 + `review-code` 人工逐条核对；B4 保留项 = 人工检查边界；S2/M3 场景在本节点绑定环境内不产生，其机器行为由 `cmd-01` 的 A6 向量覆盖；`cmd-11` 只覆盖 tools crctl 测试文件集合（磁盘集合 ≡ `manifest.files`），不读作多仓全量。
- 无空白项：11 条命令均有退出码与日志；`skipped=false` × 11。

## 6. 下一步建议

- 机器判定（本轮实测，exit 0）：`crctl next CR-2026-075 --workspace <workspace>` → `{"status":"developing","next":"implement-code","why":"test-report.status=block，按 replayNodes 回修"}`；`write-test-report` reviewLoop `current-attempt=1 / max=3`。
- 按 Skill，`status=pass` 前不得进入 `review-code` 或人工审批；本节点未进入评审、未推进状态、未改任何账本（`traceability.yml#tests` 与 `review-loop.yml` 由 `crctl test` 独占写入）。
- R17 的修复面**不在本 CR 已批准文件集内**，本节点不代裁、不越范围修复；可选路径（任一都需 owner / 评审判定面决定，本报告不预判）：① 将 `crctl-summary.test.mjs` 纳入范围（= `sdd.md` §9 `scope_in` 修订 + 人工批准）后修该测试的夹具与绑定环境交互；② 在 `gate-registry.json#exceptions` 登记例外（门禁治理动作，含 owner 与到期时间；该面交付态目前为显式空数组）；③ 由 owner 决定接受该红项并说明其对代码审批的影响。
