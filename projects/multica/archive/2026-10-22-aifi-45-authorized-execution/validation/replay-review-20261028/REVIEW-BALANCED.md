## 受限复核结论

**Verdict: NOT VERIFIED / 不可升级 PASS（review incomplete）**

本轮仅完成 snapshot manifest 和 replay-snapshot 元数据/结果层面的核对；RUN003 源码、CP-RUN-003/A–L、test-plan/tc-coverage 82–86、R4 正文及 CUSTOM 登记尚未逐项读完，因此不能给出通过结论，也不代作者或既有 reviewer 升级。

### 已核实事实

1. **Manifest 身份与快照范围**
   - `validation/replay-review-20261028/source-manifest.json` 记录 `multica` head = `81e5293adc758e392a045026cf81ec5cc1bac72d`。
   - `../multica` 当前 `git rev-parse HEAD` 与之一致；工作区确有 12 个未提交文件（11 M + 1 `?? server/internal/governance/execution_control_command_attestation_test.go`），与 manifest 的 12 个 multica 条目集合吻合。
   - change 侧 10 个文件 SHA-256 全部与 manifest 一致，包括 `canonical/specs/agent/authorized-runner.yaml`、`test-plan.md`、`tc-coverage-20261025T153000Z.md`、`control-channel-hardening-20261028.md`、R4 三份 review 与 receipts。
   - **未完成**：multica 12 个源码文件逐字节 SHA 重算。我的校验脚本路径写法在 Windows Python 下全部报 MISSING，故这是**校验未完成，不是已证实漂移**。当前只能确认 head 与未提交文件集合，不能确认“快照字节 = 本次复核字节”。

2. **Replay 证据**
   - `replay-snapshot-cp-...meta.json`：exit 0，run 43 / pass 43 / fail 0 / skip 0，leaf_pass 39；stdout 末行 package pass。
   - `replay-snapshot-daemon-...meta.json`：exit 0，run 12 / pass 12 / fail 0 / skip 0，leaf_pass 9。
   - `replay-snapshot-run003-...meta.json`：仅 `^TestTC_RUN_003$`，exit 0，1/1 pass，0.16s；stdout 第 42 行 `--- PASS: TestTC_RUN_003 (0.16s)`。**仅证明该测试进程通过，不证明“真实桥接、requirement 身份、cursor 未覆盖”等语义已被覆盖**；这些源码断言尚未读取。
   - `replay-snapshot-gov-...meta.json`：**exit 1**，run 1128 / pass 1123 / **fail 3** / skip 2，`package_failures: 1`，`error: "test failed, matched no tests, or exposed credentials; inspect evidence"`。stdout 第 4698 行为 package FAIL。此快照不是绿色证据。
   - `replay-snapshot-gov-tools-...meta.json`：exit 0，但 **skip 1**，`error: "test unverified: skipped leaves cannot count as verified; rerun without -skip and with the required environment"`。按该 harness 自身口径，**这次 exit 0 不能计为已验证绿**。

### 发现的问题与严重度

| 严重度 | 问题 | 证据 |
|---|---|---|
| **High** | 全量 governance 快照实际为红：3 个失败、1 个 package failure。任何把该批次描述为“全绿”的总结都与证据冲突。 | `todo-a-20261026/replay-snapshot-gov-20261028T080158Z.meta.json` 的 `test.exit=1`、`counts.fail=3`、`package_failures=1`；stdout 末两行 FAIL |
| **High** | `gov-tools` 虽 exit 0，但被 harness 明确标记 unverified，原因是 skipped leaf；不能作为 82–86 或总体验收的绿色依据。 | `replay-snapshot-gov-tools-20261028T080416Z.meta.json` 的 `counts.skip=1` 与 `error` 字段 |
| **High** | RUN003 的“真实桥接 / requirement 身份 / cursor 未覆盖 / command-verdict replay 冲突 / 真实并发 / DB 隔离”均**未由本轮静态阅读证实**。0.16s 单测通过不足以证明这些语义；是否存在假绿或共享库污染，证据不足。 | `replay-snapshot-run003-...meta.json`；stdout 第 42 行 |
| **Medium** | Manifest 是未提交工作树字节哈希，不是冻结提交；且本轮未重算 multica 12 个文件哈希。快照可能漂移，复核范围受限。 | manifest `limits`；`git status --short` 显示 11 modified + 1 untracked |
| **Medium** | `canonical/specs/agent/authorized-runner.yaml` 的 CP-RUN-003、A–L 是否可按 harness 前提执行并准确映射，尚未核对；change 哈希一致只证明文件未变，不证明内容正确。 | manifest change hash OK；正文未读 |
| **Medium** | `test-plan.md` 与 `tc-coverage` 增量 82–86 的当前/历史口径未审；R4 三份报告及 INCOMPLETE provenance 内容未审。 | 三份 R4 文件哈希匹配，但正文未读 |
| **Medium** | CUSTOM 登记未核。`CUSTOM.md` 为 modified；manifest 未列入新增测试文件 `execution_control_command_attestation_test.go`（untracked），其 CUSTOM 登记/归属尚未确认。 | `git status`；manifest `multica_checkout_sha256` 包含该文件，但它是 `??` |
| **Low/Info** | `gov` 与 `gov-tools` 使用 `-skip=^(TestChannelMigrationAfterUp|...)$`，其中 `gov` skip 2、`gov-tools` skip 1；跳过项与失败项的具体测试名本轮未提取。 | 两份 meta 的 `argv` 与 `counts` |

### 未验证事项（明确列出）

- RUN003 是否真正走 bridge、requirement 身份绑定是否真实、cursor 是否被覆盖或被绕过。
- command/verdict replay 冲突检测是否真实生效，所谓“真实并发”是否只是顺序执行或同事务重放。
- DB 测试是否使用隔离临时库/角色；`original_unchanged: true`、`original_release: {sessions:0,locks:0}` 是 harness 自报，本轮未独立验证共享库无污染。
- CP-RUN-003 与 A–L 的逐条映射及 harness 前置条件。
- test-plan/tc-coverage 82–86 每处“当前 vs 历史”口径是否自洽。
- R4 原报告、INCOMPLETE provenance、CUSTOM 新文件登记是否完整。
- multica 12 个源码文件与 manifest 的字节一致性。

### 范围声明

- 只做了静态读取、哈希比对与 grep/列目录；**未修改文件、未运行测试、未连接数据库、未提交、未发起真实 CR**。
- 由于上述 High 级红/未验证项及复核未完成，**不能给 PASS，也不能把现有 reviewer 结论升级为 PASS**。建议维持受限结论并按上表补齐证据。