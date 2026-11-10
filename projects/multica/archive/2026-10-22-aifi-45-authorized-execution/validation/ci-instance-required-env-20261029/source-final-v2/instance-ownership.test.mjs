// AIFIRST: ownership checks for the AIFI-45 isolated CI verification instance.
import test from 'node:test';
import assert from 'node:assert/strict';
import { assertInstanceIntent, assertInstanceOwnership } from './instance-ownership.mjs';

const target = Object.freeze({
  id: '1'.repeat(64), name: 'aifi45-ci-0123456789abcdef',
  nonce: '0123456789abcdef', image: '2'.repeat(64),
  createdAfter: '2026-10-28T00:00:00.000Z', createdBefore: '2026-10-28T00:02:00.000Z',
  expectedEnv: Object.freeze({ PGDATA: '/var/lib/postgresql/data/pgdata', POSTGRES_DB: 'postgres', POSTGRES_USER: 'ci_test_user', POSTGRES_PASSWORD: 'test-only-secret' }),
});

function inspected() {
  return {
    Id: target.id, Name: target.name, Image: target.image, Created: '2026-10-28T00:01:00.000Z',
    Config: { Labels: { 'aifi45.ci.nonce': target.nonce }, Env: Object.entries(target.expectedEnv).map(([key, value]) => `${key}=${value}`), Entrypoint: ['docker-entrypoint.sh'], Cmd: ['postgres'] },
    HostConfig: {
      Privileged: false, AutoRemove: false, NetworkMode: 'bridge', PidMode: 'private', IpcMode: 'private',
      UTSMode: 'private', UsernsMode: '', Binds: [], VolumesFrom: [], Devices: [], CapAdd: [], SecurityOpt: [],
      Tmpfs: { '/var/lib/postgresql/data': 'rw,size=1073741824' },
      PortBindings: { '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '' }] },
      PublishAllPorts: false, RestartPolicy: { Name: 'no' },
    },
    Mounts: [],
    NetworkSettings: { Ports: { '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '39421' }] } },
    State: { Running: true, Status: 'running', Paused: false, Restarting: false, Dead: false },
  };
}

test('matching immutable identity and isolated configuration are accepted', () => {
  assert.doesNotThrow(() => assertInstanceOwnership(target, inspected(), 'running'));
});

for (const key of ['PGDATA', 'POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD']) {
  test(`reject non-enumerable required environment key ${key}`, () => {
    const env = { ...target.expectedEnv };
    Object.defineProperty(env, key, { enumerable: false });
    const candidate = { ...target, expectedEnv: env };
    const x = inspected();
    x.Config.Env = x.Config.Env.filter(value => !value.startsWith(`${key}=`));
    assert.throws(() => assertInstanceIntent(candidate), /instance ownership/i);
    assert.throws(() => assertInstanceOwnership(candidate, x, 'running'), /instance ownership/i);
  });
}

test('reject inherited required PGDATA even when the inspected environment omits it', () => {
  const { PGDATA, ...remaining } = target.expectedEnv;
  const candidate = { ...target, expectedEnv: Object.assign(Object.create({ PGDATA }), remaining) };
  const x = inspected();
  x.Config.Env = x.Config.Env.filter(value => !value.startsWith('PGDATA='));
  assert.throws(() => assertInstanceIntent(candidate), /instance ownership/i);
  assert.throws(() => assertInstanceOwnership(candidate, x, 'running'), /instance ownership/i);
});

test('reject hidden unapproved environment key replacing an expected key', () => {
  const env = { ...target.expectedEnv, PATH: 'fixture-path' };
  Object.defineProperty(env, 'POSTGRES_HOST_AUTH_METHOD', { value: 'trust', enumerable: false });
  const candidate = { ...target, expectedEnv: env };
  const x = inspected();
  x.Config.Env.push('POSTGRES_HOST_AUTH_METHOD=trust');
  assert.doesNotThrow(() => assertInstanceIntent(candidate));
  assert.throws(() => assertInstanceOwnership(candidate, x, 'running'), /instance ownership/i);
});

for (const [name, mutate] of [
  ['different ID', x => { x.Id = '3'.repeat(64); }],
  ['different name', x => { x.Name = target.name + '-other'; }],
  ['different image', x => { x.Image = '3'.repeat(64); }],
  ['different nonce', x => { x.Config.Labels['aifi45.ci.nonce'] = 'ffffffffffffffff'; }],
  ['created before intent', x => { x.Created = '2026-10-27T23:59:59.999Z'; }],
  ['created after allowed time', x => { x.Created = '2026-10-28T00:02:00.001Z'; }],
  ['created one nanosecond after upper bound', x => { x.Created = '2026-10-28T00:02:00.000000001Z'; }],
  ['missing created timestamp', x => { delete x.Created; }],
  ['invalid 24th hour', x => { x.Created = '2026-10-28T24:00:00Z'; }],
  ['privileged', x => { x.HostConfig.Privileged = true; }],
  ['added capabilities', x => { x.HostConfig.CapAdd = ['SYS_ADMIN']; }],
  ['unconfined seccomp', x => { x.HostConfig.SecurityOpt = ['seccomp=unconfined']; }],
  ['device requests', x => { x.HostConfig.DeviceRequests = [{}]; }],
  ['device cgroup rules', x => { x.HostConfig.DeviceCgroupRules = ['a *:* rwm']; }],
  ['changed entrypoint', x => { x.Config.Entrypoint = ['sh']; }],
  ['changed command', x => { x.Config.Cmd = ['sh']; }],
  ['paused runtime', x => { x.State.Paused = true; }],
  ['restarting runtime', x => { x.State.Restarting = true; }],
  ['dead runtime', x => { x.State.Dead = true; }],
  ['inconsistent runtime state', x => { x.State.Status = 'exited'; }],
  ['host network', x => { x.HostConfig.NetworkMode = 'host'; }],
  ['host PID', x => { x.HostConfig.PidMode = 'host'; }],
  ['host IPC', x => { x.HostConfig.IpcMode = 'host'; }],
  ['host UTS', x => { x.HostConfig.UTSMode = 'host'; }],
  ['host user namespace', x => { x.HostConfig.UsernsMode = 'host'; }],
  ['bind mount', x => { x.HostConfig.Binds = ['/data:/var/lib/postgresql/data']; }],
  ['unknown binds', x => { delete x.HostConfig.Binds; }],
  ['unknown devices', x => { delete x.HostConfig.Devices; }],
  ['unknown inherited volumes', x => { delete x.HostConfig.VolumesFrom; }],
  ['volumes from another container', x => { x.HostConfig.VolumesFrom = ['other']; }],
  ['device', x => { x.HostConfig.Devices = ['/dev/sda']; }],
  ['persistent volume', x => { x.Mounts = [{ Type: 'volume', Destination: '/var/lib/postgresql/data' }]; }],
  ['missing tmpfs', x => { x.HostConfig.Tmpfs = {}; }],
  ['wrong PGDATA', x => { x.Config.Env = ['PGDATA=/old']; }],
  ['duplicate PGDATA', x => { x.Config.Env.push('PGDATA=/old'); }],
  ['unexpected trust authentication', x => { x.Config.Env.push('POSTGRES_HOST_AUTH_METHOD=trust'); }],
  ['changed bootstrap password', x => { x.Config.Env = x.Config.Env.map(v => v.startsWith('POSTGRES_PASSWORD=') ? 'POSTGRES_PASSWORD=changed' : v); }],
  ['auto-remove', x => { x.HostConfig.AutoRemove = true; }],
  ['restart policy', x => { x.HostConfig.RestartPolicy.Name = 'always'; }],
  ['publish-all', x => { x.HostConfig.PublishAllPorts = true; }],
  ['requested wildcard host', x => { x.HostConfig.PortBindings['5432/tcp'][0].HostIp = '0.0.0.0'; }],
  ['actual wildcard host', x => { x.NetworkSettings.Ports['5432/tcp'][0].HostIp = '0.0.0.0'; }],
  ['zero actual port', x => { x.NetworkSettings.Ports['5432/tcp'][0].HostPort = '0'; }],
  ['actual port newline', x => { x.NetworkSettings.Ports['5432/tcp'][0].HostPort = '39421\n'; }],
  ['actual port numeric type', x => { x.NetworkSettings.Ports['5432/tcp'][0].HostPort = 39421; }],
  ['multiple actual bindings', x => { x.NetworkSettings.Ports['5432/tcp'].push({ HostIp: '::', HostPort: '39421' }); }],
  ['extra published port', x => { x.NetworkSettings.Ports['80/tcp'] = [{ HostIp: '127.0.0.1', HostPort: '39422' }]; }],
  ['missing config', x => { delete x.HostConfig; }],
  ['missing running state', x => { delete x.State.Running; }],
  ['null requested binding', x => { x.HostConfig.PortBindings['5432/tcp'][0] = null; }],
  ['null actual binding', x => { x.NetworkSettings.Ports['5432/tcp'][0] = null; }],
]) {
  test(`reject ${name} independently`, () => {
    const x = inspected(); mutate(x);
    assert.throws(() => assertInstanceOwnership(target, x, 'running'), /instance ownership/i);
  });
}

test('accept a valid offset timestamp representing the same instant', () => {
  const x = inspected(); x.Created = '2026-10-28T08:01:00.123456789+08:00';
  assert.doesNotThrow(() => assertInstanceOwnership(target, x, 'running'));
});

test('accept exact sub-millisecond lower boundary', () => {
  const x = inspected(); x.Created = '2026-10-28T00:00:00.123456789Z';
  assert.doesNotThrow(() => assertInstanceOwnership({ ...target, createdAfter: x.Created }, x, 'running'));
});

test('reject malformed target ID even when observed ID matches', () => {
  const x = inspected(); x.Id = '123';
  assert.throws(() => assertInstanceOwnership({ ...target, id: x.Id }, x, 'running'), /instance ownership/i);
});

test('reject target name not derived from nonce even when observed name matches', () => {
  const x = inspected(); x.Name = 'aifi45-ci-other';
  assert.throws(() => assertInstanceOwnership({ ...target, name: x.Name }, x, 'running'), /instance ownership/i);
});

test('reject invalid nonce even when name and label match it', () => {
  const x = inspected(), nonce = 'z123456789abcdef';
  x.Name = `aifi45-ci-${nonce}`; x.Config.Labels['aifi45.ci.nonce'] = nonce;
  assert.throws(() => assertInstanceOwnership({ ...target, nonce, name: x.Name }, x, 'running'), /instance ownership/i);
});

test('reject invalid image even when observed image matches', () => {
  const x = inspected(); x.Image = 'z'.repeat(64);
  assert.throws(() => assertInstanceOwnership({ ...target, image: x.Image }, x, 'running'), /instance ownership/i);
});

test('reject newline in an otherwise consistent full ID', () => {
  const x = inspected(); x.Id = '1'.repeat(63) + '\n';
  assert.throws(() => assertInstanceOwnership({ ...target, id: x.Id }, x, 'running'), /instance ownership/i);
});

test('reject a normalised invalid calendar date even when the entire window matches', () => {
  const x = inspected(); x.Created = '2026-02-30T00:01:00Z';
  assert.throws(() => assertInstanceOwnership({ ...target, createdAfter: '2026-02-30T00:00:00Z', createdBefore: '2026-02-30T00:02:00Z' }, x, 'running'), /instance ownership/i);
});

test('reject non-RFC3339 creation window', () => {
  assert.throws(() => assertInstanceOwnership({ ...target, createdAfter: 'Wed, 28 Oct 2026 00:00:00 GMT' }, inspected(), 'running'), /instance ownership/i);
});

test('reject a missing state mode', () => {
  assert.throws(() => assertInstanceOwnership(target, inspected()), /instance ownership/i);
});

test('reject an unknown state mode', () => {
  assert.throws(() => assertInstanceOwnership(target, inspected(), false), /instance ownership/i);
});

test('requires a running instance when performing runtime work', () => {
  const x = inspected(); x.State.Running = false; x.State.Status = 'exited';
  assert.throws(() => assertInstanceOwnership(target, x, 'running'), /instance ownership/i);
  assert.doesNotThrow(() => assertInstanceOwnership(target, x, 'stopped'));
});

test('accepts an explicitly created instance without a published runtime port', () => {
  const x = inspected(); x.State.Running = false; x.State.Status = 'created'; x.NetworkSettings.Ports = null;
  assert.doesNotThrow(() => assertInstanceOwnership(target, x, 'created'));
});

test('does not accept a running instance when a stopped one is required', () => {
  assert.throws(() => assertInstanceOwnership(target, inspected(), 'stopped'), /instance ownership/i);
});

test('stopped instance still requires a valid requested port structure', () => {
  const x = inspected(); x.State.Running = false; x.State.Status = 'exited';
  x.HostConfig.PortBindings['5432/tcp'][0].HostPort = 'notaport';
  x.NetworkSettings.Ports = null;
  assert.throws(() => assertInstanceOwnership(target, x, 'stopped'), /instance ownership/i);
});

test('stopped instance rejects an actual wildcard binding if still reported', () => {
  const x = inspected(); x.State.Running = false; x.State.Status = 'exited';
  x.NetworkSettings.Ports['5432/tcp'][0].HostIp = '0.0.0.0';
  assert.throws(() => assertInstanceOwnership(target, x, 'stopped'), /instance ownership/i);
});

test('reject overbroad creation window', () => {
  assert.throws(() => assertInstanceOwnership({ ...target, createdBefore: '2036-10-28T00:00:00.000Z' }, inspected(), 'running'), /instance ownership/i);
});

test('reject non-string environment entries', () => {
  const x = inspected(); x.Config.Env.push(null);
  assert.throws(() => assertInstanceOwnership(target, x, 'running'), /instance ownership/i);
});
