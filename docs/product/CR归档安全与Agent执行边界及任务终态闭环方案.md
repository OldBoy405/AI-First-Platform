# CR 归档安全、Agent 执行边界与任务终态闭环方案

## 1. 文档定位

本文定义一个 CR 内的统一改造，包含三个必须共同验收的业务域：

1. `crctl archive` 在受控写入前拒绝不可解释或不满足归档约束的 YAML 候选；
2. Agent 在实现和评审期间遵守共享服务边界，无法建立受控验证环境时以技术失败中止；
3. multica daemon 在终态回调耗尽现有有限重试后，于进程存活期间继续补投，避免任务无期限停留在 `running`。

三个业务域可以拆分为不同 TASK 并行实施，但不得拆成多个 CR。任一业务域未完成，整个 CR 都不能进入最终代码审批、合并和归档。

本文是需求与方案来源，不替代状态机、门禁、Skill 或运行时代码。状态与审批仍以 `crctl` 权威配置为准，执行细节仍以对应代码和测试为准。

## 2. 已确认的问题

### 2.1 归档候选可能在解析成功后丢失信息

现有 `../tools/skills/shared/crctl/scripts/lib/yaml-subset.mjs` 支持项目所需的 YAML 子集，但普通模式存在两类宽松行为：

- 同一映射内的重复键会被后值静默覆盖；
- 序列内联映射的嵌套内容可能未被完整消费，错误缩进或更深层异常行可能被忽略。

现有归档流程会生成 `_backlog.yml`、`_history.yml`、`_index.yml` 和目标 CR 的 `cr.md` 候选内容，但在新 write-set 建立前没有统一验证四个候选的结构与归档后置条件。仅证明文本替换成功，不能证明候选账本具备唯一、完整且一致的归档结果。

### 2.2 Agent 可能越界管理共享服务

当验证环境与当前变更主体不一致时，Agent 可能把启动、停止、替换或重配置共享服务当成实现或测试步骤。这会扩大任务权限、影响其他任务，并使共享实例上的结果无法可靠归因到当前代码变更。

现有 Tools 已具备 Pipeline 失败中止、命令超时、`shell: false` 执行和 `crctl test` 规范证据能力。缺口主要是 Agent 与 Skill 的职责边界及环境不匹配的失败语义，不需要新增 Pipeline 节点或测试证据系统。

### 2.3 终态回调耗尽重试后可能长期悬空

multica daemon 的 `CompleteTask` 和 `FailTask` 已有有限退避重试，服务端终态接口也具备幂等语义。当前缺口是：瞬时错误耗尽现有重试后，daemon 只记录日志；只要 daemon 继续存活，服务端任务就可能持续保持 `running`。现有 orphan recovery 只在 daemon 重启等运行时失联场景收敛，不能解决存活 daemon 上的悬空任务。

## 3. 目标与约束

### 3.1 目标

- 无效归档候选在进入新 write-set、stage、commit 或 push 前失败关闭；
- 归档首次构建与远端变化后的 rebuild 使用同一套候选校验；
- Agent 不管理任务范围外的共享服务；
- 环境不匹配与代码缺陷具有稳定、不可互相掩盖的分类边界；
- daemon 存活期间，终态回调的瞬时失败能够低频、幂等补投；
- 所有改动复用现有模块和接口，不建立第二套状态、账本或调度系统。

### 3.2 可靠性承诺

终态补投承诺限定为：**daemon 进程存活期间至少一次重放，依赖服务端幂等接口收敛**。

本方案不承诺 exactly-once，也不承诺跨 daemon 重启保存待重试结果。daemon 重启时，内存待重试集合可以丢失，遗留任务由现有 orphan recovery 收敛。永久错误不会无限重试。

## 4. 模块职责边界

| 模块 | 应该拥有 | 本 CR 的职责 | 不应该拥有 |
|---|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 识别共享服务边界，委派适当 Skill，技术中止后报告并结束 | 状态机、Git 算法、受控文件写入、共享服务生命周期 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复用现有 `onFail=abort` 和 reviewLoop | 复制 Skill 算法、手写账本、服务管理 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 定义有界验证、环境不匹配及评审证据使用规则 | 原子账本逻辑、重复实现 crctl、平台终态队列 |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 严格解析归档候选并校验归档后置条件 | 业务设计判断、LLM 评审结论、共享服务管理 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 继续提供既有确定性入口 | 状态推进、人工审批、常驻服务管理 |
| README | 人读流程总览 | 简述共享服务边界并指向权威 Skill | 复制可执行规则形成第二事实源 |
| multica daemon | 任务执行生命周期、终态投递与恢复 | 保存并补投瞬时失败的终态回调 | CR 状态判断、评审结论、持久化业务队列 |

## 5. 方案设计

### 5.1 归档候选严格写前校验

#### 5.1.1 严格模式是“受支持 YAML 子集的严格解析”

在现有 `parseYaml()` 上增加可选严格模式：

```js
parseYaml(text, { strict: true })
```

默认模式保持不变，避免一次性改变其他 crctl 调用方。严格模式不扩展 YAML 标准能力，只保证当前受支持子集不会静默覆盖或丢弃输入。

严格模式遵循以下规则：

- 解析前把 `\r\n` 规范化为 `\n`；
- block map 与 flow map 的重复键立即失败；
- 键名按去除引号后的文本比较，因此 `id`、`"id"`、`'id'` 是同一个键，大小写仍敏感；
- 错误报告同时保留首次出现行和重复出现行；
- 根节点从第 0 列开始，缩进只能使用空格；
- 不强制固定两个空格，但子节点必须比父节点更深；
- 每一层解析都必须完整消费属于该层的输入；
- 裸 `-` 必须存在实际子节点，孤立序列项立即失败；
- `key:` 继续表示空值，以兼容空 backlog 的 `change-requests:`；
- 非法容器切换、非法缩进和无法解释的行立即失败并携带候选文件行号。

解析结果只要求四类根结构：

| 候选文件 | 根结构要求 |
|---|---|
| `_backlog.yml` | `change-requests` 为数组或空值 |
| `_history.yml` | `history` 为数组 |
| `_index.yml` | `change-requests` 为数组 |
| `cr.md` frontmatter | 对象 |

不建立通用 schema 注册中心，也不校验与归档无关的可选业务字段。

#### 5.1.2 在统一候选构建点校验四个文件

在 `workspace-transactions.mjs` 的 archive `buildEntries()` 内，生成 `newBacklog`、`newHistory`、`newIndex` 和 `nextCrMd` 后、计算新 write-set 哈希前，调用私有 `validateArchiveCandidates(...)`。

该位置同时覆盖：

- 首次构建归档候选；
- 远端 trunk 变化后基于新权威内容执行的 rebuild。

校验函数保持文件私有，不为了测试导出新的内部接口。调用顺序为：

```text
恢复既有未完成事务
  → 生成四个新候选
  → 严格解析与归档后置条件校验
  → 计算候选哈希并建立新 write-set
  → apply / stage / commit / lease push
```

#### 5.1.3 归档后置条件

严格解析通过后，校验以下最小业务不变量：

- backlog 中目标 CR 出现 0 次；
- history 中目标 CR 恰好出现 1 次；
- index 中目标 CR 恰好出现 1 次，且状态为本次目标终态；
- `cr.md` frontmatter 中 `status` 恰好出现 1 次，且值为本次目标终态；
- history 全局不存在重复 CR ID；
- history 每一项的 `final-status` 都属于 `archived`、`rejected`、`withdrawn`。

终态集合在 `workspace-transactions.mjs` 内定义为 archive 专用常量，并由现有 archive 检查和新校验共同复用；不从完整状态机动态派生，也不复制状态推进规则。

校验范围保持克制：history 做全局 ID 唯一性与合法终态检查；backlog、index 和 `cr.md` 只检查目标 CR 相关后置条件。

#### 5.1.4 失败语义与副作用边界

现有生成阶段错误保持原错误码，包括：

- `ENTRY_NOT_IN_BACKLOG`；
- `ENTRY_ALREADY_IN_HISTORY`；
- `INDEX_ENTRY_NOT_FOUND`。

严格解析、根结构或归档后置条件失败统一包装为：

```text
ARCHIVE_YAML_INVALID
```

内部错误只需普通 `Error` 加结构化字段，不新增错误类。稳定类别限定为：

- `duplicate-key`；
- `unconsumed-line`；
- `invalid-indentation`；
- `invalid-shape`；
- `archive-invariant`。

错误详情包含逻辑文件名、候选行号、类别、相关键或 CR ID，并提示先修复权威源账本再重跑 archive。错误不输出整份账本，也不提供新的自动修复命令。

失败保证限定为：无效的新候选不会进入新的 write-set、stage、commit 或 push。archive journal 可以在候选校验前存在；命令开始时对旧事务执行的既有 recovery 不属于“零写入”承诺，不为此重构事务顺序。

### 5.2 Agent 执行边界与验证失败语义

#### 5.2.1 Agent 与 Skill 分工

`dev-agent.md` 只声明职责边界：

- 选择并委派负责实现或评审的 Skill；
- 不启动、停止、重启、杀死、替换或重配置共享服务；
- 技术中止后报告需要的平台或人工动作；
- 委派下一角色后结束当前任务，不等待或轮询下游任务。

详细执行规则只写入 `implement-code/SKILL.md`：

- 对验证环境执行一次有界检查；
- 完成任务范围内的修正后最多重跑一次；
- 每条命令遵守现有测试计划 timeout；
- 使用既有测试入口，不创建脱离验证步骤继续存活的后台进程；
- 任务明确要求、由当前步骤创建并清理的临时隔离实例不属于共享服务；
- 修复需要管理共享服务或修改任务范围外环境时，返回 `ENVIRONMENT_MISMATCH`。

`ENVIRONMENT_MISMATCH` 是 Skill 的稳定技术失败标签，由现有 Pipeline `onFail=abort` 处理。它不是 crctl 状态、门禁、账本字段或代码 blocker。只要受控环境已经建立并出现可归因到当前变更的测试失败，就必须按代码失败处理，不能用环境不匹配覆盖。

#### 5.2.2 评审证据边界

`review-code/SKILL.md` 继续要求读取实际 diff 与规范测试证据，并增加两条边界：

- 未与当前变更主体建立可信对应关系的共享实例输出，不能作为 pass 或 block 的依据；
- 明确的 `ENVIRONMENT_MISMATCH` 触发技术中止，不生成代码 blocker。

复用现有 `release-subjects` 绑定评审和审批主体。本 CR 不改变 `crctl test` schema，也不宣称测试证据与具体 HEAD 具备密码学绑定。

`write-test-report/SKILL.md` 已具备测试计划 timeout、`shell: false` 执行和 `crctl test` 规范证据路径，本 CR 不修改。现有 `code-implementation.pipeline.json` 已具备 `onFail=abort`、checkpoint 和 reviewLoop，本 CR 不修改。

README 只增加一段人读原则并指向上述 Agent/Skill，不复制详细判定和步骤。

### 5.3 multica 任务终态补投

#### 5.3.1 最小上游侵入

终态回调缺口位于 multica daemon，无法通过 Tools 或 crctl 修复。实现采用 fork 加法定制，尽量不修改上游文件：

- 新增 `server/internal/daemon/terminal_report_retry.go`；
- 新增 `server/internal/daemon/terminal_report_retry_test.go`；
- `server/internal/daemon/daemon.go` 只增加一个零值可用的队列字段，并在统一出口 `reportTerminalTask` 增加一个 `AIFIRST` 瞬时失败入队挂钩；
- 在 `CUSTOM.md` 登记新增文件、挂钩、CR/TASK 来源和验证命令。

不逐个修改 complete/fail 调用点。统一出口是所有终态回调的唯一接缝，可以覆盖现有各类任务退出路径，同时把上游冲突面控制在两个小挂钩内。

#### 5.3.2 内存待重试集合

队列只保存终态回调所需的不可变值，不保存可变任务对象：

- 以 task ID 为键，每个任务最多一个待重试结果；
- 相同 payload 重复入队时静默去重；
- 冲突 payload 采用 first-wins，保留首次结果并记录结构化错误；
- 只在现有有限重试耗尽且最终错误仍为瞬时错误时入队；
- 初次永久错误继续走现有处理，不进入队列。

首次成功入队时通过 `sync.Once` 懒启动私有重放循环，并绑定 daemon 根 context，从而不修改 `Run`、`pollLoop` 或任务领取逻辑。

重放循环使用固定 30 秒周期和单 worker：

- 每轮读取当前待重试快照；
- 成功回调后删除对应条目；
- 瞬时错误保留条目，并在本轮遇到第一个瞬时错误后停止继续请求；
- 永久错误删除条目并记录错误，不在队列中复制 complete→fail 状态分支；
- daemon 关闭时不执行额外 drain，循环随根 context 停止。

等待重放期间，服务端任务继续保持现有 `running` 状态；只有原终态接口成功后才进入真实终态。不新增 `pending-terminal` 状态或本地账本。

#### 5.3.3 保持克制的资源策略

本 CR 不增加队列容量上限、claim gate、semaphore 联动或通用背压。它们需要侵入 `pollLoop` 和任务槽生命周期，而当前问题只要求修复存活 daemon 无后续补投的缺口。

队列按 task ID 去重。若未来实测出现终态端点局部故障、任务领取仍正常并导致内存持续增长，再依据运行数据设计容量策略；本 CR 不为推测场景预建调度框架。

日志只记录 task ID、终态种类和错误，不记录 output、error message、session 内容或完整 payload。

## 6. 关键数据流

### 6.1 归档

```text
archive 输入与既有 recovery
  → 构建 backlog/history/index/cr.md 候选
  → 严格解析四个候选
  → 校验目标 CR 后置条件与 history 全局不变量
  → 建立新 write-set
  → 原有原子写入与 Git 提交流程
```

### 6.2 环境不匹配

```text
implement-code 执行一次受控环境检查
  → 无法建立验证前提，且修复超出任务权限
  → ENVIRONMENT_MISMATCH
  → Pipeline onFail=abort
  → Agent 报告外部动作并结束
  → 不管理共享服务，不写代码 blocker
```

### 6.3 终态回调补投

```text
本地任务结束
  → 复用现有 CompleteTask / FailTask 有限重试
  → 瞬时错误仍未恢复
  → 按 task ID 进入内存待重试集合
  → 固定低频幂等补投
  → 成功后删除条目并由服务端进入真实终态
```

## 7. 修改范围

### 7.1 AI First Platform 文档

```text
docs/product/CR归档安全与Agent执行边界及任务终态闭环方案.md
```

本文由原 `crctl-archive严格YAML写前校验方案.md` 重命名并整体重写。后续 CR 的 PRD、SDD 和 TASK 由既有 Pipeline 生成，不在本文复制其可执行内容。

### 7.2 tools

生产代码与测试：

```text
skills/shared/crctl/scripts/lib/yaml-subset.mjs
skills/shared/crctl/scripts/lib/workspace-transactions.mjs
skills/shared/crctl/scripts/test/yaml-subset.test.mjs          # 新增
skills/shared/crctl/scripts/test/archive-tx.test.mjs
skills/cr/cr-archive/SKILL.md                                  # 只补失败分类
```

Agent 与流程文档：

```text
agents/dev-agent.md
skills/develop/implement-code/SKILL.md
skills/develop/review-code/SKILL.md
README.md
```

### 7.3 multica

```text
server/internal/daemon/terminal_report_retry.go                 # 新增定制
server/internal/daemon/terminal_report_retry_test.go            # 新增定制测试
server/internal/daemon/daemon.go                                # 两个小型 AIFIRST 挂钩
CUSTOM.md                                                       # 强制登记
```

## 8. 验证方案

### 8.1 YAML 子集解析器

- block map 重复键被拒绝；
- flow map 重复键被拒绝；
- 带引号与不带引号的等价键被识别为重复；
- tab 缩进、非法容器切换和错误嵌套被拒绝；
- 每层未消费行被拒绝；
- 孤立序列项被拒绝；
- `key:` 空值与现有合法账本继续通过；
- 默认非严格模式行为保持不变。

解析器测试使用内联代表性 YAML，不依赖 sibling 工作区账本。

### 8.2 archive 行为

- 合法 archive 正常路径通过；
- `archived`、`rejected`、`withdrawn` 终态继续通过；
- 目标 CR 在 backlog、history、index 或 `cr.md` 中数量/状态不满足约束时失败；
- history 任意 CR ID 重复或存在非法 `final-status` 时失败；
- 初次候选无效时返回 `ARCHIVE_YAML_INVALID`；
- 远端变化后的 rebuild 候选无效时同样失败；
- 失败时四个受控文件内容不变，本地与 origin 权威 HEAD 不变，没有新 stage、archive commit 或 push；journal 可以存在但不得提交无效候选；
- 现有生成错误码保持不变。

实现完成后，对真实工作区现有 backlog、history 和 index 执行一次只读严格解析验证；不新增长期 validation 命令或脚本。

### 8.3 Tools 合约

- Agent 文档只承担路由和职责边界；
- `implement-code` 是有界验证与 `ENVIRONMENT_MISMATCH` 的唯一详细事实源；
- `review-code` 不把共享实例输出当作 pass/block 证据；
- README 只保留总览和指针；
- Pipeline、`write-test-report`、权限矩阵和 crctl schema 无变化。

### 8.4 daemon 终态补投

- complete 瞬时失败耗尽现有重试后入队；
- fail 瞬时失败耗尽现有重试后入队；
- 服务恢复后原始不可变 payload 成功补投并删除；
- 相同 payload 去重，冲突 payload 保持 first-wins；
- 重放遇到瞬时错误时保留条目并结束本轮；
- 重放遇到永久错误时删除条目并记录错误；
- 日志不泄露终态 payload。

测试直接调用单轮重放 helper，不等待真实 ticker，不修改现有大型 `daemon_test.go`。

## 9. 验收标准

- 四个 archive 候选在新 write-set 建立前完成严格解析和归档后置条件校验；
- 初次构建与远端 rebuild 均无法把无效候选带入 Git；
- `ARCHIVE_YAML_INVALID` 具备稳定类别和有限错误详情；
- Agent 和 Skill 不再把共享服务生命周期当作实现、验证或评审动作；
- `ENVIRONMENT_MISMATCH` 只触发技术中止，不掩盖代码缺陷、不生成代码 blocker；
- 评审使用实际 diff 与规范测试证据，且不宣称测试证据具备 HEAD 级密码学绑定；
- daemon 存活期间，瞬时失败的 complete/fail 回调能够幂等补投；
- 待补投任务不引入新状态，成功回调后由现有服务端逻辑进入终态；
- multica 上游文件改动限于 `daemon.go` 两个小挂钩，全部定制登记到 `CUSTOM.md`；
- 三个业务域全部完成并通过同一 CR 的 review、approval、merge 和 archive 门禁。

## 10. 过度设计审计与明确不做

本方案已经删除或拒绝以下扩张项：

- 完整 YAML 标准解析器、第三方 YAML 依赖和通用 schema 注册中心；
- 全局强制所有 `parseYaml()` 调用进入严格模式；
- 新的 `crctl validate-archive`、账本修复命令、状态、门禁或证据 schema；
- Agent、Pipeline、Skill 或脚本层的归档校验副本；
- Pipeline、`write-test-report` 和 `agent-skill-matrix.yml` 修改；
- 测试证据 HEAD digest 或新的密码学绑定协议；
- multica 数据库、迁移、API、handler、client、`pollLoop` 或任务槽改造；
- 持久化终态 outbox、消息队列、容量管理、背压、并发调度或指数退避框架；
- feature flag、配置项、健康接口和 metrics；
- 新基础设施 Agent、部署 Pipeline、通用服务管理 Skill 或 controlled-shell 扩权；
- README 中的可执行细节副本；
- 与本 CR 无关的重构。

收敛后的实现复用现有 YAML 解析器、archive 事务构建点、Pipeline 失败中止、规范测试证据、终态接口重试和 orphan recovery。新增逻辑只填补已确认的静默解析、职责越界和存活 daemon 终态悬空缺口，不建立新的平台子系统。
