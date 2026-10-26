# 执行绑定签发（server 侧）纵片 — 计划（BUILD 继续；消费仍关闭）

用户要求继续、非必要不停。上一片（终态代次 fence）已到组件级收尾：`final5` 冻结独立回归 governance 879/878（795 leaf）、handler 13/13（10）、daemon 125/124+1 SKIP（115），原库五轮一致、vet exit0。**该片不解除** legacy 接受、动态 race、retry overlay 外部副作用、旧 claim 锁序 INCOMPLETE、0/49、5 major、消费关闭与 Gate3 边界。

## 为什么是这一片

`REQ-AUTH-003 / SC-AUTH-007/008/009` 要求：送达或 ACK 不等于消费；消费必须适用于**当前** scope/版本/租户；控制证明必须绑定**本进程随机 challenge、实际进程/根和真实任务**，且"平台仅向经 daemon_token 认证且与 DB 当前 claim 匹配的可信 daemon 控制子进程签发"。T 侧 `requestExecutionBinding`（`tools/…/lib/execution-binding.mjs`）已经实现：出 `execution-binding-challenge/v1`（challenge/install_root/operational_root/process_id/parent_process_id/operation/grant_digest/authorization_revision/policy_digest/template_digest/tools_digest），经私有 stdio 等一个 `execution-binding/v1` 签名 envelope，并按**恰好 20 个字段**与 challenge 逐项比对。**服务端签发这一半完全缺失**，所以 T 永远拿不到证明，消费无法开始。

## 本片范围（只做签发，不做准入）

1. **新表 `cr_execution_binding_issue`**（append-only）：`id, workspace_id, cr_id, grant_digest, challenge, runtime_id, task_id, daemon_id, envelope jsonb, created_at`；`UNIQUE(workspace_id, cr_id, grant_digest, challenge)`；触发器拒 `UPDATE`/`DELETE`（不可删的窄形态）。**不加 FK/级联**，不迁移既有表。
2. **`POST /api/daemon/crs/{crID}/execution-authorization/binding`**（DaemonAuth 组）：
   - 未配置合同 / 无签名 key ⇒ 503；非 `DaemonAuthPathDaemonToken`、无 daemon id、workspace 非 UUID ⇒ 403；CR-ID 非法 ⇒ 400。
   - body 严格：单个 UTF-8 JSON、重复键/未知键/大小写别名拒绝、规范化 base64、`challenge` 64hex、`runtime_id`/`dispatched_at` canonical、`operation` 匹配 `^[a-z][a-z0-9-]{1,31}$`、两 root 为绝对路径且无控制字符、process ids 为非负整数。
   - 同一 `REPEATABLE READ`（读写）事务内：解析 claim → 当前 task 行（runtime/代次/active/workspace）；复用既有 `GetExecutionAuthorizationHead` + `validateCurrentExecutionHead` 拿当前 head（含撤销/scope/policy/template 校验）；核 claim 与 head 同 workspace/CR/project；核 `coordinator_binding` 为 local_directory 且 `daemon_id` = 请求 daemon；核 challenge 的 `grant_digest/authorization_revision/policy_digest/template_digest` 与 head 事实一致。
   - 命中同一 `(workspace, cr, grant_digest, challenge)` 已有行 ⇒ 返回原 envelope、`changed=false`（SC-AUTH-009 幂等）；否则签 `execution-binding/v1`（签名输入 `UTF8("execution-binding/v1\0") || raw_payload_bytes`，Ed25519，key_id=服务 key_id）并插入一行、`changed=true`。
   - 签名 payload 恰好 20 键：`schema,key_id,workspace_id,project_id,cr_id,resource_id,daemon_id,challenge,install_root,operational_root,process_id,parent_process_id,operation,head_digest,authorization_revision,policy_digest,template_digest,tools_digest,runtime_id,task_id`。
   - 响应 `{envelope:{key_id,payload_b64,signature}, changed}`；不回显安装根之外的路径/秘密。
3. **明确不做的部分（本片写进报告，不冒充）**：daemon 侧私有 stdio 中继、T 侧消费事务接通、`EXECUTION_CONSUMPTION_REQUIRED` 的解除、activation（不可删激活）本体、同 UID 隔离控制域。**服务端签的进程号来自 daemon 转述，服务端无法验证**——这条边界必须写清楚，不能把签发说成"进程已证明"。

## 验收

- balanced 写真实 MDT→公开 HTTP→DB 测试（happy path 验签成功且恰好 20 键；stale claim 409；撤销后 409；错 scope/错 policy 409；同 challenge 重放 changed=false 同 envelope；不同 challenge 得新行；PAT 403；半参/坏 challenge/别名/重复键 400；表 UPDATE/DELETE 被触发器拒绝）。
- 主会话实现；`make sqlc` 固定版本离线生成（先存生成前 archive，规范化后只应变更预期文件）。
- 独立非作者回归 + strong 限定静态复核；CUSTOM 增量登记；wire §3.6；两仓 tasks/phase-context 更新。
- 全程：原库 HOLD、单 DB 执行者、每命令 nonce 库、pre-run source pin；不 gate/commit/push/部署；不开放消费。
