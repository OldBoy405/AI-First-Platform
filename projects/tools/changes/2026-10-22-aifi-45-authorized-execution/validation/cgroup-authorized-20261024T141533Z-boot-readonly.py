# Inspect only cgroup process identity and boot entry-point metadata.
import configparser
import hashlib
import json
import pathlib
import shlex

root = pathlib.Path('/sys/fs/cgroup/non-systemd')
rows = (root / 'cgroup.procs').read_text().splitlines()
output = {'direct_processes': [], 'cgroup_ns': {}, 'direct_process_row_count': len(rows),
          'namespace_invisible_zero_rows': sum(line == '0' for line in rows)}
for line in rows:
    directory = pathlib.Path('/proc') / line
    try:
        output['direct_processes'].append({'pid': int(line), 'comm': (directory / 'comm').read_text().strip(),
                                           'cgroup': (directory / 'cgroup').read_text().strip()})
    except FileNotFoundError:
        pass
for pid in ('1', 'self'):
    try:
        output['cgroup_ns'][pid] = str((pathlib.Path('/proc') / pid / 'ns/cgroup').readlink())
    except PermissionError:
        output['cgroup_ns'][pid] = 'unknown: permission denied'
output['pid1_cgroup'] = pathlib.Path('/proc/1/cgroup').read_text().strip()
config = pathlib.Path('/etc/wsl.conf')
raw = config.read_bytes()
parser = configparser.ConfigParser(interpolation=None, strict=False)
parser.read_string(raw.decode())
output['wsl_config_sha256'] = hashlib.sha256(raw).hexdigest()
output['wsl_boot_systemd'] = parser.get('boot', 'systemd', fallback='absent')
command = parser.get('boot', 'command', fallback='')
parts = shlex.split(command)
output['boot_command'] = {'present': bool(parts), 'executable_only': parts[0] if parts else None, 'arg_count': max(len(parts)-1, 0)}
print(json.dumps(output))
