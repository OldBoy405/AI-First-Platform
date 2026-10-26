import { test } from 'node:test';
import assert from 'node:assert/strict';
import cp from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { assertDisposable, testEnvironment, assertVerifiedTests, main } from './run.mjs';

const target = { nonce: '0123456789abcdef', database: 'aifi45_tmp_0123456789abcdef', role: 'aifi45_role_0123456789abcdef', database_oid: 100, role_oid: 200 };
const observed = { ...target, marker: 'AIFI45_DISPOSABLE:0123456789abcdef', role_marker: 'AIFI45_DISPOSABLE:0123456789abcdef', superuser: false };

test('only the generated database and role are eligible for cleanup', () => {
  assert.doesNotThrow(() => assertDisposable(target));
  for (const change of [{ database: 'stdd_aifi45_20261022' }, { database: 'postgres' }, { role: 'stdd' }, { nonce: '' }, { role: 'aifi45_role_other' }]) {
    assert.throws(() => assertDisposable({ ...target, ...change }), /refusing/);
  }
});

test('cleanup requires the same OIDs, owner, markers and restricted role', () => {
  assert.doesNotThrow(() => assertDisposable(target, observed));
  assert.throws(() => assertDisposable(target, undefined), /ownership/);
  for (const change of [{ database_oid: 101 }, { role_oid: 201 }, { role: 'stdd' }, { marker: null }, { role_marker: 'foreign' }, { superuser: true }]) {
    assert.throws(() => assertDisposable(target, { ...observed, ...change }), /ownership/);
  }
});

test('the child receives only the new DB identity, not inherited DB credentials', () => {
  const inherited = { PATH: 'tools', DATABASE_URL: 'old-secret', TEST_DATABASE_URL: 'old', PGHOST: 'old-host', PGPASSWORD: 'old-password', GITHUB_TOKEN: 'old-token', KNOWLEDGE_BASE_TOKEN: 'old-token', OPENAI_API_KEY: 'old-key', MULTICA_RUN_REAL_AGENT_SMOKE: '1' };
  const env = testEnvironment(inherited, target.database, target.role, 'ephemeral');
  assert.equal(new URL(env.DATABASE_URL).pathname, '/' + target.database);
  assert.equal(new URL(env.DATABASE_URL).username, target.role);
  for (const key of ['TEST_DATABASE_URL', 'PGHOST', 'PGPASSWORD', 'GITHUB_TOKEN', 'KNOWLEDGE_BASE_TOKEN', 'OPENAI_API_KEY']) assert.equal(env[key], undefined);
  assert.equal(env.MULTICA_RUN_REAL_AGENT_SMOKE, '0');
  assert.equal(env.GOPROXY, 'off');
  assert.equal(env.PATH, 'tools');
  assert.equal(inherited.DATABASE_URL, 'old-secret');
});

test('unsupported packages and process-redirection flags fail before DB access', () => {
  assert.throws(() => main(['./...', '^Test', 'unused']), /usage/);
  assert.throws(() => main(['./internal/governance', '^Test', 'unused', '-exec=other']), /usage/);
  assert.throws(() => main(['./internal/governance', '^Test', 'unused', '-args']), /usage/);
});

test('all skipped leaves are unverified even if their parent passes', () => {
  for (const counts of [{ run: 1, pass: 0, fail: 0, skip: 1 }, { run: 2, pass: 1, fail: 0, skip: 1 }]) {
    assert.throws(() => assertVerifiedTests({ exit: 0, counts, leaf_pass: 0, package_failures: 0, output_redacted: false }), /verified|skipped/);
  }
  assert.doesNotThrow(() => assertVerifiedTests({ exit: 0, counts: { run: 2, pass: 1, fail: 0, skip: 1 }, leaf_pass: 1, package_failures: 0, output_redacted: false }));
});

test('lost CREATE ROLE acknowledgement must not claim resources were cleaned', t => {
  const directory = mkdtempSync(join(tmpdir(), 'aifi45-db-fault-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const prefix = join(directory, 'lost-ack');
  const oldExit = process.exitCode;
  let committed = false;
  const ok = stdout => ({ status: 0, signal: null, stdout, stderr: '' });
  t.mock.method(console, 'log', () => {});
  t.mock.method(cp, 'spawnSync', (name, argv, options) => {
    assert.equal(name, 'podman');
    if (argv[0] === 'inspect') return ok(JSON.stringify([{
      Id: '666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823', State: { Running: true },
      Config: { Env: ['POSTGRES_DB=stdd_aifi45_20261022', 'POSTGRES_USER=stdd'], Labels: { 'stdd.change': '2026-10-22-aifi-45-authorized-execution' } },
      HostConfig: { PortBindings: { '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '55432' }] } },
    }]));
    if (argv.includes('pg_dump')) return ok('-- synthetic dump\n');
    const query = options?.input || '';
    if (query.includes('CREATE ROLE')) {
      committed = true;
      return { status: null, signal: null, stdout: '', stderr: '', error: new Error('simulated lost acknowledgement after commit') };
    }
    if (query.includes("'sessions'")) return ok('{"sessions":0,"locks":0}\n');
    if (query.includes("'database_present'")) return ok(JSON.stringify({ database_present: false, role_present: committed }) + '\n');
    if (query.includes('FROM pg_class') || query.startsWith('BEGIN ISOLATION LEVEL')) return ok('');
    throw new Error('unexpected blind cleanup or command in fault test');
  });
  try {
    main(['./internal/governance', '^Test', prefix]);
    const meta = JSON.parse(readFileSync(prefix + '.meta.json', 'utf8'));
    assert.equal(committed, true, 'fault must occur after role creation');
    assert.equal(meta.original_unchanged, true);
    assert.deepEqual(meta.original_release, { sessions: 0, locks: 0 });
    assert.equal(meta.owned_resources_cleaned, false);
    assert.match(meta.error, /lost acknowledgement|unresolved/);
    assert.equal(process.exitCode, 1);
  } finally {
    process.exitCode = oldExit;
  }
});
