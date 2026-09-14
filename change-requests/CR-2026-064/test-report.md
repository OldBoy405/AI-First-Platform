---
cr: CR-2026-064
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-14T07:17:34+08:00"
command-digest: 3b878c7a1e3e2851aa1f1feb68fcf4db3fb69af97c3bc602a343fc1fc33cdf76
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
    log: change-requests/CR-2026-064/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", "skills/writeback/scripts/test/*.test.mjs"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-064/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),path=require('path');const R=process.cwd();const NL=String.fromCharCode(10);const NAMES=['recoverCommand','recover_command'];const SKIP=['.git','node_modules'];const SCANNER='skills/shared/crctl/scripts/test/contract-scan.test.mjs';const HIST='skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml';const EXCLUDED=[SCANNER,HIST];const rel=p=>path.relative(R,p).split(path.sep).join('/');const segs=p=>rel(p).split('/');const norm=t=>t.split(String.fromCharCode(13)+NL).join(NL);const all=[];const walk=d=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(segs(p).some(s=>SKIP.includes(s)))continue;if(e.isDirectory())walk(p);else all.push(rel(p));}};walk(R);const surface=all.filter(r=>EXCLUDED.includes(r)===false).sort();const hit=f=>{const t=norm(fs.readFileSync(path.join(R,f),'utf8'));return NAMES.some(n=>t.includes(n));};const hits=surface.filter(hit);const exHit=EXCLUDED.filter(hit);const fx=surface.filter(r=>r.startsWith('skills/shared/crctl/scripts/test/fixtures/'));const reg=JSON.parse(norm(fs.readFileSync('skills/shared/crctl/scripts/test/gate-registry.json','utf8')));const mf=reg.manifest.files.slice();const disk=all.filter(f=>f.startsWith('skills/shared/crctl/scripts/test/')&&f.endsWith('.test.mjs')).map(f=>f.split('/').pop()).sort();const bad=[];console.log('enumerated = '+all.length);console.log('scan surface = '+surface.length);console.log('retired-name hits in surface = '+hits.length);hits.forEach(h=>console.log('  HIT '+h));console.log('excluded = '+EXCLUDED.length+' (hit = '+exHit.length+')');exHit.forEach(h=>console.log('  EXCLUDED-HIT '+h));console.log('fixtures in surface = '+fx.length);fx.forEach(f=>console.log('  IN '+f));console.log('manifest.files = '+mf.length+' cases floor sum = '+Object.values(reg.manifest.cases).reduce((a,b)=>a+b,0)+' exceptions = '+reg.exceptions.length);if(hits.length>0)bad.push('surface hits = '+hits.length);if(EXCLUDED.length!==2)bad.push('excluded count = '+EXCLUDED.length);if(EXCLUDED.filter(e=>[e.includes('*'),e.includes('?')].some(x=>x)).length!==0)bad.push('excluded 含通配');if(EXCLUDED.includes(SCANNER)===false)bad.push('扫描器自身不在排除项');if(EXCLUDED.includes(HIST)===false)bad.push('历史 traceability 不在排除项');if(!EXCLUDED.every(hit))bad.push('excluded hit count = '+exHit.length);if(fx.length!==3)bad.push('fixtures in surface = '+fx.length);if(surface.length<200)bad.push('scan surface suspiciously small = '+surface.length);if(mf.length!==21)bad.push('manifest.files = '+mf.length);if(JSON.stringify(mf.slice().sort())!==JSON.stringify(disk))bad.push('manifest.files 与磁盘测试文件集合不相等');if(reg.exceptions.length!==0)bad.push('exceptions 非空 = '+reg.exceptions.length);if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('scan-audit failures = 0');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-064/test-evidence/cmd-03.log
  - repo: multica
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),path=require('path'),cp=require('child_process');const R=process.cwd();const NL=String.fromCharCode(10);const NAMES=['recoverCommand','recover_command'];const DIR='cr-prompts-revised';const GOLD=['server/internal/governance/testdata/traceability-golden.yml','server/internal/governance/testdata/traceability-golden.json'];const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064/skills/shared/crctl/scripts/crctl.mjs';const SKIP=['.git','node_modules'];const rel=p=>path.relative(R,p).split(path.sep).join('/');const all=[];const walk=d=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(rel(p).split('/').some(s=>SKIP.includes(s)))continue;if(e.isDirectory())walk(p);else all.push(rel(p));}};walk(R);const hit=f=>{const t=fs.readFileSync(path.join(R,f),'utf8').split(String.fromCharCode(13)+NL).join(NL);return NAMES.some(n=>t.includes(n));};const remain=all.filter(hit).sort();const bad=[];const files=fs.readdirSync(path.join(R,DIR)).filter(f=>f.endsWith('.md'));const dhits=files.filter(f=>{const t=fs.readFileSync(path.join(R,DIR,f),'utf8');return NAMES.some(n=>t.includes(n));});console.log('multica files containing retired names = '+remain.length);remain.forEach(f=>console.log('  REMAIN '+f));console.log('cr-prompts-revised md files = '+files.length+' hits = '+dhits.length);dhits.forEach(h=>console.log('  HIT '+DIR+'/'+h));const dev=fs.readFileSync(path.join(R,DIR,'delivery-agent.md'),'utf8');if(dev.includes('recovery')===false)bad.push('delivery-agent.md 未改读结构化 recovery');if(NAMES.some(n=>dev.includes(n)))bad.push('delivery-agent.md 仍含退役字段名');for(const g of GOLD){const t=fs.readFileSync(path.join(R,g),'utf8');if(NAMES.some(n=>t.includes(n))===false)bad.push('历史黄金数据不含旧字段名（排除依据失效）: '+g);}if(dhits.length>0)bad.push('prompt hits = '+dhits.length);if(remain.length!==2)bad.push('multica 旧名残留文件数 = '+remain.length+'（应为 2 个历史黄金数据）');const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','dead9fe0d5a24118547a5be56d59241fdcc443a8','--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');console.log(String(r.stderr).trim());}else{const parts=String(r.stdout).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);console.log('multica diff paths = '+names.length);names.forEach(f=>console.log('  '+f));const want=[DIR+'/delivery-agent.md'];for(const f of names)if(want.includes(f)===false)bad.push('multica diff 越界路径: '+f);for(const f of want)if(names.includes(f)===false)bad.push('multica diff 缺少应改文件: '+f);}if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('multica-audit failures = 0');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-064/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),path=require('path'),cp=require('child_process');const R=process.cwd();const NL=String.fromCharCode(10);const CRCTL=path.join(R,'skills/shared/crctl/scripts/crctl.mjs');const T='skills/shared/crctl/scripts/test/';const WL=['README.md','openwiki/operations/crctl-transactions.md','skills/shared/crctl/SKILL.md','skills/cr/cr-archive/SKILL.md','skills/sync/push-progress/SKILL.md','skills/writeback/merge-feature-branch/SKILL.md','skills/shared/crctl/scripts/crctl.mjs','skills/shared/crctl/scripts/lib/workspace-transactions.mjs'].concat(['archive-tx','checkpoint-tx','crctl','merge-tx','register-tx','workspace-freshness','writeback-tx','contract-scan'].map(n=>T+n+'.test.mjs'));const ZERO=['ARCHITECTURE.md','dir-graph.yaml','skills/shared/crctl/gates.json','skills/shared/controlled-shell/rules.json','skills/shared/crctl/scripts/test/gate-registry.json','skills/shared/crctl/scripts/lib/durable-tx.mjs','skills/shared/crctl/scripts/lib/yaml-subset.mjs','skills/_index.yml','agents/_index.yml'];const bad=[];const SKIPS=['.git','node_modules'];const walk=(d,out)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const r=path.relative(R,p).split(path.sep).join('/');if(e.isDirectory()){if(SKIPS.includes(e.name))continue;walk(p,out);}else if(r.endsWith('.mjs'))out.push(r);}};const lib=[];walk(path.join(R,'skills/shared/crctl/scripts/lib'),lib);const guard=['skills/shared/crctl/scripts/crctl.mjs'].concat(lib);const BADT=['shell: true','shell:true','Invoke-Expression'];const ZP=['pipeline-templates/','.github/workflows/','agents/'];let falseCount=0;for(const f of guard){const t=fs.readFileSync(path.join(R,f),'utf8');for(const s of BADT)if(t.includes(s))bad.push('shell 逃逸守卫命中: '+f+' 含 '+s);const mm=t.match(/shell:[ ]*false/g);if(mm!==null)falseCount+=mm.length;}console.log('guard files = '+guard.length+' shell:false = '+falseCount);if(falseCount<1)bad.push('argv 先例 shell:false 计数异常');const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','81d31b8b9d4c36cfef24cd076bf9fe635b67b2b6','--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');console.log(String(r.stderr).trim());}else{const parts=String(r.stdout).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);console.log('tools diff paths = '+names.length);names.forEach(f=>console.log('  '+f));const inScope=f=>{if(f.startsWith('openwiki/'))return true;return WL.includes(f);};for(const f of names)if(inScope(f)===false)bad.push('tools diff 越界路径（不在 SDD §1.1 白名单）: '+f);for(const f of names){if(ZP.some(z=>f.startsWith(z)))bad.push('zero_diff 面被改动: '+f);if(ZERO.includes(f))bad.push('zero_diff 面被改动: '+f);}for(const f of WL)if(names.includes(f)===false)bad.push('tools diff 缺少应改文件: '+f);if(names.length===0)bad.push('tools diff 为空（实现未落盘？）');}if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('tools-guard-audit failures = 0');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-064/test-evidence/cmd-05.log
  - repo: ai-first-platform-docs
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),path=require('path'),cp=require('child_process');const R=process.cwd();const NL=String.fromCharCode(10);const CR='change-requests/CR-2026-064';const TOOLS='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064';const NAMES=['recoverCommand','recover_command'];const CATS=['producer','code consumer','Prompt-Skill consumer','active test','active docs','historical evidence'];const CRCTL=path.join(TOOLS,'skills/shared/crctl/scripts/crctl.mjs');const bad=[];const plan=fs.readFileSync(path.join(R,CR,'plan.md'),'utf8');for(const c of CATS)if(plan.includes(c)===false)bad.push('plan.md 六类归档缺少类别: '+c);if(plan.includes('平台 DB')===false)bad.push('plan.md 未记录平台部署边界');const docs=['README.md','openwiki/operations/crctl-transactions.md'];for(const f of docs){const t=fs.readFileSync(path.join(TOOLS,f),'utf8');if(NAMES.some(n=>t.includes(n)))bad.push('活跃文档仍含退役字段名: '+f);}const page=fs.readFileSync(path.join(TOOLS,'openwiki/operations/crctl-transactions.md'),'utf8');for(const k of ['recovery','executable','args','promptFor'])if(page.includes(k)===false)bad.push('OpenWiki 页缺少结构化合同字段名: '+k);const claim=['平台 DB','已部署'].join('');const tdir=path.join(R,CR,'tasks');const arts=[path.join(R,CR,'plan.md')].concat(fs.existsSync(tdir)?fs.readdirSync(tdir).filter(f=>f.endsWith('.md')).map(f=>path.join(tdir,f)):[]);for(const a of arts){const t=fs.readFileSync(a,'utf8');if(t.includes(claim))bad.push('CR 产物出现部署声称: '+path.relative(R,a));}const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','ab6f9347','--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');console.log(String(r.stderr).trim());}else{const parts=String(r.stdout).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);console.log('KB diff paths = '+names.length);names.forEach(f=>console.log('  '+f));for(const f of names)if(f.startsWith(CR+'/')===false&&f!=='change-requests/_backlog.yml')bad.push('KB diff 越界路径: '+f);}if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('kb-audit failures = 0');"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-064/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-064

<!-- crctl:analysis-below -->

## 测试摘要（对应 TASK 验收条件）

| TASK（`tasks/_index.yml` canonical id） | 验收条件要点 | 证据命令 | 实测结论 |
|---|---|---|---|
| `CR-2026-064-TASK-01` 生产者迁移（16h） | 唯一构造器 `buildRecovery` + 9 类场景 9 个生产者站点原位结构化 `recovery`；旧字段名零命中 | cmd-01、cmd-03 | `pass`：21 文件 / 588 用例 / 0 失败；扫描面 216 零命中，`EXCLUDED` 恰 2 项精确路径 |
| `CR-2026-064-TASK-02` CLI 投影迁移（8h） | `register` 单投影、`gate` 错配与 `reset` 提交失败分支结构化、删除 `crIdForRecover` 占位符 helper | cmd-01 | `pass`：`crctl.test.mjs` 226 用例全绿、`register-tx.test.mjs` 26 用例全绿 |
| `CR-2026-064-TASK-03` 消费方与文档迁移（12h） | 4 份 tools SKILL + `README.md` 原位改读 `recovery`；OpenWiki 生成页重生成；multica 交付 Agent 提示词 | cmd-03、cmd-04、cmd-06 | `pass`：活跃文档/生成页旧名零命中；multica diff 仅 `cr-prompts-revised/delivery-agent.md`；KB diff 10 路径全部落在 `change-requests/CR-2026-064/**` |
| `CR-2026-064-TASK-04` 测试迁移与契约退役保护（16h） | 7 个既有测试 + `contract-scan.test.mjs` 改结构/argv 断言；整树扫描面 + 2 项精确路径排除 + 四条结构性断言 + 硬失败面 + shell 逃逸守卫 | cmd-01、cmd-05 | `pass`：`contract-scan.test.mjs` 25 用例全绿（≥ 下限 17）；扫描审计与守卫审计 0 失败 |

四个 TASK 均由 `crctl task done` 逐条登记（`developing` 态、CAS + 审计），无积压补标。

## 验证命令与结果解读

证据命令集由 `plan.md` §6.2 逐字转录为 `.crctl/tmp/test-plan.json`（`cr-test-plan/v1`，6 条，`cmd-NN` = 1-based 下标，与覆盖矩阵全等），由 `crctl test` 以 `shell:false` 执行；每条命令的 `exit-code`/`started`/`skipped`/`timed-out` 见上方机器区，完整 stdout/stderr 见 `test-evidence/cmd-NN.log`。

| 证据ID | repo / cwd | exit | 墙钟（implement-code 自验重放） | 关键事实 |
|---|---|---|---|---|
| cmd-01 | tools / `.` | **0** | **793340 ms**（≈13.2 min；`crctl test` 内为 `duration_ms 819603`） | `verdict: pass`、`converged: true`、`files_executed 21`、`cases_executed 588`（≥ 下限 578）、`skipped_file_level 0`、`failures []`、`checks 13/13 ok`、`registry.sha256 f8d983a0…`、`exceptions_count 0`、pool 15 / availableParallelism 16、node 24.15.0 / win32 |
| cmd-02 | tools / `.` | **0** | 1179 ms | `--test-reporter=dot` 形态 13/13 pass、0 fail、0 skip；`skipped: false`（冻结 skip 模式零命中） |
| cmd-03 | tools / `.` | **0** | 71 ms | `enumerated 218` / `scan surface 216` / 命中 **0** / `excluded 2 (hit = 2)` / `fixtures in surface 3` / `manifest.files 21` ≡ 磁盘集合 / `exceptions 0` / `scan-audit failures = 0` |
| cmd-04 | multica / `.` | **0** | 734 ms | 旧名仅剩 2 个历史黄金数据、`cr-prompts-revised/**` 5 文件 0 命中、diff 恰 1 路径 |
| cmd-05 | tools / `.` | **0** | 154 ms | `shell:true` / `Invoke-Expression` 零命中（guard 面 5 文件 / `shell:false` 13 处）、tools diff 28 路径 ⊆ SDD §1.1 白名单、`zero_diff` 面零改动 |
| cmd-06 | ai-first-platform-docs / `.` | **0** | 150 ms | README/生成页旧名零命中且含结构化字段名、plan 六类归档齐备、无部署声称、KB diff 10 路径全在 `CR-2026-064/**` |

**cmd-03 谓词修正的上下文（本轮唯一进入实现期的合同修正）**：上一版 `plan.md` 的 cmd-03 断言「`EXCLUDED` 两项中恰好 1 项命中旧名」（`exHit.length!==1`），与 SDD §4.4-3 明文（扫描器自身保存退役名单、历史夹具保存旧名，两项排除各自都要求「仍含退役文本」）互斥，实现按 SDD/TASK-04 落地后必然 `hit = 2`、cmd-03 恒红。经 Ray 显式授权（选项 B：就地最小修正），本节点把谓词改为 **`if(!EXCLUDED.every(hit))`（两项排除都必须命中）**，并同步 §5.1 checklist 与 §6.3 两处措辞为「两项排除均含旧名（扫描器保存退役名单、历史夹具保存旧名）」；未动 SDD、未新增或收窄排除项、未改 `gate-registry.json`、未使用字符串规避。plan.md 新 commit `273878a1`、LF 规范化 sha256 `2ffae3b93c4aa2039576fca28a18680575578d65d46459e5dd5a9ab681d1d355`；该改动使 `approval.yml#development-start.evidence-digest` 与 `review-annotations/dev-plan.yml` 的 `subject-sha256` 漂移，前者由人工 `crctl approve --stage dev-start --resign` 受控迁移，后者见「未覆盖风险」。

## TASK 验收覆盖矩阵

| TASK | 直接证据 | 关联证据 | 未覆盖项 |
|---|---|---|---|
| `TASK-01` | cmd-01（结构断言 + argv 断言全套） | cmd-03（退役名扫描） | 无 |
| `TASK-02` | cmd-01 | cmd-05（diff 白名单、`zero_diff`） | 无 |
| `TASK-03` | cmd-03、cmd-04、cmd-06 | cmd-05（应改文件齐备） | 无 |
| `TASK-04` | cmd-01（`contract-scan` / 7 个迁移测试）、cmd-05 | cmd-03（登记面与排除面不变） | 无 |

## 新增/修改测试文件

- **修改（8 个，全部为既有文件原位迁移，`manifest.files` 集合与磁盘集合恒等）**：`archive-tx.test.mjs`（24 用例）、`checkpoint-tx.test.mjs`（23）、`crctl.test.mjs`（226）、`merge-tx.test.mjs`（17）、`register-tx.test.mjs`（26）、`workspace-freshness.test.mjs`（32）、`writeback-tx.test.mjs`（33）、`contract-scan.test.mjs`（25）。
- **新增测试文件：0 个**（R-13 登记面约束：不得新增该目录测试文件；`gate-registry.json` 未改动）。
- 用例下限校验由 cmd-01 的 `SUITE_MANIFEST_CASE_DROP` / `SUITE_MANIFEST_FILE_DRIFT` 两项检查机械执行，两项目前均 `ok`；合计 588 ≥ 578。

## 未覆盖风险

1. **`review-annotations/dev-plan.yml` 的 `subject-sha256` 相对 plan.md 变陈旧（已接受）**：授权 B 的就地修正使该记录（`0913eedc…`）不再匹配当前 `plan.md`+`tasks/` 复合摘要（`3a339e9b…`），`crctl status` 的 `developing.gateBlockers` 会如实显示「dev-plan digest 漂移」。这是选项 B 的已知代价（选项 A 不留该残渣但需重放 3 个 Agent 节点 + 第二次人工开发启动审批），由 Ray 裁量后接受；`approval.yml#development-start` 一侧由 `--resign` 受控迁移，漂移与理由留在 `approval.yml` 审计块中可复核。
2. **`cmd-02` 的 reporter 转录**：相对 SDD §6.3 第 2 条命令增加了 `--test-reporter=dot`（文件集合、断言与退出码语义不变）。理由是 node 默认 spec reporter 的摘要行恒含 `skipped` 字样，会误命中冻结 skip 模式使机器区假标 `skipped: true`；转录依据与代价写在 plan §6.2.1 / R-14 / R-15。若评审要求与 SDD 字面完全一致，去掉该参数即可，代价是该假标记。
3. **生成本报告所用 `crctl` 是 workspace 解析出的 tools 包（trunk 检出 `81d31b8`），其响应仍带 `recoverCommand` 字段**：本 CR 的交付物是 `requirement/CR-2026-064` 分支（新 `recovery`），tools 包主检出的迁移属合并后事实。已验证本 CR 未改动 `test-report.md` 机器区生成路径（`git diff` 内无相关行），故机器区与用分支内 `crctl` 生成等价；证据命令本身一律在 CR worktree 内执行（`cmd-01…06` 的 `cwd` 均为各仓 CR worktree）。
4. **平台侧部署不在本 CR 内（不适用，非缺口）**：tools 发布后的 Multica 平台 Prompt 部署由 owner 另行执行（SDD §1.1 / FR-16），本报告不对平台侧已生效作任何声称；cmd-06 对该边界有机械断言。
5. **未做跨平台（Linux/macOS）执行**：本节点全部证据在 win32 / node 24.15.0 上产生；跨平台一致性由 CI 承担，本地不重复执行。

## 下一步建议

- `review-code` 由**独立** `quality-reviewer-agent` run 执行（本报告与代码、checkpoint 为其输入）。
- 评审关注点建议：① cmd-03 谓词修正与 SDD §4.4-3 的一致性（本轮唯一合同修正，plan `273878a1`）；② `recovery` 结构断言的键序/可选性/`promptFor` 三值映射；③ `shell:false` 与 `zero_diff` 面的机械守卫结论。
- 本节点不自行判定评审结论；`review-code` PASS 后按 pipeline node 15 跑审批前 checkpoint，停在人工「代码审查通过」gate。
