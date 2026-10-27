# P0 隔离证明：方案 C 实测证据（2026-10-27，第二版）

> 原始产物：`validation/p0-run-20261027/`（探针输出、两段 execve trace、`check-result.json`、`inventory.txt`），
> 脚本：`p0-run-20261027/scripts/`（`run.sh` 一键重跑，`check.py` 是 fail-closed 判定器，exit 0 才算过）。
> 第一版（10 条探针）有两处结论错误、一处设计漏洞，已被本版取代，更正说明见 §5。

## 结论

| 范围 | 结论 |
|---|---|
| worker↔reader 两身份互隔离、对 launcher/entrypoint 不可写、不可提权 | **成立**：24/24 PASS，连跑两次结果一致 |
| 「只能经 launcher 以受限身份启动进程」 | **成立（execve 级 trace 证据）**：clean 窗口 0 违例，反向对照窗口抓到旁路 |
| **对 agent 的隔离** | **不成立**：见 §4，已登记为残余风险 ADJ-10 |

## 1. 受测对象（版本 pin，来自 `inventory.txt`）

| 项 | 值 |
|---|---|
| 身份 | `aifi45-worker` uid=995 gid=994；`aifi45-reader` uid=994 gid=993；shell `nologin`，不在 wheel |
| 私有根 | `/var/lib/aifi45/worker` `drwx------ 995 994`；`/var/lib/aifi45/reader` `drwx------ 994 993`；父目录 root 0755 |
| launcher | `/usr/local/lib/aifi45/launch.sh` root 0755，sha256 `384c5190cd21ccc1f824ce0f2d5a6553e9c126c4d28e21dfc212c4aad2e903cc` |
| entrypoint | `/usr/local/lib/aifi45/entrypoint.sh` root 0755，sha256 `afffe44262a941091d7c0af7913cc6624bb7f8ab3fff7c0ad7179daf54a200b8` |
| trace 程序 / 判定器 | `exec.bt` `975a2e1e…6abba`；`check.py` `e7916e3f…0867` |
| 环境 | Fedora 44（WSL2），kernel `6.18.54.1-microsoft-standard-WSL2`，bpftrace `0.24.2-3.fc44`，podman `5.8.5`；发行版 pid ns `4026532214`（非初始），user ns `4026531837`（初始） |

launcher：`--role` 与 `--root` 必须是两组固定配对之一，其它入参一律 `exit 64`；以
`setpriv --reuid --regid --clear-groups --no-new-privs` + `env -i` 降权后，exec **root 目录下**的固定 entrypoint。

## 2. 正向证明（全部经 launcher 执行，24 条）

每个身份 10 条（worker、reader 各一份）：

| claim | 判据 |
|---|---|
| identity | `uid/gid/groups` 与登记值逐字相等，`Uid:` 四元组一致 |
| no_caps | `CapEff` 与 `CapPrm` 均为 0 |
| no_new_privs | `NoNewPrivs=1` |
| cross_read_denied | 读对方私有根被拒 |
| write_launcher_denied / write_entrypoint_denied | 对两个 root 文件 `access(W_OK)` 被拒 |
| replace_entrypoint_denied | 对 `/usr/local/lib/aifi45` 目录写被拒（不能删了再换） |
| sudo_denied / setuid0_denied | `sudo -n true`、`os.setuid(0)` 均失败 |
| own_root_writable | 自己私有根**可写**（正对照：身份确实有写能力，拒绝不是因为什么都写不了） |

另外 4 条：

- `launcher.allowlist`：未知角色、任意根、角色/根错配、额外参数，4 种全部 `rc=64`。
- `trace.clean_only_via_launcher`：clean 窗口 160 个事件，6 次 launcher 调用（2 次放行、4 次被拒），
  uid 995/994 的 30 次 execve **全部**能沿 fork 链追到一次 uid 0 的 launcher exec，违例 0。
- `control.probes_can_turn_red`：同一 entrypoint 以 root 跑，6 项拒绝类探针全部变成 `ok`，证明探针能红。
- `control.second_path_detected`：control 窗口用 `sudo -u aifi45-worker /usr/bin/id` 绕开 launcher，
  判定器报出该 execve（uid 995，`/usr/bin/id`）为违例，证明 trace 判定能红。

## 3. execve 审计为何用 bpftrace 而不是 auditd

- 内核**支持** audit（`CONFIG_AUDIT=y`、`CONFIG_AUDITSYSCALL=y`），`audit-4.2.1` 已安装。
- 但 auditd 启动即 `DAEMON_ABORT op=set-enable res=failed`，`auditctl -s` 与加规则都返回 `Operation not permitted`。
  原因：WSL 发行版跑在非初始 PID 命名空间（`4026532214`），内核只接受初始 PID 命名空间发来的 audit 控制请求。
  auditd 已 `disable --now`，不留失败单元。
- 替代：bpftrace 挂 `sched:sched_process_fork` 与 `sched:sched_process_exec` 两个内核 tracepoint，按纳秒时间排序后重建进程树。
  它在内核层捕获全部 exec，不依赖命名空间，覆盖面与 audit 的 execve 规则相当；控制窗口已证明它能抓到旁路。
- 两个实现细节（都已在脚本中处理）：
  1. 本机 `/lib/modules/<ver>/build` 指向的内核头不完整，bpftrace 会去找头文件而失败。所以 trace 在
     `unshare -m` 私有挂载命名空间里把该目录遮掉，强制只用 BTF；**不改系统文件**。
  2. bpftrace 的 `pid` 内建变量在非初始 PID 命名空间里返回命名空间内 PID，fork 事件给的却是全局 PID。
     所以 exec 改用 tracepoint 自带的 `args->pid`（全局）。第一次跑因此误报 30 条违例，修正后为 0。

## 4. 残余风险：对 agent 的隔离不成立（ADJ-10）

- Windows 用户 GOBAO 执行 `wsl.exe -u root` 免密即得 uid 0；WSL 用户 `user` 在 wheel，`%wheel ALL=(ALL) NOPASSWD: ALL`。
- agent 以 GOBAO 运行，所以它能改 launcher/entrypoint、读任一私有根、冒充任一身份。本证据里的身份和文件就是 agent 自己建的。
- WSL 的设计是能启动发行版的 Windows 用户即可成为其 root；本机不换 Windows 用户或 VM 就无法关闭这条路。
- 处理（用户 2026-10-27 采纳）：**接受为残余风险**。C 路径片只按 `channel-component` 组件级验收，
  不得声称满足 `strict-production`；Gate 3 报告必须单列此项。

## 5. 相对第一版的更正

1. 第一版说「WSL2 内核无 audit 子系统」：**错**。实际是编了 audit，但非初始 PID 命名空间不能控制它（§3）。
2. 第一版把「root 是信任锚」当作范围外：**掩盖了 agent 即 root**（§4）。
3. 第一版 entrypoint 放在各自私有根下，归该身份所有：worker 能改自己下次运行的代码；即使改成 root 文件，
   worker 对目录有写权限，仍能删了再换。**已改**：entrypoint 挪到 root 目录，launcher 执行固定路径，
   并新增 `replace_entrypoint_denied` 探针。
4. 第一版多数探针直接用 `sudo -u` 测，未经 launcher：**已改**为全部经 launcher；`sudo -u` 只作为反向对照里的旁路。

## 6. 仍未覆盖

- Windows 侧：没有第二个真实受限的 Windows 身份，`isolation` 的 win32 分支仍为 UNVERIFIED。
- 容器路径：本次走宿主进程，镜像 digest、`--read-only`、`--cap-drop` 未涉及。
- 代码侧 `TestChannelIsolation`（pidfd、`SO_PEERCRED`、私有 socket、CLOEXEC、拒 SCM_RIGHTS）尚未实现（P0.1–P0.3）。
  本文件只证明**环境前提**，不等于 `isolation` label 通过。
