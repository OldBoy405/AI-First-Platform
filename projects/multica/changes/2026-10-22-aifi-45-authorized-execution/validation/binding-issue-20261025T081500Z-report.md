# 执行绑定签发（server 侧）— 纵片报告

前缀 `binding-issue-20261025T081500Z-`。原库事故现场继续 HOLD；所有测试只经版本化 `scripts/aifi45-db/run.mjs`，每条 nonce schema-only 库 + 受限 role，先 pin 源码、后核原库与资源。**消费/准入/activation/隔离域仍未实现，`EXECUTION_CONSUMPTION_REQUIRED` 保持。**

## 1. 为什么做这一片

`REQ-AUTH-003 / SC-AUTH-007/008/009` 要求控制证明绑定本进程随机 challenge、实际根与真实任务，且平台只向「daemon_token 认证 + 与 DB 当前 claim 匹配」的可信 daemon 控制子进程签发。T 侧 `requestExecutionBinding` 早已实现 challenge/stdin 证明校验，**服务端签发这一半完全缺失**，所以 T 永远拿不到 `execution-binding/v1`，消费无法开始。

## 2. 交付内容

| 项 | 内容 |
|---|---|
| 新表 | `cr_execution_binding_issue`：append-only 台账，`UNIQUE(workspace_id,cr_id,grant_digest,challenge)`，触发器拒 `UPDATE`/`DELETE`，**无 FK/级联**（迁移 `643`，含 down） |
| 端点 | `POST /api/daemon/crs/{crID}/execution-authorization/binding`（DaemonAuth，仅 `DaemonAuthPathDaemonToken`） |
| 请求 | exact 4 键 `task_id,runtime_id,dispatched_at,challenge`；challenge exact 12 键；`null`/别名/重复键/半参/非 canonical UUID/坏时间/非 64hex/非法 operation/非绝对根全 400 |
| 事务内校验 | `REPEATABLE READ`：`task_id` 指名的行必须同时满足 runtime/代次、active、`cr_id`=URL CR、认证 workspace、所属 daemon；head 必须存在并通过既有撤销/scope/policy/template/source 校验；行 project 必须等于 head payload 的 project；`coordinator_binding` 必须 local_directory 且 `daemon_id` 匹配；challenge 的 digest/revision/policy/template 必须等于 head 事实。任一不符 409，不签不落行 |
| 签名 | `UTF8("execution-binding/v1\0") || raw_payload_bytes`，Ed25519，payload **恰好 20 键**（与 T `requestExecutionBinding` 的期望字段集一致） |
| 幂等 | 同 `(workspace,cr,grant_digest,challenge)` 重放逐字节返回原 envelope 且 `changed=false`；唯一键冲突分支先 `Rollback` 再重读 |
| runner | 新增 `-migration=server/migrations/NNN_x.(up|down).sql`：临时库是冻结原库的 **schema-only 克隆**，新迁移必须显式应用；只允许该目录、记录 sha256 |

## 3. 证据

- `red1`：11RUN/0PASS/11FAIL —— 但**全部是 fixture 缺陷**（CR-ID 形状不符 `CRIDPattern`），按纪律不计业务 RED。
- `green1`：0RUN（`google/uuid` 未使用编译错），不计 RED。
- `green3`：11/11（10 leaf）——迁移用 `-migration=` 应用后首次全绿（含 append-only 触发器、重放幂等、撤销/错 digest/PAT 403/畸形 body）。
- **strong 首轮 2×P1+3×P2**（task↔CR 关联缺失、代次不唯一、JSON null、非 canonical runtime、冲突重读未释放事务）→ 修复：body 增 `task_id`、SQL 改为主键精确取行 + `t.cr_id` 条件、`null` 拒绝、canonical 校验、先 rollback 再重读。
- `green4`：**16RUN/16PASS（15 leaf）**，新增 `task_of_other_cr_rejected`、`task_without_cr_rejected`、`ambiguous_generation_rejected`（跨 task 错配）、`task_id_of_other_cr_task_rejected`、`null_and_noncanonical_rejected`。
- 静态：`go vet ./internal/{handler,service,governance,daemon} ./pkg/protocol` exit0；触碰文件 `gofmt -l` 空；runner `node --test` 9/9。
- 独立回归与 strong 复核见 `…-independent-report.md`、`…-strong-resume1.md`（本轮结果以它们为准，不以作者自测代替）。

### 3.1 冻结链与最终认领

| 轮次 | 冻结 | 结果 | 认领 |
|---|---|---|---|
| `green6`（作者） | 13 项 | 18RUN/18PASS（17 leaf）含 `TestTaskCRAttributionFirstWriterWins`、`relabelled_task_cannot_borrow_another_cr` | 作者证据 |
| `independent-report.md`（`34af297f…`） | 8 项（cr_id 硬化前） | 895/894/0/1（810）、13/13（10）、125/124/0/1（115） | ❌ 历史 |
| `final2-independent-report.md`（`9691e383…`） | 13 项（cr_id 硬化后） | 897/896/0/1（812）、13/13（10）、125/124/0/1（115） | ❌ 历史（互通用例前） |
| `final3-independent-report.md`（`2211d364…`） | 13 项 + 互通 | 900/899/0/1（814）、13/13（10）、125/124/0/1（115） | ❌ 历史（互通负例缺陷 I1 前） |
| **`final4-independent-report.md`（`a080127a…`）** | **13 项（最终源码，含 I1 修正）** | **governance 900/899/0/1（814 leaf）、handler 13/13（10）、daemon 125/124/0/1（115）** | ✅ **本片唯一认领** |

strong：`strong.md`（2×P1 + 3×P2：task↔CR 关联缺失、代次不唯一、JSON null、非 canonical runtime、冲突重读未释放事务）→ `strong-resume1.md`（F2–F5 CLOSED，F1 PARTIAL：`task.cr_id` 可被自报覆盖）→ `strong-resume2.md`（F1 残余 **CLOSED**；首次自报来源、消费/准入/activation/隔离域仍 OPEN）。

每条独立命令：独占 nonce 库/role、前/后 13 项源码一致、原库 137 表/6228 行/82 审批与冻结基线一致、`sessions=0`/`locks=0`、末尾 catalog 无误；governance 那条 meta 记录迁移路径与 sha256 `495ec3c0…`。

### 3.2 跨语言互通（REQ-AUTH-004 / SC-AUTH-010）

新增 `TestExecutionBindingEnvelopeInteropWithToolsVerifier`：走**真实 HTTP** 拿服务端签出的 envelope，再拉起 **Node 子进程**调 T 仓真实的 `requestExecutionBinding`（读它的 `binding_challenge` stdout 行 → 回写 envelope 到它的 stdin）。安装根按 T 的 `deriveInstallRoot`/`installDirectory` 真实布局（`<installDir>/.crctl/keys/<key_id>.pub` + `grants/<scopeHash>-<grant_id>.execution-grant.json`），公钥/head envelope 来自本测试服务。断言：T 接受且 payload 恰好 **20 键**（exit 0）；负例把 payload 内 `task_id` 换成另一个 canonical UUID、**签名不改** → T 拒绝（非 0）。

证据：`interop-20261025T083500Z-red1` **3RUN/3PASS（2 leaf）**，两个子例都真实 PASS（未 Skip）。Skip 条件：未设置 `AIFI45_TOOLS_ROOT` 时跳过（不硬编码工具仓路径）。这是**一致性证明，不是缺陷修复**（写测试前签名域/字段集已一致）。

strong 首轮判：正向互通**成立**（确实调 T 的 `requestExecutionBinding`、回写真实 HTTP envelope、布局符合 T 的安装根语义），但负例缺陷 I1：原先第二个子进程用的是首个进程的旧 challenge，即使去掉验签也会因字段不匹而拒。已修：负例改用**自己子进程**的 challenge 取合法 envelope，只改 `task_id`（仍 canonical，T 只在后续做形状校验），保留原签名 → 回写同一子进程；复核 **I1 CLOSED**（T 的验签前检查——envelope 三键/key_id/规范 base64/64 字节签名/公钥——本次输入均合法；唯一刻意制造的失败是签名不匹配）。

**残余局限（不掩盖）**：负例只断言“非 0 退出”，未精确断言 `cause_code == EXECUTION_GRANT_SIGNATURE_INVALID`；强依赖正常 fixture 环境，因此理论上环境错误也可能让它“看起来通过”。要彻底隔离最好补结构化错误断言（本轮未做，已登记为后续 tightening）。

## 4. 明确未做（不得外推）

- **服务端无法验证进程身份**：`process_id`/`parent_process_id`/两个 root 由 daemon 转述，签发只证明"平台在这个 head/claim 事实上回答了这串 challenge"。daemon 私有 stdio 中继、T 侧消费事务均**未实现**。
- **不可删 activation 本体**：本片的 append-only 只是签发台账的不可变性，不等于 activation 已完成。
- **同 UID 隔离控制域**未做；`EXECUTION_CONSUMPTION_REQUIRED` 未解除；消费仍关闭。
- 旧 claim 锁序 **INCOMPLETE**；完整业务 TC **0/49**；5 major 未关闭；Gate3/提交/推送/部署未获授权。
- 无 FK 是刻意选择（既有 fork 纪律）；跨表一致性靠应用校验，不靠数据库级联。
