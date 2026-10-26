# AIFI-45 · 规格轴评审（gate3-20261025T135000Z）— **INCOMPLETE**

> 产出方式：本条由**独立 spec 轴评审代理**执行（只读、未运行任何测试、未改产品代码），
> 该代理在最后一轮读完证据后触到 turn 上限，**未能落盘**，故由主会话按其回复**原样转录**并做三处事实校正。
> 转录不等于复核：表中 `PARTIAL / MISSING / UNVERIFIED` 全部保持代理原判，主会话**没有**把任何一项上调为 DELIVERED。

## 判定：INCOMPLETE（不得按 PASS 计）

理由是硬的：本轮**没有执行任何测试**，而规范要求 RUN 类 AC 必须核到真实 `PASS: TestTC_RUN_00N` 行；
未核到的项一律记 UNVERIFIED。

## 0. 三处事实校正

1. **规范位置**：multica 侧**没有** `canonical/specs/{agent,code}/execution-authorization.yaml`。
   multica 侧绑定规范是 `authorized-runner.yaml`（REQ-RUN-001…004 / SC-RUN-001…010）与
   `attention-routing.yaml`（REQ-NTF-001…003 / SC-NTF-001…007）；
   `execution-authorization.yaml`（REQ-AUTH-001…004 / SC-AUTH-001…010）只在 **tools** 侧。
   → 本轮以 tools 侧 AUTH 规范 + multica 侧 RUN/NTF 规范为绑定，代理的判断成立，采纳。
2. **「relay 已接线」不成立（驳回代理的第 2 条校正）**：
   `grep -rn "relayExecutionBinding\|executionBindingEndpointForRun" --include=*.go server/internal/daemon`（去测试文件）只有两处生产代码 —
   `daemon.go:8759` 调 **`executionBindingEndpointForRun`**（per-run HTTP 端点）与 `execution_binding_relay.go:77` 的**定义**。
   `relayExecutionBinding` **没有任何生产调用点**。代理把端点接线误读成中继接线。
   → 未关闭项「daemon 私有 stdio 中继尚未接入 `handleTask`」**维持**。
3. **tools 测试路径**：实为 `tools/skills/shared/crctl/scripts/test/execution-binding-endpoint.test.mjs`
   （代理按 `skills/shared/crctl/test/` 找，故 `ls` 失败）。文件存在，但本轮未读，仍记 UNVERIFIED。

## 1. 需求判定表（代理原判，未上调）

| requirement / AC | verdict | evidence (file:line) | note |
|---|---|---|---|
| REQ-AUTH-001 / SC-AUTH-001 验签+可消费、basis=execution-authorization | PARTIAL | `execution_binding_issue.go:116,338`；`execution_consumption.go:43,192-232` | 签发与消费均为真实 DB 事务 + 签名；`basis=execution-authorization` 消费字段未在所读文件中核到 |
| SC-AUTH-001 原 bytes 冻结、拒绝重复 JSON 键、14 语义字段核对 | PARTIAL | `execution_binding_issue.go:361,468,474,490,503` | 有严格字段白名单/绝对路径/null 拒绝；**重复键拒绝与 14 字段逐项核对未逐行确认** |
| SC-AUTH-001 服务端按已认证 scope 核验资源并冻结 repository/coordinator binding | DELIVERED（平台侧） | `execution_binding_issue.go:222-248` | claim 的 cr/task/project/runtime + coordinator `local_directory`/workspace/project + `daemonOfBinding==daemonID` 全复核 |
| SC-AUTH-003 task-token/cloud_pat/伪 header/自报 actor 不签发 | DELIVERED | `execution_binding_issue.go:127-132`；`execution_consumption.go:47-59` | 强制 `DaemonAuthPathDaemonToken`，否则 403 `EXECUTION_DAEMON_BINDING_REQUIRED` |
| SC-AUTH-003 不产生消费/推进（拒绝路径无副作用） | DELIVERED | 同上 + `execution_consumption.go:172-186` | 拒绝分支全在 `tx.Commit` 前返回 + `defer rollbackTx` |
| SC-AUTH-004 跨仓/扩范围/换根不扩权 | PARTIAL | `execution_binding_issue.go:187-212,222-248` | head 校验含 revocation/scope/deployment/source/repository；graph 换根/资源改绑反例未核实 |
| SC-AUTH-005 敏感动作逐项拒绝 | MISSING（本切片） | 无 production/data/permission/spend 分支证据 | 属 RUN/action 裁决面 |
| SC-AUTH-006 / SC-RUN-010 精确专项授权、operation_id 幂等、额度聚合键分离 | MISSING | 四个 governance 文件中无 `operation_id`/额度聚合 | 团队清单正确 |
| SC-AUTH-007 ACK≠消费、ACK 后仍不可推进 | DELIVERED（平台侧） | `execution_consumption.go:192-204` | 独立表 `cr_execution_consumption` 独立 commit；T 侧事务未验 |
| SC-AUTH-008 跨安装根/worktree/other workspace/同名 CR/policy/template 版本拒绝 | PARTIAL | `execution_binding_issue.go:159-167`；`execution_consumption.go:159-167` | `InstallRoot` 仅判非空，**未与权威根比对** |
| SC-AUTH-008 失联/无 head 时无新准入 | DELIVERED | `execution_binding_issue.go:167-172`；`execution_consumption.go:85-92` | 与撤销经 `execution_head_lock.go:27` 串行化 |
| SC-AUTH-009 重放返回同一 receipt 且 `changed=false` | DELIVERED | `execution_consumption.go:205-224` | `ON CONFLICT DO NOTHING` + 同事务回读；异 challenge → `EXECUTION_CONSUMPTION_CONFLICT` |
| SC-AUTH-009 同键不同 subject 报冲突 | PARTIAL | `execution_consumption.go:205-224` | 冲突键为 runtime/task/dispatched_at + challenge，无显式 subject 列比较 |
| SC-AUTH-010 / REQ-AUTH-004 跨语言原始字节签名、篡改/旧域/未知版本拒绝 | **UNVERIFIED（代理未读）** | — | 主会话另有 `execution_tc_auth010_test.go` 实跑证据（见 closeout §2），但**本评审未复核**，故本表不下调也不上调 |
| SC-RUN-001 真实 project 入口绑定原授权、无重复阶段确认 | MISSING（本切片） | 无阶段入口/派发面 | 团队清单正确 |
| SC-RUN-002 不可信主体不建执行任务 | PARTIAL | 同 SC-AUTH-003 | 授权侧拒绝已交付；「不创建执行任务」属 dispatch 面 |
| SC-RUN-003 ACK 仅 wake、消费后才推进 | PARTIAL | `execution_consumption.go:43`；`execution_activation.go:33` | activation 主体未读，wake 语义无法判定 |
| SC-RUN-004…006 repair 准入 / logical_dispatch_key / 额度与撤销 resume | MISSING | 所读文件无对应证据 | tools `repair-governance.yaml` 未读 |
| SC-RUN-007 四阶段真实入口 + 统一 Reconcile + periodic 发现 | MISSING | `agent/authorized-runner.yaml` 仍是 `go test ./cmd/server -run ^TestTC_RUN_00N$` 待跑模板 | CP-RUN-001…010 **零执行** |
| SC-RUN-008 未就绪切换拒绝、回退不清历史 | UNVERIFIED | 未读 `cmd/server` 挂载与版本开关 | — |
| SC-RUN-009 联合执行身份 + 作者不可自评 | MISSING（本切片） | 无 review/projection 代码 | 团队清单正确 |
| REQ-NTF-001…003 / SC-NTF-001…007 | MISSING（零证据） | 所读文件无 notification/Inbox 代码 | 团队清单正确 |
| migrations 643/644/645 + `.down` | UNVERIFIED | 代码引用三张表与唯一键 `(workspace_id, cr_id, runtime_id, task_id, dispatched_at)` | **未打开任何 migration 文件** |

## 2. Gate 仍会拦的项

1. **CP-RUN-001…010 零执行**：RUN 类 AC 全部不可判 PASS。
2. **REQ-AUTH-004 的 Node 侧未读**：`lib/execution-binding.mjs#fetchExecutionBindingOverHTTP`、`crctl.mjs` 的 `--binding-stdio` 门、endpoint 测试均未核。
3. **T 侧消费事务**：`lib/execution-transaction.mjs` 未读，SC-AUTH-007/009 只算平台半边。
4. **activation 语义未读**（只读到函数签名）→ SC-RUN-003 无法判定。
5. **migrations 未核**：列/约束/回滚是否与代码一致未知。
6. **路由挂载与 default-off 未核**（`execution_authorization_routes.go:20,42,70` 只读签名）→ SC-RUN-008。
7. **SC-AUTH-005/006、SC-RUN-004…009、NTF 全族**在本切片无实现痕迹。
8. **`relayExecutionBinding` 无生产调用点**（主会话已 grep 证实）——未关闭项维持。

## 3. 本评审没有验证的（不写 PASS）

- 未运行任何 `go test` / `node --test`（只读约束）⇒ 无 PASS 行证据。
- 未读：`execution_activation.go` 主体、`execution_head_lock.go` 主体、`daemon.go` 的 `handleTask` 全链、`cmd/server` 挂载点、
  tools 的 `execution-binding.mjs` / `crctl.mjs` / `execution-transaction.mjs` / `repair-governance.yaml` / `evidence-delivery-contract.yaml`、
  migrations 643/644/645 及其 `.down`。
- 未核 `design.md` / `slices.md` / `tasks.md` 与本表的一致性；未核隔离执行域是否接入产品。
- 未核 `cr_execution_binding_issue` 「同一原请求返回原包」的唯一键语义（`isExecutionBindingUniqueViolation` @ `execution_binding_issue.go:537` 只读到签名）。

## 4. 下一步（把 INCOMPLETE 变可判的最小动作）

1. 把上表 8 条未读项补读并给出 DELIVERED/PARTIAL/MISSING（**不需要跑库**）。
2. 单独一轮执行 RUN 类 10 条 TC 的待跑模板，核真实 `PASS: TestTC_RUN_00N` 行。
3. 打开 643/644/645 与其 `.down`，核列/约束/回滚。
