# CR 流程降本提效：需求来源（收敛版）

> 文档性质：经 grilling 决策收敛后的 CR 需求来源，可用于后续 CR 注册与 PRD 编写。  
> 原始来源：`CR需求来源_CR流程降本提效.md`。本文件不覆盖原始文档。  
> 决策人：Ray  
> 收敛日期：2026-09-17  
> 核心原则：只做最小、可度量、可回滚的改造；复用既有治理与事务基础设施，不再造状态机、账本或事务框架。

## 1. 一句话需求

在不改变 CR 阶段、门禁、审批、Git、账本与事务语义的前提下，首期仅实施：

1. **FR-8**：离线建立成本基线、历史回放与部署后复测；
2. **FR-1**：通过无状态 OutputGuard Core 与 Runtime Adapter，在工具结果进入模型上下文前治理无界检索、全文读取和超量输出；
3. **FR-2**：仅对贡献主要输出量的 crctl 命令做 compact summary，完整结果通过 `--detail` 获取。

FR-3～FR-7、FR-9 保留为候选 Backlog，不属于本 CR 验收范围。

## 2. 模块职责与硬边界

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 crctl |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换；离线确定性度量 | 状态推进、人工审批 |
| README | 人读流程总览、权威入口链接 | 另一份可执行细节事实源 |
| OutputGuard Core | 规则求值、确定性裁剪、提示、覆盖度结果 | CR 状态、审批、重试、Provider 安装、Runtime 恢复 |
| Runtime Adapter | 将 Runtime 原生 hook/event 映射到 Core Interface | 复制 policy、业务判断、独立版本演进 |

依赖方向：

```text
Agent → Pipeline → Skill → crctl
Runtime Adapter → OutputGuard Core → policy.json
离线度量脚本 → 既有 session/provider usage（只读）
```

## 3. 已解决的基础设施：本 CR 直接复用

### 3.1 AI-First-tools

以下能力已经存在，本 CR 不重写：

- `AI-First-tools/ARCHITECTURE.md`：定义 crctl、Pipeline、Skill、写回脚本及依赖方向；明确禁止第二套账本通道和 WAL/事务框架。
- `skills/shared/crctl/scripts/crctl.mjs`：状态、门禁与账本治理入口。
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`：锁、journal envelope、recoverable write-set、before/after CAS、恢复与冲突拒绝。
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：仓库/worktree、候选 manifest 校验、受控 Git 与原子提交。
- `skills/shared/crctl/gates.json` 与 `dir-graph.yaml`：状态机、门禁与目录图权威声明。
- `pipeline-templates/*.pipeline.json`：节点顺序、reviewLoop、onFail 与 Skill 引用权威声明。
- `skills/writeback/scripts/`：PRD/SDD/TASK/traceability 的版本化、确定性候选生成及 digest/manifest 校验。
- `.github/workflows/crctl-ci.yml`：crctl、Pipeline、Agent、Skill 与 writeback 合同校验入口。

因此，本 CR 禁止：

- 新建事务协调器、WAL、CAS 层或 Git 提交框架；
- 在 Skill、Adapter 或度量脚本中手写账本；
- 复制 passCondition、状态映射或 reviewLoop 算法；
- 拆分或重构 `workspace-transactions.mjs`；
- 修改 crctl 的阶段、门禁、审批和事务语义。

### 3.2 AI-First-multica

以下能力已经存在，本 CR 只接线、不复制：

- `server/internal/governance/runner.go`：固定 `architecture-design` 切片的节点顺序、输入传递、reviewLoop、证据检查和失败中止。
- `cr-prompts-revised/cr-coordinator-agent.md`：Agent 路由与职责边界。
- `cr-prompts-revised/dev-agent.md`、`quality-reviewer-agent.md`：Skill 选择、评审闭环与 crctl/Git 边界。
- `server/pkg/agent/*`：Runtime 启动与 Provider 事件归一化。
- `server/internal/daemon/tool_output_preview.go`：仅限制 Multica 上传/展示预览；源码明确不限制 Agent 已消费的完整工具结果。

**本 CR 不修改 `tool_output_preview.go`。** Multica daemon 收到的是 Provider 已产生的观察事件，不能作为模型消费前的 OutputGuard seam。

## 4. 基线事实

原始测量口径：

- 扫描区间：2026-08-18～2026-09-16；
- 数据源：`.multica/pi-sessions` 与 `.pi/agent/sessions`；
- 672 个 Pi session 文件，其中 643 个会话的工具结果合计约 **49.7M tokens**（o200k 编码）；
- 610 个带 CR-ID 的会话，覆盖 36 个 CR，约 **17 会话/CR**；中位数 8、P75 12、P90 56、最大 124；
- 搜索类约 10.97M tokens，目录列举约 2.32M，文件打印约 5.98M；
- crctl 命令输出约 1.24M，占执行类输出约 53%。

本 CR 只比较归一化指标，不比较绝对总量。

## 5. FR-8：离线成本与质量度量

### 5.1 目的

FR-8 只回答：

1. FR-1、FR-2 是否真的降低单位 CR 成本；
2. 是否以取证不足、缺陷后移或返工增加换取 token 下降；
3. 是否值得继续启动候选 FR。

FR-8 不推进 CR，不参与门禁，不写状态，不写账本。

### 5.2 实现位置与执行时机

建议位置：

```text
AI-First-tools/skills/shared/metrics/scripts/cr-cost.mjs
```

当前 CR 只执行两次：

1. **改造前**：读取历史日志，生成 `baseline.json`，并对 672 个历史 session 离线回放 OutputGuard policy；
2. **部署后**：完成 14 天 Pi 观察窗口，生成 `after-fr1-fr2.json` 与前后差异摘要。

不增加 Pipeline 节点、Skill 步骤、Agent 收尾动作、定时任务、数据库或仪表盘。部署后报告不是代码合并门禁。

### 5.3 输入

- 既有 session 工具调用与结果；
- 既有 CR-ID、task/run/session 标识；
- Provider usage：`input`、`cachedInput/cacheRead`、`cacheWrite`、`output`；
- 既有 Pipeline/评审数据：门禁一次通过、reviewLoop、评审发现缺陷；
- Runtime 启动能力记录和 OutputGuard trailer。

### 5.4 输出

机器结果只保留一份 JSON；人读摘要由同一脚本即时渲染，不维护第二份事实：

```json
{
  "window": "...",
  "sampleCRs": ["CR-..."],
  "coverage": { "pi": "full", "claude": "full", "codex": "partial" },
  "providerUsage": {
    "input": 0,
    "cachedInput": 0,
    "cacheWrite": 0,
    "output": 0
  },
  "toolResultTokens": 0,
  "k": 0,
  "metrics": {
    "tokensPerCR": 0,
    "sessionsPerCR": 0,
    "searchTokenRatio": 0,
    "fullReadRatio": 0,
    "bootstrapTokensPerSession": 0
  },
  "guardrails": {
    "firstPassGateRate": 0,
    "reviewLoopsPerCR": 0,
    "reviewDefectsPerCR": 0
  }
}
```

报告作为 CI artifact 或 Multica 附件保存，不进入权威账本。

### 5.5 k 的口径

```text
k = Provider 实际计费金额 ÷ 同区间工具结果 token
预计节省金额 = k × 节省的工具结果 token
```

- 使用两个完整 CR：一个接近会话数中位数，一个高会话数样本；
- 必须保留原始 usage 维度和价格来源；
- 无法取得实际计费金额时，只报告 token 放大系数，不宣称真实金额节省；
- Pi 有既有基线，可报告前后成本；其他 Runtime 首期只报告覆盖度和裁剪量，不外推 Pi 的 k。

### 5.6 观察窗口与扩项门槛

- 部署后固定观察 14 天；
- 只统计 `coverage=full` 且带 CR-ID 的完整 Pi CR；
- 样本不足时输出 `insufficient-sample`，不延长当前 CR、不编造结论；
- 目标桶（搜索/列举/打印 + crctl）`tokens/CR` 至少下降 **20%**；
- X-5 三项质量护栏必须全部不恶化；
- 只有满足上述条件，才允许重新立项评估 FR-3～FR-9。

## 6. FR-1：通用 OutputGuard

### 6.1 正确的 seam

OutputGuard 必须在工具结果进入下一轮模型上下文之前执行：

```text
Runtime 原生工具调用
  → Runtime Adapter（Pre/Post hook）
  → OutputGuard Core
  → 裁剪后的模型可见结果
  → Runtime/Multica transcript
```

只修改 Multica daemon 的 transcript/preview 已经太晚，不能降低模型上下文成本。

### 6.2 建议目录

```text
AI-First-tools/output-guard/
  core.mjs
  policy.json
  capabilities.json
  conformance.json
  adapters/
    pi.ts
    claude-hook.mjs
    codex-hook.mjs
    codebuddy-hook.mjs
    qoder-hook.mjs
```

职责：

- `core.mjs`：纯函数、无状态规则求值与确定性裁剪；
- `policy.json`：阈值、命令族、裁剪和提示规则的唯一事实源；
- `capabilities.json`：Runtime 的 full/partial/unavailable 声明；
- `conformance.json`：跨 Adapter 共用测试向量；
- Adapter：只做 Provider hook 输入/输出映射。

### 6.3 Runtime 覆盖

| Runtime | 调用前拒绝/改写 | 成功结果模型前替换 | 首期声明 |
|---|---:|---:|---|
| Pi | `tool_call` | `tool_result` | full |
| Claude Code | `PreToolUse` | `PostToolUse.updatedToolOutput` | full |
| CodeBuddy | `PreToolUse` | `PostToolUse.updatedToolOutput` | full |
| Qoder | `PreToolUse` | `PostToolUse.updatedToolOutput` | full |
| Codex | Managed `PreToolUse` | `PostToolUse` block/feedback 路径 | partial |

限制：

- Claude、CodeBuddy、Qoder 对失败调用没有通用结果替换/强制重试合同；
- Codex hosted `WebSearch` 和部分特殊路径不经过通用 hook；
- Codex 的结果替换不是透明 `updatedToolOutput`，必须明确标记 uncovered 路径；
- OutputGuard 不安装 Provider、不修复 Runtime、不重试失败调用。

参考依据：

- Pi：`@earendil-works/pi-coding-agent/docs/extensions.md` 中 `tool_call` / `tool_result` 合同；
- Claude：<https://code.claude.com/docs/en/hooks>；
- Codex：<https://developers.openai.com/codex/hooks>；
- CodeBuddy：<https://www.codebuddy.ai/docs/cli/hooks>；
- Qoder：<https://docs.qoder.com/en/cli/hooks>。

### 6.4 首期命令族

只治理实测高消耗命令：

- `grep` / `rg`；
- `find`；
- `Get-ChildItem`；
- `cat`；
- `Get-Content`。

不实现完整 Bash/PowerShell 解析器：

- 能确定违规：执行前拒绝或施加上限；
- 无法确定：允许执行，但结果仍受统一输出封顶；
- 不解析任意管道、重定向、脚本嵌套；
- 后续仅依据 FR-8 数据增加命令族。

阈值不在 PRD、Prompt、Skill 或代码常量中拍脑袋指定。TASK-01 基线完成后确定，并写入 `policy.json`。

### 6.5 裁剪策略

| 结果类型 | 策略 |
|---|---|
| 搜索/列举 | 返回唯一文件列表、总命中数和可执行的缩小范围写法 |
| 文件读取 | 保留连续行窗口与原始行号，提示下一次 `offset/limit` |
| 普通 shell | 保留头部和尾部，中间显示省略量 |

不调用 LLM 摘要，不做语义压缩，保证便宜、确定、可复现。

#### 6.5.1 模型可见结果与门禁证据不变量

- 每个被裁剪的结果必须明确标记 `complete=false`，不得伪装成完整结果；
- OutputGuard 只能修改结果正文，必须保留 `toolName`、`toolCallId`、`isError`、`exitCode` 以及 Runtime 要求的结果结构；
- 若某条 Runtime 路径无法安全保持上述字段或结果结构，则不得裁剪，并将该路径标记为 `coverage=unavailable`；
- 被丢弃的原始正文不得继续进入下一轮模型上下文；
- `complete=false` 的结果不是充分门禁证据：Reviewer、gate 或审批不得直接据此作最终判断；
- 作出最终判断前，必须继续按 `offset/limit` 切片取证，或使用一次性逃生阀取得完整结果。

### 6.6 逃生阀

统一使用 Bash/PowerShell 都能识别的首行注释：

```text
# output-guard: full reason=需要核对完整生成文件，分片会丢失跨段关系
<原命令>
```

要求：

- `reason` 必填、单行、限制长度；
- 只绕过当前调用；
- 原生 Read/Grep/Glob 需要全量时，提示改用带该标记的 shell；
- 不绕过 Git 白名单、protected paths、审批或账本写入控制；
- 不创建授权文件、nonce、永久开关或“下一次调用”状态。

### 6.7 提示与观测

只有发生拒绝或裁剪时，向模型可见结果追加一行稳定 trailer：

```text
[output-guard action=truncate complete=false original≈12k kept≈4k reason=output-cap]
```

Runtime 启动日志记录一次：

```text
output-guard runtime=pi coverage=full policy=v1
```

正常未触发调用不增加文本。FR-8 从既有 session 和启动记录派生数据，不新增 JSONL、sidecar、数据库或 CR 台账。

### 6.8 原始输出与隐私

- 原始结果只在 Adapter 内存中短暂存在；
- 裁剪后立即丢弃未保留部分；
- 下一轮模型上下文、session、Multica transcript 和日志只接收裁剪结果；
- 度量只记录原始/保留 token 数，不保存正文；
- 使用逃生阀时，完整输出按正常工具结果进入会话。

### 6.9 缺失、损坏与无 Adapter 降级

无 Adapter、Adapter 禁用、bundle 损坏或 policy 解析失败时：

```text
OUTPUT_GUARD_UNAVAILABLE runtime=<runtime> reason=<ADAPTER_MISSING|DISABLED|BUNDLE_INVALID|POLICY_INVALID>
```

- 原工具调用继续，结果不修改；
- FR-8 标记 `coverage=unavailable`；
- 该会话不进入完整覆盖效果样本；
- 不静默假装已生效；
- 不让 Agent 退化为 Prompt 自觉；
- 不影响 crctl、Git、账本和审批安全层的 fail-closed 行为。

### 6.10 发布、安装与升级

Core、Policy、五个 Adapter 属于同一个 Tools Release，原子发布、原子升级：

```text
Tools Release
  ├─ OutputGuard Core
  ├─ policy.json
  ├─ capabilities.json
  ├─ conformance.json
  └─ 五个 Runtime Adapter
```

- Adapter 从同一 Release 的相对路径读取 policy；
- 不复制到其他目录后独立维护；
- 不提供单独 Adapter 升级命令；
- `policyVersion` 只表示格式版本，不建设多版本兼容或迁移框架；
- 运行中的会话继续使用启动时版本，新会话使用新版；
- 启动检查只报告缺失/损坏与明确修复命令，不静默安装或修复。

独立使用 Tools 时，Adapter 在启用 Tools 时由用户或管理员显式安装一次，不在 CR 过程中安装：

- Project scope：首期试点；
- User scope：开发者机器全项目；
- Managed scope：企业统一部署。

Claude 场景由 Tools Plugin 携带 Skills 与 hooks。仅复制 `SKILL.md` 或读取 Tools 仓库不会自动安装 Adapter。

### 6.11 上线方式

不建设长期 shadow mode。上线前用 672 个历史 Pi session 离线回放 policy，抽检误伤后启用。

实现五个 Adapter，但按以下顺序启用：

```text
Pi → Claude → CodeBuddy → Qoder → Codex(partial)
```

前一个 Runtime 完成 conformance、真实冒烟和降级验证后，再启用下一个。这是部署顺序，不新增 CR 状态或 Pipeline 节点。

## 7. FR-2：crctl 输出瘦身

### 7.1 当前事实

当前 `crctl.mjs` 的成功输出由统一 `ok()` 完整、缩进打印 JSON，尚无 `--detail`、`--verbose` 或必要的 `--output json` 模式。

### 7.2 最小改造

1. FR-8 基线按命令聚合 crctl 输出 token；
2. 选择覆盖至少 **80% crctl 输出 token** 的最小命令集合；
3. 只为这些命令增加独立 summary projector；
4. 默认输出 compact summary JSON；
5. `--detail` 返回原完整字段；
6. 不新增无意义的 `--output json`、`--verbose`、`--pretty` 平行开关；
7. 现有机器调用方若依赖完整字段，显式补 `--detail`。

禁止在全局 `ok()` 中粗暴删除所有命令字段。

### 7.3 不变量

- 命令退出码不变；
- 错误码、字段语义和失败信息不变；
- 状态、门禁、审批、CAS、事务和 Git 行为不变；
- `--detail` 的业务字段与旧完整输出等价；
- 既有测试全绿，并增加 summary/detail 合同测试。

## 8. TASK 拆分

本需求保持 **一个 CR、十个独立 TASK**，不为五个 Runtime 重复 PRD/SDD/审批流程。复用现有跨仓 checkpoint、事务与受控 Git；每个 Adapter 保持独立提交，支持单独回滚。

| TASK | 内容 | 依赖/验收重点 |
|---|---|---|
| TASK-01 | FR-8 基线、k、命令分布与 672 session policy 离线回放 | 无；先于阈值与命令选择 |
| TASK-02 | OutputGuard Core、policy、capabilities、conformance | TASK-01；纯函数、无状态 |
| TASK-03 | Pi Adapter | TASK-02；full conformance |
| TASK-04 | Claude Adapter/Plugin | TASK-02；成功调用 full conformance |
| TASK-05 | CodeBuddy Adapter/Plugin | TASK-02；成功调用 full conformance |
| TASK-06 | Qoder Adapter/Plugin | TASK-02；成功调用 full conformance |
| TASK-07 | Codex Adapter | TASK-02；partial manifest 与支持路径测试 |
| TASK-08 | FR-2 高频 crctl summary/detail | TASK-01；覆盖 ≥80% crctl 输出 token |
| TASK-09 | Multica Runtime 启动接线 | TASK-03～07；只部署/挂载，不复制 policy；不改 preview |
| TASK-10 | 部署后复测、质量护栏与回滚结论 | 代码合并后 14 天；不作为合并门禁 |

TASK-03～07 的实现可准备，但启用顺序必须遵循 §6.11。

## 9. 验收标准

### 9.1 合并前硬验收

| 编号 | 验收标准 |
|---|---|
| AC-1 | 阶段机、passCondition、审批、账本、Git/worktree 与事务语义零改动 |
| AC-2 | `durable-tx.mjs`、`workspace-transactions.mjs` 无新事务框架或重复实现 |
| AC-3 | Core 对同一输入产生确定结果，policy/capabilities/conformance 为唯一事实源 |
| AC-4 | Pi、Claude、CodeBuddy、Qoder 通过 full conformance；Codex 按 partial manifest 验证支持项 |
| AC-5 | 无界搜索、递归列举、全文读取被拒绝/收窄时均给出可执行替代写法 |
| AC-6 | 逃生阀只影响当前调用、原因可见，且不能绕过既有安全控制 |
| AC-7 | 原始被裁剪正文不进入下一轮模型上下文、session、Multica transcript 或新增日志 |
| AC-8 | Adapter/policy 损坏时显式 fail-open，并标记 `coverage=unavailable` |
| AC-9 | 历史 672 session 回放完成；合法调用抽检零误伤 |
| AC-10 | FR-2 只覆盖基线选出的最小命令集；默认 compact summary，`--detail` 完整等价 |
| AC-11 | crctl 退出码、错误码、状态、门禁、审批、事务和 Git 行为逐一不变 |
| AC-12 | `AI-First-multica/server/internal/daemon/tool_output_preview.go` 零 diff |
| AC-13 | README 仅提供总览和权威链接，不复制 policy、hook 细节或完整能力矩阵 |
| AC-14 | 每个 Runtime 至少完成一次真实冒烟：拒绝、裁剪、逃生、损坏降级 |
| AC-15 | 在待丢弃区域放置唯一 sentinel，端到端验证该 sentinel 未进入模型可见 `tool_result`，同时保留 `toolName`、`toolCallId`、`isError`、`exitCode` 与结果结构 |
| AC-16 | 使用 `complete=false` 结果尝试完成 Reviewer/gate/审批判断时，系统必须要求继续切片取证或使用逃生阀，不得接受为充分门禁证据 |

### 9.2 部署后验证

- 14 天 Pi 观察窗口；
- 输出 `after-fr1-fr2.json`；
- 目标桶 `tokens/CR` 相对基线下降至少 20%；
- 门禁一次通过率不下降；
- reviewLoop/CR 不上升；
- 评审阶段发现缺陷数不下降；
- 任一质量护栏恶化，回滚对应 Runtime Adapter；
- 样本不足写 `insufficient-sample`，不做成本结论。

## 10. 回滚

| 失败类型 | 回滚动作 |
|---|---|
| 单 Runtime Adapter 误伤 | 禁用该 Adapter，新会话生效；其他 Runtime 保持启用 |
| Core/Policy 共性错误 | 整体回退 Tools Release |
| policy/Adapter 缺失或损坏 | 自动显式 fail-open，覆盖度改为 unavailable；不自动修复 |
| 阈值过严 | 修改 `policy.json` 并随完整 Tools Release 发布 |
| FR-2 调用方字段缺失 | 调用方补 `--detail`；必要时回退对应 projector |
| X-5 任一指标恶化 | 回滚对应措施，不新增补偿流程 |

不建设远程动态开关；安装配置就是启用开关。

## 11. 明确非目标

- 不实现 Agent/Pipeline/Skill/crctl 的架构重构；
- 不把固定 architecture-design Runner 泛化为通用工作流引擎；
- 不修复所有存量 Prompt 重复，只要求本次不新增越界；
- 不新增状态、门禁、审批或 CR 生命周期节点；
- 不新增账本、数据库、仪表盘、sidecar 日志、WAL、CAS 或事务框架；
- 不修改 Multica daemon preview；
- 不实现完整 Bash/PowerShell parser；
- 不调用 LLM 做输出摘要；
- 不自动安装 Provider、重试失败工具或修复 Runtime；
- 不要求所有 Runtime 具有相同能力；
- 不优化 crctl 运行时小文件读取；
- 不拆分 `workspace-transactions.mjs`；
- 不治理历史上从未读取的大文件；
- 不通过合并相邻会话解决 bootstrap；
- 不把检索纪律仅写入 Skill/Prompt 作为主要手段；
- 不建设测试与夹具族索引。

## 12. 候选 Backlog（不属于本 CR）

以下需求保留原始动机，但只有 §5.6 的收益门槛通过后才能重新立项：

| 候选 FR | 内容 | 当前处理 |
|---|---|---|
| FR-3 | SKILL.md 核心/附录分层 | 延后；不得在当前 TASK 顺手实施 |
| FR-4 | CUSTOM/AGENTS/README/architecture 等指引分层 | 延后 |
| FR-5 | Pipeline/gates/注册面定位摘要页 | 延后；不得复制 passCondition |
| FR-6 | 跨会话交接卡 | 延后；如实施必须保持非权威投影 |
| FR-7 | PRD/SDD 稳定锚点与任务相关节 | 延后；涉及受控写路径需另行确认 |
| FR-9 | crctl 字段、错误码、命令面事实页及 CI 新鲜度 | 延后；如实施必须复用现有生成/digest 机制 |

候选 Backlog 不是当前验收合同，不得借当前 CR 扩大范围。

## 13. 风险

| 风险 | 缓解 |
|---|---|
| 护栏过严导致取证不足 | 历史回放、零误伤抽检、连续行窗口、一次性逃生阀、X-5 回滚 |
| Runtime hook 能力不一致 | capabilities 明确 full/partial/unavailable，不伪装全覆盖 |
| Codex 特殊路径绕过 | partial manifest；不对 uncovered 路径宣称生效 |
| Adapter 配置漂移 | Core/Policy/Adapter 原子随 Tools 发布；启动只检查、不修复 |
| 被裁剪原文形成敏感副本 | 只在内存短暂存在，未保留部分立即丢弃 |
| FR-2 破坏脚本调用 | 仅改高收益命令；`--detail` 恢复完整字段；扫描并更新真实调用方 |
| 度量噪声导致虚假收益 | 固定 14 天窗口、归一化指标、coverage 过滤、样本不足显式报告 |
| 为适配五 Runtime 再造平台 | 通用 Core + 薄 Adapter；无中央 HTTP 服务、无新工作流引擎 |

## 14. 决策记录（Q1～Q36）

| 决策 | 采纳结论 |
|---|---|
| Q1 | 原附件是候选措施池，不是九项全部交付合同 |
| Q2 | 架构边界对本次新增/修改为硬约束；存量不扩散，不顺带全仓重构 |
| Q3 | 交接、度量、定位类新产物均为非权威投影 |
| Q4 | 首批范围冻结为 FR-8 + FR-1 + FR-2 |
| Q5 | 阈值由 FR-8 基线确定，最终写入规则文件，不进 Prompt/Skill/常量 |
| Q6 | 逃生阀单次生效、原因必填，不绕过安全治理 |
| Q7 | crctl 保持单一 JSON 模式；默认 compact summary，统一 `--detail` |
| Q8 | k 与真实账单对齐；保留原始 usage；无价格则不宣称金额 |
| Q9 | 采用通用 OutputGuard Core + Runtime 薄 Adapter |
| Q9.1 | 无 Adapter 时 Tools 可继续运行，但 FR-1 unavailable、FR-8 coverage incomplete |
| Q10 | FR-2 只优化基线识别的高输出命令，不覆盖所有命令 |
| Q11 | FR-8 只执行两次离线测量，不进入 CR 主流程 |
| Q12 | 不修改 Multica preview；首期目标 Runtime 为 Pi、Claude、Codex、CodeBuddy、Qoder |
| Q13 | Runtime 能力分级；四个 full，Codex partial |
| Q14 | OutputGuard 不负责 Provider 安装、失败修复或工具重试 |
| Q15 | Core/Policy/Adapter 由 Tools 统一分发；独立 Runtime 在启用 Tools 时显式安装一次 Plugin |
| Q16 | 不做完整 shell parser，只覆盖实测命令族，未知调用允许但做结果封顶 |
| Q17 | 不新增观测台账；复用 session、启动记录和稳定 trailer |
| Q18 | 逃生阀使用首行 `# output-guard: full reason=...`，保持无状态 |
| Q19 | 搜索、文件读取、普通 shell 分别采用文件列表、连续行窗口、头尾保留策略 |
| Q20 | Adapter/policy 故障 fail-open，但必须显式标记 unavailable |
| Q21 | Core、Policy、五个 Adapter 随同一 Tools Release 原子发布升级；不做多版本矩阵 |
| Q22 | 使用历史会话离线回放代替长期 shadow mode |
| Q23 | 一个 CR、十个 TASK，复用现有跨仓 checkpoint/事务能力 |
| Q24 | 实现五个 Adapter，但依次启用：Pi → Claude → CodeBuddy → Qoder → Codex |
| Q25 | 真实 after 报告不阻塞代码合并；合并前用 conformance、回放和冒烟证明 |
| Q26 | 首期只对 Pi 做成本结论，其他 Runtime 不外推 Pi 基线与 k |
| Q27 | 五个 Adapter 共用 conformance；Codex 用 capability manifest 声明不支持项 |
| Q28 | Pi 部署后使用固定 14 天观察窗口；样本不足明确报告 |
| Q29 | Runtime 特有问题单独禁用 Adapter；共性问题回退完整 Tools Release |
| Q30 | FR-2 选择覆盖至少 80% crctl 输出 token 的最小命令集合 |
| Q31 | 被裁剪原始输出不落盘、不进 transcript，仅内存短暂存在 |
| Q32 | policy/capabilities/conformance/实现测试分别承担权威事实；README 只导航 |
| Q33 | 启动只检查 Adapter，不自动安装、修复或修改用户配置 |
| Q34 | 后续扩项要求目标桶 tokens/CR 至少下降 20%，且 X-5 全部不恶化 |
| Q35 | FR-3～FR-7、FR-9 保留为候选 Backlog，不属于当前验收 |
| Q36 | 先生成并确认本收敛版 Markdown，不覆盖原附件，不直接创建正式 CR |

## 15. 后续动作

本文件确认后，才进入以下动作：

1. 由人工决定是否以本文件创建 Multica Issue/正式 CR；
2. 注册时保留原始附件与本收敛版，原始附件作为需求演进证据；
3. PRD/SDD 只能细化本文件当前范围，不得把候选 Backlog 重新带入；
4. 所有受控写入继续走既有 Skill/crctl/writeback 流程。
