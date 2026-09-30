#!/usr/bin/env node
// CR-2026-073 TASK-04 / plan.md §5：U / S / P 快照的**版本化夹具构建器**。
//
// 作用：在一个**独立 install root**（不指向任何业务工作区）里建出三个可评审的测试 CR worktree：
//   <root>/.rayai-worktrees/knowledge-base/requirement/CR-2026-901|902|903   （KB 夹具仓 worktree）
//   <root>/.rayai-worktrees/tools/requirement/CR-2026-901|902|903           （tools 夹具仓 worktree）
//
// 边界（不得越界）：
//   * 只做 git init / add / commit / worktree add 与文件写入；不调用 crctl、不产生平台事件、不触碰业务仓；
//   * 夹具内容来自本目录 shared/（三案共用同一 SDD/AC）与 variants/{U,S,P}/（只替换 plan.md 与 TASK-01.md）；
//   * 快照初始 status 为 tech-design-reviewed，其后由调用方按合法 crctl 流程
//     （`crctl advance --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed --workspace <kbWorktree>`）
//     建立可评审状态；本脚本不写受控 status 之外的状态。
//
// 用法：
//   node build-snapshots.mjs --install-root <空目录> [--tools-package <tools 包路径>] [--variants U,S,P]
//
// 输出：JSON（install root、三个 CR 的 kb/tools worktree 路径、快照 SHA、owner 等）。

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const FIXTURE_DIR = import.meta.dirname;
const KB_REPO_ID = 'ai-first-platform-docs';
const TOOLS_REPO_ID = 'tools';
const VARIANTS = {
  U: { cr: 'CR-2026-901', title: 'fixture 快照 U：误设全仓', axis: '无已批准全量要求却把全仓 make test 设为关键 cmd-01，TASK 附加全仓绿色' },
  S: { cr: 'CR-2026-902', title: 'fixture 快照 S：子集冒充全量', axis: '关键 cmd 只跑两个定向用例，plan §5 与 TASK 声称全量测试通过' },
  P: { cr: 'CR-2026-903', title: 'fixture 快照 P：定向证据一致', axis: '定向 cmd-NN 覆盖 FR/AC，范围标注一致且不附加全量' },
};

function fail(msg) { process.stderr.write(`build-snapshots: ${msg}\n`); process.exit(1); }

function arg(name, def = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? def : process.argv[i + 1];
}

function git(cwd, args) {
  const r = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, GIT_AUTHOR_NAME: 'cr073-fixture', GIT_AUTHOR_EMAIL: 'fixture@local',
      GIT_COMMITTER_NAME: 'cr073-fixture', GIT_COMMITTER_EMAIL: 'fixture@local' },
  });
  if (r.status !== 0) fail(`git ${args.join(' ')} (cwd=${cwd}) exit=${r.status}\nSTDOUT:${r.stdout}\nSTDERR:${r.stderr}`);
  return r.stdout.trim();
}

function readNorm(rel) {
  return fs.readFileSync(path.join(FIXTURE_DIR, rel), 'utf8').replaceAll('\r\n', '\n');
}

function sha256(text) { return crypto.createHash('sha256').update(text, 'utf8').digest('hex'); }

/** 默认 tools 包 = 本夹具所在 KB worktree 的 install root 的 dir-graph#workspace.tools_package_path（与 crctl deriveInstallRoot 同口径）。 */
function resolveToolsPackage(kbWorktree) {
  const commonDir = git(kbWorktree, ['rev-parse', '--git-common-dir']);
  const installRoot = path.dirname(path.resolve(kbWorktree, commonDir));
  const cfg = fs.readFileSync(path.join(installRoot, 'dir-graph.yaml'), 'utf8').replaceAll('\r\n', '\n');
  const m = cfg.match(/tools_package_path:\s*"?([^"\n]+)"?/);
  if (!m) fail(`无法从 ${installRoot}/dir-graph.yaml 解析 tools_package_path`);
  return path.resolve(installRoot, m[1].trim());
}

function writeFiles(root, files) {
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content, 'utf8');
  }
}

const installRoot = arg('install-root');
if (!installRoot) fail('缺少 --install-root <空目录>');
const root = path.resolve(installRoot);
if (fs.existsSync(root) && fs.readdirSync(root).length > 0) {
  fail(`--install-root ${root} 已存在且非空；先删除（夹具根是一次性目录）后重跑`);
}
const variants = (arg('variants', 'U,S,P')).split(',').map((s) => s.trim().toUpperCase()).filter(Boolean);
for (const v of variants) if (!VARIANTS[v]) fail(`未知 variant: ${v}`);

const kbWorktreeSelf = path.resolve(FIXTURE_DIR, '..', '..', '..', '..', '..');
const toolsPackage = path.resolve(arg('tools-package', resolveToolsPackage(kbWorktreeSelf)));
if (!fs.existsSync(path.join(toolsPackage, 'skills', 'shared', 'crctl', 'gates.json'))) {
  fail(`--tools-package 不是 tools 包（缺 skills/shared/crctl/gates.json）: ${toolsPackage}`);
}

const AT = new Date().toISOString().replace(/\.\d{3}Z$/, '+00:00');
const TOOLS_REPO_DIR = path.join(root, 'tools-fixture');

fs.mkdirSync(root, { recursive: true });

// 1) 两个夹具仓的 main（install root 的 dir-graph + KB 夹具仓；tools 夹具仓）
git(root, ['init', '-q', '-b', 'main', '.']);
writeFiles(root, {
  'dir-graph.yaml': [
    'workspace:',
    '  root: "."',
    '  timezone: "Asia/Shanghai"',
    '  edition: fixture-scope-snapshot',
    '  path_basis: "workspace-root"',
    `  tools_package_path: ${JSON.stringify(toolsPackage)}`,
    'repositories:',
    `  - id: ${KB_REPO_ID}`,
    '    path: "."',
    '    trunk: main',
    '    role: knowledge-base',
    `  - id: ${TOOLS_REPO_ID}`,
    '    path: "tools-fixture"',
    '    trunk: main',
    '    role: code',
    '',
  ].join('\n'),
  'README.md': '# CR-2026-073 plan §5 快照夹具 install root（一次性；非业务工作区）\n',
});
git(root, ['add', '-A']);
git(root, ['commit', '-qm', 'fixture: install root (dir-graph + readme)']);

fs.mkdirSync(TOOLS_REPO_DIR, { recursive: true });
git(TOOLS_REPO_DIR, ['init', '-q', '-b', 'main', '.']);
writeFiles(TOOLS_REPO_DIR, {
  'README.md': '# tools 夹具仓（CR-2026-073 plan §5 快照；只承载证据命令的 repo 声明面）\n',
  'scripts/README.md': '本目录承载快照的 `cmd-NN` 目标（夹具不实现、不执行）。\n',
});
git(TOOLS_REPO_DIR, ['add', '-A']);
git(TOOLS_REPO_DIR, ['commit', '-qm', 'fixture: tools 夹具仓 main']);

// 2) 逐案建 worktree、写内容、提交
const out = { installRoot: root, toolsPackage, generatedAt: AT, snapshots: {} };

for (const v of variants) {
  const { cr, title, axis } = VARIANTS[v];
  const kb = path.join(root, '.rayai-worktrees', 'knowledge-base', 'requirement', cr);
  const tools = path.join(root, '.rayai-worktrees', TOOLS_REPO_ID, 'requirement', cr);
  git(root, ['worktree', 'add', '-q', kb, '-b', `requirement/${cr}`]);
  git(TOOLS_REPO_DIR, ['worktree', 'add', '-q', tools, '-b', `requirement/${cr}`]);

  const sub = (text) => text
    .replaceAll('__CR__', cr)
    .replaceAll('__TITLE__', title)
    .replaceAll('__SUMMARY__', `CR-2026-073 TASK-04 / plan §5 快照（${v}）：${axis}。非业务 CR，仅用于 review-dev-plan 判据取证。`)
    .replaceAll('__AT__', AT);
  const sdd = sub(readNorm('shared/sdd.md'));
  const files = {
    'change-requests/_backlog.yml': sub(readNorm('shared/_backlog.yml')),
    [`change-requests/${cr}/cr.md`]: sub(readNorm('shared/cr.md')),
    [`change-requests/${cr}/prd.md`]: sub(readNorm('shared/prd.md')),
    [`change-requests/${cr}/sdd.md`]: sdd,
    [`change-requests/${cr}/plan.md`]: sub(readNorm(`variants/${v}/plan.md`)),
    [`change-requests/${cr}/tasks/_index.yml`]: sub(readNorm('shared/tasks/_index.yml')),
    [`change-requests/${cr}/tasks/TASK-01.md`]: sub(readNorm(`variants/${v}/TASK-01.md`)),
    [`change-requests/${cr}/review-annotations/sdd.yml`]: sub(readNorm('shared/review-annotations/sdd.yml')).replaceAll('__SDD_SHA__', sha256(sdd)),
  };
  writeFiles(kb, files);
  git(kb, ['add', '-A']);
  git(kb, ['commit', '-qm', `fixture: ${cr} 快照 ${v}（plan/TASK 证据范围变体）`]);
  const sha = git(kb, ['rev-parse', 'HEAD']);
  out.snapshots[v] = { variant: v, cr, axis, kbWorktree: kb, toolsWorktree: tools, branch: `requirement/${cr}`, snapshotSha: sha };
}

out.reviewerResources = Object.fromEntries(Object.entries(out.snapshots).map(([v, s]) => [v, [
  { repo: KB_REPO_ID, worktreePath: s.kbWorktree },
  { repo: TOOLS_REPO_ID, worktreePath: s.toolsWorktree },
]]));
process.stdout.write(JSON.stringify(out, null, 2) + '\n');
