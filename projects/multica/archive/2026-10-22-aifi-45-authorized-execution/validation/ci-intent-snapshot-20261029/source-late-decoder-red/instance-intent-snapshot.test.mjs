// AIFIRST: intent snapshot boundary tests; no engine or database access.
import test from 'node:test';
import assert from 'node:assert/strict';
import { TextDecoder } from 'node:util';
import { runInNewContext } from 'node:vm';
import { encodeInstanceIntent, decodeInstanceIntent } from './instance-intent-record.mjs';

const target = { name: 'aifi45-ci-0123456789abcdef', nonce: '0123456789abcdef', image: 'a'.repeat(64),
  createdAfter: '2026-10-28T00:00:00Z', createdBefore: '2026-10-28T00:02:00Z',
  expectedEnv: { PGDATA: '/var/lib/postgresql/data/pgdata', POSTGRES_DB: 'x', POSTGRES_USER: 'x', POSTGRES_PASSWORD: 'x' } };
const invalid = /^Error: invalid intent record$/;

test('rejects shared backing before an accepted intent can change after its checksum', () => {
  const original = encodeInstanceIntent(target);
  const changed = encodeInstanceIntent({ ...target, image: 'b'.repeat(64) });
  assert.equal(original.length, changed.length);
  const payloadStart = original.indexOf('{');
  const payloadEnd = original.length - 5;
  assert.ok(payloadStart > 0 && payloadEnd > payloadStart);
  const shared = Buffer.from(new SharedArrayBuffer(original.length));
  shared.set(original);
  const decode = TextDecoder.prototype.decode;
  let swapped = false, returned = null, rejected = false;
  try {
    TextDecoder.prototype.decode = function (...args) {
      shared.set(changed.subarray(payloadStart, payloadEnd), payloadStart);
      swapped = true;
      return decode.apply(this, args);
    };
    try { returned = decodeInstanceIntent(shared); } catch (error) {
      assert.equal(error?.message, 'invalid intent record');
      rejected = true;
    }
  } finally { TextDecoder.prototype.decode = decode; }
  if (!rejected && returned?.image === 'b'.repeat(64)) assert.equal(swapped, true);
  assert.equal(rejected, true, 'shared backing must not be accepted');
});

test('rejects the actual oversized view before traversing a forged own length', () => {
  const bytes = Buffer.alloc(4197);
  Object.defineProperty(bytes, 'length', { value: 1 });
  let traversed = false;
  bytes.indexOf = () => { traversed = true; throw Error('unexpected traversal'); };
  assert.throws(() => decodeInstanceIntent(bytes), invalid);
  assert.equal(traversed, false);
});

test('rejects a Buffer-prototype impostor with a fixed error', () => {
  const fake = Object.create(Buffer.prototype);
  assert.equal(Buffer.isBuffer(fake), true);
  assert.throws(() => decodeInstanceIntent(fake), invalid);
});

test('rejects a valid record in a non-byte impostor and a proxied Buffer with a fixed error', () => {
  let record = encodeInstanceIntent(target);
  if (record.length % 2) record = encodeInstanceIntent({ ...target, createdAfter: '2026-10-28T00:00:00.12Z' });
  assert.equal(record.length % 2, 0);
  const backing = new ArrayBuffer(record.length);
  new Uint8Array(backing).set(record);
  const fake = new Uint16Array(backing);
  Object.setPrototypeOf(fake, Buffer.prototype);
  assert.equal(Buffer.isBuffer(fake), true);
  assert.throws(() => decodeInstanceIntent(fake), invalid);
  assert.throws(() => decodeInstanceIntent(new Proxy(encodeInstanceIntent(target), {})), invalid);
});

test('rejects resizable and detached backing stores with a fixed error', () => {
  const record = encodeInstanceIntent(target);
  const backing = new ArrayBuffer(record.length, { maxByteLength: record.length + 1 });
  const resizable = Buffer.from(backing);
  resizable.set(record);
  assert.throws(() => decodeInstanceIntent(resizable), invalid);
  const detachedBacking = new ArrayBuffer(record.length);
  const detached = Buffer.from(detachedBacking);
  detached.set(record);
  structuredClone(detachedBacking, { transfer: [detachedBacking] });
  assert.throws(() => decodeInstanceIntent(detached), invalid);
});

test('ignores input-owned traversal methods and accepts a nonzero-offset Buffer view', () => {
  const record = encodeInstanceIntent(target);
  const outer = Buffer.alloc(record.length + 16);
  record.copy(outer, 8);
  const view = outer.subarray(8, 8 + record.length);
  view.indexOf = () => { throw Error('input indexOf invoked'); };
  view.subarray = () => { throw Error('input subarray invoked'); };
  for (const key of ['length', 'buffer', 'byteOffset', 'byteLength']) {
    Object.defineProperty(view, key, { get() { throw Error('input property invoked'); } });
  }
  const result = decodeInstanceIntent(view);
  assert.equal(result.name, target.name);
  assert.equal(result.image, target.image);
});

test('accepts a real cross-realm byte view with Buffer-shaped prototype without claiming provenance', () => {
  const record = encodeInstanceIntent(target);
  const view = runInNewContext('new Uint8Array(length)', { length: record.length });
  view.set(record);
  Object.setPrototypeOf(view, Buffer.prototype);
  assert.equal(Buffer.isBuffer(view), true);
  assert.equal(decodeInstanceIntent(view).name, target.name);
});

test('does not expose a snapshot to a decoder method replaced after module initialization', () => {
  const record = encodeInstanceIntent(target);
  const decode = TextDecoder.prototype.decode;
  let invoked = false;
  try {
    TextDecoder.prototype.decode = function (payload) {
      invoked = true;
      const start = payload.indexOf(Buffer.from('"image":"')) + Buffer.byteLength('"image":"');
      payload.fill('b', start, start + 64);
      return decode.call(this, payload);
    };
    const result = decodeInstanceIntent(record);
    assert.equal(result.image, target.image, 'late decoder replacement changed the verified payload');
    assert.equal(invoked, false);
  } finally { TextDecoder.prototype.decode = decode; }
});

test('wipes distinct private snapshots after nested success and malformed input', async () => {
  const allocate = Buffer.allocUnsafeSlow;
  const allocations = [];
  let decodeIntent;
  try {
    Buffer.allocUnsafeSlow = size => { const bytes = allocate(size); allocations.push(bytes); return bytes; };
    ({ decodeInstanceIntent: decodeIntent } = await import('./instance-intent-record.mjs?wipe-observer'));
  } finally { Buffer.allocUnsafeSlow = allocate; }
  const record = encodeInstanceIntent(target);
  const malformed = Buffer.from(record);
  malformed[malformed.length - 1] ^= 1;
  const decode = TextDecoder.prototype.decode;
  let nested = false, observed = false;
  try {
    TextDecoder.prototype.decode = function (...args) {
      if (!nested) {
        nested = true;
        observed = args[0].buffer === allocations[0].buffer && args[0].includes(Buffer.from(target.name));
        const result = decodeIntent(record);
        assert.equal(result.name, target.name);
      }
      return decode.apply(this, args);
    };
    assert.equal(decodeIntent(record).name, target.name);
  } finally { TextDecoder.prototype.decode = decode; }
  assert.equal(nested, true);
  assert.equal(observed, true, 'the inspected allocation received the input');
  assert.equal(allocations.length, 2);
  assert.notEqual(allocations[0], allocations[1]);
  assert.equal(allocations.every(bytes => bytes.every(value => value === 0)), true);
  assert.throws(() => decodeIntent(malformed), invalid);
  assert.equal(allocations.length, 3);
  assert.equal(allocations[2].every(value => value === 0), true);
  assert.notEqual(record[0], 0, 'caller-owned input must remain intact');
});

test('never publishes a decoded intent when private snapshot erasure fails', async () => {
  const allocate = Buffer.allocUnsafeSlow;
  const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
  const fill = typedArrayPrototype.fill;
  let allocation, decodeIntent;
  try {
    Buffer.allocUnsafeSlow = size => { allocation = allocate(size); return allocation; };
    typedArrayPrototype.fill = () => { throw Error('erasure failed'); };
    ({ decodeInstanceIntent: decodeIntent } = await import('./instance-intent-record.mjs?wipe-failure'));
  } finally {
    Buffer.allocUnsafeSlow = allocate;
    typedArrayPrototype.fill = fill;
  }
  try {
    assert.throws(() => decodeIntent(encodeInstanceIntent(target)), invalid);
    assert.ok(allocation);
  } finally { if (allocation) fill.call(allocation, 0); }
});
