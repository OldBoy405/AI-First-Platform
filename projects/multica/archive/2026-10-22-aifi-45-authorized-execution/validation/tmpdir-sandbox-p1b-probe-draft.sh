#!/bin/bash
# P1b LOCKED DRAFT ONLY. This unconditional exit prevents accidental execution.
# A hostile shell startup environment is outside the scope of this guard.
exit 125
# First executable statements below are a secondary static lock, not authorization.
readonly P1B_STATIC_UNLOCK=false
if [[ "$P1B_STATIC_UNLOCK" != true ]]; then
    builtin printf '%s\n' 'P1B_BLOCKED: unapproved locked draft; do not execute' >&2
    exit 125
fi

# Everything below is unreachable in this draft. DO NOT unlock this artifact.
# Any future executable proposal needs a new, independently reviewed artifact,
# exact image/profile/payload/probe pins, a new resource identity and authorization.
# No sourcing, BASH_ENV, shell startup files, inherited descriptors, or host execution.
# A launcher must establish a sterile environment BEFORE starting this interpreter;
# a script cannot retroactively prevent Bash startup hooks or malicious bootstrap code.
# P1 did NOT run its in-container probe; its earlier PASS is withdrawn. P1a remains
# unpassed and is neither a prerequisite success nor evidence for this proposal.
#
# Allowed NOW: writing this draft and `bash -n <this-file>` only. bash -n does not
# execute either the shell body or the Python heredoc, and does NOT validate Python.
# No auto-tests, containers, network/DB access, Go/CLI, old scripts, or secret reads.
# The future code below observes ONLY its own newly authorized container, never
# pre-existing containers, host sessions, credentials, or application data.
# It creates no socket and runs no application, Go, engine CLI, or shell payload
# other than the fixed, public, two-line exit-0 scratch execution canary.
#
# Evidence policy: emit only fixed reason codes, approved paths, public artifact
# hashes, numeric identity/limits/counts and approved mount flags. Never dump env,
# mountinfo, /proc/*/cmdline, process environments, addresses, routes, Unix names,
# source paths, overlay lowerdir/upperdir, stderr from tools, or secret contents.
# Unknown files/mounts/types/escapes/options, unreadable trees, permission-only
# write failures and unavailable proc tables all fail closed, without raw values.

set -euo pipefail
readonly P1B_PROFILE_APPROVED=false
if [[ "$P1B_PROFILE_APPROVED" != true ]]; then
    builtin printf '%s\n' 'P1B_BLOCKED: no approved immutable profile' >&2
    exit 125
fi
[[ $$ == 1 && $BASHPID == 1 ]] || {
    builtin printf '%s\n' 'P1B_FAIL: shell_not_pid1' >&2; exit 1;
}
# Future clean sandbox only: enumerate EXPORTED NAMES, never export/env values.
# Reject unknown names without echoing them; no /proc/*/environ or `env` dump.
while IFS= read -r name; do
    case "$name" in PATH|HOME|LANG|PWD|SHLVL|_) ;;
        *) builtin printf '%s\n' 'P1B_FAIL: unexpected_export_name' >&2; exit 1 ;;
    esac
done < <(compgen -e)
[[ ${PATH-} == /usr/bin:/bin && ${HOME-} == /work && ${LANG-} == C.UTF-8 &&
   ${PWD-} == / && ${SHLVL-} == 1 ]] || {
    builtin printf '%s\n' 'P1B_FAIL: approved_environment_mismatch' >&2; exit 1;
}
# No PATH lookup, Python startup hooks, site packages, bytecode-cache writes
# (-B below), or subprocess helpers.
# The immutable bootstrap image/interpreter/stdlib must be independently pinned;
# this in-container code cannot attest the interpreter that executes itself.
# Read public source into an unexported shell variable, then use -c, not Python
# stdin: a large Bash heredoc may otherwise leave fd0 as a deleted temporary file.
# The original stdin must already be /dev/null or a public pipe (launcher policy).
p1b_python=''
IFS= read -r -d '' p1b_python <<'P1B_PYTHON' || [[ -n $p1b_python ]]
import errno
import hashlib
import ipaddress
import os
import re
import stat

# UNAPPROVED STATIC INPUTS. Empty is deliberate: never learn trust from a running
# container, auto-populate from mountinfo/find, or accept an env/argv profile.
PROFILE_APPROVED = False
IMAGE_DIGEST = 'UNAPPROVED'
SECCOMP_PROFILE_SHA256 = 'UNAPPROVED'
AGENT_NAMES = ()
MOUNTS = {}
PUBLIC_TREE = {}
# MOUNTS: decoded absolute target -> exact dict with keys:
#   role, fs, source, root, options, super_options, optional
# The last three are sorted tuples of exact mountinfo tokens, not regexes.
# Device/mount/parent IDs are validated relationally; they are not portable pins.
# source/root/super_options are compared privately and are NEVER printed.
# Common file binds /etc/{hosts,hostname,resolv.conf} and /probe.sh require exact
# independently approved fs/source/root/options, NOT source basename matching.
# A runtime-generated container ID or bind source is NOT known here. Capturing
# it and approving a per-run immutable profile requires separate authorization.
# Typical Docker/Podman defaults may NOT fit this deliberately smaller profile.
#
# PUBLIC_TREE: every reachable non-pseudo path -> exact public metadata dict:
#   kind ('dir','file','link','char'), mode (permission bits), uid, gid, nlink;
#   file additionally: size, sha256; link: target; char: rdev (major,minor).
# Include '/', mountpoints, empty /work and /tmp, /dev's exact devices/symlinks,
# root canary dir, /payload and /payload/names.txt. Do NOT include /probe.sh's
# digest here (self-hash cycle): its digest is checked by an independent verifier
# against the approved script artifact, not against a value derived from itself.
# Pseudo interiors are excluded only by the explicit roles below; not by -xdev.
# All file-content entries MUST be independently classified public before use.
# No metadata-only/opaque/unreadable regular files or directories are accepted.
# This requires a minimal purpose-built image; do not hash existing secret files.
# An image digest/string printed by this program is NOT image identity attestation.

ALLOWED_ROLES = {
    '/': 'root', '/work': 'scratch', '/tmp': 'scratch',
    '/payload': 'payload', '/probe.sh': 'probe',
    '/proc': 'proc', '/sys': 'sys', '/sys/fs/cgroup': 'cgroup',
    '/dev': 'dev',
    '/etc/hosts': 'config', '/etc/hostname': 'config',
    '/etc/resolv.conf': 'config',
    '/proc/bus': 'proc_ro', '/proc/fs': 'proc_ro',
    '/proc/irq': 'proc_ro', '/proc/sys': 'proc_ro',
    '/proc/sysrq-trigger': 'proc_ro',
    '/proc/acpi': 'mask_empty', '/proc/scsi': 'mask_empty',
    '/proc/interrupts': 'mask_null', '/proc/kcore': 'mask_null',
    '/proc/keys': 'mask_null', '/proc/latency_stats': 'mask_null',
    '/proc/timer_list': 'mask_null', '/proc/sched_debug': 'mask_null',
}
REQUIRED_MOUNTS = {'/', '/work', '/tmp', '/payload', '/probe.sh',
                   '/proc', '/sys', '/sys/fs/cgroup', '/dev'}
# No blanket /dev/*, /proc/*, /run/* or /etc/* allowance. No shared memory,
# devpts/TTY, mqueue, host mounts, volumes or extra scratch mount by default.
# If a runtime needs one, do NOT widen this rule without a new reviewed proposal.
READ_ONLY_ROLES = {'root', 'payload', 'probe', 'proc', 'sys', 'cgroup',
                   'config', 'proc_ro', 'mask_empty', 'mask_null'}
PSEUDO_ROLES = {'proc', 'sys', 'cgroup', 'proc_ro', 'mask_empty', 'mask_null'}
BIND_FILESYSTEMS = {'ext4', 'xfs', 'btrfs', 'overlay', 'tmpfs'}
ZERO_CAP = '0000000000000000'
LIMITS = {'memory.max': '134217728', 'memory.swap.max': '0',
          'pids.max': '64', 'cpu.max': '50000 100000'}
EXEC_BYTES = b'#!/bin/sh\nexit 0\n'
RO_CANARY_DIR = '/p1b-ro-canary'  # public, empty, root-image directory, mode 0777
PROBE_PATH = '/probe.sh'
MAX_ENTRIES = 16384
seen = set()
mounts = {}


def fail(code):
    # code must be a source literal; no exception messages/untrusted strings.
    print('P1B_FAIL=' + code, flush=True)
    raise SystemExit(1)


def require(ok, code):
    if not ok:
        fail(code)


def emit(key, value):
    # Call only with explicitly non-secret, already validated data.
    print('P1B_' + key + '=' + str(value), flush=True)


def digest_ok(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def read_public(path, limit=1048576):
    # Call sites must name public proc/cgroup tables or a pinned public file.
    # Never use this helper for unknown paths, application state or credentials.
    with open(path, 'rb') as handle:
        data = handle.read(limit + 1)
    require(len(data) <= limit, 'public_input_too_large')
    return data


def text_public(path, limit=1048576):
    return read_public(path, limit).decode('ascii', 'strict')


def status(path):
    result = {}
    for line in text_public(path, 65536).splitlines():
        key, sep, value = line.partition(':')
        require(bool(sep) and key not in result, 'status_format')
        result[key] = value.strip()
    return result


def identity():
    require(os.getpid() == 1 and os.getppid() == 0, 'pid1')
    require(os.getresuid() == (65534, 65534, 65534), 'uid')
    require(os.getresgid() == (65534, 65534, 65534), 'gid')
    require(os.getgroups() in ([], [65534]), 'supplementary_groups')
    require(os.getcwd() == '/', 'cwd')
    # This is a future sterile container check, not permission to read existing env.
    require(set(os.environ) <= {'PATH', 'HOME', 'LANG', 'PWD', 'SHLVL', '_'},
            'environment_names')
    require(os.environ.get('PATH') == '/usr/bin:/bin' and
            os.environ.get('HOME') == '/work' and
            os.environ.get('LANG') == 'C.UTF-8' and
            os.environ.get('PWD') == '/' and os.environ.get('SHLVL') == '1',
            'environment_values')
    info = status('/proc/self/status')
    for key in ('CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb'):
        require(info.get(key) == ZERO_CAP, 'capabilities')
    require(info.get('NoNewPrivs') == '1', 'no_new_privileges')
    require(info.get('Seccomp') == '2', 'seccomp_mode')
    require(re.fullmatch(r'[1-9][0-9]*', info.get('Seccomp_filters', '')) is not None,
            'seccomp_filters')
    require(info.get('Uid', '').split() == ['65534'] * 4 and
            info.get('Gid', '').split() == ['65534'] * 4, 'saved_fs_identity')
    require(info.get('NSpid', '').split()[-1:] == ['1'], 'namespace_pid')
    # PID namespace snapshot: no daemon, postgres or other hidden command names.
    require({n for n in os.listdir('/proc') if n.isdecimal()} == {'1'},
            'additional_process')
    require(os.listdir('/proc/self/task') == ['1'], 'additional_thread')
    # No inherited socket, executable, directory or credential FD. Ignore ONLY
    # the already-closed transient FD used by listdir itself.
    for fd in os.listdir('/proc/self/fd'):
        try:
            target = os.readlink('/proc/self/fd/' + fd)
        except FileNotFoundError:
            require(fd not in ('0', '1', '2'), 'missing_standard_fd')
            continue
        require(fd in ('0', '1', '2'), 'inherited_extra_fd')
        require(target == '/dev/null' or re.fullmatch(r'pipe:\[[0-9]+\]', target)
                is not None, 'inherited_fd_kind')
    emit('IDENTITY', 'uid:65534,gid:65534,pid:1,caps:0,nnp:1,seccomp:2')
    emit('ENVIRONMENT', 'PATH:/usr/bin:/bin,HOME:/work,LANG:C.UTF-8,cwd:/')
    emit('SECCOMP_PROFILE_PIN', SECCOMP_PROFILE_SHA256)
    # Mode=2/filter count do NOT attest filter contents or syscall enforcement.


def unescape_mount(value):
    # Kernel mountinfo encodes SP/TAB/LF/backslash as \040/\011/\012/\134.
    # Decode ONCE; never split decoded whitespace or recursively decode \134040.
    out = []
    i = 0
    escapes = {'040': ' ', '011': '\t', '012': '\n', '134': '\\'}
    while i < len(value):
        if value[i] != '\\':
            out.append(value[i])
            i += 1
        else:
            token = value[i + 1:i + 4]
            require(token in escapes, 'mount_escape')
            out.append(escapes[token])
            i += 4
    return ''.join(out)


def absolute_path(value):
    # Canonical decoded paths only. Whitelisted roots may contain spaces but
    # never control chars, backslashes, relative/empty/dot/dotdot components.
    return (value.startswith('/') and not any(ord(c) < 32 or ord(c) == 127
            or c == '\\' for c in value) and
            (value == '/' or (not value.endswith('/') and
             all(p not in ('', '.', '..') for p in value[1:].split('/')))))


def option_tuple(raw):
    values = raw.split(',')
    require(all(values) and len(values) == len(set(values)), 'mount_option_format')
    return tuple(sorted(values))


def parse_mounts():
    result = {}
    ids = set()
    raw = read_public('/proc/self/mountinfo', 2097152)
    for line in raw.decode('ascii', 'strict').splitlines():
        fields = line.split(' ')
        require(all(fields) and fields.count('-') == 1, 'mount_record_format')
        sep = fields.index('-')
        require(sep >= 6 and len(fields) == sep + 4, 'mount_field_count')
        require(fields[0].isdecimal() and fields[1].isdecimal() and
                re.fullmatch(r'[0-9]+:[0-9]+', fields[2]) is not None,
                'mount_id_format')
        mid, parent = int(fields[0]), int(fields[1])
        root, target = unescape_mount(fields[3]), unescape_mount(fields[4])
        require(absolute_path(root) and absolute_path(target), 'mount_path_format')
        require(mid > 0 and parent > 0 and mid != parent and mid not in ids and
                target not in result, 'duplicate_or_stacked_mount')
        optional = tuple(sorted(fields[6:sep]))
        # No shared/master/propagate_from/unbindable/idmapped/unknown fields.
        require(not optional, 'mount_propagation_or_unknown_field')
        ids.add(mid)
        result[target] = {
            'id': mid, 'parent': parent, 'dev': fields[2], 'root': root,
            'options': option_tuple(fields[5]), 'optional': optional,
            'fs': fields[sep + 1], 'source': unescape_mount(fields[sep + 2]),
            'super_options': option_tuple(fields[sep + 3]),
        }
    return result, raw


def owner_mount(path):
    choices = [p for p in mounts if p == '/' or path == p or path.startswith(p + '/')]
    require(bool(choices), 'mount_owner_missing')
    return max(choices, key=len)


def validate_mounts():
    global mounts
    mounts, raw = parse_mounts()
    require(set(mounts) == set(MOUNTS) and REQUIRED_MOUNTS <= set(mounts),
            'mount_inventory')
    for target, row in mounts.items():
        require(target in ALLOWED_ROLES, 'mount_target_not_allowed')
        role = ALLOWED_ROLES[target]
        expected = MOUNTS[target]
        require(set(expected) == {'role', 'fs', 'source', 'root', 'options',
                                 'super_options', 'optional'}, 'mount_profile_schema')
        require(expected['role'] == role and all(row[k] == expected[k] for k in
                ('fs', 'source', 'root', 'options', 'super_options', 'optional')),
                'mount_profile_mismatch')
        options = set(row['options'])
        super_flags = set(row['super_options'])
        target_info = os.lstat(target)
        require(not stat.S_ISLNK(target_info.st_mode) and
                (os.major(target_info.st_dev), os.minor(target_info.st_dev)) ==
                tuple(int(n) for n in row['dev'].split(':')), 'mount_target_device')
        require(('ro' in options) != ('rw' in options), 'mount_rw_flag')
        require(('ro' in super_flags) != ('rw' in super_flags), 'super_rw_flag')
        if role in READ_ONLY_ROLES:
            require('ro' in options and
                    os.statvfs(target).f_flag & os.ST_RDONLY, 'readonly_mount_flag')
        else:
            require(role in ('scratch', 'dev') and 'rw' in options and
                    'rw' in super_flags and not
                    (os.statvfs(target).f_flag & os.ST_RDONLY), 'writable_mount_role')
        if role == 'root':
            require(row['fs'] == 'overlay' and row['source'] == 'overlay' and
                    row['root'] == '/', 'root_overlay_source')
            # A readonly VFS overlay can have rw super options. Do not mistake
            # that for a writable root or expose the host overlay paths.
        elif role in ('scratch', 'dev', 'mask_empty'):
            flags = {'nosuid', 'noexec'} if role == 'dev' else {'nosuid', 'nodev'}
            require(row['fs'] == 'tmpfs' and row['source'] == 'tmpfs' and
                    row['root'] == '/' and flags <= options, 'tmpfs_source_or_flags')
            if role == 'scratch':
                require('noexec' not in options, 'scratch_not_executable')
                size = os.statvfs(target)
                require(0 < size.f_blocks * size.f_frsize <= 16777216,
                        'scratch_size')
            elif role == 'mask_empty':
                require(not os.listdir(target), 'nonempty_mask')
        elif role in ('proc', 'proc_ro'):
            require(row['fs'] == 'proc' and row['source'] == 'proc' and
                    {'nosuid', 'nodev', 'noexec'} <= options, 'proc_mount_source')
            require(row['root'] == ('/' if role == 'proc' else target[5:]) and
                    row['dev'] == mounts['/proc']['dev'], 'proc_bind_origin')
        elif role in ('sys', 'cgroup'):
            fstype = 'sysfs' if role == 'sys' else 'cgroup2'
            require(row['fs'] == fstype and row['root'] == '/' and
                    {'nosuid', 'nodev', 'noexec'} <= options, 'sys_cgroup_source')
        elif role == 'mask_null':
            info = os.lstat(target)
            require(row['fs'] == 'tmpfs' and row['source'] == 'tmpfs' and
                    row['root'] == '/null' and row['dev'] == mounts['/dev']['dev']
                    and stat.S_ISCHR(info.st_mode) and
                    (os.major(info.st_rdev), os.minor(info.st_rdev)) == (1, 3),
                    'null_mask_origin')
        else:
            require(role in ('payload', 'probe', 'config') and
                    row['fs'] in BIND_FILESYSTEMS, 'bind_filesystem')
        # Visible parent must be the longest enclosing mount; no hidden parent,
        # overmount, out-of-tree parent or shadowed nested mount is accepted.
        if target != '/':
            ancestors = [p for p in mounts if p != target and
                         (p == '/' or target.startswith(p + '/'))]
            parent_path = max(ancestors, key=len)
            require(row['parent'] == mounts[parent_path]['id'], 'mount_parent')
        else:
            require(row['parent'] not in {r['id'] for r in mounts.values()},
                    'root_parent_visible')
    # Three separately allocated tmpfs instances, not aliases/subdirectory binds.
    require(len({mounts[p]['dev'] for p in ('/', '/work', '/tmp', '/dev')}) == 4,
            'scratch_device_alias')
    for target in sorted(mounts):
        row = mounts[target]
        emit('MOUNT', '{}|{}|{}|{}|{}'.format(target, ALLOWED_ROLES[target],
             row['fs'], 'ro' if 'ro' in row['options'] else 'rw',
             ','.join(k for k in ('nosuid', 'nodev', 'noexec') if k in row['options'])))
    # Do not print/hash the raw mountinfo: overlay paths/bind source metadata
    # are not public evidence. Keep the snapshot only for in-memory comparison.
    return raw


def forbidden_path(path):
    # Metadata comparison only, before opening ANY file. Not an exhaustive
    # credential detector; the public-only manifest is the primary boundary.
    parts = path.split('/')
    return (path in ('/etc/shadow', '/etc/gshadow', '/init', '/mnt/c', '/usr/local/go')
            or any(p in ('secrets', '.ssh', '.aws', '.azure', '.kube', '.docker',
                         '.pgpass', 'pgpass', 'pg_service.conf', 'PG_VERSION')
                   for p in parts))


def inspect_public(path):
    require(not forbidden_path(path), 'forbidden_path_present')
    require(path in PUBLIC_TREE, 'unapproved_tree_path')
    require(path not in seen, 'tree_path_visited_twice')
    seen.add(path)
    require(len(seen) <= MAX_ENTRIES, 'tree_entry_limit')
    expected = PUBLIC_TREE[path]
    info = os.lstat(path)
    if stat.S_ISSOCK(info.st_mode):
        fail('filesystem_socket')
    kinds = ((stat.S_ISDIR, 'dir'), (stat.S_ISREG, 'file'),
             (stat.S_ISLNK, 'link'), (stat.S_ISCHR, 'char'))
    kind = next((name for test, name in kinds if test(info.st_mode)), None)
    require(kind is not None and expected.get('kind') == kind, 'tree_type')
    common = {'kind', 'mode', 'uid', 'gid', 'nlink'}
    extras = {'dir': set(), 'file': {'size', 'sha256'},
              'link': {'target'}, 'char': {'rdev'}}[kind]
    require(set(expected) == common | extras, 'tree_profile_schema')
    require((stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid, info.st_nlink) ==
            (expected['mode'], expected['uid'], expected['gid'], expected['nlink']),
            'tree_metadata')
    require(not (info.st_mode & (stat.S_ISUID | stat.S_ISGID)), 'setid_file')
    # Ban real Go/CLI by name anywhere, not merely executable names on one fs.
    # Renamed binaries are excluded by the independently audited content pins,
    # NOT by this basename heuristic or executable permission bits alone.
    name = os.path.basename(path)
    require(name not in {'go', 'gofmt', *AGENT_NAMES} and
            re.fullmatch(r'go1\.[^/]*', name) is None, 'go_or_agent_name')
    if kind == 'file':
        require(info.st_nlink == 1 and info.st_size == expected['size'] and
                digest_ok(expected['sha256']), 'public_file_profile')
        # Only now, after the exact public path/type/metadata allowlist check,
        # open a public regular file. Never follow links or read unknown content.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        with os.fdopen(fd, 'rb') as handle:
            before = os.fstat(handle.fileno())
            require((before.st_dev, before.st_ino, before.st_mode, before.st_size) ==
                    (info.st_dev, info.st_ino, info.st_mode, info.st_size), 'file_race')
            value = hashlib.sha256()
            for chunk in iter(lambda: handle.read(65536), b''):
                value.update(chunk)
            after = os.fstat(handle.fileno())
            require((after.st_size, after.st_mtime_ns, after.st_ctime_ns) ==
                    (before.st_size, before.st_mtime_ns, before.st_ctime_ns), 'file_changed')
        require(value.hexdigest() == expected['sha256'], 'public_file_hash')
    elif kind == 'link':
        require(os.readlink(path) == expected['target'], 'symlink_target')
    elif kind == 'char':
        require(owner_mount(path) == '/dev' and
                (os.major(info.st_rdev), os.minor(info.st_rdev)) == expected['rdev']
                and expected['rdev'] in {(1, 3), (1, 5), (1, 7), (1, 8), (1, 9)},
                'unapproved_device')
    return kind


def walk_public(path, mount_target):
    kind = inspect_public(path)
    if kind != 'dir':
        return
    # No -xdev. Every discovered mount is accounted for separately, including
    # same-device bind mounts. Never recurse into proc/sys pseudo subtrees.
    for name in sorted(os.listdir(path)):
        child = path.rstrip('/') + '/' + name
        if child in mounts and child != mount_target:
            continue
        require(owner_mount(child) == mount_target, 'unaccounted_mount_crossing')
        walk_public(child, mount_target)


def inventory():
    for target in sorted(mounts):
        role = ALLOWED_ROLES[target]
        if role in PSEUDO_ROLES:
            continue
        if role == 'probe':
            info = os.lstat(PROBE_PATH)
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and
                    not (info.st_mode & 0o222) and info.st_uid == 0,
                    'probe_artifact_metadata')
            # Public source of this draft only. Hash is evidence, NOT self-trust.
            emit('PROBE_SHA256_OBSERVED', hashlib.sha256(read_public(PROBE_PATH)).hexdigest())
            continue
        walk_public(target, target)
    require(seen == set(PUBLIC_TREE), 'public_tree_exact_inventory')
    require(not os.listdir('/work') and not os.listdir('/tmp'), 'scratch_not_empty')
    # Payload is exactly a root-owned public names.txt on its own readonly mount.
    require(os.listdir('/payload') == ['names.txt'], 'payload_extra_entry')
    for path in ('/payload', '/payload/names.txt'):
        info = os.lstat(path)
        require(info.st_uid == 0 and info.st_gid == 0 and
                not (info.st_mode & 0o022), 'payload_ownership_or_mode')
    data = read_public('/payload/names.txt', 16384)
    expected = (''.join(name + '\n' for name in AGENT_NAMES)).encode('ascii')
    require(data == expected, 'payload_exact_bytes')
    emit('PAYLOAD_SHA256', hashlib.sha256(data).hexdigest())
    emit('PUBLIC_TREE_ENTRIES', len(seen))
    emit('FILESYSTEM_SOCKETS', 'zero_in_exact_visible_nonpseudo_inventory')
    emit('IMAGE_DIGEST_DECLARED_NOT_ATTESTED', IMAGE_DIGEST)
    emit('VISIBLE_GO_CLI', 'absent_under_approved_public_content_inventory')


def interfaces_and_routes():
    # /proc/net is usually a symlink to self/net, NOT a directory for a generic
    # no-follow scanner. Use explicit /proc/self/net tables in our own netns.
    require(os.readlink('/proc/net') == 'self/net', 'proc_net_alias')
    require(os.readlink('/proc/self/ns/net') == os.readlink('/proc/1/ns/net'),
            'network_namespace_changed')
    lines = text_public('/proc/self/net/dev', 16384).splitlines()
    require(len(lines) == 3 and 'Inter-' in lines[0] and 'face' in lines[1] and
            lines[2].split(':', 1)[0].strip() == 'lo', 'network_interface_table')
    require(os.listdir('/sys/class/net') == ['lo'], 'network_interface_inventory')
    require(text_public('/sys/class/net/lo/type', 32).strip() == '772', 'not_loopback')
    v6_address_count = 0
    for line in text_public('/proc/self/net/if_inet6', 16384).splitlines():
        f = line.split()
        require(len(f) == 6 and f[5] == 'lo' and
                re.fullmatch(r'[0-9a-fA-F]{32}', f[0]) is not None and
                all(re.fullmatch(r'[0-9a-fA-F]{2}', f[i]) for i in (1, 2, 3, 4)),
                'ipv6_address_format')
        require(int(f[0], 16) == 1 and int(f[2], 16) == 128 and
                int(f[3], 16) == 16, 'nonloopback_ipv6_address')
        v6_address_count += 1
    ipv4 = text_public('/proc/self/net/route', 16384).splitlines()
    require(bool(ipv4) and ipv4[0].split() ==
            ['Iface', 'Destination', 'Gateway', 'Flags', 'RefCnt', 'Use', 'Metric',
             'Mask', 'MTU', 'Window', 'IRTT'], 'ipv4_route_header')
    v4_count = 0
    for line in ipv4[1:]:
        f = line.split()
        require(len(f) == 11 and f[0] == 'lo' and all(
                re.fullmatch(r'[0-9A-Fa-f]{8}', f[i]) for i in (1, 2, 7)) and
                re.fullmatch(r'[0-9A-Fa-f]{1,8}', f[3]) is not None and
                all(f[i].isdecimal() for i in (4, 5, 6, 8, 9, 10)),
                'ipv4_route_format')
        address = ipaddress.IPv4Address(bytes.fromhex(f[1])[::-1])
        mask = ipaddress.IPv4Address(bytes.fromhex(f[7])[::-1])
        network = ipaddress.IPv4Network(str(address) + '/' + str(mask), strict=True)
        require(network.subnet_of(ipaddress.IPv4Network('127.0.0.0/8')) and
                int(f[2], 16) == 0 and (int(f[3], 16) & 2) == 0,
                'nonloopback_ipv4_route')
        v4_count += 1
    v6_count = 0
    for line in text_public('/proc/self/net/ipv6_route', 16384).splitlines():
        f = line.split()
        require(len(f) == 10 and f[9] == 'lo' and all(
                re.fullmatch(r'[0-9A-Fa-f]{32}', f[i]) for i in (0, 2, 4)) and
                all(re.fullmatch(r'[0-9A-Fa-f]{2}', f[i]) for i in (1, 3)),
                'ipv6_route_format')
        require(int(f[0], 16) == 1 and int(f[1], 16) == 128 and
                int(f[2], 16) == 0 and int(f[3], 16) == 0 and int(f[4], 16) == 0,
                'nonloopback_ipv6_route')
        # Even an unreachable/default ::/0 lo entry is not silently treated as
        # loopback. A real environment difference must be captured and reviewed.
        v6_count += 1
    emit('NETWORK_INTERFACES', 'lo_only')
    emit('IPV6_ADDRESS_ROWS_LOOPBACK_ONLY', v6_address_count)
    emit('ROUTE_ROWS_LOOPBACK_ONLY', str(v4_count) + ',' + str(v6_count))
    # These proc views are NOT proof about all policy routing tables, addresses,
    # namespace provenance, host firewall/NAT, or a later-time network condition.
    # No AF_INET/AF_UNIX/AF_NETLINK socket, ping, curl or connect is created here.


def no_sockets():
    for name in ('tcp', 'tcp6', 'udp', 'udp6', 'raw', 'raw6'):
        lines = text_public('/proc/self/net/' + name, 1048576).splitlines()
        require(len(lines) == 1 and 'local_address' in lines[0] and
                'inode' in lines[0], 'inet_socket_or_bad_table')
    lines = text_public('/proc/self/net/unix', 1048576).splitlines()
    require(len(lines) == 1 and lines[0].split() ==
            ['Num', 'RefCount', 'Protocol', 'Flags', 'Type', 'St', 'Inode', 'Path'],
            'unix_socket_or_bad_table')
    # Zero Unix entries includes abstract, unnamed, non-listening and PG/engine
    # sockets; no socket paths/names are printed. File scans also reject every
    # socket inode, not just a few conventional .s.PGSQL/docker/podman locations.
    lines = text_public('/proc/self/net/packet', 16384).splitlines()
    require(len(lines) == 1 and 'Iface' in lines[0] and 'Inode' in lines[0],
            'packet_socket_or_bad_table')
    emit('SOCKET_TABLES', 'tcp,tcp6,udp,udp6,raw,raw6,unix,packet:zero_rows')
    emit('PG_ENGINE_SOCKET', 'namespace_unix_entries:zero;filesystem_inventory:separate')


def cgroup_observation():
    # cgroup v2 only; a private namespace rooted at the intended cgroup must be
    # established externally. Seeing '/' does NOT establish ownership/enforcement.
    require(text_public('/proc/self/cgroup', 4096) == '0::/\n', 'cgroup_membership_view')
    for filename, expected in LIMITS.items():
        value = text_public('/sys/fs/cgroup/' + filename, 4096).strip()
        require(value == expected, 'cgroup_limit_value')
        emit('CGROUP_REPORTED_' + filename.upper().replace('.', '_'), expected)
    emit('CGROUP_ENFORCEMENT', 'NOT_PROVEN_NO_STRESS_TEST')


def readonly_errno_canary():
    # Nonprivileged touch yielding EACCES/ENOENT is NOT evidence of readonly.
    # Require ro mountinfo + statvfs AND precisely EROFS at a pre-approved,
    # searchable, mode-0777 empty root-image directory, not a bind or symlink.
    info = os.lstat(RO_CANARY_DIR)
    require(owner_mount(RO_CANARY_DIR) == '/' and stat.S_ISDIR(info.st_mode) and
            stat.S_IMODE(info.st_mode) == 0o777 and not os.listdir(RO_CANARY_DIR),
            'readonly_canary_precondition')
    path = RO_CANARY_DIR + '/p1b-must-not-exist'
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                     os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except OSError as exc:
        require(exc.errno == errno.EROFS, 'readonly_not_erofs')
    else:
        os.close(fd)
        # Do not conceal the unexpected mutation with best-effort cleanup.
        fail('readonly_canary_created')
    emit('ROOT_READONLY', 'mountinfo_ro+statvfs_rdonly+errno_EROFS')
    emit('READONLY_BINDS', 'each_exact_mount_ro+statvfs_rdonly')


def scratch_execution():
    # This is the ONLY proposed successful write/exec. It is unapproved NOW.
    # No Go, CLI, old scripts, arbitrary command, dynamic interpolation or shell
    # command construction. Exact public bytes, permissions, owner and exit code.
    os.umask(0o077)
    for directory in ('/work', '/tmp'):
        path = directory + '/p1b-exit-zero'
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                     os.O_NOFOLLOW | os.O_CLOEXEC, 0o700)
        with os.fdopen(fd, 'wb') as handle:
            require(handle.write(EXEC_BYTES) == len(EXEC_BYTES), 'canary_short_write')
            handle.flush()
            os.fchmod(handle.fileno(), 0o700)
        info = os.lstat(path)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 65534 and
                info.st_gid == 65534 and stat.S_IMODE(info.st_mode) == 0o700 and
                info.st_nlink == 1 and info.st_size == len(EXEC_BYTES) and
                read_public(path, 64) == EXEC_BYTES, 'execution_payload_exactness')
        child = os.fork()
        if child == 0:
            try:
                os.execve(path, [path], {'PATH': '/usr/bin:/bin', 'HOME': '/work',
                                      'LANG': 'C.UTF-8'})
            except BaseException:
                os._exit(126)
        waited, result = os.waitpid(child, 0)
        require(waited == child and os.WIFEXITED(result) and
                os.WEXITSTATUS(result) == 0, 'tmpfs_execution')
        require(read_public(path, 64) == EXEC_BYTES, 'canary_changed')
        os.unlink(path)  # only our exact O_EXCL-created public scratch file
        require(not os.listdir(directory), 'scratch_residue')
        emit('TMPFS_EXEC', directory + '|exact_exit_zero|sha256:' +
             hashlib.sha256(EXEC_BYTES).hexdigest())


def main():
    require(PROFILE_APPROVED and digest_ok(IMAGE_DIGEST.removeprefix('sha256:')) and
            IMAGE_DIGEST.startswith('sha256:') and digest_ok(SECCOMP_PROFILE_SHA256),
            'immutable_profile_unapproved')
    require(bool(MOUNTS) and bool(PUBLIC_TREE) and bool(AGENT_NAMES) and
            len(set(AGENT_NAMES)) == len(AGENT_NAMES) and all(
                re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name)
                for name in AGENT_NAMES), 'public_profile_incomplete')
    identity()
    before = validate_mounts()
    interfaces_and_routes()
    no_sockets()
    cgroup_observation()
    inventory()  # all mounts accounted for; no unknown/inaccessible subtree skip
    readonly_errno_canary()
    scratch_execution()
    # Detect changes without pretending finite snapshots eliminate TOCTOU.
    after, raw = parse_mounts()
    require(raw == before and after == mounts, 'mount_snapshot_changed')
    identity()
    interfaces_and_routes()
    no_sockets()
    cgroup_observation()
    emit('RESULT', 'OBSERVATIONS_ONLY_NOT_PASS')
    emit('ACCEPTANCE', 'BLOCKED_PENDING_INDEPENDENT_EXTERNAL_EVIDENCE')
    # Even a future successful observation run is not P1/P1a/P1b acceptance.
    # A nonzero exit prevents a generic exit-0 wrapper from upgrading it to PASS.
    raise SystemExit(3)


try:
    main()
except SystemExit:
    raise
except BaseException:
    # No Python traceback: filenames, input lines and exception text may be private.
    fail('unavailable_or_malformed_public_evidence')
P1B_PYTHON
exec /usr/bin/python3 -I -S -B -c "$p1b_python"

# OFFLINE / REAL-ENVIRONMENT GAPS -- no claim of execution or isolation here:
# 1. This file is locked; profiles are empty/unapproved. bash -n validates shell
#    grammar only. Python availability/version (>=3.9), syntax, imports, statvfs,
#    seccomp interaction, fork/exec and all observations remain wholly untested.
#    No automatic tests or run conditions have been approved. Do not unlock to test.
# 2. Need separately authorized, fresh, attributable resource creation receipts,
#    exact full IDs, immutable image content/provenance and interpreter/stdlib
#    inventory, actual command/PID1/cwd/uid/groups, sterile bootstrap env and FD
#    policy, and reviewed seccomp-profile hash. Never inspect existing containers'
#    environments or use secret-bearing inspect dumps. No P1/P1a evidence reuse.
# 3. Need a concrete per-run exact mount profile, including decoded escaped paths,
#    source/root of common readonly /etc file binds and /probe.sh, super options,
#    root-overlay provenance, readonly proc/sys/cgroup and private propagation.
#    Exact relation to approved sources must be established outside this namespace;
#    mountinfo alone cannot distinguish every readonly host bind from safe input.
#    Unknown/stacked/idmapped/FUSE/9p/virtiofs/host-drive/extra default runtime mounts
#    fail. Reject escaped control/backslash paths rather than misparse them.
#    Default /dev/pts,/dev/shm,/dev/mqueue and nonempty proc masks may need runtime
#    changes; those changes and this stricter minimal profile are NOT authorized.
# 4. Need a purpose-built public-only root inventory and exact payload/CLI-name
#    bytes; bind-covered image contents are not visible here. Trusted offline image
#    audit must exclude renamed real Go/CLIs and hidden/opaque/secret material.
#    Never generate a public allowlist by reading unknown runtime files/secrets.
#    /probe.sh's observed hash must match an independently approved external hash;
#    self-observed hashes, image strings and approved-looking filenames aren't trust.
# 5. /proc/self/net + sysfs checks are netns snapshots, not complete policy-routing
#    or cross-namespace/socket provenance proofs. Need separately approved external
#    capture of only-loopback addresses, ALL route tables/rules (v4/v6), no network
#    attachment/port publication, namespace ownership and no inherited foreign-ns
#    sockets. The probe makes no network/netlink socket and prints no addresses or
#    Unix paths. Missing ipv6 tables/default reject ::/0 entries fail, not waive.
#    Socket table emptiness and full visible filesystem scan do not prove facts
#    about host/other namespaces or a later instant. PG/engine path checks alone
#    would miss abstract/nonstandard/bind-hidden sockets; never substitute them.
# 6. cgroup file values are observations, NOT enforcement. Need authorized external
#    hierarchy/namespace/membership and ancestor-limit provenance; no stress test,
#    allocation bomb, fork bomb or CPU load is proposed. Seccomp mode likewise
#    isn't filter-content attestation. No host-wide isolation claim is possible.
# 7. Readonly requires kernel ro + statvfs and the root EROFS canary; EACCES is a
#    hard failure. The world-writable public canary directory and tiny executable
#    scratch tmpfs layout do not exist by assumption; need real artifact evidence.
#    Each readonly file bind is proved by its exact VFS/statvfs flags, not by touch.
# 8. Need externally attributable stdout/exit receipt, exact script/payload/image/
#    seccomp/profile hashes, start/stop boundaries, cleanup and before/after scope
#    evidence for NEW resources only. Record sanitized facts, never raw env,
#    secrets, full inspect/mountinfo/route/socket dumps or session data. Ownership
#    ambiguity means preserve, not delete; this probe contains no engine cleanup.
#
# INDEPENDENT REVIEW CHECKLIST (before any separately approved future run):
# - Both literal false locks remain intact here; no execution/auto-test approval.
# - Resolve bootstrap trust/circular self-hash, public inventory origin, exact names
#   and payload bytes; audit Python and Bash separately (bash -n isn't Python lint).
# - Check mount decoder, exact source/fs/root whitelist, readonly binds/EROFS,
#   same-device bind traversal, pseudo exclusions, sockets (incl. abstract), FD
#   inheritance, route/policy-table gaps and snapshot/TOCTOU limitations.
# - Check uid/gid/PID1/all five caps/NNP/seccomp, cgroup OBSERVED-vs-ENFORCED wording,
#   tmpfs size/source/flags/exact exec bytes; no real Go/CLI/old-script invocation.
# - Approve any test/run conditions independently; review actual evidence before
#   any acceptance. Never infer PASS from static text or from P1a, and never alter
#   the sealed P1 directory. An observation exit=3 is intentionally NOT PASS.
