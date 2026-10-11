---
cr: CR-2026-076
status: pass
tester: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
generated-by: crctl-test
generated-at: "2026-10-11T19:43:24+08:00"
command-digest: abf0f64ae5ede35876ad13b1a84e3585515816e25c78cdad6c6c718c83bebeb1
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/, "-count=1", -v, -run, "Test(ResolveTaskWorkspaceBinding|InjectTaskCRWorkspaceEnv|ParseExecutionContext|TaskWorkspaceBinding|PipelinePromptCarriesTheVerifiedExecutionContext|FindPipelineCRRootCardinality|PreparePipelineTaskHydratesMachineLocalPaths|PreparePipelineTaskDirtyGate|InspectPipelineWorkspaceDirtyInput|InspectPipelineWorkspaceDetailContract|DaemonEnvBuildHasNoConfigFirstRootFallback)"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-01.log
    source-revision: e5f0fc089ee93517482f57f4b6332ff70dd25218
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/, "-count=1", -v, -run, "Test(ConfigurePipelineGitEnvironment|ConfigureTaskGitEnvironment|PreparePipelineTaskHydratesMachineLocalPaths|InjectTaskCRWorkspaceEnv)"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-02.log
    source-revision: e5f0fc089ee93517482f57f4b6332ff70dd25218
  - repo: multica
    cwd: server
    executable: node
    args: [-e, "const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CR=String.fromCharCode(13);const D='internal/daemon/repocache/';const LD=p=>fs.readFileSync(p,'utf8').split(CR+NL).join(NL);const prod=fs.readdirSync(D).filter(f=>f.endsWith('.go')&&!f.endsWith('_test.go')).sort();console.log('prod-files: '+prod.join(' '));const bad=[];const pats=['GIT_CONFIG_GLOBAL','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_','GIT_CONFIG_VALUE_','multica-identity.config','config.worktree'];const hits={};for(const p of pats){hits[p]=[];for(const f of prod){const ls=LD(D+f).split(NL);for(let i=0;i<ls.length;i++){if(ls[i].indexOf(p)>=0){hits[p].push(f+':'+(i+1));}}}console.log('sites '+p+' = '+hits[p].length+' ['+hits[p].join(', ')+']');}if(hits['GIT_CONFIG_GLOBAL'].length!==0){bad.push('repocache 生产文件出现 GIT_CONFIG_GLOBAL: '+hits['GIT_CONFIG_GLOBAL'].join(','));}const gc=hits['GIT_CONFIG_COUNT'].concat(hits['GIT_CONFIG_KEY_'],hits['GIT_CONFIG_VALUE_']);if(gc.length===0){bad.push('未观测到 daemon 子进程 Git 配置追加点（cache.go gitEnv）');}for(const h of gc){if(h.slice(0,h.indexOf(':'))!=='cache.go'){bad.push('GIT_CONFIG_* 追加点不在 cache.go: '+h);}}const cw=hits['multica-identity.config'].concat(hits['config.worktree']);if(cw.length===0){bad.push('未观测到 checkout 私有 Git 配置写入点（identity.go）');}for(const h of cw){if(h.slice(0,h.indexOf(':'))!=='identity.go'){bad.push('checkout 私有配置写入点不在 identity.go: '+h);}}const dep=cp.spawnSync('go',['list','-deps','./internal/daemon/repocache/'],{encoding:'utf8'});const dl=String(dep.stdout?dep.stdout:'').split(NL).map(s=>s.trim()).filter(s=>s.length>0);const dh=dl.filter(s=>s.endsWith('/internal/daemon'));console.log('go-list-deps: status='+dep.status+' pkgs='+dl.length+' internal-daemon-hits='+dh.length);if(dep.status!==0){bad.push('go list -deps 非零退出: '+String(dep.stderr?dep.stderr:'').slice(0,300));}if(dh.length!==0){bad.push('repocache 依赖 internal/daemon: '+dh.join(','));}if(bad.length!==0){console.error(bad.join(NL));process.exit(1);}console.log('cmd-03 ok: repocache 生产面 GIT_CONFIG_GLOBAL 命中 0；GIT_CONFIG_* 追加点仅 cache.go；checkout 私有配置写入点仅 identity.go；go list -deps 命中 internal/daemon = 0（观测面 = FR-02 第二处写入点核实结论；该包全文件测试的既有平台失败另行留证，不判为通过）');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-03.log
    source-revision: e5f0fc089ee93517482f57f4b6332ff70dd25218
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
    log: change-requests/CR-2026-076/test-evidence/cmd-04.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/caller-contract.test.mjs, skills/shared/crctl/scripts/test/fault-harness.test.mjs, skills/shared/crctl/scripts/test/durable-tx.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-05.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/register-tx.test.mjs, skills/shared/crctl/scripts/test/owner-source-scan.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-06.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/merge-tx.test.mjs, skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs, skills/shared/crctl/scripts/test/workspace-resolver.test.mjs]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-07.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/workspace-freshness.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-08.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs, skills/shared/crctl/scripts/test/contract-scan.test.mjs, skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs, skills/shared/crctl/scripts/test/check-agents-contract.test.mjs, skills/shared/crctl/scripts/test/lint-prompts.test.mjs, skills/shared/crctl/scripts/test/skill-scope.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-09.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl-summary.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-10.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/test/suite-gate.mjs, --run]
    timeout-seconds: 3600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-11.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: tools
    cwd: skills/shared/engineering-docs/scripts
    executable: node
    args: [node_modules/vitest/vitest.mjs, run, src/__tests__/chain.test.ts]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-12.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: ai-first-platform-docs
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),cp=require('crypto');const NL=String.fromCharCode(10),CR=String.fromCharCode(13);const LD=p=>fs.readFileSync(p,'utf8').split(CR+NL).join(NL);const bad=[];const B=LD('change-requests/_backlog.yml').split(NL);let inCr=false,prdPath='';for(const l of B){if(l.indexOf('  - id: CR-2026-076')===0){inCr=true;}else if(inCr&&l.indexOf('  - id: ')===0){inCr=false;}if(inCr&&l.indexOf('prd-path:')>=0){prdPath=l.split('prd-path:')[1].split(String.fromCharCode(34)).join('').trim();}}const okFile=prdPath?fs.existsSync(prdPath):false;if(!okFile){bad.push('prd-path 未指向分支内实际文件: '+prdPath);}else{console.log('prd-path='+prdPath+' sha256='+cp.createHash('sha256').update(LD(prdPath)).digest('hex'));}const prd=okFile?LD(prdPath):'';const ids=[];for(let i=1;i<=9;i++){ids.push('FR-SUP-0'+i);}for(let i=1;i<=10;i++){ids.push('AC-SUP-'+(i<10?'0'+i:String(i)));}const cnt=[];for(const id of ids){const n=prd.split(id).length-1;cnt.push(id+'='+n);if(n<1){bad.push('PRD 未见编号: '+id);}}console.log('编号出现次数: '+cnt.join(' '));const ann='change-requests/CR-2026-076/review-annotations/requirement.yml';const at=fs.existsSync(ann)?LD(ann).split(NL):[];if(!at.some(l=>l.trim()==='verdict: pass')){bad.push('需求评审 verdict 非 pass: '+ann);}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-13 ok: prd-path 指向分支内实际文件；FR-SUP-01…09 与 AC-SUP-01…10 逐号存在；需求评审 verdict=pass（实质覆盖由独立需求评审判定，本命令不作正确性结论）');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-13.log
    source-revision: 098d81d99488ad5f966d40ac038e65d87f182856
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-14.log
    source-revision: a95941eef8d71dcfed62b2d330de1c2ef17a543a
  - repo: ai-first-platform-docs
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CR=String.fromCharCode(13);const LD=p=>fs.readFileSync(p,'utf8').split(CR+NL).join(NL);const RD=p=>fs.existsSync(p)?LD(p):'';const bad=[];const S=x=>x?String(x):'';const run=(c,a)=>{const r=cp.spawnSync(c,a,{encoding:'utf8'});return {code:r.status,out:S(r.stdout),err:S(r.stderr)};};const v=run('multica',['--version']);const vline=S(v.out.trim().split(NL)[0]);console.log('installed-entry: '+vline);if(v.code!==0){bad.push('multica --version 非零退出: '+v.err.trim());}const tok=S(vline.split(' ')[1]);const d=run('multica',['daemon','status','--output','json']);let cli='';try{cli=S(JSON.parse(d.out).cli_version);}catch(e){bad.push('daemon status 非 JSON: '+d.out.slice(0,200));}console.log('daemon-cli-version: '+cli);if(cli&&tok&&cli!==tok){bad.push('daemon 与已安装 CLI 版本不一致: '+cli+' vs '+tok);}const R='change-requests/CR-2026-076/test-evidence/';const rh=RD(R+'fr14-launch-receipt.md');const rb=RD(R+'fr14-run-behavior.md');if(!rh.trim()){bad.push('缺少启动回执原样证据: '+R+'fr14-launch-receipt.md');}else{console.log('launch-receipt sha256='+cr.createHash('sha256').update(rh).digest('hex'));if(tok&&rh.indexOf(tok)<0){bad.push('启动回执未载明现场入口版本: '+tok);}}if(!rb.trim()){bad.push('缺少 run 目标行为证据: '+R+'fr14-run-behavior.md');}else{console.log('run-behavior sha256='+cr.createHash('sha256').update(rb).digest('hex'));}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-15 ok: 已安装 CLI／daemon 版本一致且与启动回执一致、run 目标行为证据原样在位');"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-076/test-evidence/cmd-15.log
    source-revision: 098d81d99488ad5f966d40ac038e65d87f182856
---

# 测试报告 · CR-2026-076

<!-- crctl:analysis-below -->

> 机器区（marker 以上）由 `crctl test` 生成，本节点不改写；本节由 `write-test-report` 节点补充（`write-test-report` 第 3 次 attempt），全部事实为本次 run 现查。
> 本轮的输入是**人类裁定**（原文 = Issue AIFI-62 评论 `01a12960-0a7c-72ef-9d02-24d48280f35e`，裁定请求原文 = `01a12957-4600-770a-b97d-b2bc83f38f10`）：`cmd-03` 作为既有平台失败保留证据、移出本 CR 的阻断命令集，并按既有受控流程同步修订 `tasks/TASK-02.md` AC-04；**不将失败报告为通过、不新增豁免机制、不扩大 `repocache` 修复范围、不重置评审次数**。落地形态见 `plan.md` §5.5／§6.2 的 `cmd-03` 行（命令形态唯一事实源）与 `tasks/TASK-02.md` AC-04。

## 一、测试摘要（对应 TASK 验收条件）

| 项 | 值（原样） |
|---|---|
| 入口 | `node <tools CR worktree>/skills/shared/crctl/scripts/crctl.mjs test CR-2026-076 --plan .crctl/tmp/test-plan.json --workspace <KB CR worktree>`（显式 `--workspace` 与本 run 绑定根同根，工具层无 `WORKSPACE_CONTEXT_MISMATCH`） |
| 计划来源 | `plan.md` §6.2 证据命令表逐条**解析转录** 15 条（转录器硬失败：证据ID ≡ 1-based 下标 ≡ `cmd-NN`，`args` 必须为 JSON 字符串数组）；本轮 `cmd-03` 行按裁定改形，其余 14 行未变 |
| `command-digest` | `abf0f64ae5ede35876ad13b1a84e3585515816e25c78cdad6c6c718c83bebeb1`（与 attempt 2 的 `ded6a0f5…` 不同：命令集合中仅 `cmd-03` 一行改变） |
| 结果 | `status=pass`：15 条全部 `exit-code=0`；`blockers` 空 |
| 记账 | `traceability.yml#tests status=pass`、`generated-at: 2026-10-11T13:56:30+08:00`；`review-loop.yml#write-test-report current-attempt=3`（cycle 1，max 3，**未重置**）；`.crctl/audit.log` 同日 `13:56:30` 记 `kind=test status=pass attempt=3`、`digest=abf0f64a…` |
| 未启动／未覆盖命令 | 无：15 条全部 `started=true`、`timed-out=false`、`skipped=false` |
| 单条耗时 | 见各 `cmd-NN.log` 内耗时（最长 `cmd-11`：`duration_ms=911091`，约 15.2 分钟） |

**`cmd-03` 的处置形态（本轮唯一变化项）**

- **原命令形态**（`go test ./internal/daemon/repocache/ -count=1 -v`，attempt 1／2 的实跑命令）：本机（Windows）非零退出——默认临时根 55 项失败、短临时根 `C:\ctmp` 8 项、同环境改前基线 `a2046ce34` 逐名一致，`go list -deps` 命中 `internal/daemon` = 0，本 CR 在 multica 仓的 9 个变更文件不含该包 → 与本 CR 变更面无因果。
- **处置**：该命令不再进入本 CR 的 `cr-test-plan`，故其退出码不再推导报告 `status`；**失败原文不删不改**，保留为留证：`test-evidence/cmd-03-existing-failure-full-package.log`／`cmd-03-existing-failure-short-root.log`／`cmd-03-existing-failure-baseline.log`／`cmd-03-existing-failure-short-root-failures.log` 与 `cmd-03-analysis.md`（该文件已补「六、裁定与处置」）。**不判为通过。**
- **现形态**：只读符号核实观测（`node -e`，`repo=multica cwd=server`，`timeout=300`）。本轮现查输出：`sites GIT_CONFIG_GLOBAL = 0`；`sites GIT_CONFIG_COUNT / GIT_CONFIG_KEY_ / GIT_CONFIG_VALUE_` 全部落在 `cache.go`（37／42／43／52／53／54）；`sites multica-identity.config / config.worktree` 全部落在 `identity.go`（13／73／78／117）；`go-list-deps: status=0 pkgs=100 internal-daemon-hits=0`。观测面 = FR-02「第二处 Git 配置写入点」核实结论（① 不存在，见 `sdd.md` §4.2／`dep-36`），即 AC-04 第 3 条「给出核对符号与依据」的机械形态。
- **先验红再验绿**：注入一处合成的第二写入点（`identity.go` 尾部追加一行含 `GIT_CONFIG_GLOBAL` 的函数）后，同一命令 `exit=1` 并报 `repocache 生产文件出现 GIT_CONFIG_GLOBAL: identity.go:197`；移除注入后恢复 `exit=0`，注入前文件按 `git hash-object` 校验还原为原值（两仓 CR worktree `git status --porcelain` 均为空）。
- **机制口径**：未新增任何豁免参数（`crctl test` 仍只接受 `--plan`，无失败豁免开关），未改 `crctl`／pipeline／状态机；改变的是**命令集合本身**（原命令移出、槽位改由观测面等价的只读核实承担），故不存在「把失败改写为通过」的通道。

## 二、验证命令与结果解读（15/15 逐条）

| cmd | repo／cwd | exit | 本次现查关键输出（原样摘要） |
|---|---|---|---|
| cmd-01 | multica／server | 0 | `go test ./internal/daemon/ -run Test(绑定/投影/预检 11 组名称)`：顶层 `--- PASS` 19；`ok …/internal/daemon 1.718s` |
| cmd-02 | multica／server | 0 | 顶层 `--- PASS` 12；`ok …/internal/daemon 0.236s` |
| cmd-03 | multica／server | 0 | 只读符号核实观测（见 §一）：`GIT_CONFIG_GLOBAL=0`；`GIT_CONFIG_*` 仅 `cache.go`；checkout 私有配置仅 `identity.go`；`pkgs=100 internal-daemon-hits=0` |
| cmd-04 | tools／. | 0 | `tests 266 / pass 266 / fail 0 / skipped 0` |
| cmd-05 | tools／. | 0 | `tests 40 / pass 40 / fail 0 / skipped 0` |
| cmd-06 | tools／. | 0 | `tests 49 / pass 49 / fail 0`（日志另含 win32 平台限制声明：`平台不支持以权限位表达不可读：source-not-readable 分支未在本轮实际执行`） |
| cmd-07 | tools／. | 0 | `tests 54 / pass 54 / fail 0 / skipped 0` |
| cmd-08 | tools／. | 0 | `tests 38 / pass 38 / fail 0 / skipped 0` |
| cmd-09 | tools／. | 0 | `tests 116 / pass 116 / fail 0 / skipped 0` |
| cmd-10 | tools／. | 0 | `tests 8 / pass 8 / fail 0 / skipped 0` |
| cmd-11 | tools／. | 0 | `suite-gate: files_executed=31 cases_executed=756 skipped_file_level=0`／`failures=0`／`verdict=pass`／`registry_sha256=9caf3e248e5a6a361335c83eead4b710484880a4cefc0402b4fcec277674850b`／`exceptions_count=0` |
| cmd-12 | tools／skills/shared/engineering-docs/scripts | 0 | vitest `Test Files 1 passed (1)`／`Tests 6 passed (6)` |
| cmd-13 | ai-first-platform-docs／. | 0 | `cmd-13 ok`；`prd-path=change-requests/CR-2026-076/prd.md`（`sha256=521746b36e53aab0bfc6419e8ee1c4b83292d16a342b00618a064948dbd574c6`）；`FR-SUP-01…09` 与 `AC-SUP-01…10` 逐号存在；需求评审 `verdict=pass` |
| cmd-14 | tools／. | 0 | `tests 3 / pass 3 / fail 0`；13 项 SDD §8 变更 Skill 全部 `equal=true`（`equal=false` = 0），三份 CR Agent instructions 只打印线上 `sha256Remote` |
| cmd-15 | ai-first-platform-docs／. | 0 | `cmd-15 ok`；`installed-entry: multica v0.6.1-429-ge5f0fc089` 与 `daemon-cli-version: v0.6.1-429-ge5f0fc089` 一致；`launch-receipt sha256=12baff1cd3fc2b8896507ee5028023b7e9bf93584e18ea8166df905ae22cc7c4`、`run-behavior sha256=fc10485e63272ec9c432c836c8a7ed8808b8731a1e0f65047613a857f8b466be`，两者非空 |

要点：

1. 本轮 `status=pass` 且无 `exit-code` 非 0 项；与 attempt 2 的差别**只有 `cmd-03` 的形态与处置**（§一），不是新增失败，也不是把既有失败记为通过——原形态的 `exit=1` 与 55／8 项失败原文仍在留证文件内。
2. `cmd-11`（tools 全量门）本轮 `files_executed=31`／`cases_executed=756`／`failures=0`／`verdict=pass`，与 attempt 2 同值（新增用例数与 `gate-registry.json#manifest.cases` 登记一致）。
3. `cmd-12 + cmd-14 + cmd-15` 三者 `exit=0`：`AC-24`（关键）覆盖成立（attempt 1 时三者中 `cmd-14`／`cmd-15` 为 `exit 1`，成因是 TASK-17 未开工，已在 attempt 2 闭合）。
4. attempt 2 §二 要点 4 的更正仍然成立并本轮同值复核：`launch-receipt sha256` = `12baff1c…`（非 `92af4482…`）；证据两轮一致，不影响 `cmd-15` 判定。
5. 本轮现查 `cmd-13.log`／`cmd-15.log` 的 mtime 未前移（内容与 attempt 2 逐字节相同）；其余 13 份 `cmd-NN.log` 已按本轮实跑更新。

## 三、TASK 验收覆盖矩阵（证据ID ≡ `cmd-NN`）

矩阵行取自 `plan.md` 覆盖矩阵「验收证据」列（17 张 TASK 全覆盖），`exit-code` 取自本报告机器区。

| TASK | 验收证据 | exit-code | 覆盖判定 |
|---|---|---|---|
| TASK-01 | cmd-01 + cmd-04 + cmd-06 | 0 / 0 / 0 | 覆盖 |
| TASK-02 | cmd-02 + cmd-03 | 0 / 0 | 覆盖：`cmd-02` = 叠加式身份行为面；`cmd-03` = 该包写入点只读符号核实（原形态失败另作留证，§一） |
| TASK-03 | cmd-04 + cmd-09 | 0 / 0 | 覆盖 |
| TASK-04 | cmd-04 + cmd-05 | 0 / 0 | 覆盖 |
| TASK-05 | cmd-04 | 0 | 覆盖 |
| TASK-06 | cmd-04 + cmd-07 | 0 / 0 | 覆盖 |
| TASK-07 | cmd-04 + cmd-09 | 0 / 0 | 覆盖 |
| TASK-08 | cmd-04 | 0 | 覆盖 |
| TASK-09 | cmd-05 + cmd-07 | 0 / 0 | 覆盖 |
| TASK-10 | cmd-07 + cmd-08 | 0 / 0 | 覆盖 |
| TASK-11 | cmd-10 + cmd-11 | 0 / 0 | 覆盖 |
| TASK-12 | cmd-12 | 0 | 覆盖 |
| TASK-13 | cmd-04 + cmd-06 + cmd-09 | 0 / 0 / 0 | 覆盖 |
| TASK-14 | cmd-04 + cmd-06 | 0 / 0 | 覆盖 |
| TASK-15 | cmd-04 + cmd-06 + cmd-09 | 0 / 0 / 0 | 覆盖 |
| TASK-16 | cmd-13 | 0 | 覆盖 |
| TASK-17 | cmd-12 + cmd-14 + cmd-15 | 0 / 0 / 0 | 覆盖 |

关键 AC：`AC-24`（关键）的证据面 = `cmd-12 + cmd-14 + cmd-15`，本轮三者均 `exit 0`；`tasks/_index.yml` 现查 17/17 `status: done`（本轮未改动该索引）。

## 四、新增/修改测试文件

- **本轮（attempt 3）**：无新增、无修改测试文件，实现面零改动 —— `multica`／`tools` 两仓 CR worktree 本轮现查 `git status --porcelain` 均为空；本轮只做受控文书同步（`plan.md` §5.5／§6.2、`tasks/TASK-02.md` AC-04、`sdd.md` r7）与证据重跑。
- tools 仓（相对 merge-base，CR 累计）：新增 3 个 —— `skills/shared/crctl/scripts/test/owner-source-scan.test.mjs`（TASK-15）、`publish-effectiveness.test.mjs`（TASK-17）、`suite-gate-count.test.mjs`；修改 12 个（`caller-contract`／`checkpoint-tx`／`contract-scan`／`crctl-summary`／`crctl`／`fault-harness`／`merge-tx`／`pipeline-structure`／`register-tx`／`version-set`／`workspace-freshness`／`workspace-resolver`）。两处新建测试与 `gate-registry.json` 的 `manifest.files`／`manifest.cases` 同批登记（登记 owner 见 `plan.md` §5.5）。
- multica 仓（相对 merge-base，CR 累计）：新增 `server/internal/handler/claim_cr_association_test.go`、修改 `server/internal/daemon/pipeline_task_test.go`（后者由 `cmd-01`／`cmd-02` 实跑）。
- 证据绑定：本报告机器区 `commands[].log` 指向 `test-evidence/cmd-NN.log`；`cmd-03.log` 现为**现形态命令**的实跑日志，原形态的四份留证日志已更名（§一）。

## 五、未覆盖风险（含「不适用」说明，不空白通过）

1. **`cmd-03` 原形态的既有失败未被消除**（存量平台失败）：本 CR 不修复、不扩大 `repocache` 范围，也**不判其为通过**；原文与基线对照见 `test-evidence/cmd-03-existing-failure-*.log` 与 `cmd-03-analysis.md`。现形态 `cmd-03` 只断言符号级核实结论与依赖隔离，**不声称**该包任何测试通过。
2. `status=pass` 与 `blockers` 空**已达成**（`write-test-report` 的 `passCondition` 入口条件满足）；attempt 2 记录的「口径外项导致 `status=block`」冲突已由人类裁定消解（§一），本轮不再有该冲突。
3. **`server/internal/handler/` 的新增投影用例不在证据面内**（声明型不适用）：`tasks/TASK-01.md:31` 已声明「DB 可达时执行；本机 DB 不可达时该包 `TestMain` 整包 skip，不计入本 TASK 证据面」，`plan.md` §6.2 亦无覆盖该包的命令。本报告据实记录、不声称其已通过。
4. **`cmd-13` 不作正确性结论**：只做交接完整性机械核对（`prd-path` 指向分支内实际文件、编号逐号存在、需求评审 `verdict=pass`），实质覆盖由独立需求评审判定（`review-annotations/requirement.yml`）。
5. **`cmd-14` 只覆盖 SDD §8 声明变更的 Skill 集合**（13 项），不声称覆盖其余 Skill；三份 CR Agent instructions 为记录型观测（只打印线上 `sha256`，无相等断言）。
6. **`cmd-15` 不覆盖被启动 run 的业务结果正确性**：只断言已安装入口版本一致与「启动回执／行为证据原样在位」，行为事实由 `test-evidence/fr14-run-behavior.md` 原文承载，由人工与评审消费。
7. **命令级 `skipped` 全为 `false`**：本轮无「零用例假绿」形态；`cmd-11` 的 `skipped_file_level=0`。
8. **两条 `LOCAL_TRUST_DOC_DRIFT_WARN`**（`PLAN`／`TASK` 正文漂移与 `approval.yml#development-start` 证据摘要漂移）按 `write-test-report` Step 1.5 口径（CR-2026-076 FR-05／`SDD §4.5`）只提示、不撤销批准、不强制重审，**不得据此判 `block`**；本轮两值再次前移，成因即本轮受控同步（§六），处置按人类裁定保留为记录型漂移、**不重置评审次数**，由 `review-code` 消费。

## 六、两条 `LOCAL_TRUST_DOC_DRIFT_WARN` 的实据（本轮现查复核）

| 项 | 本轮现查值 |
|---|---|
| warning-1（dev-plan 正文漂移） | `crctl status` 本轮终值原样：annotation 记录 `0d865cb612add41f…`，当前重算 `c87c9912bdd4f779…`（attempt 2 时为 `53cd27f0…`，本轮受控同步后两次前移）；annotation 现读 `review-annotations/dev-plan.yml:23 subject-sha256: 0d865cb612add41f5f50dce7db0493ba285328f6a7cff4b50a38e926d25952a6`，`verdict: pass`、`reviewed-at: 2026-10-10T16:59:46+08:00`（未变） |
| warning-2（approval 证据漂移） | `crctl status` 本轮终值原样：`514d530cb2ec31a8…`（记录）vs `9fb45ae3096ecd1a…`（重算；attempt 2 时为 `d5824a5420b0c10a…`）；`approval.yml:16-18` 现读 `approval#development-start`、`approved-at: 2026-10-10T17:10:10+08:00`、`via: crctl-approve`、`evidence-digest: 514d530cb2ec31a882b7d53a197a921d7f67241484278be1d4fa8546a495d669`（未变） |
| 本轮前移的成因 | 本轮受控同步本身：`plan.md` §2 依赖图 TASK-02 行／§5.5／§6.2（`cmd-03` 行）、`tasks/TASK-02.md` AC-04、`sdd.md` 修订 r7 —— 三份文件均属 warning-1／warning-2 的摘要面 |
| 处置 | 保留为**记录型漂移**，由 `review-code` 消费；本轮不重签、不改写 annotation／approval、不以 warning 判 `block`、不重置任何评审次数（人类裁定原文见本节开头引用） |

（完整归因推导见 `01a128ee-1e94-7364-8a7b-c3e4d7ea9435` §三.1–§三.4；本节只登记复核后的机器值。）

## 七、下一步建议

- 本节点（`write-test-report` 第 3 次 attempt）合同已执行完毕：报告 `status=pass`、`blockers` 空，机器区与记账由 `crctl test` 原子发布，本节分析已按本轮事实重写。
- `crctl next CR-2026-076` 本轮现查原样：

  ```text
  { "cr": "CR-2026-076", "status": "developing", "next": "push-progress → review-code",
    "humanApproval": false, "why": "测试证据 pass，推送 checkpoint 后进入代码评审" }
  ```

- 本轮同批产物：`plan.md` §2 依赖图 TASK-02 行／§5.5／§6.2（`cmd-03` 行）、`tasks/TASK-02.md` AC-04（含修订说明）、`sdd.md` 修订 r7、`test-evidence/cmd-03-analysis.md`（补「六、裁定与处置」）与四份留证日志更名；实现面 0 改动（两仓 `git status --porcelain` 空）。
- 未触发：`review-code` 与后续节点未由本节点启动；未请求人工审批；未改动 `tasks/_index.yml`（17/17 `done`，本轮未变）；未 `review-loop reset`（`write-test-report` 现为 3/3，是消耗而非重置）。

## 八、B-01…B-09 回修补跑记录（本节点第 4 次重跑；机器区以上为准）

> 触发：`review-code` attempt 1/3 **BLOCK**（9 条 blocker，`repair-target=implement-code`，canonical 原文见 `review-annotations/code.yml`）。本次按 `replayNodes` 在同一 plan 上重跑 `crctl test`——**命令集合与 `command-digest` 逐字节未变**（`abf0f64ae5ede35876ad13b1a84e3585515816e25c78cdad6c6c718c83bebeb1`），故 §一～§三 的命令形态与处置结论继续有效，以下只登记本轮**计数与改动面**的现查值，并声明其取代 §一／§二 中对应行的旧计数。

### 8.1 机器事实（本轮现查，与机器区同源）

- 报告：`status=pass`，`generated-at: 2026-10-11T19:43:24+08:00`，15/15 命令 `exit-code=0`、`started=true`、`timed-out=false`、`skipped=false`。
- 逐命令用例数（取代 §二 表内旧值）：`cmd-01` 顶层 `--- PASS` 20；`cmd-02` 13；`cmd-03` 现形态 `exit=0`（两处 `ok:` 观测）；`cmd-04` 272/272；`cmd-05` 40/40；`cmd-06` 49/49；`cmd-07` 55/55；`cmd-08` 40/40；`cmd-09` 116/116；`cmd-10` 8/8；`cmd-11` `files_executed=31`／`cases_executed=765`／`failures=0`／`verdict=pass`／`registry_sha256=9caf3e24…`；`cmd-12` vitest 6/6（1 file）；`cmd-13`／`cmd-15` 各 1 条 `ok`；`cmd-14` 3/3（13 项 Skill `equal=true`）。
- 记账：`traceability.yml#tests status=pass`、`command-digest=abf0f64a…`（未变）；`review-loop.yml#write-test-report` 本轮**未重置**（`current-attempt=3`、`cycle=1`、`max-attempts=3`，本节点是被消费而非重置）。

### 8.2 本轮改动面（三仓 CR worktree 现查）

- `tools`：`skills/shared/crctl/scripts/crctl.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`；测试 `test/crctl.test.mjs`、`merge-tx.test.mjs`、`merge-fixture.mjs`、`workspace-freshness.test.mjs`。
- `multica`：`server/internal/daemon/daemon.go`（触发事实随绑定注入）、`pipeline_task.go`（两全局配置叠加）、`cr_workspace_binding_test.go`、`pipeline_task_test.go`、`CUSTOM.md`（#129／#130 + 计数基线行）。
- 未改任何 SDD §8 声明的 `SKILL.md`（13 项发布面逐字不变 → `cmd-14` 继续 `equal=true`）；契约文本的细化说明属 `plan.md` §5.4 第 1 项由人类执行的平台导入步，不在本轮实现面内。

### 8.3 新增用例与 blocker 的对应（均落在本轮 `cmd-04`／`cmd-05`／`cmd-07`／`cmd-08`／`cmd-11` 实跑内）

| blocker | 新增/改写的用例（文件 → 用例名关键片段） | 断言要点（机器可判） |
|---|---|---|
| B-01 | `crctl.test.mjs` → `TASK-08 AC-15（B-01 回修）` | 自由文本／Agent 触发／非责任角色／actor 缺失四类负例均 `NOT_TTY` 且零写入零提交零授权审计；平台注入事实齐备时 cycle 1→2 |
| B-02 | `crctl.test.mjs` → `TASK-08 AC-16（B-02 回修）` | `ledger-after-commit` 崩溃后同指令重投返回幂等成功（`recovered=true`）、不新增 cycle／提交；该 cycle 再耗尽后同旧指令 `TX_INPUT_CONFLICT`；提交前回滚后同指令仍可正常开启一个 cycle |
| B-03 | `workspace-freshness.test.mjs` → 真实 `testCr` 产物 + 矛盾源/无效报告 | 真实 `crctl test` 生成的 `test-report.md` 含逐命令 `source-revision`（两仓），G06 判 `tree-equal`／`route=continue`；同仓矛盾源 `TX_INPUT_CONFLICT`、无机器区报告 `TEST_REPORT_INVALID` |
| B-04 | `pipeline_task_test.go` → `TestConfigureTaskGitEnvironment` 三个子测试 | 两文件按 Git 顺序 include 且身份跨文件可解析；XDG 无身份 + `~/.gitconfig` 有身份仍成功；同键时 `~/.gitconfig` 胜出 |
| B-05 | `crctl.test.mjs` → `B-05` | 责任角色不匹配、段内残留 `signature`／`key-id`／`grant-approved-at` 均维持硬阻断（`status` 面 blocker 仍在） |
| B-06 | `crctl.test.mjs` → `B-06`、`merge-tx.test.mjs` → `B-06` | 同一 `verifyReleaseSubjects` 缝：本地允许正文本漂移只给 `LOCAL_TRUST_DOC_DRIFT_WARN`（approve 面 warnings、merge 面继续合入）；`--grant`／非责任角色批准仍 `RELEASE_SUBJECT_DRIFT`／`APPROVED_ARTIFACT_DRIFT` 零写入 |
| B-07 | `crctl.test.mjs` → `B-07` | code 评审提交后替换受控 artifact → 恢复期 `TX_RECOVERY_CONFLICT`，annotation 与 HEAD 零改写 |
| B-08 | `crctl.test.mjs` → `B-08` | 成功后原命令重投（payload 缺失）与同 payload 补回重投均 `idempotent=true`、`changed=false`、单次提交、attempts 不变、review 事件仍 1 条 |
| B-09 | `crctl.test.mjs` → `B-09` | 对象未变 → `SUBJECT_UNCHANGED`/implement-code；已变且已收尾 → `SUBJECT_CHANGED_REVIEW`/review-code；dirty → 回修；`review-code` 耗尽 → `humanApproval=true`／`LOOP_EXHAUSTED`；`test-report=block` 仍回 implement-code |

### 8.4 未触发项

未请求人工审批、未 `review-loop reset`、未改任何审批／状态／发布事实；`cmd-03` 的存量平台失败仍按既有裁定留证、不判为通过（§五.1）。
