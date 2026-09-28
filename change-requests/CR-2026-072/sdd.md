---
id: CR-2026-072-sdd
type: SDD
cr-ref: CR-2026-072
title: CRCTL_WORKSPACE 跨项目错根防护：显式 workspace 与任务级绑定 技术设计
target-version: 0.45
status: draft
created: 2026-09-28T23:07:56+08:00
updated: 2026-09-28T23:07:56+08:00
---

# 1. 架构概览

本 CR 同时修改 tools（调用方合约与 crctl 入口）和 multica（daemon 注入与 gitguard 拒绝审计），knowledge-base 仅承载本 SDD。遵守 tools 的 crctl 唯一状态写者约束和 multica 的任务单路径、CR Git 权威/平台投影分离约束；不新增状态、数据库表、服务或审批途径。

```text
任务可信绑定（Pipeline 预检 / 普通任务项目 local_directory）
  → Agent/Pipeline 传路径 → Skill 确认路径与当前 CR 的 operational authority
  → crctl 显式 --workspace 校验 → 既有状态机、gate、CAS、事务

普通任务无可信绑定 → 不注入 CRCTL_WORKSPACE → 调用方无法确认则不调用
gitguard 拒绝 → 无条件拒绝；有可信绑定才写对应项目 outbox 审计
```

**两个路径不混用。** `installation root` 是项目的 knowledge-base 根，供 `register`、`workspace inspect` 及需要派生多仓 worktree 的操作定位仓集合；`operational workspace` 是 inspect 对本 CR 返回的唯一当前事实源（merge 前 CR worktree，merge finalize 后 transaction workspace）。对 `status/next/gate/advance` 等单 CR 命令，调用方核对 inspect 输出与当前任务绑定，传该阶段的 operational workspace；对跨仓深命令保留既有安装根/authority 参数组合及门禁，明确核对其最终写目标。`--workspace` 是必填路径，不是项目身份凭证；CLI 不通过 CR-ID 推断项目。路径规范化后的等价性比较使用 realpath（Windows 大小写规范化），并同时比较 inspect 所示的 CR/仓/分支；校验不通过中止，不退回环境变量或第一个候选根。对 merge 后 transaction workspace，无可证明的 authority 则中止而不是复用已过期 worktree。

**术语边界校验。** PRD 所称“workspace”指命令已确认的安装根或 operational workspace，不能把任意可含同名 `cr.md` 的目录当成可信项目绑定。代表场景：项目 A 已 archived、B developing，同名 `CR-2026-001`；B 任务的显式 B authority 返回 developing，空 flag 即使 cwd=B/env=A 也拒绝。此区分不变更已有阶段/status 的业务含义。

# 2. 数据模型

不新增持久 schema。仅重用以下进程内/命令行数据：

| 对象 | 字段 / 生产者 | 消费 / 失败语义 |
|---|---|---|
| `PipelineWorkspace`、`PipelineLocalWorkDir` | Pipeline CR 根预检和 inspect 得出的 operational path，设计依赖 dep-5 | Pipeline 环境注入及调用方命令；0/多根或任一资源不健康时中止 |
| `ProjectResources` 的 `local_directory` | 当前任务项目资源及 daemon_id，设计依赖 dep-7 | 非 Pipeline 任务仅一条匹配且验证通过时绑定；0 条不注入，>1 条拒绝 |
| `resources[].worktreePath`、`operationalWorkspace` | crctl `workspace inspect`，设计依赖 dep-4 | 原样传节点；变更阶段时重新 inspect，不持久化第二套状态 |
| `--workspace <path>` | 调用方对本次命令明确提供 | 非 help 的 CR 数据命令强制非空且有效；缺失/空值 `WORKSPACE_REQUIRED`，无效路径 `WORKSPACE_NOT_FOUND`（不回退） |
| `CRCTL_WORKSPACE` | daemon 可提供的提示/受控 gitguard 审计绑定 | 绝不作为 crctl 命令默认 root；无可信任务绑定时从 agentEnv 移除，防止继承宿主陈旧变量 |
| `CRCTL_OPERATIONAL_WORKSPACE` | Pipeline 预检绑定，设计依赖 dep-6 | 写路径若还接受此环境输入，则与当前任务已确认 operational path 比对；不一致于首次读取 CR 数据/写入前拒绝，不以它覆盖显式旗标 |
| `.crctl/outbox` audit | gitguard 仅有由 daemon 本任务项目资源/Pipeline 预检得到的独立审计根时写入，设计依赖 dep-8 | 不再用 `CRCTL_WORKSPACE` 决定审计归属；无绑定时拒绝动作仍返回原 FORBIDDEN_*，仅跳过错误归属的审计 |

旗标解析应拒绝 `--workspace` 无值、全空白、重复而不一致的值以及紧邻其他 flag 的布尔值；`help` 保留无旗标。`git` 白名单命令、纯静态 `validate` 等非 CR 数据入口须逐项辨明，不粗暴把 Git 通道/文档校验变成假 CR 数据操作；一旦其执行涉及 CR 事实源/审计同样必须具备显式合法 root。错误 JSON 仍沿用 `{error:{code,message}}` 与非零退出，避免破坏已有 CLI 结果格式。

# 3. 接口契约

不新增 HTTP API、IPC 或事件 schema；变更 CLI 参数、任务环境、审计归属。接口概要：

```text
crctl status|next|gate|advance|... CR-ID --workspace <verified-authority>
crctl workspace inspect CR-ID --workspace <verified-installation-root>
crctl register ... --workspace <verified-installation-root>
crctl checkpoint|merge|writeback-apply|archive ... --workspace <verified-root>
```

`...` 表示所有读写 CR 数据的既有子命令，不放宽审批、CAS、gate。安装根和 operational path 的选择按命令原有 authority 解析执行；需要两个路径的命令继续传现有参数（如 `--operational-workspace`），写前核对解析后的目标属于本任务 operational workspace。**显式 `--workspace` 不等于允许将 A 的 CR 操作重定向到 B**；身份边界由任务已有绑定 + inspect 负责，不引入仅凭同名 CR-ID 的 CLI 全局查找。

CLI 前置校验发生于 `loadGates`、状态查询和 CR 数据路径读取之前；未提供路径输出 `WORKSPACE_REQUIRED`，有路径但无目录/不是该命令可用的 workspace 时输出 `WORKSPACE_NOT_FOUND`（或现有更具体的有效性错误）。`--workspace` 的值只是参数，不在错误信息中泄露其他项目账本。`status/next` 对显式 B 查询始终只观察 B，终态也不依赖 `STATUS_DIVERGED` 弥补路由错误。

普通任务环境合约：Pipeline 注入预检 root 和 operational path；普通任务只有在项目 `local_directory` 与本 daemon 匹配、路径已验证且唯一时可注入对应 root，缺失则环境中无 `CRCTL_WORKSPACE`/`CRCTL_OPERATIONAL_WORKSPACE`。本注入是路径提示而非自动运行 crctl 的授权，Agent 必须自行验证后传旗标。`CRWorkspaceRoots` 继续供 collector 和 Pipeline 根候选集合使用，不是普通任务选择第一项的理由。

# 4. 关键算法与流程

1. **调用方迁移先于强校验发布。** 逐项清点 `agents/{requirement-writer,dev-agent,quality-reviewer-agent,delivery-agent}.md`、`pipeline-templates/*.pipeline.json`、`skills/**/SKILL.md` 中真实 crctl 调用、`skills/shared/crctl/SKILL.md`、`skills/sync/push-progress/SKILL.md`、CLI HELP、README 示例、自动注入 hook、以及扫描面外 CI/workflow/脚本。沿用既有 `caller-contract.test.mjs` 清单追加调用形态检查；历史叙述、夹具/生成转换脚本无需机械改写。注入 hook 在无可信路径时不得建议无旗标的状态调用，也不得把 cwd 枚举出的同名 CR 标记为本任务权威；可停止注入或仅给出带可信路径的可执行建议。设计依赖 dep-9、dep-10、dep-11、dep-12。
2. **统一 CLI 入口。** `parseArgs`/`parseGitArgs` 得出 flag，非 help 且需要 CR 数据访问的子命令先校验 `typeof workspace === 'string' && trim()`，否则 `fail('WORKSPACE_REQUIRED',...)`；合法值仅从该 flag 进入 `detectWorkspace`，删除 env/cwd 回退。显式路径绝对化后验证目标工作区，再 `loadGates` 和分发；可采用少量命令分类但不重写深原语。设计依赖 dep-1、dep-2。`status` 终态分支同样经过入口校验，设计依赖 dep-3。
3. **daemon 绑定。** Pipeline 保留已预检的 root/operational，CR-ID 多匹配维持硬失败；非 Pipeline 通过现有项目 local_directory 解析结果注入，未匹配不写 env 键且清除继承的旧 CR 环境键。不能从 `CRWorkspaceRoots[0]` 或 workspace 当前 cwd 猜项目。工作目录为 disposable worktree 时，不将其等同 CR authority；使用资源对应的项目根，若不能确认该项目是 CR 根则不注入。设计依赖 dep-5、dep-6、dep-7。
4. **写路径及审计。** 单 CR 写命令保留原 gate/CAS/事务，以显式路径与验证后的 operational path 一致为前置（含 symlink 和 Windows 路径）；旧 `CRCTL_OPERATIONAL_WORKSPACE` 若与其冲突则失败关闭，不能跳转到别的项目。daemon 将本任务预检 root 独立传给 gitguard 的审计参数/专用内部环境键，并在最终环境叠加后保证该值与任务绑定一致；gitguard 不再从 `CRCTL_WORKSPACE` 获取审计根。gitguard 先拒绝违规 git；只有可信任务 root 时才写其拒绝审计，未绑定时不写其他项目 outbox，拒绝错误码不变。设计依赖 dep-2、dep-8。
5. **回归。** 两个临时根同名 CR，一端 archived、另一端 developing：验证显式 B 对 status/next/gate/advance 的路由、A/B 数据哈希，环境 A + cwd B 的无旗标、空旗标、无效旗标均失败且零数据副作用；另测多根歧义、Pipeline/普通任务带/不带项目绑定、operational env 错配、gitguard 拒绝及正确/无归属审计。运行 `crctl.test.mjs`、`caller-contract.test.mjs`、`lint-prompts.mjs`、daemon 相关测试，保存真实结果和受影响调用点清单；单独发布 CLI 拒绝上线。

# 5. 技术选型与替代方案

| 决策 | 理由 / 替代 |
|---|---|
| 命令行显式 flag + 既有 inspect | 不从进程 env/cwd 推断跨项目身份；全局 CR 根注册器不解决任务归属且引入第二个权威 |
| 复用项目 local_directory 与 Pipeline 预检 | 已有任务边界；不添加按 CR-ID 枚举选择第一个根 |
| 沿用既有测试框架和状态机 | 同批迁移可回归且不创建平行事务、审批或 gate |

# 6. FR 与 AC 逐项映射

| 需求 | 设计落点 | 可观测结果 / 可达性说明 |
|---|---|---|
| FR-1 | §1、§3、§4.1 的各类调用方；inspect 后传递 | 不依赖隐式根；包括 README、push-progress 和 hook 的扫描面外调用 |
| FR-2 | §2、§4.2 入口统一前置校验 | `WORKSPACE_REQUIRED` 在任何 CR 数据读取之前，合法显式路径保持原行为 |
| FR-3 | §2、§4.3 daemon 项目绑定 | 无可信绑定无 env；Pipeline 仍预检，歧义中止 |
| FR-4 | §2、§4.4 gitguard | 拒绝仍生效，有根归本项目，无根不误写他项目 |
| FR-5 | §4.1、§4.5 同批交付/回归 | 清单及四类测试记录，审批继续由人类 |
| AC-1 | §1 路由、§4.2 测试 | A archived/B developing 时显式 B 的 status/next 只能见 B；入口先于终态返回，因此可达 |
| AC-2 | §2 参数与 §4.2 测试 | cwd=B/env=A 而缺/空 flag 一律 `WORKSPACE_REQUIRED` 且非零；入口早于读取保证 A/B 哈希不变 |
| AC-3 | §1、§3 authority 比对、§4.4 | 显式 B/env=A 的 read/gate/advance 均以 B 为准；无效 flag 不回退，写前校验目标与 B 一致 |
| AC-4 | §2、§4.3/4.4 | Pipeline 预检路径；普通任务无根不注入、有根只注入该项目；歧义与审计均失败关闭 |
| AC-5 | §4.1/4.5 | 提交准确清单、crctl/caller-contract/lint/daemon 实际测试结果；调用方先迁移且与 CLI 同批发布 |

以上每项的生产者分别是 CLI 分发、daemon 环境构建及 gitguard；存储仅沿用 Git CR 文件与现有审计 outbox。无新消费者迁移或响应 schema 变更，现有数据不做回填；没有可信路径时不提供兼容性 env 回退。

# 7. 安全与性能考量

- workspace flag 校验必须先于 `loadGates`/终态查询，避免貌似可信的跨项目读取；只有校验存在性并不能证明项目身份，故调用方核实任务绑定和 inspect，不能将 CLI 强校验误当身份校验。
- 双路径写命令不得允许环境变量覆盖已确认 operational workspace；校验路径 realpath 防止相对路径、symlink 与 Windows 别名逃逸。不干预现有审批、签名、事务和审计权限。
- 普通任务无匹配资源时不注入比猜错更安全；gitguard 仍拒绝被禁 git，审计未写入要可由当前拒绝错误及 daemon 日志观察，不因审计失败放行。
- 每次调用只多做一次 flag/路径校验，复用现有 inspect，不扫描全盘 CR 根；已有 Pipeline inspect 不重复添加全局枚举。

# 8. Prompt 采纳影响

本 CR 修改 `skills/shared/crctl/scripts/crctl.mjs` 的统一 dispatch/入口，故必须核对以下调用方采纳显式 `--workspace`：

| Skill / 调用面 | 现状 | 应改为 |
|---|---|---|
| `skills/develop/write-tech-design/SKILL.md`、`skills/develop/review-tech-design/SKILL.md` 及其余 develop review/approve Skill | 节点写 `crctl ...` 可依赖 env | 从 Pipeline inspect 获取当前 CR 权威路径，所有执行命令带 `--workspace` |
| `skills/requirement/**/SKILL.md`、`skills/writeback/**/SKILL.md` | 注册、评审及合并/回写命令存在隐式根示例 | 注册/inspect 显式安装根，其余按阶段权威路径/深原语原有双路径语义传参 |
| `skills/sync/push-progress/SKILL.md`、`skills/shared/crctl/SKILL.md` | checkpoint 默认借助 `CRCTL_WORKSPACE`，共有 CLI 示例未强制 flag | checkpoint 传已核对 root；共享合同显式前置校验和正确示例 |
| `skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs` | 指针建议的状态命令缺 flag | 有可信项目路径才提示显式命令；无路径不注入貌似权威的命令 |

其他 Skill/Agent/Pipeline/实际脚本在 §4.1 清单中逐项核对，不以本表代替最终调用点清单。未修改 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`。

# 9. 批准范围

- **scope_in**：FR-1～FR-5 / AC-1～AC-5 必须交付的 tools Agent/Skill/Pipeline/README/CLI/回归测试与 multica daemon/gitguard/测试；必要时仅调整 knowledge-base 已识别的真实调用点（如 `.github/workflows/cr-guard.yml`）并在清单注明；multica 的实际定制改动同步登记 `CUSTOM.md`。
- **scope_out**：AIFI-35 的业务测试和 blocked 门禁；新 CR 根注册服务、状态机/账本事务重写、数据库迁移、新审批通道、无关前端/共享服务配置；确定性 PRD/SDD/TASK/traceability 转换脚本。
- **zero_diff**：`dir-graph.yaml#change-request-track.state_machine` 与 `gates.json` 的状态/门禁定义、crctl 既有深原语的 CAS/commit/push 算法、multica 对外 HTTP 契约、`skills/shared/controlled-shell/rules.json#protectedPaths.deny`；CLI dispatch 的入口校验属于 scope_in，不在 zero_diff。
- **follow_up**：普通任务若未来确有项目资源以外的自动 CR 根路由需求，另立窄任务定义可信绑定来源，不为当前 AC 添加猜根服务；当前 AC 的无根失败关闭不依赖此项。

# 既有实现依赖与事实

下列事实均在本 CR 的三个 `resources[].worktreePath` 所示 HEAD 核对，正文以 dep-N 引用，不以安装根或其他工作树冒充版本依据。SHA 为各仓当前完整 HEAD。

| ID | repo | commit SHA | relative path | stable symbol/对象 | 依赖结论 |
|---|---|---|---|---|---|
| dep-1 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/shared/crctl/scripts/crctl.mjs` | `detectWorkspace` | 显式 flag 优先，否则读取 `CRCTL_WORKSPACE`，再由 cwd 向上寻找 backlog；仅目录存在性检查 |
| dep-2 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/shared/crctl/scripts/crctl.mjs` | `main` / `parseArgs` / `authorityWorkspace` | CLI 在解析 flag 后先 detectWorkspace 再 loadGates/dispatch；写路径辅助解析可读取 `CRCTL_OPERATIONAL_WORKSPACE` |
| dep-3 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/shared/crctl/scripts/crctl.mjs` | `cmdStatus` | 终态 `resolveTerminalForQuery` 分支先于非终态状态解析及漂移检测 |
| dep-4 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `resolveOperationalWorkspace` | merge 前返回 CR worktree；merge finalized 后按 journal/txws 判定，事实不一致抛错 |
| dep-5 | multica | `1c24d353cc8fda9024623f8bdc85f312e0364672` | `server/internal/daemon/pipeline_task.go` | `preparePipelineTask` / `findPipelineCRRoot` | Pipeline 在配置根中要求恰一命中，inspect 后填 `PipelineWorkspace`/`PipelineLocalWorkDir` |
| dep-6 | multica | `1c24d353cc8fda9024623f8bdc85f312e0364672` | `server/internal/daemon/daemon.go` | agentEnv `CRCTL_WORKSPACE` 赋值分支 | Pipeline 注入对应 root；普通任务回退至 `CRWorkspaceRoots[0]` |
| dep-7 | multica | `1c24d353cc8fda9024623f8bdc85f312e0364672` | `server/internal/daemon/local_directory.go` | `localDirectoryAssignmentForTask` / `findLocalDirectoryAssignment` | 普通任务按项目资源和 daemon_id 找 local_directory；无匹配返回 nil，重复匹配返回错误 |
| dep-8 | multica | `1c24d353cc8fda9024623f8bdc85f312e0364672` | `server/cmd/multica/cmd_gitguard.go` | `gitguardExecCmd` deny 分支 | 被禁 Git 操作拒绝后以 `os.Getenv("CRCTL_WORKSPACE")` 为根调用 `SpoolDenial`；审计失败不解除拒绝 |
| dep-9 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/sync/push-progress/SKILL.md` | Step 1 checkpoint 命令 | Pipeline 示例依赖运行时注入 `CRCTL_WORKSPACE`，不显式传旗标 |
| dep-10 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs` | `findBacklog` / `ctx` | hook 从 cwd 找 backlog、逐 CR 读状态，末尾建议无 flag 的 `crctl status <CR-ID>` |
| dep-11 | tools | `b2e935684d3bbfb4727ae3f0ec1f7e4026b5c293` | `skills/shared/crctl/scripts/test/caller-contract.test.mjs` | `REVIEWED_CALLS` / `OUT_OF_SURFACE_CALLERS` | 已列投影命令的扫描面和 CI 面外调用；现有断言针对 detail/summary 消费，不等于全命令显式旗标检查 |
| dep-12 | ai-first-platform-docs | `1602ef02ec2a968f15f50c5770de1d74631298f8` | `.github/workflows/cr-guard.yml` | Validate backlog / changed artifacts | 实际 CI 的 `crctl validate` 命令已带 `--workspace .`；须逐项核对 gate 等其他命令 |

# SDD-CLOSE：需求延后到设计的事项

- **SDD-CLOSE-01（路径 authority）**：生产者 Pipeline 预检/项目 local_directory，传递 inspect 的 operational path，消费者 Agent/Skill 在每次 CR 命令前比对；merge 后 txws 由既有 resolver 确认。不能凭 env 或同名 ID 降级。§1～§4 已关闭。
- **SDD-CLOSE-02（CLI 缺参、空参和错误）**：入口读取任何 CR 数据之前判旗标；缺/空统一 `WORKSPACE_REQUIRED`，无效路径无回退；现有 JSON 错误形状保持。§2～§4 已关闭。
- **SDD-CLOSE-03（拒绝审计）**：gitguard 始终拒绝；独立的任务预检根而非 `CRCTL_WORKSPACE` 决定既有 outbox 归属，缺归属不产出归错项目的事件；消费者仍为现有 collector，不新增 event schema。§2～§4 已关闭。
