#!/bin/sh
# E2: Linux kernel enforcement of trust-root key isolation.
#
# Run as root inside the AIFI-ISO WSL distro:
#   wsl -d AIFI-ISO -u root -- sh /mnt/c/.../e2-linux-key-isolation-20261108/probe.sh
#
# Root is used only for orchestration, hash capture, and cleanup.
# The trust anchor is installed by aifi-svc (uid 1500); all three write
# attempts are executed by aifi-agent (uid 1501) through runuser.
# The verdict is based only on each command's real exit status and stderr,
# plus SHA-256 before/after. No test -w or mode-bit inference is used.

set -u
LC_ALL=C
export LC_ALL

SVC=aifi-svc
AGENT=aifi-agent

BASE=
AGENT_STAGE=
TRUST=
KEY=
SVC_STAGE=
WORK=
ATTACKER=
cleaned=0

cleanup() {
    [ "$cleaned" -eq 1 ] && return 0
    cleaned=1
    [ -n "$BASE" ] && rm -rf -- "$BASE"
    [ -n "$AGENT_STAGE" ] && rm -rf -- "$AGENT_STAGE"
    printf '\n=== cleanup ===\n'
    if [ -n "$BASE" ]; then
        printf 'removed: %s\n' "$BASE"
    fi
    if [ -n "$AGENT_STAGE" ]; then
        printf 'removed: %s\n' "$AGENT_STAGE"
    fi
    if { [ -n "$BASE" ] && [ -e "$BASE" ]; } || { [ -n "$AGENT_STAGE" ] && [ -e "$AGENT_STAGE" ]; }; then
        printf 'cleanup_check: LEFTOVER PRESENT\n'
    else
        printf 'cleanup_check: both paths absent\n'
    fi
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    die "probe must run as root (it uses runuser to switch to $SVC/$AGENT)"
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

BASE=$(mktemp -d "/var/lib/aifi-e2-probe.XXXXXX") || die "mktemp failed for trust-root base"
AGENT_STAGE=$(mktemp -d "/var/tmp/aifi-e2-agent.XXXXXX") || die "mktemp failed for agent staging dir"
TRUST="$BASE/trustroot"
KEY="$TRUST/aifi-release.ed25519.pub"
SVC_STAGE="$BASE/svc-stage"
WORK="$BASE/work"
ATTACKER="$AGENT_STAGE/attacker.ed25519.pub"

printf '=== E2 Linux key isolation probe ===\n'
printf 'date_utc: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'kernel: %s\n' "$(uname -srm)"
printf 'distro: %s\n' "$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}" )"
printf 'root_uid: %s\n' "$(id -u)"

SVC_UID=$(runuser -u "$SVC" -- id -u)
AGENT_UID=$(runuser -u "$AGENT" -- id -u)
case "$SVC_UID" in
    ''|*[!0-9]*) die "could not resolve uid for $SVC" ;;
esac
case "$AGENT_UID" in
    ''|*[!0-9]*) die "could not resolve uid for $AGENT" ;;
esac
[ "$SVC_UID" -ne "$AGENT_UID" ] || die "service and agent resolve to the same uid"
[ "$AGENT_UID" -ne 0 ] || die "agent uid is 0"

printf 'service_identity: %s uid=%s\n' "$SVC" "$SVC_UID"
printf 'agent_identity:   %s uid=%s\n' "$AGENT" "$AGENT_UID"
printf 'service_full_id:  %s\n' "$(runuser -u "$SVC" -- id)"
printf 'agent_full_id:    %s\n' "$(runuser -u "$AGENT" -- id)"

# ---------------------------------------------------------------------------
# Setup: root-owned parent, service-owned trust root, read-only for agent.
# ---------------------------------------------------------------------------
umask 022
mkdir -p -- "$TRUST" "$SVC_STAGE" "$WORK" || die "mkdir failed"
chown root:root "$BASE"
chmod 0755 "$BASE"
chown "$SVC:$SVC" "$TRUST" "$SVC_STAGE"
chmod 0755 "$TRUST"
chmod 0700 "$SVC_STAGE"
chown root:root "$WORK"
chmod 0700 "$WORK"
chown "$AGENT:$AGENT" "$AGENT_STAGE"
chmod 0700 "$AGENT_STAGE"

printf '\n=== [setup] service identity generates Ed25519 keypair (private key stays in memory) ===\n'
runuser -u "$SVC" -- python3 -c '
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
import sys

key = Ed25519PrivateKey.generate()
pub = key.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
with open(sys.argv[1], "wb") as f:
    f.write(pub)
' "$SVC_STAGE/signer.ed25519.pub"
rc_keygen=$?
printf 'keygen_exit_code=%s\n' "$rc_keygen"
if [ "$rc_keygen" -ne 0 ]; then
    die "service-side key generation failed"
fi

printf '\n=== [setup] service identity installs public key into trust root ===\n'
runuser -u "$SVC" -- sh -c 'cd /; id -u; install -m 0644 "$1" "$2"' sh "$SVC_STAGE/signer.ed25519.pub" "$KEY" >"$WORK/install.out" 2>"$WORK/install.err"
rc_install=$?
printf 'exit_code=%s\n' "$rc_install"
printf '%s\n' '--- stdout ---'
cat "$WORK/install.out"
printf '%s\n' '--- stderr ---'
cat "$WORK/install.err"
printf '%s\n' '--- end ---'
if [ "$rc_install" -ne 0 ]; then
    die "service-side install failed"
fi

printf '\n=== [state] installed trust anchor ===\n'
stat -c 'mode=%a owner=%U:%G uid=%u gid=%g inode=%i size=%s path=%n' "$BASE" "$TRUST" "$KEY" || die "stat failed"

# ---------------------------------------------------------------------------
# Positive control: agent must still be able to READ the anchor.
# This distinguishes "read-only trust anchor" from "no access at all".
# ---------------------------------------------------------------------------
printf '\n=== [control] agent reads the same anchor (expected: success) ===\n'
runuser -u "$AGENT" -- sh -c 'cd /; id -u; sha256sum "$1"' sh "$KEY" >"$WORK/agent-read.out" 2>"$WORK/agent-read.err"
rc_read=$?
printf 'exit_code=%s\n' "$rc_read"
printf '%s\n' '--- stdout ---'
cat "$WORK/agent-read.out"
printf '%s\n' '--- stderr ---'
cat "$WORK/agent-read.err"
printf '%s\n' '--- end ---'

# ---------------------------------------------------------------------------
# Capture the exact state before any write attempt.
# ---------------------------------------------------------------------------
printf '\n=== [state] before attempts ===\n'
before_sha_line=$(sha256sum "$KEY") || die "sha256sum before failed"
before_sha=$(printf '%s\n' "$before_sha_line" | awk '{print $1}')
before_inode=$(stat -c '%i' "$KEY") || die "stat inode before failed"
before_size=$(stat -c '%s' "$KEY") || die "stat size before failed"
before_mode=$(stat -c '%a' "$KEY") || die "stat mode before failed"
before_owner=$(stat -c '%U:%G' "$KEY") || die "stat owner before failed"
printf '%s\n' "$before_sha_line"
printf 'inode=%s size=%s mode=%s owner=%s\n' "$before_inode" "$before_size" "$before_mode" "$before_owner"

# ---------------------------------------------------------------------------
# Execute one attempt as the agent and print the raw result.
# ---------------------------------------------------------------------------
run_attempt() {
    label=$1
    action=$2
    shift 2
    out="$WORK/$label.out"
    err="$WORK/$label.err"
    runuser -u "$AGENT" -- "$@" >"$out" 2>"$err"
    rc=$?
    printf '\n=== [%s] %s ===\n' "$label" "$action"
    printf 'runner: %s (uid %s)\n' "$AGENT" "$AGENT_UID"
    printf 'exit_code=%s\n' "$rc"
    printf '%s\n' '--- stdout ---'
    cat "$out"
    printf '%s\n' '--- stderr ---'
    cat "$err"
    printf '%s\n' '--- end ---'
    return "$rc"
}

# 1/3: overwrite in place (O_WRONLY|O_CREAT|O_TRUNC).
run_attempt overwrite \
    'overwrite in place via shell redirection (O_WRONLY|O_CREAT|O_TRUNC)' \
    sh -c 'cd /; id -u; printf "%s\n" "ATTACKER-OVERWRITE" > "$1"' sh "$KEY"
rc_overwrite=$?

# 2/3: replace the inode by rename.
printf '\n=== [replace] agent creates its own Ed25519 pubkey in its own staging dir ===\n'
runuser -u "$AGENT" -- python3 -c '
import os
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

print("uid=%d" % os.getuid())
key = Ed25519PrivateKey.generate()
pub = key.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
with open(sys.argv[1], "wb") as f:
    f.write(pub)
' "$ATTACKER" >"$WORK/attacker-keygen.out" 2>"$WORK/attacker-keygen.err"
rc_attacker_key=$?
printf 'attacker_keygen_exit_code=%s\n' "$rc_attacker_key"
printf '%s\n' '--- stdout ---'
cat "$WORK/attacker-keygen.out"
printf '%s\n' '--- stderr ---'
cat "$WORK/attacker-keygen.err"
printf '%s\n' '--- end ---'
if [ "$rc_attacker_key" -ne 0 ]; then
    die "agent-side key generation failed"
fi
printf 'attacker_key_sha256: %s\n' "$(sha256sum "$ATTACKER" | awk '{print $1}')"
printf 'replace_fs_device: source=%s target=%s\n' "$(stat -c '%d' "$AGENT_STAGE")" "$(stat -c '%d' "$TRUST")"

run_attempt replace \
    'replace inode via rename (mv -f attacker.pub over trust anchor)' \
    sh -c 'cd /; id -u; mv -f "$1" "$2"' sh "$ATTACKER" "$KEY"
rc_replace=$?

# 3/3: append (O_WRONLY|O_APPEND).
run_attempt append \
    'append via shell redirection (O_WRONLY|O_APPEND)' \
    sh -c 'cd /; id -u; printf "%s\n" "ATTACKER-APPEND" >> "$1"' sh "$KEY"
rc_append=$?

# ---------------------------------------------------------------------------
# Capture the exact state after all attempts and compare.
# ---------------------------------------------------------------------------
printf '\n=== [state] after attempts ===\n'
after_sha_line=$(sha256sum "$KEY") || die "sha256sum after failed"
after_sha=$(printf '%s\n' "$after_sha_line" | awk '{print $1}')
after_inode=$(stat -c '%i' "$KEY") || die "stat inode after failed"
after_size=$(stat -c '%s' "$KEY") || die "stat size after failed"
after_mode=$(stat -c '%a' "$KEY") || die "stat mode after failed"
after_owner=$(stat -c '%U:%G' "$KEY") || die "stat owner after failed"
printf '%s\n' "$after_sha_line"
printf 'inode=%s size=%s mode=%s owner=%s\n' "$after_inode" "$after_size" "$after_mode" "$after_owner"

sha_equal=no
[ "$before_sha" = "$after_sha" ] && sha_equal=yes
inode_equal=no
[ "$before_inode" = "$after_inode" ] && inode_equal=yes
metadata_equal=no
if [ "$before_size" = "$after_size" ] && [ "$before_mode" = "$after_mode" ] && [ "$before_owner" = "$after_owner" ]; then
    metadata_equal=yes
fi

# ---------------------------------------------------------------------------
# Verdicts: only real exit status + stderr text + hash comparison are used.
# ---------------------------------------------------------------------------
overwrite_verdict=NOT_DENIED
if [ "$rc_overwrite" -ne 0 ] && grep -Eq 'Permission denied|Operation not permitted' "$WORK/overwrite.err"; then
    overwrite_verdict=DENIED
fi

replace_verdict=NOT_DENIED
if [ "$rc_replace" -ne 0 ] && grep -Eq 'Permission denied|Operation not permitted' "$WORK/replace.err"; then
    replace_verdict=DENIED
fi

append_verdict=NOT_DENIED
if [ "$rc_append" -ne 0 ] && grep -Eq 'Permission denied|Operation not permitted' "$WORK/append.err"; then
    append_verdict=DENIED
fi

read_control=FAILED
[ "$rc_read" -eq 0 ] && read_control=OK

printf '\n=== summary ===\n'
printf 'kernel: %s\n' "$(uname -srm)"
printf 'uid_service=%s\n' "$SVC_UID"
printf 'uid_agent=%s\n' "$AGENT_UID"
printf 'uids_distinct=yes\n'
printf 'read_control=%s (exit=%s)\n' "$read_control" "$rc_read"
printf 'overwrite: exit=%s verdict=%s\n' "$rc_overwrite" "$overwrite_verdict"
printf 'replace:   exit=%s verdict=%s\n' "$rc_replace" "$replace_verdict"
printf 'append:    exit=%s verdict=%s\n' "$rc_append" "$append_verdict"
printf 'sha256_before=%s\n' "$before_sha"
printf 'sha256_after=%s\n' "$after_sha"
printf 'sha256_equal=%s\n' "$sha_equal"
printf 'inode_before=%s inode_after=%s inode_equal=%s\n' "$before_inode" "$after_inode" "$inode_equal"
printf 'metadata_equal=%s\n' "$metadata_equal"

cleanup

if [ "$overwrite_verdict" = DENIED ] && \
   [ "$replace_verdict" = DENIED ] && \
   [ "$append_verdict" = DENIED ] && \
   [ "$sha_equal" = yes ] && \
   [ "$metadata_equal" = yes ] && \
   [ "$read_control" = OK ] && \
   [ "$SVC_UID" -ne "$AGENT_UID" ]; then
    printf '\nRESULT: PASS -- all three write attempts were denied by the kernel; anchor SHA-256 unchanged; service/agent uids differ.\n'
    exit 0
else
    printf '\nRESULT: FAIL -- see raw results above; do not adjust the conclusion, adjust the scheme.\n'
    exit 1
fi
