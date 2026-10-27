# P0 隔离证明 — 方案 C 实测证据（2026-10-27）

> 环境：WSL2 Ubuntu，kernel `6.18.54.1-microsoft-standard-WSL2`，podman `5.8.5`。
> 身份与 launcher 由主会话经 WSL 直接创建并驱动（sudo 免密），全部输出为实跑。
> **结论**：宿主进程路径的隔离证明 **10/10 PASS**，反向对照 4/4 通过（证明探针不是空转）。
> **未覆盖**：auditd（WSL2 内核无 audit 支持）、容器 profile（本路径未使用容器）、Windows 侧。

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

1. **auditd 不可用**：`auditctl` 未安装，`/proc/self` 无 audit 相关项，WSL2 内核不带 audit 子系统。
   因此「launcher 之外没有第二条 execve」这一条**没有审计证据**，替代证据是 D（nologin + 无 sudoers +
   无 setuid）+ launcher 参数白名单。
2. **root 是信任锚，不在隔离声明内**：N4 显示任何 root 都能以 worker 身份起进程。本证明的范围是
   「worker/reader 两个身份之间、以及它们对 launcher/私有根」，不是「root 也受限」。
3. **未走容器**：本路径是宿主进程（runbook §5 允许）。因此镜像 digest / `--read-only` / `--cap-drop`
   这些容器级证明**未使用**；`podman images --digests` 已列出现存镜像 digest 备查，但不作为本次证据。
4. **Windows 侧未做**：Windows 只有 GOBAO/Administrator/CodeSandbox 等，无第二个真实受限身份（见 runbook §0）。
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
