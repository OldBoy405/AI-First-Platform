---
id: CR-2026-076-sdd
type: SDD
cr-ref: CR-2026-076
title: CR 执行闭环与门禁减负修订 技术设计
target-version: "0.49"
status: draft
created: "2026-10-10T15:11:00+08:00"
updated: "2026-10-10T15:11:00+08:00"
---

# CR 执行闭环与门禁减负修订 技术设计（SDD）

> 输入：`change-requests/CR-2026-076/prd.md`（status=requirement-approved，需求评审 PASS，`review-annotations/requirement.yml`）。
> 本文只做技术设计，不回写 `specs/`、不改注册事实、不推进任何未由本合同授权的状态。
> 既有实现事实一律以 `§10 既有实现依赖与事实` 的 `dep-N` 承载，正文不复述实现细节。

## 1. 架构概览

### 1.1 目标与四个工作包

本 CR 在三个参与仓内定点修订「CR 执行闭环」与「门禁减负」，不新增执行器、不建影子账本。四个工作包与 PRD 的对应：

| 工作包 | PRD 落点 | 主要落仓 |
|---|---|---|
| W1 运行绑定、Git 身份、评审落盘与普通 BLOCK 复评闭环 | FR-01、FR-02、FR-03、FR-04 | multica（绑定/身份）、tools（评审与 next） |
| W2 合法本地信任与流程减负 | FR-05、FR-06、FR-07 | tools（gate/approve/next/loop） |
| W3 G05/G06 内容等价比较与最小重验 | FR-08、FR-09、FR-10、FR-11 | tools（比较缝与发布事务） |
| W4 CI 收敛、小缺陷与实际生效 | FR-12、FR-13、FR-14 | tools（测试门禁/文档链）、平台消费者核对 |

补充修订（FR-SUP-01～FR-SUP-09）与 W1/W2 同批交付，注册阶段与阶段根交接（FR-SUP-05）、错误根防线（FR-SUP-06）、作者/评审者开工检查（FR-SUP-07）落在 multica + tools 两侧。

### 1.2 AIFI-62 承接边界（与 PRD §1.5 逐行一致）

| 能力 | 本 CR | 承接方 |
|---|---|---|
| FR-01～FR-04 的生产实现（绑定、Git 身份、评审落盘原子闭环、普通 BLOCK 复评） | **本 CR 交付** | — |
| FR-SUP-01～FR-SUP-04（owner／source 新输入与真实 owner 变更校验、单文件来源导入） | **本 CR 交付** | — |
| FR-SUP-05、FR-SUP-08、FR-SUP-09（注册节点交接、PRD 交接完整性、历史事实只读扫描） | **本 CR 交付**（平台运行上下文交接按「仅对新注册后交接作必要集成验收」执行） | — |
| FR-SUP-06 的「错误根防线」部分（错误项目根／阶段根、失效或错误 worktree、主 checkout 冒充在途 CR 操作根一律写前拒绝） | **本 CR 交付**（写入边界安全校验） | — |
| FR-SUP-06 的「reviewer 可信绑定与启动预检／平台直接派发单层独立 reviewer」 | 保留编号与需求描述，不重复实现 | AIFI-60（步骤 3，复用 AIFI-58/59） |
| FR-SUP-07 的「写入边界安全校验与诊断口径」（`workspace inspect`／`status`／`next` 只读核对、`WORKSPACE_CONTEXT_MISMATCH` 失败关闭） | **本 CR 交付** | — |
| FR-SUP-07 的「删除逐节点手抄根、普通评论代调度及重复派发说明」与相关生效合同最小同步 | 保留编号，不重复实施 | AIFI-60（步骤 3） |
| FR-SUP-09／AC-SUP-10 的「评审 Task 正常结束后仍以正式交付证据判定节点成功、证据缺失可见失败、原卡死形态受控恢复」 | 保留编号，不作为本 CR 验收前置 | AIFI-60（步骤 1／2） |
| 平台 CR 投影 reconcile 权威源根治（在途 CR 读自身 worktree 分支） | 不在本 CR，**也不作为本节点成败依据** | 独立 CR |

### 1.3 参与仓、路径 authority 与提交口径

- 参与仓集合、分支、worktree 路径一律取自 `workspace inspect` 的 `resources[]`；所有代码事实只按 `resources[].worktreePath` 取证，禁止按目录命名拼接 `.rayai-worktrees/{repo}/requirement/{cr}`，禁止回退主工作区（多仓路径 authority 见 `SDD-CLOSE-04`）。
- 提交口径：SDD 与各仓代码/文档在各自 `resources[].worktreePath` 内分别提交，随后由同一批 `crctl checkpoint` 纳入发布（本地提交不等于远端发布）。
- 三仓职责：`tools`（方法论包：crctl、Skill、Pipeline 模板、门禁、文档链校验）、`multica`（平台：daemon 绑定与身份、governance 投影与派发）、`knowledge-base`（本 CR 的 CR 产物与平台设计文档，**无代码变更**）。

```text
        ┌────────────────────────── multica（平台） ──────────────────────────┐
        │  daemon: parseExecutionContext → resolveTaskWorkspaceBinding        │
        │         → findPipelineCRRoot → inspectPipelineWorkspace             │
        │         → configureTaskGitEnvironment（Git trust 叠加 + 绑定注入）   │
        │  governance: runner / crsync / reconcile（投影，本 CR 不改权威源）   │
        └───────────────┬─────────────────────────────────────────────────────┘
                        │ 注入 CRCTL_OPERATIONAL_WORKSPACE / CRCTL_TASK_AUDIT_ROOT / MULTICA_TASK_ID
                        ▼
        ┌──────────────────────────── tools（方法论包） ───────────────────────┐
        │  crctl.mjs: bindTaskWorkspace → 业务子命令（advance/approve/next/    │
        │             review-record/review-loop/owner-set/register/merge/      │
        │             checkpoint/workspace/validate/gate）                     │
        │  lib: durable-tx（事务/CAS/恢复）、workspace-transactions（仓解析、   │
        │       release-subjects、checkpoint 分类）                            │
        │  gates.json + dir-graph.yaml（状态机与门禁）                          │
        │  engineering-docs/scripts（文档链校验 chain.ts）                      │
        └───────────────┬─────────────────────────────────────────────────────┘
                        │ 读/写 CR 账本与评审证据
                        ▼
        ┌───────────────────── knowledge-base（CR 权威工作区） ────────────────┐
        │  change-requests/{CR-ID}/{cr.md, prd.md, sdd.md, plan.md, tasks/,    │
        │  review-annotations/, review-loop.yml, approval.yml, traceability.yml}│
        └──────────────────────────────────────────────────────────────────────┘
```

依赖方向为单向：平台只注入绑定与身份，业务判定一律在 tools 的 crctl 内；crctl 不反向调用平台接口（FR-07 的「认证人类事实」以 daemon 注入的触发事实为输入，见 §4.7）。

### 1.4 关键流程（端到端）

```text
[注册期]  来源文档上传/入库 → register 校验 owner(user_id) 与 source(containment+可读)
          → 写入 cr.md + _backlog.yml → （须经 requirement-authoring pipeline 的登记节点）
[设计期]  绑定归一（dep-1）→ workspace inspect（dep-3）只读核验 → write-tech-design
          → review-tech-design（独立 reviewer task，review-record 落盘）
          → 人工审批（approve --stage tech-design）
[编码期]  write-dev-plan → write-dev-tasks → review-dev-plan
          → 【本 CR 交付后】默认路径不再经 dev-start 人工确认，直接经既有 advance 进入 developing
          → workspace-freshness(implement-start) → implement-code → write-test-report
          → workspace-freshness(review-start) → review-code → 人工代码审批
[交付期]  merge-feature-branch（tree 等价判定 + 发布 source 固定）→ writeback → archive
```

### 1.5 变更面总览（按仓）

| 仓 | 变更对象 | FR 落点 |
|---|---|---|
| multica | `server/internal/daemon/pipeline_task.go`（绑定解析新增 task/来源 Issue 关联段；Git trust 改为叠加） | FR-01、FR-02、FR-SUP-05、FR-SUP-06、FR-SUP-07 |
| multica | `server/internal/daemon/repocache/*`（身份加载核对，仅在叠加式 trust 需要时改） | FR-02 |
| tools | `skills/shared/crctl/scripts/crctl.mjs`（review-record、next、gate/approve、review-loop、owner-set、register、merge、workspace、checkpoint） | FR-03～FR-11、FR-SUP-01～09 |
| tools | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新增单一 tree 比较缝；发布 source 固定） | FR-08、FR-09、FR-11 |
| tools | `skills/shared/crctl/gates.json` + `dir-graph.yaml`（developing 门禁与合法转换） | FR-06 |
| tools | `pipeline-templates/code-implementation.pipeline.json`（移除 dev-start 必经节点） | FR-06 |
| tools | `skills/shared/crctl/scripts/test/*`（suite-gate 数量门禁、summary 例外收敛、fixture 同根化、freshness/merge/fault 夹具） | FR-03、FR-08、FR-10、FR-12 |
| tools | `skills/shared/engineering-docs/scripts/src/validators/chain.ts` + 测试 | FR-13 |
| tools | Skill／模板／矩阵／Agent 合同同步 | FR-04、FR-06、FR-SUP-02、FR-SUP-07、FR-14 |
| knowledge-base | 本 CR 的 CR 产物（本 SDD、plan、tasks、评审证据） | 全部 |

## 2. 数据模型

### 2.1 实体与存储

本 CR **不引入数据库 schema 变更**：全部状态与证据仍为知识库仓内的文件账本（YAML/Markdown），由 crctl 单通道写入（`dep-27`）。实体清单：

| 实体 | 载体 | 本 CR 变更 |
|---|---|---|
| E1 CR 注册投影 | `change-requests/{cr}/cr.md` frontmatter + `change-requests/_backlog.yml` 条目 | 值域收紧：`owners.{requirement,development,test}.id` 必须为当前 workspace 成员的 `user_id`；`source` 为知识库内相对路径或 `""` |
| E2 评审证据 | `change-requests/{cr}/review-annotations/{stage}.yml` | 结构沿用；`warnings` 采用既有 `{code,message}` 数组形式（`dep-19`、`SDD-CLOSE-05`） |
| E3 评审循环 | `change-requests/{cr}/review-loop.yml` | 字段沿用；人类继续的授权事实新增审计记录（不新增字段类型） |
| E4 审批记录 | `change-requests/{cr}/approval.yml` 各 section | 字段沿用；本地信任判定读取既有 `via`/`signature`/`evidence-digest`（`dep-20`） |
| E5 任务绑定三元组 | 注入环境 `MULTICA_TASK_ID`／`CRCTL_OPERATIONAL_WORKSPACE`／`CRCTL_TASK_AUDIT_ROOT` | 语义不变；新增「绑定来源」诊断标签（只读输出，不进入账本） |
| E6 任务 Git trust 配置 | `<CR 根>/.crctl/task-gitconfig` | 由「替换全局配置」改为「叠加」：safe.directory + include 原全局配置 |
| E7 workspace 观察 | `crctl workspace inspect` 输出（`classification`／`dirty`／`operationalWorkspace`／`resources[]`） | 新增 freshness 比较输入字段（tree 结论与各仓结论） |
| E8 测试登记 | `skills/shared/crctl/scripts/test/gate-registry.json`（manifest／exceptions） | 数量下降由失败改为 warning；四个 summary 例外在根因转绿后撤销 |
| E9 发布事务与 journal | `.crctl/transactions/`、`.crctl/outbox/`（durable-tx） | 复用；发布对象 source 固定规则（`dep-14`、`dep-21`） |
| E10 release-subjects | `review-annotations/code.yml#release-subjects` → `approval.yml#code.release-subjects` | 复用既有构造/重核缝（`dep-14`）；等价 tree 允许以空提交等内容等价源推进 |

**写路径鉴权完整性（条件触发判定）**：本 CR 不涉及 DB schema、DDL 或新写路径鉴权面，故 PRD/Skill 要求的「每个变更的回滚（down）与约束缺失窗口」条款不触发；判定依据为 §3.5「无新增 HTTP API」与 `SDD-CLOSE-03`（无 schema 变更）。CR 账本写路径鉴权仍走既有 author/owner 判定与 CAS/事务（`dep-13`），本 CR 不新增授权模型（`scope_out`）。

### 2.2 关键字段定义

```yaml
# E1 owners.*.id 合法值域
owners:
  requirement: { id: "<workspace member user_id: UUID>", assigned-at: "<RFC3339+08:00>" }
  development: { id: "<workspace member user_id: UUID>", assigned-at: "<RFC3339+08:00>" }
  test:        { id: "<workspace member user_id: UUID>", assigned-at: "<RFC3339+08:00>" }
# 拒绝：显示名、membership ID、非本 workspace 的 user_id、非 UUID 形状

# E1 source 值域
source: "" | "<knowledge-base 内相对路径，注册时可读且 containment 通过>"

# E2 warnings（沿用既有可扩展形式，禁止计数型字段）
warnings:
  - { code: "<固定枚举>", message: "<可读原因>", ref: "<可选：相对路径或 dep-N>" }

# E6 task-gitconfig（叠加式，Git 原生 include）
[safe]
	directory = <CR 根 realpath，POSIX 分隔>
	directory = <operational workspace realpath，POSIX 分隔>
[include]
	path = <原全局 Git 配置 realpath>
```

`warnings` 的 code 枚举（本 CR 新增，均不阻断）：

| code | 触发 | FR |
|---|---|---|
| `LOCAL_TRUST_DOC_DRIFT_WARN` | 合法本地批准下 PRD/SDD/PLAN/TASK 正文漂移 | FR-05 |
| `LOCAL_TRUST_TASK_SET_DRIFT_WARN` | 合法本地批准下 TASK 集合增删 | FR-05 |
| `EVIDENCE_DEFINITION_DRIFT_WARN` | 工具升级导致证据定义变化（非内容被改） | FR-05 |
| `LEGACY_SUBJECT_MISSING_WARN` | 合法存量 PASS 缺 `subject-sha256` | FR-05 |
| `SUITE_COUNT_BELOW_BASELINE_WARN` | 逐文件用例数低于登记基线 | FR-12 |
| `BINDING_INHERITED_WARN` | 绑定来自 task/来源 Issue 的正式关联（非显式声明） | FR-01 |

### 2.3 兼容与迁移

- 历史 CR 的 owner 数据**不做全量迁移**；错误值只经 `handover-cr`／`owner-set` 受控定点修复（FR-SUP-08）。
- 历史显式 `source: manual` 哨兵、既有注册事务、进行中发布 journal 一律按原意图保留，不归一化、不重写（`dep-13`、`dep-14`）。
- 旧 coding 运行图不热换：`approve-dev-start` 的旧审批调用与历史记录保留兼容（FR-06）。

## 3. 接口契约

### 3.1 crctl CLI（无新增子命令）

本 CR **不新增、不改名 crctl 子命令**（`case '<cmd>'` 集合不变，`dep-2`），只扩展既有子命令的判定、参数校验与输出字段：

| 子命令 | 参数变更 | 行为变更 |
|---|---|---|
| `workspace inspect` | 无 | 输出新增 `freshness` 块（各仓 tree 结论与比较输入），保持既有字段类型 |
| `gate` / `validate` | 无 | 漂移类失败按 §4.5 降级为 `warnings[]`；硬阻断不变；`validate` 新增只读维度 `owner-source-anomalies`（FR-SUP-08，仅报告） |
| `next` | 无 | 判定优先级与理由文本（§4.4）；新增可选 `nextReason` 与 `warnings[]` |
| `review-record` | 无 | 原子闭环与恢复（§4.3）；`--bump-attempt` 语义不变 |
| `review-loop reset` | 新增可选 `--continue-reason`；保留 `--loop`／`--reason` | 非 TTY 下允许「认证人类继续」一次一 cycle（§4.7）；TTY 模式保持 |
| `approve` | 无 | 本地信任判定按来源/stage/归属（§4.5）；server-approve 路径严格不变 |
| `owner-set` / `register` | 无 | 目标值写入前校验（§4.13） |
| `merge` | 无 | tree 等价判定与发布 source 固定（§4.8、§4.10） |
| `checkpoint` | 无 | 发布事实与版本核对（§4.12） |

回执形状沿用 `{op, phase, changed, ...}` 与 `ok()/fail()` 单出口（`dep-28`），不得新增同义错误码。

### 3.2 错误码闭包（NFR-02 映射）

| 错误类 | 既有 code／出口 | 写入范围 | 调用方动作 |
|---|---|---|---|
| 输入/payload 解析或对象校验失败 | `BAD_ARGS`、`PRD_NOT_FOUND` 类既有 code | 零业务写入 | 修合法输入后重跑 |
| 来源/权限/绑定/路径冲突 | `WORKSPACE_CONTEXT_MISMATCH`、`WORKSPACE_REQUIRED`、`CR_WORKSPACE_BINDING_UNAVAILABLE` | 零业务写入，启动前失败关闭 | 由合法来源/平台纠正，不清绑定 |
| 操作重放输入冲突 | `TX_INPUT_CONFLICT` | 不覆盖原意图，零新副作用 | 核验原操作后走恢复入口 |
| 锁/CAS/事务失败 | `TX_LEDGER_RECOVERY_REQUIRED`、锁超时既有 code | 回滚或按 durable recovery 固定恢复 | 按结构化恢复指令恢复同一操作 |
| review 提交失败 | `REVIEW_COMMIT_FAILED` 类既有 code（非零） | 回滚本次账本与暂存影响，保留 payload | 恢复同一操作，不重评、不再 bump |
| commit 后事件阶段中断 | 既有事务恢复路径 | 保留真实已提交事实 | 按原事务恢复事件与完成事实 |
| dirty/分叉/冲突/环境或同步故障 | 既有技术错误（`ENVIRONMENT_MISMATCH` 等） | 不写业务 BLOCK | 原合法环境修复/同步/报告 |
| 证据在审批后被改动 | `EVIDENCE_DRIFT` | 零写入 | 见 §4.5：合法本地漂移降级 warning，其余仍硬阻断 |
| 测试数量下降 | 新增 warning `SUITE_COUNT_BELOW_BASELINE_WARN` | 不阻断 | 显式维护登记，不自动改基线 |

### 3.3 Skill / Pipeline 合同

| 对象 | 变更 |
|---|---|
| `pipeline-templates/code-implementation.pipeline.json` | 移除 `human_approval`（确认进入代码开发）与 `approve-dev-start` 节点；`review-dev-plan` PASS 后由 `write-dev-tasks` 收尾并经既有 `advance` 进入 `developing`（`dep-25`） |
| `gates.json#statusGates.developing` | 去掉 `passCondition: dev-start` 与 `approval: development-start`；保留 plan/tasks 存在性与 globNonEmpty（`dep-24`） |
| `gates.json#approvalStages.dev-start` | 保留（旧调用兼容），不再是默认必经 |
| `dir-graph.yaml#change-request-track.state_machine` | `task-breakdown → developing` 的触发改为「review-dev-plan PASS 后收尾」，保留 `approve-dev-start` 兼容转换；状态集合与转移统计口径按 `dep-26` 记录（`SDD-CLOSE-07`） |
| `pipeline-templates/requirement-authoring.pipeline.json` | `source` 取消 `required: true`，与空值语义一致；owner 输入示例改为 `user_id`（`dep-29`） |
| Skill 同步清单 | 见 §8 |

### 3.4 平台内部接口（multica）

| 接口 | 变更 |
|---|---|
| `parseExecutionContext` | 不变：仍只认触发评论中唯一 `execution_context` fenced YAML 块；多块/重复键/非法值 → `CR_WORKSPACE_BINDING_UNAVAILABLE`（`dep-4`） |
| `resolveTaskWorkspaceBinding` | 新增解析段：无 `execution_context` 时先取 task 的正式 CR 关联，唯一则用；否则取当前来源 Issue 的唯一正式 CR 关联，唯一则用；多关联或冲突 → 显式要求合法输入（`dep-5`、§4.1） |
| `configureTaskGitEnvironment` | 生成叠加式 trust 配置（safe.directory + include 原全局配置），不替换用户身份（`dep-6`、§4.2） |
| `findPipelineCRRoot` / `inspectPipelineWorkspace` | 不变：仍做 CR 根唯一性与 `healthy` 预检；错误根一律拒绝（`dep-7`） |
| `CRCTL_TASK_AUDIT_ROOT` 消费 | 不变：审计根与操作根可不同（`dep-30`） |

### 3.5 HTTP / REST 契约

**N/A**：本 CR 不新增或修改 HTTP endpoint、request/response；NFR-01 明示不定义新 HTTP API、通用授权框架或第二执行入口。平台侧的上传入库 source 桥接与创建入口交互复用既有通道（`dep-31`），不新增状态码。

---

## 4. 关键算法与流程

### 4.1 启动绑定归一与预检（FR-01、FR-SUP-05、FR-SUP-06、FR-SUP-07）

判定顺序（任一步失败即失败关闭，不做业务纠正、不自动重试、不切执行器）：

```text
1) 若触发评论声明 execution_context：
     a. 解析唯一 fenced YAML 块（多块/重复键/非法 → CR_WORKSPACE_BINDING_UNAVAILABLE）
     b. local_directory 必须唯一（0 个或多个 → 拒绝）
     c. findPipelineCRRoot(a, cr_id) 必须唯一命中（0 或 >1 → 拒绝）
     d. inspectPipelineWorkspace 必须 operationalWorkspace 与声明逐字同根
     e. 【新增】声明的 cr_id 必须与 task/来源 Issue 的正式 CR 关联一致；不一致 → 拒绝
2) 若无 execution_context：
     a. 【新增】取 task 的正式 CR 关联；唯一 → 用
     b. 【新增】否则取当前来源 Issue 的唯一正式 CR 关联；唯一 → 用，并输出 BINDING_INHERITED_WARN
     c. 多关联/冲突/显式 CR 信号但无可确认目标 → 请求既有合法输入（不猜 CR、不扫历史评论）
     d. 无 CR 信号 → 保持既有普通任务行为
3) 绑定产物：CRCTL_OPERATIONAL_WORKSPACE（操作根 realpath）、CRCTL_TASK_AUDIT_ROOT（审计根）、MULTICA_TASK_ID
4) crctl 侧 bindTaskWorkspace：三元组不完整/异根 → WORKSPACE_CONTEXT_MISMATCH（零业务写入）；
   显式 --workspace 与绑定异根 → 同样拒绝（绑定不可被覆盖）
```

边界：

- 只接受「真实目录」判定（`realpath` 后仍为目录）；`\\?\` 前缀与尾分隔符按同一目录的合法别名各剥一层（`dep-1`）。
- 错误根防线（FR-SUP-06 本 CR 部分）：路径存在、同安装根均**不构成**通过理由；必须同时满足项目归属、CR、阶段 authority、资源健康。
- 注册阶段（尚无 CR worktree）：只绑定 knowledge-base 主 checkout，不猜 CR-ID、不拿旧 CR worktree 充当注册根；CR 创建后只消费 `register` 返回的 `cr_id` 与 `operational_workspace`，并经 `workspace inspect` 复核。
- 作者/评审者开工检查（FR-SUP-07）：业务写入前消费 `workspace inspect`／`status`／`next`，不以「命令成功」或「next 能看到 PRD」单独证明绑定正确；失败即停止写入。

### 4.2 任务 Git trust 叠加（FR-02）

```text
生成 <CR 根>/.crctl/task-gitconfig：
  [safe] directory = <CR 根 realpath>      # Git 原生 trust 叠加
  [safe] directory = <operational realpath>
  [include] path   = <原全局配置 realpath>  # 保留原配置与身份加载链
注入 GIT_CONFIG_GLOBAL = 该文件
```

- 禁止：改写用户全局姓名/邮箱、把身份替换为机器人兜底、设置非 Git 原生的 trust 旁路。
- 身份不可用（原全局配置中 `user.name`/`user.email` 均缺失，身份加载链见 `dep-6`）时，正常新操作必须在账本写入前报环境问题；已有未完成事务按原恢复合同处理，**不得**把环境错误记成业务 BLOCK。
- 原全局配置路径解析：`git config --get` 既有白名单形态不可读全局路径时，回退读取进程启动前的 `HOME`/`USERPROFILE` 下标准位置；两者皆不可判 → 技术失败（不猜、不写死）。

### 4.3 review-record 原子闭环（FR-03）

```text
前置核验 → payload/对象校验 → 实际 write-set 构造 → durable transaction + CAS
  → 整个 index 的隔离断言（porcelain 输出不得含 write-set 之外的路径）
  → 仅本次实际 files[] 的隔离提交 → finishLedgerTransaction → 发含真实提交 SHA 的 outbox → 成功返回
```

- `PASS` 无 bump：write-set = annotation + traceability；`PASS` 有 bump：额外纳入 `review-loop.yml`。
- 失败：非零返回，回滚本次账本写入与**本次暂存影响**（不夹带、不丢弃作者或其他任务的变更），保留原 payload；不发成功事件、不推进下一节点。
- commit 后崩溃：按已提交事实恢复；**不重新评审、不再 bump**；事件引用真正包含评审账本的 SHA。
- 恢复固定原 CR、loop／cycle／attempt、被评审对象、verdict/blockers、payload、bump 意图与本次 write-set；输入或对象被替换不得当作同一次操作的新执行。幂等识别复用既有事务键与意图摘要（`dep-13`），**不引入第二幂等账本**（`SDD-CLOSE-01`）。
- 本地提交不等于远端发布：远端仍由 `checkpoint`／`push-progress` 完成；`advance` 保持状态职责，不自动 add 整个 CR、不代提交作者代码。

### 4.4 `next` 判定优先级与普通 BLOCK 回修（FR-04）

```text
优先级：① upstream 路线（review-dev-plan:upstream-design-blocker → write-tech-design）
        → ② 耗尽等待合法人类继续（LOOP_EXHAUSTED → humanApproval=true，不自动放行）
        → ③ 普通 BLOCK 回修
对象变化判定（复用既有 subject／composite digest）：
  - 对象已变 + 作者已收尾（plan/tasks 实际提交且状态合法）→ 建议独立复评（review-dev-plan / review-code）
  - 对象未变 → 继续回修，不重复拆任务
  - 必需产物缺失／摘要不可计算 → 原修复或技术失败；无旧摘要不推断"已修好"
```

- 不要求全量重拆、不固定每轮提交次数、不允许 `write-dev-plan` 冒用 `write-dev-tasks` 尚未完成的职责。
- 工具、Skill、矩阵、模板与实际导入 instructions 同步后，关闭按 CR-ID／cycle 写死的临时例外（§8）。

### 4.5 合法本地信任与漂移降级（FR-05）

**本地信任适用范围**：仅当来源、stage 与归属合法（`approval.yml` 该 section 无 server-approve 签名事实、CR/阶段与当前操作根一致、责任角色匹配）时才按本地批准处理；来源缺失、未知或非法**不得**默认为本地。

| 情形（合法本地路径） | 结果 |
|---|---|
| PRD/SDD/PLAN/TASK 正文漂移 | warning `LOCAL_TRUST_DOC_DRIFT_WARN`，不撤销批准、不重签、不强制重审 |
| TASK 集合增删 | warning `LOCAL_TRUST_TASK_SET_DRIFT_WARN`，同上 |
| 工具升级带来的证据定义变化 | warning `EVIDENCE_DEFINITION_DRIFT_WARN` |
| 合法存量 PASS 缺 `subject-sha256` | 提示继续 `LEGACY_SUBJECT_MISSING_WARN`，不补造摘要/新 PASS/新签名 |

**仍硬阻断**：必需文件缺失、索引/依赖/记录结构非法、最新真实 BLOCK、blockers 非空、真实测试失败、server-approve 签名/摘要/源绑定不符。

一致性要求：`gate`、`validate`、`next`、`approve`、`merge` 对同一事实必须给出同一结论；单独 warning 不触发 `onFail`、不造成失败退出，也不在后续同一漂移上再阻断；有真实错误时仍失败。保持既有字段类型，warning 只用既有可扩展数组形式，不新增提示次数账本。

**server-approve 路径严格不变**：`grantCanonicalString` 与 Ed25519 验签、`approval.yml` 六字段精确比较、`EVIDENCE_DRIFT` 在 grant 重核路径的硬失败全部保留（`dep-20`）。

### 4.6 默认 coding 取消重复开发启动确认（FR-06）

- 默认编码路径的必经节点变为：设计批准 → PLAN/TASK 完整 → `review-dev-plan` PASS 且 blockers 空 → 资源与实际 readiness → 经既有 `advance` 进入 `developing`。不再插入独立 `human_approval`／`approve-dev-start`。
- `developing` 门禁保留 plan/tasks/globNonEmpty 与 readiness；**不伪造** development-start 批准，不写入 `approval.yml#development-start`。
- 旧审批调用与历史记录兼容；`approve-dev-start` Skill 保留但不在默认路径上必经。
- 本 CR **自身**按其执行时合法有效的旧合同运行，不自我减负、不预先使用未发布的新门禁授权。

### 4.7 人类继续一次一 cycle（FR-07）

```text
判定顺序：① 认证来源与权限（平台已认证人类触发事实 + 既有角色权限，不认 Agent 自报人类、不认仅 --confirm）
        → ② 当前 CR/loop/耗尽事实（LOOP_EXHAUSTED；未耗尽 → LOOP_NOT_EXHAUSTED）
        → ③ 目标唯一性（唯一 → 普通"继续"即可表达；不唯一 → 明确询问，不固定措辞）
        → ④ 原指令的重放/恢复事实（同一来源指令在同一明确目标操作范围只授权一次）
        → ⑤ 明确 cycle 转换（current-cycle+1，attempt 归零，历史 attempts 保留）
```

- 授权事实写入既有审计（`.crctl/audit.log`）与既有恢复依据；不新增票据服务、权限数据库或常驻调度器。
- 失败可恢复同一操作；成功重投不得再增 cycle；下一次耗尽必须有新的人类指令，旧评论**不得**重解释为无限授权。
- 新 cycle 不清真实 blockers，不代表业务批准。
- TTY 直连模式保留；两条路径汇合到同一写入缝。

### 4.8 单一 Git tree 内容比较缝（FR-08、FR-09、FR-11）

```text
compareTree(ws, cr, {purpose}) → { perRepo: [{repo, refA, refB, equal, reason}], allEqual }
  purpose=g05: 被评审/批准代码源 vs 当前已提交源
  purpose=g06: 测试报告记录的源 vs 同步后源
判据：git rev-parse <refA>^{tree} 与 <refB>^{tree} 相等（整个 tree：代码、测试、README、配置）
      不可判（对象缺失/工作区不健康/多仓任一不可判）→ 不宣称全仓等价
```

- 两个消费目的共用同一实现（单一缝），不设扩展名白名单、不设 `codeRoot`、不做语义哈希。
- SHA 继续承担历史追溯与发布事务身份；内容等价不抹掉版本信息（tree 相等 ≠ SHA 相等）。
- 知识仓其他 CR 的已提交账本变化**不**算当前代码资源变化；当前 CR artifact 按合法本地/server-approve 规则分别核验。
- G05 合入：tree 相同 → 允许以额外空提交等内容等价源推进，不因 HEAD 不同回实现；tree 不同 → 先更新测试/代码评审证据并执行必要的原代码确认，不得直接合入。
- 代码源不可判（FR-11）：先沿既有读取/同步路径恢复原 Git 对象；仍不可判则建立新测试、代码评审与必要代码确认事实，**不以当前 HEAD 补造历史 source**、不伪造原批准、不无理由重做实现。
- 多仓（FR-08.4）：逐仓结论、逐仓 path authority 取 `resources[].worktreePath`；提交口径按各仓 worktree 分别提交、同批 checkpoint 纳管。

### 4.9 freshness 最小重验（FR-10）

```text
实施前 gate=implement-start：
  fresh / behind-clean → 继续（必要同步后继续尚未开始的实施）
评审前 gate=review-start：
  tree 与有效测试源相同 → 接续现有评审，不因同步重复实现/测试
  tree 改变 → 先走既有 write-test-report 与 review-code 节点
  仅真实测试/评审失败 → 回 implement-code
dirty / 分叉 / 冲突 / 同步失败 / 环境不匹配 → 既有失败合同（技术中止不计业务失败）
```

等价比较**不替代**有效报告、日志、真实退出码与 verdict；不把未执行验证宣称已测。不新增 CR 状态、不建完整执行器、不加后台重试。

### 4.10 发布事务与发布意图固定（FR-09）

- 新发布事务固定**本次实际发布 source**；已有产生副作用的 journal 按原意图与 source 恢复，后来的等价 HEAD 或文档变化不得改变进行中的发布对象。
- 一致面：批准入口、release-subjects 构造与重核、`merge` 远端源预检、后续 publish 消费者必须同一口径，**不得只放宽单个 helper**（`dep-14`、`dep-15`、`dep-21`）。
- 本地提交不等于远端发布；`checkpoint` 负责远端事实与发布结果。

### 4.11 CI 数量门禁与既有红例收敛（FR-12）

- 逐文件用例数低于登记基线 → warning `SUITE_COUNT_BELOW_BASELINE_WARN`（不阻断）。
- 仍失败：必需文件零有效执行、少跑/未登记文件、文件集合不一致、加载失败、TAP 不可判/未收敛、真实未豁免失败、登记 schema/基线字段/例外结构或期限非法。
- 沿用 manifest、suite report 与 exceptions（`dep-22`）；显式维护登记，不自动改基线，不建数量审批流程；摘要不得把有效例外中的实际失败说成"所有测试通过"。
- 四个 summary 宿主环境例外（`dep-22` 登记）定点复现：根因是夹具使用系统临时目录 + 显式异根 `--workspace`，被已批准的绑定拒绝语义拒绝。修法：夹具改为**同安装根内**的临时根（或经绑定归一提供操作根），在隔离子进程内复用既有 `baseEnv`；根因转绿后撤销对应例外条目（到期即清、不得静默续期），不造新豁免。不在生产任务全局清可信绑定变量。
- 保留已完成的两处 fixture 修复回归，不重复实施。

### 4.12 Windows 文档链真实扫描（FR-13）

- 文件名提取改用 `node:path.basename`（`dep-23` 的 `file.split("/").pop()` 在 Windows 反斜杠路径下返回整条路径 → 类型判不出 → 文档被静默跳过 → 空扫描假通过）。
- 断言强化：`docCount` 必须 > 0；新增 Windows 原生嵌套路径（`docs\\{sub}\\x.md`）用例证明真实扫描。
- 不新增路径助手/依赖、不改 gate 表达式、不扩建文档链类型或规则体系；使用既有测试入口（vitest）。

### 4.13 实际发布生效与合法执行边界（FR-14）

- 复用维护来源的导入/发布流程，核对 CLI、daemon、Skill/instructions 与必要平台消费者的**实际取用版本**；生产者先兼容新合同、再切消费者（`dep-8`、`dep-30`）。
- 源码合入、构建成功或仓库镜像更新**不单独**算实际交付完成；`plan.md` 必须提前列明所需人类动作、责任方、窗口与可达入口。
- 接受一次明确合法且有边界的人工启动前置；不接受逐节点人肉代跑。正式治理只用已发布、已验证入口；候选 CLI 仅用于隔离 fixture 或明确受控测试。稳定入口不可用则技术中止，不盲目重投。
- 技术中止只修同一环境/事务且不重复 bump；真实 BLOCK 按正常回修；证据 ID 稳定、不机械重编号。

### 4.14 owner 值域校验与契约同步（FR-SUP-01、FR-SUP-02）

```text
写入前（register 与 owner-set 共用同一校验缝）：
  1) 取目标值 → 必须为 UUID 形状（拒绝显示名与错误 ID 类型）
  2) 一次 multica workspace member list 查询 → 按返回的 user_id 命中当前 workspace 成员
  3) 未命中/查询失败 → 技术失败（不伪装"成员不存在"、不猜 ID、不用静态名单兜底）
  4) 同名歧义无法确认 → 停止并要求人工确认，不自动消歧
  5) 通过 → 写入 cr.md 与 _backlog.yml（经既有受控账本通道）
错误语义：owner-set 的失败命名为 owner-set 失败，register 的失败命名为注册失败，不互相冒名。
```

- 三角色可指向同一成员；`membership ID` 与 `user_id` 同为 UUID 形状，故仅校验形状不足够（`dep-32`）。
- 已有 CR 的 owner 纠正只经 `handover-cr`／`owner-set` 受控流程，由有权限责任方执行并留痕；保留原始注册参数不等于冻结现任 owner；同值重放不追加固定数量历史记录。
- 契约同步（FR-SUP-02）：`requirement-register` 参数说明与 Pipeline owner 输入示例改为 `user_id` 口径，删除可被误抄为 ID 的示例（§8 清单）。

### 4.15 source 自动绑定与校验（FR-SUP-03、FR-SUP-04）

| 创建需求时 | 行为 |
|---|---|
| 成功上传一个主来源文档 | 复用既有附件读取/入库能力保存到知识库，自动把相对路径传给 `register.source`；确保随后派生的 CR worktree 实际可读 |
| 未上传，或注册前移除 | `source` 缺省或空串统一持久化为 `""`；writer 使用标题、摘要与已确认上下文 |
| 上传、读取或保存失败 | 明确失败并停止注册，不静默降级为无文档 |

- 校验缝（注册事务持久化前）：containment（不得仅凭字符串前缀，须处理相邻目录前缀与符号链接越界）+ 文件存在/可读 + 目标为后续知识库 worktree 可读路径；writer 保留**使用时**的同一检查防线，不因"入口已校验"删除。
- 禁止把附件 ID、下载 URL、Issue 标识、显示名、任务临时路径当作 `source`；不新增 OCR/通用转换/多文件聚合；`source` 不扩为数组。
- 保留规划流程/CLI 传入合法知识库来源文件路径的能力；「未上传为空」是本入口默认行为，不等于禁止既有规划报告作为来源。
- 注册失败的零写入保证**不要求**删除此前成功上传的原件。

### 4.16 历史事实只读扫描（FR-SUP-08）

- 一次性只读扫描（版本化脚本 + `validate` 只读维度），列出非终态 CR 的 owner 身份异常与 `source` 路径异常，每项至少给出 CR-ID、字段/角色、原值与异常原因；状态从 `cr.md` 读取，不假定 `_backlog.yml` 含 status。
- 只报告、不自动修复、不阻塞无关 CR、不建定时巡检/缓存/名单系统。修复只经既有受控入口由人工裁决。

### 4.17 PRD 交接完整性（FR-SUP-09）

- 本 PRD 已实质覆盖 AC-SUP-01～AC-SUP-10 并保留原 FR/AC 编号（逐条核对见 §6）；`prd-path` 指向分支内实际存在的 PRD 文件；checkpoint 结果据实报告。
- 本条在本 CR 的实现形态是 writer 自审 + 独立需求评审的交付检查（已由 `review-annotations/requirement.yml` 落地），**不**建设语义覆盖检查器、不扩大为平台新功能。

## 5. 技术选型与替代方案

### D-01 Git trust 用原生 include 叠加，不替换全局配置

- **Decision**：`task-gitconfig` 写入 `[safe] directory` + `[include] path=<原全局配置>`，注入 `GIT_CONFIG_GLOBAL` 指向该文件。
- **Context**：`dep-6`（当前实现）把 `GIT_CONFIG_GLOBAL` 指向仅含 safe.directory 的文件，等效于把用户全局配置整份换掉，姓名/邮箱等身份事实丢失（FR-02/AC-04 要保留）。
- **Alternatives**：(a) 追加 `user.name`/`user.email` 到生成配置——会把身份复制成第二事实源，用户在全局配置里的改动不再生效，且引入机器人兜底风险；(b) 用 `git -c safe.directory=...` 逐命令注入——`-c` 在受控 shell 白名单里是 forbiddenFlags（`dep-27`），会被 guard 拒绝；(c) 直接改用户全局配置——违反 FR-02 明文禁止。
- **Consequences**：身份链保持单一来源；代价是依赖 Git 的 `include` 语义与全局配置路径可解析，路径不可判时按技术失败中止（不猜）。

### D-02 tree 等价比较放在 `workspace-transactions.mjs` 的单一缝，不在 crctl 内双实现

- **Decision**：新增一个导出的 `compareTree`，G05（合入）与 G06（同步后重验）共用；crctl 与 Skill 只消费结论。
- **Context**：两个消费目的判据完全相同（整个 Git tree 内容比较），分开实现会产生两套等价语义与两套夹具（FR-08 明确要求共用）。
- **Alternatives**：(a) 各自实现——两处漂移风险，且 NFR-03 要求等价场景不新增实现轮次；(b) 在 Skill 层描述比较步骤——Skill 不得承载账本/对象级判定，会把判定交给模型自觉。
- **Consequences**：比较缝成为唯一判定点，测试可单点覆盖；不可判必须显式返回不可判，禁止默认等价。

### D-03 人类继续以「认证触发事实」为输入，不用 `--confirm` 或 TTY 作为唯一通路

- **Decision**：`review-loop reset` 增加 `--continue-reason`，授权事实来自 daemon 注入的平台认证触发事实（人类成员）与既有角色权限；TTY 直连模式保留。
- **Context**：`dep-20` 当前仅接受交互式 TTY，平台派发的 Agent run 无法表达「人类已说继续」，与 FR-07 的认证来源要求不匹配；仅加 `--confirm` 等于让 Agent 自报人类。
- **Alternatives**：(a) 保持 TTY 独占——FR-07/AC-15 不可达；(b) 只加 `--confirm`——明确被 FR-07 排除（不承认 Agent 自报人类）；(c) 新建票据服务——违反 PRD §7 范围排除。
- **Consequences**：授权事实进入既有审计与恢复依据；非认证来源（Agent 自报、无 actor 的普通评论）一律不授权。

### D-04 local trust 漂移降级为既有 `warnings[]`，不新增计数账本

- **Decision**：FR-05 的减负以既有 `{code,message}` 数组形式表达（`dep-19`），不新增提示次数/提交账本。
- **Context**：`dep-19` 已在 `status` 输出上稳定使用该形式；PRD NFR-04 要求保持既有字段类型与 warning 扩展形式。
- **Alternatives**：(a) 新增专用计数/账本——违反范围排除；(b) 复用不同义 code 混在 `blockers` 里——会污染 PASS 条件（`evaluatePassCondition` 依赖 blockers 为空）。
- **Consequences**：warning 与 blocker 严格分流；`gate`/`validate`/`next`/`approve`/`merge` 对同一事实必须同判（AC-10）。

### D-05 Windows 文档链修复用 `node:path.basename`，不引入路径助手

- **Decision**：只替换 `dep-23` 的文件名提取并强化断言（docCount > 0 + 原生嵌套路径用例）。
- **Context**：`dep-23` 用 `/` 分割 Windows 反斜杠路径，类型判定失败 → 文档被静默跳过 → 空扫描假通过。
- **Alternatives**：(a) 归一化为 POSIX 再 split——多一层易漏的转换，且命名链路上还有其它消费点；(b) 引入 `path-browserify` 类依赖——违反零依赖不变量与 FR-13 明文。
- **Consequences**：修复面最小；docCount 成为「真实扫描」的可观测证据。

## 6. FR / AC 到技术实现映射

### 6.1 FR → 技术方案

| FR | 技术方案落点 | 交付仓 |
|---|---|---|
| FR-01 机器保证启动前可信绑定 | §4.1 判定顺序；平台侧 `resolveTaskWorkspaceBinding` 新增 task/来源 Issue 关联段（`dep-5`）；crctl 侧 `bindTaskWorkspace` 保持失败关闭（`dep-1`） | multica + tools |
| FR-02 任务 Git trust 保留用户身份 | §4.2 + D-01；`configureTaskGitEnvironment` 叠加式配置（`dep-6`） | multica |
| FR-03 review-record 原子闭环 | §4.3；`cmdReviewRecord` 的 write-set/隔离提交/恢复（`dep-12`、`dep-13`） | tools |
| FR-04 普通 BLOCK 与 next 一致 | §4.4；`cmdNext` 优先级与对象变化判定（`dep-16`、`dep-17`） | tools |
| FR-05 合法本地信任贯通 | §4.5 + D-04；`runGateChecks`/`cmdApprove`/`cmdValidate`/`cmdMerge` 同判（`dep-18`、`dep-19`） | tools |
| FR-06 默认 coding 取消 dev-start | §4.6；Pipeline 模板、`gates.json`、状态机、Skill/矩阵同步（`dep-24`～`dep-26`） | tools |
| FR-07 人类继续一次一 cycle | §4.7 + D-03；`cmdReviewLoopReset` 认证来源判定与幂等（`dep-20`） | tools + multica（注入事实） |
| FR-08 共用 tree 比较缝 | §4.8 + D-02；`compareTree` 单一缝（`dep-14`） | tools |
| FR-09 合入对象与发布意图核验 | §4.8、§4.10；`cmdMerge` 等价推进与发布 source 固定（`dep-15`、`dep-21`） | tools |
| FR-10 同步后最小重验 | §4.9；freshness 输出与 `workspace-freshness` Skill 路由（`dep-7`） | tools |
| FR-11 代码源不可判时恢复或新建证据 | §4.8 恢复分支；先复原对象、否则新建测试/评审事实 | tools |
| FR-12 数量下降告警与红例收敛 | §4.11；`suite-gate` + `gate-registry.json` 例外收敛（`dep-22`） | tools |
| FR-13 Windows chainCheck | §4.12 + D-05；`chain.ts` 文件名提取与断言（`dep-23`） | tools |
| FR-14 实际发布生效与执行边界 | §4.13；已发布入口核对与 plan 人类动作清单（`dep-8`、`dep-30`） | tools + multica（核对面） |
| FR-SUP-01 owner user_id 与写入前校验 | §4.14；`cmdRegister`/`cmdOwnerSet` 共用校验缝（`dep-31`、`dep-32`） | tools |
| FR-SUP-02 owner 契约与示例同步 | §4.14、§8；register Skill + Pipeline 输入示例（`dep-29`、`dep-33`） | tools |
| FR-SUP-03 source 自动绑定与空值语义 | §4.15；创建入口 + `register.source` 持久化语义 | tools |
| FR-SUP-04 source 注册前/使用前校验 | §4.15；containment + 可读性双防线 | tools |
| FR-SUP-05 注册阶段与阶段根交接 | §4.1、§4.14；注册节点绑定 KB 主 checkout，返回后经 `workspace inspect` 复核（`dep-7`、`dep-26`） | multica + tools |
| FR-SUP-06 错误根防线（本 CR 部分） | §4.1；启动前失败关闭与错误根拒绝（`dep-5`、`dep-7`）；reviewer 派发部分按 §1.2 移交 AIFI-60 | multica |
| FR-SUP-07 开工检查与诊断安全合同（本 CR 部分） | §4.1；`workspace inspect`/`status`/`next` 只读核对 + `WORKSPACE_CONTEXT_MISMATCH` 失败关闭（`dep-1`、`dep-2`） | tools |
| FR-SUP-08 历史事实一次性检查 | §4.16；版本化只读扫描 + `validate` 只读维度（`dep-19`） | tools |
| FR-SUP-09 PRD 交接完整性与节点完成判定（本 CR 部分） | §4.17；`prd-path` 与实际文件一致、checkpoint 据实报告；节点完成判定移交 AIFI-60 | knowledge-base（产物） |

### 6.2 AC 逐项设计与验收映射

**AC-01**（FR-01）
- 设计落点：§4.1 判定顺序 2a；`resolveTaskWorkspaceBinding`（`dep-5`）+ `CRCTL_OPERATIONAL_WORKSPACE` 注入（`dep-6`）。
- 可观测结果：无手工根声明的评论触发的任务，其环境出现三元组，且 `crctl workspace inspect` 的 `operationalWorkspace` 与该根同根。
- 可达性说明：task 的正式 CR 关联存在时先于来源 Issue 分支命中，不被 `execution_context` 缺失提前过滤。

**AC-02**（FR-01）
- 设计落点：§4.1 判定顺序 2b/2c/2d。
- 可观测结果：仅来源 Issue 有唯一正式 CR 关联时绑定成功并带 `BINDING_INHERITED_WARN`；多关联时非零退出要求合法输入；无 CR 信号任务绑定为空且行为不变。
- 可达性说明：三条分支互斥且覆盖「唯一/多/无」，不存在被前置条件吞掉的中间态。

**AC-03**（FR-01）
- 设计落点：§4.1 步骤 1e 与 4；错误出口 `CR_WORKSPACE_BINDING_UNAVAILABLE`/`WORKSPACE_CONTEXT_MISMATCH`（`dep-2`）。
- 可观测结果：冲突场景在启动/业务写入前非零退出，CR 账本无变化；归档 CR 的新任务重新解析当前 authority。
- 可达性说明：冲突判定先于任何账本写入，且不依赖 worktree 是否仍存在。

**AC-04**（FR-02）
- 设计落点：§4.2 + D-01。
- 可观测结果：任务内 `git commit` 成功且提交作者为原全局配置姓名/邮箱；任务外对照全局配置文件未被修改；身份缺失时错误发生在新账本写入之前。
- 可达性说明：`[include]` 使身份来自原配置，不因 trust 配置注入而被遮蔽。

**AC-05**（FR-03）
- 设计落点：§4.3 write-set 构造与隔离提交（`dep-12`、`dep-13`）。
- 可观测结果：四种组合各自产生对应 2 或 3 个账本文件的隔离提交，`HEAD` 与 outbox 事件含同一真实 SHA；远端 ref 不变。
- 可达性说明：write-set 由实际落盘文件构造，不依赖模型选择。

**AC-06**（FR-03）
- 设计落点：§4.3 失败分支；隔离断言（`dep-12`）。
- 可观测结果：存在不相关暂存或作者变更时非零退出、暂存与本次账本回滚、payload 保留、无成功事件。
- 可达性说明：隔离断言检查整个 index，先于 commit 执行。

**AC-07**（FR-03）
- 设计落点：§4.3 commit 后恢复分支；事务键与意图摘要（`dep-13`，`SDD-CLOSE-01`）。
- 可观测结果：重投返回幂等成功且不产生第二次提交/attempt；事件指向真实提交。
- 可达性说明：恢复先识别原意图与完成事实，再决定恢复或幂等返回。

**AC-08**（FR-03）
- 设计落点：§4.3 对象变化分支。
- 可观测结果：原对象被替换时非零技术中止，annotation 中 verdict 与 subject 保持原值。
- 可达性说明：判定以记录的对象摘要与当前对象比较，不重算后覆盖。

**AC-09**（FR-04）
- 设计落点：§4.4 优先级与对象变化判定（`dep-16`、`dep-17`）。
- 可观测结果：`crctl next` 在对象已变且收尾完成时返回独立复评节点；对象未变返回回修节点；upstream/耗尽优先返回对应节点或 `humanApproval=true`。
- 可达性说明：`next` 直接读取当前证据与摘要，结论不依赖人工传递。

**AC-10**（FR-05、FR-09）
- 设计落点：§4.5 + D-04；`runGateChecks`、`cmdValidate`、`cmdNext`、`cmdApprove`、`cmdMerge` 同判（`dep-18`、`dep-19`、`dep-15`）。
- 可观测结果：正文/TASK 集合/证据定义漂移时五个入口均输出 `warnings[]`、退出码 0、批准段保持有效；后续同一漂移不再阻断。
- 可达性说明：warning 与 blocker 分流，`evaluatePassCondition` 只看 verdict/blockers，不受 warning 影响。

**AC-11**（FR-05）
- 设计落点：§4.5 `LEGACY_SUBJECT_MISSING_WARN`；`dep-16` 的 legacy 兼容分支。
- 可观测结果：缺 `subject-sha256` 的存量 PASS 得到提示且流程继续，annotation 不被补写。
- 可达性说明：判据只取「记录存在 + 缺摘要」，不要求重签。

**AC-12**（FR-05、FR-06、FR-10）
- 设计落点：§4.5「仍硬阻断」清单；§4.9 技术失败合同。
- 可观测结果：缺件/结构非法/最新 BLOCK/blockers 非空/真实测试失败仍非零退出，warning 不掩盖。
- 可达性说明：硬阻断与 warning 的判定输入不同（文件存在性/结构/verdict 与漂移类别），不互相覆盖。

**AC-13**（FR-05、FR-09）
- 设计落点：§4.5 server-approve 分支；验签与六字段比较（`dep-20`）。
- 可观测结果：签名/摘要/源绑定/归属任一变化时仍非零拒绝，`approval.yml` 不被改写为本地批准。
- 可达性说明：本地放宽分支以「无签名事实」为前置，签名事实存在时不进入。

**AC-14**（FR-06）
- 设计落点：§4.6；Pipeline 模板、`gates.json`、状态机（`dep-24`～`dep-26`），§8 同步清单。
- 可观测结果：新合同下 `task-breakdown → developing` 无需 `approval.yml#development-start`；`approval.yml` 不出现伪造段；旧审批记录仍可读；本 CR 自身仍按旧合同运行。
- 可达性说明：`developing` 门禁保留 plan/tasks/readiness 判定，移除的只是额外人工确认，不引入新前置。

**AC-15**（FR-07）
- 设计落点：§4.7 + D-03；`cmdReviewLoopReset` 五步判定（`dep-20`）。
- 可观测结果：认证人类在目标唯一时「继续」后 `review-loop.yml` 的 cycle +1、attempt 归零、历史 attempts 保留；目标不唯一返回询问；Agent 自报或仅 `--confirm` 非零拒绝。
- 可达性说明：认证事实来自平台注入，先于 cycle 判定读取。

**AC-16**（FR-07）
- 设计落点：§4.7 第 ④ 步与幂等要求。
- 可观测结果：同指令重投不增 cycle；失败恢复同一操作；无新指令时 `LOOP_EXHAUSTED` 保持；blockers 不被清除。
- 可达性说明：授权事实在事务内先识别既有完成事实，再决定恢复或返回。

**AC-17**（FR-08、FR-09）
- 设计落点：§4.8 `compareTree` purpose=g05；§4.10 发布核对（`dep-14`、`dep-15`）。
- 可观测结果：HEAD 不同但 tree 相同的多仓逐一给出 `equal=true`，`merge` 以等价源继续，SHA 仍出现在追溯与发布记录中。
- 可达性说明：tree 比较只取对象摘要，不要求 HEAD 相等；签名与远端检查在合并前仍执行。

**AC-18**（FR-08～FR-10）
- 设计落点：§4.8 tree 不同分支 + §4.9 路由。
- 可观测结果：代码/测试/README/配置任一变化使 `equal=false`，流程回到 `write-test-report`/`review-code`，仅真实失败回 `implement-code`。
- 可达性说明：比较覆盖整棵 tree，不受扩展名过滤影响（无白名单设计）。

**AC-19**（FR-10）
- 设计落点：§4.9 两条 gate 分支（`dep-7`）。
- 可观测结果：同步后 tree 相同 → 接续既有评审；不同 → 产生新测试/复评步骤；实施前同步 → 继续未开始实施；dirty/分叉/冲突/环境不匹配 → 既有技术失败输出。
- 可达性说明：gate 判定输入为 `resources[].classification` 与 tree 结论，二者独立可得。

**AC-20**（FR-11）
- 设计落点：§4.8 不可判分支。
- 可观测结果：对象可恢复时按原对象继续；不可判时产生新测试/复评/确认事实，不出现「以当前 HEAD 补造历史 source」的记录。
- 可达性说明：恢复先于新建证据，判定顺序固定。

**AC-21**（FR-05、FR-08、FR-09）
- 设计落点：§4.8 比较范围界定；§4.5 本地 artifact 判定。
- 可观测结果：仅知识仓其他 CR 账本变化时 G05 结论仍为等价；当前 CR artifact 变化按 AC-10 处理。
- 可达性说明：代码资源集合来自仓库声明（`dep-14`），知识仓账本不在代码资源集合内。

**AC-22**（FR-09）
- 设计落点：§4.10 journal source 固定；发布消费者一致面（`dep-14`、`dep-15`）。
- 可观测结果：部分 publish 后出现等价 HEAD/文档变化时，恢复仍使用原 journal 的 source，不追随新对象。
- 可达性说明：source 在事务开始时固定并持久化于 journal，恢复路径只读该字段。

**AC-23**（FR-12）
- 设计落点：§4.11；`suite-gate` 与 `gate-registry.json`（`dep-22`）。
- 可观测结果：数量下降输出 warning 且退出码 0；少跑/未登记/集合不一致/零执行/加载/TAP/真实失败/非法例外仍非零；四个 summary 例外逐项复现并撤销；summary 文本不再把豁免内失败写成全通过。
- 可达性说明：数量判定与失败判定输入不同（基线与 run 结果 vs 单文件结论），可分别观测。

**AC-24**（FR-13、FR-14）
- 设计落点：§4.12（`chain.ts`，`dep-23`）与 §4.13（已发布入口与 plan 人类动作清单）。
- 可观测结果：Windows 下文档链扫描 `docCount > 0` 且嵌套目录文件名解析正确；发布后在安装环境新 run 上记录 CLI/daemon/Skill/instructions 实际版本与目标行为证据；plan 含人类动作/责任方/窗口。
- 可达性说明：两项互不依赖、可分别观测：前者由既有 vitest 入口判定，后者由安装后 run 的证据判定。

**AC-SUP-01**（FR-SUP-01、FR-SUP-02）
- 设计落点：§4.14 校验缝；`cmdRegister`/`cmdOwnerSet`（`dep-31`）。
- 可观测结果：合法 `user_id` 写入成功，三角色可同值；显示名/membership ID/非本 workspace UUID 非零拒绝且账本不变。
- 可达性说明：校验在持久化前执行，且以成员查询结果为唯一值域。

**AC-SUP-02**（FR-SUP-01、NFR-SUP-01）
- 设计落点：§4.14 第 3 步错误语义。
- 可观测结果：成员查询失败时报技术失败（非「成员不存在」），且零业务写入。
- 可达性说明：错误分类由查询结果可得性决定，不依赖对 ID 的猜测。

**AC-SUP-03**（FR-SUP-03）
- 设计落点：§4.15 上传分支。
- 可观测结果：`cr.md#source` 为知识库内相对路径，CR worktree 内该文件可读，创建界面显示已绑定文件名。
- 可达性说明：绑定在注册持久化前完成，故 worktree 派生后必可读。

**AC-SUP-04**（FR-SUP-03）
- 设计落点：§4.15 空值与失败分支。
- 可观测结果：未上传/移除时 `source == ""`；上传/读取/入库失败时注册停止；不出现 `manual`/Issue key/附件 ID/URL/临时路径；既有规划路径入口仍可用。
- 可达性说明：空值与失败为两条独立分支，均不写入 `manual` 哨兵。

**AC-SUP-05**（FR-SUP-04）
- 设计落点：§4.15 校验缝两处（注册前与使用时）。
- 可观测结果：不存在/非文件/不可读/越界（含相邻前缀与符号链接）非零拒绝；注册后删除文件仍在使用前被拒。
- 可达性说明：containment 用真实路径解析而非字符串前缀，符号链接与相邻前缀均被覆盖。

**AC-SUP-06**（FR-SUP-05～07、NFR-SUP-02）
- 设计落点：本 CR 侧 = §4.1 预检与正确阶段根（`dep-5`、`dep-7`）+ 独立 reviewer 证据闭环（评审走独立 reviewer task，见 §9 `scope_in`）；平台派发部分按 §1.2 移交 AIFI-60。
- 可观测结果：注册后阶段交接取得经预检的正确阶段根；独立评审证据与后续审批读取在同一权威工作区；绑定不完整/错误项目根/显式异根被拒绝。
- 可达性说明：本 CR 只对新注册后交接作必要集成验收，不等待 AIFI-60 部署即可用既有机制完成闭环。

**AC-SUP-07**（NFR-SUP-01、FR-SUP-03、FR-SUP-04）
- 设计落点：§4.15 零写入保证与幂等；`dep-31` 事务边界。
- 可观测结果：校验失败不占用 `registration_key`、不产生账本记录与派生 worktree；缺省与空串等价；同键同输入重放/恢复仍成功；历史 `source` 不被改写。
- 可达性说明：校验位于事务持久化之前，重放路径复用既有意图摘要而非新增校验分支。

**AC-SUP-08**（FR-SUP-02、FR-SUP-08、NFR-SUP-02）
- 设计落点：§4.14、§4.16、§8 同步清单（`dep-29`、`dep-33`）。
- 可观测结果：Skill 与 Pipeline 的 source 空值设置、owner 示例一致（无 `product-owner` 类示例）；只读扫描只输出异常、不改状态；沿用既有测试/fixture。
- 可达性说明：一致性由文本核对 + 既有测试覆盖，不新增测试平台。

**AC-SUP-09**（FR-SUP-05、FR-SUP-06、NFR-SUP-02）
- 设计落点：§4.1 注册分支与 §4.14；`register` 返回 `cr_id`/`operational_workspace` 并经 inspect 复核（`dep-7`、`dep-31`）。
- 可观测结果：新 CR 只在唯一 KB 主 checkout 注册；后续任务启动前绑定其权威 CR 工作区；错误根/旧 worktree/歧义资源在写前被拒；注册进程不被运行中换绑。
- 可达性说明：注册期与在途期的根来源分别为主 checkout 与 `workspace inspect`，两阶段各自唯一。

**AC-SUP-10**（FR-SUP-09、FR-SUP-02）
- 设计落点：§4.17。
- 可观测结果：PRD 实质覆盖 AC-SUP-01～10 且保留原编号，`prd-path` 指向分支内实际文件；checkpoint 结果据实报告。
- 可达性说明：覆盖核对逐条进行（本条即 §6.2 的 AC-SUP 段），不依赖字符串计数。

### 6.3 SDD-CLOSE 关闭项

**SDD-CLOSE-01（幂等指纹与事务键，关闭 FR-03 延后项）**
- 结论：复用 `dep-13` 的 `ledgerTxKey(op, cr, stage)` + `inputDigest`（意图摘要）作为唯一幂等识别；review-record 的幂等事实集合为 {CR, loop, cycle, attempt, 被评审对象摘要, verdict/blockers, payload 摘要, bump 意图, write-set 路径集合}。不新增第二幂等账本、不新增指纹文件；字段键序与编码沿用既有渲染器（YAML 行级改写，LF 归一）。
- 覆盖层：数据生产（payload 组装）→ 存储/传输（journal + 账本）→ 响应（回执 `changed`）→ 消费（重投分支）→ 兼容降级（legacy 无摘要按既有兼容分支）五层均已给出口。

**SDD-CLOSE-02（错误码闭包，关闭 NFR-02 延后项）**
- 结论：见 §3.2；所有新增消费点继承既有 code 与结构化 recovery，映射到 `fail()` 单出口（`dep-28`），不新增同义错误码体系；input/payload 类统一 `BAD_ARGS`，绑定类统一 `WORKSPACE_CONTEXT_MISMATCH`/`CR_WORKSPACE_BINDING_UNAVAILABLE`，事务类统一 `TX_INPUT_CONFLICT`/`TX_LEDGER_RECOVERY_REQUIRED`。

**SDD-CLOSE-03（数据模型，关闭 PRD「数据模型完整性」延后项）**
- 结论：无 DB schema/DDL 变更（§2.1）；文件账本实体与字段见 §2.2，变更仅为值域收紧与 warning 数组扩展。因此不涉及迁移 down 脚本、约束缺失窗口与 DDL 规范。

**SDD-CLOSE-04（多仓路径 authority）**
- 结论：所有仓库路径来自 `resources[].worktreePath`（§1.3）；禁止 `.rayai-worktrees/{repo}/requirement/{cr}` 命名拼接与主工作区回退；审计根可不同于操作根（`dep-30`），不得判为冲突。

**SDD-CLOSE-05（warning 扩展形式）**
- 结论：canonical 形式为 `warnings: [{code, message, ref?}]`（沿用 `dep-19` 的既有数组形式）；code 枚举见 §2.2；禁止计数型字段、禁止新增提示账本；warning 不参与 `evaluatePassCondition`（`dep-18`）。

**SDD-CLOSE-06（人类动作与窗口的承载）**
- 结论：`plan.md`（`write-dev-plan` 产物）承载所需人类动作、责任方、窗口与可达入口，SDD 只固定该承载义务（FR-14）；不新增台账文件。

**SDD-CLOSE-07（状态数口径）**
- 结论：本 CR 引用的状态机口径以 `dep-26` 为准——**15 个具名状态 + 注册前 `(new)`**（口语「16 态」含 `(new)`）；转移**28 条声明，wildcard 展开后 50 条**。本 CR 只改 `task-breakdown → developing` 的触发语义与保留 `approve-dev-start` 兼容转换，**不新增状态**；若新增/调整转移条数，须在实现期以 `dep-26` 的实际内容为准更新本节与 plan，并写明所用口径。

**SDD-CLOSE-08（发布生效核对口径）**
- 结论：交付完成的判据为「安装后新 run 的目标行为证据 + 实际取用版本记录」（CLI、daemon、Skill/instructions、必要平台消费者），源码合入/构建/镜像更新不构成完成；证据 ID 稳定、不机械重编号（§4.13）。

## 7. 安全与性能考量

### 7.1 安全控制点

| 控制点 | 设计 | 不放宽项 |
|---|---|---|
| 绑定与权限 | 权限判断先于业务写入；绑定三元组完整/同根/同目录才放行（`dep-1`、`dep-2`） | 路径 containment、可信根、所有权 |
| 签名路径 | server-approve 的 Ed25519 验签、canonical 串与六字段精确比较保持原样（`dep-20`） | 签名、摘要、源绑定、归属 |
| 事务 | 复用 CAS + durable recovery；等价场景不新增写入口（`dep-13`） | lease、远端源、真实测试失败 |
| 人工边界 | 人类继续以认证触发事实为输入；审批门与角色边界不变 | 人工审批身份、审批门 |
| source 路径 | containment 用真实路径解析（处理相邻前缀与符号链接）；注册前与使用时双防线 | 路径越界 |
| 审计 | 全部状态/账本写入仍追加既有审计与 outbox（`dep-27`、`dep-13`） | 审计不删除、clean 不放松 |

- 明文禁止：不清/不覆盖生产任务的可信绑定变量、不做运行中 rebind、不切第二执行器、不以逐节点人肉代跑代替正式闭环。
- 环境错误（身份缺失、同步失败、dirty/分叉）一律按技术失败，**不得**写成业务 BLOCK。

### 7.2 性能与成本

- 等价判定复用原生 Git 对象（`git rev-parse <ref>^{tree}`）与既有仓库解析，不引入语义扫描、扩展名影响分析、常驻进程或额外依赖。
- 行为成本目标（与 NFR-03 一致，由 AC-10、AC-17 观测）：相同 tree 的同步不触发无理由重测/重实现；同一操作重投不增加 cycle/attempt/提交。
- `next`、`gate`、`validate` 保持纯读判定，不写账本、不发事件；warning 的产生不增加额外 IO。

### 7.3 跨平台与行尾纪律

- 文本读入先 `\r\n → \n` 归一后再哈希/跨行解析；匹配失败硬报错，禁止静默降级为空集合（Windows autocrlf 会改写检出内容）。
- 新增路径处理只用 `node:path`（`basename`/`join`）与既有 realpath 解析，不手写分隔符分割。
- 文档链扫描必须给出非零且准确的 `docCount`，并用原生嵌套路径用例覆盖（`dep-23`、§4.12）。

## 8. Prompt 采纳影响

本 CR 的 diff **会触及** `skills/shared/crctl/scripts/crctl.mjs` 的命令面（既有子命令的判定/参数扩展，`dep-2`）与 Skill/Pipeline 合同，故本节为必填。`skills/shared/controlled-shell/rules.json#protectedPaths.deny` 与 `git` 白名单**不变**（见 §9 `zero_diff`），无 guard deny 面变更。

| Skill / 合同路径 | 现状 | 应改为 |
|---|---|---|
| `skills/develop/approve-dev-start/SKILL.md` | 默认 coding 路径的必经启动确认 | 保留为旧调用兼容入口；默认路径不再必经，说明改为「仅历史/显式调用」 |
| `skills/develop/implement-code/SKILL.md` | 编码前等待 development-start 批准 | 消费 `crctl next` 的 developing 判定与 readiness，不再要求 `approval.yml#development-start` |
| `skills/sync/workspace-freshness/SKILL.md` | 仅输出 fresh/behind-clean/diverged/unknown 路由 | 增补消费 `workspace inspect` 的 tree 等价结论，按 §4.9 的三段路由（接续/最小复评/技术失败） |
| `skills/develop/review-code/SKILL.md` | 漂移即视为阻断 | 按 §4.5 消费 `warnings[]`，仅硬条件失败才 BLOCK |
| `skills/develop/review-dev-plan/SKILL.md` | 同上 | 同上；并让出 `next` 的 upstream/耗尽优先级判定给 crctl |
| `skills/develop/write-test-report/SKILL.md` | 同上 | 同上；测试数量下降改为 warning 观测点 |
| `skills/shared/crctl/SKILL.md` | 子命令与绑定归一说明 | 增补 `review-loop reset --continue-reason`、`validate` 只读维度 `owner-source-anomalies`、`warnings[]` 语义；声明无新增子命令 |
| `skills/requirement/requirement-register/SKILL.md` | owner 输入为角色名示例、`source` 为必填 | owner 改为 `user_id` 口径示例；`source` 允许空值并与自动绑定/失败停止语义一致 |
| `skills/sync/handover-cr/SKILL.md` | owner-set 调用说明 | 增补写入前校验与「owner-set 失败不命名为注册失败」的错误语义 |
| `skills/sync/push-progress/SKILL.md` | checkpoint 调用说明 | 增补发布 source 固定与实际生效核对（§4.10、§4.13） |
| `skills/cr/cr-review-record/SKILL.md` | review-record 调用说明 | 增补原子闭环/恢复语义与「不重评、不再 bump」约束 |
| `skills/shared/controlled-shell/SKILL.md` | 白名单与 deny 面说明 | 无改动（deny 面不变），确认不新增命令面 |
| `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/dev-agent.md`、`agents/quality-reviewer-agent.md`、`agents/requirement-writer.md` | 阶段节点/权限/评审合同 | 按 FR-06（去 dev-start）、FR-SUP-07（诊断与失败关闭口径）同步；评审独立性不变 |

同步完成的判定：上述文件与 §3.3 的 Pipeline/门禁/状态机变更一致，且 FR-04 要求的「按 CR-ID/cycle 写死的临时例外」已关闭。

## 9. 批准范围

### scope_in

- **FR-01～FR-14 的生产实现**（工作包 W1～W4）：绑定、Git 身份、评审落盘原子闭环、普通 BLOCK 复评、本地信任减负、默认 coding 去 dev-start、人类继续一次一 cycle、G05/G06 tree 比较与最小重验、发布意图固定、CI 数量告警与红例收敛、Windows 文档链、实际生效核对。
- **FR-SUP-01～FR-SUP-05、FR-SUP-08、FR-SUP-09（本 CR 部分）**：owner `user_id` 校验与契约同步、source 自动绑定与双防线校验、注册阶段根交接、PRD 交接完整性、一次性只读历史扫描。
- **FR-SUP-06 的错误根防线部分**与 **FR-SUP-07 的写入边界安全校验与诊断口径部分**（§1.2 表已逐行标注）。
- **AC-01～AC-24、AC-SUP-01～AC-SUP-05、AC-SUP-06（本 CR 侧）、AC-SUP-07、AC-SUP-08、AC-SUP-09、AC-SUP-10（交接检查部分）**，映射见 §6.2。
- 三仓变更面见 §1.5；`knowledge-base` 仓只承载 CR 产物（本 SDD、plan、tasks、评审证据），无代码变更。

### scope_out

- `specs/`、`delivery/` 回写与归档（回写期由 writeback 系列完成，本 CR 设计期不触）。
- 平台 CR 投影 reconcile 权威源根治（在途 CR 读自身 worktree 分支 + 活跃运行守卫收口）——独立 CR。
- AIFI-60 承接项：单层独立 reviewer 的平台派发与启动预检、评审 Task 完成判定与受控恢复、日志与正式产物交接收口、逐节点手抄根/重复调度说明裁剪。
- PRD §7 已排除项：新数据库/影子账本/权限框架/票据服务/通用恢复器、完整 coding Runner、常驻调度器、多文档聚合或 OCR、成员缓存、定时巡检、全量历史迁移、`codeRoot`、扩展名白名单、语义哈希、智能测试影响分析、额外预评审、运行中旧图热换、提交消息语义分析。
- reviewer/Agent/Git 审计身份模型统一、`origin` 字段语义扩展。

### zero_diff

以下对象**明确不得改动**（与 `scope_in` 无重叠：`scope_in` 改的是这些对象的**调用侧/消费者**，不是上述判定本体）：

- `verifyGrantSignature`／`grantCanonicalString` 的签名算法与错误码，以及 `approval.yml#<server-approve 段>` 的六字段集合；
- 状态集合（15 具名状态 + `(new)`）与 `crctl advance` 的 CAS/审计/事务语义；
- `rules.json#protectedPaths.deny` 的受控路径集合、`rules.json#git` 白名单 shape 与 `forbiddenFlags`；
- crctl 子命令集合与 `case '<cmd>'` 分支名（只扩展既有子命令，不新增/不改名/不删除）；
- `specs/`、`delivery/` 的权威路径推导、writeback/archive 合同与迁移登记；
- 用户全局 Git 配置本体（任何写入）；
- 生产任务已注入的可信绑定变量（任何清除/覆盖）。

### follow_up

- 修复 AIFI-62 正文所指的平台投影 reconcile 权威源闭环：需让在途 CR 的 reconcile 读该 CR 自己的 worktree 分支（daemon 采集器 + GitHub 模式两处同改），并与活跃运行守卫在同一变更内收口——另立 CR。
- 校验发现的历史 `source` 异常与 owner 异常：本 CR 只提供只读扫描；批量修复留待人工裁决后的后续动作，不入本 CR 范围。
- `origin` 字段（与 `source` 同为空串）的语义与校验：本 CR 不展开。
- reviewer/Agent/评论 mention 的身份模型统一：PRD 明确留待后续。

## 10. 既有实现依赖与事实

> 本节是本 SDD 唯一的既有实现事实清单。正文只写「设计依赖 `dep-N`」，不在正文重述实现行为。所有 `commit SHA` 取被引用仓（`tools`、`multica`）当前 `requirement/CR-2026-076` worktree 的 HEAD（只读取证）。编号为稳定标识，只增不改。

dep-1
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: bindTaskWorkspace（任务绑定三元组归一点）
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 绑定三元组缺失或不完整、两路径非目录或异安装根、显式 --workspace 与绑定异根，均以 WORKSPACE_CONTEXT_MISMATCH 失败关闭且零业务写入；`\\?\` 命名前缀与尾分隔符按同一真实目录的合法别名处理。

dep-3
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdWorkspace（workspace inspect 输出）
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 可只读取得 operationalWorkspace、operationalWorkspaceError、resources[].{repo,branch,worktreePath,classification,dirty}，作为启动预检、路径 authority 与路由的输入。

dep-27
  repo: tools
  relative path: skills/shared/controlled-shell/rules.json
  stable symbol/对象: git 白名单、forbiddenFlags、protectedPaths.deny
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: git 子命令与参数形状受白名单限制（含 -c/--exec 等 forbiddenFlags），change-requests 下的账本路径为 crctl 独占写入；命令面扩展必须落在既有白名单内。

dep-19
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdStatus 的 warnings 数组（{code,message}）、cmdValidateDimensions/cmdValidate 的只读维度结果
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: warning 已是可扩展数组形态且不参与通过判定，可直接承载减负信号；validate 已有可扩展的只读维度面（errors/warnings/checked/notChecked）。

dep-20
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdApprove、approveAndAdvance、approveWithGrant、classifyGrantState、assertAdjacentApprove、verifyGrantSignature、grantCanonicalString
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 审批入口已分本地与 server-approve 两路；签名路径有 canonical 串与 Ed25519 验签、并在重放时做六字段精确比较；本地路径无签名事实可作区分依据。

dep-14
  repo: tools
  relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
  stable symbol/对象: resolveRepositories、deriveInstallRoot、buildReleaseSubjects、renderReleaseSubjects、verifyReleaseSubjects、classifyRemoteCommit、classifyCheckpointRemote
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 参与仓解析、release-subjects 构造与重核、远端提交分类已集中在该模块，可作为 tree 等价比较与发布意图固定的单一落点。

dep-21
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdCheckpoint
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 远端发布事实由 checkpoint 收口，本地提交与远端发布已分层。

dep-15
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdMerge
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 合入入口存在且含远端源/受控只读查询与失败回流，可挂载 G05 等价推进判定。

dep-13
  repo: tools
  relative path: skills/shared/crctl/scripts/lib/durable-tx.mjs
  stable symbol/对象: beginLedgerTransaction、finishLedgerTransaction、abortLedgerTransaction、recoverLedgerTransaction、applyWriteSet、ledgerTxKey
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 账本写入已具备事务键、输入意图摘要、CAS、写集回滚与恢复能力，可直接承载 review-record 的原子闭环与幂等，无需第二幂等账本。

dep-2
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: requireExplicitWorkspace
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 非 help 子命令在无绑定且无显式 --workspace 时以 WORKSPACE_REQUIRED 失败关闭，是绑定归一之后的第二道门。

dep-28
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: fail、ok（唯一回执出口）
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 全部子命令经同一出口返回 JSON 与非零码，新增判定必须沿用该出口与既有 code，不新增同义错误码。

dep-25
  repo: tools
  relative path: pipeline-templates/code-implementation.pipeline.json
  stable symbol/对象: human_approval 节点（确认进入代码开发）与 approve-dev-start 节点
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 默认 coding 路径当前包含 dev-start 人工确认与收尾节点，需按 FR-06 从必经路径移除并保留旧调用兼容。

dep-24
  repo: tools
  relative path: skills/shared/crctl/gates.json
  stable symbol/对象: statusGates.developing、approvalStages.dev-start
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: developing 门禁当前要求 dev-start 阶段的 passCondition 与 development-start 审批段，需按 FR-06 调整判定组合。

dep-26
  repo: tools
  relative path: dir-graph.yaml
  stable symbol/对象: change-request-track.state_machine.transitions
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 状态与合法转换的单一事实源；当前为 15 个具名状态 + 注册前 (new)，转移 28 条声明、wildcard 展开 50 条，含 task-breakdown→developing(approve-dev-start) 与 task-breakdown→tech-design-reviewed 的回退转换。

dep-29
  repo: tools
  relative path: pipeline-templates/requirement-authoring.pipeline.json
  stable symbol/对象: inputs（source、requirement_owner、dev_owner、test_owner）
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: source 当前声明为必填，owner 输入仍为角色名口径示例，需按 FR-SUP-02/FR-SUP-03 同步为空值语义与 user_id 口径。

dep-4
  repo: multica
  relative path: server/internal/daemon/pipeline_task.go
  stable symbol/对象: parseExecutionContext、executionContextNode、fencedYamlBlocks
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: 触发评论中的 execution_context fenced 块解析已存在，多块、重复键、非法 cr_id 或空 operational_workspace 一律以 CR_WORKSPACE_BINDING_UNAVAILABLE 失败。

dep-5
  repo: multica
  relative path: server/internal/daemon/pipeline_task.go
  stable symbol/对象: resolveTaskWorkspaceBinding
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: 声明块存在时已走 local_directory→findPipelineCRRoot→inspect 三段预检并比对操作根同根；无声明时只回落到 task 关联根，尚无「来源 Issue 唯一正式 CR 关联」解析段。

dep-6
  repo: multica
  relative path: server/internal/daemon/pipeline_task.go
  stable symbol/对象: configureTaskGitEnvironment
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: 当前生成仅含 [safe] directory 两行的配置并注入 GIT_CONFIG_GLOBAL，等效于替换用户全局配置，身份事实随之丢失；需按 FR-02 改为 Git 原生 include 叠加。

dep-7
  repo: multica
  relative path: server/internal/daemon/pipeline_task.go
  stable symbol/对象: findPipelineCRRoot、inspectPipelineWorkspace、pipelineWorkspaceInspect
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: CR 根唯一性（0/多命中拒绝）与 workspace 健康预检已实现，可直接作为错误根防线（错误项目根/阶段根、失效 worktree 写前拒绝）的基础。

dep-30
  repo: multica
  relative path: server/cmd/multica/cmd_gitguard.go
  stable symbol/对象: taskAuditRootEnv（CRCTL_TASK_AUDIT_ROOT 消费）
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: 审计根与操作根分离是既有事实（审计根为安装根），诊断与校验不得把二者不同判为绑定冲突。

dep-31
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdRegister、buildRegisterResult、cmdOwnerSet、editCrOwnerProjection、editBacklogOwnerProjection、rollbackOwnerWrite
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 注册与 owner 变更已有受控事务入口、投影一致性与回滚能力，可在其持久化前挂 owner/source 校验而不新增写入通道。

dep-12
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdReviewRecord、renderReviewsStage、upsertReviewsStage、queryTrackedChanges
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 评审证据写入、traceability 段落渲染与 index 受控只读查询已存在，可在此基础上补齐整索引隔离断言与恢复语义。

dep-22
  repo: tools
  relative path: skills/shared/crctl/scripts/test/suite-gate.mjs（登记表：skills/shared/crctl/scripts/test/gate-registry.json）
  stable symbol/对象: parseFileTap、validateExceptions、EXCEPTION_KINDS、CODES、registry.manifest、registry.exceptions
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 逐文件 TAP 解析、例外 schema/期限校验与显式登记表已存在；登记表当前含 4 个 summary 宿主环境例外（kind=suite-failure，根因：夹具用系统临时目录 + 显式异根 --workspace）。

dep-23
  repo: tools
  relative path: skills/shared/engineering-docs/scripts/src/validators/chain.ts
  stable symbol/对象: collectDocs、chainCheck、ChainResult.docCount
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 文档链扫描以 split("/").pop() 取文件名，在 Windows 反斜杠路径下类型判不出而被 continue 跳过，可造成空扫描假通过；需按 FR-13 改为 node:path.basename 并强化 docCount 断言。

dep-8
  repo: multica
  relative path: server/internal/governance/runner.go
  stable symbol/对象: Runner.StartArchitecture、RunnerErrCRNotReady（RUNNER_CR_NOT_READY）
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: 架构期启动受平台投影门禁约束（放行条件为投影 status 与 needsReconcile）；本 CR 不修改该门禁，也不把投影事实当作本节点成败依据。

dep-32
  repo: multica
  relative path: server/cmd/multica/cmd_workspace.go
  stable symbol/对象: workspace member list 子命令（返回成员 user_id）
  commit SHA: a2046ce34449aaed67df000a1320d73d9976e987
  依赖结论: 成员 user_id 查询入口已存在，可作为 owner 值域的唯一来源（一次查询复用三角色）。

dep-16
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: cmdNext
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: next 已按状态路由并输出 next/humanApproval/why，是 FR-04 判定优先级与 AC-09 的落点。

dep-17
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: devPlanFreshness、devPlanCompositeDigest、detectNewTechDesignCycle
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: plan/TASK 的对象变化与摘要比较已存在，可直接复用于普通 BLOCK 的「对象已变/未变」分支，无需新增摘要体系。

dep-18
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: runGateChecks、evaluatePassCondition、cmdGate
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: 通过条件只依赖 verdict 与 blockers，warning 天然不影响通过判定；这是 FR-05 减负与 AC-10 的关键性质。

dep-33
  repo: tools
  relative path: skills/requirement/requirement-register/SKILL.md、skills/develop/approve-dev-start/SKILL.md、agent-skill-matrix.yml
  stable symbol/对象: Skill 参数说明、节点必经性与 Agent/Skill 权限矩阵（生效合同）
  commit SHA: 0f5690f845dcf1e0dd9fdc37797b7e4294335266
  依赖结论: Skill 文档与权限矩阵是生效合同的事实源；FR-04/FR-06/FR-SUP-02/FR-SUP-07 的合同同步必须落在这些文件上，否则会出现「crctl 已改、合同未改」漂移。

### 待核实依赖

无法在本轮绑定五要素（repo/path/symbol/SHA/结论）的引用，列为此类，不得当作既有能力断言：

- **上传附件 → 知识库 source 桥接（平台侧）**：FR-SUP-03/AC-SUP-03 要求「复用现有附件上传/读取能力」。本轮只在 multica 仓定位到候选承载文件（`server/internal/governance/runner_requirement.go`、`runner_requirement_entry.go`、`runner_requirement_registry.go`），未取到稳定符号与行为结论。实施期须先定点核实该桥接的实际入口与可读性保证，再决定是复用还是新增最小接线；核实前不得在 plan/TASK 中按既有能力排期。
- **repocache 身份加载与 GIT_CONFIG_GLOBAL 的交互（平台侧）**：FR-02/AC-04 要求任务内提交身份来自原全局配置。本轮未确认 `server/internal/daemon/repocache/cache.go` / `identity_test.go` 是否也写入或覆盖 Git 配置环境。实施期须先核实，若存在第二处写入点，需与 `dep-6` 的叠加式配置在同一变更内收口。

---

