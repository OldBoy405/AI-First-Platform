#!/bin/bash
set -euo pipefail
echo "== 1. reader identity =="
if ! id aifi45-reader >/dev/null 2>&1; then
  sudo useradd --system --create-home --home-dir /var/lib/aifi45/reader --shell /usr/sbin/nologin aifi45-reader
fi
id aifi45-worker aifi45-reader

echo "== 2. private roots =="
sudo install -d -o aifi45-worker -g aifi45-worker -m 0700 /var/lib/aifi45/worker
sudo install -d -o aifi45-reader -g aifi45-reader -m 0700 /var/lib/aifi45/reader
sudo install -d -m 0755 -o root -g root /var/lib/aifi45
sudo ls -ldn /var/lib/aifi45 /var/lib/aifi45/worker /var/lib/aifi45/reader

echo "== 3. launcher =="
sudo install -d -m 0755 -o root -g root /usr/local/lib/aifi45
sudo tee /usr/local/lib/aifi45/launch.sh >/dev/null <<'SH'
#!/bin/bash
set -euo pipefail
role=""; root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="${2:-}"; shift 2 ;;
    --root) root="${2:-}"; shift 2 ;;
    *) echo "denied: unknown arg $1" >&2; exit 64 ;;
  esac
done
case "$role" in
  worker) uid=aifi45-worker ;;
  reader) uid=aifi45-reader ;;
  *) echo "denied: role" >&2; exit 64 ;;
esac
case "$root" in
  /var/lib/aifi45/worker|/var/lib/aifi45/reader) ;;
  *) echo "denied: root" >&2; exit 64 ;;
esac
exec setpriv --reuid="$uid" --regid="$uid" --clear-groups --no-new-privs \
  env -i PATH=/usr/bin:/bin HOME="$root" "$root/entrypoint.sh"
SH
sudo chown root:root /usr/local/lib/aifi45/launch.sh
sudo chmod 0755 /usr/local/lib/aifi45/launch.sh
ls -ln /usr/local/lib/aifi45/launch.sh
sha256sum /usr/local/lib/aifi45/launch.sh

echo "== 4. per-role entrypoints =="
for role in worker reader; do
  sudo tee "/var/lib/aifi45/$role/entrypoint.sh" >/dev/null <<EP
#!/bin/bash
set -euo pipefail
echo "uid=\$(id -u) gid=\$(id -g) euid=\$(id -u)"
grep -E '^(Uid|Gid|CapEff|CapPrm|NoNewPrivs):' /proc/self/status
EP
  sudo chown "$role:aifi45-$role" "/var/lib/aifi45/$role/entrypoint.sh" 2>/dev/null || sudo chown "aifi45-$role:aifi45-$role" "/var/lib/aifi45/$role/entrypoint.sh"
  sudo chown "aifi45-$role:aifi45-$role" "/var/lib/aifi45/$role/entrypoint.sh"
  sudo chmod 0700 "/var/lib/aifi45/$role/entrypoint.sh"
done
sudo ls -ln /var/lib/aifi45/worker/entrypoint.sh /var/lib/aifi45/reader/entrypoint.sh
