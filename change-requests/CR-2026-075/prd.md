---
id: CR-2026-075-prd
type: PRD
cr-ref: CR-2026-075
title: CR 执行入口与声明一致性修订方案
target-version: 0.48
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owner-role: requirement
status: draft
created: "2026-10-02T21:07:07+08:00"
updated: "2026-10-02T21:07:07+08:00"
---

# CR 执行入口与声明一致性修订方案

## 1. 概述

### 1.1 需求来源与权威边界

本需求来自 AIFI-41 的附件 `2026-09-30-crctl-bound-workspace-local-recovery.md`，标题《CR 执行入口与声明一致性修订方案》v4，attachment id 为 `01a0f837-a3ce-7567-b005-de7e1a77f921`。附件是尚未实施的方案，本 PRD 将其实施目标纳入新 CR，不将方案交付误报为代码或配置发布。

注册权威为本 CR 的 `cr.md`：目标版本 `0.48`、目标 spec `ai-first-platform`，需求/开发/测试三角色负责人均为 Ray（`a0e71a32-509d-4ee9-aea4-d086a5b1ff93`）。`origin` 为空，不关联其他 CR，无 promotion 上下文。附件是本 Issue 的输入，而非仓库规划报告路径，故注册 `source` 保持空串；不将附件下载路径、历史 `manual` 或 Issue URL伪造成 worktree 内的文件来源。

### 1.2 问题陈述

1. Pipeline 已有 CR 预检与 operational workspace 路径，但普通 Issue 委派未获得同等接线，调用方反复手填 workspace，遗漏入口参数会扩大为无必要的恢复委派。
2. 共享文档能力与调用方声明不一致：未支持类型被委派给通用生成器、日期值与 schema 冲突、索引责任重叠、校验被描述为自动触发。
3. 规划/竞品的业务确认与索引规则已声明，但声明不能替代可调用的受控写入操作；需要补业务入口而非重造事务基础设施。
4. 示例中的 CR-ID、目标版本输入、审批和运行时前提表述须与真实合同一致；仅改仓库文档而未同步生效配置不构成完成。

### 1.3 解决方案摘要与实施分解

本 CR 内只有两个内部任务，不另拆 CR，也不在需求期创建开发任务账本：

| 内部任务 | 交付边界 | 依赖/顺序 |
|---|---|---|
| A：预检上下文并绑定公共入口 | Pipeline 与普通 Issue 使用可信预检结果，绑定到独立 task 环境；launcher 和直接 node 入口具有一致参数归一与冲突拒绝行为 | 先交付兼容原显式 CLI 的实现及测试 |
| B：补齐定点受控写入并统一合同/部署 | 两个业务专用写入操作与确定性转换；文档、日期、索引、校验、输入示例、调用关系、本地纠正和短提示对齐；同步实际生效版本 | 在 A 验证后收敛重复提示，完成全范围测试与部署 |

复用现有 daemon 预检、launcher、Git 环境配置、crctl 公共入口、锁/journal/CAS/write-set/恢复/审计/隔离提交与现有测试。Skill 负责业务判断和确认，版本化模块负责确定性候选转换，crctl 独占受控执行；模块名称、命令名称、指纹序列化与事务实现方案由 SDD 确定。

### 1.4 现状核实与引用先例

2026-10-02 注册前后的只读核实确认：multica `server/internal/daemon/pipeline_task.go` 存在 `preparePipelineTask`、`inspectPipelineWorkspace`、`installPipelineCrctlLauncher`、`configurePipelineGitEnvironment`；tools 的 `durable-tx.mjs`、`workspace-transactions.mjs` 及所列测试文件存在。当前 crctl 主命令分派未发现规划/竞品专用分支，实施前仍应复核是否已有等价入口。

已读取 tools 的 `write-planning-entry/SKILL.md` 和 `write-competitive-report/SKILL.md`：规划路径/id 与 `_index.yml`、规划审批、slug 冲突追加短 hash；竞品的明确确认、报告冲突选择、原 body 保留、按 `(date,title)` 追加 updates、reports 索引与日期规则均作为保留先例。新操作只补确定性执行缺口，不替代业务确认、不复制已有事务协议。

附件引用的审计报告及旧 commit 仅为历史依据，不替代当前目标分支事实或本次验收证据。既有 shared common 日期 schema 路径已核实存在；不将其强套到 CR 或竞品的完整 timestamp 字段。

## 2. 用户故事

| 编号 | 角色、行为与价值 |
|---|---|
| US-01 | 作为 CR 执行 Agent，我希望 Pipeline 与普通 Issue 都在准备节点时获得已验证的 operational workspace，使合法首次调用不因遗漏 workspace 进入恢复委派。 |
| US-02 | 作为 workspace 管理者，我希望绑定不能被配置、历史环境或显式异根覆盖，使跨 task、越界与坏 worktree 在业务写入前被拒绝。 |
| US-03 | 作为需求/设计作者，我希望按所属文档合同生成和检查，不把未支持类型委派给共享生成器，也不因额外不适用检查丢失原节点成果。 |
| US-04 | 作为规划/竞品责任 Agent，我希望在明确确认后，通过专用受控操作一致更新关联文件和指定索引，中断可恢复且不覆盖并发修改。 |
| US-05 | 作为独立 reviewer，我希望每项 A/B 验收具有接口测试或真实节点回放，能区分机器约束与提示词约定，避免静态关键词冒充实际行为。 |
| US-06 | 作为部署负责人，我希望代码、仓库合同与实际 imported Skills/Agent instructions 一致，并可安全恢复显式调用模式。 |

## 3. 功能需求

### FR-01：两条 CR 入口使用可信预检

- Pipeline 后续节点消费现有 `Task.PipelineCrID`、`PipelineWorkspace`、`PipelineLocalWorkDir` 与预检结果，不重复发明根解析。注册 bootstrap 尚无 operational workspace，仍使用明确 KB 主 checkout。
- 普通 Issue 从本次 `Task.TriggerCommentContent` 读取唯一 YAML `execution_context`，其中 `cr_id` 合法非空，`operational_workspace` 非空；缺失、重复键、多块、冲突或非法值停止准备 CR 节点。不扫描历史评论补齐，不以 `PipelinePrompt` 为空跳过。
- 仅使用当前 `Task.ProjectResources` 中唯一且已验证的 KB `local_directory` 根，通过既有 inspect 核实 CR authority；声明与预检结果必须是同一真实目录。
- 无可信根、资源歧义、越界或坏 worktree 均停止；只有 GitHub 资源时需使用既有项目能力配置 KB 本地根，不猜 cwd、不使用主机根列表替代授权。

### FR-02：task 环境隔离与入口一致

复用 `MULTICA_TASK_ID`、`CRCTL_OPERATIONAL_WORKSPACE`、`CRCTL_TASK_AUDIT_ROOT`。绑定在 `custom_env` 合并后写入；无可信绑定时清除旧 CRCTL 绑定值。每个 task 独立持有环境，不建立共享可覆写 context 文件。普通 CR 委派接入既有 launcher 与 Git 环境配置；同环境直接 node 执行 crctl 与 launcher 必须同结果，不以 launcher 作为唯一安全层。

### FR-03：公共 CLI 首次归一与失败关闭

仅对原本需要 workspace 的命令，在原显式根检查之前归一 workspace，不补 CR-ID、不改业务处理器：

1. 两个 CRCTL 绑定变量任一存在（包括空串/空白）即视为绑定声明；它们与当前 task ID 必须完整有效，否则拒绝。
2. 有完整有效绑定：遗漏 workspace 使用已预检的 operational 路径；显式路径为同一真实目录或合法别名时接受，不同目录时拒绝覆盖。
3. 两个绑定变量均不存在：保持原显式 CLI 模式。仅 task ID 不表示已绑定；旧 `CRCTL_WORKSPACE` 不参与 fallback。缺 workspace 仍报 `WORKSPACE_REQUIRED`。
4. 原本不需要 workspace 的 help 等命令保持原行为。

绑定不完整、冲突或显式异根统一返回 `WORKSPACE_CONTEXT_MISMATCH`，在业务写入前拒绝；独立终端/CI、daemon 只读预检和注册 bootstrap 保留明确根。

### FR-04：调用方同 run 一次本地纠正

正常新入口首次归一，不先制造错误再重试。本地纠正仅允许以下两项，且需可信入口、明确原意/合法输入、已有可信上下文、日志证明业务写入前失败、无新授权：

- 可信旧显式入口仅遗漏 workspace，返回 `WORKSPACE_REQUIRED`：补已确认的显式根后同节点同 run 调用一次，不扫描或切换 CLI 版本。
- 恰为额外添加的 `validate prd.md` 返回 `UNKNOWN_ARTIFACT`：停止此不适用检查，执行原 PRD 重读自检，继续本节点原有登记/发布。

同节点同 run 最多一次纠正是 Skill 行为约定，只以节点日志/回放验收，不宣称机器计数。第二次失败、权限/路径拒绝、上下文冲突、审批问题、`CONTRACT_DRIFT`、注册指纹冲突或写入/提交结果不明，进入原停止或结构化事务恢复路径。`BAD_ARGS` 不在本地纠正许可内；不扩到任意未知类型或 SDD 检查；不跨 run 自动重启、不重置 review attempt，Pipeline 保持 `onFail: abort`。

### FR-05：校验触发及能力范围真实

`validate-doc` 由调用方规定步骤或用户显式请求触发，删除任何文档写后自动调用/所有写入 Skill 自动调用的 blanket 承诺。某类型未声明 naming/locations 等维度时 WARN 并明确“该维度未检查”，继续其他适用维度；必需配置无效或违反已声明规则仍失败，不用 WARN 豁免。

保留 crctl validate 的既有 artifact/schema 分支，包括 `cr.md`、`_backlog.yml`、评审 YAML 及既有 basename 分支、`test-report.md`、`approval.yml`、`traceability.yml`；PRD/SDD 不新增支持，`prd.md`/`sdd.md` 仍为 `UNKNOWN_ARTIFACT`。作者原 PRD 重读自检、SDD 规定检查、门禁与独立评审不变；tools AGENTS 明确“validate-doc 或调用方规定的等价检查”，不增加额外通用校验闸门。未检查或无证据不得声称完整通过。

### FR-06：文档生成按所属类型合同

engineering-docs 只承诺现有 PRD、SDD、MODULE、PLAN、TASK、RELEASE、FORM 模板/schema 范围。调用方区分模板参考与完整执行：参考不移交业务内容、落盘或索引责任；完整执行须类型受支持、路径/检查/责任明确、所需受控入口实际可用。删除任何 frontmatter 必须通用委派及固定 `owClient.writeFile` 的表述，不增加类型体系、renderOnly、SDK 或 adapter。

规划保留 DESIGN-DOC 业务格式，直接消费已确认 planning-draft，正式 id 与 `{YYYY-MM-DD}-{slug}` 文件和索引 id 一致，替换草稿待分配值；planning-draft 指向 write-planning-entry，不承诺全局自动序号。竞品保留自身 frontmatter、五个章节与索引字段，不再请求未支持的 COMPETITIVE 通用 schema。

### FR-07：日期按文档/字段生成

- 使用 engineering-docs common isoDate 的 `created/updated` 以北京时间日历生成 `YYYY-MM-DD`，不依赖宿主机默认时区；渲染值匹配现有 schema，不放宽 pattern。
- planning-draft 既有日期字段维持原合同。
- CR、角色、审计的既有 timestamp 保持各自完整 ISO/北京时间合同。
- 竞品 `reportDate` 保持纯日期；`addedAt/updated` 等规定字段保持 `YYYY-MM-DDTHH:mm:ss+08:00`。

不以相同字段名推导相同类型，不批量重写存量文档，不顺带调整前端 UTC 显示行为。

### FR-08：索引路径及责任唯一

索引路径取调用方合同/目录图。规划/竞品继续 `_index.yml`，已明确 `_index.yaml` 的工程文档维持原路径；不得同时默认创建另一份索引，也不全仓改后缀。调用方已负责索引时共享模板不重复登记；无索引合同不创建。

必须维护索引但无获准受控入口时中止完整执行，可保留参考模板/草稿，不跳过索引后报告完成。此次只补规划/竞品两个缺口，不补齐所有文档类型执行能力；legacy CLI/MCP 存在不代表当前可用通道，不因此删除或重构遗留实现。

### FR-09：两个业务专用受控操作

如目标分支无等价入口，提供规划落盘与竞品落盘两个专用公开 crctl 操作。调用关系为“Skill 业务确认 → 参数/限定范围校验 → 版本化模块确定性转换 → 既有事务/CAS/审计/隔离提交/恢复”。不接收任意文件写清单，不代替用户选覆盖策略，不生成业务报告，不推进 CR 状态或审批。

非 CR 规划/竞品显式使用可信项目根，不伪造 CR-ID，不纳入 CR 状态机。规划成功必须文档和指定规划索引一致；竞品成功必须报告、竞品主文件规定的 frontmatter 更新及 reports 索引一致。正文/索引转换与事务执行职责分离，不复制锁或恢复协议。

### FR-10：规划确认、冲突与重放

只接受上游已确认草稿及其确定的目标 id/路径、title、source、target-version、owner、正文和索引字段；正式 id/路径一致。未确认零业务写入。重复同一落盘意图不得再产生文档或索引条目；同名不同内容禁止静默覆盖，按原 slug 冲突追加短 hash 规则由 Skill 确认新目标，不能由 crctl 自动选择新业务意图。

幂等作用域为可信 workspace 中同一正式规划 id/目标路径；比较对象为上述已确认业务字段和正文/索引内容，排除当次执行自动生成的审计时间/事务标识，不增加注册式公共幂等键。优先检查输入/范围及确认，再处理未完成同意图事务恢复，再判同意图已完成重放；身份相同但业务内容漂移必须冲突，不因重放覆盖原结果。序列化算法由 SDD 定义。

### FR-11：竞品确认、冲突与重放

保留草稿完整展示与 `confirmed=true` 后落盘；保留报告已有时选择覆盖或新日期、原竞品 body 不变、reports 条目/排序及 `status: new` 规则。updates 以同一竞品下 `(date,title)` 判重，已存在项跳过，不以 source/summary 改动偷偷替换；新项按原字段追加。

报告操作身份为可信 workspace 中 `(competitor-id,report-date)`/已确认报告路径，参与重放判定的业务输入包括报告 frontmatter/正文、updates 条目集合、sources、指定索引内容及已确认冲突策略，排除自动审计时间/事务标识。相同意图重放不重复更新索引或 updates；同身份不同意图不得当作成功重放，覆盖需重新明确确认。检查与恢复/重放优先级同 FR-10。

### FR-12：一致性、错误闭包与事务恢复

本次是本地 CLI/daemon 入口，不新增 HTTP 接口，因此不引入 HTTP 状态。CLI 正常完成 exit=0；失败非零并提供既有 JSON `error` 对象及固定 `code/message`，事务错误保留规定的结构化 `recovery`。每次操作最多处理一个规划/竞品业务意图；无跨仓或跨远端全局原子承诺。

CLI 判定次序固定为：语法解析 → 可信 task/项目上下文 → 业务字段与真实路径/业务范围 → 业务确认与冲突策略 → 幂等/恢复 → 事务与提交；首个失败即唯一结果。矩阵只声明 Skill 级关系，不能冒充机器级子命令授权；新操作必须校验限定业务写入范围。绑定失败使用 FR-03 的唯一代码。新操作的输入/范围/确认/业务冲突四类采用下表固定 code；其余现有事务错误原样继承，不重映射为成功。完整错误枚举、校验实现与序列化算法归 SDD，不允许改变这里的行为优先级。

| 失败类/既有先例 | 状态、零写入范围与客户端动作 |
|---|---|
| `WORKSPACE_REQUIRED` / `WORKSPACE_CONTEXT_MISMATCH` | 非零、对应固定 code；零业务文件/索引写入。前者仅满足 FR-04 才可纠正，后者停止并修正可信配置，不猜根。 |
| `BAD_ARGS`（语法解析/缺少必需 argv） | 非零、固定 code；零业务文件/索引写入。修正命令输入，不纳入自动本地纠正。 |
| `BUSINESS_INPUT_INVALID`（业务字段不合法） | 非零、固定 code；零业务文件/索引写入。按原业务合同修正字段，不生成新意图。 |
| `BUSINESS_WRITE_SCOPE_DENIED`（越界/任意文件清单/超出操作范围） | 非零、固定 code；零业务文件/索引写入。不重定向到猜测路径、不自动改权限，交原异常入口处理。 |
| `BUSINESS_CONFIRMATION_REQUIRED`（未确认或覆盖策略未确认） | 非零、固定 code；零业务文件/索引写入。Skill 展示草稿/冲突并取得新的明确确认；草稿本身不调用写入操作。 |
| `BUSINESS_INTENT_CONFLICT`（同业务身份不同已确认内容且无新的合法冲突决定） | 非零、固定 code；不覆盖原文档/索引/updates。由 Skill 按规划 hash 或竞品覆盖/日期原规则重新确认，不换身份掩盖冲突。 |
| `TX_INPUT_CONFLICT` / `REGISTRATION_INPUT_MISMATCH` | 非零、对应固定 code；不重写已有事务意图或账本。核对原意和业务输入，不换键掩盖冲突；后者仅引用注册边界，不为新操作增加注册键。 |
| `TX_LOCK_HELD` / `CAS_CONFLICT` | 非零、对应固定 code；不强行取得锁、不覆盖并发第三值。保持现场，按既有恢复/冲突合同处理。 |
| `TX_RECOVERY_CONFLICT` | 非零、固定 code；不覆盖恢复中检测到的第三值。停止自动写入，请求已有异常裁决。 |
| `TX_GIT_FAILED` 或写入/提交中断 | 非零、既有固定错误与结构化恢复。已持久化 journal/部分 write-set 不承诺零残留，按同意图事务恢复；最终关联文件一致才可报告完成，不夹带无关改动。 |

错误不明或缺少合法恢复合同必须停止，不由 Skill 猜测补账。区分预检失败零业务写入与事务中断可恢复现场；不把任何非零退出一概宣称零写入。多文件 write-set 可恢复但不保证瞬时同时可见；不为更强保证建设新基础设施。

### FR-13：调用登记、命令示例与输入兼容

- 定点补 product-planning-agent 与 competitive-analyst-agent 调用已有 crctl 的关系，限定各自业务写入操作；同步矩阵、Agent/Skill 及必要索引。不授予 CR 状态推进、审批、合入或任意写入，不扩展矩阵检查器。
- 修正附件点名七个 Skill 的十二处 advance 调用/说明，全部含显式 `{cr_id}`；绑定只可补 workspace。覆盖 cr-review-record、review-code、review-dev-plan、review-tech-design、write-dev-tasks、write-tech-design、review-requirement，数量须按目标分支复核并消除范围内全部漏项。
- 保留 normalizeTargetVersion 既有兼容：输入可含 v/V，持久化输出无前缀 `MAJOR.MINOR[.PATCH]`；示例推荐 `0.16.0`，`unassigned` 确认、禁止同义值/prerelease 的边界不变。不改其他 version 字段或分支命名。
- approve 明确人类交互终端或已签名且通过校验的服务端 grant；无合法 grant 的非 TTY 拒绝。不允许 Agent 代签，不放宽验签。

### FR-14：绑定验证后收敛重复提示

先实现并验证 FR-01～03，再删除受控 CR 后续节点逐命令手填 workspace 的重复提示。仍保留 execution_context 传递、显式 CR-ID、业务阶段、作者/reviewer/审批人职责、写入/检查/发布要求和共享权威合同短指针。bootstrap、独立 CLI/CI、daemon 预检例子保留明确根。同步清理错误的通用生成/自动校验委派，不以删文字制造隐含责任。

### FR-15：部署与安全回退

按顺序交付：兼容显式模式的 CLI/daemon 与两个业务操作，暂留原提示 → 验证两条入口/直接脚本/业务失败与恢复 → 同步 shared 与调用方合同、短提示、Agent instructions、imported Skills 及维护的部署副本 → 核对实际生效版本。使用原独立评审与审批，不直接修改线上配置越权实施。

回退先恢复安全显式 workspace 调用，再撤绑定；撤业务操作前停止调用并收敛在途事务，无等价入口则暂停正式落盘、保留草稿。不得恢复受控账本手写或失实能力承诺；不迁移/重写已有 CR、指纹、账本、review attempt，不批量重生成历史文档。

### FR-16：可归因测试与证据

A1～A8、B1～B20 全部保留，使用现有测试组织与节点回放，不新建框架。Windows 动态路径必须在 Windows 执行；受控操作一致性/范围拒绝/CAS/中断恢复需接口级证据；本地纠正、未声明维度、规划/竞品生成需节点日志/回放。证据须记录实际命令、结果及对应变更/生效版本，旧审计的“冲突存在”断言、静态关键词或共享实例输出不能替代完成验收。

## 4. 非功能需求

- **NFR-01 安全：** 路径比较使用真实目录语义和原 containment/健康检查，不能用字符串前缀替代；custom_env、主机遗留环境和历史评论不得取得根授权。所有受控账本、审批、评审记录仍由既有入口管理。
- **NFR-02 兼容性：** 显式 CLI/CI/bootstrap、旧允许输入规范化、审批 grant/TTY、原 schema/字段、独立 reviewer、状态机/gates/reviewLoop/checkpoint 均不降级。仅提供矩阵允许的定点业务调用关系，不宣称新增机器级隔离。
- **NFR-03 可恢复性：** 复用现有锁/journal/CAS/write-set/隔离提交；失败分类确定，恢复不得强写第三值；不承诺多文件瞬时可见或全局原子。
- **NFR-04 可维护性：** 复用已有 helper、版本化模块和测试，不新增依赖、执行器、通用服务或持久化重试账本。仓库文本用可移植路径；multica 代码注释遵循其英文规则，定制登记按实际 CUSTOM.md 结构及本 CR/TASK 追溯。
- **NFR-05 性能与可观测性：** 绑定复用已有只读预检，避免每条命令重复根探索；本地纠正有界且无轮询。记录入口/事务结果，但不泄露凭据或将提示词约定伪装成机器保证；不新增无来源的吞吐/延时 SLA。

## 5. 验收标准

下表沿用附件向量编号；每行必须有实际测试或运行回放证据，映射的 FR 全部满足后才可验收。

| 编号 | 对应需求 | 可观察验收结果 |
|---|---|---|
| AC-A1 | FR-01～03 | Pipeline 有效绑定下 Git 检查遗漏 workspace，首次使用本 CR operational 路径，无 WORKSPACE_REQUIRED、重试或恢复委派。 |
| AC-A2 | FR-02～03 | 同环境直接 node 执行 crctl 与 launcher 同结果；不能绕过绑定。 |
| AC-A3 | FR-01～02 | 普通 Issue 的唯一上下文/可信根触发预检绑定，不依赖 PipelinePrompt 非空。 |
| AC-A4 | FR-01、03、12 | 缺失/重复/冲突/非法上下文，无根/歧义/越界/坏 worktree 均停止节点准备或零业务写入失败，不猜根。 |
| AC-A5 | FR-03、12 | 同真实目录/合法别名接受；显式异根返回 WORKSPACE_CONTEXT_MISMATCH，绑定不被覆盖。 |
| AC-A6 | FR-03 | 独立 CLI/bootstrap 显式根有效；仅 task ID 不误绑定，旧 CRCTL_WORKSPACE 不作 fallback；缺根报 WORKSPACE_REQUIRED，help 保持可用。 |
| AC-A7 | FR-02 | 并发 task 隔离；custom_env 后注入；无绑定清旧值；配置不可覆盖可信绑定。 |
| AC-A8 | FR-02～03、16 | Windows 空格/中文路径、POSIX 及 Git --/--cwd 的 argv 保持完整，不重拼 shell 字符串；Windows 用例真实在 Windows 执行。 |
| AC-B1 | FR-04 | 旧可信入口遗漏根且预检零业务写入可证明时，同节点同 run 只补参调用一次；无恢复委派/版本扫描；与 A1 首次归一区分。 |
| AC-B2 | FR-04～05 | 额外 validate prd.md 的 UNKNOWN_ARTIFACT 后完成原 PRD 重读自检及后续登记/发布，不跳过必需检查。 |
| AC-B3 | FR-04、12 | 第二次失败、权限/路径/绑定冲突或写入不明停止自动纠正，走原异常或合法事务恢复。 |
| AC-B4 | FR-14～15 | 短提示仍含上下文/CR-ID/业务输入输出/职责/发布合同，显式与 bootstrap 说明未误删。 |
| AC-B5 | FR-05 | validate-doc/AGENTS/PRD/SDD 无 blanket 自动调用承诺，无额外通用校验闸门；原必需自检与评审保留。 |
| AC-B6 | FR-05 | 未声明维度 WARN 且明确未检查；必需配置无效/违反规则仍失败；不能宣称完整通过。 |
| AC-B7 | FR-05 | 合法既有评审 YAML 分支有效；prd.md/sdd.md 仍 UNKNOWN_ARTIFACT，不扩大纠正集合。 |
| AC-B8 | FR-07 | common 日期渲染匹配原 schema，覆盖北京时间跨日和宿主时区差异；竞品/CR 等业务 timestamp 保留，存量不重写。 |
| AC-B9 | FR-06、10～11 | 已确认规划/竞品使用各自字段/id/章节，不调用未支持通用类型；未确认零业务写入。 |
| AC-B10 | FR-08 | 有获准入口只维护指定 yml/yaml 索引；无合同不创建，无双索引、不全仓改名。 |
| AC-B11 | FR-13 | 七个指定 Skill 的十二处基线漏项及范围内全部实际漏项补齐 CR-ID；合法真实调用到业务 gate，不在缺位置参数处 BAD_ARGS。 |
| AC-B12 | FR-13 | 0.16.0、v/V 输入规范化至无前缀值；unassigned/禁止值/prerelease 边界维持，文字与实现一致。 |
| AC-B13 | FR-12～13 | grant/TTY、写入前提与现实现一致；除限定业务调用登记外，不放宽授权/审批/业务范围。 |
| AC-B14 | FR-15～16 | 仓库、维护部署副本、实际 imported Skills 与 Agent instructions 的生效版本一致，覆盖规划/竞品调用方；只改仓库不算完成。 |
| AC-B15 | FR-09～12 | 确认后操作成功及同意图重放：规划两文件、竞品三文件一致，原 body/确认/冲突规则保留，索引与 updates 不重复，状态/审批不变。 |
| AC-B16 | FR-09、12 | 越界、任意文件清单或超出对应业务范围的输入，在业务文件/索引写入前拒绝，不提供任意写接口。 |
| AC-B17 | FR-12 | 候选生成后并发变化/恢复遇第三值返回既有 CAS/冲突结果，不覆盖、不由 Skill 补账。 |
| AC-B18 | FR-12 | 规划两文件/竞品三文件写入及提交中断按原事务恢复，最终一致才报告完成；不宣称瞬时可见/全局原子。 |
| AC-B19 | FR-06、08 | engineering-docs 必需索引但入口不可用时中止完整执行，仅保留模板参考/草稿，不漏索引报完成。 |
| AC-B20 | FR-13 | 两角色的矩阵/Agent/Skill/必要索引一致，限定各自操作；不宣称矩阵实现子命令级机器授权。 |

### 5.1 证据组织与完成条件

使用 tools 既有 `crctl.test.mjs`、`caller-contract.test.mjs`、`contract-scan.test.mjs`、`pipeline-structure.test.mjs`、`durable-tx.test.mjs` 及矩阵/Agent/提示检查；multica 既有 daemon binding/执行上下文测试与 delegation-contract 测试。具体新增测试位置及可执行计划由开发期 SDD/PLAN/TASK 确认。

交付必须同时满足：A/B 全量证据、Pipeline 与普通 Issue 覆盖、两个业务操作接口级证据、合同一致、实际生效版本一致、独立评审与人类审批通过。代码、文档和配置只完成之一不算整个 CR 完成。回退验证按 FR-15；需求期仅交付本 PRD，不声称上述实施验收已经通过。

## 6. 成功指标

- A1～A8、B1～B20 的适用验收证据覆盖率与通过率均为 100%；错误分支无未决的不确定返回或业务副作用描述。
- 有效绑定的三类入口（Pipeline、普通 Issue、直接脚本）首次缺 workspace 调用，因该遗漏产生的 WORKSPACE_REQUIRED/恢复委派为 0。
- 未确认/越界/绑定冲突向量业务写入为 0；同意图重放的新增重复文档/索引/updates 为 0；中断恢复向量最终关联文件不一致为 0。
- 源码合同、部署副本、实际 imported Skills/Agent instructions 的本次范围漂移项为 0；保留原权限/审批/路径/事务边界，无新增通用基础设施。
- 一次本地纠正以每条适用节点回放中的次数不超过 1 衡量，不将其报告为跨 run 机器硬保证。

## 7. 范围排除

- 不另拆 CR、不关联或改变其他 CR 的已审批范围；不宣称解决来源 Issue 的所有独立阻断。
- 不纳入 source 默认值/manual 修复、source required 的前端语义或 UTC 显示问题。
- 不新增 PRD/SDD validator、状态机/gates、Pipeline 种类、Skill 种类、执行器、重试服务、持久化 attempt 账本、MCP 工具、数据库/API 字段。
- 不改审批权限、验签、controlled-shell 白名单；不授予规划/竞品 Agent CR 生命周期写入职责。
- 不新增通用文档/索引写入器、任意文件接口、事务/权限框架、auto-invoked-by、反向调用清单、能力注册服务或矩阵通用第五类扫描。
- 不统一所有时间格式、不改变既有 schema 类型、不批量重写存量文档或迁移已有 CR/账本/指纹/review attempt。
- 不全仓改索引后缀，不为本需求删除或重构 legacy CLI/MCP，不补齐全部工程文档完整执行能力。
- 不把提示词约定宣称为机器硬保证，不承诺多文件瞬时可见、跨仓或跨远端全局原子性。
- 需求期不执行 A/B 代码、部署或开发任务登记，不替人审批，不由作者执行独立评审；状态及下一步只消费 crctl 返回。
