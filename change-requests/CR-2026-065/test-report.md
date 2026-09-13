---
cr: CR-2026-065
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-13T18:56:51+08:00"
command-digest: df94c863f10f5ebbac01d0774a84994c3843f7f2de946f7459d60421e41ebe51
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/test/suite-gate.mjs, --run, --max-runtime-ms, 1200000]
    timeout-seconds: 1500
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-065/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-name-pattern, "CR-2026-037 Prompt 采纳", --test-name-pattern, "checkpoint T05 contract", --test-name-pattern, "TASK-06 ⑤", --test-name-pattern, "CR-2026-042 静态合同：已知 Skill 越界文本零命中", skills/shared/crctl/scripts/test/crctl.test.mjs, skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-065/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-reporter=dot", --test-name-pattern, "TASK-01 RED-7", --test-name-pattern, CR-2026-065, skills/shared/crctl/scripts/test/archive-tx.test.mjs, skills/shared/crctl/scripts/test/trace-outbox.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-065/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),cp=require('child_process'),path=require('path');const T='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-065';const BASE='dddd0ad63fb79bd7608314b4553f30e8ce7b7289';const NL=String.fromCharCode(10);const bad=[];const rp=path.join(T,'skills/shared/crctl/scripts/test/gate-registry.json');let reg=null;if(!fs.existsSync(rp)){bad.push('gate-registry.json 缺失');}else{try{reg=JSON.parse(fs.readFileSync(rp,'utf8'));}catch(e){bad.push('gate-registry.json 非法 JSON');}}if(reg!==null){if(reg.schema!=='crctl-suite-gate/v1'){bad.push('registry schema 不符: '+reg.schema);}const files=fs.readdirSync(path.join(T,'skills/shared/crctl/scripts/test')).filter(f=>f.endsWith('.test.mjs')).sort();let mf=[];if(reg.manifest&&reg.manifest.files){mf=reg.manifest.files;}if(JSON.stringify([...mf].sort())!==JSON.stringify(files)){bad.push('manifest.files 与实际 '+files.length+' 个测试文件集合不等: '+mf.length);}let cs={};if(reg.manifest&&reg.manifest.cases){cs=reg.manifest.cases;}if(JSON.stringify(Object.keys(cs).sort())!==JSON.stringify(files)){bad.push('manifest.cases 键集与文件集合不等');}for(const f of Object.keys(cs)){if(!(Number.isInteger(cs[f])&&cs[f]>0)){bad.push('manifest.cases['+f+'] 非正整数');}}let sm={};if(reg.stateMachine){sm=reg.stateMachine;}if(!Array.isArray(sm.namedStates)){bad.push('stateMachine.namedStates 非数组');}else if(sm.namedStates.length!==15){bad.push('stateMachine.namedStates 数量 != 15');}if(!Array.isArray(sm.transitions)){bad.push('stateMachine.transitions 非数组');}else if(sm.transitions.length!==31){bad.push('stateMachine.transitions 数量 != 31');}let wc={};if(sm.wildcards){wc=sm.wildcards;}if(!Array.isArray(wc['any-active'])){bad.push('stateMachine.wildcards.any-active 非数组');}else if(wc['any-active'].length!==12){bad.push('stateMachine.wildcards.any-active 目标数 != 12');}if(!Array.isArray(reg.exceptions)){bad.push('exceptions 非数组');}else if(reg.exceptions.length!==0){bad.push('exceptions 不是显式空数组');}}const r=cp.spawnSync(process.execPath,[T+'/skills/shared/crctl/scripts/crctl.mjs','git','diff','--name-only',BASE,'--cwd',T],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');}else{const out=String(r.stdout==null?'':r.stdout).split(NL);const b=out.findIndex(l=>l.trim()==='{');const changed=out.slice(0,b<0?out.length:b).map(s=>s.trim()).filter(Boolean);console.log('FR-15 diff paths = '+changed.length);changed.forEach(p=>console.log('  '+p));const okPath=p=>{if(p.startsWith('skills/shared/crctl/scripts/test/')){return true;}if(p==='skills/shared/crctl/scripts/lib/outbox-contract.mjs'){return true;}if(p==='skills/shared/crctl/scripts/crctl.mjs'){return true;}if(p==='.github/workflows/crctl-ci.yml'){return true;}return false;};for(const p of changed){if(!okPath(p)){bad.push('越界改动: '+p);}}}if(bad.length>0){console.log('registry-scope-audit failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);}console.log('registry-scope-audit failures = 0');"]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-065/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs'),path=require('path');const EV='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-065/change-requests/CR-2026-065/test-evidence';const bad=[];const need=(p,label)=>{if(fs.existsSync(p)){return;}bad.push('缺失 '+label);};const readJson=p=>{try{return JSON.parse(fs.readFileSync(p,'utf8'));}catch(e){return null;}};const pairs=[['NC-1','inject','block'],['NC-1','restore','pass'],['NC-2','inject','block'],['NC-2','restore','pass'],['NC-3','inject','block'],['NC-3','restore','pass']];for(const t of pairs){const p=path.join(EV,'drift',t[0]+'-'+t[1]+'.json');need(p,t[0]+' '+t[1]);const d=readJson(p);if(d===null){bad.push(t[0]+' '+t[1]+' 非法 JSON');}else{if(d.verdict!==t[2]){bad.push(t[0]+' '+t[1]+' verdict != '+t[2]);}if(d.converged!==true){bad.push(t[0]+' '+t[1]+' converged != true');}if(!Array.isArray(d.failures)){bad.push(t[0]+' '+t[1]+' 缺 failures');}else{if(t[1]==='inject'&&d.failures.length===0){bad.push(t[0]+' inject 失败集合为空');}if(t[1]==='restore'&&d.failures.length!==0){bad.push(t[0]+' restore 失败集合非空');}}}}for(const n of ['default-run1','default-run2','conc2-run1','conc2-run2','conc1-run1','conc1-run2']){need(path.join(EV,'concurrency',n+'.json'),'收敛实测 '+n);}need(path.join(EV,'NC-summary.md'),'NC-summary.md');if(bad.length>0){console.log('evidence-form-audit failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);}console.log('evidence-form-audit failures = 0');"]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-065/test-evidence/cmd-05.log
---

# 测试报告 · CR-2026-065

<!-- crctl:analysis-below -->

## 分析段 · CR-2026-065（`write-test-report` node-7）

> 本段只写在机器区下方的分析标记之后；`generated-by: crctl-test` 之上的机器区**未改动一个字节**，`traceability.yml` / `review-loop.yml` 全部由 `crctl test` 独占写入。
> 证据命令集 = `plan.md` §6.2 证据命令表 5 行**逐字转录**（`cr-test-plan/v1`，token 数 4/12/8/2/2），不重排、不补 flag、不改 `--test-reporter=dot`；本轮 `crctl test` 只执行 **1 次**，未重跑、未删命令、未放宽任何 AC。

### A. 执行事实（第一手）

| 项 | 值 |
|---|---|
| 调用 | `crctl test CR-2026-065 --plan .crctl/tmp/test-plan.json --workspace <KB worktree>`（crctl 取 tools worktree） |
| 起止 / 墙钟 | `2026-09-13 18:42:26 +08:00` → `18:56:51 +08:00` = **865 s**；node-7 预算 1200 s，余量 ≈ 335 s，**未触发超时** |
| 结果 | `status=pass` / `attempt=1` / `commandDigest=df94c863f10f5ebbac01d0774a84994c3843f7f2de946f7459d60421e41ebe51` / `changed=true`；输出无 blockers（5/5 命令 exit 0） |
| 写入面 | journal `phase=complete`，entries = `test-report.md` + `traceability.yml` + `review-loop.yml` + `test-evidence/cmd-01…05.log`（8 条） |
| 测试源绑定 | 执行前 tools HEAD = `52fa8d7a2209e0873b4b98f1c3d7db240300f1ce`（clean）；KB HEAD = `4a5cf168…`（clean） |
| 转录校验 | 表内 cells → `JSON.parse` → `JSON.stringify(args)` **逐条往返相等**（21 个 token 全等）；`plan.md` §6.2 注③ 口径复核：cmd-04/cmd-05 脚本体 `"`/`\`/`\|`/换行 = 0 |
| 评审预算 | `review-loop.yml`：`write-test-report` `{current-cycle:1, current-attempt:1}`（1/3） |

**执行偏差登记（1 条，如实）**：派单文字要求计划写到 **tools worktree** 的 `.crctl/tmp/test-plan.json`；实测 tools worktree **不存在 `.crctl/`**，而 `crctl test` 对 `--plan` 的定位是 `path.resolve(workspace, planPath)` 且必须落在 `<workspace>/.crctl/tmp` 之内（`skills/shared/crctl/scripts/lib/workspace-transactions.mjs:4198`、`:4206-4210`）。故计划实际落在 **KB worktree** `…/.rayai-worktrees/knowledge-base/requirement/CR-2026-065/.crctl/tmp/test-plan.json`（6235 B；被 `.crctl/.gitignore` 的 `*` 排除，不入 Git）。`--plan` 参数值仍是逐字相对路径 `.crctl/tmp/test-plan.json`；该偏差只涉及「哪个 worktree 的 `.crctl/tmp`」，不影响证据内容与 `commandDigest`（后者只由 5 条命令的 canonical subject 决定）。

### B. 逐条证据解读（`cmd-NN` ↔ `plan.md` 覆盖矩阵「验收证据」列）

| 证据ID | 命令要点（逐字 args 摘要） | 实测 | 覆盖的 plan 行 |
|---|---|---|---|
| cmd-01 | `suite-gate.mjs --run --max-runtime-ms 1200000`（timeout 1500 s） | **exit 0** / 822,652 ms / `verdict=pass` / `converged=true` / `failures=[]` / `files_executed=21` / `cases_executed=576` / `skipped_file_level=0` / `observer=tap-per-file` / `command=node --test --test-reporter=tap <21 files> (pool=15, availableParallelism=16)` | §6.1 FR-11/FR-12/FR-14/FR-16/FR-17；§7 AC-01/AC-10/AC-11/AC-12/AC-14/AC-15 + 3 条业务闭环 |
| cmd-02 | `--test --test-reporter=dot` + 4 × `--test-name-pattern`（BR-1…BR-4 用例名） | **exit 0**，stdout `....`（4 个用例命中；基线 exit 1） | §6.1 FR-1…FR-7；§7 AC-02…AC-07 |
| cmd-03 | `--test --test-reporter=dot` + `TASK-01 RED-7` + `CR-2026-065`（archive-tx / trace-outbox） | **exit 0**，stdout `........`（8 个用例命中；基线 exit 1 / `EMIT_FAILED`） | §6.1 FR-8/FR-9/FR-10；§7 AC-08/AC-09 |
| cmd-04 | 登记面 schema + `stateMachine` 计数 + diff 白名单（`-e` 单参数） | **exit 0**：`FR-15 diff paths = 11`（全在白名单）、`registry-scope-audit failures = 0`（基线去实施前 = 9 条） | §6.1 FR-1/FR-3/FR-6/FR-15；§7 AC-02/AC-03/AC-13 |
| cmd-05 | 负控 + 收敛证据形态核对（`-e` 单参数，读 KB 绝对路径） | **exit 0**：`evidence-form-audit failures = 0`（基线 exit 1 / 17 项缺失登记，复算见 H-4） | §6.1 FR-13；§7 AC-06/AC-07/AC-09/AC-10/AC-11 + 业务闭环① |

**`cmd-NN` 全等机械核对（三方一致）**：`plan.md` §6.1（17 行 FR）「验收证据」列 token 集、§7（18 行 AC/业务闭环）「验收证据」列 token 集、机器区 5 条 `commands` 的 1-based 下标、`test-evidence/*.log` 文件名四者 **全等 = `{cmd-01, cmd-02, cmd-03, cmd-04, cmd-05}`**（逐行解析 + 集合比较，无静默降级）。

### C. cmd-01 机器判定面（15 字段逐项）

| 字段 | 实测 | 门槛（plan §5.1 第 2 条 / TASK-03 §4.2、TASK-04 §4.2） |
|---|---|---|
| `verdict` | `pass` | pass |
| `converged` | `true` | true |
| `exit_code` | `0` | 0 |
| `failures` | `[]` | 空 |
| `files_executed` | `21` | 21 |
| `files[]` | 21 条，`state` 全 `ok`（`failures: []`、`skipped_cases: 0`） | 恰 21 条且全 ok |
| `skipped_file_level` | `0` | 0 |
| `cases_executed` | `576` | > 0 |
| `observer` | `tap-per-file` | 非空 |
| `command` | `node --test --test-reporter=tap <21 files> (pool=15, availableParallelism=16)` | 与 `suite-gate.mjs` 常量一致（`CONCURRENCY = null`，本机 `availableParallelism()=16` ⇒ 池 = 15） |
| `checks[]` | 13 条 check code 全 `ok: true`（含 `SUITE_MANIFEST_CASE_DROP`、`EXCEPTION_EXPIRED`、`SUITE_NONCONVERGENCE`） | 无 check 复用例外，`exceptions=[]` |
| `registry` | `sha256=e642b97e6f610c99ba904fd395c8c637f5a695d3e8e79953bbff589fd486ab4c`、`exceptions_count=0` | 例外显式为空 |
| `platform` | `win32` / node `24.15.0` | B-4 修订后的机制前提（v24 单文件 TAP 顶层 plan ≡ 顶层结果行数） |
| `duration_ms` | `822,652`（基线整跑 894.8 s 同口径对比 → 缩短 ≈ 72 s；与 implement-code 期 default-run1 `783,450 ms` 同量级，抖动 ≈ +39 s） | 与 894.8 s 同口径 |

`cmd-01.log` 结构复核：`--- stdout ---` / `--- stderr ---` 标记**各恰好 1 次**；stdout = 15 字段 JSON（第 1–300 行）+ 6 行 `suite-gate:` 人类摘要；stderr 空；人类摘要用 `skipped_file_level=`（下划线形态，不命中冻结 skip 模式表）⇒ crctl 判定 `commands[].skipped = false` 与日志自洽。

### D. `files[].cases` ↔ `manifest.cases` 逐项对照（21/21 全等）

方法：解析 `test-evidence/cmd-01.log` 的 stdout JSON 与 `skills/shared/crctl/scripts/test/gate-registry.json#manifest.cases`，逐项比较（本轮 `manifest.cases` 为 TASK-04 刷新的终值）。

| 文件 | cases | manifest | | 文件 | cases | manifest |
|---|---|---|---|---|---|---|
| archive-tx.test.mjs | 24 | 24 | | pipeline-structure.test.mjs | 35 | 35 |
| check-agents-contract.test.mjs | 1 | 1 | | register-tx.test.mjs | 26 | 26 |
| check-skill-matrix.test.mjs | 8 | 8 | | test-cr.test.mjs | 27 | 27 |
| checkpoint-tx.test.mjs | 23 | 23 | | trace-outbox.test.mjs | 12 | 12 |
| contract-scan.test.mjs | 15 | 15 | | trace-semantic.test.mjs | 5 | 5 |
| crctl.test.mjs | 224 | 224 | | upgrade-check.test.mjs | 2 | 2 |
| durable-tx.test.mjs | 10 | 10 | | version-set.test.mjs | 12 | 12 |
| fault-harness.test.mjs | 8 | 8 | | workspace-freshness.test.mjs | 32 | 32 |
| lint-prompts.test.mjs | 38 | 38 | | workspace-resolver.test.mjs | 7 | 7 |
| merge-tx.test.mjs | 17 | 17 | | writeback-tx.test.mjs | 33 | 33 |
| | | | | yaml-subset.test.mjs | 17 | 17 |

合计：Σ`files[].cases` = **576** ≡ Σ`manifest.cases` = **576** ≡ `cases_executed` = **576**；不匹配项 **0**。刷新幅度（`2c84241` → `52fa8d7`）：初值 21 项中 20 项由 `1` 刷成实测值，`check-agents-contract.test.mjs` 终值仍为 `1`（该文件恰 1 个用例，非漏刷新）；值域全部满足「终值 ≥ 初值且为正整数」（TASK-04 §4.3）。

### E. TASK 验收覆盖矩阵（每条证据 → 验收条件）

| TASK | 验收条件 | 承载证据 | 实测 | 判定 |
|---|---|---|---|---|
| TASK-01 | ①`cmd-02` exit 0 | cmd-02 | exit 0 / 4 用例命中（BR-1、BR-2、BR-3、BR-4 各一） | ✅ |
| TASK-01 | ②`cmd-04` exit 0（registry schema / manifest / `namedStates=15` / `transitions=31` / `any-active=12` / `exceptions=[]`） | cmd-04 | exit 0 / `registry-scope-audit failures = 0` | ✅ |
| TASK-01 | ③负控自检（N-1 局部；正式全量注入证据归 TASK-04） | cmd-05 | `drift/NC-1-{inject,restore}.json` 形态正确（`block`/非空 vs `pass`/空，`converged=true`） | ✅ |
| TASK-01 | ④diff 面一览 + `zero_diff` 零 diff | cmd-04 + 补充观测 | 11 条路径全在白名单；`crctl git diff --name-only dddd0ad6 -- skills/shared/controlled-shell/rules.json dir-graph.yaml pipeline-templates` = **空** | ✅ |
| TASK-02 | ①`cmd-03` exit 0 | cmd-03 | exit 0 / 8 用例命中（RED-7 构造 A/B + `CR-2026-065` 前缀契约用例） | ✅ |
| TASK-02 | ②回归保护「同一漂移二次观测」（`detected_at` 语义不回归） | **cmd-01**（非 cmd-03，归属更正见 H-1） | `crctl.test.mjs` 224/224 用例 `state=ok`；用例实体在 `crctl.test.mjs:800`（`CR-2026-052 AC-11`） | ✅（归属如实报告） |
| TASK-02 | ③契约面自检（`lib/outbox-contract.mjs` 五导出 + 不变性） | cmd-03 + cmd-01 | `contract-scan.test.mjs` 15/15 用例 ok；`CR-2026-065` 契约用例绿 | ✅ |
| TASK-02 | ④diff 面自检（4 个允许路径 + 无 `SKILL.md` 改动） | cmd-04 | 11 条含 `outbox-contract.mjs` / `crctl.mjs` / `archive-tx.test.mjs` / `trace-outbox.test.mjs`；**无任何 `SKILL.md`** | ✅ |
| TASK-03 | ①`contract-scan` 窄跑（exit 0 + 命中清单 ≥ 4） | 补充观测（非 canonical 证据集） | exit 0；dot = 8 点；tap 逐名 **8 条**（≥ 4），含「合法片段判绿 / 无顶层 plan / plan 与结果行数矛盾 / 缩进栈不成对 / 诊断块 `...` 回归 / 归属自测 / 禁词自测 / 零写路径静态断言」 | ✅ |
| TASK-03 | ②`cmd-01` 全量（§C 全部门槛） | cmd-01 | 见 §C，10 项门槛全满足 | ✅ |
| TASK-03 | ③`cmd-04` exit 0 | cmd-04 | exit 0 | ✅ |
| TASK-03 | ④CI 步骤改动限于 `:109-111` | 补充观测（`crctl git diff --unified=0`） | `@@ -111 +111 @@` 单行替换（`--test-concurrency=2 …*.test.mjs` → `suite-gate.mjs --run`），**落在声明区间内**；`--stat` = `1 file changed, 1 insertion(+), 1 deletion(-)` | ✅ |
| TASK-03 | ⑤`sdd.md` 零改动 | 补充观测（digest + status） | `sha256(LF) = ecc1f90253ad28438bfc5ac20e7485b9c8dff57797d0805dadace5cd8917d62f` ≡ `review-annotations/sdd.yml#subject-sha256`；KB `status --short` 无 `sdd.md` | ✅ |
| TASK-04 | ①`cmd-05` exit 0（6 份 drift + 6 份 concurrency + `NC-summary.md`） | cmd-05 | exit 0 / `failures = 0` | ✅ |
| TASK-04 | ②`cmd-01` 最终池值 + `command` 与常量一致 | cmd-01 + 常量读 | `pool=15` ≡ `CONCURRENCY=null`（`max(1, availableParallelism()-1)`，本机 16 ⇒ 15） | ✅ |
| TASK-04 | ③`cmd-04` exit 0 + `manifest.cases` 终值 ≥ 初值 | cmd-04 + 逐项对照 | `manifest.cases` 全部正整数且 ≥ 初值；21/21 与 `files[].cases` 全等 | ✅ |
| TASK-04 | ④还原留痕（tools clean、注入物不在 diff） | 补充观测 | tools `status --short` = 空；11 条 diff 不含 `dir-graph.yaml` / `SKILL.md` | ✅ |

### F. 新增 / 修改交付文件（相对登记基线 `dddd0ad6`，11 条 / +1410 −61）

| 类别 | 路径 | 幅度 |
|---|---|---|
| 新增（4） | `skills/shared/crctl/scripts/test/suite-gate.mjs` | +568 |
|  | `skills/shared/crctl/scripts/test/gate-registry.json` | +244 |
|  | `skills/shared/crctl/scripts/test/assertion-sources.mjs` | +98 |
|  | `skills/shared/crctl/scripts/lib/outbox-contract.mjs` | +62 |
| 测试修改（4） | `test/archive-tx.test.mjs`、`test/trace-outbox.test.mjs`、`test/checkpoint-tx.test.mjs`、`test/crctl.test.mjs` | ±（见 `cmd-04` 输出的 11 条清单） |
|  | `test/contract-scan.test.mjs` | 既有文件新增静态断言与解析/归属自测 |
| 产品面最小改写（1） | `skills/shared/crctl/scripts/crctl.mjs` | +36/−… |
| CI（1） | `.github/workflows/crctl-ci.yml` | 1 行替换（`:111`） |

测试文件总数仍为 **21 个 `*.test.mjs`**（无新增/无删除，`cmd-04` 的集合相等断言 + `cmd-01` 的 `files_executed=21` 双向承载）；无新增依赖、无新增 crctl 子命令。

### G. 未覆盖风险与残余项（不得空白通过）

1. **AC-12 的「到期例外 → 门禁红」在证据面无观测点（保留）**：交付态 `exceptions: []`，`EXCEPTION_EXPIRED` 不可观测（`checks[].EXCEPTION_EXPIRED.ok=true` 只说明「当前无到期例外」，不等于「到期即红」被证明）。**可复跑配方**（本轮不执行：node-7 不能重跑注入，且会污染 `cmd-01` 证据）：① 临时向 `gate-registry.json#exceptions` 追加一条 `{id: <稳定标识>, kind: suite-nonconvergence, reason: <原因>, owner: Ray, expires: <过去时点 ISO-8601 带偏移>}` → ② `node skills/shared/crctl/scripts/test/suite-gate.mjs --run --max-runtime-ms 1200000` 应 **红**（`checks[].EXCEPTION_EXPIRED.ok=false`、`failures` 含该 code、退出码非 0）→ ③ `crctl git checkout -- skills/shared/crctl/scripts/test/gate-registry.json` 还原 → ④ `crctl git status --short` 空。取证强度建议由 `review-code` 判定是否需要在本 CR 内补一次。
2. **`plan` §6.1 FR-8 / §7 AC-08 把 「drift-audit 不回归」的证据归属写为 `cmd-03`，与实测不符（如实报告，不改 plan 正文）**：该用例实体在 `skills/shared/crctl/scripts/test/crctl.test.mjs:800`（`CR-2026-052 AC-11：同一漂移二次观测…`），`cmd-03` 的文件集（archive-tx / trace-outbox）与 pattern 集都不含它 ⇒ **真实承载者 = `cmd-01`**（全量 21 文件，`crctl.test.mjs` 224/224 ok）。故 AC-08 的「drift-audit 不回归」证据应读作 `cmd-01`；`cmd-03` 实际只承载构造 A/B 与 `CR-2026-065` 契约用例。
3. **窄跑证据的强度：`cmd-02` = 4 点、`cmd-03` = 8 点，但退出码无法区分「命中 4/8 条」与「命中 0 条」**（Node 无命中时同样 exit 0）。本轮以 dot 点数（第一手计数）作为锚点；若要更强的机械锚，应改用 tap 逐名（如 TASK-03 §4.1 对 `contract-scan` 的窄跑已做）。此外该面依赖 Node 对**重复 `--test-name-pattern` 取并集**的语义（plan §6.2 注②），本机 v24.15.0 实测成立（4 点 + 8 点）；运行时语义若变化会静默改变命中集合，属残余依赖。
4. **负控（N-1/N-2/N-3）证据是 `implement-code` 期产物，本轮只做形态核对**：`cmd-05` 只读 `verdict` / `converged` / `failures[]`，不重放注入 ⇒ 「注入确实发生过」的强度取决于 TASK-04 期的逐次整跑记录（`drift/NC-*` 与 `concurrency/*`），本轮未重跑（预算 + 不污染证据集）。
5. **机器区未发布 `sourceRevision` / `logSha256`**（`SKILL.md` 文本提到 resultFacts）：本版 crctl 的机器区 per-command 字段固定为 `repo/cwd/executable/args/timeout-seconds/exit-code/signal/timed-out/started/skipped/log`（`lib/workspace-transactions.mjs:4103-4124`）。证据绑定面实际为 repo+worktree（`52fa8d7` clean）+ 真实退出码 + `log` 路径 + `commandDigest`。属 crctl 既有形态、在本 CR `scope_in` 之外，登记为观察项，**不作为本报告的 block**。
6. **`cmd-04` / `cmd-05` 的 args 内含硬编码绝对路径与基线 SHA**（`dddd0ad6…`、两个 worktree 绝对路径）：换机、换 worktree 路径或基线前移都会使这两条命令语义失效（脚本会照旧判绿或全判缺失）。这是 `plan.md` §6.2 注④/注⑧ 的既定口径（正斜杠化 + KB 绝对路径），本轮实测通过；仅作残余项登记。
7. **lint / build 步骤：不适用**——本 CR 无 lint/build 门禁（CI 的 `contracts` job 门禁面 = 全量测试步骤 `:111`），`zero_diff` 面不含任何 lint 配置；证据集按 `plan.md` §6.2 只声明测试面。

### H. 派单 5 条非阻塞项逐条处置

| # | 内容 | 处置 | 实测依据 |
|---|---|---|---|
| H-1 | drift-audit 不回归被归给 `cmd-03`，真实载体在 `crctl.test.mjs:800`（只由 `cmd-01` 承载） | **已处理（如实报告归属，不改 plan 正文）** | 见 §G-2；`cmd-01` `crctl.test.mjs` 224/224 ok |
| H-2 | AC-12「构造到期例外 → 门禁红」证据面缺命令承载 | **保留（本轮不可执行）** | 见 §G-1（含可复跑配方与「不可观测」事实：`exceptions=[]`） |
| H-3 | `manifest.cases` 全为 1 时「只查正整数」会漏刷新 | **已由本轮 `cmd-01` 逐项对照承载** | 见 §D（21/21 全等、Σ 576 ≡ `cases_executed`；`SUITE_MANIFEST_CASE_DROP` check ok） |
| H-4 | `plan` 记 `cmd-05 = 17 项缺失`，复评为 19 项 | **以实测为准报告**：交付态 **0 项失败**；基线态按 `cmd-05` 同一脚本口径复算 = **19**（13 条「缺失 X」+ 6 条「X 非法 JSON」——`readJson` 对不存在的文件返回 `null` 亦计入），与复评的 19 一致，`plan` 的 17 属欠计 2 条 | 只读复算（`EV` 指向不存在的目录，无副作用） |
| H-5 | SDD §4.6 写 `test-evidence/cmd-NN.log`，plan §6.4 / TASK-04 用 `test-evidence/drift/NC-*` | **按 TASK-04 现状执行并登记命名映射（不改 SDD）** | 见下方映射表 |

**命名映射（H-5，本轮实测路径）**

| 命名面 | 实际路径 | 承载物 | 谁核对 |
|---|---|---|---|
| canonical 命令日志 | `test-evidence/cmd-01…05.log` | `crctl test` 发布的 5 条命令 stdout/stderr | 机器区 `commands[].log`、`cmd-NN` 下标 |
| 负控注入证据 | `test-evidence/drift/NC-{1,2,3}-{inject,restore}.json`（6 份） | 三类漂移「注入红 / 还原绿」整跑记录 | `cmd-05` 形态核对 |
| 并发收敛实测 | `test-evidence/concurrency/{default,conc2,conc1}-run{1,2}.json`（6 份） | 3 候选 × 2 次连续整跑 | `cmd-05` 存在性核对 |
| 负控/收敛汇总 | `test-evidence/NC-summary.md` | 三类注入与三候选的耗时/收敛/结论表 | `cmd-05` 存在性核对 |

### I. 下一步建议

1. `test-report.md#status = pass` ⇒ 走 `push-progress` 一次（`crctl checkpoint CR-2026-065 --message 代码与测试证据`）把 KB 写面（报告 + 5 份日志 + 账本投影）与 tools `52fa8d7` 一起 checkpoint，再做 `workspace-freshness gate=review-start`。
2. `review-code`（独立 reviewer）优先复核：§D 的逐项对照是否足以替代「manifest 漏刷新」缺口（H-3）、§G-1 的 AC-12 观测缺口是否需要在 CR 内补一次注入（H-2）、§G-2 的 AC-08 证据归属更正是否需回改 plan 正文（本轮未改）。
3. 若 `review-code` 判 `block`，回修面只应是上述 §G 残余项，不涉及本报告机器区（`status=pass` 为 `crctl` 按真实退出码判定，不得手改）。
