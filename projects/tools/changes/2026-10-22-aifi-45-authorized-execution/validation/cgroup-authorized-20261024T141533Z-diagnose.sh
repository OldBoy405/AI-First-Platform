#!/bin/sh
# Read-only diagnostics. Do not print environment, tokens, full configs or logs.
set -u
section() { printf '\n=== %s ===\n' "$1"; }
run() { "$@"; result=$?; printf '[exit=%s]\n' "$result"; }
section identity
run id -u
run id -g
printf 'pid1='; IFS= read -r value < /proc/1/comm; printf '%s\n' "$value"
printf 'cgroup='; while IFS= read -r value; do printf '%s\n' "$value"; done < /proc/self/cgroup
for variable in XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
  case "$variable" in
    XDG_RUNTIME_DIR) value=${XDG_RUNTIME_DIR-} ;;
    DBUS_SESSION_BUS_ADDRESS) value=${DBUS_SESSION_BUS_ADDRESS-} ;;
  esac
  if [ -n "$value" ]; then printf '%s=present\n' "$variable"; else printf '%s=absent\n' "$variable"; fi
done
section user-manager
run loginctl show-user "$(id -u)" -p State -p Linger -p Sessions -p RuntimePath
run systemctl show "user@$(id -u).service" -p ActiveState -p SubState -p MainPID -p ControlGroup -p Delegate -p DelegateControllers -p FragmentPath -p DropInPaths
run systemctl --user show default.target -p ActiveState -p SubState
section podman-api-units
run systemctl --user show podman.service -p ActiveState -p SubState -p MainPID -p ControlGroup -p KillMode -p FragmentPath -p DropInPaths
run systemctl --user show podman.socket -p ActiveState -p SubState -p Listen -p FragmentPath -p DropInPaths
section podman-processes
run ps -C podman -o pid,comm,cgroup --no-headers
section cgroup-ancestors
usercg=$(systemctl show "user@$(id -u).service" -p ControlGroup --value 2>/dev/null)
for directory in /sys/fs/cgroup /sys/fs/cgroup/non-systemd /sys/fs/cgroup/user.slice "/sys/fs/cgroup/user.slice/user-$(id -u).slice" "/sys/fs/cgroup${usercg}"; do
  [ -d "$directory" ] || continue
  printf '%s\n' "$directory"
  run stat -c 'mode=%a uid=%u gid=%g' "$directory"
  for field in cgroup.controllers cgroup.subtree_control; do
    [ -r "$directory/$field" ] || continue
    printf '%s=' "$field"; IFS= read -r value < "$directory/$field"; printf '%s\n' "$value"
  done
done
section configuration-sources
for directory in /usr/share/containers /etc/containers "$HOME/.config/containers"; do
  for file in "$directory/containers.conf" "$directory"/containers.conf.d/*.conf; do
    [ -f "$file" ] || continue
    printf 'config=%s\n' "$file"
    awk '/^[[:space:]]*cgroup_manager[[:space:]]*=/ { if ($0 ~ /"systemd"/) print "cgroup_manager=systemd"; else if ($0 ~ /"cgroupfs"/) print "cgroup_manager=cgroupfs"; else print "cgroup_manager=other" }' "$file"
  done
done
section native-current-manager
run podman info --format '{{.Host.CgroupManager}} {{json .Host.CgroupControllers}}'
section native-systemd-parameter-only
run podman --cgroup-manager=systemd info --format '{{.Host.CgroupManager}} {{json .Host.CgroupControllers}}'
section wsl-boot-config
if [ -r /etc/wsl.conf ]; then awk '/^\[boot\]/{boot=1;next} /^\[/{boot=0} boot && /^[[:space:]]*systemd[[:space:]]*=/ {if ($0 ~ /true/) print "systemd=true"; else print "systemd=other"}' /etc/wsl.conf; fi
