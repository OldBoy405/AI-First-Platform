// AIFIRST: trusted T committed verdict channel (M003) — the protected store.
//
// One request may change business state once. The store enforces that with three
// artefacts per store:
//
//   head.json            the chain head: sequence and the digest of the last frame
//   frames/<seq>-<d>.json one frozen envelope per committed change, write-once
//   journal.json          "prepared" marker written BEFORE anything is published
//
// The journal is durable before the business function runs; the frame precedes the
// head, and the head precedes journal removal. A crash can leave a journal with no
// frame, a frame ahead of head, or an already-advanced head. applyOnce refuses all
// of these unresolved states; a separate trusted recovery must decide how to proceed.
//
// Frame digests detect inconsistent contents, not an authenticated history or rollback.
// This store does not itself authenticate signatures or serialize concurrent writers.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { TxError } from './workspace-transactions.mjs';

const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const HEX64_RE = /^[0-9a-f]{64}$/;
const MAX_COMMAND_BYTES = 2 * 1024 * 1024;
const MAX_RESULT_BYTES = 8 * 1024 * 1024;

function isCanonicalSignature(signature) {
  if (typeof signature !== 'string' || signature.length !== 88) return false;
  const bytes = Buffer.from(signature, 'base64');
  return bytes.length === 64 && bytes.toString('base64') === signature;
}

function reject(code, message, cause) {
  throw new TxError(code, message, cause ? { cause_code: cause } : undefined);
}

function writeDurable(file, bytes, hooks) {
  const temp = `${file}.tmp`;
  const fd = fs.openSync(temp, 'wx', 0o600);
  try {
    for (let offset = 0; offset < bytes.length;) {
      const written = fs.writeSync(fd, bytes, offset, bytes.length - offset);
      if (!Number.isSafeInteger(written) || written <= 0 || written > bytes.length - offset) {
        reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '持久文件写入未完成');
      }
      offset += written;
    }
    hooks.fsync(fd, 'file');
  } finally {
    fs.closeSync(fd);
  }
  hooks.beforeRename(file);
  fs.renameSync(temp, file);
  const dirFd = fs.openSync(path.dirname(file), process.platform === 'win32' ? 'r+' : 'r');
  try { hooks.fsync(dirFd, 'dir'); } finally { fs.closeSync(dirFd); }
}

function syncDir(dir, hooks) {
  const fd = fs.openSync(dir, process.platform === 'win32' ? 'r+' : 'r');
  try { hooks.fsync(fd, 'dir'); } finally { fs.closeSync(fd); }
}

function defaultHooks() {
  return {
    failAt: null,
    fsync(fd, kind) {
      if (this.failAt === `fsync:${kind}`) reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', `注入的 fsync 失败（${kind}）`);
      fs.fsyncSync(fd);
    },
    beforeRename(file) {
      if (this.failAt === 'rename') reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '注入的 rename 前失败');
      void file;
    },
    beforeProduce() {
      if (this.failAt === 'produce') reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '注入的业务函数失败');
    },
    beforeFrame() {
      if (this.failAt === 'frame') reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '注入的 frame 发布前失败');
    },
  };
}

function readHead(headPath) {
  let bytes;
  try { bytes = fs.readFileSync(headPath, 'utf8'); }
  catch (error) {
    if (error.code === 'ENOENT') {
      try { fs.lstatSync(headPath); }
      catch (statError) {
        if (statError.code === 'ENOENT') return { sequence: 0, digest: null };
        reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '无法检查 head.json', statError.code);
      }
      reject('EXECUTION_CONTROL_STORE_CORRUPT', 'head.json 路径存在但目标不可读取');
    }
    reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '无法读取 head.json', error.code);
  }
  let head;
  try { head = JSON.parse(bytes); }
  catch { reject('EXECUTION_CONTROL_STORE_CORRUPT', 'head.json 不可解析'); }
  if (!head || typeof head !== 'object' || Array.isArray(head) || !Number.isSafeInteger(head.sequence) || head.sequence < 0
      || (head.sequence === 0 ? head.digest !== null : typeof head.digest !== 'string' || !HEX64_RE.test(head.digest))) {
    reject('EXECUTION_CONTROL_STORE_CORRUPT', 'head.json 内容不合法');
  }
  return head;
}

/** Open (creating if needed) one store root. Absolute path only, never inside an agent-writable root. */
export function openControlStore({ root, storeId, forbiddenRoots = [] }) {
  if (typeof root !== 'string' || !path.isAbsolute(root)) reject('EXECUTION_CONTROL_STORE_INVALID', 'store root 必须是绝对路径');
  if (typeof storeId !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}$/.test(storeId)) {
    reject('EXECUTION_CONTROL_STORE_INVALID', 'storeId 不合法');
  }
  const resolved = path.resolve(root);
  for (const forbidden of forbiddenRoots) {
    if (typeof forbidden !== 'string' || !path.isAbsolute(forbidden)) continue;
    const rootPath = path.resolve(forbidden);
    if (resolved === rootPath || resolved.startsWith(`${rootPath}${path.sep}`)) {
      reject('EXECUTION_CONTROL_STORE_INVALID', 'store root 位于 agent 可写根内');
    }
  }
  const dir = path.join(resolved, storeId);
  fs.mkdirSync(path.join(dir, 'frames'), { recursive: true, mode: 0o700 });
  const headPath = path.join(dir, 'head.json');
  const journalPath = path.join(dir, 'journal.json');
  const head = readHead(headPath);
  return { dir, head, headPath, journalPath, framesDir: path.join(dir, 'frames') };
}

export function readJournal(store) {
  if (!fs.existsSync(store.journalPath)) return null;
  try { return JSON.parse(fs.readFileSync(store.journalPath, 'utf8')); }
  catch { reject('EXECUTION_CONTROL_STORE_CORRUPT', 'journal.json 不可解析'); }
}

export function readFrames(store) {
  return fs.readdirSync(store.framesDir)
    .filter(name => name.endsWith('.json'))
    .sort()
    .map(name => {
      try { return JSON.parse(fs.readFileSync(path.join(store.framesDir, name), 'utf8')); }
      catch { reject('EXECUTION_CONTROL_STORE_CORRUPT', `frame ${name} 不可解析`); }
    });
}

/**
 * Check the frame sequence, predecessor links, signature shape and content digests.
 * A 64-byte signature is only a shape check; authentication is a separate operation.
 */
export function assertFrameChain(frames) {
  let expectedSequence = 1;
  let previousDigest = null;
  for (const frame of frames) {
    if (!frame || typeof frame !== 'object' || Array.isArray(frame)) {
      reject('EXECUTION_CONTROL_STORE_CORRUPT', 'frame 不是对象');
    }
    if (frame.sequence !== expectedSequence) {
      reject('EXECUTION_CONTROL_STORE_CORRUPT', `frame 链跳号：期望 ${expectedSequence}，实际 ${frame.sequence}`);
    }
    if (frame.previous_digest !== previousDigest) {
      reject('EXECUTION_CONTROL_STORE_CORRUPT', `frame ${frame.sequence} 的 previous_digest 未指向前一帧`);
    }
    if (!isCanonicalSignature(frame.signature)) {
      reject('EXECUTION_CONTROL_STORE_CORRUPT', `frame ${frame.sequence} 的签名不是规范编码的 64 bytes`);
    }
    if (typeof frame.digest !== 'string' || !HEX64_RE.test(frame.digest)) {
      reject('EXECUTION_CONTROL_STORE_CORRUPT', `frame ${frame.sequence} 缺少 digest`);
    }
    const body = {
      sequence: frame.sequence,
      previous_digest: frame.previous_digest,
      request_id: frame.request_id,
      command_digest: frame.command_digest,
      result_b64: frame.result_b64,
      signature: frame.signature,
    };
    if (sha256(Buffer.from(JSON.stringify(body), 'utf8')) !== frame.digest) {
      reject('EXECUTION_CONTROL_STORE_CORRUPT', `frame ${frame.sequence} 的 digest 与内容不符`);
    }
    previousDigest = frame.digest;
    expectedSequence += 1;
  }
  return { sequence: previousDigest ? expectedSequence - 1 : 0, digest: previousDigest };
}

/**
 * Apply one request at most once.
 *
 * `request` = { requestId, commandBytes, signature }. `produce` runs only when the
 * request has no committed frame; its returned bytes are frozen in the frame.
 * A replay with the same command bytes returns the original bytes and does not run
 * `produce` again. The same request with different bytes is a conflict.
 */
export function applyOnce(store, request, produce, options = {}) {
  const hooks = { ...defaultHooks(), ...(options.hooks ?? {}) };
  const { requestId, commandBytes, signature } = request ?? {};
  if (typeof requestId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestId)) {
    reject('EXECUTION_CONTROL_STORE_INVALID', 'requestId 不合法');
  }
  if (!Buffer.isBuffer(commandBytes) || !commandBytes.length || commandBytes.length > MAX_COMMAND_BYTES) {
    reject('EXECUTION_CONTROL_STORE_INVALID', 'commandBytes 缺失或超过大小上限');
  }
  if (!isCanonicalSignature(signature)) {
    reject('EXECUTION_CONTROL_STORE_INVALID', 'signature 必须是规范 base64 编码的 64 bytes');
  }
  if (typeof produce !== 'function') reject('EXECUTION_CONTROL_STORE_INVALID', 'produce 必须是函数');

  let pendingJournal = false;
  try { fs.lstatSync(store.journalPath); pendingJournal = true; }
  catch (error) {
    if (error.code !== 'ENOENT') reject('EXECUTION_CONTROL_STORE_UNAVAILABLE', '无法检查 journal', error.code);
  }
  if (pendingJournal) {
    reject('EXECUTION_CONTROL_STORE_RECOVERY_REQUIRED', '未完成的 journal 必须先恢复');
  }
  const frames = readFrames(store);
  const head = assertFrameChain(frames);
  const diskHead = readHead(store.headPath);
  if (head.sequence !== diskHead.sequence || head.digest !== diskHead.digest) {
    reject('EXECUTION_CONTROL_STORE_CORRUPT', 'head.json 与 frames 不一致');
  }
  store.head = diskHead;
  const commandDigest = sha256(commandBytes);
  const existing = frames.find(frame => frame.request_id === requestId);
  if (existing) {
    if (existing.command_digest !== commandDigest) {
      reject('EXECUTION_CONTROL_STORE_CONFLICT', '同一 request 的 command bytes 不同，拒绝替换');
    }
    return {
      replayed: true,
      frame: existing,
      resultBytes: Buffer.from(existing.result_b64, 'base64'),
      envelope: existing,
    };
  }

  const sequence = head.sequence + 1;

  // 1. Journal first: after this point a crash is recoverable, before it nothing happened.
  const journal = { request_id: requestId, command_digest: commandDigest, sequence, phase: 'prepared' };
  writeDurable(store.journalPath, Buffer.from(JSON.stringify(journal), 'utf8'), hooks);

  // 2. Business change.
  hooks.beforeProduce();
  const resultBytes = produce({ requestId, commandBytes, sequence });
  if (!Buffer.isBuffer(resultBytes) || resultBytes.length > MAX_RESULT_BYTES) {
    reject('EXECUTION_CONTROL_STORE_INVALID', 'produce 必须返回有界的 Buffer');
  }

  // 3. Frame, then head, then clear the journal.
  const body = {
    sequence,
    previous_digest: head.digest,
    request_id: requestId,
    command_digest: commandDigest,
    result_b64: resultBytes.toString('base64'),
    signature,
  };
  const digest = sha256(Buffer.from(JSON.stringify(body), 'utf8'));
  const frame = { ...body, digest };
  hooks.beforeFrame();
  writeDurable(path.join(store.framesDir, `${String(sequence).padStart(6, '0')}-${digest}.json`),
    Buffer.from(JSON.stringify(frame), 'utf8'), hooks);
  writeDurable(store.headPath, Buffer.from(JSON.stringify({ sequence, digest }), 'utf8'), hooks);
  fs.unlinkSync(store.journalPath);
  syncDir(store.dir, hooks);

  store.head = { sequence, digest };
  return { replayed: false, frame, resultBytes, envelope: frame };
}
