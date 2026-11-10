// AIFIRST: intent snapshot boundary tests; no engine or database access.
import test from 'node:test';
import assert from 'node:assert/strict';
import { TextDecoder } from 'node:util';
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
  if (!rejected) {
    assert.equal(swapped, true, 'the checksum/decode race was not exercised');
    assert.equal(returned?.image === 'b'.repeat(64), true, 'the changed valid payload was not consumed');
  }
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

test('rejects non-byte impostors and a proxied Buffer with a fixed error', () => {
  const fake = new Uint16Array(2);
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
  const result = decodeInstanceIntent(view);
  assert.equal(result.name, target.name);
  assert.equal(result.image, target.image);
});
