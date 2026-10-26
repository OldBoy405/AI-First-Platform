# trust-root 边界实证（AIFI-45 / ADJ-AIFI45-M002、ADJ-AIFI45-003）

用户已要求“继续、非必要不要一直请示”。本片回答一个一直阻碍 major 的具体问题：**在被管进程与 daemon 同 UID 的前提下，验签公钥/授权文件能被替换吗？容器化只读挂载能挡住吗？**

## 结论（有实证，不是推断）

| 事实 | 值 | 来源 |
|---|---|---|
| 同 UID（今天的 agent 进程）重写公钥 | **可行**（append / 替换均成功） | `trust-root-20261025T084600Z-probe.json` `same_uid_rewrite_possible: true` |
| 容器内（同一目录只读 bind）9 类写尝试 | **全部未成功**（无一条 BYPASS；逐项清单见 JSON `denied_vectors`） | `container_rewrite_denied: true` |
| 只读性的决定性证据 | 容器内向**新路径**创建文件报 `Read-only file system` | `erofs_create_error: "touch: /control-ro/keys/brand-new: Read-only file system"` |
| 一次次尝试后的公钥内容 | **摘要未变** | `key_digest_unchanged: true` |
| 容器内可见的引擎 socket / 控制通道 | **不可见**（`/run/podman/podman.sock`、`/var/run/docker.sock`、`/control*` 全 absent） | `control_channel_visible: false` |
| 容器内可见宿主工作区 | **不存在**（容器内 `/work` 不存在，不是“空卷”） | `host_workspace_mounted: false` |
| 是否开放准入/消费 | **未开**（`admission_enabled=false`、`consumption_enabled=false`） | 同上 |

被拒的具体写向量：`append_key`、`overwrite_key`、`replace_key`（cp 覆盖）、`unlink_key`、`move_key`、`chmod_key`、`symlink_key`（符号链接替换）、`create_in_keys`、`unlink_grant`。

**关于断言强度（经 strong 两轮复核后补正）**：busybox 的 `cp`/`ln` 在目标已存在时会先报 `File exists`，所以不能把每个向量的错误文本都当成 EROFS 证据；当前证据链是三层：(1) 9 个向量**全部未成功**且无 `BYPASS`；(2) 一个**新路径**的创建报 `Read-only file system`（决定性只读证据）；(3) 所有尝试之后公钥 sha256 **未变**。严格说，(1) 只能证明这些命令没有成功，不能证明它们每一个都返回 EROFS；因此报告只声称“容器内无法完成这些写操作，且新路径写入确定被只读挂载拒绝”。容器内仍能**读**公钥与 grant（公开材料，签名才是权威），这是有意保留的。

**容器形态的局限**：本次容器**没有**任何宿主工作卷（容器内 `/work` 不存在，不是“空卷”），也没有可见的引擎 socket 或控制路径；但它同样没有控制通道，所以它目前只证明了“文件系统边界成立”，并不包含“如何把服务端签好的证明交给容器内的 T”。

## 这次实证说明了什么、没说明什么

**说明**：`0700/0600 + 路径 pin + 过滤 env` 这类同 UID 手段**不能**保护验签公钥 —— 与 ADJ-003 的判断一致，现在有真实复现；而“容器 + 只读 bind + 无控制通道 + 无宿主工作区”这一组合**确实**挡住了全部尝试，并且容器里没有可达的控制通道。因此若要把“公钥不可被替换、challenge 不可被冒充”变成事实，隔离执行域是必要条件，不是可选项。

**没说明**：daemon **尚未**把 agent 跑进这个容器（本探针只测边界，不接任务/claim/准入）；没有测 cgroup 资源限额（上一片 `probe.mjs` 已单独证过 `cpu/memory/pids` 与 32MiB 写入被 SIGKILL）；没有测持续新鲜度、CR 归属或 T 消费事务；`same_uid_rewrite_possible: true` 就是当前产品状态，**消费必须继续关闭**。

## 复现

```bash
node scripts/aifi45-isolation/trust-root-probe.mjs   # 输出 JSON，退出码 0 表示 9 项 check 全过
```

脚本自己创建临时 trust root（`keys/<key_id>.pub`、`grants/<scope>-<id>.execution-grant.json`，0600）、先做同 UID 重写、再在 `--read-only --network=none --cap-drop=ALL --security-opt=no-new-privileges --user=1000:1000` 的容器里以只读 bind 挂载同一目录并逐个尝试写入（失败一律 `denied:`，成功则打印 `BYPASS:` 让断言失败）；额外作新路径 EROFS 探针与读后摘要校验；结束时按名删除容器并清理临时目录（OID 级，不做前缀扫删）。引擎：podman 5.8.3/5.8.5，镜像按 digest 固定（`alpine@sha256:bbfcd601…6d30`），`--pull=never`、`--http-proxy=false`。

最新一次运行：`trust-root-20261025T090800Z-probe.json`（9 项 check 全过，`exit 0`；JSON 含 `denied_vectors` 9 项、`erofs_create_error`、`key_digest_unchanged: true`）。历史：`…T090200Z-*`（9 check，/work 用 `test -e`）、`…T085700Z-*`（`test -d` 只能证明“不是目录”）、`…T084600Z-*`（`cp` 源文件未预先创建，strong 判证据不足）。

## 对 major 的影响（保持诚实）

- ADJ-AIFI45-M002 / ADJ-AIFI45-003 的**根因**现在有实证且路径明确，但两者仍**未关闭**（`resolved` 仍为 `false`）：本片只证明“该边界能成立”，**没有**把 daemon 的 agent 执行改到该容器内，也没有接消费。探针 JSON 里的 `true/false` 只描述本次容器形态，不是“产品已就绪”的字段。
- 下一步（若继续）是把该容器变成真实的执行域：agent 子进程在容器内运行、trust root 只读挂载、控制通道只经 daemon 私有 stdio，再用合成对手做真实负例。这一步会动 `handleTask` 的执行路径，风险显著高于本片，需要单独 RED→GREEN 与独立回归。
- 完整业务 TC 仍 **0/49**、5 major 未关闭、消费关闭、旧 claim 锁序 INCOMPLETE、原库 HOLD；Gate3/提交/推送/部署未授权。
