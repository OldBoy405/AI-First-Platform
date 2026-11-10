# WP5 M 侧局部收敛：不完整扫描与 accepted 拒收计数（2026-11-05）

**性质**：`server/internal/daemon/crevents.go` 的两处局部行为修正 + 两个新测试。**不是**拒收计数缺陷的完整修复，不改变合同、HOLD、迁移或 Gate。

## 改了什么

| # | 位置 | 行为 |
|---|---|---|
| 1 | `scanOutboxDir` | 原来对 `os.ReadFile` 的**所有**错误 `continue`，令不可读源文件从批次里静默消失，`settleRoot` 仍可返回成功。现在只有 `ENOENT`（枚举后被别的 pass 消费）继续跳过；其他读取失败返回错误，`collectRootWithOptions` 传播错误，源文件与 cursor 保留。 |
| 2 | `collectRootWithOptions` | 在 `validateCRAck` 通过后**立即**清除该批 accepted 文件的拒收计数。原实现只在 `deleteAccepted` 清，而 cursor 写入失败、必需 commit scan 失败或同批存在 rejected 时都会提前返回，旧计数被保留；同文件后来一次拒收就可能误达 3 次而移入 `dead/`。 |

`readOutboxFile` 是可替换的读取 seam（生产即 `os.ReadFile`），只为让读取失败判定在测试中可达；不改变生产调用。

## 实跑证据

- 真实 RED：先加 seam（无行为变化）与两个测试，旧实现下两条**行为性**失败，断言各异：
  - `stale rejection count 2 survived a validated accepted ACK`
  - `events=1 err=<nil>, want a read failure naming the unreadable file`
- 同一测试另含「ACK 不完整（只回一个 accepted）时计数不得清零」的对照，证明清零受完整 ACK 校验门控，而不是仅仅在发送后无条件发生。
- 修复后同命令 PASS（`TestAcceptedAckClearsStaleRejectionCountBeforeCleanup`、`TestScanOutboxDirReportsUnreadableEventFile`、既有 `TestValidateCRAckRequiresCompleteExactBatch`、`TestSettleRootKeepsAcceptedOutboxWhenCommitScanFails`）。
- `go build ./...`、`go vet ./internal/daemon/` 干净（`go1.27.1 windows/amd64`，`GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOWORK=off`）。
- 整包回归用 `-overlay` 对「本次改动前」版本作对照：改动前后失败集合**完全相同**（22 项），pass 叶子 2110 → 2112。22 项为环境性既有失败——无 agent CLI（`claude/codex/...` 未安装）、需要 disposable `DATABASE_URL` 的 DB 用例、缺失可执行文件；与本次改动无关。

## 未覆盖 / 仍 OPEN

- 无真实 DB、真实 daemon、多实例、断电或跨进程证据。
- 读取失败用注入的 `*os.PathError{Err: os.ErrPermission}` 表征，**不是**真实 Windows ACL 拒绝；未做真实权限拒绝夹具。
- 悬空 `*.json` 符号链接的 `ReadFile` 也是 `ENOENT`，仍会被跳过：该目录项留在磁盘且无内容可上报（目标出现后下一 tick 可读），但无法从 `ENOENT` 区分「已被消费」与「悬空链接」。强档只读审查 `01a1aa9d-b282-7374-9f4d-47aad46c8dfa`（请求 `OpenAIPersonal/gpt-6.1-sol:high`，actual unknown）限定三文件未发现新增 P1/P2，并指出此残留与缺失链/混合 ACK/后批失败的测试覆盖缺口。本切片未改该分支。
- 拒收计数仍以**文件名**为键（且所有 root 共用同一个 `rejectCounts`）：两个物理 root 下的同名文件不是“各自分裂计数”，而是**共用同一个计数与同一个清零**（串计、互清）；同一 root 的路径/符号链接别名又会以另一个键呈现。`EvalSymlinks`、`stat`、`SameFile` 单独都不能关闭最终 `rename`/`remove` 前的替换窗口。该缺陷保持 OPEN。
- 计数的清零只有一个所有者：完整且可归因的每批 ACK（`collectRootWithOptions`），以及隔离成功时清自身（`applyAckRejections`）；`deleteAccepted` 自 2026-11-05 起不再清计数（`TestDeleteAcceptedDoesNotOwnRejectionCounters`，`-overlay` 变异可打红）。该去重不改变上述归属缺陷。
- 计数仍为进程内状态，重启从零（已采纳方向，但未与现行合同逐条配对）。
- 3 次后的 `os.Rename` 仍按名字作用，未证明不覆盖 `dead/` 中的同名他人条目；本切片未动该分支。
- 迟到 ACK 删除同名新对象的条件性风险（见 `wp5-outbox-rejection-count-20261104.md`）未解决。
- 未改 `gate-registry.json`、未运行 HOLD 测试、未推进 Gate。

## 快照

raw SHA-256：`crevents.go` `ad70a99b81eafb6f981bc9c6c0e78c6d1cbefe48824ab4fa1577ffbe17989989`；`crevents_test.go` `b80aa6efe8351ed3df6d696f5175a68ed8c92630d6cac23bcf4077d444b9c148`。未单独记录修改前哈希，不能据此证明其他文件未变。
