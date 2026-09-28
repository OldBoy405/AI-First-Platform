---
id: CR-2026-072-prd
type: PRD
cr-ref: CR-2026-072
title: CRCTL_WORKSPACE 跨项目错根防护：显式 workspace 与任务级绑定
target-version: 0.45
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owner-role: requirement
status: draft
created: 2026-09-28T22:44:42+08:00
updated: 2026-09-28T22:44:42+08:00
---

# 概述

AIFI-35 暴露了跨项目同名 CR 的错根风险：`crctl` 目前可从 `--workspace`、`CRCTL_WORKSPACE`、cwd 选择根；环境注入若指向另一项目，即使 CR-ID 相同，终态查询也可能给出看似可信的错误结果。`STATUS_DIVERGED` 不足以作为路由正确性的保障。本 CR 是 Dayan 项目独立的 CR 路由治理，不解除 AIFI-35 的业务测试门禁。

目标是让每次 CR 读写都携带经本任务确认的项目 workspace；缺少可信绑定时失败关闭。调用方先迁移，再与 crctl 入口强制校验、daemon 回退删除同批交付。复用现有 crctl 状态机、gate、CAS、审计和事务，不建立第二套项目根注册器或状态副本。登记的目标版本为 0.45，目标 spec 为 `ai-first-platform`。

# 用户故事

- **US-1** 作为 Dayan 的 CR 作者，我希望查询同名 CR 时只读到本任务绑定的 worktree 状态，以免因另一个项目已归档而停止推进。
- **US-2** 作为 Pipeline/Skill 调用者，我希望显式传递已校验的安装根与 operational workspace，并在不确定时中止，而非让环境变量隐式选择。
- **US-3** 作为普通任务执行 Agent，我希望无可信项目根时不收到假定的根，避免将门禁、推进或拒绝审计落在错误项目。

# 功能需求

- **FR-1｜调用点迁移。** 清点四个 CR Agent Prompt、共享 crctl 合同、Pipeline 模板、实际调用 crctl 的 Skill/脚本，以及 `push-progress` 和自动状态注入 hook 等扫描面外调用点。所有执行 CR 数据读写的调用显式提供 `--workspace`，来源须是本命令已验证的权威路径；无法确认时不调用。安装/项目根用于 `workspace inspect` 与注册；`status/next` 核对并使用返回的 operational worktree/transaction workspace；双路径写命令仍服从 crctl 现有解析与门禁，并校验实际写入目标与任务 operational workspace 一致。Agent 负责路由、Pipeline 负责上下文传递和节点编排、Skill 负责业务契约；不复制 crctl 算法。README 只保留人读流程与一个正确示例，确定性转换脚本无需仅为本次改写。
- **FR-2｜CLI 入口失败关闭。** 对非 `help` 的 CR 数据读写命令，缺少显式、非空的有效 `--workspace` 时，在读取 CR 状态、执行门禁或写文件前返回结构化 `WORKSPACE_REQUIRED`，退出非零且零 CR 数据副作用；不以 `CRCTL_WORKSPACE`、cwd 或同名 CR-ID 自动补足。显式路径无效时同样在访问 CR 数据前失败；现有合法显式路径的读写和门禁语义保持不变。CLI 本身不宣称显式路径必然属于当前项目，可信项目绑定由调用方保证。
- **FR-3｜daemon 任务绑定。** Pipeline 任务继续使用已预检的 task root 与 operational workspace；同名 CR 根歧义维持报错。普通任务只在已有可信项目本地目录/CR 根绑定时注入对应工作区；无绑定时不注入 `CRCTL_WORKSPACE`，不回退 `CRWorkspaceRoots[0]`，调用方必须显式提供可信路径。`CRWorkspaceRoots` 仍可供 CR event collector 使用，但不得作为当前任务根。若 `CRCTL_OPERATIONAL_WORKSPACE` 可能覆盖写目标，应保证与当前任务已确认的 operational workspace 一致，否则拒绝写入。
- **FR-4｜拒绝审计归属。** gitguard 继续拒绝被禁止的 Git 操作；拒绝审计不得仅凭错误项目的 `CRCTL_WORKSPACE` 归属。没有可信归属时失败关闭，不把拒绝动作或审计写到别的项目。
- **FR-5｜同批交付与回归。** 先使真实调用方显式携带路径，再启用 CLI 强校验并同步 daemon 行为；不得把破坏性 CLI 改动单独发布。复用现有 `crctl.test.mjs`、`caller-contract.test.mjs`、`lint-prompts.mjs` 与 daemon 相关测试；报告受影响调用点清单及每项结果。门禁失败即停止；需求、架构、开发启动、代码人工审批仍由对应人类负责人执行。

# 非功能需求

- **NFR-1 正确性/隔离：** 跨项目同名 CR 的读、gate、写和审计不得串项目；缺失可信路径不产生 CR 数据副作用，不靠终态漂移告警兜底。
- **NFR-2 兼容性：** 显式路径的现有状态机、CAS、深原语事务、reviewLoop 与 checkpoint 行为不变；调用方与 CLI 在同一交付批次兼容切换。
- **NFR-3 可追溯性：** 任务绑定、实际 operational workspace 和受影响调用点可由现有机器输出与测试证据核对，不另造全局根注册器。

# 验收标准

- **AC-1（FR-1/FR-2）：** 临时 workspace A、B 均有 `CR-2026-001`，A 为 `archived`、B 为 `developing`；B 任务传显式 B 路径时 `status/next` 只返回 B 事实，终态查询不能依赖 `STATUS_DIVERGED` 才纠错。
- **AC-2（FR-2）：** cwd 在 B、`CRCTL_WORKSPACE` 指向 A 时，不提供 `--workspace` 的 CR 数据读写返回 `WORKSPACE_REQUIRED`、非零退出，A/B 均无 CR 数据读写副作用；空旗标同样失败。
- **AC-3（FR-1/FR-2）：** 显式 B 路径且环境变量指向 A 时，读、gate、推进只采信 B；`status/next` 与写命令使用与任务匹配的 operational 路径；显式无效路径不回退 A 或 cwd。
- **AC-4（FR-3/FR-4）：** Pipeline 使用预检路径；普通任务无可信根时不出现 `CRCTL_WORKSPACE`，有可信根时仅注入该项目根；同名根歧义报错而非回退第一项；gitguard 拒绝依然生效且审计不误归属其他项目。
- **AC-5（FR-1/FR-5）：** 提交四类现有测试（crctl 单测、调用方合同测试、prompt lint、daemon 相关测试）的结果和确切受影响调用点清单；Agent、Pipeline、Skill 可执行命令与示例不再依赖隐式工作区；CLI 与真实调用方同批发布。

# 成功指标

- 跨项目同名 CR 隔离回归中的错误根读取、写入或审计为 0；缺旗标用例 100% 在 CR 数据访问前失败。
- 调用点清单覆盖的可执行 CR 数据命令显式 workspace 覆盖率 100%；上述四类测试均通过，失败项列出并阻止交付。

# 范围排除

- 不自动解除 AIFI-35 的 `blocked` 状态，不补做其业务测试；AIFI-35 仅为问题来源。
- 不重建状态机、gate、Git/账本事务；不在 Agent/README/Pipeline 管理 CR 状态或实现 crctl 内部算法。
- 不建立按 CR-ID 猜根服务、全局根注册器或新的合同扫描框架；普通任务缺可信绑定先失败关闭，确有真实自动路由需求时再讨论窄映射。
- 不为本次修改 PRD/SDD/TASK/traceability 等确定性转换脚本，也不代 Ray 完成人工审批。
