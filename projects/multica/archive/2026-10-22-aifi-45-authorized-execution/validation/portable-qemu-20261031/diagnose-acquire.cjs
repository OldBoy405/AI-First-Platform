#!/usr/bin/env node
// Run only after coordinator review, in a clean environment.
// This does not prove isolation, run business code, or constitute acceptance evidence.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const https = require('node:https');
const tls = require('node:tls');
const zlib = require('node:zlib');
const { TextDecoder } = require('node:util');

const MiB = 1024 * 1024;
const utf8 = new TextDecoder('utf-8', { fatal: true });
const MAX_TAR = 512 * MiB;
const MAX_MEMBERS = 200000;
const MAX_MEMBER = 512 * MiB;
const NAME = /^[A-Za-z0-9@._+~-]+$/;
function fail(code) { throw new Error(code); }
function number(s, min, max) {
  if (!/^[0-9]+$/.test(s || '')) fail('BAD_NUMBER');
  const n = Number(s);
  if (!Number.isSafeInteger(n) || n < min || n > max) fail('BAD_NUMBER');
  return n;
}
function options(argv, spec) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    const k = argv[i];
    if (!Object.hasOwn(spec, k) || Object.hasOwn(out, k) || i + 1 >= argv.length) fail('BAD_ARGUMENTS');
    out[k] = argv[i + 1];
  }
  for (const [k, required] of Object.entries(spec)) if (required && !out[k]) fail('BAD_ARGUMENTS');
  return out;
}
// Windows drive-letter paths are allowed; UNC, device and relative paths are not.
const SAME_PATH = (a, b) => (process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b);
function checkedAbsolute(p) {
  if (typeof p !== 'string' || !p || p.includes('\0')) fail('BAD_PATH');
  if (process.platform === 'win32') {
    if (!/^[A-Za-z]:[\\/]/.test(p) || /^[\\/]{2}/.test(p) || /[<>"|*?]/.test(p)) fail('BAD_PATH');
  } else if (!p.startsWith('/') || p.startsWith('//')) fail('BAD_PATH');
  const parts = p.split(/[\\/]+/).filter(Boolean);
  if (parts.some((x) => x === '.' || x === '..')) fail('BAD_PATH');
  if (process.platform === 'win32' && parts[0].length !== 2) fail('BAD_PATH');
  return path.resolve(p);
}
function checkedExisting(p, kind) {
  p = checkedAbsolute(p);
  const parts = p.split(/[\\/]+/).filter(Boolean);
  let cur = process.platform === 'win32' ? parts[0] : '/';
  for (let i = process.platform === 'win32' ? 1 : 0; i < parts.length; i++) {
    cur = path.join(cur, parts[i]);
    const st = fs.lstatSync(cur);
    if (st.isSymbolicLink() || (i < parts.length - 1 && !st.isDirectory())) fail('UNSAFE_PATH');
    if (i === parts.length - 1 && (kind === 'dir' ? !st.isDirectory() : !st.isFile())) fail('WRONG_PATH_TYPE');
  }
  if (!SAME_PATH(fs.realpathSync(p), p)) fail('NONCANONICAL_PATH');
  if (p === '/' && kind !== 'dir') fail('WRONG_PATH_TYPE');
  return p;
}
function contained(parent, child) {
  const rel = path.relative(parent, child);
  return !!rel && !path.isAbsolute(rel) && rel !== '..' && !rel.startsWith('../');
}
function makeOwned(parent, prefix) {
  for (let i = 0; i < 10; i++) {
    const name = prefix + crypto.randomBytes(16).toString('hex');
    const dir = path.join(parent, name);
    try {
      fs.mkdirSync(dir, { mode: 0o700 });
      if (!fs.readdirSync(parent).includes(name) || fs.lstatSync(dir).isSymbolicLink() || !SAME_PATH(fs.realpathSync(dir), dir)) fail('UNSAFE_CREATED_DIRECTORY');
      return { name, dir };
    } catch (e) { if (e.code !== 'EEXIST') throw e; }
  }
  fail('NAME_COLLISION');
}
function exclusiveJson(p, obj) { fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n', { flag: 'wx', mode: 0o600 }); }
function exclusiveText(p, text) { fs.writeFileSync(p, text, { flag: 'wx', mode: 0o600 }); }
function digestFile(p) {
  const fd = fs.openSync(p, 'r');
  const hash = crypto.createHash('sha256');
  const b = Buffer.allocUnsafe(1024 * 1024);
  let size = 0;
  try {
    for (;;) { const n = fs.readSync(fd, b, 0, b.length, null); if (!n) break; size += n; hash.update(b.subarray(0, n)); }
  } finally { fs.closeSync(fd); }
  return { bytes: size, sha256: hash.digest('hex') };
}
function field(buf, start, len) {
  const b = buf.subarray(start, start + len);
  const z = b.indexOf(0);
  return utf8.decode(z < 0 ? b : b.subarray(0, z));
}
function octal(buf, start, len) {
  const s = field(buf, start, len).trim();
  if (!/^[0-7]+$/.test(s)) fail('BAD_TAR_NUMBER');
  const n = parseInt(s, 8);
  if (!Number.isSafeInteger(n)) fail('BAD_TAR_NUMBER');
  return n;
}
function pax(data) {
  const out = Object.create(null);
  let at = 0;
  while (at < data.length) {
    const space = data.indexOf(32, at);
    if (space < 0 || space - at > 12) fail('BAD_PAX');
    const digits = data.subarray(at, space).toString('ascii');
    if (!/^[1-9][0-9]*$/.test(digits)) fail('BAD_PAX');
    const length = Number(digits), end = at + length;
    if (!Number.isSafeInteger(length) || end > data.length || end <= space + 2 || data[end - 1] !== 10) fail('BAD_PAX');
    const record = utf8.decode(data.subarray(space + 1, end - 1));
    const eq = record.indexOf('=');
    if (eq <= 0 || Object.hasOwn(out, record.slice(0, eq))) fail('BAD_PAX');
    const key = record.slice(0, eq);
    if (!['path', 'size', 'linkpath', 'mtime', 'atime', 'ctime', 'uid', 'gid', 'uname', 'gname', 'charset', 'comment'].includes(key)) fail('UNSUPPORTED_PAX');
    out[key] = record.slice(eq + 1);
    at = end;
  }
  return out;
}
// Validate the tar framing and checksums before exposing entries. PAX local
// headers are supported; GNU long-name and global PAX extensions fail closed.
function tarEntries(compressed) {
  const tar = zlib.zstdDecompressSync(compressed, { maxOutputLength: MAX_TAR });
  const entries = [];
  let off = 0, pending = null, ended = false;
  while (off + 512 <= tar.length) {
    const h = tar.subarray(off, off + 512);
    if (h.every(x => x === 0)) {
      if (off + 1024 > tar.length || !tar.subarray(off + 512, off + 1024).every(x => x === 0) || !tar.subarray(off).every(x => x === 0) || pending) fail('BAD_TAR_END');
      ended = true; break;
    }
    let sum = 0;
    for (let i = 0; i < 512; i++) sum += i >= 148 && i < 156 ? 32 : h[i];
    if (sum !== octal(h, 148, 8)) fail('BAD_TAR_CHECKSUM');
    const headerSize = octal(h, 124, 12), mode = octal(h, 100, 8);
    const type = String.fromCharCode(h[156] || 48);
    let name = field(h, 0, 100), prefix = field(h, 345, 155);
    if (prefix) name = prefix + '/' + name;
    let size = headerSize;
    if (type !== 'x' && pending) {
      if (pending.path !== undefined) name = pending.path;
      if (pending.size !== undefined) size = number(pending.size, 0, MAX_MEMBER);
      if (pending.linkpath !== undefined) fail('PAX_LINK');
      pending = null;
    }
    if (size > MAX_MEMBER || name.length > 4096) fail('TAR_LIMIT');
    const begin = off + 512, end = begin + size, next = begin + Math.ceil(size / 512) * 512;
    if (!Number.isSafeInteger(next) || next > tar.length) fail('TRUNCATED_TAR');
    if (type === 'x') {
      if (pending || size > 4 * MiB) fail('BAD_PAX');
      pending = pax(tar.subarray(begin, end));
    } else {
      if (type === 'g' || type === 'L' || type === 'K') fail('UNSUPPORTED_TAR_EXTENSION');
      entries.push({ name, type, mode, size, data: tar.subarray(begin, end) });
      if (entries.length > MAX_MEMBERS) fail('TAR_LIMIT');
    }
    off = next;
  }
  if (!ended) fail('BAD_TAR_END');
  return entries;
}
function safeMember(name, type) {
  if (typeof name !== 'string' || !name || name.includes('\0') || name.includes('\\') || name.includes(':') || name.startsWith('/') || Buffer.byteLength(name, 'utf8') > 4096) fail('BAD_MEMBER_PATH');
  let parts = name.split('/');
  if (parts.includes('..')) fail('BAD_MEMBER_PATH');
  while (parts[0] === '.') parts.shift();
  if (parts[parts.length - 1] === '') { if (type !== '5') fail('BAD_MEMBER_PATH'); parts.pop(); }
  if (parts.some(p => !p || p === '.' || Buffer.byteLength(p, 'utf8') > 255 || /[. ]$/.test(p) || /[<>"|?*\x00-\x1f]/.test(p) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(p))) fail('BAD_MEMBER_PATH');
  if (!parts.length) { if (type !== '5') fail('BAD_MEMBER_PATH'); return '.'; }
  return parts.join('/');
}
function pkginfo(entries) {
  const found = entries.filter(e => e.type === '0' && (e.name === '.PKGINFO' || e.name === './.PKGINFO'));
  if (found.length !== 1 || found[0].size > 4 * MiB) fail('BAD_PKGINFO');
  const text = utf8.decode(found[0].data);
  const values = { depends: [] };
  for (const line of text.split('\n')) {
    const m = /^(pkgname|pkgver|depend) = (.+)\r?$/.exec(line);
    if (!m) continue;
    const v = m[2].replace(/\r$/, '');
    if (m[1] === 'depend') values.depends.push(v);
    else { if (values[m[1]] !== undefined) fail('BAD_PKGINFO'); values[m[1]] = v; }
  }
  if (!values.pkgname || !NAME.test(values.pkgname) || !values.pkgver) fail('BAD_PKGINFO');
  return values;
}
function versionParts(v) {
  if (!/^[0-9A-Za-z._+~:-]+$/.test(v) || v.length > 200) fail('UNCOMPARABLE_VERSION');
  const epoch = v.match(/^([0-9]+)[:~](.+)$/);
  const e = epoch ? epoch[1] : '0';
  const rest = epoch ? epoch[2] : v;
  if (/[:~]/.test(rest)) fail('UNCOMPARABLE_VERSION');
  const parts = rest.match(/[0-9]+|[A-Za-z]+|[._+~-]/g);
  if (!parts || parts.join('') !== rest) fail('UNCOMPARABLE_VERSION');
  return [e, ...parts];
}
function cmpNum(a, b) { a = a.replace(/^0+/, '') || '0'; b = b.replace(/^0+/, '') || '0'; return a.length === b.length ? (a === b ? 0 : a < b ? -1 : 1) : a.length < b.length ? -1 : 1; }
function compareVersion(a, b) {
  if (a === b) return 0;
  const x = versionParts(a), y = versionParts(b);
  let c = cmpNum(x[0], y[0]); if (c) return c;
  for (let i = 1; i < Math.min(x.length, y.length); i++) {
    const an = /^[0-9]+$/.test(x[i]), bn = /^[0-9]+$/.test(y[i]);
    const aa = /^[A-Za-z]+$/.test(x[i]), ba = /^[A-Za-z]+$/.test(y[i]);
    if ((an && bn)) c = cmpNum(x[i], y[i]);
    else if (aa && ba) c = x[i] === y[i] ? 0 : x[i] < y[i] ? -1 : 1;
    else if (x[i] === y[i]) c = 0;
    else fail('UNCOMPARABLE_VERSION');
    if (c) return c;
  }
  fail('UNCOMPARABLE_VERSION');
}
function dependency(s) {
  const m = /^([A-Za-z0-9@._+~-]+)(?:(>=|<=|=|>|<)([0-9A-Za-z._+~:-]+))?$/.exec(s);
  if (!m) fail('BAD_DEPENDENCY');
  return { name: m[1], op: m[2] || null, version: m[3] || null };
}
function satisfies(pkgver, dep) {
  if (!dep.op) return true;
  const c = compareVersion(pkgver, dep.version);
  return dep.op === '=' ? c === 0 : dep.op === '>' ? c > 0 : dep.op === '<' ? c < 0 : dep.op === '>=' ? c >= 0 : c <= 0;
}
function filenameParts(file) {
  const m = /^(mingw-w64-ucrt-x86_64-[A-Za-z0-9@._+~-]+)-([0-9][A-Za-z0-9._+~]*)-([0-9]+(?:\.[0-9]+)*)-any\.pkg\.tar\.zst$/.exec(file);
  if (!m) return null;
  return { name: m[1], version: m[2] + '-' + m[3], file };
}

async function acquire(args) {
  const o = options(args, { '--parent': true, '--max-file-bytes': false, '--max-total-bytes': false, '--request-timeout-ms': false, '--total-timeout-ms': false });
  const parent = checkedExisting(o['--parent'], 'dir');
  const maxFile = o['--max-file-bytes'] ? number(o['--max-file-bytes'], 1, 512 * MiB) : 160 * MiB;
  const maxTotal = o['--max-total-bytes'] ? number(o['--max-total-bytes'], 1, 4 * 1024 * MiB) : 512 * MiB;
  const requestMs = o['--request-timeout-ms'] ? number(o['--request-timeout-ms'], 1000, 30 * 60 * 1000) : 120000;
  const totalMs = o['--total-timeout-ms'] ? number(o['--total-timeout-ms'], 1000, 60 * 60 * 1000) : 30 * 60 * 1000;
  const owned = makeOwned(parent, 'acquire-');
  const completed = [], partial = [], downloads = [];
  let total = 0;
  const deadlineAt = Date.now() + totalMs;
  function checkDeadline() { if (Date.now() >= deadlineAt) fail('TOTAL_TIMEOUT'); }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), totalMs);
  const agent = new https.Agent({ keepAlive: false, rejectUnauthorized: true, ca: tls.rootCertificates });
  async function response(urlPath) {
    checkDeadline();
    if (!/^\/(?:mingw\/ucrt64\/|msys\/x86_64\/)[A-Za-z0-9@._+~/-]*$/.test(urlPath) || urlPath.includes('..')) fail('BAD_URL_PATH');
    const u = new URL('https://repo.msys2.org' + urlPath);
    if (u.protocol !== 'https:' || u.hostname !== 'repo.msys2.org' || u.username || u.password || u.port || u.hash || u.search) fail('BAD_URL');
    return await new Promise((resolve, reject) => {
      const req = https.get(u, { agent, rejectUnauthorized: true, signal: controller.signal, headers: { 'accept-encoding': 'identity' } }, res => {
        res.once('close', () => clearTimeout(deadline));
        if (res.statusCode !== 200) { res.destroy(); reject(new Error('HTTP_STATUS')); return; }
        resolve(res);
      });
      const deadline = setTimeout(() => req.destroy(new Error('REQUEST_TIMEOUT')), requestMs);
      req.once('error', e => { clearTimeout(deadline); reject(e); });
    });
  }
  function count(n, local, limit) {
    checkDeadline();
    total += n;
    if (total > maxTotal || local > limit) fail('DOWNLOAD_LIMIT');
  }
  async function download(urlPath, file, limit) {
    const dest = path.join(owned.dir, file);
    const fd = fs.openSync(dest, 'wx', 0o600);
    partial.push(file);
    let size = 0;
    const h = crypto.createHash('sha256');
    try {
      const res = await response(urlPath);
      for await (const chunk of res) {
        size += chunk.length; count(chunk.length, size, limit);
        h.update(chunk);
        let at = 0;
        while (at < chunk.length) {
          const n = fs.writeSync(fd, chunk, at, chunk.length - at);
          if (n <= 0) fail('WRITE_FAILURE');
          at += n;
        }
      }
    } finally { fs.closeSync(fd); }
    const sum = h.digest('hex'), readback = digestFile(dest);
    checkDeadline();
    if (readback.bytes !== size || readback.sha256 !== sum) fail('READBACK_MISMATCH');
    const item = { file, url_path: urlPath, bytes: size, sha256: sum };
    downloads.push(item);
    return item;
  }
  function checkedPackageBytes(item) {
    const data = fs.readFileSync(path.join(owned.dir, item.file));
    if (data.length !== item.bytes || crypto.createHash('sha256').update(data).digest('hex') !== item.sha256) fail('READBACK_MISMATCH');
    checkDeadline();
    return data;
  }
  async function packageAndSig(urlPath) {
    const file = urlPath.slice(urlPath.lastIndexOf('/') + 1);
    if (!NAME.test(file)) fail('BAD_FILENAME');
    const pkg = await download(urlPath, file, maxFile);
    const sig = await download(urlPath + '.sig', file + '.sig', Math.min(maxFile, 4 * MiB));
    return { ...pkg, signature: sig };
  }
  async function index() {
    const res = await response('/mingw/ucrt64/');
    let size = 0, pending = '', lines = 0;
    const map = new Map();
    const decoder = new TextDecoder('utf-8', { fatal: true });
    function line(s) {
      if (++lines > 500000 || s.length > 65536) fail('INDEX_LIMIT');
      // Apache truncates long link text, so only the href is authoritative.
      const m = /<a href="([A-Za-z0-9@._+~-]+)">[^<]*<\/a>\s+[0-9]{2}-[A-Za-z]{3}-[0-9]{4}\s+[0-9]{2}:[0-9]{2}\s+[0-9]+(?:\.[0-9]+)?[KMGT]?\s*$/i.exec(s);
      if (!m) return;
      const item = filenameParts(m[1]);
      if (!item) return;
      const list = map.get(item.name) || [];
      list.push(item); map.set(item.name, list);
    }
    for await (const chunk of res) {
      size += chunk.length; count(chunk.length, size, 32 * MiB);
      pending += decoder.decode(chunk, { stream: true });
      let p;
      while ((p = pending.indexOf('\n')) >= 0) { line(pending.slice(0, p).replace(/\r$/, '')); pending = pending.slice(p + 1); }
      if (pending.length > 65536) fail('INDEX_LIMIT');
    }
    pending += decoder.decode();
    if (pending) line(pending.replace(/\r$/, ''));
    return map;
  }
  try {
    const key = await packageAndSig('/msys/x86_64/msys2-keyring-1~20260814-1-any.pkg.tar.zst');
    const keyEntries = tarEntries(checkedPackageBytes(key));
    checkDeadline();
    const keyInfo = pkginfo(keyEntries);
    if (keyInfo.pkgname !== 'msys2-keyring' || keyInfo.pkgver.replace(':', '~') !== '1~20260814-1') fail('KEYRING_IDENTITY');
    key.pkgname = keyInfo.pkgname; key.pkgver = keyInfo.pkgver; key.depends = keyInfo.depends;
    key.file_list = keyEntries.map(e => ({ name: e.name, type: e.type, bytes: e.size }));
    key.role = 'keyring'; completed.push(key);
    const idx = await index();
    const root = 'mingw-w64-ucrt-x86_64-qemu';
    const rootFile = root + '-11.1.3-1-any.pkg.tar.zst';
    const rootItem = filenameParts(rootFile);
    if (!(idx.get(root) || []).some(x => x.file === rootFile)) fail('ROOT_NOT_IN_INDEX');
    // The pinned root must also be the highest indexed version.
    function best(name) {
      const list = idx.get(name);
      if (!list || !list.length) fail('DEPENDENCY_NOT_FOUND');
      let candidate = list[0];
      for (const item of list.slice(1)) {
        const c = compareVersion(item.version, candidate.version);
        if (c > 0) candidate = item;
        else if (c === 0 && item.file !== candidate.file) fail('AMBIGUOUS_VERSION');
      }
      return candidate;
    }
    if (best(root).file !== rootItem.file) fail('PINNED_ROOT_NOT_LATEST');
    const queue = [root], selected = new Map(), requirements = new Map();
    while (queue.length) {
      const name = queue.shift();
      if (selected.has(name)) continue;
      if (selected.size >= 60) fail('PACKAGE_LIMIT');
      const item = best(name);
      const entry = await packageAndSig('/mingw/ucrt64/' + item.file);
      const info = pkginfo(tarEntries(checkedPackageBytes(entry)));
      checkDeadline();
      if (info.pkgname !== name || info.pkgver.replace(':', '~') !== item.version) fail('PACKAGE_IDENTITY');
      entry.pkgname = name; entry.pkgver = info.pkgver; entry.depends = info.depends; entry.role = 'dependency-closure';
      selected.set(name, entry); completed.push(entry);
      for (const raw of info.depends) {
        const dep = dependency(raw);
        const list = requirements.get(dep.name) || [];
        list.push(dep); requirements.set(dep.name, list);
        if (!selected.has(dep.name) && !queue.includes(dep.name)) queue.push(dep.name);
      }
    }
    for (const [name, deps] of requirements) {
      const item = selected.get(name);
      if (!item || deps.some(d => !satisfies(item.pkgver, d))) fail('UNSATISFIED_DEPENDENCY');
    }
    checkDeadline();
    const result = { schema: 1, status: 'complete-unverified-signatures', packages: completed, dependency_closure: [...selected.keys()], total_network_bytes: total };
    exclusiveText(path.join(owned.dir, 'acquisition-summary.txt'), `Status: complete; signatures NOT verified\nClosure packages: ${selected.size}\nNetwork bytes: ${total}\n`);
    checkDeadline();
    exclusiveJson(path.join(owned.dir, 'acquisition.json'), result);
    process.stdout.write(owned.name + ' OK\n');
  } catch (e) {
    process.stderr.write('DIAG '+(e&&e.stack||e)+'\n');
    try { exclusiveJson(path.join(owned.dir, 'acquisition-unknown.json'), { schema: 1, status: 'unknown', reason: /^[A-Z_]+$/.test(e.message || '') ? e.message : 'IO_OR_FORMAT_FAILURE', completed, downloads, created_files: partial, total_network_bytes: total }); } catch (_) { /* preserve all files */ }
    process.stdout.write(owned.name + ' FAILED\n');
    process.exitCode = 1;
  } finally { clearTimeout(timer); agent.destroy(); }
}

module.exports = { MiB, MAX_MEMBERS, MAX_MEMBER, fail, options, checkedAbsolute, checkedExisting, contained, makeOwned, exclusiveJson, exclusiveText, digestFile, tarEntries, safeMember };
if (require.main === module) acquire(process.argv.slice(2)).catch(() => { process.stdout.write('FAILED\n'); process.exitCode = 1; });
