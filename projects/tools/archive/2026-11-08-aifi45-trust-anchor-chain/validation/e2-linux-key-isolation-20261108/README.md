# E2 — Linux 内核拒绝 agent 覆盖验签公钥

**结论：PASS。** 在 WSL2 Ubuntu 24.04 的 ext4 根文件系统上，服务方 `aifi-svc`（uid 1500）安装 Ed25519 验签公钥；`aifi-agent`（uid 1501）用 overwrite、rename/replace、append 三种真实操作尝试覆盖，三次都被内核以 `Permission denied`（EACCES 语义）拒绝，退出码均非 0。尝试前后公钥 SHA-256 完全一致，inode/大小/mode/owner 也未变。

- 真实运行输出（未编辑）：`probe.stdout.txt`
- 可复跑脚本：`probe.sh`
- 运行时间：`2026-11-08T14:30:50Z`
- 环境：`Linux 6.18.54.1-microsoft-standard-WSL2 x86_64`，`Ubuntu 24.04.3 LTS`
- 运行方式：root 仅负责建目录、抓哈希、清理；安装与攻击分别由 1500 / 1501 执行，未使用 sudo。

### 结论表

| 项目 | 真实结果 |
|---|---|
| 服务方 uid（`aifi-svc`） | **1500** |
| agent uid（`aifi-agent`） | **1501** |
| overwrite | exit **2**；stderr `Permission denied`；**DENIED** |
| replace / rename | exit **1**；stderr `Permission denied`；**DENIED** |
| append | exit **2**；stderr `Permission denied`；**DENIED** |
| SHA-256 before | `a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92` |
| SHA-256 after | `a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92` |
| SHA-256 相同 | **yes** |
| inode before / after | **5189 / 5189** |
| agent 读同一锚（正对照） | exit **0**；读到同一 SHA-256；**OK** |

---

## 1. 权限方案与理由

本次运行的实际目录树（临时路径，运行结束已删除）：

```text
/var/lib/aifi-e2-probe.tuyQ4Z/                      root:root          0755
└── trustroot/                                       aifi-svc:aifi-svc  0755
    └── aifi-release.ed25519.pub                     aifi-svc:aifi-svc  0644  (113 bytes)
```

`probe.stdout.txt` 中的 `stat` 原文：

```text
mode=755 owner=root:root uid=0 gid=0 inode=903 size=4096 path=/var/lib/aifi-e2-probe.tuyQ4Z
mode=755 owner=aifi-svc:aifi-svc uid=1500 gid=1500 inode=3440 size=4096 path=/var/lib/aifi-e2-probe.tuyQ4Z/trustroot
mode=644 owner=aifi-svc:aifi-svc uid=1500 gid=1500 inode=5189 size=113 path=/var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub
```

### 为什么选 0755 目录 + 0644 文件，而不是 0700/0600

- **验签需要读公钥。** agent 必须以 1501 身份读取 trust root 中的公钥才能验签，所以目录至少要有 `r-x`、文件要有 `r--`。选 `0700`/`0600` 会把读也一并拒绝，验签流程不成立，而且会让“拒绝写”与“根本没有访问权”混在一起，证据不精确。
- **最小权限：只给读，不给写。** `0755` 目录的 owner 是 1500，agent 落在 other 位，只有 `r-x`，没有目录写权限，因此不能在目录里创建、删除、rename 条目；`0644` 文件的 agent 只有 `r--`，不能以写方式 open，因此不能 overwrite/append。
- **两层边界。** `trustroot` 由 1500 拥有（服务方可以轮换公钥），其父目录由 root 拥有且 0755（agent 不能把整个 trustroot 目录换掉；连 1500 也不能，只有 root 能移动/替换 trust root 容器）。这符合“root 决定 trust root 位置、服务方维护锚内容、agent 只读”的分工。
- **不用 `chattr +i`。** 本次只用标准 DAC（owner/mode）就足以拒绝 agent；`+i` 是额外的 root-only 机制，且依赖文件系统支持，没必要引入。
- **不是同 UID 权限位冒充。** 安装与三次尝试分别真实运行在 1500 和 1501；每次 attempt 的 stdout 里都打印了 `id -u` 的结果 `1501`，安装的 stdout 打印 `1500`。
- 公钥是公开材料，0644 可读没有问题；私钥只在内存中生成，从未落盘。

---

## 2. 三次尝试：真实退出码与 stderr 原文

| # | 尝试 | 具体操作 | 真实退出码 | stderr 判定 | 结果 |
|---|------|----------|-----------|-------------|------|
| 1 | overwrite | `printf ... > "$KEY"`，即 `O_WRONLY\|O_CREAT\|O_TRUNC` | **2** | `Permission denied` | **DENIED** |
| 2 | replace（rename/替换 inode） | agent 先生成自己的 Ed25519 公钥，再 `mv -f attacker.pub "$KEY"`；源/目标 device 均为 2112，同文件系统，走 `rename(2)` | **1** | `Permission denied` | **DENIED** |
| 3 | append | `printf ... >> "$KEY"`，即 `O_WRONLY\|O_APPEND` | **2** | `Permission denied` | **DENIED** |

### 1/3 overwrite

```text
=== [overwrite] overwrite in place via shell redirection (O_WRONLY|O_CREAT|O_TRUNC) ===
runner: aifi-agent (uid 1501)
exit_code=2
--- stdout ---
1501
--- stderr ---
sh: 1: cannot create /var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub: Permission denied
--- end ---
```

### 2/3 replace / rename

agent 在自己的 0700 staging 目录中真实生成了一份 Ed25519 公钥（`attacker_keygen_exit_code=0`，stdout `uid=1501`），然后尝试 rename 覆盖：

```text
=== [replace] replace inode via rename (mv -f attacker.pub over trust anchor) ===
runner: aifi-agent (uid 1501)
exit_code=1
--- stdout ---
1501
--- stderr ---
mv: cannot move '/var/tmp/aifi-e2-agent.5bQIao/attacker.ed25519.pub' to '/var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub': Permission denied
--- end ---
```

同一文件系统的证据（避免把跨设备 copy 回退误当成 rename）：

```text
replace_fs_device: source=2112 target=2112
```

### 3/3 append

```text
=== [append] append via shell redirection (O_WRONLY|O_APPEND) ===
runner: aifi-agent (uid 1501)
exit_code=2
--- stdout ---
1501
--- stderr ---
sh: 1: cannot create /var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub: Permission denied
--- end ---
```

> 说明：执行器是 Ubuntu 的 `/bin/sh` → dash，所以前缀是 `sh: 1:`；dash 对 append 的打开失败也报 `cannot create`，这是真实的库/ shell 文案。判定依据是真实退出码 + stderr 文本，不是模式位推断。`Permission denied` 是 EACCES 的用户态文本；本次没有用 strace 抓数值 errno，README 不把数值 errno 当作证据。

---

## 3. 覆盖前后 SHA-256 原文

```text
=== [state] before attempts ===
a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92  /var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub
inode=5189 size=113 mode=644 owner=aifi-svc:aifi-svc

=== [state] after attempts ===
a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92  /var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub
inode=5189 size=113 mode=644 owner=aifi-svc:aifi-svc
```

汇总行原文：

```text
sha256_before=a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92
sha256_after=a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92
sha256_equal=yes
inode_before=5189 inode_after=5189 inode_equal=yes
metadata_equal=yes
```

> 每次复跑都会生成新的临时 Ed25519 密钥，因此不同次运行的 SHA-256 会不同；证据要求的是**同一次运行内** before/after 相等。本次运行的上述两个哈希完全相同，inode 也相同。

---

## 4. 两个真实 uid 的原文

```text
# 服务方
$ runuser -u aifi-svc -- id -u
1500

# agent
$ runuser -u aifi-agent -- id -u
1501
```

完整身份与所属组：

```text
service_identity: aifi-svc uid=1500
agent_identity:   aifi-agent uid=1501
service_full_id:  uid=1500(aifi-svc) gid=1500(aifi-svc) groups=1500(aifi-svc)
agent_full_id:    uid=1501(aifi-agent) gid=1501(aifi-agent) groups=1501(aifi-agent)
```

安装公钥时 stdout 的真实 `id -u`（由 1500 执行）：

```text
--- stdout ---
1500
```

三次 attempt 的 stdout 真实 `id -u`（由 1501 执行）：

```text
1501
```

汇总行：

```text
uid_service=1500
uid_agent=1501
uids_distinct=yes
```

### 读权限正对照

为了排除“agent 根本没有访问权，所以写失败”的歧义，脚本还让 agent 读取同一文件并计算哈希：

```text
=== [control] agent reads the same anchor (expected: success) ===
exit_code=0
--- stdout ---
1501
a981a58dd1fc2d7080efb1289e8a1a05a6380deb74d61f8f39c05ccaea331b92  /var/lib/aifi-e2-probe.tuyQ4Z/trustroot/aifi-release.ed25519.pub
```

agent 能读到同一 SHA-256，说明 0755/0644 的方案是“可读不可写”，不是“完全不可访问”。

---

## 5. 复跑方式

在 Windows 侧（Git Bash）执行，root 仅用于 orchestration，临时目录会在脚本退出时删除。建议把复跑输出写到新文件，避免覆盖本次冻结的 `probe.stdout.txt`（每次都会生成新密钥，SHA-256 会不同）：

```sh
cd "/c/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-11-08-aifi45-trust-anchor-chain/validation/e2-linux-key-isolation-20261108"
wsl -d AIFI-ISO -u root -- sh -c 'cd "/mnt/c/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-11-08-aifi45-trust-anchor-chain/validation/e2-linux-key-isolation-20261108" && sh ./probe.sh' > probe.rerun.stdout.txt
```

脚本设置 `LC_ALL=C`，因此 stderr 固定为英文，判定不受 locale 影响。

脚本自包含：`mktemp` 建立 `/var/lib/aifi-e2-probe.XXXXXX` 与 `/var/tmp/aifi-e2-agent.XXXXXX`，由 1500 生成并安装 Ed25519 公钥，1501 执行三次覆盖，抓取 before/after SHA-256 与 `stat`，最后在 EXIT trap 中清理。`probe.stdout.txt` 是用同一命令、输出到该文件时产生的真实运行原样 stdout；复跑请用上面的 `probe.rerun.stdout.txt`。本次运行 stderr 为空。

清理后的真实检查：

```text
=== cleanup ===
removed: /var/lib/aifi-e2-probe.tuyQ4Z
removed: /var/tmp/aifi-e2-agent.5bQIao
cleanup_check: both paths absent
```

---

## 6. 边界（必须连同结论一起读）

### 6.1 本地第二身份 ≠ 生产隔离

`aifi-svc`（1500）和 `aifi-agent`（1501）只是**同一个 WSL2 Linux 实例里的两个本地 UID**。它们共享同一个内核、同一个根文件系统、同一个 PID/挂载/网络命名空间；root 可以绕过 DAC；这不是容器、VM、主机或租户边界，也不是生产上的服务方/agent 身份。证据只能说明“在这个本地 ext4 根文件系统上，DAC 对这三个写操作拒绝了 1501”，不能说明生产部署（独立容器/主机、seccomp、capabilities、mount namespace、只读根、KMS/HSM 等）也有同样的隔离强度。

### 6.2 Windows 未验证

本次探针运行在 WSL2 的 Linux ext4 根文件系统（`/var/lib`、`/var/tmp`，device 2112）。**没有验证** Windows NTFS ACL、DrvFs `/mnt/c`（本环境中为 0777）、Windows 服务账户、跨 OS 路径访问或 Windows 侧的 trust store。不能把本结论外推到 Windows。

### 6.3 未覆盖的攻击面

本次只验证 overwrite、rename/replace inode、append 三种写原语。未测试：root/特权进程、`CAP_DAC_OVERRIDE`、`open_by_handle_at`、内核漏洞、ACL/`chattr +i`/其他文件系统、硬链接/符号链接组合攻击、密钥轮换流程、供应链与运行时完整性。公钥是每次运行新生成的临时测试密钥，私钥从未落盘；没有使用生产密钥材料。

---

## 7. 一句话结论

- **能支持：** 在本次 WSL2 Ubuntu 24.04 ext4 环境中，对 owner=1500、目录 0755/文件 0644 的 trust root，uid 1501 的 agent 通过 overwrite、rename/replace、append 三种真实操作均被内核以 `Permission denied`（EACCES）拒绝，退出码非 0，且公钥 SHA-256、inode 和元数据前后一致。
- **不能支持：** 它不能证明生产环境（独立容器/主机、Windows ACL、root/特权或内核级攻击、其他文件系统/内核版本）的隔离，也不能替代对 trust root 供应链、密钥轮换和运行时完整性的验证。
