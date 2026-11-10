// AIFI-45: zero private snapshots on success and failure. These tests inspect
// owned test-only allocation references, not subprocess or container output.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupervisorCollector } from './supervisor-collector.mjs';

const canary = Buffer.from('erase-canary-82d7f1');
function frame(type, sequence, payload) {
  const h = Buffer.alloc(12);
  h[0] = 1; h[1] = type;
  h.writeUInt32BE(sequence, 4); h.writeUInt32BE(payload.length, 8);
  return Buffer.concat([h, payload]);
}
const terminal = () => frame(3, 1, Buffer.from([0]));

// Capture the allocator at import time in a separate module instance. The
// original is restored before decoding; no output bytes are printed by tests.
test('decoder clears its private unpooled copy on success and all parse failures', async () => {
  const allocated = [];
  const original = Buffer.allocUnsafeSlow;
  const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
  const originalSet = typedArrayPrototype.set;
  const names = ['from', 'copyBytesFrom', 'concat', 'allocUnsafe', 'alloc', 'of'];
  const descriptors = new Map(names.map(name => [name, Object.getOwnPropertyDescriptor(Buffer, name)]));
  let decode, monitoring = false, extraAllocations = 0, copiedIntoPrivate = false;
  const wrappers = new Map(names.map(name => {
    const originalMethod = Buffer[name];
    return [name, function(...args) {
      if (monitoring) extraAllocations++;
      return Reflect.apply(originalMethod, this, args);
    }];
  }));
  const trackedSlow = function(size) {
    const buf = original(size);
    allocated.push(buf);
    return buf;
  };
  function install() {
    Buffer.allocUnsafeSlow = trackedSlow;
    for (const [name, wrapper] of wrappers) Buffer[name] = wrapper;
  }
  function restore() {
    Buffer.allocUnsafeSlow = original;
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(Buffer, name, descriptor);
      else delete Buffer[name];
    }
  }
  try {
    install();
    typedArrayPrototype.set = function(...args) {
      const value = Reflect.apply(originalSet, this, args);
      if (monitoring && allocated.includes(this)) copiedIntoPrivate = this.includes(canary);
      return value;
    };
    ({ decodeSupervisorBuffer: decode } = await import('./supervisor-protocol.mjs?erase-test'));
  } finally {
    restore();
    typedArrayPrototype.set = originalSet;
  }
  for (const [wire, expected] of [
    [Buffer.concat([frame(2, 0, canary), terminal()]), 'EXITED_ZERO'],
    [frame(2, 0, canary), 'MISSING_TERMINAL'],
    [Buffer.concat([frame(2, 0, canary), Buffer.from([1])]), 'TRUNCATED'],
    [Buffer.concat([frame(2, 0, canary), terminal(), Buffer.from([1])]), 'TRAILING_DATA'],
  ]) {
    const before = Buffer.from(wire);
    const count = allocated.length;
    const copiesBefore = extraAllocations;
    copiedIntoPrivate = false;
    let result;
    // Catch selected runtime allocators and methods captured while importing.
    try {
      install();
      monitoring = true;
      result = decode(wire);
    } finally {
      monitoring = false;
      restore();
    }
    assert.equal(allocated.length, count + 1, 'one private allocation required');
    assert.equal(extraAllocations, copiesBefore, 'decoder must not make extra Buffer allocations');
    assert.equal(copiedIntoPrivate, true, 'decoder must copy the canary into its private allocation');
    assert.equal(wire.equals(before), true, 'caller buffer must not be modified');
    assert.equal(result.decoded ? result.reportedOutcome : result.error, expected);
    assert.equal(allocated[count].every(value => value === 0), true, 'private decoder copy must be zeroed');
  }
});

test('collector clears its private buffer after success and representative failure paths', () => {
  for (const mode of ['success', 'parse-failure', 'abort', 'stdout-limit', 'stderr-limit',
    'invalid-input', 'missing-eof', 'after-eof', 'duplicate-eof', 'empty-chunk', 'invalid-event', 'reentrant']) {
    const allocated = [];
    const original = Buffer.alloc;
    let collector;
    try {
      Buffer.alloc = function(size, ...args) {
        const buf = original(size, ...args);
        allocated.push(buf);
        return buf;
      };
      collector = createSupervisorCollector();
    } finally {
      Buffer.alloc = original;
    }
    assert.equal(allocated.length, 1, 'one private collector allocation required');
    const wire = mode === 'parse-failure' ? frame(2, 0, canary) : Buffer.concat([frame(2, 0, canary), terminal()]);
    assert.equal(collector.stdout(wire).ok, true);
    assert.equal(allocated[0].includes(canary), true, 'test must exercise the copied canary');
    if (mode === 'success' || mode === 'parse-failure') {
      assert.equal(collector.stdoutEOF().ok, true);
      assert.equal(collector.stderrEOF().ok, true);
      const result = collector.result();
      assert.equal(mode === 'success' ? result.reportedOutcome : result.error,
        mode === 'success' ? 'EXITED_ZERO' : 'MISSING_TERMINAL');
    } else if (mode === 'after-eof' || mode === 'duplicate-eof') {
      assert.equal(collector.stdoutEOF().ok, true);
      const result = mode === 'after-eof' ? collector.stdout(Buffer.from([1])) : collector.stdoutEOF();
      assert.equal(result.error, mode === 'after-eof' ? 'DATA_AFTER_EOF' : 'DUPLICATE_EOF');
    } else {
      let result;
      switch (mode) {
        case 'abort': result = collector.abort(); break;
        case 'stdout-limit': result = collector.stdout(Buffer.alloc(65537)); break;
        case 'stderr-limit': result = collector.stderr(Buffer.alloc(65537)); break;
        case 'invalid-input': result = collector.stderr({}); break;
        case 'missing-eof': result = collector.result(); break;
        case 'empty-chunk': result = collector.stderr(Buffer.alloc(0)); break;
        case 'invalid-event': result = collector.stderrEOF(1); break;
        case 'reentrant':
          result = collector.stderr(new Proxy({}, { getPrototypeOf() { collector.abort(); throw Error('ignored'); } }));
          break;
      }
      const expected = { abort: 'ABORTED', 'stdout-limit': 'STDOUT_LIMIT', 'stderr-limit': 'STDERR_LIMIT',
        'invalid-input': 'INVALID_INPUT', 'missing-eof': 'MISSING_BOTH_EOF', 'empty-chunk': 'EMPTY_CHUNK',
        'invalid-event': 'INVALID_EVENT', reentrant: 'REENTRANT' };
      assert.equal(result.error, expected[mode]);
    }
    assert.equal(allocated[0].every(value => value === 0), true, 'private collector buffer must be zeroed');
  }
});

for (const malformed of [false, true]) for (const reverse of [false, true]) {
  test(`collector clears private stdout at second EOF before result (malformed=${malformed}, reverse=${reverse})`, () => {
    const allocated = [];
    const original = Buffer.alloc;
    let collector;
    try {
      Buffer.alloc = function(size, ...args) {
        const buffer = original(size, ...args);
        allocated.push(buffer);
        return buffer;
      };
      collector = createSupervisorCollector();
    } finally {
      Buffer.alloc = original;
    }
    assert.equal(allocated.length, 1, 'one private collector allocation required');
    const wire = malformed ? frame(2, 0, canary) : Buffer.concat([frame(2, 0, canary), terminal()]);
    const before = Buffer.from(wire);
    assert.equal(collector.stdout(wire).ok, true);
    assert.equal(allocated[0].includes(canary), true, 'test must observe the copied canary');
    assert.equal((reverse ? collector.stderrEOF() : collector.stdoutEOF()).ok, true);
    assert.equal(allocated[0].includes(canary), true, 'one EOF must not consume incomplete input');
    assert.equal((reverse ? collector.stdoutEOF() : collector.stderrEOF()).ok, true);
    assert.equal(allocated[0].every(value => value === 0), true, 'private buffer must be zero before result');
    assert.equal(wire.equals(before), true, 'caller buffer must not be modified');
    const result = collector.result();
    assert.equal(malformed ? result.error : result.reportedOutcome, malformed ? 'MISSING_TERMINAL' : 'EXITED_ZERO');
  });
}

test('failed EOF erasure cannot later publish a successful result', () => {
  const allocated = [];
  const original = Buffer.alloc;
  let collector;
  try {
    Buffer.alloc = function(size, ...args) {
      const buffer = original(size, ...args);
      allocated.push(buffer);
      return buffer;
    };
    collector = createSupervisorCollector();
  } finally {
    Buffer.alloc = original;
  }
  const privateBuffer = allocated[0];
  assert.equal(collector.stdout(Buffer.concat([frame(2, 0, canary), terminal()])).ok, true);
  assert.equal(privateBuffer.includes(canary), true, 'test must observe the copied canary');
  assert.equal(collector.stdoutEOF().ok, true);
  Object.defineProperty(privateBuffer, 'fill', { configurable: true, value() { throw new Error('injected'); } });
  let threw = false;
  try { collector.stderrEOF(); } catch { threw = true; } finally { delete privateBuffer.fill; }
  assert.equal(threw, true, 'fault injection must reach both erase attempts');
  const result = collector.result();
  assert.equal(result.decoded, false, 'failed erasure must not publish a successful result');
  assert.equal(result.error, 'INVALID_INPUT');
  assert.equal(privateBuffer.every(value => value === 0), true, 'retry must clear the private buffer');
});

for (const reverse of [false, true]) {
  test(`decoder view failure erases private stdout (reverse=${reverse})`, () => {
    const allocated = [];
    const original = Buffer.alloc;
    let collector;
    try {
      Buffer.alloc = function(size, ...args) {
        const buffer = original(size, ...args);
        allocated.push(buffer);
        return buffer;
      };
      collector = createSupervisorCollector();
    } finally {
      Buffer.alloc = original;
    }
    const privateBuffer = allocated[0];
    assert.equal(collector.stdout(Buffer.concat([frame(2, 0, canary), terminal()])).ok, true);
    assert.equal(privateBuffer.includes(canary), true, 'test must observe the copied canary');
    assert.equal((reverse ? collector.stderrEOF() : collector.stdoutEOF()).ok, true);
    Object.defineProperty(privateBuffer, 'subarray', { configurable: true, value() { throw new Error('injected'); } });
    let result;
    try { result = reverse ? collector.stdoutEOF() : collector.stderrEOF(); } finally { delete privateBuffer.subarray; }
    assert.equal(result.error, 'INVALID_INPUT');
    assert.equal(privateBuffer.every(value => value === 0), true, 'exception path must erase the private buffer');
    assert.equal(collector.result().error, 'INVALID_INPUT');
  });
}
