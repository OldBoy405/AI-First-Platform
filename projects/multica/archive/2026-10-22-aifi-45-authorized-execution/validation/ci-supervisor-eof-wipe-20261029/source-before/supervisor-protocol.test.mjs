// AIFI-45 v1 complete-buffer protocol contract (no process or I/O integration):
// Each frame has a 12-byte header: u8 version=1, u8 type, u16 reserved=0,
// u32 sequence, u32 payload length; integers are unsigned big-endian. Sequence
// starts at 0 and increases by one for every frame, including the terminal.
// Types 1 and 2 are opaque stdout and stderr bytes, discarded, length 0..1024.
// Type 3 is the sole terminal, exactly one byte: 0=EXITED_ZERO,
// 1=EXITED_NONZERO, 2=REJECTED, 3=OUTPUT_LIMIT. Unknown values are invalid.
// The frame limit is 1036 bytes including header, total limit is 65536 bytes,
// and at most 128 frames are allowed including terminal. Exactly one terminal
// must end the buffer; even one byte after it is invalid. A data-frame boundary
// without a terminal is MISSING_TERMINAL, including exactly 128 data frames.
// A subsequent partial header after 128 data frames is FRAME_COUNT_LIMIT.
// After the input and total-size checks, error precedence is frame count, partial
// header, version/reserved, sequence,
// type, frame size, terminal length, partial body, terminal value, trailing data.
// Thus a valid header with an incomplete body is TRUNCATED. Limits apply to the
// received wire bytes, not to output or reconstructed text. Fixed error enums:
// INVALID_INPUT, TOTAL_LIMIT, FRAME_COUNT_LIMIT, TRUNCATED, INVALID_HEADER,
// INVALID_SEQUENCE, INVALID_TYPE, FRAME_LIMIT, INVALID_LENGTH, INVALID_TERMINAL,
// TRAILING_DATA, MISSING_TERMINAL. Every result is frozen with a null prototype
// and exactly two enumerable own data properties. Errors contain only
// {decoded:false,error:<enum>}, never partial results. Success contains only
// {decoded:true,reportedOutcome:<enum>}. decoded means wire decoding succeeded;
// it does not imply successful execution, OS exit, or permission to clean up.
// Success returns only the wrapper's reported outcome, not stdout/stderr. No
// frame can assert treeEmpty, prove OS exit, or authorize cleanup. Buffer input
// is exclusively a complete, stable, non-shared buffer from a fixed trusted
// wrapper; no provenance authentication or streaming/collection is performed.
// This slice relies on trusted same-process built-ins. The bounded copy is not
// a cross-thread synchronization guarantee. Buffer.isBuffer may invoke proxy
// traps, including getPrototypeOf; the decoder must not read non-Buffer length.
import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeSupervisorBuffer } from './supervisor-protocol.mjs';

const HEADER = 12;
const MAX_PAYLOAD = 1024;
const MAX_TOTAL = 65536;
const MAX_FRAMES = 128;
const secret = Buffer.from('test-secret:stderr:must-not-be-returned');

function frame(type, sequence, payload = Buffer.alloc(0), version = 1, reserved = 0) {
  const header = Buffer.alloc(HEADER);
  header.writeUInt8(version, 0);
  header.writeUInt8(type, 1);
  header.writeUInt16BE(reserved, 2);
  header.writeUInt32BE(sequence, 4);
  header.writeUInt32BE(payload.length, 8);
  return Buffer.concat([header, payload]);
}
const terminal = (sequence, outcome = 0) => frame(3, sequence, Buffer.from([outcome]));
const data = (sequence, payload = secret, type = 2) => frame(type, sequence, payload);
const join = (...frames) => Buffer.concat(frames);
// Assertions intentionally compare only booleans, never display actual data.
function decode(input) {
  try { return decodeSupervisorBuffer(input); } catch { assert.fail('decoder threw'); }
}
function assertResult(result, decoded, detail) {
  let object = false, nullPrototype = false, frozen = false, keysMatch = false, fieldsMatch = false;
  try {
    object = result !== null && typeof result === 'object';
    if (object) {
      nullPrototype = Object.getPrototypeOf(result) === null;
      frozen = Object.isFrozen(result);
      const field = decoded ? 'reportedOutcome' : 'error';
      const keys = Reflect.ownKeys(result);
      keysMatch = keys.length === 2 && keys.includes('decoded') && keys.includes(field);
      const d = Object.getOwnPropertyDescriptor(result, 'decoded');
      const v = Object.getOwnPropertyDescriptor(result, field);
      const fixed = x => x && Object.hasOwn(x, 'value') && x.enumerable && !x.writable && !x.configurable;
      fieldsMatch = fixed(d) && fixed(v) && d.value === decoded && v.value === detail;
    }
  } catch { /* Report only a fixed assertion, not thrown input or payload. */ }
  assert.equal(object, true, 'result must be an object');
  assert.equal(nullPrototype, true, 'result must have null prototype');
  assert.equal(frozen, true, 'result must be frozen');
  assert.equal(keysMatch, true, 'result must have exactly the allowed own keys');
  assert.equal(Boolean(fieldsMatch), true, 'result fields must be fixed and match the contract');
}
const fail = (buffer, error) => assertResult(decode(buffer), false, error);
const pass = (buffer, outcome) => assertResult(decode(buffer), true, outcome);

test('all terminal outcomes are only wrapper reports; data is always discarded', () => {
  for (const [value, label] of ['EXITED_ZERO', 'EXITED_NONZERO', 'REJECTED', 'OUTPUT_LIMIT'].entries()) {
    const bytes = join(data(0, secret, 1), data(1, secret, 2), terminal(2, value));
    const before = Buffer.from(bytes);
    pass(bytes, label);
    assert.equal(bytes.equals(before), true, 'decoder must not mutate input');
  }
  pass(terminal(0), 'EXITED_ZERO');
});

test('accepts nonzero-offset Buffer views and empty opaque frames', () => {
  const wire = join(data(0, Buffer.alloc(0), 1), data(1, Buffer.alloc(0), 2), terminal(2, 1));
  const larger = join(secret, wire, secret);
  pass(larger.subarray(secret.length, secret.length + wire.length), 'EXITED_NONZERO');
});

for (const property of ['length', 'byteLength']) {
  test(`own ${property} cannot change the actual Buffer view length`, () => {
    for (const forged of [0, MAX_TOTAL + 1]) {
      const wire = join(data(0), terminal(1, 1));
      Object.defineProperty(wire, property, { value: forged });
      pass(wire, 'EXITED_NONZERO');
    }
  });
  test(`own ${property} cannot hide an actual total-limit overflow`, () => {
    const oversized = Buffer.alloc(MAX_TOTAL + 1);
    terminal(0).copy(oversized);
    secret.copy(oversized, HEADER + 1);
    Object.defineProperty(oversized, property, { value: HEADER + 1 });
    fail(oversized, 'TOTAL_LIMIT');
  });
}

function offsetView() {
  const backing = new ArrayBuffer(256);
  const outside = Buffer.from(backing);
  secret.copy(outside, 0);
  secret.copy(outside, 160);
  const wire = terminal(0, 1);
  const bytes = Buffer.from(backing, 80, wire.length);
  wire.copy(bytes);
  return bytes;
}

test('own byteOffset cannot redirect the actual Buffer view', () => {
  const wire = offsetView();
  Object.defineProperty(wire, 'byteOffset', { value: 0 });
  pass(wire, 'EXITED_NONZERO');
});

test('own buffer cannot substitute a different backing store', () => {
  const wire = offsetView();
  const decoy = new ArrayBuffer(256);
  terminal(0, 0).copy(Buffer.from(decoy, 80, HEADER + 1));
  Object.defineProperty(wire, 'buffer', { value: decoy });
  pass(wire, 'EXITED_NONZERO');
});

test('own buffer cannot hide or invent a shared backing store', () => {
  const shared = Buffer.from(new SharedArrayBuffer(HEADER + 1));
  terminal(0).copy(shared);
  const decoy = new ArrayBuffer(HEADER + 1);
  terminal(0).copy(Buffer.from(decoy));
  Object.defineProperty(shared, 'buffer', { value: decoy });
  fail(shared, 'INVALID_INPUT');

  const nonshared = offsetView();
  Object.defineProperty(nonshared, 'buffer', { value: new SharedArrayBuffer(256) });
  pass(nonshared, 'EXITED_NONZERO');
});

test('non-Buffer length is never read; proxy prototype traps may run', t => {
  let lengthReads = 0, prototypeChecks = 0;
  const object = { get length() { lengthReads++; return HEADER + 1; } };
  fail(object, 'INVALID_INPUT');
  const proxy = new Proxy(object, {
    getPrototypeOf(target) { prototypeChecks++; return Reflect.getPrototypeOf(target); },
  });
  assert.equal(Buffer.isBuffer(proxy), false);
  const probeChecks = prototypeChecks;
  prototypeChecks = 0;
  fail(proxy, 'INVALID_INPUT');
  assert.equal(lengthReads, 0);
  // The runtime may invoke this trap for Buffer.isBuffer; compare against an
  // observed direct probe rather than assuming that the trap cannot run.
  if (probeChecks > 0) assert.equal(prototypeChecks > 0, true, 'decoder observes the runtime Buffer.isBuffer trap');
  t.diagnostic(`proxy getPrototypeOf trap calls: direct=${probeChecks}, decoder=${prototypeChecks}`);
  fail(new Proxy({}, { getPrototypeOf() { throw new Error(secret.toString()); } }), 'INVALID_INPUT');
});

test('only a non-shared Buffer is accepted', () => {
  const bad = [null, undefined, 'test-secret', [], new Uint8Array([1]), {}, 123,
    Buffer.from(new SharedArrayBuffer(13))];
  for (const value of bad) fail(value, 'INVALID_INPUT');
});

test('all proper prefixes reject; frame boundaries require a terminal', () => {
  const first = data(0, secret, 1);
  const wire = join(first, terminal(1));
  for (let i = 0; i < wire.length; i++) {
    fail(wire.subarray(0, i), i === 0 || i === first.length ? 'MISSING_TERMINAL' : 'TRUNCATED');
  }
});

test('header version, reserved bits, type and sequence are independently enforced', () => {
  fail(frame(1, 0, secret, 0), 'INVALID_HEADER');
  fail(frame(1, 0, secret, 2), 'INVALID_HEADER');
  fail(frame(1, 0, secret, 1, 1), 'INVALID_HEADER');
  fail(frame(0, 0, secret), 'INVALID_TYPE');
  fail(frame(4, 0, secret), 'INVALID_TYPE'); // No tree-empty assertion exists.
  fail(frame(255, 0, secret), 'INVALID_TYPE');
  fail(terminal(1), 'INVALID_SEQUENCE');
  fail(join(data(0), terminal(0)), 'INVALID_SEQUENCE');
  fail(join(data(0), terminal(2)), 'INVALID_SEQUENCE');
  fail(join(data(0), data(1), terminal(0xffffffff)), 'INVALID_SEQUENCE');
});

test('terminal payload is exact and enumerated, never a field bag', () => {
  fail(frame(3, 0), 'INVALID_LENGTH');
  fail(frame(3, 0, Buffer.from([0, 1])), 'INVALID_LENGTH');
  fail(frame(3, 0, secret), 'INVALID_LENGTH');
  fail(terminal(0, 4), 'INVALID_TERMINAL');
  fail(terminal(0, 255), 'INVALID_TERMINAL');
});

test('error precedence is deterministic when multiple fields are invalid', () => {
  const badHeader = frame(99, 7, Buffer.alloc(0), 2, 1);
  badHeader.writeUInt32BE(0xffffffff, 8);
  fail(badHeader, 'INVALID_HEADER');
  badHeader[0] = 1; badHeader.writeUInt16BE(0, 2);
  fail(badHeader, 'INVALID_SEQUENCE');
  badHeader.writeUInt32BE(0, 4);
  fail(badHeader, 'INVALID_TYPE');
  badHeader[1] = 3;
  fail(badHeader, 'FRAME_LIMIT');
  badHeader.writeUInt32BE(2, 8);
  fail(badHeader, 'INVALID_LENGTH');
  fail(join(terminal(0, 4), secret), 'INVALID_TERMINAL');
});

test('one terminal is required and no bytes may follow it, even another terminal', () => {
  fail(Buffer.alloc(0), 'MISSING_TERMINAL');
  fail(data(0), 'MISSING_TERMINAL');
  fail(join(terminal(0), terminal(1)), 'TRAILING_DATA');
  fail(join(terminal(0, 2), data(1)), 'TRAILING_DATA');
  fail(join(terminal(0, 3), Buffer.from([0xff])), 'TRAILING_DATA');
});

test('frame payload limit includes boundary and rejects oversized declarations before reading body', () => {
  const full = data(0, Buffer.alloc(MAX_PAYLOAD, 0x78));
  pass(join(full, terminal(1)), 'EXITED_ZERO');
  fail(join(data(0, Buffer.alloc(MAX_PAYLOAD + 1)), terminal(1)), 'FRAME_LIMIT');
  const headerOnly = data(0, Buffer.alloc(0));
  headerOnly.writeUInt32BE(0xffffffff, 8);
  fail(headerOnly, 'FRAME_LIMIT');
  const truncated = data(0, Buffer.alloc(0));
  truncated.writeUInt32BE(MAX_PAYLOAD, 8);
  fail(truncated, 'TRUNCATED');
});

test('total wire byte limit is inclusive and enforced before parsing', () => {
  const frames = Array.from({ length: 63 }, (_, i) => data(i, Buffer.alloc(MAX_PAYLOAD)));
  const end = data(63, Buffer.alloc(243));
  const wire = join(...frames, end, terminal(64));
  assert.equal(wire.length, MAX_TOTAL);
  pass(wire, 'EXITED_ZERO');
  fail(join(wire, Buffer.from([0])), 'TOTAL_LIMIT');
  fail(Buffer.alloc(MAX_TOTAL + 1, 0x78), 'TOTAL_LIMIT');
});

test('total limit is checked before copying, while an accepted buffer is copied', async () => {
  const oversized = Buffer.alloc(MAX_TOTAL + 1);
  const valid = terminal(0, 1);
  const originalAllocate = Buffer.allocUnsafeSlow;
  let calls = 0, observedDecode;
  try {
    Buffer.allocUnsafeSlow = function (...args) { calls++; return Reflect.apply(originalAllocate, this, args); };
    ({ decodeSupervisorBuffer: observedDecode } = await import('./supervisor-protocol.mjs?allocation-test'));
  } finally {
    Buffer.allocUnsafeSlow = originalAllocate;
  }
  const overflowResult = observedDecode(oversized);
  const afterOverflow = calls;
  const validResult = observedDecode(valid);
  const afterValid = calls;
  assertResult(overflowResult, false, 'TOTAL_LIMIT');
  assertResult(validResult, true, 'EXITED_NONZERO');
  assert.equal(afterOverflow, 0, 'oversized input must not be copied');
  assert.equal(afterValid - afterOverflow, 1, 'accepted input must exercise the copy observation');
});

test('frame count includes terminal and is inclusive', () => {
  const frames = Array.from({ length: MAX_FRAMES - 1 }, (_, i) => data(i, Buffer.alloc(0)));
  pass(join(...frames, terminal(MAX_FRAMES - 1)), 'EXITED_ZERO');
  fail(join(...frames, data(MAX_FRAMES - 1, Buffer.alloc(0)), terminal(MAX_FRAMES)), 'FRAME_COUNT_LIMIT');
});

test('128 complete data frames with no following bytes have no terminal', () => {
  const frames = Array.from({ length: MAX_FRAMES }, (_, i) => data(i, Buffer.alloc(0)));
  fail(join(...frames), 'MISSING_TERMINAL');
});

test('partial header after 128 data frames hits frame count before truncation', () => {
  const frames = Array.from({ length: MAX_FRAMES }, (_, i) => data(i, Buffer.alloc(0)));
  const next = terminal(MAX_FRAMES);
  for (let size = 1; size < HEADER; size++) {
    fail(join(...frames, next.subarray(0, size)), 'FRAME_COUNT_LIMIT');
  }
});

test('rejection, overflow and parse failures write nothing to stdout or stderr', () => {
  const originalOut = process.stdout.write;
  const originalErr = process.stderr.write;
  const writes = [];
  try {
    process.stdout.write = () => { writes.push(true); return true; };
    process.stderr.write = () => { writes.push(true); return true; };
    for (const bytes of [
      join(data(0), terminal(1, 2)),
      join(data(0), terminal(1, 3)),
      join(data(0), terminal(1, 2), secret),
      join(data(0), terminal(1, 3), secret),
      join(data(0), Buffer.alloc(MAX_TOTAL, 0x78), secret),
    ]) decode(bytes);
  } finally {
    process.stdout.write = originalOut;
    process.stderr.write = originalErr;
  }
  assert.equal(writes.length === 0, true, 'decoder must not write to output streams');
});

test('errors never return earlier data or attacker bytes, including rejection and overflow paths', () => {
  const cases = [
    [join(data(0), terminal(1, 2), secret), 'TRAILING_DATA'],
    [join(data(0), terminal(1, 3), secret), 'TRAILING_DATA'],
    [join(data(0), frame(99, 1, secret)), 'INVALID_TYPE'],
    [join(data(0), frame(3, 1, secret)), 'INVALID_LENGTH'],
    [join(data(0), data(3, secret)), 'INVALID_SEQUENCE'],
    [join(data(0), terminal(1).subarray(0, 12)), 'TRUNCATED'],
    [Buffer.concat([data(0), Buffer.alloc(MAX_TOTAL, 0x78), secret]), 'TOTAL_LIMIT'],
  ];
  for (const [wire, expected] of cases) fail(wire, expected);
});
