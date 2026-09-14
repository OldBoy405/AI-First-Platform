---
cr: CR-2026-066
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-14T17:20:28+08:00"
command-digest: 9b2a728bac3a4594e43cbee3c7f7fb84ab582eb5d0beee5297e32a418df960e6
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/test/suite-gate.mjs, --run]
    timeout-seconds: 1080
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", skills/shared/crctl/scripts/test/pipeline-structure.test.mjs, skills/shared/crctl/scripts/test/contract-scan.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-name-pattern, "CR-2026-042 静态合同", --test-name-pattern, "checkpoint T05 contract", --test-name-pattern, "CR-2026-044 AC-13", --test-name-pattern, "CR-2026-044 AC-14", --test-name-pattern, "CR-2026-050 AC-12", skills/shared/crctl/scripts/test/crctl.test.mjs, skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-name-pattern, CR-2026-066, skills/shared/crctl/scripts/test/archive-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const cp=require('child_process'),fs=require('fs'),path=require('path'); const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL; const read=p=>fs.readFileSync(path.join(R,p),'utf8').split(CR).join(NL); const bad=[]; const run=(label,args)=>{const r=cp.spawnSync(process.execPath,args,{cwd:R,encoding:'utf8',shell:false});const s=String(r.stdout==null?'':r.stdout),e=String(r.stderr==null?'':r.stderr);console.log('['+label+'] exit='+r.status);if(r.status!==0){bad.push(label+' exit='+r.status);console.log(s.slice(-500));console.log(e.slice(-500));}}; run('lint-prompts',['skills/shared/crctl/scripts/lint-prompts.mjs','--mode','enforce']); run('skill-matrix',['skills/shared/crctl/scripts/check-skill-matrix.mjs']); run('agents-contract',['skills/shared/crctl/scripts/check-agents-contract.mjs']); const wbt=fs.readdirSync(path.join(R,'skills/writeback/scripts/test')).filter(f=>f.endsWith('.test.mjs')).map(f=>'skills/writeback/scripts/test/'+f); run('writeback-tests',['--test','--test-reporter=dot'].concat(wbt)); const active=new Set();let cur=null; for(const l of read('skills/_index.yml').split(NL)){const t=l.trim();if(t.indexOf('- id: ')===0){cur=t.slice(6).trim();continue;}if(cur!==null&&t==='status: active'){active.add(cur);}} const pf=fs.readdirSync(path.join(R,'pipeline-templates')).filter(f=>f.endsWith('.pipeline.json')); for(const f of pf){const d=JSON.parse(read('pipeline-templates/'+f));const dn=d.nodes===undefined?[]:d.nodes;const ids=dn.map(n=>n.id);if(new Set(ids).size!==ids.length){bad.push(f+' 重复 node id');}for(const n of dn){if(n.kind==='skill'&&!n.ref){bad.push(f+' skill 节点缺 ref');}if(n.kind==='skill'&&n.ref&&!active.has(n.ref)){bad.push(f+' inactive ref '+n.ref);}const rl=n.reviewLoop;if(rl){if(rl.repairNodeId&&ids.indexOf(rl.repairNodeId)<0){bad.push(f+' 悬空 repairNodeId');}const rp=rl.replayNodes===undefined?[]:rl.replayNodes;for(const x of rp){if(ids.indexOf(x.nodeId)<0){bad.push(f+' 悬空 replayNode '+x.nodeId);}}}}} console.log('pipeline structure checked = '+pf.length+' active skills = '+active.size); const base='5d5a4ada96b882eb2c640e34bb72857a7073b668'; const WL=['pipeline-templates/requirement-authoring.pipeline.json','pipeline-templates/architecture-design.pipeline.json','pipeline-templates/code-implementation.pipeline.json','pipeline-templates/_index.yml','skills/requirement/review-requirement/SKILL.md','skills/develop/review-tech-design/SKILL.md','skills/develop/review-dev-plan/SKILL.md','skills/develop/review-code/SKILL.md','skills/sync/push-progress/SKILL.md','agent-skill-matrix.yml','AGENT-SKILL-MATRIX.md','agents/dev-agent.md','agents/quality-reviewer-agent.md','agents/delivery-agent.md','skills/shared/crctl/scripts/lib/workspace-transactions.mjs','skills/cr/cr-archive/SKILL.md','skills/writeback/merge-feature-branch/SKILL.md','README.md','openwiki/pipelines/overview.md','dir-graph.yaml','skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','skills/shared/crctl/scripts/test/archive-tx.test.mjs','skills/shared/crctl/scripts/test/contract-scan.test.mjs','skills/shared/crctl/scripts/test/crctl.test.mjs','skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs']; const ZERO=['skills/shared/crctl/scripts/crctl.mjs','skills/shared/controlled-shell/rules.json','skills/shared/crctl/gates.json','skills/shared/crctl/scripts/test/gate-registry.json','pipeline-templates/emit-registry.mjs','skills/shared/crctl/scripts/lib/yaml-subset.mjs','skills/shared/crctl/scripts/lib/durable-tx.mjs','ARCHITECTURE.md','AGENTS.md']; const CRCTL=path.join(R,'skills/shared/crctl/scripts/crctl.mjs'); const r0=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only',base,'--cwd',R],{encoding:'utf8'}); if(r0.status!==0){bad.push('crctl git diff 失败');}else{const parts=String(r0.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('tools diff paths = '+changed.length);changed.forEach(f=>console.log('  '+f));for(const f of changed){if(WL.indexOf(f)<0){bad.push('越界路径 '+f);}}for(const f of WL){if(changed.indexOf(f)<0){bad.push('缺少应改文件 '+f);}}for(const f of ZERO){if(changed.indexOf(f)>=0){bad.push('zero_diff 面被改动 '+f);}}} const hunk=(p,tokens)=>{const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--unified=0',base,'--',p,'--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('diff 失败 '+p);return;}const lines=String(r.stdout).split(NL).filter(l=>{const c=l.charAt(0);if(c==='+'){return l.indexOf('+++')!==0;}if(c==='-'){return l.indexOf('---')!==0;}return false;});for(const l of lines){for(const t of tokens){if(l.indexOf(t)>=0){bad.push(p+' 改动命中禁改 token '+t);}}}}; hunk('dir-graph.yaml',['state_machine:','wildcards:','transitions:','namedStates']); hunk('skills/shared/crctl/scripts/lib/workspace-transactions.mjs',['function checkpointCr','function mergeCr','function applyWriteback','function registerCr','function reconcileLocalTrunks','function buildRecovery']); const at=read('skills/shared/crctl/scripts/test/archive-tx.test.mjs'); const ac8=at.split('CR-2026-066 AC-8').length-1; const tn=at.split('test(').length-1; console.log('archive-tx AC-8 tokens = '+ac8+' test( count = '+tn); if(ac8<6){bad.push('archive-tx 未登记 6 条 AC-8 用例名（CR-2026-066 AC-8，实得 '+ac8+'）');} if(tn<30){bad.push('archive-tx test( 调用数 = '+tn+'（基线 24 + 新增 6）');} const KP=[['skills/shared/crctl/scripts/test/crctl.test.mjs','CR-2026-042 静态合同'],['skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs','checkpoint T05 contract'],['skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','CR-2026-044 AC-13'],['skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','CR-2026-044 AC-14'],['skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','CR-2026-050 AC-12']]; const SQ=String.fromCharCode(39); for(const kv of KP){const kn=read(kv[0]).split('test('+SQ+kv[1]).length-1; console.log('cmd-03 guard '+kv[0]+' :: '+kv[1]+' = '+kn); if(kn<1){bad.push('cmd-03 定点用例名缺失 ['+kv[1]+']（'+kv[0]+' 内声明形态 test( + token 实得 '+kn+'）');}} const pp=read('skills/sync/push-progress/SKILL.md'); if(pp.indexOf('评审 PASS')<0){bad.push('push-progress SKILL 缺 [评审 PASS] 口径');} if(pp.indexOf('搭车')<0){bad.push('push-progress SKILL 缺 [搭车] 口径');} if(pp.indexOf('审批后的阶段终点 checkpoint 为强制完成条件')>=0){bad.push('push-progress SKILL 保留旧句');} const rd=read('README.md'); if(rd.indexOf('评审 PASS')<0){bad.push('README 缺 [评审 PASS] 口径');} if(rd.indexOf('阶段终点 checkpoint 是 Pipeline 完成条件')>=0){bad.push('README 保留旧句');} const ow=read('openwiki/pipelines/overview.md'); if(ow.indexOf('review PASS')<0){bad.push('openwiki 缺 [review PASS] 口径');} for(const t of ['mandatory approval checkpoint','mandatory checkpoint','checkpoints are mandatory','checkpoint (mandatory)','D8[','D12[','checkpoint →']){if(ow.indexOf(t)>=0){bad.push('openwiki 保留旧词法 '+t);}} const dg=read('dir-graph.yaml'); if(dg.indexOf('修复、证据、checkpoint 与当前评审节点')>=0){bad.push('dir-graph contract 第 5 条保留旧词法');} if(dg.indexOf('基线重核')<0){bad.push('dir-graph contract 第 5 条未改准');} if(bad.length>0){console.log('tools-close-audit failures = '+bad.length);bad.forEach(x=>console.log('FAIL '+x));process.exit(1);} console.log('tools-close-audit failures = 0');"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-05.log
  - repo: multica
    cwd: .
    executable: node
    args: [-e, "const cp=require('child_process'),fs=require('fs'),path=require('path'); const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL; const read=p=>fs.readFileSync(path.join(R,p),'utf8').split(CR).join(NL); const bad=[],D='cr-prompts-revised/',F=['quality-reviewer-agent.md','dev-agent.md','delivery-agent.md','cr-coordinator-agent.md']; const full={};for(const n of F){full[n]=read(D+n);} const qa=full['quality-reviewer-agent.md']; const b0=qa.indexOf('## 受限 crctl 权限'),e0=qa.indexOf('## ',b0+3); if(b0<0){bad.push('quality-reviewer-agent 缺 [受限 crctl 权限] 节');} const blk=b0<0?'':qa.slice(b0,e0<0?qa.length:e0); if(blk.indexOf('workspace inspect')<0){bad.push('受限 crctl 权限块未列入只读 workspace inspect');} if(blk.indexOf('checkpoint')<0){bad.push('受限 crctl 权限块禁止面未保留 checkpoint');} if(qa.indexOf('本 Agent 不负责 push/checkpoint')>=0){bad.push('quality-reviewer-agent 保留旧句 [本 Agent 不负责 push/checkpoint]');} if(full['dev-agent.md'].indexOf('统一 checkpoint')>=0){bad.push('dev-agent 保留 [统一 checkpoint] 旧前提句');} if(full['dev-agent.md'].indexOf('checkpoint 未完成时')>=0){bad.push('dev-agent 保留 [checkpoint 未完成时] 旧前提句');} const da=full['delivery-agent.md']; if(da.indexOf('recovery')<0){bad.push('delivery-agent 未登记结构化 recovery 例外');} if(da.indexOf('同 run')<0){bad.push('delivery-agent 缺 [同 run] 搭车口径');}if(da.indexOf('localTrunkSync')<0){bad.push('delivery-agent 汇报面缺 [localTrunkSync]');} for(const n of F){const t=full[n];if(t.indexOf('单独开委派')<0){bad.push(D+n+' 缺搭车硬规则 [单独开委派]');}if(t.indexOf('已部署')>=0){bad.push(D+n+' 出现部署声称');}} const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-066/skills/shared/crctl/scripts/crctl.mjs'; const r0=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','43848770bff13465de8ed9a0e28ecc7371716514','--cwd',R],{encoding:'utf8'}); if(r0.status!==0){bad.push('crctl git diff 失败');}else{const parts=String(r0.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('multica diff paths = '+changed.length);changed.forEach(f=>console.log('  '+f));for(const f of changed){if(f.indexOf(D)!==0){bad.push('multica 越界路径 '+f);continue;}if(F.indexOf(f.slice(D.length))<0){bad.push('multica 越界路径 '+f);}}for(const n of F){if(changed.indexOf(D+n)<0){bad.push('multica 缺少应改文件 '+D+n);}}} if(bad.length>0){console.log('multica-audit failures = '+bad.length);bad.forEach(x=>console.log('FAIL '+x));process.exit(1);} console.log('multica-audit failures = 0');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-06.log
  - repo: ai-first-platform-docs
    cwd: .
    executable: node
    args: [-e, "const cp=require('child_process'),fs=require('fs'),path=require('path'); const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL; const read=p=>fs.readFileSync(path.join(R,p),'utf8').split(CR).join(NL); const bad=[],CRD='change-requests/CR-2026-066/'; const plan=read(CRD+'plan.md').split(NL).filter(l=>l.indexOf('const cp=require(')<0).join(NL); const pl=plan.split(NL); const i0=pl.findIndex(l=>l.indexOf('## 10. ')===0); let i1=pl.length; if(i0<0){bad.push('plan.md 缺 [## 10. 交付说明必填块] 节');}else{for(let i=i0+1;i<pl.length;i++){if(pl[i].indexOf('## ')===0){i1=i;break;}}} const L10=i0<0?0:i1-i0; console.log('plan section10 lines = '+L10); if(L10<10){bad.push('plan.md 交付说明必填块节行数 = '+L10+'（< 10，疑似空节）');} const blk=i0<0?'':pl.slice(i0,i1).join(NL); for(const t of ['AC-6 延期验证点','载体','时点','观察项 ①','观察项 ②','观察项 ③','观察项 ④','责任 agent','关闭触发','AIFIRST_ARCHITECTURE_RUNNER','未重生成','D-6','cr-prompts-revised/agent-skill-matrix.yml','部署窗口','受限 crctl 权限','workspace inspect']){if(blk.indexOf(t)<0){bad.push('plan.md 交付说明必填块（section10）缺 token '+t);}} if(plan.indexOf('已重生成')>=0){bad.push('plan.md 不得声称已重生成（本 CR 走 [未重生成 + Runner 保持禁用] 分支）');} if(plan.indexOf('平台已部署')>=0){bad.push('plan.md 出现平台部署声称');} const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-066/skills/shared/crctl/scripts/crctl.mjs'; const r0=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','9a64fc4fac97e328a2dee0bff1711cc4f2a4c367','--cwd',R],{encoding:'utf8'}); if(r0.status!==0){bad.push('crctl git diff 失败');}else{const parts=String(r0.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('KB diff paths = '+changed.length);changed.forEach(f=>console.log('  '+f));for(const f of changed){if(f.indexOf(CRD)!==0&&f!=='change-requests/_backlog.yml'){bad.push('KB 越界路径 '+f);}}} if(bad.length>0){console.log('kb-audit failures = '+bad.length);bad.forEach(x=>console.log('FAIL '+x));process.exit(1);} console.log('kb-audit failures = 0');"]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-066/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-066

<!-- crctl:analysis-below -->
_以下为模型撰写段（`crctl` 机器区在标记之前，未改写）。_

## 1. 测试摘要（对应 TASK 验收条件）

| TASK | 验收条件 | 证据 | 结果 |
|---|---|---|---|
| CR-2026-066-TASK-01 | 三份 JSON 节点数 5/4/12、`push-progress` 计数 0、`_index.yml` ≡ JSON、被删 7 个完整 id 零出现；四个既有测试文件按新事实同步 | cmd-02 / cmd-03 / cmd-05（含 5 项用例名守卫、`archive-tx AC-8 tokens = 6`）/ cmd-01 | pass |
| CR-2026-066-TASK-02 | 四个 review SKILL 均含 clean 前置 + PASS 发布 + 对账 + BLOCK 不发布；权限面四处载体（tools 三处 + multica 副本）与 SKILL 前置同一条断言 | cmd-02（新断言 A/B/C/D）/ cmd-06 / cmd-05（lint-prompts + skill-matrix + agents-contract） | pass |
| CR-2026-066-TASK-03 | `archiveCr` 三个成功返回点均带 `localTrunkSync`；4 状态 × 6 reason 分类；dirty/wrong-branch ⇒ skipped 且本地逐字节未变；argv 级命令面恰 7 项 | cmd-04（6/6 pass）/ cmd-05（AC-8 守卫）/ cmd-01 | pass |
| CR-2026-066-TASK-04 | FR-9 四处同口径（旧词法零命中）；FR-6/FR-7 搭车硬规则落七份 Prompt；FR-7 静态断言；交付登记块 | cmd-05 / cmd-06 / cmd-07 / cmd-02 | pass |

## 2. 验证命令与结果解读

| 证据ID | 实测结果 |
|---|---|
| cmd-01 | `verdict=pass` / `exit_code=0` / `files_executed=21` / **`cases_executed=596`**（基线 588 + 6 条 AC-8 用例 + 1 条 AC-3/AC-4 断言用例）/ `failures=0` / `skipped_file_level=0` / `converged=true` / `exceptions_count=0` / `duration_ms=906098` |
| cmd-02 | exit 0（`pipeline-structure` 36 用例 + `contract-scan`：含 TASK-01 的 replayNodes 4 项快照与 TASK-02 的 A/B/C/D 断言） |
| cmd-03 | exit 0（10 个点号）；**存在性不由本命令承担**：5 个既有用例名 token 由 cmd-05 守卫（g）逐个判定（`CR-2026-042 静态合同 = 5`、`checkpoint T05 contract = 1`、`CR-2026-044 AC-13 = 2`、`CR-2026-044 AC-14 = 1`、`CR-2026-050 AC-12 = 1`） |
| cmd-04 | exit 0（6 个点号 = 6 条命中的 AC-8 用例通过，仅作执行面辅助计数；名字级证据由 cmd-05 守卫（f）承载：`CR-2026-066 AC-8` token = 6 ∧ `test(` 计数 = 38） |
| cmd-05 | exit 0（`tools-close-audit failures = 0`）：CI 静态五步全绿、`pipeline structure checked = 8`、**`tools diff paths = 25`** 与交付面白名单双向相等、`zero_diff` 文件零改动、hunk 级禁改 token 零命中、FR-9 四处口径正/负 token 全过、AC-8 与用例名守卫全绿 |
| cmd-06 | exit 0（`multica-audit failures = 0`）：`## 受限 crctl 权限` 块含只读 `workspace inspect` ∧ 禁止面仍含 `checkpoint`、三句旧前提零命中、四副本均含搭车硬规则、delivery 含 `recovery`/`同 run`/`localTrunkSync`、`multica diff paths = 4` 且无部署声称 |
| cmd-07 | exit 0（`kb-audit failures = 0`）：`plan section10 lines = 35`、16 个正向 token 齐备、负向判据零命中、`KB diff paths` 全在 `change-requests/CR-2026-066/**` ∪ `change-requests/_backlog.yml` |

**耗时与预算（如实登记）**：七条命令合计 ≈ 988 s < `write-test-report` 节点预算 1200 s（余量 ≈ 212 s）；cmd-01 自身 906 s < 其 `timeoutSeconds 1080`。与 plan §5.4 的 786 s 基线相比偏高——同一批 21 文件 / pool=15，差异来自 `archive-tx.test.mjs` 新增 3 个 fixture（6 条 AC-8 用例）与本次机器负载；不改变任何判据与阈值。

## 3. TASK 验收覆盖矩阵

| TASK | 关键 AC | 覆盖命令 | 结论 |
|---|---|---|---|
| CR-2026-066-TASK-01 | AC-1（两条判据）、AC-2、AC-5（回归面） | cmd-02、cmd-03、cmd-05、cmd-01 | 全绿 |
| CR-2026-066-TASK-02 | AC-3、AC-4①~④ | cmd-02、cmd-06、cmd-05 | 全绿 |
| CR-2026-066-TASK-03 | AC-8①~⑥ | cmd-04、cmd-05、cmd-01 | 全绿 |
| CR-2026-066-TASK-04 | AC-5、AC-6、AC-7、AC-9、AC-10 | cmd-05、cmd-06、cmd-07、cmd-01 | 全绿 |

## 4. 新增/修改测试文件

- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`：删除 `…0015` 节点序断言并替换为 AC-1 两条判据；改写 11 处既有断言（节点数事实源推导、replayNodes 4 项、`…0008` 前置删除、`…0010.approvalPrompt` 反向断言、registry 3 个 skill 节点、`FR-12.2` 5 节点顺序、`FR-12.3` / `FR-12.3b`、`CR-2026-050 AC-12` 5/4/12）；**追加** AC-3/AC-4 断言块（clean 前置 + 发布 + 对账 + BLOCK 不发布 + 四处载体 + C/D 反向面）。用例数 35 → 36。
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：`CR-2026-042 静态合同` 用例改写（inputs 2 项、节点数由 `_index.yml` 推导 + 12、replayNodes 4 项、`auto_push_after_task` 零残留）；同 `--test-name-pattern` 命中的 `_index.yml nodes` 用例同步 16 → 12。
- `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs`：`checkpoint T05 contract` 的跨 4 份 pipeline `filter(...)` 断言改为**显式枚举**（cr 三份 `deepEqual(..., [])` + `resume-cr` 逐条负向 + 枚举非空断言）；L495-506 review-alignment 断言逐字保留。
- `skills/shared/crctl/scripts/test/contract-scan.test.mjs`：code replayNodes ref 快照 5 → 4 项；**追加** FR-7 静态文本断言（tools 三份 Prompt 的 `push-progress` ∧ `单独开委派`/`同 run`）。
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`：**新增** 6 条 `CR-2026-066 AC-8` 用例（复用既有 fixture，不新建夹具）。文件用例数 24 → 30。
- **不新增测试文件**：`gate-registry.json` 零 diff，`manifest.files` 保持 21。

## 5. 未覆盖风险（含不适用说明）

1. **AC-6 延期验证点：不可在本 CR 产出证据**（需另一个 CR 走完四阶段）⇒ 按「登记即达成」定义提交，登记块见 §6；关闭触发 = 载体归档或该链路首次走完。
2. **FR-11 平台生成物（`gate_nodes_gen.go` Seq / registry digest）**：本 CR 走「**未重生成** ⇒ 重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」分支；重生成归 owner 部署窗口（登记为 `follow_up`）。
3. **平台侧部署时序（SDD-CLOSE-05）**：本 CR 只改仓库内文本；部署窗口必须与 tools 侧改动**成对生效**，否则 FR-2 前置在 Multica 侧仍会被旧白名单误判（不在本 CR 代码面内消除）。
4. **Linux（Ubuntu）侧 CI 不适用于本轮 run**：`crctl-ci.yml` 的 Ubuntu 矩阵由外部 CI 承担，不属本轮 run 拥有的工作面（plan §6.2 表注⑥），本报告不作完成声明。
5. **三个 `-e` 审计命令与 multica 跨仓断言不落长期 CI 面**（D-5）：只作本次交付证据。
6. **`openwiki/pipelines/index.md` / `openwiki/quickstart.md` 仍含 "mandatory checkpoints" 字样**：两文件不在 SDD §1.2 的 29 文件交付面内，且 `cmd-05` 的 25 文件白名单双向相等会拒绝越界改动 ⇒ 本 CR 不改，登记为残余（建议后续文档 CR/CR-P1 一并清理）。
7. **cmd-04 的 dot 点数（6）不是名字级证据**：AC-8 用例名存在性一律由 cmd-05 守卫（f）承载（`cmd-04` 空跑即绿已实测）。
8. **AC-8② 的 6 个 reason 中 `diverged` / `fetch-failed` / `trunk-unavailable` / `ff-only-failed` 未做活值覆盖**：以函数体赋值路径 + 枚举闭包 + 内存负控判定（判据与 cmd-05 的 hunk 级零 diff 相容）；活值覆盖的是 `synced` / `unchanged`（AC-8①）与 `skipped/dirty` / `skipped/wrong-branch`（AC-8③）。
9. **本 CR 不改 `AGENTS.md`（`zero_diff`）**：其 replayNodes 描述仍含 "checkpoint 节点" 字样（通用形状描述，非本 CR 数值面）；§9 明令零 diff，故保留。

## 6. 交付登记块（逐字转录 `change-requests/CR-2026-066/plan.md` §10）

**AC-6 延期验证点**

```text
AC-6 延期验证点
  载体       : 本 CR 交付后新注册的小体量演练 CR（首选，由协调者/owner 指定）；次选 = CR-P1 的首次阶段评审 PASS 链
  时点       : 载体走完四个阶段的评审发布与审批之后
  观察项 ①   : 每个 review PASS 后远端存在完整批次（repositories[].confirmed=true ∧ metadataCommit 非空 ∧ 对账通过）
  观察项 ②   : 审批动作不产生任何 checkpoint 委派（评审 PASS 之后的 checkpoint 次数 = 0）
  观察项 ③   : 审批未发布时 merge 给出 MERGE_SOURCE_MISSING/RELEASE_REMOTE_NOT_PUSHED + recovery，同 run 执行后可继续（或首次即通过）
  观察项 ④   : 「为单个 push-progress 单独开 task」次数 = 0
  责任 agent : delivery-agent（记录发布批次与 merge 兜底）；cr-coordinator-agent（记录委派计数）
  关闭触发   : 载体归档，或该链路首次走完
```

**FR-11 平台生成物登记（二选一，本 CR 的实际分支 = ②）**

- 受影响映射（可复算，SDD §6.7）：`gate_nodes_gen.go#ApprovalGates` requirement `…0005` Seq 5 → **Seq 4**；`#ReviewGates` requirement `…0004` Seq 4 → **Seq 3**；`#ApprovalGates` dev-start `…0004` Seq 5 → **Seq 4**；`#ApprovalGates` code `…0010` Seq 14 → **Seq 11**；`#ReviewGates` code `…0009` Seq 12 → **Seq 10**；tech-design 两项不变；`#ArchitectureCoreRegistryJSON` 整块 digest 必变（nodes 5→4，当前 `sha256:5454bfd9…c91cc`）。
- **登记文本 = ②：未重生成 ⇒ 重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用**（`runner.go:56-63` 未设即 false；multica `.github/workflows/*` 对 `gate-nodes`/`governance` 零引用 ⇒ 未重生成不会让任一侧 CI 变红）。重新生成由 owner 在**部署窗口**执行，不属本 CR 范围。

**D-6：第五份权限面副本的排除理由（S-7）**

- `cr-prompts-revised/agent-skill-matrix.yml` L192-194 仍含旧块注释（未含 `workspace inspect`）；按 `CUSTOM.md#75` 的「公共 Prompt 唯一事实源为 `tools/agents/`、目录内副本不再独立演进、分叉时以 tools 为准人工对齐」在下一次部署/rebase 核对时处理（本 CR 不改，登记为 `follow_up` 第一项）。

**SDD-CLOSE-05：部署时序（成对生效）**

- 本 CR 只改仓库内文本；平台把 `push-progress` 绑定给 `quality-reviewer-agent`、Prompt 投影与生成物重生成均为 owner 的**部署窗口**动作。部署前 Multica 侧运行的仍是旧白名单（不含只读 `workspace inspect`）⇒ 部署窗口必须与 tools 侧改动**成对生效**，否则 FR-2 前置会被旧合同误判。本 CR 的机械断言只约束仓库内文本，**不约束部署状态，也不构成平台侧的部署声称**。

**AC-4②③ 的断言 B 核对结论**

- 被核文件：`../multica/cr-prompts-revised/quality-reviewer-agent.md` 的 **`## 受限 crctl 权限`** 节（穷尽式白名单）。命中的 token：允许面 **只读 `workspace inspect`**；禁止面仍含 **`checkpoint`**。核对方式 = `cmd-06`（`repo=multica` 的一次性交付证据，不落长期 CI 面）。

## 7. TASK 完成记录（TASK 卡要求的逐行/逐项留档）

### 7.1 TASK-01：SDD §6.4 既有断言改动行逐行核对表（按表行计数：`pipeline-structure` 12 行 ＋ `contract-scan` 1 ＋ `crctl` 1 ＋ `checkpoint-tx` 1 = 15 行）

| # | 断言/用例 | 处置 | 新落点 |
|---|---|---|---|
| 1 | `AC-1: 节点序 review-code < checkpoint(…0015) < human_approval` | 删除 | 替换为 AC-1 两条判据断言 |
| 2 | `AC-2: checkpoint 节点 onFail/ref；16 节点` | 改写 | 节点数 ≡ `_index.yml` 事实源 + 12；保留 id 全局唯一与 gate 保留断言 |
| 3 | `AC-3: replayNodes 5 项` | 改写 | 4 项（删 `…0008`）+ 目标存在性断言 |
| 4 | `…0008 < …0017 < …0009` 相邻关系 | 改写 | 删除 `…0008` 参与的前置，保留 `…0017 < …0009`，补 `…0007 < …0017` |
| 5 | `…0010.approvalPrompt` 含 checkpoint 前提（L114-116） | 改写为反向 | `assert.equal(includes(...), false)` |
| 6 | 同上（FR-01 用例内 L135-137） | 改写为反向 | 同款反向断言 |
| 7 | `CR-2026-044 AC-13/14` requirement 7 节点 + 草稿 checkpoint | 改写 | 5 节点 + `approve-requirement` 之后无 push-progress + inputs 删除 + `_index.yml`=5 |
| 8 | `CR-2026-044 AC-14` architecture 5 节点 | 改写 | push-progress 计数 0 + 4 节点 + 全节点无 `crctl checkpoint`/`auto_push` |
| 9 | `CR-2026-044 AC-13` code 16 节点 + TASK checkpoint | 改写 | 计数 0 + inputs 无 `auto_push_after_task` + `auto_push`/`SKIPPED` 零残留 + 12 节点 |
| 10 | `CR-2026-045 AC-03` registry 4 skill 节点 + `push-progress` 行 | 改写 | 3 节点（与 skill 节点集一致）+ 去掉 push-progress 行 + digest 只断格式 |
| 11 | `FR-12.2` requirement 7 节点顺序 + auto_push 分支 | 改写 | 5 节点顺序 + inputs 删除 + push-progress 计数 0；execution_context/reviewLoop 字段集断言逐字保留 |
| 12 | `FR-12.3` / `FR-12.3b` / `CR-2026-050 AC-12` | 改写 | 12 节点 + 顺序去掉 `…0008` + replayNodes 4 项；gate 名保留、checkpoint label/auto_push 断言删除；8 条 pipeline 5/4/12 |
| — | `L229`（architecture 后续节点不得依赖 `node-1.md`） | **保留** | 本卡不涉及（未改动，实测仍绿） |
| 13 | `contract-scan AC-2c` replayNodes ref 快照 | 改写 | 5 → 4 项（去 `push-progress`） |
| 14 | `crctl.test.mjs CR-2026-042 静态合同` | 改写 | inputs 2 项、节点数推导 + 12、replayNodes 4 项、`review_llm` 零命中、`auto_push_after_task` 零残留 |
| 15 | `checkpoint-tx.test.mjs checkpoint T05 contract` | 改写（L491） | `filter` → 显式枚举（三份空集 `deepEqual` + `resume-cr` 逐条负向 + 枚举非空）；L495-506 逐字保留 |
| 补 | `crctl.test.mjs _index.yml nodes`（同 `--test-name-pattern` 命中，§6.4 未单列） | 改写 | 16 → 12（若不改则 cmd-03 必红） |

**同卡证据**：`tools diff paths = 25` 双向相等；三份 JSON `push-progress` 计数 0；`_index.yml` brief 三条与 JSON 一致；守卫（g）五行计数留档（见 §2）；负控（非证据）：`_index.yml` nodes 12→16 ⇒ AC-1 红、篡改一个 `ref=push-progress` ⇒ AC-1 红，还原后全绿且工作区干净。

### 7.2 TASK-02：B-1 两侧核对表与负向 token

| 侧 | 要素 | 落点 | 核验 |
|---|---|---|---|
| SKILL 侧 | clean 前置 | 四份 SKILL 的 Step 1 起始（`crctl workspace inspect` + `classification == 'healthy'` + 「请作者先提交」+ 不得写操作） | cmd-02 断言 A 逐文件校验 |
| SKILL 侧 | PASS 发布 | 四份 SKILL 新增「PASS 发布与对账」步（`push-progress` + 阶段 message + `phase`/`batchId`/`repositories`/`metadataCommit`） | cmd-02 |
| SKILL 侧 | 对账 + 失败语义 | 取证链（非 KB HEAD ≡ `sourceSha`；KB `HEAD = metadataCommit` ∧ `HEAD^ = sourceSha`）+ `CONTRACT_DRIFT` + 「不改 verdict」+ BLOCK 不发布 | cmd-02 |
| 载体① | `tools/agent-skill-matrix.yml` | `can-call` 增 `push-progress`、`forbidden` 去 `push-progress` 保留 `checkpoint`、块注释含只读 `workspace inspect` | cmd-02 断言 B |
| 载体② | `tools/AGENT-SKILL-MATRIX.md` | `## 本 CR 权限变更` 追加带 `CR-2026-066` 的行（含 `push-progress` 与 `workspace inspect`） | cmd-02 断言 B |
| 载体③a | `tools/agents/quality-reviewer-agent.md` | `## 权限事实源` 声明同一允许面（含只读 `workspace inspect`） | cmd-02 断言 B |
| 载体③b | `multica/.../quality-reviewer-agent.md` | `## 受限 crctl 权限` 允许面新增只读 `workspace inspect`；禁止面保留 `checkpoint`；L54 冲突句原位改写 | cmd-06 |

**「调用时机」旧前提句逐字改写**：`review-requirement`（删「（push-progress 之后）」）、`review-dev-plan`（`push-progress 之前` → 「开发启动人工审批之前」）、`review-code`（删「（代码编写与统一 checkpoint 后）」＋ 用途句改为「评审 PASS 时由本 Skill 发布阶段批次」）；`review-tech-design` 无该前提句。四文件 `push-progress 之后` / `push-progress 之前` / `统一 checkpoint 后` 三 token **零命中**（cmd-02 断言 D）；`crctl checkpoint` 零命中（断言 C）。负控（非证据）：删载体①注释 token ⇒ 断言红；删 SKILL 的「请作者先提交」⇒ 断言红；还原后全绿。

### 7.3 TASK-03：AC-8 六项用例 → 用例名（源码 token）→ 守卫计数

| # | 用例名 | `cmd-05` 守卫 / 活值 |
|---|---|---|
| ① | `CR-2026-066 AC-8① 三个成功返回点均含 localTrunkSync` | cleanup-pending / complete / 幂等重放三返回点均校验七键行形状；活值 `synced` + `unchanged` |
| ② | `CR-2026-066 AC-8② 4 状态 × 6 reason 分类正确（赋值路径 + 逐项无多无少）` | 4 状态分支各 1 条、6 reason 字面量集合闭包、`unchanged\|synced` 行不赋值 reason；含内存负控 |
| ③ | `CR-2026-066 AC-8③ dirty / wrong-branch ⇒ skipped 且本地逐字节未变` | 活值 `skipped/dirty`（tools）+ `skipped/wrong-branch`（multica）+ 未提交文件逐字节未变、零删除 |
| ④ | `CR-2026-066 AC-8④ argv 级命令面白名单（7 个调用点，硬失败）` | **实测调用点 = 7**；归一化签名集合恰为 `rev-parse` / `rev-parse --verify` / `symbolic-ref` / `status` / `fetch --prune` / `merge-base --is-ancestor` / `merge --ff-only`；argv 元素零 `reset/clean/stash/--force/push`；含内存负控 |
| ⑤ | `CR-2026-066 AC-8⑤ changed=false 重放仍返回且零新 commit` | `originMasterCount` 前后相等；`localTrunkSync` 仍返回；同一 authority commit |
| ⑥ | `CR-2026-066 AC-8⑥ cr-archive SKILL 分类/输出块含 localTrunkSync 与 4×6 口径` | 文本面：4 状态 + 6 reason + `status=unchanged\|synced ⇒ reason=null` + 补救指引 |

`cmd-04` dot 点数 = 6（执行面辅助）；`cmd-05` 守卫（f）`CR-2026-066 AC-8 tokens = 6` ∧ `test( count = 38`（≥ 30）。负控（非证据）：`complete` 返回点改回不带 `localTrunkSync` ⇒ AC-8 全体红；还原后全绿。`zero_diff`：`crctl.mjs` / `gates.json` / `gate-registry.json` 零 diff；`reconcileLocalTrunks` 函数体零 diff（hunk 级 token 检查无命中）。

### 7.4 TASK-04：四处同口径与七份 Prompt 硬规则落点

| 处 | 现文 → 目标 | 核验 |
|---|---|---|
| `push-progress/SKILL.md` | 「PRD 草稿与 TASK checkpoint 仍为可选节点；需求/架构/代码审批后的阶段终点 checkpoint 为强制完成条件」→「阶段终点完成条件 = 评审 PASS 的 checkpoint（评审者每阶段一次）；审批后不再有 checkpoint 节点；搭车；失败重跑同一 checkpoint 不重评/不重审批」 | cmd-05（含 `评审 PASS` ∧ `搭车` 正 token，旧句零命中） |
| `README.md` §6 checkpoint 行 | 「需求/架构/代码三个阶段审批后的阶段终点 checkpoint 是 Pipeline 完成条件…」→ 同口径（保留「随时可用」语义） | cmd-05 |
| `openwiki/pipelines/overview.md` | 三处审批后 checkpoint 描述 → 「the review PASS publishes the stage batch (mandatory)」；mermaid 删 `D8`/`D12`（`D9G pass → D10` 直连）；replayNodes 例改 `baseline re-verify`；contract 第 9 条改「stage terminal completion = the review PASS checkpoint」；frontmatter description 同步 | cmd-05（`review PASS` 正 token；`mandatory approval checkpoint`/`mandatory checkpoint`/`checkpoints are mandatory`/`checkpoint (mandatory)`/`D8[`/`D12[`/`checkpoint →` 零命中） |
| `dir-graph.yaml` contract 第 5 条 | 「修复、证据、checkpoint 与当前评审节点」→「修复、证据、**基线重核**与当前评审节点」 | cmd-05（`基线重核` 正 token + 旧词法零命中；`state_machine` 段 hunk 级零 diff） |

| Prompt | 落点 |
|---|---|
| `tools/agents/quality-reviewer-agent.md` | 新增「发布职责与搭车硬规则」节（PASS 后发布一次 + 硬规则句）；`## 权限事实源` 由 TASK-02 落盘、本卡未回退 |
| `tools/agents/dev-agent.md` | 委派路由合同追加「评审 PASS 即发布」+ 硬规则句 |
| `tools/agents/delivery-agent.md` | 汇报面含 `localTrunkSync`；新增「publication lag 与搭车纪律」节（recovery 双向边界 ① ②+ 硬规则句） |
| `multica/.../quality-reviewer-agent.md` | 追加 PASS 发布职责 + 硬规则句（TASK-02 的权限块与 L54 改写未回退） |
| `multica/.../dev-agent.md` | L23/L41 原位改写为「评审 PASS 即发布」口径 + 新增硬规则节 |
| `multica/.../delivery-agent.md` | recovery 双向边界 + 汇报面 `localTrunkSync` + 硬规则句 |
| `multica/.../cr-coordinator-agent.md` | 硬规则句 + 「不得把 checkpoint/阶段发布单独包装成一个 task 唤醒」显式禁止（只读边界未改） |

**FR-7 静态断言**：`contract-scan.test.mjs` 追加「tools 三份 Prompt 均含 `push-progress` ∧（`单独开委派` ∨ `同 run`）」；负控（非证据）：tools 侧删 token ⇒ cmd-02 红；multica 侧删 token ⇒ cmd-06 红；还原后全绿。`cmd-05` 的 tools 白名单 25 文件双向相等 ⇒ 无越界、`zero_diff` 面零改动。

## 8. 下一步建议

`status=developing` 下以 `crctl next CR-2026-066` 为准：本报告 `status=pass` 后进入**代码评审前统一 checkpoint**（`push-progress`，message=代码与测试证据）→ **评审前 workspace freshness（review-start）** → **独立 `review-code`**（新 run、由 `quality-reviewer-agent` 执行，不复用作者会话）。发布与评审的判定全以 crctl 权威值为准。
