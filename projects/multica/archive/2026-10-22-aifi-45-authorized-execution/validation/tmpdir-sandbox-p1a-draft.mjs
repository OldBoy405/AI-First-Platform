// P1a v0.1.1 — REVIEW ONLY. This file has NOT been approved for execution.
// Independent review must produce a new reviewed revision before changing this lock.
// Only create / projected OWN inspect / unforced rm; existing containers: ps only.
// Missing offline Podman info schema evidence is a separate, fail-closed BLOCK.
// The inherited command is inert configuration, not a command this runner invokes.
import { execFile } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { closeSync, fsyncSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REVIEWED_FOR_EXECUTION = false;
const VERSION = 'p1a-draft/0.1.1';
const ROOT = dirname(fileURLToPath(import.meta.url));
const TEMPLATE = join(ROOT, 'tmpdir-sandbox-p1-33208526b7482e14693a');
// Offline raw-byte anchors, NOT approval. Independently recheck these before execution.
const FROZEN_INTENT_SHA256 = '81a1ab01c37725b66736c61ede5d34cb243e1eaf6fa5cb0792112d5e7eb92d01';
const FROZEN_SOURCE_SHA256 = '673ac45c194d0770bb5be0288e48f74b511bc8930e42d1db985dae1bb5faa66f';
const APPROVAL_FILE = join(ROOT, 'tmpdir-sandbox-p1a-execution-approval.json');
const REVIEW_FILE = join(ROOT, 'tmpdir-sandbox-p1a-review.md');
const INFO_BASIS_FILE = join(ROOT, 'tmpdir-sandbox-p1a-info-schema.md');
const PROTECTED_STATE_PROOF = 'ps ID/state snapshots only; no StartedAt/restart-count, history, volume-content or isolation proof';
const EXE = 'C:/Program Files/RedHat/Podman/podman.exe';
const CONNECTION = 'podman-machine-default';
const IMAGE = 'e8d5705906235eb37953eaba46b51a273440dc3552fe1c8b5f2d743cfcb31350';
const OLD_NONCE = '8871bdc64ef539ea999c668f9c26a412';
const OLD_NAME = `multica-tmpdir-sbx-p1-${OLD_NONCE}`;
const MANIFEST = '7fac386da3a4ab1f73e7e71b09da6c62beac175496806631c04a2fd96e22ca08';
const PROTECTED = [
  '01050b2499847e72b06cb5d84b8ec2945dc75045842544a65caf550ef573a762',
  '666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823',
  '96211305e92b4ec8a686b5f774cac92e960b86ce14acaa40eb8c1201e993e01f',
];
// Literal audited argv, including the deliberately inert image command. No archive
// is generated, read, supplied on stdin, or executed; no old script is imported.
const EXPECTED_ARGS = [
  'create', '-i', '--name', OLD_NAME,
  '--label', 'io.multica.sbx.purpose=tmpdir-path-p1', '--label', `io.multica.sbx.nonce=${OLD_NONCE}`,
  '--pull=never', '--image-volume=ignore', '--read-only', '--read-only-tmpfs=false',
  '--tmpfs', '/work:rw,exec,nosuid,nodev,size=16m,mode=1777', '--tmpfs', '/tmp:rw,exec,nosuid,nodev,size=8m,mode=1777',
  '--network=none', '--http-proxy=false', '--cap-drop=all', '--security-opt=no-new-privileges', '--user', '65534:65534',
  '--pids-limit=64', '--memory=128m', '--memory-swap=128m', '--cpus=0.5', '--ulimit', 'nofile=256:256',
  '--restart=no', '--timeout=60', '--stop-timeout=2', '--unsetenv-all',
  '--env', 'PATH=/usr/bin:/bin', '--env', 'HOME=/work/home', '--env', 'LANG=C', '--env', `SBX_MANIFEST_SHA256=${MANIFEST}`,
  '--entrypoint=/bin/bash', IMAGE, '--noprofile', '--norc', '-c',
  'set -eu; mkdir /work/in; tar -x --no-same-owner --no-same-permissions -C /work/in -f -; cd /work/in; [ "$(sha256sum manifest.sha256 | cut -d" " -f1)" = "$SBX_MANIFEST_SHA256" ]; sha256sum -c --strict --quiet manifest.sha256; exec /bin/bash --noprofile --norc probe.sh',
];
const need = (ok, code) => { if (!ok) throw new Error(code); };
const bytes = path => readFileSync(path); // Hash original bytes; never normalize CRLF/BOM/encoding.
const sha = value => createHash('sha256').update(value).digest('hex');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const fullID = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const empty = expr => `{{if ${expr}}}false{{else}}true{{end}}`;
const field = (key, expr) => ({ key, template: `{{json ${expr}}}` });
const raw = (key, template) => ({ key, template });
const projection = fields => `{${fields.map(x => `${JSON.stringify(x.key)}:${x.template}`).join(',')}}`;
const PS_STATE_ARGS = ['ps', '-a', '--no-trunc', '--format', projection([
  field('id', '.ID'), field('state', '.State'),
])];
// BLOCK: no offline, fixed-version Go-struct/template basis is available here.
// In particular, the prior .Host.Security.SeccompEnabled spelling is UNVERIFIED.
// A newly reviewed revision must supply the exact template and a raw-byte-bound
// INFO_BASIS_FILE explaining the matching client/server versions and Go fields
// for rootless/seccomp/graphRoot/controllers. JSON tags are not Go field proof.
const INFO_FORMAT = null;
const SET_COMMANDS = {
  containers: ['ps', '-a', '-q', '--no-trunc'],
  volumes: ['volume', 'ls', '-q'],
  networks: ['network', 'ls', '-q', '--no-trunc'],
  images: ['images', '-q', '--no-trunc'],
  pods: ['pod', 'ps', '-q', '--no-trunc'],
};
const withSHA = value => typeof value === 'string' ? value.replace(/^sha256:/, '') : value;
const tmpfsOK = (value, size) => {
  if (typeof value !== 'string') return false;
  const options = value.split(',');
  const required = ['rw', 'exec', 'nosuid', 'nodev', `size=${size}`, 'mode=1777'];
  const allowed = new Set([...required, 'rprivate', 'tmpcopyup', 'notmpcopyup']);
  return required.every(x => options.includes(x)) && options.every(x => allowed.has(x));
};

async function main() {
  // No filesystem writes, CLI calls, environment reads, or automatic unlock here.
  need(REVIEWED_FOR_EXECUTION, 'REVIEW_ONLY_EXECUTION_LOCKED');
  need(process.argv.length === 3 && /^--approval-sha256=[a-f0-9]{64}$/.test(process.argv[2]),
    'INDEPENDENT_APPROVAL_DIGEST_REQUIRED');
  need(typeof INFO_FORMAT === 'string' && INFO_FORMAT.length > 0, 'PODMAN_INFO_OFFLINE_SCHEMA_UNVERIFIED_BLOCK');
  // Freeze the FINAL execution file first (including any lock/schema edits), then
  // independently review it and issue a detached approval. The current REVIEW_FILE
  // says BLOCK; binding its hash alone is NOT approval. The operator must obtain
  // this approval digest out-of-band from a new independent review, NOT from this runner or an
  // untrusted self-computed hash. No embedded approval hash: avoid a hash cycle.
  const approvalSHA256 = process.argv[2].slice('--approval-sha256='.length);
  const approvalBytes = bytes(APPROVAL_FILE);
  need(sha(approvalBytes) === approvalSHA256, 'INDEPENDENT_APPROVAL_RECORD_HASH_MISMATCH');
  const approval = JSON.parse(approvalBytes.toString('utf8'));
  const runnerHash = sha(bytes(fileURLToPath(import.meta.url)));
  const reviewHash = sha(bytes(REVIEW_FILE));
  const infoBasisHash = sha(bytes(INFO_BASIS_FILE));
  const infoFormatHash = sha(Buffer.from(INFO_FORMAT, 'utf8'));
  need(approval.schema === 'multica-p1a-approval/v1' && approval.decision === 'APPROVED_CREATE_ONLY' &&
    approval.scope === 'one-new-own-container-create-inspect-unforced-rm-no-start' && approval.version === VERSION &&
    approval.runnerSHA256 === runnerHash && approval.reviewSHA256 === reviewHash &&
    approval.templateIntentSHA256 === FROZEN_INTENT_SHA256 && approval.templateSourceSHA256 === FROZEN_SOURCE_SHA256 &&
    approval.infoSchemaBasisSHA256 === infoBasisHash && approval.infoFormatSHA256 === infoFormatHash,
  'INDEPENDENT_APPROVAL_BINDING_MISMATCH');
  // Hashes check integrity, not reviewer identity or semantic approval. A trusted
  // independent reviewer must approve all these exact bytes and the reduced ps proof.
  const approvalBinding = { approvalSHA256, runnerSHA256: runnerHash, reviewSHA256: reviewHash,
    infoSchemaBasisSHA256: infoBasisHash, infoFormatSHA256: infoFormatHash };
  const templateBytes = bytes(join(TEMPLATE, 'intent.json'));
  const sourceHash = sha(bytes(join(TEMPLATE, 'run-p1.mjs'))); // Never evaluate/import old source.
  need(sha(templateBytes) === FROZEN_INTENT_SHA256 && sourceHash === FROZEN_SOURCE_SHA256,
    'FROZEN_TEMPLATE_RAW_BYTE_HASH_MISMATCH');
  const template = JSON.parse(templateBytes.toString('utf8'));
  need(template.image === IMAGE && template.connection === CONNECTION && template.podmanExe === EXE &&
    template.name === OLD_NAME && template.nonce === OLD_NONCE && template.manifestHash === MANIFEST,
  'TEMPLATE_IDENTITY_DRIFT');
  need(Array.isArray(template.createArgs) && template.createArgs.length === EXPECTED_ARGS.length &&
    EXPECTED_ARGS.every((arg, index) => template.createArgs[index] === arg), 'TEMPLATE_ARG_FIELD_DRIFT');
  need(equal(template.pre?.containers, PROTECTED) && Array.isArray(template.pre?.volumes) &&
    Array.isArray(template.pre?.networks) && Array.isArray(template.pre?.images) &&
    template.pre.images.includes(IMAGE), 'TEMPLATE_PRESET_INVALID');

  need(Array.isArray(template.protectedBefore) && template.protectedBefore.length === PROTECTED.length,
    'TEMPLATE_PROTECTED_STATE_INVALID');
  const historicalStates = PROTECTED.map(id => {
    const rows = template.protectedBefore.filter(x => x.id === id);
    need(rows.length === 1 && typeof rows[0].status === 'string', 'TEMPLATE_PROTECTED_STATE_INVALID');
    return { id, state: rows[0].status }; // Deliberately NOT the old StartedAt/restart-count proof.
  });

  const nonce = randomBytes(32).toString('hex'); // One nonce per invocation, never reused or resumed.
  const name = `multica-tmpdir-sbx-p1a-${nonce}`;
  const createArgs = [...template.createArgs];
  createArgs[3] = name;
  createArgs[7] = `io.multica.sbx.nonce=${nonce}`;
  const argumentChecks = createArgs.map((arg, index) => ({
    index, matches: arg === (index === 3 ? name : index === 7 ? `io.multica.sbx.nonce=${nonce}` : EXPECTED_ARGS[index]),
    changed: arg !== template.createArgs[index],
  }));
  need(nonce !== OLD_NONCE && argumentChecks.every(x => x.matches && x.changed === [3, 7].includes(x.index)),
    'CREATE_ARG_FIELD_DRIFT');
  const dir = join(ROOT, `tmpdir-sandbox-p1a-${nonce}`);
  mkdirSync(dir, { mode: 0o700 }); // Exclusive directory creation; never use or modify the P1 directory.
  const own = (file, value) => {
    const fd = openSync(join(dir, file), 'wx', 0o600);
    try { writeFileSync(fd, JSON.stringify(value, null, 2) + '\n'); fsyncSync(fd); }
    finally { closeSync(fd); }
  };
  const readOwn = file => JSON.parse(bytes(join(dir, file)).toString('utf8'));
  const intent = {
    version: VERSION, at: new Date().toISOString(), nonce, name, image: IMAGE, connection: CONNECTION,
    podmanExe: EXE, templateIntentSHA256: FROZEN_INTENT_SHA256, templateSourceSHA256: sourceHash,
    runnerSHA256: runnerHash, approvalBinding,
    createArgs, argumentChecks, expectedPre: template.pre, protectedIDs: PROTECTED,
    protectedStateProof: PROTECTED_STATE_PROOF,
    operations: ['ps-only-existing-state', 'create-once', 'projected-own-inspect', 'verified-unforced-rm'],
    // These are argv literals, NOT values read from any host/container environment.
    environmentPolicy: 'no environment reads, no inheritance, no environment output',
    strictNetworkAssertionUnchanged: true,
  };
  own('intent.json', intent); // Durable intent precedes even read-only engine contact.
  need(equal(readOwn('intent.json'), intent), 'INTENT_READBACK_FAILED');

  let id = '';
  let receiptRecord;
  let pre;
  let beforeStates;
  let createAttempted = false;
  let createCalls = 0;
  let removeCalls = 0;
  let cleaned = false;
  let postVerified = false;
  let deleteAuthorized = false;
  let interrupted = false;
  const failures = [];
  const unresolved = [];
  const safeCode = error => /^[A-Z0-9_]+$/.test(error?.message || '') ? error.message : 'INTERNAL_OR_EVIDENCE_IO_FAILURE';
  const recordFailure = (stage, error) => failures.push({ stage, code: safeCode(error) });
  const onSignal = () => { interrupted = true; };
  process.on('SIGINT', onSignal);
  process.on('SIGTERM', onSignal);

  // --format restricts CLI output, NOT proven engine/API retrieval. The client
  // may fetch full inspect internally, so inspect is allowed ONLY for our newly
  // receipted ID. Existing containers use ps ID/state only (even formatted inspect
  // is forbidden). ps formatting also does not prove server-side list redaction.
  // No Config.Env, full inspect output, endpoint objects, IP/MAC,
  // raw mounts/labels, secrets or raw stdout/stderr are recorded or printed.
  const jsonEquals = (expr, expected) => `{{eq (json ${expr}) ${JSON.stringify(JSON.stringify(expected))}}}`;
  const ownershipFields = [
    field('id', '.Id'), field('name', '.Name'), field('image', '.Image'),
    field('nonce', '(index .Config.Labels "io.multica.sbx.nonce")'),
    field('purpose', '(index .Config.Labels "io.multica.sbx.purpose")'),
    field('status', '.State.Status'), field('running', '.State.Running'),
    field('paused', '.State.Paused'), field('restarting', '.State.Restarting'),
    ...[['mountsEmpty', '.Mounts'], ['bindsEmpty', '.HostConfig.Binds'],
      ['volumesFromEmpty', '.HostConfig.VolumesFrom'], ['devicesEmpty', '.HostConfig.Devices']].map(([key, expr]) => raw(key, empty(expr))),
  ];
  // One field per call: an unsupported field cannot discard the other results.
  // Cleanup uses only identity/state/attachment fields, not diagnostic fields.
  const diagnosticFields = [
    ...ownershipFields, field('created', '.Created'),
    field('user', '.Config.User'),
    raw('entrypointMatches', jsonEquals('.Config.Entrypoint', ['/bin/bash'])),
    raw('commandMatches', jsonEquals('.Config.Cmd', EXPECTED_ARGS.slice(EXPECTED_ARGS.indexOf(IMAGE) + 1))),
    field('networkMode', '.HostConfig.NetworkMode'),
    raw('networkBindingsEmpty', empty('.NetworkSettings.Networks')),
    raw('networkNames', '{{$comma := ""}}[{{range $key, $value := .NetworkSettings.Networks}}{{$comma}}{{json $key}}{{$comma = ","}}{{end}}]'),
    raw('hostPortBindingsEmpty', empty('.HostConfig.PortBindings')),
    raw('portMapEmpty', empty('.NetworkSettings.Ports')),
    raw('noBoundPorts', '{{$ok := true}}{{range .NetworkSettings.Ports}}{{if .}}{{$ok = false}}{{end}}{{end}}{{$ok}}'),
    raw('exposedPortsEmpty', empty('.Config.ExposedPorts')),
    ...[['capAddEmpty', '.HostConfig.CapAdd'], ['effectiveCapsEmpty', '.EffectiveCaps'],
      ['boundingCapsEmpty', '.BoundingCaps']].map(([key, expr]) => raw(key, empty(expr))),
    field('readonly', '.HostConfig.ReadonlyRootfs'), field('privileged', '.HostConfig.Privileged'),
    raw('noNewPrivileges', '{{$ok := false}}{{range .HostConfig.SecurityOpt}}{{if or (eq . "no-new-privileges") (eq . "no-new-privileges=true")}}{{$ok = true}}{{end}}{{end}}{{$ok}}'),
    raw('tmpfsCount', '{{len .HostConfig.Tmpfs}}'),
    field('workTmpfs', '(index .HostConfig.Tmpfs "/work")'), field('tmpTmpfs', '(index .HostConfig.Tmpfs "/tmp")'),
    field('memory', '.HostConfig.Memory'), field('memorySwap', '.HostConfig.MemorySwap'),
    field('pids', '.HostConfig.PidsLimit'), field('nanoCpus', '.HostConfig.NanoCpus'),
    field('cpuQuota', '.HostConfig.CpuQuota'), field('cpuPeriod', '.HostConfig.CpuPeriod'),
    field('timeout', '.Config.Timeout'), field('stopTimeout', '.Config.StopTimeout'),
    raw('nofileLimit', '{{$ok := false}}{{range .HostConfig.Ulimits}}{{if and (or (eq .Name "nofile") (eq .Name "RLIMIT_NOFILE") (eq .Name "rlimit_nofile")) (eq .Soft 256) (eq .Hard 256)}}{{$ok = true}}{{end}}{{end}}{{$ok}}'),
    field('restartPolicy', '.HostConfig.RestartPolicy.Name'),
    field('pidMode', '.HostConfig.PidMode'), field('ipcMode', '.HostConfig.IpcMode'), field('utsMode', '.HostConfig.UTSMode'),
  ];
  const ownFormats = [...new Set(diagnosticFields.map(spec => projection([spec])))];
  const connectionArgs = ['system', 'connection', 'list', '--format', '{{.Name}}|{{.URI}}'];
  const infoArgs = ['info', '--format', INFO_FORMAT];
  const inspectArgs = format => ['inspect', '--type', 'container', '--format', format, id];
  const readAllowlist = new Set([connectionArgs, infoArgs, PS_STATE_ARGS, ...Object.values(SET_COMMANDS)].map(JSON.stringify));
  const invoke = async (args, timeout = 15000) => {
    const readAllowed = readAllowlist.has(JSON.stringify(args)) ||
      (fullID(id) && pre && !pre.containers.includes(id) && !PROTECTED.includes(id) &&
        ownFormats.some(format => equal(args, inspectArgs(format))));
    const createAllowed = createAttempted && createCalls === 0 && equal(args, createArgs) && !interrupted;
    const removeAllowed = deleteAuthorized && removeCalls === 0 && fullID(id) && !PROTECTED.includes(id) && pre &&
      !pre.containers.includes(id) && equal(args, ['rm', id]);
    need(readAllowed || createAllowed || removeAllowed, 'COMMAND_NOT_ALLOWLISTED');
    // Recheck durable receipt/intent/pre-state at the command boundary, including
    // immediately before rm; an earlier in-memory proof cannot replace a lost file.
    if ((readAllowed && args[0] === 'inspect') || removeAllowed) persistedOwnership(true);
    if (createAllowed) createCalls++;
    if (removeAllowed) removeCalls++;
    // No shell, inherited environment, stdin payload, raw errors, or retries.
    return new Promise(resolve => {
      const child = execFile(EXE, [`--connection=${CONNECTION}`, ...args], {
        encoding: 'utf8', timeout, killSignal: 'SIGKILL', maxBuffer: 1024 * 1024, windowsHide: true,
        env: { SystemRoot: 'C:\\Windows', USERPROFILE: 'C:\\Users\\GOBAO' },
      }, (error, stdout) => resolve({
        ok: !error, status: error ? (Number.isInteger(error.code) ? error.code : null) : 0,
        killed: Boolean(error?.killed), stdout: stdout || '',
      }));
      child.stdin?.end();
    });
  };
  const query = async args => { const result = await invoke(args); need(result.ok, 'READ_COMMAND_FAILED'); return result.stdout.trim(); };
  const parsed = async args => JSON.parse(await query(args));
  const sets = async () => {
    const result = {};
    for (const [kind, args] of Object.entries(SET_COMMANDS)) {
      const lines = (await query(args)).split(/\r?\n/).filter(Boolean).map(x => ['containers', 'images', 'pods'].includes(kind) ? withSHA(x) : x);
      need(lines.every(x => ['containers', 'images', 'pods'].includes(kind) ? fullID(x) : /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(x)), 'RESOURCE_SET_FORMAT_INVALID');
      result[kind] = [...new Set(lines)].sort();
    }
    return result;
  };
  const states = async () => {
    const rows = (await query(PS_STATE_ARGS)).split(/\r?\n/).filter(Boolean).map(line => JSON.parse(line));
    need(rows.every(x => fullID(x.id) && Object.keys(x).length === 2 &&
      ['configured', 'created', 'initialized', 'running', 'stopped', 'paused', 'exited'].includes(x.state)) &&
      new Set(rows.map(x => x.id)).size === rows.length, 'PS_STATE_SNAPSHOT_INVALID');
    // Point-in-time ID/state equality cannot prove no intervening restart/start,
    // unchanged StartedAt/restart counts, unchanged volumes, or full non-interference.
    return PROTECTED.map(protectedID => {
      const row = rows.find(x => x.id === protectedID);
      need(Boolean(row), 'PROTECTED_PS_STATE_MISSING');
      return { id: row.id, state: row.state };
    });
  };
  const localRootless = async () => {
    const rows = (await query(connectionArgs)).split(/\r?\n/).filter(Boolean).map(line => line.split('|'));
    const matches = rows.filter(row => row[0] === CONNECTION);
    need(matches.length === 1 && matches[0].length === 2, 'CONNECTION_NOT_EXPLICIT');
    const uri = new URL(matches[0][1]);
    need(uri.protocol === 'ssh:' && uri.hostname === '127.0.0.1' && uri.username === 'user' && !uri.password &&
      uri.pathname === '/run/user/1000/podman/podman.sock' && !uri.search && !uri.hash &&
      /^\d+$/.test(uri.port) && Number(uri.port) > 0 && Number(uri.port) <= 65535, 'CONNECTION_NOT_LOCAL_ROOTLESS_SOCKET');
    const host = await parsed(infoArgs);
    need(host.rootless === true && host.seccomp === true && host.graphRoot === '/home/user/.local/share/containers/storage' &&
      ['cpu', 'memory', 'pids'].every(x => host.controllers?.includes(x)), 'ROOTLESS_SECURITY_MISMATCH');
    // Neither connection URI nor host payload is persisted.
    return { explicitLocalSocket: true, rootless: true, seccomp: true, expectedStorage: true, controllers: true };
  };
  const persistedOwnership = (requireReceipt = false) => {
    need(equal(readOwn('intent.json'), intent) && equal(readOwn('preflight.json'), { pre, beforeStates, connectionChecks: {
      explicitLocalSocket: true, rootless: true, seccomp: true, expectedStorage: true, controllers: true,
    } }), 'DURABLE_INTENT_OR_PRESET_MISMATCH');
    if (requireReceipt) {
      need(receiptRecord?.ok === true && receiptRecord.status === 0 && receiptRecord.killed === false &&
        receiptRecord.fullReceiptID === true && fullID(id) && receiptRecord.id === id &&
        equal(readOwn('create-result.json'), receiptRecord), 'DURABLE_FULL_CREATE_RECEIPT_MISSING_OR_MISMATCH');
    }
  };
  const identityChecks = x => ({
    fullReceiptID: fullID(id) && x.id === id,
    nameMatches: typeof x.name === 'string' && x.name.replace(/^\//, '') === name,
    nonceMatches: x.nonce === nonce, purposeMatches: x.purpose === 'tmpdir-path-p1',
    imageMatches: withSHA(x.image) === IMAGE,
    outsidePreset: Boolean(pre && !pre.containers.includes(id) && !PROTECTED.includes(id)),
    createdAndNotRunning: x.status === 'created' && x.running === false && x.paused === false && x.restarting === false,
    // VM creation time is diagnostic only; Windows/VM clocks need not be ordered.
    // This runner has no start command; current state alone is not history proof.
  });
  const inspectOwn = async (fields, stage) => {
    need(fullID(id) && pre && !pre.containers.includes(id) && !PROTECTED.includes(id), 'OWN_INSPECT_ID_NOT_OWNED');
    persistedOwnership(true); // Missing/failed/lost durable receipt: no inspect, no deletion.
    const values = {};
    const errors = [];
    for (const spec of fields) {
      let evidence;
      try {
        const value = await parsed(inspectArgs(projection([spec])));
        need(value && Object.keys(value).length === 1 && Object.hasOwn(value, spec.key), 'OWN_PROJECTION_SHAPE_INVALID');
        values[spec.key] = value[spec.key];
        evidence = { field: spec.key, ok: true, value: value[spec.key] };
      } catch (error) {
        evidence = { field: spec.key, ok: false, code: safeCode(error) };
        errors.push({ field: spec.key, code: evidence.code });
      }
      try { own(`${stage}-${spec.key}.json`, evidence); }
      catch (error) { recordFailure(`${stage}-${spec.key}-evidence`, error); }
    }
    return { values, complete: errors.length === 0, errors };
  };

  try {
    const connectionChecks = await localRootless();
    pre = await sets();
    need(['containers', 'volumes', 'networks', 'images'].every(key => equal(pre[key], template.pre[key])), 'AUDITED_PRESET_DRIFT');
    beforeStates = await states();
    need(equal(beforeStates, historicalStates), 'AUDITED_PROTECTED_PS_STATE_DRIFT');
    own('preflight.json', { pre, beforeStates, connectionChecks });
    persistedOwnership();
    need(!interrupted, 'INTERRUPTED_BEFORE_CREATE');
    await localRootless();
    need(equal(await sets(), pre) && equal(await states(), beforeStates), 'PRE_CREATE_DRIFT');
    // No name/nonce lookup can authorize deletion. A collision simply makes create fail.
    createAttempted = true;
    const receipt = await invoke(createArgs, 45000);
    const candidate = receipt.stdout.trim();
    if (fullID(candidate) && !pre.containers.includes(candidate) && !PROTECTED.includes(candidate)) id = candidate;
    // Retain the candidate before evidence I/O, but NEVER authorize deletion from
    // memory/name/nonce alone. Failed or lost durable full receipts retain resources.
    receiptRecord = { ok: receipt.ok, status: receipt.status, killed: receipt.killed, fullReceiptID: Boolean(id), id: id || null };
    own('create-result.json', receiptRecord);
    need(receipt.ok && id, 'CREATE_FAILED_OR_FULL_ID_MISSING');
    const diagnostic = await inspectOwn(diagnosticFields, 'diagnostic');
    const x = diagnostic.values;
    const identity = identityChecks(x);
    const checks = {
      ...identity, projectedFieldsComplete: diagnostic.complete,
      networkModeNone: x.networkMode === 'none', networkBindingsEmpty: x.networkBindingsEmpty === true,
      networkNamesEmpty: Array.isArray(x.networkNames) && x.networkNames.length === 0,
      networkNamesOnlyNone: Array.isArray(x.networkNames) && x.networkNames.length === 1 && x.networkNames[0] === 'none',
      hostPortBindingsEmpty: x.hostPortBindingsEmpty === true, noBoundPorts: x.noBoundPorts === true,
      portMapEmpty: x.portMapEmpty === true, exposedPortsEmpty: x.exposedPortsEmpty === true,
      userMatches: x.user === '65534:65534', entrypointMatches: x.entrypointMatches === true, commandMatches: x.commandMatches === true,
      ...Object.fromEntries(['mountsEmpty', 'bindsEmpty', 'volumesFromEmpty', 'devicesEmpty', 'capAddEmpty',
        'effectiveCapsEmpty', 'boundingCapsEmpty', 'noNewPrivileges'].map(key => [key, x[key] === true])),
      readonly: x.readonly === true, notPrivileged: x.privileged === false,
      tmpfsExact: x.tmpfsCount === 2 && tmpfsOK(x.workTmpfs, '16m') && tmpfsOK(x.tmpTmpfs, '8m'),
      memoryExact: x.memory === 134217728 && x.memorySwap === 134217728, pidsExact: x.pids === 64,
      cpuExact: x.nanoCpus === 500000000 || (x.cpuQuota === 50000 && x.cpuPeriod === 100000),
      timeoutExact: x.timeout === 60 && x.stopTimeout === 2, nofileExact: x.nofileLimit === true,
      restartDisabled: x.restartPolicy === 'no',
      privateNamespaces: ['', 'private'].includes(x.pidMode) && ['', 'private', 'shareable'].includes(x.ipcMode) && ['', 'private'].includes(x.utsMode),
      unsetenvAllAndAllArgsPinned: argumentChecks.every(check => check.matches),
    };
    own('own-diagnostic.json', { id, checks, projectionErrors: diagnostic.errors,
      networkMode: x.networkMode ?? null, networkNames: x.networkNames ?? null,
      creationClockEvidence: { hostIntentAt: intent.at, vmCreated: x.created ?? null, usedForOwnershipOrDeletion: false } });
    need(Object.values(identity).every(Boolean), 'OWN_IDENTITY_OR_STATE_MISMATCH');
    const afterCreate = await sets();
    const expected = { ...pre, containers: [...pre.containers, id].sort() };
    const setChecks = Object.fromEntries(Object.keys(pre).map(key => [key, equal(afterCreate[key], expected[key])]));
    own('after-create.json', { sets: afterCreate, checks: setChecks });
    need(Object.values(setChecks).every(Boolean), 'AFTER_CREATE_RESOURCE_DRIFT');
    // Preserve the old strict network assertion. A sole "none" map entry is
    // diagnostic evidence, NOT an exception permitting PASS or any execution.
    const informational = new Set(['networkNamesOnlyNone', 'portMapEmpty', 'exposedPortsEmpty']);
    need(Object.entries(checks).every(([key, value]) => informational.has(key) || value), 'STRICT_CONFIGURATION_ASSERTION_BLOCK');
    need(!interrupted, 'INTERRUPTED_AFTER_CREATE');
  } catch (error) {
    recordFailure('diagnostic', error);
  } finally {
    if (id) {
      try {
        persistedOwnership(true);
        await localRootless();
        const ownership = await inspectOwn(ownershipFields, 'cleanup');
        need(ownership.complete, 'CLEANUP_OWN_PROJECTION_INCOMPLETE');
        const x = ownership.values;
        const checks = identityChecks(x);
        need(Object.values(checks).every(Boolean), 'CLEANUP_OWNERSHIP_OR_CREATED_STATE_MISMATCH');
        // Do not remove anything with unexpected mount/device attachments, even without -v.
        need(x.mountsEmpty === true && x.bindsEmpty === true && x.volumesFromEmpty === true && x.devicesEmpty === true,
          'CLEANUP_ATTACHMENT_MISMATCH');
        try { own('cleanup-authorization.json', { id, checks, noAttachments: true, noForce: true, noVolumeRemoval: true }); }
        catch (error) { recordFailure('cleanup-authorization-evidence', error); }
        // Extra evidence I/O failure must not defeat already-proven safe cleanup.
        deleteAuthorized = true;
        const removed = await invoke(['rm', id]); // No -f, no -v, no stop/kill, no alternate target.
        deleteAuthorized = false;
        cleaned = removed.ok;
        try { own('cleanup-result.json', { id, ok: removed.ok, status: removed.status, killed: removed.killed }); }
        catch (error) { recordFailure('cleanup-result-evidence', error); }
        need(removed.ok, 'UNFORCED_REMOVE_FAILED');
      } catch (error) {
        deleteAuthorized = false;
        unresolved.push('RECEIPT_ID_RETAINED_OR_REMOVAL_UNCONFIRMED');
        recordFailure('cleanup', error);
      }
    } else if (createAttempted) {
      unresolved.push('FULL_CREATE_ID_MISSING_NO_LOOKUP_OR_DELETION');
    }
    // Verification is attempted independently of cleanup/evidence failures.
    if (pre) {
      try {
        await localRootless();
        const after = await sets();
        const afterStates = await states();
        const checks = {
          ...Object.fromEntries(Object.keys(pre).map(key => [`${key}Unchanged`, equal(after[key], pre[key])])),
          protectedStatesUnchanged: Boolean(beforeStates && equal(afterStates, beforeStates)),
        };
        postVerified = Object.values(checks).every(Boolean);
        // Record mismatches before failing, not only on the successful path.
        own('after.json', { after, afterStates, checks });
        need(postVerified, 'FINAL_RESOURCE_OR_PROTECTED_STATE_DRIFT');
      } catch (error) { postVerified = false; recordFailure('postcheck', error); }
    }
    if (interrupted) failures.push({ stage: 'signal', code: 'INTERRUPTED' });
    if (unresolved.length > 0) {
      try { own('unresolved.json', { reasons: unresolved, receiptCandidateID: id || null, deletionAttempted: removeCalls > 0 }); }
      catch (error) { recordFailure('unresolved-evidence', error); }
    }
    const pass = failures.length === 0 && unresolved.length === 0 && createAttempted && cleaned && postVerified;
    try {
      own('summary.json', { version: VERSION, id: id || null, createAttempted, cleaned, postVerified,
        protectedStateProof: PROTECTED_STATE_PROOF, approvalBinding,
        unresolved, failures, result: pass ? 'PASS_CREATE_ONLY' : 'BLOCK', containerExecutionAttempted: false });
    } catch (error) { recordFailure('summary-evidence', error); }
    process.removeListener('SIGINT', onSignal);
    process.removeListener('SIGTERM', onSignal);
    console.log(pass && failures.length === 0 ? 'P1a PASS_CREATE_ONLY (not P1 execution)' : 'P1a BLOCK; review exclusive evidence files; no automatic recovery');
    if (!pass || failures.length) process.exitCode = 1;
  }
}

main().catch(() => {
  // Never print exception payloads, CLI output, or environment data.
  console.error('P1a BLOCK: review-only lock or pre-mutation failure; no automatic recovery');
  process.exitCode = 1;
});
