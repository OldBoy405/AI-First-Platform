// AIFI-45: controlled-event accumulator only. It has no transport, deadline,
// source authentication, process-exit proof, or cleanup authority. A future
// trusted pump must supply real events and independently enforce those boundaries.
import { types } from 'node:util';
import { decodeSupervisorBuffer } from './supervisor-protocol.mjs';

export const STDOUT_LIMIT = 65536;
export const STDERR_LIMIT = 65536;

const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const getBacking = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const getOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset').get;
const getLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const setBytes = typedArrayPrototype.set;
const ok = Object.freeze({ __proto__: null, ok: true });

export function createSupervisorCollector() {
  const stdout = Buffer.alloc(STDOUT_LIMIT);
  let stdoutLength = 0;
  let stderrLength = 0;
  let stdoutEnded = false;
  let stderrEnded = false;
  let failure = null;
  let decoded = null;
  let busy = false;

  function fail(error) {
    if (!failure) {
      stdout.fill(0);
      failure = Object.freeze({ __proto__: null, decoded: false, error });
    }
    return failure;
  }

  function event(expected, actual, action) {
    if (failure) return failure;
    if (busy) return fail('REENTRANT');
    busy = true;
    try {
      if (actual !== expected) return fail('INVALID_EVENT');
      const result = action();
      return failure || result;
    } catch {
      return fail('INVALID_INPUT');
    } finally {
      busy = false;
    }
  }

  function data(channel, input) {
    if (channel === 'stdout' ? stdoutEnded : stderrEnded) return fail('DATA_AFTER_EOF');
    if (!Buffer.isBuffer(input) || !types.isUint8Array(input) || failure) return fail('INVALID_INPUT');
    const backing = getBacking.call(input);
    if (types.isSharedArrayBuffer(backing)) return fail('INVALID_INPUT');
    const offset = getOffset.call(input);
    const length = getLength.call(input);
    // Constructing the view rejects detached storage, even when its length is zero.
    const bytes = new Uint8Array(backing, offset, length);
    if (failure) return failure;
    if (length === 0) return fail('EMPTY_CHUNK');
    if (channel === 'stdout') {
      if (length > STDOUT_LIMIT - stdoutLength) return fail('STDOUT_LIMIT');
      setBytes.call(stdout, bytes, stdoutLength);
      stdoutLength += length;
    } else {
      if (length > STDERR_LIMIT - stderrLength) return fail('STDERR_LIMIT');
      stderrLength += length;
    }
    return ok;
  }

  function eof(channel) {
    if (channel === 'stdout') {
      if (stdoutEnded) return fail('DUPLICATE_EOF');
      stdoutEnded = true;
    } else {
      if (stderrEnded) return fail('DUPLICATE_EOF');
      stderrEnded = true;
    }
    if (stdoutEnded && stderrEnded && stdoutLength !== 0) {
      try {
        decoded = decodeSupervisorBuffer(stdout.subarray(0, stdoutLength));
      } finally {
        stdout.fill(0);
      }
    }
    return ok;
  }

  return Object.freeze({
    __proto__: null,
    stdout(...args) { return event(1, args.length, () => data('stdout', args[0])); },
    stderr(...args) { return event(1, args.length, () => data('stderr', args[0])); },
    stdoutEOF(...args) { return event(0, args.length, () => eof('stdout')); },
    stderrEOF(...args) { return event(0, args.length, () => eof('stderr')); },
    abort(...args) { return event(0, args.length, () => fail('ABORTED')); },
    result(...args) {
      return event(0, args.length, () => {
        if (!stdoutEnded && !stderrEnded) return fail('MISSING_BOTH_EOF');
        if (!stdoutEnded) return fail('MISSING_STDOUT_EOF');
        if (!stderrEnded) return fail('MISSING_STDERR_EOF');
        if (stdoutLength === 0) return fail('EMPTY_STDOUT');
        if (!decoded.decoded) failure = decoded;
        return decoded;
      });
    },
  });
}
