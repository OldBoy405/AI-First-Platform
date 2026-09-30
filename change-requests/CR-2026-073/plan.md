---
id: CR-2026-073-plan
type: PLAN
cr-ref: CR-2026-073
sdd-ref: "change-requests/CR-2026-073/sdd.md"
target-version: 0.46
status: draft
created: 2026-09-30T13:05:00+08:00
updated: 2026-09-30T13:25:00+08:00
---

# CR-2026-073 开发计划

## 1. 交付里程碑

| 阶段 | 交付 | 估算 |
|---|---|---|
| 设计 | 已批准 PRD/SDD 对齐、四组接口与验证范围确认 | 0.5 人天 |
| 实现 | G1 测试缓冲/分类、G2 审计根/actor、G3 终态去重与隔离回归、G4 三个开发 Skill 口径 | 2 人天 |
| 测试 | 定向运行八个 cmd-NN；C 项另取独立 reviewer 的实际案例 verdict 与真实上游同步全量日志/基线；运行既有 prompt/matrix 校验 | 1 人天 |
| 联调 | 三仓临时 origin 夹具下核查入口/重放；无真实共享服务 | 0.25 人天 |
| 发布 | 独立评审、人工审批后由后续 Pipeline 合入/回写；本阶段不建立交付 TASK | 0.25 人天 |

合计 **4 人天 / 32h**（Ray 开发与测试角色；人工门禁时间不计）。计划层只给估算，不在此规定实现微步骤。

## 2. 任务依赖图

- G1 → `CR-2026-073-TASK-01`：A，`runTestPlan` 与定向黑盒回归；独立。
- G2 → `CR-2026-073-TASK-02`：B，三个 CLI adapter 的 install-root 审计及事前 actor；产出 G3 的稳定根/身份契约。
- G3 → `CR-2026-073-TASK-03`：B，依赖 TASK-02 的根与身份，完成终态业务事件去重、三入口/清理/重放夹具回归。
- G4 → `CR-2026-073-TASK-04`：C，三个 develop Skill 的批准范围/证据约束、独立 reviewer 案例和上游同步证据核查；独立。

每个变更组恰一主责 TASK；G1/G2/G3/G4 的任务编号连续，无 merge/writeback/archive 流程 TASK。

## 3. 资源与分工

Ray (`owners.development.id` 与 `owners.test.id` 均为 `a0e71a32-509d-4ee9-aea4-d086a5b1ff93`)：TASK-01 8h、TASK-02 8h、TASK-03 10h、TASK-04 6h；同一人的双角色分别负责真实实现与测试报告。独立 `quality-reviewer-agent` 评审 plan/TASK 与代码，不由作者自评。只操作 `workspace inspect` 返回的 tools 与 KB CR worktree；multica 仓仅只读核对 `CUSTOM.md` 上游同步规则，不改 multica 代码。

## 4. 风险与回滚策略

| 风险 | 缓解与回滚 |
|---|---|
| 10 MiB 的单段溢出被误当非零/timeout，或截断片段被发布为证据 | TASK-01 黑盒验证边界、四类 canonical 原字节；失败撤销 TASK-01 变更及对应测试，不能靠提高无限缓冲规避 |
| install-root 与 authority 混淆，清理后 actor 变成 unknown | TASK-02 在事务前绑定 identity、根来自 `ctx.installRoot`；TASK-03 在临时三仓夹具验证终态。共享改动回滚必须先撤 TASK-03 的去重/夹具消费，再撤 TASK-02 的根/身份；不可单独撤 TASK-02 留下依赖它的 TASK-03 |
| 终态重放产生重复事件或将不同 tx/stage 合并 | TASK-03 用稳定 journal 标识、分阶段测试；与 TASK-02 作为同一 B 组逆拓扑回滚 |
| 普通 CR 局部测试被宣称为全量，上游同步约束被削弱 | TASK-04 仅修改三个 Skill 提示词及合同测试；另取独立评审真实 verdict 与上游同步原始全量日志。任一取不到时不声称对应 AC 已证实；失败单独撤 TASK-04，不改 SDD/机器门禁 |

## 5. 验收与发布策略

批准范围为 SDD §8 的 A/B/C：下表 `cmd-01`～`cmd-05` 验证 A/B 的定向行为；`cmd-06`～`cmd-08` **只**验证三个 Skill 的文字合同及测试夹具断言，不能代替独立 reviewer 的真实 verdict 或 multica 上游同步全量执行。`cmd-NN` 使用尚待 TASK 实现的命名测试案例；测试不存在或匹配不到案例时不得以零退出冒充通过，应检查实际执行的 test 数与断言结果。`node --test-name-pattern` 只选命中案例，skip 不算通过。tools 的全仓 `go test ./...`、`make test` 不在本 CR 的绿色关键证据内；已批准全量绿色而不可达时，须解决失败或正式修订验收合同，不绕过 `crctl test`。

C 项**实际评审取证**（TASK-04 实现期，独立于 `cmd-06`/`cmd-07`）：在隔离的测试 CR worktree 中准备可供 `review-dev-plan` 读取的 SDD、plan 两张稳定表及 TASK；测试 CR 只用版本化夹具/合法 crctl 流程建立可评审状态，不手改任何业务 CR 的受控 status 或 canonical review。以无批准全量要求的相同 SDD/AC 分别提交三个快照：U：plan 将全仓测试列为必须通过的关键 cmd、TASK 附加全仓绿色；S：关键 cmd 仅执行子集而 plan/TASK 声称全量通过；P：改为足以覆盖 FR/AC 的定向 cmd，plan/TASK 一致标注子集范围且不附加全量。每个快照由**新的独立 quality-reviewer-agent task/run** 按 `review-dev-plan` 对该快照和真实资源路径作判断；U/S 期望 `verdict=block`、具体 FR/AC 与证据 ID、`repair-target=write-dev-plan`，P 期望不因缺全仓测试而 BLOCK（其他 blocker 不能冒充该案结论）。取证入口：测试 CR 各自的 canonical `review-annotations/dev-plan.yml`、`review-loop.yml`、`crctl next` 返回及对应 issue reviewer 评论；在本 CR `test-evidence/scope-review/` 留案例 ID、原始 workspace/CR-ID、快照 SHA 和上述原始证据的只读副本/可核查引用，`test-report.md` 逐案引用实际 verdict。`cmd-06`/`cmd-07` 的绿色仅证明合同断言，不证明这些 verdict；未取得独立实际 verdict 时 AC-6/AC-7 的评审部分不得标 pass。不得拿本 CR 自身的 plan 评审当作 U/S 案例。

C 项**上游场景取证**（TASK-04 实现期，独立于 `cmd-08`）：本 CR 不执行上游 merge/rebase，不改 multica/CUSTOM.md；查验一笔**真实上游同步**在其目标 fork 上按 `CUSTOM.md` 运行的全量原始日志（含各命令、cwd、commit SHA、时间、exit code，失败也保留）及同 Windows 环境的合并前/纯上游基线。将原始日志及逐项失败名单/数量对照存入本 CR `test-evidence/upstream-sync/`，标明同步记录与基线来源；用 `CUSTOM.md#已知测试失败基线`（含 2026-09-30 第七次同步三方对照）逐项核对新增/既有失败，不把已知失败改成绿或以子集替代全量。原始日志缺失、运行命令不全或基线不可核时，不能仅凭 CUSTOM 摘要宣称 AC-7 上游场景通过，须补取真实同步证据/下一次独立授权的上游同步再核验并报告未闭合项。本 CR 的普通 CR 定向验收不要求上游全量绿色；`cmd-08` 仅证明保留该规则的文字合同。

执行证据命令表命令时 cwd 相对于 tools CR worktree；`crctl test` 要按稳定表命令依次产生 `test-evidence/cmd-NN.log` 和机器区，真实输出经测试报告消费。独立 reviewer verdict 与上游真实日志是额外证据，不能由 cmd 日志伪造，测试报告分别引用。额外执行现有 `lint-prompts.mjs`、`check-skill-matrix.mjs`（非替代 cmd 的整体验证）及相关已有回归；记录结果原文与范围，不扩大批准验收门槛。发布前核对 TASK 进度随完成即时经 `crctl task done` 标记、真实 test-report 和独立 review PASS；之后人类审批。无需 feature flag，无 schema/数据迁移，不修改共享服务。

环境前提：Node 可用、工具仓工作区与隔离临时目录可写、临时 bare origin Git 夹具可创建；无常驻服务、浏览器或数据库依赖；无需额外环境 readiness 命令。测试无法建立时按 `implement-code` 的 `ENVIRONMENT_MISMATCH` 技术中止并报告所需动作，不以猜测结果替代证据。

## 6. 两张稳定表

**交付覆盖表（稳定表 1/2）**

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 / AC-1 | §2、§3.1 stdout/stderr 与真实元数据 | CR-2026-073-TASK-01 | cmd-01 | 撤 TASK-01 及其测试 |
| FR-2 / AC-2 | §3.1 非零/超时/启动失败分类 | CR-2026-073-TASK-01 | cmd-02 | 撤 TASK-01 及其测试 |
| FR-3 / AC-3 | §3.1 溢出技术错误与 canonical 原子性 | CR-2026-073-TASK-01 | cmd-03 | 撤 TASK-01 及其测试 |
| FR-4 / AC-4 | §3.2 install-root / 事前 actor / advance 同根 | CR-2026-073-TASK-02；关联 CR-2026-073-TASK-03 | cmd-04 | 先撤 TASK-03 再撤 TASK-02 |
| FR-5 / AC-5 | §2、§3.2 三入口/清理/终态事件去重 | CR-2026-073-TASK-03；关联 CR-2026-073-TASK-02 | cmd-05 | 先撤 TASK-03 再撤 TASK-02 |
| FR-6 / AC-6 | §3.3 plan 定向命令合同；AC-6 误设全仓 verdict 另见 §5 scope-review/U | CR-2026-073-TASK-04 | cmd-06 | 撤 TASK-04 |
| FR-7 / AC-6、AC-7 | §3.3 TASK 继承/评审 blocker 合同；实际 verdict 另见 §5 scope-review/U、S、P | CR-2026-073-TASK-04 | cmd-07 | 撤 TASK-04 |
| FR-8 / AC-7 | §3.3 上游全量/失败基线**规则**；实际同步全量及原始失败对照另见 §5 upstream-sync | CR-2026-073-TASK-04 | cmd-08 | 撤 TASK-04 |

**证据命令表（稳定表 2/2）**

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["--test","--test-name-pattern","CR073 long output complete","skills/shared/crctl/scripts/test/test-cr.test.mjs"]` | 120 |
| cmd-02 | tools | . | node | `["--test","--test-name-pattern","CR073 true failure and legacy classification","skills/shared/crctl/scripts/test/test-cr.test.mjs"]` | 120 |
| cmd-03 | tools | . | node | `["--test","--test-name-pattern","CR073 overflow preserves canonical","skills/shared/crctl/scripts/test/test-cr.test.mjs"]` | 120 |
| cmd-04 | tools | . | node | `["--test","--test-name-pattern","CR073 terminal audit root and actor","skills/shared/crctl/scripts/test/terminal-audit.test.mjs"]` | 120 |
| cmd-05 | tools | . | node | `["--test","--test-name-pattern","CR073 terminal audit replay and cleanup","skills/shared/crctl/scripts/test/terminal-audit.test.mjs"]` | 120 |
| cmd-06 | tools | . | node | `["--test","--test-name-pattern","CR073 ordinary CR targeted evidence","skills/shared/crctl/scripts/test/skill-scope.test.mjs"]` | 60 |
| cmd-07 | tools | . | node | `["--test","--test-name-pattern","CR073 scope mismatch blocks review","skills/shared/crctl/scripts/test/skill-scope.test.mjs"]` | 60 |
| cmd-08 | tools | . | node | `["--test","--test-name-pattern","CR073 upstream full-suite exception","skills/shared/crctl/scripts/test/skill-scope.test.mjs"]` | 60 |

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 完整分区输出、真实退出及 SHA | §3.1 / §4.1 | CR-2026-073-TASK-01 | cmd-01 |
| AC-2 真正非零与原有 timeout/启动失败 | §3.1 / §4.1 | CR-2026-073-TASK-01 | cmd-02 |
| AC-3 ENOBUFS 技术错误、null exit、canonical 不变 | §3.1 / §4.1 | CR-2026-073-TASK-01 | cmd-03 |
| AC-4 三合法入口、同根及真实 actor、无重建 | §3.2 / §4.2 | CR-2026-073-TASK-02；关联 CR-2026-073-TASK-03 | cmd-04 |
| AC-5 终态重放去重、无历史倒填 | §3.2 / §4.2 | CR-2026-073-TASK-03 | cmd-05 |
| AC-6 普通 CR 错设全仓 BLOCK、定向证据继承 | §3.3 / §4.3 | CR-2026-073-TASK-04 | cmd-06、cmd-07（合同）；§5 scope-review/U、P（独立 verdict） |
| AC-7 子集冒充全量 BLOCK；真实上游同步全量/基线 | §3.3 / §4.3 | CR-2026-073-TASK-04 | cmd-07、cmd-08（合同）；§5 scope-review/S、upstream-sync（独立 verdict 与全量原始证据） |
