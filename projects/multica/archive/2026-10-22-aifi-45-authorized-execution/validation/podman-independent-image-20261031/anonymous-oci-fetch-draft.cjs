'use strict';

/*
 * REVIEW DRAFT ONLY. Do not execute without independent review and authorization.
 * CLI: node anonymous-oci-fetch-draft.cjs --parent ABSOLUTE_EXISTING_DIRECTORY
 * Creates one random, exclusively-created child of parent. Nothing is removed.
 * OCI bytes only: this does not run an image or create an isolated database.
 *
 * The operator must supply a trusted Node executable/runtime and a trusted,
 * private parent and ancestors, with no concurrent local writers. Node startup
 * options, preloads, extra/system CA stores, DNS and filesystem/Windows ACLs
 * are outside this script's control. POSIX modes are not Windows ACLs. Directory
 * entry races/reparse points in ancestors cannot be excluded by Node path APIs.
 * The script does not access process.env or use Node's global HTTP agent.
 *
 * Fail-closed restrictions intentionally may reject otherwise valid images:
 * only the pinned single-platform manifest, listed media types, SHA-256 and
 * exact CDN hosts are supported. Manifest size is checked against HTTP
 * Content-Length and the pinned digest, not an independently pinned size.
 * Layer diff_ids, signatures, provenance, tag freshness and image safety are
 * not verified. No archive is unpacked. Readback is not a durability guarantee.
 * The overall watchdog can terminate during a write, leaving a partial or absent
 * receipt; an externally blocked event loop cannot be timed out by this process.
 */

const https = require('node:https');
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const MANIFEST = 'sha256:cd4ccfdaf62cbfeb5c6ee19ef0dd663406d4ed740c320b324d016a90e85385b3';
const REGISTRY = 'registry-1.docker.io';
const TOKEN_HOST = 'auth.docker.io';
// Exact hostnames only; no wildcard suffixes. Changes require human review.
const CDN_HOSTS = new Set([
  'production.cloudfront.docker.com',
]);
const MANIFEST_TYPES = new Set([
  'application/vnd.oci.image.manifest.v1+json',
  'application/vnd.docker.distribution.manifest.v2+json',
]);
const CONFIG_TYPES = new Set([
  'application/vnd.oci.image.config.v1+json',
  'application/vnd.docker.container.image.v1+json',
]);
const LAYER_TYPES = new Set([
  'application/vnd.oci.image.layer.v1.tar',
  'application/vnd.oci.image.layer.v1.tar+gzip',
  'application/vnd.oci.image.layer.v1.tar+zstd',
  'application/vnd.docker.image.rootfs.diff.tar',
  'application/vnd.docker.image.rootfs.diff.tar.gzip',
]);
const MIB = 1024 * 1024;
const LIMIT = Object.freeze({
  token: 64 * 1024,
  manifest: 8 * MIB,
  config: 1 * MIB,
  layer: 128 * MIB,
  total: 256 * MIB,
  layers: 16,
  redirects: 3,
  requestMs: 5 * 60 * 1000,
  overallMs: 15 * 60 * 1000,
});
const SHA256 = /^sha256:[0-9a-f]{64}$/;
const agent = new https.Agent({ keepAlive: false, rejectUnauthorized: true });
let networkBytes = 0;
let deadline = 0;

function fail(code) { throw new Error(code); }

function checkUrl(u, hosts) {
  if (u.protocol !== 'https:' || u.username || u.password || u.port || u.hash ||
      !hosts.has(u.hostname)) fail('url');
}

function openResponse(url, headers) {
  const remaining = deadline - Date.now();
  if (remaining <= 0) fail('deadline');
  return new Promise((resolve, reject) => {
    let response;
    const req = https.request(url, {
      method: 'GET', agent, rejectUnauthorized: true,
      maxHeaderSize: 16 * 1024, headers,
    }, (res) => {
      response = res;
      res.once('close', () => clearTimeout(timer));
      resolve(res);
    });
    const timer = setTimeout(() => {
      if (response) response.destroy(new Error('timeout'));
      req.destroy(new Error('timeout'));
    }, Math.min(LIMIT.requestMs, remaining));
    req.once('error', (err) => { clearTimeout(timer); reject(err); });
    req.end();
  });
}

async function responseFor(start, token, accept, allowRedirects) {
  let url = new URL(start);
  let bearerAllowed = url.hostname === REGISTRY && Boolean(token);
  let leftRegistry = false;
  const hosts = allowRedirects ? new Set([REGISTRY, ...CDN_HOSTS]) : new Set([TOKEN_HOST]);
  for (let hop = 0; ; hop++) {
    checkUrl(url, hosts);
    if (leftRegistry && url.hostname === REGISTRY) fail('redirect-return');
    const headers = { 'accept-encoding': 'identity', accept };
    if (bearerAllowed && url.hostname === REGISTRY) headers.authorization = 'Bearer ' + token;
    const res = await openResponse(url, headers);
    const status = res.statusCode;
    if ([301, 302, 303, 307, 308].includes(status)) {
      try {
        if (!allowRedirects || hop >= LIMIT.redirects || typeof res.headers.location !== 'string') {
          fail('redirect');
        }
        const next = new URL(res.headers.location, url);
        checkUrl(next, hosts);
        if (next.origin !== url.origin) {
          bearerAllowed = false;
          if (url.hostname === REGISTRY) leftRegistry = true;
        }
        if (leftRegistry && next.hostname === REGISTRY) fail('redirect-return');
        url = next;
      } finally { res.destroy(); }
      continue;
    }
    if (status !== 200) { res.destroy(); fail('http'); }
    const encoding = res.headers['content-encoding'];
    if (encoding && encoding.toLowerCase() !== 'identity') {
      res.destroy(); fail('encoding');
    }
    return res;
  }
}

function advertisedLength(res) {
  const s = res.headers['content-length'];
  if (s === undefined) return null;
  if (typeof s !== 'string' || !/^(0|[1-9][0-9]*)$/.test(s)) fail('length');
  const n = Number(s);
  if (!Number.isSafeInteger(n)) fail('length');
  return n;
}

function countNetwork(n) {
  networkBytes += n;
  if (networkBytes > LIMIT.total) fail('total');
}

async function getToken() {
  const url = new URL('https://' + TOKEN_HOST + '/token');
  url.searchParams.set('service', 'registry.docker.io');
  url.searchParams.set('scope', 'repository:pgvector/pgvector:pull');
  const res = await responseFor(url, null, 'application/json', false);
  try {
    const advertised = advertisedLength(res);
    if (advertised !== null && advertised > LIMIT.token) fail('token-size');
    let size = 0;
    const chunks = [];
    for await (const chunk of res) {
      countNetwork(chunk.length);
      size += chunk.length;
      if (size > LIMIT.token) fail('token-size');
      chunks.push(chunk);
    }
    if (advertised !== null && size !== advertised) fail('length');
    const doc = JSON.parse(Buffer.concat(chunks, size).toString('utf8'));
    const token = doc.token || doc.access_token;
    if (typeof token !== 'string' || token.length > 16384 ||
        !/^[A-Za-z0-9._~+\/=-]+$/.test(token)) fail('token');
    return token;
  } finally { res.destroy(); }
}

function validateDescriptor(d, types, cap) {
  if (!d || typeof d !== 'object' || !types.has(d.mediaType) ||
      typeof d.digest !== 'string' || !SHA256.test(d.digest) ||
      !Number.isSafeInteger(d.size) || d.size < 0 || d.size > cap ||
      d.urls !== undefined || d.data !== undefined) fail('descriptor');
}

async function writeAll(handle, chunk) {
  let offset = 0;
  while (offset < chunk.length) {
    const result = await handle.write(chunk, offset, chunk.length - offset, null);
    if (result.bytesWritten <= 0) fail('write');
    offset += result.bytesWritten;
  }
}

async function verifyReadback(filename, digest, size) {
  const handle = await fs.open(filename, 'r');
  try {
    const hash = crypto.createHash('sha256');
    const buffer = Buffer.alloc(64 * 1024);
    let actual = 0;
    for (;;) {
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, null);
      if (bytesRead === 0) break;
      actual += bytesRead;
      if (actual > size) fail('readback-size');
      hash.update(buffer.subarray(0, bytesRead));
    }
    if (actual !== size || 'sha256:' + hash.digest('hex') !== digest) fail('readback');
  } finally { await handle.close(); }
}

async function fetchBlob(root, url, token, digest, expectedSize, cap, capture, record) {
  const filename = path.join(root, 'blobs', 'sha256', digest.slice(7));
  // Exclusive creation; partial files are intentionally retained on failure.
  const handle = await fs.open(filename, 'wx', 0o600);
  let res;
  let size = 0;
  const hash = crypto.createHash('sha256');
  const chunks = capture ? [] : null;
  try {
    res = await responseFor(url, token, [...MANIFEST_TYPES].join(', '), true);
    const advertised = advertisedLength(res);
    if (advertised !== null && advertised > cap) fail('size');
    // The manifest is pinned by digest but has no independent expected size.
    if (expectedSize === null && advertised === null) fail('manifest-length');
    if (expectedSize !== null && advertised !== null && advertised !== expectedSize) fail('length');
    if (expectedSize === null) record.size = advertised;
    for await (const chunk of res) {
      countNetwork(chunk.length);
      size += chunk.length;
      if (size > cap || (expectedSize !== null && size > expectedSize) ||
          (advertised !== null && size > advertised)) fail('size');
      await writeAll(handle, chunk);
      hash.update(chunk);
      if (chunks) chunks.push(chunk);
    }
    if ((advertised !== null && size !== advertised) ||
        (expectedSize !== null && size !== expectedSize) ||
        'sha256:' + hash.digest('hex') !== digest) fail('digest-or-size');
    await handle.sync();
  } finally {
    if (res) res.destroy();
    await handle.close();
  }
  await verifyReadback(filename, digest, size);
  record.size = size;
  record.status = 'complete';
  return chunks ? Buffer.concat(chunks, size) : null;
}

async function writeJsonExclusive(filename, value) {
  const handle = await fs.open(filename, 'wx', 0o600);
  try {
    await writeAll(handle, Buffer.from(JSON.stringify(value) + '\n', 'utf8'));
    await handle.sync();
  } finally { await handle.close(); }
}

async function main() {
  if (process.argv.length !== 4 || process.argv[2] !== '--parent' ||
      !path.isAbsolute(process.argv[3])) fail('usage');
  const parent = path.normalize(process.argv[3]);
  if (process.platform === 'win32' && !/^[A-Za-z]:\\/.test(parent)) fail('parent');
  const parentStat = await fs.lstat(parent);
  if (!parentStat.isDirectory() || parentStat.isSymbolicLink()) fail('parent');
  const actualParent = path.normalize(await fs.realpath(parent));
  const comparable = (p) => process.platform === 'win32' ? p.toLowerCase() : p;
  if (comparable(parent) !== comparable(actualParent)) fail('parent-reparse');

  const name = 'oci-fetch-' + crypto.randomBytes(16).toString('hex');
  const root = path.join(parent, name);
  await fs.mkdir(root, { mode: 0o700 }); // not recursive; collision is an error
  // Only a generated basename is printed; no URLs, headers, tokens or errors.
  process.stdout.write('owned-directory=' + name + '\n');
  const records = [{ digest: MANIFEST, size: null, status: 'unknown' }];
  let complete = false;
  let error;
  try {
    await fs.mkdir(path.join(root, 'blobs'), { mode: 0o700 });
    await fs.mkdir(path.join(root, 'blobs', 'sha256'), { mode: 0o700 });
    const token = await getToken();
    const base = 'https://' + REGISTRY + '/v2/pgvector/pgvector/';
    const raw = await fetchBlob(root, base + 'manifests/' + MANIFEST, token,
      MANIFEST, null, LIMIT.manifest, true, records[0]);
    const manifest = JSON.parse(raw.toString('utf8'));
    if (!manifest || manifest.schemaVersion !== 2 || !MANIFEST_TYPES.has(manifest.mediaType) ||
        !Array.isArray(manifest.layers) || manifest.layers.length > LIMIT.layers) fail('manifest');
    validateDescriptor(manifest.config, CONFIG_TYPES, LIMIT.config);
    for (const layer of manifest.layers) validateDescriptor(layer, LAYER_TYPES, LIMIT.layer);

    const seen = new Map([[MANIFEST, records[0]]]);
    if (seen.has(manifest.config.digest)) fail('duplicate-role');
    const configRecord = { digest: manifest.config.digest, size: manifest.config.size, status: 'unknown' };
    records.push(configRecord);
    seen.set(configRecord.digest, configRecord);
    const layerRecords = [];
    for (const layer of manifest.layers) {
      if (layer.digest === MANIFEST || layer.digest === manifest.config.digest) fail('duplicate-role');
      let record = seen.get(layer.digest);
      if (record && record.size !== layer.size) fail('duplicate-size');
      if (!record) {
        record = { digest: layer.digest, size: layer.size, status: 'unknown' };
        records.push(record);
        seen.set(layer.digest, record);
      }
      layerRecords.push(record);
    }
    const declaredRemaining = records.slice(1).reduce((sum, r) => sum + r.size, 0);
    if (declaredRemaining > LIMIT.total - networkBytes) fail('total');

    const configBytes = await fetchBlob(root, base + 'blobs/' + manifest.config.digest, await getToken(),
      manifest.config.digest, manifest.config.size, LIMIT.config, true, configRecord);
    const config = JSON.parse(configBytes.toString('utf8'));
    if (!config || config.os !== 'linux' || config.architecture !== 'amd64' ||
        !config.rootfs || config.rootfs.type !== 'layers' ||
        !Array.isArray(config.rootfs.diff_ids) || config.rootfs.diff_ids.length !== manifest.layers.length ||
        !config.rootfs.diff_ids.every((d) => typeof d === 'string' && SHA256.test(d))) fail('platform');
    for (let i = 0; i < manifest.layers.length; i++) {
      const layer = manifest.layers[i];
      const record = layerRecords[i];
      if (record.status === 'complete') continue; // identical digest and size
      await fetchBlob(root, base + 'blobs/' + layer.digest, await getToken(),
        layer.digest, layer.size, LIMIT.layer, false, record);
    }
    await writeJsonExclusive(path.join(root, 'oci-layout'), { imageLayoutVersion: '1.0.0' });
    await writeJsonExclusive(path.join(root, 'index.json'), {
      schemaVersion: 2,
      mediaType: 'application/vnd.oci.image.index.v1+json',
      manifests: [{
        mediaType: manifest.mediaType, digest: MANIFEST, size: records[0].size,
        platform: { os: 'linux', architecture: 'amd64' },
        annotations: { 'org.opencontainers.image.ref.name': 'pg17' },
      }],
    });
    complete = true;
  } catch (e) { error = e; }
  try {
    // No URL, path, header, error, credential, image metadata or token in receipt.
    await writeJsonExclusive(path.join(root, 'receipt.json'), {
      ownership: 'self-created-random-directory',
      status: complete ? 'complete' : 'unknown',
      objects: records,
    });
  } catch (_) { error = error || new Error('receipt'); }
  if (error) throw error;
}

deadline = Date.now() + LIMIT.overallMs;
// Covers filesystem operations as well as requests; no cleanup or retry on expiry.
const watchdog = setTimeout(() => process.exit(1), LIMIT.overallMs);
main().then(() => {
  clearTimeout(watchdog);
  agent.destroy();
  process.stdout.write('status=complete\n');
}, () => {
  clearTimeout(watchdog);
  agent.destroy();
  // Never print exception messages: libraries may embed URLs or other secrets.
  process.stderr.write('status=unknown; acquisition failed (details suppressed)\n');
  process.exitCode = 1;
});
