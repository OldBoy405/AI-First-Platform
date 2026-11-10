// One-shot AIFI-45 boundary probe. It never runs project scripts or PostgreSQL.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { closeSync, fsyncSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));
const nonce = '8871bdc64ef539ea999c668f9c26a412';
const name = `multica-tmpdir-sbx-p1-${nonce}`;
const image = 'e8d5705906235eb37953eaba46b51a273440dc3552fe1c8b5f2d743cfcb31350';
const podmanExe = 'C:/Program Files/RedHat/Podman/podman.exe';
const tarExe = 'C:/Program Files/Git/usr/bin/tar.exe';
const connection = 'podman-machine-default';
const protectedIDs = [
  '96211305e92b4ec8a686b5f774cac92e960b86ce14acaa40eb8c1201e993e01f',
  '666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823',
  '01050b2499847e72b06cb5d84b8ec2945dc75045842544a65caf550ef573a762',
];
const files = ['probe.sh', 'names.txt', 'manifest.sha256'];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const own = (name, data) => writeFileSync(join(dir, name), data, { flag: 'wx' });
const run = (cmd, args, options = {}) => spawnSync(cmd, args, { encoding: 'utf8', timeout: 20000, maxBuffer: 4 * 1024 * 1024, windowsHide: true, ...options });
function checked(cmd, args, options) {
  const r = run(cmd, args, options);
  if (r.status !== 0 || r.error) throw new Error(`${cmd} ${args[0]} failed: status=${r.status}, error=${r.error?.message || ''}, stderr=${(r.stderr || '').slice(0, 500)}`);
  return r.stdout;
}
const podRun = (args, options) => run(podmanExe, [`--connection=${connection}`, ...args], options);
const pod = (...args) => {
  const r = podRun(args);
  if (r.status !== 0 || r.error) throw new Error(`podman ${args[0]} failed: status=${r.status}, error=${r.error?.message || ''}, stderr=${(r.stderr || '').slice(0, 500)}`);
  return r.stdout;
};
const parse = (...args) => JSON.parse(pod(...args));
const inspect = id => parse('inspect', '--type', 'container', id)[0];
const info = () => parse('info', '--format', 'json');
const sets = () => ({
  containers: parse('ps', '-a', '--no-trunc', '--format', 'json').map(x => x.Id).sort(),
  volumes: pod('volume', 'ls', '-q').trim().split(/\r?\n/).filter(Boolean).sort(),
  networks: pod('network', 'ls', '-q', '--no-trunc').trim().split(/\r?\n/).filter(Boolean).sort(),
  images: [...new Set(parse('images', '--no-trunc', '--format', 'json').map(x => x.Id))].sort(),
});
const protectedState = id => {
  const fields = pod('inspect', '--type', 'container', '--format', '{{.Id}}|{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}', id).trim().split('|');
  if (fields.length !== 4 || !/^[a-f0-9]{64}$/.test(fields[0]) || !/^\d+$/.test(fields[3])) throw new Error('invalid protected container status');
  return { id: fields[0], status: fields[1], started: fields[2], restartCount: Number(fields[3]) };
};
const absent = value => value == null || (Array.isArray(value) && value.length === 0) || (typeof value === 'object' && Object.keys(value).length === 0);
const tmpfsMatches = (value, size) => {
  if (typeof value !== 'string') return false;
  const opts = value.split(',');
  const required = ['rw', 'exec', 'nosuid', 'nodev', `size=${size}`, 'mode=1777'];
  const allowed = new Set([...required, 'rprivate', 'tmpcopyup', 'notmpcopyup']);
  return required.every(x => opts.includes(x)) && opts.every(x => allowed.has(x));
};
const requireThat = (ok, why) => { if (!ok) throw new Error(why); };
const manifest = readFileSync(join(dir, 'manifest.sha256'));
const manifestHash = hash(manifest);
const entry = 'set -eu; mkdir /work/in; tar -x --no-same-owner --no-same-permissions -C /work/in -f -; cd /work/in; [ "$(sha256sum manifest.sha256 | cut -d\" \" -f1)" = "$SBX_MANIFEST_SHA256" ]; sha256sum -c --strict --quiet manifest.sha256; exec /bin/bash --noprofile --norc probe.sh';
const createArgs = [
  'create', '-i', '--name', name,
  '--label', 'io.multica.sbx.purpose=tmpdir-path-p1', '--label', `io.multica.sbx.nonce=${nonce}`,
  '--pull=never', '--image-volume=ignore', '--read-only', '--read-only-tmpfs=false',
  '--tmpfs', '/work:rw,exec,nosuid,nodev,size=16m,mode=1777', '--tmpfs', '/tmp:rw,exec,nosuid,nodev,size=8m,mode=1777',
  '--network=none', '--http-proxy=false', '--cap-drop=all', '--security-opt=no-new-privileges', '--user', '65534:65534',
  '--pids-limit=64', '--memory=128m', '--memory-swap=128m', '--cpus=0.5', '--ulimit', 'nofile=256:256',
  '--restart=no', '--timeout=60', '--stop-timeout=2', '--unsetenv-all',
  '--env', 'PATH=/usr/bin:/bin', '--env', 'HOME=/work/home', '--env', 'LANG=C', '--env', `SBX_MANIFEST_SHA256=${manifestHash}`,
  '--entrypoint=/bin/bash', image, '--noprofile', '--norc', '-c', entry,
];
let id = '';
let failure = '';
let pre;
let startResult;
let cleaned = false;
let createAttempted = false;
try {
  const lines = manifest.toString('utf8').trim().split('\n');
  requireThat(lines.length === 2, 'unexpected manifest length');
  const manifestNames = [];
  for (const line of lines) {
    const m = line.match(/^([a-f0-9]{64})  (probe\.sh|names\.txt)$/);
    requireThat(m && hash(readFileSync(join(dir, m[2]))) === m[1], 'manifest mismatch');
    manifestNames.push(m[2]);
  }
  requireThat(manifestNames.sort().join() === 'names.txt,probe.sh', 'manifest has duplicate names');
  const sourceNames = readFileSync('C:/Users/GOBAO/Downloads/AI/multica/scripts/agent-cli-command-names.txt');
  requireThat(hash(sourceNames) === hash(readFileSync(join(dir, 'names.txt'))), 'agent names drift');
  const connections = parse('system', 'connection', 'list', '--format', 'json');
  const target = connections.find(x => x.Name === connection);
  const uri = target && new URL(target.URI);
  requireThat(uri?.protocol === 'ssh:' && uri.hostname === '127.0.0.1' && uri.pathname === '/run/user/1000/podman/podman.sock', 'connection is not the expected local socket');
  const host = info();
  requireThat(host.host?.security?.rootless === true && host.host?.security?.seccompEnabled === true && host.store?.graphRoot === '/home/user/.local/share/containers/storage', 'host identity/security mismatch');
  requireThat(['cpu', 'memory', 'pids'].every(x => host.host?.cgroupControllers?.includes(x)), 'required cgroup controllers missing');
  const img = parse('image', 'inspect', image)[0];
  requireThat(img.Id === image && Object.keys(img.Config.Volumes || {}).join() === '/var/lib/postgresql/data', 'image identity/volume mismatch');
  pre = sets();
  requireThat(protectedIDs.every(x => pre.containers.includes(x)), 'protected container missing');
  const protectedBefore = pre.containers.map(protectedState);
  requireThat(podRun(['container', 'exists', name]).status === 1, 'name already exists or engine unavailable');
  requireThat(parse('ps', '-a', '--no-trunc', '--filter', `label=io.multica.sbx.nonce=${nonce}`, '--format', 'json').length === 0, 'nonce already exists');
  const tarPath = join(dir, 'p1.tar');
  closeSync(openSync(tarPath, 'wx'));
  checked(tarExe, ['--force-local', '--format=ustar', '--owner=0', '--group=0', '--numeric-owner', '--mtime=@0', '-cf', 'p1.tar', ...files], { cwd: dir });
  requireThat(checked(tarExe, ['--force-local', '-tf', 'p1.tar'], { cwd: dir }).trim().split(/\r?\n/).join('\n') === files.join('\n'), 'unexpected tar entries');
  const tarBytes = readFileSync(tarPath);
  const intent = { at: new Date().toISOString(), evidenceDirectory: dir, nonce, name, image, connection, podmanExe, tarExe, runnerHash: hash(readFileSync(fileURLToPath(import.meta.url))), probeHash: hash(readFileSync(join(dir, 'probe.sh'))), namesHash: hash(sourceNames), tarHash: hash(tarBytes), manifestHash, podmanVersion: pod('version', '--format', 'json'), tarVersion: checked(tarExe, ['--version']).split(/\r?\n/)[0], createArgs, pre, protectedBefore };
  const fd = openSync(join(dir, 'intent.json'), 'wx');
  try { writeFileSync(fd, JSON.stringify(intent, null, 2) + '\n'); fsyncSync(fd); } finally { closeSync(fd); }
  createAttempted = true;
  const created = podRun(createArgs, { timeout: 60000 });
  const candidate = (created.stdout || '').trim();
  if (/^[a-f0-9]{64}$/.test(candidate)) id = candidate;
  own('create.stdout', created.stdout || '');
  own('create.stderr', created.stderr || '');
  own('create.result.json', JSON.stringify({ status: created.status, error: created.error?.message || null }, null, 2));
  requireThat(created.status === 0 && !created.error && id, 'create failed or full ID receipt missing; retain unknown resources');
  const x = inspect(id);
  const h = x.HostConfig;
  const env = Object.fromEntries((x.Config.Env || []).map(s => { const i = s.indexOf('='); return [s.slice(0, i), s.slice(i + 1)]; }));
  const allowedEnv = new Set(['PATH', 'HOME', 'LANG', 'SBX_MANIFEST_SHA256', 'container', 'HOSTNAME', 'TERM']);
  requireThat(x.Id === id && x.Name.replace(/^\//, '') === name && x.Image === image && x.Config.Labels?.['io.multica.sbx.nonce'] === nonce && new Date(x.Created) >= new Date(intent.at), 'container identity mismatch');
  requireThat(x.State.Status === 'created' && x.Config.User === '65534:65534', 'container state/user mismatch');
  requireThat(x.Config.Entrypoint?.join('\0') === '/bin/bash' && x.Config.Cmd?.join('\0') === ['--noprofile', '--norc', '-c', entry].join('\0'), 'entrypoint mismatch');
  requireThat(Object.keys(env).length === (x.Config.Env || []).length && Object.keys(env).every(k => allowedEnv.has(k)) && env.PATH === '/usr/bin:/bin' && env.HOME === '/work/home' && env.LANG === 'C' && env.SBX_MANIFEST_SHA256 === manifestHash, 'container environment mismatch');
  requireThat(absent(x.Mounts) && absent(h.Binds) && absent(h.VolumesFrom) && absent(h.Devices) && absent(h.CapAdd), 'unexpected mounts/devices/capabilities');
  requireThat(h.NetworkMode === 'none' && absent(h.PortBindings) && absent(x.NetworkSettings?.Networks), 'unexpected network');
  requireThat(h.ReadonlyRootfs === true && h.Privileged === false && absent(x.EffectiveCaps) && absent(x.BoundingCaps) && (h.SecurityOpt || []).some(v => v.includes('no-new-privileges')), 'security settings mismatch');
  requireThat(Object.keys(h.Tmpfs || {}).sort().join() === '/tmp,/work' && tmpfsMatches(h.Tmpfs['/tmp'], '8m') && tmpfsMatches(h.Tmpfs['/work'], '16m') && h.Memory === 134217728 && h.MemorySwap === 134217728 && h.PidsLimit === 64 && (h.NanoCpus === 500000000 || (h.CpuQuota === 50000 && h.CpuPeriod === 100000)), 'limits/tmpfs mismatch');
  requireThat(x.Config.Timeout === 60 && (h.Ulimits || []).some(u => ['nofile', 'rlimit_nofile'].includes(String(u.Name).toLowerCase()) && u.Soft === 256 && u.Hard === 256), 'timeout/ulimit mismatch');
  requireThat(h.RestartPolicy?.Name === 'no' && ![h.PidMode, h.IpcMode, h.UTSMode].includes('host'), 'host namespace/restart mismatch');
  const afterCreate = sets();
  requireThat(JSON.stringify(afterCreate.containers) === JSON.stringify([...pre.containers, id].sort()) && JSON.stringify(afterCreate.volumes) === JSON.stringify(pre.volumes) && JSON.stringify(afterCreate.networks) === JSON.stringify(pre.networks) && JSON.stringify(afterCreate.images) === JSON.stringify(pre.images), 'unexpected container/volume/network/image');
  own('verified-before-start.json', JSON.stringify({ id, name, image, nonce, created: x.Created, manifestHash, tmpfs: h.Tmpfs }, null, 2));
  startResult = podRun(['start', '-a', '-i', id], { input: tarBytes, timeout: 90000 });
  own('p1.stdout', startResult.stdout || '');
  own('p1.stderr', startResult.stderr || '');
  own('p1.result.json', JSON.stringify({ status: startResult.status, error: startResult.error?.message || null }, null, 2));
  const finished = inspect(id);
  own('p1.state.json', JSON.stringify({ exitCode: finished.State.ExitCode, oomKilled: finished.State.OOMKilled, finishedAt: finished.State.FinishedAt, running: finished.State.Running }, null, 2));
  requireThat(startResult.status === 0 && !startResult.error && finished.State.ExitCode === 0 && !finished.State.OOMKilled && !finished.State.Running && !(startResult.stderr || '').includes('P1_FAIL') && (startResult.stdout || '').trim().endsWith('P1_RESULT=PASS'), 'probe failed, timed out or did not produce PASS');
} catch (e) {
  failure = e.message;
} finally {
  if (id) {
    try {
      const x = inspect(id);
      const intent = JSON.parse(readFileSync(join(dir, 'intent.json'), 'utf8'));
      requireThat(x.Id === id && x.Name.replace(/^\//, '') === name && x.Image === image && x.Config.Labels?.['io.multica.sbx.nonce'] === nonce && !pre.containers.includes(id), 'refusing cleanup: ownership mismatch');
      if (!absent(x.Mounts)) own('unresolved-mounts.json', JSON.stringify(x.Mounts.map(m => ({ type: m.Type, name: m.Name, destination: m.Destination })), null, 2));
      if (x.State.Running) pod('stop', '-t', '2', id);
      pod('rm', id);
      requireThat(podRun(['container', 'exists', id]).status === 1, 'removed ID still exists or engine unavailable');
      requireThat(parse('ps', '-a', '--no-trunc', '--filter', `label=io.multica.sbx.nonce=${nonce}`, '--format', 'json').length === 0, 'nonce still present');
      cleaned = true;
    } catch (e) { failure += `; cleanup: ${e.message}`; }
  }
  if (createAttempted && !id) {
    try {
      const matches = parse('ps', '-a', '--no-trunc', '--filter', `label=io.multica.sbx.nonce=${nonce}`, '--format', 'json').map(x => ({ id: x.Id, names: x.Names, image: x.Image }));
      own('unresolved.json', JSON.stringify({ reason: 'full create ID receipt missing; no deletion attempted', matches }, null, 2));
    } catch (e) { failure += `; unresolved lookup: ${e.message}`; }
  }
  try {
    if (pre) {
      const after = sets();
      const before = JSON.parse(readFileSync(join(dir, 'intent.json'), 'utf8')).protectedBefore;
      const afterProtected = before.map(x => protectedState(x.id));
      requireThat(JSON.stringify(before) === JSON.stringify(afterProtected), 'protected container state changed');
      requireThat(JSON.stringify(pre.volumes) === JSON.stringify(after.volumes) && JSON.stringify(pre.networks) === JSON.stringify(after.networks) && JSON.stringify(pre.images) === JSON.stringify(after.images), 'volume/network/image set changed');
      requireThat(JSON.stringify(pre.containers) === JSON.stringify(after.containers), 'container set changed');
      own('after.json', JSON.stringify({ after, afterProtected }, null, 2));
    }
  } catch (e) { failure += `; postcheck: ${e.message}`; }
  own('summary.json', JSON.stringify({ id: id || null, cleaned, unresolved: createAttempted && !id, result: failure ? 'BLOCK' : 'PASS', failure: failure || null }, null, 2));
}
console.log(failure ? `P1 BLOCK: ${failure}` : 'P1 PASS');
if (failure) process.exitCode = 1;
