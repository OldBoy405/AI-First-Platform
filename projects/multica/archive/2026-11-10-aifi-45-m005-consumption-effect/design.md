# AIFI-45 M005 consumption-effect — 技术设计

> 设计来源：design 档（strong）planner 起草正文并独立挑战，主会话核对源码后合并（见末节「独立复核处置」）。

## Context

准入决策器 `DecideAdmission`（`execution_admission.go`）只在「该 consumption 的 task 有 effect 结算 → 指向已入链、验签通过、`command_digest` 与冻结命令字节一致的 v2 verdict、cursor 已覆盖其 seq」时放行。这条链的写入口（`ApplyControlCommandTx`、`TransitionControlCommandTx`、`AppendVerdictFrameTx`、`SettleControlCommandTx`）已建成并有测试，生产零调用方，所以生产准入永远停在 `WAIT_TRUSTED_T_COMMIT`。

已批准的信任模型（AIFI-45 design §2）：T（含 crctl）是非可信客户端，签发者在服务端，只签服务端可核实的事实。服务端现在唯一已经在核实并提交的事实，是 `HandleDaemonExecutionConsumption` 里的 consumption 回执：认领行、授权头、已签发的绑定证明在同一事务内重验。

本 change 只补这一个生产者：不改 schema、路由、T、daemon，也不改准入判定。实施另更新 `execution_admission.go` 中陈旧的「写入口无生产调用方」注释、登记 CUSTOM.md，并在 `scripts/aifi45-disposable/selections.json` 增加一个一次性库选择（proposal C4）。

## Decisions

### 1. effect 只表示「平台已核实并提交 consumption」

**方案**：settlement 的 `effect_kind=consumption`、`effect_ref={"receipt":<回执 id>}`。它不断言 T 的业务工作已提交，也不断言额度。

**为什么**：服务端核实不了 T 的工作（发生在 daemon 主机的 Git 里）；签一个核实不了的结论，等于把 agent 自报变成了平台背书。

**排除**：把 T 的裁决签成 effect——违背已批准的信任模型；用远端 GitHub 观察当结算——M008 K5 已定「远端是观察，不是结算」。

**后果（须知）**：首个 consumption 之后准入即可 `ADMITTED`。T 的停止/额度候选（RUN-006）与恢复入口（M008）的事实仍未被签为 effect，留给后继载体。

### 2. 签发与回执同一事务，只在首次写入路径

**方案**：仅在回执 `INSERT … RETURNING` 有行的路径、commit 之前调用 `issueConsumptionEffectTx`；任一步失败整笔回滚，回执也不落库。回执重放（`ON CONFLICT` 分支）不签发。

**为什么**：若回执已提交而 effect 缺失，重放不会再签发，准入将永久停在 `WAIT_TRUSTED_T_COMMIT` 且无重试路径。

**排除**：提交后补签或尽力补签——留下「有回执无 effect」；对历史行回填——签名时间与事实不符，且工作区纪律要求先排除对历史 CR 实例的回填或改写。

### 3. 复用平台已有 execution 密钥；清单在进程内现生成

**方案**：私钥取 `ApprovalService` 已有的 Ed25519 key（`execution_consumption.go` 已校验其存在）。写入口要求清单按 purpose 区分，所以进程内构造两条 `ControlKey`：`platform-consume-command`（purpose `control-command`、domain `execution-control-command/v1`）与 `platform-consume-verdict`（purpose `tool-attestation`、domain `execution-verdict/v1`），公钥相同，scope 精确等于该链的 `{store_id, lineage_id}`，有效期取当前时间 ±1h。签名域由 `controlPreimage(domain, …)` 区分。

**为什么**：签名与验签在同一进程同一事务，清单文件与 pin 只防「文件被替换」，这里不存在该攻击面；不新增密钥、不新增生命周期。两个 key id 固定，不由 `a.keyID` 派生（避免超长，且 map 以 key id 为键，同一 id 无法同时满足两种 purpose）。

**排除**：清单文件与 pin 仪式、第二把密钥、轮换（见 proposal non_goals）。

### 4. 链粒度：每个 CR 一条 lineage，store 按 lineage 派生

**方案**：`lineage = uuid.NewSHA1(mergeLineageNamespace, "consume:"+workspaceID+":"+crID)`（沿用 `MergeLineageID` 惯例）；`store_id = "platform-consumption:"+lineage`；`scope = "consume:"+crID`；epoch=1、owner_fence=1；cursor 在 governance 内联 `INSERT … ON CONFLICT DO NOTHING` 引导（`BeginOwnerTx` 在 daemon 包，governance 不能反向 import）。

**为什么**：verdict 的唯一键是 `(store_id, epoch, seq)`，不含 lineage，所以 store 必须随 lineage 变，否则第二个 CR 的首帧会撞键。每 CR 一链：CR 间互不串行，CR 内串行（既有每 lineage 单 open 槽位语义）。

**排除**：全局单 lineage 或常量 store——过度串行，且撞唯一键。

### 5. 同一 task 新 generation 的守卫：锁后、只认匹配的 consumption effect

**方案**：先取 lineage 锁，再读 `request_id=task_id` 的结算。已有 `kind=effect 且 effect_kind=consumption` → 跳过签发（回执照常落库）；已有其他结算或 command 占用 → 返回错误，整笔回滚。

**为什么**：回执唯一键含 `dispatched_at`，同一 task 的新 generation 是新回执，但 command 主键是 `request_id`；不守卫会让重新认领的 task 永远无法 consume。守卫必须在锁之后，否则两个并发 generation 会同时读到「无结算」。只认匹配的 effect，避免「已有他种结算（如 channel dispatch）却返回 201 而没有 consumption effect」。

### 6. `reservation_id` 取回执 id；撤销串行靠 handler 已持有的锁

**方案**：`candidate.reservation_id` 与 command 的 `reservation_id` 列填本次回执 id（UUID 列、无外键）。`SettleControlCommandTx` 的撤销重查沿 command→reservation→selection 连接，缺行视为未撤销；撤销与 consumption 的串行由 handler 在调用前已取得并验证的认领行锁与授权头锁保证。

**为什么**：consumption 没有预算 reservation，新建 selection/reservation 生产者属 non-goal。

**契约**：`issueConsumptionEffectTx` 只能在 handler 已持有认领与授权头锁的事务里调用；该前置写在函数注释里。

### 7. 加锁顺序固定

**claim 行 → 授权头 → lineage advisory lock → cursor `FOR UPDATE` → command**。不提前取 lineage 锁，不在持 lineage 锁时回头取行锁。

## Architecture

```text
Handler（ReadCommitted；认领行锁 → 授权头锁 → 验绑定/证明）
  → INSERT receipt
     ├─ conflict → 读原回执 → 200 / changed=false（不签发）
     └─ RETURNING id → issueConsumptionEffectTx
          1. lineage、store、scope 由 (workspace, cr) 确定
          2. 取 lineage 锁 → 读 request_id 的结算（守卫，见决策 5）
          3. cursor 引导 + FOR UPDATE → seq = last_seq+1，prev = last_digest 或 ""
          4. 签 command（operation=execution-consume，request_id=task_id，reservation=回执 id）
             → ApplyControlCommandTx → created→issued→result_ready
          5. 签 v2 verdict（result=pass，effect=effect，command_digest=sha256(command)）
             → AppendVerdictFrameTx（CommitRef="consumption:"+回执 id）
          6. SettleControlCommandTx（kind=effect，effect_kind=consumption，effect_ref={"receipt":id}，head_ref=grant digest）
  → COMMIT → 201 → DecideAdmission（判定逻辑不变）
任一步失败 → ROLLBACK（回执一并回滚）
```

`issued → settled_*` 被触发器 `cr_execution_command_transition` 禁止，所以必须经 `result_ready`。

## Risks / Trade-offs

| 风险 / 代价 | 控制 |
|---|---|
| 准入语义被误读为「T 已被核实」 | 决策 1 与 spec 写明；`effect_kind=consumption` 可查；代码注释同文 |
| 自签自验不是安全边界 | 边界是私钥与数据库凭据不被 agent 取得（部署两项检查，归上线就绪清单）；保留链是因为写入口、准入与既有用例都依赖它 |
| 同 CR 串行、handler 行锁持有更久 | 固定锁序；TC-CE-003（同 CR 双 task）与既有撤销竞态用例作回归 |
| 同 task 两行回执使准入计数为 2 | 准入只与 0 比较并 `LIMIT 1` 读同一有效链，仍 `ADMITTED`；TC-CE-004 锁定该行为，不改判定器 |
| 缺 reservation 行使通用撤销重查失效 | 由 handler 持有的授权头锁补足；函数前置条件写入注释，撤销竞态用例保留 |

## 独立复核处置（strong planner，8 条）

| # | 严重度 | 发现 | 处置 |
|---|---|---|---|
| 1 | BLOCK | 常量 store 使第二个 CR 首帧撞 `(store_id,epoch,seq)` | 已采纳：store 按 lineage 派生；TC-CE-003 加 CR-B |
| 2 | BLOCK | 锁前守卫在并发新 generation 下失效 | 已采纳：守卫在 lineage 锁之后 |
| 3 | MINOR | 新等待点延长行锁持有 | 已采纳：固定锁序（决策 7）；既有撤销竞态用例回归 |
| 4 | MAJOR | 两个 purpose 不能共用同一 key id | 已采纳：两个固定 key id（决策 3） |
| 5 | MAJOR | 「任意结算存在即跳过」会吞掉异义占用 | 已采纳：只跳过匹配的 consumption effect |
| 6 | MINOR | 回执 id 作 reservation 使撤销重查退化 | 已采纳：前置条件写入契约（决策 6） |
| 7 | MINOR | 同 task 两行回执使计数重复 | 已采纳：TC-CE-004 断言准入仍 ADMITTED，不改判定器 |
| 8 | MINOR | 缺少连续 generation / 跨 CR 测试 | 部分采纳：跨 CR 与新 generation 已入测试；**并发 generation 形态不测**——锁序与守卫位置已由设计保证，并发压力用例已记入 test-plan §五「本期不补」 |
