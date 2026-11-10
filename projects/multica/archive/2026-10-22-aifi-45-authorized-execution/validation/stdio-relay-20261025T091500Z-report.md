# stdio-relay 片 · 增量 1：daemon 侧绑定客户端（已完成，组件级）

## 做了什么

在这一片之前，**没有任何产品代码调用绑定签发端点**：`POST /api/daemon/crs/{crID}/execution-authorization/binding` 只接受 daemon 令牌，但 daemon 侧没有客户端；`crctl authorization-bind` 又必须显式 `--binding-stdio`，等于「T 在等一个不存在的对端」。本增量补上对端的一半。

新增 `multica/server/internal/daemon/execution_binding_client.go`：

- `Client.requestExecutionBinding(ctx, crID, executionBindingRequest) (executionBinding, error)`。
- body **恰好四键** `task_id`/`runtime_id`/`dispatched_at`/`challenge`，`challenge` 以 `json.RawMessage` 透传。
- 返回 `Envelope`（原始字节）与 `Changed`（服务端是否新签）。
- 早退：空 CR ID、空 challenge 都**不发网络请求**；200 但无 envelope 视为错误（不产生"空证明"）。

## RED 有牙齿（两次才成立）

| 轮次 | 场景 | 结果 |
|---|---|---|
| `red1` | 用 map 重编码 challenge 的朴素实现 | **7/7 全过 —— 假绿** |
| `red2` | 同上，但断言改为「challenge 按子进程的**键序**到达」 | **6 PASS / 1 FAIL**（`execution_binding_client_test.go:100: challenge was re-encoded instead of passed through in order`） |
| `green2` | 还原为 RawMessage 透传 | 7/7，6 leaf |

`red1` 的教训：最初的断言只查 `"process_id":42` 存在，而 `encoding/json` 对 `RawMessage` 只会 **compact**（不去键序），map 重编码也只是把键排序 —— 两者都能通过该断言。也就是说**第一个断言没有鉴别力**，`red1` 的"全绿"是假证据，已作为反例保留。

鉴别力来自键序：正确的透传保留 `schema → challenge → install_root → …`；map 重编码会变成字典序（`authorization_revision` 打头）。**事后更正（strong resume1）：这不是密码学要求。** 服务端把 challenge **逐字段解码校验**后，用自己的 20 键 payload 签名，challenge 只作为其中的 64 位 hex nonce 值；所以键序变化不会让签名失败。这条断言真正的价值是：中继不应在没有理由的情况下**重构**子进程给自己的输入（避免引入解析差异），而不是“重排就裂”。原本写成“服务端按该字节算摘要”是错的，已改正。

## 明确没做

- **没有**接入 `handleTask`：中继是一个可测试单元，但今天**没有真实调用点**（下一增量）。
- **没有**打开消费或准入；`EXECUTION_CONSUMPTION_REQUIRED` 不变；T 的 `EXECUTION_CONSUMPTION_REQUIRED` 非零退出被如实上报，**不**当作中继失败或准入。
- 不签隔离域、activation、全局 C1。

---

# 增量 2：daemon 私有中继（已完成，组件级）

`server/internal/daemon/execution_binding_relay.go`：

daemon spawn `crctl authorization-bind --binding-stdio` 子进程 → 从 stdout 读到 `{"binding_challenge":{…}}` → 用增量 1 的客户端让平台签**同一串字节** → 把 `{"envelope":<raw>}` 写回子进程 stdin → 关管道 → wait。

不变量：

1. **不重构输入**：challenge 直接转给服务端、envelope 原样回子进程，中继不发明自己的编码（键序/空白变化本身不影响验签——服务端与 T 各自解析字段值；真正的字节级对象是 `payload_b64` 及其签名，不能被重算）。
2. **fail-closed**：签发失败时**不写任何字节**直接关管道——子进程拿不到半份证明（`relay-red1` 就是把这个契约改坏后抓到的）。
3. **非零退出不是失败**：T 在校验后主动以 `EXECUTION_CONSUMPTION_REQUIRED` 退出（消费仍关闭），中继把它当 `ExitCode`/`StderrTail` 如实上报，调用方不得读成准入。
4. **弱限不耗内存**：challenge 128KiB、stderr 32KiB 封顶；stdout 噪音行跳过，只接“仅含 `binding_challenge` 对象”的形态（`relay-red2` 抓的是 envelope 被替换）。

## 证据

| 轮次 | 内容 | 结果 |
|---|---|---|
| `relay-green1` | 初版实现 | 7RUN/6PASS/1SKIP（5 leaf） |
| `relay-red1` | 把 fail-closed 改成“失败仍返回 nil” | **1 FAIL**：`err = nil, want the refusal` |
| `relay-red2` | 把 envelope 换成 `{}` | **2 FAIL**：`child received:` 不等 + 上一项仍在 |
| `relay-green2` | 还原 + 与增量 1 一起跑 | 14RUN/13PASS/1SKIP（11 leaf） |
| `relay-green4` | 修“超时杀进程被当普通拒绝”后（含专项 hang 测试） | **15RUN/14PASS/1SKIP（12 leaf）** |

## 非作者独立回归抓到的一个真缺陷（green3 → green4）

独立面（`…-independent2-report.md`）在 green3 上做“子进程写出 challenge 后不读 stdin、不退出”实验：实测 **30.00s 返回 `err=nil`、ExitCode=1**。原因：中继把 `cmd.Wait()` 的 `*ExitError` 一律当“T 自己以非零退出”——而 deadline 到期后**被我们杀掉**的子进程也是 `*ExitError`。

后果是真实可观测错误：调用方无法区分“T 校验完主动拒绝”与“中继杀了一个卡死的子进程”。green4 改为 Wait 后先看 `ctx.Err()`，非空就返回 wrap 了 deadline 的错误；并新增 `TestExecutionBindingRelayStopsWhenTheChildNeverFinishes`（500ms ctx，断言 error 且 wrap `DeadlineExceeded`、耗时 ≤ 10s）防回退。

那轮独立实验的两个 mutation（fail-closed→`return nil`、裸 envelope→外壳）均被现有测试抓到，且两轮 mutation 后 4/4 hash 还原一致。

## strong 首轮抓到的真实缺陷（都已在 green3 修）

1. **写回形态错了**：原来包一层 `{"envelope":…}`，而 T 的 `readProof` 把 stdin 当**证明文档本体**。写完测试还是绿的，因为我的合成 helper 也跟着错——**测试把错误假设当成了契约**。现改为裸 envelope，并加一条“开头不得是 `{"envelope":`”的断言。
2. **无界等待**：无 deadline 时 `Write`/`Wait` 没有完成保证。现为自设 30s（T 自设 15s）+ `cmd.WaitDelay=5s`。strong 判 **PARTIAL**（极端组合下写端不保证被关；单次 envelope 写入远小于管道缓冲，实际暴露有界，留待 phase 末复判）。
3. **reader 泄漏**：EOF 的 send 不受 ctx 保护。现在 `select` 到 ctx.Done。

另：strong 主动**更正**了它上一轮的“端到端逐字节 OPEN”——服务端签的是自建 payload，HTTP compact 不构成验签缺陷；本报告上方相关表述已同步改正。

`red1` 第一个探针当时**没打中**（替换字符串没匹配上，`DeliversEnvelopeToThisRun` 仍绿）；重打后才是真正的 `relay-red2`。这一条与增量 1 的 `red1` 同类：**没抓到不算证据**，已分别保留为反例。

## 仍未做

- 未接 `handleTask`（无真实调用点，所以今天它是“能用的零件”不是“已生效的行为”）。
- 同 UID 对手仍可读同 UID 管道；真正边界要容器。
- 消费/准入/activation/隔离域/全局 C1 均未签。

## 下一步（同片增量 2，未开始）

按 seam 调查（`runTask` → `agent.ResolveBackend` → `Backend.Execute` → `Command.exec`/`newRuntimeCmd`，单一 exec 点，全仓 `ExtraFiles` 零使用）二选一：

- **env + per-run 0600 文件**（最小）：`taskTempDir` 每次 run 新建 0700、结束即删，可作为交付路径；`MULTICA_` 前缀已被 `isBlockedEnvKey` 保护，agent 的 `custom_env` 覆盖不了。
- **ExtraFiles 附加 fd**（更接近"私有 stdio"）：需在 `pkg/agent` 的 `Config`/`Command`/`newRuntimeCmd` 三处透传，且 Windows 不支持。

两者都**不防同 UID 对手**（同 UID 可读同 UID 的任何文件/管道），真正的边界要容器，见 `trust-root-20261025T084600Z-report.md`。

## 终轮独立回归（green4，唯一认领）

非作者（DB 独占）在 `…-independent3-report.md` 报告：

| 项 | 值 |
|---|---|
| RUN/PASS/FAIL/SKIP | **140 / 138 / 0 / 2** |
| PASS leaf / SKIP leaf | **127 / 2** |
| `TestExecutionBindingRelayStopsWhenTheChildNeverFinishes` | **PASS**（0.5s，非 SKIP） |
| 原库 | 137 表 / 6228 行 / 82 审批 ID+hash，前后一致 |
| 安全 | `error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0` |
| 4/4 hash | 跑前跑后一致（清单 `…-relay-green4-source-manifest.json`） |

两个 SKIP：`TestExecutionBindingRelayHelperProcess`（helper 子进程，设计如此）、Windows symlink 那条（环境限制）。**均不计 PASS。**

**冻结链**：green1（初版）→ red1/red2（mutation 探针）→ green2 → green3（strong 三项 P2 修复）→ **green4（终轮，已认领）**。green1–green3 一律作为历史，不认领。

**仍然成立**：中继没有接入 `handleTask`（产品里无调用点）；不构成隔离（同 UID 可读同 UID 管道）；消费/准入关闭；不签 activation/隔离执行域/全局 C1；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；原库 HOLD。
