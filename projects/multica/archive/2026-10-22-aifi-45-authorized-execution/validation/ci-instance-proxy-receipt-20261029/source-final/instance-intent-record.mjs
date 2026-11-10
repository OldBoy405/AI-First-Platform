// AIFIRST: serialization boundary for isolated CI instance intent; no I/O or authorization.
import { createHash } from 'node:crypto';
import { TextDecoder, types } from 'node:util';
import { assertInstanceIntent } from './instance-ownership.mjs';

const magic = 'AIFI45-INTENT/1';
const suffix = Buffer.from('\nEND\n');
const maxPayload = 4096;
const validationEnv = Object.freeze({ PGDATA: '/var/lib/postgresql/data/pgdata', POSTGRES_DB: 'x', POSTGRES_USER: 'x', POSTGRES_PASSWORD: 'x' });
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const getBacking = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const getOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset').get;
const getLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const getResizable = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'resizable')?.get;
const setBytes = typedArrayPrototype.set;
const clearBytes = typedArrayPrototype.fill;
const decodeText = TextDecoder.prototype.decode;
const allocatePrivate = Buffer.allocUnsafeSlow.bind(Buffer);

function publicIntent(value) {
  const intent = { name: value?.name, nonce: value?.nonce, image: value?.image,
    createdAfter: value?.createdAfter, createdBefore: value?.createdBefore };
  assertInstanceIntent({ ...intent, expectedEnv: validationEnv });
  return intent;
}

export function encodeInstanceIntent(target) {
  assertInstanceIntent(target);
  const payload = Buffer.from(JSON.stringify(publicIntent(target)), 'utf8');
  if (payload.length > maxPayload) throw Error('intent record too large');
  const digest = createHash('sha256').update(payload).digest('hex');
  return Buffer.concat([Buffer.from(`${magic}\n${payload.length}\n${digest}\n`), payload, suffix]);
}

export function decodeInstanceIntent(input) {
  const reject = () => { throw Error('invalid intent record'); };
  try {
    if (!Buffer.isBuffer(input) || !types.isUint8Array(input)) reject();
    const backing = getBacking.call(input);
    if (types.isSharedArrayBuffer(backing) || getResizable?.call(backing)) reject();
    const actualLength = getLength.call(input);
    if (actualLength > maxPayload + 100) reject();
    const view = new Uint8Array(backing, getOffset.call(input), actualLength);
    const bytes = allocatePrivate(actualLength);
    try {
      setBytes.call(bytes, view);
      const a = bytes.indexOf(10), b = bytes.indexOf(10, a + 1), c = bytes.indexOf(10, b + 1);
      if (a < 0 || b < 0 || c < 0 || !bytes.subarray(0, a).equals(Buffer.from(magic))) reject();
      const length = bytes.subarray(a + 1, b).toString('latin1');
      const digest = bytes.subarray(b + 1, c).toString('latin1');
      if (!/^(0|[1-9][0-9]{0,3})$/.test(length) || Number(length) > maxPayload || !/^[0-9a-f]{64}$/.test(digest)) reject();
      const end = c + 1 + Number(length);
      if (bytes.length !== end + suffix.length || !bytes.subarray(end).equals(suffix)) reject();
      const payload = bytes.subarray(c + 1, end);
      if (createHash('sha256').update(payload).digest('hex') !== digest) reject();
      const text = decodeText.call(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }), payload);
      const value = JSON.parse(text);
      if (!value || typeof value !== 'object' || Array.isArray(value)) reject();
      const intent = publicIntent(value);
      if (JSON.stringify(intent) !== text) reject();
      return intent;
    } finally { clearBytes.call(bytes, 0); }
  } catch { reject(); }
}
