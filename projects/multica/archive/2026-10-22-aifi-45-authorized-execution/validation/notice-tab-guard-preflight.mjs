// Offline compile-only preparation. Never executes a test binary or dependency init.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const args = process.argv.slice(2);
if (args.length !== 4 || process.platform !== 'win32') {
  throw new Error('Expected Windows: node notice-tab-guard-preflight.mjs <server-root> <go.exe> <existing-module-cache> <new-output-dir>');
}
const [source, go, modules, output] = args.map(value => path.resolve(value));
const target = './internal/governance/noticeguard_test';
const packageName = 'github.com/multica-ai/multica/server/internal/governance/noticeguard_test';
if (!fs.statSync(go).isFile() || !fs.statSync(modules).isDirectory() ||
    !fs.statSync(path.join(source, 'go.mod')).isFile()) {
  throw new Error('Required local input missing');
}
// Exclusive creation: no reuse, removal, inherited HOME, GOENV, or credentials.
fs.mkdirSync(output);
for (const dir of ['home', 'tmp', 'cache', 'gopath']) fs.mkdirSync(path.join(output, dir));
const env = {
  SystemRoot: 'C:\\Windows', WINDIR: 'C:\\Windows',
  PATH: `${path.dirname(go)};C:\\Windows\\System32`,
  HOME: path.join(output, 'home'), USERPROFILE: path.join(output, 'home'),
  APPDATA: path.join(output, 'home'), LOCALAPPDATA: path.join(output, 'home'),
  TEMP: path.join(output, 'tmp'), TMP: path.join(output, 'tmp'),
  GOCACHE: path.join(output, 'cache'), GOPATH: path.join(output, 'gopath'),
  GOMODCACHE: modules, GOPROXY: 'off', GOSUMDB: 'off', GOTOOLCHAIN: 'local',
  GOENV: 'off', GOWORK: 'off', GOFLAGS: '-mod=readonly', GOTELEMETRY: 'off',
  CGO_ENABLED: '0', GOOS: 'windows', GOARCH: 'amd64',
};
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
const textHash = filename => sha256(fs.readFileSync(filename, 'utf8').replace(/\r\n/g, '\n'));
const records = [];
const meta = {
  kind: 'offline-compile-only-NOT-RED-NOT-TEST-EXECUTION',
  target, source, output, startedAt: new Date().toISOString(),
  environmentKeys: Object.keys(env).sort(),
  restrictions: {
    dependencyInitExecuted: false, testBinaryExecuted: false,
    osIsolationEstablished: false, initializationSafetyProven: false,
    credentialsInherited: false, engineOrDatabaseInvoked: false,
    moduleAndToolchainDownloadsDisabled: true,
  },
  commands: records,
};
const save = () => fs.writeFileSync(path.join(output, 'preflight.json'), JSON.stringify(meta, null, 2) + '\n');
function run(name, argv) {
  const result = spawnSync(go, argv, {
    cwd: source, env, encoding: 'utf8', timeout: 240000,
    maxBuffer: 32 * 1024 * 1024, windowsHide: true,
  });
  fs.writeFileSync(path.join(output, `${name}.stdout`), result.stdout ?? '');
  fs.writeFileSync(path.join(output, `${name}.stderr`), result.stderr ?? '');
  records.push({ name, executable: go, argv, exit: result.status, signal: result.signal, error: result.error?.code ?? null });
  save();
  if (result.error || result.status !== 0) throw new Error(`${name} failed; no test was executed`);
  return result.stdout;
}
// go list -json emits a stream of top-level JSON objects, not an array.
function parseObjects(text) {
  const result = [];
  let depth = 0, start = -1, quoted = false, escaped = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === '"') quoted = false;
    } else if (ch === '"') quoted = true;
    else if (ch === '{') { if (depth++ === 0) start = i; }
    else if (ch === '}') {
      if (--depth < 0) throw new Error('Invalid go list JSON stream');
      if (depth === 0) { result.push(JSON.parse(text.slice(start, i + 1))); start = -1; }
    } else if (depth === 0 && !/\s/.test(ch)) throw new Error('Unexpected go list output');
  }
  if (depth || quoted || !result.length) throw new Error('Incomplete or empty go list output');
  return result;
}
try {
  meta.goVersion = run('version', ['version']).trim();
  const packages = parseObjects(run('deps', ['list', '-deps', '-test', '-json', target]));
  const governance = 'github.com/multica-ai/multica/server/internal/governance';
  if (packages.some(pkg => pkg.ForTest && pkg.ForTest !== packageName)) {
    throw new Error('Unexpected parent or unrelated test variant');
  }
  if (!packages.some(pkg => pkg.ForTest === packageName)) throw new Error('Target test variant missing');
  const selected = [];
  for (const pkg of packages.filter(pkg => !pkg.Standard)) {
    // The .test synthetic main can point at generated files not yet present.
    const files = [...new Set([...(pkg.GoFiles ?? []), ...(pkg.CgoFiles ?? []), ...(pkg.SFiles ?? []), ...(pkg.EmbedFiles ?? [])])];
    selected.push({
      importPath: pkg.ImportPath, forTest: pkg.ForTest ?? null,
      imports: pkg.Imports ?? [],
      files: files.map(file => {
        const filename = path.resolve(pkg.Dir, file);
        if (!fs.existsSync(filename)) {
          if (pkg.Name !== 'main' || pkg.ImportPath !== packageName + '.test') throw new Error('Selected source missing');
          return { file, generatedSyntheticMain: true };
        }
        const bytes = fs.readFileSync(filename);
        return { file, directory: pkg.Dir, canonicalLfSha256: textHash(filename),
          // A candidate locator, NOT an initialization safety audit. Package vars
          // and functions they call must also be independently inspected.
          explicitInitCandidate: file.endsWith('.go') && /\bfunc\s+init\s*\(/.test(bytes.toString('utf8')) };
      }),
    });
  }
  const manifest = { hashConvention: 'UTF-8 CRLF-to-LF before SHA-256', packages: selected };
  fs.writeFileSync(path.join(output, 'dependency-source-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  meta.packageCount = packages.length;
  meta.nonStandardPackageCount = selected.length;
  meta.parentGovernanceImportedWithoutTestVariant = packages.some(pkg => pkg.ImportPath === governance) && !packages.some(pkg => pkg.ForTest === governance);
  const noticePath = path.join(source, 'internal/governance/execution_notice.go');
  const testPath = path.join(source, 'internal/governance/noticeguard_test/execution_notice_test.go');
  meta.noticeCanonicalLfSha256 = textHash(noticePath);
  meta.testCanonicalLfSha256 = textHash(testPath);
  const binary = path.join(output, 'noticeguard.test.exe');
  run('compile', ['test', '-c', '-vet=off', '-o', binary, target]);
  meta.compiledBinarySha256 = sha256(fs.readFileSync(binary));
  meta.noticeSourceUnchangedDuringCompile = textHash(noticePath) === meta.noticeCanonicalLfSha256;
  meta.testSourceUnchangedDuringCompile = textHash(testPath) === meta.testCanonicalLfSha256;
  if (!meta.noticeSourceUnchangedDuringCompile || !meta.testSourceUnchangedDuringCompile) throw new Error('Owned source drift during compile');
  meta.status = 'COMPILED_ONLY_EXECUTION_BLOCKED';
} catch (error) {
  meta.status = 'PREFLIGHT_FAILED_NOT_RED';
  meta.failure = error.message;
  process.exitCode = 1;
} finally {
  meta.finishedAt = new Date().toISOString();
  save();
  console.log(JSON.stringify({ status: meta.status, output, commands: records, packageCount: meta.packageCount, nonStandardPackageCount: meta.nonStandardPackageCount }));
}
