#!/usr/bin/env node
// Run only after coordinator review, in a clean environment.
// This does not prove isolation, run business code, or constitute acceptance evidence.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
// The adjacent acquisition script exports the shared, built-in-only tar parser.
// Importing it does not start acquisition.
const u = require('./portable-qemu-acquire.cjs');

const MAX_JSON = 32 * u.MiB;
const MAX_PACKAGES = 61; // keyring plus at most 60 closure packages
const MAX_ARCHIVE = 512 * u.MiB;
const MAX_EXTRACTED = 4 * 1024 * u.MiB;
const MAX_ENTRIES = 200000;
function checkFileName(s) {
  if (typeof s !== 'string' || !/^[A-Za-z0-9@._+~-]+\.pkg\.tar\.zst$/.test(s) || s.includes('..')) u.fail('BAD_ARCHIVE_NAME');
  return s;
}
function checkDigest(s) { if (typeof s !== 'string' || !/^[0-9a-f]{64}$/.test(s)) u.fail('BAD_DIGEST'); }
function ensureDirectory(root, rel) {
  let current = root;
  if (!rel || rel === '.') return;
  for (const part of rel.split('/')) {
    current = path.join(current, part);
    try { fs.mkdirSync(current, { mode: 0o700 }); }
    catch (e) { if (e.code !== 'EEXIST') throw e; }
    const st = fs.lstatSync(current);
    if (st.isSymbolicLink() || !st.isDirectory()) u.fail('UNSAFE_OUTPUT_DIRECTORY');
  }
}
function extract(args) {
  const opts = u.options(args, { '--parent': true, '--acquisition': true });
  const parent = u.checkedExisting(opts['--parent'], 'dir');
  const acquisition = u.checkedExisting(opts['--acquisition'], 'file');
  if (!u.contained(parent, acquisition) || path.basename(acquisition) !== 'acquisition.json') u.fail('BAD_ACQUISITION_PATH');
  const st = fs.statSync(acquisition);
  if (st.size > MAX_JSON) u.fail('MANIFEST_LIMIT');
  const manifest = JSON.parse(fs.readFileSync(acquisition, 'utf8'));
  if (!manifest || manifest.schema !== 1 || manifest.status !== 'complete-unverified-signatures' || !Array.isArray(manifest.packages) || !manifest.packages.length || manifest.packages.length > MAX_PACKAGES) u.fail('BAD_MANIFEST');
  const source = path.dirname(acquisition);
  const archiveNames = new Set();
  for (const pkg of manifest.packages) {
    if (!pkg || typeof pkg !== 'object') u.fail('BAD_MANIFEST');
    checkFileName(pkg.file); checkDigest(pkg.sha256);
    if (!Number.isSafeInteger(pkg.bytes) || pkg.bytes < 1 || pkg.bytes > MAX_ARCHIVE || typeof pkg.pkgname !== 'string' || !pkg.pkgname || pkg.pkgname.length > 255) u.fail('BAD_MANIFEST');
    if (archiveNames.has(pkg.file.toLowerCase())) u.fail('DUPLICATE_ARCHIVE');
    archiveNames.add(pkg.file.toLowerCase());
  }
  const owned = u.makeOwned(parent, 'extract-');
  let total = 0, count = 0;
  const files = [], seen = new Set();
  // Reserve result names so a package cannot pre-create either result file.
  const reserved = new Set(['extract-manifest.json', 'extract-summary.txt']);
  try {
    for (const pkg of manifest.packages) {
      const archive = u.checkedExisting(path.join(source, pkg.file), 'file');
      if (!u.contained(source, archive)) u.fail('BAD_ARCHIVE_PATH');
      const check = u.digestFile(archive);
      if (check.bytes !== pkg.bytes || check.sha256 !== pkg.sha256) u.fail('ARCHIVE_MISMATCH');
      const compressed = fs.readFileSync(archive);
      if (compressed.length !== pkg.bytes || crypto.createHash('sha256').update(compressed).digest('hex') !== pkg.sha256) u.fail('ARCHIVE_MISMATCH');
      const entries = u.tarEntries(compressed);
      for (const e of entries) {
        if (++count > MAX_ENTRIES) u.fail('ENTRY_LIMIT');
        if (e.type !== '0' && e.type !== '5') u.fail('UNSUPPORTED_MEMBER_TYPE');
        if (e.mode & 0o7000) u.fail('SPECIAL_MODE');
        if (e.size > u.MAX_MEMBER || (e.type === '5' && e.size !== 0)) u.fail('MEMBER_LIMIT');
        const rel = u.safeMember(e.name, e.type);
        // Pacman metadata repeats in every archive and carries no payload.
        if (/^\.(PKGINFO|MTREE|BUILDINFO|BUILDID|INSTALL|CHANGELOG)$/.test(rel)) continue;
        // Case-folding also rejects aliases on common case-insensitive filesystems.
        const key = rel.toLowerCase();
        // Directories legitimately repeat across packages; regular files must not.
        if (seen.has(key) || (e.type !== '5' && reserved.has(key))) u.fail('DUPLICATE_MEMBER');
        seen.add(key);
        if (rel === '.') continue;
        const dest = path.join(owned.dir, ...rel.split('/'));
        if (!u.contained(owned.dir, dest)) u.fail('BAD_OUTPUT_PATH');
        if (e.type === '5') {
          ensureDirectory(owned.dir, rel);
        } else {
          total += e.size;
          if (total > MAX_EXTRACTED) u.fail('EXTRACTED_SIZE_LIMIT');
          const slash = rel.lastIndexOf('/');
          ensureDirectory(owned.dir, slash < 0 ? '' : rel.slice(0, slash));
          // Preserve only the owner's executable capability, never special bits.
          const fd = fs.openSync(dest, 'wx', (e.mode & 0o111) ? 0o700 : 0o600);
          try {
            let offset = 0;
            while (offset < e.data.length) {
              const n = fs.writeSync(fd, e.data, offset, e.data.length - offset);
              if (n <= 0) u.fail('WRITE_FAILURE');
              offset += n;
            }
          } finally { fs.closeSync(fd); }
          const expected = crypto.createHash('sha256').update(e.data).digest('hex');
          const actual = u.digestFile(dest);
          if (actual.bytes !== e.size || actual.sha256 !== expected) u.fail('OUTPUT_MISMATCH');
          files.push({ path: rel, bytes: e.size, sha256: expected, source_package: pkg.pkgname, source_archive: pkg.file });
        }
      }
    }
    u.exclusiveText(path.join(owned.dir, 'extract-summary.txt'), `Status: complete; package signatures not verified by this tool\nPackages: ${manifest.packages.length}\nFiles: ${files.length}\nFile bytes: ${total}\n`);
    u.exclusiveJson(path.join(owned.dir, 'extract-manifest.json'), { schema: 1, status: 'complete', signature_verification: 'not performed', archive_count: manifest.packages.length, member_count: count, file_bytes: total, files });
    process.stdout.write(owned.name + ' OK\n');
  } catch (_) {
    process.stdout.write(owned.name + ' FAILED\n');
    process.exitCode = 1;
  }
}
try { extract(process.argv.slice(2)); }
catch (_) { process.stdout.write('FAILED\n'); process.exitCode = 1; }
