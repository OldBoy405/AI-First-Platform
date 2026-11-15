# BUILD 验证报告（AIFI-45）

> Change：`2026-10-22-aifi-45-authorized-execution`；目标业务仓 `tools`（crctl），跨仓证据来自 `multica`。
> 本报告是 **Gate 3 的输入**，不是批准、不是交付证明，也不替代 T 侧对 49 条 TC 的验收口径。
> 数据来自 2026-11-08 本机实跑；每条都写明「跑了什么、结果、边界」。

## 1. 结论（先说不好的）

- 登记面内 **94 个测试文件全部真跑，2217 个顶层用例，0 失败、0 零执行、0 超时、0 推迟**。
- 判定是 **`verdict=pass`（退出码 0）**。这不是把未跑的东西算成通过：需要一次性 PostgreSQL + backend 的那条用例已经**移出 hermetic 套件**，放到 `skills/shared/crctl/scripts/integration/`（路径由 canonical 的 `supplementary_evidence.action` 指向）。集成层不是“推迟”，是本套件不覆盖的层级。
- `TC-RPR-005` 本轮从「无可采信证据」转为**整条**：`and` 两条由既有的签名 `repair-resume` 承载（签名绑定 + stop CAS + head CAS + 证据新鲜性），本轮把它们**断言**出来，未加新机制。此前把 M 侧 `TestTC_RUN_005` 当候选是错的：它断言的是根恢复/重试/fence，不是修复准入/采纳。
- **32 条 T 侧 TC 的 canonical CP 动作 32/32 成立**（`1..1`、恰好一条顶层 `ok`、160/160 断言），见 [validation/e5-cp-sweep-20261108.md](validation/e5-cp-sweep-20261108.md)。这条测量存在的原因：曾有两条的 `--test-name-pattern` 匹配到 0 个测试，CP 永远不可能通过而无人发现。
- Windows 侧隔离 leaf 仍 **UNVERIFIED**（本机没有第二个 Windows 受限令牌）；本次隔离证明用的是 WSL 内第二 uid。

## 2. 全量 suite 门

命令（必须带隔离 profile，否则 `execution-control-isolation` 会按设计故意失败）：

```
AIFI45_ISOLATION_PROFILE=1500:1500 AIFI45_ISOLATION_AGENT=1501:1501 \
  node test/suite-gate.mjs --run
```

| 指标 | 值 |
|---|---|
| files_executed | 94 |
| cases_executed | 2217 |
| failures | 0 |
| skipped_file_level | 0 |
| converged | true |
| deferred | 0（`holds` 为空；平台用例已移入 `integration/`，不在本套件的辖区） |
| verdict / 退出码 | `pass` / 0 |
| 耗时 | 933278 ms |
| registry | 94 files / 94 cases / 2111 例 / 0 外部推迟 |

**分层说明（本轮唯一的结构性改动）**：`test/tc-auth-005-006-real-platform.test.mjs` → 
`skills/shared/crctl/scripts/integration/tc-auth-005-006-real-platform.mjs`（内容零改动；`import.meta.dirname` 的上跳深度相同，
`toolsRoot` / `cli` 常量无需修）。此前它被挂在 `holds` 里，而 `holds` 会被**无条件排除执行**，
所以不管平台在不在都是 `partial`；现在它在 hermetic 套件之外，`pass`/`block` 只反映代码本身。
新路径下结构不变：无 env 时仍 `2/2 SKIP、exit 0`。

**2217 ≠ 覆盖 49 条 TC。** 前者是测试用例执行数，后者是验收场景数，两者分母不同，不能互相顶替。

## 3. 关键套件逐条（本轮真跑计数）

| 套件 | 结果 |
|---|---|
| `crctl.test.mjs` | 301 / 301 |
| `execution-authorization.test.mjs` | 176 / 176 |
| `repair-governance.test.mjs` | 30 / 30 |
| `delivery-contract.test.mjs` | 18 / 18 |
| `register-tx.test.mjs` | 46 / 46 |
| `register-applied-not-evidence.test.mjs` | 5 / 5 |
| `execution-transaction.test.mjs` | 54 / 54 |
| `durable-tx.test.mjs` | 71 / 71 |
| `checkpoint-tx.test.mjs` | 32 / 32 |
| `receipt-protocol-pairing.test.mjs` | 6 / 6 |
| `evidence-receipt-reuse.test.mjs` | 1 / 1 |
| `caller-contract.test.mjs` | 16 / 16 |
| `git-run-raw-bytes-memory.test.mjs` | 10 / 10 |
| `execution-control-isolation.test.mjs` | 12 / 12（顶层 3） |
| `suite-gate-leaf-memory.test.mjs` | 40 / 40 |
| `suite-gate-count.test.mjs` | 8 / 8 |

## 4. 49 条 TC 的证据口径

| 状态 | 数量 | 说明 |
|---|---:|---|
| 整条有证据 | 29 | 全部 THEN/AND 子句 + canonical 声明的入口内 + 实跑通过（含本轮转整条的 `TC-RPR-005`、`TC-EVD-007`） |
| 条款级 | 1 | `TC-AUTH-007`：canonical 要求「历史送达记录仍**可查询**」，而送达/ACK 历史是平台记录；本仓只有「已安装包仍可复验」，复制一份会得到两本账 |
| 补充证据 | 2 | `TC-AUTH-005` / `TC-AUTH-006`：本地 CP 走 in-process stub，真实拒绝需要平台，故另有真实平台证据，canonical 以 `supplementary_evidence` 登记并标 `not_counted_as_cp_pass` |
| 无可用证据 | 0 | `TC-RPR-005` 本轮补齐跨 run 子句后转整条，见 §4.1 |

### 4.1 本轮唯一一次证据等级提升：`TC-RPR-005`

`then` 早已断言（含两个真实子进程并发准入）。`and` 两条此前无人断言，`grep adoption\|takeover` 为空，
曾被记为「未实现」。实测后确认：**既有的签名 `repair-resume` 就是可信 adoption 映射**——
它绑定 `supersedes_grant` / `previous_head_digest` / `stop_origin` / `stop_version` / `changed_path`，
做 stop CAS 与 head CAS，复用已评估证据时返回 `REPAIR_RESUME_EVIDENCE_STALE`，
恢复时保留原 origin、root cause 快照与 `consumed`，不新增消费。本轮把这些**断言**出来，未加任何新机制。

最弱的一环要说清：末尾「resume 之后再 repair-admit」端到端那一段，实际命中的是同 origin 的
stored-receipt replay，它**不读** `resumes` 记录。所以它证明「跨 run 得到同一 receipt」是对的，
但若将来把 canonical 收紧为「必须存在由 repair-admit 显式消费的独立映射」，这一组不能支撑那个更强语义。

### 4.2 CP 动作实测（本轮新增的唯一测量）

见 [validation/e5-cp-sweep-20261108.md](validation/e5-cp-sweep-20261108.md)：32/32 条 canonical `action`
都恰好选中唯一顶层 TC、`1..1`、fail/skip/todo 全 0、160/160 断言成立。
这条检查存在的理由很具体：**曾经有 2 条 TC 的 `--test-name-pattern` 匹配到 0 个测试**（TAP `1..0`），
CP 动作永远不可能通过，而没有任何东西发现。

三个必须知道的限定（不自欺）：

1. `TC-AUTH-009` 的故障注入在 outbox seam，不是 HTTP 响应丢失；
2. `TC-AUTH-010` 正例的已签字节由 Node 签出，不是 Go 生产签名；
3. `TC-EVD-009` 的故障是同进程抛错，不是 SIGKILL。

若审核方把「Arrange 真实性」也计入整条资格，上面三条应降回条款级。

## 5. 本轮收口的内容（可复核）

| 项 | 事实 |
|---|---|
| 三个保证的载体 | A 不谎报（`test-report`/CP 证据口径、`SUITE_MANIFEST_CASE_DROP`、`partial≠pass`）；B 不产生第二次效果（授权消费 receipt、修复租约、`appendLedgerEntry`/`applyWriteSet` 三分类、`TX_RECOVERY_CONFLICT`）；C 不互相覆盖（`workspace-backlog` 外锁 + 按条目内锁 + 按序唯一节点闸门 + `commitPaths` 限定提交面） |
| 同一事实双判定 | `advance` 与 evidence 面共用 `resolveEvidenceContractSelection`；register dirty 守卫只豁免已持久化 manifest 的逐字路径 |
| fail-open 收口 | `policy_version` 在 repair 准入与修复续签/恢复两处从「可选」改为「必需且等于当前版本」（M 侧对 initial/revoke 本就强制非空） |
| 假通过修复 | `git-run-raw-bytes-memory` 的合成导出改为从被测源码 import 解析（原为硬编码，源码新增命名导入即整文件 link 失败）；`caller-09` 的审批头行文案按扫描器自带锚点白名单登记 |
| gate 三态 | 声明过的外部依赖 → `partial`（退出码 2，不计入执行数）；任何真实失败仍 `block`；无推迟时 `pass`。本仓现在零推迟，所以判定是 `pass` |
| 分层 | 需要真实平台的用例移入 `integration/`，hermetic 套件只含无服务依赖的契约/单元测试。`holds` 机制保留但当前为空 |

## 6. 未闭合项（Gate 3 之后仍需处理）

1. `TC-RPR-005` 已转为整条（见 §4.1）；残余风险是末尾那段端到端断言实际命中的是 stored-receipt replay，不读 `resumes`。
2. `TC-AUTH-007` 的「历史送达记录仍**可查询**」owner 是**平台**：送达/ACK 历史是平台的记录，本仓复制一份会得到两本账。本仓已证 ACK≠消费、不误推进、已安装包仍可复验。
3. `TC-EVD-007` 已转整条（readiness 门住交付判定 + 旧 release receipt 仍 allowed + 无上线真值字段，含变异验证）。
4. Windows 侧隔离 leaf **不是缺令牌**：`test/execution-control-isolation.test.mjs:190/193` 明确「本实现的受限令牌驱动尚未接上」，给了 profile 也会 fail（fail-closed，不假绿）。验证它需要 `CreateRestrictedToken`+`CreateProcessAsUser`（原生依赖），或在一台具备第二 Windows 身份的主机上用 `Start-Process -Credential` 证明。这是 **Windows runner 部署的前置条件**，不是本仓测试待办。
5. 已接受残留（不再作为待办）：同句柄 `release()` 重放（单线程不可达）、PID 复用（保守阻断）、跨机/NFS（阻断）、`appendLedgerEntry` 仅逐字幂等（所有账本写在 workspace 锁内）、`authorization-bind` 停在 `EXECUTION_CONSUMPTION_REQUIRED`（`SC-AUTH-007` 要求 ACK ≠ 消费）。

## 7. Gate 3 提交判定

### 第一次提交（2026-11-08 上半天）— 被拒，且拒绝是对的

```
stdd gate approve --gate 3 --confirmed-by dialog --evidence "确认Gate 3"
→ Gate 3 缺少实施切片记录（.stdd.yaml）  exit 1
```

失败点在 `_gate_input_manifest`，**早于任何写入**。当时判断：`phases.build.slices_completed` 的合法写入口是
STDD build Skill B3.4，而按「子句完整证据」口径 S2/S3/S4/S5 都到不了 100%，写它就是谎报。

后来修正了这个判断：B3.4 第 1 步的 `tc_coverage` 定义是**每个 TC-ID 有对应测试函数**，不是子句完整证据。
按定义逐片实测（[validation/e5-cp-sweep-20261108.md](validation/e5-cp-sweep-20261108.md)，32/32 成立），
S1–S5 的 `tc_coverage` 是真的，每片的 `note` 另写证据等级。S6 未写（Windows leaf 仍 UNVERIFIED）。

### 第一次确认（2026-11-08T16:11:36）

`input_manifest` 16 条、`input_fingerprint=07c978d7…`，`phases.build.status=completed`。
当时判定为 `verdict=partial`（1 条声明过的外部依赖推迟）。

### 本次 reapprove（分层方案）

用户采纳「分层」建议并给出确认原文「确认按分层方案调整 Gate 3」。本次改动只有两件事：

1. `test/tc-auth-005-006-real-platform.test.mjs` → `skills/shared/crctl/scripts/integration/tc-auth-005-006-real-platform.mjs`（内容零改动），
   并同步 `gate-registry.json`（95→94 文件、2113→2111 例、`holds` 清空）与 canonical 两处
   `supplementary_evidence.action` 路径；
2. 本报告的判定与未闭合项按新事实重写。

结果：**`verdict=pass`（退出码 0）、`deferred=[]`、`failures=[]`、`warnings=[]`**。
`partial` 语义保留（声明过的外部依赖仍会产出 `partial`），但本仓当前零推迟。

Gate 3 的 `input_manifest` 覆盖本文件、`design.md`、`test-plan.md`、`canonical/specs/**`、`specs/*/spec.md`、`.stdd.yaml`；
此后其中任一文件变动都会让 Gate 3 变 stale，需显式 `--reapprove` 并给出用户确认原文，不会自动重签。
旧批准会以 `superseded` 回执保留在审计链里。
