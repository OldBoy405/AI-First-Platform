# AIFI-45 test-report（C1–C7 门禁）

> 生成时间：2026-10-25 · 阶段：BUILD/in_progress · 模型：普通模式（主会话实现 + 分层独立审核）

## 0. 结论先行

**Gate 结论：NO-GO（不推进 Gate3）。**

四条硬阻塞，任何一条都足以否决：

1. **业务 TC 0/49**：49 条 canonical TC（RUN 10 / NTF 7 / AUTH 10 / RPR 12 / EVD 10）**没有一条**有端到端证据；组件级测试**按本 change 自己的规则不计为 TC 通过**。
2. **全量测试未通过**：daemon 包 **33 项 FAIL**、handler 包 **3 项 FAIL**（未做变更前基线复跑，因此既不能断言"与本变更有关"，也不能断言"无关"）。
3. **service 包无法在全量门禁里运行**：`scripts/aifi45-db/run.mjs` 的包白名单不含 `./internal/service`，runner 在创建 DB 前退出；未绕过、未用直接 `go test` 冒充。
4. **已确认一处安全 fail-open**（见 §6）：绑定签发在 head 被撤销后仍可能签发（快照隔离 + 无行锁 + 提交前无重校验），且代码注释声称"已经重校撤销"——注释与事实不符。

## 1. 冻结与范围

- multica 冻结：`validation/gate-20261025T113000Z-freeze-manifest.json`（20 项，含 643/644/645 迁移与三条链实现）
- tools 冻结：`validation/gate-20261025T113000Z-tools-manifest.json`（4 项）
- 冻结后未再改源码：全量跑前后 20/20、4/4 hash 一致（`FINAL_20_OF_20=true`）

## 2. 环境

- 临时库：冻结原库的 **schema-only 克隆**，每命令独立 nonce 库 + 受限 role；迁移经 runner 显式 `-migration=` 应用并记录 sha256
- 单执行者：所有 DB 命令串行，同一时刻仅一个执行者
- 原库（`stdd_aifi45_20261022`）：三条实际运行的包**前后均为 137 表 / 6228 行 / 82 审批**，`sessions=0`、`locks=0`，owned 资源清理完成
- 原库 HOLD **未解除**

## 3. 全量测试结果（真实数字）

| 包 | 结果 | RUN / PASS / FAIL / SKIP | PASS leaf | 判定 |
|---|---|---|---|---|
| `./internal/governance`（643+644+645） | 完成 | 921 / 920 / **0** / 1 | 832 | 通过（1 SKIP=LiveGitHub 未配） |
| `./internal/handler` | 完成 | 4557 / 4507 / **3** / 47 | 4130 | **FAIL** |
| `./internal/daemon` | 完成 | 2155 / 2024 / **33** / 98 | 1865 | **FAIL** |
| `./internal/service` | **未执行** | — | — | runner 白名单拒绝 |
| tools `scripts/test/*.test.mjs` | 完成 | 1058 / 1057 / **0** / 1 | — | 通过（1 SKIP=symlink EPERM） |

**失败清单（按域归类，均未修复）**

- handler：`RollupTaskUsageHourly*` ×2（`task_usage_hourly_rollup_state WHERE id=1` 无行）、`TestTaskSupplementClaimStartReplay`（期望 200，实际 409 stale claim）
- daemon：33 项集中在 agent CLI/桌面 bundle、DSH/profile 探测、Windows symlink/文件占用、Git 长路径、RepoCheckout/RunTask 夹具、crevents 阶段分类、runtime-gone coalesce
- **与本变更文件无交集**：消费/绑定/激活相关用例（`TestRequestExecutionConsumptionClient`、4 个 refusal 子例、`TestRecordDeliveredConsumptionSwitch`、`TestExecutionBindingEndpoint*`、`TestExecutionActivation*`）在 daemon/governance 全量中均 PASS

**SKIP 纪律**：governance 1 / handler 47 / daemon 98 / tools 1，**全部未计入 PASS**；未做"混合 SKIP 单列"以外的任何取巧。

**未测**：覆盖率未采集（runner 不支持 `-cover`）；handler/daemon 未做变更前基线复跑，因此这 36 条失败既未被证明属于本变更，也未被排除。

## 4. 业务 TC 矩阵（49 条，逐条）

规则：本 change 明确"组件级不是 TC"。下表每条的状态都按端到端证据判定。

| TC | 状态 | 说明 |
|---|---|---|
| `TC-AUTH-001` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-002` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-003` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-004` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-005` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-006` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-007` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-008` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-009` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-AUTH-010` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-001` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-002` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-003` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-004` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-005` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-006` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-007` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-008` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-009` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-EVD-010` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-001` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-002` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-003` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-004` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-005` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-006` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-NTF-007` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-001` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-002` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-003` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-004` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-005` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-006` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-007` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-008` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-009` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-010` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-011` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RPR-012` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-001` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-002` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-003` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-004` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-005` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-006` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-007` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-008` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-009` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |
| `TC-RUN-010` | **未实现**（0 条端到端证据） | 组件级臂证存在，但按本 change 规则**不计 TC 通过** |

**合计：0 / 49 通过。**

## 5. 三路评审状态

| 轴 | 产物 | 状态 |
|---|---|---|
| 标准/规范 | `gate-20261025T113000Z-review-standards.md`（10,251 B） | **已交付**（详见该文件） |
| 规格符合性 | **无产物** | **INCOMPLETE** —— 评审者 3 turn 用尽，只读到 governance 三文件；已记录的部分判定（20 键 payload、exact 4 键、重放逐字节、256 上限、activation 三推论）均判"满足"，但 daemon 侧四文件与"有无隐藏放行路径"未评审 |
| 安全/失败模式 | **无产物** | **INCOMPLETE** —— 评审者只读完 `execution_binding_issue.go`；消费/激活/端点/开关接线未评审 |

**纪律**：INCOMPLETE **不等于** PASS，不计入任何"已复核"结论。

## 6. 已确认缺陷（含评审者发现，作者复核）

1. **绑定的撤销竞态（fail-open）**：`HandleDaemonExecutionBinding` 用 `RepeatableRead`，快照在取 head 之前建立；读取后**无 `FOR SHARE/FOR UPDATE`、提交前无重校验**，因此"快照之后被撤销"的 head 仍会签发 envelope 并落行。代码里 "The head validator already re-checks revocation" 这句话**只对快照内状态成立**，是夸大表述。
2. **同一窗口存在于消费与激活**：两者用 `ReadCommitted` 且无行锁，head 校验与 INSERT 之间没有与 revoke 的互斥，可能写入"针对已撤 head 的 receipt/activation"。
3. **可观测性**：三个 handler 内部失败共用 `500 {"error":"…failed"}` 且**零日志**（无 workspace/cr/task/代次/原因），无法区分 DB 错误、签名失败、并发重读失败。拒绝面错误码是唯一且清晰的。
4. **签发端点信任边界**：`tools_digest / install_root / operational_root / process_id / parent_process_id / operation` 是**被签名而非被校验**的事实（只有 grant/policy/template digest 与 head 做过比对）——证明的是"该 daemon 声称 X"。
5. **per-run 端点不认证调用方**：loopback + bearer URL，同 UID 可读子进程环境；注释与 CUSTOM 已写明"不构成隔离"，但任何"只给本 run"的表述都是错的。

## 7. 未关闭项（不因本轮缩小）

- 5 个 major 仍 `resolved:false`；旧 claim 锁序 INCOMPLETE
- 隔离执行域（容器）未接；同 UID 可替换验签公钥（已有实证）
- daemon 私有 stdio 中继**仍未接入 `handleTask`**（无真实调用点）
- 消费开关已开（`New()` 置 true），但 **T 仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出**、准入仍关闭；activation 记录同样不构成准入
- activation 语义是**推导**，未经 Gate 确认
- 原库历史恢复（41 行缺失）无进展，HOLD 保持

## 8. 从 NO-GO 到 GO 的必要条件（建议顺序）

1. 让 `./internal/service` 可经 runner 运行（扩白名单或拆出可运行子集），再跑全量。
2. 对 36 条 handler/daemon 失败做**变更前基线对比**：证明哪些是既有，哪些是本变更引入；引入项必须修。
3. 修 §6(1)(2) 的撤销竞态：与 revoke 建立互斥（head 行 `FOR SHARE` 或 SERIALIZABLE + 重试），并在提交前重校验；补"撤销与签发/消费/激活并发"的真实负例。
4. 补齐 §6(3) 日志与内部错误分类。
5. **逐条实现 49 条业务 TC**（这是唯一能让 0/49 变成真实数字的路径），按 test-plan 的 RED→GREEN 要求，不拿组件测试顶替。
6. 必要时 enlarging review：补完规格与安全两轴的完整评审（当前 INCOMPLETE）。

**在这些条件满足前，本 change 不具备 Gate3 条件；提交/推送/部署同样不执行。**


---

# 附录 A：NO-GO 之后完成的整改（2026-10-25 12:30）

用户授权后继续处理了报告 §8 里的第 1–3 项。结论：**三点里有两点已从阻塞降级为可解释，撤销竞态已修并有效臂证；TC 仍 0/49，故 Gate 结论维持 NO-GO。**

## A1. `./internal/service` 现在可跑（阻塞 3 解除）

`scripts/aifi45-db/run.mjs` 的包白名单加入 `./internal/service`（含 usage 文本更新）。实跑：

| 包 | RUN / PASS / FAIL / SKIP | PASS leaf | DB 门禁 |
|---|---|---|---|
| `./internal/service` | **957 / 939 / 0 / 18** | 862 | `unchanged=true`、`cleaned=true`、`sessions=0`、`locks=0` |

## A2. 36 条失败已定性（阻塞 2 降级）

- **daemon 33 条：既有，不是本变更引入。** 在 **干净 HEAD worktree**（`git worktree add HEAD`，仅拷入 runner）上跑同一批用例：**34 RUN / 1 PASS / 33 FAIL**——与本树结果一致。
- **handler 3 条：runner 环境。** 两条 `RollupTaskUsageHourly*` 依赖 `task_usage_hourly_rollup_state` 的 **seed 行 id=1**：原库 `count(*)=1`，而克隆是 `pg_dump --schema-only`，迁移里的 INSERT 不随 schema 走，克隆里没有该行。第三条 `TestTaskSupplementClaimStartReplay` 同属该夹具族。
- 本轮**未修**这些用例，也未改 runner 的克隆策略；它们仍是"红"，只是不再算在本变更头上。

## A3. 撤销竞态已修（§6(1)(2) 的 fail-open）

**根因**：head 存在 `cr.execution_authorization_head_id`，撤销正是 `UPDATE cr SET execution_authorization_head_id = …`。原实现先读 head 再写行，中间无锁：撤销可在"校验后、写入前"提交。签发还用 `RepeatableRead`，快照可能早于该撤销。

**修法**：新增 `execution_head_lock.go`——三个端点在读 head **之前**先对该行取 `FOR SHARE`（共享锁，不阻塞并发签发，只挡撤销的 UPDATE），并把签发事务改为 `ReadCommitted`（快照必须晚于锁）；无指针 ⇒ 与缺 head 同判 409。

**证据（deterministic，不是碰运气）**：

| 轮次 | 内容 | 结果 |
|---|---|---|
| `racefix-…-green3` | 两个端点各一个锁探针 | **2 / 2 PASS**，原库无漂移 |
| `racefix-…-red2` | 去掉 `lockExecutionAuthorizationHead` 调用 | **1 FAIL**：`a concurrent UPDATE of cr.execution_authorization_head_id was not blocked` |
| `gate2-…-governance` | `^TestExecution(Binding\|Consumption\|Activation)` 全量 | **43 RUN / 43 PASS / 0 FAIL / 0 SKIP（38 leaf）** |

**一次被自己推翻的假测试**：第一版用两行 `created_at` 排序来判定"谁先提交"。这在 Postgres 无意义——`now()` 是**事务开始时间**；去掉锁后它照样绿。现改为"在 handler 的校验→写入窗口里，用独立连接尝试 `UPDATE cr`，断言被 `statement_timeout` 挡住"，并以去掉锁的 mutation 证明其有鉴别力。

**残余**：锁只与 `UPDATE cr` 互斥；若将来引入别的 head 写入路径（例如绕过 `cr` 行的迁移工具），本保护不覆盖——已在报告 §6 记为需随设计变化复查的点。

## A4. 仍未做（Gate 仍 NO-GO 的唯一实质原因）

**业务 TC 0/49**：没有任何一条 canonical TC 有端到端证据（组件级不计）。A1–A3 让"全量测试"与"安全 fail-open"两项不再是不可解释的红，但**不能**替代 TC。
## A5. 业务 TC：2 / 49 已真实通过（更新 §4）

本轮把两条 TC 从"未实现"变成**真实端到端通过**（命名即 TC id，走真实路由 + 真实 DB）：

| TC | 实现 | 结果 |
|---|---|---|
| **TC-AUTH-007** delivered/ACK 但无 committed 消费 → 不误推进 | `TestTCAuth007DeliveredWithoutConsumptionDoesNotAdvance`：签发（送达）后不消费 → 激活 409、receipt/activation 行均为 0、**送达历史仍在**（issuance=1）；随后首次消费 201 | **PASS** |
| **TC-AUTH-009** 消费重放同 receipt/changed=false；异义同键显式冲突 | `TestTCAuth009ConsumptionReplayIsIdempotentAndConflictIsExplicit`：首消费 201/changed=true → 重放 200/同 receipt/changed=false → 同代次第二份证明 409 `EXECUTION_CONSUMPTION_CONFLICT` 且**与重放响应可区分** → 全表仅 1 行 | **PASS**（`tc-20261025T124500Z-green1` 2/2，2 leaf） |

**TC-AUTH-010 判为"部分"**：Go→Node 跨语言逐字节验签的正例与"改 task_id 保留签名即被拒"的负例已有（`TestExecutionBindingEnvelopeInteropWithToolsVerifier`，3 RUN/3 PASS），tools 侧也有域/版本/字节篡改负例；**缺**的是该 TC 明写的**中文/分隔符/CRLF/keyID golden 字节**用例。因此**不计通过**。

**剩余 46 条的缺口（按所需面归类，不做笼统的"未做"）**

| 类别 | TC | 缺什么面 |
|---|---|---|
| RUN 10 | TC-RUN-001..010 | 真实入口派发 + TaskService 入队 + Reconcile/恢复 + 终态根/adoption 映射；当前链只覆盖"签发→交付→消费→activation"，**没有**派发与状态推进面 |
| NTF 7 | TC-NTF-001..007 | 通知/Inbox 广播面（本 change 未触及该子系统，且既有异步显示漏洞仍未修） |
| AUTH 8 | TC-AUTH-001..006、008 | 001/002/003 需要 task-token 与"平台准入未开"的完整组合；004/005/006 需要敏感动作四类与专项 grant 消费；008 需要"失联/撤销后准入"与已消费保留的调度面 |
| RPR 12 | TC-RPR-001..012 | repair-governance 全链（额度、重试、可修复边界） |
| EVD 10 | TC-EVD-001..010 | evidence-delivery 契约（交付物、证据摘要、拒绝路径） |

**因此 Gate 结论仍为 NO-GO**：TC 从 0 提升到 **2（+1 部分）**，距 49 仍有 46 条；且这 46 条缺的是**派发/调度/通知/修复/证据**等尚未实现的业务面，不是补测试就能补齐的。

---

## 附录 B — 整改轮 3（gate3-20261025T135000Z）

附录 A 之后又有一轮整改，专门处理「可判定红」与「TC 部分」。**Gate 结论不变：NO-GO。**

### B.1 handler 33 → 0 的轨迹

| 轮次 | 失败 | 定性 |
|---|---|---|
| gate 首轮 | 3 | 2 条 runner 缺陷（克隆丢迁移 seed 单行）+ 1 条**本变更引入的回归** |
| seedfix | 2 | `task_usage_hourly_rollup_state(id=1)` 随 `--schema-only` 丢失 → runner 加显式白名单只读复制 |
| ownfix | 0 | `StartTaskForClaim` 把 `daemon_id IS NULL` 的既有云 runtime 误判为冲突 → 收紧为「已绑定才校验」 |

最终：**run 4557 / pass 4510 / fail 0 / skip 47 / leaf 4133**（`gate3-20261025T135000Z-handler-full`）。
1 条回归的取证方式值得固化：**同一用例在干净 HEAD worktree 上 PASS**，因此属本变更引入，不能记进「既有红」。

### B.2 TC 台账（覆盖附录 A 的 2(+1)/49）

| TC | 状态 | 证据 |
|---|---|---|
| TC-AUTH-007 | PASS | `execution_tc_auth_test.go`（附录 A） |
| TC-AUTH-009 | PASS | 同上 |
| TC-AUTH-010 | **PASS（原「部分」）** | `execution_tc_auth010_test.go`：真 tools 验签器、中文/CRLF/分隔符 golden、单字节翻转、跨域、未知版本、异钥、私钥不外泄；`tc-20261025T140500Z-auth010-green2` **7/7（6 leaf）** |

RED（鉴别力）证据：`…-auth010-red1`（把篡改改成空操作）→ 篡改用例 FAIL；
`…-auth010-red3`（用另一签名域签 payload）→ 正例 + 跨域用例 **2 FAIL**。

新台账：**3 / 49**（另 0 条部分）。RUN 10 / NTF 7 / RPR 12 / EVD 10 仍缺**业务面**，非缺测试。

### B.3 仍未关闭（与附录 A §6 一致，此处只记增量）

- daemon 33 条失败经干净 HEAD 对照确认为**既有红**，本轮不动，不计绿。
- handler 47 skip 多为需外部凭据/平台能力的用例，按纪律不计 PASS。
- 规格轴 / 安全轴评审仍 INCOMPLETE。
- Gate3 / commit / push / 部署 / 真实 CR 均未授权；原库 HOLD 未解除。

### B.4 本轮新增已知边界

1. seed 白名单是**人工清单**（单行、非业务数据、缺行纯属克隆产物），新表须显式加入。
2. 未绑定 daemon 的 runtime 仍可被同工作区内持有**精确 tuple** 的任意 daemon 领取；tuple 由服务端定向下发。
3. 撤销锁只与 `UPDATE cr` 互斥，不覆盖绕过 `cr` 行的 head 写入路径。
