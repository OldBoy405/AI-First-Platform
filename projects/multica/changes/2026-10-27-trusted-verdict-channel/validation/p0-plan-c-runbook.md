# P0 隔离证明 — 方案 C 落地步骤（需人工执行）

> 目标：证明「两个**真实受限**身份下，worker 无法读取/改写它不该碰的东西」，并把这份证明作为
> C 路径切片（M-S2 daemon trust、S3/S4 worker、S6 client、S7 composition、S8 observer）的前置。
> 本文件只写**你要做的动作**与**我要核对的证据**；我没法替你创建系统身份、也无法自证隔离成立。

## 0. 现状（我这边已核实）

- Windows 本地只有 `GOBAO` / `Administrator` / `CodexSandbox*` / `Guest`，**没有两个可用的受限身份**；
  `Guest` 默认禁用且不适用于服务进程 → Windows 本机不能作为 P0 的证明环境。
- WSL Ubuntu 可用，`podman 5.8.3` / `docker 5.8.5` 已装，但**没有批准的 launcher/profile**，也没有
  两个真实 UID 的受审 launcher。→ 现有容器都是 rootful/默认 profile，不能当证据。

## 1. 你需要提供的东西（一次性，之后我全部复用）

按重要性排序。**第 1–4 项缺任何一项，方案 C 都无法成立**。

| # | 项 | 具体要求 | 我拿它做什么 |
|---|---|---|---|
| 1 | **两个真实受限 UID** | 在 WSL 里建两个普通用户（非 root、非 sudoers）：`aifi45-worker`（跑 worker）、`aifi45-reader`（跑 reader/observer）。给出 UID/GID。 | 用它们分别跑进程；证据里记录 `id -u` 与 `/proc/self/status` 的 `Uid:` |
| 2 | **受审 launcher** | 一个**固定路径、root 拥有、mode 0755、不可被 worker 写**的脚本，例如 `/usr/local/lib/aifi45/launch.sh`；只接受白名单参数（`--role worker|reader`、`--root <私有根>`），拒绝其它入参，用 `exec setpriv --reuid --regid --clear-groups` 降权后启动。 | 它是「谁能以什么身份跑什么」的唯一入口；证据核 sha256 + 所有权 + mode |
| 3 | **私有根目录** | 每角色一个，例如 `/var/lib/aifi45/worker`、`/var/lib/aifi45/reader`；owner 为该 UID、mode 0700，父目录 root 拥有。 | 用来证明交叉不可读写（worker 读不到 reader 根、反之亦然） |
| 4 | **容器 profile（如走容器）** | `podman` 的 approved profile 文件（rootless + `--userns=keep-id` 或显式 `--uidmap`），注明镜像 digest（`sha256:…`，不用 tag）、`--read-only`、`--cap-drop=ALL`、`--security-opt no-new-privileges`、私有根 bind mount。 | 证据里要核镜像 digest 与 profile 内容，防止「跑的是另一个镜像」 |
| 5 | 审计开关 | `auditd` 已装并记录 `execve`（或等价 eBPF），给出确认命令与输出 | 证明「launcher 之外没有第二条启动路径」 |
| 6 | 版本 pin | `podman --version`、内核版本、镜像 digest | 写进证据头，防漂移 |

**不需要你做的**：不用你写测试、不用你判断隔离是否成立——那是我的活。你只要把上面 6 项准备好并告诉我路径/UID/digest。

## 2. 你执行的具体命令（可直接粘）

以下都在 WSL 里跑；`sudo` 一次建身份，之后不再需要 root。

```bash
# 2.1 两个受限身份（无 sudo、无 login shell 亦可）
sudo useradd --system --create-home --home-dir /var/lib/aifi45/worker --shell /usr/sbin/nologin aifi45-worker
sudo useradd --system --create-home --home-dir /var/lib/aifi45/reader --shell /usr/sbin/nologin aifi45-reader
id aifi45-worker; id aifi45-reader

# 2.2 私有根
sudo install -d -o aifi45-worker -g aifi45-worker -m 0700 /var/lib/aifi45/worker
sudo install -d -o aifi45-reader -g aifi45-reader -m 0700 /var/lib/aifi45/reader
sudo ls -ldn /var/lib/aifi45/worker /var/lib/aifi45/reader

# 2.3 受审 launcher（root 拥有、0755、拒绝未知参数）
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
case "$role" in worker) uid=aifi45-worker;; reader) uid=aifi45-reader;; *) echo "denied: role" >&2; exit 64;; esac
exec setpriv --reuid="$uid" --regid="$uid" --clear-groups --no-new-privs \
  env -i PATH=/usr/bin:/bin HOME="$root" "$root/entrypoint.sh"
SH
sudo chown root:root /usr/local/lib/aifi45/launch.sh
sudo chmod 0755 /usr/local/lib/aifi45/launch.sh
sha256sum /usr/local/lib/aifi45/launch.sh

# 2.4 审计（若未装：sudo apt-get install -y auditd）
sudo systemctl enable --now auditd
sudo auditctl -l | head

# 2.5 版本 pin
podman --version; uname -r
```

**把 2.1–2.5 的输出贴给我**（尤其 `id`、`ls -ldn`、`sha256sum`、`podman --version`）。

若是走容器而非宿主进程，另加第 4 项 profile，例如：

```bash
# 2.6 容器 profile（rootless，镜像用 digest 而不是 tag）
podman pull --quiet quay.io/<org>/<image>@sha256:<digest>
podman run --rm --read-only --cap-drop=ALL --security-opt no-new-privileges \
  --userns=keep-id --volume /var/lib/aifi45/worker:/work:rw,Z \
  quay.io/<org>/<image>@sha256:<digest> id
```

## 3. 我要跑的验证（你不用动）

拿到上面信息后，我做这几条并出证据（每条都要能 FAIL，不是走过场）：

| 证明 | 方法 | 失败判定 |
|---|---|---|
| 身份真实 | 在 launcher 里 `id -u` + `/proc/self/status` 的 `Uid:`/`Gid:` | 出现 uid 0 或与登记值不符 |
| 交叉不可读 | worker 读 `/var/lib/aifi45/reader/*`、reader 读 worker 根 | 任一读成功 |
| 不可改 launcher | worker 尝试写 `/usr/local/lib/aifi45/launch.sh` | 写成功 |
| 没有第二条路径 | 审计日志里除 launcher 外的 `execve`（同 uid） | 出现未登记的启动 |
| 降权不可逆 | 进程内 `setuid(0)` 尝试失败 | 成功提权 |
| 无新权限 | `no_new_privs` 生效、`CapEff=0` | 任一不满足 |
| 镜像不被替换 | 运行时 `podman inspect` digest == 登记值 | 不一致 |

结果写进 `validation/p0-isolation-evidence.md`，含每条的原始命令与输出；任一条不满足 → 该证明记 **FAILED**，
C 路径切片继续 block，不得用「看起来像」替代。

## 4. 拿到之后我做什么

1. 把 6 项信息登记为 profile（`channel-component` v1 之外的 **isolation profile**），sha256 入证据；
2. 跑 `TestChannelIsolation`（expectations 里的 `isolation` label，playforms.linux 分支）；
3. 通过后解除 C 路径片的 block：M-S2 daemon trust → S3/S4 → S6 → S7 → S8；
4. Gate 3 报告里 `isolation` 从 UNVERIFIED 改成实际结果，其余未做项照旧如实列。

## 5. 如果你不想走容器

纯宿主进程也能满足 P0，只要满足：两个非 root UID、launcher 固定且不可被低权写、私有根 0700、
审计可查。此时第 4 项（容器 profile）可省，但第 1–3、5、6 项仍是必需的。

## 6. 常见坑（先提醒）

- **别用 `sudo -u` 当 launcher**：它允许任意命令，等于没有受审入口，审计也糊。
- **别用同一个 UID 跑 worker 与 reader**：隔离变成形式，交叉读取永远通过。
- **别用 tag 引用镜像**：`latest` 一漂移，昨天的证据今天不成立。
- **别在 `/tmp` 建私有根**：默认 `1777`，交叉读取直接成立。
- **WSL 的 `/mnt/c` 不要放私有根**：DrvFs 没有 POSIX 权限语义，0700 不生效。
