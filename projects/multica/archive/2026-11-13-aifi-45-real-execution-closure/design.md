# AIFI-45：真实 daemon+agent 授权执行闭环（节点证据、受控停止、删除后终态安全） - 技术设计

## Context

本稿是 UNDERSTAND 的 Gate 2 设计输入，不是实施授权。本轮只读核对代码并覆盖本文件；未运行测试、数据库、podman 或真实模型，也未修改 `specs/`、`test-plan.md`、`canonical/`、两个代码仓或归档产物。下文用 `multica/`、`tools/`、`知识库/` 区分三个根目录；行号是本次只读核对位置。

**2026-11-14 同步修订（BUILD 阶段，待 Gate 2 重审）**：①D4 写入侧 workspace 锁模式由 `FOR SHARE` 改为 `FOR KEY SHARE`，并发探针不加生产 hook，新增 `governance-wsd-lock`（ADJ-S7-1/2/3）；②D1 新增第 7 条：授权节点的信任根由 daemon 注入 `CRCTL_EXECUTION_TRUST_ROOT`，承接已完成的成对 tools change（ADJ-E4-1）；③D1 第 2 条的内存标记名与实现一致（ADJ-S3-1）。重审议题见文末 G2-7、G2-8。

**2026-11-14 第二次同步修订（无模型替身运行 A0 发现，待 Gate 2 重审）**：真实 podman 整栈的替身运行（`architecture-stub`，零模型费用，输出前缀 `stub-run`，不是 TC-REC-004 证据）在 source 任务启动 agent 之前即被 daemon 拒绝，暴露两处 design 假设与现有生产代码不符：**B1** 设计 D1.2/F6 假定「source strict 预检已存在」，实际 comment 触发、无 pipeline 载体的 source 任务在 `prepareClaimedPipelineTask` 里因 `PipelineWorkspace` 为空而得 `EXECUTION_BINDING_UNAVAILABLE`，无法产生自己的 consumption，而 `StartArchitecture` 的 admission 要求它；**B2** daemon 对每个 pipeline 节点任务要求 `crctl workspace inspect --detail` 输出 `targetSpecId`/`targetVersion`，tools HEAD 不输出。本轮新增 D1.8（source 路径，multica）、D1.9（tools inspect 补字段，成对 tools change）、SC-REC-009/010、TC-REC-010、S10/S11、G2-9；同轮并入 D4.4「/current head」措辞勘误与 MINOR-9 的 CP 映射说明（见 test-plan 回归矩阵）；用户已裁定 B1 与 B2 合并为同一次修订与同一次 Gate 2，B2 选「tools 补字段」。证据见 `design-adjustments.md#ADJ-A0-1`。

**2026-11-14 第三次同步修订（A0 重跑发现，待 Gate 2 重审）**：B1/B2 修复后 A0 重跑（零模型费用）source 任务已取得 consumption=1、effect=1，writer 节点也越过 authority 事实，但随后在预消费处失败：`EXECUTION_CONSUMPTION_CONFLICT`。**B3**：daemon 的信任根每 workspace 只有一个，而 tools `authorization-bind` 的本地 receipt 以 `<scopeHash>-<grant_id>-<stage>` 为键且 stage 固定、challenge 每次随机，所以 source 之后的任何节点、任何重新派发的 generation 预消费都会冲突；平台侧本来就是每 task+generation 一条。本轮新增 D1.10（预消费用的信任根按 generation 取子目录）、S12、G2-10，并在 SC-REC-001 与 TC-REC-001 里各增一条，不新增 SC/TC/CP；用户已同意按该方案处理（只改 multica daemon，不改 tools 合同）。证据见 `design-adjustments.md#ADJ-A0-2`。

### 当前问题与既有先例

- 节点任务复用 F6 的 private relay、F1 的 consumption/effect 和 F7 的撤销状态机，不新增 journal、outbox、第二套账本或迁移历史回执。节点完成锚仍是该节点任务当前 generation 的回执及自身 effect，source 只用于 initial/review/approve 的重新准入；不能统一改成 source 锚（`知识库/projects/multica/archive/2026-11-11-aifi-45-admission-task-binding/design.md:154-171,193-213`）。
- 首次新 consumption 已在同一数据库事务提交可信 command、verdict、settlement、投影与 receipt/effect；同 generation 重放复用结果，后续 generation 只复用既有可信输入，不补新签名（`multica/server/internal/governance/execution_consumption_effect.go:66-155`；`multica/server/internal/governance/execution_consumption.go:197-242`）。
- 真实 harness 复用 podman 的 `multica/daemon:real-pg`、tmpfs PG17、迁移、真实 daemon 与 pi CLI；历史模型仅为 `Gobao/deepseek-v4.1-flash` 先例，不是本变更的模型选择（`知识库/projects/tools/archive/2026-11-08-aifi45-trust-anchor-chain/validation/e2-m2-real-loop-20261108b/run.sh:101-138,249-289,443-500`）。一次性 PG 的生命周期/释放和逐 selection 执行可复用 `scripts/aifi45-disposable`，但它没有 server/daemon 编排，仍需一个统一驱动（`multica/scripts/aifi45-disposable/instance.mjs:19-138`；`multica/scripts/aifi45-disposable/run-selection.mjs:1-15,110-180`）。

### 只读事实（F1—F12 摘要）

| 编号 | 已核对事实及本设计的直接影响 |
|---|---|
| F1 | daemon 的 per-run endpoint 是 `MULTICA_EXECUTION_BINDING_ENDPOINT`；只处理 POST，其他方法 405。相同字节重放幂等，不同 challenge 的第二次请求当前返回 409（`multica/server/internal/daemon/execution_binding_endpoint.go:45-58,126-163,179-190`）。daemon 只把实际交付的 challenge 送入 `recordConsumptionAfterDelivery`；该生产开关在 `New` 为 true（`multica/server/internal/daemon/daemon.go:852,8758-8781`）。 |
| F2 | crctl 对 authorization-bind 的 409/5xx 统一 fail-closed 为 `EXECUTION_BINDING_UNAVAILABLE`，成功才更新本地 effect/receipt；非 legacy advance 每次生成新随机 challenge（`tools/skills/shared/crctl/scripts/lib/execution-binding.mjs:156-170`；`tools/skills/shared/crctl/scripts/crctl.mjs:1499-1513,1569-1583,1627-1650`）。因此 writer 的第二次 advance 当前会撞 run 级单次一证。 |
| F3 | 生产门控只在 `advance`、`backlog-set`、`archive`、`approve-and-advance` 和 reservation 创建处调用；普通人工 approve 走 `approveAndAdvance`，不经过该门控（`tools/skills/shared/crctl/scripts/crctl.mjs:1467-1470,1506,1662-1760,1945,2662,6195,7194`）。 |
| F4 | 节点写次数不是每节点恒 1：writer 首次最多 2 次，PASS review 为 0；若按归档锚合同，零写入节点无法靠自身 crctl 回执完成（`tools/skills/develop/write-tech-design/SKILL.md:50-52,139-141`；`tools/skills/develop/review-tech-design/SKILL.md:150-154`）。完整处理见 D1 表。 |
| F5 | 已归档准入明确规定“当前任务 + 当前 generation + 当前 head”和首次 effect，且历史不自动回填（`知识库/projects/multica/archive/2026-11-11-aifi-45-admission-task-binding/design.md:154-171,193-213`）。 |
| F6 | strict preflight 已执行 daemon token/CR/agent 身份校验，安装并验证 grant，再用 `authorization-bind` 私有 relay 取证；启动前失败不拉起 agent（`multica/server/internal/daemon/execution_verifier.go:26-113,184-217`）。节点 claim 通常没有 source 的 `TriggerCommentContent`，不能直接把它当 strict source；legacy 也不能被误升级（`multica/server/internal/daemon/execution_verifier.go:26-58`；`multica/server/internal/daemon/daemon.go:5810-5835`）。 |
| F7 | 撤销持 CR 行锁，追加 reject approval_record 并原子移动 `execution_authorization_head`；非 approve head 在 `Decide` 返回 `HEAD_REJECTED`，不新增、不推进（`multica/server/internal/governance/execution_authorization_revoke.go:291-342`；`multica/server/internal/governance/execution_admission.go:153-156`）。撤销不走 approve，不落 run 终态；revoked/wait_reason 是授权状态，不是 run 新状态（`multica/server/internal/governance/execution_admission_gate.go:187-215`）。 |
| F8 | 旧真实链路已有 source bind、独立 T 重提取、改一个来源字段拒签、重启去重；历史 script 的 trap 只足以证明其当时路径，不能替代本 harness 的 setup 失败/超时清理（`知识库/projects/tools/archive/2026-11-08-aifi45-trust-anchor-chain/validation/e2-m2-real-loop-20261108b/run.sh:101-138,350-429,521-569`）。 |
| F9 | 周期恢复只扫描 architecture 与 requirement（`multica/server/internal/daemon/daemon.go:1825-1829`）。run 唯一键在 `pipeline_run`，活动任务唯一索引在 `agent_task_queue`（`multica/server/migrations/585_aifirst_pipeline_runs.up.sql:49`；`multica/server/migrations/591_agent_task_pipeline_node_active_unique.up.sql:14-17`）。 |
| F10 | workspace 删除先 `FOR UPDATE`，随后清 notice 与 dispatch-root，但不级联 consumption/command/verdict/settlement（`multica/server/internal/handler/workspace.go:1076-1160,1200-1350`；`multica/server/internal/governance/workspace_delete_execution.go:22-90`）。reservation 只有无锁 `SELECT EXISTS`，command 无 workspace guard，这是 D4 的静态根因（`multica/server/internal/governance/execution_control_reservation.go:73-106`；`multica/server/internal/governance/execution_control_store_state.go:148-215`）。 |
| F11 | `ApplyControlCommandTx` 的唯一生产调用方是 `issueConsumptionEffectTx`，workspace 来自 authenticated daemon claim，lineage 由 workspace/CR 派生且不依赖 selection；receipt 本身没有可 join 的 selection（`multica/server/internal/governance/execution_consumption_effect.go:58-59,66-155`）。只读枚举与输入一致：33 处测试直调 + 1 处生产调用；红灯探针保留在旧入口，CI 的 R5 理由正是旧入口未覆盖生产路径（`multica/server/internal/governance/execution_control_command_attestation_test.go:151-213`；`multica/server/internal/handler/workspace_delete_no_recreate_test.go:174-241`；`知识库/projects/multica/archive/2026-11-12-fork-ci-test-evidence-trust/design.md:257-264`）。 |
| F12 | fork-ci 曾把人工确认改成机器可核对 CP；本变更的真实结果必须由脚本输出带 run/task/effect/失败原因的 PASS/FAIL，不靠会话中“看见绿灯”（`知识库/projects/multica/archive/2026-11-12-fork-ci-test-evidence-trust/design-adjustments.md:598-625`）。不得用 `agent confirm` 把未执行项写成 `manual-pass`（同文件 `:497-506,673`）。 |

### Gate 1 固定约束（不改）

1. 真实模型次数与费用须在 BUILD 前另行确认，不用 Fable；architecture run 上限 3 次。一次性数据库只能由本变更自建、自释放，不接触旧实例或他仓授权（`知识库/projects/multica/changes/2026-11-13-aifi-45-real-execution-closure/canonical/proposals/2026-11-13-aifi-45-real-execution-closure.yaml:84-86,146-147`）。
2. 若最终方案必须改 tools 的 skill、crctl 或生产调用方，立即停止并建立有各自 Gate 的成对 tools change，不双写、不互认批准；tools 既有脏工作树不归本变更（同文件 `:88-90`）。multica 代码注释使用英文，并按当时 CUSTOM 登记；不接受本 change id 就停下确认（同文件 `:90`）。
3. 不改归档；不改签名 schema、密钥或签名语义，不迁移/回填历史 consumption。确需改归档行为合同，必须在当前 change 明示修订，不能当缺陷顺手改（同文件 `:91,115-123`）。
4. 不做 M008 可信 no-effect/旧执行者自动重准入，不做 code run，不清既有残留 `wait_reason`，不做平台独立查询面，不做真实 backend CI/WSL/管理员凭据/历史 legacy 迁移；统一收口后仍有红灯只显式记录（同文件 `:116-123`）。
5. 长程预授权不覆盖真实模型、podman/数据库、真实 backend/daemon 编排、tools 修改、提交、推送或部署；遇到这些边界停下询问。

## Decisions

### 1. D1 节点证据生产：daemon 生产一次平台证据，agent 的 advance 只做节点业务推进

**方案（B 的有界修订版，G2-1 已确认；信任根注入见第 7 条，2026-11-14 修订）**：

1. **识别 authorized 节点而不误伤 legacy**：server 在以 DB 为准校验 pipeline claim 时，增加只读 wire 字段 `PipelineExecutionContract`。若该 run 的 workspace/CR 存在初始 `stage=execution, decision=approve` approval_record，则填既有 `authorized-execution/v1`；没有初始记录才保持 legacy 空值。不要用当前 head 是否存在来降级：撤销或异常删除 head 后，初始记录仍在，daemon 会 preflight 并 fail-closed。未知非空合同值同样拒绝。该字段只解决“节点没有 source trigger comment，如何知道该走 strict”的识别问题，不是第二账本；现有 DB claim 校验点可复用（`multica/server/internal/handler/daemon.go:2624-2720`）。
2. **agent 启动前只消费一次**：`prepareClaimedPipelineTask` 对 source strict 或上述 authorized 节点调用现有 `consumeClaimedExecution`，沿用 daemon token、workspace/CR/task/generation/current head 校验、trust store 和 private relay；只有平台返回非空、已持久化的当前 generation receipt 后，才在该内存 Task 标记 `ExecutionPreconsumed` 并启动 agent。失败不启动，不落成事后消费（`multica/server/internal/daemon/execution_verifier.go:184-217`；`multica/server/internal/daemon/execution_consumption_client.go:58-65`）。该标记不持久化、不替代 receipt；同 generation effect 复用及后续 generation 规则仍由 M005 原入口负责。
3. **run-end 不重复消费**：只有上述成功 preflight 的任务跳过 `recordDeliveredConsumption`；legacy 和原有非 preflight 路径不变。这样每个节点任务当前 generation 的平台 consumption 恰为一条，effect 的 command/verdict/settlement request id 均属于该节点任务，而不是 source（`multica/server/internal/daemon/daemon.go:8758-8781`）。
4. **agent advance 与“一次一证”共存**：authorized 且已 preflight 的节点 run endpoint 改为最多接受 **2 个不同 challenge**；相同字节仍可无限幂等重放，第三个不同 challenge 仍 409。source endpoint、legacy 节点 endpoint 和未成功 preflight 的任务仍为 1。上限 2 来自本变更实际逐节点表的最大值，不写成无限多次，也不新增配置。每次仍单独做 Ed25519、current head、manifest、task/attempt/generation、TSID/256 上限校验（`multica/server/internal/governance/execution_binding_issue.go:37-41,276-340`）。这些 advance proof 不再触发第二次平台 consumption；唯一平台回执/effect 已由 preflight 产生。
5. **归档合同边界**：admission-task-binding 的节点完成锚、initial/review/approve source 锚和 M005 的“一 generation 一条 receipt/effect”均不变；SC-AUTH-007 的“run endpoint 恰一 challenge”需要在本 change 明示、限于已预消费 authorized 节点地修订为“最多 2 个不同 challenge，重放同字节例外”。签名 schema、签发上限和 legacy 行为不变。若用户不接受该修订，就不能把 B 当纯 daemon 内部改动实施。
6. **不强迫每节点造一次业务写**：零 advance 节点直接靠 preflight 回执完成；有 1/2 次 advance 的节点仍按原 skill 执行业务转换。保留现有 third-proof 409 和 `EXECUTION_BINDING_UNAVAILABLE` 红灯，不用事务回滚第一笔合法 CR 更新来伪装一次写。
7. **授权节点的信任根定位（D1.7，承接成对 tools change）**：BUILD 前的静态核对：crctl 只认 `--trust-root`，没有环境变量，也没有默认根；节点 skill 的 advance 不带该 flag；daemon 信任库（`ExecutionTrustStore.Root`，自 D1.10 起为 `~/.multica/execution-trust/<workspace>/<generation>`）只喂 daemon 自己 spawn 的 crctl。因此 preflight 成功后，agent 里的 advance 仍找不到 grant。按 G2-1 预设的路径，已另建成对 tools change `2026-11-13-aifi-45-node-trust-root`（独立的 Gate 1/2/3，均已由用户确认，互不代签），新增环境变量 `CRCTL_EXECUTION_TRUST_ROOT`：语义等同 `--trust-root`，同值通过、异值 `EXECUTION_TRUST_ROOT_INVALID`，仅对 `advance`、`authorization-bind`、`authorization-scope`、`sensitive-action`、`repair-admit`、`repair-resume`、`register`、`archive` 生效。multica 侧的契约（L2 表同名行）：
   - **值**：该任务 grant 所安装的信任库根，即 daemon 自己调用 crctl 时传入的 `--trust-root` 实参（预消费时已打开的 `store.Root`，D1.10 之后是该任务当前 generation 的专属根）。tools 侧逐字比较，不归一路径。
   - **范围**：仅 `ExecutionPreconsumed` 的授权节点任务。legacy、source 任务的环境里没有该变量；预消费未成功时 agent 根本不启动。
   - **位置**：在既有 `injectTaskCRWorkspaceEnv`（daemon.go，已在 custom_env 之后调用）内：函数开头与 `CRCTL_WORKSPACE` 等变量一起先 `delete`，在 `binding.bound()` 早退之后、与 `CRCTL_OPERATIONAL_WORKSPACE` 同条件地发布，即仅「已绑定且 `ExecutionPreconsumed`」的任务发布；未绑定则不发布，crctl 失败关闭。`isBlockedEnvKey` 只拦 `MULTICA_` 前缀与若干系统名，不拦 `CRCTL_*`，所以必须靠「后写加先删」，agent 的 custom_env 才不能设置或覆盖它。不调用 `os.Setenv`，daemon 进程环境不变；并发任务各自的 env map 互不影响。
   - **载体**：`Task.ExecutionTrustRoot`（`json:"-"`，不进 wire），与 `ExecutionPreconsumed` 在 `prepareClaimedPipelineTask` 预消费成功处同时设置。不新增第二个标记。
   - **"daemon-only" 的含义**：`execution_trust.go` 把信任库称为 daemon-only install root，并要求它在 CR workspace 与 `PipelineLocalWorkDir` 之外，以免「缺口换名重现」。该约束保持：安装与写入者仍只有 daemon，信任库仍在 agent 工作树之外；agent 得到的是路径，不是新的写入通道。实现时校正该注释，使其不再暗示 agent 不可知晓路径。agent 与 daemon 同一 OS 用户时，agent 本来就能读写该目录（目录权限 0700 只挡不同用户），注入没有改变这一点，也不声称改变。
   - **只定位，不授权**：agent 今天本来就能给 crctl 传任意 `--trust-root`，所以 agent 本地准入成功不等于平台授权。权威仍是平台侧该任务当前 generation 的预消费回执，以及服务端签发的 binding proof；注入不新增 agent 能力，也不提供隔离。agent 与 daemon 是否同一 OS 用户、provider 沙箱能否读该目录均未验证；读不到时 crctl 失败关闭（不回退 `.crctl`），表现为「无回执不推进」，按止损点处理。
   - **版本错位**：发布顺序先 tools 后 daemon 注入。daemon 对授权节点无条件注入，不探测 crctl 能力，不加握手 flag。旧 crctl 不认该变量时 advance 失败关闭，节点不推进，不会越权。
   - **影响面**：变量在场时 `register`/`archive` 也进入 control admission（tools 已接受，不开 env 旁路）。architecture 节点按节点表不调用二者；requirement 节点（含 requirement-register）的合同值与调用形态未核对，本变更不声称覆盖 requirement（G2-4）。

**逐节点静态表及推荐处理**：

| 节点 | 当前业务 advance/任务形态 | 推荐处理 |
|---|---|---|
| architecture `write-tech-design` | 首次 `requirement-approved→tech-designing` 一次，再 `tech-designing→tech-design-review-pending` 一次；回修/重进通常跳过第一次（`tools/skills/develop/write-tech-design/SKILL.md:50-52,139-141`）。状态机是两个独立合法转换，没有直接一跳（`tools/dir-graph.yaml:218-220`）。 | daemon preflight 一证；endpoint 放行至多两个不同 advance challenge；不改 skill/状态机。 |
| architecture `review-tech-design` | PASS 0 次，BLOCK 回修 1 次（`tools/skills/develop/review-tech-design/SKILL.md:150-154`）。 | preflight 一证；PASS 无需 agent 取证，BLOCK 至多一次。 |
| architecture human 门 | `human_approval` 不派发 agent 任务，Runner 直接等对账（`multica/server/internal/governance/runner.go:870-895`）。 | 不创建任务、不 preflight、不造回执；人工 source 锚不变。 |
| architecture `approve-tech-design` | 只发对账；approve 后 stamp 不走 preflight advance（`tools/skills/develop/approve-tech-design/SKILL.md:31-43`；`multica/server/internal/governance/runner.go:904-918`）。 | preflight 一证，approve 路径无需额外出证。 |
| requirement `requirement-register` | 默认 `backlog-set cr-id` 不经 execution 门控，仅传 trust-root 的 register 才 advance（`tools/skills/requirement/requirement-register/SKILL.md:32-34`）。 | preflight 一证；实际 advance 可为 0/1。 |
| requirement `write-requirement-prd` / `push-progress` | 只有 `backlog-set`/事务推进，没有 execution advance（`tools/skills/requirement/write-requirement-prd/SKILL.md:99-108`；`tools/skills/sync/push-progress/SKILL.md:1-40`）。 | preflight 一证，不造业务转换。 |
| requirement `review-requirement` | PASS 1 次，BLOCK 0 次（`tools/skills/requirement/review-requirement/SKILL.md:152-153`）。 | preflight 一证，PASS 至多一次。 |
| requirement human 门 / `approve-requirement` | 人工门无 agent；approve 只做 review stamp（`tools/skills/requirement/approve-requirement/SKILL.md:31-40`）。 | 分别按人工门、preflight 一证处理。 |

**为什么**：A 要同时修两个状态转换语义和所有零写节点；C 要打开 crctl、generation 证明和跨仓信任合同。B 复用已经具备身份校验、授权安装、消费和 effect 的 F6/F1 路径，只补“节点识别 + 启动前生产 + 有界业务 proof 重放”，能以最少状态面让零写和双写节点都满足现有准入锚。

**三个方案的比较、验证与风险**：

| 方案 | 改动/跨仓 | 归档合同 | 主要验证 | 风险与结论 |
|---|---|---|---|---|
| A. skill 侧每节点恰好一次门控写 | 所有零写节点要造业务转换；writer 要合并两跳；需成对 tools change。writer 合并并非删一行，而是修改 dir-graph 和调用方 `--expect`（`tools/dir-graph.yaml:218-220`）。 | 可保留 run endpoint 单 proof，但改动节点业务状态机；仍须证明“恰好一次”在重试/回修下成立。 | 全节点 PASS/BLOCK/回修/重进矩阵 + 真实 architecture/requirement。 | 改动面最大且把平台取证问题变成业务状态变化；**不推荐**。 |
| B. daemon preflight（推荐的有界修订版） | 主要改 multica；若 agent 授权材料可见性探针证明必须改 crctl/skill，仍须停下建成对 tools change。 | 明示修订 SC-AUTH-007 的 authorized-node endpoint 不同 challenge 上限 1→2；其余锚、签名、effect 合同不变。 | 组件覆盖 0/1/2/3 proof、同字节 replay、skip duplicate consumption、legacy/unknown marker；真实 A 覆盖双写 writer 与零写 PASS reviewer。 | 上限调整是有意的合同放宽，必须 Gate 2 明示；marker 误分类、run-end 重消费、agent grant 来源均需红测。 |
| C. 修改 control admission | 修改 crctl 合同、proof generation 与准入组合；涉及平台断言语义和 tools 成对 change。 | 同时触碰 SC-AUTH-007、M005/准入解释，迁移和旧回执边界更复杂。 | 全入口证明链、旧/新 generation、legacy、并发及跨仓版本组合。 | 为已存在的问题再开一套证明语义，验证矩阵最大；**不推荐**。 |

**备选方案及排除原因**：纯 B0（只把 strict preflight 扩到节点，仍保留 endpoint 单 proof）会让 writer 第二次 advance 继续 409，也会在 run-end 重复消费，因而不完整；task 结束后由 daemon 自签一份 advance 仍不能解决第二次 agent advance，且节点可能已 completed，不采纳；统一改用 source 锚违反 F5，不采纳。

#### D1.8 strict source 任务的预检与预消费（B1，2026-11-14 修订）

**事实**：`prepareClaimedPipelineTask` 对 strict 任务在 `preparePipelineTask` 之后要求 `task.PipelineWorkspace != ""`；该字段只由 `preparePipelineTask` 对带 pipeline 载体的节点任务设置，载体字段又只由 server 对 pipeline-node 任务下发（`validateClaimedPipelineCarrier`）。comment 触发的 strict source 任务没有载体，因此在现有代码里没有任何合法路径产生 consumption；`NewAdmissionDecider` 对 `StartArchitecture` 要求 source 当前 generation 的 consumption（`execution_admission.go` 的该判断带注释：source 任务可无自己的 CR id，由回执确立 CR 与 generation）。

**决定**：`prepareClaimedPipelineTask` 对「strict 且无 pipeline 载体」的任务新增 source 分支，其余分支不变：

1. **CR 身份**：只取现有绑定规则已有的来源与优先级——comment 声明的 `execution_context.cr_id`，否则任务自己的 CR 关联，否则 issue 上唯一的 CR 关联；声明与关联冲突沿用 `assertDeclarationMatchesAssociation` 拒绝。三者都没有、或 issue 有多个关联 → `EXECUTION_BINDING_UNAVAILABLE`，不启动 agent，不猜 CR。
2. **CR 根**：与该任务运行时的 `resolveTaskWorkspaceBinding` 同一结果（任务自己的 verified `local_directory` 内查找，`findPipelineCRRoot`）。预检与运行用同一个根，不得各自推导。
3. **本地范围，不写 `Pipeline*` 字段**：source 的 CR 号、CR 根只存在于 `prepareClaimedPipelineTask` 的局部值，传给安装授权、head 核对与 `consumeClaimedExecution`（把后者对 `task.PipelineCrID`/`PipelineWorkspace` 的读取改为接收参数）；不写入 `Task.Pipeline*`，否则 `settleCREventsForTask`、`taskCRWorkspaceRoot`、`localDirectoryAssignmentForTask`、`pipelineExecutionContextBlock`、`resolveTaskWorkspaceBinding` 等 pipeline 专用路径会把 source 当成节点。
4. **之后的链路与节点完全相同**：`OpenExecutionTrustStore`、`InstallExecutionAuthorization`、head 核对（initial、未撤销、lineage/grant digest/revision 一致）、`consumeClaimedExecution`、`claimOK` 的完整元组比对；任一步失败不启动 agent。
5. **不扩大节点语义**：source 不设 `ExecutionPreconsumed`、不注入 `CRCTL_EXECUTION_TRUST_ROOT`（SC-REC-008 的 (b)/legacy/source 不含该变量的结论不变）、不开 binding endpoint（`executionBindingEndpointForRun` 仍要求 `PipelineCrID`），run 结束不再消费（`recordDeliveredConsumption` 同样要求 `PipelineCrID`，本就不对 source 生效）。因此 source 的 consumption 恰在启动前产生一次，其 effect 的 request id 是 source 任务 id。
6. **不改的东西**：server 侧 claim、`StartArchitecture` admission、M005 一 generation 一回执、归档锚点合同；legacy（无 strict 声明）任务行为不变。

**为什么不选「source 不需要 consumption」**：那要同时放宽 `NewAdmissionDecider` 对来源任务的准入要求，是削弱安全不变量，且违反 Gate 1 的「真实来源」目标；修在 daemon 一侧只是让既有合同可被满足。

**未验证**：server 侧消费入口（`/binding` 签发与 `/consumption`）对无节点载体的 source 任务的校验是否全部成立，仅读码推断；由 TC-REC-004 的真实 A 与 A0 观察，若 server 拒绝即按止损点停下，不借手工 DB 修复。

#### D1.9 节点 authority 事实：tools 的 `workspace inspect --detail` 补两个字段（B2，2026-11-14 修订）

**事实**：`inspectPipelineAuthority` 对每个 pipeline 节点任务运行 `crctl workspace inspect <CR> --workspace <root> --detail`，要求 JSON 含 `targetSpecId`（或 kebab 名）非空，`targetVersion` 非空、非 `unassigned`、符合版本形态，否则分别为 `TARGET_SPEC_AUTHORITY_DRIFT`、`WRITEBACK_VERSION_UNASSIGNED`/`INVALID`（`pipeline_task.go`）。tools HEAD（即 `.github/aifirst-tools-pin` 钉住的 `e52b808`）该命令的输出键只有 `op,cr,mode,txId,resources,changed,operationalWorkspace,operationalWorkspaceError,freshness`；`git log -S` 证明 tools 历史上从未输出过这两个键；daemon 单测用的是手写 JSON，因此一直没有被发现。

**决定（用户 2026-11-14 选择）**：补在 tools，不改 daemon 的读法。daemon 侧不动代码，合同本来就是这两个键。tools 侧**并入已有的成对 tools change `2026-11-13-aifi-45-node-trust-root`**（用户 2026-11-14 裁定「并入」，AI 此前建议另开）：该 change 的 proposal/design/spec/test-plan 同步修订（新增 REQ-NTR-005、SC-NTR-009/010、TC-NTR-010/011），其 Gate 1/2 重审、已确认的 Gate 3 因此过期并在实现后以新的取证 run 重审；tools 与 multica 的 Gate 各自独立，互不代签。并入的依据：两处改动都未提交、都落在同一个 `crctl.mjs` 与同一个被冻结的 `skills/shared/crctl/scripts` 输入目录下，另开 change 既不能隔离证据，也省不掉旧 9 项的重跑，反而多出一套独立流程与分开提交的归属问题（对比见 ADJ-A0-1）。multica 对其的契约：

- `workspace inspect --detail` 成功输出新增 `targetSpecId`（字符串或 null）与 `targetVersion`（字符串或 null）：`targetSpecId` 来自既有 authority 裁决 `resolveTargetSpecMode`（仅 mode=new 时有值；legacy 或裁决失败为 null），`targetVersion` 来自既有 `readCrMdTargetVersion`（读不到为 null）。只复用已有读取器，只读，不新增裁决、错误码、flag；失败时给 null，由 daemon 沿用既有错误码失败关闭。
- 其余既有字段、类型与值不变，默认（非 detail）面不变；`crctl-detail` 金样本 `workspace-inspect.json` 的字段路径集合随之增补（`fieldPaths` 不计 null，夹具 CR 带 `target-version: 0.42`，故 `targetVersion` 路径必增；`targetSpecId` 视夹具而定）。该文件工作树内容与 HEAD 无差异（`git diff HEAD --quiet` 返回 0，`git status` 的 M 仅是 stat 差异），tools 侧可编辑，但每次编辑前须重新核实。
- 实现须为纯插入（不改既有行），以便 `scripts/aifi45-real-run/crctl-stage.mjs` 的「覆盖版只许对 HEAD 增行」检查继续成立；若 tools 需要改既有行，必须先修订该检查并重新评审，而不是绕过。
- 发布顺序先 tools 后 daemon 真实运行；本变更不探测 crctl 能力。daemon 对缺字段的 crctl 保持失败关闭。

**multica 侧**：真实运行 CR 工作区必须带有效的 `target-version`（形如 `v1.0.0`）与 `target-spec-id`（`cr-workspace.mjs` 当前写 `unassigned`，须改）；除此无生产代码改动。B2 没有 multica 侧单独的 TC：其保证由 tools 侧 TC-NTR-010/011（字段与金样本）与 TC-REC-004（节点真实推进过 authority 事实）承担。另外，补完且 daemon 重跑 A0 后，替身 writer 越过 `inspectPipelineAuthority` 即是无模型的首次端到端观察，不必等真实 run A。


#### D1.10 预消费用的信任根按 task generation 取子目录（B3，2026-11-14 修订）

**问题**（A0 重跑实测，读码核实，见 ADJ-A0-2）：本地 receipt 在信任根之内，键为 `<scopeHash>-<grant_id>-<stage>`（`lib/execution-authorization.mjs:436-440`）；`authorization-bind` 的 stage 固定（`crctl.mjs:2682`），challenge 每次随机（`lib/execution-binding.mjs:161`），同键再绑定即 `EXECUTION_CONSUMPTION_CONFLICT`（tools 测试断言为合同）。daemon 每个 workspace 只有一个信任根，所以 source 之后的节点、重新派发的 generation 预消费都会冲突。此前测试用假 crctl 或只跑 source，所以未暴露。

**决策**：

1. 每个任务预消费所用的信任根，是 workspace 信任根下的 generation 子目录：`<workspace 根>/<g>`，`g = hex(sha256(task_id|runtime_id|dispatched_at))` 的前 32 个字符（纯十六进制，Windows 路径安全）。`ExecutionTrustStore` 增加一个方法 `Generation(taskID, runtimeID, dispatchedAt)`，返回以该子目录为根的 store；`prepareClaimedPipelineTask` 在既有 `OpenExecutionTrustStore` 之后调用它，其后的授权安装、grant 事实读取、预消费的 `--trust-root`、`ExecutionTrustRoot` 注入都用返回的 store。`OpenExecutionTrustStore` 及其位置校验、既有调用方不改；子目录在已校验过的根内，不重复校验。
2. 不新增身份校验：三个标识在此之前已经过 `GetTaskExecutionClaim`（规范 UUID 与 claim 时间解析）和完整元组比对，空值到不了这里。
3. source 与节点任务同一入口。同一 generation 重复准备得到同一个根，本地 receipt 的同键冲突保护在该 generation 内保留。
4. **取舍**：本地 receipt 不再跨 generation 互斥。这层互斥正是 B3 本身，并与已批准的 SC-REC-001（每个 generation 各有一条 consumption）冲突；据读码，未发现受审保证依赖它，权威仍是平台 `UNIQUE(workspace, cr, runtime, task, dispatched_at)` 与服务端 binding proof。每个 generation 留下一个小目录（公钥、grant、sidecar、receipt），不回收；回收要判断 generation 是否仍在使用，另行设计。
5. 既有 TC-REC-009 子用例的期望值随之由 workspace 根改为该任务的 generation 根（断言意图不变：env 值即该任务 grant 所安装的根）。

**已排除**：tools 侧让 receipt 键带 challenge——改 tools 已断言为合同的「同阶段异 challenge 即冲突」并削弱本地重放保护，须 tools 独立 Gate；让 source 不占用该 stage——解决不了节点之间与重新派发的冲突。

**验证口径**：SC-REC-001 增一条 and，TC-REC-001 增一个子用例（不新增 TC/CP）：同 workspace 内不同 generation 的预消费用不同的信任根，传给 crctl 的 `--trust-root` 与发布给节点的根相同。真实 crctl 下「source 之后 writer 预消费成功」只能由 A0 重跑与真实 A（TC-REC-004）端到端观察；单测里的 crctl 是替身，不证明 tools 行为。

---

### 2. D2 真实闭环：一个命令型 CP，两次计划运行，第三次只作止损复跑

**方案**：新增一个自包含、失败即非零的真实运行驱动，复用 F8 的镜像/迁移/真实 daemon/pi CLI 和 disposable PG 的 setup-failure 释放逻辑，但不复用任何 fixture 签名或他仓资源。所有真实资源在 BUILD 前单独授权；脚本必须支持 `--model`，拒绝 Fable 及空模型，并在发起第一次模型请求前打印模型、计划 run 数、费用确认标识与资源归属。历史候选 `Gobao/deepseek-v4.1-flash` 仅列给用户参考，不预选（`知识库/projects/tools/archive/2026-11-08-aifi45-trust-anchor-chain/validation/e2-m2-real-loop-20261108b/run.sh:497-500`）。

| 运行 | 前置与真实步骤 | 机器可核对的成功判据 | 是否可复用 |
|---|---|---|---|
| **A：architecture 主链** | 新 CR 可由 fixture 建到 `requirement-approved` 并准备最小 PRD，避免默认需求模型成本；不得预置 execution grant 到 agent 工作区。真实认证 owner/admin 调授权路由，daemon 用真实 task token 安装 grant，独立 T 从原字节重提取 source 并核对；改一个来源字段而保留签名必须拒签。真实 source task 经 production 启动 architecture；writer 两次 advance 到 review-pending；reviewer 0 advance PASS；到人工门；在该边界重启 daemon/backend（`知识库/projects/multica/changes/2026-11-13-aifi-45-real-execution-closure/canonical/proposals/2026-11-13-aifi-45-real-execution-closure.yaml:166-170`）。 | source run/task/generation/receipt/effect 均非空；writer 和 reviewer 各有自己当前 generation 的一条 consumption 与自身 effect；writer 两个不同 advance proof 成功但只有一条平台 receipt；CR 为 `tech-design-review-pending`；重启不重复任务；CR 无 revoked 等待。独立查询 command/verdict/settlement 的 request id 必须等于各节点 task id。 | source tamper、双写、零写、人工门与重启可共用 A；撤销不能等到 A 到人工门后再做。 |
| **B：受控停止对照** | 新 CR 重复真实 source/授权/启动；在 writer 任务处于 running（以 DB 任务状态确认，不 sleep）时撤销当前 head；等 writer 任务结束，确认不推进 reviewer；停止并重启 backend/daemon，确认仍不推进。若撤销提交前该节点已 passed，本次记 INCONCLUSIVE 而非 PASS，不算止损证据。已落盘的 CR 更新和源证据保留（`multica/server/internal/governance/execution_authorization_revoke.go:291-342`）。 | 当前非 approve head 导致当前及后续派发/完成 `HEAD_REJECTED`；run 不被伪造成 completed/failed；无 reviewer 新任务；重启后 CR/run/task/head 一致；无自动修复或补签。 | B 自己包含一次重启对照，不能再复用已到人工门的 A 来证明“及时停下”。 |
| **第三次（预留，不默认执行）** | 仅当 A/B 因已定位的节点证据生产缺陷失败，修完同一生产者后定向复跑失败场景。不得用它顺便跑新功能或换模型。 | 同一失败 CP 转 PASS，且前面的 PASS 断言重跑；输出原失败与新结果的可关联 id。 | 第三次前重新取得用户同意，仍受 architecture run ≤3 总上限约束。 |
| **requirement 可选链** | 只有用户明确另选才新增；用于覆盖 register/PRD/push/review 的 0/1 advance 表。 | 每个实际执行节点均有自己当前 generation 回执/effect，并到对应人工门。 | 不能伪装成 architecture 的第三次止损复跑；需要独立模型次数/费用授权。 |

**命令与证据格式**：驱动按阶段输出单行、可 grep 的 `PASS real-run <check> run_id=<id> task_id=<id> generation=<id> effect_ref=<id> detail=<...>`；失败输出 `FAIL real-run stage=<stage> node=<label/id> task_id=<id> reason=<stable-code>` 并非零退出。至少包含 `source`、`source-tamper-rejected`、`writer-two-advances-one-receipt`、`review-zero-advance-own-effect`、`human-gate`、`restart-dedup`、`revoke-stop`、`restart-revoke-stop`、`cleanup`。每个 PASS 由脚本查询 DB/实际 CR 文件后打印，禁止仅凭进程退出码或人工日志判断；configured/requested/actual model、各 agent task id 和可取得的 usage 分开记录，缺失 actual/usage 就写 `UNCONFIRMED`，不推断（`知识库/projects/multica/changes/2026-11-13-aifi-45-real-execution-closure/canonical/proposals/2026-11-13-aifi-45-real-execution-closure.yaml:172-174`）。

**清理是所有路径的职责**：

- 驱动在创建第一项资源前安装 `EXIT/ERR/INT/TERM` 清理；容器、网络、镜像 tag、临时目录和数据库均以 nonce label + 完整 ID/路径登记，创建后立刻登记。只清理本 run 登记对象，不用名称模式 kill，不碰旧 `multica-*`。
- 一次性 PG 复用 `startInstance` 的 setup-failure `release`；backend/daemon 容器同样使用唯一归属与 `--rm`，驱动另有总 deadline。`--timeout` 只按 podman 的实际停止语义使用，不把它描述成自动到期销毁（`multica/scripts/aifi45-disposable/instance.mjs:33-49,121-138`）。
- 外层 supervisor 在 driver 超时/异常退出后执行同一清理并复查 label；清理函数幂等，单个对象不存在不掩盖后续对象。secret 不写日志。正常、setup 失败、阶段失败、超时、进程被终止都走清理；无法处理的 SIGKILL 由外层 deadline/归属复查兜底。
- 在第一次真实模型前，以 dummy backend/daemon 资源各做一次“setup 中途失败”和“运行中超时”的 cleanup smoke；输出 `remaining=0` 才允许继续。这两项需要 podman 授权，但不需要模型。

**为什么**：A 能以一次 architecture run 同时证明最关键的双写、零写和重启；撤销有严格时间窗，若不在 B 单独构造就会退化成“最终也停了”的弱证据。统一 CP 和资源归属可防止 F12 的人工 manual-pass 及经验中的容器泄漏。

**备选方案及排除原因**：三次全部默认运行会在首错后浪费模型费用，排除；把撤销塞进 A 人工门后不能证明不派发下一节点，排除；只做真实 model、不做 cleanup 故障注入会保留 setup/timeout 泄漏风险，排除；只做 unit/httptest 不满足 Q3/Q5，排除。

---

### 3. D3 撤销后推进与重启：保留授权拒绝态，不制造 run 终态

**方案**：不改 `RevokeExecutionAuthorization` 的 append + CAS，不给 pipeline_run 增加 revoked/failed 状态，不删既有 CR 更新、approval_record、task、binding/consumption 或 effect。下一次 claim、节点完成和 `ResumeActiveRuns` 都继续进入同一 `executionAdmissionGate.Decide`；当前 head 非 approve 即 `HEAD_REJECTED`，等待来源只展示 revoked，不触发 admission、补偿写或重新签名（`multica/server/internal/governance/execution_admission.go:153-156`；`multica/server/internal/governance/execution_admission_gate.go:187-215`）。

真实撤销点取 writer 任务处于 running 时（DB 确认，不靠 sleep）。断言只依赖「撤销已提交后节点完成与下一节点派发都被 `HEAD_REJECTED` 拒绝」，与 agent 当时进行到哪一步无关；若撤销提交前该节点已 passed，驱动输出 INCONCLUSIVE 并非零退出，不得记为 PASS。这样不需要拦截 daemon 终末 callback 的测试代理，也不增加任何生产分支。

补一个经真实路由和 production 恢复入口的集成场景：source bind → StartArchitecture → 当前 writer task 有自己的 receipt/effect → revoke → task completion 拒绝 → reviewer 不派发 → 调 `ResumeActiveRuns`/实际进程重启 → 仍拒绝且历史行不变。现有测试主要覆盖 httptest 直调与 admission 分量，不能替代这个端到端场景（`multica/server/internal/governance/execution_authorization_revoke_transaction_test.go:87-150`；`multica/server/internal/daemon/execution_control_recovery_d8_test.go:20-24`）。

**为什么**：当前状态机已经把撤销建模成不可再次准入的授权头，安全停止不需要新终态；增加 run 终态或自动 cancel/repair 会把 M008 非目标重新带入。真实 B 只验证并闭合既有保证，若发现主链 bug，先证明最小生产路径缺哪个既有 gate，再停下报告，不顺手扩大撤销语义。

**备选方案及排除原因**：撤销时直接把 run 标 failed/cancelled 会丢失“授权拒绝”与“run 执行终态”的区别，且 proposal 明确不做 code run/自动恢复，排除；强杀当前 agent 只能停进程，不能保证重启后不派发，排除；把撤销改成普通人工 approve/advance 会绕过 F3 的门控差异并伪造审批，排除。

---

### 4. D4 删除 workspace 后 command/reservation 并发：共用 workspace 行锁

**方案（A，G2-2 已确认；写入侧锁模式于 BUILD 修订为 `FOR KEY SHARE`，见下方「锁模式」）**：

1. 给 `ControlCommandInput` 增加必填 `WorkspaceID`，它是 daemon 认证上下文解析出的**可信调用输入**，不是签名字段；不改命令签名/schema。生产调用由 `HandleDaemonExecutionConsumption` 传入已认证的 workspace id，不能从 `ReservationID` 反推 selection：该值在生产路径就是 receipt id，而 effect lineage 是无 selection 的（`multica/server/internal/governance/execution_consumption_effect.go:58-59,66-78`）。
2. 在 `ApplyControlCommandTx` 的任一 cursor/verdict/settlement 写入前，执行 `SELECT id FROM workspace WHERE id=$1 FOR KEY SHARE`，无行返回 `ErrReservationWorkspaceGone`（或同属现有 no-row 语义的固定错误），随后仍做原 attestation、lineage、stage、actor、cursor、settlement 校验。guard 持锁至事务提交；它不是 DB FK，也不改变历史证据保留。
3. 在生产 handler 最早识别出 workspace 后、claim/head lock 之前取得同一 `FOR KEY SHARE`，使全局锁序固定为 **workspace → claim → head → lineage → cursor**。`issueConsumptionEffectTx` 已在 head 之后预锁 lineage，若只在 Apply 内补锁会形成 head→workspace 反序；共同前置 guard 是为避免这个死锁窗口，不是重复兜底（`multica/server/internal/governance/execution_consumption_effect.go:69-105`）。同事务重复 `FOR KEY SHARE` 可保持 Apply 的独立调用安全。
4. `CreateReservationTx` 用同一 `FOR KEY SHARE` 替换无锁 `SELECT EXISTS`，且必须先锁 workspace，再重读 selection，再插入；不要在锁前把 selection 的旧读结果用于准入（2026-11-14 勘误：原文还写「/current head」；`ReservationRequest` 不携带 head、reservation 行不依赖 head、`CreateReservationTx` 无生产调用方，故不实现 head 重读，见 ADJ-C1-1 MINOR-2）。只有当前 reservation 是 receipt 的生产 command 才走第 1 条的显式 workspace；对确有真实 selection 的 reservation 调用，调用方同时核对其 workspace 一致性，不伪造 selection（`multica/server/internal/governance/execution_control_reservation.go:73-106`）。
5. workspace 删除继续先 `FOR UPDATE`，保留 notice/dispatch-root 清理及执行证据保留现状，不新增 cascade、外键、收敛转移、后台迁移或“删除后补写一条终止 command”（`multica/server/internal/handler/workspace.go:1076-1160`；`multica/server/internal/governance/workspace_delete_execution.go:22-90`）。

**并发正确性**：写入侧的 guard 都是 `FOR KEY SHARE`，彼此兼容；与删除的 `FOR UPDATE` 互斥。READ COMMITTED 下，若 writer 先取得 KEY SHARE，删除等 writer 提交，之后没有删除后的新写；若删除先取得 EXCLUSIVE/UPDATE，writer 等待，删除提交后其锁定查询返回 no row 并回滚。锁必须在 selection/head 重读和所有写入之前取得，不能靠 `time.Now`、创建时间、transaction id 或事务外检查判断归属。

**锁模式（BUILD 修订，ADJ-S7-1）**：写入侧用 `FOR KEY SHARE` 而不是 `FOR SHARE`。两者与删除的 `FOR UPDATE` 都互斥，删除与写入的互斥保证相同；区别在普通 UPDATE：`UPDATE workspace SET issue_counter = …` 取 `FOR NO KEY UPDATE`，与 `FOR SHARE` 冲突、与 `FOR KEY SHARE` 不冲突。用 `FOR SHARE` 会让每次授权节点消费期间，该 workspace 的创建 issue 被阻塞到消费事务结束。聊天会话创建对同一把删除锁已经用 `FOR KEY SHARE`（`multica/server/pkg/db/queries/workspace.sql:82`）。BUILD 中已用变异验证：改成 `FOR SHARE` 后 `governance-wsd-lock` 变红。

**33 处测试的处理**：本次只读枚举与 F11 一致，为 33 个测试直调 + 1 个生产直调。把 workspace fixture 收进现有 command/attestation 测试 helper：需要成功的用例创建并使用真实 workspace id；已用真实 workspace 的 3 类用例直接传 id；缺 workspace 的用例保留一个明确 `ErrReservationWorkspaceGone` 红测。不得给 30 个原 opaque fixture 随机填新 UUID 来绕过 guard，也不得删除原 successful/gated 分叉断言。生产唯一调用点单独传 authenticated workspace，不能靠测试默认值。

**不依赖 sleep 的并发探针**（BUILD 修订，ADJ-S7-2/3；不引入任何生产 hook）：

- 暂停点用生产自己的行锁，不加测试 hook：交错二把真实 `DeleteWorkspace` 暂停在它自己的 sweep（此时它已持有 workspace 锁）——另一事务先对该 workspace 的 `cr_execution_notice` 行 `FOR UPDATE`，删除删到该行即阻塞；测试用 `FOR KEY SHARE NOWAIT` 探针断言删除确实持有 workspace 锁（前提断言，不成立则整例失败）。
- 交错一：writer 事务（reservation 与 command 各一组）取得 workspace 锁并写入 → 真实 `DeleteWorkspace` 请求 `FOR UPDATE` → 经 `pg_blocking_pids`/`pg_stat_activity` 在 deadline 内确认删除被该 writer 阻塞 → writer 提交 → 删除成功。断言写入先于删除完成且恰好一份。
- 交错二：删除暂停并持有 workspace 锁 → writer 请求锁 → 经 `pg_blocking_pids` 确认 writer 被删除阻塞 → 释放暂停，删除提交 → writer 以 `ErrReservationWorkspaceGone` 失败回滚；该 writer 本次创建的行数为 0，且 A 的 19 张执行表与删除前对照一致（仅 delete 类行消失）。
- 先后顺序由 DB 观察到的锁等待决定，不由固定 `Sleep` 决定；轮询只用于观察锁状态，每一步有 8 秒 deadline，超时即测试失败。重复 reservation 的既有幂等由既有用例覆盖（`TestChannelFoundationReservation` 的固定 id 冲突与回滚、selection 重验证等子测试），本变更未改它们。
- 消费入口的锁序与锁模式单独由 `governance-wsd-lock`（TC-WSD-007）验证：在生产 handler 已证明 claim、将要写入的时点，用独立连接断言 workspace 行的 `FOR UPDATE` 被阻塞、普通 `UPDATE` 不被阻塞。只测 store 函数挡不住 handler 里的取锁被删掉或移到 claim 之后。

**为什么**：A 把保证放在所有 command 写入共同入口，现有 `TestWorkspaceDeletionRefusesNewCommand` 的成功/拒绝断言可原样保留；R5 所指的旧入口缺口也被补齐。虽然需要迁移 33 个 fixture，但这是显式编译/测试成本，换来生产与测试不分成两种合同。

**备选方案及排除原因**：

- **B：只在 `issueConsumptionEffectTx`/生产 handler 做 guard**，不改 `ApplyControlCommandTx` 输入。生产 C5 同样可闭合，33 处 fixture 不动；但旧探针必须改成经 production consumption 路由或命名/断言修订为“生产路径不再重建”，不能直接声称所有 Apply 直调都安全。只有用户明确接受该断言对象修订才可选；旧红灯在转换前不得变绿。
- 只在 reservation 中保留 `EXISTS`、插入后再次查询 workspace：若删除在第二次查询后提交，仍可能留下删除后的写，排除。
- 用独立 advisory lock 而删除不共同持有：无法与现有 `FOR UPDATE` 形成互斥，排除；把 workspace guard 放成事务后清理或后台补偿，不满足“删除后终态安全”，排除。
- 静默把旧红灯标成 expected-risk/known-finding：延续 R5 的假绿，排除；修复后应把当前 ownership 中的排除改为普通 CI 回归，归档 R5 原文不动（`multica/scripts/aifi45-disposable/test-ownership.json:54-65`）。

---

### 5. D5 实施切片与止损：先证明真实生产者，再处理独立删除窗口

**方案**：

| 切片 | 内容与进入条件 | 验证 | 授权/停止条件 |
|---|---|---|---|
| **S0：Gate 2 设计裁定** | 选 D1、D4、运行次数、模型和可选 requirement；确认是否需 tools 成对 change。 | 只读设计评审；没有运行证据就不写 PASS。 | 未裁定不进入 BUILD。 |
| **S1：节点生产者与无模型组件探针** | 若选 B：claim marker、preflight、skip run-end duplicate、authorized-node 上限 2、legacy 不变；授权节点的 agent 环境注入 `CRCTL_EXECUTION_TRUST_ROOT`（D1.7，依赖成对 tools change），须在真实 A 之前完成；若选 A/C 必须先有 tools change 和对应 Gate。 | 0/1/2/3 challenge、same-byte replay、third 409、writer 两跳到 review-pending、review PASS 零写、每 generation 一条 receipt/effect、legacy/unknown marker、信任根注入的两类环境（TC-REC-009）。 | 普通无外部资源测试可在既有授权内做；任何真实 DB/podman/model 另授权。失败只修同一生产者。 |
| **S2：harness 与真实 A** | 先写统一驱动，做 setup/timeout cleanup smoke，再运行 A。source 授权和 T tamper 不用 fixture 签名。 | 所有 A 的 PASS CP + `remaining=0`；独立 DB 查询核对 task/generation/effect。 | podman、自建 PG、backend/daemon、真实模型逐项授权；首次真实失败即停，不修 D3/D4、不继续真实链。 |
| **S3：撤销与真实 B** | 仅在 A 全绿后，补真实路由/ResumeActiveRuns 集成场景并跑 B；需要时仅修被证明缺失的既有 gate。 | revoke 后无推进、无 reviewer 新任务、重启保持、历史不变、清理为零。 | 第二次真实 run 已包含在模型/费用确认中；若超预算或需新语义，停下。 |
| **S4：D4 workspace 并发** | 仅在真实链成功后实施 A 或经批准的 B；迁移 fixture、共同锁、无 sleep 探针。 | 旧成功探针仍成功；删除后无新 command/cursor/verdict/settlement/reservation；两种交错、重复 reservation 和 legacy 回归。 | 自建一次性 PG 单独授权；不触碰旧库。 |
| **S5：收尾验证** | 跑受影响 selections 与完整组；将已修复旧红灯转为普通回归；核对 multica CUSTOM 登记。 | `scripts/aifi45-disposable/run-selection.mjs` 机器输出、工作树 diff、CP/资源释放记录一致（`multica/scripts/aifi45-disposable/run-selection.mjs:1-15,110-180`）。 | podman/一次性 DB 再授权；提交、推送、部署均不在长程预授权内。 |
| **S10：D1.8 source 路径（2026-11-14 增补）** | daemon 对 strict 无载体的 source 任务新增预检与预消费分支，范围为局部值，不写 `Pipeline*`；TC-REC-010。 | 单测四象限 + 与节点同链路的失败关闭；A0 替身运行复核；不改 server。 | 在 S1–S3、S9 之后、真实 A 之前。 |
| **S11：D1.9 tools 成对 change（2026-11-14 增补）** | 并入 tools 的 `node-trust-root`（其 Gate 1/2/3 重审），`workspace inspect --detail` 补两字段；multica 侧 CR 工作区夹具改用有效 target-version。 | tools 侧测试与金样本；A0 越过 authority 事实；真实 A 观察。 | 🔒 tools 修改须独立 Gate；先于 daemon 真实运行。 |
| **S12：D1.10 预消费信任根按 generation 取子目录（2026-11-14 增补）** | `ExecutionTrustStore.Generation`；`prepareClaimedPipelineTask` 改用；TC-REC-001 增子用例，TC-REC-009 期望值随之更新。 | daemon 单测；A0 重跑 source→writer 均预消费成功；不改 tools、不改 server。 | 在 S3、S9、S10 之后、真实 A 之前。 |

止损顺序固定为 **S1 → A → B/D3 → D4 → 完整回归**。第一次真实运行若因证据生产失败，只能修 S1 的生产链并记录失败 CP；不得借 D4 改动、模型重试或手工 DB 修复把链路“推绿”。第三次 architecture run 只能定向复跑该失败，且在第三次前重新问用户。若失败是模型/凭据/资源不可用，不改业务代码，记录 `UNCONFIRMED/BLOCKED` 并请求资源或模型裁定。

**为什么**：节点证据是主线，撤销依赖它，D4 则可用独立 DB 场景闭合。先跑 A 能以最贵资源尽早验证最大不确定性，同时把后续真实费用绑定到已有成功证据。

**备选方案及排除原因**：先把 33 个 D4 fixture 全部修完再跑真实链，会让主要阻塞未验证就消耗大量工作，排除；A/B/D4 并行会违反首错止损并混合失败原因，排除；一次性预授权三次模型和所有资源会绕过费用/归属边界，排除。

---

## 模型分层记录（STDD model-dispatch）

| 工作 | 档位 | configured（`stdd config models --format json`，2026-11-13） | requested | actual |
|---|---|---|---|---|
| 本文 design 撰写（planner 子代理） | strong（`model_tiers.design`） | `GB-JP/kimi-k3.1-pro`，effort `max` | `GB-JP/kimi-k3.1-pro:max`（Agent 的 model 参数） | unknown（子代理会话未回传运行元数据） |
| 事实核对（只读 explore 子代理 E1/E2/E3 及追问） | balanced（`model_tiers.assist`，按用户同意委派简单任务） | `GB-JP/deepseek-flash`，effort `max` | `GB-JP/deepseek-flash:max` | unknown |
| specs、agent spec、test-plan、Step 5.5 机械审查、本节 | 主会话（不属于任何档位） | — | — | 由用户选定的主会话模型，未回传 |

主会话本身不是 strong 映射，planner 跳过条件 ①②均不满足，故按规则派发了 strong 档 planner。设计中「撤销点」一节由主会话在 planner 输出基础上修订（去掉需拦截 daemon 终末回调的测试代理，改为 DB 确认 writer 运行中撤销，不满足则 INCONCLUSIVE）。

## 接口锚定（L2）

proposal 的风险评估标了 cross_system，按 STDD Step 4.5 至少需要 L2（精确的接口契约）。以下是 D1-B + D4-A（G2-1/G2-2 已确认）的接口契约；实现不得偏离，偏离须走 design-adjustment。

| 接口 | 契约 |
|---|---|
| pipeline claim 响应的合同字段 `PipelineExecutionContract`（string） | 取值只有 `""`（legacy）与 `"authorized-execution/v1"`。server 仅按数据库推导：该 workspace/CR 存在初始 `stage=execution, decision=approve` 的 approval_record 则为后者，否则为空；撤销后初始记录仍在，所以不降级。daemon 遇到其他非空值拒绝启动 agent（任务失败闭合）。 |
| daemon 的节点预消费 | 仅当合同字段为 `authorized-execution/v1`：agent 启动前调用既有 `consumeClaimedExecution`，返回非空且已持久化的当前 generation 回执后才标记「已预消费」（内存标记，不持久化）并启动 agent；失败不启动 agent。已预消费的任务在 run 结束时跳过 `recordDeliveredConsumption`。 |
| 单 run binding endpoint 的 challenge 上限 | source、legacy、未预消费节点：1。authorized 且已预消费的节点：2 个不同 challenge。相同字节重放：幂等成功。第 N+1 个不同 challenge：HTTP 409。每个 challenge 单独完整校验；接受 proof 不触发 consumption。 |
| `governance.ControlCommandInput` | 新增必填字段 `WorkspaceID`（uuid，来自 daemon 认证上下文，不进签名载荷、不改 schema）。`ApplyControlCommandTx` 在任何 cursor/verdict/settlement/command 写入之前执行 `SELECT id FROM workspace WHERE id=$1 FOR KEY SHARE`；无行返回固定错误 `ErrReservationWorkspaceGone`，随后才做既有校验。 |
| `CreateReservationTx` | 以同一 `FOR KEY SHARE` 取代无锁 `SELECT EXISTS`，先锁 workspace、再重读 selection/head、再插入。 |
| 全局锁序 | workspace → claim → head → lineage → cursor。生产 handler 在 claim/head 加锁前先取 workspace `FOR KEY SHARE`。 |
| agent 子进程环境变量 `CRCTL_EXECUTION_TRUST_ROOT` | 仅当任务已绑定且 `ExecutionPreconsumed` 时，在 `injectTaskCRWorkspaceEnv` 内（custom_env 之后调用）与 `CRCTL_OPERATIONAL_WORKSPACE` 同条件发布，值为该任务 grant 所安装的信任库根（daemon 自己调用 crctl 时的 `--trust-root` 实参，即 `store.Root`）；其余任务一律先 `delete` 后不发布（含 custom_env 带入的同名变量）。不写 daemon 进程环境。`Task.ExecutionTrustRoot`（`json:"-"`，不进 wire）与 `ExecutionPreconsumed` 在 `prepareClaimedPipelineTask` 预消费成功处同时设置。 |
| 真实运行驱动 CLI | `node scripts/aifi45-real-run/run.mjs --scenario <architecture-main\|architecture-revoke\|cleanup-smoke> [--config <path>]`。`--config` 缺失或其中 `model` 为空/Fable、`max_runs` 缺失或超出上限时，在创建任何资源前拒绝并非零退出。 |
| 驱动输出（每行一条，可 grep） | 成功：`PASS real-run <check> k=v ...`，末行 `PASS real-run cleanup remaining=0`；失败：`FAIL real-run stage=<s> node=<n> task_id=<id> reason=<code>` 并非零退出；无法判定：`INCONCLUSIVE real-run stage=<s> reason=<code>` 并非零退出。 |
| `run-config.json`（不入库） | `{"model": "<provider/model>", "max_runs": <int, 本 change 总上限 3>, "cost_ack": "<用户确认费用与次数的原文>"}`。 |

## Architecture

以下是推荐的 D1-B + D4-A 数据流，均以 Gate 2 批准为前提。

### 1. 节点证据、advance 与恢复

```text
真实 owner/admin POST authorization
  → approval_record(execution approve) + head
  → source strict preflight → consumption + source effect
  → StartArchitecture / StartRequirement → source 准入 → 当前节点任务

节点 claim（DB 权威）
  → 初始 execution approval 存在？
       否：legacy 原路径，endpoint 仍单 proof
       是：PipelineExecutionContract=authorized-execution/v1
            → daemon trust/grant 校验 + authorization-bind private relay
            → 当前 task/generation/head 的唯一 consumption + 自身 effect
            → ExecutionPreconsumed=true，ExecutionTrustRoot=store.Root
            → 启动 agent（环境仅此类任务注入 CRCTL_EXECUTION_TRUST_ROOT=store.Root）
                 0 次业务 advance：直接用 preflight receipt 完成
                 1/2 次 advance：各自新 challenge，只签发，不重复 consumption
                 第 3 个不同 challenge：409，fail-closed
            → markNode：当前 task/generation/head receipt + 自身 effect
            → 下一节点 / human_approval
```

`ResumeActiveRuns` 仍只扫描 architecture/requirement，run 唯一键、活动任务部分唯一索引和 claim generation 继续负责去重；不为本设计新增恢复任务类型（`multica/server/internal/daemon/daemon.go:1825-1829`）。人工门不是 agent 任务，不能为了对齐证据模型而创建伪任务。

### 2. 撤销与重启

```text
writer 任务 running（DB 确认）
  → revoke：CR 行锁 + append reject + head CAS
  → markNode / 下一次 discovery / ResumeActiveRuns
       → Decide：HEAD_REJECTED
       → 不推进、不派发 reviewer、不补签、不改 run 终态
  → backend/daemon 重启 → 同一 Decide，历史记录保持
```

### 3. 删除 workspace 的锁边界

```text
command/reservation writer              workspace 删除
  SELECT workspace FOR KEY SHARE           SELECT workspace FOR UPDATE
  → 重读 selection/head（reservation）      → 清 notice/dispatch-root
  → claim/head/lineage/cursor（command）    → DELETE workspace
  → 写 command/verdict/settlement            → 保留执行证据
  → COMMIT 后释放                            → COMMIT 后释放
```

KEY SHARE 先到则删除等待；UPDATE 先到则 writer 等待并在删除提交后得到 no row。生产 handler 的最前 guard 保证不会再出现 head→workspace 的反序。没有跨仓共享锁、后台收敛、历史删除或 FK 依赖。

---

## Risks

| 风险 | 影响 | 设计控制 |
|---|---|---|
| SC-AUTH-007 的单 proof 上限被误认为可静默放宽 | 破坏归档验收语义 | B 明示仅 authorized+preflight 节点为 2，同字节重放例外，第三个仍 409；Gate 2 不批准就停止 B。签名 schema、签发主体和 256 上限不变（`multica/server/internal/governance/execution_binding_issue.go:37-41`）。 |
| authorized/legacy marker 误判 | 合法 legacy 被阻断，或授权节点漏掉 preflight | marker 由 DB 初始 approval_record 推导；unknown 非空值拒绝；current head 缺失/撤销不能降级 legacy。legacy 原样用例必须保留。 |
| preflight 成功后 run-end 又消费 | 同 generation 冲突或重复 effect | 只有收到已持久化非空 receipt 才设置内存标记并跳过；红测核对每 generation 一条 receipt/effect。 |
| agent 看不到 daemon trust root 中的 grant/source | preflight 成功但 advance 仍无可用授权材料 | 已由成对 tools change（变量 `CRCTL_EXECUTION_TRUST_ROOT`）与 D1.7 的 daemon 注入承接；真实 A 不得预置 `.crctl` grant。注入后仍读不到（agent 与 daemon 不同 OS 用户、provider 沙箱限制）时 crctl 失败关闭，按止损点停在 S1 的生产链，不暗中改 tools、不回退 `.crctl`。 |
| 信任根变量泄漏到非授权任务，或被 custom_env 覆盖 | legacy/source 任务行为改变，或 agent 配置改写信任根 | 只对 `ExecutionPreconsumed` 任务在 custom_env 之后发布，其余先 delete；TC-REC-009 断言注入、不注入、custom_env 覆盖三种情形，并断言 daemon 进程环境未被写入。宿主进程环境中由运维者导出的同名变量不在本保证内（子进程环境为 `os.Environ()` 叠加 agentEnv，daemon 不清洗宿主变量）。 |
| source 路径误写 `Pipeline*` 字段或放大节点语义 | pipeline 专用路径（CR 事件收集、绑定、prompt）把 source 当节点；或 source 获得信任根变量/endpoint | 范围仅为局部值；TC-REC-010 断言 `Task.Pipeline*`、`ExecutionPreconsumed`、`ExecutionTrustRoot` 在 source 后保持空，且 `executionBindingEndpointForRun` 仍为 nil。 |
| tools inspect 补字段破坏既有 detail 合同或金样本 | 其他 crctl 消费者读到新键、金样本比对红 | 只增字段、既有键不变；金样本路径集合同步增补；纯插入使 crctl-stage 检查继续有效。 |
| server 对 source 的 binding/consumption 校验仍有未知拒绝 | 修了 daemon 仍不产生 source consumption | 按止损点停下，只修节点证据生产者链路，不借手工 DB 或放宽 admission 推绿。 |
| 共享信任根下本地 receipt 同键冲突（B3） | source 之后的节点或重新派发的 generation 预消费失败 | D1.10 按 generation 取子目录；TC-REC-001 子用例断言根不同且传给 crctl 的根一致；真实 crctl 下是否成立由 A0 重跑与真实 A 观察（单测里的 crctl 是替身）。代价：每个 generation 留一个不回收的小目录，且本地 receipt 不再跨 generation 互斥（非受审保证的依据，权威在平台唯一键）。 |
| tools 与 daemon 版本错位 | 旧 crctl 不认变量，授权节点 advance 失败关闭、节点不推进 | 发布顺序先 tools 后 daemon；daemon 对授权节点无条件注入，不探测 crctl 能力、不加握手；错位表现为「无回执不推进」，由真实 A 的首次失败暴露，不会越权。 |
| 变量在场时 `register`/`archive` 也进入 control admission | 授权节点内原本按 legacy 能跑的 register/archive 调用失败 | tools 设计已接受且不开 env 旁路；architecture 节点按节点表不调用二者；requirement 节点（含 requirement-register）是否受影响未核对，本变更不声称覆盖 requirement（G2-4）。 |
| endpoint 第 2 次 proof 被误当第 2 次 consumption | 双写仍失败或重复 effect | proof 签发与 consumption 分离；组件和真实 A 同时核对“两次 advance、一条 receipt”。 |
| 真实模型不确定性、次数和费用失控 | 超预算或结果不可复现 | 计划 A/B，两次后才可能申请第三次；模型、费用和可选 requirement 分开确认；agent 不自动重试新 run；记录 actual/usage，未知不猜。 |
| setup/timeout/进程死亡留下容器或库 | 影响他仓资源、泄漏凭据 | 资源创建前 trap、nonce+完整 ID、外层 deadline、清理 smoke、最终 `remaining=0`；不按通用名称清理。 |
| 撤销测试撤销点落在节点已 passed 之后 | 误把“已推进”当作“撤销后推进” | 撤销前以 DB 确认 writer 仍 running；否则记 INCONCLUSIVE；断言查询无新任务并做实际重启。 |
| workspace/head/lineage 锁序反置 | 并发死锁，反而阻断正常消费 | 生产 handler 在 claim/head 前取 KEY SHARE；统一 workspace→claim→head→lineage→cursor；两种锁序探针带 deadline。 |
| D4 为省事改测试断言或随机填 workspace | 旧红灯被掩盖，C5 假闭合 | A 保留旧探针；33 个 fixture 建真实归属；若选 B，Gate 2 必须明确修订探针对象。 |
| 测试设施混入生产路径 | 新运行时复杂度/绕过风险 | 探针不引入生产 hook：用另一事务对删除自己 sweep 的行加锁来暂停真实 `DeleteWorkspace`，`pg_blocking_pids` 确认等待；`governance-wsd-lock` 只用既有的 `ExecutionConsumptionValidationTestHook`；生产不读取环境变量开关。 |
| 真实 A 成功后顺手做 M008/code run/历史回填 | 超 Gate 1 范围 | D3 只验证现有 HEAD_REJECTED；D4 只 guard 新写；非目标发现另开记录。 |
| 当前环境不能复现 F8 | 历史 harness 可存在但当前 podman/model/工具版本不可用 | F8 只作实现先例；先 cleanup smoke 和版本/归属检查，失败记 BLOCKED，不宣称真实闭环。 |

## Trade-offs

1. **D1-B 用一个小而明确的 endpoint 基数修订，换掉跨仓状态机/准入大改**。代价是 SC-AUTH-007 必须重新裁定，且要解释“最多两个业务 proof”不等于“两条平台 receipt”。上限 2 是当前节点实际需求，不为未来无限扩展。
2. **不为零写节点伪造一次业务 advance**。这使 writer/reviewer/human/approve 保持各自业务语义，但要求 daemon preflight 成为共同生产者；新增 marker 是为保护 legacy，现有 trigger comment 无法识别节点。
3. **真实撤销必须多用一次 architecture run**。A 到人工门后已无法证明 writer→reviewer 的撤销窗口；用 B 换取强证据，比在同一 run 事后撤销更符合 Q5，第三次仍只预留。
4. **D4-A 用 33 个测试 fixture 的修改换共同入口保证**。D4-B 代码更少，但必须修订旧探针的断言对象；推荐不让测试便利性决定安全边界。
5. **共享行锁而不是 FK/cascade/后台补偿**。它只阻止删除后的新写，保留历史证据与现有删除清理；代价是生产锁序必须前置固定。
6. **机器 CP 比人工确认更严格**。某些真实模型 usage 或外部行为可能只能标 UNCONFIRMED；本变更宁可留下明确未验证项，也不把会话观察写成 PASS（`知识库/projects/multica/archive/2026-11-12-fork-ci-test-evidence-trust/design-adjustments.md:497-506`）。

## 已回答的事实

1. **H1 静态上已有具体反例**：architecture PASS reviewer 没有 advance，但仍以节点任务完成；按已归档当前任务锚，它没有自身 consumption/effect，不能借 source 回执完成。human 门没有 agent 任务，不应纳入“每 agent 节点出证”的反例（`tools/skills/develop/review-tech-design/SKILL.md:150-154`；`multica/server/internal/governance/runner.go:870-895`）。
2. **H2 静态上已有具体反例**：writer 首次两个合法 advance，第二次使用不同 challenge；当前 endpoint 第二个不同 challenge 为 409，crctl 在该处停止，因此第二次 CR 更新不写，CR 停在第一次后的 `tech-designing`。这是读码结论，尚未用真实 daemon+agent 复现（`tools/skills/develop/write-tech-design/SKILL.md:50-52,139-141`；`multica/server/internal/daemon/execution_binding_endpoint.go:126-139`）。
3. **F5/F6 可组合但不能原样拼接**：F6 已能生产当前任务回执，F5 已要求该回执；缺口是 authorized 节点识别、agent 前调用、run-end 去重以及双 advance 基数，而不是新建账本。
4. **D4 根因和调用面已静态定位**：生产 command 有 authenticated workspace 但没有 guard，reservation 有无锁 EXISTS；33 个测试直调与 1 个生产直调的枚举和输入一致（`multica/server/internal/governance/execution_consumption_effect.go:155`；`multica/server/internal/governance/execution_control_reservation.go:73-106`）。
5. **F9 的恢复范围已核对**：只有 architecture/requirement；没有 code run 周期发现。`ReconcileCode` 的引用只读检索只见定义，未见生产调用，但这不替代完整调用图验证（`multica/server/internal/governance/runner_code.go:28`；`multica/server/internal/daemon/daemon.go:1825-1829`）。
6. **本设计阶段没有产生运行 PASS**：所有“会拒绝/会 409/会停住”均为静态推导；真实证据只能在授权后的 CP 产生。

## 仍未验证的事实 / 更正

### 仍未验证

1. authorized 节点 marker、preflight、skip run-end、第二个 advance、零写 PASS reviewer 的完整闭环均未运行；尤其节点 agent 的 crctl 能否读到注入的信任根（agent 与 daemon 是否同一 OS 用户、provider 沙箱是否允许读 daemon 信任库）尚未验证；BUILD 前的静态结论是 crctl 只认 `--trust-root`、节点 skill 的 advance 不带该 flag，该结论现由成对 tools change 的变量通道与 D1.7 的 daemon 注入承接，二者均未经真实节点运行验证（`tools/skills/shared/crctl/scripts/crctl.mjs:1044-1055,1439-1453`）。
2. preflight 崩溃/重领时是否总获得新 `dispatched_at` generation，或可能在同 generation 用新 challenge 重取证，未做故障注入；若同 generation 重试会撞既有 changed=false 条件，必须作为生产者缺陷停下，不得自动补签（`multica/server/internal/governance/execution_consumption.go:197-242`）。
3. 真实 source 原字节 T 重提取、改一个来源字段拒签、重启去重和 revoke 后真实路由/ResumeActiveRuns 仍未在本变更执行；F8 只证明历史环境。
4. D4 的两种 READ COMMITTED 锁交错与 33 处 fixture 迁移已在 S7 于一次性 PG 运行并做了变异检查（探针不使用 hook，见 ADJ-S7-2）；完整 selections 全组回归（S8）尚未运行。
5. 当前 podman、镜像、PG17、pi CLI、所选模型凭据、actual model 与 usage 均未验证；模型名称和费用不能由历史 F8 代替用户选择。
6. requirement 真实 run 默认不做，因此其节点表是静态处理设计，不宣称已真实闭环。
7. 既有 `wait_reason=admission` 残留是否误导操作、完整 workspace 删除后所有非目标执行行如何展示，均不在本变更修复范围；不借本变更顺手清理。
8. D1.8：server 消费入口与 `/binding` 签发对无节点载体 source 任务的校验：A0 重跑已观察到 source 任务 consumption=1、effect=1（零模型替身，不是 TC-REC-004 证据）；真实模型下是否同样成立待真实 A。
9. D1.9：A0 重跑已观察到 writer 节点越过 authority 事实；其余 crctl 消费者与全量套件是否受影响，由 tools 成对 change 的最终取证验证。

### 对输入/代码表述的更正

1. **F6 的注释过时点不止 `daemon.go:765-768`**：`execution_consumption_client.go:11-18,55-57` 也仍写“生产默认关闭/只记录 local delivered challenge”，但 `New` 实际设置 `recordConsumptionAfterDelivery=true`（`multica/server/internal/daemon/daemon.go:847-853`）。实施时这些英文注释应一起按事实修正；这不是改行为。
2. **F9 的函数定义行号需更正**：实际为 `runner.go:595` 的 `StartArchitecture`、`runner_requirement_entry.go:131` 的 `StartRequirement`；输入所给约 1924/362 是 HTTP 入口附近。这不改变两个 production 入口的实质结论（`multica/server/internal/governance/runner.go:595-647`；`multica/server/internal/governance/runner_requirement_entry.go:131-187`）。
3. **F1 的 replay 表述须区分**：同字节是幂等重放；不同 challenge 不是 changed=false，而是 endpoint 409。B 的修订只扩大 authorized 节点的不同 challenge 数，不把不同字节当幂等（`multica/server/internal/daemon/execution_binding_endpoint.go:126-139,179-190`）。
4. **A 方案不能被描述成“writer 去掉一次重复 advance”**：两次 advance 对应状态机中两个不同合法转换，没有直接边；合并会改变状态机和 skill 前置，不是纯去重（`tools/dir-graph.yaml:218-220`）。
5. 除上述行号、陈旧注释和 A 方案成本表述外，未发现输入 F1—F12 与本次只读代码相冲突的行为事实；未验证项不作“已一致”处理。

## Gate 2 待用户裁定

| 议题 | 推荐 | 用户需要明确的决定 |
|---|---|---|
| **G2-1：D1 证据生产者及合同** | 选 **B 有界修订版**：节点启动前一证，authorized 节点 endpoint 最多两个不同 advance challenge，run-end 不重复消费。 | 是否接受对 SC-AUTH-007 的这一明示修订？若不接受，需在 A/C 间另选并允许成对 tools change；纯 daemon 单 proof 方案不足以通过 writer。若授权材料可见性必须改 tools，是否同意另建成对 change？ |
| **G2-2：D4 锁边界和旧探针** | 选 **A**：显式 WorkspaceID + 写入侧 workspace 行锁（BUILD 修订为 FOR KEY SHARE，见 G2-7），迁移 33 个 fixture，旧探针断言不变。 | 是否接受这笔测试改动？若选 B，必须同时明确旧探针改为 production-route/生产路径断言，不能只把红灯删掉。 |
| **G2-3：真实资源、模型和费用** | 计划 **A+B 两次 architecture run**，第三次仅止损复跑且再次询问；默认不跑 requirement。 | 是否授权本变更自建/自释放 podman、PG、backend/daemon 及 cleanup smoke？用户在 BUILD 前指定非 Fable 模型、可接受费用和实际两次上限；历史候选 `Gobao/deepseek-v4.1-flash` 仅供参考。 |
| **G2-4：真实 CR 前置** | 默认 seed 到 `requirement-approved`，用真实授权和 source task 启动 architecture，以节省需求链模型成本。 | 接受此前置，还是另行授权完整 requirement 真实 run？不得预置 execution grant 来绕过交付链。 |
| **G2-5：长程边界** | Gate 2 后仅预授权普通文件实现与无外部资源测试。 | 真实模型、podman/DB、真实 backend/daemon、tools 修改、提交、推送、部署仍需逐项许可；遇 tools 需要时停止，不借 multica Gate 代替。 |
| **G2-6：锚定标签** | 保持 proposal 的 `anchoring.level: L1` 不动，L2 接口锚定只写进本 design（本节）。工具检查 (l) 在 `is_critical=false` 时不适用，改标签会让 Gate 1 过期。 | 是否同意不改 proposal 标签？若坚持标 L2，须同意一并重签 Gate 1。 |
| **G2-7：D4 的三处 BUILD 修订（ADJ-S7-1/2/3）** | 接受：锁模式用 `FOR KEY SHARE`（不额外阻塞 `issue_counter` 的普通 UPDATE）；并发探针不加生产 hook，用生产自己的 sweep 行锁暂停真实删除；新增 `governance-wsd-lock` 验证消费入口的锁序与模式。 | 是否接受这三处对已批准 design/test-plan 的修订？ |
| **G2-8：授权节点的信任根注入（D1.7，ADJ-E4-1）** | 接受：daemon 对授权节点注入 `CRCTL_EXECUTION_TRUST_ROOT`（值为 `store.Root`，仅 `ExecutionPreconsumed` 任务，custom_env 之后发布）；依赖已确认的 tools 成对 change，发布顺序先 tools 后 daemon；新增 TC-REC-009。Gate 1 的范围与成功标准不变，AI 判断不重审 Gate 1（依据与反面见 design-adjustments ADJ-E4-1）。 | ①是否接受 D1.7 的边界：只定位不隔离、不探测 crctl 能力、不为 register/archive 开旁路？②「把 daemon 信任库路径告知授权节点的 agent」是否应视为 Gate 1 层面的新增接受风险（若是，需 Gate 1+2 一并重审）？AI 的判断是否，理由：不新增 agent 能力、本地准入非权威、写入者仍只有 daemon。该判断由你裁定。 |
| **G2-9：source 路径与 tools 补字段（D1.8/D1.9，ADJ-A0-1）** | 接受：①daemon 为 strict 无载体 source 任务新增预检/预消费分支（局部范围，不写 `Pipeline*`，不设 `ExecutionPreconsumed`，不注入信任根，不开 endpoint）；②tools 侧补字段**并入**已有成对 change `node-trust-root`（用户已裁定「并入」；其 Gate 1/2 重审、Gate 3 过期重签，独立于本 Gate）；daemon 读法不变；③B1 与 B2 同一次修订、同一次 Gate 2（用户已裁定）。Gate 1 范围与成功标准不变（G1「真实来源」「真实节点」本就包含它们），AI 判断不重审 Gate 1。 | ①是否接受 D1.8 的边界（修在 daemon，不放宽 admission）？②是否接受 tools 侧各 Gate 由 tools change 独立确认、本 Gate 不代签？③「补字段后先由 A0 无模型观察、再由真实 A 复核」是否可接受？ |
| **G2-10：预消费信任根按 task generation 取子目录（D1.10，ADJ-A0-2）** | 接受：`ExecutionTrustStore.Generation`，根为 `<workspace 根>/<g>`；只改 multica daemon，不改 tools 合同与平台侧；在 SC-REC-001 与 TC-REC-001 内增补，不新增 SC/TC/CP。Gate 1 范围与成功标准不变（G1「真实节点各有回执」本就包含），AI 判断不重审 Gate 1。 | 是否接受 D1.10 的取舍：每个 generation 留一个不回收的小目录，本地 receipt 不再跨 generation 互斥（权威仍在平台唯一键与 binding proof）？真实 crctl 下的成立由 A0 重跑与真实 A 观察，不由单测证明。 |



