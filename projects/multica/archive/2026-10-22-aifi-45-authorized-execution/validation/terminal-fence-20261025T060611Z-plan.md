# 终态callback完整代次fence纵片（BUILD继续）

用户已要求“继续，非必要不停下来”；前片claim/project组件19项已独立851/851、13/13、112P/1 Windows SKIP，限定静态完成、宿主最后只读137表/82审批不变、37对精确临时库role不存在、四包vet通过。**这不代表完整terminal链已修。** 原库HOLD/0完整TC/5major/消费关闭与Gate边界保持。

## 已核事实与最小落点

见 `claim-project-20261025T052646Z-terminal-fence-facts.md` 及 `terminal-fence-20261025-complete-tx-facts.md`：reclaim复用task行换dispatched_at；当前terminal report/body/outbox只有taskID；Fail/Complete SQL仅id+status CAS。Complete的CAS前可能锁chat_session→maturity advisory并写Inbox，但CAS零行返回ErrNoRows会让实际runInTx回滚。**不新增前置task/runtime行锁**以免改变旧锁序；以现有CAS位置追加optional generation与真实MDT scope谓词，零行继续回滚前置写。

## 计划和验收顺序

1. 公开MDT fail HTTP首个真实RED：旧gen1 body runtime_id/dispatched_at送到已重领gen2 running任务，应409且无写/重试/通知副作用；当前忽略字段会终结gen2。先一个，不拿编译错当RED。
2. 给现有CompleteAgentTask/FailAgentTask SQL CAS增加显式enforce_claim bool及claim runtime/generation/auth workspace/daemon参数。false保留legacy，true缺参拒绝；新增条件在现有WHERE，不复制整套UPDATE或加前置锁。运行版本化make sqlc（固定v1.31.1；已安装同版）并核生成差异，禁止手编生成列或覆盖前脏改。无新表/迁移/FK。
3. 服务增加严格ForClaim路径共享既有事务/副作用逻辑，要求真实TxStarter；正确代次终态重放幂等，generation mismatch或active CAS零行是明确stale claim，不能被现有ErrNoRows分支当“已终态成功”；所有副作用只在transitioned时。
4. handler新字段二者同时存在/同时缺失，strict时间先检查原token微秒精度，真实MDT认证workspace/daemon来自context。旧无字段路径暂按legacy，后续非可删activation解决强制防降级，**本片不冒充已关闭legacy bypass major**。
5. daemon在handleTask入口保存真实claimed tuple到context，集中terminalReport取同task上下文并携带字段；不枚举漏改上百个早退。HTTP SDK qualified complete/fail、补偿、outbox持久化/重放/去重均保留代次；legacy v1/v2记录继续解码，无凭据入文件。缺失/无效new tuple不得退taskID-only。
6. 每段公开RED→最小GREEN；补stale/同代成功/重放/异runtime/异daemon/半参/时间截断/legacy兼容及outbox隔代不覆盖、compensation fence。真正新库端到端+非作者回归/strong审核后继续下一片。

## 已执行（按 tag，作者证据；均为每命令独占 nonce 库+原库前后一致+27 项源码 pin 后核）

| tag | 结果 | 说明 |
|---|---|---|
| `fail-red1` | 1RUN/1FAIL | 旧 gen1 fail 对 gen2 running 得 200 且 status=failed（真实业务 RED） |
| `fail-green1` | 1/1 | 同 CAS 位置加代次谓词后 409 且仍 running |
| `sdk/…` | — | 见前片；本片 SDK 用于 SDK→MDT→HTTP 贯通 |
| `fail-matrix-green1` | 13RUN/11P/2F | 第 1 轮 fixture 触发 `agent_runtime_workspace_daemon_provider_key` 唯一键冲突（fixture 缺陷，非业务 RED） |
| `fail-matrix-green2` | 13/13（12 leaf） | 仅把 otherRuntime 的 daemon_id 改为独占值 |
| `complete-red1` | 1RUN/1FAIL | 旧 gen1 complete 对 gen2 running 得 200 且 status=completed |
| `complete-green1` | 1/1 | Complete 走同一可选代次参数 |
| `foreign-replay-red1` | 1RUN/1FAIL | 同 workspace 另一真实 MDT 用同 tuple 回放终态得 200（strong 发现 P2 真实复现） |
| `foreign-replay-green1` | 1/1 | 终态幂等改为单条 scoped SELECT 重验 owner/scope |
| `http-green1` | 15/15（14 leaf） | 终态 HTTP 矩阵合并 |
| `overlay-red1` | 0RUN | 测试 import 错包（`internal/featureflag`）导致模块查找失败；**不算业务 RED** |
| `overlay-red2` | 1RUN/1FAIL | stale 回调仍调用 `BuildTaskOverlay`（calls=1） |
| `overlay-green1` | 1/1 | strict 路径在 CAS 前先读 scoped 记录并短路，calls=0 |
| `sender-store-red1` | 6RUN/6F | sender 不带两键、缺参仍发送、store 丢 tuple、同 task 两代互相冲突 |
| `sender-store-green1` | 6/6（5 leaf） | `clientForTerminalClaim`+`deliveryKey`+record v3 |
| `daemon-attach-red1` | 1RUN/1FAIL | 已验证 claim 后 `reportTerminalTask` 仍 legacy |
| `daemon-attach-green1` | 7RUN/6P/1F | 实现后 acknowledge 仍按 taskID 校验文件名（实现自身遗漏） |
| `daemon-attach-green2` | 7/7（6 leaf） | `acknowledge`/`terminalReportFileName` 统一走 `deliveryKey` |
| `queue-green1` | 未运行 | 参数放错（flag 在 evidence-prefix 之前），runner `usage` 退出；不算 RED |
| `queue-green2` | 未运行 | 同上，顺序仍错 |
| `queue-green3` | 35/35（31 leaf） | `^Test(TerminalReport|SendTerminalTaskReport)` 全绿，含既有 queue 测试在 v3 信封下 |

## 尚未关闭（本片继续做，不冒充已修）

- **retryable fail 的 Composio 外部副作用**：stale 已被 pre-check 挡住（`overlay-green1`），但**有效代次**在事务失败时仍可能已创建外部 session（`BuildTaskOverlay` 是真实 POST `/tool_router/session`），数据库回滚不撤销外部资源。`terminal-fence-20261025-retry-overlay-facts.md` 已给最小落点（事务后构建 + deferred `fire_at` 回填），**尚未实现**。
- **进程重启后的重放语义**：内存 map 为空时，outbox 里的 generation 记录仍带 tuple（record v3 落盘），但 restart 后新 claim 到来前，同 task 的旧 legacy 记录重放仍是 legacy；此组合尚无测试。
- **Complete 完整矩阵**：仅 1 个 stale 用例；半参/坏时间/重复键/别名/跨 daemon 回放/重放幂等对 Complete 尚未逐条覆盖（Fail 已覆盖）。
- **动态并发**：CAS 与 scoped SELECT 之间的并发快照 race 未做动态证明；静态结论不外推。
- **legacy 无字段路径仍被接受**：这不关闭「不可删 activation / 防降级」major，也不等于生产可信准入。

## 执行纪律

主会话产品，balanced写独立测试/事实调查，必要strong独立。M native models在06:06:11Z重读schema1/configured balanced Gobao/deepseek-flash/max、strong OpenAIPersonal/gpt-6.1-sol/high，actual unknown。DB单执行权主会话；每条run.mjs独占nonce schema-only库/role，先wx源码manifest/原库原行证据，后即时与冻结137表/82审批对照、session锁0及exact catalog资源不存在；否则STOP。不原库测试/写、不共享库、不真实CR/模型调用。Gate3/commit/push/部署仍未授权。
