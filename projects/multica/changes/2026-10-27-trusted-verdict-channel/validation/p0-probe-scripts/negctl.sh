#!/bin/bash
set -uo pipefail
LAUNCH=/usr/local/lib/aifi45/launch.sh
echo "### N1 root CAN read the reader root (proves B is not vacuous)"
sudo -n ls /var/lib/aifi45/reader && echo "N1 OK: root read succeeded -> B has a real target"

echo
echo "### N2 root CAN write the launcher (proves C is not vacuous)"
sudo -n cp "$LAUNCH" /tmp/launch.bak
printf '\n# probe\n' | sudo -n tee -a "$LAUNCH" >/dev/null && echo "N2 OK: root append succeeded"
sudo -n cp /tmp/launch.bak "$LAUNCH" && sudo -n chown root:root "$LAUNCH" && sudo -n chmod 0755 "$LAUNCH"
sha256sum "$LAUNCH"

echo
echo "### N3 the allowed invocation really runs (proves F is not vacuous)"
sudo -n "$LAUNCH" --role reader --root /var/lib/aifi45/reader | head -2

echo
echo "### N4 a same-uid process can be started by root (discloses the trust boundary)"
sudo -n -u aifi45-worker id -u && echo "N4: root CAN impersonate the worker -> root is the trust anchor, not part of the isolation claim"
