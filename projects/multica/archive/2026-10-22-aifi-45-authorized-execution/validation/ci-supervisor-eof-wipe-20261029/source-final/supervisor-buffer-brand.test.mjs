// AIFI-45: reject non-Uint8Array views that spoof Buffer's prototype.
// This is not a guarantee that an accepted Uint8Array has Buffer provenance.
import test from 'node:test';
import assert from 'node:assert/strict';
import { types } from 'node:util';
import { decodeSupervisorBuffer } from './supervisor-protocol.mjs';
import { createSupervisorCollector } from './supervisor-collector.mjs';

function spoofedNonByteView() {
  const fake = new Uint16Array(13);
  const bytes = new Uint8Array(fake.buffer);
  // An otherwise valid wire: one data frame followed by EXITED_ZERO.
  bytes[0] = 1; bytes[1] = 1; bytes[11] = 1;
  bytes[13] = 1; bytes[14] = 3; bytes[20] = 1; bytes[24] = 1;
  Object.setPrototypeOf(fake, Buffer.prototype);
  return fake;
}

test('decoder rejects non-byte typed array with a forged Buffer prototype', () => {
  const fake = spoofedNonByteView();
  assert.equal(Buffer.isBuffer(fake), true, 'fixture must exercise Buffer.isBuffer spoofing');
  assert.equal(types.isUint8Array(fake), false, 'fixture must not be a byte view');
  const result = decodeSupervisorBuffer(fake);
  assert.equal(result.decoded, false);
  assert.equal(result.error, 'INVALID_INPUT');
});

test('Buffer-shaped Uint8Array remains accepted; provenance is not authenticated', () => {
  const byteView = new Uint8Array(13);
  byteView[0] = 1; byteView[1] = 3; byteView[11] = 1;
  Object.setPrototypeOf(byteView, Buffer.prototype);
  assert.equal(Buffer.isBuffer(byteView), true);
  assert.equal(types.isUint8Array(byteView), true);
  assert.equal(decodeSupervisorBuffer(byteView).reportedOutcome, 'EXITED_ZERO');
});

test('both collector channels reject non-byte typed array Buffer impersonators', () => {
  for (const channel of ['stdout', 'stderr']) {
    const collector = createSupervisorCollector();
    const result = collector[channel](spoofedNonByteView());
    assert.equal(result.decoded, false);
    assert.equal(result.error, 'INVALID_INPUT');
    assert.equal(collector.result().error, 'INVALID_INPUT');
  }
});
