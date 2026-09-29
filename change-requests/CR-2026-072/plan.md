---
id: CR-2026-072-plan
type: PLAN
cr-ref: CR-2026-072
sdd-ref: "change-requests/CR-2026-072/sdd.md"
target-version: 0.45
status: draft
created: 2026-09-28T23:46:25+08:00
updated: 2026-09-29T11:55:00+08:00
---

# CR-2026-072 开发计划

依据已审批 SDD（`sdd.md`，dep-1～dep-11 均在 tools `b2e9356…` / multica `1c24d353…` 核对）将 FR-1～FR-5 / AC-1～AC-5 转化为开发任务。改动面：tools（调用方合约与 crctl 入口）+ multica（daemon 绑定与 gitguard 审计）；knowledge-base 仅承载 CR 文档。不新增状态机、事务、审批途径或第二套工作区解析。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 估算 |
|---|---|---|---|
| M1 调用方迁移 | 四 Agent Prompt、共享 crctl 合同、Pipeline 模板、Skill、push-progress、注入 hook、README 全部可执行 CR 调用显式 `--workspace`；caller-contract 扩展解析与断言（CR 数据命令抽取 + 非空 `--workspace` 断言） | TASK-01 | 0.5 人天 |
| M2 crctl CLI 入口强校验 | 非 help 的 CR 数据命令强制非空有效 `--workspace`，缺/空 `WORKSPACE_REQUIRED`、无效 `WORKSPACE_NOT_FOUND`，先于 `loadGates`/状态读取；删除 env/cwd 回退；含跨项目同名 CR 隔离回归用例 | TASK-02 | 1 人天 |
| M3 daemon 任务绑定 | Pipeline 保留预检 root；删除普通任务 `CRWorkspaceRoots[0]` 回退；无可信 local_directory 绑定不注入并清除继承的 CRCTL_* 环境键；`CRCTL_OPERATIONAL_WORKSPACE` 与任务 operational path 不一致时写路径拒绝 | TASK-03 | 0.5 人天 |
| M4 拒绝审计归属 | gitguard 拒绝行为不变；审计根改由任务预检 root 独立传入，不再读 `CRCTL_WORKSPACE`；无绑定时不写他项目 outbox，错误码不变 | TASK-04 | 0.5 人天 |
| M5 回归与证据 | 运行四类既有测试、产出受影响调用点清单与真实结果（经 `crctl test` / write-test-report） | TASK-05 | 0.5 人天 |
| M6 评审与发布 | review-dev-plan → 开发启动人工审批（Ray）→ 实现/测试报告 → review-code → 代码人工审批（Ray）→ writeback（delivery-agent）。TASK-01 必须先于 TASK-02 进入同一交付批次（FR-5 同批交付门） | — | — |

估算总工时：约 3 人天（单实现者；评审与人工审批不占实现工时）。

## 2. 任务依赖图

```text
TASK-01 调用方迁移（tools：agents/pipeline-templates/skills/hook/README）
   │  发布顺序前置（同批交付门）：TASK-01 未完成不合入 TASK-02 强校验
   ▼
TASK-02 crctl CLI 入口强校验（tools：crctl.mjs + test/crctl.test.mjs）
TASK-03 daemon 任务绑定（multica：daemon.go / pipeline_task.go / local_directory.go + Go 测试）
   │  注入 CRCTL_TASK_AUDIT_ROOT（生产者 → 消费者）
   ▼
TASK-04 gitguard 拒绝审计归属（multica：cmd_gitguard.go + Go 测试）    【TASK-03 与 TASK-01/02 可并行】
   ▼
TASK-05 全量回归 + 调用点清单 + 证据落盘（依赖 TASK-01～04 全部完成）
```

依赖说明：TASK-02 对 TASK-01 仅为**发布顺序**约束（代码无调用关系）；TASK-04 硬依赖 TASK-03（消费其注入的 `CRCTL_TASK_AUDIT_ROOT`，生产者未完成消费者不得标记 done）；TASK-03 与 TASK-01/02 相互独立可并行；TASK-05 消费全部前置 TASK 的真实运行结果。

## 3. 资源与分工

| 角色 | 承担 | 范围 |
|---|---|---|
| dev-agent（实现） | TASK-01～05 编码与自测 | TASK-01/02 → tools 仓；TASK-03/04 → multica 仓；TASK-05 → 两仓运行 + knowledge-base 证据 |
| quality-reviewer-agent | review-dev-plan / review-code 独立评审 | 独立 run，直连不经协调者 |
| Ray（三角色 owner） | 开发启动确认、代码审批 | 仅人类在本地交互式终端执行 `crctl approve` |

环境边界：全部工作在 Pipeline 预检的 CR worktree（tools / multica / knowledge-base 三仓，`crctl workspace inspect` 均 healthy）；不触碰任务范围外的共享服务。

## 4. 风险与回滚策略

| # | 风险 | 缓解 | 回滚单元 |
|---|---|---|---|
| R1 | 扫描面外调用点遗漏（CI workflow、hook、脚本） | SDD §4.1 逐项清单 + caller-contract 扩展解析与断言（CR 数据命令 + 非空 `--workspace`） + lint-prompts enforce；TASK-05 交付清单 | revert TASK-01（文档/Skill/Prompt，无下游代码消费者） |
| R2 | CLI 强校验先于调用方迁移上线，旧 Pipeline 全量失败 | 同批交付门：TASK-01 完成才合入 TASK-02；`WORKSPACE_REQUIRED` 先于任何 CR 数据读取 | revert TASK-02（含其同批 CLI 用例） |
| R3 | Windows 路径大小写 / symlink / 相对路径逃逸 | realpath 规范化比较 + TASK-02 用例覆盖等价与逃逸面 | 同 TASK-02 |
| R4 | daemon 注入变更回归影响现有 Pipeline | Pipeline 预检路径保持不变；Go 回归覆盖有/无绑定两态 | revert TASK-03（含其同批 daemon 用例）；`CRCTL_TASK_AUDIT_ROOT` 被 TASK-04 消费，TASK-04 为下游消费者，按逆拓扑顺序先于 TASK-03 回退 |
| R5 | 拒绝审计误归属他项目 | gitguard 用例覆盖有根（归本项目）/ 无根（不写）两态；拒绝错误码不变；审计失败不放行 | revert TASK-04（含其同批审计用例） |

整体回滚顺序（逆拓扑）：TASK-05（证据/报告）→ TASK-04 → TASK-03 → TASK-02 → TASK-01；knowledge-base 仅 CR 文档，随各 TASK commit 一并回退。单 TASK commit 均自含其新增测试；被消费的共享改动（TASK-03 注入的 `CRCTL_TASK_AUDIT_ROOT`）按逆拓扑先回退其下游消费者（TASK-04）再回退生产者，单点 revert 不破坏其余 TASK 的构建与测试。

## 5. 验收与发布策略

- **环境**：本机三仓 CR worktree（tools / multica / knowledge-base）。owner：Ray（development owner）；建立方式：Pipeline 预检 + `crctl workspace inspect`（当前三仓 healthy、dirty=false，HEAD 与 SDD dep 表一致）；可获得性：随 CR worktree 存续，merge finalize 后以 inspect 重取 transaction workspace，不持久化副本。无数据库、常驻服务或浏览器依赖。
- **readiness 证据**：复用第 6 节稳定表 cmd-01～cmd-04（即各 FR 行「验收证据」列），不新增第八节之外的命令或判据。
- **缺失时处置**：环境前提无法建立时按 `ENVIRONMENT_MISMATCH` 中止并报告所需动作（详细语义的事实源为 implement-code Skill，此处只引用）。
- **发布**：TASK-01（调用方）与 TASK-02/03/04（CLI 强校验 + daemon）必须同一交付批次（FR-5/AC-5）；门禁失败即停；开发启动确认与代码审批由 Ray 本人执行，Agent 不代签。

## 6. 两张稳定表

### 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 调用点迁移 | SDD §4.1、§8 | CR-2026-072-TASK-01 | cmd-02、cmd-03 | revert TASK-01 commit（无下游代码消费者） |
| FR-2 CLI 入口失败关闭 | SDD §2、§4.2 | CR-2026-072-TASK-02 | cmd-01 | revert TASK-02 commit（含同批 CLI 用例） |
| FR-3 daemon 任务绑定 | SDD §2、§4.3 | CR-2026-072-TASK-03 | cmd-04 | revert TASK-03 commit（含同批 daemon 用例） |
| FR-4 拒绝审计归属 | SDD §2、§4.4 | CR-2026-072-TASK-04 | cmd-04 | revert TASK-04 commit（含同批审计用例） |
| FR-5 同批交付与回归 | SDD §4.1、§4.5 | CR-2026-072-TASK-05 | cmd-01、cmd-02、cmd-03、cmd-04 | revert TASK-05 报告 commit；实现仓按 TASK-04→03→02→01 逆序回退 |

### 证据命令表（稳定表 2/2）

cwd 相对对应仓 CR worktree 根（tools：`.rayai-worktrees\tools\requirement\CR-2026-072`；multica：`.rayai-worktrees\multica\requirement\CR-2026-072`）；命令算法以本表为唯一事实源。

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | skills/shared/crctl/scripts | node | ["--test","test/crctl.test.mjs"] | 600 |
| cmd-02 | tools | skills/shared/crctl/scripts | node | ["--test","test/caller-contract.test.mjs"] | 600 |
| cmd-03 | tools | skills/shared/crctl/scripts | node | ["lint-prompts.mjs","--mode","enforce"] | 300 |
| cmd-04 | multica | server | go | ["test","./internal/daemon/","./cmd/multica/","-count=1","-v","-run","Test(InjectTaskCRWorkspaceEnv|DaemonEnvBuildHasNoConfigFirstRootFallback|PreparePipelineTaskHydratesMachineLocalPaths|GitguardDenialAuditAttribution|GitguardExecHelperProcess)"] | 900 |

覆盖说明：cmd-01 观测 FR-2/AC-1～AC-3（含 TASK-02 新增的 A/B 同名 CR 隔离、缺/空/无效旗标用例、operational 双值同时存在且冲突及仅 `CRCTL_OPERATIONAL_WORKSPACE` 存在且与显式 `--workspace` 冲突（env 不作唯一权威）的首次读写前失败关闭用例，测试自建临时 workspace）；cmd-02 观测 FR-1：既有 caller-01～08 登记/漂移/`--detail` 断言保持不变，本 CR 在同一测试内**扩展解析与断言**——现有 `extractProjected` 仅抽取四类投影命令与 `hasDetail`、`REVIEWED_CALLS` 条目仅 `file/command/verdict/note`、`OUT_OF_SURFACE_CALLERS.commands` 仅命令名，均不含 argv 结构，故新增 CR 数据命令抽取（覆盖投影集合之外的真实 CR 数据读写子命令）与逐调用点断言（每处 CR 数据读写命令含 `--workspace` 且路径 token 非空，扫描面内与已登记扫描面外调用点均纳入）；cmd-03 观测 FR-1 的 prompt/README 漂移面（enforce 模式命中即非零）；cmd-04 观测 FR-3/FR-4/AC-4：收敛为定向包集 `./internal/daemon/` + `./cmd/multica/`（本 CR 在 multica 仓的全部改动面），以 `-run` 过滤到 TASK-03/04 新增的 daemon 绑定与审计用例，并含 AC-4「Pipeline 用预检路径」的既有回归 `TestPreparePipelineTaskHydratesMachineLocalPaths`；`-v` 使每条用例的 PASS 在证据日志中独立可核。收敛依据（2026-09-29 人工批准）：本机这两个包的整包基线为既有环境性失败（daemon 包 67 项；`cmd/multica` 包测试二进制 10 分钟超时，且失败输出约 10 MB 超 crctl test 运行器 1 MiB 子进程缓冲，见 AIFI-38），与本 CR 改动无关，整包在该运行面产不出通过证据。FR-5/AC-5 的验收面为四条命令结果的并集。

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 显式 B 只见 B；终态查询不依赖 STATUS_DIVERGED 纠错 | SDD §1、§4.2 | CR-2026-072-TASK-02 | cmd-01 |
| AC-2 cwd=B/env=A 缺/空旗标 → WORKSPACE_REQUIRED 非零且 A/B 零副作用 | SDD §2、§4.2 | CR-2026-072-TASK-02 | cmd-01 |
| AC-3 显式 B/env=A 时读、gate 只观察 B，推进仅以 B 为权威；无效路径不回退；operational 双值冲突及仅 env 冲突（env=A、无旗标、`--workspace=B`）均于首次读写前失败关闭（env 不作唯一权威，A/B 零副作用） | SDD §1、§3、§4.2、§4.4 | CR-2026-072-TASK-02 | cmd-01 |
| AC-4 Pipeline 用预检路径；普通任务无根不注入、有根只注入该项目、歧义报错；gitguard 审计不误归属 | SDD §4.3、§4.4 | CR-2026-072-TASK-03 | cmd-04 |
| AC-5 四类测试结果 + 确切调用点清单；显式覆盖率 100%；CLI 与调用方同批发布 | SDD §4.1、§4.5 | CR-2026-072-TASK-05 | cmd-01、cmd-02、cmd-03、cmd-04 |

AC-1～AC-5 均为影响主路径验收可达性的关键 AC，逐行单列、TASK owner 逐行唯一；无合并行。AC-4 的 owner 为 TASK-03（daemon 绑定与 `CRCTL_TASK_AUDIT_ROOT` 注入的生产者层），TASK-04 为其**关联 TASK**（gitguard 审计归属消费者），TASK-04 的验收面经 §6 交付覆盖表 FR-4 行与 cmd-04 追溯。
