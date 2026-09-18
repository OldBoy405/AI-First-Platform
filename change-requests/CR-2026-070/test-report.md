---
cr: CR-2026-070
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-18T17:19:41+08:00"
command-digest: 035232f14f4e06b0c5c447525b0edf348b1acd20a0c745e2719789217dfd9e6c
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", output-guard/test/core.test.mjs, output-guard/test/conformance.test.mjs, output-guard/test/adapters-contract.test.mjs]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-070/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/execenv/, "-count=1", -v, -run, TestBriefSkills]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-070/test-evidence/cmd-02.log
  - repo: multica
    cwd: .
    executable: node
    args: [-e, "const fs = require('fs'), P = require('path'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const read = (p) => fs.readFileSync(P.join(R, p), 'utf8').split(CRLF).join(NL); const exists = (p) => fs.existsSync(P.join(R, p)); const bad = []; const AN = 'Treat that list as the authoritative entry point for skill selection'; const LAND = 'server/internal/daemon/execenv/runtime_config_sections.go'; const TESTF = 'server/internal/daemon/execenv/runtime_config_test.go'; const CONST = 'skillsRoutingRule'; if (!exists(LAND)) { bad.push('FAIL 缺 ' + LAND); } else { const t = read(LAND); if (t.length < 1000) { bad.push('FAIL ' + LAND + ' 读空或过短 length=' + t.length); } const n = t.split(AN).length - 1; if (n !== 1) { bad.push('FAIL 落点面锚短语命中数 = ' + n + '（期望恰 1）'); } for (const k of ['use the discovered copy directly, before any repository exploration', 'no recursive search for', 'stop the current node and report the missing capability', 'do not produce a business verdict']) { if (t.indexOf(k) < 0) { bad.push('FAIL 落点面缺规则子句 ' + k); } } const i = t.indexOf(AN); const win = i < 0 ? '' : t.slice(Math.max(0, i - 1200), i + 2400); for (const p of ['.pi/skills', '.claude', '.codex', '.qwen', '.multica', 'AGENTS.md', 'CLAUDE.md', 'QWEN.md']) { if (win.indexOf(p) >= 0) { bad.push('FAIL 规则文本窗口出现 Provider 私有面字面量 ' + p); } } if (t.indexOf(CONST) < 0) { bad.push('FAIL 落点面缺常量符号 ' + CONST); } } if (!exists(TESTF)) { bad.push('FAIL 缺 ' + TESTF); } else { const t = read(TESTF); if (t.indexOf(AN) >= 0) { bad.push('FAIL 测试文件内联了锚短语（落点面会扩为 2 文件，违反 SDD 6.4）'); } if (t.indexOf(CONST) < 0) { bad.push('FAIL 测试文件未引用被测常量符号 ' + CONST); } if (t.split('TestBriefSkills').length - 1 < 1) { bad.push('FAIL 测试文件缺 TestBriefSkills 系列断言'); } } let scanned = 0; const hits = []; const walk = (dir) => { if (!fs.existsSync(dir)) { bad.push('FAIL 零复制面目录缺失（硬失败） ' + dir); return; } for (const e of fs.readdirSync(dir, { withFileTypes: true })) { if (['node_modules', '.git'].indexOf(e.name) >= 0) { continue; } const p = P.join(dir, e.name); if (e.isDirectory()) { walk(p); continue; } const dot = e.name.lastIndexOf('.'); const ext = dot < 0 ? '' : e.name.slice(dot); if (['.go', '.md', '.ts', '.tsx', '.json', '.yml', '.yaml', '.txt', '.js', '.mjs'].indexOf(ext) < 0) { continue; } scanned++; const rel = P.relative(R, p).split(P.sep).join('/'); if ([LAND, TESTF].indexOf(rel) >= 0) { continue; } const txt = fs.readFileSync(p, 'utf8').split(CRLF).join(NL); if (txt.indexOf(AN) >= 0) { hits.push(rel); } } }; walk(P.join(R, 'server/internal')); walk(P.join(R, 'cr-prompts-revised')); if (scanned < 1000) { bad.push('FAIL 零复制面扫描文件数 = ' + scanned + '（期望 >1000；读空即硬失败）'); } if (hits.length > 0) { bad.push('FAIL 零复制面锚短语命中数 = ' + hits.length + '：' + hits.slice(0, 5).join(',')); } if (!exists('CUSTOM.md')) { bad.push('FAIL 缺 CUSTOM.md'); } else { const t = read('CUSTOM.md'); if (t.length < 5000) { bad.push('FAIL CUSTOM.md 读空或过短 length=' + t.length); } if (t.indexOf('CR-2026-070') < 0) { bad.push('FAIL CUSTOM.md 缺 CR-2026-070 台账行'); } if (t.indexOf('runtime_config_sections.go') < 0) { bad.push('FAIL CUSTOM.md 台账行未登记落点文件'); } } console.log('audit-multica scanned=' + scanned + ' copyFaceHits=' + hits.length); if (bad.length) { console.log('audit-multica failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-multica failures = 0');"]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-070/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const cp = require('child_process'), fs = require('fs'), P = require('path'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const bad = []; const CRCTL = P.join(R, 'skills/shared/crctl/scripts/crctl.mjs'); const jrun = (args, cwd) => { const r = cp.spawnSync(process.execPath, [CRCTL].concat(args), { cwd, encoding: 'utf8', shell: false }); if (r.status !== 0) { bad.push('FAIL crctl ' + args.join(' ') + ' exit=' + r.status); console.log(String(r.stderr == null ? '' : r.stderr).slice(-300)); return null; } return String(r.stdout == null ? '' : r.stdout).split(CRLF).join(NL); }; const lines = (out) => { const p = out.split(NL); const i = p.findIndex((l) => l.trim() === '{'); return p.slice(0, i < 0 ? p.length : i).map((s) => s.trim()).filter(Boolean); }; const wsRaw = jrun(['workspace', 'inspect', 'CR-2026-070'], R); let ws = null; if (wsRaw !== null) { try { ws = JSON.parse(wsRaw); } catch (e) { bad.push('FAIL workspace inspect 输出不可解析 ' + e.message); } } const pathOf = (id) => { if (!ws) { return null; } if (!Array.isArray(ws.resources)) { return null; } const x = ws.resources.filter((r) => r.repo === id)[0]; return x ? x.worktreePath : null; }; const MUL = pathOf('multica'), KB = pathOf('ai-first-platform-docs'); if (!MUL) { bad.push('FAIL 取不到 multica worktreePath'); } if (!KB) { bad.push('FAIL 取不到 ai-first-platform-docs worktreePath'); } const names = (root, base) => { const out = jrun(['git', 'diff', '--name-only', base, '--cwd', root], R); return out === null ? null : lines(out); }; const T0 = 'c3e7c934ef2636c56cc840543cadb4feb5f554aa'; const M0 = '59b47993810fabd12fcc393c2fa2e46611f9530d'; const K0 = '349ae2271cfa53009dd90bbbb967d11ce98892c9'; const tz = names(R, T0); if (tz === null) { bad.push('FAIL tools diff 不可判'); } else { console.log('tools diff paths = ' + tz.length); for (const f of tz) { console.log('  ' + f); } if (tz.length !== 0) { bad.push('FAIL tools diff 非空 = ' + tz.length + '（AC-9/AC-10 的 zero_diff 面）'); } } const MZ = ['CUSTOM.md', 'server/internal/daemon/execenv/runtime_config_sections.go', 'server/internal/daemon/execenv/runtime_config_test.go']; if (MUL) { const mz = names(MUL, M0); if (mz === null) { bad.push('FAIL multica diff 不可判'); } else { console.log('multica diff paths = ' + mz.length); for (const f of mz) { console.log('  ' + f); } if (mz.length === 0) { bad.push('FAIL multica diff 为空（硬失败：基线或分支不对，不得静默通过）'); } for (const f of mz) { if (MZ.indexOf(f) < 0) { bad.push('FAIL multica diff 越界路径 ' + f); } } for (const f of MZ) { if (mz.indexOf(f) < 0) { bad.push('FAIL multica diff 缺应改文件 ' + f); } } if (mz.length > 3) { bad.push('FAIL multica diff 路径数 = ' + mz.length + '（上界 3）'); } } } if (KB) { const kz = names(KB, K0); if (kz === null) { bad.push('FAIL KB diff 不可判'); } else { console.log('KB diff paths = ' + kz.length); for (const f of kz) { console.log('  ' + f); } const KZ = ['AGENTS.md', 'dir-graph.yaml', 'CONTEXT.md', 'README.md', 'maturity-config.yaml', 'change-requests/CR-2026-070/prd.md', 'change-requests/CR-2026-070/sdd.md']; const KP = ['specs/', 'delivery/', 'docs/']; const ALLOW = ['change-requests/CR-2026-070/', 'change-requests/_backlog.yml', 'change-requests/_history.yml', 'change-requests/_index.yml']; for (const f of kz) { if (KZ.indexOf(f) >= 0) { bad.push('FAIL KB zero_diff 面被写入 ' + f); } for (const z of KP) { if (f.indexOf(z) === 0) { bad.push('FAIL KB zero_diff 前缀面被写入 ' + f); } } let okK = false; for (const a of ALLOW) { if (f.indexOf(a) === 0) { okK = true; } } if (!okK) { bad.push('FAIL KB diff 越界路径 ' + f); } } for (const f of ['change-requests/CR-2026-070/plan.md', 'change-requests/CR-2026-070/tasks/_index.yml', 'change-requests/CR-2026-070/evidence/fr1-smoke.json', 'change-requests/CR-2026-070/evidence/pi-source.json']) { if (kz.indexOf(f) < 0) { bad.push('FAIL KB diff 缺少应交付文件 ' + f); } } } } if (bad.length) { console.log('audit-diff failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-diff failures = 0');"]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-070/test-evidence/cmd-04.log
  - repo: ai-first-platform-docs
    cwd: .
    executable: node
    args: [-e, "const cp = require('child_process'), fs = require('fs'), P = require('path'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const bad = []; const EV = 'change-requests/CR-2026-070/evidence/fr1-smoke.json'; if (!fs.existsSync(P.join(R, EV))) { bad.push('FAIL 缺 FR-1 行为验收证据 ' + EV); } else { const raw = fs.readFileSync(P.join(R, EV), 'utf8').split(CRLF).join(NL); if (raw.length < 500) { bad.push('FAIL fr1-smoke.json 读空或过短 length=' + raw.length); } let d = null; try { d = JSON.parse(raw); } catch (e) { bad.push('FAIL fr1-smoke.json 解析失败 ' + e.message); } if (d) { if (d.schema !== 'cr-2026-070-fr1-smoke/v1') { bad.push('FAIL fr1-smoke.json schema = ' + d.schema); } const runs = Array.isArray(d.runs) ? d.runs : null; const runCount = runs ? runs.length : 0; if (runCount < 3) { bad.push('FAIL fr1-smoke.json runs 缺失或少于 3 条'); } for (const ac of ['AC-2', 'AC-3', 'AC-4']) { const r0 = runs ? runs.filter((x) => x.ac === ac)[0] : null; if (!r0) { bad.push('FAIL 缺 ' + ac + ' 运行记录'); continue; } for (const k of ['scenario', 'agentId', 'runId', 'observedAt', 'provider', 'toolCalls']) { if (r0[k] === undefined) { bad.push('FAIL ' + ac + ' 缺字段 ' + k); } } const tc = Array.isArray(r0.toolCalls) ? r0.toolCalls : []; if (tc.length < 1) { bad.push('FAIL ' + ac + ' toolCalls 为空（取证面不可判，硬失败）'); } let search = 0, guess = 0; for (const c of tc) { const cmd = String(c && c.command == null ? '' : c.command); const fam = ['find ', 'find.exe', 'Get-ChildItem', '-Recurse', 'dir /s', 'rg --files'].some((x) => cmd.indexOf(x) >= 0); if (cmd.indexOf('SKILL.md') >= 0 && fam) { search++; } if (['.pi/agent/skills', '.multica/skills', '.claude/skills', '.claude/agents'].some((x) => cmd.indexOf(x) >= 0)) { guess++; } } if (search !== 0) { bad.push('FAIL ' + ac + ' 内 SKILL.md 搜索类 bash 调用数 = ' + search + '（期望 0）'); } if (guess !== 0) { bad.push('FAIL ' + ac + ' 内猜测私有目录访问数 = ' + guess + '（期望 0）'); } const rr = cp.spawnSync('multica', ['agent', 'tasks', String(r0.agentId), '--output', 'json'], { encoding: 'utf8', shell: false, timeout: 120000, maxBuffer: 67108864 }); const so = String(rr.stdout == null ? '' : rr.stdout).split(CRLF).join(NL); if (rr.status !== 0) { bad.push('FAIL multica agent tasks ' + r0.agentId + ' exit=' + rr.status + '（平台 run 记录不可判）'); } else if (so.indexOf(String(r0.runId)) < 0) { bad.push('FAIL 平台 run 列表未见 ' + ac + ' 的 runId ' + r0.runId + '（记录与平台不一致）'); } else { console.log(ac + ' run ' + r0.runId + ' 平台可见'); } } const ac4 = runs ? runs.filter((x) => x.ac === 'AC-4')[0] : null; if (ac4) { if (ac4.businessVerdictWritten !== false) { bad.push('FAIL AC-4 businessVerdictWritten 必须为 false'); } if (ac4.missingCapabilityReported !== true) { bad.push('FAIL AC-4 missingCapabilityReported 必须为 true'); } if (!(Array.isArray(ac4.reviewAnnotationsNewFiles) && ac4.reviewAnnotationsNewFiles.length === 0)) { bad.push('FAIL AC-4 reviewAnnotationsNewFiles 必须存在且为空数组（run 期新落盘的 verdict 文件不得静默忽略）'); } const cf = ac4.controlledFiles && typeof ac4.controlledFiles === 'object' ? ac4.controlledFiles : null; if (!cf) { bad.push('FAIL AC-4 缺 controlledFiles'); } else { const ks = Object.keys(cf); if (ks.length < 4) { bad.push('FAIL AC-4 controlledFiles 少于 4 条'); } if (ks.filter((k) => k.indexOf('change-requests/CR-2026-070/review-annotations/') === 0).length < 1) { bad.push('FAIL AC-4 controlledFiles 缺 change-requests/CR-2026-070/review-annotations/*.yml 受控条目（业务 verdict 落盘面未覆盖）'); } for (const k of ks) { const v = cf[k] ? cf[k] : {}; const hasB = v.beforeSha256 ? 1 : 0, hasA = v.afterSha256 ? 1 : 0; if (hasB + hasA < 2) { bad.push('FAIL AC-4 controlledFiles ' + k + ' 缺 before/after sha256'); } else if (v.beforeSha256 !== v.afterSha256) { bad.push('FAIL AC-4 controlledFiles ' + k + ' run 前后 sha256 不一致（run 期有写入）'); } } } } } } if (bad.length) { console.log('audit-fr1-smoke failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-fr1-smoke failures = 0');"]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-070/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const cp = require('child_process'), fs = require('fs'), P = require('path'), crypto = require('crypto'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const bad = []; const CRCTL = P.join(R, 'skills/shared/crctl/scripts/crctl.mjs'); const jrun = (args, cwd) => { const r = cp.spawnSync(process.execPath, [CRCTL].concat(args), { cwd, encoding: 'utf8', shell: false, timeout: 120000 }); if (r.status !== 0) { bad.push('FAIL crctl ' + args.join(' ') + ' exit=' + r.status); console.log(String(r.stderr == null ? '' : r.stderr).slice(-300)); return null; } return String(r.stdout == null ? '' : r.stdout).split(CRLF).join(NL); }; const lines = (out) => { const p = out.split(NL); const i = p.findIndex((l) => l.trim() === '{'); return p.slice(0, i < 0 ? p.length : i).map((s) => s.trim()).filter(Boolean); }; const wsRaw = jrun(['workspace', 'inspect', 'CR-2026-070'], R); let ws = null; if (wsRaw !== null) { try { ws = JSON.parse(wsRaw); } catch (e) { bad.push('FAIL workspace inspect 输出不可解析 ' + e.message); } } const pathOf = (id) => { if (!ws) { return null; } if (!Array.isArray(ws.resources)) { return null; } const x = ws.resources.filter((r) => r.repo === id)[0]; return x ? x.worktreePath : null; }; const KB = pathOf('ai-first-platform-docs'); if (!KB) { bad.push('FAIL 取不到 KB worktreePath（Pi 侧证据不可判）'); } const EV = KB ? P.join(KB, 'change-requests/CR-2026-070/evidence/pi-source.json') : null; let ev = null; if (EV === null) { bad.push('FAIL 缺 KB worktreePath，Pi 侧交付证据不可判'); } else if (!fs.existsSync(EV)) { bad.push('FAIL 缺 Pi 侧交付证据 ' + EV); } else { const raw = fs.readFileSync(EV, 'utf8').split(CRLF).join(NL); if (raw.length < 300) { bad.push('FAIL pi-source.json 读空或过短 length=' + raw.length); } try { ev = JSON.parse(raw); } catch (e) { bad.push('FAIL pi-source.json 解析失败 ' + e.message); } } if (ev) { for (const k of ['schema', 'upstreamUrl', 'baseCommit', 'checkoutPath', 'branch', 'headCommit', 'changedFiles', 'testFile', 'testLogPath', 'testLogSha256', 'buildCommand', 'artifactVersion', 'installedPackage']) { if (ev[k] === undefined) { bad.push('FAIL pi-source.json 缺字段 ' + k); } } if (ev.schema !== 'cr-2026-070-pi-source/v1') { bad.push('FAIL pi-source.json schema = ' + ev.schema); } if (ev.baseCommit !== 'd981de1229ef899957bbe968bc8dcda02a21f477') { bad.push('FAIL baseCommit 未钉在 v0.85.1 tag SHA：' + ev.baseCommit); } const CO = ev.checkoutPath; const coOk = CO ? fs.existsSync(CO) : false; if (!coOk) { bad.push('FAIL Pi 源码检出不存在（ENVIRONMENT_MISMATCH：需先按 TASK-02 建立检出）' + CO); } else { const hv = jrun(['git', 'rev-parse', 'HEAD', '--cwd', CO], R); const head = lines(hv === null ? '' : hv); if (head[0] !== ev.headCommit) { bad.push('FAIL checkout HEAD = ' + head[0] + ' != 记录的 headCommit ' + ev.headCommit); } const fv = jrun(['git', 'diff', '--name-only', String(ev.baseCommit), '--cwd', CO], R); const files = lines(fv === null ? '' : fv); const rec = (Array.isArray(ev.changedFiles) ? ev.changedFiles : []).slice().sort(); const act = files.slice().sort(); if (JSON.stringify(rec) !== JSON.stringify(act)) { bad.push('FAIL 变更文件集不一致 rec=' + JSON.stringify(rec) + ' act=' + JSON.stringify(act)); } if (act.length < 1) { bad.push('FAIL 变更文件集为空（硬失败）'); } for (const f of act) { const inFace = (f.indexOf('packages/coding-agent/src/') === 0) ? true : (f.indexOf('packages/coding-agent/test/') === 0); if (!inFace) { bad.push('FAIL 变更文件越出 AC-12 面（仅版本化源码与其测试）：' + f); } const artefact = (f.indexOf('dist') >= 0) ? true : (f.indexOf('node_modules') >= 0); if (artefact) { bad.push('FAIL 变更文件含构建产物或依赖目录：' + f); } } const VITEST = P.join(CO, 'node_modules', 'vitest', 'vitest.mjs'); if (!fs.existsSync(VITEST)) { bad.push('FAIL 缺 vitest（ENVIRONMENT_MISMATCH：检出未 npm ci）' + VITEST); } else { const r2 = cp.spawnSync(process.execPath, [VITEST, 'run', String(ev.testFile), '--reporter=verbose'], { cwd: P.join(CO, 'packages', 'coding-agent'), encoding: 'utf8', shell: false, timeout: 900000, maxBuffer: 67108864 }); const so = String(r2.stdout == null ? '' : r2.stdout).split(CRLF).join(NL); const se = String(r2.stderr == null ? '' : r2.stderr).split(CRLF).join(NL); console.log('pi-side vitest exit=' + r2.status); console.log(so.slice(-1500)); if (r2.status !== 0) { bad.push('FAIL Pi 侧用例活体复跑 exit=' + r2.status + ' stderr=' + se.slice(-300)); } for (const k of ['300 second default', 'reports 300 seconds and kills the process tree', 'explicit timeout 1200 is not overridden', 'keeps existing errors before spawn', 'schema description matches the default']) { if (so.indexOf(k) < 0) { bad.push('FAIL Pi 侧用例输出缺断言名 ' + k); } } } } const LG = ev.testLogPath; const LGA = LG && fs.existsSync(LG) ? LG : (KB ? P.join(KB, String(LG)) : null); const lgOk = LGA ? fs.existsSync(LGA) : false; if (!lgOk) { bad.push('FAIL 缺 Pi 侧测试日志 ' + LG); } else { const t = fs.readFileSync(LGA); if (t.length < 200) { bad.push('FAIL Pi 侧测试日志读空或过短 length=' + t.length); } const h = crypto.createHash('sha256').update(t).digest('hex'); if (h !== ev.testLogSha256) { bad.push('FAIL Pi 侧测试日志 sha256 漂移 ' + h); } } const IP = ev.installedPackage ? ev.installedPackage.path : null; const ipOk = IP ? fs.existsSync(IP) : false; if (!ipOk) { bad.push('FAIL 记录的已安装包路径不存在 ' + IP); } else { const f = P.join(IP, 'dist', 'core', 'tools', 'bash.js'); if (!fs.existsSync(f)) { bad.push('FAIL 已安装包缺 dist/core/tools/bash.js'); } else { const t = fs.readFileSync(f, 'utf8').split(CRLF).join(NL); const h = crypto.createHash('sha256').update(t).digest('hex'); if (h !== ev.installedPackage.bashJsSha256) { bad.push('FAIL 已安装包 dist/core/tools/bash.js sha256 漂移（可能被就地修改，AC-12 负向）：' + h); } if (t.indexOf('no default timeout') < 0) { bad.push('FAIL 已安装包不再声明 no default timeout（本 CR 不得以安装包为改动载体；若环境已升级请按 plan 5.3 重新基线）'); } } } } if (bad.length) { console.log('audit-pi-source failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-pi-source failures = 0');"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-070/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-070

<!-- crctl:analysis-below -->

## 1. 测试摘要（对应 TASK 验收条件）

- 六条证据命令**全部 exit-code 0**、`skipped=false`、`timed-out=false`（机器区原样）；`command-digest=035232f1…9e6c`，`status=pass`，`tester=Ray`（`cr.md owners.test.id`）。
- 四张 TASK（TASK-01／02／03／04）均已 `done`（`tasks/_index.yml`，逐张经 `crctl task done` 登记）。
- 本 CR 的行为类验收（FR-1 的 AC-2／AC-3／AC-4、FR-2 的 AC-5～AC-8）均由**真实 run 的会话记录**取得，非静态断言顶替（`dep-1` §5）。

## 2. 验证命令与结果解读（cmd-01～cmd-06）

| 证据ID | 观测面 | 本次实测（原样摘要） | 解读 |
|---|---|---|---|
| cmd-01 | tools 仓 OutputGuard conformance（core／conformance／adapters-contract 三文件，dot reporter） | exit 0；dot 输出 35 个（同面复算 `pass 35 / fail 0 / skipped 0`） | AC-9 的既有 CI 面零回归（tools diff 为 0） |
| cmd-02 | multica `TestBriefSkills` 定点执行 | exit 0；`--- PASS: TestBriefSkillsListIsNamesOnly` ＋ 7 项子用例（claude／codex／grok／some-unknown-provider／opencode／traecli／hermes） | 既有形状钉子测试在本 CR 后仍恰 7 项子用例（pi 的覆盖由 cmd-03 源码级断言守卫）；`--- PASS:` 在场 ⇒ `skipped=false` 非假绿 |
| cmd-03 | multica 落点面源码级断言 ＋ 零复制面扫描 | exit 0；`audit-multica scanned=1492 copyFaceHits=0`、`failures = 0` | 规则文本单点落盘（锚短语恰 1 命中、四子句＋常量符号在场）、零复制面命中 0、`CUSTOM.md` 含 CR-2026-070 台账行 |
| cmd-04 | 三仓 diff 白名单 ＋ KB 交付面 | exit 0；`tools diff paths = 0`、`multica diff paths = 3`（`CUSTOM.md`／`runtime_config_sections.go`／`runtime_config_test.go`）、`KB diff paths = 15`（含两份证据文件） | AC-9／AC-10／AC-11 的 zero_diff 面成立；multica 白名单**双向相等**（不多不少恰 3） |
| cmd-05 | `fr1-smoke.json` 结构 ＋ 独立重算 ＋ 平台 run 活体锚定 ＋ AC-4 受控文件前后一致 | exit 0；三条 run 均「平台可见」、`audit-fr1-smoke failures = 0` | FR-1 的行为验收（AC-2／AC-3／AC-4）成立 |
| cmd-06 | Pi 侧交付证据活体取证（变更文件集＋用例复跑＋日志哈希＋安装包负向） | exit 0；`pi-side vitest exit=0`（`Test Files 1 passed`／`Tests 5 passed`，5 条断言名齐备）、`audit-pi-source failures = 0` | AC-5～AC-8／AC-12 成立；安装包 `dist/core/tools/bash.js` sha256 无漂移且仍含 `no default timeout` ⇒ 本 CR 未以安装包为改动载体 |

**基线数字说明（非门禁）**：plan §6.3 的 `cmd-01` 行记 38 pass，本次同面实测 35 pass（同一字面命令，`pass 35 / fail 0 / skipped 0`）。plan §6.3 已明示「不得把本表数字当门禁阈值比对」，判据为 exit 0；该差异不影响任何 AC 判据，登记以免被读成漂移。

## 3. FR-1 三条真实 run 的对账（采集 run 之后的实施 run 执行，平台面独立核验）

`fr1-smoke.json#runs[].toolCalls` 由三份节点回报评论**原文转录**；平台面以 `multica agent tasks <agentId> --output json` 现查（非转述）：

| AC | agentId | runId | 平台 `tool_calls` / 报告数组 | 同序前缀相等 | 尾部差集（逐条枚举） |
|---|---|---|---|---|---|
| AC-2 | `2ed1a9de-4c8e-4b78-bfb1-055af99c6681` | `01a0b3be-50e9-786c-9ec2-3f19f582d1ba` | 15 / 12 | **12/12** | `206:write(target=reply.md)`＝①写正文、`248:bash`＝②发布评论、`250:bash`＝③清理 |
| AC-3 | `2ed1a9de-4c8e-4b78-bfb1-055af99c6681` | `01a0b3c3-fa05-7d2a-b967-be5852fcd7a6` | 11 / 8 | **8/8** | `103:write(target=./reply.md)`、`112:powershell`、`114:powershell` |
| AC-4 | `39ec52e7-d1ba-4abb-92fb-ca65a11ca458` | `01a0b3c9-a5e3-78ad-9a4e-f7969866fa40` | 14 / 11 | **11/11** | `93:write(target=./reply.md)`、`104:bash`、`107:bash` |

- 三条数组的**末条均为取数调用自身** ⇒ 适用「尾部差集 ≤ 3 条」分支；三条差集均恰为 3，且逐条落在允许集合内（① 写回报正文文件 ＋ ② 发布回报评论 ＋ ③ 清理临时正文文件）。
- 平台面 `read(target)` 与节点自报位置逐字一致：AC-2／AC-3 均为 `.pi/skills/review-{requirement,dev-plan}/SKILL.md`（各 2 次），AC-4 为 `.pi/skills/review-requirement/SKILL.md`（1 次）。
- 独立重算（cmd-05 内建算法，非节点自报）：三条数组的 SKILL.md 搜索类调用数 = **0**、猜测私有目录访问数 = **0**。
- 未入证的 attempt（不在 `runs[]` 内）：`01a0b3b8-69c4-7f40-90de-ac1300fbf57b`（`status=failed`，平台无 `result.tool_calls`，且 run 自身误用 `2>nul` 落成保留名文件致收尾 `git add` 失败）；`01a0b354-e674-774a-b4a9-202d404fe71e`（AC-2 首轮版本，数组含 1 次搜索类调用，已按机械判据判红）。

## 4. AC-4 受控文件窗口（run 前后一致）

`fr1-smoke.json#runs[2].controlledFiles` ＝ run 前 `change-requests/CR-2026-070/review-annotations/` 目录**实际存在的全部 3 个文件**（`dev-plan.yml`／`requirement.yml`／`sdd.yml`）＋ 4 个账本文件，共 **7 条**；前后 sha256 **全等**（读入先 `\r\n → \n` 归一、64 位小写十六进制）。`reviewAnnotationsNewFiles = []`、`businessVerdictWritten=false`、`missingCapabilityReported=true`。窗口与**单一 run** 对齐：before 集取于下发 AC-4 节点的那一 run 结束时刻，after 集于采集 run（`01a0b3c9-a5e3-78ad-9a4e-f7969866fa40`）结束后由本实施 run 以同一口径重算。

## 5. TASK 验收覆盖矩阵

| TASK | 验收面 | 证据 |
|---|---|---|
| TASK-01 | FR-1 规则文本单点落盘 ＋ 形状钉子测试增项 | cmd-02、cmd-03、cmd-04 |
| TASK-02 | Pi 侧默认 300 秒 ＋ 秒数传递 ＋ schema 文案 ＋ 用例 | cmd-06（5 条断言名活体复跑）、`evidence/pi-source.json`、`evidence/pi-vitest.log` |
| TASK-03 | `CUSTOM.md#96` 台账行 | cmd-03（含 CR-2026-070 与落点文件）、cmd-04（multica diff 恰 3 文件） |
| TASK-04 | 三条 run 记录 ＋ AC-4 受控文件窗口 ＋ 独立重算 ＋ 平台锚定 | cmd-05、`evidence/fr1-smoke.json` |

**TASK-04 §4 负向自检（两项均实跑，未静默跳过）**

- 自检 3：把 `fr1-smoke.json` 的一条 `toolCalls` 替换为 `find . -name SKILL.md -type f` ⇒ cmd-05 **exit 1**（`FAIL AC-2 内 SKILL.md 搜索类 bash 调用数 = 1（期望 0）`）；恢复原文件后 cmd-05 exit 0。
- 自检 4：从 `pi-source.json#changedFiles` 删去 `packages/coding-agent/src/core/tools/bash.ts` ⇒ cmd-06 **exit 1**（`FAIL 变更文件集不一致 rec=[…test/bash-default-timeout.test.ts] act=[…bash.ts,…test/…]`）；恢复后 cmd-06 exit 0。
- 两次恢复均**逐字节相同**（复原后 sha256 与变更前一致：`fr1-smoke.json`＝`5a31e040…501e`、`pi-source.json`＝`cb78a02f…330d`）；恢复后两条命令均复跑 exit 0。

## 6. 新增/修改的测试与证据产物

- KB 仓本节点新增：`change-requests/CR-2026-070/evidence/fr1-smoke.json`、`change-requests/CR-2026-070/test-report.md`、`change-requests/CR-2026-070/test-evidence/cmd-01..06.log`（后两类由 `crctl test` 生成，机器区不可改写）。
- multica 仓本次新增测试面：`server/internal/daemon/execenv/runtime_config_test.go` 内 `TestBriefSkills*` 系列断言（见 cmd-03／cmd-02）。
- Pi 侧测试文件（`packages/coding-agent/test/bash-default-timeout.test.ts`）属 CR worktree 集合之外的检出，按 `pi-source.json` 记录取证，不随本 CR 仓库提交。

## 7. 未覆盖风险与不适用说明

- **AC-6 的 daemon PID 子项 = N/A（有据）**：单元 B 的验收落在 Pi 工具进程（`createBashTool` 本地执行路径），`cmd-06` 只观察父/后代 PID 与既有 `killProcessTree` 路径；本 CR 不启停、不重启任何共享服务。
- **环境 1 依赖本地 CR 版 multica 构建**：运行中 daemon 由桌面应用以替换后的 `multica dev` 二进制拉起（安装目录二进制 2026-09-18 13:35、daemon pid 19760 于其后启动）。若桌面应用自动更新覆盖该二进制，`cmd-05` 的平台锚定面与 AC-4 的规则文本注入面需按 plan §5.3 重新基线；AC-4 的规则文本在场事实本 run 未复核（属环境 1 前置，已在 AC-4 节点下发 run 内实测）。
- **AC-12 不要求验证运行环境已升级**（按 `dep-1` 明文，判据只看交付 diff 的文件集合归属）；运行环境升级不在本 CR 交付面内。
- `runs[].observedAt` 取平台 `completed_at`（AC-2 `09:02:49Z`、AC-3 `09:07:54Z`、AC-4 `09:14:14Z`），为 RFC3339 UTC；`multica agent tasks` 的 `result.tool_calls` 只在 run 结束时落盘，故 AC-4 采集 run 内不存在执行对账的窗口，对账与登记由本实施 run 承担（TASK-04 §3.1 的执行主体与窗口更正）。

## 8. 下一步建议

本报告 `status=pass` ⇒ 进入 `review-code`（该节点先跑 `workspace-freshness`，gate＝`review-start`）。FR-1／FR-2／FR-3 三个 FR 的验收证据均已齐备，回修轮次为 0（`write-test-report` 首轮 pass）。
