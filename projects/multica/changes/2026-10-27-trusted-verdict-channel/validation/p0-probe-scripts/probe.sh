#!/bin/bash
set -uo pipefail
LAUNCH=/usr/local/lib/aifi45/launch.sh
pass=0; fail=0
emit() { printf '%s | %s | %s\n' "$1" "$2" "$3"; }

echo "### A. identity is real and unprivileged"
out=$(sudo -n "$LAUNCH" --role worker --root /var/lib/aifi45/worker 2>&1 || true)
uid_line=$(printf '%s\n' "$out" | grep '^Uid:' || true)
cap_line=$(printf '%s\n' "$out" | grep '^CapEff:' || true)
nnp_line=$(printf '%s\n' "$out" | grep '^NoNewPrivs:' || true)
if printf '%s' "$out" | grep -q '^uid=995 ' && printf '%s' "$uid_line" | grep -q '995' \
   && printf '%s' "$cap_line" | grep -q ':	0000000000000000' && printf '%s' "$nnp_line" | grep -q '1$'; then
  emit A PASS "uid=995 CapEff=0 NoNewPrivs=1"; pass=$((pass+1))
else
  emit A FAIL "$out" | head -6; fail=$((fail+1))
fi

echo
echo "### B. cross-read is impossible (worker -> reader root)"
if sudo -n "$LAUNCH" --role worker --root /var/lib/aifi45/worker >/dev/null 2>&1 \
   && sudo -n -u aifi45-worker ls /var/lib/aifi45/reader >/dev/null 2>&1; then
  emit B FAIL "worker read the reader root"; fail=$((fail+1))
else
  emit B PASS "worker cannot list /var/lib/aifi45/reader"; pass=$((pass+1))
fi
if sudo -n -u aifi45-reader ls /var/lib/aifi45/worker >/dev/null 2>&1; then
  emit B2 FAIL "reader read the worker root"; fail=$((fail+1))
else
  emit B2 PASS "reader cannot list /var/lib/aifi45/worker"; pass=$((pass+1))
fi

echo
echo "### C. launcher cannot be rewritten by a low-privilege identity"
if sudo -n -u aifi45-worker tee -a "$LAUNCH" >/dev/null 2>&1 <<< '#x'; then
  emit C FAIL "worker appended to the launcher"; fail=$((fail+1))
else
  emit C PASS "worker cannot write the launcher"; pass=$((pass+1))
fi

echo
echo "### D. no second start path (no shell, no sudo, no setuid helper)"
shell=$(getent passwd aifi45-worker | cut -d: -f7)
sudoers=$(sudo -n -l -U aifi45-worker 2>&1 | head -1)
setuid=$(sudo find /var/lib/aifi45 -perm -4000 2>/dev/null | wc -l)
if [ "$shell" = "/usr/sbin/nologin" ] && printf '%s' "$sudoers" | grep -qi 'not allowed' && [ "$setuid" = "0" ]; then
  emit D PASS "shell=nologin sudo=none setuid=0"; pass=$((pass+1))
else
  emit D FAIL "shell=$shell sudo=$sudoers setuid=$setuid"; fail=$((fail+1))
fi

echo
echo "### E. privilege cannot be regained inside the worker"
if sudo -n -u aifi45-worker sh -c 'sudo -n true' >/dev/null 2>&1; then
  emit E FAIL "worker ran sudo"; fail=$((fail+1))
else
  emit E PASS "sudo unavailable to worker"; pass=$((pass+1))
fi
if sudo -n -u aifi45-worker python3 -c 'import os,sys; os.setuid(0); sys.exit(0)' >/dev/null 2>&1; then
  emit E2 FAIL "setuid(0) succeeded"; fail=$((fail+1))
else
  emit E2 PASS "setuid(0) refused"; pass=$((pass+1))
fi

echo
echo "### F. launcher rejects anything outside the allowlist"
if sudo -n "$LAUNCH" --role root --root /var/lib/aifi45/worker >/dev/null 2>&1; then
  emit F FAIL "unknown role accepted"; fail=$((fail+1))
else
  emit F PASS "unknown role denied"; pass=$((pass+1))
fi
if sudo -n "$LAUNCH" --role worker --root /etc >/dev/null 2>&1; then
  emit F2 FAIL "arbitrary root accepted"; fail=$((fail+1))
else
  emit F2 PASS "non-private root denied"; pass=$((pass+1))
fi
if sudo -n "$LAUNCH" --role worker --root /var/lib/aifi45/worker --exec /bin/sh >/dev/null 2>&1; then
  emit F3 FAIL "extra argument accepted"; fail=$((fail+1))
else
  emit F3 PASS "extra argument denied"; pass=$((pass+1))
fi

echo
echo "### G. version pins"
emit G INFO "podman=$(podman --version 2>/dev/null || echo none) kernel=$(uname -r) launcher_sha256=$(sha256sum $LAUNCH | cut -d' ' -f1)"
echo "--- image digests (rootless list) ---"
podman images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' 2>/dev/null | head -5 || true

echo
echo "RESULT pass=$pass fail=$fail"
