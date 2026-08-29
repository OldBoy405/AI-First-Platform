---
id: CR-2026-054-prd
type: PRD
cr-ref: CR-2026-054
title: "CR 归档安全、Agent 执行边界与任务终态闭环 — 归档候选严格写前校验、共享服务边界与存活 daemon 终态补投"
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-29T12:14:42+08:00
updated: 2026-08-29T12:14:42+08:00
---

# 1. 概述

## 1.1 问题陈述

本 CR 覆盖三个已经确认、但必须共同验收的闭环缺口：

1. **归档候选可信性不足**：`crctl archive` 当前能够完成文本和账本变更，但普通 YAML 子集解析可能对重复键后值覆盖，或未完整消费异常嵌套行。归档候选在进入新的 write-set 前也缺少统一的结构和后置条件校验，因而不能仅凭生成成功证明归档结果完整、唯一且一致。
2. **Agent 共享服务职责边界不够明确**：当验证环境与当前变更主体不一致时，Agent 可能尝试启动、停止、替换或重配置共享服务。这样会扩大任务权限、影响其他任务，并使共享实例产生的结果无法可靠归因于当前变更。
3. **存活 daemon 的终态回调可能悬空**：multica daemon 的 `CompleteTask` 和 `FailTask` 已有有限退避重试，但瞬时错误耗尽重试后只记录日志；daemon 继续存活时，服务端任务可能长期保持 `running`。现有 orphan recovery 不能覆盖这一场景。

三个问题分别属于归档安全、执行边界和任务终态可靠性，但共享同一 CR 的共同验收边界。任一业务域未完成，CR 不得进入最终代码审批、合并或归档。

## 1.2 目标

- 在任何新的 archive write-set、stage、commit 或 push 之前，拒绝无法严格解释或不满足归档约束的四个候选文件。
- 让首次归档构建与远端 trunk 变化后的 rebuild 使用相同候选校验规则。
- 让 Agent、Pipeline、Skill、crctl 和 multica daemon 的职责边界可被文档、测试和评审证据核查。
- 当验证前提超出当前任务权限时，以稳定的技术失败中止，而不是管理共享服务或伪造代码 blocker。
- 让 daemon 在进程存活期间对耗尽有限重试的瞬时终态回调进行低频、幂等补投，并依赖既有服务端幂等接口最终收敛。

## 1.3 成功结果

归档链路不会把无效候选带入 Git；Agent 不会把共享服务生命周期纳入普通实现或验证动作；daemon 存活时，瞬时失败的终态回调至少获得一次后续重放机会。整个方案不新增第二套状态机、账本、测试证据协议或通用调度系统。

# 2. 用户故事

- **US-1 归档操作者**：作为执行 `crctl archive` 的维护者，我希望候选账本在受控写入前被严格检查，以便错误不会被提交、推送或固化到历史。
- **US-2 归档操作者**：作为遇到解析或归档约束错误的维护者，我希望看到有限且带行号、文件名、类别和相关键/CR ID 的错误，以便修复权威源后安全重跑，而不是依赖猜测或自动修复。
- **US-3 版本维护者**：作为在远端 trunk 发生变化后重建归档候选的维护者，我希望 rebuild 与首次构建遵守同一规则，以便远端变化不会绕过归档安全校验。
- **US-4 开发 Agent**：作为执行实现任务的 Agent，我希望知道哪些共享服务动作超出职责边界，以便在验证环境不可用时中止并报告外部动作，而不影响其他任务。
- **US-5 开发负责人**：作为开发负责人，我希望环境不匹配与可归因代码缺陷有不同的失败语义，以便正确安排平台动作或代码修复，不让环境标签掩盖真实缺陷。
- **US-6 代码评审者**：作为代码评审者，我希望只使用与当前变更主体可信对应的 diff 和规范测试证据，以便不把共享实例的不可归因输出当作通过或阻塞依据。
- **US-7 daemon 维护者**：作为 daemon 维护者，我希望终态回调在瞬时故障后能够自动低频重放，以便服务端任务不会仅因 daemon 仍存活而永久停留在 `running`。
- **US-8 服务端任务系统**：作为接收终态回调的服务端，我希望继续使用既有幂等终态接口，不引入新的本地状态，以便重复投递最终收敛且现有 orphan recovery 仍然有效。
- **US-9 CR 审核者**：作为 CR 审核者，我希望三个业务域均有独立的 FR、测试证据和验收结果，以便确认该问题只能以一个完整 CR 关闭。

# 3. 功能需求（FR）

## 3.1 归档候选严格校验

| 编号 | 需求 | 优先级 | 可验证结果 |
|---|---|---:|---|
| FR-1 | 系统必须在现有 `parseYaml()` 增加可选严格模式；严格模式只覆盖当前受支持 YAML 子集，不扩展 YAML 标准能力。默认非严格模式行为必须保持兼容。 | P0 | 严格模式可由 archive 调用；既有非严格调用方回归测试通过。 |
| FR-2 | 严格模式必须在解析前将 `CRLF` 规范化为 `LF`，拒绝 block map/flow map 重复键，并将带引号和不带引号但文本相同的键视为重复；错误必须包含首次与重复出现位置。 | P0 | 重复键、等价引号键和 Windows 行尾样例均得到确定性结果并携带行号。 |
| FR-3 | 严格模式必须完整消费每层输入，并拒绝 tab 缩进、非法缩进、非法容器切换、无法解释的行和无实际子节点的裸 `-`；合法的 `key:` 空值必须继续支持。 | P0 | 每类非法输入均失败；合法空值账本和现有合法样例继续通过。 |
| FR-4 | archive 构建必须在计算新 write-set 哈希之前，对 `_backlog.yml`、`_history.yml`、`_index.yml` 和目标 `cr.md` 四个候选执行严格解析及根结构校验：分别要求 `change-requests` 为数组或空值、`history` 为数组、`change-requests` 为数组、frontmatter 为对象。 | P0 | 无效候选不会进入新 write-set、stage、commit 或 push。 |
| FR-5 | archive 必须在首次构建和远端 trunk 变化后的 rebuild 中复用同一候选校验；校验必须验证目标 CR 在 backlog 中为 0 次、在 history/index 中各恰好 1 次，index 状态及 `cr.md` frontmatter `status` 均为目标终态，history ID 全局唯一且 `final-status` 仅允许 `archived`、`rejected`、`withdrawn`。 | P0 | 首次构建和 rebuild 的同类无效样例均失败，合法三种终态均通过。 |
| FR-6 | 解析、根结构或归档后置条件失败必须统一返回 `ARCHIVE_YAML_INVALID`，并使用有限稳定类别：`duplicate-key`、`unconsumed-line`、`invalid-indentation`、`invalid-shape`、`archive-invariant`。详情至少包含逻辑文件名、候选行号、类别及相关键或 CR ID，并提示修复权威源后重跑。 | P0 | 错误码和类别稳定；不输出完整账本，不提供自动修复命令。 |
| FR-7 | 现有候选生成错误 `ENTRY_NOT_IN_BACKLOG`、`ENTRY_ALREADY_IN_HISTORY`、`INDEX_ENTRY_NOT_FOUND` 必须保持原语义；archive 校验失败不得新增 archive commit、stage 或 push。既有 journal recovery 行为不因本 CR 改变。 | P0 | 生成阶段错误码回归通过；失败副作用边界测试通过。 |

## 3.2 Agent 执行边界与验证失败语义

| 编号 | 需求 | 优先级 | 可验证结果 |
|---|---|---:|---|
| FR-8 | `dev-agent.md` 必须明确：Agent 只负责路由、职责判断和委派；不得启动、停止、重启、杀死、替换或重配置共享服务；技术中止后报告所需平台/人工动作；委派下一角色后结束当前任务，不等待或轮询下游任务。 | P0 | Agent 文档审查确认职责边界，无可执行规则重复扩散到其他事实源。 |
| FR-9 | `implement-code` 必须定义一次有界验证检查，并规定任务范围内修正后最多重跑一次；命令遵守既有测试计划 timeout，使用既有测试入口，不创建脱离验证步骤继续存活的后台进程。只有任务明确要求、由当前步骤创建并清理的临时隔离实例不视为共享服务。 | P0 | Skill 文档及其评审用例能区分允许的临时隔离实例和禁止的共享服务动作。 |
| FR-10 | 当验证前提无法建立且修复需要管理共享服务或修改任务范围外环境时，`implement-code` 必须返回 `ENVIRONMENT_MISMATCH` 并由既有 Pipeline `onFail=abort` 中止；该标签不是 CR 状态、门禁、账本字段或代码 blocker。验证环境已经受控且出现可归因于当前变更的测试失败时，必须按代码失败处理。 | P0 | 环境不匹配触发技术中止；代码失败不会被环境标签覆盖，也不生成代码 blocker。 |
| FR-11 | `review-code` 必须读取实际 diff 和规范测试证据；未与当前变更主体建立可信对应关系的共享实例输出不得作为 pass 或 block 依据；明确的 `ENVIRONMENT_MISMATCH` 必须技术中止且不得生成代码 blocker。评审继续复用现有 `release-subjects` 绑定，不增加 HEAD 级密码学绑定声明。 | P0 | 评审场景测试能验证证据采信边界及技术中止语义。 |
| FR-12 | README 只增加共享服务边界的人读原则并指向权威 Agent/Skill；Pipeline 的 `onFail=abort`、reviewLoop、`write-test-report` 的 timeout/shell/test 证据路径、权限矩阵和 `crctl test` schema 保持不变。 | P1 | 文档差异和配置回归确认未建立第二套可执行规则或证据协议。 |

## 3.3 daemon 终态回调补投

| 编号 | 需求 | 优先级 | 可验证结果 |
|---|---|---:|---|
| FR-13 | daemon 对 `CompleteTask` 和 `FailTask` 继续复用现有有限重试；仅当有限重试耗尽且最终错误仍为瞬时错误时，才保存终态回调所需的不可变值进入待重试集合。初次永久错误不得入队。 | P0 | complete/fail 的瞬时耗尽样例入队；永久错误不入队。 |
| FR-14 | 待重试集合必须以 task ID 去重，每个任务最多保存一个结果；相同 payload 重复入队静默去重，冲突 payload 采用 first-wins 并记录结构化错误。首次成功入队时懒启动与 daemon 根 context 绑定的单一重放循环。 | P0 | 去重、冲突保留和懒启动均有单元测试；无重复 worker。 |
| FR-15 | 重放必须以固定 30 秒周期、单 worker 执行；每轮读取当前快照，成功回调后删除条目；遇到瞬时错误保留条目，并在本轮第一个瞬时错误后停止继续请求；永久错误删除条目并记录错误。 | P0 | 通过单轮 helper 测试上述三种路径，不等待真实 ticker。 |
| FR-16 | 重放必须使用原始不可变终态 payload，并依赖现有服务端幂等接口收敛；等待期间服务端任务保持 `running`，成功回调后由现有服务端逻辑进入真实终态。不得新增 `pending-terminal` 状态或本地持久化账本。 | P0 | payload 保持一致；不新增状态/账本；成功后服务端终态行为回归通过。 |
| FR-17 | daemon 关闭时不执行额外 drain，重放循环随根 context 停止；不承诺跨重启保存待重试结果。日志只记录 task ID、终态种类和错误，不记录 output、error message、session 内容或完整 payload。 | P0 | 关闭和重启边界测试通过；日志脱敏测试通过。 |
| FR-18 | multica 定制必须新增独立终态重试文件及测试文件，`daemon.go` 的上游改动限于零值可用队列字段和统一 `reportTerminalTask` 的两个小型 `AIFIRST` 挂钩，并在 `CUSTOM.md` 登记文件、挂钩、CR/TASK 来源及验证命令；不得逐个改造 complete/fail 调用点。 | P1 | diff 审查确认修改面和定制台账完整。 |

## 3.4 CR 完整闭环

| 编号 | 需求 | 优先级 | 可验证结果 |
|---|---|---:|---|
| FR-19 | 三个业务域必须在同一 CR 中分别完成实现、测试和评审；任一域未完成、无法验证或未满足本 PRD 验收标准时，不得进入最终代码审批、合并和归档。 | P0 | CR 评审清单逐域有证据；缺一域时门禁无法视为完成。 |
| FR-20 | 本 CR 的实现必须复用现有 YAML 解析器、archive 事务构建点、Pipeline 失败中止、规范测试证据、终态接口重试和 orphan recovery；不得建立第二套状态、账本、调度或服务管理能力。 | P1 | SDD/TASK/代码评审记录确认无越界新增子系统。 |

# 4. 非功能需求（NFR）

- **NFR-1 正确性与原子性**：候选校验发生在新 write-set 哈希和受控写入之前；无效候选不得进入 stage、commit 或 push。既有 recovery 的副作用边界保持不变。
- **NFR-2 兼容性**：严格 YAML 解析为显式可选能力；非严格 `parseYaml()` 调用方继续保持原行为。合法 `key:` 空值和 `archived`/`rejected`/`withdrawn` 三种归档终态必须兼容。
- **NFR-3 安全与隔离**：Agent 不得改变任务范围外共享服务生命周期；评审不得采信无法归因的共享实例输出；错误和日志不得泄露完整账本、终态 payload 或会话内容。
- **NFR-4 可恢复性**：daemon 存活期间，耗尽有限重试的瞬时终态回调至少获得一次后续重放机会；补投依赖服务端幂等，不承诺 exactly-once 或跨 daemon 重启持久化。
- **NFR-5 调度约束**：补投使用单 worker、固定 30 秒周期；不引入新的队列容量策略、背压、claim gate、semaphore 联动或指数退避框架。
- **NFR-6 可观测性**：错误类别、文件名、行号、相关键/CR ID、task ID 和终态种类可用于定位；不得为本 CR 增加新的 metrics、健康接口或通用诊断系统。
- **NFR-7 变更可控性**：multica 上游 `daemon.go` 只保留两个小型挂钩；新增定制必须登记到 `CUSTOM.md`，tools 文档修改不得复制 Pipeline、测试证据或状态机的执行规则。

# 5. 验收标准

每条验收标准均需关联对应 FR，并在实现阶段由规范测试、文档审查或 diff 审查提供证据。

| 编号 | 对应 FR | 验收条件 |
|---|---|---|
| AC-1 | FR-1~FR-3 | block/flow 重复键、引号等价键、tab/错误缩进、非法容器切换、未消费行、孤立 `-` 均被严格模式拒绝；CRLF 规范化和合法空值继续通过；默认模式回归通过。 |
| AC-2 | FR-4~FR-7 | 合法 archive 以及三种目标终态通过；四候选任一根结构或归档不变量失败时返回 `ARCHIVE_YAML_INVALID` 与稳定类别；首次构建和远端 rebuild 均在 write-set 前失败，既有生成错误码保持不变。 |
| AC-3 | FR-8~FR-12 | Agent/Skill/README 的职责边界、委派结束、一次有界验证、最多一次重跑、timeout 和证据边界可核查；Pipeline、权限矩阵、测试报告和 `crctl test` schema 无非需求变更。 |
| AC-4 | FR-10~FR-11 | 无法建立且超出权限的验证前提返回 `ENVIRONMENT_MISMATCH`，Pipeline 中止且不写代码 blocker；受控环境中的可归因测试失败按代码失败处理；共享实例输出不影响 pass/block。 |
| AC-5 | FR-13~FR-15 | complete/fail 瞬时错误耗尽有限重试后入队；永久错误不入队；相同 payload 去重、冲突 first-wins；成功删除、瞬时错误保留并结束本轮、永久错误删除。 |
| AC-6 | FR-16~FR-18 | 重放使用原始 payload，服务端现有幂等终态接口收敛；不新增状态或持久化账本；关闭时停止；日志不泄露 payload；multica diff 和 `CUSTOM.md` 满足最小定制范围。 |
| AC-7 | FR-19~FR-20 | 三个业务域均完成测试和评审并通过同一 CR 的代码审批、合并及归档门禁；未完成任一域时不能宣称 CR 完成，且未出现第二套状态、账本、调度或服务管理系统。 |

# 6. 成功指标

上线后通过既有测试证据、CR 评审记录和运行日志观察以下指标：

1. **归档安全**：archive 候选校验相关测试覆盖 FR-1~FR-7；无效候选在 write-set 前失败，且没有由该失败产生的 archive commit、push 或无效账本写入。
2. **执行边界**：FR-8~FR-12 的文档与行为审查通过；发生环境前提不足时可观察到 `ENVIRONMENT_MISMATCH` 技术中止，且不产生代码 blocker 或共享服务变更。
3. **终态闭环**：FR-13~FR-18 的 complete/fail、去重、瞬时/永久错误、关闭和日志测试全部通过；daemon 存活期间，耗尽有限重试的瞬时终态回调至少进入一次重放路径。
4. **变更收敛**：三个业务域在同一 CR 的 review、approval、merge、writeback 和 archive 阶段均有可追溯证据；multica 定制项全部登记，未引入排除范围内的新状态或平台子系统。

这些指标用于验证本 CR 的交付闭环，不承诺 exactly-once、跨 daemon 重启可靠投递或对未受控共享环境结果的归因能力。

# 7. 范围排除

本 CR 明确不包含：

- 完整 YAML 标准解析器、第三方 YAML 依赖、通用 schema 注册中心或全局强制严格解析。
- 新增 `crctl validate-archive`、账本修复命令、状态、门禁或证据 schema。
- 在 Agent、Pipeline、Skill 或脚本层复制归档校验；修改 Pipeline、`write-test-report`、`agent-skill-matrix.yml` 的既有能力；新增测试证据 HEAD digest 或密码学绑定协议。
- Agent、Skill 或平台新增共享服务管理能力、基础设施 Agent、部署 Pipeline、通用服务管理 Skill 或 controlled-shell 扩权。
- multica 的数据库、迁移、API、handler、client、`pollLoop`、任务槽改造，或除本 PRD 约定挂钩外的上游文件修改。
- 持久化终态 outbox、消息队列、队列容量管理、背压、并发调度、claim gate、semaphore 联动、指数退避框架、feature flag、配置项、健康接口和 metrics。
- 新增 `pending-terminal` 状态；exactly-once 保证；跨 daemon 重启保存待重试结果；永久错误无限重试。
- README 中复制可执行细节，或与本 CR 无关的重构。

本 PRD 是需求基线；具体接口、文件组织、并发实现和测试编排由后续 SDD 与 TASK 定义，但不得突破上述范围和共同验收边界。
