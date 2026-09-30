---
id: CR-2026-073-plan
type: PLAN
cr-ref: CR-2026-073
sdd-ref: "change-requests/CR-2026-073/sdd.md"
target-version: 0.46
status: draft
created: 2026-09-30T13:05:00+08:00
updated: 2026-09-30T13:05:00+08:00
---

# CR-2026-073 开发计划

## 1. 交付里程碑

| 阶段 | 交付 | 估算 |
|---|---|---|
| 设计 | 已批准 PRD/SDD 对齐、四组接口与验证范围确认 | 0.5 人天 |
| 实现 | G1 测试缓冲/分类、G2 审计根/actor、G3 终态去重与隔离回归、G4 三个开发 Skill 口径 | 2 人天 |
| 测试 | 定向运行八个 cmd-NN，核查原始失败/成功及 canonical 不变量；运行既有 prompt/matrix 校验 | 1 人天 |
| 联调 | 三仓临时 origin 夹具下核查入口/重放；无真实共享服务 | 0.25 人天 |
| 发布 | 独立评审、人工审批后由后续 Pipeline 合入/回写；本阶段不建立交付 TASK | 0.25 人天 |

合计 **4 人天 / 32h**（Ray 开发与测试角色；人工门禁时间不计）。计划层只给估算，不在此规定实现微步骤。

## 2. 任务依赖图

- G1 → `CR-2026-073-TASK-01`：A，`runTestPlan` 与定向黑盒回归；独立。
- G2 → `CR-2026-073-TASK-02`：B，三个 CLI adapter 的 install-root 审计及事前 actor；产出 G3 的稳定根/身份契约。
- G3 → `CR-2026-073-TASK-03`：B，依赖 TASK-02 的根与身份，完成终态业务事件去重、三入口/清理/重放夹具回归。
- G4 → `CR-2026-073-TASK-04`：C，三个 develop Skill 的批准范围/证据约束与案例核查；独立。

每个变更组恰一主责 TASK；G1/G2/G3/G4 的任务编号连续，无 merge/writeback/archive 流程 TASK。

## 3. 资源与分工

Ray (`owners.development.id` 与 `owners.test.id` 均为 `a0e71a32-509d-4ee9-aea4-d086a5b1ff93`)：TASK-01 8h、TASK-02 8h、TASK-03 10h、TASK-04 6h；同一人的双角色分别负责真实实现与测试报告。独立 `quality-reviewer-agent` 评审 plan/TASK 与代码，不由作者自评。只操作 `workspace inspect` 返回的 tools 与 KB CR worktree；multica 仓仅只读核对 `CUSTOM.md` 上游同步规则，不改 multica 代码。

## 4. 风险与回滚策略

| 风险 | 缓解与回滚 |
|---|---|
| 10 MiB 的单段溢出被误当非零/timeout，或截断片段被发布为证据 | TASK-01 黑盒验证边界、四类 canonical 原字节；失败撤销 TASK-01 变更及对应测试，不能靠提高无限缓冲规避 |
| install-root 与 authority 混淆，清理后 actor 变成 unknown | TASK-02 在事务前绑定 identity、根来自 `ctx.installRoot`；TASK-03 在临时三仓夹具验证终态。共享改动回滚必须先撤 TASK-03 的去重/夹具消费，再撤 TASK-02 的根/身份；不可单独撤 TASK-02 留下依赖它的 TASK-03 |
| 终态重放产生重复事件或将不同 tx/stage 合并 | TASK-03 用稳定 journal 标识、分阶段测试；与 TASK-02 作为同一 B 组逆拓扑回滚 |
| 普通 CR 局部测试被宣称为全量，上游同步约束被削弱 | TASK-04 只修改三个 Skill 提示词、用普通 CR 与上游情形分别核查；失败单独撤 TASK-04，不改 SDD/机器门禁 |

## 5. 验收与发布策略

批准范围为 SDD §8 的 A/B/C：只运行下表**实际覆盖的定向** `cmd-NN` 作为本 CR 的 FR/AC 证据；每条命令的范围是明确命名的临时夹具案例，不是 tools 全量套件，也不宣称全量通过。`cmd-NN` 使用尚待 TASK 实现的命名测试案例；测试不存在或匹配不到案例时不得以零退出冒充通过，应在实现后检查实际执行的 test 数与断言结果。`node --test-name-pattern` 由 Node 测试 runner 只选命中案例，其他案例的 skip 不算通过。全仓 `go test ./...`、`make test` 不在已批准 SDD/AC 的本次验收要求中；上游同步场景仍依 multica `CUSTOM.md` 跑全量，保留 Windows 原始失败与基线对照，不作为这里的绿色 cmd。若已批准验收明确要求全量绿色而当前不可达，只能解决失败或正式修订合同，不绕过 `crctl test`。

执行证据命令表命令时 cwd 相对于 tools CR worktree；`crctl test` 要按稳定表命令依次产生 `test-evidence/cmd-NN.log` 和机器区，真实输出经测试报告消费。额外执行现有 `lint-prompts.mjs`、`check-skill-matrix.mjs`（非替代 cmd 的整体验证）及相关已有回归；记录结果原文与范围，不扩大批准验收门槛。发布前核对 TASK 进度随完成即时经 `crctl task done` 标记、真实 test-report 和独立 review PASS；之后人类审批。无需 feature flag，无 schema/数据迁移，不修改共享服务。

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
| FR-6 / AC-6 | §3.3 plan 定向命令、实际范围 | CR-2026-073-TASK-04 | cmd-06 | 撤 TASK-04 |
| FR-7 / AC-6、AC-7 | §3.3 TASK 继承与 review blocker | CR-2026-073-TASK-04 | cmd-07 | 撤 TASK-04 |
| FR-8 / AC-7 | §3.3 上游全量与失败基线例外 | CR-2026-073-TASK-04 | cmd-08 | 撤 TASK-04 |

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
| AC-6 普通 CR 错设全仓 BLOCK、定向证据继承 | §3.3 / §4.3 | CR-2026-073-TASK-04 | cmd-06、cmd-07 |
| AC-7 子集冒充全量 BLOCK；上游全量基线 | §3.3 / §4.3 | CR-2026-073-TASK-04 | cmd-07、cmd-08 |
