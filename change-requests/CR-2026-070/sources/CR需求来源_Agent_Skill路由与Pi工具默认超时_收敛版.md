# Agent Skill 路由与 Pi 工具默认超时：最小治理方案

> 文档类型：后续 CR 需求来源（收敛版）  
> 日期：2026-09-17  
> 来源事件：AIFI-32 / CR-2026-069 两次质量评审阻塞  
> 状态：待注册 CR  
> 目标：复用现有能力，以最小改造消除同类评审无限阻塞

## 1. 结论与范围

本需求只实施两项：

1. **FR-1：Agent 使用 Runtime 已发现的 Skill**——Agent 选择已安装 Skill 后，直接使用 Runtime 原生发现结果；不得通过 Shell 或文件系统递归搜索 `SKILL.md`。预期 Skill 不可用时立即技术中止，不猜路径。
2. **FR-2：Pi 内置 bash 增加 300 秒默认 timeout**——未显式传入 timeout 的 Agent bash 调用使用 300 秒默认值；显式 timeout 继续覆盖默认值；复用 Pi 已有 `setTimeout`、AbortSignal、错误返回和跨平台 `killProcessTree()`。

明确不实施：

- Task 当前工具/持续时间 UI；
- 新运行态字段、数据库、sidecar 或 metrics；
- 新 Skill Locator、Skill manifest 或全局注册表；
- 新 Dangerous Command Guard、Shell lexer 或 Shell parser；
- 新进程树、事务、账本、状态机或错误码框架；
- 修改 CR-2026-069、OutputGuard 算法或现有 Pipeline。

本需求不重新打开已归档的 CR-2026-069，作为独立后续 CR 注册。

---

## 2. 问题事实

### 2.1 第一次阻塞

| 项目 | 事实 |
|---|---|
| 节点 | `review-requirement` |
| 触发行为 | Agent 为定位 Skill 猜测 `~/.multica/skills`，失败后执行根目录搜索 |
| 命令 | `find / -maxdepth 6 -type d -name "review-requirement" ... \| head -20` |
| 结果 | `find.exe` 持续占用单核，工具调用不返回 |
| CPU | 约 1110 秒 |
| 阻塞时间 | 约 18 分 38 秒 |
| 恢复 | 人工识别并终止精确子进程 PID 后，同一 Agent run 恢复 |

### 2.2 第二次阻塞

| 项目 | 事实 |
|---|---|
| 节点 | `review-dev-plan` 复评 |
| 触发行为 | Agent 在全局 `~/.pi/agent/skills` 未找到 workspace Skill，随后执行根目录搜索 |
| 命令 | `find / -name "SKILL.md" -path "*review-dev-plan*" ... \| head -20` |
| 结果 | 与第一次相同，工具调用不返回 |
| CPU | 约 1350 秒 |
| 阻塞时间 | 约 22 分 38 秒 |
| 恢复 | 人工终止精确子进程 PID 后，同一 Agent run 恢复 |

### 2.3 共同根因

```text
Runtime 已注入并原生发现 Skill
  → Agent 没有直接使用已发现 Skill
  → Agent 用 Shell 猜路径
  → 猜测失败后执行 find /
  → bash 调用未显式传 timeout，Pi 当前无默认 timeout
  → 工具调用无限等待，Agent 无法进入下一轮
```

两次均发生在 Agent 读取 Issue 上下文后、首次加载当前 `review-*` Skill 的阶段，属于可重复路径，不是偶发故障。

### 2.4 不属于本需求的问题

另一次 dev-agent “疑似卡住”经核实是 `suite-gate` 正常执行：

- 显式传入 `timeout: 1200`；
- 同一命令两次耗时约 876/878 秒；
- 测试期间持续创建和清理 fixture、生成子进程；
- 命令自行正常返回。

该问题属于长命令进度展示，不是无限阻塞。本 CR 不做 UI 或运行态可观测性改造。

---

## 3. 已解决的基础设施（必须复用）

本节列出现有能力。实现不得为这些能力建立第二套系统。

### 3.1 Multica 已完成 Runtime 原生 Skill 注入

Multica `server/internal/daemon/execenv/context.go` 已为不同 Runtime 写入原生 Skill 目录。Pi 的确定位置为：

```text
{workDir}/.pi/skills/{name}/SKILL.md
```

现有 `writeSkillFiles()` 已负责：

- 创建 Skill 目录；
- 写入 `SKILL.md` 与附属文件；
- 处理 Skill slug 冲突；
- 记录 sidecar manifest 并在任务清理时删除托管文件；
- 保留用户自有 Skill，不覆盖用户文件。

`runtime_config_sections.go#writeSkills` 已在运行时 brief 中列出本任务安装的 Skill 名称，并明确由各 Runtime 原生发现 Skill。该设计避免复制描述和路径形成第二事实源。

**结论：本需求不新增 Skill Locator、manifest、注册表或路径映射。**

### 3.2 OutputGuard 已完成调用前和结果侧治理

CR-2026-069 已归档，主干已有：

```text
output-guard/
  core.mjs
  policy.json
  capabilities.json
  conformance.json
  adapters/pi/index.ts
```

已有能力：

- `find` / `Get-ChildItem` 命令族；
- Pi `tool_call` 执行前 block/rewrite；
- Pi `tool_result` 执行后裁剪；
- policy/capabilities/conformance 单一事实源。

当前 `core.mjs` 把含 `|`、`;`、`&&`、`||` 等复合 Shell 结构的调用判为 indeterminate 并 passthrough；两次事故命令均属于该类。这符合“不实现完整 Shell parser”的既有合同。

**结论：本需求不增加第二 Guard，不扩展 Shell 解析，不修改 OutputGuard 行为。**

### 3.3 Pi 已完成 timeout 与进程树清理原语

Pi 内置 bash 已具备：

- `timeout?: number` 输入；
- 标准库 `setTimeout`；
- AbortSignal 取消；
- timeout 后调用 `killProcessTree(child.pid)`；
- 现有 `Command timed out after N seconds` 错误；
- 显式 timeout 上限校验。

现有 `killProcessTree()` 已实现：

- Windows：受信任的 `System32/taskkill.exe /F /T /PID <pid>`；
- POSIX：进程组 `SIGKILL`，失败时回退单 PID。

现有唯一缺口是：

```text
timeout 为 optional，未传入时没有默认值。
```

**结论：本需求只补默认值，不重写 timeout、Abort、错误或进程树实现。**

### 3.4 CR 状态与账本能力已经解决

Pipeline 与 crctl 已拥有节点顺序、reviewLoop、失败中止、状态、门禁、CAS、受控账本写入、审计和原子提交。

工具调用 timeout 是 Runtime 执行错误：

- Runtime 返回现有工具错误；
- Agent/Skill 按现有失败语义停止或恢复；
- Pipeline 按现有节点失败规则中止；
- crctl 不写新状态、不增加账本字段。

**结论：Pipeline、Skill、crctl、版本化转换脚本和受控账本零业务改造。**

---

## 4. 架构与职责边界

| 模块 | 本 CR 应做 | 本 CR 不应做 |
|---|---|---|
| Agent | 路由、职责判断、选择并直接使用 Runtime 已发现的 Skill | 不管理进程、不实现状态机/Git/账本算法 |
| Multica Runtime brief | 在现有 Skills 区提供一条共享 Agent 行为约束 | 不复制 Skill 描述、路径表或 Provider 算法 |
| Pipeline | 复用现有工具失败中止 | 不新增节点，不复制 Skill 或 timeout 算法 |
| Skill | 复用现有业务步骤与技术失败语义 | 不查找自身文件，不实现 timeout 或账本逻辑 |
| Pi Runtime | 为已有 bash timeout 增加默认值 | 不判断 CR 业务、不写账本 |
| OutputGuard | 保持现有 policy/core/adapter 合同 | 不增加第二 Guard，不扩展为 Shell parser |
| crctl | 零改动 | 不记录工具 timeout，不新增状态或错误投影 |
| 版本化脚本 | 零改动 | 不推进状态，不处理人工审批或进程生命周期 |
| README | 原则上零改动；如需说明仅给总览与权威链接 | 不复制 timeout、Skill 路由或执行细节 |

---

## 5. FR-1：Agent 直接使用 Runtime 已发现的 Skill

### 5.1 需求

在 Multica 单一的共享 Skills brief 中，为所有 Agent 增加一条 Provider-neutral 的行为约束：

```text
When a listed skill matches the task, use it through the runtime's native skill discovery before repository exploration. If the expected skill is unavailable, stop and report the missing capability; do not search the filesystem for SKILL.md.
```

中文语义：

1. 当前任务列出的 Skill 是 Agent 选择 Skill 的权威入口；
2. Agent 选择 Skill 后使用 Runtime 原生发现结果；
3. Skill 不可用时立即停止并报告缺失能力；
4. 不使用 Shell、`find`、`Get-ChildItem` 或全盘文件检索寻找 `SKILL.md`；
5. 不猜测 `~/.multica/skills`、`~/.pi/agent/skills` 或其他 Runtime 私有目录。

### 5.2 唯一写入点

该规则只写入 Multica `writeSkills` 生成的共享 Agent brief，不复制到：

- `review-requirement`；
- `review-tech-design`；
- `review-dev-plan`；
- `review-code`；
- 各 Agent 独立 Prompt；
- README；
- Pipeline JSON。

如现有 Runtime 已提供等价、单一的公共 Agent contract，则修改该 contract，并保持 `writeSkills` 只引用该单一来源；不得保留两份完整语义。

### 5.3 失败语义

预期 Skill 未被 Runtime 发现时：

- Agent 停止当前节点；
- 按现有技术中止路径报告 Skill 名、当前 Runtime 和任务；
- 不生成业务 verdict；
- 不调用 `crctl review-record`、`advance` 或其他状态写入；
- 不新增 `SKILL_NOT_FOUND` 等平行错误体系，复用现有运行时/技术中止错误。

### 5.4 约束

- 不硬编码 Pi 路径为跨 Runtime 通用合同；
- 不在 Agent Prompt 复制所有 Provider 的 Skill 路径；
- 不新增 Skill 文件索引或缓存；
- 不把路径发现下沉到 review Skill；
- 不改变 Skill 名、frontmatter 或现有注入目录。

---

## 6. FR-2：Pi 内置 bash 增加默认 timeout

### 6.1 需求

Pi 内置 bash 的 timeout 解析使用以下唯一规则：

```text
调用显式传 timeout → 使用显式值
调用未传 timeout   → 使用 300 秒默认值
```

默认值固定为 300 秒。当前不增加配置文件、环境变量或远程开关；后续只有实际数据证明固定值不适用时才考虑配置化。

### 6.2 实现边界

只修改 Pi 内置 bash 的现有 timeout 解析点及对应 schema/说明：

- 复用现有 `setTimeout`；
- 复用现有 `killProcessTree()`；
- 复用现有 AbortSignal；
- 复用现有 timeout 错误；
- 复用现有显式 timeout 上限；
- 不增加依赖；
- 不新增 Runtime Executor；
- 不在 Multica、OutputGuard、Agent、Skill 或 Pipeline 再设置第二套计时器。

不得直接修改已安装包的 `dist` 作为交付；必须修改 Pi 包的版本化源代码、运行测试、构建发布，并按现有依赖升级流程让 Multica Runtime 使用新版本。

### 6.3 显式 timeout

显式 timeout 保持原语义：

- `timeout: 1200` 等长测试调用继续使用 1200 秒；
- 显式值不被 300 秒默认值覆盖；
- 非法值和超上限值继续使用现有校验与错误；
- 持久服务继续走现有持久服务 handoff，不通过无限 bash 调用维持。

### 6.4 超时结果

默认 timeout 命中后：

1. Pi 使用现有 `killProcessTree(child.pid)` 清理工具调用进程树；
2. 返回现有 `Command timed out after 300 seconds` 工具错误；
3. Agent 根据当前 Skill/节点的既有失败语义处理；
4. 无任何 CR 状态、门禁、审批或账本副作用；
5. 不新增 `TOOL_TIMEOUT`、`TOOL_TIMEOUT_CLEANUP_FAILED` 等平行错误结构。

---

## 7. 验收标准

| AC | 验收内容 |
|---|---|
| AC-1 | Multica 共享 Skills brief 只增加一处 Provider-neutral 行为规则，未在各 review Skill 或 Agent Prompt 复制 |
| AC-2 | 重放第一次 `review-requirement` 触发场景，Agent 直接使用 Runtime 已发现的 Skill，session 不出现查找 `SKILL.md` 的 Shell 调用 |
| AC-3 | 重放第二次 `review-dev-plan` 复评场景，Agent 直接使用 Runtime 已发现的 Skill，session 不出现根目录或 HOME 递归检索 |
| AC-4 | 预期 Skill 不可用时节点技术中止，不执行文件系统兜底搜索，不生成 verdict，不写 crctl 状态/账本 |
| AC-5 | Pi bash 未显式传 timeout 时使用 300 秒默认值 |
| AC-6 | timeout 到期后复用现有 `killProcessTree()`，父进程及其后代被清理；Multica daemon 不受影响 |
| AC-7 | 显式 `timeout: 1200` 原样生效，不被默认值覆盖；dev-agent 长测试行为无回归 |
| AC-8 | AbortSignal、非法 timeout、显式 timeout 上限和现有错误文本行为无回归 |
| AC-9 | OutputGuard 全部 conformance 测试通过，`core.mjs`、`policy.json`、`capabilities.json` 和 compound-shell passthrough 合同不因本需求改变 |
| AC-10 | Pipeline、四类 review Skill、crctl、状态机、受控账本、版本化转换脚本和审批合同无业务 diff |
| AC-11 | 未新增依赖、数据库、sidecar、metrics、错误码、状态或事务框架 |
| AC-12 | Pi 包通过版本化源码修改、测试、构建和正常依赖升级交付，没有直接 patch 本机安装目录 |

---

## 8. 验证方案

### 8.1 Agent 行为验证

执行两条历史触发场景：

1. `review-requirement` 首次加载；
2. `review-dev-plan` 自修复后的独立复评。

检查 session：

- 已选择正确 Skill；
- 未出现 `find /`；
- 未出现递归搜索 `SKILL.md`；
- 未猜测 `~/.multica/skills` 或全局 `~/.pi/agent/skills`；
- 后续证据读取使用 Skill 规定的路径和步骤。

Agent 行为验证应使用真实 smoke run 留证；Prompt 静态断言只证明规则存在，不能替代真实行为验证。

### 8.2 Pi timeout 验证

使用可控的长时间父子进程 fixture，测试环境缩短等待时间但走与 300 秒默认值相同的解析和 cleanup 路径：

1. 未显式传 timeout，默认计时器生效；
2. 到期后父子进程全部退出；
3. 返回现有 timeout 错误；
4. Multica daemon PID 和状态保持不变；
5. 显式 timeout 覆盖默认值；
6. AbortSignal 仍可提前取消；
7. 正常短命令行为不变。

不得在验收测试中真实等待 300 秒或执行 `find /`。

### 8.3 回归验证

- Pi 原有 bash 测试；
- OutputGuard conformance；
- Multica Skill 注入、sidecar manifest、collision 与 cleanup 测试；
- CR Pipeline/crctl 现有门禁测试；
- dev-agent `suite-gate` 显式 `timeout:1200` 冒烟。

---

## 9. 发布顺序与回滚

### 9.1 发布顺序

1. 发布 Multica 共享 Agent 行为规则；
2. 用质量评审 Agent 重放两次历史场景；
3. 发布含 bash 默认 timeout 的 Pi 包；
4. 按现有依赖升级流程更新 Runtime；
5. 验证未显式 timeout 与显式 timeout 两条路径。

不新增 CR 状态或 Pipeline 节点。

### 9.2 回滚

- Agent 规则误伤：回滚单一共享规则，不修改 Skill 文件；
- 默认 timeout 误伤：回滚 Pi 包版本或调整固定默认值；
- 显式长任务应补 timeout，不通过永久关闭默认保护处理；
- OutputGuard、crctl、Pipeline 与账本无本 CR 改动，无需参与回滚。

---

## 10. 风险与控制

| 风险 | 控制 |
|---|---|
| Agent 仍忽略已发现 Skill | 真实回放两次历史触发场景；规则放在单一共享 Skills brief，避免多份 Prompt 漂移 |
| 300 秒误伤长任务 | 现有显式 timeout 覆盖；长测试、build、migration 必须显式声明 |
| timeout 后遗留子进程 | 复用并回归测试现有 `killProcessTree()`，不另写 cleanup |
| 把本需求扩成 Shell parser | OutputGuard 复合命令 passthrough 合同保持不变 |
| 在多个层设置 timeout | Pi built-in bash 为唯一 owner，其他模块零重复计时器 |
| 直接 patch 本机 dist | 只通过 Pi 版本化源码、构建、发布和依赖升级交付 |
| 误把正常长测试当阻塞 | 本 CR 不做 UI；以显式 timeout、进程活动和最终返回作为判断依据 |

---

## 11. 建议注册信息

### 标题

**Agent Skill 路由与 Pi bash 默认超时：评审无限阻塞最小治理**

### 摘要

针对 AIFI-32 / CR-2026-069 中两次质量评审因 Agent 未使用 Runtime 已发现 Skill、转而执行 `find /`，且 Pi bash 未显式传 timeout 时可无限等待的问题，实施两项最小治理：在 Multica 单一共享 Skills brief 中要求 Agent 直接使用 Runtime 原生发现的 Skill、缺失时技术中止；在 Pi 内置 bash 的现有 timeout 解析点增加 300 秒默认值，复用既有 `setTimeout`、AbortSignal、错误返回和跨平台 `killProcessTree()`。不新增 Skill Locator、Shell Guard/parser、错误码、metrics、数据库、sidecar、Pipeline 节点、账本或事务框架，不修改已归档 CR-2026-069 的 OutputGuard 合同。

### 建议优先级

P1。问题已在同一 CR 的两个独立评审节点稳定复现，均需人工终止精确子进程才能恢复。

### 建议实施规模

两个独立改动单元：

1. Multica 单一共享 Agent Skill 使用规则；
2. Pi built-in bash 默认 timeout 与回归测试。

不在需求来源阶段预先拆更多 TASK；开发计划根据实际 Pi 源码仓和依赖发布路径完成最小拆分。

---

## 12. 完成定义

以下条件全部满足才算完成：

- 两个历史评审场景真实回放均不再搜索 `SKILL.md`；
- 未显式传 timeout 的 Pi bash 最多运行 300 秒；
- timeout 后现有进程树清理测试通过；
- 显式 timeout、AbortSignal 和长测试无回归；
- OutputGuard、Pipeline、Skill、crctl、状态机、审批和账本合同无变化；
- 未新增并行事实源、依赖、状态、错误体系或事务框架；
- Pi 变更通过版本化源码发布，Multica Runtime 使用正式升级版本。
