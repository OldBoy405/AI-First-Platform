# CR 终态 settle fail-closed 与 test-facts 白名单修复

## 范围与结论

用户采纳最小方案并明确实施，同时要求修正监控配置。本次只改 daemon 消费侧与 controlled-shell 只读规则，未改签名协议、事件身份、数据库 schema、Runner 或生产部署；Gate3 仍 NO-GO，TC-RUN-009 未通过。

**组件结论**：CR 绑定任务在无法完成终态 settle 时不再报告 completed；healthy outbox 仍会先投递，非 CR 任务和周期 best-effort 采集不变。真实配置中缺失的 test-facts 只读 `show` 形状已补齐。作者与独立显式环境最终各运行 47 个相关顶层测试，均 exit 0。该结论不等于真实 snapshot、服务端投影、生产入口或 RUN-009 端到端验收。

## 代码修改

### multica

- `server/internal/daemon/daemon.go`
  - 无 CR 绑定任务仍直接返回 nil。
  - CR 绑定任务在 collector 缺失、`PipelineWorkspace` 为空或 root 不在 collector 投影时返回错误。
  - 沿用既有 `settleFailedResult` → `blocked` / `CR_EVENTS_SETTLE_FAILED` → terminal failure 路径，不新增失败分类。
- `server/internal/daemon/crevents.go`
  - 周期 `collectRoot` 保持 commit-scan best-effort。
  - 终态 `settleRoot` 要求 commit scan 成功；scan 失败时仍先投递并 ACK healthy outbox，再返回错误，避免把无关交付积压在失败通道后。
  - scan 失败不推进 cursor；已成功发送的 snapshot 在返回 scan 错误前更新 `lastSnapshot`，避免无意义重发。
- `server/internal/daemon/crevents_test.go`
  - 覆盖无 collector、缺 workspace、root 未纳管、commit scan 失败、outbox 先行、最终 terminal failure、无 CR 绑定不受影响。
  - `TestProposedSnapshotReadShapes` 的真实规则与内联 fixture 均覆盖新增只读形状及近似拒绝例。

### tools

- `skills/shared/controlled-shell/rules.json`
  - `show` 仅新增三种只读形状：
    - `--name-only --format= <40hex>`；
    - `<sha>:change-requests/<CR>/test-report.md`；
    - `<sha>:change-requests/<CR>/trace.tests[.yml/.yaml/.json]`。
  - 未加入写入选项、任意路径、rev 名、 traversal 或 shell flag；既有 `forbiddenFlags` 不变。

### 台账

- multica `CUSTOM.md` #284。
- tools `CUSTOM.md` `CUSTOM-TODO-017`，仍标 pending。

## 监控配置的处理边界

静态核查表明生产 collector 的 roots 来自带身份的 heartbeat `local_directory_snapshot`，正常 pipeline 的 `PipelineWorkspace` 也从该 task 视图选出；`CRWorkspaceRoots` 仅是测试/fixture 兼容面。因此本次**没有**新增静态 root、全局 fallback 或 task-scoped overlay——这些做法可能绕过 snapshot 撤销与 provenance 约束。

实际修复的是当前生效规则文件中对 test-facts 的只读采集缺口。若某任务在终态时 root 已不在投影，现会显式失败并保留 workspace/CR/root/daemon 诊断；这并不证明真实运行配置已错误，也不替代修复服务端 snapshot 投影。部署若另存规则副本，仍须同步核对。

## RED / GREEN 与独立复核

| 阶段 | 结果 | 证据 |
|---|---|---|
| 旧实现，四条静默成功分支 | exit 1；未纳管、无 collector、缺 workspace、commit scan 失败均因返回 nil 而 RED | `AUTHOR-RED.log` |
| 初版实现 | exit 0 | `AUTHOR-GREEN.log` |
| 严格 scan 提前返回导致 outbox 滞留 | exit 1，0 report(s) | `AUTHOR-RED-OUTBOX-FIRST.log` |
| outbox 先行 + 最终 failure 链 | exit 0 | `AUTHOR-GREEN-V2.log` |
| 作者最终定向，vet 开启 | exit 0 | `AUTHOR-FINAL.log` |
| 独立最终定向 | exit 0 | `INDEPENDENT-FINAL.log` |
| 当前全部相关 47 个顶层测试，作者 | exit 0 | `AUTHOR-REGRESSION-FINAL-ALL-V3.log` |
| 当前全部相关 47 个顶层测试，独立显式 Node 环境 | exit 0 | `INDEPENDENT-REGRESSION-FINAL-ALL-NODE.log` |
| 真实 rules / 内联 fixture parity | 均 exit 0 | `AUTHOR-PARITY-REAL-RULES.log`、`AUTHOR-PARITY-INLINE-FIXTURE.log` |

47 是**同一组顶层测试的一次运行计数**，不与定向运行、子测试、历史运行相加。日志未使用 `-v`，不声称逐项 leaf 计数；pattern 与测试总数由当前 `crevents_test.go` 的 46 个顶层测试加 `TestMKb008` 得出。

### 中间失败，未隐藏

- 一次扩大回归因新建 Go 缓存导致磁盘不足；只删除了本轮亲自创建并逐一核对的临时目录。
- 5 个 test-facts 用例最初失败。临时同包诊断证明 `git show` 直接执行成功，而 `crGuardCheck` 返回 `FORBIDDEN_SUBCOMMAND`；补齐 test-report/trace.tests 对象形状后 4 个恢复，再补 `show --name-only` 后第 5 个恢复。诊断文件已删除。
- 独立完整回归前几次失败日志均保留：前置斜杠 `GOTMPDIR` 可复现 `TestMKb003`/`TestMKb008` 的 Windows 路径字符串断言失败；反斜杠形式通过。另一组 5 个 review-payload 失败在独立 shell 完整运行中出现，但相同源码、规则、工具链下，主会话通过，独立逐步诊断也通过；改用显式 Node `spawnSync` 环境后独立完整运行通过。**不宣称该 shell 环境差异的深层原因已完全查明。**

独立代码复核会话 `01a18a55-4e59-7020-aecc-d43a0401144b` 的 B1（outbox 滞留）、B5（终态 failure 链）、lastSnapshot 次序和规则形状问题已修订；最终复核称本次修改集无组件内 BLOCK。独立测试会话为 `01a18a62-9f78-7020-aecc-d4417f07e6ab`、`01a18a69-ce1d-7020-aecc-d444c4ac2b03`。所有复核均请求与主会话相同的 `Gobao/deepseek-flash`、reasoning max；实际 backend 回执 unknown。

## 明确未关闭

- `applyReview` 的错误会传播为 `INGEST_FAILED`；但 `applyStatus` 经 `projectGateTransition` 吞掉投影错误后仍可能 processed/ACK。这是独立服务端问题，本次未改。
- test-facts 对一般读取失败仍有跳过语义；当前实际规则下已验证的形状可读，但旧规则副本、未来规则漂移和其他读取错误仍可能使事实缺失。
- 未验证真实 heartbeat/root 配置、路径别名、生产规则副本、服务端对既有 `CR_EVENTS_SETTLE_FAILED` 的接受、真实 Runner 行为、数据库、部署或恢复。
- 未运行整个 daemon 包、真实 DB、容器、真实 CR 或端到端 RUN-009；不得据此关闭 RUN-009、RUN-007/008、EVD-008 或 Gate3。

## 最终原始 SHA-256

| 文件 | SHA-256 |
|---|---|
| multica `daemon.go` | `0ff63f5d13e198f35335e823075c7acef0778d9d2ec9adc524dc6cb2653f1fc4` |
| multica `crevents.go` | `8d2076eb5f0d4102ae26bf0a4a5e21cd382d0bdb0a2e74f256a0449f667b2714` |
| multica `crevents_test.go` | `06ba7977593054ab0074a02a62e578bb1be35d2d6edabf70452c678f86863a25` |
| tools `rules.json` | `0c00e331e1cc882f7107b130ed1c467822f40750bd360969fa08d374816a9d6d` |

两仓相关文件 `git diff --check` 均通过；未改写历史证据或运行部署/清理真实资源。
