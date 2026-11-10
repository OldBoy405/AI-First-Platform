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
  let decode;
  try {
    Buffer.allocUnsafeSlow = function(size) {
      const buf = original(size);
      allocated.push(buf);
      return buf;
    };
    ({ decodeSupervisorBuffer: decode } = await import('./supervisor-protocol.mjs?erase-test'));
  } finally {
    Buffer.allocUnsafeSlow = original;
  }
  for (const [wire, expected] of [
    [Buffer.concat([frame(2, 0, canary), terminal()]), 'EXITED_ZERO'],
    [frame(2, 0, canary), 'MISSING_TERMINAL'],
    [Buffer.concat([frame(2, 0, canary), Buffer.from([1])]), 'TRUNCATED'],
    [Buffer.concat([frame(2, 0, canary), terminal(), Buffer.from([1])]), 'TRAILING_DATA'],
  ]) {
    const before = Buffer.from(wire);
    const count = allocated.length;
    const result = decode(wire);
    assert.equal(allocated.length, count + 1, 'one private allocation required');
    assert.equal(wire.equals(before), true, 'caller buffer must not be modified');
    assert.equal(result.decoded ? result.reportedOutcome : result.error, expected);
    assert.equal(allocated[count].every(value => value === 0), true, 'private decoder copy must be zeroed');
  }
});

test('collector clears its private buffer after success, parse failure and abort', () => {
  for (const mode of ['success', 'parse-failure', 'abort']) {
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
    if (mode === 'abort') {
      assert.equal(collector.abort().error, 'ABORTED');
    } else {
      assert.equal(collector.stdoutEOF().ok, true);
      assert.equal(collector.stderrEOF().ok, true);
      const result = collector.result();
      assert.equal(mode === 'success' ? result.reportedOutcome : result.error,
        mode === 'success' ? 'EXITED_ZERO' : 'MISSING_TERMINAL');
    }
    assert.equal(allocated[0].every(value => value === 0), true, 'private collector buffer must be zeroed');
  }
});
