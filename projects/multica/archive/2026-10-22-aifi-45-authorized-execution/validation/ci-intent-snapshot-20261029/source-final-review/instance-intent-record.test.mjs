// AIFIRST: isolated intent serialization tests; no engine or database access.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { TextDecoder } from 'node:util';
import { encodeInstanceIntent, decodeInstanceIntent } from './instance-intent-record.mjs';

const expected = { name: 'aifi45-ci-0123456789abcdef', nonce: '0123456789abcdef', image: 'a'.repeat(64),
  createdAfter: '2026-10-28T00:00:00Z', createdBefore: '2026-10-28T00:02:00Z' };
const secret = 'fake password/should never persist';
const target = { ...expected, expectedEnv: { PGDATA: '/var/lib/postgresql/data/pgdata', POSTGRES_DB: 'postgres', POSTGRES_USER: 'test', POSTGRES_PASSWORD: secret }, private: secret };

function frame(payload) {
  const bytes = Buffer.from(payload, 'utf8');
  const hash = createHash('sha256').update(bytes).digest('hex');
  return Buffer.concat([Buffer.from(`AIFI45-INTENT/1\n${bytes.length}\n${hash}\n`), bytes, Buffer.from('\nEND\n')]);
}

test('roundtrip records only the intended public fields, never secret', () => {
  const bytes = encodeInstanceIntent(target);
  assert.ok(Buffer.isBuffer(bytes));
  assert.deepEqual(decodeInstanceIntent(bytes), expected);
  assert.equal(bytes.includes(secret), false);
  assert.equal(bytes.includes(encodeURIComponent(secret)), false);
});

test('rejects changed payload with original digest', () => {
  const bytes = Buffer.from(encodeInstanceIntent(target));
  const index = bytes.indexOf(Buffer.from('"image":"')) + Buffer.byteLength('"image":"');
  assert.ok(index >= Buffer.byteLength('"image":"')); bytes[index] = 'b'.charCodeAt(0);
  assert.throws(() => decodeInstanceIntent(bytes));
});

test('rejects truncation', () => {
  const bytes = encodeInstanceIntent(target);
  assert.throws(() => decodeInstanceIntent(bytes.subarray(0, bytes.length - 1)));
});

test('rejects trailing content', () => {
  const bytes = encodeInstanceIntent(target);
  assert.throws(() => decodeInstanceIntent(Buffer.concat([bytes, Buffer.from('x')])));
});

for (const [name, mutate] of [
  ['incorrect magic/version', s => s.replace('AIFI45-INTENT/1', 'AIFI45-INTENT/2')],
  ['length with leading zero', s => s.replace(/\n([0-9]+)\n/, '\n0$1\n')],
  ['nondecimal length', s => s.replace(/\n[0-9]+\n/, '\nNaN\n')],
  ['incorrect declared length', s => s.replace(/\n([0-9]+)\n/, (_, n) => `\n${Number(n) + 1}\n`)],
  ['incorrect end marker', s => s.replace(/\nEND\n$/, '\nFIN\n')],
]) {
  test(`rejects ${name}`, () => {
    assert.throws(() => decodeInstanceIntent(Buffer.from(mutate(encodeInstanceIntent(target).toString('utf8')))));
  });
}

test('rejects a payload above the byte limit', () => {
  assert.throws(() => decodeInstanceIntent(frame(' '.repeat(4097))));
});

test('oversized records are rejected before private allocation', async () => {
  const allocate = Buffer.allocUnsafeSlow;
  const sizes = [];
  let decode;
  try {
    Buffer.allocUnsafeSlow = size => { sizes.push(size); return allocate(size); };
    ({ decodeInstanceIntent: decode } = await import('./instance-intent-record.mjs?allocation-boundary'));
  } finally { Buffer.allocUnsafeSlow = allocate; }
  sizes.length = 0;
  assert.throws(() => decode(Buffer.alloc(4197)), /^Error: invalid intent record$/);
  assert.deepEqual(sizes, []);
  assert.throws(() => decode(Buffer.alloc(4196)), /^Error: invalid intent record$/);
  assert.deepEqual(sizes, [4196]);
});

test('oversized payload is rejected after bounded copy but before payload parsing', () => {
  const large = frame(' '.repeat(4097)), boundary = frame(' '.repeat(4096));
  const largeStart = large.indexOf(Buffer.from('    ')), boundaryStart = boundary.indexOf(Buffer.from('    '));
  assert.ok(largeStart > 0 && boundaryStart > 0);
  const subarray = Buffer.prototype.subarray;
  let largeReads = 0, boundaryReads = 0;
  try {
    Buffer.prototype.subarray = function (start, stop) {
      if (this.length === large.length && start === largeStart && stop === large.length - 5) largeReads++;
      if (this.length === boundary.length && start === boundaryStart && stop === boundary.length - 5) boundaryReads++;
      return subarray.call(this, start, stop);
    };
    assert.throws(() => decodeInstanceIntent(large), /^Error: invalid intent record$/);
    assert.throws(() => decodeInstanceIntent(boundary), /^Error: invalid intent record$/);
  } finally { Buffer.prototype.subarray = subarray; }
  assert.equal(largeReads, 0);
  assert.equal(boundaryReads, 1);
});

test('rejects a non-Buffer input', () => {
  assert.throws(() => decodeInstanceIntent(encodeInstanceIntent(target).toString('utf8')));
});

for (const [name, payload] of [
  ['top-level array', '[]'],
  ['top-level null', 'null'],
  ['JSON with whitespace', ` ${JSON.stringify(expected)}`],
  ['JSON with changed key order', JSON.stringify({ nonce: expected.nonce, name: expected.name, image: expected.image, createdAfter: expected.createdAfter, createdBefore: expected.createdBefore })],
  ['JSON with noncanonical escaped field', JSON.stringify(expected).replace('aifi45', '\\u0061ifi45')],
]) {
  test(`rejects ${name} even with matching digest`, () => assert.throws(() => decodeInstanceIntent(frame(payload))));
}

test('rejects high-bit bytes in the length header', () => {
  const bytes = Buffer.from(encodeInstanceIntent(target)), first = bytes.indexOf(10);
  bytes[first + 1] |= 0x80;
  assert.throws(() => decodeInstanceIntent(bytes));
});

test('rejects high-bit bytes in the digest header', () => {
  const bytes = Buffer.from(encodeInstanceIntent(target)), first = bytes.indexOf(10), second = bytes.indexOf(10, first + 1);
  bytes[second + 1] |= 0x80;
  assert.throws(() => decodeInstanceIntent(bytes));
});

test('rejects a duplicate JSON field even with a matching digest', () => {
  const payload = JSON.stringify(expected).replace('{', '{"nonce":"ffffffffffffffff",');
  assert.throws(() => decodeInstanceIntent(frame(payload)));
});

test('rejects additional secret-bearing fields even with a matching digest', () => {
  assert.throws(() => decodeInstanceIntent(frame(JSON.stringify({ ...expected, password: secret }))));
});

test('rejects invalid nonce and creation window in both directions', () => {
  for (const bad of [{ ...expected, nonce: 'BAD' }, { ...expected, createdBefore: 'invalid' }]) {
    assert.throws(() => encodeInstanceIntent({ ...target, ...bad }));
    assert.throws(() => decodeInstanceIntent(frame(JSON.stringify(bad))));
  }
});

test('rejects a UTF-8 BOM even with a matching digest', () => {
  const payload = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(JSON.stringify(expected))]);
  const hash = createHash('sha256').update(payload).digest('hex');
  const forged = Buffer.concat([Buffer.from(`AIFI45-INTENT/1\n${payload.length}\n${hash}\n`), payload, Buffer.from('\nEND\n')]);
  assert.throws(() => decodeInstanceIntent(forged));
});

test('configures the UTF-8 decoder to reject malformed data', () => {
  const decode = TextDecoder.prototype.decode; let fatal;
  try {
    TextDecoder.prototype.decode = function (...args) { fatal = this.fatal; return decode.apply(this, args); };
    assert.deepEqual(decodeInstanceIntent(encodeInstanceIntent(target)), expected);
    assert.equal(fatal, true);
  } finally { TextDecoder.prototype.decode = decode; }
});

test('rejects invalid UTF-8 even with matching digest', () => {
  const bytes = encodeInstanceIntent(target), offset = bytes.indexOf(Buffer.from('{'));
  const payload = Buffer.from(bytes.subarray(offset, bytes.length - 5));
  payload[2] = 0xff;
  const hash = createHash('sha256').update(payload).digest('hex');
  const forged = Buffer.concat([Buffer.from(`AIFI45-INTENT/1\n${payload.length}\n${hash}\n`), payload, Buffer.from('\nEND\n')]);
  assert.throws(() => decodeInstanceIntent(forged));
});
