# P0 隔离证明 — 方案 C 实测证据（2026-10-27）

> 环境：WSL2 Ubuntu，kernel `6.18.54.1-microsoft-standard-WSL2`，podman `5.8.5`。
> 身份与 launcher 由主会话经 WSL 直接创建并驱动（sudo 免密），全部输出为实跑。
> **结论（2026-10-27 复核后修正）**：worker↔reader 两身份互隔离 **10/10 PASS**，反向对照 4/4。
> **但对 agent 不成立**：Windows 用户 GOBAO 可 `wsl -u root` 免密，WSL `user` 在 wheel 且 `NOPASSWD: ALL`；
> agent 正是以 GOBAO 运行，所以它能改 launcher、读任一私有根、冒充任一身份。本证据**不能**解除 C 路径 block。
> **未覆盖**：auditd（内核支持，只是未安装）、容器 profile（本路径未用容器）、Windows 侧身份。

## 1. 受测对象（版本 pin）

| 项 | 值 |
|---|---|
| 两个受限身份 | `aifi45-worker` uid=995 gid=994；`aifi45-reader` uid=994 gid=993 |
| 私有根 | `/var/lib/aifi45/worker`（`drwx------ 995 994`）、`/var/lib/aifi45/reader`（`drwx------ 994 993`） |
| 父目录 | `/var/lib/aifi45` `drwxr-xr-x root root` |
| launcher | `/usr/local/lib/aifi45/launch.sh` `-rwxr-xr-x root root` 602 bytes，sha256 `5ef745f4579154aadaaa40ea8494cce4f6c080482c8c6b6bf8b57030b7b6fff5` |
| 内核 / 容器 | `6.18.54.1-microsoft-standard-WSL2` / podman `5.8.5` |

launcher 只接受 `--role worker|reader` 与 `--root /var/lib/aifi45/{worker,reader}`，其它入参 `exit 64`；
落地用 `setpriv --reuid --regid --clear-groups --no-new-privs` + `env -i`，再 exec 该私有根下的 `entrypoint.sh`。

## 2. 正向证明（每条都能 FAIL）

| # | 证明 | 方法 | 结果 |
|---|---|---|---|
| A | 身份真实且非特权 | launcher 内 `id -u` + `/proc/self/status` | **PASS**：`uid=995`、`Uid: 995 995 995 995`、`CapEff=0000000000000000`、`NoNewPrivs=1` |
| B | worker 不能读 reader 根 | `sudo -u aifi45-worker ls /var/lib/aifi45/reader` | **PASS**：Permission denied |
| B2 | reader 不能读 worker 根 | `sudo -u aifi45-reader ls /var/lib/aifi45/worker` | **PASS**：Permission denied |
| C | 低权写不了 launcher | `sudo -u aifi45-worker tee -a launch.sh` | **PASS**：Permission denied |
| D | 没有第二条启动路径 | shell / sudoers / setuid 三查 | **PASS**：`shell=/usr/sbin/nologin`、`sudo -l -U aifi45-worker` 无权限、私有根下 setuid 文件 0 个 |
| E | 不能提权 | worker 内 `sudo -n true` | **PASS**：不可用 |
| E2 | 不能 `setuid(0)` | worker 内 `python3 os.setuid(0)` | **PASS**：Operation not permitted |
| F | launcher 拒绝未知角色 | `--role root` | **PASS**：denied，`exit 64` |
| F2 | launcher 拒绝任意根 | `--root /etc` | **PASS**：denied |
| F3 | launcher 拒绝额外参数 | `--exec /bin/sh` | **PASS**：denied |

`RESULT pass=10 fail=0`

## 3. 反向对照（证明探针不是空转）

| # | 对照 | 结果 |
|---|---|---|
| N1 | root 能读 reader 根 | **读到了 `entrypoint.sh`** → B 有真实目标，不是「目录不存在所以拒绝」 |
| N2 | root 能写 launcher | **追加成功**，恢复后 sha256 与登记值一致（`5ef745f4…`） |
| N3 | 合法调用真的执行 | `--role reader` 输出 `uid=994 gid=993` → F 不是靠「全都拒绝」通过 |
| N4 | root 能冒充 worker | `sudo -u aifi45-worker id -u` → `995` |

## 4. 诚实披露（不满足项）

1. **更正：auditd 是没装，不是内核不支持**。初版写「WSL2 内核无 audit 子系统」是错的——当时用
   `ls /proc/self | grep audit`（loginuid 名字里不含 audit）和 `dpkg`（本机是 Fedora 44）检查，两个方法都无效。
   复核：`/proc/config.gz` 有 `CONFIG_AUDIT=y`、`CONFIG_AUDITSYSCALL=y`，`/proc/self/loginuid` 存在，PID1 为 systemd，
   包管理器为 dnf。可 `dnf install audit` 后补真实 execve 审计。在补上前，「launcher 外无第二条 execve」**无证据**；
   D 只证明 worker 身份自己没有 shell/sudo/setuid，不证明别人不能以它的身份启动进程。
2. **更正：「root 是信任锚」掩盖了真正的问题**。复核：`wsl.exe -u root -e id` → `uid=0`，无需口令；
   `user` 属 wheel，`%wheel ALL=(ALL) NOPASSWD: ALL`。agent 以 Windows 用户 GOBAO 运行，等同于 WSL root——
   本次身份、launcher 正是 agent 自己用 sudo 建的。设计里要防的是 agent，所以本证据只证明 worker/reader
   两身份之间的隔离，**不证明对 agent 的隔离**。要成立，agent 必须跑在拿不到 WSL root 的身份上（例如另一个
   不能启动该发行版的 Windows 用户，或另一台 VM）；本机现有配置做不到。
2b. **entrypoint 归各自身份所有（0700）**：worker 能改自己下次运行的代码。不算提权，但「以 worker 身份运行的是什么」
   没有被钉住，应改为 root:root 0755 并登记 sha256。
2c. B/B2/C/E 用 `sudo -u <身份>` 直接测身份权限，没有经过 launcher；经过 launcher 的只有 A、F、N3。
3. **未走容器**：本路径是宿主进程（runbook §5 允许）。因此镜像 digest / `--read-only` / `--cap-drop`
   这些容器级证明**未使用**；`podman images --digests` 已列出现存镜像 digest 备查，但不作为本次证据。
4. **Windows 侧未做**：现在没有第二个真实受限的 Windows 身份。这不是做不到，是还没建（需管理员 `net user` 建本地用户）。
   `isolation` label 的 win32 分支仍为 UNVERIFIED。
5. **隔离证明 ≠ `TestChannelIsolation`**：expectations 里的 `isolation` label 要求的是 5 条 Linux 探针
   （pidfd / `SO_PEERCRED` / 私有 socket / CLOEXEC / 拒 SCM_RIGHTS），那是**代码侧**证明，尚未实现（P0.1）。
   本文件证明的是**环境前提**：两个真身份、受审 launcher、私有根确实成立。

## 5. 复现方式

```bash
# 一次性环境（已在本次执行）
bash /tmp/setup.sh        # 建身份、私有根、launcher、entrypoint
bash /tmp/probe.sh        # 10 条正向证明
bash /tmp/negctl.sh       # 4 条反向对照
```

脚本原文随本文件归档于 `validation/p0-probe-scripts/`。
