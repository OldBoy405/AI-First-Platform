// Controlled-event collector contract: no transport, authentication, OS-exit
// evidence, process-tree assertion, cleanup permission, or lifecycle integration.
// Each channel has a fixed inclusive byte limit. Empty data events are errors;
// an entirely empty stdout is also an error. result() seals missing EOF as a
// sticky failure. The first failure, including a decoder failure, always wins.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupervisorCollector, STDOUT_LIMIT, STDERR_LIMIT } from './supervisor-collector.mjs';

const secret = 'collector-canary-7e124b';
const byte = Buffer.from(secret);
function frame(type, sequence, payload) {
  const h = Buffer.alloc(12);
  h[0] = 1; h[1] = type;
  h.writeUInt32BE(sequence, 4); h.writeUInt32BE(payload.length, 8);
  return Buffer.concat([h, payload]);
}
const end = n => frame(3, 0, Buffer.from([n]));
const error = name => ({ decoded: false, error: name });
const ok = { ok: true };
function check(actual, expected) {
  // Never print caller-controlled values if an assertion fails.
  let valid = false;
  try {
    const keys = Reflect.ownKeys(actual);
    const expectedKeys = Object.keys(expected);
    valid = Object.getPrototypeOf(actual) === null && Object.isFrozen(actual) &&
      keys.length === expectedKeys.length && expectedKeys.every(key => {
        const d = Object.getOwnPropertyDescriptor(actual, key);
        return d && 'value' in d && d.enumerable && !d.writable && !d.configurable && d.value === expected[key];
      });
  } catch { /* Fixed diagnostics only. */ }
  assert.equal(valid, true, 'result must contain only the expected fixed fields');
}
function safely(fn) {
  try { return fn(); } catch { assert.fail('collector unexpectedly threw'); }
}
const step = (fn, expected = ok) => check(safely(fn), expected);
function complete(c, wire = end(0)) {
  step(() => c.stdout(wire));
  step(() => c.stdoutEOF());
  step(() => c.stderrEOF());
}
function assertSticky(c, expected) {
  for (const action of [() => c.stdout(byte), () => c.stderr(byte), () => c.stdoutEOF(),
    () => c.stderrEOF(), () => c.abort(), () => c.result()]) step(action, expected);
}
function maxWire() {
  const parts = Array.from({ length: 63 }, (_, i) => frame(1, i, Buffer.alloc(1024, 0x78)));
  parts.push(frame(2, 63, Buffer.alloc(243, 0x78)));
  parts.push(frame(3, 64, Buffer.from([1])));
  return Buffer.concat(parts);
}

test('limits are fixed finite byte counts', () => {
  assert.equal(STDOUT_LIMIT, 65536);
  assert.equal(STDERR_LIMIT, 65536);
});

test('all decoder outcomes are exposed only as fixed reports after both EOFs', () => {
  for (const [n, reportedOutcome] of ['EXITED_ZERO', 'EXITED_NONZERO', 'REJECTED', 'OUTPUT_LIMIT'].entries()) {
    for (const reverse of [false, true]) {
      const c = createSupervisorCollector();
      const first = frame(1, 0, byte);
      const wire = Buffer.concat([first, frame(2, 1, byte), frame(3, 2, Buffer.from([n]))]);
      for (let i = 0; i < wire.length; i++) step(() => c.stdout(wire.subarray(i, i + 1)));
      step(() => c.stderr(byte));
      step(() => reverse ? c.stderrEOF() : c.stdoutEOF());
      step(() => reverse ? c.stdoutEOF() : c.stderrEOF());
      const result = { decoded: true, reportedOutcome };
      step(() => c.result(), result);
      step(() => c.result(), result);
    }
  }
});

test('snapshots offset views and disregards forged own accessors and later mutations', () => {
  const c = createSupervisorCollector();
  const wire = end(1);
  const backing = Buffer.concat([byte, wire, byte]);
  const part = backing.subarray(byte.length, byte.length + wire.length);
  for (const key of ['length', 'byteLength', 'byteOffset', 'buffer']) {
    Object.defineProperty(part, key, { get() { throw new Error(secret); } });
  }
  step(() => c.stdout(part));
  backing.fill(0);
  step(() => c.stderrEOF()); step(() => c.stdoutEOF());
  step(() => c.result(), { decoded: true, reportedOutcome: 'EXITED_NONZERO' });
});

test('actual buffer length, offset and backing govern limits and shared rejection', () => {
  for (const channel of ['stdout', 'stderr']) {
    const c = createSupervisorCollector();
    const tooBig = Buffer.alloc(65537);
    Object.defineProperty(tooBig, 'length', { value: 1 });
    Object.defineProperty(tooBig, 'byteLength', { value: 1 });
    step(() => c[channel](tooBig), error(channel === 'stdout' ? 'STDOUT_LIMIT' : 'STDERR_LIMIT'));
    assertSticky(c, error(channel === 'stdout' ? 'STDOUT_LIMIT' : 'STDERR_LIMIT'));
    const s = createSupervisorCollector();
    const shared = Buffer.from(new SharedArrayBuffer(16));
    Object.defineProperty(shared, 'buffer', { value: new ArrayBuffer(16) });
    step(() => s[channel](shared), error('INVALID_INPUT'));
    assertSticky(s, error('INVALID_INPUT'));
  }
});

test('exact limits are inclusive across arbitrarily split chunks', () => {
  const c = createSupervisorCollector(), wire = maxWire();
  assert.equal(wire.length, STDOUT_LIMIT);
  for (let i = 0; i < wire.length; i += 137) step(() => c.stdout(wire.subarray(i, i + 137)));
  for (let i = 0; i < STDERR_LIMIT; i += 256) step(() => c.stderr(Buffer.alloc(256, 0x41)));
  step(() => c.stdoutEOF()); step(() => c.stderrEOF());
  step(() => c.result(), { decoded: true, reportedOutcome: 'EXITED_NONZERO' });
});

test('both cumulative and single-chunk overflows fail immediately without partial decoding', () => {
  for (const channel of ['stdout', 'stderr']) {
    const code = channel === 'stdout' ? 'STDOUT_LIMIT' : 'STDERR_LIMIT';
    for (const split of [true, false]) {
      const c = createSupervisorCollector();
      if (split) step(() => c[channel](Buffer.alloc(65536)));
      step(() => c[channel](Buffer.alloc(split ? 1 : 65537)), error(code));
      assertSticky(c, error(code));
    }
  }
});

test('empty chunk and empty stdout are distinct sticky failures', () => {
  for (const channel of ['stdout', 'stderr']) {
    const c = createSupervisorCollector();
    step(() => c[channel](Buffer.alloc(0)), error('EMPTY_CHUNK'));
    assertSticky(c, error('EMPTY_CHUNK'));
  }
  const c = createSupervisorCollector();
  step(() => c.stderr(byte)); step(() => c.stdoutEOF()); step(() => c.stderrEOF());
  step(() => c.result(), error('EMPTY_STDOUT'));
  assertSticky(c, error('EMPTY_STDOUT'));
});

test('result seals missing EOF without handing even a valid wire to the decoder', () => {
  for (const [channel, code] of [[null, 'MISSING_BOTH_EOF'], ['stdout', 'MISSING_STDERR_EOF'], ['stderr', 'MISSING_STDOUT_EOF']]) {
    const c = createSupervisorCollector();
    step(() => c.stdout(end(0)));
    if (channel) step(() => c[`${channel}EOF`]());
    step(() => c.result(), error(code));
    assertSticky(c, error(code));
  }
});

test('data following its own EOF and repeated EOF are distinct sticky failures', () => {
  for (const channel of ['stdout', 'stderr']) {
    for (const event of ['data', 'eof']) {
      const c = createSupervisorCollector();
      step(() => c[`${channel}EOF`]());
      const code = event === 'data' ? 'DATA_AFTER_EOF' : 'DUPLICATE_EOF';
      step(() => event === 'data' ? c[channel](byte) : c[`${channel}EOF`](), error(code));
      assertSticky(c, error(code));
    }
  }
});

test('completion is not immune to later invalid controlled events', () => {
  for (const event of ['data', 'eof']) {
    const c = createSupervisorCollector(); complete(c);
    step(() => c.result(), { decoded: true, reportedOutcome: 'EXITED_ZERO' });
    const code = event === 'data' ? 'DATA_AFTER_EOF' : 'DUPLICATE_EOF';
    step(() => event === 'data' ? c.stdout(byte) : c.stderrEOF(), error(code));
    assertSticky(c, error(code));
  }
});

test('malformed, truncated, missing-terminal and trailing wires return only decoder errors', () => {
  for (const [wire, code] of [[Buffer.from([1]), 'TRUNCATED'], [frame(1, 0, byte), 'MISSING_TERMINAL'],
    [Buffer.concat([end(0), byte]), 'TRAILING_DATA'], [frame(99, 0, byte), 'INVALID_TYPE']]) {
    const c = createSupervisorCollector(); complete(c, wire);
    step(() => c.result(), error(code)); assertSticky(c, error(code));
  }
});

test('only genuine stable Buffer views are accepted; never read non-buffer length', () => {
  let reads = 0;
  const obj = { get length() { reads++; throw new Error(secret); } };
  const { proxy, revoke } = Proxy.revocable({}, {}); revoke();
  const detached = Buffer.from(new ArrayBuffer(16));
  structuredClone(detached.buffer, { transfer: [detached.buffer] });
  const inputs = [null, undefined, secret, [], {}, 1, new Uint8Array(1), obj, proxy, detached,
    new Proxy({}, { getPrototypeOf() { throw new Error(secret); } }), new Proxy(Buffer.alloc(1), {})];
  for (const channel of ['stdout', 'stderr']) for (const value of inputs) {
    const c = createSupervisorCollector();
    step(() => c[channel](value), error('INVALID_INPUT'));
    assertSticky(c, error('INVALID_INPUT'));
  }
  assert.equal(reads, 0);
});

test('reentrant proxy traps cannot cause hidden state transitions or override the first error', () => {
  const c = createSupervisorCollector();
  const hostile = new Proxy({}, { getPrototypeOf() { c.stdoutEOF(); throw new Error(secret); } });
  step(() => c.stdout(hostile), error('REENTRANT'));
  assertSticky(c, error('REENTRANT'));
});

test('abort records a fixed sticky failure before or after EOF without accepting a reason', () => {
  for (const completeFirst of [false, true]) {
    const c = createSupervisorCollector();
    if (completeFirst) complete(c);
    else step(() => c.stdout(end(0)));
    step(() => c.abort(), error('ABORTED'));
    assertSticky(c, error('ABORTED'));
  }
});

test('wrong event arity is rejected without inspecting extra inputs', () => {
  const hostile = new Proxy({}, { get() { throw new Error(secret); } });
  for (const action of [c => c.stdout(), c => c.stderr(byte, hostile), c => c.stdoutEOF(hostile),
    c => c.stderrEOF(hostile), c => c.abort(hostile), c => c.result(hostile)]) {
    const c = createSupervisorCollector(); step(() => action(c), error('INVALID_EVENT'));
    assertSticky(c, error('INVALID_EVENT'));
  }
});

test('collector does not write to streams or leak canaries in any result', () => {
  const out = process.stdout.write, err = process.stderr.write;
  let writes = 0;
  const results = [];
  try {
    process.stdout.write = process.stderr.write = () => { writes++; return true; };
    const c = createSupervisorCollector();
    results.push(c.stdout(Buffer.concat([end(0), byte])), c.stderr(byte), c.stdoutEOF(), c.stderrEOF(), c.result());
    const b = createSupervisorCollector();
    results.push(b.stdout(new Proxy({}, { getPrototypeOf() { throw new Error(secret); } })), b.result());
  } finally { process.stdout.write = out; process.stderr.write = err; }
  assert.equal(writes, 0);
  assert.equal(JSON.stringify(results).includes(secret), false);
});
