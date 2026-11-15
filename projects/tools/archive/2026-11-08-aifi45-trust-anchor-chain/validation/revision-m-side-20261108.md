# 修订：M 侧现状与「真实闭环」的真实缺口（2026-11-08）

用户决定：**10 条全是条款级 → 先补真实 M 闭环再签 Gate 3**。
因此本文件先纠正上一份 test-report 里的一处**事实错误**，再给出最小补齐路径。

## 1. 纠正：test-report §7.4 的说法是错的

上一份报告写「M 侧 Go 实现（`ExecutionAuthorization` / binding issue / daemon relay / trust root 安装）本轮未做」。
**核实后不成立**，四项里三项已有实现：

| 设计落点 | 实际状态 | 证据 |
|---|---|---|
| `BuildExecutionAuthorization` | **已存在**，且对**原始 bytes** 计算 `sha256`、生成逐字段 `json-pointer` 绑定 | `server/internal/governance/execution_authorization.go:259`（函数）、`:331`（bindings）、`:339`（`sourceDigest := sha256.Sum256(raw)`） |
| daemon-owned trust root 安装 | **已存在**，注释直写 ADJ-AIFI45-003：根在 daemon 自己的 HOME 下、永不建在工作区内、**已有文件绝不被静默替换** | `server/internal/daemon/execution_trust.go:1-10` |
| `HandleDaemonExecutionBinding` + relay + endpoint | **已存在**：挑战含 `operation`、head/claim 校验、大小写敏感测试 | `governance/execution_binding_issue.go:94,432,469-474`；`daemon/execution_binding_{client,endpoint,relay}.go` |
| **operation 白名单** | **确实缺失** | `execution_binding_issue.go:472-473` 只做 `executionBindingOperationRE.MatchString` —— 名称形状合法即通过，**没有枚举约束** |

所以「真实闭环」不是 4 个新功能，而是：
**一处小的 M 改动（operation 白名单）+ 一次真实闭环运行取证 + ADJ-003 的 Linux 半侧身份证据。**

## 2. 为什么 operation 白名单是决定性的

设计写的是「五个 operation 白名单，**不开放任意 nonce 代签**」。
现状只校验名称形状，因此一个 canonical 形状的任意 operation（例如 `advance-any`），在 head/claim 都合法时也会被签名。
这不是风格问题：T 侧 `requireControlAdmission` 依赖「这个 challenge 只可能由控制入口发起」；
若 M 侧能为任意 operation 名签名，T 侧的 operation 绑定就退化成一个可协商的字符串。

**一处检查（白名单）+ 一个负例（形状合法但不在名单内 → 拒绝且不签名）** 即可闭合，不需要第二套机制。

## 3. 最小补齐路径

| # | 动作 | 关闭什么 |
|---|---|---|
| **M1** | `execution_binding_issue.go` 增加 operation 白名单（枚举，拒绝名单外名称）；负例：形状合法但未列入 → 拒绝且不签名 | 「任意代签」缺口 |
| **M2** | 一次真实闭环：认证 actor 的 `structured-human-request/v1` → `BuildExecutionAuthorization` 签发 → daemon 在 daemon-owned trust root 安装 key/grant/source → 它亲启的 crctl 子进程走 `requireControlAdmission` → 现有 claim/head/DB 归属复核 | TC-TAC-001/002/004/006/007/008/009/010 的真实外部事实 |
| **M2·实测结果** | **前五步真实完成**（签发 HTTP 201、14 个 json-pointer 绑定、trust root 安装、静态 `--check`），**第六步被 M 的启动门挡住**：`execution_verifier.go:62-68` 在装配后**无条件**返回 `EXECUTION_CONSUMPTION_REQUIRED`（「不要在当前 head/撤销/claim 与受保护通道被 T 消费前启动 agent」）。方向是对的，缺的是它之后应有的接线。见 [m2-blocker-20261108](m2-blocker-20261108.md) | 闭环未闭合；10 条 TC 仍全部条款级 |
| **L1** | Linux 不同 UID 的真实公钥覆盖拒绝（WSL 内已有 uid 1500/1501） | TC-TAC-005 的 Linux 半侧；ADJ-003 的 Linux 半侧 |
| **W1** | Windows 不同身份拒绝 | **保持 C（不引原生依赖）**：记为 Windows runner 部署前置，不写成已证明 |

M2 之后，8 条 TC 可从条款级升到整条；TC-TAC-005 保持条款级，但补上 Linux 真实证据。

## 4. M 侧改动的落点与登记

multica 是独立仓，带自己的 `CUSTOM.md` 台账（稳定 `#N` 行、CR 索引、核对基线四数、`// AIFIRST:` 标记）。
按本仓约束，改它必须：

1. 在**在途** multica change 下登记：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution`
   （`status: active`、`current_phase: build`）——同一授权执行工作的延续，不新开一条把同一设计切成两半；
2. 新增 `// AIFIRST:` 标记 + CUSTOM.md 明细行 + CR 索引；
3. 按 CUSTOM.md 的核对命令重取四个数并加一行基线。

若 CUSTOM.md 的格式不接受本次标识，按规则**停止并确认**，不编造 CR 身份。

## 5. 不在本次范围

- 不实现 Windows 受限令牌驱动（与已裁决的 C 一致）。
- 不为「真实闭环」新增第二本账、CA/PKI 或原生依赖。
- 不改归档 change 的冻结产物。
- 不把 M2 的运行结果写成「生产可用」：它只是一次性实例上的真实链路证据。
