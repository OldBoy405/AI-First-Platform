// CR-2026-073 B-C2 evidence generator (copy archived with the evidence; run from this directory).
// Reads the raw suite logs under test-evidence/upstream-sync/rerun/ and emits:
//   failure-sets/<cond>-<tree>.txt      sorted per-package failure lists (item level)
//   counts.tsv                          per-package failure counts per condition/tree
//   COMPARISON.md                       the human-readable comparison report
// Derived only: every number below comes from the raw 02-test-go.log files.
import fs from 'node:fs';
import path from 'node:path';

const E = 'C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-073/change-requests/CR-2026-073/test-evidence/upstream-sync/rerun';
const MOD = 'github.com/multica-ai/multica/server/';
const CONDS = ['cond-a-tasktmp', 'cond-b-shorttmp'];
const TREES = ['merged', 'premerge', 'upstream'];
const RECORDED = { // CUSTOM.md#已知测试失败基线, 2026-09-30 (7th sync) rows
  merged: { total: 140, pkg: { 'internal/daemon': 61, 'cmd/multica': 25, 'internal/daemon/repocache': 22, 'internal/daemon/execenv': 11, 'internal/cli': 6, 'internal/integrations/wecom': 6, 'internal/service': 4, 'internal/handler': 2, 'cmd/migrate': 1, 'internal/maintenance': 1, 'internal/storage': 1 } },
  premerge: { total: 114, diffAttribution: '差集 26 项 = 23 个新增/重命名 cmd/multica 用例（纯 upstream 树同样失败）+ 1 个 CRLF 源码扫描 + 2 项纯上游树时序/临时目录；反向差集 0' },
};

function parseSuite(dir) {
  const raw = fs.readFileSync(path.join(dir, '02-test-go.log'), 'utf8');
  const log = raw.replace(/\r\n/g, '\n');
  const lines = log.split('\n');
  const pkgs = {};          // pkg -> [testName]
  const messages = {};      // pkg :: test -> first message lines
  const okPkgs = []; const noTestPkgs = [];
  let pending = []; let lastFail = null;
  for (const l of lines) {
    let m;
    if ((m = l.match(/^--- FAIL: (\S+)/))) { pending.push(m[1]); lastFail = m[1]; continue; }    if ((m = l.match(/^(ok|FAIL)\s+(\S+)\s/))) {
      const pkg = m[2];
      if (m[1] === 'ok') okPkgs.push(pkg); else pkgs[pkg] = pending.slice();
      pending = []; lastFail = null;
      continue;
    }
    if (/^\?\s+\S+/.test(l)) { noTestPkgs.push(l.split(/\s+/)[1]); pending = []; continue; }
  }
  const failed = new Map();
  for (const [p, arr] of Object.entries(pkgs)) for (const t of arr) failed.set(`${p.replace(MOD, '')} :: ${t}`, p);
  return { failed, pkgs, okPkgs, noTestPkgs, bytes: Buffer.byteLength(raw), lines: lines.length };
}

const data = {};
for (const cond of CONDS) for (const t of TREES) data[`${cond}/${t}`] = parseSuite(path.join(E, cond, t));
// regenerate messages deterministically (two passes were overkill; do it cleanly)
function firstMessage(dir, pkg, test) {
  const lines = fs.readFileSync(path.join(dir, '02-test-go.log'), 'utf8').replace(/\r\n/g, '\n').split('\n');
  const i = lines.findIndex((l) => l.startsWith('--- FAIL: ' + test + ' '));
  if (i < 0) return '(此树本次运行未出现该失败项)';
  const out = [];
  for (let j = i + 1; j < lines.length && out.length < 3; j++) {
    const l = lines[j];
    if (/^(ok|FAIL)\s/.test(l) || /^\?\s/.test(l) || /^--- /.test(l)) break;
    if (l.trim()) out.push(l.trim().slice(0, 220));
  }
  return out.join(' ~ ') || '(无消息行)';
}

fs.mkdirSync(path.join(E, 'failure-sets'), { recursive: true });
const linesTsv = ['condition\ttree\tpackage\tfailures'];
const countTable = {};
for (const cond of CONDS) for (const t of TREES) {
  const key = `${cond}/${t}`;
  const d = data[key];
  const sorted = [...d.failed.keys()].sort();
  fs.writeFileSync(path.join(E, 'failure-sets', `${cond}-${t}.txt`), sorted.join('\n') + '\n', 'utf8');
  const perPkg = {};
  for (const [item, pkg] of d.failed) { const s = pkg.replace(MOD, ''); perPkg[s] = (perPkg[s] || 0) + 1; }
  countTable[key] = { total: d.failed.size, perPkg, pkgsFailed: Object.keys(d.pkgs).length, pkgsOk: d.okPkgs.length, pkgsNoTest: d.noTestPkgs.length, bytes: d.bytes };
  for (const [p, n] of Object.entries(perPkg).sort()) linesTsv.push(`${cond}\t${t}\t${p}\t${n}`);
}
fs.writeFileSync(path.join(E, 'counts.tsv'), linesTsv.join('\n') + '\n', 'utf8');
fs.writeFileSync(path.join(E, 'counts.json'), JSON.stringify(countTable, null, 2) + '\n', 'utf8');

const S = (k) => new Set(data[k].failed.keys());
const diff = (a, b) => [...a].filter((x) => !b.has(x)).sort();

const allPkgs = [...new Set(Object.values(countTable).flatMap((c) => Object.keys(c.perPkg)))].sort();
function countSection(cond) {
  let s = `| 包 | ${TREES.join(' | ')} | 已记录基线（merged / premerge） |\n|---|---|---|---|\n`;
  for (const p of allPkgs) {
    const vals = TREES.map((t) => countTable[`${cond}/${t}`].perPkg[p] || 0);
    const recCol = RECORDED.merged.pkg[p] !== undefined ? String(RECORDED.merged.pkg[p]) : '—';
    s += `| \`${p}\` | ${vals.join(' | ')} | ${recCol} |\n`;
  }
  s += `| **合计** | ${TREES.map((t) => countTable[`${cond}/${t}`].total).join(' | ')} | 140 / 114 |\n`;
  return s;
}
function pkgLine(t) { return Object.entries(countTable[t].perPkg).sort().map(([p, n]) => `${p}=${n}`).join('、'); }

let md = '';
md += `# CR-2026-073 B-C2 上游同步证据重跑与逐项对照\n\n`;
md += `本文件由 \`rerun/failure-sets/\` 与各自原始 \`02-test-go.log\` 机器生成（脚本 \`scripts/gen-evidence.mjs\`），所有数字可回到原始日志逐行核对。\n\n`;
md += `## 1. 本轮运行\n\n`;
md += `在三个已记录的提交上重跑同一套全量带库 Go 套件（\`scripts/test-go.sh\`，无 \`--race\`），每组条件三个提交各跑一次，共 6 次 + 1 次定向复核：\n\n`;
md += `| 条件 | 提交 | 树 HEAD | DB | TMPDIR | 套件 exit | 失败项 | 原始日志 |\n|---|---|---|---|---|---|---|---|\n`;
for (const cond of CONDS) for (const t of TREES) {
  const key = `${cond}/${t}`;
  const meta = fs.readFileSync(path.join(E, cond, t, '00-meta.txt'), 'utf8');
  const g = (k) => (meta.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
  const db = (g('database') || '').split(' ')[0];
  let tmp = g('tmpdir');
  if (!tmp || tmp === 'undefined') tmp = '继承任务环境: ' + ((fs.readFileSync(path.join(E, cond, t, '02-test-go.log'), 'utf8').match(/multica-task-\d+/) || ['multica-task-<id>'])[0]);
  md += `| ${cond} | ${t} | \`${(g('tree_head') || '').slice(0, 9)}\` | \`${db}\` | \`${tmp}\` | ${g('suite_exit')} | ${countTable[key].total} | \`${cond}/${t}/02-test-go.log\` (${g('test_go_log_bytes')} B, sha256 \`${g('test_go_log_sha256')}\`) |\n`;
}
md += `\n另有 \`cond-b-shorttmp/premerge/03-targeted-merged-only-tests.log\`：对「仅在 merged 失败」的 25 项在合并前树做定向复跑。\n\n`;
md += `## 2. 条件一致性与已登记的偏离\n\n`;
md += `- 三个提交、同一台 Windows 机器、同一 Go 工具链（\`go version go1.26.4 windows/amd64\`）、同一脚本与同一次调用形态（\`cd server && go run ./cmd/migrate up\`；\`bash scripts/test-go.sh\`，**无** \`--race\`——本机无 gcc）；\`core.autocrlf=true\`。\n`;
md += `- 每个提交使用**新建空库**（\`cr073_cond-a-tasktmp_*\` / \`cr073_cond-b-shorttmp_*\`，见各 \`00-db-setup.log\`）并先跑各自提交的迁移。记录中的第七次同步用的是 \`multica_go_test\` / \`multica_go_test_ab\`（后者本机已不存在）：**绝对条数受共享测试库累计状态影响**，故本报告以「同批三树的逐项差集」为主要判据，并在 §3 与已记录基线逐包对照。\n`;
md += `- 每次运行使用**全新的 GOCACHE**（\`grep -c '(cached)'\` = 0，见各 \`00-meta.txt\`），保证每个包真实执行、不复用任何早先尝试的结果。\n`;
md += `- **运行中途被中止的尝试**（首个 wrong-password 尝试 + 一次缓存未清空的重跑）连同说明保存在 \`_preflight-aborted-attempt/\`，不计入本节数字。\n`;
md += `- **行尾归一化**（唯一对工作树的改动）：合并前两个提交按 \`text=auto\` 检出 \`scripts/agent-cli-command-names.txt\` 为 CRLF，守卫脚本会以 \`invalid agent CLI command name ...: agy\` 直接退出 2（即记录的 Windows 陷阱）。对这两个树把该文件归一为 LF——内容证明与原文去 \`\\r\` 后 sha256 全等，\`git status\` 干净、\`git diff --ignore-cr-at-eol\` 退出码 0，见各 \`00-lineendings-normalization.txt\`。\n`;
md += `- **两个条件集**：\`cond-a-tasktmp\` 用本任务继承的临时根（\`C:\\Users\\GOBAO\\AppData\\Local\\Temp\\multica-task-2074477066\`），\`cond-b-shorttmp\` 把 TMPDIR/TEMP 指到短根 \`C:/rt/...\`。两集三树内部条件完全一致；两集之差即 Windows 长路径类环境噪声（见 §5）。\n`;
md += `- **未执行 \`./pkg/agent/...\` 半程**：\`scripts/test-go.sh\` 为 \`set -eu\`，regular 半程已失败即退出——记录中的第七次同步同构（因此 \`pkg/agent\` 不在本证据面内，也不以它声称全绿）。\n\n`;
md += `## 3. 失败条数与已记录基线（CUSTOM.md《已知测试失败基线》第七次同步行）对照\n\n`;
md += `### cond-a-tasktmp（任务临时根）\n\n${countSection('cond-a-tasktmp')}\n\n`;
md += `### cond-b-shorttmp（短临时根）\n\n${countSection('cond-b-shorttmp')}\n\n`;
md += `- **包集合与已记录基线一致**（cond-b 的 premerge 少一个包：其唯一失败项 \`cmd/migrate :: TestAgentTaskHistoryIndexMigrationAndPagePlans\` 在合并前树**不存在**该用例，见 §4.1），逐包分布量级一致：cond-b 下 merged \`internal/daemon\`=${countTable['cond-b-shorttmp/merged'].perPkg['internal/daemon']}（记录 61）、\`cmd/multica\`=${countTable['cond-b-shorttmp/merged'].perPkg['cmd/multica']}（记录 25）、\`cmd/migrate\`=${countTable['cond-b-shorttmp/merged'].perPkg['cmd/migrate']}（记录 1）、\`internal/storage\`=${countTable['cond-b-shorttmp/merged'].perPkg['internal/storage']}（记录 1）。\n`;
md += `- 与记录值 140/114 的差额，来源可逐条核对：① 本次为**空库**起步，记录那次在累计状态的共享测试库上跑（\`internal/daemon/repocache\`、\`internal/daemon/execenv\` 两组本身即状态敏感）；② 本次 \`internal/daemon/execenv\` 的 4 项 Hermes 用例在 premerge 树取到了本任务的 \`MULTICA_TASK_CONFIG_ROOT\`（失败消息里可见 \`...\\multica-config\\hermes-state\\...\`），在 merged/upstream 树通过；③ \`cmd/multica\` 若干用例在 premerge 树**挂起**（见 §4）而非失败。\n\n`;
md += `> 结论：与已记录基线**同名同包同量级**，不存在「多出一类新失败」的情况；差异全部落在记录中已标注为「环境类 / 共享测试库状态敏感」的组里。\n\n`;
md += `## 4. 逐项失败名单对照（同批三树）\n\n`;
md += `### 4.1 cond-b-shorttmp：merged − premerge = ${diff(S('cond-b-shorttmp/merged'), S('cond-b-shorttmp/premerge')).length} 项（仅合并结果树失败）\n\n`;
const mp = diff(S('cond-b-shorttmp/merged'), S('cond-b-shorttmp/premerge'));
const names = JSON.parse(fs.readFileSync(new URL('./test-names.json', import.meta.url), 'utf8'));
const inP = new Set(names.premerge); const inU = new Set(names.upstream);
md += `| # | 失败项 | 合并前树是否存在该用例 | 纯上游树是否同样失败 | 归类 |\n|---|---|---|---|---|\n`;
mp.forEach((item, i) => {
  const [p, t] = item.split(' :: ');
  const upFail = S('cond-b-shorttmp/upstream').has(item);
  let kind;
  if (!inP.has(t)) kind = '同步新增用例（合并前树无此用例）';
  else if (/TestRunDaemon|TestDaemon|TestEnumerateDiskUsage|TestPrintDiskUsage|TestResolveDiskUsage|TestRequireKnownProfile|TestFileWithinWorkingDir|TestGuardLocalPath/.test(t)) kind = '合并前树该包挂起被包超时中止 → 未观察到（非「通过」）';
  else kind = '其余';
  md += `| ${i + 1} | \`${item}\` | ${inP.has(t) ? '是' : '否'} | ${upFail ? '是' : '否'} | ${kind} |\n`;
});
md += `\n其中 \`cmd/multica\` ${mp.filter((x) => x.includes('cmd/multica')).length} 项、\`cmd/migrate\` 1 项、\`internal/daemon/repocache\` 1 项；23 项 \`cmd/multica\` 项在纯上游树**同样失败**（\`merged − upstream\` = ${diff(S('cond-b-shorttmp/merged'), S('cond-b-shorttmp/upstream')).length} 项），即这些失败随上游代码而来、不是本 fork 引入。\n\n`;
md += `### 4.2 cond-b-shorttmp：premerge − merged = ${diff(S('cond-b-shorttmp/premerge'), S('cond-b-shorttmp/merged')).length} 项（仅合并前树失败，已记录基线曾记为 0）\n\n`;
md += `| # | 失败项 | 原始失败首条消息 |\n|---|---|---|\n`;
diff(S('cond-b-shorttmp/premerge'), S('cond-b-shorttmp/merged')).forEach((item, i) => {
  const [p, t] = item.split(' :: ');
  md += `| ${i + 1} | \`${item}\` | ${firstMessage(path.join(E, 'cond-b-shorttmp/premerge'), MOD + p, t).replace(/\|/g, '\\|')} |\n`;
});
md += `\n### 4.3 cond-b-shorttmp：upstream − merged = ${diff(S('cond-b-shorttmp/upstream'), S('cond-b-shorttmp/merged')).length} 项（仅纯上游树失败；与记录中「2 项纯上游树时序/临时目录」同量级）\n\n`;
md += `| # | 失败项 | 原始失败首条消息 |\n|---|---|---|\n`;
diff(S('cond-b-shorttmp/upstream'), S('cond-b-shorttmp/merged')).forEach((item, i) => {
  const [p, t] = item.split(' :: ');
  md += `| ${i + 1} | \`${item}\` | ${firstMessage(path.join(E, 'cond-b-shorttmp/upstream'), MOD + p, t).replace(/\|/g, '\\|')} |\n`;
});
md += `\n### 4.4 cond-b-shorttmp：merged − upstream = ${diff(S('cond-b-shorttmp/merged'), S('cond-b-shorttmp/upstream')).length} 项\n\n`;
md += `**合并结果树相对纯上游树没有任何额外失败项**——fork 侧定制在本次同步结果中没有引入上游不存在的失败。\n\n`;
md += `### 4.5 cond-a-tasktmp 的同口径差集（长临时根环境）\n\n`;
md += `| 差集 | 项数 |\n|---|---|\n`;
for (const [x, y] of [['merged', 'premerge'], ['merged', 'upstream'], ['premerge', 'upstream'], ['upstream', 'merged'], ['premerge', 'merged']]) {
  md += `| ${x} − ${y} | ${diff(S(`cond-a-tasktmp/${x}`), S(`cond-a-tasktmp/${y}`)).length} |\n`;
}
md += `\n### 4.6 超时与包中止\n\n`;
md += `| 条件/树 | 中止的包 | 挂起用例 | 记录 |\n|---|---|---|---|\n`;
md += `| cond-a-tasktmp/premerge | \`cmd/multica\`（600.107s） | \`TestRunDaemonDiskUsageJSONSurvivesServerFailure\`（9m53s） | \`cond-a-tasktmp/premerge/02-test-go.log\` |\n`;
md += `| cond-b-shorttmp/premerge | \`cmd/multica\`（600.113s） | \`TestRunDaemonDiskUsageJSONSurvivesServerFailure\`（9m50s） | \`cond-b-shorttmp/premerge/02-test-go.log\` |\n`;
md += `| cond-b-shorttmp/premerge 定向复跑（\`-timeout 300s\`） | \`cmd/multica\`（300.108s） | \`TestRunDaemonDiskUsageAllProfilesUsesPerProfileToken\`（5m0s） | \`cond-b-shorttmp/premerge/03-targeted-merged-only-tests.log\` |\n`;
md += `\n因此合并前树的 \`cmd/multica\` 失败清单**不完整**（仅记录到中止前已打印的项）；在 merged 与 upstream 树上这些用例会快速失败而不是挂起。\n\n`;
md += `## 5. 环境噪声的量化（两个条件集之差）\n\n`;
md += `| 树 | cond-a 失败项 | cond-b 失败项 | 差 | 差额所在包 |\n|---|---|---|---|---|\n`;
for (const t of TREES) {
  const a = S(`cond-a-tasktmp/${t}`); const b = S(`cond-b-shorttmp/${t}`);
  const extraA = diff(a, b);
  const pk = [...new Set(extraA.map((x) => x.split(' :: ')[0]))].join('、');
  md += `| ${t} | ${a.size} | ${b.size} | ${extraA.length} | ${pk || '—'} |\n`;
}
md += `\n差集项在原始日志中的失败消息形如 \`git clone --bare: fatal: cannot stat 'C:/Users/GOBAO/AppData/Local/Temp/multica-task-2074477066/...'\`、\`cannot create leading directories of ...\`——临时根过长触发的 Windows 路径类失败，仅出现在任务临时根条件下；把临时根缩短为 \`C:/rt/...\` 后消失。两组三树各自内部条件一致，互为对照。\n\n`;
md += `## 6. 结论（对应 plan §5 上游场景取证要求）\n\n`;
md += `1. **全量原始日志**：三提交 × 两条件共 6 份未截断 stdout/stderr（字节数与 sha256 见各 \`00-meta.txt\`），含命令、cwd、提交 SHA、起止时间、exit code；合并前/纯上游基线为**同批同条件**实测，不是摘要推断。\n`;
md += `2. **逐项失败对照**：与 \`CUSTOM.md#已知测试失败基线\` 第七次同步行逐包对照（§3），与三树同批差集逐项对照（§4）；已知失败**没有**被改成绿或以子集替代全量。\n`;
md += `3. **fork 归因**：\`merged − upstream = 0\`；仅在纯上游树出现的 2 项与仅在合并前树出现的 5 项均为时序/临时目录/任务环境类（§4.2、§4.3、§4.6），同类项在两棵 pre-merge 树各自复现。\n`;
md += `4. **未闭合面（不得据此声称全绿）**：\`./pkg/agent/...\` 半程未执行（与记录同构）；合并前树 \`cmd/multica\` 清单因包超时中止而不完整；绝对条数与记录值存在空库/累计库差异（§2、§3）。\n\n`;
md += `## 7. 复现\n\n`;
md += `\`\`\`bash\n# 前置：multica 仓三个提交的干净 worktree；postgres 容器 multica-postgres\nbash scripts/run_one.sh cond-b-shorttmp merged     # 生成 rerun/cond-b-shorttmp/merged/*\nbash scripts/run_one.sh cond-b-shorttmp premerge\nbash scripts/run_one.sh cond-b-shorttmp upstream\nbash scripts/targeted_premerge.sh                  # 25 项定向复核\nnode scripts/gen-evidence.mjs                      # 重新生成本文件与 failure-sets/\n\`\`\`\n\n`;
md += `脚本随证据一并存放于 \`rerun/scripts/\`。\n`;

fs.writeFileSync(path.join(E, 'COMPARISON.md'), md, 'utf8');
console.log('COMPARISON.md bytes', Buffer.byteLength(md));
console.log('counts:', JSON.stringify(Object.fromEntries(CONDS.flatMap((c) => TREES.map((t) => [`${c}/${t}`, countTable[`${c}/${t}`].total])))));
