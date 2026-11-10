# X6 收敛方案（aac9e7c 版）— strong 独立只读复核（设计 + 源码两轮合并，2026-10-28）

> **结论：静态 BLOCK。** 本文仅为静态读档/读源复核记录，**不是**实现、Gate 通过、审批、验收或部署结论。
> - 请求档位为 strong；本文不把模型请求当作实际后端身份证明。
> - 复核期间**未修改**被审方案、design、canonical、源码或任何先前报告；**未运行测试，未连接 DB/容器，未发送通知，未检查生产部署、镜像、定时任务或仓外调用者**。
> - PostgreSQL 可见性、锁、`ON CONFLICT`、INVALID 索引行为均为**未实测推断**。“已核”仅指在下列 SHA 的文件中静态读到。
> - 本文**不断言**任何仓外调用、部署状态或 646 是否已上线。
> - 先前报告原样保留：`ntf-scope-x6-review-strong-20261028.md`、`ntf-x6-convergence-review-strong-20261028.md`、`ntf-x6-convergence-recheck-strong-20261028.md`（后者只覆盖 `7ece53e0…` 旧版，不覆盖本版）。

## 1. 对象与快照（写入前重算，两轮期间未变）

### 1.1 设计侧（AI First Platform 仓，本变更目录相对路径）

| 对象 | raw sha256 |
|---|---|
| 被审：`validation/ntf-x6-canonical-convergence-20261028.md`（110 行） | `aac9e7c18aac14c8da70e69c6ac9edef131e1e0eaf917196df607140899fc097` |
| `design.md`（§5 = L74–84） | `c97d10135d1f3ad1783ac2d39d3343123e89428b415e1579436fd8084bcfec3b` |
| `canonical/specs/code/attention-routing.yaml`（REQ-NTF-003 = L39–65） | `ad774f8b830d3c0979e2d5ba065f36025559b63efabc759d6e56cd5e3939d5f7` |
| 先前定向复核 `validation/ntf-x6-convergence-recheck-strong-20261028.md`（审 `7ece53e013a077d48a843e9c4bb7882c7834c71cfac90dab2a699baa4c06c7f6`） | `7b5e3fe5ddd2eb134dee3cde9753e111aefa32cf4150afc999b7fc379bb93730` |
| 先前 `validation/ntf-x6-convergence-review-strong-20261028.md` | `c6e8ba2db0eb5865149bfce17f7f57dee802ccca6201c75e08b7688378df28ce` |
| 先前 `validation/ntf-scope-x6-review-strong-20261028.md` | `d71cf020e708227317580fe49e7d1b7d538097d89e94d9d8ba8879b18e17fe34` |

被审版 SHA ≠ 先前定向复核所审 `7ece53e0…`，故本文为对新版的独立复核，旧复核结论不自动沿用。

### 1.2 源码侧（sibling `multica` 当前工作树，HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d`）

| 文件 | raw sha256（工作树字节） | git blob 工作树 / HEAD |
|---|---|---|
| `server/internal/governance/execution_notice.go`（515 行） | `3c523681b010b4c70f4ba96122d57851f21801c5bef4e9ea9b9c7727f819085f` | `22749eafb6d75144bf2f87775f4467538914b4cd` / `8d6bcce4c0bce4b1be770896e93998ed9f63152e`（**未提交改动**，另一作者，非 X6） |
| `server/migrations/646_cr_execution_notice.up.sql`（30 行） | `5f2725841b6775816b7b1cf29e6720f80fa23bb3d4e6abcac5bf32e28256b55d` | `553b15f0af62e23c7ca7ae1f1b65d759c3d090e5`（同 HEAD） |
| `server/migrations/646_cr_execution_notice.down.sql`（4 行） | `ba4cb26eccdb543ed5143f6622bd16c51c7c8efc589c304a98b24314c67e30fe` | `bf378b71c742f3bc6630e61b76f987376d7d5de0`（同 HEAD） |
| `server/cmd/migrate/main.go`（1139 行） | `9708fb56d50d081ddc9d499b2bbe8ab92605c0df3fd8670507cda065f0b5d30b` | `6e54cafff3717522b68e5685c2a8bc3db66e7b50`（同 HEAD） |
| `packages/core/inbox/ws-updaters.ts`（237 行） | `7e902d693420778255a6fe03779b93f00fc741e87f90cef877a6965c58c18cee` | `801bdf88ad483ee5f856a2a7dd246c99464ad3bc`（同 HEAD） |
| `packages/core/realtime/use-realtime-sync.ts` | `0653d3d2ad437b012252613e513c68dc119cca6988620b37172e533aed90de0d` | `3d8c66def3d8f58a41f508f85c721c463719d44d`（同 HEAD） |
| `apps/mobile/data/realtime/use-inbox-realtime.ts`（86 行） | `1295f51eb9d1c8a6ba9fd361a21782e6299b57351eeeb49151347bf52dae0a8f` | `aa18618173e602b682cc6851ea83758b6d36a67b`（同 HEAD） |

raw sha256 与 blob 不同源（git 提示 CRLF 规范化），两者分别记录。

## 2. 第一轮：设计复核（被审方案 vs design §5 / canonical / 先前复核）

### 2.1 先前复核所提修订在本版文字中的落实

| 先前问题 | 本版位置 | 判定 |
|---|---|---|
| §4 “状态更新保护仅作补充”会致重播 | L79 改为“不以旧表 UPDATE 守卫作隔离或补充保障” | 文字矛盾已消除 |
| up/down 两向每版本单 hook 覆盖 | L85 写明同版本同方向多 hook 须显式组合、down 先安全检查再清理再 SQL | 文字已补；能力不存在（见 §3.3） |
| 索引有效性仅启用前检查 | L36 改为每副本启动/重启/加入服务前检查 | 文字已补 |
| 引用未提交广播改动 | L52 注明属另一作者未提交改动 | 已注明 |
| 追溯链接 | L3 链接 `ntf-x6-convergence-review-strong`，**未链接** `ntf-x6-convergence-recheck-strong` | 部分 |
| SC-NTF-006/007 偏离无 ADJ | L73 明确 NO-GO / 未就绪，不自建 ADJ | 以未就绪声明处理；偏离本身未消除 |
| 撤权 pending 无终态 | L47 “是否取消…尚待批准” | **未决** |

### 2.2 仍未消除的设计矛盾

1. design §5 L80 “旧通知无该字段，行为不变” vs 方案 L64/L73 旧行阻断新通知；L73 承认兼容风险，未消除。
2. design L78 “同 CR 跨 run 保持键” vs 方案 L21 失败发生身份仅定义跨 commit，跨 run 的重放/新失败边界未定义。
3. `backlog-b-disposition-20261026.md` X6 旧决议与 `CUSTOM.md #195` 未同步；方案 L10 仅声明其不构成授权。
4. 方案 §3 旧 pending 永不由新恢复器恢复，与 SC-NTF-007（canonical L58–63）冲突，方案 L73、L106 自认阻断。

## 3. 第二轮：源码复核（仅静态读当前工作树）

### 3.1 `execution_notice.go` — 旧恢复先广播后 UPDATE（已核）

- 工作树 `RecoverPendingNotices` L338–383：L346–349 无锁 SELECT 全部 pending（无 `FOR UPDATE`/`SKIP LOCKED`）→ L366 广播 → L369–371 `UPDATE … SET state=delivered WHERE workspace_id=$1 AND id=$3`，**不以 `state='pending'` 或版本为条件**。多恢复器并发可重复广播；拒绝 UPDATE 发生在广播之后，不能构成隔离。投递路径同序：L318 广播，L325–327 UPDATE。
- **HEAD 版多版本风险（方案未写）**：HEAD `RecoverPendingNotices` L365–369 在 `broadcast == nil` 时跳过广播、L370 仍标 delivered；HEAD `BusBroadcaster` L389–390 在 `bus == nil` 时返回 nil 视为成功。即 HEAD 语义下旧二进制可能**未广播即静默标 delivered（丢提醒）**。工作树已改为强制非空（L255–257、L342–344、L391–396），但属未提交改动；新旧二进制混跑时语义不一致。
- **仓内无生产调用者**：对工作树与 HEAD 的非 `_test.go` Go 源 grep，`DeliverNotice`、`RecoverPendingNotices`、`BusBroadcaster` 只有定义；`cr_execution_notice` 非测试引用仅 `execution_notice.go`、646 up/down 与 `CUSTOM.md`。这**仅**说明仓内未接线，**不能**推出仓外、已部署镜像或定时任务不存在调用者——未检查。
- **Loader 缺 details**：L438 只 SELECT `recipient_id, type, severity, title, body, read, archived`，L443–455 组装的 item 无 `details`；L304 写 `inbox_item` 也不写 `details`。
- **去重键（方案未写）**：L130–133 = `sha256(join(["cr-execution-notice/v1", crID, cause, evidenceDigest, audience], "\x00"))`。不含 project、recipient、失败发生身份（workspace 由唯一索引补）。同 CR/cause/evidence/audience 换 recipient 会被 L274 `ON CONFLICT (workspace_id, dedupe_key) DO NOTHING` 吞并，违反 SC-NTF-006 “接收者变化”。
- **冲突回读**：L276–293 同事务内另一 SELECT 只取 `id, inbox_item_id, state`，**不比对身份**即视为幂等成功。
- **授权**：L486–497 authorizer 仅校验 member 存在；L499–504 maintainer 取最早 `owner/admin`。均非业务授权，与方案 L78 描述一致。

### 3.2 迁移 646（已核，与 HEAD 一致）

- up：L10–21 建 `cr_execution_notice`，L7–9 注释刻意无 FK；L15/L18 CHECK 闭集；L25–26 `UNIQUE (workspace_id, dedupe_key)`；L28–30 `(workspace_id, created_at) WHERE state='pending'`。均**非** CONCURRENTLY，`main.go` 中无 646 登记（grep 无匹配）。
- down：L2–4 依次 DROP 两索引与 `DROP TABLE IF EXISTS cr_execution_notice`，**破坏性**，源码层无回退守卫。
- 646 是否已部署：**未核**。

### 3.3 `server/cmd/migrate/main.go` — 并发 index hook（已核，与 HEAD 一致）

- `preMigrationHooks` L449–459：3 个固定 hook 后 L456 `hooks[version] = cleanupInvalidConcurrentIndexHook(index)`；`preRollbackHooks` L461–474：L464、L470、L472 依次赋值。**每版本一个 hook，后写覆盖前写，无组合机制。**
- `cleanupInvalidConcurrentIndexHook` L732–763：仅按名称 `to_regclass` + `indisvalid`（L736–742），INVALID 时 L757 `DROP INDEX CONCURRENTLY`；**不校验表达式/谓词**，同名异定义视为有效（L752–753）。
- 执行器 L1043–1110：循环不包事务（L1006–1008），advisory lock 串行（L1015）；顺序 hook（L1074–1079）→ 条件（L1083–1088）→ SQL（L1091）→ 记账（L1096–1103），**SQL 与版本记录分两次执行**；多语句文件经单次 `conn.Exec`（L1091），隐式事务行为未证。
- 仓内可参照的回退守卫：`ensureSourceContextRollbackSafe`（L562）、`refuseChannelChatRouteHistoryRollback`（L491）；X6 所需“存在 v2 时拒绝 down”的 hook **不存在**。

### 3.4 客户端重放（已核，与 HEAD 一致）

- `ws-updaters.ts`：L40–43 仅 `details.execution_notification_key` 非空才属新策略；L50–59 claim 存于 QueryClient 缓存（L45–46 key 含 workspace+Inbox ID），legacy 恒放行；L73–85 `onInboxNew` 仅失效刷新。
- `use-realtime-sync.ts`：静音（L620）、焦点（L625）先于 claim（L630）；新策略 OS tag `workspace:id`（L644–646）；显示失败释放（L668–686、L694）。
- 结合 §3.1：服务端 payload 与行均无 key → 执行通知在客户端**恒走 legacy 路径**，每次重播均弹提醒，不受 claim 约束。claim 范围仅单 QueryClient/session。
- mobile `use-inbox-realtime.ts`：L51 `inbox:new` 与 L81 重连仅刷新列表/未读，无提醒、无 claim。

## 4. 六项硬阻断结论（静态）

| # | 阻断 | 方案条件写出 | 源码已证事实 | 结论 |
|---|---|---|---|---|
| 1 | 旧恢复广播前隔离与多版本 | L67、L69、L79、L96 | 先广播后无条件 UPDATE、无锁（L346–371）；HEAD 版 nil broadcast/bus 静默标 delivered；仓内无调用者（仓外未查） | **BLOCK**（多版本风险重于方案所写） |
| 2 | project/recipient 授权 | L22、L77–78 | 仅 member / 最早 owner-admin（L486–504）；键无 project/recipient | **BLOCK** |
| 3 | claim/撤权 TOCTOU | L46–47 | 无 claim、无租约、广播前无授权复核 | **BLOCK**（协议不存在；撤权终态未决） |
| 4 | index concurrent hook / INVALID / rollback | L36、L85–87、L97 | 单 hook 覆盖（L456、L464–472）；hook 不校验定义；SQL/记账两步；646 down 破坏性无守卫 | **BLOCK** |
| 5 | 引用真实性 | L52、L69、L85 等 | 所引事实与源码相符；但漏写“键缺 recipient/project”“HEAD 静默标 delivered”；L3 缺先前定向复核链接 | **限定**（属实但不完整） |
| 6 | client replay | L52、L54、L99 | 服务端不下发 key → 恒 legacy；claim 仅会话内；mobile 仅刷新 | **BLOCK** |

总体：**静态 BLOCK**。最新改文消除了先前复核指出的若干**文字**矛盾（§2.1），但没有一项阻断被实现或证明，§2.2 的设计矛盾仍在。

## 5. 最小接续切片（建议，未执行）

1. 方案补写源码事实：去重键缺 recipient/project；HEAD 版 nil broadcast/bus 静默标 delivered 的混版本丢提醒风险；仓内无调用者、仓外与已部署调用方须另行清点；补链接 `ntf-x6-convergence-recheck-strong-20261028.md` 与本文。
2. 决策：旧恢复器的广播前拦截手段；撤权 pending 终态；SC-NTF-006/007 偏离走正式 ADJ 或在 canonical 标未就绪；同步 backlog-b 与 `CUSTOM.md #195`；定义跨 run 失败发生身份。
3. 设计（不实现）`main.go` 组合 hook 与索引定义（表达式/谓词）校验，以及 v2 存在时的 down 拒绝 hook。
4. 经授权的隔离 DB RED：并发 recover 重复广播；nil broadcast/bus 丢 pending；换 recipient 被吞；646 down 销毁数据；`READ COMMITTED` 冲突回读。

## 6. 未核与限制

- 生产部署、实例版本、镜像、定时任务、仓外调用者、646 是否已上线、应用角色权限：**未检查**。
- DB/容器/测试：**未访问、未运行**；PG 语义均为推断。
- 本文写入前重算 §1 全部 SHA，与两轮阅读时一致；作者若再改方案或源码，本文不自动覆盖新版。
