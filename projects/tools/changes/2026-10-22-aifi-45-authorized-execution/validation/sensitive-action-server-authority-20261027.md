# 敏感动作：平台账本成为唯一权威（AIFI-45 增量 59）

> 承接增量 58 的第 2 项（把唯一权威消费路径接到真实 Runner）。用户已定：**服务端唯一权威，缺配置或不可用即拒绝，不回落**。

## 1. 变更

| 文件 | 变更 |
|---|---|
| `tools/skills/shared/crctl/scripts/lib/execution-sensitive-action.mjs` | 重写为薄服务端客户端：不再写本地账本、不再本地判定额度 |
| `tools/skills/shared/crctl/scripts/crctl.mjs` | `cmdSensitiveAction` 解析 `--server`/`MULTICA_SERVER_URL` + `MULTICA_DAEMON_TOKEN`；缺失即由库层拒绝 |
| `tools/skills/shared/crctl/scripts/test/execution-control-policy.test.mjs` | 原"只接受原 operation"（本地账本语义）替换为传输/错误映射/回执校验用例 |
| `tools/skills/shared/crctl/scripts/test/execution-authorization.test.mjs` | `TC-AUTH-005/006` 改为真 CLI + 真 HTTP 假平台；新增"没有平台就没有裁决" |

## 2. 保留在本地的只有两件事

1. **发请求前的廉价拒绝**：撤销包、请求四键形状、kind 白名单。不合法时一个字节都不发（用例断言 `fetch` 零调用）。
2. **切换护栏**：若该 `action_scope_id` 在旧本地账本里已有消费记录 → `EXECUTION_SENSITIVE_ACTION_LEDGER_UNRECONCILED`，且不发出请求。否则切到平台后同一额度会从零重新计数。**是否列明、还剩多少，一律由平台回答**，本地匹配不到不构成拒绝（只是没有旧账本需要对账）。

## 3. 失败语义

| 情况 | 行为 |
|---|---|
| 未配置服务端（无地址） | `EXECUTION_SENSITIVE_ACTION_SERVER_REQUIRED`，不发请求 |
| 有地址无 daemon 凭据 | `EXECUTION_SENSITIVE_ACTION_AUTH_UNAVAILABLE`，不发请求 |
| 回退凭据（pat/jwt/task-token） | 同上，拒绝 |
| 平台 403 | `EXECUTION_SENSITIVE_ACTION_UNAUTHORIZED` |
| 平台 409 + EXHAUSTED | `EXECUTION_SENSITIVE_ACTION_EXHAUSTED` |
| 平台 409 + REVOKED/UNVERIFIED | `EXECUTION_POLICY_UNVERIFIED` |
| 不可达 / 超时 | `EXECUTION_SENSITIVE_ACTION_UNAVAILABLE`，**结果未知**，不解释为"没消费" |
| 回执缺字段或 operation_id 不符 | 同上，保守阻断 |

超时不做补偿、不换 ID：重试必须沿用同一 `operation_id`，由平台幂等回执回答。未加后台重试队列。

## 4. 验收（真实 CLI 一腿）

- `TC-AUTH-005`：普通授权 4 个 kind 全被平台拒；**平台确实收到 4 个请求**（URL/方法/body 逐项断言），本地 `actions/` 目录不存在。
- `TC-AUTH-006`：已列 scope 的正例/重放/耗尽/三种放宽，共 **6 次请求全部到达平台**；本地无任何账本写入。
- 新增"没有平台就没有裁决"：未配置服务端 → `SERVER_REQUIRED`；有地址无 token → `AUTH_UNAVAILABLE`；两种情况下平台**零请求**。
- 单元层：请求非法时 `fetch` 零调用；回执与请求不一致即阻断。
- 服务端一腿由 `TestTC_RUN_010`（真路由 + 真 DB）覆盖，见增量 58。**两腿分开验证，未做端到端串联**——串联需要真实平台与 DB 同时在线。

实现细节：CLI 用例用 `spawn` 而非 `spawnSync`——假平台与 CLI 同进程，同步 spawn 会阻塞事件循环导致每次都走到 10s 超时（实测两次 10.3s 全红后定位）。

## 5. 变异

- `tools-gate` 前：把平台 403 当成功 → `TC-AUTH-005`、`TC-AUTH-006` 双双变红（2 fail），文件已还原并核 sha。

## 6. 仍未做的

- **daemon 尚未把 `MULTICA_SERVER_URL`/`MULTICA_DAEMON_TOKEN` 注入任务环境**。当前由人工/运维提供；未注入时 CLI 拒绝（fail-closed），不会静默走本地。
- `TC-RUN-010` 仍未记 PRESENT：差同档复核（strong + balanced）。
- 台账仍 **43/49**。
