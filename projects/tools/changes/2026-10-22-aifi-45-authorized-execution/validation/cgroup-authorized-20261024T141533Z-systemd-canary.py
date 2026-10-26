# Parameter-only systemd-manager test; never writes manager/VM configuration.
import json
import subprocess
import uuid

nonce = uuid.uuid4().hex
name = 'aifi45-systemd-cgroup-' + nonce
image = 'docker.io/library/alpine@sha256:bbfcd601d7cd20d35bb0b8b866ad1a8a0d107ca3e1c20870c75c5ce2c1186d30'
expected_image = 'f439434f9e6739ae2f80313f260d2084bb89feaf7220a06a5398e6b90797e2e3'
result = {'name': name, 'nonce': nonce, 'rootless_required': True, 'steps': [], 'no_persistent_config_change': True}
owned = False

def run(args, timeout=15):
    command = ['podman', '--cgroup-manager=systemd'] + args
    proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    return command, proc

try:
    _, proc = run(['image', 'inspect', image])
    assert proc.returncode == 0, 'locked local image unavailable'
    assert json.loads(proc.stdout)[0]['Id'].removeprefix('sha256:') == expected_image, 'image ID mismatch'
    command, proc = run(['create', '--name', name, '--label', 'aifi45.cgroup.canary=' + nonce,
                         '--pull=never', '--http-proxy=false', '--network=none', '--read-only',
                         '--cap-drop=ALL', '--security-opt=no-new-privileges', '--user=1000:1000',
                         '--pids-limit=16', '--memory=64m', '--cpus=0.25', '--entrypoint=/bin/sh', image,
                         '-c', 'for f in cpu.max memory.max pids.max; do printf "%s=" "$f"; while IFS= read -r line; do printf "%s\\n" "$line"; done < "/sys/fs/cgroup/$f"; done'])
    result['steps'].append({'argv': command, 'exit': proc.returncode, 'stdout': proc.stdout, 'stderr': proc.stderr})
    created = proc.returncode == 0
    _, inspected = run(['inspect', name])
    if inspected.returncode == 0:
        meta = json.loads(inspected.stdout)[0]
        assert meta['Config']['Labels'].get('aifi45.cgroup.canary') == nonce, 'ownership mismatch'
        owned = True
        result['requested_host_config'] = {key: meta['HostConfig'].get(key) for key in ('Memory', 'NanoCpus', 'PidsLimit')}
    if created:
        assert owned, 'created object ownership unproven'
        command, proc = run(['start', '--attach', name], 20)
        result['steps'].append({'argv': command, 'exit': proc.returncode, 'stdout': proc.stdout, 'stderr': proc.stderr})
except Exception as error:
    result['error'] = str(error)
finally:
    if owned:
        try:
            command, proc = run(['rm', '-f', name])
            result['cleanup'] = {'argv': command, 'exit': proc.returncode, 'stderr': proc.stderr}
            _, exists = run(['container', 'exists', name])
            result['cleanup']['exists_exit'] = exists.returncode
        except Exception as error:
            result['cleanup_error'] = str(error)
    else:
        result['cleanup'] = {'no_owned_object': True}
print(json.dumps(result))
