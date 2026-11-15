# AIFI-45 M2 真实跨端闭环复跑（四条件启动门）

## 结论

**本次目标链走通**：真实 daemon 在当前 head、未撤销、claim 一致后，亲启非只读
`authorization-bind --binding-stdio`，T 的 `requireControlAdmission` 通过既有消费写事务生成
receipt，平台 `cr_execution_consumption` 写入对应行，daemon 未再因
`EXECUTION_CONSUMPTION_REQUIRED` 停住。两条后续真实 task 负例分别得到 T 的
`EXECUTION_SOURCE_INVALID` 与 `EXECUTION_GRANT_SCOPE_MISMATCH`，平台消费均为 0 行。

- A source_event_id：`fb9321da-65ab-45e7-8145-b42e660f7153`
- A source_digest：`ea2c309aa5e8d5ecd9f3d220995d5a5f9c5b0ce7ae7cb583c196ed37496f018b`
- A project / CR：`de2511d6-1c70-4507-b555-a824b69d8b2e` / `CR-2026-992`
- B donor project / CR：`fbeedc58-c6e3-42e0-ad1b-e6a8101dbb53` / `CR-2026-993`
- 镜像：`localhost/multica-backend:m2-20261109T013134Z-4b65a9c3b41c7da8`
- 镜像 ID：`771d0aedc2e944f96a5e1421d8aa727519b7e8b686dc8af0dba6a77ed0b16d25`
- 镜像清理由 EXIT trap 强制执行；结果见 `image-cleanup.stdout.txt` 与 `podman-ps-after.stdout.txt`。

## 箭头与证据

| 箭头 / 事实 | 真实结果 | 证据 |
|---|---|---|
| 当前源码（白名单 + 四条件门）→ 强制新镜像 | 真实，`podman build --rm` | `build.stdout.txt` |
| tmpfs PG → 真迁移 → HTTPS health | 真实 | `migrate.stdout.txt`, `health.stdout.txt` |
| 原 structured-human-request bytes → 真实签发 | 真实，A/B 均 HTTP 201、同一签名服务 | `issue-authorization.stdout.txt`, `issue-cross-project.stdout.txt` |
| DB 归属 / source_event_id / 原 bytes digest / bindings | 真实 | `db-grant-row.stdout.txt` |
| daemon GET → daemon-owned trust root → 静态 check | 真实 | `trust-root-install.stdout.txt` |
| daemon stdio relay → 非只读 authorization-bind | 真实，签名 operation 为 authorization-bind | `binding-relay.stdout.txt` |
| T requireControlAdmission → 既有消费写事务 | 真实，T receipt 含 operation/stage/challenge/task/receipt_id | `crctl-admission.stdout.txt` |
| 平台消费事实 | 真实，A 正例 1 行；B donor 1 行；两负例各 0 行 | `db-consumption.stdout.txt` |
| daemon 启动门 | 真实放行；正例日志无 EXECUTION_CONSUMPTION_REQUIRED，后续 agent 成败不属于准入门 | `crctl-admission.stdout.txt` |
| acceptance 改一个字符、旧签名 | 真实拒绝 `EXECUTION_SOURCE_INVALID` | `negative-tampered.stdout.txt` |
| 同 key 的 project B grant 替换 A | 真实拒绝 `EXECUTION_GRANT_SCOPE_MISMATCH` | `negative-cross-project.stdout.txt` |
| 容器/网络/tmp 文件/本次镜像销毁 | trap 真实执行 | `podman-ps-after.stdout.txt`, `image-cleanup.stdout.txt` |

## 负例构造边界

篡改例在真实 daemon 重新投递 A 后修改 source sidecar 内原始请求 bytes 的
`accepted_rules: allow-a` 为 `allow-b`，保留 grant、签名、digest 与 bindings；真实 T 在非只读
准入验源时拒绝。跨 project 例先让 B 经真实签发/投递/准入取得材料；A 的静态 check 和平台 binding
均真实完成后，临时代理仅延迟未修改的响应 750ms，watcher 将 A grant 文件替换为同 key B grant，
T 消费前 CAS 重读拒绝。没有伪造路由、签名、receipt、DB 行，也没有宿主直接启动 crctl 替代 daemon。

## 边界

一次性实例、自签 CA、同 UID 容器及 seed 的初始 workspace/project/CR/pipeline 队列不等于生产部署、
生产信任链或 Runner 完整业务分发证据。正例只覆盖 authorization-bind 的既有消费事务，没有声称
advance 或修复/注册/归档业务事务已跑。后续 agent provider 的成功与否不改变启动准入事实。

## TC-TAC-001..010：本次没有一条可单独据此升整条

| TC | 能否升整条 | 本次补强与仍缺内容 |
|---|---|---|
| TC-TAC-001 | 否 | 已有真实 bind/receipt/consumption；仍缺真实 advance、全部 AND 与完整业务/零副作用矩阵。 |
| TC-TAC-002 | 否 | 已有同 key B→A 的真实 bind 拒绝；仍缺两个首次写入口/五入口、整根复制及全量零副作用。 |
| TC-TAC-003 | 否 | 未跑 env/sidecar/endpoint/路径 pin/坏 key/根包含等伪造矩阵。 |
| TC-TAC-004 | 否 | 真实篡改拒绝已补强；仍缺机器凭据/错误 actor、跨 DB project 拒签及对应 DB 零变化。 |
| TC-TAC-005 | 否 | 本次没有不同 OS/UID/SID 的内核写拒绝；不能补 Windows 或部署隔离。 |
| TC-TAC-006 | 否 | 未跑旧 head、撤销、失联、恢复、普通读与重放完整矩阵。 |
| TC-TAC-007 | 否 | repair-admit/resume 正例、预算/origin/stop 与崩溃恢复未跑。 |
| TC-TAC-008 | 否 | repair/resume 负例矩阵未跑。 |
| TC-TAC-009 | 否 | registration key、register/archive 正例与重放未跑。 |
| TC-TAC-010 | 否 | register/archive 负例与零副作用未跑。 |

因此本证据不支持生产启用或 ADJ-AIFI45-001/002/003 自动关闭。
