// AIFIRST: AIFI-45 disposable DB test runner. Never run tests on the preserved DB.
import cp from 'node:child_process';
import { randomBytes, createHash } from 'node:crypto';
import { writeFileSync, mkdirSync, openSync, writeSync, closeSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const container = '666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823';
const original = 'stdd_aifi45_20261022';
const serverRoot = fileURLToPath(new URL('../../server/', import.meta.url));
const ident = s => '"' + s.replaceAll('"', '""') + '"';
const literal = s => "'" + s.replaceAll("'", "''") + "'";
const hash = s => createHash('sha256').update(s).digest('hex');

export function assertDisposable(target, observed) {
  const { nonce, database, role } = target;
  if (!/^[a-f0-9]{16}$/.test(nonce) || database !== `aifi45_tmp_${nonce}` || role !== `aifi45_role_${nonce}`) {
    throw new Error('refusing non-owned disposable target');
  }
  if (arguments.length > 1 && (!observed || observed.database !== database || observed.role !== role ||
      observed.database_oid !== target.database_oid || observed.role_oid !== target.role_oid ||
      observed.marker !== `AIFI45_DISPOSABLE:${nonce}` || observed.role_marker !== observed.marker || observed.superuser !== false)) {
    throw new Error('disposable database/role ownership changed');
  }
}

export function testEnvironment(inherited, database, role, password) {
  const env = { ...inherited };
  for (const k of Object.keys(env)) {
    if (/^PG|DATABASE|^KNOWLEDGE_BASE_|^GH_TOKEN$|^GITHUB_TOKEN$|^(OPENAI|ANTHROPIC)_API_KEY$/.test(k)) delete env[k];
  }
  env.DATABASE_URL = `postgres://${role}:${password}@127.0.0.1:55432/${database}?sslmode=disable`;
  env.GOPROXY = 'off';
  env.MULTICA_RUN_REAL_AGENT_SMOKE = '0';
  return env;
}

export function assertVerifiedTests(result) {
  if (result.exit !== 0 || result.package_failures || result.counts.fail || !result.counts.run || result.output_redacted) {
    throw new Error('test failed, matched no tests, or exposed credentials; inspect evidence');
  }
  if (!(result.leaf_pass > 0)) throw new Error('test unverified: no passed leaf tests; all matched leaves may have skipped');
}

export function main(args) {
  const [pkg, pattern, evidencePrefix, ...extra] = args;
  if (!['./internal/governance', './internal/handler', './internal/daemon', './cmd/server', './pkg/protocol'].includes(pkg) ||
      !pattern || !evidencePrefix || extra.some(x => !/^-(skip=.+|shuffle=(on|off|\d+)|timeout=\d+[smh])$/.test(x))) {
    throw new Error('usage: node run.mjs <approved-package> <test-regex> <evidence-prefix> [-skip=...] [-shuffle=...] [-timeout=...]');
  }
  const nonce = randomBytes(8).toString('hex');
  const target = { nonce, database: `aifi45_tmp_${nonce}`, role: `aifi45_role_${nonce}` };
  assertDisposable(target);
  const marker = `AIFI45_DISPOSABLE:${nonce}`;
  const password = randomBytes(24).toString('hex'); // Never persist or print credentials.
  const scrub = s => String(s || '').replaceAll(password, '[REDACTED]');
  const prefix = resolve(evidencePrefix);
  mkdirSync(dirname(prefix), { recursive: true });
  const journal = openSync(prefix + '.events.jsonl', 'wx', 0o600);
  const event = (kind, data = {}) => writeSync(journal, JSON.stringify({ at: new Date().toISOString(), kind, ...data }) + '\n');
  const save = (suffix, text) => writeFileSync(prefix + suffix, scrub(text), { flag: 'wx', mode: 0o600 });
  const command = (name, argv, input, allowFailure = false) => {
    const r = cp.spawnSync(name, argv, { input, encoding: 'utf8', timeout: 300000, maxBuffer: 64 << 20 });
    if (!allowFailure && r.status !== 0) throw new Error(scrub(`${name} failed (${r.status}): ${r.stderr || r.error?.message}`));
    return r;
  };
  const sql = (database, text, role = 'stdd', allowFailure = false) => command('podman', [
    'exec', '-i', container, 'psql', '-X', '-q', '-U', role, '-d', database, '-At', '-v', 'ON_ERROR_STOP=1',
  ], text, allowFailure);
  const jsonSQL = (database, text, role) => sql(database, text, role).stdout.trim().split(/\r?\n/).filter(Boolean).map(JSON.parse);
  const snapshot = () => {
    const tables = jsonSQL(original, `SELECT json_build_object('schema',n.nspname,'table',c.relname)
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE c.relkind IN ('r','p') AND n.nspname !~ '^pg_' AND n.nspname<>'information_schema' ORDER BY n.nspname,c.relname;`);
    const queries = tables.map(t => `SELECT json_build_object('table',${literal(t.schema + '.' + t.table)},'count',count(*),
      'digest',md5(COALESCE(string_agg(md5(row_to_json(t)::text),'' ORDER BY md5(row_to_json(t)::text)),''))) FROM ${ident(t.schema)}.${ident(t.table)} t;`);
    queries.push(`SELECT json_build_object('approval_id',a.id,'hash',md5(row_to_json(a)::text)) FROM public.approval_record a ORDER BY id;`);
    return jsonSQL(original, 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n' + queries.join('\n') + '\nCOMMIT;');
  };
  const observe = () => jsonSQL('postgres', `SELECT json_build_object('database',d.datname,'role',r.rolname,
    'database_oid',d.oid,'role_oid',r.oid,'superuser',r.rolsuper,
    'marker',shobj_description(d.oid,'pg_database'),'role_marker',shobj_description(r.oid,'pg_authid'))
    FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba WHERE d.datname=${literal(target.database)};`)[0];
  let before, result, failure, release = null, roleCreated = false, databaseCreated = false, unchanged = false, cleaned = false;
  event('plan', { container, original, target, package: pkg, pattern, extra });
  try {
    const info = JSON.parse(command('podman', ['inspect', container]).stdout)[0];
    const values = Object.fromEntries(info.Config.Env.map(s => { const i = s.indexOf('='); return [s.slice(0, i), s.slice(i + 1)]; }));
    const port = info.HostConfig.PortBindings['5432/tcp'][0];
    if (info.Id !== container || !info.State.Running || info.Config.Labels['stdd.change'] !== '2026-10-22-aifi-45-authorized-execution' ||
        values.POSTGRES_DB !== original || values.POSTGRES_USER !== 'stdd' || port.HostIp !== '127.0.0.1' || port.HostPort !== '55432') throw new Error('approved container identity mismatch');
    const busy = jsonSQL(original, `SELECT json_build_object('sessions',(SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()),
      'locks',(SELECT count(*) FROM pg_locks WHERE locktype='advisory'));`)[0];
    if (busy.sessions || busy.locks) throw new Error('original database is not released');
    before = snapshot();
    save('.original-before.json', JSON.stringify(before, null, 2));
    const dump = command('podman', ['exec', container, 'pg_dump', '-U', 'stdd', '-d', original, '--data-only', '--table=public.approval_record', '--no-owner', '--no-privileges']).stdout;
    save('.original-approval-record.sql', dump);
    const schema = command('podman', ['exec', container, 'pg_dump', '-U', 'stdd', '-d', original, '--schema-only', '--no-owner', '--no-privileges']).stdout;
    if (schema.includes(original)) throw new Error('schema explicitly references preserved database');
    save('.schema.sql', schema);
    event('source-preserved', { approval_rows: before.filter(x => x.approval_id).length, original_tables: before.filter(x => x.table).length, schema_sha256: hash(schema), audit_dump_sha256: hash(dump) });
    event('create-role-intent', { role: target.role });
    sql('postgres', `CREATE ROLE ${ident(target.role)} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD ${literal(password)};`);
    roleCreated = true;
    target.role_oid = jsonSQL('postgres', `SELECT json_build_object('oid',oid) FROM pg_roles WHERE rolname=${literal(target.role)};`)[0].oid;
    sql('postgres', `COMMENT ON ROLE ${ident(target.role)} IS ${literal(marker)};`);
    event('create-database-intent', { database: target.database, owner: target.role });
    sql('postgres', `CREATE DATABASE ${ident(target.database)} WITH TEMPLATE template0 OWNER ${ident(target.role)};`);
    databaseCreated = true;
    sql('postgres', `COMMENT ON DATABASE ${ident(target.database)} IS ${literal(marker)};`);
    target.database_oid = observe().database_oid;
    assertDisposable(target, observe());
    event('created', { target });
    // Import as the restricted owner, not the original privileged role.
    sql(target.database, schema, target.role);
    const identity = jsonSQL(target.database, `SELECT json_build_object('database',current_database(),'role',current_user,
      'superuser',r.rolsuper,'create_db',r.rolcreatedb,'create_role',r.rolcreaterole,'bypass_rls',r.rolbypassrls,
      'audit_rows',(SELECT count(*) FROM approval_record),'workspace_rows',(SELECT count(*) FROM workspace))
      FROM pg_roles r WHERE r.rolname=current_user;`, target.role)[0];
    if (identity.database !== target.database || identity.role !== target.role || identity.superuser || identity.create_db || identity.create_role || identity.bypass_rls || identity.audit_rows || identity.workspace_rows) throw new Error('fresh restricted database validation failed');
    const denied = sql(original, 'SELECT 1 FROM public.approval_record LIMIT 0;', target.role, true);
    if (denied.status !== 3 || !denied.stderr.includes('permission denied')) throw new Error('fresh role can read original audit table or denial check is invalid');
    event('isolation-verified', { identity, original_audit_table_read_denied: true });
    const goArgs = ['test', pkg, '-run', pattern, '-count=1', '-json', '-timeout=180s', ...extra];
    const r = cp.spawnSync('go', goArgs, { cwd: serverRoot, env: testEnvironment(process.env, target.database, target.role, password), encoding: 'utf8', timeout: 300000, maxBuffer: 128 << 20 });
    const redacted = (r.stdout || '').includes(password) || (r.stderr || '').includes(password);
    save('.stdout.jsonl', r.stdout || '');
    save('.stderr.log', r.stderr || '');
    const events = (r.stdout || '').split(/\r?\n/).flatMap(l => { try { return [JSON.parse(l)]; } catch { return []; } });
    const counts = Object.fromEntries(['run', 'pass', 'fail', 'skip'].map(action => [action, events.filter(e => e.Test && e.Action === action).length]));
    const parents = new Set();
    for (const name of new Set(events.filter(e => e.Test).map(e => e.Test))) {
      for (let i = name.indexOf('/'); i >= 0; i = name.indexOf('/', i + 1)) parents.add(name.slice(0, i));
    }
    const leafPass = events.filter(e => e.Test && e.Action === 'pass' && !parents.has(e.Test)).length;
    result = { argv: ['go', ...goArgs], cwd: serverRoot, exit: r.status, signal: r.signal, counts, leaf_pass: leafPass,
      package_failures: events.filter(e => !e.Test && e.Action === 'fail').length, output_redacted: redacted };
    event('test-finished', result);
    assertVerifiedTests(result);
  } catch (err) {
    failure = scrub(err.message);
    event('failure', { error: failure });
  } finally {
    try {
      if (before) {
        const after = snapshot();
        save('.original-after.json', JSON.stringify(after, null, 2));
        unchanged = JSON.stringify(before) === JSON.stringify(after);
        release = jsonSQL(original, `SELECT json_build_object('sessions',(SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()),
          'locks',(SELECT count(*) FROM pg_locks WHERE locktype='advisory'));`)[0];
        event('original-compared', { unchanged, release });
        if (!unchanged) throw new Error('ORIGINAL_DATABASE_DRIFT: preserve disposable database; stop all further writes');
        if (release.sessions || release.locks) throw new Error('original database is not released after test; preserve disposable resources');
      }
      if (databaseCreated && unchanged) {
        assertDisposable(target, observe());
        sql('postgres', `DROP DATABASE ${ident(target.database)};`);
        databaseCreated = false;
        event('database-dropped', { database: target.database, oid: target.database_oid });
      }
      if (roleCreated && !databaseCreated && unchanged) {
        const r = jsonSQL('postgres', `SELECT json_build_object('oid',oid,'marker',shobj_description(oid,'pg_authid')) FROM pg_roles WHERE rolname=${literal(target.role)};`)[0];
        if (r?.oid !== target.role_oid || r.marker !== marker) throw new Error('refusing changed role cleanup');
        sql('postgres', `DROP ROLE ${ident(target.role)};`);
        roleCreated = false;
        event('role-dropped', { role: target.role, oid: target.role_oid });
      }
      if (before) {
        const absent = jsonSQL('postgres', `SELECT json_build_object(
          'database_present',EXISTS(SELECT 1 FROM pg_database WHERE datname=${literal(target.database)}),
          'role_present',EXISTS(SELECT 1 FROM pg_roles WHERE rolname=${literal(target.role)}));`)[0];
        cleaned = absent.database_present === false && absent.role_present === false;
        event('resources-absence-verified', absent);
        if (!cleaned) throw new Error('disposable resource state unresolved; preserve recorded identities');
      } else {
        cleaned = !roleCreated && !databaseCreated;
      }
    } catch (err) {
      failure = [failure, scrub(err.message)].filter(Boolean).join('; ');
      event('cleanup-or-preservation-failed', { error: failure });
    }
    const meta = { at: new Date().toISOString(), container, preserved_database: original, target,
      test: result || null, original_unchanged: unchanged, original_release: release, owned_resources_cleaned: cleaned, error: failure || null };
    save('.meta.json', JSON.stringify(meta, null, 2));
    closeSync(journal);
    console.log(JSON.stringify(meta));
  }
  if (failure || !unchanged || !cleaned) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); } catch (err) { console.error(err.message); process.exitCode = 1; }
}
