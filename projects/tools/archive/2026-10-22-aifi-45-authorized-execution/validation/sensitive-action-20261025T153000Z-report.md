# tools · 敏感动作消费（SC-AUTH-005 / SC-AUTH-006）+ 送达≠消费（SC-AUTH-007）

## 为什么要做

规范把敏感动作当作**与实施授权分开**的签名条目：普通实施授权不覆盖
生产发布 / 破坏性数据 / 权限扩大 / 对外承诺与支出。`sensitive_actions` 的字段与校验此前已存在
（`lib/execution-authorization.mjs`：`kind/target/environment/limit` 四类 + 唯一 `action_scope_id` 校验），
但**没有任何执行判定**——等于“写得出来、不生效”。本轮补上唯一的执行点。

## 交付

| 文件 | 变更 |
|---|---|
| `skills/shared/crctl/scripts/lib/execution-sensitive-action.mjs` | 新增 `consumeSensitiveAction(workspace, grant, request)` |
| `skills/shared/crctl/scripts/crctl.mjs` | 新增 `sensitive-action` 动词 + 帮助行 + import |
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | `OPS` 增加 `action`（复用既有排他锁，不另造一套） |
| `skills/shared/crctl/scripts/test/execution-authorization.test.mjs` | 新增 `TC-AUTH-005`、`TC-AUTH-006`、`TC-AUTH-007` |

## 语义（唯一执行点的全部规则）

1. 未列明该 `kind/target/environment` → `EXECUTION_SENSITIVE_ACTION_UNAUTHORIZED`，**在任何写之前**。
2. 列明但换对象/换环境/换类型 → 同上（不允许借同一 `action_scope_id` 改绑）。
3. 同 `operation_id` 重试 → 返回**原 receipt**，`replayed: true`，不消耗第二份。
4. 不同 `operation_id` **共享同一额度**，用尽 → `EXECUTION_SENSITIVE_ACTION_EXHAUSTED`（换 ID 不重获满额）。
5. 账本按 `action_scope_id` 落盘（`.crctl/actions/<sha256前32>.json`），记录 `lineage_id`；
   另一条 lineage 声称同一动作身份 → 保守阻断（否则重签就能重置额度）。
6. 并发窗口用既有 `acquireLock`（scope `sensitive:<sha256前32>`）串行化，写入用 `durableWriteFile`（原子）。

## 证据（先 RED 后 GREEN）

| 用例 | RED（改坏什么→报什么） | GREEN |
|---|---|---|
| `TC-AUTH-005` 四类未列明动作分别拒绝、无写盘、HEAD 不动 | 允许未列明动作 → `expected UNAUTHORIZED / actual INTERNAL_ERROR` **FAIL** | `ok 1 - TC-AUTH-005` |
| `TC-AUTH-006` 一次消费、同键重放、跨 operation_id 共享额度、换目标/环境/类型拒绝 | 关掉额度校验 → `expected 1 / actual 0` **FAIL** | `ok 1 - TC-AUTH-006` |
| `TC-AUTH-007` 送达 ACK ≠ 业务消费 | 把 `fail('EXECUTION_CONSUMPTION_REQUIRED')` 改成 `ok({admitted:true})` → **FAIL** | `ok 1 - TC-AUTH-007` |

三条 CP 的四条断言实测满足（exit 0 / `ok 1 - <TC>` / `# fail 0` / `# skipped 0` / `# todo 0`）。
tools 全量：**1061 / 1060 pass / 0 fail / 1 skip**。

## 未做 / 边界

- `TC-AUTH-002`（“不足授权仅补问关键取舍”）**未实现**：它需要先决定签名 schema 里 `acceptance`/`delivery_targets`
  能否为空，属规范修订，不是纯代码（见 multica 记录 `decisions-pending-20261025T153000Z.md#D1`）。
- 准入仍 fail-closed（`EXECUTION_CONSUMPTION_REQUIRED`），是否解除见同一份备忘的 D2。
- 账本只做“同机串行 + 原子写”，不做跨机一致性；跨机共享额度需要服务端账本（当前不在本切片范围）。
