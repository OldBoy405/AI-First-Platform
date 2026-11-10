// AIFIRST: ownership checks for the AIFI-45 isolated CI verification instance.
const check = condition => { if (!condition) throw new Error('instance ownership or isolation mismatch'); };
const hex = (value, length) => typeof value === 'string' && value.length === length && /^[0-9a-f]+$/.test(value);
const envKeys = new Set(['PATH', 'GOSU_VERSION', 'LANG', 'PG_MAJOR', 'PG_VERSION', 'PGDATA',
  'POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD', 'container', 'HOME', 'HOSTNAME']);

function timestamp(value) {
  if (typeof value !== 'string' || /[\r\n]/.test(value)) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(?:Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  if (year < 100 || hour > 23 || minute > 59 || second > 59) return null;
  const calendar = new Date(Date.UTC(year, month - 1, day));
  if (calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 || calendar.getUTCDate() !== day) return null;
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) return null;
  return BigInt(millis) * 1000000n + BigInt((match[7] || '').padEnd(9, '0').slice(3));
}

export function assertInstanceIntent(target) {
  check(hex(target?.image, 64) && hex(target?.nonce, 16) && target.name === `aifi45-ci-${target.nonce}`);
  const lower = timestamp(target.createdAfter);
  const upper = timestamp(target.createdBefore);
  check(lower !== null && upper !== null && lower <= upper && upper - lower <= 120000000000n);
  const env = target.expectedEnv;
  check(env && typeof env === 'object' && !Array.isArray(env) &&
    Object.prototype.propertyIsEnumerable.call(env, 'PGDATA') && env.PGDATA === '/var/lib/postgresql/data/pgdata' &&
    ['POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD'].every(key => Object.prototype.propertyIsEnumerable.call(env, key) && typeof env[key] === 'string' && env[key].length > 0) &&
    Object.entries(env).every(([key, value]) => envKeys.has(key) && typeof value === 'string'));
  return { lower, upper };
}

export function assertInstanceOwnership(target, inspected, mode) {
  const { lower, upper } = assertInstanceIntent(target);
  const h = inspected?.HostConfig;
  const c = inspected?.Config;
  check(hex(target?.id, 64));
  check(inspected?.Id === target.id && inspected?.Name === target.name && inspected?.Image === target.image &&
    c?.Labels?.['aifi45.ci.nonce'] === target.nonce);
  const created = timestamp(inspected?.Created);
  check(created !== null && created >= lower && created <= upper);
  check(h?.Privileged === false && h?.AutoRemove === false && h?.NetworkMode === 'bridge' &&
    h?.PidMode === 'private' && h?.IpcMode === 'private' && h?.UTSMode === 'private' &&
    h?.UsernsMode === '' && h?.PublishAllPorts === false && h?.RestartPolicy?.Name === 'no');
  const empty = value => value === null || (Array.isArray(value) && value.length === 0);
  check(empty(h?.Binds) && empty(h?.VolumesFrom) && empty(h?.Devices) &&
    empty(h?.CapAdd) && empty(h?.SecurityOpt) &&
    (h?.DeviceRequests === undefined || empty(h.DeviceRequests)) &&
    (h?.DeviceCgroupRules === undefined || empty(h.DeviceCgroupRules)) &&
    Array.isArray(inspected?.Mounts) && inspected.Mounts.length === 0);
  check(Array.isArray(c?.Entrypoint) && c.Entrypoint.length === 1 && c.Entrypoint[0] === 'docker-entrypoint.sh' &&
    Array.isArray(c?.Cmd) && c.Cmd.length === 1 && c.Cmd[0] === 'postgres');
  check(h?.Tmpfs && Object.keys(h.Tmpfs).length === 1 &&
    h.Tmpfs['/var/lib/postgresql/data'] === 'rw,size=1073741824');
  check(Array.isArray(c?.Env) && c.Env.every(value => typeof value === 'string'));
  const expectedEnv = target.expectedEnv;
  const actualEnv = new Map();
  for (const value of c.Env) {
    const separator = value.indexOf('=');
    check(separator > 0);
    const key = value.slice(0, separator);
    check(!actualEnv.has(key) && Object.hasOwn(expectedEnv, key) && typeof expectedEnv[key] === 'string' && expectedEnv[key] === value.slice(separator + 1));
    actualEnv.set(key, true);
  }
  check(actualEnv.size === Object.keys(expectedEnv).length);
  const requested = h?.PortBindings;
  check(requested && Object.keys(requested).length === 1 && Array.isArray(requested['5432/tcp']) &&
    requested['5432/tcp'].length === 1 && requested['5432/tcp'][0]?.HostIp === '127.0.0.1');
  const validPort = port => typeof port === 'string' && /^[0-9]{1,5}$/.test(port) &&
    Number(port) >= 1 && Number(port) <= 65535;
  const requestedPort = requested['5432/tcp'][0].HostPort;
  check(requestedPort === '' || requestedPort === '0' || (mode !== 'created' && validPort(requestedPort)));
  const state = inspected?.State;
  check(['created', 'running', 'stopped'].includes(mode) && state?.Paused === false &&
    state?.Restarting === false && state?.Dead === false);
  check(mode === 'running' ? state?.Running === true && state?.Status === 'running' :
    state?.Running === false && (mode === 'created' ? state?.Status === 'created' :
      ['stopped', 'exited'].includes(state?.Status)));
  check(inspected?.NetworkSettings && Object.hasOwn(inspected.NetworkSettings, 'Ports'));
  const ports = inspected.NetworkSettings.Ports;
  if (mode === 'running') {
    check(ports && Object.keys(ports).length === 1 &&
      Array.isArray(ports['5432/tcp']) && ports['5432/tcp'].length === 1);
  } else if (ports != null) {
    check(typeof ports === 'object' && !Array.isArray(ports) &&
      Object.keys(ports).every(key => key === '5432/tcp'));
  }
  const bindings = ports?.['5432/tcp'];
  if (bindings != null) {
    check(Array.isArray(bindings) && (mode === 'running' ? bindings.length === 1 : bindings.length <= 1));
    if (bindings.length) {
      const port = bindings[0];
      check(port?.HostIp === '127.0.0.1' && validPort(port.HostPort));
      check(requestedPort === '' || requestedPort === '0' || requestedPort === port.HostPort);
    }
  }
}
