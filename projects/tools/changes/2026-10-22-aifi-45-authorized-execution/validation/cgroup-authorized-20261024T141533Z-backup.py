# Prepare private recovery copies only; do not modify live VM configuration.
import hashlib
import json
import os
import pathlib
import stat
import uuid

assert os.geteuid() == 0, 'backup helper requires VM root, not rootful Podman'
base = pathlib.Path('/var/lib/aifi45-config-backups')
try:
    base.mkdir(mode=0o700)
except FileExistsError:
    pass
meta = base.lstat()
assert stat.S_ISDIR(meta.st_mode) and meta.st_uid == 0 and not (meta.st_mode & 0o077), 'unsafe backup parent'
directory = base / ('cgroup-20261024-' + uuid.uuid4().hex)
directory.mkdir(mode=0o700)
manifest = {'backup_directory': str(directory), 'files': [], 'live_config_modified': False, 'rootful_engine_used': False}
for number, path in enumerate(('/etc/wsl.conf', '/etc/containers/containers.conf',
                               '/etc/systemd/system/user@.service.d/delegate.conf')):
    source = pathlib.Path(path)
    info = source.lstat()
    assert stat.S_ISREG(info.st_mode), 'nonregular source config'
    raw = source.read_bytes()
    if path == '/etc/wsl.conf':
        assert hashlib.sha256(raw).hexdigest() == '8a037d60c1eabd07cd092bca5f0e1a6ec2e9649a0eb8574e750cc7053bc9da47', 'WSL config changed since inspection'
    target = directory / (str(number) + '.original')
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    manifest['files'].append({'source': path, 'backup': str(target), 'sha256': hashlib.sha256(raw).hexdigest(),
                              'original_mode': oct(stat.S_IMODE(info.st_mode)), 'uid': info.st_uid, 'gid': info.st_gid})
descriptor = os.open(directory / 'manifest.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
with os.fdopen(descriptor, 'w') as stream:
    json.dump(manifest, stream, indent=2)
    stream.flush()
    os.fsync(stream.fileno())
print(json.dumps(manifest))
