// AIFIRST: isolated CI verification instance lifecycle.
import { types } from 'node:util';
import { assertInstanceIntent, assertInstanceOwnership } from './instance-ownership.mjs';

export function runOwnedInstance(options) {
  let engine, record, runProbe, target;
  try {
    let inputTarget;
    ({ engine, record, target: inputTarget, runProbe } = options);
    target = Object.freeze({ name: inputTarget?.name, nonce: inputTarget?.nonce, image: inputTarget?.image,
      createdAfter: inputTarget?.createdAfter, createdBefore: inputTarget?.createdBefore,
      expectedEnv: Object.freeze({ ...inputTarget?.expectedEnv }) });
  } catch { throw Error('instance intent unreadable'); }
  let id, runtimePort, requestedPort, trusted = false, failed = null, hadFailure = false, cleaned = false;
  const event = (name, details) => {
    const acknowledged = record(name, details);
    if (acknowledged !== true) {
      if (acknowledged && typeof acknowledged.then === 'function') Promise.resolve(acknowledged).catch(() => {});
      throw Error('journal record not synchronously confirmed');
    }
  };
  const check = (mode, observed) => {
    try {
      assertInstanceOwnership({ ...target, id }, observed, mode);
      if (requestedPort !== undefined) {
        const actual = observed.NetworkSettings.Ports?.['5432/tcp'];
        if (observed.HostConfig.PortBindings['5432/tcp'][0].HostPort !== requestedPort ||
            (runtimePort && actual?.length && actual[0].HostPort !== runtimePort)) throw Error('instance port changed');
      }
    } catch (err) { trusted = false; throw err; }
  };
  let phase = 'intent validation';
  try {
    assertInstanceIntent(target);
    phase = 'intent journal';
    event('intent', { name: target.name, nonce: target.nonce, image: target.image,
      createdAfter: target.createdAfter, createdBefore: target.createdBefore });
    phase = 'create';
    id = engine.create(target);
    if (typeof id !== 'string' || id.length !== 64 || !/^[0-9a-f]{64}$/.test(id)) {
      id = undefined;
      throw Error('create acknowledgement unresolved');
    }
    phase = 'created journal';
    event('created', { id, name: target.name });
    phase = 'created ownership';
    const created = engine.inspect(id);
    check('created', created);
    requestedPort = created.HostConfig.PortBindings['5432/tcp'][0].HostPort;
    trusted = true;
    phase = 'start';
    trusted = false;
    if (engine.start(id) !== true) throw Error('instance start unresolved');
    phase = 'running ownership';
    const started = engine.inspect(id);
    check('running', started);
    runtimePort = started.NetworkSettings.Ports['5432/tcp'][0].HostPort;
    trusted = false;
    phase = 'probe';
    const result = runProbe(id);
    if (types.isPromise(result)) {
      Promise.prototype.then.call(result, undefined, () => {});
      throw Error('probe exit unresolved');
    }
    const then = result?.then, exited = result?.exited, code = result?.code;
    if (!result || typeof then === 'function' || exited !== true ||
        !Number.isInteger(code) || code < 0 || code > 255) throw Error('probe exit unresolved');
    trusted = true;
    if (code !== 0) throw Error(`probe failed with exit ${code}`);
  } catch {
    hadFailure = true;
    failed = `instance ${phase} failed`;
    try { event('failure', { error: failed, id: id || null }); }
    catch { trusted = false; failed += '; instance failure journal failed'; }
  } finally {
    if (id && trusted) {
      let cleanupPhase = 'cleanup inspection';
      try {
        let observed = engine.inspect(id);
        const mode = observed?.State?.Running ? 'running' : observed?.State?.Status === 'created' ? 'created' : 'stopped';
        check(mode, observed);
        if (mode === 'running') {
          cleanupPhase = 'stop';
          if (engine.stop(id) !== true) throw Error('instance stop unresolved');
          cleanupPhase = 'stopped ownership';
          observed = engine.inspect(id);
          check('stopped', observed);
        }
        cleanupPhase = 'remove';
        if (engine.remove(id) !== true) throw Error('instance removal unresolved');
        cleanupPhase = 'absence verification';
        const idPresent = engine.exists(id);
        const namePresent = engine.exists(target.name);
        if (idPresent !== false || namePresent !== false) throw Error('instance absence unresolved');
        cleanupPhase = 'cleaned journal';
        event('cleaned', { id, name: target.name });
        cleaned = true;
      } catch {
        hadFailure = true;
        const cleanupError = `instance ${cleanupPhase} failed`;
        failed = [failed, cleanupError].filter(Boolean).join('; ');
        try { event('cleanup-failed', { id, error: cleanupError }); }
        catch { failed += '; instance cleanup journal failed'; }
      }
    }
  }
  if (hadFailure || !cleaned) throw Error(failed || 'instance cleanup unresolved');
  return { cleaned: true };
}
