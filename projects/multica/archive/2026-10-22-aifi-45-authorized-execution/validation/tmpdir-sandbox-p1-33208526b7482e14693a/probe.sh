#!/bin/bash
# Read-only boundary probe; no application scripts, Go, agent CLI, DB or network.
set -eu -o pipefail
fail() { printf 'P1_FAIL: %s\n' "$1" >&2; exit 1; }
[ "$(id -u)" = 65534 ] || fail uid
[ "$$" = 1 ] || fail pid1
for key in CapEff CapPrm CapBnd; do
  value=$(awk -v k="$key:" '$1==k {print $2}' /proc/self/status)
  [ "$value" = 0000000000000000 ] || fail "$key"
done
[ "$(awk '$1=="NoNewPrivs:" {print $2}' /proc/self/status)" = 1 ] || fail no_new_privileges
[ "$(awk '$1=="Seccomp:" {print $2}' /proc/self/status)" = 2 ] || fail seccomp
awk '$5=="/" && $6 ~ /(^|,)ro(,|$)/ {ok=1} END {exit !ok}' /proc/self/mountinfo || fail root_not_readonly
if grep -E ' - (9p|drvfs|virtiofs|fuse(\.| ))' /proc/self/mountinfo >/dev/null; then fail host_mount; fi
awk '$6 ~ /(^|,)rw(,|$)/ && $5 !~ /^\/(work$|tmp$|dev(\/|$)|proc(\/|$)|etc\/(hosts|hostname|resolv.conf)$|run\/\.containerenv$)/ {print "unexpected writable mount:", $5 > "/dev/stderr"; bad=1} END {exit bad}' /proc/self/mountinfo || fail writable_mount
for d in / /etc /usr /var/lib/postgresql/data; do
  if touch "$d/.p1-write-probe" 2>/dev/null; then fail "unexpected_write:$d"; fi
done
printf '#!/bin/sh\nexit 0\n' > /work/p1-exec-probe
chmod 700 /work/p1-exec-probe
/work/p1-exec-probe || fail tmpfs_execution
printf '#!/bin/sh\nexit 0\n' > /tmp/p1-exec-probe
chmod 700 /tmp/p1-exec-probe
/tmp/p1-exec-probe || fail tmpfs_execution
[ "$(ls -1 /sys/class/net | tr '\n' ' ')" = 'lo ' ] || fail network_interfaces
[ "$(wc -l < /proc/net/route)" -eq 1 ] || fail route
for f in /proc/net/tcp /proc/net/tcp6; do
  [ -r "$f" ] || fail tcp_table_unavailable
  if awk 'NR>1 && $4=="0A" {found=1} END {exit !found}' "$f"; then fail tcp_listener; fi
done
for f in /proc/[0-9]*/comm; do
  [ -r "$f" ] || continue
  IFS= read -r comm < "$f" || continue
  [ "$comm" != postgres ] || fail postgres_running
done
for f in /var/run/postgresql/.s.PGSQL.5432 /run/podman/podman.sock /var/run/docker.sock /run/user/1000/podman/podman.sock /usr/local/go /mnt/c /init; do
  [ ! -e "$f" ] || fail "unexpected_path:$f"
done
[ -z "${GOROOT+x}" ] && [ -z "${GOPATH+x}" ] || fail go_environment
find / -xdev -type d \( ! -readable -o ! -executable \) -prune -print > /work/inaccessible-directories 2>/work/find-errors || fail directory_scan
[ ! -s /work/find-errors ] || fail directory_scan_errors
while IFS= read -r d; do [ ! -x "$d" ] || fail "searchable_unreadable_directory:$d"; done < /work/inaccessible-directories
find / -xdev -type d \( ! -readable -o ! -executable \) -prune -o \( -type f -o -type l \) -executable -printf '%f\n' > /work/executable-names 2>/work/find-errors || fail executable_scan
[ ! -s /work/find-errors ] || fail executable_scan_errors
for n in go gofmt; do
  if command -v "$n" >/dev/null 2>&1 || grep -Fxq "$n" /work/executable-names; then fail "unexpected_command:$n"; fi
done
while IFS= read -r n || [ -n "$n" ]; do
  case "$n" in ''|'#'*) continue ;; *[!A-Za-z0-9._-]*) fail invalid_agent_name ;; esac
  if command -v "$n" >/dev/null 2>&1 || grep -Fxq "$n" /work/executable-names; then fail "unexpected_command:$n"; fi
done < names.txt
if grep -Eq '^go1\.[^/]*$' /work/executable-names; then fail versioned_go; fi
[ "$(cat /sys/fs/cgroup/memory.max)" = 134217728 ] || fail memory_limit
[ "$(cat /sys/fs/cgroup/memory.swap.max)" = 0 ] || fail swap_limit
[ "$(cat /sys/fs/cgroup/pids.max)" = 64 ] || fail pids_limit
[ "$(cat /sys/fs/cgroup/cpu.max)" = '50000 100000' ] || fail cpu_limit
while IFS='=' read -r key _; do
  case "$key" in PATH|HOME|LANG|SBX_MANIFEST_SHA256|container|HOSTNAME|TERM|PWD|OLDPWD|SHLVL|_) ;; *) fail "unexpected_env:$key" ;; esac
done < <(env)
printf 'P1_ID=uid:%s,pid:%s\n' "$(id -u)" "$$"
printf 'P1_ROOT_MOUNT='; awk '$5=="/" {print $6}' /proc/self/mountinfo
printf 'P1_NET=lo\nP1_CGROUP=%s,%s,%s,%s\n' "$(cat /sys/fs/cgroup/memory.max)" "$(cat /sys/fs/cgroup/memory.swap.max)" "$(cat /sys/fs/cgroup/pids.max)" "$(cat /sys/fs/cgroup/cpu.max)"
printf 'P1_INACCESSIBLE_DIRECTORIES_BEGIN\n'; cat /work/inaccessible-directories; printf 'P1_INACCESSIBLE_DIRECTORIES_END\n'
sed 's/^/P1_MOUNT /' /proc/self/mountinfo
printf 'P1_RESULT=PASS\n'
