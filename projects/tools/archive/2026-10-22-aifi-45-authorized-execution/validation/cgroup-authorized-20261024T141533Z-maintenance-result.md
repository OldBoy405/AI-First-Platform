# rootless cgroup 委派：维护窗口执行结果

用户已授权配置 rootless cgroup 委派／管理器，并授权维护窗口（含重启 `podman-machine-default` 及必要回退重启）。本节记录实际执行与结果，不把请求值、`Delegate=` 声明或容器创建成功当作强制执行的证明。

## 结论

**内核资源限额现已真实强制。** 生产形态路径（默认 `cgroup_manager=cgroupfs`，即 `/etc/containers/containers.conf` 现值）下取得三项独立证据：

| 限额 | 请求 | 内核侧观测 | 行为证据 |
|---|---|---|---|
| CPU | `--cpus=0.25` | `cpu.max=25000 100000` | 限额文件由内核落定 |
| 内存（负例） | `--memory=32m` | `memory.max=33554432` | 写 200MiB 时容器被 **SIGKILL（exit 137）** |
| 内存（正例对照） | `--memory=512m` | `memory.max=536870912` | 同一写操作 `head_exit=0`，`memory.events` 的 `oom=0 oom_kill=0` |
| 进程数 | `--pids-limit=16` | `pids.max=16` | 第 16 个进程失败：`/bin/sh: can't fork: Resource temporarily unavailable`，exit 2 |

内存负例与正例对照排除了“写操作本身失败”这一替代解释：同一命令、同一镜像，仅上限不同，结果从 SIGKILL 变为成功且 OOM 计数为零。所有探针使用已锁定本地 Alpine（ID 核验 `f439434f…`）、`--network=none`、无 host 挂载、无凭据、只读 rootfs、`--cap-drop=ALL`、`no-new-privileges`、UID1000，并按随机 nonce label 核所有权后精确 `rm -f`；三个探针 `exists_exit=1`（已不存在）。

**仍未证明（不随本片关闭）**：完整 49 条业务 TC、五个 major、可信 claim、每 repo 当前身份、受保护控制通道、不可删 activation、legacy 降级防护、消费事务与 dispatch/adoption/wake。资源隔离这一项从“环境阻塞”转为“内核强制已实证”，但它是准入的前置条件之一，不是准入本身。

## 根因（先证伪再动手）

运行时探针（未改配置）先给出决定性事实：向 root 层写 `+cpu +memory +pids` 成功后，`/non-systemd` 的 `cgroup.controllers` 确实变为 `cpu memory pids`；但紧接着向 `/non-systemd/cgroup.subtree_control` 写入直接返回 **Device or resource busy**。原因是该 domain cgroup 挂着 13 条直属进程记录，且这些 PID 在本 distro 的 PID namespace 中全部渲染为 `0`（属于父 namespace），无法在当前 namespace 内寻址迁移——kernel 的 No Internal Process Constraint 禁止有直属进程的 domain cgroup 向子层分配 domain controller。

因此这不是 `cgroup_manager` 参数问题：单独用 `podman --cgroup-manager=systemd`（不落盘）测同一受限镜像，仍 create0 / start125（`memory.max` 不存在）。可回滚的运行时改动已按原值写回（root `subtree_control` 复原为空），随后才进入维护窗口。

## 变更与执行顺序

1. 维护前快照：3 个容器原 ID／StartedAt／卷挂载、5 个卷，专用库自身身份与 **83 行全量 `id|md5(grant_json)`** 摘要（`cgroup-authorized-…-db-before-history.txt`，SHA256 `e39534a2…`）。
2. 私有恢复副本：`/var/lib/aifi45-config-backups/cgroup-20261024-62ab7fcac54c4125b8ce796f093f5682`，root-owned 0700、文件 0600，含 `/etc/wsl.conf`、`/etc/containers/containers.conf`、`user@.service.d/delegate.conf` 原文与 SHA256/mode/uid/gid 清单。未把配置原文或凭据写入记录。
3. 唯一配置变更：`/etc/wsl.conf` 由 `[user]\ndefault=user` 改为追加 `[boot]\nsystemd=true`，sha `8a037d60…` → `97fa04e3…`，mode 644 root:root，原子替换。未改 `containers.conf`、未改 `delegate.conf`、未切 rootful。
4. 温和停止：backend → 两个 PostgreSQL，按原 ID，`podman stop --time 30`，全部 exit 0 且状态 `exited`；容器未删除，5 个卷保留。
5. 重启：`podman machine stop` exit 0；`podman machine start` **exit 125**。按预案用原生 `wsl.exe --terminate podman-machine-default`（exit 0）并重试一次，仍 exit 125。此时 `podman info`／`podman ps` 已可用，说明发行版本体已启动、仅机器状态跟踪失败。
6. 恢复：按原 ID 启动 pg1、pg2 → `pg_isready` 通过 → backend，均 exit 0；三者 `running`，cgroup 落在 `user.slice/user-1000.slice/user@1000.service/app.slice/<原ID>`。

## 重启后核实

- 委派链：`/sys/fs/cgroup` root `subtree_control=cpuset cpu io memory pids`；`init.scope`、`user.slice`、`user-1000.slice`、`user@1000.service` 均获 `cpu io memory pids`；`user@1000.service` 有效控制器 `cpu io memory pids`，`Delegate=yes`。`/non-systemd` 不再是容器路径。
- 专用库：`stdd_aifi45_20261022 | stdd | 642_cr_execution_authorization_head`，**83 行**，聚合 md5 **`ced5ac216bcc912979a222221d15ffd0`（与维护前完全一致）**，逐行摘要文件 SHA256 `e39534a2…` 一致，advisory 锁 0、其它会话 0。
- 服务：`multica-postgres`、`stdd-aifi45-20261022-pg`、`multica-backend` 均 running；`multica-postgres` 与专用库各保留原 PostgreSQL data volume。

## 遗留操作性问题（未修，不掩盖）

`podman machine` CLI 的状态跟踪与本次配置变更不匹配：`podman machine list` 显示 `Running:false`（`lastUp 2026-10-24T22:51:49Z`），而引擎与 API 实际可用。首次 `start` 报 `machine did not transition into running state: ssh error: machine not in running state`；重试另报状态文件原子替换 `Access is denied`。现场存在 `podman-machine-default.lock` 与运行中的 Podman Desktop（4 个进程）及一个 `win-sshproxy`，锁竞争是可疑原因，但**本轮未证明**具体责任方，也不擅自关闭用户的应用。

后果与当前可用恢复路径（本次已实际走通）：容器没有自动重启策略，重启后需 `wsl.exe --distribution podman-machine-default`（保证发行版启动）再 `podman start <原ID>` 逐个恢复。**不声称 `podman machine start` 现在能正常收尾**；该 CLI 状态/就绪检查问题需单独跟进。

## 证据索引

同前缀 `cgroup-authorized-20261024T141533Z`：

- `-before.json`、`-diagnose.*`、`-ancestors.*`、`-systemd-canary.*`、`-boot-readonly*.{py,json,log}`、`-backup.*`：变更前定位与私有备份。
- `-delegation-runtime-probe.stdout.log`：root 启用成功 / `/non-systemd` EBUSY 的决定性对照，及回滚（`revert=ok`、`root_subtree_final` 为空）。
- `-maintenance-step1.json`、`-maintenance-step2.json`、`-maintenance-step3-restore.json`：停止、重启、恢复的 argv/exit/状态。
- `-post-revert-state.log`、`-post-restart-cgroup.log`：变更前后委派链。
- `-premaintenance.json`、`-db-before-history.txt`：维护前容器/卷/DB 身份与 83 行摘要。
- `-enforcement-canary.json`、`-enforcement-canary2.json`、`-enforcement-pids2.json`：cpu/memory/pids 限额与正反对照。
- `-machine-state-diagnosis.json`：机器状态跟踪与锁/进程现场。

一次 `/proc/1/ns/cgroup` 读取因权限被拒（记为 unknown），一次 `podman inspect` 的 `.Id` Go template 字段不可用（改用 `.ID`）——均为诊断脚本问题，不是产品缺陷、业务 RED 或修复成功证据。

## 口径

本次只关闭“资源限额是否被内核强制”这一项环境验收。业务 TC 仍 **0/49**，五个 major 仍 `resolved:false`，`.stdd.yaml` 仍 `build/in_progress`，Gate 3／commit／push／发布／真实 CR 试点均未发生，消费继续关闭。

---

# 阶段二：`podman machine` 状态跟踪与稳定性

## 已修复

1. **自动恢复（原生机制）**：三个容器设 `--restart=always`；启用用户级 `podman-restart.service`（此前 `enable` 报 `Access denied`，根因是 `/home/user/.config/systemd` 及其子目录被 root 拥有，已 `chown -R user:user`）。实测：发行版重启后三个容器**自行**回到 running，无需人工 `podman start`。
2. **状态文件损坏修复**：已按原文档恢复（本次曾被我自己的写入竞争探针覆盖成 `{}`，见“本轮自身失误”）。备份在 `cgroup-authorized-…-state-backup.json`。
3. **端口一致性**：一次失败 `start` 曾把 `sshd_config` 改成 `Port 59669` 并同步改了机器状态与 `system: connection`，但当时 sshd 仍监听 52723，导致 CLI 连不上。现已收敛到单一值 **59669**（sshd 监听、`podman system connection list`、机器状态一致），SSH 实测 `ok`。
4. **稳定性**：WSL 会在约 2 分钟内回收空闲发行版（即使容器在跑），容器随之停摆。已恢复 Podman Desktop 运行，并以 `wsl.exe -d podman-machine-default --exec sleep infinity` 分离会话作本地保活；实测 100s 后发行版仍在、三容器 running。未做全局 `wsl --shutdown`，未影响其他发行版。

## 仍未修复（外部组件 bug，已定位到证据边界）

`podman machine start` 仍以 `exit 125` 结束，`machine list` 恒为 `Running:false`、`inspect` 恒为 `stopped`，尽管引擎、SSH、命名管道、API 均可用。链条：

- debug 日志：`detected port conflict on machine ssh port [52723], reassigning` → 改写 `sshd_config` → `could not start api proxy since expected pipe is not available` → `machine did not transition into running state`。
- 失败收尾是写状态文档：`rename .tmp-podman-machine-default.json<N> podman-machine-default.json: Access is denied`。
- 排除项：文件属性仅 `Archive`、目录正常、无其他进程独占（独占打开成功）；用**完全相同的临时文件名**做 20 次原子替换 **0 失败**；对副本做 200 次替换 **0 失败**；关掉 Podman Desktop 后仍失败；删掉状态文档再 `start` 则机器被判为不存在且文档**未被重建**（已回滚）。
- 结论：状态写入失败发生在 podman 进程内部（Win 侧实现），外部无法修复；不在本仓范围内打补丁，也不再用非受控实验继续扰动生产状态文档。**工作替代路径**：原生 `wsl.exe -d podman-machine-default` 拉起引擎 + `restart=always` + `podman-restart.service` 自动拉起容器；`podman` CLI 走 SSH 连接（59669）正常。

## 本轮自身失误（保留，不美化）

- 把写入竞争测量直接作用于**真实**状态文档（120 次写 `{}`），造成机器状态损坏；已按原内容恢复，并改为对副本测量。
- 多次强杀 `win-sshproxy`／`wsl --terminate`：前者移除保活连接、后者直接终止容器，导致 Postgres 被非温和停止、容器多次停摆；期间一次 `stop` 因连接漂移失败。事后逐次核验：**83 行、逐行摘要 `e39534a2…` 始终一致，0 锁、0 其它会话、`pg_is_in_recovery=false`**，无数据丢失。
- 一次 DB 断言把多行 `string_agg` 当单行切分，产生过 `matches_pre:false` 的假失败，已更正为按行数切分并留存两次结果。

## PoC 重跑（用户请求的第二项）

`multica/scripts/aifi45-isolation/probe.mjs` 实跑 **exit 0**，输出包含：

```
"checks": ["version: runtime configuration", "real CLI bootstrap (not an LLM task)",
 "positive: runtime configuration", "positive control can read synthetic credential",
 "negative: runtime configuration",
 "isolated writes, runtime caps, absent host secrets/socket, link targets, readonly root, no route"],
"resourceLimitsEnforced": true, "modelRequests": 0, "hostWorkspaceMounted": false,
"admissionEnabled": false, "ownedResourcesCleaned": true
```

即前一轮的 `resourceLimitsEnforced:false` 已随控制器委派实际生效而转为 **true**；README 原句“caps 仅在运行时委派控制器时应用”仍准确，未改动。前两次重跑失败分别是 `podman info exit 125`（发行版空闲回收）与 API 不可达，均已作为失败证据保留（`aifi45-isolation-rerun-20261024T152510Z.*`、`-rerun2-*`），**不**与本次通过合并计数。

证据：`stability-and-probe.json`、`machine-start-debug.{stderr.log,meta.json}`、`machine-port-drift-check.json`、`machine-state-write-probe.json`、`state-rename-final-probe.json`、`machine-rebuild-experiment.json`、`machine-clean-start{,2}.json`、`unit-enable-and-restore.json`、`service-final-restore.json`、`db-recheck-and-contention.json`、`final-after-poc.json`、`aifi45-isolation-rerun3-*.{stdout.log,stderr.log,meta.json}`。

## 边界

PoC 通过只说明“该离线 CLI 引导实验在真实限额下成立”，其自带 boundary 仍写明 daemon task/claim/receipt 集成未验证。业务 TC **0/49**、五个 major、可信 claim、准入、Gate 3、commit/push 均未推进。

