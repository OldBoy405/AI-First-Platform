#!/bin/bash
# Root-owned probe body. Write checks use access(2) via test -w so a privileged
# control run can show "ok" without modifying anything.
set -u
case "$(id -un)" in
  aifi45-worker) other=/var/lib/aifi45/reader ;;
  *)             other=/var/lib/aifi45/worker ;;
esac
r() { if "$@" >/dev/null 2>&1; then echo ok; else echo denied; fi; }
echo "PROBE identity user=$(id -un) uid=$(id -u) gid=$(id -g) groups=$(id -G)"
grep -E '^(Uid|Gid|CapEff|CapPrm|NoNewPrivs):' /proc/self/status | tr -s '\t' ' ' | sed 's/^/PROBE status /'
echo "PROBE cross_read $(r ls "$other")"
echo "PROBE write_launcher $(r test -w /usr/local/lib/aifi45/launch.sh)"
echo "PROBE write_entrypoint $(r test -w /usr/local/lib/aifi45/entrypoint.sh)"
echo "PROBE replace_entrypoint $(r test -w /usr/local/lib/aifi45)"
echo "PROBE sudo $(r sudo -n true)"
echo "PROBE setuid0 $(r python3 -c 'import os; os.setuid(0)')"
echo "PROBE own_root_write $(r sh -c 'echo ok > "$HOME/.probe" && rm -f "$HOME/.probe"')"
