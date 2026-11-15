# AIFI-45 真实 CLI 隔离实验记录

> 普通 BUILD；只验证限定配置的离线 CLI/bootstrap 与 synthetic shell adversary，不是生产 executor、可信平台 claim、消费或完整 TC。`authorization-bind` 保持 `EXECUTION_CONSUMPTION_REQUIRED`。真实 CLI/临时镜像依赖已获用户授权；未获模型支出/真实凭据/生产启用授权。

## 固定输入

- M：`scripts/aifi45-isolation/{codex.lock.json,probe.mjs,README.md}`；不全局安装。
- Codex `0.163.0`，官方 `openai/codex` release `rust-v0.163.0` 的 `codex-x86_64-unknown-linux-musl.tar.gz`。
- 112589966 bytes；SHA256 `beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4`，来自官方 release API asset digest。重用公共临时 cache 前重新核 regular file/大小/SHA，不把 cache 当信任根。
- 本地 Alpine digest `bbfcd601d7cd20d35bb0b8b866ad1a8a0d107ca3e1c20870c75c5ce2c1186d30`；image ID `f439434f9e6739ae2f80313f260d2084bb89feaf7220a06a5398e6b90797e2e3`。Rootless Podman/Linux amd64，`--pull=never`。

## 已实际执行，不改写失败

| 尝试/检查 | 实际结果 | 能证明/不能证明 |
|---|---|---|
| 原 npm Linux 整包下载 | 180s timeout / exit1 | 失败，不是行为 RED/隔离 PASS |
| 同版官方单文件直接 fetch | 600s timeout / exit1，只报告16MiB | 失败；不再仅增加 timeout |
| 原生 curl 4并发 bounded ranges | 完整112589966 bytes拼合且整包 SHA256通过；随后 tar exit2，整体 exit1 | 传输/完整性已实证，不代表容器启动 |
| GNU tar 1.35 tiny archive根因反例 | 相对创建exit0；绝对Windows `C:` archive路径exit2、`Cannot connect to C: resolve failed`；相对archive+显式cwd exit0 | 定位本地路径被当remote host；不是归档损坏，更不是业务 TC RED |
| curl默认配置 synthetic正负对照 | 仅临时fake HOME/CURL_HOME：`curl --version`读取合成错误option；`curl -q --version`不读取；两者exit0 | `exit0`本身不能证明不读配置，必须断言实际诊断；未读真实curlrc/token |
| 修订完整PoC | artifact/完整SHA/tar/临时镜像构建通过，首个`podman start` exit125 | 真实CLI尚未执行，正/负canary未运行；不是隔离PASS |
| 本机 codex 版本对照 | 宿主 `codex --version` = `codex-cli 0.163.0`，与锁定的官方Linux版同版本 | 宿主是Windows二进制，**不能在Linux容器内执行**；容器必须用同版本Linux构建，不是重复安装 |
| 授权后VM调整尝试（已回退） | `podman info`: rootless cgroupfs/controllers=[]。临时改machine `/etc/wsl.conf` 加`[boot] systemd=true`并重启后：PID1=systemd、控制器委派为cpu/io/memory/pids、限额实测exit0；但`podman machine start`报`expected pipe is not available: podman-machine-default`、客户端`127.0.0.1:52723`拒连 | 该调整与 podman machine WSL 的 API proxy 不兼容，不可用。已还原`/etc/wsl.conf`（仅留`[user] default=user`）并重启；三容器（shared postgres/backend、本change专用DB）恢复running，DB身份复核`stdd_aifi45_20261022|stdd`，无数据变更 |
| 最终PoC运行 | exit0；`resourceLimitsEnforced:false`；真实`codex-cli 0.163.0`；6项check全过；`ownedResourcesCleaned:true` | 真实CLI bootstrap+文件/网络/凭据边界已实证；**CPU/内存/PID限额未强制**（本机无委派控制器），未接daemon任务/claim/receipt |
| 同flags的现有Alpine `/bin/true`诊断 | exit127，crun: `open memory.max for writing: No such file or directory`；容器保持created，State.ExitCode虽0不代表执行 | 原因在运行时cgroup能力，不是Codex、网络、artifact或加timeout可解；own诊断容器已清 |
| 中途fail-fast预检（已被下方最终运行取代） | 当时实际`UNSUPPORTED_ISOLATION_RUNTIME`/exit1，未下载/启动 | `podman info`: rootless=true、cgroupVersion=v2、manager=cgroupfs、controllers=[]；当时选择不移限额/不提权，后经用户授权才尝试VM调整 |
| 收尾资源核验 | instance label容器0、volume0，purpose label镜像0 | 全部定向清理，无全局prune。固定公共artifact cache按设计保留 |

## 已修订的安全边界，等待整脚本运行核验

- Host工具环境白名单，不继承token/proxy/curl override；curl首参数`-q`禁默认配置。可信launcher仍使用已授权的本地Podman连接；不把其连接配置共享给不可信容器。
- 容器`--http-proxy=false`，inspect拒绝代理变量；非root、只读root、无cap、no-new-privileges、network-none、私有HOME/代码volume。无真实HOME、workspace、`.git`、`.crctl`、engine socket bind。
- 真实CLI仅`--version`，无模型请求；正对照显式挂synthetic secret确认同镜像可读，负对照移除该挂载，检查能力/路径/写入/链接目标/只读根和实际IPv4 route。
- 每次资源使用随机nonce与instance label，create前记container name intent；cleanup先exists/inspect核归属，定向rm自己容器/卷/镜像，不prune。cleanup失败非零；成功JSON在清理后输出。SIGKILL/engine失联可能留资源，不宣称穷举恢复；公共固定摘要artifact cache明确保留。

## 需要操作者协助的实际阻断

本机运行时未委派资源控制器（rootless cgroupfs、`controllers=[]`），已由真实内核操作与`podman info`交叉核实。启用systemd可拿到控制器，但会破坏 podman machine WSL 的 API proxy pipe，因此该方案被回退；不把 machine 留在一个半坏状态换绿色。

当前PoC以**无 cpu/memory/pids 限额**运行并在结果中显式标记`resourceLimitsEnforced:false`，不假装有限额，也不据此把profile登记为隔离能力已就绪。资源耗尽约束需要：可委派控制器的 rootless 运行时（如 Linux 宿主/受管 CI runner），或后续单独授权解决 machine 的 systemd+API proxy 组合。

独立审查两项P2（curlrc/代理、cleanup误绿）与cache校验→重读TOCTOU已回修并随本次实际运行生效（`-q`、环境白名单、无代理透传、nonce归属、清理后报成功）；静态与动态证据均已取得。

## 未解除的阻断

- daemon真实任务/profile、当前平台claim/head/revoke、每仓fresh身份、M grant/source/key安装器及受保护trust root尚未完成。
- T消费事务、额度、不可删activation/legacy防降级与M永久派发/adoption未接通。
- 不能据此关闭ADJ-AIFI45-003/ADJ-AIFI45-M002，也不能把无网`--version`当真实有模型任务隔离证明。完整TC/切片仍0。

## 2026-10-25 追加：同 UID 保护不了验签公钥；只读容器 bind 挡得住

**问题**：ADJ-AIFI45-M002/M003 一直缺一条实证——在 agent 与 daemon 同 UID 时，验签公钥/授权文件能不能被替换？容器化只读挂载能不能挡住？

**实测**（`multica/scripts/aifi45-isolation/trust-root-probe.mjs`，证据 `validation/trust-root-20261025T090800Z-probe.json`，9 项 check 全过 exit 0）：

| 事实 | 结果 |
|---|---|
| 同 UID 重写公钥（append / cp 覆盖） | **成功**，`same_uid_rewrite_possible: true` |
| 同一目录 `--read-only` bind 进容器后 9 类写尝试 | **全部未成功**，无 `BYPASS`，`denied_vectors` 9 项 |
| 新路径创建（决定性只读证据） | `touch: /control-ro/keys/brand-new: Read-only file system` |
| 所有尝试后公钥 sha256 | **未变**，`key_digest_unchanged: true` |
| 容器内引擎 socket / 控制路径 | 全部不可见，`control_channel_visible: false` |
| 容器内宿主工作区 | 不存在（`/work` 不存在，无工作卷） |

**结论**：`0700/0600 + 路径 pin + 过滤 env` 这类同 UID 手段**不能**保护验签公钥；容器 + 只读 bind + 无控制通道是"challenge 不可被冒充"的**必要条件**。

**明确没做到**：daemon **尚未**把 agent 跑进该容器（本探针不接任务/claim/准入）；cgroup 限额来自另一支 `probe.mjs`，不在本探针；持续新鲜度、CR 归属、T 侧消费事务均未验证。因此 `consumption_enabled` 仍为 `false`，M002/M003 仍**未关闭**。

**下一步**：把该容器变成真实执行域（agent 在容器内、trust root 只读、控制通道只经 daemon 私有 stdio，合成对手做负例）。会动 `handleTask` 执行路径，需独立 RED→GREEN 与非作者回归。
