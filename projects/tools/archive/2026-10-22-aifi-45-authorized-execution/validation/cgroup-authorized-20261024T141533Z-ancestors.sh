#!/bin/sh
# Read-only hierarchy/privilege checks, not controller or configuration changes.
set -u
printf 'sudo_noninteractive='; if sudo -n true 2>/dev/null; then printf 'available\n'; else printf 'unavailable\n'; fi
for unit in -- -.slice user.slice "user-$(id -u).slice"; do
  [ "$unit" = -- ] && continue
  printf '\nunit=%s\n' "$unit"
  systemctl show -- "$unit" -p ControlGroup -p DisableControllers -p CPUAccounting -p MemoryAccounting -p TasksAccounting
  printf '[exit=%s]\n' "$?"
done
for directory in /sys/fs/cgroup /sys/fs/cgroup/non-systemd /sys/fs/cgroup/non-systemd/user.slice "/sys/fs/cgroup/non-systemd/user.slice/user-$(id -u).slice" "/sys/fs/cgroup/non-systemd/user.slice/user-$(id -u).slice/user@$(id -u).service"; do
  [ -d "$directory" ] || continue
  printf '\npath=%s\n' "$directory"
  stat -c 'mode=%a uid=%u gid=%g' "$directory"
  for field in cgroup.type cgroup.controllers cgroup.subtree_control; do
    [ -r "$directory/$field" ] || continue
    printf '%s=' "$field"; IFS= read -r value < "$directory/$field"; printf '%s\n' "$value"
  done
  if [ -r "$directory/cgroup.procs" ]; then printf 'direct_processes='; awk 'END {print NR}' "$directory/cgroup.procs"; fi
done
printf '\nconfig_file_permissions\n'
for file in /etc/containers/containers.conf /etc/wsl.conf /etc/systemd/system/user@.service.d/delegate.conf; do
  [ -f "$file" ] && stat -c '%n mode=%a uid=%u gid=%g' "$file"
done
printf '\npython3='; command -v python3 || true
printf 'install='; command -v install || true
