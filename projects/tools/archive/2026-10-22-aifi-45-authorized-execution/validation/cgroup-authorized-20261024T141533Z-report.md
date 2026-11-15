# rootless cgroup 配置授权后预检与重启边界

## 当前结论

用户已明确授权“配置当前 Podman/WSL 的 rootless cgroup 委派／管理器”。该授权不再重复索取；但上轮承诺的 **VM 重启单独确认**仍有效，本轮未获重启窗口许可。

**尚未修复、不算隔离 PASS。** 已完成故障定位、真实参数试验、私有备份和服务保护检查；未修改生效配置、未启用控制器、未移动上游进程、未切 rootful、未重启或停止现有服务。根权限仅用于虚拟机内配置文件的私有恢复副本，没有运行 rootful Podman。

## 已实证的根因与排除项

- 当前环境仍 rootless、cgroup v2、cgroupfs，实际 delegated controllers=[]。
- systemd PID1 和 user manager 已运行；Linger=yes，user@1000.service 的 Delegate=yes、DelegateControllers=cpu/io/memory/pids。但它们是声明，不是控制器实际可用性证明。
- `/sys/fs/cgroup` 有 cpu/memory/pids 等控制器，但 subtree_control 为空；`/non-systemd` 及至 user@1000.service 的祖先节点 controllers/subtree_control 均为空。
- `/non-systemd` 是 domain cgroup；cgroup.procs 有9条记录，均为0，在当前 PID namespace 中无法映射成可操作进程。不能因 `/proc/0` 不存在便当作“没有进程”。没有进入其他 PID namespace 或尝试迁移这些上游进程。
- Linux cgroup v2 的 No Internal Process Constraint 要求非根 domain cgroup 没有直属进程才能向子层分配 domain controller。因此不采用盲目改全局根节点、搬移不明进程或变更其他 WSL 分发版的在线绕行。
- 仅通过原生参数 `podman --cgroup-manager=systemd` 测试，不落盘配置：锁定 Alpine 本地镜像，指定64MiB/0.25CPU/16pids，无网络/host挂载/凭据、UID1000、只读rootfs、cap-drop/no-new-privileges。create exit0，真实 start **exit125**，仍报 `memory.max` 不存在。故仅换管理器不能证明或解决本机的上游委派缺口。
- 该探针按随机 nonce label 核所有权后精确 rm，exit0；exists exit1，已不存在。不是业务 TC 的 RED/GREEN。

内核依据：[No Internal Process Constraint](https://docs.kernel.org/admin-guide/cgroup-v2.html#no-internal-process-constraint)。此前存在启用 WSL `systemd=true` 后 Podman API pipe 不可用的环境记录；其具体原因本轮没有证明，不将网络搜索摘要当作已确认根因，也不保证直接重启即可解决。

## 私有恢复准备

已用与 Podman API 无关的原生 `wsl.exe --distribution podman-machine-default --user root --exec python3 -` 成功访问当前 distro 并制作配置副本：

- 目录：`/var/lib/aifi45-config-backups/cgroup-20261024-62ab7fcac54c4125b8ce796f093f5682`，root-owned 0700；副本及 manifest 为0600。
- `/etc/wsl.conf`：`8a037d60c1eabd07cd092bca5f0e1a6ec2e9649a0eb8574e750cc7053bc9da47`
- `/etc/containers/containers.conf`：`591b680ca69ad912f8fd264c095f309ef32f78920fef69228729dd497c72c9c6`
- `/etc/systemd/system/user@.service.d/delegate.conf`：`fa504d2bb2e3c2f09e625328fbadac756a25c43ae4266acd9913a8ef82bcfefc`

没有把配置原文、环境变量或凭据带入记录；没有修改活跃配置。后续回退须按备份及实际应用后的摘要对照，不覆盖并发的人类配置变更。原生 WSL 入口当前可用，不据此保证任何启动故障下都必然可恢复。

## 重启影响与后续受控方案（尚未执行）

需要单独批准的下一步是 **当前 Podman WSL 虚拟机的维护窗口**，不是 `wsl --shutdown` 全局停机，也不是新建/删除机器：

1. 取得窗口后，先重新核服务/卷与专用测试库身份，按既有单执行者规则保存专用库当前 ID+内容摘要；不访问共享库的 SQL/凭据。
2. 优先 backend，再 PostgreSQL，按已核验原始 container ID 温和停止，保留所有卷和容器，不 rm/recreate/prune。
3. 做最小且可回退的 WSL 启动层及 rootless 管理器配置；对已知 API pipe 风险建立启动检查和回退条件，不盲目重复旧方案。
4. 仅重启 `podman-machine-default`。若 API 异常，优先经原生 WSL 入口恢复配置并回退；可能需要第二次本机重启。若无法安全恢复，停止并报告，不切 rootful、不操作其他 distro、不删除 VM/数据卷。
5. 通过原始 ID 恢复两库、backend；核专用库摘要及服务状态，然后做真实 kernel cpu.max/memory.max/pids.max 正例和受限行为验证。HostConfig、Delegate声明或start成功本身均不是完整的强制执行证明。

当前3个受影响容器都在持续运行，StartedAt 均早于本轮预检，未重启：

| 容器 | 原始 ID | 数据卷 |
|---|---|---|
| multica-postgres | `96211305e92b4ec8a686b5f774cac92e960b86ce14acaa40eb8c1201e993e01f` | 原有 PostgreSQL data volume，保持 |
| stdd-aifi45-20261022-pg | `666bfec52ac3c3d13b43389891f50c4105833198eab7e4167b76f014a774e823` | 原有 PostgreSQL data volume，保持 |
| multica-backend | `01050b2499847e72b06cb5d84b8ec2945dc75045842544a65caf550ef573a762` | 不重建 |

详见 `cgroup-authorized-20261024T141533Z-checkpoint.json`。本轮没有执行任何 DB SQL，因此不将前轮83条历史与锁/session快照冒称为本轮实时 DB 验证。

## 证据与口径

同前缀的 `-before.json`、`-diagnose.{sh,stdout.log,stderr.log,meta.json}`、`-ancestors.{sh,stdout.log,stderr.log}`、`-systemd-canary.{py,stdout.json,stderr.log,meta.json}`、`-boot-readonly*.{py,json,log}`、`-backup.{py,stdout.json,stderr.log,meta.json}`、`-checkpoint.json` 保留原始诊断和返回值。

一次 namespace 诊断因 `/proc/1/ns/cgroup` 读取权限失败，后续明确记为 unknown；一次 metadata inspect 的 `.Id` Go template 字段不可用，改用 `.ID` 成功。两者都不是产品缺陷、业务 RED 或修复成功证据。当前 task/component 进度不扩张：业务 TC仍0/49、5 major未关闭、消费关闭、BUILD/in_progress，无 Gate3/commit/push/生产试点。
