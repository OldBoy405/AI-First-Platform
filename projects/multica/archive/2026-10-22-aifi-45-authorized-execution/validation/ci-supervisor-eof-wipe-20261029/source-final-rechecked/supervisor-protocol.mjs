// AIFI-45 v1: decode one complete buffer from a fixed trusted wrapper only.
// This is not transport authentication, collection, streaming, OS-exit proof,
// or cleanup authorization. See supervisor-protocol.test.mjs for the wire contract.
import { types } from 'node:util';

const HEADER_BYTES = 12;
const MAX_PAYLOAD_BYTES = 1024;
const MAX_TOTAL_BYTES = 65536;
const MAX_FRAMES = 128;
const OUTCOMES = Object.freeze(['EXITED_ZERO', 'EXITED_NONZERO', 'REJECTED', 'OUTPUT_LIMIT']);
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const getBacking = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const getOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset').get;
const getLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const setBytes = typedArrayPrototype.set;
const clearBytes = typedArrayPrototype.fill;
const allocatePrivate = Buffer.allocUnsafeSlow.bind(Buffer);
const reject = error => Object.freeze({ __proto__: null, decoded: false, error });

export function decodeSupervisorBuffer(input) {
  try {
    if (!Buffer.isBuffer(input) || !types.isUint8Array(input)) return reject('INVALID_INPUT');
    // Use intrinsic getters and snapshot only after bounding the actual view.
    // Shared memory cannot supply a stable snapshot while another agent writes.
    const backing = getBacking.call(input);
    if (types.isSharedArrayBuffer(backing)) return reject('INVALID_INPUT');
    const length = getLength.call(input);
    if (length > MAX_TOTAL_BYTES) return reject('TOTAL_LIMIT');
    const view = new Uint8Array(backing, getOffset.call(input), length);
    // Never place potentially sensitive wire bytes in Node's shared Buffer pool.
    // Erase the private snapshot on every parse outcome, including exceptions.
    const bytes = allocatePrivate(length);
    try {
      setBytes.call(bytes, view);
      let offset = 0;
      let sequence = 0;
      while (offset < length) {
        if (sequence >= MAX_FRAMES) return reject('FRAME_COUNT_LIMIT');
        if (length - offset < HEADER_BYTES) return reject('TRUNCATED');
        const version = bytes[offset];
        const type = bytes[offset + 1];
        const reserved = bytes.readUInt16BE(offset + 2);
        const actualSequence = bytes.readUInt32BE(offset + 4);
        const payloadLength = bytes.readUInt32BE(offset + 8);
        if (version !== 1 || reserved !== 0) return reject('INVALID_HEADER');
        if (actualSequence !== sequence) return reject('INVALID_SEQUENCE');
        if (type !== 1 && type !== 2 && type !== 3) return reject('INVALID_TYPE');
        if (payloadLength > MAX_PAYLOAD_BYTES) return reject('FRAME_LIMIT');
        if (type === 3 && payloadLength !== 1) return reject('INVALID_LENGTH');
        offset += HEADER_BYTES;
        if (payloadLength > length - offset) return reject('TRUNCATED');
        if (type === 3) {
          const outcome = bytes[offset];
          if (outcome >= OUTCOMES.length) return reject('INVALID_TERMINAL');
          if (offset + payloadLength !== length) return reject('TRAILING_DATA');
          // decoded reports protocol decoding only, not OS exit or cleanup permission.
          return Object.freeze({ __proto__: null, decoded: true, reportedOutcome: OUTCOMES[outcome] });
        }
        // Opaque data is deliberately discarded, including stderr and secrets.
        offset += payloadLength;
        sequence++;
      }
      return reject('MISSING_TERMINAL');
    } finally {
      clearBytes.call(bytes, 0);
    }
  } catch {
    // Never expose exception text, caller objects, payload, or partial results.
    return reject('INVALID_INPUT');
  }
}
