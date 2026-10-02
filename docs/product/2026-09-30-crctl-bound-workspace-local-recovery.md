# CR 执行入口与声明一致性修订方案

> **版本：v4，按已确认的复用与职责边界修订。状态：方案交付，尚未实施。**
> 本方案统一交付“入口绑定＋调用方本地纠正＋提示去重”、声明/调用合同修订，以及规划/竞品受控写入的最小接线；**一个 CR、两个内部任务 A/B**，不另拆 CR。执行沿用现有需求、开发、测试、独立评审和审批流程，不新增执行器或 Skill 种类；必要时补充已有能力的调用关系及权限登记。文档更新不等于代码发布，也不直接改变 CR-2026-074 的已审批范围。

**目标：** 将可确定的运行上下文交给现有入口处理，让 Agent 按真实能力和字段合同执行；消除错误委派、互斥校验及不可执行示例，而不是继续堆提示、重试或校验器。

**技术路径：** 复用 daemon 预检、task 环境、crctl 公共入口、既有事务原语和测试。Skill 做业务判断，版本化模块做确定性转换，crctl 执行受控写入；不把业务写入入口的缺口误写成事务基础设施的缺口。

**本轮交付边界：** 仅修订本方案文档，不修改 tools/multica 代码、账本、CR 状态或线上配置。以下 A/B 是后续 CR 的实施计划，不表示本轮已实施。

**事实依据：** AIFI-40 相关调用记录及 `docs/research/2026-09-30-tools-contract-claims-audit.md`。核对基线为 tools `41b112ed4d97baaaca3b82367a72f35520dc3d4b`、multica `78566fde28a1ea53527f2356249fb5df72bcb9cf`；实施前复核目标分支的实际接口。

## 1. 交付范围与边界

### 1.1 已有基础设施：直接复用，不重建

| 已有能力 | 核对位置 | 本次用法 |
|---|---|---|
| task 预检、launcher、Git 环境配置 | multica `server/internal/daemon/pipeline_task.go`：`preparePipelineTask`、`inspectPipelineWorkspace`、`installPipelineCrctlLauncher`、`configurePipelineGitEnvironment` | 接通普通 Issue 委派，复用 Pipeline 已有路径 |
| 显式根检查、operational authority 与真实路径比较 | tools `skills/shared/crctl/scripts/crctl.mjs`：`requireExplicitWorkspace`、`authorityWorkspace`、`realpathOrSelf`、`sameRealPath` | 在公共入口归一参数，保留原拒绝条件 |
| 锁、journal、CAS、write-set、事务恢复 | tools `skills/shared/crctl/scripts/lib/durable-tx.mjs`：`beginLedgerTransaction`、`applyWriteSet`、`recoverLedgerTransaction`、`abortLedgerTransaction`、`finishLedgerTransaction` 等 | 为定点业务写入复用原语，不复制锁、journal 或恢复协议 |
| Git/workspace 事务、结构化 recovery、隔离提交接线 | tools `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 与 `crctl.mjs` 的既有执行路径 | 沿用受控执行、审计和提交方式，不把原语暴露成任意文件写接口 |
| YAML 解析与现有回归组织 | tools `skills/shared/crctl/scripts/lib/yaml-subset.mjs`、`skills/shared/crctl/scripts/test/` | 优先复用，业务转换和接口行为用现有 fixtures/测试验证 |

**已核对的缺口：** 当前未发现规划/竞品的专用公开受控写入入口；它们的业务字段、确认和索引规则已在对应 Skill 中声明，但不能据此声称确定性写入已脚本化。事务原语存在，不等于这两个业务操作已经可调用。实施前复核目标分支，已有等价实现则直接复用。

### 1.2 逻辑架构与职责

在保证完成目标质量的前提下采用 ponytail 优先级：**复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码**。

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出、失败语义 | 手写原子账本逻辑、重复实现 crctl |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本/模块 | PRD/SDD/TASK/traceability 等确定性转换，本次两个业务路径的候选内容转换 | 状态推进、人工审批、另建事务执行器 |
| README | 人读流程总览、权威入口链接 | 另一份可执行细节事实源 |

### 1.3 本次最小改造

| 问题 | 本 CR 的处理 | 保持不变 |
|---|---|---|
| CR 节点重复遗漏 workspace | 当前任务预检后绑定，公共 CLI 归一参数 | 显式 CLI、注册前 bootstrap、路径与授权门禁 |
| 已知入口小错误扩大为恢复委派 | 新入口首次归一；旧入口/额外 PRD 检查由调用方 Skill 按约定纠正一次 | Pipeline onFail、reviewLoop、审批和事务恢复 |
| validate-doc 失实自动调用承诺 | 调用方决定触发，未声明维度明确未检查 | 必需校验、作者自检、独立评审；权限仅按下述范围定点登记 |
| 时间生成值与 schema 冲突 | 按文档类型/字段统一格式，兼容现有 schema | 既有时间字段、存量文档，不统一改成一种格式 |
| 未支持类型的能力委派 | 规划/竞品节点按自己的既有合同生成 | 不给通用生成器增加 DESIGN-DOC/COMPETITIVE 类型体系 |
| 索引责任和文件名不一致、业务写入未接线 | 调用方/目录图指定索引，补规划/竞品两个专用受控操作和确定性转换 | 不全仓改名、不建立通用索引服务或任意文件写入接口 |
| advance 示例缺少 CR-ID | 修正 7 个 Skill 中 12 处调用/说明文本 | CR-ID 仍是显式业务参数，不自动推断 |
| v 前缀口径不一致 | 明确兼容输入与规范化输出的区别 | 保留 normalizeTargetVersion 行为与持久化格式 |

**不纳入：** source 默认值修复、PRD/SDD validator、新状态机、新重试服务、新持久化 attempt 账本、新 MCP 工具、数据库/API 字段、审批权限或 controlled-shell 白名单变更；不新增通用文档/索引写入器、事务框架、权限框架、`auto-invoked-by`、反向调用清单、能力注册服务或矩阵扫描器的通用第五类检查。

**权限边界：** 取消错误的通用 frontmatter 委派要求，不等于允许直接编辑受控文件。`cr.md`、`_backlog.yml`、审批、评审记录等仍由既有 crctl 写入入口管理；specs/delivery 的 writeback 与人工确认不变。规划/竞品索引同样属于受控账本，但不纳入 CR 状态机。

当前 `product-planning-agent`、`competitive-analyst-agent` 均未登记 `can-call: crctl`。本次允许定点补充调用已有 crctl 的关系，并在 Agent/对应 Skill 中限定为各自业务写入操作；不因此授予 CR 状态推进、审批、合入或任意文件写入职责。新业务入口必须校验限定写入范围。现有矩阵只识别 Skill 级关系、不解析子命令权限；**矩阵及提示词约束不得冒充机器级子命令授权或隔离**，不为此建设新权限体系。

**审计边界：** 不把待核事项升级为已证明缺陷。source 的 required 是否意味着非空、目标前端的 UTC 显示原因不在本 CR 改行为；竞品字段的既有北京时间要求保留。AIFI-40 的 source/manual 冲突仍按独立修复处理，本 CR 不宣称消除该 Issue 的所有阻断。

## 2. 权威来源与整体执行顺序

| 信息 | 权威来源 | 使用方式 |
|---|---|---|
| 当前 CR 和 operational workspace | 当前 task 的预检结果 | 后续节点只消费已验证 execution_context |
| 任务可使用的 KB 根 | 当前任务可信项目资源 | 不以 cwd、历史评论或主机根列表代替 |
| 命令语法、支持类型、错误边界 | 目标 CLI 实现与已有合同 | 文档/示例对齐，不从“validate”名称推导通用能力 |
| 文档字段及格式 | 所属业务节点、适用 schema/模板 | 不将通用 schema 强套到业务专用类型 |
| 索引路径及写入责任 | 调用方合同和目录图 | 明确指定，不默认创建另一份索引 |
| 必需校验与评审 | 调用方步骤与既有流程 | 共享校验 Skill 不宣称自己会自动触发 |

执行链为：**可信根 → 当前上下文 → 只读预检 → task 绑定 → 既有业务节点 → 规定的自检/校验 → 原发布和审批流程**。

共享规则只保留权威合同。Agent/节点提示保留业务输入、输出、阶段和短指针；不各自重写绑定、恢复、能力范围或索引算法。

## 3. 运行上下文与入口绑定合同

### 3.1 两条入口，复用一次预检

**Pipeline 后续节点：** 复用 `preparePipelineTask`、`inspectPipelineWorkspace` 已有预检结果，以及 `Task.PipelineCrID`、`PipelineWorkspace`、`PipelineLocalWorkDir`。注册节点尚无 operational workspace，不适用后续节点自动绑定。

**普通 Issue 委派：** 从当前触发评论 `Task.TriggerCommentContent` 获取唯一 YAML `execution_context`，要求具有非空、合法的 `cr_id` 和 `operational_workspace`。拒绝重复键、多块、冲突或无效值；不扫描历史评论补齐，不因 `PipelinePrompt` 为空而跳过处理。

普通委派使用 `Task.ProjectResources` 中当前任务自己唯一且已验证的 KB `local_directory` 根，调用既有 `inspectPipelineWorkspace(ctx, root, cr_id)`。预检结果须与声明的 operational workspace 在真实路径意义上相同；真实路径检查复用已有规则，不能用字符串前缀代替。

缺少可信根、资源歧义、路径越界或 worktree 不健康时，停止准备该 CR 节点并报告配置/上下文问题。如果项目目前只有 GitHub 资源，先用现有项目能力配置 KB 本地根；不猜目录、不改全局根列表代替授权。

### 3.2 task 环境与公共 CLI

复用既有 `MULTICA_TASK_ID`、`CRCTL_OPERATIONAL_WORKSPACE`、`CRCTL_TASK_AUDIT_ROOT`。绑定在 `custom_env` 合并后写入；无可信绑定时清除旧值。每个 task 使用自己的环境，不共享一个可被覆盖的 context 文件。

普通 CR 委派也接入现有 launcher 和 Git 环境配置；launcher 是便捷入口，不承担唯一的安全检查。

在 `skills/shared/crctl/scripts/crctl.mjs` 添加私有 `bindTaskWorkspace(cmd, flags, env)`，在参数解析后、原显式 workspace 检查前执行：

```js
bindTaskWorkspace(cmd, flags, process.env);
requireExplicitWorkspace(cmd, flags);
```

该函数只对既有需要 workspace 的命令归一 `flags.workspace`，不补 CR-ID、不改业务命令处理器：

- 任一 CRCTL 绑定变量存在时，包括空串/空白，按“绑定声明存在”检查；两者及当前 task ID 必须完整有效。
- 仅有 `MULTICA_TASK_ID` 不代表已绑定 CR；普通非 CR 任务和注册 bootstrap 不能因此被误判为不完整绑定。
- 有完整、有效的绑定且未传 workspace：使用预检后的 operational 路径。
- 显式 workspace 与绑定为同一真实目录，包括合法路径别名：接受。
- 显式路径不同、绑定不完整或互相冲突：用 `WORKSPACE_CONTEXT_MISMATCH` 零业务写入失败，不能覆盖绑定。
- 两个 CRCTL 绑定变量均不存在：保持原显式 CLI 模式；未传必需参数仍返回 `WORKSPACE_REQUIRED`，旧 `CRCTL_WORKSPACE` 不参与判断。
- help 等原本不需要 workspace 的命令，保持原行为，不因缺失绑定而被误拒绝。

`CRCTL_WORKSPACE` 不作为 fallback。daemon 的只读预检在受控 Agent 运行上下文之外，继续明确传 authority root；注册前 bootstrap 继续使用既有明确根的入口。独立终端/CI 也继续显式传 workspace。

## 4. 文档生成、校验与索引合同

### 4.1 校验按调用方步骤触发

`validate-doc` 是被显式调用的检查 Skill，触发来源是调用方步骤或用户明确要求。删除“任何文档写入后自动调用”“所有写入型 Skill 自动调用”等承诺；描述职责，不建立反向调用注册表。

对 naming/locations 等依赖类型声明的检查：

- 该类型确实没有声明该维度：输出 WARN，明确写“该维度未检查”；其他适用维度继续。
- 必需配置无效，或违反已声明规则：仍按既有失败合同处理，不能用 WARN 豁免。
- 缺少证据不能宣称完整通过；关键词出现也不能证明实际调用。

`crctl validate` 仍是专用 artifact/schema 校验器。当前支持 `cr.md`、`_backlog.yml`、`review-annotations/*.yml`、basename 为 `requirement.yml|sdd.yml|code.yml` 的既有分支、`test-report.md`、`approval.yml`、`traceability.yml`；不支持 `prd.md` 和 `sdd.md`。实施时用目标版本验证，不将列表误缩成“五类”。

PRD 保留 `write-requirement-prd` 原定重读自检；SDD 保留其规定检查。既有评审、门禁和独立 reviewer 保持。tools `AGENTS.md` 明确“validate-doc 或调用方规定的等价检查”，不为 CR 写入节点增加额外通用校验闸门。

### 4.2 engineering-docs 的职责收窄

engineering-docs 只承诺已有模板/schema 明确支持的 PRD、SDD、MODULE、PLAN、TASK、RELEASE、FORM，不宣称能生成任意业务 frontmatter。

调用方必须区分：

1. **参考模板：** 使用适用模板或自身既有字段合同构造内容，落盘/索引的业务责任由调用方承担；不把这写成完整委派，也不授权 Skill 裸写账本。
2. **完整执行 Skill：** 文档类型必须受支持，路径、检查及写入责任明确，需要受控写入时已有可用的规定入口，才按完整步骤执行。只有模板/schema 不等于具备完整落盘能力。

不新增 renderOnly 参数或通用生成服务。删除“任何 frontmatter 必须走本 Skill”的绝对化要求，改为“按所属文档合同生成和检查；受控文件仍走规定写入入口”。普通文档使用当前运行时已有且获准的文件写入能力，不再固定 `owClient.writeFile`；受控账本及关联文件按 §4.4 执行，不凭空增加 SDK 或 adapter。

**规划条目：** `write-planning-entry` 直接消费已确认的 planning-draft 草稿，保留其既有 DESIGN-DOC 业务格式；正式 id 与当前 `{YYYY-MM-DD}-{slug}` 文件/索引 id 一致，替换草稿待分配值。本节点决定内容、确认、冲突处理及目标索引，经专用受控操作完成落盘，不请求通用生成器生成未支持类型。同步 planning-draft 的“engineering-docs 落盘/自动分配序号”说明，指向既有 `write-planning-entry`；不新增全局序号分配器。

**竞品报告：** `write-competitive-report` 按自身已列出的 frontmatter、章节及索引字段生成，不借未声明的 `doc-role=COMPETITIVE` 映射到通用 schema。保留确认后写入、冲突时询问、保留原 body、按 `(date,title)` 幂等追加 updates 等原规则；经 §4.4 的专用受控操作落盘，不得为去掉错误委派削弱这些保障。

相关 requires/delegates 与文字同步反映实际使用；仅按 §1 定点补充已有 crctl 的调用关系，不因引用过旧泛化权限。权限矩阵、Agent 定义及相关索引同步检查。

### 4.3 时间格式按字段，不按“所有时间”套用

本方案采用**兼容现有 schema/存量文档**的路径，不修改通用 schema 的字段类型：

| 文档/字段 | 格式与来源 |
|---|---|
| 适用 engineering-docs common schema 的 `created/updated` | 按北京时间日历生成 `YYYY-MM-DD`，匹配既有 isoDate；不依赖宿主机默认时区 |
| planning-draft 既有日期字段 | 保留其文档约定的日期格式，不强套通用完整 timestamp |
| CR 流程、角色或审计的既有 timestamp 字段 | 保留各自完整 ISO/北京时间合同 |
| 竞品 `reportDate` | 保留 `YYYY-MM-DD` |
| 竞品 `addedAt/updated` 等规定字段 | 保留完整 `YYYY-MM-DDTHH:mm:ss+08:00`，不套 common isoDate |

修订 engineering-docs 的 `today` 生成说明，使模板渲染值与 schema 一致。相同字段名出现在不同文档，不代表相同类型；不批量重写已有文档，不放宽 pattern 以掩盖冲突。若未来要把通用日期字段升级为 timestamp，应另经兼容评审，不由本次实现者顺带改动。

### 4.4 索引的业务责任与受控执行分开

索引路径从调用方合同/目录图获得，不再默认给每种文档创建 `_index.yaml`。

- 规划和竞品按既有 `_index.yml` 合同更新；不得同时生成另一份 `_index.yaml`。
- 已明确使用 `_index.yaml` 的工程文档继续使用原路径，不全仓改后缀。
- 调用方已经负责索引时，共享模板参考不再自行写索引；没有索引合同则不猜测创建。
- 必须更新索引却没有可用受控入口时，明确中止完整执行；可保留模板参考/草稿，不能跳过索引后宣称完成。本次不补齐所有文档类型的生成与索引能力。

**最小执行关系：** Skill 的业务判断与确认 → crctl 业务入口的参数/写入范围校验 → 版本化模块的确定性候选内容转换 → 既有事务原语的 CAS、写入、审计、提交与恢复。

只补规划、竞品两个业务专用受控操作，具体命令命名和转换模块文件名由该 CR 的 SDD 确定。转换模块可直接调用，不必另起进程或建立 adapter；不复制 Skill 的业务判断，也不自行推进状态、审批或管理事务。crctl 不生成报告、不替用户选择覆盖策略，入口不得接收可绕过业务范围的任意文件写清单。非 CR 规划/竞品任务仍使用可信项目根的显式 workspace，不伪造 CR-ID 或将它们纳入 CR 状态机。

| 操作 | 同一次业务写入范围 | 必须保留的规则 |
|---|---|---|
| 规划落盘 | 正式文档＋指定规划索引 | 已确认草稿、正式 id/路径一致、禁止静默覆盖及原冲突处理 |
| 竞品落盘 | 报告＋竞品主文件规定的 frontmatter 更新＋reports 索引 | 明确确认、覆盖/日期冲突询问、原 body 不变、updates 按 `(date,title)` 幂等追加及原索引规则 |

**一致性：** 成功返回时关联文件一致，不得单边成功就报告完成；中断按已有事务机制恢复，CAS 冲突或第三方修改不得强行覆盖。提交沿用既有隔离方式，不夹带无关改动。既有 write-set 是可恢复的多文件写入，**不承诺多文件瞬时可见或跨仓/跨远端的全局原子性**；不为更强保证建设新基础设施。Skill 不猜测补账或直接编辑账本。

被动 Skill 的步骤、模板使用说明及已确认调用方一起对齐。legacy CLI/MCP 源码存在不代表它属于当前执行通道；本次不因此删除或重构遗留实现。

### 4.5 命令与输入示例对齐现有实现

修正 7 个 Skill 中 12 处 advance 调用/说明文本，保持 CR-ID 显式：

```bash
# 已绑定 CR 后续节点
crctl advance {cr_id} --to tech-design-review-pending --trigger write-tech-design-complete --expect tech-designing
# 独立 CLI：仍必须显式传根
crctl advance {cr_id} --to tech-design-review-pending --trigger write-tech-design-complete --expect tech-designing --workspace {workspace}
```

仅 workspace 可由有效绑定补齐；`BAD_ARGS` 不是新增的通用本地恢复许可。

目标版本选择**保留既有规范化兼容**：`target_version` / `--target-version` 输入可带 v/V，现有 `normalizeTargetVersion` 规范化后持久化为无前缀 `MAJOR.MINOR[.PATCH]`。示例统一推荐 `0.16.0`，说明兼容输入，不把 v 前缀再描述成必然非法。`unassigned` 的确认规则、禁用同义值和 prerelease 等原限制不变；不改变其他 `version` 字段或分支名的命名规范。

这是本方案提出的兼容口径，纳入 CR 需求评审；若业务要求严格拒绝历史前缀输入，必须先修改需求/兼容范围，而不是静默改变代码行为。

同样将 approve 的局部绝对化句改为：**人类交互终端，或服务端已签名并通过校验的 grant；无合法 grant 的非 TTY 调用拒绝**。不增加 Agent 代签能力，不放宽验签或授权。

## 5. 调用方 Skill 的同 run 本地纠正约定

**正常路径不是重试：** 新公共入口在绑定有效时直接补齐 workspace，遗漏参数的首次调用即应通过入口检查；不先制造 WORKSPACE_REQUIRED 再纠正。

本地纠正只处理下表的例外，且必须同时满足：错误来自可信既有入口、确定发生在业务写入前、原意和合法输入明确、无须新授权、已有可信上下文。**同一节点、同一 run 最多一次纠正**是调用方 Skill 的行为约定，以节点日志/回放验收，**不宣称机器计数或硬保证**；不跨 run 自动重启，不重置评审 attempt，不新增持久化重试状态。

| 首批允许情形 | 调用方 Skill 的原地动作 | 不适用边界 |
|---|---|---|
| 可信旧显式入口返回 WORKSPACE_REQUIRED，已确认合法根，仅遗漏参数且日志证明入口预检零业务写入 | 补显式 workspace 后调用一次；不扫描或自动切换 CLI 版本 | 上下文本身缺失/冲突、猜根、改权限、写入阶段不明 |
| 恰为额外添加的 `validate prd.md` 返回 UNKNOWN_ARTIFACT | 停止这项不适用检查，执行原 PRD 重读自检，完成原节点后续登记/发布 | 跳过任意未知类型、必需校验或 SDD 检查 |

第二次失败、权限/路径拒绝、上下文冲突、审批问题、CONTRACT_DRIFT、注册指纹冲突、写入/提交结果不明，全部走既有停止或事务恢复路径；只按错误码不能证明零写入。Pipeline 保持 `onFail: abort`。

共享 `crctl/SKILL.md` 可以描述调用约定，但不将业务判断归给 CLI。在本地纠正路径，crctl 代码只负责绑定校验、参数归一和原有失败/恢复处理，不判断 PRD 检查是否多余、不自动重试业务命令。本节不扩充纠正情形，不建立通用错误纠正引擎。

## 6. 提示词收敛合同

机器绑定验证成功后，才删除受控 CR 后续节点中的“每条命令手工附 workspace”重复提示。原注册 bootstrap、独立终端/CI、daemon 预检示例保留明确根。

Agent/Skill/Pipeline 仍保留：

- execution_context 的输入输出及消费方式，业务 CR-ID 与目标阶段。
- 作者、reviewer、审批人的职责及权限。
- 实际支持的写入入口、校验通道和发布/checkpoint 要求。
- 指向 crctl 权威绑定/受控写入合同，以及调用方 Skill 本地纠正约定的短指针。

不删必要业务参数；不把“自动绑定 workspace”改写成“所有参数自动补齐”。同步清除错误的通用生成/自动校验委派，替换为本方案定义的调用方责任，避免减少文字后反而留下隐含契约。

## 7. 实施分解：一个 CR、两个任务

### 任务 A：预检上下文并绑定公共入口

**接口：** 消费已有 Task 字段、当前触发评论及可信项目根；产出当前 task 的已验证 operational 绑定。CLI 通过私有 `bindTaskWorkspace(cmd,flags,env)` 向原处理器提供明确 workspace，不生成新账本或公共 API。

**落点：**

- multica `server/internal/daemon/pipeline_task.go`：复用预检、launcher、Git 环境配置；接入普通 CR 委派。
- multica `server/internal/daemon/daemon.go`：保持 custom_env 后绑定、无绑定清旧值，覆盖普通任务路径。
- multica 测试：`pipeline_task_test.go`、`cr_workspace_binding_test.go`，放在既有测试组织内。
- tools `skills/shared/crctl/scripts/crctl.mjs`：公共参数归一入口。
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs` 等既有测试：绑定/显式模式/冲突/直接脚本调用。

**步骤：**

- [ ] 在既有 fixtures 中补 A1—A8 的失败用例，先观察当前缺失绑定或遗漏普通 Issue 路径的失败。
- [ ] 接入唯一 execution_context 解析及可信根预检；复用已有 inspect/launcher/environment helper。
- [ ] 实现公共绑定归一和冲突拒绝，保留显式模式；不重构命令处理器。
- [ ] 运行 A 向量、相关回归及 Windows 动态路径用例；记录普通 Issue 与 Pipeline 两条路径。
- [ ] 以现有 CR Git 门禁提交并独立评审；交付可兼容旧显式提示的实现。

### 任务 B：补齐定点受控写入，统一合同与短提示，完成部署

**接口：** 消费任务 A 的有效运行模式及原有业务输入；产出规划/竞品两个业务受控操作、确定性转换模块和 §4—§6 的已对齐合同/提示。业务确认、评审循环、审批、checkpoint 合同不变。任务 B 包含必要的确定性实现，不是仅修改文档和提示词；新增范围须纳入该 CR 需求/架构评审，不直接变更已审批 CR 的范围。

**落点：**

- tools `skills/shared/crctl/scripts/crctl.mjs`：两个专用业务入口及受控执行接线，复用既有事务、审计和隔离提交路径，不开放通用任意文件写接口。
- tools 对应规划/竞品 Skill 的版本化转换模块：在该 CR 的 SDD 中确定文件落点，作为可直接调用的确定性模块；不引入新执行器，不复制事务逻辑。
- tools `skills/shared/crctl/SKILL.md`：绑定、业务写入接口、调用方本地纠正约定、命令/审批语句。
- tools `agent-skill-matrix.yml`、`agents/{product-planning-agent,competitive-analyst-agent}.md` 及必要索引：按 §1 定点登记和限定已有 crctl 的调用关系。
- tools `skills/shared/validate-doc/SKILL.md`、`AGENTS.md`：触发、WARN、校验通道及写入权限边界。
- tools `skills/shared/engineering-docs/SKILL.md`：类型、运行时写入前提、时间和索引责任；检查关联说明，保持现有 schema/模板资产格式。
- tools `skills/planning/{planning-draft,write-planning-entry}/SKILL.md`、`skills/competitive/write-competitive-report/SKILL.md`：各自生成、确认、id、落盘和索引合同。
- tools 缺 CR-ID 的 7 个 Skill：`cr/cr-review-record`、`develop/{review-code,review-dev-plan,review-tech-design,write-dev-tasks,write-tech-design}`、`requirement/review-requirement`。
- tools `skills/requirement/requirement-register/SKILL.md`、`pipeline-templates/requirement-authoring.pipeline.json`：目标版本输入与规范化值；README 仅同步人读总览及权威链接，不复刻可执行细节。
- tools 既有 `caller-contract.test.mjs`、`contract-scan.test.mjs`、`pipeline-structure.test.mjs`、`crctl.test.mjs`、`durable-tx.test.mjs`：定点回归，业务行为优先通过受控操作接口验证。
- multica `cr-prompts-revised/{requirement-writer,dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md`、维护的部署副本及既有 delegation-contract 测试；实际 imported Skills、Agent instructions 与上游规则同步，包含本次涉及的规划/竞品调用方。

**步骤：**

- [ ] 将 B 向量观察点补到现有测试/运行回放；旧审计脚本断言的是冲突存在，不能原样作为修复后的通过标准。
- [ ] 复核现有业务写入能力；无等价实现时，补两个专用入口和确定性转换，复用既有事务路径，验证规划两文件、竞品三文件的一致性、CAS、范围拒绝及中断恢复。
- [ ] 按 §4 统一共享合同和调用方，消除互斥日期、未知委派及双索引责任；完整执行缺受控入口时明确中止。
- [ ] 定点登记两个角色调用已有 crctl，限定各自操作，同步 Agent/Skill/必要索引；不宣称矩阵实现机器级子命令授权。
- [ ] 补 CR-ID 示例、统一版本口径、限定审批与运行时前提；不改已有校验/规范化函数行为。
- [ ] 对照任务 A 的已覆盖模式清理重复 workspace 提示，保留 bootstrap/显式说明及必要参数；分别验收首次归一和旧入口的一次纠正。
- [ ] 运行 B 回归并回放本地纠正；复核规则与权限矩阵，不以静态关键词证明 Agent 行为。
- [ ] 按 §9 分阶段部署，核对线上版本；同一 CR 内提交和独立评审，不另立基础设施任务。

## 8. 验收向量与实际证据

| 编号 | 情形 | 必须观察到的结果 |
|---|---|---|
| A1 | Pipeline 有效绑定，Git 检查不传 workspace | 首次调用使用本 CR operational 路径，无 WORKSPACE_REQUIRED，不产生重试或恢复委派 |
| A2 | 同环境直接 node 执行 crctl.mjs | 与 launcher 同结果，不绕过绑定 |
| A3 | 普通 Issue，唯一上下文与可信项目根 | 自动预检/绑定，不依赖 PipelinePrompt 非空 |
| A4 | 缺失/重复/冲突上下文、无根、越界或坏 worktree | 停止准备节点或零业务写入失败，不猜根 |
| A5 | 显式路径同真实目录/合法别名，或不同目录 | 同目录接受，不同目录拒绝覆盖 |
| A6 | 独立 CLI/bootstrap；包括仅 task ID、旧 CRCTL_WORKSPACE | 显式方式有效，旧变量不作 fallback，缺参报错；help 可用 |
| A7 | 并发 task、custom_env、主机遗留值 | task 隔离，无绑定清旧值，配置不能覆盖绑定 |
| A8 | Windows 空格/中文、POSIX、Git --/--cwd | 参数保持正确，不重拼 shell 字符串 |
| B1 | 可信旧显式入口遗漏 workspace，已有确认根且日志证明预检零业务写入 | Skill 补显式参数后同 run 调用一次，不创建恢复委派，不扫描/切换 CLI 版本；与 A1 的首次归一区分 |
| B2 | 额外 PRD validate 不适用 | 回到原重读自检，后续登记/发布仍完成 |
| B3 | 第二次失败、权限/绑定冲突、写入不明 | 既有异常路径上报，不继续自动重试 |
| B4 | 短提示与线上配置 | 上下文/业务参数保留，显式模式和原流程不误删 |
| B5 | validate-doc/AGENTS/PRD/SDD 合同 | 无 blanket 自动调用，无新增通用校验闸门 |
| B6 | 未声明维度 vs 必需配置无效/违反规则 | 前者 WARN 且未检查，后者按既有失败；不能宣称完整通过 |
| B7 | 合法评审 YAML、prd.md、sdd.md | 既有 YAML 分支有效；PRD/SDD 仍 UNKNOWN_ARTIFACT，不扩恢复集合 |
| B8 | common 日期字段，含北京时间跨日边界 | 渲染值匹配原 schema；业务 timestamp 保留，不改存量格式 |
| B9 | 已确认规划草稿、竞品报告 | 各自字段/id/章节有效，不再调用未支持的通用类型；未确认仍零写入 |
| B10 | 调用方 yml 索引、既有 yaml 索引、无索引合同 | 有获准入口时只更新指定路径；无合同不创建，无另一份默认索引，不全仓改名 |
| B11 | 7 个 Skill 的 12 处 advance 文本 | CR-ID 完整；真实调用不在缺位置参数处 BAD_ARGS，业务门禁仍执行 |
| B12 | 0.16.0、v/V 前缀、unassigned、禁止值/prerelease | 原规范化/拒绝边界保持，文档区分输入和无前缀持久化值 |
| B13 | 审批与文件写入前提 | grant/TTY 说明与现实现一致；除定点业务调用登记外，不放宽原授权、审批或写入范围 |
| B14 | imported Skills、Agent instructions、仓库来源 | 实际生效版本一致，覆盖规划/竞品调用方；只改仓库文档不算部署完成 |
| B15 | 已确认的规划/竞品受控操作成功及同一操作重跑 | 规划两文件、竞品三文件一致，正文及既有确认/冲突规则保留，不重复登记；脚本不推进状态或审批 |
| B16 | 专用入口收到越界路径或超出业务范围的写入请求 | 零业务写入拒绝，不开放任意文件写接口 |
| B17 | 候选生成后出现并发修改或恢复时遇到第三值 | 既有 CAS/冲突路径拒绝覆盖，不由 Skill 强行补账 |
| B18 | 两文件/三文件写入中断及提交阶段中断 | 沿既有事务机制恢复，最终关联文件一致；未收敛不报告完成，不承诺瞬时可见或全局原子性 |
| B19 | engineering-docs 必须更新索引但没有可用受控入口 | 中止完整执行，可保留模板参考/草稿，不跳过索引后宣称完成 |
| B20 | 两个角色的 crctl 调用登记及职责说明 | 矩阵/Agent/Skill/必要索引一致，仅声明对应业务操作；不冒充机器级子命令授权 |

确定性示例（迁入现有测试，不新建框架）：

```js
assert.deepEqual(normalizeTargetVersion('v0.16.0'), { ok: true, value: '0.16.0' });
assert.equal(new RegExp(common.definitions.isoDate.pattern).test('2026-09-30'), true);
assert.equal(new RegExp(common.definitions.isoDate.pattern).test('2026-09-30T22:00:00+08:00'), false);
```

其中 normalizeTargetVersion 从已有 workspace-transactions 模块导入，common 读取现有 common-defs.schema.json。日期断言还需配套校验修订后生成合同，不把“schema 拒绝 timestamp”误当作错误已经消失。

从 tools 根运行：

```bash
node --test skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/caller-contract.test.mjs skills/shared/crctl/scripts/test/contract-scan.test.mjs skills/shared/crctl/scripts/test/pipeline-structure.test.mjs skills/shared/crctl/scripts/test/durable-tx.test.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs
```

从 multica 的 server/ 运行 `go test ./internal/daemon -run 'Test.*(Pipeline|CRWorkspace|TaskCR|Bound|ExecutionContext)'`；仓根运行 `node --test cr-prompts-revised/test/delegation-contract.test.mjs`。

实施者记录实际命令/结果。Windows 动态用例必须在 Windows 执行；受控操作的一致性、范围拒绝、CAS 和中断恢复必须有接口级运行证据；本地纠正、未声明维度和业务文档行为用既有节点日志/回放验收。机械检查通过、关键词命中或旧审计复现通过，不等于语义合同和生产行为都正确，也不能证明“一次纠正”具备机器硬保证。

## 9. 发布、回退与完成标准

1. 确认包含两个业务受控操作的 CR 范围以及项目可信 KB 根；没有根先完成现有配置，不只交付 Pipeline 路径。
2. 发布兼容显式模式的 CLI/daemon 实现及两个定点受控操作，暂保留原 workspace 提示。
3. 验证 Pipeline、普通 Issue、直接脚本入口、业务受控写入及失败/恢复；使用合法业务输入，source 的独立缺陷单独报告，不绕过 CONTRACT_DRIFT。
4. 按现有平台流程同步共享合同、调用方 Skills、定点调用关系、短提示、Agent instructions 和上游规则，检查 imported/线上版本真正生效。
5. 收集 A/B 全部证据：新入口首次归一、旧入口一次显式参数纠正、额外 PRD 检查处理、日期/规划/竞品/索引合同、受控写入与恢复、正确 advance 示例；独立评审与审批仍走原流程。

**回退：** 先恢复安全的显式 workspace 调用方式，再撤回绑定代码。撤回新增业务操作前先停止其调用并收敛在途事务；没有等价受控入口时暂停正式落盘、保留草稿，不恢复 Skill 手写账本。不把已纠正的失实能力/校验声明重新作为回退目标。已有 CR、指纹、账本和 reviewLoop attempt 不迁移、不重写。文档修订不触发历史内容批量重生成。

**完成标准：** 一个 CR 内 A/B 所有验收项具有测试或运行证据；普通 Issue 与 Pipeline 均覆盖；两个业务操作及关联文件的一致性、CAS 和中断恢复有证据；调用、字段、索引与校验合同一致；线上和仓库版本同步。除已声明的定点业务调用登记外，原权限、审批、路径与事务边界不放宽，不将提示词约束宣称为机器硬保证。代码、文档和线上配置三者只完成其中之一，不算完成；本轮仅交付方案文档。

**最小落点：接通已有入口、补两个业务写入缺口、明确调用方的一次纠正约定、让声明符合真实合同，再删除重复提示；一个 CR、两个任务，复用事务基础设施，不再造框架。**
