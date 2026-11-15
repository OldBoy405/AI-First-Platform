# AIFI-45 M2 真实跨端闭环取证（当前代码实跑）

## 结论：闭环未走通，已按真实阻断点停止

真实完成：当前源码镜像构建、tmpfs PG 真迁移、真实 HTTP 签发出 201、真实
`approval_record`/CR/project 行、真实 daemon claim 与 claim 复核、真实授权 GET、
daemon-owned trust root 安装 key/grant/source、daemon 亲启 crctl `--check`。

**未走通**：daemon 随后在当前代码的严格 preflight 固定返回
`EXECUTION_CONSUMPTION_REQUIRED`，未进入 binding challenge、`requireControlAdmission`、
业务消费或 advance/register。两条 T 侧负例因此均为 **NOT RUN**，没有用本地注入替代。

- source_event_id：`e2ac071b-9390-4710-8a91-14b6a30ee2d7`
- source_digest：`09bfb6d313dd765978d1c39e638e29455126096ccc353d713cff26c47d145cb1`（前缀 `09bfb6d313dd7659`）
- bindings 字段数：`14`
- trust root：`/root/.multica/execution-trust/899654dd-6d37-48ad-83ee-3596d5f8aafe`
- 镜像：`localhost/multica-backend:m2-20261108T154054Z-3a89e7d39bae6c5f`
- 镜像 ID：`3ef1bd77e84f7fe1349412cf9b02340226d4e58853c9ffae5db7ff5c89990426`
- 任务终态：`failed`

## 箭头与证据文件

| 箭头 / 事实 | 结果 | 原始证据 |
|---|---|---|
| 当前源码 → backend 镜像 | 真实 | `build.stdout.txt` |
| tmpfs PG → 真迁移 → health | 真实 | `migrate.stdout.txt`, `health.stdout.txt` |
| structured-human-request 原 bytes → 真实签发 route | 真实，HTTP 201 | `issue-authorization.stdout.txt`, `source-request.json` |
| 签发行与 DB 归属 / source_event_id / digest / bindings | 真实 | `db-grant-row.stdout.txt` |
| daemon 授权 GET → daemon-owned trust root | 真实 | `trust-root-install.stdout.txt`, `daemon.log.txt` |
| daemon 亲启 crctl 静态 `--check` | 真实，但不是控制准入 | `trust-root-install.stdout.txt` |
| binding endpoint → requireControlAdmission → 业务消费 | **未走通**：前置固定门禁 | `crctl-admission.stdout.txt` |
| tampered source 负例 | **NOT RUN** | `negative-tampered.stdout.txt` |
| cross-project 负例 | **NOT RUN** | `negative-cross-project.stdout.txt` |
| 清理后容器与镜像 ID | 真实 | `podman-ps-after.stdout.txt` |

## 边界

一次性实例、自签 CA、同 UID 容器和 seed 的初始 workspace/project/CR/pipeline 队列
**不等于生产部署或生产信任链**。claim、二次 claim 校验、授权 delivery、安装、
crctl --check 和终态回调来自真实路由/DB/daemon；脚本没有声称 pipeline 队列由完整
Runner 业务链产生。没有临时私钥、PAT、daemon token、JWT 或 DB 密码写入证据。
所有随机容器、网络与 tmpfs DB 均由 trap 销毁；既有 `multica-postgres`、
`multica-backend`、`multica-internal` 未作为运行资源使用。

## TC-TAC-001..010：没有一条可据此升整条

- **TC-TAC-001**：缺 daemon 亲启的非只读 admission、真实业务事务与消费事实。
- **TC-TAC-002**：真实两 project grant 替换与零副作用未跑。
- **TC-TAC-003**：本次只有真实 daemon 静态 check；不能替代各伪造输入下的真实 admission。
- **TC-TAC-004**：真实 route/source/DB 子句得到补强；篡改来源经 daemon/T 的拒绝未跑，仍只能条款级。
- **TC-TAC-005**：本次没有不同 OS 身份写保护证据；既有 Linux 半侧不能补 Windows。
- **TC-TAC-006**：旧 head、撤销、失联、恢复矩阵未在真实链跑完。
- **TC-TAC-007**：repair-admit/resume 正例及故障恢复未经真实 daemon。
- **TC-TAC-008**：repair 负例矩阵未经真实 daemon。
- **TC-TAC-009**：预分配 registration key、register/archive 正例与重放未跑。
- **TC-TAC-010**：register/archive 负例与零副作用未跑。

因此这份证据不能支持生产启用、ADJ-AIFI45-001/002/003 关闭或任何整条 TC 升级。
