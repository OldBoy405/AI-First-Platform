---
id: CR-2026-075-plan
type: PLAN
cr-ref: CR-2026-075
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
status: draft
created: 2026-10-02T23:52:00+08:00
updated: 2026-10-03T00:35:00+08:00
---

# CR-2026-075 开发计划

承接已审批 `sdd.md` v0.4（tech-design cycle 2 / attempt 1 PASS，Blockers 0；LF 规范化 `sha256=86179d81c2c3a70c57ee1cfef178752429e20f80c45e5e82d59979d88973f9d6`）。范围：FR-01～FR-16、AC-A1～A8 与 AC-B1～B20 全部（SDD §9 `scope_in`）。交付仓分工：tools 承载 A 段 CLI 归一、共享恢复原语扩展、两个业务受控写入入口与确定性转换模块、合同/提示对齐；multica 承载 task 级绑定解析/发布与同包测试、部署副本与定制登记；knowledge-base（ai-first-platform-docs）只承载本 CR 文档与 `test-evidence/`。代码与文档路径一律取 `crctl workspace inspect CR-2026-075 --workspace <workspace>` 的 `resources[].worktreePath` 与 `operationalWorkspace` 原样值（本次实测三仓 `classification=healthy`、`dirty=false`），不按目录命名拼接。TASK 编号即 canonical 完整 id（`CR-2026-075-TASK-NN`），与 `tasks/_index.yml` 的 id 集一致。计划层不含步骤粒度表述；步骤切分在 write-dev-tasks / implement-code 按 `coding-discipline` §2 执行。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 预估（人天当量） |
|---|---|---|---|
| M1 A 段 CLI 归一（先交付，同批交付门上游） | `bindTaskWorkspace` 前置归一与失败关闭；显式模式/help/Windows 动态路径用例 | TASK-01 | 1.0 |
| M2 A 段 daemon 绑定解析与发布 | `resolveTaskWorkspaceBinding`、`parseExecutionContext`、三元组成对写入/清除、Git 环境配置与 launcher 泛化、同包表驱动测试 | TASK-02 | 1.5 |
| M3 共享恢复原语 | `durable-tx.mjs` 可选 `expect` 锁内比对 + 可选 `sampleCommitState` 锁内取样；既有 `recoverLedgerCommand(ws,key)` 仅做取样器接线（保持两参、无 `expect`）；业务摘要/txId 比对由 TASK-04/05 的新增 `recoverBusinessLedgerCommand` 承载；故障注入向量 | TASK-03 | 1.0 |
| M4 B 段两个业务入口 | 共享命令面/事务接线/提交定型 + `lib/planning-entry.mjs`；`lib/competitive-report.mjs` | TASK-04、TASK-05 | 2.5 |
| M5 合同、提示与登记对齐 | `cmdValidate` 维度层；engineering-docs 合同与日期；12 处 CR-ID、矩阵/Agent 登记、FR-14 提示收敛 | TASK-06、TASK-07、TASK-08 | 2.0 |
| M6 部署副本与生效版本台账 | 四份部署副本收敛；`delegation-contract.md` 成功集合对齐平台现状（`steered`）与维护副本同步；`CUSTOM.md` 登记；平台侧同步（人类 owner 执行，验收前置）与 `cmd-10`/`cmd-11` 生效内容比对 | TASK-09 | 0.5 |
| M7 回归与证据 | 全量证据回归 `cmd-01`～`cmd-12`；未覆盖风险清单 | TASK-10 | 0.5 |
| M8 评审与发布 | review-dev-plan → 开发启动人工确认（Ray）→ implement-code → test-report → review-code → 代码人工审批（Ray）→ 交付回写 | reviewer / delivery-agent | — |

M8 由 Pipeline 门禁承载，不属于开发 TASK；阶段发布由 reviewer 在评审 PASS 分支内一次闭合。合计 9.0 人天当量。

## 2. 任务依赖图

```text
TASK-01 crctl 绑定归一（tools：crctl.mjs + test/crctl.test.mjs 用例）
   │  同批交付门（FR-03 先于 FR-02 的绑定发布生效）：TASK-01 未完成不合入 TASK-02
   ▼
TASK-02 daemon 绑定解析与发布（multica：pipeline_task.go / daemon.go + pipeline_task_test.go / cr_workspace_binding_test.go）
   │
TASK-03 共享恢复原语（tools：lib/durable-tx.mjs + crctl.mjs 的 recoverLedgerCommand 取样器接线 + test/durable-tx.test.mjs）
   ├─→ TASK-04 规划业务入口（tools：crctl.mjs 命令面/事务接线/提交定型 + 新增 recoverBusinessLedgerCommand + lib/planning-entry.mjs + test/planning-entry.test.mjs）
   │        [TASK-04/05 与 TASK-03 为消费者关系：生产者在先，未完成不得标记 done]
   └─→ TASK-05 竞品业务入口（tools：lib/competitive-report.mjs + test/competitive-report.test.mjs）
            [TASK-05 实现依赖 TASK-04 的产出：唯一 cmdBusinessEntry(wsRoot,flags,kind) 骨架与 recoverBusinessLedgerCommand 由 TASK-04 落地，TASK-05 只追加 kind='competitive' 分支、禁止复制；两任务同编辑 crctl.mjs 分派面，顺序编辑；两条业务意图互不依赖]

TASK-06 validate 维度层 + validate-doc/AGENTS 触发条件（tools：crctl.mjs 的 cmdValidate 新增层 + crctl.test.mjs validate 分支）
        [与 TASK-01 同编辑 crctl.mjs，顺序编辑；逻辑独立]
TASK-07 engineering-docs 合同与日期（tools：slug.ts + base.ts/index-sync.ts + engineering-docs/validate-doc 相关 SKILL 文本）
        [产出 TASK-04/05 调用的 SKILL 文本基线，先于 TASK-08 定稿]

TASK-01、TASK-02、TASK-04、TASK-05、TASK-06、TASK-07 ─→ TASK-08 调用登记与提示收敛（12 处 CR-ID、矩阵/Agent/索引登记、FR-14 收敛）
        [FR-14 门槛（SDD §4.9）：TASK-01 的 cmd-01 与 TASK-02 的 cmd-08 全绿后才执行收敛；未满足时保留原提示]
TASK-08、TASK-07 ─→ TASK-09 部署副本与生效版本台账（multica：cr-prompts-revised/*.md 与维护副本 + delegation-contract 对齐 + CUSTOM.md 登记）
TASK-01～TASK-09 ─→ TASK-10 全量证据回归 cmd-01～cmd-12 ─→ review-code
```

依赖说明：TASK-01 与 TASK-02 无代码调用关系，但存在**同批交付顺序**约束——绑定被普通任务获得（TASK-02）之前，CLI 必须已具备归一与失败关闭（TASK-01），否则旧 CLI 会以 `OPERATIONAL_WORKSPACE_MISMATCH` 拒绝本可合法归一或缺参的调用。TASK-03 是被 TASK-04/05 消费的生产者（`expect` 与 `sampleCommitState`），消费者未完成不得单独标记生产者 done；TASK-05 除消费者关系外还与 TASK-04 存在**实现产出依赖**（唯一 `cmdBusinessEntry` 骨架与 `recoverBusinessLedgerCommand` 由 TASK-04 先落地），业务意图互不依赖不等于实现产出无依赖。TASK-10 消费全部前置 TASK 的真实运行结果，不含任何实现动作。

## 3. 资源与分工

单一执行 Agent：dev-agent（`cr.md owners.development`：Ray，同时是人工审批人）。测试报告由 `owners.test`（Ray）责任执行，消费实现的真实验证结果。

| 仓库 | 分工 | 承载 TASK |
|---|---|---|
| tools | A 段 CLI 归一、共享恢复原语、两个业务入口与转换模块、合同/提示/登记、定向测试 | TASK-01、TASK-03、TASK-04、TASK-05、TASK-06、TASK-07、TASK-08 |
| multica | daemon 绑定解析与发布、同包 Go 测试、部署副本与 `CUSTOM.md` 登记 | TASK-02、TASK-09 |
| knowledge-base | 本 CR 受控文档（plan/tasks/test-report/证据） | Pipeline 节点受控生成；TASK-10 落 `test-evidence/` |

工时分配（人天当量）：TASK-01 1.0、TASK-02 1.5、TASK-03 1.0、TASK-04 1.5、TASK-05 1.0、TASK-06 0.5、TASK-07 0.5、TASK-08 1.0、TASK-09 0.5、TASK-10 0.5。

环境边界：全部工作在 Pipeline 预检的三仓 CR worktree 内；不启停或修改任务范围外的数据库、消息队列、常驻服务与平台配置。

## 4. 风险与回滚策略

| # | 风险 | 缓解 | 回滚 |
|---|---|---|---|
| R1 | 绑定归一改变普通任务「缺 `--workspace`」的观察行为（DEC-2 的有意放松） | 仅在有完整有效绑定时归一；无可信绑定仍 `WORKSPACE_REQUIRED`；显式异根与不完整绑定先于 `detectWorkspace` 拒绝；cmd-01 覆盖显式模式/绑定模式/冲突三态 | revert TASK-01（含其同批 `crctl.test.mjs` 用例）；daemon 侧 revert TASK-02 |
| R2 | 绑定发布先于调用方迁移，旧调用方在绑定环境失败 | 同批交付门：TASK-01 先完成再合入 TASK-02；`WORKSPACE_CONTEXT_MISMATCH` 先于任何 CR 数据读写；两仓测试各自覆盖有/无绑定两态 | 逆拓扑：先 revert TASK-02（停止发布绑定），再 revert TASK-01 |
| R3 | 共享恢复原语判据来源改为锁内取样，触及既有调用点 `recoverLedgerCommand` | `expect`/`sampleCommitState` 均为可选入参，未提供时行为逐字不变；既有 helper 保持 `recoverLedgerCommand(ws, key)` 两参与无 `expect` 的兼容语义，只把锁外预读的 `currentHead`/`headMessage` 换成锁内取样（SDD §9 zero_diff 第④类），五个既有调用点（`crctl.mjs:1201/1871/2093/2594/2852`）零改动；业务摘要/txId 比对只在新增 `recoverBusinessLedgerCommand`（TASK-04 落地、TASK-05 复用）内传 `expect`；`phase=complete`/第三值/CAS/锁分支与错误码零新增；取样失败固定 `TX_GIT_FAILED` 保守失败（零写入、journal 保留、不回滚）；cmd-04 的 B17-a/B17-b、B18-c/B18-d 向量覆盖锁内取样与保守失败，cmd-01 复跑证明既有两参调用的恢复兼容 | 先 revert TASK-04、TASK-05（消费者），再 revert TASK-03 |
| R4 | 共享 `_index.yml` 被多意图写入导致「完成提交定位」误判 | 完成提交由提交消息 `AI-First-Intent` 唯一定位，并以 `C..HEAD` 对关联路径为空为判据；B18-a 向量覆盖「A 完成后 B 更新共享索引再重放 A」 | revert TASK-04（含 `planning-entry.test.mjs` 用例） |
| R5 | 两个业务入口的提交形态与 gitguard/`protectedPaths` 交互未经验证 | 不改 `rules.json`、不新增 commit 形态，沿用既有 `[cr] ` 前缀与 `AI-First-Tx` trailer；cmd-02/03 断言提交消息三行形态与 `changed`/`commit` 回执 | revert TASK-04 → TASK-05 |
| R6 | 12 处 `crctl advance` 补 `{cr_id}` 或 FR-14 收敛误删保留项（业务参数、阶段说明、职责、发布合同、bootstrap 显式根示例） | 只补位置参数、不删业务参数与阶段说明；收敛只删逐命令重复的 `--workspace <workspace>` 示例；cmd-05/cmd-06 扫描兜底，保留项核对保留为 review-code 人工检查项 | revert TASK-08（文本合同，无下游代码消费者） |
| R7 | FR-14 收敛早于 A 段验证门槛（SDD §4.9） | TASK-08 的收敛动作以 cmd-01 与 cmd-08 全绿为前置；门槛未满足时保留原提示、不借「文字已改」宣称行为已变 | revert TASK-08；提示恢复原样 |
| R8 | 生效版本台账被误读为「已部署/已生效」 | TASK-09 只做仓库侧收敛与台账；平台侧同步（本 CR 涉及的 imported Skills、四份 CR Agent instructions、规划/竞品两个业务调用方 Agent instructions）由有权限的人类 owner（Ray）按卡内同步清单执行，**是 TASK-09 验收的前置**；前置完成后由只读的 cmd-10（CR Agent instructions 与部署副本逐字一致 + imported Skills 取用路径）与 cmd-11（imported Skill 实际内容 + 两个业务调用方 Agent instructions 与仓库目标逐字一致）断言，agent 不写平台配置（SDD §9 `scope_in` 未含平台侧写入与平台配置变更）；前置未完成时 TASK-09 不 done、按缺失环境前提报告所需人工动作，不以 `pending-deploy` 或路径/ref 一致充作 AC-B14 通过；该前置开发期即可执行，不依赖 merge/writeback；范围外既有漂移逐条记录、不计入本次范围漂移项（PRD §6 口径） | revert TASK-09（部署副本与台账） |
| R9 | 共享文件跨 TASK 编辑（`crctl.mjs` 被 TASK-01/03/04/06 编辑；`crctl.test.mjs` 被 TASK-01/06 编辑；SKILL 文本被 TASK-07/08 编辑） | 依赖图约束顺序编辑；每个 TASK commit 自含其新增测试；revert 按逆拓扑顺序 | 逆拓扑回滚顺序：TASK-10 → TASK-09 → TASK-08 → TASK-07 → TASK-06 → TASK-05 → TASK-04 → TASK-03 → TASK-02 → TASK-01 |
| R10 | Windows 基线失败被误当本 CR 回归 | multica `./internal/daemon/` 包内 `TestRegisterTaskReposAllowsProjectOnlyURL` 在本机因临时仓路径超出 Windows MAX_PATH 而失败（本轮只读实测原文见 `test-evidence/`），故 cmd-08 使用定向 `-run` 名集、不声明该包全量通过；本计划不把该包全量命令设为关键证据 | 与实现无关，不回滚；仅在 test-report 未覆盖风险段记录 |
| R11 | `delegation-contract.test.mjs` 在本轮基线即红（上游 `steered` 漂移），被误当本 CR 引入或反向绕过 | 本轮只读实测：19 用例中 18 pass / 1 fail，唯一失败为「枚举对齐」——平台 `server/internal/handler/admission.go` 的 `DispatchStatus` 现有 `blocked,coalesced,deferred,queued,steered`，而 `cr-prompts-revised/delegation-contract.md` 成功集合仍为 `coalesced,deferred,queued`；该字面量由上游提交 `e2f4a2203`（`MUL-7631`）引入，不属本工作区任一 CR。处置：TASK-09 把仓库声明（合同正文 + 四份提示词与 `bak/` 维护副本内联正文）对齐到平台现有事实并让 cmd-09 转绿；只改文本声明，**不改** `admission.go`、不新增平台 status、不改合同判定语义之外的内容 | revert TASK-09（文本）；`admission.go` 零改动故无代码回退 |

整体回滚顺序见 R9；知识库侧仅是 CR 文档，随各 TASK commit 一并回退。单 TASK commit 均自含其新增测试；被消费的共享改动（TASK-03 的 `expect`/`sampleCommitState`、TASK-01 的 `bindTaskWorkspace`）按逆拓扑先回退下游消费者再回退生产者，单点 revert 不破坏其余 TASK 的构建与测试。

## 5. 验收与发布策略

- **环境静态前提**：无需常驻服务、浏览器或数据库。验收环境 = 三仓 CR worktree（Pipeline `resources[].worktreePath`，`workspace inspect` 为 healthy 且 `dirty=false` 即就绪）+ Node ≥18（本机 v24.15.0）+ Git + Go 1.26（模块缓存在本机）+ pnpm 11。engineering-docs 测试需先在 `skills/shared/engineering-docs/scripts/` 安装 `node_modules`（该目录 `.gitignore` 已忽略 `node_modules/`、`dist/`、`.tmp-test/`，安装后 worktree 仍 `dirty=false`）。multica/Go 测试使用本机模块缓存，不访问网络。
- **环境 owner 与可获得性**：owner 为 dev-agent；三仓 CR worktree 由 Pipeline resources 建立并随 CR 存续（merge finalize 后以 `workspace inspect` 重取，不持久化副本）；缺失或不健康时报告所需建立动作，不自动补齐、不猜路径。
- **readiness 证据**：复用证据命令表既有 `cmd-NN`，不新增命令行、不放宽「验收证据 ↔ 证据ID」双向唯一映射——tools/Node 与测试入口就绪由 `cmd-01` 证明；multica/Go 工具链就绪由 `cmd-08` 证明；engineering-docs vitest 入口（含 `node_modules` 安装）就绪由 `cmd-07` 证明；平台只读查询通道（`multica` CLI）就绪由 `cmd-10` 证明。
- **缺失时处置**：环境前提无法建立时按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（该标签的唯一详细事实源是 `implement-code`，此处只引用不复述）。
- **证据范围（CR-2026-073 FR-6/FR-8）**：本计划不使用 `go test ./...`、`make test` 等全仓命令作为关键证据或必须通过项；每条 `cmd-NN` 的真实运行范围逐行写明（单文件 / 单包定向名集 / 单目录），范围小于全仓的命令不在任何产物中表述为「全量通过」。`cmd-08` 只覆盖 `./internal/daemon/` 包内定向用例名集，不声称该包全量绿（R10）。本 CR 唯一按 SDD §5.2/SDD-CLOSE-09 批准口径执行的聚合门禁是 `cmd-12`（`node suite-gate.mjs --run`：逐文件 spawn、manifest 集合与 case 基线判定），其真实运行范围 = tools `skills/shared/crctl/scripts/test/` 测试文件集合（SDD §9 `scope_in` 内的测试文件），不扩展为多仓全量。
- **发布策略**：零新依赖 CLI，无 feature flag；review-dev-plan PASS → 人工开发启动确认（Ray，仅人类在交互式终端执行 `crctl approve`）→ implement-code → write-test-report → `workspace-freshness` → review-code → 人工代码审批（Ray）→ 交付回写（delivery-agent）。FR-15 第③④步的平台侧同步（本 CR 涉及的 imported Skills、四份 CR Agent instructions 与规划/竞品两个业务调用方 Agent instructions）**由有权限的人类 owner（Ray，平台管理员）执行，是 TASK-09 验收的前置**：TASK-09 仓库侧收敛完成后，人类 owner 按卡内同步清单逐条把仓库目标文本推送到平台，再由只读的 `cmd-10`/`cmd-11` 断言线上内容与仓库目标逐字一致并归档 `test-evidence/`。agent 不写平台配置（SDD §9 `scope_in` 未含平台侧写入或平台配置变更）。前置未完成时 TASK-09 不 done，按缺失环境前提报告所需人工动作，**不以 `pending-deploy` 或路径/ref 一致充作 AC-B14 通过**；该前置开发期即可执行，不依赖 merge/writeback，也不要求先把本 CR 合入 trunk。
- **回退策略**：先恢复安全显式 workspace 调用（停用归一，回到显式根模式），再撤绑定发布；撤业务入口前停止调用并收敛在途事务，无等价入口则暂停正式落盘、保留草稿；不迁移或重写已有 CR/账本/指纹/review attempt。

## 6. 两张稳定表

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-01 两条 CR 入口使用可信预检 | §2.2 `execution_context` 解析、§3.3 daemon 接口、§4.1 绑定解析 | CR-2026-075-TASK-02（关联 TASK-01） | cmd-08 | revert TASK-02；TASK-09 消费绑定对的部署面，按逆拓扑先 09 后 02 |
| FR-02 task 环境隔离与入口一致 | §2.1 三元组有效性与成对写入/清除、§4.1 发布点、§4.6 launcher/Git 环境泛化 | CR-2026-075-TASK-02（关联 TASK-01） | cmd-01 + cmd-08 | 同 FR-01 |
| FR-03 公共 CLI 首次归一与失败关闭 | §1.1 边界术语、§2.1、§3.2、§4.2 `bindTaskWorkspace` | CR-2026-075-TASK-01 | cmd-01 | revert TASK-01（含其同批 `crctl.test.mjs` 用例） |
| FR-04 调用方同 run 一次本地纠正 | §4.2 纠正约定、§4.6 提示对齐 | CR-2026-075-TASK-01（关联 TASK-08） | cmd-01 + cmd-05 | revert TASK-01；TASK-08 仅文本合同与回放断言，可独立回退 |
| FR-05 校验触发及能力范围真实 | §3.4 维度报告层、§4.6 触发条件改写 | CR-2026-075-TASK-06 | cmd-01 + cmd-06 | revert TASK-06（含其 validate 分支用例）；既有 artifact/schema 分支零改动故无下游 |
| FR-06 文档生成按所属类型合同 | §2.3 两个业务 payload、§4.4 确定性转换、§4.6 删除通用委派 | CR-2026-075-TASK-07（关联 TASK-04、TASK-05） | cmd-07 + cmd-02 + cmd-03 | revert TASK-07；TASK-04/05 的模块不反向依赖其文本，可后撤销 |
| FR-07 日期按文档/字段生成 | §4.7 唯一规则与两处实现 | CR-2026-075-TASK-07（关联 TASK-04、TASK-05） | cmd-07 + cmd-02 + cmd-03 | 同 FR-06 |
| FR-08 索引路径及责任唯一 | §2.4 路径权威与单索引解析、§4.4 索引文本生成 | CR-2026-075-TASK-04（关联 TASK-05、TASK-07） | cmd-02 + cmd-03 + cmd-07 | 逆拓扑：revert TASK-04 → TASK-05 → TASK-07 |
| FR-09 两个业务专用受控操作 | §3.1 命令面与参数面、§4.3 执行骨架、§4.4 转换职责分离 | CR-2026-075-TASK-04（关联 TASK-05、TASK-03） | cmd-02 + cmd-03 | revert TASK-04 → TASK-05；TASK-03 是其上游生产者，须最后回退 |
| FR-10 规划确认、冲突与重放 | §2.3 规划 payload 与回执、§4.4、§4.5 判定顺序 | CR-2026-075-TASK-04 | cmd-02 | revert TASK-04（含 `planning-entry.test.mjs`） |
| FR-11 竞品确认、冲突与重放 | §2.3 竞品 payload 与回执、§4.4、§4.5 判定顺序 | CR-2026-075-TASK-05 | cmd-03 | revert TASK-05（含 `competitive-report.test.mjs`）；与 TASK-04 无互相依赖 |
| FR-12 一致性、错误闭包与事务恢复 | §4.3、§4.5（含 §4.5.2 key、§4.5.4 第 2 步锁内比对）、§5.1/§5.3 锁内取样 | CR-2026-075-TASK-03（关联 TASK-04、TASK-05） | cmd-04 + cmd-01 + cmd-02 + cmd-03 | 逆拓扑：先 revert TASK-04、TASK-05（消费者），再 revert TASK-03 |
| FR-13 调用登记、命令示例与输入兼容 | §4.6（12 处 CR-ID、矩阵/Agent 定点登记、版本口径） | CR-2026-075-TASK-08 | cmd-01 + cmd-05 + cmd-06 | revert TASK-08（文本合同，无下游代码消费者） |
| FR-14 绑定验证后收敛重复提示 | §4.6 收敛范围、§4.9 门槛 | CR-2026-075-TASK-08（关联 TASK-01、TASK-02） | cmd-05 + cmd-06 | revert TASK-08；门槛依赖 TASK-01/02，回退后提示恢复原样 |
| FR-15 部署与安全回退 | §4.8 交付与回退顺序、SDD-CLOSE-10 生效版本最小证据 | CR-2026-075-TASK-09（关联 TASK-10） | cmd-09 + cmd-10 + cmd-11 | revert TASK-09（部署副本与台账）；平台侧同步按 TASK-09 同步清单以同一份仓库目标文本回退（由人类 owner 执行），无平台代码/配置结构回退动作 |
| FR-16 可归因测试与证据 | §5.2 验证落点与可达性、§5.3 风险 | CR-2026-075-TASK-10 | cmd-01 + cmd-02 + cmd-03 + cmd-04 + cmd-05 + cmd-06 + cmd-07 + cmd-08 + cmd-09 + cmd-10 + cmd-11 + cmd-12 | revert TASK-10（证据与报告）；实现仓按 §4 R9 逆拓扑回退 |

FR-04 的观测面说明（不新增命令行，不放宽映射）：本行由两段既有证据闭合——`cmd-01` 观测 CLI 侧边界（旧显式入口缺根报 `WORKSPACE_REQUIRED`、补已确认显式根后同调用成功、`BAD_ARGS` 与空串/裸旗标不在本地纠正集合、第二次失败不自动重试）；`cmd-05` 的 `caller-contract.test.mjs` 承载 SDD §5.2 规定的节点回放向量：以调用方合同文本为输入，在 fixture 中按「首次缺根失败（预检零业务写入已证明）→ 同 run 仅补参一次 → 第二次失败不重试并上报」的执行步骤驱动真实 CLI 调用，断言同 run 调用计数（最多两次调用、最多一次纠正）与失败路由（第二次失败后无第三次调用、无恢复委派），回放记录随 `cmd-05` 原始输出归档 `test-evidence/`；TASK-08 负责合同文本与回放断言同批落地，TASK-10 复跑归档。不新建重试服务或测试框架。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/crctl.test.mjs"] | 900 |
| cmd-02 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/planning-entry.test.mjs"] | 600 |
| cmd-03 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/competitive-report.test.mjs"] | 600 |
| cmd-04 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/durable-tx.test.mjs"] | 600 |
| cmd-05 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/caller-contract.test.mjs","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs"] | 300 |
| cmd-06 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/contract-scan.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/lint-prompts.test.mjs"] | 300 |
| cmd-07 | tools | skills/shared/engineering-docs/scripts | node | ["node_modules/vitest/vitest.mjs","run"] | 600 |
| cmd-08 | multica | server | go | ["test","./internal/daemon/","-count=1","-v","-run","Test(InjectTaskCRWorkspaceEnv|DaemonEnvBuildHasNoConfigFirstRootFallback|PreparePipelineTaskHydratesMachineLocalPaths|ConfigurePipelineGitEnvironment|ConfigureTaskGitEnvironment|InstallPipelineCrctlLauncher|InstallCrctlLauncher|ResolveTaskWorkspaceBinding|ParseExecutionContext|TaskWorkspaceBinding)"] | 900 |
| cmd-09 | multica | . | node | ["--test","cr-prompts-revised/test/delegation-contract.test.mjs"] | 300 |
| cmd-10 | multica | . | node | ["-e","const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CRLF=String.fromCharCode(13,10);const LD=p=>fs.readFileSync(p,'utf8').split(CRLF).join(NL);const H=t=>cr.createHash('sha256').update(t).digest('hex');const TR=x=>x.replace(new RegExp(NL+'+$'),'');const bad=[];const PROMPTS=['requirement-writer','dev-agent','quality-reviewer-agent','cr-coordinator-agent'];for(const n of PROMPTS){const p='cr-prompts-revised/'+n+'.md';if(!fs.existsSync(p)){bad.push('部署副本缺失: '+p);continue;}const t=LD(p);if(t.split('--workspace <workspace>').length>1)bad.push('短提示未收敛（仍含逐命令 workspace 示例）: '+p);if(t.length<800)bad.push('部署副本疑似被截断: '+p);if(t.indexOf('CR-ID')<0)bad.push('收敛误删显式 CR-ID: '+p);console.log('deployment-copy '+n+' sha256='+H(t));}const SK={'crctl':'skills/shared/crctl','validate-doc':'skills/shared/validate-doc','engineering-docs':'skills/shared/engineering-docs','cr-review-record':'skills/cr/cr-review-record','review-code':'skills/develop/review-code','review-dev-plan':'skills/develop/review-dev-plan','review-tech-design':'skills/develop/review-tech-design','write-dev-tasks':'skills/develop/write-dev-tasks','write-tech-design':'skills/develop/write-tech-design','review-requirement':'skills/requirement/review-requirement','write-planning-entry':'skills/planning/write-planning-entry','planning-draft':'skills/planning/planning-draft','write-competitive-report':'skills/competitive/write-competitive-report','requirement-register':'skills/requirement/requirement-register'};const list=JSON.parse(cp.execFileSync('multica',['skill','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of Object.keys(SK)){const e=list.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 imported Skill: '+n);continue;}const o=(e.config&&e.config.origin)||{};if(o.repo!=='AI-First-tools'||o.ref!=='main'||o.path!==SK[n])bad.push('取用路径漂移: '+n+' '+JSON.stringify(o));else console.log('imported-skill '+n+' AI-First-tools@main/'+o.path);}const ag=JSON.parse(cp.execFileSync('multica',['agent','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of PROMPTS){const e=ag.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 Agent: '+n);continue;}const live=String(e.instructions||'').split(CRLF).join(NL);const t=LD('cr-prompts-revised/'+n+'.md');if(TR(live)!==TR(t))bad.push('线上 instructions 与部署副本不一致: '+n+' live='+H(live)+' target='+H(t));else console.log('agent-in-sync '+n+' sha256='+H(live));}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-10 ok: 部署副本收敛与 imported Skills 取用路径零漂移；四份 CR Agent 线上 instructions 与部署副本逐字一致（LF）');"] | 300 |
| cmd-11 | tools | . | node | ["-e","const fs=require('fs'),cp=require('child_process'),cr=require('crypto');const NL=String.fromCharCode(10),CRLF=String.fromCharCode(13,10);const LD=p=>fs.readFileSync(p,'utf8').split(CRLF).join(NL);const H=t=>cr.createHash('sha256').update(t).digest('hex');const TR=x=>x.replace(new RegExp(NL+'+$'),'');const bad=[];const SK={'crctl':'skills/shared/crctl','validate-doc':'skills/shared/validate-doc','engineering-docs':'skills/shared/engineering-docs','cr-review-record':'skills/cr/cr-review-record','review-code':'skills/develop/review-code','review-dev-plan':'skills/develop/review-dev-plan','review-tech-design':'skills/develop/review-tech-design','write-dev-tasks':'skills/develop/write-dev-tasks','write-tech-design':'skills/develop/write-tech-design','review-requirement':'skills/requirement/review-requirement','write-planning-entry':'skills/planning/write-planning-entry','planning-draft':'skills/planning/planning-draft','write-competitive-report':'skills/competitive/write-competitive-report','requirement-register':'skills/requirement/requirement-register'};const list=JSON.parse(cp.execFileSync('multica',['skill','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of Object.keys(SK)){const e=list.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 imported Skill: '+n);continue;}const g=JSON.parse(cp.execFileSync('multica',['skill','get',e.id,'--with-content','--output','json'],{encoding:'utf8',maxBuffer:512*1024*1024}));const parts=[{p:'SKILL.md',c:String(g.content||'')}].concat((g.files||[]).map(f=>({p:f.path,c:String(f.content||'')})));let nBad=0;for(const it of parts){const p=SK[n]+'/'+it.p;if(!fs.existsSync(p)){bad.push('仓库目标缺失: '+p);nBad++;continue;}if(TR(it.c.split(CRLF).join(NL))!==TR(LD(p))){bad.push('实际 Skill 文件与仓库目标不一致: '+p);nBad++;}}if(!nBad)console.log('skill-in-sync '+n+' files='+parts.length+' sha256='+H(parts.map(x=>x.p+':'+H(x.c.split(CRLF).join(NL))).join(NL)));}const AG={'product-planning-agent':'agents/product-planning-agent.md','competitive-analyst-agent':'agents/competitive-analyst-agent.md'};const ag=JSON.parse(cp.execFileSync('multica',['agent','list','--output','json'],{encoding:'utf8',maxBuffer:64*1024*1024}));for(const n of Object.keys(AG)){const e=ag.filter(x=>x.name===n)[0];if(!e){bad.push('平台未登记 Agent: '+n);continue;}const live=String(e.instructions||'').split(CRLF).join(NL);const t=LD(AG[n]);if(TR(live)!==TR(t))bad.push('线上 instructions 与仓库目标不一致: '+n+' live='+H(live)+' target='+H(t));else console.log('agent-in-sync '+n+' sha256='+H(live));}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-11 ok: 本 CR 涉及 imported Skills 全文件与规划/竞品两个业务调用方 Agent instructions 均与仓库目标逐字一致（LF）');"] | 600 |
| cmd-12 | tools | . | node | ["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"] | 3600 |

命令算法唯一事实源为本表行。真实运行范围与观测面逐条说明：

- `cmd-01`：单文件 `crctl.test.mjs`（本轮实测 237 用例 / 172s，同目录、`node --test`）。观测 A 段 CLI 归一与失败关闭（显式模式、绑定模式、同真实目录/别名接受、异根 `WORKSPACE_CONTEXT_MISMATCH`、空串/裸旗标与缺根 `WORKSPACE_REQUIRED`、help 不受影响、Windows 空格/中文路径 argv 完整性）与本 CR 新增的 validate 维度层分支；`crctl.test.mjs` 新增用例按 SDD §5.2 的 B2/B5～B7、B9～B13、B16 落点写入。不声称覆盖 crctl 全部子命令行为。
- `cmd-02`/`cmd-03`：新增单文件（同目录、`node --test`），观测规划/竞品各自入口的命令面、范围拒绝、确认与冲突、首次写入出口、重放与第三方值、CAS 与中断恢复；`cmd-02` 另含 B15-a（跨日身份）与 B18-a（完成提交唯一来源）向量，`cmd-03` 另含 B15-b（合法覆盖）向量。
- `cmd-04`：单文件 `durable-tx.test.mjs`，观测共享原语的 `expect` 锁内比对（B17-a/B17-b）与 `sampleCommitState` 锁内取样（B18-b/B18-c/B18-d），含既有恢复语义回归与五个既有 `recoverLedgerCommand(ws, key)` 两参调用点（`crctl.mjs:1201/1871/2093/2594/2852` 零改动）的恢复兼容回归（默认路径不传 `expect`，行为与现状逐字一致）；`cmd-01` 复跑提供既有调用的端到端兼容证据。不声称覆盖 `lib/` 全部模块。
- `cmd-05`：两个单文件合并运行——`caller-contract.test.mjs`（调用方合同：业务参数与阶段说明保留、`--workspace` 重复示例收敛后调用形态仍合法；**另含 SDD §5.2 的节点回放向量**：输入 = 调用方合同文本与 TASK-01 固定的 CLI 边界，步骤 = 在 fixture 中以真实 CLI 执行「首次缺根失败 → 零业务写入断言 → 同 run 补参一次成功」，另以第二次失败变体断言同 run 调用计数不超过两次、不出现第三次调用与恢复委派，失败路由落回原异常路径）与 `pipeline-structure.test.mjs`（Pipeline 模板受控节点结构）；回放记录随本命令原始输出归档 `test-evidence/`。
- `cmd-06`：四个单文件合并运行——`contract-scan.test.mjs`、`check-skill-matrix.test.mjs`、`check-agents-contract.test.mjs`、`lint-prompts.test.mjs`（合同一致性、矩阵/Agent 登记、提示 lint）。
- `cmd-07`：`skills/shared/engineering-docs/scripts` 目录下 vitest 全量（该包自身范围的测试入口）。观测工程文档侧 `today(now)` 北京时间渲染与跨宿主时区向量；范围是该 TS 包自身的测试集，不声称 tools 仓全量。
- `cmd-08`：multica `./internal/daemon/` 单包 + 定向 `-run` 名集（`-v` 输出各用例 `--- PASS` 行）。名集同时含既有锚点用例（`TestInjectTaskCRWorkspaceEnv*`、`TestDaemonEnvBuildHasNoConfigFirstRootFallback`、`TestPreparePipelineTaskHydratesMachineLocalPaths`、`TestConfigurePipelineGitEnvironment`、`TestInstallPipelineCrctlLauncher`）与 TASK-02 固定的新增用例名前缀（`ResolveTaskWorkspaceBinding`、`ParseExecutionContext`、`TaskWorkspaceBinding`、`ConfigureTaskGitEnvironment`、`InstallCrctlLauncher`）。用例名由 TASK-02 验收条件固定，改名即视为证据失效（观测面 < 声称面）；不声称该包全量通过（R10）。
- `cmd-09`：multica `cr-prompts-revised/test/delegation-contract.test.mjs` 单文件（该测试按 `admission.go` 枚举源与 `bak/README.md` 的维护集合解析）。本轮基线为 19 用例 / 18 pass / 1 fail（失败项＝合同成功集合缺平台现有 `steered`，见 R11）；TASK-09 对齐声明后须 19/19 绿。观测面＝合同正文与四份提示词/维护副本的逐字一致与枚举对齐，不声称覆盖 CR Agent 全部行为。
- `cmd-10`：multica CR worktree 内只读内联脚本：①四份部署副本存在性、非空、短提示已收敛（无逐命令 `--workspace <workspace>` 示例）且未误删显式 CR-ID，并输出各副本 LF sha256；②经 `multica skill list --output json` 输出本 CR 涉及 14 个 imported Skill 的**取用路径台账**并断言 `origin.repo=AI-First-tools` / `origin.ref=main` / `origin.path` 与本 CR 声明的仓库路径一致；③经 `multica agent list --output json` **读取四份线上 Agent instructions 正文并与 `cr-prompts-revised/*.md` 逐字比对（LF 规范化后全等）**，不一致即非零退出并打印两侧 sha256，一致则输出 in-sync sha256。该命令只读，不写平台、不写仓库；平台侧同步（人类 owner 前置）未完成时本命令必然红，不得以路径/ref 一致充当通过。
- `cmd-11`：tools CR worktree 内只读内联脚本：①经 `multica skill get <id> --with-content --output json` 读取本 CR 涉及 14 个 imported Skill 的**全部实际内容**（`content` 即 SKILL.md 正文 + `files[]` 各附带文件正文），逐文件与仓库 `skills/**/<文件相对路径>` 逐字比对（LF 规范化后全等，任一不一致或仓库目标缺失即非零退出）；②读取规划/竞品两个业务调用方 Agent（`product-planning-agent`、`competitive-analyst-agent`）的线上 instructions，与 `agents/{product-planning-agent,competitive-analyst-agent}.md` 逐字比对（LF 规范化后全等），覆盖 AC-B14 的两业务调用方。该命令只读，不写平台、不写仓库。
- `cmd-12`：tools 仓根执行 SDD §5.2/SDD-CLOSE-09 指定的聚合门禁 `node skills/shared/crctl/scripts/test/suite-gate.mjs --run`：逐文件 spawn（不读外部报告）、磁盘文件集合 ≡ `gate-registry.json#manifest.files`、每文件顶层用例数 ≥ `manifest.cases` 基线；任一不可判即硬失败。真实运行范围 = tools `skills/shared/crctl/scripts/test/` 测试文件集合，不上到多仓全量。

新增测试文件 `planning-entry.test.mjs`、`competitive-report.test.mjs` 必须登记进 `gate-registry.json#manifest`（`dep-26`），并由 SDD §5.2/SDD-CLOSE-09 批准的聚合门禁 `cmd-12`（`node suite-gate.mjs --run`）验证：磁盘集合 ≡ manifest 文件集、新增/既有文件的顶层用例数不低于 manifest 基线；不以其他未获批的全仓命令替代。tools 侧测试一律先规范化行尾（`\r\n → \n`），跨行匹配失败硬失败（工程纪律 #1）；新增用例不得绕过 `controlledGit` 直接 `spawnSync('git', …)` 取证。FR-14 的「保留项未误删」与 `cmd-10` 的「保留项」边界按 SDD §8/§4.9 保留为 review-code 人工检查项，`cmd-06`/`cmd-10` 的静态断言不代替该检查。

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-A1 Pipeline 有效绑定下首次归一成功、无 `WORKSPACE_REQUIRED`/重试/恢复委派 | §4.1 发布 + §4.2 归一 | CR-2026-075-TASK-01 | cmd-01 + cmd-08 |
| AC-A2 同环境直接 `node` 与 launcher 同结果、不能绕过绑定 | §4.1 launcher + `GIT_CONFIG_GLOBAL` | CR-2026-075-TASK-02 | cmd-08 |
| AC-A3 普通 Issue 的 `execution_context` 触发预检绑定，不依赖 `PipelinePrompt` 非空 | §2.2、§4.1 | CR-2026-075-TASK-02 | cmd-08 |
| AC-A4 缺失/重复/冲突/非法上下文、无根/歧义/越界/坏 worktree 一律停止或零写入失败 | §2.2、§4.1 | CR-2026-075-TASK-02 | cmd-08 |
| AC-A5 同真实目录/合法别名接受；异根 `WORKSPACE_CONTEXT_MISMATCH` 且绑定不被覆盖 | §4.2 | CR-2026-075-TASK-01 | cmd-01 |
| AC-A6 独立 CLI/bootstrap 显式根有效；仅 task ID 不误绑定；旧 `CRCTL_WORKSPACE` 不作 fallback；缺根 `WORKSPACE_REQUIRED`；help 可用 | §4.2 第 3 条 | CR-2026-075-TASK-01 | cmd-01 |
| AC-A7 并发 task 隔离、`custom_env` 后注入、无绑定清旧值、配置不可覆盖绑定 | §4.1 写入点 + §7 | CR-2026-075-TASK-02 | cmd-08 |
| AC-A8 Windows 空格/中文路径、POSIX 与 Git `--`/`--cwd` 的 argv 完整，不重拼 shell 字符串；Windows 用例真机执行 | §4.2 + §5.2 | CR-2026-075-TASK-01 | cmd-01 |
| AC-B1 旧可信入口遗漏根且预检零业务写入时，同节点同 run 只补参一次；与 A1 首次归一区分 | §4.2 纠正约定 | CR-2026-075-TASK-01（回放断言由 TASK-08 的 cmd-05 承载） | cmd-05 + cmd-01 |
| AC-B2 额外 `validate prd.md` 的 `UNKNOWN_ARTIFACT` 后完成原 PRD 重读自检及后续登记/发布 | §4.6 | CR-2026-075-TASK-06 | cmd-01 |
| AC-B3 第二次失败、权限/路径/绑定冲突或写入不明停止自动纠正，走原异常或合法事务恢复 | §4.2、§4.3 | CR-2026-075-TASK-01（回放断言由 TASK-08 的 cmd-05 承载） | cmd-05 + cmd-01 |
| AC-B4 短提示仍含上下文/CR-ID/业务输入输出/职责/发布合同，显式与 bootstrap 说明未误删 | §4.6 | CR-2026-075-TASK-08 | cmd-05 |
| AC-B5 validate-doc/AGENTS/PRD/SDD 无 blanket 自动调用承诺，无额外通用校验闸门 | §3.4、§4.6 | CR-2026-075-TASK-06 | cmd-01 + cmd-06 |
| AC-B6 未声明维度 WARN 且明确未检查；必需配置无效/违反规则仍失败 | §3.4 | CR-2026-075-TASK-06 | cmd-01 |
| AC-B7 合法既有评审 YAML 分支有效；`prd.md`/`sdd.md` 仍 `UNKNOWN_ARTIFACT` | §3.4 | CR-2026-075-TASK-06 | cmd-01 |
| AC-B8 common 日期渲染匹配原 schema、覆盖北京时间跨日与宿主时区差异；业务 timestamp 保留 | §4.7 | CR-2026-075-TASK-07 | cmd-07 + cmd-02 + cmd-03 |
| AC-B9 已确认规划/竞品按各自字段/id/章节落盘，不调用未支持通用类型；未确认零写入 | §2.3、§4.4、§4.6 | CR-2026-075-TASK-04（竞品同构由 TASK-05 产出） | cmd-02 + cmd-03 |
| AC-B10 只维护指定 yml/yaml 索引；无合同不创建，无双索引、不全仓改名 | §2.4 | CR-2026-075-TASK-04（竞品同构由 TASK-05 产出） | cmd-02 + cmd-03 |
| AC-B11 七个指定 Skill 的十二处漏项及范围内全部实际漏项补齐 CR-ID；真实调用不在缺位置参数处 `BAD_ARGS` | §4.6 | CR-2026-075-TASK-08 | cmd-01 + cmd-05 + cmd-06 |
| AC-B12 版本输入规范化至无前缀值；`unassigned`/禁止值/prerelease 边界维持 | §2.3、§4.6 | CR-2026-075-TASK-08 | cmd-06 |
| AC-B13 grant/TTY、写入前提与现实现一致；除限定业务调用登记外不放宽授权/审批/业务范围 | §4.6 | CR-2026-075-TASK-08 | cmd-06 |
| AC-B14 仓库、维护部署副本、实际 imported Skills 与 Agent instructions 生效版本一致，覆盖规划/竞品调用方 | §4.8、SDD-CLOSE-10 | CR-2026-075-TASK-09（关联 TASK-10） | cmd-09 + cmd-10 + cmd-11 |
| AC-B15 首次成功与同意图重放回执字段/提交/身份一致，不重复登记，合法覆盖与重放分支互不代替，首次写入有独立出口 | §2.3、§4.5 | CR-2026-075-TASK-04（竞品同构由 TASK-05 产出） | cmd-02 + cmd-03 |
| AC-B16 越界、任意文件清单或超出业务范围的输入在业务写入前拒绝 | §4.3 第 4 步 | CR-2026-075-TASK-04（竞品同构由 TASK-05 产出） | cmd-02 + cmd-03 |
| AC-B17 候选生成后并发变化/恢复遇第三值返回既有 CAS/冲突结果，不覆盖、不补账 | §4.3 第 7 步、§4.5 | CR-2026-075-TASK-03（业务侧由 TASK-04/05 消费） | cmd-04 + cmd-02 + cmd-03 |
| AC-B18 中断非零退出、stderr 有既有错误/合法恢复、stdout 无成功回执；收敛后才 `phase=complete` | §4.3、§4.5 | CR-2026-075-TASK-03（业务侧由 TASK-04/05 消费） | cmd-04 + cmd-02 + cmd-03 |
| AC-B19 必需索引但入口不可用时中止完整执行，仅保留模板参考/草稿，不漏索引报完成 | §2.4、§4.4 | CR-2026-075-TASK-04（关联 TASK-07） | cmd-02 + cmd-07 |
| AC-B20 两角色矩阵/Agent/Skill/必要索引一致，限定各自操作；不宣称子命令级机器授权 | §4.6 | CR-2026-075-TASK-08 | cmd-06 |

AC-B14 的观测面边界（不新增命令行）：`cmd-09` 断言合同正文与四份提示词/维护副本逐字一致且成功集合对齐平台枚举（基线为 1 项红、由 TASK-09 对齐 `steered` 后转绿，见 R11）；`cmd-10` 读取四份 CR Agent 的线上 instructions 并与 `cr-prompts-revised/*.md` 逐字比对（LF 规范化后全等，不一致即非零退出），同时断言本 CR 涉及 14 个 imported Skill 的取用路径台账；`cmd-11` 读取这 14 个 imported Skill 的**全部实际内容**（SKILL.md 正文 + `files[]` 附带文件，逐文件与仓库目标比对）与规划/竞品两个业务调用方 Agent 的线上 instructions，断言与仓库目标逐字一致。平台侧同步由有权限的人类 owner（Ray）按 TASK-09 同步清单执行，是 TASK-09 验收的前置（开发期即可执行，不依赖 merge/writeback）；前置完成后三条命令须全部转绿。未完成同步时 TASK-09 不 done、按缺失环境前提报告所需人工动作，**不以 `pending-deploy` 或路径/ref 一致充作 AC-B14 通过**，也不在任何产物中表述为已生效。

## 8. 修订记录

| 日期 | 版本 | 说明 |
| --- | --- | --- |
| 2026-10-02 | 0.1 | 首版：承接已审批 `sdd.md` v0.4，落 M1～M8 里程碑、TASK-01～TASK-10 依赖图、资源分工、R1～R10 风险与逆拓扑回滚、验收与发布策略、两张稳定表与 28 行 AC 覆盖矩阵；TASK 编号与 `tasks/_index.yml` 的 id 集一致 |
| 2026-10-03 | 0.2 | review-dev-plan attempt 1 BLOCK 回修（B-01～B-06）：①既有 `recoverLedgerCommand(ws,key)` 保持两参与无 `expect` 兼容语义、仅做取样器接线，业务摘要/txId 比对归新增 `recoverBusinessLedgerCommand`（TASK-04/05），M3/R3 与 TASK-03 同步，FR-12 证据补 `cmd-01`；②TASK-05 增加对 TASK-04 的实现依赖（唯一骨架），§2 依赖图与 `_index.yml` 同步；③TASK-02/TASK-09 的受控 `git status` argv 改为 `--cwd <repo worktree>` + `--workspace <operational workspace>`；④FR-04/AC-B1/B3 证据映射补 `cmd-05` 节点回放（输入、步骤、同 run 调用计数与失败路由断言、归档责任）；⑤FR-15/AC-B14 落实人类 owner 平台侧同步前置与 `cmd-10`/`cmd-11` 实际内容/版本比对，去掉 `pending-deploy` 充作通过的表述；⑥新增 `cmd-12`（`node suite-gate.mjs --run`）绑定 SDD-CLOSE-09 的聚合门禁，FR-16 证据扩到 `cmd-01`～`cmd-12` |
