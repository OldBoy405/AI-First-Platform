#!/bin/bash
# P0 evidence run. Installs pinned launcher/entrypoint, then collects probes and an
# execve trace (bpftrace on sched tracepoints; auditd cannot run in a WSL distro).
set -euo pipefail
SRC=/mnt/c/Users/GOBAO/AppData/Local/Temp/aifi45/p0
OUT=/tmp/aifi45-p0; rm -rf "$OUT"; mkdir -p "$OUT"
L=/usr/local/lib/aifi45
sudo -n install -o root -g root -m 0755 "$SRC/launch.sh" "$L/launch.sh"
sudo -n install -o root -g root -m 0755 "$SRC/entrypoint.sh" "$L/entrypoint.sh"
sudo -n rm -f /var/lib/aifi45/worker/entrypoint.sh /var/lib/aifi45/reader/entrypoint.sh
cp "$SRC/exec.bt" "$SRC/check.py" "$OUT/"
{ ls -ldn "$L" "$L/launch.sh" "$L/entrypoint.sh" /var/lib/aifi45 /var/lib/aifi45/worker /var/lib/aifi45/reader
  sudo -n ls -lan /var/lib/aifi45/worker /var/lib/aifi45/reader
  sha256sum "$L/launch.sh" "$L/entrypoint.sh" "$OUT/exec.bt" "$OUT/check.py"
  echo "kernel=$(uname -r) bpftrace=$(rpm -q bpftrace) podman=$(podman --version)"
  echo "pidns=$(sudo -n readlink /proc/1/ns/pid) userns=$(sudo -n readlink /proc/1/ns/user)"
} > "$OUT/inventory.txt" 2>&1

trace() { # $1=name; remaining = workload command string
  local name=$1; shift
  sudo -n unshare -m sh -c "mount -t tmpfs none /lib/modules/\$(uname -r) && exec bpftrace -B line $OUT/exec.bt" > "$OUT/trace-$name.txt" 2>&1 &
  for _ in $(seq 1 60); do grep -q '^Attached' "$OUT/trace-$name.txt" 2>/dev/null && break; sleep 0.5; done
  grep -q '^Attached' "$OUT/trace-$name.txt" || { echo "tracer did not attach"; exit 1; }
  bash -c "$*"
  sleep 1
  sudo -n pkill -INT -f "bpftrace -B line $OUT/exec.bt" || true
  wait || true
}

trace clean "
  sudo -n $L/launch.sh --role worker --root /var/lib/aifi45/worker > $OUT/probes-worker.txt 2>&1
  sudo -n $L/launch.sh --role reader --root /var/lib/aifi45/reader > $OUT/probes-reader.txt 2>&1
  for bad in '--role root --root /var/lib/aifi45/worker' '--role worker --root /etc' \
             '--role worker --root /var/lib/aifi45/reader' '--role worker --root /var/lib/aifi45/worker --exec /bin/sh'; do
    if sudo -n $L/launch.sh \$bad >/dev/null 2>&1; then echo \"LAUNCH accepted \$bad\"; else echo \"LAUNCH denied rc=\$? \$bad\"; fi
  done > $OUT/launcher-allowlist.txt"

# Negative controls: the same probe body as root must show 'ok' everywhere, and a
# second start path outside the launcher must show up as a trace violation.
sudo -n env -i PATH=/usr/bin:/bin HOME=/var/lib/aifi45/worker $L/entrypoint.sh > "$OUT/probes-rootctl.txt" 2>&1
trace control "sudo -n -u aifi45-worker /usr/bin/id > $OUT/control-second-path.txt 2>&1"

python3 "$OUT/check.py" "$OUT"
