const fs = require('fs');
const cp = require('child_process');
const crypto = require('crypto');
const path = require('path');
const [label, pkg, run, ...extra] = process.argv.slice(2);
if (!/^[a-z0-9-]+$/.test(label || '')) throw new Error('invalid evidence label');
const root = 'C:/Users/GOBAO/Downloads/AI/multica';
const out = 'C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation';
const runner = 'C:/Users/GOBAO/AppData/Local/Temp/aifi45-gotest.cjs';
const started = new Date();
const stamp = started.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const stem = path.join(out, "revoke-" + label + "-" + stamp);
const owned = [...fs.readdirSync(path.join(root,'server/internal/governance')).filter(p => /^execution_authorization_revoke.*\.go$/.test(p)).map(p => 'server/internal/governance/'+p), 'server/internal/governance/execution_fixture_ownership_test.go', 'server/internal/governance/execution_authorization_routes.go', 'server/pkg/db/queries/approval.sql', 'server/pkg/db/generated/approval.sql.go', 'server/internal/governance/execution_authorization_head.go', 'server/internal/governance/execution_authorization_head_test.go', 'server/cmd/server/execution_authorization_head_test.go'];
const hashes = Object.fromEntries(owned.filter(p => fs.existsSync(path.join(root,p))).map(p => [p, crypto.createHash('sha256').update(fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n')).digest('hex')]));
const original = cp.spawnSync;
let captured;
cp.spawnSync = function(command, args, options) {
  const before = Date.now();
  const result = original.apply(this, arguments);
  if (command === 'go' && args[0] === 'test') {
    const events = (result.stdout || '').split(/\r?\n/).flatMap(line => { try { return [JSON.parse(line)]; } catch { return []; } });
    const tests = events.filter(e => e.Test);
    const counts = list => Object.fromEntries(['run', 'pass', 'fail', 'skip'].map(action => [action, list.filter(e => e.Action === action).length]));
    captured = { schema: 'aifi45-revoke-run/v1', label, started_utc: started.toISOString(), completed_utc: new Date().toISOString(), process_elapsed_ms: Date.now() - before, final_argv: [command, ...args], cwd: options.cwd, exit: result.status, signal: result.signal, spawn_error: result.error ? String(result.error) : null, counts_all: counts(tests), counts_top: counts(tests.filter(e => !e.Test.includes('/'))), package_results: events.filter(e => !e.Test && ['pass', 'fail', 'skip'].includes(e.Action)), failed_tests: tests.filter(e => e.Action === 'fail').map(e => e.Test), source_sha256_lf: hashes, runner_sha256_lf: crypto.createHash('sha256').update(fs.readFileSync(runner, 'utf8').replace(/\r\n/g, '\n')).digest('hex'), database: { container: 'stdd-aifi45-20261022-pg', container_id_prefix: '666bfec52ac3', loopback_port: 55432, database: 'stdd_aifi45_20261022', user: 'stdd' }, harness: Object.fromEntries(['PI_PROVIDER', 'PI_MODEL', 'PI_REASONING_LEVEL'].map(k => [k, process.env[k] || null])) };
    fs.writeFileSync(stem + '.go.jsonl', result.stdout || '', {flag: 'wx'});
    fs.writeFileSync(stem + '.stderr.log', result.stderr || '', {flag: 'wx'});
    fs.writeFileSync(stem + '.meta.json', JSON.stringify(captured, null, 2) + '\n', {flag: 'wx'});
  }
  return result;
};
process.argv = [process.execPath, runner, pkg, run, ...extra];
require(runner);
if (!captured) throw new Error('no go test process captured');
console.log('evidence=' + stem);
console.log('process_elapsed_ms=' + captured.process_elapsed_ms);
process.exitCode = captured.exit === null ? 1 : captured.exit;
