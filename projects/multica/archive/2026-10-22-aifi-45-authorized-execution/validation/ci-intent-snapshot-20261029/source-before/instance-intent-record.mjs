// AIFIRST: serialization boundary for isolated CI instance intent; no I/O or authorization.
import { createHash } from 'node:crypto';
import { TextDecoder } from 'node:util';
import { assertInstanceIntent } from './instance-ownership.mjs';

const magic = 'AIFI45-INTENT/1';
const suffix = Buffer.from('\nEND\n');
const maxPayload = 4096;
const validationEnv = Object.freeze({ PGDATA: '/var/lib/postgresql/data/pgdata', POSTGRES_DB: 'x', POSTGRES_USER: 'x', POSTGRES_PASSWORD: 'x' });

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

export function decodeInstanceIntent(bytes) {
  const reject = () => { throw Error('invalid intent record'); };
  if (!Buffer.isBuffer(bytes) || bytes.length > maxPayload + 100) reject();
  const a = bytes.indexOf(10), b = bytes.indexOf(10, a + 1), c = bytes.indexOf(10, b + 1);
  if (a < 0 || b < 0 || c < 0 || !bytes.subarray(0, a).equals(Buffer.from(magic))) reject();
  const length = bytes.subarray(a + 1, b).toString('latin1');
  const digest = bytes.subarray(b + 1, c).toString('latin1');
  if (!/^(0|[1-9][0-9]{0,3})$/.test(length) || Number(length) > maxPayload || !/^[0-9a-f]{64}$/.test(digest)) reject();
  const end = c + 1 + Number(length);
  if (bytes.length !== end + suffix.length || !bytes.subarray(end).equals(suffix)) reject();
  const payload = bytes.subarray(c + 1, end);
  if (createHash('sha256').update(payload).digest('hex') !== digest) reject();
  let text, value;
  try {
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(payload);
    value = JSON.parse(text);
    if (!value || typeof value !== 'object' || Array.isArray(value)) reject();
    const intent = publicIntent(value);
    if (JSON.stringify(intent) !== text) reject();
    return intent;
  } catch { reject(); }
}
