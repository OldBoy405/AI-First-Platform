# 2026-11-13-aifi-45-real-execution-closure 切片执行计划

> 依据：design.md（D1-B、D4-A，Gate 2 已确认 G2-1～G2-6 按建议）、test-plan.md（13 TC，2026-11-14 第三次同步后）。全部切片顺序执行，并行组一律 `—`（止损顺序要求前一片结论决定后一片）。
> 长程模式（full_auto）：**不覆盖**一次性 PG/podman、真实模型、真实 backend/daemon、tools 仓修改、提交推送部署、受审文档修改——标「🔒」的切片在到达授权点时必须停下问用户。

## Dependency Graph Summary

```
S1 endpoint 基数(TC-REC-003)  ─┐
S2 claim 合同值(TC-REC-002)   ─┼→ S3 daemon 预消费(TC-REC-001) → S4 真实运行驱动+清理冒烟(TC-REC-007)🔒
                               │                                    → S5 真实 run A(TC-REC-004)🔒
                               │                                    → S6 撤销:组件(TC-REC-006)+真实 run B(TC-REC-005)🔒
                               └───────────────(止损：S5 失败只修 S1–S3)──────────
S9 授权节点信任根注入(TC-REC-009，依赖 S3 与成对 tools change；Gate 2 重审后才写代码，须在 S5 之前)
S12 预消费信任根按 task generation 取子目录(TC-REC-001 子用例，依赖 S3、S9、S10；Gate 2 重审后才写代码，须在 A0 重跑与 S5 之前)
S7 D4 workspace 边界(TC-WSD-005/006/007)🔒(一次性 PG) → S8 全组回归+台账(TC-REC-008)🔒
```

**止损顺序（design D5）**：S1 → S2 → S3 → S9 → S4 → S5 → S6 → S7 → S8。首次真实运行（S5）失败只修 S1–S3 的节点证据生产者，不借 S7 改动或手工 DB 修复把链路推绿，S6/S7 的真实保证重新取舍。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟡 Med | S | — | TC-REC-003 | `executionBindingEndpoint` 支持按运行上限接受至多 N 个不同 challenge（authorized 已预消费=2，其余=1，同字节仍幂等）；不触发第二次消费 | 无 |
| 2 | P0 | 🟡 Med | M | — | TC-REC-002 | claim 响应新增 `PipelineExecutionContract`（只由 DB 初始 `stage=execution, decision=approve` 记录推出）；daemon `Task` 接收；撤销后不降级 | 无 |
| 3 | P0 | 🔴 High | M | — | TC-REC-001 | `prepareClaimedPipelineTask` 对 authorized 节点在 agent 启动前走既有 strict 消费；成功后内存标记、run 结束跳过 `recordDeliveredConsumption`；失败不启动 agent；未知非空值拒绝；空值原路径不变 | 1, 2 |
| 4 | P0 | 🟡 Med | M | — | TC-REC-007 | `scripts/aifi45-real-run/`：驱动骨架、配置校验（拒绝缺配置/空模型/Fable/未知参数）、资源登记与全路径清理、cleanup-smoke 场景 🔒 podman | 3 |
| 5 | P0 | 🔴 High | M | — | TC-REC-004 | 驱动 `architecture-main` 场景：真实来源+篡改拒签+writer 双 advance 一回执+reviewer 零写有回执+人工门+交接处重启；首次失败止损 🔒 podman/DB/模型 | 4 |
| 6 | P0 | 🔴 High | M | — | TC-REC-006, TC-REC-005 | 组件：撤销后 `ResumeActiveRuns`/新 Runner 不派发不推进；驱动 `architecture-revoke` 场景（DB 确认 writer running 时撤销，否则 INCONCLUSIVE）🔒 一次性 PG；真实 run B 另需 🔒 模型 | 5 |
| 7 | P0 | 🔴 High | L | — | TC-WSD-005, TC-WSD-006, TC-WSD-007 | `ControlCommandInput.WorkspaceID` + `ApplyControlCommandTx`/`CreateReservationTx`/生产 handler 的 workspace `FOR KEY SHARE`；迁移 33 处 fixture；并发探针（`pg_blocking_pids`，无 sleep，无生产 hook）+ `governance-wsd-lock` 🔒 一次性 PG | 无（但在 S5 之后做） |
| 8 | P0 | 🟡 Med | S | — | TC-REC-008 | `selections.json` 新增 rec-001/002/003/009/rec-revoke/handler-wsd-race/governance-wsd-lock；`test-ownership.json` 移除 command 探针已知失败；CUSTOM.md 登记；全组回归 🔒 一次性 PG | 1–7 |
| 9 | P0 | 🔴 High | S | — | TC-REC-009 | daemon 对授权节点注入 `CRCTL_EXECUTION_TRUST_ROOT`：`Task.ExecutionTrustRoot`（`json:"-"`）在预消费成功处设置，`injectTaskCRWorkspaceEnv` 内先 delete 后按条件发布；依赖成对 tools change（已实现、未提交） | 3（须在 S5 之前） |
| 10 | P0 | 🔴 High | M | — | TC-REC-010 | daemon 对 strict、无 pipeline 载体的 source 任务新增预检/预消费分支（D1.8）：CR 身份沿用现有绑定规则，范围为局部值，不写 `Pipeline*`、不设 `ExecutionPreconsumed`/信任根；失败关闭 | 3 |
| 11 | P0 | 🟡 Med | S | — | SC-REC-010（并入 tools node-trust-root 的 SC-NTR-009/010；multica 侧无单测） | tools 并入 `node-trust-root`（其 Gate 1/2/3 重审）：`workspace inspect --detail` 补 `targetSpecId`/`targetVersion`（D1.9）；multica 侧 `cr-workspace.mjs` 改写有效 `target-version` 🔒 tools 修改须独立 Gate | — |
| 12 | P0 | 🟡 Med | S | — | TC-REC-001（增子用例）、TC-REC-009（期望值更新） | 预消费信任根按 task generation 取子目录（D1.10）：`ExecutionTrustStore.Generation`，`prepareClaimedPipelineTask` 改用；不改 tools、不改 server | 3、9、10（须在 S5 与 A0 重跑之前） |

## Rationale

### Slice 1: endpoint 基数（P0，先行）
- **依赖关系**：纯 daemon 内存逻辑，无外部依赖；S3 依赖它提供「authorized 已预消费=2」。
- **风险分析**：经验库「复制的身份校验只测一个失败条件」→ 每种 endpoint 类型（source/legacy/未预消费/authorized 已预消费）与每个 challenge 序号独立 subtest。放宽单 proof 是对 SC-AUTH-007 的明示修订，不得对其他 endpoint 放宽。
- **工作量估算**：S（1 个文件 + 1 个测试文件，现有 endpoint 测试不依赖 DB，可本地 `go test ./internal/daemon`）。

### Slice 2: claim 合同值（P0）
- **依赖关系**：与 S1 无依赖；S3 需要它识别 authorized 节点。
- **风险分析**：误分类会让合法 legacy 被阻断或授权节点漏掉预消费；撤销后初始记录仍在，不得降级。需要 DB 的 handler 测试（TC-REC-002）。
- **工作量估算**：M（handler、响应结构、daemon Task、sqlc 查询可能新增）。

### Slice 3: daemon 预消费（P0，核心）
- **依赖关系**：依赖 S1（endpoint 上限）、S2（合同值）。
- **风险分析**：高。涉及授权安装、private relay、run 结束的重复消费、未知合同值。节点 agent 的 `.crctl` 授权材料是否可见尚未验证；若必须改 crctl/skill，即停下建成对 tools change（不在长程预授权内）。
- **工作量估算**：M（daemon 2–3 个文件 + 测试；既有 strict 路径可复用）。

### Slice 4–6: 真实运行驱动与两次真实 run（P0，需授权）
- **依赖关系**：S4 驱动与清理冒烟（只需 podman）先于 S5；S5 成功后才做 S6（撤销证据依赖 S5 的链路）。
- **风险分析**：真实模型次数与费用、容器泄漏（经验库）。architecture run 总计 ≤3，第三次仅止损且需重新确认；到授权点停下问用户，不自行起 podman 或调模型。
- **工作量估算**：S4=M，S5=M（以运行与定位为主），S6=M。

### Slice 7: D4 workspace 边界（P0）
- **依赖关系**：与 S1–S6 代码无依赖，但按止损顺序在真实链成功后做，避免混合失败原因。
- **风险分析**：高（锁序、33 处 fixture）。经验库「ReadCommitted 下先读后写守卫放在序列化锁之前」「常量 id 多链键冲突」。旧探针 `TestWorkspaceDeletionRefusesNewCommand` 断言不放宽。
- **工作量估算**：L（>3 个文件、33 个调用点；fixture 迁移属机械工作，可委派 balanced 子代理）。

### Slice 8: 全组回归与台账（P0）
- **依赖关系**：S1–S7、S9 全部完成。
- **风险分析**：0 FAIL、0 skip、remaining=0；CUSTOM.md 登记使用 STDD change id（台账已接受原生 STDD 行，如 line 194 先例）。
- **工作量估算**：S。

### Slice 9: 授权节点信任根注入（P0，S5 之前）
- **依赖关系**：依赖 S3（`ExecutionPreconsumed` 与预消费所用的信任库）与成对 tools change（变量通道，已在 tools 仓实现、未提交；Gate 1/2 于 2026-11-14T23:06:22 重签 current，Gate 3 因并入 B2/B4 而 stale，待用户在 S4/S5 取证后重签）；设计第 7 条经 Gate 2 重审通过后才写代码。
- **风险分析**：中高。变量泄漏到非授权任务或被 custom_env 覆盖会改变 legacy 行为；`isBlockedEnvKey` 不拦 `CRCTL_*`，靠「后写加先删」保证。注入只定位信任根，不授权、不提供隔离；agent 是否读得到该目录要到真实 A 才知道。
- **工作量估算**：S（1 个 Task 字段、1 处设置、`injectTaskCRWorkspaceEnv` 内几行，加一个测试文件；沿用 `cr_workspace_binding_test.go` 的函数级测试结构）。

### Slice 12: 预消费信任根按 task generation 取子目录（P0，A0 重跑与 S5 之前）
- **依赖关系**：依赖 S3（预消费所用信任库）、S9（注入值即该根）、S10（source 路径同一入口）；D1.10 经 Gate 2 重审通过后才写代码。
- **风险分析**：中。单测里的 crctl 是替身，真实 crctl 下 source→节点是否都成功只能由 A0 重跑与真实 A 观察；TC-REC-009 的期望值随之更新。
- **工作量估算**：S（`execution_trust.go` 一个方法，`prepareClaimedPipelineTask` 一处调用，TC-REC-001 一个子用例）。
