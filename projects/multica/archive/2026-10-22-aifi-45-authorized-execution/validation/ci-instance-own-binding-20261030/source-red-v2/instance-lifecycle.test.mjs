// AIFIRST: fake-I/O tests for isolated CI verification instance lifecycle.
import test from 'node:test';
import assert from 'node:assert/strict';
import { runOwnedInstance } from './instance-lifecycle.mjs';

const id = 'a'.repeat(64);
const password = 'fake secret/with chars';
function setup() {
  const target = {
    name: 'aifi45-ci-0123456789abcdef', nonce: '0123456789abcdef', image: 'b'.repeat(64),
    createdAfter: '2026-10-28T00:00:00Z', createdBefore: '2026-10-28T00:02:00Z',
    expectedEnv: { PGDATA: '/var/lib/postgresql/data/pgdata', POSTGRES_DB: 'postgres', POSTGRES_USER: 'testuser', POSTGRES_PASSWORD: password },
  };
  const events = [], calls = [], originalName = target.name;
  let state = null;
  let exists = false;
  const engine = {
    create(t) {
      calls.push('create'); exists = true;
      state = {
        Id: id, Name: t.name, Image: t.image, Created: '2026-10-28T00:01:00Z',
        Config: { Labels: { 'aifi45.ci.nonce': t.nonce }, Env: Object.entries(t.expectedEnv).map(([k, v]) => `${k}=${v}`), Entrypoint: ['docker-entrypoint.sh'], Cmd: ['postgres'] },
        HostConfig: { Privileged: false, AutoRemove: false, NetworkMode: 'bridge', PidMode: 'private', IpcMode: 'private', UTSMode: 'private', UsernsMode: '', Binds: [], VolumesFrom: [], Devices: [], CapAdd: [], SecurityOpt: [], Tmpfs: { '/var/lib/postgresql/data': 'rw,size=1073741824' }, PortBindings: { '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '' }] }, PublishAllPorts: false, RestartPolicy: { Name: 'no' } },
        Mounts: [], NetworkSettings: { Ports: null }, State: { Running: false, Status: 'created', Paused: false, Restarting: false, Dead: false },
      };
      return id;
    },
    inspect(value) { calls.push(`inspect:${value}`); assert.equal(value, id); return structuredClone(state); },
    start(value) { calls.push(`start:${value}`); assert.equal(value, id); state.State.Running = true; state.State.Status = 'running'; state.NetworkSettings.Ports = { '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '39421' }] }; return true; },
    stop(value) { calls.push(`stop:${value}`); assert.equal(value, id); state.State.Running = false; state.State.Status = 'exited'; state.NetworkSettings.Ports = null; return true; },
    remove(value) { calls.push(`remove:${value}`); assert.equal(value, id); exists = false; return true; },
    exists(value) { calls.push(`exists:${value}`); assert.ok(value === id || value === originalName); return exists; },
  };
  const record = (name, details) => { calls.push(`record:${name}`); events.push({ name, details }); return true; };
  const runProbe = value => { calls.push(`probe:${value}`); assert.equal(value, id); return { exited: true, code: 0 }; };
  return { target, engine, record, runProbe, calls, events };
}

function run(s) { return runOwnedInstance({ engine: s.engine, record: s.record, target: s.target, runProbe: s.runProbe }); }

test('normal lifecycle validates and removes only the observed full ID', () => {
  const s = setup(); const result = run(s);
  assert.equal(result.cleaned, true);
  const operations = s.calls.filter(x => !x.startsWith('record:'));
  assert.deepEqual(operations, ['create', `inspect:${id}`, `start:${id}`, `inspect:${id}`, `probe:${id}`, `inspect:${id}`, `stop:${id}`, `inspect:${id}`, `remove:${id}`, `exists:${id}`, `exists:${s.target.name}`]);
  assert.ok(s.calls.indexOf('record:intent') < s.calls.indexOf('create'));
  assert.doesNotMatch(JSON.stringify(s.events), /fake secret|fake%20secret/);
});

test('intent failure performs no create', () => {
  const s = setup(); s.record = () => { throw Error('journal unavailable'); };
  assert.throws(() => run(s), /intent journal failed/);
  assert.equal(s.calls.includes('create'), false);
});

test('asynchronous intent acknowledgement never permits create', () => {
  const s = setup(); s.record = () => Promise.resolve(true);
  assert.throws(() => run(s), /journal|record/i);
  assert.equal(s.calls.includes('create'), false);
});

test('false intent acknowledgement never permits create', () => {
  const s = setup(); s.record = () => false;
  assert.throws(() => run(s), /journal|record/i);
  assert.equal(s.calls.includes('create'), false);
});

test('external target mutation cannot replace the pre-creation snapshot', () => {
  const s = setup(), create = s.engine.create, name = s.target.name;
  s.engine.create = t => { s.target.name = 'other'; return create(t); };
  assert.equal(run(s).cleaned, true);
  assert.ok(s.calls.includes(`exists:${name}`));
});

test('invalid creation window never permits create', () => {
  const s = setup(); s.target.createdAfter = 'not a timestamp';
  assert.throws(() => run(s), /instance ownership|intent/i);
  assert.equal(s.calls.includes('create'), false);
});

test('an inverted creation window is rejected before create', () => {
  const s = setup(); s.target.createdAfter = '2026-10-28T00:02:00.000000001Z';
  assert.throws(() => run(s), /intent validation failed/);
  assert.equal(s.calls.includes('create'), false);
});

test('a creation window over 120 seconds is rejected before create', () => {
  const s = setup(); s.target.createdBefore = '2026-10-28T00:02:00.000000001Z';
  assert.throws(() => run(s), /intent validation failed/);
  assert.equal(s.calls.includes('create'), false);
});

test('dangerous bootstrap authentication is rejected before create', () => {
  const s = setup(); s.target.expectedEnv.POSTGRES_HOST_AUTH_METHOD = 'trust';
  assert.throws(() => run(s), /instance ownership|intent/i);
  assert.equal(s.calls.includes('create'), false);
});

test('lost create acknowledgement remains unresolved and never retries or removes', () => {
  const s = setup(), create = s.engine.create;
  s.engine.create = t => { create(t); throw Error('lost create acknowledgement'); };
  assert.throws(() => run(s), /instance create failed/);
  assert.equal(s.calls.filter(x => x === 'create').length, 1);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
  assert.ok(s.events.some(event => event.name === 'failure' && event.details.error === 'instance create failed'));
});

test('malformed create ID is unresolved and never cleaned', () => {
  const s = setup(), create = s.engine.create;
  s.engine.create = t => { create(t); return '123'; };
  assert.throws(() => run(s));
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('wrong identity before start prevents start and cleanup', () => {
  const s = setup(), inspect = s.engine.inspect;
  s.engine.inspect = value => { const x = inspect(value); x.Name = 'other'; return x; };
  assert.throws(() => run(s), /created ownership failed/);
  assert.equal(s.calls.some(x => /^(start|stop|remove):/.test(x)), false);
});

test('inherited requested port with an extra own binding prevents start and removal', () => {
  const s = setup(), inspect = s.engine.inspect;
  s.engine.inspect = value => {
    const x = inspect(value);
    x.HostConfig.PortBindings = Object.assign(Object.create({ '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '' }] }),
      { '80/tcp': [{ HostIp: '0.0.0.0', HostPort: '8080' }] });
    return x;
  };
  assert.throws(() => run(s), /created ownership failed/);
  assert.equal(s.calls.some(x => /^(start|probe|stop|remove|exists):/.test(x)), false);
});

test('inherited tmpfs with an extra own binding prevents start and removal', () => {
  const s = setup(), inspect = s.engine.inspect;
  s.engine.inspect = value => {
    const x = inspect(value);
    x.HostConfig.Tmpfs = Object.assign(Object.create({ '/var/lib/postgresql/data': 'rw,size=1073741824' }),
      { '/unexpected': 'rw' });
    return x;
  };
  assert.throws(() => run(s), /created ownership failed/);
  assert.equal(s.calls.some(x => /^(start|probe|stop|remove|exists):/.test(x)), false);
});

test('inherited actual running port prevents probe and cleanup after start', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => {
    const x = inspect(value);
    if (++inspections === 2) {
      x.NetworkSettings.Ports = Object.assign(Object.create({ '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '39421' }] }),
        { '80/tcp': [{ HostIp: '0.0.0.0', HostPort: '8080' }] });
    }
    return x;
  };
  assert.throws(() => run(s), /running ownership failed/);
  assert.ok(s.calls.includes(`start:${id}`));
  assert.equal(s.calls.some(x => /^(probe|stop|remove|exists):/.test(x)), false);
});

test('fixed host port in the created instance prevents start and removal', () => {
  const s = setup(), inspect = s.engine.inspect;
  s.engine.inspect = value => { const x = inspect(value); x.HostConfig.PortBindings['5432/tcp'][0].HostPort = '39421'; return x; };
  assert.throws(() => run(s), /created ownership failed/);
  assert.equal(s.calls.some(x => /^(start|stop|remove):/.test(x)), false);
});

test('a changed requested port on first running inspect prevents probe and cleanup', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections >= 2) x.HostConfig.PortBindings['5432/tcp'][0].HostPort = '39421'; return x; };
  assert.throws(() => run(s), /running ownership failed/);
  assert.equal(s.calls.some(x => /^(probe|stop|remove):/.test(x)), false);
});

test('wrong identity at cleanup prevents stop and removal', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections >= 3) x.Id = 'b'.repeat(64); return x; };
  assert.throws(() => run(s), /cleanup inspection failed/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('runtime port drift before cleanup prevents stop and removal', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections >= 3) x.NetworkSettings.Ports['5432/tcp'][0].HostPort = '39422'; return x; };
  assert.throws(() => run(s), /cleanup inspection failed/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('a stopped instance with a changed reported port is preserved', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections === 3) { x.State.Running = false; x.State.Status = 'exited'; x.NetworkSettings.Ports['5432/tcp'][0].HostPort = '39422'; } return x; };
  assert.throws(() => run(s), /cleanup inspection failed/);
  assert.equal(s.calls.some(x => x.startsWith('remove:')), false);
});

test('a changed reported port after stop prevents removal', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections === 4) x.NetworkSettings.Ports = { '5432/tcp': [{ HostIp: '127.0.0.1', HostPort: '39422' }] }; return x; };
  assert.throws(() => run(s), /port|ownership/i);
  assert.equal(s.calls.some(x => x.startsWith('remove:')), false);
});

test('a changed requested port prevents cleanup', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections === 3) x.HostConfig.PortBindings['5432/tcp'][0].HostPort = '39421'; return x; };
  assert.throws(() => run(s), /cleanup inspection failed/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('wrong identity after stop prevents removal', () => {
  const s = setup(), inspect = s.engine.inspect; let inspections = 0;
  s.engine.inspect = value => { const x = inspect(value); if (++inspections >= 4) x.Image = 'c'.repeat(64); return x; };
  assert.throws(() => run(s), /stopped ownership failed/);
  assert.ok(s.calls.includes(`stop:${id}`));
  assert.equal(s.calls.some(x => x.startsWith('remove:')), false);
});

test('throwing error getters cannot escape or permit cleanup after journal failure', () => {
  const s = setup(), record = s.record;
  s.engine.start = () => { throw { get message() { throw Error('FAKE_ONLY_SECRET'); } }; };
  s.record = (event, details) => event === 'failure' ? false : record(event, details);
  assert.throws(() => run(s), error => {
    assert.doesNotMatch(error.message, /FAKE_ONLY_SECRET/);
    return true;
  });
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
  assert.doesNotMatch(JSON.stringify(s.events), /FAKE_ONLY_SECRET/);
});

test('throwing options getters cannot expose their message or create an instance', () => {
  const s = setup();
  const options = { get engine() { throw Error('FAKE_ONLY_SECRET'); }, record: s.record, target: s.target, runProbe: s.runProbe };
  assert.throws(() => runOwnedInstance(options), error => { assert.doesNotMatch(error.message, /FAKE_ONLY_SECRET/); return true; });
  assert.equal(s.calls.includes('create'), false);
});

test('throwing target getters cannot expose their message or create an instance', () => {
  const s = setup();
  Object.defineProperty(s.target, 'name', { get() { throw Error('FAKE_ONLY_SECRET'); } });
  assert.throws(() => run(s), error => { assert.doesNotMatch(error.message, /FAKE_ONLY_SECRET/); return true; });
  assert.equal(s.calls.includes('create'), false);
});

test('an empty start error cannot produce a successful lifecycle', () => {
  const s = setup(); s.engine.start = () => { throw ''; };
  assert.throws(() => run(s), /failed|unresolved/i);
  assert.equal(s.calls.some(x => x.startsWith('probe:')), false);
});

test('an empty cleaned-record error cannot produce a successful lifecycle', () => {
  const s = setup(), record = s.record;
  s.record = (event, details) => { if (event === 'cleaned') throw ''; return record(event, details); };
  assert.throws(() => run(s), /failed|unresolved/i);
  assert.ok(s.calls.includes(`remove:${id}`));
});

test('a finished failing probe still cleans a correctly identified instance and fails', () => {
  const s = setup(); s.runProbe = () => ({ exited: true, code: 1 });
  assert.throws(() => run(s), /probe failed/);
  assert.ok(s.calls.includes(`remove:${id}`));
  assert.ok(s.calls.includes(`exists:${s.target.name}`));
});

test('a failed failure-record acknowledgement preserves the instance', () => {
  const s = setup(), record = s.record;
  s.runProbe = () => ({ exited: true, code: 1 });
  s.record = (event, details) => event === 'failure' ? false : record(event, details);
  assert.throws(() => run(s), /journal|record/i);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
  assert.equal(s.calls.some(x => x === 'record:cleaned'), false);
});

test('an asynchronous failure-record acknowledgement preserves the instance', () => {
  const s = setup(), record = s.record;
  s.runProbe = () => ({ exited: true, code: 1 });
  s.record = (event, details) => event === 'failure' ? Promise.resolve(true) : record(event, details);
  assert.throws(() => run(s), /journal/i);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('a throwing failure-record acknowledgement preserves the instance', () => {
  const s = setup(), record = s.record;
  s.runProbe = () => ({ exited: true, code: 1 });
  s.record = (event, details) => { if (event === 'failure') throw Error('journal unavailable'); return record(event, details); };
  assert.throws(() => run(s), /journal/i);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('a probe throwing without an exit receipt preserves the instance', () => {
  const s = setup(); s.runProbe = () => { throw Error('probe failed'); };
  assert.throws(() => run(s), /probe failed/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('a thenable with forged exit fields does not prove process exit', () => {
  const s = setup(); s.runProbe = () => ({ then() {}, exited: true, code: 0 });
  assert.throws(() => run(s), /probe|exit/i);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('a Promise proxy hiding then cannot forge a synchronous exit receipt', () => {
  const s = setup(), keys = [];
  const pending = new Promise(() => {});
  s.runProbe = value => {
    s.calls.push(`probe:${value}`);
    return new Proxy(pending, { get(_target, key) {
      keys.push(String(key));
      return key === 'exited' ? true : key === 'code' ? 0 : undefined;
    } });
  };
  assert.throws(() => run(s), error => error.message === 'instance probe failed');
  assert.deepEqual(keys, []);
  assert.equal(s.calls.some(x => /^(stop|remove|exists):/.test(x)), false);
  assert.equal(s.calls.filter(x => x.startsWith('inspect:')).length, 2);
  assert.deepEqual(s.events.map(event => event.name), ['intent', 'created', 'failure']);
  assert.doesNotMatch(JSON.stringify(s.events), /fake secret|fake%20secret/);
});

test('a transparent proxy exit receipt is rejected without cleanup', () => {
  const s = setup(); s.runProbe = () => new Proxy({ exited: true, code: 0 }, {});
  assert.throws(() => run(s), /instance probe failed/);
  assert.equal(s.calls.some(x => /^(stop|remove|exists):/.test(x)), false);
  assert.equal(s.events.some(event => event.name === 'cleaned'), false);
});

test('a revoked proxy exit receipt is rejected without cleanup', () => {
  const s = setup(), receipt = Proxy.revocable({ exited: true, code: 0 }, {});
  receipt.revoke();
  s.runProbe = () => receipt.proxy;
  assert.throws(() => run(s), /instance probe failed/);
  assert.equal(s.calls.some(x => /^(stop|remove|exists):/.test(x)), false);
  assert.equal(s.events.some(event => event.name === 'cleaned'), false);
});

test('an exception reading an exit field preserves the instance', () => {
  const s = setup(); s.runProbe = () => ({ get exited() { throw Error('receipt unreadable'); } });
  assert.throws(() => run(s), /instance probe failed/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('a rejected Promise probe is consumed without reporting its secret', async () => {
  const s = setup();
  s.runProbe = () => Promise.reject(new Error(password));
  assert.throws(() => run(s), /instance probe failed/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
  await new Promise(resolve => setImmediate(resolve));
});

test('a child-process-like handle does not prove exit and preserves the instance', () => {
  const s = setup(); s.runProbe = () => ({ pid: 123, exitCode: null });
  assert.throws(() => run(s), /probe|exit/i);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});

test('an asynchronous start result cannot prove start or permit cleanup', () => {
  const s = setup(), start = s.engine.start;
  s.engine.start = value => { start(value); return Promise.resolve(true); };
  assert.throws(() => run(s), /start failed/);
  assert.equal(s.calls.some(x => /^(probe|stop|remove):/.test(x)), false);
});

test('an asynchronous stop result cannot permit remove', () => {
  const s = setup(), stop = s.engine.stop;
  s.engine.stop = value => { stop(value); return Promise.resolve(true); };
  assert.throws(() => run(s), /stop failed/);
  assert.equal(s.calls.some(x => x.startsWith('remove:')), false);
});

test('an asynchronous remove result cannot claim successful cleanup', () => {
  const s = setup(), remove = s.engine.remove;
  s.engine.remove = value => { remove(value); return Promise.resolve(true); };
  assert.throws(() => run(s), /remove failed/);
  assert.equal(s.calls.some(x => x === 'record:cleaned'), false);
});

for (const [label, value] of [['false', false], ['undefined', undefined], ['truthy string', 'true'], ['truthy number', 1]]) {
  for (const operation of ['start', 'stop', 'remove']) {
    test(`${operation} ${label} is not a synchronous confirmation`, () => {
      const s = setup(), original = s.engine[operation];
      s.engine[operation] = id => { original(id); return value; };
      assert.throws(() => run(s), new RegExp(`${operation} failed`));
      assert.equal(s.calls.includes('record:cleaned'), false);
      if (operation === 'start') assert.equal(s.calls.some(x => /^(probe|stop|remove):/.test(x)), false);
      if (operation === 'stop') assert.equal(s.calls.some(x => x.startsWith('remove:')), false);
    });
  }
}

test('stop failure does not attempt remove', () => {
  const s = setup(); s.engine.stop = value => { s.calls.push(`stop:${value}`); throw Error('stop failed'); };
  assert.throws(() => run(s), /stop failed/);
  assert.equal(s.calls.some(x => x.startsWith('remove:')), false);
});

test('remove failure is not treated as success', () => {
  const s = setup(); s.engine.remove = value => { s.calls.push(`remove:${value}`); throw Error('remove failed'); };
  assert.throws(() => run(s), /remove failed/);
});

test('ID absent but name still present cannot be claimed as cleanup', () => {
  const s = setup(); s.engine.exists = value => { s.calls.push(`exists:${value}`); return value === s.target.name; };
  assert.throws(() => run(s), /absence|unresolved/i);
  assert.ok(s.calls.includes(`exists:${id}`) && s.calls.includes(`exists:${s.target.name}`));
});

test('name absent but ID still present cannot be claimed as cleanup', () => {
  const s = setup(); s.engine.exists = value => { s.calls.push(`exists:${value}`); return value === id; };
  assert.throws(() => run(s), /absence|unresolved/i);
  assert.ok(s.calls.includes(`exists:${id}`) && s.calls.includes(`exists:${s.target.name}`));
});

test('indeterminate absence cannot be claimed as cleanup', () => {
  const s = setup(); s.engine.exists = value => { s.calls.push(`exists:${value}`); return undefined; };
  assert.throws(() => run(s), /absence|unresolved/i);
});

test('escaped and raw passwords never enter journal or thrown errors', () => {
  const s = setup(); s.runProbe = () => { throw Error(`failed ${password} ${encodeURIComponent(password)} ${new URLSearchParams({ x: password }).toString()}`); };
  assert.throws(() => run(s), err => {
    assert.match(err.message, /failed/);
    assert.doesNotMatch(err.message, /fake secret|fake%20secret|fake\+secret/);
    return true;
  });
  assert.doesNotMatch(JSON.stringify(s.events), /fake secret|fake%20secret|fake\+secret/);
  assert.equal(s.calls.some(x => /^(stop|remove):/.test(x)), false);
});
