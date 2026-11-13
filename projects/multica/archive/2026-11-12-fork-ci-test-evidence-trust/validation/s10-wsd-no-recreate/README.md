# Slice 10 — 禁新建探针（SC-WSD-005 / TC-WSD-005）

> **本文件分两段，按时间顺序保留，不覆盖。**
>
> - **§1–§7 = 裁定前（U3 上报点）**：探针两半均红灯，即为发现。当时**未修任何生产代码、
>   未放宽任何断言、未改任何触发器**，按 design U3 停止并向用户上报。
> - **§8 起 = 裁定后（R5 / ADJ-017）**：用户裁定「只修reservation半句，command做好记录，
>   待以后可以找回并修订」。reservation 半句已修并实测转绿；command 半句**保持红灯原样**，
>   登记为可找回的已声明发现（`owner=known-finding`），不计为覆盖。
>
> 记录不等于批准，也不等于已修复；两半的结论分别见 §9 与 §10。

---

## 裁定前记录（§1–§7，原文保留）

## 1. 本轮产出物

| 文件 | 归属 | 说明 |
| --- | --- | --- |
| `server/internal/handler/workspace_delete_no_recreate_test.go` | 新增（fork 自有） | 探针本体，4 个子测试 + 父测试 |
| `scripts/aifi45-disposable/selections.json` | 上游挂钩（追加 1 条） | 新增 `handler-wsd-no-recreate`，31 条 selection，CRLF 保持 |
| `red/handler-wsd-no-recreate.ndjson` | 证据 | 一次性实例上的 go test JSON 流 |
| `red/handler-wsd-no-recreate.json` | 证据 | runner 汇总：`ok=false`、`stage=test`、`reasons=["exit=1","fail=3"]` |
| `containers-before.txt` / `containers-after.txt` | 证据 | 运行前后容器清单，`diff` 为空 |

`selections.json` 编码核对：`crlf=122`、`bareLf=0`、`selections=31`、名称唯一。
`go vet ./internal/handler` 无输出（编译与静态检查通过）。

## 2. 探针设计（为什么红灯可信）

复用 Slice 9 的 `newExecutionFixture`：A/B 两个 workspace，各 19 张 `cr_execution_*` 表各一行。

1. **先腾出 open 槽**：对 A、B 各调用生产入口
   `governance.TransitionControlCommandTx(ctx, tx, commandID, "created", "settled_no_effect", verdictID, "", 0)`。
   command 是 append-only，结算是唯一能释放「每 lineage 至多一条未结算 command」槽位的路径；
   fixture 已备好结算所需的 verdict 行。**没有用 DELETE 绕过守卫。**
2. **真实删除 A**：`deleteWorkspaceViaHandler` → 期望 204，实测 204。
3. **核对前提**：`workspace` 表中 A 已不存在；A 的 `cr_execution_contract_selection` 行
   仍在且与删除前**逐字节相同**（整行文本比较）。前提不成立则探针无意义，直接 Fatal。
4. **四个子测试**，各自独立事务 + `defer Rollback`，无论红绿都不留残留：

| 子测试 | 对象 | 断言 | 实测 |
| --- | --- | --- | --- |
| `reservation_for_deleted_workspace` | A | `CreateReservationTx` SHALL 拒绝 | **FAIL：被接受** |
| `reservation_for_live_workspace` | B | 正向对照，SHALL 成功且事务内可见该行 | PASS |
| `command_for_deleted_workspace` | A | `ApplyControlCommandTx` SHALL 拒绝 | **FAIL：被接受** |
| `command_for_live_workspace` | B | 正向对照，SHALL 成功且事务内可见该行 | PASS |

正向对照是必需的：没有它，A 的拒绝可能只是请求构造错误或槽位冲突，而不是 workspace 边界。
两个对照都通过，说明**同样的请求构造在活着的 workspace 上被接受**，A 与 B 的唯一差别就是
workspace 是否还存在。

reservation 请求用全新 candidate 字节与全新 `uuid.NewString()` 任务 id，两条唯一性规则
（`(lineage_id, candidate_digest)`、`proposed_task_id`）都不可能是拒绝理由。
command 用 `ed25519` 现签 envelope（`SignControlPayloadBytes`，与 governance attestation 测试同一套导出 API），
`seq=2`（fixture 已占 seq 1，`UNIQUE(lineage_id, seq)`），`prev_digest=""` → NULL。

## 3. 实测结果（一次性实例，非旧库）

命令：

```
node scripts/aifi45-disposable/run-selection.mjs \
  --selections scripts/aifi45-disposable/selections.json \
  --only handler-wsd-no-recreate \
  --evidence-dir <本目录>/red
```

runner 输出：

```
FAIL handler-wsd-no-recreate pass=2 fail=3 skip=0
  workspace_delete_no_recreate_test.go:154: SC-WSD-005 violated: CreateReservationTx accepted
    reservation 3ca4e09f-c344-447b-98b2-651c889468a3 for deleted workspace
    2e166b92-9db4-4a51-9d02-a7b02251fca0 through retained selection
    6d43b155-9f1a-433f-8ca4-ac0168bc706b
  --- FAIL: TestWorkspaceDeletionRefusesNewReservationAndCommand/reservation_for_deleted_workspace (0.00s)
  workspace_delete_no_recreate_test.go:185: SC-WSD-005 violated: ApplyControlCommandTx accepted
    command b97cc2e3-2aec-4e3a-bc07-d4f47a6e588b (state created) on lineage
    db196f50-4283-4561-933e-b93469bebda6 of deleted workspace 2e166b92-9db4-4a51-9d02-a7b02251fca0
  --- FAIL: TestWorkspaceDeletionRefusesNewReservationAndCommand/command_for_deleted_workspace (0.01s)
  --- FAIL: TestWorkspaceDeletionRefusesNewReservationAndCommand (0.10s)
released instance 65a37a694e96 remaining=0
EXIT=1
```

`pass=2` 是两个正向对照，`fail=3` 是 A 的两个子测试加父测试。`skip=0`。
`packages=0` 是 runner 对 `-run` 精确选择模式的既有计数口径，与 Slice 9 各 selection 一致。

## 4. 代码级根因（读码定位，与实测一致）

| 路径 | 位置 | 事实 |
| --- | --- | --- |
| reservation 创建 | `server/internal/governance/execution_control_reservation.go:70` | 整个函数不查 `workspace` 表 |
| 唯一的 workspace 相关语句 | 同文件 `:89-91` | `SELECT mode, lineage_id::text FROM cr_execution_contract_selection WHERE id=$1 AND workspace_id=$2 AND project_id=$3 AND cr_id=$4` —— 这是对**保留下来的 selection 行**做过滤，不是对 workspace 做存在性检查 |
| command 创建 | `server/internal/governance/execution_control_store_state.go:148` | 全文件 `workspace` 零引用；校验链为字段 → 验签 → lineage 锁 → 重放 → 停止序 → open 槽 → 复验 → INSERT |

D2 保留 selection 行，于是 `:89-91` 的重读在 teardown 之后依然命中，`:70` 的后续校验全部通过。
**保留策略本身没错，缺的是创建路径上的 workspace 存在性边界。**

## 5. 边界核对（本轮实际执行）

- 数据库：仅 runner 自建一次性 podman 实例（`released instance 65a37a694e96 remaining=0`）；
  未连接 `localhost:5432`，未操作旧 `multica-postgres` 容器。
- 容器清单：运行前后 `diff` 为空（`INVENTORY_UNCHANGED`），仅两个既有 `Exited` 容器
  （`multica-postgres`、`multica-backend`）。
- nonce 门禁未放宽；未读取或打印任何 PAT/凭据；未改仓库 secret。
- 未提交、未推送、未部署。multica `HEAD = origin/main = 903a46c5ae9fa6c3ee644fa4740d189d739dcc91`，
  工作区仅含本 change 的文件，无夹带。
- 记录仓其他未提交改动未清理、未混入。

## 6. 10.3 收敛转移：确认未实现

本 change 的生产代码改动只有两处：`server/internal/handler/workspace.go` 的 11 行 sweep 挂钩
（`git diff --stat`：1 file changed, 11 insertions(+), 0 deletions），以及新增的
`server/internal/governance/workspace_delete_execution.go`。后者 `grep cursor|converg|收敛` 无命中。
迁移 649 只加两条 `BEFORE TRUNCATE` 守卫。**command 与 cursor 的收敛转移未实现**，
与 canonical SC-WSD-005 的「本 change SHALL NOT 实现 command 与 cursor 的收敛转移」一致；
收敛作为后继议题登记，不在本 change 内偷偷补上。

## 7. 待用户裁定（U3，未决）

canonical SC-WSD-005 原文：「SHALL 被拒绝；若当前代码允许，该测试红灯即为发现，SHALL 停止并
向用户上报，由用户裁定是否在本 change 内修复（design U3），不得静默放宽断言或改触发器。」

因此本轮到此停止。探针保持红灯原样留在仓库里，`handler-wsd-no-recreate` 已进 selections，
`baseline-handler` 整包基线也会带上这条红灯——这是如实暴露，不是回归被掩盖。
裁定前不动生产代码，也不把断言改成「记录现状」。

**裁定已到达，见 §8。** 本节描述的「两半均红、未修生产代码」是上报当时的状态，不是最终状态。

---

## 裁定后记录（§8 起）

## 8. 用户裁定与修订（R5 / ADJ-017）

用户裁定原文（AskUserQuestion 选项，逐字）：

> 只修reservation半句，command做好记录，待以后可以找回并修订

按 STDD revision 流程处理，**先修订、再动生产代码**（与 R4 同顺序）：

1. `design.md` 新增 `## 修订记录（BUILD 前，Gate 2 重签）` 的 **R5** 条目：原文 / 核实依据
   （实测 FAIL 报文 + 两处爆炸半径事实）/ 用户裁定原话 / 修订后 / 连带实现决定 / 影响范围。
   同时更新「未验证事实 #3」为已回答、U3 条目追加裁定、决策 7 段落追加 R5 更新、风险表 D2 行追加。
2. canonical `specs/code/workspace-delete-execution-tables.yaml` 的 **SC-WSD-005**：
   置信度 low → medium；`then` 改为「reservation 半句 SHALL 被拒绝，本 change SHALL 在
   `CreateReservationTx` 内加 workspace 存在性检查使其成立；command 半句经探针实测当前代码放行，
   按 U3 用户裁定（R5）不在本 change 内修复，SHALL 保持探针断言原样（红灯即为已声明的发现），
   SHALL 登记为可找回的已知失败并指向后继议题，不得静默放宽断言、不得改触发器、不得把红灯洗成绿灯。」
   `and` 三项：SHALL NOT 实现收敛转移；两半各自独立测试函数；登记可经 `test-ownership check`
   与归档基线 spec 找回。
3. canonical `specs/agent/workspace-delete-execution-tables.yaml` 的 **CP-WSD-005** description 同步；
   `action` 与两条断言（`exit_code 0`、`stdout_contains 'PASS handler-wsd-no-recreate '`）**一字未改**——
   锁定命令本身没变，变的是它现在只覆盖 reservation 半句。
4. canonical `specs/code/test-ownership-and-ci-reconciliation.yaml` 的 **SC-TOR-001** 追加一条 `and`：
   归属表 SHALL 允许 `owner=known-finding` 承载经用户裁定不在本 change 内修复的已知失败，
   该条目 SHALL 指名后继议题与复现命令，SHALL 与其他条目一样被 `check` 核对真实 func、
   被 `skip-regex` 排除、被 `ci-evidence` 核对排除生效，且 SHALL NOT 被计为覆盖。
5. 人工视图手工镜像（`stdd canon generate --type spec` 的 CLI 缺陷见 ADJ-015，`--all` 会动到
   他人未提交记录，故用 Edit 逐处镜像）：`specs/workspace-delete-execution-tables/spec.md`、
   `specs/test-ownership-and-ci-reconciliation/spec.md`、`test-plan.md` 的 TC-WSD-005 与 TC-TOR-001。
6. **Gate 2 以裁定原文重签**：`stdd gate approve 2026-11-12-fork-ci-test-evidence-trust --gate 2
   --confirmed-by dialog --reapprove --evidence "只修reservation半句，command做好记录，待以后可以找回并修订"`，
   回执时间 **2026-11-12T23:54:09**，旧回执 superseded。

**连带实现决定：不新增机制。** 读码核实 `test-ownership.mjs` 的 `ENTRY_FIELDS` 里 `owner` 是自由字符串
（无枚举校验），`check` / `skip-regex` 与 `ci-evidence.mjs` 的 rule 3 已经能处理「已声明的排除」。
因此已知发现走既有 `entries` 通道即可：**`test-ownership.mjs` 与 `ci-evidence.mjs` 一行未改**。

## 9. reservation 半句：修复与实测（GREEN）

### 9.1 生产改动（唯一一处）

`server/internal/governance/execution_control_reservation.go`：

- 新增哨兵 `ErrReservationWorkspaceGone`
  （`EXECUTION_CONTROL_RESERVATION_WORKSPACE_GONE: the workspace no longer exists`）。
- 在「Re-read the selection」之前插入 workspace 存在性检查：
  `SELECT EXISTS (SELECT 1 FROM workspace WHERE id = $1::uuid)`，不存在即返回该哨兵。
  注释说明**为什么必须单独问一次**：selection 行在 teardown 后被保留，下面的重读依然命中。
- 头部加 `// AIFIRST:` 英文注释，标注 STDD change 与 SC-WSD-005/R5。

`git diff --numstat` 口径见 §12。**未改触发器、未改迁移、未改 sqlc、未放宽任何既有断言。**

### 9.2 夹具修正（不是放宽断言）

`server/internal/governance/execution_contract_selection_test.go` 的
`selectionWorkspace = "aaaaaaaa-0000-4000-8000-000000000001"` 在库里**从来没有对应的 workspace 行**。
新边界生效后，该夹具的 reservation 探针会因「workspace 不存在」而红——这是夹具缺前提，不是产品缺陷。
修法是在 `insertSelectionWithMode` 开头**补一行真实 workspace**（事务内，随探针回滚，
`ON CONFLICT (id) DO NOTHING` 因为一个探针可能插多条 selection）。
`workspace` 表结构核实自 `server/migrations/001_init.up.sql:15-23`（id/name/slug 必填）。
**断言强度未降低**：探针仍然要求「活着的 workspace 上必须成功」。

### 9.3 探针拆成两个独立测试函数

`server/internal/handler/workspace_delete_no_recreate_test.go` 由原来的
`TestWorkspaceDeletionRefusesNewReservationAndCommand`（4 子测试）拆为：

| 测试函数 | 子测试 | selection | 结论 |
| --- | --- | --- | --- |
| `TestWorkspaceDeletionRefusesNewReservation` | `reservation_for_deleted_workspace` / `reservation_for_live_workspace` | `handler-wsd-no-recreate` | **GREEN** |
| `TestWorkspaceDeletionRefusesNewCommand` | `command_for_deleted_workspace` / `command_for_live_workspace` | `handler-wsd-no-recreate-command` | **RED（已声明发现）** |

拆分的理由写进了文件头英文注释：两半的裁定不同，必须能被 CI 分别排除/纳入；
合成一个函数会让 reservation 的绿灯被 command 的红灯吞掉。

`reservation_for_deleted_workspace` 除了 `err == nil` 即 Fatal，还额外要求
`errors.Is(err, governance.ErrReservationWorkspaceGone)`——**否则「因为别的原因被拒」也能空洞地变绿**。

### 9.4 实测（一次性实例，tools env 已注入）

```
PASS handler-wsd-no-recreate pass=3 fail=0 skip=0
released instance 32985751b4f5 remaining=0
EXIT=0
```

`pass=3` = 父测试 + 2 个子测试。**满足 CP-WSD-005 的两条锁定断言**：`exit_code 0` 与
`stdout_contains 'PASS handler-wsd-no-recreate '`。证据：`green/handler-wsd-no-recreate.{ndjson,json}`。

### 9.5 变异验证（证明守卫承重，且探针非空洞）

把 `if !workspaceExists {` 中和为 `if !workspaceExists && false {`（保持可编译），
在一次性实例上重跑同一条 selection：

```
FAIL handler-wsd-no-recreate pass=1 fail=2 skip=0
  workspace_delete_no_recreate_test.go:171: SC-WSD-005 violated: CreateReservationTx accepted
    reservation cba346e2-2ce8-453f-92dc-f80126013f2a for deleted workspace
    43c1c6f2-cc2a-423a-bcb4-e51a34cec624 through retained selection
    174e3ca9-c33b-43d0-a0ca-3a6b259a935c
  --- FAIL: TestWorkspaceDeletionRefusesNewReservation/reservation_for_deleted_workspace (0.00s)
  --- FAIL: TestWorkspaceDeletionRefusesNewReservation (0.09s)
released instance f1857f6c492f remaining=0
EXIT=1
```

**DETECTED**：红的正是「已删除 workspace 被接受」这一条断言，正向对照仍绿（`pass=1`）。
随后按原字节还原并核对 sha256：

```
543ace58cdf56edf8863d31295a3a2104b0e7b6ed14a9d4eeac1c0ac5040b8c2  execution_control_reservation.go
```

与中和前逐字节一致。证据：`mutation-guard-neutered/`（含 `restored-sha256.txt`、前后容器清单）。

### 9.6 夹具修正未回归 governance（环境差异已排除）

`channel-protocol`（含 `TestChannelFoundationSelection` / `TestChannelFoundationReservation` /
`TestChannelProtocol` / `TestChannelStoreGuards` / `TestChannelPolicyResume`）第一次重跑
**FAIL pass=39 fail=2**，两条失败均为
`execution_control_protocol_test.go:334: AIFI45_TOOLS_ROOT is required; the shared vector fixture lives in the tools repo`。

**这不是回归，是 S9 已定性的同一环境差异**（本 shell 未设 tools env）。按 S4/S9 同条件注入
`AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`、
`CRCTL_MJS=…/skills/shared/crctl/scripts/crctl.mjs`（tools HEAD 核实 `e52b8081f159`，与 pin 一致）后重跑：

```
PASS channel-protocol pass=46 fail=0 skip=0
released instance 6307e8b4c2c7 remaining=0
EXIT=0
```

证据：`green-governance/`（缺 env，如实留证）与 `green-governance-toolsenv/`（补齐 env，46/0/0）。
**对 S13 的硬结论沿用 S9**：CI 的 `backend-tests` 必须显式注入这两个变量。

## 10. command 半句：保持红灯，登记为可找回的已声明发现

### 10.1 为什么不修（爆炸半径已读码核实）

`ApplyControlCommandTx`（`server/internal/governance/execution_control_store_state.go:148`）
的唯一生产调用方把**消费回执 id** 当作 `ReservationID` 传入。若照 reservation 的做法加
「reservation → selection → workspace」查找，生产路径会立刻断——它传进来的根本不是 reservation id。
另有 33 处测试调用点使用不透明随机 id。因此 command 半句需要的是**另一套边界设计**，
与 command/cursor 收敛转移是同一个后继议题，不是本 change 内顺手能补的一行。

### 10.2 实测（与登记时声明的预期逐字相符）

```
FAIL handler-wsd-no-recreate-command pass=1 fail=2 skip=0
  workspace_delete_no_recreate_test.go:222: SC-WSD-005 violated: ApplyControlCommandTx accepted
    command dea9231b-f043-48b4-81d5-12b4f083d0ad (state created) on lineage
    2fe9c279-acac-4a96-8230-b1f0f607805c of deleted workspace fc9fd30e-9199-40e2-b44c-f8c64c67d630
  --- FAIL: TestWorkspaceDeletionRefusesNewCommand/command_for_deleted_workspace (0.01s)
  --- FAIL: TestWorkspaceDeletionRefusesNewCommand (0.10s)
released instance 3dec80c92696 remaining=0
EXIT=1
```

证据：`known-finding/handler-wsd-no-recreate-command.{ndjson,json}`。
**断言一字未改，触发器一字未改，红灯未被洗成绿灯。**

### 10.3 登记方式（三处可找回，零新机制）

`scripts/aifi45-disposable/test-ownership.json` 的 `entries` 追加第 5 条：

| 字段 | 值 |
| --- | --- |
| `package` | `./internal/handler` |
| `test` | `TestWorkspaceDeletionRefusesNewCommand` |
| `owner` | `known-finding` |
| `entry` | `run-selection.mjs --selections selections.json --only handler-wsd-no-recreate-command (expected RED: pass=1 fail=2 skip=0)` |
| `reason` | 声明这是 KNOWN FINDING 而非覆盖、非静默 skip；指名 ADJ-017 / SC-WSD-005 command 半句 / R5；给出根因位置 `execution_control_store_state.go:148` 与消费回执契约障碍；写出后继议题（给 `ApplyControlCommandTx` 加 workspace 边界且不破坏消费回执契约，与 command/cursor 收敛转移一并处理）；说明可从本表、ADJ-017、归档基线 spec SC-WSD-005 三处找回 |

这是**已声明的排除**，不是静默 skip：`check` 会打印 `owner=known-finding` 与 reason，
`skip-regex` 把它交给 `go test -skip`，`ci-evidence` rule 3 会核对它确实没出现在 CI 流里
（出现即判红）。`required-packages` 未变，`allowed-skips` 未变（它不是 skip）。

### 10.4 归属表测试 RED → GREEN

`test-ownership.test.mjs` 新增 2 项、改 1 项既有断言（真实表的 skip-regex 期望值追加第 5 个名字）：

- `TC-TOR-001 the committed known-finding stays declared, justified, resolvable and excluded`：
  按 `owner === "known-finding"` 过滤，断言 package、`entry` 含 `run-selection.mjs` 与 selection 名、
  `reason` 含 `ADJ-017` 与 `follow-up`，`check` 输出含 `owner=known-finding`，`skip-regex` 含该测试名。
- `TC-TOR-001 a known-finding entry needs a real func and a reason like any exclusion`：
  沙箱三例（拼错名 `TestAlpah`、空 reason、空 entry）**全部必须失败**——已知发现不享受宽松校验。

RED：`red-ownership.tap` **18 tests / 16 pass / 2 fail**（两项新用例在登记前红）。
GREEN：`green-ownership.tap` **18 / 18 / 0**。

## 11. selections 与编码核对

`scripts/aifi45-disposable/selections.json` 由 31 条增至 **32 条**，新增：

```json
{"name": "handler-wsd-no-recreate", "package": "./internal/handler", "run": "^TestWorkspaceDeletionRefusesNewReservation$"},
{"name": "handler-wsd-no-recreate-command", "package": "./internal/handler", "run": "^TestWorkspaceDeletionRefusesNewCommand$"}
```

编码核对：`crlf=127`、`bareLf=0`、名称唯一。`test-ownership.json` 与 `test-ownership.test.mjs` 保持 LF
（后者 293 行）。`go vet ./internal/handler ./internal/governance` exit 0、无输出。

## 12. 整包回归与逐名对账（一次性实例，tools env 已注入）

对账方法沿用 S9：从原始 `go test -json` 流取测试名，把内嵌 UUID 规范化为 `<uuid>`
（S9 已证明部分子测试名带随机 workspace UUID 或一次性 nonce，原始名集合不可直接比较）。
完整输出：`regression-reconcile.txt`。

### 12.1 handler 整包

| | pass | fail | skip |
| --- | --- | --- | --- |
| S9 post-649（`regression-handler-649/`） | 4533 | 3 | 47 |
| S10（`regression-handler/`） | **4535** | **7** | **47** |

- **PASS 新增恰好 4 名**，全是本切片探针：`TestWorkspaceDeletionRefusesNewReservation`
  及其 2 个子测试，加 `TestWorkspaceDeletionRefusesNewCommand/command_for_live_workspace`（正向对照）。
- **FAIL 新增 4 名** = 2 个 command 已知发现名（父 + `command_for_deleted_workspace`，**声明内预期红灯**）
  + 2 个 presenter 名（`TestGetPresenterStateVisibility`、`TestPresenterMemberRemovalLinkage`，
  从 PASS 移过来）。**FAIL 移除 0 名。SKIP 集合逐名不变（47）。**
- 2 个 presenter 受害者的报文与 S4/S8/S9 同因：
  `project_presenter_test.go:317/416/451: create member user: … duplicate key … "user_email_key"`，
  即已裁定为范围外的 Windows 时钟粒度 flake（**ADJ-006**）。这是第四次观察到受害者移动。
  **未修改任何上游 presenter 测试。**
- `TestSearchIndexChangesScopeToWorkspace` 与基线**同名同因**（S4 已定性范围外）。
- 算术自洽：4533 + 4 − 2 = 4535 pass；3 + 4 = 7 fail。

### 12.2 governance 整包

| | pass | fail | skip |
| --- | --- | --- | --- |
| S9 post-649 toolsenv（`regression-governance-649-toolsenv/`） | 1344 | 48 | 1 |
| S10 toolsenv（`regression-governance-toolsenv/`） | **1344** | **48** | **1** |

**FAIL 新增 0、移除 0；SKIP 逐名不变**（唯一 skip = `TestReconcileLiveGitHub`，已在 `allowed-skips` 声明）。
PASS 名差异只有 2 个 `nonce-format` 子测试，其名内嵌本轮随机 disposable nonce。
**结论：`insertSelectionWithMode` 补 workspace 行的夹具修正对 governance 零回归。**

### 12.3 脚本目录全量与静态检查

- `node --test "scripts/aifi45-disposable/*.test.mjs"` → **156 pass / 0 fail / 0 skip**
  （= S9 的 154 + 本切片 2 项归属表用例），`regression-directory.tap`，duration_ms 1882.2784。
- `gofmt -l` 三个 Go 文件：**首轮点名 `workspace_delete_no_recreate_test.go` 缺文件末尾换行**，
  已 `gofmt -w` 修正（纯空白，`gofmt -d` 只有 `\ No newline at end of file` 一处），修后无输出。
- `go vet ./internal/handler ./internal/governance` exit 0、无输出。
- **格式修正后按最终字节重跑两条 selection**（`final/`）：
  `PASS handler-wsd-no-recreate pass=3 fail=0 skip=0` exit 0（实例 `42554a34be4e`）、
  `FAIL handler-wsd-no-recreate-command pass=1 fail=2 skip=0` exit 1（实例 `d1e4ac7d57c6`），
  与 §9.4 / §10.2 逐字相符。最终 sha256：
  reservation `543ace58…`、selection_test `32e81745…`、no_recreate_test `88bd6f2c…`。
- `test-ownership check` exit 0：`5 entry(ies)`（第 5 条打印 `owner=known-finding` 与完整 reason）、
  `allowed skips: 4`；`skip-regex` exit 0，输出
  `^(TestChannelIsolation|TestChannelMigrationAfterUp|TestChannelMigrationAfterDown|TestChannelMigrationAfterReapply|TestWorkspaceDeletionRefusesNewCommand)$`。
  证据：`ownership-final.txt`。

## 13. 边界核对（裁定后本轮实际执行）

- 数据库：仅 runner 自建一次性 podman 实例。裁定后共 **9 个**实例
  （`32985751b4f5` green、`3dec80c92696` known-finding、`2691ac2ea4f6` 缺 env、`6307e8b4c2c7` 补 env、
  `f1857f6c492f` 变异、`56f0b58fb181` handler 整包、`54807d73bcb4` governance 整包、
  `42554a34be4e` + `d1e4ac7d57c6` 最终字节复跑），**全部 `released … remaining=0`**；
  另有裁定前 RED 取证的 `65a37a694e96`（§3），同样 released remaining=0。
- 容器清单：每次运行前后 `diff` 均为空（`INVENTORY_UNCHANGED`），仅两个既有 `Exited` 容器。
- 未连接 `localhost:5432`，未操作旧 `multica-postgres` / `multica-backend` 容器，未触碰卷。
- nonce 门禁未放宽；未读取或打印任何 PAT/凭据；未改仓库 secret。
- 未提交、未推送、未部署。multica `HEAD = origin/main = 903a46c5ae9f`，工作区仅含本 change 的文件。
- tools HEAD 核实 `e52b8081f159`（与 pin 一致），其既有未提交改动未触碰。
- 记录仓其他未提交改动未清理、未混入。

## 14. 切片验证（B3.4）与未验证项

### 14.1 B3.4 三项检查

| 检查 | 结果 |
| --- | --- |
| TC 覆盖 | **1/1**（TC-WSD-005）。其预期结果**全部成立**：reservation 半句实测被拒（绿）；command 半句的预期结果本身就是「保持探针断言原样、红灯即为已声明的发现、登记为可找回的已知失败并指向后继议题」——这三项也已逐条成立（§10.2 红灯原样、§10.3 三处找回路径）。 |
| 产出物核对 | slices.md 切片 10 目标「已删 workspace 的 selection 禁新建 reservation/command 探针」逐项存在：探针文件、两条 selection、归属表条目、归属表用例、生产边界、夹具修正。 |
| 测试运行 | 新增 **8** 项（Go 2 顶层 + 4 子测试 + node 2 项）。node 2 项与 reservation 的 3 个 pass 全绿；**`TestWorkspaceDeletionRefusesNewCommand` 与其 `command_for_deleted_workspace` 子测试是红的**。 |

**「新增测试全部通过」这一条本切片不成立，如实记录为已声明偏离**：command 半句的红灯是
**用户裁定（R5 / ADJ-017）与重签后的 canonical SC-WSD-005 明文要求保留的状态**
（「SHALL 保持探针断言原样（红灯即为已声明的发现）…不得把红灯洗成绿灯」）。
授权来源是 Gate 2 以裁定原文 `--reapprove` 重签（2026-11-12T23:54:09），不是 AI 自行放宽。
该红灯经 `owner=known-finding` 声明排除、被 `ci-evidence` rule 3 核对排除生效，**不计为覆盖**。

**不得据此声称 SC-WSD-005 的安全目标已全部达成**：workspace teardown 后仍可为保留的
selection 新建 **command**，这个产品缺口**仍然存在**，只是按裁定不在本 change 内修。

### 14.2 未验证 / 未完成（不得报通过）

- `TestWorkspaceDeletionRefusesNewCommand` **红灯**，是已声明发现，**不计为覆盖**；
  TC-WSD-005 记 1/1 的依据见 §14.1（command 半句的预期结果就是「保持红灯 + 可找回登记」），
  **不代表 command 的产品缺口已修**。
- command 与 cursor 的**收敛转移未实现**（canonical 明文 SHALL NOT），作为后继议题登记。
- 未在 ubuntu-latest 上跑过这两条 selection；真实 CI run 属 TC-CBE-005（须推送，另行授权）。
- `make test` 未执行（U5 排除）。
- `TestChannelIsolation*` 未在 WSL AIFI-ISO 实跑（TC-TOR-004）。
- **ADJ-005（major）仍未决**：S13 设 `MULTICA_CONTROLLED_SHELL_RULES` 前须用户裁定。
- **ADJ-018（minor，新发现）待裁定**：CUSTOM.md 四数基线表停在 2026-11-10，本 change 未重算；
  实测值与三点限制已写进 #327 合并注意，合并窗口前须重算补行。