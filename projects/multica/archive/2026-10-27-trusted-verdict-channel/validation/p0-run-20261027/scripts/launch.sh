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
  worker) uid=aifi45-worker; want=/var/lib/aifi45/worker ;;
  reader) uid=aifi45-reader; want=/var/lib/aifi45/reader ;;
  *) echo "denied: role" >&2; exit 64 ;;
esac
[ "$root" = "$want" ] || { echo "denied: root" >&2; exit 64; }
exec setpriv --reuid="$uid" --regid="$uid" --clear-groups --no-new-privs \
  env -i PATH=/usr/bin:/bin HOME="$root" /usr/local/lib/aifi45/entrypoint.sh
