---
id: CR-2026-070-prd
type: PRD
cr-ref: CR-2026-070
title: Agent Skill 路由与 Pi bash 默认超时：评审无限阻塞最小治理
target-version: 0.43
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-18T09:10:00+08:00
updated: 2026-09-18T09:10:00+08:00
---

# 1. 概述

## 1.1 问题陈述

需求来源是 Issue **AIFI-33** 附件《CR需求来源_Agent_Skill路由与Pi工具默认超时_收敛版.md》（17,049 B，附件 id `01a0b04e-58a0-75e8-b98a-bda8970e573f`），已登记在 `change-requests/CR-2026-070/sources/`。AIFI-33 只有收敛版一份附件，无原始演进版本。**本 PRD 的一切范围判定以该收敛版为唯一权威**（来源 §1、§11）。

事故事实（来源 §2.1～§2.2，均发生在 AIFI-32 / CR-2026-069 期间）：

| 项目 | 第一次 | 第二次 |
|---|---|---|
| 节点 | `review-requirement` | `review-dev-plan` 复评 |
| 触发行为 | 猜测 `~/.multica/skills` 失败后执行根目录搜索 | 全局 `~/.pi/agent/skills` 未找到 workspace Skill 后执行根目录搜索 |
| 命令 | `find / -maxdepth 6 -type d -name "review-requirement" ... \| head -20` | `find / -name "SKILL.md" -path "*review-dev-plan*" ... \| head -20` |
| CPU | 约 1110 秒 | 约 1350 秒 |
| 阻塞时长 | 约 18 分 38 秒 | 约 22 分 38 秒 |
| 恢复方式 | 人工终止精确子进程 PID，同一 Agent run 恢复 | 同上 |

共同根因链（来源 §2.3）：Runtime 已注入并原生发现 Skill → Agent 没有直接使用已发现 Skill → 用 Shell 猜路径 → 猜测失败后执行 `find /` → bash 调用未显式传 timeout、Pi 当前无默认 timeout → 工具调用无限等待，Agent 无法进入下一轮。两次均发生在读取 Issue 上下文后、首次加载当前 `review-*` Skill 的阶段，**属可重复路径，不是偶发故障**。

不属于本需求的问题（来源 §2.4）：另一次 dev-agent「疑似卡住」经核实是 `suite-gate` 正常执行（显式 `timeout: 1200`，同一命令两次耗时约 876/878 秒，命令自行正常返回），属长命令进度展示，不在本 CR 范围。

## 1.2 解决方案摘要

以最小改造消除同类无限阻塞，只做两件事，其余全部复用既有能力：

1. **FR-1**：在 Multica 单一的共享 Skills brief 中增加一条 Provider-neutral 的 Agent 行为约束——已列出的 Skill 是权威入口，选定后直接使用 Runtime 原生发现结果；预期 Skill 不可用时立即技术中止，不猜路径、不做文件系统兜底搜索。
2. **FR-2**：在 Pi 内置 bash 的**现有** timeout 解析点补一个 300 秒默认值，未显式传 timeout 时生效，显式值继续覆盖默认值；复用既有 `setTimeout`、AbortSignal、错误返回与跨平台 `killProcessTree()`。

明确不新建第二套系统（来源 §3 各节结论）：不新增 Skill Locator / manifest / 全局注册表 / 路径索引；不新增 Shell Guard、lexer 或 parser，不改 OutputGuard 行为；不新增状态、错误码、账本字段、metrics、数据库、sidecar、事务框架；Pipeline、四类 `review-*` Skill、crctl、版本化转换脚本与审批合同零业务改造；不修改、不重开已归档的 CR-2026-069。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

### 1.3.1 scope_in 边界（原文前缀，评审核对用）

- 「FR-1 Agent 直接使用 Runtime 原生发现的 Skill（禁止 Shell 或文件系统递归搜 `SKILL.md`）」（cr.md summary / 来源 §5）
- 「FR-2 Pi 内置 bash 未显式传 timeout 时默认 300 秒」（cr.md summary / 来源 §6）
- 「不新增 Skill Locator、Shell Guard/parser、错误码、metrics、数据库、sidecar、Pipeline 节点、账本或事务框架，不修改已归档 CR-2026-069 的 OutputGuard 合同」（cr.md summary）
- 「本需求不重新打开已归档的 CR-2026-069，作为独立后续 CR 注册」（来源 §1 末段）
- 「不关联其他CR、版本延续、负责人都是Ray」（AIFI-33 Issue 正文）

### 1.3.2 目标仓库与版本

| 项 | 值 | 依据 |
|---|---|---|
| target-version | `0.43` | 版本延续：`specs/_index.yml` current = `0.42`、cr-ref = CR-2026-069（已归档），CR 序列最新为 CR-2026-069，下一个未占用版本为 0.43 |
| target-spec-id | `ai-first-platform` | 与 CR-2026-060～069 同一 spec 的后续演进 |
| origin | 空 | 本 CR 是独立后续 CR，不是修复某个已归档 CR 的缺陷（来源 §1 明示「不重新打开 CR-2026-069」） |
| 关联 CR | 无 | Issue 正文明示「不关联其他CR」 |
| FR-1 落点仓 | `multica`（`../multica`，dir-graph repositories 已声明为参与仓） | 唯一写入点在 `runtime_config_sections.go` 的共享 Skills brief |
| FR-2 落点仓 | Pi 包 `@earendil-works/pi-coding-agent` 的**版本化源码仓** | 不在本 workspace `dir-graph.yaml#repositories` 声明的三仓内；当前已安装版本 0.85.1 只作现状证据，不是交付目标（见 §1.4 事实 5、FR-2 交付边界） |

FR-2 的落点仓不在 CR 参与仓集合是本需求的既有事实，不是本 PRD 新造的依赖：**不得**以「改不动」为理由退化成 patch 本机 `dist`（来源 §6.2 明令禁止），**也不得**在需求期私自修改 `dir-graph.yaml` 扩充参与仓。开发计划阶段按实际 Pi 源码仓位置与既有依赖发布路径完成最小拆分；若届时需要把 Pi 源码仓纳入 CR worktree 集合，作为架构期决策提出，不在本 PRD 内预先承诺改 `dir-graph.yaml`。

### 1.3.3 契约说明（确定性四查适用面）

本 CR 不新增 HTTP API、不新增 CLI 命令与 flag、不新增 Skill 契约，只改一条 Agent 行为约束（FR-1）与一个既有工具调用的默认值（FR-2）。FR-2 定义了 Agent 可调用的工具行为合同，四查按「行为 + 验收 + 引用先例」这一层给出，实现细节归 SDD：

| 查项 | FR-1 | FR-2 |
|---|---|---|
| 幂等 | N/A（无请求指纹；brief 文本为一次性注入） | 同一 `timeout` 输入必得同一解析结果；未传与传 `300` 解析结果等价，其余显式值不等价于默认值 |
| 权限判定顺序 | N/A（无权限分支） | 固定顺序见 FR-2「判定顺序」：非法值 → 超上限 → 合法显式值 → 未传取默认 |
| 错误闭包 | 见 FR-3 失败语义：技术中止 + 不写状态/账本，复用现有运行时/技术中止错误，不新增 `SKILL_NOT_FOUND` | 见 FR-2 超时结果：复用现有 `Command timed out after N seconds`，不新增 `TOOL_TIMEOUT` 类平行错误结构 |
| 副作用与事务边界 | 零 CR 状态、零门禁、零审批、零账本写入 | 只清理本次工具调用的进程树；不产生 CR 侧副作用；无新增持久资源 |

## 1.4 当前事实（落笔前核实）

以下断言均在写入前用命令核实，核实口径为「仓库内存在 / 位置与签名」，不含实现算法评价：

1. **Multica 已完成 Runtime 原生 Skill 注入**：`writeSkillFiles()` 存在于 `server/internal/daemon/execenv/context.go:939`；`context.go:140` 的注释确定 Pi 位置为 `{workDir}/.pi/skills/{name}/SKILL.md`（native discovery）。附属文件写入、slug 冲突、sidecar manifest 记录与清理、保留用户自有 Skill 均由该既有函数承担（来源 §3.1）。
2. **共享 Skills brief 的唯一生成点存在**：`writeSkills` 定义于 `server/internal/daemon/execenv/runtime_config_sections.go:833`，输出 `## Skills` 段（只列 Skill 名称），由同文件 `:1058` 在 brief 组装时调用；其函数注释明示「Names only, deliberately」，理由正是避免形成第二事实源（实测约 3,100 tokens/次、占整份 brief 40%）。该函数与「等价的单一公共 Agent contract」二者之一是 FR-1 的落点。
3. **未发现既有等价且单一的公共 Agent 行为 contract 承载该规则**：`grep -rn "native skill discovery"` 在 `server/internal/daemon/execenv/` 非测试代码中只命中 `runtime_config.go:161-178` 的 per-runtime 文件位置注释，规则正文不存在。故来源 §5.2「单一写入点、不得并存两份完整语义」在当时代码中是**新约束**而不是既有约束的复述。
4. **OutputGuard 已具备调用前与结果侧治理**（CR-2026-069 归档产物）：`tools/output-guard/` 目录当前含 `core.mjs`、`policy.json`、`capabilities.json`、`conformance.json`、`adapters/`、`test/`（`ls` 核实）。来源 §3.2 断言 `core.mjs` 把含 `|`、`;`、`&&`、`||` 的复合命令判为 indeterminate 并 passthrough，两次事故命令均属该类——**本 CR 不改该合同**，其不变性由 AC-9 的 conformance 复跑取证。
5. **Pi 内置 bash 的唯一缺口确认**（现状证据取自本机已安装 `@earendil-works/pi-coding-agent` 0.85.1 的 `dist/core/tools/bash.js`，读取方式=按行 grep，不作为交付物）：`resolveTimeoutMs(timeout)` 在 `timeout === undefined` 时返回 undefined（`:14-24`）；输入 schema 描述为 `"Timeout in seconds (optional, no default timeout)"`（`:28`）；超时错误文本为 `` `Command timed out after ${timeoutSecs} seconds` ``（`:257`）；非法值错误 `Invalid timeout: must be a finite number of seconds`（`:19`）；超上限错误 `Invalid timeout: maximum is ${MAX_TIMEOUT_SECONDS} seconds`（`:22`）。与来源 §3.3「现有唯一缺口是 timeout 为 optional，未传入时没有默认值」一致，即本 FR 只需补默认值。
6. **`killProcessTree()` 与 AbortSignal 已存在**：`dist/core/tools/` 内含 `killProcessTree`（Windows 走受信任 `System32/taskkill.exe /F /T /PID`，POSIX 走进程组 `SIGKILL` 并在失败时回退单 PID，来源 §3.3），且 `:71-76` 已有 `setTimeout` + `timeoutHandle` 清理路径。**不另写 cleanup。**
7. **版本与 CR 序列事实**：主 checkout `specs/_index.yml` → `current: "0.42"`、`cr-ref: CR-2026-069`；`change-requests/` 下目录最新为 `CR-2026-069`（`status: archived`），无本需求既有条目，故注册分配 `CR-2026-070`、target-version `0.43`。
8. **三仓 worktree 已 ensure**：`crctl workspace inspect CR-2026-070` → `ai-first-platform-docs`、`multica`、`tools` 均在 `requirement/CR-2026-070` 分支。

## 1.5 需求期不下结论的实现细节（归开发期 SDD）

- FR-1 规则正文的最终措辞与落点选择（改 `writeSkills` 输出，还是改等价的公共 Agent contract 并让 `writeSkills` 只引用单一来源）——来源 §5.2 已给出「二者不得并存两份完整语义」的裁决边界。
- FR-2 中「默认值」与内部 `timeout:` 错误传递的具体接线方式（现有实现把**调用方传入值**回传进错误文本，默认值生效时错误文本必须报告实际生效秒数）。
- Pi 源码仓的实际路径、版本发布号与 Multica 侧依赖升级提交。

## 1.6 修订记录

| 版本 | 时间 | 内容 |
|---|---|---|
| 0.1 | 2026-09-18 | 初稿：按收敛版来源 §5～§12 落 FR-1/FR-2 与 12 条 AC；核实来源 §3 的四项复用能力断言（事实 1～6）与版本序列（事实 7） |

---

# 2. 用户故事

- **US-1** 作为 CR 流程负责人，我希望 `review-*` 节点不再因 Agent 全盘搜文件而无限阻塞，以便 CR 按 Pipeline 节奏进入人工审批，而不是靠人工识别并终止子进程才能继续。
- **US-2** 作为质量评审 Agent（`quality-reviewer-agent`），我希望任务列出的 Skill 就是我选择 Skill 的权威入口、并由 Runtime 原生发现，以便不需要猜测任何 Runtime 私有目录就能加载评审合同。
- **US-3** 作为执行长命令的 Agent，我希望忘记传 timeout 时平台仍给一次有界等待与干净的进程树清理，以便错误以现有工具错误形式回到我的下一轮，而不是永久挂死。
- **US-4** 作为跑长测试的 dev-agent，我希望显式声明的 `timeout: 1200` 原样生效，以便 `suite-gate` 类正常长任务不被 300 秒默认值误伤。
- **US-5** 作为运行环境维护者，我希望预期 Skill 不可用时节点立即技术中止并给出缺失能力事实，以便不会产出一份基于猜路径的伪评审结论或脏账本。
- **US-6** 作为方法论包维护者，我希望 timeout 的 owner 只有一处、Skill 路由规则只有一处，以便后续排障不需要在多层之间比对哪套计时器或哪份 Prompt 副本生效。

---

# 3. 功能需求

## FR-1 Agent 直接使用 Runtime 已发现的 Skill〔来源 §5〕

**行为合同**（Agent 侧可观察行为，全部可测试）：

1. 当前任务 brief 列出的 Skill 名称是 Agent 选择 Skill 的**权威入口**；
2. 选定 Skill 后，通过 Runtime 的原生发现结果使用它，先于任何仓库探索；
3. 禁止的兜底形式（枚举）：用 Shell 或文件系统递归搜索 `SKILL.md`（含 `find`、`Get-ChildItem` 等等价命令族）、按猜测访问 `~/.multica/skills`、`~/.pi/agent/skills` 或其他 Runtime 私有目录；
4. 预期 Skill 未被 Runtime 发现时：Agent **停止当前节点**，按现有技术中止路径报告 Skill 名、当前 Runtime 与任务；不生成业务 verdict；不调用 `crctl review-record`、`advance` 或任何状态写入；不新增 `SKILL_NOT_FOUND` 等平行错误体系。

**唯一写入点**：规则只写入 Multica 单一共享 Skills brief（`writeSkills` 生成段），或——若现有 Runtime 已提供等价且单一的公共 Agent contract——修改该 contract 并保持 `writeSkills` 只引用该单一来源。**两种落点不得同时持有完整语义**，且不得复制到 `review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code`、各 Agent 独立 Prompt、README、Pipeline JSON。

**约束**（不可违反项）：不把 Pi 路径硬编码为跨 Runtime 通用合同；不在 Agent Prompt 复制所有 Provider 的 Skill 路径表；不新增 Skill 文件索引、缓存、Locator、manifest 或全局注册表；不把路径发现下沉到 review Skill；不改变 Skill 名称、frontmatter 或现有注入目录。

## FR-2 Pi 内置 bash 未显式传 timeout 时默认 300 秒〔来源 §6〕

**唯一解析规则**：

```text
调用显式传 timeout → 使用显式值
调用未传 timeout   → 使用 300 秒默认值
```

默认值固定为 300 秒；本期不引入配置文件、环境变量或远程开关（来源 §6.1）。

**判定顺序（固定，消除并列歧义）**：

1. 显式值非有限数或 ≤ 0 → 现有 `Invalid timeout: must be a finite number of seconds`；
2. 显式值换算后超既有上限 → 现有 `Invalid timeout: maximum is <MAX_TIMEOUT_SECONDS> seconds`；
3. 合法显式值 → 使用该值（含 `timeout: 1200`），不被默认值覆盖；
4. 未传 → 300 秒。
5. 传 `0`、负数、`NaN`、`Infinity` 归入第 1 档，行为与现状一致（零写入、不启动进程）。

**超时结果**（顺序确定）：

1. 复用现有 `killProcessTree(child.pid)` 清理**该工具调用**的进程树（父进程及其后代）；
2. 返回现有错误文本 `Command timed out after <实际生效秒数> seconds`（默认值生效时为 `Command timed out after 300 seconds`）；
3. Agent 按当前 Skill/节点的既有失败语义处理；
4. 无任何 CR 状态、门禁、审批或账本副作用；
5. 不新增 `TOOL_TIMEOUT`、`TOOL_TIMEOUT_CLEANUP_FAILED` 等平行错误结构。

**实现边界**：只修改 Pi 内置 bash 的现有 timeout 解析点及对应 schema/说明；复用现有 `setTimeout`、AbortSignal、timeout 错误与显式 timeout 上限校验；不增加依赖；不新增 Runtime Executor；不在 Multica、OutputGuard、Agent、Skill 或 Pipeline 再设置第二套计时器。

**交付边界**：必须通过 Pi 包的版本化源码修改 + 测试 + 构建发布，再按既有依赖升级流程让 Multica Runtime 使用新版本；**不得**以直接修改已安装包的 `dist` 作为交付（来源 §6.2）。

## FR-3 既有能力的复用合同（跨 FR 约束）〔来源 §3、§4〕

本 CR 的第三项需求是对「不建第二套系统」的可验收约束，因为它是两个改动单元共同的边界：

| 面 | 必须复用 | 本 CR 禁止 |
|---|---|---|
| Skill 发现与注入 | Multica 既有 `writeSkillFiles()` 与 Runtime 原生发现 | 新增 Skill Locator / manifest / 注册表 / 路径映射 / 索引缓存 |
| 命令与输出治理 | 已归档 CR-2026-069 的 OutputGuard `core.mjs` + `policy.json` + `capabilities.json` + `adapters/pi` | 新增第二 Guard、扩展 Shell 解析、修改复合命令 passthrough 合同 |
| 计时与清理 | Pi 既有 `setTimeout` / AbortSignal / timeout 错误 / `killProcessTree()` | 第二套计时器、自写进程清理 |
| CR 流程 | Pipeline 既有节点顺序、`reviewLoop`、工具失败中止；crctl 既有状态、门禁、CAS、账本、审计 | 新增 Pipeline 节点、状态、错误码、账本字段、sidecar、metrics、事务框架 |
| 工具错误的归类 | Runtime 执行错误 → 既有工具错误 → 既有失败语义 | 把 timeout 记账为 CR 业务状态或写入受控账本 |

---

# 4. 非功能需求

- **NFR-1 兼容性**：显式传 timeout 的调用行为逐字不变（含 `timeout: 1200` 的长测试路径）；AbortSignal 提前取消、非法值与超上限校验、现有错误文本语义无回归。
- **NFR-2 回归面收敛**：OutputGuard `core.mjs`、`policy.json`、`capabilities.json` 与 compound-shell passthrough 合同不因本需求改变；Pipeline、四类 `review-*` Skill、crctl、状态机、受控账本、版本化转换脚本与审批合同零业务 diff。
- **NFR-3 跨平台清理正确性**：timeout 后的进程树清理走既有实现（Windows `System32/taskkill.exe /F /T /PID`，POSIX 进程组 `SIGKILL` + 失败回退单 PID），Multica daemon 进程不受影响。
- **NFR-4 阻塞上界**：未显式传 timeout 的 bash 调用最长寿命从「无界」变为 ≤300 秒；不新增可观测性字段、metrics 或 UI。
- **NFR-5 零新增基础设施**：不新增依赖、数据库、sidecar、错误码、状态或事务框架。
- **NFR-6 单一事实源**：Skill 路由规则在一处生效；timeout 默认值的 owner 只有 Pi built-in bash 一处；README 若需说明只给总览与权威链接，不复制 timeout 或 Skill 路由细节。
- **NFR-7 平台中立**：FR-1 规则文本不得假设 Pi 专有目录为跨 Runtime 合同，也不得枚举各 Provider 路径表。

---

# 5. 验收标准

AC 编号沿用来源 §7 以保持可追溯；映射列是本 PRD 追加的取证口径。

| AC | 验收内容 | 对应 FR |
|---|---|---|
| AC-1 | Multica 共享 Skills brief 只增加一处 Provider-neutral 行为规则，未在各 `review-*` Skill 或 Agent Prompt 复制（对 FR-1 禁止复制面做 diff 核对，命中处必须为零） | FR-1 |
| AC-2 | 重放第一次 `review-requirement` 触发场景：Agent 直接使用 Runtime 已发现的 Skill，session 不出现查找 `SKILL.md` 的 Shell 调用 | FR-1 |
| AC-3 | 重放第二次 `review-dev-plan` 复评场景：Agent 直接使用 Runtime 已发现的 Skill，session 不出现根目录或 HOME 递归检索 | FR-1 |
| AC-4 | 预期 Skill 不可用时节点技术中止：不执行文件系统兜底搜索、不生成 verdict、不写 crctl 状态或账本（构造 Skill 缺失场景后核对 cr.md/账本零变化） | FR-1 |
| AC-5 | Pi bash 未显式传 timeout 时使用 300 秒默认值 | FR-2 |
| AC-6 | timeout 到期后复用现有 `killProcessTree()`，父进程及其后代被清理；Multica daemon 不受影响（daemon PID 与状态前后一致） | FR-2 |
| AC-7 | 显式 `timeout: 1200` 原样生效、不被默认值覆盖；dev-agent 长测试行为无回归 | FR-2 |
| AC-8 | AbortSignal、非法 timeout（非有限数 / ≤0）、显式 timeout 上限与现有错误文本行为无回归 | FR-2 |
| AC-9 | OutputGuard 全部 conformance 测试通过；`core.mjs`、`policy.json`、`capabilities.json` 与 compound-shell passthrough 合同不因本需求改变 | FR-3 |
| AC-10 | Pipeline、四类 `review-*` Skill、crctl、状态机、受控账本、版本化转换脚本与审批合同无业务 diff | FR-3 |
| AC-11 | 未新增依赖、数据库、sidecar、metrics、错误码、状态或事务框架 | FR-3 |
| AC-12 | Pi 变更通过版本化源码修改、测试、构建与正常依赖升级交付，没有直接 patch 本机安装目录（已安装 `dist` 不出现在任何交付 diff 中） | FR-2 |

补充判定口径：

- AC-2 / AC-3 的行为验证必须用真实 smoke run 留证（来源 §8.1）；Prompt 静态断言只证明规则存在，不能替代真实行为验证。
- AC-5～AC-8 的 timeout 验证在测试环境缩短等待时间，但必须走与 300 秒默认值相同的解析与 cleanup 路径（来源 §8.2）；**验收测试中不得真实等待 300 秒、不得执行 `find /`**。
- AC-9～AC-11 以复跑既有测试与 diff 面为观察点，不要求新增测试基础设施。

---

# 6. 成功指标

| 指标 | 上线前基线 | 目标 | 观察方式 |
|---|---|---|---|
| 两次历史评审场景回放中的 `SKILL.md` 搜索调用次数 | 2 次 CR 各 1 次，均无界阻塞 | 0 | 回放 session 工具调用记录 |
| 未显式传 timeout 的 bash 调用最长寿命 | 无界（实测阻塞 18 分 38 秒 / 22 分 38 秒） | ≤ 300 秒 | AC-5 与 fixture 计时 |
| 同类无限阻塞所需的人工终止次数 | 每事故 1 次（合计 2 次） | 0 | 后续 CR 流程记录 |
| 显式长任务（`timeout: 1200`）正常返回率 | 现状正常 | 无回归 | `suite-gate` 冒烟 |
| timeout 后遗留子进程数 | 未度量（此前无默认 timeout 触发路径） | 0 | AC-6 |
| 交付 diff 涉及的改动单元数 | — | 恰为 2（Multica 规则 + Pi 默认 timeout 及其回归测试） | diff 核对 |

发布顺序与回滚沿用来源 §9，不新增 CR 状态或 Pipeline 节点：先发布 Multica 共享 Agent 行为规则 → 用质量评审 Agent 重放两次历史场景 → 发布含 bash 默认 timeout 的 Pi 包 → 按既有依赖升级流程更新 Runtime → 验证默认与显式两条路径。回滚粒度到「单一共享规则」与「Pi 包版本/固定默认值」两处，OutputGuard、crctl、Pipeline 与账本因本 CR 零改动不参与回滚。

---

# 7. 范围排除

以下明确不做（来源 §1「明确不实施」、§2.4、§3 各节结论、§4「不应做」列）：

1. Task 当前工具 / 持续时间 UI；
2. 新运行态字段、数据库、sidecar 或 metrics；
3. 新 Skill Locator、Skill manifest 或全局注册表；
4. 新 Dangerous Command Guard、Shell lexer 或 Shell parser；
5. 新进程树、事务、账本、状态机或错误码框架；
6. 修改 CR-2026-069、OutputGuard 算法或现有 Pipeline；
7. 把 dev-agent「正常长测试」当阻塞问题处理的可观测性改造（以显式 timeout、进程活动与最终返回为判断依据）；
8. timeout 默认值的配置化（配置文件 / 环境变量 / 远程开关）——只有实际数据证明固定值不适用时才另立需求；
9. 在 Multica、OutputGuard、Agent、Skill 或 Pipeline 侧设置第二套计时器；
10. 直接 patch 本机已安装 Pi 包 `dist` 作为交付；
11. 需求期预先拆更多 TASK（按来源 §11：开发计划依实际 Pi 源码仓与依赖发布路径做最小拆分）；
12. 把 `docs/product/`、`docs/analysis/` 既有平台级文档搬入本 CR 产物，或为本 CR 改动 `dir-graph.yaml` 的状态机 / gates 声明（状态机与 gates 唯一事实源在 tools 包，本仓库不复刻）。
