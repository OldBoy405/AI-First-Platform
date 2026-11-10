'use strict';

// Offline unit checks of the definitions only. This is not a sandbox for
// untrusted source or a substitute for reviewing the downloader and runtime.
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

const source = fs.readFileSync(__dirname + '/anonymous-oci-fetch-draft.cjs', 'utf8');
const markers = [...source.matchAll(/^async function main\(\) \{/gm)];
if (markers.length !== 1) throw new Error('expected one main definition');
const prefix = source.slice(0, markers[0].index);

function definitions() {
  // None of these stubs grants access to the real network or filesystem.
  const https = Object.freeze({
    Agent: class { destroy() {} },
    request() { throw new Error('network disabled'); },
  });
  const empty = Object.freeze(Object.create(null));
  const modules = Object.freeze({
    'node:https': https,
    'node:fs/promises': empty,
    'node:path': empty,
    'node:crypto': empty,
  });
  const sandbox = {
    URL,
    Buffer,
    require(name) {
      if (!Object.hasOwn(modules, name)) throw new Error('module disabled');
      return modules[name];
    },
  };
  try {
    const script = new vm.Script(prefix + `\n;({
      responseFor, advertisedLength, validateDescriptor, writeAll,
      configTypes: CONFIG_TYPES, configCap: LIMIT.config,
      setOpenResponse(fn) { openResponse = fn; }
    })`);
    return script.runInNewContext(sandbox, {
      timeout: 1000,
      contextCodeGeneration: { strings: false, wasm: false },
    });
  } catch (_) {
    throw new Error('could not evaluate downloader definitions');
  }
}

// Suppress original exceptions and assertion details so neither headers nor
// URLs can be included in test output, even when a check fails.
function offlineTest(name, fn) {
  test(name, async () => {
    try {
      await fn(definitions());
    } catch (_) {
      throw new Error('offline check failed');
    }
  });
}

function expectError(fn, code) {
  let caught = false;
  try { fn(); } catch (err) {
    caught = true;
    assert.ok(err && err.message === code);
  }
  assert.ok(caught);
}

async function expectAsyncError(fn, code) {
  let caught = false;
  try { await fn(); } catch (err) {
    caught = true;
    assert.ok(err && err.message === code);
  }
  assert.ok(caught);
}

const registry = 'https://registry-1.docker.io/v2/example';
const cdn = 'https://production.cloudfront.docker.com/blob?signature=offline-placeholder';
const token = 'offline-test-bearer';

function response(statusCode, location) {
  return {
    statusCode,
    headers: location === undefined ? {} : { location },
    destroyed: false,
    destroy() { this.destroyed = true; },
  };
}

function useResponses(api, responses) {
  const calls = [];
  api.setOpenResponse(async (url, headers) => {
    // Record only non-secret properties, not URLs or header values.
    calls.push({
      registry: url.hostname === 'registry-1.docker.io',
      cdn: url.hostname === 'production.cloudfront.docker.com',
      hasAuthorization: Object.hasOwn(headers, 'authorization'),
      correctBearer: headers.authorization === 'Bearer ' + token,
    });
    if (calls.length > responses.length) throw new Error('unexpected request');
    return responses[calls.length - 1];
  });
  return calls;
}

offlineTest('registry to CDN drops bearer and destroys redirect response', async (api) => {
  const redirect = response(307, cdn);
  const final = response(200);
  const calls = useResponses(api, [redirect, final]);
  const result = await api.responseFor(registry, token, 'application/octet-stream', true);
  assert.ok(result === final && calls.length === 2 && redirect.destroyed);
  assert.ok(calls[0].registry && calls[0].hasAuthorization && calls[0].correctBearer);
  assert.ok(calls[1].cdn && !calls[1].hasAuthorization);
});

offlineTest('same-registry redirect retains bearer', async (api) => {
  const redirect = response(302, '/v2/other');
  const calls = useResponses(api, [redirect, response(200)]);
  await api.responseFor(registry, token, 'application/octet-stream', true);
  assert.ok(calls.length === 2 && redirect.destroyed);
  assert.ok(calls.every((call) => call.registry && call.correctBearer));
});

offlineTest('subsequent CDN redirect still has no bearer', async (api) => {
  const calls = useResponses(api, [response(307, cdn), response(302, '/next'), response(200)]);
  await api.responseFor(registry, token, 'application/octet-stream', true);
  assert.ok(calls.length === 3 && calls[0].correctBearer);
  assert.ok(calls.slice(1).every((call) => call.cdn && !call.hasAuthorization));
});

const invalidRedirects = [
  ['unknown host', 'https://example.invalid/blob'],
  ['CDN suffix spoof', 'https://production.cloudfront.docker.com.example.invalid/blob'],
  ['registry suffix spoof', 'https://registry-1.docker.io.example.invalid/blob'],
  ['plaintext HTTP', 'http://production.cloudfront.docker.com/blob'],
  ['userinfo', 'https://user@production.cloudfront.docker.com/blob'],
  ['non-default port', 'https://production.cloudfront.docker.com:8443/blob'],
  ['fragment', 'https://production.cloudfront.docker.com/blob#fragment'],
];
for (const [label, location] of invalidRedirects) {
  offlineTest('reject redirect: ' + label, async (api) => {
    const redirect = response(307, location);
    const calls = useResponses(api, [redirect]);
    await expectAsyncError(() => api.responseFor(registry, token, '*/*', true), 'url');
    assert.ok(calls.length === 1 && calls[0].correctBearer && redirect.destroyed);
  });
}

offlineTest('reject invalid starting host before opening a response', async (api) => {
  const calls = useResponses(api, []);
  await expectAsyncError(
    () => api.responseFor('https://example.invalid/blob', token, '*/*', true), 'url');
  assert.ok(calls.length === 0);
});

offlineTest('reject return from CDN to registry before opening it', async (api) => {
  const first = response(307, cdn);
  const second = response(307, registry);
  const calls = useResponses(api, [first, second]);
  await expectAsyncError(() => api.responseFor(registry, token, '*/*', true), 'redirect-return');
  assert.ok(calls.length === 2 && first.destroyed && second.destroyed);
  assert.ok(calls[0].correctBearer && calls[1].cdn && !calls[1].hasAuthorization);
});

offlineTest('content length accepts absent and canonical safe integers', (api) => {
  const length = (value) => api.advertisedLength({ headers: { 'content-length': value } });
  assert.ok(length(undefined) === null);
  assert.ok(length('0') === 0 && length('1') === 1);
  assert.ok(length('9007199254740991') === Number.MAX_SAFE_INTEGER);
});

offlineTest('content length rejects malformed and unsafe values', (api) => {
  for (const value of [null, 0, ['1'], '', '00', '01', '-1', '+1', ' 1', '1 ',
    '1.0', '1e3', 'NaN', '9007199254740992']) {
    expectError(() => api.advertisedLength({ headers: { 'content-length': value } }), 'length');
  }
});

function descriptor(api) {
  return {
    mediaType: 'application/vnd.oci.image.config.v1+json',
    digest: 'sha256:' + 'a'.repeat(64),
    size: api.configCap,
  };
}

offlineTest('descriptor accepts valid digest and size boundaries', (api) => {
  const d = descriptor(api);
  api.validateDescriptor(d, api.configTypes, api.configCap);
  api.validateDescriptor({ ...d, size: 0 }, api.configTypes, api.configCap);
});

offlineTest('descriptor rejects malformed digests and media types', (api) => {
  const d = descriptor(api);
  for (const digest of [null, 42, '', 'sha256:' + 'a'.repeat(63),
    'sha256:' + 'a'.repeat(65), 'sha256:' + 'A'.repeat(64),
    'sha256:' + 'g'.repeat(64), 'sha512:' + 'a'.repeat(64)]) {
    expectError(() => api.validateDescriptor({ ...d, digest }, api.configTypes, api.configCap), 'descriptor');
  }
  expectError(() => api.validateDescriptor({ ...d, mediaType: 'invalid' }, api.configTypes, api.configCap), 'descriptor');
  expectError(() => api.validateDescriptor(null, api.configTypes, api.configCap), 'descriptor');
});

offlineTest('descriptor rejects invalid sizes and external content fields', (api) => {
  const d = descriptor(api);
  for (const size of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1,
    api.configCap + 1, '1', null, undefined]) {
    expectError(() => api.validateDescriptor({ ...d, size }, api.configTypes, api.configCap), 'descriptor');
  }
  for (const extra of [{ urls: null }, { urls: [] }, { data: null }, { data: '' }]) {
    expectError(() => api.validateDescriptor({ ...d, ...extra }, api.configTypes, api.configCap), 'descriptor');
  }
});

offlineTest('short writes complete with correct offsets and bytes', async (api) => {
  const input = Buffer.from('offline');
  const chunks = [];
  let expectedOffset = 0;
  const handle = {
    async write(chunk, offset, length, position) {
      assert.ok(chunk === input && offset === expectedOffset);
      assert.ok(length === input.length - offset && position === null);
      const bytesWritten = Math.min(2, length);
      chunks.push(Buffer.from(chunk.subarray(offset, offset + bytesWritten)));
      expectedOffset += bytesWritten;
      return { bytesWritten };
    },
  };
  await api.writeAll(handle, input);
  assert.ok(chunks.length > 1 && expectedOffset === input.length);
  assert.ok(Buffer.concat(chunks).equals(input));
});

offlineTest('zero-progress write fails rather than looping', async (api) => {
  let calls = 0;
  const handle = {
    async write() {
      calls++;
      if (calls > 1) throw new Error('repeated zero-progress write');
      return { bytesWritten: 0 };
    },
  };
  await expectAsyncError(() => api.writeAll(handle, Buffer.from('x')), 'write');
  assert.ok(calls === 1);
});

offlineTest('empty write does not call handle', async (api) => {
  let calls = 0;
  await api.writeAll({ async write() { calls++; } }, Buffer.alloc(0));
  assert.ok(calls === 0);
});
