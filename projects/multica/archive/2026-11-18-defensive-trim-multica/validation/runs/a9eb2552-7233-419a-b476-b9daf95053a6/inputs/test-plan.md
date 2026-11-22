# Multica 防御性编程精简 — 测试方案与详细案例

> `2026-11-18-defensive-trim-multica` · 2026-11-18 · Phase 2 Spec：`canonical/specs/code/{authorized-runner,execution-wait-visibility,ci-backend-environment}.yaml`。以下为验收计划；已执行的定向验证见 `phase-context.md`，最终同次证据未生成。

## 一、测试策略
### 1.1 测试金字塔
Go 以生产 HTTP/事务集成为主，配合状态推导测试；Node 用临时 Git 仓库验证真实 Tools 阶段和 `stageCrctl`。
### 1.2 测试原则
- 断言关键状态码、错误码、记录数或摘要；从现有生产入口取证。
- 测试夹具分别构造省略和显式传值，不能恒删或恒传某参数。
- chi 共存测试用真实凭证抵达 handler 的业务码（如 `400 RUNNER_CR_NOT_READY`），不能拿 401 当通过。
- 锁序测试必须交错：占住后取的锁，用独立连接带超时探测先取的锁。
### 1.3 已有测试资产
- Go：签发、重放、头和撤销、`TestTC_RUN_010`、进展推导/回执、生产路由共存。
- Node：`crctl-stage.test.mjs`、`stack.test.mjs`、`tools-pin.test.mjs`。

## 二、详细测试案例

### 授权与敏感动作（authorized-runner）

#### 签发、重放与兼容字节
| 字段 | 内容 |
|---|---|
| **ID** | TC-RUN-201 |
| 子用例 | 201a SC-RUN-201 合同补值与拒绝；201b SC-RUN-202 原记录重放；201c SC-RUN-203 基线字节。 |
| 预置 | 实际签发 HTTP 夹具；固定密钥、ID、时间和可信签发事实的基线字节样本。 |
| 操作 | 提交缺字段、空串、显式相等、合法不符请求；再按原/不同授权人、冻结字节或锁内项目重试，对照 CRLF、`-0` 及补值样本。 |
| 预期 | 签发 201 且部署值、记录及初始头正确；不符 409 `EXECUTION_CONTRACT_MISMATCH` 或不匹配 409 `EXECUTION_AUTHORIZATION_CONFLICT`，均零写入；匹配重放 200 `reused=true`、原信封、零新记录或头更新；冻结、原 payload、Ed25519 签名字节等于基线。 |

#### 历史批准与撤销链
| 字段 | 内容 |
|---|---|
| **ID** | TC-RUN-202 |
| 子用例 | 202a SC-RUN-204 旧申请形状、原文篡改；202b SC-RUN-205 有效及损坏撤销链。 |
| 预置 | 有效 v1 历史形态批准（冻结原文有现行新申请不允许的字段）、有效撤销及独立坏记录夹具。 |
| 操作 | 经生产头 GET 读有效记录及原文、前驱、签名或 revision 损坏的对照。 |
| 预期 | 批准 200 且原摘要、record、公钥匹配；有效撤销可读，原文篡改和损坏链被拒。 |

#### 撤销交错与额度
| 字段 | 内容 |
|---|---|
| **ID** | TC-RUN-203 |
| 子用例 | 203a SC-RUN-206 动作先与撤销先；203b SC-RUN-207 同操作幂等与 `ordinary_grant_has_no_effect`。 |
| 预置 | 两个独立 CR 有有效专项批准，另有普通批准；真实撤销与 daemon 动作凭证、独立连接。 |
| 操作 | 按 design C3 交错并在放行前探测 CR 锁；在有效头下重试同一 `operation_id`，另请求未列明动作。 |
| 预期 | 动作先为 200、仅一笔 effect，随后撤销 201；撤销先为 201、动作 409 `EXECUTION_AUTHORIZATION_HEAD_INVALID`、未查重且零结算。重复操作返回原回执、仅一笔 effect 且只扣一次；未列明动作零结算。 |

### 进展与路由（execution-wait-visibility）

#### 进展一致性与失败回执
| 字段 | 内容 |
|---|---|
| **ID** | TC-EWV-101 |
| 子用例 | 101a SC-EWV-101 首读交错及缺失/坏详情；101b SC-EWV-102 未知状态；101c SC-EWV-103 成功回执省略坏进展。 |
| 预置 | running/failed 详情夹具及无 running 前沿的 run；实际 GET handler 及可成功提交的两个 POST handler，按 design C4 控制交错；生产路由与凭证由 TC-EWV-102 单独验证。 |
| 操作 | GET 首读后提交 completed；另读缺键，并分别对 running、failed 前沿读取数组、标量、字面 `null`；给生产推导传未知状态；在 POST 提交后的回执读面植入坏详情。 |
| 预期 | GET 首读 running 时回应 running/idle；缺键正常，坏详情 500 `query failed`；未知状态报错。两个 POST 均成功，`run_id`、`changed` 匹配已提交结果，记录错误且无 `progress` 键。 |

#### 真实路由共存
| 字段 | 内容 |
|---|---|
| **ID** | TC-EWV-102 |
| 子用例 | 102a SC-EWV-104 Runner 开关、成员 GET 和两个 POST 共存。 |
| 预置 | `NewRouterWithOptions`、有效 run、成员 JWT、两个 POST 的真实 `mat_` 凭证。 |
| 操作 | 切换 Runner 查询同一 GET；开启时用各自的 `pipeline_id` 和请求体向不存在的 CR 发 start、resume。 |
| 预期 | GET 关时 404、开时 200；两个 POST 均返回 400 `RUNNER_CR_NOT_READY`。 |

### 固定取材（ci-backend-environment）

#### 严格 pin 与显式 overlay
| 字段 | 内容 |
|---|---|
| **ID** | TC-CBE-101 |
| 子用例 | 101a SC-CBE-101 严格 pin 与拒绝降级；101b SC-CBE-102 固定对象与显式 HEAD。 |
| 预置 | 临时 Tools 仓库中旧提交、当前 HEAD 与工作树取材内容可区分。 |
| 操作 | 经真实 Tools 阶段试合法和 `HEAD`/空白/多行/非法 pin；调 `stageCrctl` 试固定提交、坏对象、省略 ref、显式 HEAD。 |
| 预期 | 固定取材和 commit 匹配所指提交，两摘要匹配 crctl、`addedFiles=[]`；坏 pin 为 `TOOLS_FAILED`、无 stage 目录及 overlay；坏对象或无 ref 失败；显式 HEAD 纯追加成功、删除或重写失败。 |

## 三、测试执行矩阵

| 模块 | 层次 | 选择或命令 |
|---|---|---|
| RUN 签发、头、敏感动作 | Go/DB | `run-default-contract-issue`、`run-authorization-head`、`run-sensitive-action` |
| EWV 进展、路由 | Go/DB | `ewv-progress`、`ewv-route` |
| CBE 取材 | Node/临时 Git | `CP-CBE-101` 指定三文件 |

## 四、回归风险矩阵
| 区域 | 风险 | 保护 |
|---|---|---|
| RUN | 字节漂移、旧批准被重审、交错重扣 | 原字节/摘要对照、有效与损坏头、双向事务和 effect 数 |
| EWV | 首读和进展矛盾、坏数据报 idle、POST 被遮蔽 | 首读交错、读失败回执及精确业务码 |
| CBE | pin 降级或报告与实际取材不符 | 坏 pin/对象与分歧工作树夹具 |

## 五、建议补充顺序
1. 先签发、固定取材；头读取完成后再收拢敏感动作，进展与路由可独立进行。

## 六、同次执行证据计划 / Same-Run Evidence Plan

每个 TC 独占一个 CP。DB 只使用 `run-selection.mjs` 自建并回收的实例，以 `selections.json` 的 `expected` 对账逐项执行；JSON/NDJSON 按 selection 写入本 change 的 `validation/selection-capture`，与当次 run ID 关联。各子命令和 CP 串行执行，避免覆盖同一证据文件。

取证前确认 `AIFI45_TOOLS_ROOT` 与 `CRCTL_MJS` 分别指向同一干净检出及其 `skills/shared/crctl/scripts/crctl.mjs`，该检出的提交须等于 `.github/aifirst-tools-pin`。冻结清单纳入本次改动的运行与测试输入，以及实际 selection、runner 入口和 pin 文件；不把回写台账或取证产物当作执行输入。

Gate 2 前只预检首 task：`stdd agent verify authorized-runner --change 2026-11-18-defensive-trim-multica --dry-run`。

```stdd-evidence-plan-v1
{
  "task": "authorized-runner",
  "tasks": ["authorized-runner", "execution-wait-visibility", "ci-backend-environment"],
  "inputs": [
    {"root":"project","path":"server/internal/governance/execution_authorization.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_http.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_http_test.go"},
    {"root":"project","path":"server/internal/governance/execution_fixture_export_test.go"},
    {"root":"project","path":"server/internal/governance/execution_default_contract.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_test.go"},
    {"root":"project","path":"server/internal/governance/execution_default_contract_test.go"},
    {"root":"project","path":"server/internal/governance/execution_default_contract_http_test.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_head.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_head_test.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_revoke.go"},
    {"root":"project","path":"server/internal/governance/execution_authorization_revoke_history_test.go"},
    {"root":"project","path":"server/internal/governance/execution_activation.go"},
    {"root":"project","path":"server/internal/governance/execution_binding_issue.go"},
    {"root":"project","path":"server/internal/governance/execution_consumption.go"},
    {"root":"project","path":"server/internal/governance/execution_sensitive_action.go"},
    {"root":"project","path":"server/internal/governance/execution_control_policy.go"},
    {"root":"project","path":"server/internal/governance/execution_control_policy_test.go"},
    {"root":"project","path":"server/cmd/server/execution_run_010_test.go"},
    {"root":"project","path":"server/internal/governance/pipeline_progress.go"},
    {"root":"project","path":"server/internal/governance/pipeline_progress_test.go"},
    {"root":"project","path":"server/internal/governance/pipeline_progress_receipt_test.go"},
    {"root":"project","path":"server/internal/governance/pipeline_progress_route_test.go"},
    {"root":"project","path":"server/internal/governance/requirement_shape_default_contract_test.go"},
    {"root":"project","path":"server/cmd/server/router.go"},
    {"root":"project","path":"server/cmd/server/pipeline_runs_route_coexistence_test.go"},
    {"root":"project","path":"scripts/aifi45-real-run/crctl-stage.mjs"},
    {"root":"project","path":"scripts/aifi45-real-run/crctl-stage.test.mjs"},
    {"root":"project","path":"scripts/aifi45-real-run/stack.mjs"},
    {"root":"project","path":"scripts/aifi45-real-run/stack.test.mjs"},
    {"root":"project","path":"scripts/aifi45-disposable/tools-pin.mjs"},
    {"root":"project","path":"scripts/aifi45-disposable/tools-pin.test.mjs"},
    {"root":"project","path":"scripts/aifi45-disposable/selections.json"},
    {"root":"project","path":"scripts/aifi45-disposable/run-selection.mjs"},
    {"root":"project","path":".github/aifirst-tools-pin"}
  ],
  "coverage": {"applicability":"not_applicable","reason":"Go 与 Node 栈，仓库覆盖率检查只支持 pytest-cov"},
  "checks": [
    {"tc":"TC-RUN-201","case_id":"issue-replay-bytes","requirement":"REQ-RUN-201","scenarios":["SC-RUN-201","SC-RUN-202","SC-RUN-203"],"cp":"CP-RUN-201","kind":"command","applicability":"required"},
    {"tc":"TC-RUN-202","case_id":"history-and-revocation","requirement":"REQ-RUN-202","scenarios":["SC-RUN-204","SC-RUN-205"],"cp":"CP-RUN-202","kind":"command","applicability":"required"},
    {"tc":"TC-RUN-203","case_id":"sensitive-action","requirement":"REQ-RUN-203","scenarios":["SC-RUN-206","SC-RUN-207"],"cp":"CP-RUN-203","kind":"command","applicability":"required"},
    {"tc":"TC-EWV-101","case_id":"progress-and-receipt","requirement":"REQ-EWV-101","scenarios":["SC-EWV-101","SC-EWV-102","SC-EWV-103"],"cp":"CP-EWV-101","kind":"command","applicability":"required"},
    {"tc":"TC-EWV-102","case_id":"production-route","requirement":"REQ-EWV-102","scenarios":["SC-EWV-104"],"cp":"CP-EWV-102","kind":"command","applicability":"required"},
    {"tc":"TC-CBE-101","case_id":"pinned-tools-stage","requirement":"REQ-CBE-101","scenarios":["SC-CBE-101","SC-CBE-102"],"cp":"CP-CBE-101","kind":"command","applicability":"required"}
  ]
}
```
