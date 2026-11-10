// AIFIRST: AIFI-45 SC-NTF-003 — isolated, stdlib-only guard snapshot check.
// This does not run BuildNotice/DeliverNotice, their dependencies or the full TC.
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const mode = process.argv[2];
if (!['red', 'green'].includes(mode)) throw new Error('expected red or green');
const here = dirname(fileURLToPath(import.meta.url));
const source = 'C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/execution_notice.go';
const test = join(here, 'guard-snapshot_test.go');
const go = 'C:/Program Files/Go/bin/go.exe';
const tempParent = 'C:/Users/GOBAO/AppData/Local/Temp';
const lf = s => s.replace(/\r\n/g, '\n');
const sha = s => createHash('sha256').update(lf(s), 'utf8').digest('hex');
const src = lf(readFileSync(source, 'utf8'));
const testContent = lf(readFileSync(test, 'utf8'));
const startMarker = '// looksLikeCommandShipping rejects';
const endMarker = '// BuildNotice renders';
if (src.split(startMarker).length !== 2 || src.split(endMarker).length !== 2) {
  throw new Error('ambiguous source anchors');
}
const start = src.indexOf(startMarker), end = src.indexOf(endMarker, start);
if (start < 0 || end <= start) throw new Error('guard not found');
const snippet = src.slice(start, end);
if (!snippet.includes('func looksLikeCommandShipping(value string) bool {')) throw new Error('guard signature changed');
const root = mkdtempSync(join(tempParent, 'aifi45-guard-'));
for (const d of ['cache', 'home', 'tmp', 'gopath']) mkdirSync(join(root, d));
writeFileSync(join(root, 'guard.go'), 'package guardprobe\n\nimport "strings"\n\n' + snippet, { flag: 'wx' });
writeFileSync(join(root, 'guard_test.go'), testContent, { flag: 'wx' });
const env = {
  SystemRoot: 'C:\\Windows', WINDIR: 'C:\\Windows', PATH: 'C:\\Windows\\System32',
  HOME: join(root, 'home'), USERPROFILE: join(root, 'home'),
  APPDATA: join(root, 'home'), LOCALAPPDATA: join(root, 'home'),
  TEMP: join(root, 'tmp'), TMP: join(root, 'tmp'),
  GOCACHE: join(root, 'cache'), GOPATH: join(root, 'gopath'),
  GOENV: 'off', GOWORK: 'off', GO111MODULE: 'off', GOTOOLCHAIN: 'local',
  GOPROXY: 'off', GOSUMDB: 'off', GOTELEMETRY: 'off', CGO_ENABLED: '0', GOFLAGS: '',
};
const run = args => spawnSync(go, args, { cwd: root, env, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024, shell: false });
const deps = run(['list', '-deps', '-test', '-f', '{{if not .Standard}}{{.ImportPath}}{{end}}', 'guard.go', 'guard_test.go']);
writeFileSync(join(root, 'deps.stdout'), deps.stdout || '', { flag: 'wx' });
writeFileSync(join(root, 'deps.stderr'), deps.stderr || '', { flag: 'wx' });
const nonstd = (deps.stdout || '').split(/\r?\n/).filter(Boolean);
const allowed = /^command-line-arguments(?: \[command-line-arguments\.test\]|\.test)?$/;
if (deps.status !== 0 || !nonstd.length || nonstd.some(x => !allowed.test(x))) {
  throw new Error(`dependency proof failed; artifacts retained in ${root}`);
}
const result = run(['test', '-json', '-count=1', 'guard.go', 'guard_test.go']);
writeFileSync(join(root, 'test.ndjson'), result.stdout || '', { flag: 'wx' });
writeFileSync(join(root, 'test.stderr'), result.stderr || '', { flag: 'wx' });
const events = (result.stdout || '').split(/\r?\n/).filter(Boolean).map(line => JSON.parse(line));
const expected = new Set([
  'TestCommandGuardTabs', ...['sudo', 'psql', 'kubectl', 'podman', 'docker'].flatMap(c => [`TestCommandGuardTabs/space_${c}`, `TestCommandGuardTabs/tab_${c}`]),
  'TestCommandGuardExistingBehavior', ...['ordinary_tab', 'prefix_not_command', 'literal_backslash_t', 'trailing_tab', 'existing_shell_chain', 'unicode_separator_dollar', 'unicode_separator_shebang'].map(x => `TestCommandGuardExistingBehavior/${x}`),
]);
const runs = events.filter(x => x.Action === 'run' && x.Test).map(x => x.Test);
const failed = events.filter(x => x.Action === 'fail' && x.Test).map(x => x.Test);
const passed = events.filter(x => x.Action === 'pass' && x.Test).map(x => x.Test);
const skipped = events.filter(x => x.Action === 'skip');
const redFailures = new Set(['TestCommandGuardTabs', ...['sudo', 'psql', 'kubectl', 'podman', 'docker'].map(c => `TestCommandGuardTabs/tab_${c}`)]);
const sameSet = (a, b) => a.length === b.size && new Set(a).size === a.length && a.every(x => b.has(x));
const expectedFailures = mode === 'red' ? redFailures : new Set();
const matched = sameSet(runs, expected) && sameSet(failed, expectedFailures) && skipped.length === 0 &&
  passed.length + failed.length === expected.size && result.status === (mode === 'red' ? 1 : 0) &&
  !result.signal && !result.error && sha(src) === sha(readFileSync(source, 'utf8')) && sha(testContent) === sha(readFileSync(test, 'utf8'));
console.log(JSON.stringify({ mode, root: resolve(root), exit: result.status, runs: runs.length, passed: passed.length, failed: failed.length,
  skipped: skipped.length, failedTests: failed, sourceLfSha256: sha(src), snippetLfSha256: sha(snippet), testLfSha256: sha(testContent),
  nonstandardDependencies: nonstd, matched }, null, 2));
if (!matched) throw new Error(`unexpected ${mode} result; artifacts retained in ${root}`);
