# tools 流程步骤优化方案

> 文档状态：方案稿。本文记录 CR 注册、PRD 编写与需求评审流程的兼容改法和分阶段实施计划，不直接修改 tools 包代码。

## 1. 目标与范围

本文基于以下实际工具调用记录，分析并优化 tools 包的 CR 注册、PRD 编写与需求评审流程：

- `change-requests/CR-2026-026/注册过程操作记录.md`；
- `change-requests/CR-2026-026/PRD编写过程操作记录.md`；
- `change-requests/CR-2026-026/PRD评审过程操作记录.md`；
- `change-requests/CR-2026-026/SDD撰写工具调用.md`；
- `change-requests/CR-2026-026/SDD评审过程操作记录.md`；
- `change-requests/CR-2026-026/PlanTask撰写评审过程操作记录.md`；
- `change-requests/CR-2026-026/开发测试评审回修过程操作记录.md`；
- `change-requests/CR-2026-026/合并回写归档过程操作记录.md`。

范围限定为：

- tools 包位置发现；
- 注册前预检；
- `crctl cr-init` 后验证；
- 注册提交与 worktree 派生；
- P0–P2 的流程、命令和测试改造。
- PRD 上下文准备、文档落盘、索引登记和提交；
- 需求评审 payload、三账本写入、状态路由和证据提交；
- SDD 上下文准备、架构事实读取、回修与技术评审；
- Plan/TASK 拆解、索引生成、依赖与估算校验、合并评审；
- implement-code、测试报告、代码评审、suggestion scope change 和回修闭环；
- 多仓合并、specs/delivery 回写、追溯链生成、归档发布与 worktree 清理；
- 确定性步骤代码化、批量读取、调用合并和过度设计控制。

不改变以下既有契约：

- CR-ID 仍由 `crctl cr-init` 通过 CAS 原子分配；
- `cr.md`、`_backlog.yml`、`_index.yml` 仍只能由 `crctl` 写入；
- 状态机仍以目标 workspace 的 `dir-graph.yaml#change-request-track.state_machine` 为事实源；
- 所有 Git 操作仍必须经 `controlled-shell` / `crctl git`；
- 注册提交必须先于 knowledge-base worktree 派生；
- active repo、trunk、worktree 仍由目标 workspace 的 `dir-graph.yaml#repositories` 动态解析。

### 1.1 推荐架构：三层职责边界

不要继续把所有功能堆进 `crctl.mjs`。tools 包的优化应收敛为三层：

#### 第一层：crctl 权威原语

`crctl` 只承担跨 Skill 共享、必须保持唯一事实源的权威能力：

- 状态机转换；
- gate 校验；
- CAS 与多文件一致写；
- `_backlog.yml`、`review-loop.yml`、`traceability.yml` 等受控账本写入；
- identity、时间戳和审计；
- 受控 Git；
- worktree 路径权威解析；
- approval、review-record、checkpoint 等目的明确的原语。

`crctl` 继续保持唯一状态写者和账本权威写者，但不承担完整 Skill 工作流编排，不负责生成 SDD、Plan、TASK 或评审语义。

#### 第二层：Skill 确定性 Runner

Runner 位于各 Skill 自己的版本化目录：

```text
skills/{group}/{skill}/scripts/prepare.mjs
skills/{group}/{skill}/scripts/finalize.mjs
```

Runner 组合现有 `crctl` 原语，完成：

- 解析权威 worktree 和目标仓；
- 批量读取并规范化上下文；
- 生成和保护 frontmatter；
- 结构、schema、引用、依赖和估算校验；
- 调用 purpose-specific `crctl` 账本命令；
- 合并状态变更与产物提交；
- 输出机器可读执行摘要和下一步。

Runner 不复制状态机、gate 或账本写入逻辑；这些仍委托给 `crctl`。Runner 的价值是把一个 Skill 内反复由 LLM 编排的确定性步骤收进深模块。

#### 第三层：LLM 语义步骤

LLM 只接收 Runner 产生的规范化上下文，只输出：

- PRD、SDD、Plan、TASK 的语义正文；
- blocker 修复后的文档内容；
- 评审 verdict、blockers、dimensions、suggestions；
- 架构取舍、范围判断、任务边界和风险分析。

LLM 不再：

- 操作 `_backlog.yml`、`review-loop.yml` 或 `traceability.yml`；
- 自行解析 worktree 路径；
- 搜索 Skill 文件位置；
- 检查 Git 历史确认刚完成的提交；
- 生成确定性的 TASK 索引；
- 手工推进状态；
- 在 `crctl.mjs` 中 grep schema。

Pipeline 仍负责跨节点顺序、reviewLoop 和 human approval，但它是三层能力的编排载体，不形成第四套业务规则或事实源。

该架构比新增通用 `crctl patch`、`crctl run-workflow` 或继续扩大 `crctl.mjs` 更符合现有 purpose-specific command 设计：权威原语保持集中，Skill 差异留在各自 Runner，LLM 接口保持最小。

## 2. 现状与问题

### 2.1 24 次调用的结构

CR-2026-026 在约 3 分钟内完成注册，但 24 次调用中有 6 次失败或探索性调用：

| 调用 | 问题 |
|---|---|
| #4 | 在 workspace 内搜索注册 Skill；实际 Skill 位于 tools 包 |
| #5 | 用 Glob 检查被忽略的 `.rayai-worktrees` |
| #6 | 按旧账本结构 grep `_backlog.yml` 编号 |
| #12 | PowerShell 环境使用 Unix `head` |
| #15 | 重试 `crctl cr-init --help` |
| #18 | PowerShell 环境使用 Unix `tail` |

重复或可合并调用包括：

- #2、#5、#9、#10：多次检查目录、账本、worktree 和 Git 状态；
- #12、#15：同一个 help 探索；
- #13、#20：重复查询 register 提交先例；
- #17、#18、#19：注册后分散验证三份产物；
- #22、#23、#24：路径解析、worktree 创建和最终状态验证分散执行。

### 2.2 `tools` 路径不能写死为 `../tools`

当前 workspace 的 `dir-graph.yaml` 使用：

```yaml
workspace:
  tools_package_path: "../tools"
```

这是本项目的 sibling 挂载实例，不是 tools 包的通用规则。

标准新项目按 `tools/docs/QODER-使用指南.md` 将 tools 包安装到：

```text
<workspace>/tools/
```

tools 包自身的 `dir-graph.yaml` 也声明 `target_install_path: "tools/"`。

`docs/references/tools.md` 只记录仓库地址、commit SHA 和来源，不是运行时路径配置。

当前 `crctl.mjs` 已有两个 fallback：

1. `<workspace>/tools/`
2. 当前 `crctl.mjs` 所属 package root

但当前实现没有消费 `workspace.tools_package_path`。因此本方案新增统一的 tools root 解析函数，并将现有调用统一接入。

## 3. 统一 tools root 解析

### 3.1 解析优先级

新增 `resolveToolsRoot(workspace)`，候选顺序为：

1. `workspace.dir-graph.yaml#workspace.tools_package_path`；
2. `<workspace>/tools/`；
3. 当前 `crctl.mjs` 所属的 package root。

相对路径一律相对目标 workspace 根解析，不相对当前进程目录解析。

每个候选路径必须验证以下最小标记：

```text
AGENTS.md
dir-graph.yaml
skills/_index.yml
pipeline-templates/_index.yml
skills/shared/crctl/
```

全部候选均不存在时，返回结构化错误：

```json
{
  "error": {
    "code": "TOOLS_PACKAGE_NOT_FOUND",
    "message": "未找到可用的 tools 包",
    "workspace": "...",
    "candidates": ["..."]
  }
}
```

禁止通过向父目录无限搜索来碰运气发现 tools 包。

### 3.2 统一接入点

`resolveToolsRoot` 应被以下逻辑复用：

- `loadStateMachine`：目标 workspace `dir-graph.yaml` 仍优先；tools 包目录作为 fallback；
- `loadPipeline`：从解析出的 tools root 加载 pipeline 模板；
- 注册预检；
- tools 包一致性检查；
- 注册摘要中的 `tools_context`。

`gates.json` 仍使用与 `crctl.mjs` 同一 package root 内的版本，避免从另一个挂载点加载不匹配的门禁文件。

### 3.3 摘要留痕

注册完成摘要增加：

```yaml
tools_context:
  root: C:/.../tools
  source: workspace.tools_package_path | workspace-default | package-root
  configured-path: ../tools
```

这样可以区分：

- 当前项目的 sibling 挂载；
- 新项目的 workspace 内安装；
- IDE 直接从 package root 执行 `crctl` 的 fallback。

## 4. P0：低风险流程收敛

### 4.1 目标

不改变 `crctl` 状态机和账本写入语义，只消除错误探索、shell 差异和重复读取。

### 4.2 修改内容

修改：

- `skills/requirement/requirement-register/SKILL.md`
- `skills/shared/controlled-shell/SKILL.md`
- 注册操作记录模板或运行时日志格式

规则：

1. 首先调用统一 tools root 解析，不再搜索固定的 `../tools`；
2. 默认只读取 `AGENTS.md`、目标 workspace `dir-graph.yaml`、tools `AGENTS.md` 和 `requirement-register/SKILL.md`；
3. `SearchMemory`、历史 CR、历史提交只在事实冲突时按需读取；
4. 不再 grep `_backlog.yml` 计算 CR 编号；编号只能由 `crctl cr-init` 分配；
5. 不使用 `head`、`tail` 等未抽象的 shell 管道；
6. Git 调用日志明确记录 `crctl git` 或 controlled-shell 适配器，不再笼统标记为裸 Bash；
7. 将目录、Git 状态、已有 worktree 检查合并为一次注册预检。

### 4.3 P0 验收

- 注册过程不再出现 #4、#5、#6、#12、#18 类探索失败；
- 同一注册不读取两个历史 CR 作为默认步骤；
- 不出现 `../tools` 的全局假设；
- 24 次调用降至约 12–14 次；
- 不改变 CR-ID 分配、trunk clean 门禁和三文件原子写入。

## 5. P1：增加确定性批量能力

### 5.1 `register-preflight`

增加只读命令：

```text
crctl register-preflight --workspace .
```

一次返回：

- `tools_context`；
- knowledge-base repo 和 trunk；
- 所有 `active != false` 的 repo；
- trunk clean 状态；
- 已有 CR worktree；
- 已存在的 `requirement/CR-*` 分支；
- 阻塞原因和结构化错误。

预检不分配 CR-ID，也不写账本，避免预检结果与 `cr-init` 之间产生错误的编号假设。

### 5.2 `registration-check`

增加只读命令：

```text
crctl registration-check CR-2026-026 --workspace .
```

一次校验：

- `change-requests/CR-2026-026/cr.md` 存在；
- `_backlog.yml` 与 `_index.yml` 均有同一 CR-ID；
- owners 三角色均有 `id` 和 `assigned-at`；
- `cr.md.status=drafting`；
- 三份注册产物的 CR-ID、标题和元信息一致；
- 当前变更中没有意外暂存文件。

该命令替代 #17、#18、#19 的分散人工读取。

### 5.3 批量 worktree 路径

扩展：

```text
crctl worktree-path CR-2026-026 --all --workspace .
```

一次返回所有 active repo 的 bucket 和绝对路径。

路径仍由 `dir-graph.yaml#repositories` 解析，不允许在 Skill 中写死 knowledge-base、multica 或任何本机绝对路径。

### 5.4 P1 验收

- #2、#5、#9、#10 收敛为一次 `register-preflight`；
- #17、#18、#19 收敛为一次 `registration-check`；
- #22 的两次 `worktree-path` 收敛为一次批量调用；
- 失败输出统一为结构化 JSON；
- `crctl` 测试覆盖 sibling tools、workspace/tools、package-root 三种布局。

## 6. P2：并行化多仓库派生

### 6.1 保持的依赖

以下顺序不能改变：

```text
cr-init
→ 注册文件提交
→ knowledge-base worktree 派生
```

原因是 knowledge-base worktree 必须从包含注册记录的 trunk commit 派生。

### 6.2 可并行部分

注册提交成功后：

1. 所有 repo 的 worktree 路径解析并行；
2. 非 knowledge-base repo 的 `fetch origin` 与 knowledge-base push 的后续收尾并行；
3. 各 active repo 的 `worktree add` 并行；
4. 最终状态与 worktree 结果统一汇总。

### 6.3 失败补偿

任一 repo 创建失败时：

- 停止后续业务节点；
- 返回已创建 worktree 列表；
- 返回失败 repo、命令、stdout、stderr；
- 由受控清理入口决定是否移除已创建 worktree；
- 不写 PRD，不推进后续 CR 状态。

不能简单使用“全部并行后忽略失败”，否则会留下半成品 worktree。

### 6.4 P2 验收

- 两个 active repo 的 fetch/add 不再强制串行；
- 单仓库项目行为不增加额外调用；
- 多仓库失败时可恢复且不丢失已创建清单；
- `git worktree add` 仍经 `controlled-shell` / `crctl git`；
- 注册流程最终调用降至约 8–10 次。

## 7. 建议的最终注册调用序列

```text
1. crctl register-preflight
2. requirement-register 读取用户输入和必要上下文
3. crctl cr-init --summary --source --target-version
4. crctl registration-check
5. crctl git add <三份显式注册文件>
6. crctl git commit --template register --cr <CR-ID>
7. crctl git push origin <knowledge-base-trunk>
8. crctl worktree-path --all
9. 并行 fetch / worktree add
10. crctl status + worktree 结果汇总
```

其中 5–7 仍需保持显式文件白名单，不能改成 `git add -A`。

## 8. 实施文件与测试

### tools 包

```text
C:\Users\GOBAO\Downloads\AI\tools\skills\shared\crctl\scripts\crctl.mjs
C:\Users\GOBAO\Downloads\AI\tools\skills\shared\crctl\scripts\test\crctl.test.mjs
C:\Users\GOBAO\Downloads\AI\tools\skills\requirement\requirement-register\SKILL.md
C:\Users\GOBAO\Downloads\AI\tools\skills\shared\controlled-shell\SKILL.md
C:\Users\GOBAO\Downloads\AI\tools\README.md
C:\Users\GOBAO\Downloads\AI\tools\docs\QODER-使用指南.md
```

### 必测布局

1. tools 位于 `<workspace>/tools`；
2. tools 位于 `workspace.tools_package_path` 指向的 sibling 目录；
3. workspace 未配置 tools 路径，但从 tools package root 执行 `crctl`；
4. 配置路径存在但不是合法 tools 包；
5. 所有候选路径均不存在；
6. 多仓库 worktree 创建一成功一失败；
7. workspace 有无关脏文件时，注册仍拒绝或只暂存三份显式注册文件。

## 9. 成功标准

优化完成后，注册流程应满足：

- 不把 `../tools` 当作通用路径；
- 能兼容 workspace 内安装、sibling 挂载和 package-root 执行；
- 失败/探索性调用由 6 次降为 0；
- 注册调用由 24 次降至约 8–10 次；
- 不改变 CAS、状态机、受控 Git、commit-before-worktree 等安全契约；
- 所有路径、repo、trunk、worktree 信息都有机器可读来源和摘要留痕。

## 10. 纳入 CR-2026-026 的 `review-dev-plan` 评审暂停

### 10.1 当前边界

本节引用的设计依据是：

```text
docs/analysis/开发计划与TASK合并评审门禁方案.md
```

该方案定义了一个新的编码前合并评审节点：

```text
write-dev-plan
  → write-dev-tasks
  → review-dev-plan
  → push-progress
  → human_approval（开发启动）
  → approve-dev-start
```

`review-dev-plan` 同时评审：

- SDD → plan 覆盖；
- plan → TASK 覆盖；
- TASK 可执行性；
- 验收可验证性；
- 依赖拓扑；
- 接口契约一致性；
- 范围与极简性；
- 风险、回滚和估算一致性。

它不是两个独立评审，不新增 `review-plan`、`review-tasks` 或新的 CR 状态。

### 10.2 统一评审暂停配置

需求、技术设计、开发计划/TASK 合并评审、代码评审统一使用同一套配置语义：

```json
{
  "reviewSelection": {
    "pauseBeforeReview": true,
    "defaultModel": null,
    "onReplay": "reuse",
    "stages": {
      "requirement": {},
      "tech-design": {},
      "dev-plan": {},
      "code": {}
    }
  }
}
```

规则：

- `pauseBeforeReview` 默认值为 `true`；
- `true`：评审前暂停，等待用户选择 LLM/runner；
- `false`：自动执行评审；
- 自动模式下没有 `defaultModel` 或运行时 `review_llm` 时硬失败，不能静默使用当前会话模型；
- `onReplay: "reuse"`：reviewLoop 回修时复用已选模型，不重复询问；
- 用户可显式要求切换模型，切换后从当前评审轮次重新执行；
- `review-dev-plan` 与其他评审点完全共享上述语义。

评审选择节点只写执行上下文，不写 CR 状态或 `approval.yml`：

```yaml
review_context:
  stage: dev-plan
  reviewer_model: "<model-or-runner>"
  selected-by: user
  selected-at: ISO-8601
```

之后 `review-dev-plan` 将模型留痕写入临时 payload：

```yaml
dimensions:
  reviewer-model: "<model-or-runner>"
```

最终仍由：

```text
crctl review-record --stage dev-plan --bump-attempt
```

写入 `review-annotations/dev-plan.yml`、`review-loop.yml` 和 `traceability.yml#reviews.dev-plan`。

### 10.3 `review-dev-plan` 的节点位置

`code-implementation.pipeline.json` 应在 `write-dev-tasks` 后插入两个逻辑节点：

```text
write-dev-tasks
  → reviewer-selection(dev-plan)
  → review-dev-plan
  → push-progress
  → human_approval(dev-start)
```

这里的 `reviewer-selection(dev-plan)` 是评审模型选择，不是开发启动审批。

开发启动审批仍保留原有职责：

```text
review-dev-plan PASS
  → human_approval
  → crctl approve --stage dev-start
```

不得把模型选择节点当成 `approve-dev-start` 的替代品。

### 10.4 `review-dev-plan` 的 reviewLoop

按 CR-2026-026 方案复用现有 reviewLoop：

```json
{
  "ref": "review-dev-plan",
  "reviewLoop": {
    "repairRef": "write-dev-plan",
    "feedbackInput": "review_feedback",
    "attemptInput": "self_repair_attempt",
    "replayPolicy": "rerun-listed-nodes-in-order",
    "replayNodes": [
      { "ref": "write-dev-plan", "purpose": "repair-plan" },
      { "ref": "write-dev-tasks", "purpose": "regenerate-tasks" },
      { "ref": "review-dev-plan", "purpose": "rerun-current-review" }
    ],
    "maxAttempts": 3,
    "passCondition": {
      "allOf": [
        { "path": "verdict", "equals": "pass" },
        { "path": "blockers", "isEmpty": true }
      ]
    },
    "onBlock": "route-to-repair-node"
  }
}
```

回修时：

- 默认复用原评审模型；
- 不重复进入模型选择节点；
- `write-dev-plan` 消费 `review_feedback`；
- `write-dev-tasks` 重新生成 TASK 和 `_index.yml`；
- 评审记录继续由 `crctl review-record` 统一写入；
- 三轮仍未通过时停止，不进入开发启动 `human_approval`。

### 10.5 状态和门禁兼容性

不新增状态，沿用 CR-2026-026 方案：

```text
PASS：
task-breakdown
  → 现有开发启动人工审批

BLOCK：
task-breakdown
  → tech-design-reviewed
  → write-dev-plan
  → write-dev-tasks
  → reviewer-selection(dev-plan)
  → review-dev-plan
```

需要增加的门禁：

- `approve-dev-start` 必须校验 `review-annotations/dev-plan.yml`；
- 必须满足 `verdict=pass` 且 `blockers=[]`；
- `plan.md`、`tasks/_index.yml` 和至少一个 TASK 文件必须存在；
- dev-start evidence digest 至少覆盖：
  - `review-annotations/dev-plan.yml`
  - `plan.md`
  - `tasks/_index.yml`

评审失败时不得直接进入 `human_approval`，也不得把 blocker 留给 `implement-code`。

### 10.6 具体实施顺序

按 tools 现有“先声明、后执行、统一 crctl 落盘”的方式实施：

1. 在 `skills/_index.yml` 登记 `review-dev-plan`；
2. 新增 `skills/develop/review-dev-plan/SKILL.md`；
3. 在 `agent-skill-matrix.yml` 为现有开发角色登记 `review-dev-plan`；
4. 在 `code-implementation.pipeline.json` 插入：
   - `reviewer-selection(dev-plan)`；
   - `review-dev-plan`；
   - `reviewLoop` 和 `replayNodes`；
5. 将统一 `reviewSelection` 配置扩展为四个阶段：
   - requirement；
   - tech-design；
   - dev-plan；
   - code；
6. 扩展 `write-dev-plan`、`write-dev-tasks` 的回修输入；
7. 在 `crctl` 的 `REVIEW_STAGE_*` 映射中加入：

   ```text
   stage: dev-plan
   annotation: review-annotations/dev-plan.yml
   loop: review-dev-plan
   repair-target: write-dev-plan
   ```

8. 在 `gates.json` 增加：
   - `review-dev-plan` loop；
   - dev-start approval 的 dev-plan passCondition；
   - developing 目标态的完整 plan/TASK/dev-plan 门禁；
9. 在目标 workspace 的 `dir-graph.yaml` 增加：

   ```text
   task-breakdown
     → tech-design-reviewed
     trigger: review-dev-plan:block -> write-dev-plan
   ```

10. 增加测试：
    - 默认 `pauseBeforeReview=true`；
    - `pauseBeforeReview=false` 且无模型时硬失败；
    - 四个阶段均能记录 `reviewer-model`；
    - reviewLoop 回修不重复询问模型；
    - `dev-plan` stage 的 review-record、traceability 和 gate 投影一致；
    - blocker 未清空时 `approve-dev-start` 返回 `GATE_BLOCKED`；
    - 三轮耗尽返回 `LOOP_EXHAUSTED`；
    - 现有 requirement/tech/code review 行为不回归。

### 10.7 实施边界

本方案不把 `review-dev-plan` 做成独立人工审批，也不新增第二套评审账本。

保持现有分层：

```text
LLM：评审判断 + 临时 payload
review-record：schema、身份、时间、轮次、canonical annotation、traceability
crctl：状态转换、门禁、审批和证据摘要
human_approval：模型选择或最终开发启动确认
```

因此，`review-dev-plan` 只是把 CR-2026-026 已定义的编码前质量门禁接入统一评审暂停协议，不改变 tools 的核心状态机和证据模型。

## 11. PRD 编写与需求评审流程优化

### 11.1 分析对象与核心结论

本节基于：

```text
change-requests/CR-2026-026/PRD编写过程操作记录.md
change-requests/CR-2026-026/PRD评审过程操作记录.md
```

PRD 编写共发生 9 次工具调用，第一次需求评审共发生 6 次工具调用。15 次调用中，真正必须由 LLM 完成的核心语义工作只有两类：

1. 根据 CR 摘要、来源文档和已确认边界生成或修订 PRD；
2. 根据 PRD 内容形成评审 verdict、blockers、dimensions 和 suggestions。

其余调用主要是：

- Skill 和路径探测；
- worktree、状态和文件存在性校验；
- 模板或历史先例查找；
- schema 实现查询；
- frontmatter、时间戳、统计信息生成；
- `_backlog.yml` 登记；
- Git add、commit 和 log；
- canonical 账本写入后的重复读取验证；
- PASS/BLOCK 后的状态路由和下一步计算。

这些操作具有明确输入、固定规则和可验证输出，应下沉到版本化代码中执行。优化目标不是减少质量门禁，而是缩小 LLM 接口，使模型只承担语义判断。

目标调用规模：

| 流程 | 当前调用 | 优化目标 | 降幅 |
|---|---:|---:|---:|
| PRD 编写 | 9 | 3 | 约 67% |
| PRD 评审 | 6 | 2–3 | 约 50%–67% |
| 合计 | 15 | 5–6 | 约 60%–67% |

该指标只约束外部工具调用和 LLM 往返次数，不以牺牲状态机、CAS、审计或人工审批为代价。

### 11.2 PRD 编写流程中的效率问题

#### 11.2.1 协议发现占用五次调用

现有 PRD 编写过程的前五次调用依次完成：

1. 检查 `write-requirement-prd` Skill 是否存在；
2. 检查 worktree 中 CR 目录；
3. 查找最近 CR 的 PRD；
4. 读取 Skill 协议；
5. 读取最近 PRD 全文。

其中只有目标 CR、来源文档和已有回修反馈属于本次 PRD 的必要内容。其余问题如下：

- Skill 是否存在应由 Skill/Pipeline 加载器保证；
- knowledge-base worktree 已由注册流程创建并输出，不应由模型再次猜测和验证；
- “最近一个 PRD”不是权威协议，可能把历史文档中的临时结构、错误或旧约定传播到新 CR；
- Skill 结构、frontmatter 和章节要求应由版本化模板提供，而不是依赖历史先例；
- 每次会话重新读取完整 Skill 和先例会产生固定延迟，且内容越长成本越高。

优化后，模型不再执行 Skill 存在性检查和历史 PRD 搜索，只消费一次性准备好的 PRD 上下文。

#### 11.2.2 PRD 与 backlog 登记被拆成两个提交

当前流程：

```text
写 prd.md
→ git add/commit prd.md
→ crctl backlog-set prd-path
→ git add/commit _backlog.yml
→ git log 核对
```

这产生两个业务上不可分割的提交，并留下短暂的不一致窗口：

- PRD 已存在，但 `_backlog.yml` 尚未登记 `prd-path`；
- 首次提交成功、第二次提交失败时，需要人工判断如何恢复；
- push-progress 必须理解并推送两次提交；
- `git log` 只是为了确认刚执行的提交，属于冗余验证。

目标流程应调整为：

```text
写 prd.md
→ 校验 PRD
→ crctl backlog-set prd-path
→ 显式暂存 prd.md + _backlog.yml
→ 单次 commit
```

提交结果由确定性 Runner 直接返回 commit SHA，不再额外执行 `git log`。

#### 11.2.3 frontmatter 仍由 LLM 手工生成

`write-requirement-prd` 要求模型填写：

- `id`；
- `type`；
- `cr-ref`；
- title、target-version、owner；
- created、updated；
- status。

除正文标题和业务字段外，这些值都可以从 `cr.md`、identity 和当前时间确定性生成。让模型生成会带来：

- 时间格式不一致；
- owner 或 target-version 从错误 workspace 读取；
- 创建时间在回修时被意外覆盖；
- `cr-ref` 与目录 CR-ID 不一致；
- Skill、模板和 schema 约定漂移。

应由文档 Runner 生成或保护 frontmatter，LLM 只写正文和必要的业务内容。

### 11.3 需求评审流程中的效率问题

#### 11.3.1 评审协议泄漏到 `crctl.mjs`

当前评审过程需要 grep `crctl.mjs`，确认 `dimensions` 是否要求具体键名。

原因是接口声明与实现不完全一致：

- `review-requirement/SKILL.md` 声称该 stage 要求评审维度齐全；
- `cmdReviewRecord` 实际只验证 `dimensions` 是非数组映射；
- requirement 的五个维度没有机器可读的唯一事实源；
- 调用方无法仅根据 Skill 或 CLI 输出确定合法 payload。

LLM 阅读 `crctl.mjs` 属于实现泄漏。应建立机器可读的 review stage 契约，并由 `crctl` 精确校验。

#### 11.3.2 临时 payload 的机械结构仍由 LLM 编排

LLM 应负责：

- verdict；
- blocker 内容；
- 各维度结论；
- suggestions。

LLM 不应负责：

- 临时目录和文件名；
- YAML 引号与数组格式；
- stage 到 annotation 文件名映射；
- reviewer 和时间戳；
- attempt 递增；
- repair-target 默认值；
- traceability 投影结构。

现有 `crctl review-record` 已接管大部分 canonical 写入，下一步应让调用适配器直接接受结构化判断对象，由代码生成临时 payload 或通过 stdin 传入，避免模型处理机械 YAML 细节。

#### 11.3.3 三账本原子写入后再次人工复核

`crctl review-record` 已通过 `casWriteMulti` 同批写入：

```text
review-annotations/requirement.yml
review-loop.yml
traceability.yml
```

随后模型又执行 `git status` 和读取 `traceability.yml`，核对 reviewer、verdict、blocker-count、attempt 和 repair-target。

如果调用方仍需逐字段复核，说明 `review-record` 的返回接口不够深。正确做法是：

1. `review-record` 写入成功后重新解析目标文件；
2. 内部断言 annotation、review-loop 和 traceability 一致；
3. 返回 `verified: true`、写入文件、摘要、hash、attempt 和 next；
4. 一致性失败时由 `crctl` 硬失败；
5. 调用方不再手工读取账本。

#### 11.3.4 PASS 路由和提交仍分散在模型步骤中

需求评审 PASS 时还需要：

```text
review-record
→ advance requirement-reviewing
→ git add
→ commit
→ crctl next
```

BLOCK 时需要：

```text
review-record
→ 保持 drafting
→ git add
→ commit
→ 输出 repair-target
```

这些分支都可由确定性 Runner 根据 canonical verdict 处理。LLM 不应自行决定是否调用 `advance`，只负责评审判断。

### 11.4 合并与批量处理机会

#### 11.4.1 PRD 上下文一次准备

新增：

```text
skills/requirement/write-requirement-prd/scripts/prepare.mjs
```

一次完成：

- 调用 `crctl worktree-path` 解析 knowledge-base worktree；
- 验证 worktree 存在且分支为 `requirement/{CR-ID}`；
- 校验权威 `cr.md.status=drafting`；
- 并行读取：
  - `cr.md`；
  - source 文档；
  - `_config.yml`；
  - 现有 `prd.md`；
  - 上一轮 requirement annotation；
- 生成受保护 frontmatter；
- 输出规范化 JSON 上下文。

示例：

```json
{
  "cr": "CR-2026-026",
  "workspace": "C:/.../.rayai-worktrees/knowledge-base/requirement/CR-2026-026",
  "mode": "create",
  "status": "drafting",
  "metadata": {
    "title": "...",
    "targetVersion": "...",
    "owner": "..."
  },
  "source": {
    "path": "docs/analysis/...",
    "content": "..."
  },
  "reviewFeedback": null,
  "frontmatter": {
    "created": "...",
    "updated": "..."
  }
}
```

模型通过一次读取获得全部上下文，不再分别探测文件和协议。

#### 11.4.2 PRD 收尾一次完成

新增：

```text
skills/requirement/write-requirement-prd/scripts/finalize.mjs
```

职责：

1. 确认目标文件位于权威 knowledge-base worktree；
2. 校验 frontmatter 与 CR 元数据一致；
3. 校验必要章节存在；
4. 统计 US、FR、NFR、AC；
5. 调用 `crctl backlog-set`；
6. 通过 `crctl git` 显式暂存 `prd.md` 和 `_backlog.yml`；
7. 使用统一 commit template 提交；
8. 返回 SHA 和 `crctl next`。

建议为 `crctl git commit --template` 增加：

```text
prd-draft
requirement-review
```

生成满足 controlled-shell 白名单的规范提交消息。

#### 11.4.3 评审上下文一次准备

新增：

```text
skills/requirement/review-requirement/scripts/prepare.mjs
```

一次返回：

- PRD 全文；
- source 文档；
- 当前 CR status；
- 当前 attempt/maxAttempts；
- 上一轮评审记录；
- 必需评审维度；
- 当前 PRD 的 LF 规范化 SHA-256；
- 允许的 verdict、repair-target 和 payload 形状。

模型只对该上下文作语义评审。

#### 11.4.4 评审收尾一次完成

新增：

```text
skills/requirement/review-requirement/scripts/finalize.mjs
```

职责：

1. 接受 LLM 的结构化判断；
2. 生成或写入临时 payload；
3. 调用 `crctl review-record --stage requirement --bump-attempt`；
4. 由 `crctl` 内部完成三账本写后自检；
5. PASS 时调用：

   ```text
   crctl advance --to requirement-reviewing --trigger review-requirement --embedded
   ```

6. BLOCK 时保持或确认 `drafting`；
7. 显式暂存评审证据及可能变更的 `cr.md`；
8. 单次提交；
9. 返回 verdict、attempt、repair-target、commit SHA 和 next。

优化后的调用序列：

```text
1. prepare review context
2. LLM 生成评审判断
3. finalize review
```

如果运行时支持结构化工具参数，步骤 2 的结果可以直接传给 finalize，不必让 LLM Write 临时 YAML。

### 11.5 review stage 契约的单一事实源

建议在 `skills/shared/crctl/gates.json` 中增加 `reviewStages` 段，作为全部评审 stage 的机器可读权威定义：

```json
{
  "reviewStages": {
    "requirement": {
      "expectedStatuses": [
        "drafting",
        "requirement-reviewing"
      ],
      "annotationFile": "requirement.yml",
      "loop": "review-requirement",
      "repairTarget": "write-requirement-prd",
      "subjectFile": "prd.md",
      "requiredDimensions": [
        "结构完整性",
        "FR 可测试性",
        "范围合理性",
        "与规划对齐",
        "依赖识别"
      ]
    }
  }
}
```

现有常量：

```text
REVIEW_STAGE_FILES
REVIEW_STAGE_EXPECT
REVIEW_STAGE_LOOPS
REVIEW_REPAIR_TARGETS
```

应从该结构加载或通过启动时一致性断言保持同步，避免 Skill、Pipeline 和 `crctl` 各自维护一份。

`review-record` 应验证：

- required dimensions 全部存在；
- 未知维度按策略拒绝或记录 warning；
- `verdict=pass` 时 `blockers=[]`；
- `verdict=block` 时至少有一个 blocker；
- stage 对应 subject 文件存在；
- subject hash 使用 CRLF→LF 规范化后计算。

### 11.6 Pipeline 结构化上下文

当前 `requirement-register` 在 `node-1.md` 末尾输出 YAML，后续节点再读取 Markdown 并解析 `execution_context`。

该设计同时承担：

- 人类摘要；
- 机器状态传递；
- worktree 路径事实源；
- owner 数据传递。

建议拆分：

```text
node-1.md
  人类可读摘要

.crctl/runtime/{CR-ID}/execution-context.json
  机器可读上下文
```

短期由 `requirement-register/scripts/register.mjs` 生成 JSON，后续节点读取固定路径。

长期由 Pipeline runtime 支持声明式 outputs：

```json
{
  "outputs": {
    "crId": {
      "type": "string"
    },
    "knowledgeBaseWorktree": {
      "type": "path"
    },
    "owners": {
      "type": "object"
    }
  }
}
```

后续节点直接绑定：

```text
{{nodes.register.outputs.crId}}
{{nodes.register.outputs.knowledgeBaseWorktree}}
```

不得继续依赖从自然语言 Markdown 中恢复关键运行参数。

### 11.7 engineering-docs 的兼容治理

当前 `engineering-docs` 存在三套未完全对齐的模型：

1. `write-requirement-prd` 使用 CR 工作台路径和 `CR-YYYY-NNN-prd` frontmatter；
2. `engineering-docs/templates/PRD-template.md` 使用通用产品文档模型；
3. `engineering-docs/schemas/prd.schema.json` 要求 `PRD-NNN`、`name`、`refs` 和日期格式。

因此不应简单恢复旧 MCP 或直接用通用 schema 校验 CR PRD。

推荐先定义 CR 产物专用 schema：

```text
skills/shared/engineering-docs/schemas/cr-prd.schema.json
skills/shared/engineering-docs/templates/CR-PRD-template.md
```

最小字段包括：

```yaml
id: CR-YYYY-NNN-prd
type: PRD
cr-ref: CR-YYYY-NNN
title: string
target-version: string
owner: string
owner-role: requirement
status: draft
created: ISO-8601 with offset
updated: ISO-8601 with offset
```

只恢复最小本地 renderer/validator：

```text
render CR-PRD frontmatter
validate CR-PRD frontmatter
```

不恢复常驻 MCP server，不自动分配新的 PRD-ID，也不改变 `change-requests/{CR-ID}/prd.md` 的路径契约。

### 11.8 过度设计评估

#### 11.8.1 不新增通用 YAML patch

现有 `backlog-set`、`owner-set`、`checkpoint-add` 等 purpose-specific 子命令符合账本治理原则。不得为了减少调用增加：

```text
crctl patch <file> <json-path> <value>
```

通用 patch 会扩大受控写面，削弱字段级 gate 和审计语义。

#### 11.8.2 不把全部流程塞进单个 crctl 命令

不建议新增：

```text
crctl run-requirement-pipeline
```

该命令会把语义生成、评审循环、状态推进和人工审批隐藏进一个大接口，使失败恢复和审计更困难。

应保持三层职责：

```text
crctl：权威原语
Skill Runner：确定性阶段编排
LLM：语义内容与判断
```

Pipeline 只编排三层能力及人工审批，不复制状态机、gate、schema 或 Skill 内部确定性步骤。

#### 11.8.3 不自动选择历史 PRD 作为模板

历史 PRD 只能在以下情况下按需读取：

- 用户明确要求保持某个 CR 的结构；
- 当前需求需要引用该 CR 的事实或决策；
- review feedback 指向历史兼容性。

不得默认读取“最近一个 CR”，也不需要构建 PRD 相似度检索系统。

#### 11.8.4 不用正则代替需求评审

代码可做：

- 章节存在性检查；
- FR/AC 编号统计；
- 未引用 FR 的候选提示；
- frontmatter 校验；
- source 路径和 hash 校验。

代码不能替代：

- 需求是否合理；
- AC 是否真正覆盖业务语义；
- 边界是否正确；
- blocker 与 suggestion 的严重度判断；
- 与规划目标是否实质一致。

机械检查只能作为评审上下文，不得直接生成最终 verdict。

#### 11.8.5 暂不并行创建 worktree

当前 workspace 的 active repo 数量较少。并行 `worktree add` 需要处理：

- 部分成功；
- 分支已存在；
- 本地路径已占用；
- fetch 成功但 add 失败；
- 清理补偿。

在没有实际耗时数据证明其为主要瓶颈前，优先完成上下文批量读取和提交合并。worktree 并行化保持为后续可选项。

### 11.9 推荐实施顺序

#### P0：协议与提示词收敛

修改：

```text
skills/requirement/write-requirement-prd/SKILL.md
skills/requirement/review-requirement/SKILL.md
pipeline-templates/requirement-authoring.pipeline.json
```

内容：

1. 删除 Skill 存在性检查；
2. 删除默认历史 PRD 读取；
3. 删除 review 后人工 traceability 对账；
4. 删除 requirement-register prompt 中重复的 `cr-init` 动作；
5. 明确标记 semantic 与 deterministic 步骤；
6. 修正 `cr_id`、source 等输入描述与实际语义不一致；
7. 明确所有后续节点只接受权威 worktree 上下文。

#### P1：PRD prepare/finalize Runner

新增：

```text
skills/requirement/write-requirement-prd/scripts/prepare.mjs
skills/requirement/write-requirement-prd/scripts/finalize.mjs
```

并增加对应单元测试。

#### P1：评审 prepare/finalize Runner

新增：

```text
skills/requirement/review-requirement/scripts/prepare.mjs
skills/requirement/review-requirement/scripts/finalize.mjs
```

扩展 `review-record` 返回值和内部一致性自检。

#### P1：review stage 契约代码化

修改：

```text
skills/shared/crctl/gates.json
skills/shared/crctl/scripts/crctl.mjs
skills/shared/crctl/scripts/test/crctl.test.mjs
```

增加 required dimensions、subject 文件和 stage 元数据的单一事实源。

#### P2：注册流程 Runner 与结构化输出

新增：

```text
skills/requirement/requirement-register/scripts/register.mjs
```

将 repositories 解析、注册提交、worktree 派生和 execution context 输出从 LLM prompt 下沉到代码。

#### P2：CR PRD 专用 renderer/validator

新增：

```text
skills/shared/engineering-docs/templates/CR-PRD-template.md
skills/shared/engineering-docs/schemas/cr-prd.schema.json
```

提供最小本地渲染和校验能力，不恢复旧 MCP。

### 11.10 测试计划

#### PRD prepare

- 主 workspace 与 worktree status 不一致时指向权威 worktree；
- worktree 缺失时硬失败；
- `cr.md.status` 非 drafting 时硬失败；
- source 缺失和 source 可选两种路径；
- 首次创建与已有 PRD 编辑模式；
- review feedback 存在时正确加载；
- CRLF 输入统一规范化。

#### PRD finalize

- PRD 与 `_backlog.yml` 在同一 commit；
- `prd-path` 已存在时幂等；
- frontmatter CR-ID 不一致时拒绝；
- created 保持、updated 更新；
- 必需章节缺失时拒绝提交；
- Git commit 失败时输出明确重试状态；
- 不使用 `git add -A`。

#### review prepare/finalize

- requirement 五个维度全部要求存在；
- verdict 与 blockers 组合合法性；
- PASS 从 drafting 推进 requirement-reviewing；
- requirement-reviewing 自环重审合法；
- BLOCK 保持 drafting；
- attempt 递增与 LOOP_EXHAUSTED；
- annotation、review-loop、traceability 内部自检；
- subject SHA 使用 LF 规范化；
- payload 失败时保留供重试；
- finalize 单次提交评审证据和状态变更。

#### register Runner

- `cr-init` 仅调用一次；
- CR-ID CAS 冲突时可重试；
- trunk 未解析时零写入；
- registration commit 先于 worktree 创建；
- worktree 已存在时幂等返回；
- 多 repo 中一个失败时输出完整成功/失败清单；
- execution-context JSON 与实际路径、branch、owners 一致。

#### 回归测试

- 15 个具名状态与注册前 `(new)` 口径不变；
- 25 条声明转换、wildcard 展开后 47 条口径不变；
- 所有人工审批仍只经 `crctl approve`；
- `STATUS_DIVERGED` 行为不回归；
- `_backlog.yml`、review-loop 和 traceability 仍由受控命令写入；
- 现有 requirement、tech-design、dev-plan、code review 行为不回归。

### 11.11 轻量度量

每个 Runner 输出统一执行摘要：

```json
{
  "op": "write-requirement-prd.finalize",
  "durationMs": 1234,
  "filesRead": 4,
  "filesWritten": 2,
  "commitSha": "abcdef1",
  "status": "drafting",
  "next": "review-requirement"
}
```

首期只输出到 stdout 和既有 audit log，不增加数据库、后台服务或远程遥测。

对比指标：

- 每阶段外部工具调用数；
- 失败或探索性调用数；
- 重复读取文件数；
- Git commit 数；
- LLM 输入上下文字数；
- prepare、semantic、finalize 各阶段耗时。

### 11.12 最终目标流程

#### PRD 编写

```text
1. prepare.mjs
   → 解析权威 worktree
   → 批量读取上下文
   → 生成受保护 frontmatter

2. LLM
   → 生成或定点修订 PRD 正文

3. finalize.mjs
   → 校验
   → backlog-set
   → 单次 commit
   → 输出 next
```

#### PRD 评审

```text
1. prepare.mjs
   → 读取 PRD/source/review contract/attempt

2. LLM
   → 输出 verdict/blockers/dimensions/suggestions

3. finalize.mjs
   → review-record
   → 三账本自检
   → PASS/BLOCK 路由
   → 单次 commit
   → 输出 next
```

### 11.13 成功标准

优化完成后应满足：

- PRD 编写最多 3 次外部调用；
- PRD 评审最多 3 次外部调用；
- 不再由 LLM 检查 Skill 是否存在；
- 不再默认读取最近历史 PRD；
- 不再 grep `crctl.mjs` 理解 payload schema；
- PRD 与 `prd-path` 在同一 commit；
- 评审三账本写入后不再由模型重复读取核对；
- PASS/BLOCK 路由由确定性 Runner 执行；
- LLM 只负责 PRD 语义内容和评审语义判断；
- 所有状态推进继续经过 `crctl` 状态机和 gate；
- 人工需求审批、开发启动审批和代码审批不被自动化绕过；
- CRLF 规范化、CAS、多账本一致写和审计能力全部保留。

## 12. SDD、Plan/TASK 撰写与评审流程优化

### 12.1 分析对象与调用规模

本节基于：

```text
change-requests/CR-2026-026/SDD撰写工具调用.md
change-requests/CR-2026-026/SDD评审过程操作记录.md
change-requests/CR-2026-026/PlanTask撰写评审过程操作记录.md
```

记录中的调用规模：

| 阶段 | 已记录调用 | 说明 |
|---|---:|---|
| SDD 撰写 | 14 | 包含需求审批交接、状态推进、上下文读取和提交 |
| SDD BLOCK 回修与 attempt-2 重审 | 10 | attempt-1 由用户终端执行，不计入这 10 次 |
| Plan/TASK 撰写 | 11 | 包含技术设计审批交接、拆分、索引和状态推进 |
| Plan/TASK 评审 | 0 | 仅会话内分析，没有 canonical review-record |

“Plan/TASK 评审 0 调用”不是效率成果，而是证据链缺失。后续 `review-annotations/dev-plan.yml` 明确记录为回顾性例外落盘，且没有同步 review-loop 和 traceability。正常 CR 不得复制此模式。

真正需要 LLM 执行的语义工作包括：

- 依据 PRD、架构事实和代码基线设计 SDD；
- 根据 blocker 定点修订 SDD；
- 将 SDD 转化为里程碑、风险和发布计划；
- 按模块边界和依赖拆分 TASK；
- 判断 SDD、Plan、TASK 的质量与范围；
- 形成技术评审和开发计划评审的 verdict、blockers 和 suggestions。

以下步骤应由代码执行：

- 审批证据和状态交接；
- worktree、目标仓和 Skill 路径解析；
- ARCHITECTURE、Pipeline、gates 和评审记录的批量读取；
- frontmatter 生成与保护；
- FR 覆盖率、TASK 索引、工时、依赖图和接口签名校验；
- 状态推进、账本写入和 Git 提交；
- review-record 后的三账本一致性自检；
- PASS、NORMAL、UPSTREAM 路由。

优化目标：

| 阶段 | 当前调用 | 目标调用 |
|---|---:|---:|
| SDD 撰写 | 14 | 4–6 |
| SDD 回修与重审 | 10 | 4–6 |
| Plan/TASK 撰写 | 11 | 4–5 |
| Plan/TASK canonical 评审 | 0（缺证据） | 2–3 |

### 12.2 根因问题一：`crctl approve` 的提交边界过浅

需求审批和技术设计审批后都出现：

```text
crctl approve 已生成 approval.yml 并推进状态
→ approval.yml 留在未提交状态
→ 下一阶段手工 git add/commit approval.yml
```

SDD 撰写记录中，需求审批状态提交和 `approval.yml` 分成两个提交；Plan/TASK 撰写记录中，技术设计审批再次出现相同情况。

当前实现的根因：

1. `cmdApprove` 先调用 `writeApprovalSection` 写 `approval.yml`；
2. 随后调用 `cmdAdvance`；
3. `cmdAdvance` 默认只暂存和提交 `cr.md`；
4. `approval.yml` 不在该提交内。

这导致：

- 审批记录与审批状态并非同一个业务原子提交；
- 后续 Skill 必须检查并补交 approval；
- safe.directory 或 Git 错误会把补交责任转移给用户；
- `git log` 被用来恢复刚发生的审批事实；
- approval 已生效但证据文件尚未进入分支历史。

#### 12.2.1 优化方案

将 `crctl approve` 深化为完整审批原语：

```text
gate 校验
→ 人类 TTY 或签名 grant 确认
→ 写 approval.yml
→ embedded 状态推进
→ 显式暂存 approval.yml + cr.md
→ 单次 commit
→ 用真实 commit SHA 写审计/outbox
```

要求：

- 人工在环规则不变；
- grant 验签规则不变；
- evidence-digest 规则不变；
- approval 和状态推进任一步失败都输出明确恢复状态；
- 不允许自动修改用户全局 `safe.directory` 配置；
- controlled Git 可以使用当前 worktree 的命令级安全配置或返回结构化修复提示；
- 审批完成后下一阶段不再补提交 approval.yml。

#### 12.2.2 验收

- requirement、tech-design、dev-start、code 四种审批均一次提交；
- 提交同时包含 `approval.yml` 和 `cr.md`；
- 下一阶段启动时 worktree clean；
- 不再执行 `git log` 确认刚完成的审批；
- approval 与状态不出现分离提交。

### 12.3 根因问题二：embedded 状态变更被拆成独立提交

SDD 撰写完成后：

```text
提交 sdd.md
→ crctl advance --embedded
→ 单独提交 cr.md
```

SDD 回修重入评审态和 Plan/TASK 进入 task-breakdown 时也重复该模式。

`--embedded` 的设计目的本来就是让状态与同一业务产物进入一个提交。当前调用顺序却先提交产物，再 embedded advance，再提交状态，等于失去 embedded 的收益。

#### 12.3.1 优化原则

Runner 必须采用：

```text
产物已落盘但未提交
→ crctl advance --embedded
→ 显式暂存产物 + cr.md + 必要账本
→ 单次 commit
```

适用场景：

| Skill | 转换 | 同一提交中的文件 |
|---|---|---|
| write-tech-design 初次进入 | requirement-approved → tech-designing | 可只在 prepare 阶段保持未提交，最终与 sdd.md 一起提交 |
| write-tech-design 完成 | tech-designing → tech-design-review-pending | sdd.md、cr.md、必要 ARCHITECTURE.md |
| write-tech-design 回修完成 | tech-designing → tech-design-review-pending | sdd.md、cr.md |
| write-dev-tasks 完成 | tech-design-reviewed → task-breakdown | plan.md、tasks/、cr.md |
| review-dev-plan NORMAL | task-breakdown → tech-design-reviewed | cr.md、review evidence |
| review-dev-plan UPSTREAM | task-breakdown → tech-design-review-pending | cr.md、review evidence |

初次 `write-tech-design` 进入 `tech-designing` 时，需要保证状态在生成过程中已写入权威 `cr.md`。Runner 可以先 embedded 写状态，生成失败时保留可恢复的 `tech-designing` 状态；成功后与 SDD 同一提交。不得为减少提交而在 `requirement-approved` 状态直接生成并提交 SDD。

### 12.4 SDD 撰写流程中的效率问题

#### 12.4.1 Skill 路径探索失败

记录先查找：

```text
skills/architecture
```

随后才通过 Glob 找到：

```text
skills/develop/write-tech-design/SKILL.md
```

Skill 位置已由 `skills/_index.yml` 和 agent-skill matrix 声明，模型不应自行猜分组目录。

优化：

- Pipeline runtime 按 `ref=write-tech-design` 加载 Skill；
- Runner 接收已解析的 Skill root；
- 只允许从 `skills/_index.yml` 解析 active Skill；
- 找不到时由加载器返回 `SKILL_NOT_REGISTERED`，不进行全仓 Glob。

#### 12.4.2 默认读取最近 SDD 先例

最近 CR 的 SDD 不是权威设计模板。默认读取会：

- 增加长文档输入；
- 把旧 CR 的技术选择带入新 CR；
- 隐藏模板和当前规范之间的漂移；
- 让“最近”这一非业务关系影响设计。

应只读取：

- 当前 CR 的 PRD；
- 当前目标仓的 ARCHITECTURE.md；
- 当前变更触及的真实实现文件；
- 当前 Pipeline 与 gates；
- 上一轮本 CR 评审记录。

历史 SDD 仅在用户明确要求保持兼容或本 CR 引用该历史设计时读取。

#### 12.4.3 上下文读取分散

SDD 撰写分别读取：

- Skill；
- ARCHITECTURE.md；
- code-implementation pipeline；
- crctl 目录；
- gates.json。

其中 ARCHITECTURE、Pipeline、gates 和代码事实之间没有顺序依赖，应由 Runner 并行读取。

新增：

```text
skills/develop/write-tech-design/scripts/prepare.mjs
```

职责：

1. 调用 `crctl` 解析权威 worktree 和当前状态；
2. 从 `dir-graph.yaml#repositories` 解析目标代码仓；
3. 定位目标仓 ARCHITECTURE.md；
4. 定位与 CR 相关的 Pipeline、gates 和 Skill；
5. 批量读取 PRD、架构约束、相关实现文件和上一轮评审；
6. 输出规范化设计上下文；
7. 初次进入时调用 `advance --embedded` 写入 `tech-designing`；
8. 不提交，由 finalize 统一处理。

输出示例：

```json
{
  "op": "write-tech-design.prepare",
  "cr": "CR-2026-026",
  "mode": "create",
  "status": "tech-designing",
  "worktree": "C:/.../requirement/CR-2026-026",
  "targetRepositories": [
    {
      "id": "tools",
      "path": "C:/.../tools",
      "architecture": "C:/.../tools/ARCHITECTURE.md"
    }
  ],
  "prd": {
    "path": "change-requests/CR-2026-026/prd.md",
    "sha256": "..."
  },
  "reviewFeedback": null,
  "requiredSections": [
    "架构概览",
    "数据模型",
    "接口契约",
    "关键算法与流程",
    "技术选型与替代方案",
    "FR 映射",
    "安全与性能"
  ],
  "promptAdoptionRequired": true
}
```

#### 12.4.4 FR 覆盖率由 LLM 自报

记录中的“FR 全覆盖 24/24”由模型生成。该结论应由代码验证：

1. 从 PRD 提取全部 FR 标识；
2. 从 SDD FR 映射章节提取引用；
3. 输出 missing、duplicate、unknown；
4. 覆盖率不是 100% 时 finalize 失败；
5. 支持 `FR-6a`、`FR-6b` 等非纯数字编号；
6. 解析失败必须硬失败，禁止空数组降级。

新增：

```text
skills/develop/write-tech-design/scripts/validate-sdd.mjs
```

必须遵守 CRLF→LF 规范化和跨行解析失败硬失败规则。

#### 12.4.5 SDD finalize

新增：

```text
skills/develop/write-tech-design/scripts/finalize.mjs
```

职责：

- 校验 frontmatter；
- 校验 PRD→SDD FR 覆盖；
- 校验必要章节；
- 条件性校验 Prompt 采纳影响；
- 调用 `crctl advance --embedded` 进入 tech-design-review-pending；
- 显式暂存 `sdd.md`、`cr.md` 和新建的目标仓 ARCHITECTURE.md；
- 单次 commit；
- 输出 commit SHA、覆盖率和 next。

### 12.5 SDD 回修与技术评审流程优化

#### 12.5.1 回修准备一次完成

当前 BLOCK 后分别执行：

```text
git status
crctl status
Read review-annotations/sdd.yml
```

新增：

```text
skills/develop/write-tech-design/scripts/prepare-repair.mjs
```

一次返回：

- 当前状态；
- dirty files；
- blocker；
- repair-instructions；
- attempt/maxAttempts；
- 上一轮 subject hash；
- 当前 SDD hash；
- fixed-blockers 输出契约。

若 review feedback 已由 Pipeline 结构化传入，Runner 只校验与 canonical annotation 一致，不重复从自然语言节点恢复。

#### 12.5.2 回修提交禁止 `git add -A`

SDD 回修提交曾把 `CONTEXT.md` 和多份账本一起纳入。Runner 必须维护显式允许列表：

```text
change-requests/{cr}/sdd.md
change-requests/{cr}/cr.md
目标仓新建或修订的 ARCHITECTURE.md
```

上一轮评审证据本身不应与 SDD 回修混入同一新提交，除非它们此前确实未提交且 Runner 能证明属于同一 CR。不能通过 `git add -A` 自动吸收遗留文件。

#### 12.5.3 技术评审 prepare/finalize

新增：

```text
skills/develop/review-tech-design/scripts/prepare.mjs
skills/develop/review-tech-design/scripts/finalize.mjs
```

`prepare.mjs` 批量返回：

- PRD；
- SDD；
- 目标仓 ARCHITECTURE.md；
- 当前状态；
- review stage 契约；
- attempt；
- 上一轮 annotation；
- Pipeline reviewLoop；
- Prompt 采纳影响是否触发；
- SDD subject SHA。

LLM 只输出：

```json
{
  "verdict": "pass",
  "blockers": [],
  "dimensions": {
    "prd-sdd-alignment": "pass",
    "architecture": "pass",
    "data-model": "pass",
    "interface-contracts": "pass",
    "performance-security": "pass",
    "testability": "pass",
    "prompt-adoption": "pass"
  },
  "suggestions": []
}
```

`finalize.mjs`：

1. 将结构化判断交给 `crctl review-record`；
2. 由 `review-record` 三账本写后自检；
3. PASS 时保持 tech-design-review-pending；
4. BLOCK 时调用 embedded 回退到 tech-designing；
5. 显式暂存 annotation、review-loop、traceability 和可能变化的 cr.md；
6. 单次提交；
7. 返回 next。

#### 12.5.4 review-record 返回接口深化

`review-record` 当前已经完成大部分确定性工作，但接口仍使调用方需要自行判断文件和下一步。建议返回：

```json
{
  "op": "review-record",
  "cr": "CR-2026-026",
  "stage": "tech-design",
  "verdict": "pass",
  "attempt": 2,
  "verified": true,
  "annotation": "change-requests/CR-2026-026/review-annotations/sdd.yml",
  "traceability": "change-requests/CR-2026-026/traceability.yml",
  "reviewLoop": "change-requests/CR-2026-026/review-loop.yml",
  "subjectSha256": "...",
  "repairTarget": "write-tech-design",
  "next": "crctl approve --stage tech-design"
}
```

写后自检失败时返回非零退出，不让 Skill 再读账本进行二次判断。

### 12.6 Plan/TASK 撰写流程中的效率问题

#### 12.6.1 Plan 与 TASK Skill 分开读取

`write-dev-plan` 和 `write-dev-tasks` 是连续节点，后者必然消费前者产物。Pipeline 可以在进入 code-implementation 时一次加载二者的结构契约，避免模型先后读取两份 Skill。

建议新增共享上下文：

```text
skills/develop/shared/plan-task-contract.json
```

仅声明两类文档共同的机器可读字段：

- frontmatter 字段；
- TASK ID 和 slug 规则；
- estimate 单位；
- depends-on 格式；
- 必需章节；
- index 字段。

语义说明仍保留在各自 Skill，不把两个 Skill 合并成一个大 Skill。

#### 12.6.2 Plan frontmatter 与估算汇总代码化

新增：

```text
skills/develop/write-dev-plan/scripts/prepare.mjs
skills/develop/write-dev-plan/scripts/finalize.mjs
```

`prepare` 返回：

- SDD；
- SDD annotation；
- target-version；
- 当前状态；
- review feedback；
- 已有 plan；
- 允许的回修范围。

`finalize`：

- 生成或保护 frontmatter；
- 校验里程碑、依赖、风险、验收章节；
- 提取每个里程碑估算；
- 计算总工时；
- 暂不单独提交，允许与 TASK 一起形成业务原子提交。

默认情况下，`write-dev-plan` 不需要独立 commit。Plan 是 TASK 拆分的中间产物，应与 TASK 和 task-breakdown 状态一起提交。只有用户明确要求 checkpoint 或 Pipeline 在 plan 与 TASK 之间存在人工确认时才单独提交。

#### 12.6.3 TASK 内容可并行，索引必须确定性生成

当前 TASK 按三批写入的方式合理：

```text
TASK-01、TASK-02
→ TASK-03、TASK-04
→ TASK-05、TASK-06、TASK-07
```

应保留同层并行，但以下内容由代码统一生成或验证：

- TASK 编号；
- `id`；
- slug；
- status=pending；
- plan-ref；
- sdd-ref；
- `_index.yml`；
- estimate 总和；
- dependency graph；
- interface contract 交叉引用。

LLM 输出 TASK 草稿对象：

```json
{
  "title": "实现 dev-plan review stage",
  "slug": "dev-plan-review-stage",
  "estimateHours": 12,
  "dependsOn": [],
  "description": "...",
  "files": ["..."],
  "implementation": "...",
  "acceptance": ["..."],
  "contracts": {
    "consumes": [],
    "produces": []
  }
}
```

Runner 分配 TASK-ID 并渲染文件，避免模型手工维护编号和 frontmatter。

#### 12.6.4 TASK finalize

新增：

```text
skills/develop/write-dev-tasks/scripts/finalize.mjs
skills/develop/write-dev-tasks/scripts/validate-tasks.mjs
```

验证器执行：

1. TASK 文件数量大于零；
2. ID 连续且无重复；
3. 所有 depends-on 指向存在 TASK；
4. 依赖图无环；
5. estimate 是合法数值和单位；
6. TASK estimate 总和与 plan 一致；
7. 消费接口均由上游 TASK 产出；
8. 同名接口签名一致；
9. 不含 TBD、待定和空泛实现指令；
10. 每个 TASK 至少有两条可验证验收条件；
11. `_index.yml` 由脚本生成，不由模型自由编辑。

完成后：

```text
crctl advance --to task-breakdown --trigger write-dev-tasks --embedded
→ 显式暂存 plan.md + tasks/ + cr.md
→ crctl git commit --template task-breakdown
```

形成一个业务提交，不再拆成 plan/tasks commit 和 cr.md status commit。

### 12.7 Plan/TASK 合并评审的证据问题

#### 12.7.1 “0 次调用”不能满足质量门

记录中的八维度分析本身可以是高质量语义判断，但没有执行：

```text
write review payload
crctl review-record --stage dev-plan --bump-attempt
```

因此缺少：

- canonical `review-annotations/dev-plan.yml`；
- review-loop attempt；
- traceability 投影；
- subject hash；
- gate 可验证证据。

后续手工补写的 dev-plan annotation 明确声明：

```text
轮次账本与 traceability 不同步
```

这只能作为新能力自举期间的一次性历史例外，不能成为正常评审模式。

#### 12.7.2 正常评审流程

新增：

```text
skills/develop/review-dev-plan/scripts/prepare.mjs
skills/develop/review-dev-plan/scripts/finalize.mjs
```

`prepare` 一次读取：

- SDD；
- SDD 评审记录；
- Plan；
- `_index.yml`；
- 全部 TASK；
- 当前状态；
- attempt；
- 双轨 repair-target 契约。

同时由代码预计算：

- SDD 设计条目集合；
- Plan 里程碑集合；
- TASK ID 与依赖图；
- estimate 差异；
- 接口签名差异；
- 空验收和 TBD；
- 未被 TASK 承接的 Plan 项。

这些结果作为评审证据输入 LLM，但不直接决定 verdict。

LLM 输出八类语义判断和 repair-target：

```json
{
  "verdict": "block",
  "repairTarget": "write-dev-plan",
  "blockers": ["..."],
  "dimensions": {
    "sdd-to-plan": "pass",
    "plan-to-tasks": "block",
    "task-executability": "pass",
    "dependency-topology": "pass",
    "interface-contracts": "pass",
    "acceptance-verifiability": "block",
    "scope-and-simplicity": "pass",
    "risk-and-rollback": "pass",
    "estimate-consistency": "pass"
  },
  "suggestions": []
}
```

`finalize` 负责：

- 调用 `review-record --stage dev-plan`；
- 读取 canonical route；
- PASS 保持 task-breakdown；
- NORMAL embedded 回退 tech-design-reviewed；
- UPSTREAM embedded 路由 tech-design-review-pending；
- 单次提交 review evidence 和状态；
- 输出 replay 或 abort 指令。

#### 12.7.3 自举例外治理

不要在普通 Pipeline 增加：

```text
skip-review-dev-plan=true
```

对于“某 CR 正在实现一个新的 gate，因此在工具落地前无法调用该 gate”的历史迁移，只允许使用版本化一次性迁移脚本：

```text
skills/shared/crctl/scripts/migrate-review-evidence.mjs
```

要求：

- 显式 `--bootstrap-reason`；
- 引用原始评审记录路径；
- 写入 annotation、review-loop、traceability 三处；
- `provenance: retrospective-bootstrap`；
- 记录操作者和迁移时间；
- 只允许历史 CR 或显式迁移模式；
- 不改变正常 `review-record` 前置状态；
- 不让 bootstrap 证据自动成为后续 CR 的先例。

如果该脚本的使用频率长期只有一次，可以将其作为 CR 专用迁移脚本归档，不必永久扩展 `crctl` 顶层命令面。

### 12.8 合并与并行机会

#### 12.8.1 可并行读取

以下读取可由 Runner 内部并行：

- PRD、SDD、Plan、TASK；
- ARCHITECTURE.md；
- Pipeline JSON；
- gates.json；
- review annotations；
- review-loop；
- 相关代码入口和测试文件。

读取完成后统一做 CRLF→LF 规范化和 hash。

#### 12.8.2 可并行生成

允许并行：

- 无依赖的同层 TASK 草稿；
- 多目标仓的只读架构扫描；
- 多份只读 schema 校验；
- 不共享写入文件的静态分析。

禁止并行：

- 有 depends-on 的 TASK；
- 会修改同一 Pipeline、gates 或 crctl 文件的 TASK；
- reviewLoop 回修；
- 状态推进和账本写入；
- 同一 CR 的多个 finalize。

#### 12.8.3 可合并提交

| 现有提交 | 建议合并 |
|---|---|
| approval.yml + status | 一个 approve commit |
| SDD + tech-design-review-pending status | 一个 SDD finalize commit |
| SDD repair + review-pending status | 一个 repair finalize commit |
| Plan + TASK + task-breakdown status | 一个 task-breakdown commit |
| review annotation + loop + trace + BLOCK status | 一个 review finalize commit |

评审判断和文档修订不应合并为同一个提交。先提交修订后的 subject，再由独立评审生成新证据，才能保持“评审针对哪一版文档”可追溯。

### 12.9 过度设计控制

#### 12.9.1 不继续扩大 `crctl.mjs`

不要把以下内容直接实现为新的大型 `cmd*`：

- SDD 上下文收集；
- Plan 生成；
- TASK 渲染；
- TASK 图分析；
- 完整 review workflow。

这些是 Skill 特有编排，应进入各 Skill 的 Runner。`crctl` 只新增多个 Skill 都需要的权威原语或深化现有浅接口。

#### 12.9.2 不新增通用 workflow 或 patch

禁止以减少调用为由新增：

```text
crctl run-workflow
crctl patch
crctl write-any-ledger
```

这些接口会扩大调用者必须理解的规则，破坏 purpose-specific 审计。

#### 12.9.3 不把 Plan 和 TASK 合并成一个大文档

Plan 和 TASK 具有不同生命周期：

- Plan 描述里程碑、依赖和风险；
- TASK 是编码唯一依据并需要逐项 done。

优化应合并工具调用和提交，不应合并领域文档。

#### 12.9.4 不自动生成语义 verdict

代码可以发现：

- 依赖环；
- 工时不一致；
- 缺失引用；
- 空验收；
- 未覆盖 FR；
- 接口签名字符串差异。

代码不能独立决定：

- 架构是否合理；
- TASK 是否具有正确业务边界；
- 某个差异是 blocker 还是 suggestion；
- 上游设计是否需要回退。

最终 verdict 和 repair-target 仍由 LLM 按 stage 契约判断。

#### 12.9.5 不为 safe.directory 修改全局环境

Runner 和 controlled Git 不应执行：

```text
git config --global --add safe.directory '*'
```

可接受方案：

- 命令级 `-c safe.directory=<resolved-worktree>`；
- repo 级显式配置并要求用户批准；
- 检测后返回结构化修复提示。

不得为了自动化方便扩大所有仓库的 Git 信任范围。

### 12.10 分阶段实施计划

#### P0：修复根因级提交边界

修改：

```text
skills/shared/crctl/scripts/crctl.mjs
skills/shared/crctl/scripts/test/crctl.test.mjs
skills/shared/controlled-shell/
```

内容：

1. `crctl approve` 原子提交 approval.yml + cr.md；
2. embedded advance 调用规范写入 Skill；
3. 禁止 CR 流程示例使用 `git add -A`；
4. controlled Git 处理 safe.directory；
5. review-record 返回 verified、files、attempt、next；
6. 保持状态机、gate、CAS 和人工审批规则不变。

#### P1：SDD Runner

新增：

```text
skills/develop/write-tech-design/scripts/prepare.mjs
skills/develop/write-tech-design/scripts/prepare-repair.mjs
skills/develop/write-tech-design/scripts/validate-sdd.mjs
skills/develop/write-tech-design/scripts/finalize.mjs
skills/develop/review-tech-design/scripts/prepare.mjs
skills/develop/review-tech-design/scripts/finalize.mjs
```

同步修改：

```text
skills/develop/write-tech-design/SKILL.md
skills/develop/review-tech-design/SKILL.md
pipeline-templates/architecture-design.pipeline.json
```

#### P1：Plan/TASK Runner

新增：

```text
skills/develop/write-dev-plan/scripts/prepare.mjs
skills/develop/write-dev-plan/scripts/finalize.mjs
skills/develop/write-dev-tasks/scripts/prepare.mjs
skills/develop/write-dev-tasks/scripts/validate-tasks.mjs
skills/develop/write-dev-tasks/scripts/finalize.mjs
skills/develop/review-dev-plan/scripts/prepare.mjs
skills/develop/review-dev-plan/scripts/finalize.mjs
```

同步修改：

```text
skills/develop/write-dev-plan/SKILL.md
skills/develop/write-dev-tasks/SKILL.md
skills/develop/review-dev-plan/SKILL.md
pipeline-templates/code-implementation.pipeline.json
```

#### P2：review stage 契约与 Pipeline outputs

延续第 11 节方案：

- review stage 元数据单一事实源；
- required dimensions 精确校验；
- subject hash；
- Pipeline 结构化 outputs；
- reviewLoop 直接传递结构化 feedback；
- node Markdown 不再承担机器状态传递。

#### P2：历史自举证据迁移

仅在存在其他历史 CR 需要补齐时实现版本化迁移脚本。若没有第二个使用者，不将其加入永久 CLI 命令面。

### 12.11 测试计划

#### approve 原子提交

- 四 stage approval 均提交 approval.yml + cr.md；
- gate 失败零写入；
- 人工拒绝仍执行合法回退；
- commit 失败时文件状态可恢复；
- grant 模式与 TTY 模式一致；
- evidence-digest 对应审批时文件版本；
- outbox 使用真实 commit SHA。

#### SDD prepare/finalize

- 初次 requirement-approved → tech-designing；
- 回修 tech-designing 合法；
- 其他状态硬失败；
- 多仓目标 ARCHITECTURE 正确解析；
- tools 仓与非 tools 仓不会串读 ARCHITECTURE；
- ARCHITECTURE 缺失时按 Skill 规则处理；
- FR-6a/FR-6b 等编号正确解析；
- 跨行解析失败硬失败；
- SDD 与 review-pending 状态同一提交。

#### review-tech-design

- 七维度齐全；
- Prompt 采纳影响条件触发和跳过；
- BLOCK 回退 tech-designing；
- PASS 保持 review-pending；
- attempt 增长；
- LOOP_EXHAUSTED；
- annotation、review-loop、traceability 自检；
- subject hash 变化后 `crctl next` 建议重审。

#### Plan/TASK

- Plan 总工时提取；
- TASK ID 唯一和连续；
- depends-on 悬空；
- 直接环和间接环；
- estimate 不一致；
- interface consume/produce 不一致；
- TASK 含 TBD；
- 验收条件为空；
- `_index.yml` 由脚本生成；
- Plan/TASK/cr.md 同一提交；
- 回修时废弃 TASK 不残留。

#### review-dev-plan

- PASS；
- NORMAL 路由；
- UPSTREAM 路由；
- UPSTREAM 不递增普通回修 attempt；
- repair-target 枚举；
- blocker 与 route 一致；
- developing gate 必须要求 canonical dev-plan PASS；
- 会话内未落盘评审不能通过 gate；
- bootstrap 迁移证据带 provenance。

#### 回归

- 15 个具名状态与注册前 `(new)` 不变；
- 25 条声明转换、wildcard 展开后 47 条不变；
- approval 仍只由 `crctl approve` 写；
- review canonical 仍只由 `review-record` 写；
- `_backlog.yml`、review-loop、traceability 不允许模型直接编辑；
- worktree 分支仍为 CR 事实源；
- CRLF→LF 纪律不回归。

### 12.12 最终目标流程

#### SDD 撰写

```text
1. write-tech-design prepare
   → 解析 worktree/目标仓/状态
   → embedded 进入 tech-designing
   → 批量读取 PRD/ARCHITECTURE/Pipeline/gates/代码事实

2. LLM
   → 输出 SDD 语义正文

3. write-tech-design finalize
   → frontmatter/章节/FR 覆盖校验
   → embedded 进入 tech-design-review-pending
   → sdd.md + cr.md 单次提交
```

#### SDD BLOCK 回修与重审

```text
1. prepare-repair
   → blocker/attempt/subject 上下文

2. LLM
   → 定点修订 SDD

3. write-tech-design finalize
   → SDD + review-pending 状态提交

4. review-tech-design prepare
   → 批量评审上下文

5. LLM
   → verdict/blockers/dimensions/suggestions

6. review-tech-design finalize
   → review-record
   → 三账本自检
   → PASS/BLOCK 路由
   → 单次提交
```

#### Plan/TASK

```text
1. write-dev-plan prepare
   → SDD/状态/反馈上下文

2. LLM
   → Plan 语义内容

3. write-dev-tasks prepare
   → Plan/SDD/任务契约

4. LLM
   → TASK 草稿对象，可按无依赖层并行

5. write-dev-tasks finalize
   → 分配 ID
   → 渲染 TASK
   → 生成 _index.yml
   → 工时/依赖/接口校验
   → embedded task-breakdown
   → Plan/TASK/cr.md 单次提交
```

#### Plan/TASK 评审

```text
1. review-dev-plan prepare
   → SDD/Plan/TASK/机械分析结果

2. LLM
   → 八维度判断和 repair-target

3. review-dev-plan finalize
   → review-record
   → PASS/NORMAL/UPSTREAM
   → 评审证据与状态单次提交
```

### 12.13 成功标准

优化完成后应满足：

- `crctl.mjs` 不承载 SDD、Plan、TASK 的完整工作流；
- 所有 Skill 特有确定性编排落在各自 `scripts/*.mjs`；
- LLM 不再搜索 Skill 路径、提交 approval、生成 `_index.yml` 或检查 Git log；
- approval.yml 与审批状态同一提交；
- SDD 与 review-pending 状态同一提交；
- Plan、TASK、task-breakdown 状态同一提交；
- review-record 后不再由模型读取三账本核对；
- Plan/TASK 评审必须有 canonical annotation、attempt 和 traceability；
- SDD 撰写调用降至 4–6；
- SDD 回修重审调用降至 4–6；
- Plan/TASK 撰写调用降至 4–5；
- Plan/TASK canonical 评审控制在 2–3 次调用；
- 不增加通用 patch/workflow 命令；
- 不新增 CR 状态；
- 不改变人工审批、CAS、状态机、worktree 和审计安全边界。

## 13. 开发、测试报告、代码评审与 scope change 优化

### 13.1 分析对象与调用规模

本节基于：

```text
change-requests/CR-2026-026/开发测试评审回修过程操作记录.md
```

记录时间为 2026-08-09 13:30–14:40（Asia/Shanghai），共 133 次工具调用：

| 阶段 | 调用数 | 主要内容 |
|---|---:|---|
| implement-code | 63 | TASK-01～07 实现、配置登记、测试和提交 |
| write-test-report | 7 | 测试执行、报告、traceability |
| review-code attempt-1 | 10 | diff、验证重跑、评审记录和状态推进 |
| scope change、回修与 attempt-2 | 53 | 用户主动将 suggestions 纳入当前 CR 后的实现、测试、文档和重评审 |

本轮 53 次回修不是 Pipeline 自动违反 strict policy，而是用户在 attempt-1 PASS 后明确要求扩大当前 CR 范围。优化目标不是禁止该选择，而是把它建模为显式、可审计、可恢复的 scope change：

```text
PASS + suggestions
→ 用户明确选择将部分 suggestions 纳入当前 CR
→ 记录 scope change
→ 原 PASS 证据失效
→ 回到 developing
→ implement-code / test / review attempt-2
```

当前流程缺少正式的 scope change 证据和失效机制，因此只能通过手工状态回退、回顾性 dev-plan 证据和文档注释补齐。

典型目标调用量：

| 阶段 | 当前 | 优化目标 |
|---|---:|---:|
| implement-code | 63 | 25–35 |
| write-test-report | 7 | 2–3 |
| review-code | 10 | 3–4 |
| 显式 scope change 后回修 | 53 | 12–20 |
| 无 scope change 的典型总量 | 80 | 30–45 |
| 含 scope change 的典型总量 | 133 | 45–65 |

### 13.2 scope change 的正式语义

#### 13.2.1 strict policy 的准确含义

`strict` 应解释为：

```text
suggestions 不自动升格为 blocker
```

它不意味着用户永远不能在当前 CR 实现 suggestions。用户可以显式改变范围，但必须产生 scope change 证据，使原 PASS 和相关测试证据失效。

三种路径：

| 决策 | 行为 |
|---|---|
| 接受当前交付范围 | 保持 PASS，进入代码人工审批 |
| 延后 suggestions | 保持 PASS，suggestions 留在 annotation，后续 CR 消费 |
| 纳入当前 CR | 记录 scope change，原 PASS 失效，回到 implement-code |

不得把第三种路径隐式实现为“PASS 后继续改代码”，否则状态、review attempt、test evidence 和 approval gate 无法判断哪一版代码被评审通过。

#### 13.2.2 scope change 是人类决策

scope change 必须由人类显式确认，强度与人工审批一致：

- TTY 交互；
- 或服务端签名 grant；
- LLM 不能自行决定扩大范围；
- LLM 可以根据用户指令生成 reason 和 repair instructions，但不能伪造 requested-by。

代码评审 PASS 后的 human approval 节点建议提供三种决策：

```text
1. 批准当前范围
2. 将选中的 suggestions 纳入当前 CR
3. 以其他原因驳回
```

用户在会话中明确要求 LLM 实现 suggestions，应映射到第 2 种决策。

### 13.3 scope change 权威证据

#### 13.3.1 新增受控账本

建议增加：

```text
change-requests/{CR-ID}/scope-change.yml
```

该文件由 crctl 独占写入，并加入 controlled-shell protectedPaths deny。

示例：

```yaml
schema: cr-scope-change/v1
cr-id: CR-2026-026
changes:
  - id: SC-001
    stage: code
    type: promote-review-suggestions
    status: open
    source-review:
      annotation: change-requests/CR-2026-026/review-annotations/code.yml
      attempt: 1
      verdict: pass
      reviewed-at: "2026-08-09T14:07:52+08:00"
      annotation-sha256: "..."
      subject-digest: "..."
    promoted-suggestions:
      - index: 1
        text: "..."
        fingerprint: "sha256:..."
      - index: 2
        text: "..."
        fingerprint: "sha256:..."
    requested-by: "human-id"
    requested-at: "2026-08-09T14:10:00+08:00"
    reason: "用户决定在本 CR 内完成两项改进"
    repair-target: implement-code
    invalidates:
      review-stage: code
      review-attempt: 1
      code-approval-ready: true
      test-evidence: true
    resolved-by: null
```

不修改 attempt-1 annotation。原评审记录仍保持不可变，scope-change 账本额外声明它已不再代表当前交付范围。

#### 13.3.2 purpose-specific crctl 原语

不要增加通用 YAML patch。建议增加目的明确的命令族：

```text
crctl scope-change promote-suggestions <CR-ID>
  --stage code
  --attempt 1
  --indices 1,2
  --reason "<reason>"
  [--grant <file>]

crctl scope-change resolve <CR-ID>
  --id SC-001
  --by-stage code
  --by-attempt 2
```

由于不应继续扩大 `crctl.mjs`，实现放在独立命令模块：

```text
skills/shared/crctl/scripts/commands/scope-change.mjs
```

`crctl.mjs` 只保留薄 dispatch。

`promote-suggestions` 执行：

1. 校验当前状态为 `code-reviewing`；
2. 读取 canonical code annotation；
3. 校验指定 attempt 为 PASS 且 blockers 为空；
4. 校验 suggestion index 存在；
5. 计算 annotation hash 和 suggestion fingerprint；
6. 人类身份确认或 grant 验签；
7. CAS 追加 scope change；
8. 使 code approval gate 失效；
9. 通过现有 `approve-code:reject -> implement-code` 转换回到 developing；
10. scope-change.yml + cr.md 单次提交；
11. 返回结构化 review feedback。

这里复用现有 reject 转换，不新增 CR 状态，也不增加状态机转换数量。语义是：用户拒绝按原 PASS 范围进入代码审批，并要求扩大当前交付范围。

#### 13.3.3 suggestion 标识

现有 suggestions 通常是字符串，没有稳定 ID。第一阶段可使用：

```text
attempt + 数组 index + 内容 hash
```

例如：

```text
CODE-A1-S01@sha256:abcd...
```

scope change 记录保存 index、原文和 fingerprint。即使 annotation 后续被意外修改，hash 不一致也会触发 `EVIDENCE_DRIFT`。

长期可把 review annotation schema 升级为带 ID 的 suggestion 对象，但首期不必为了 scope change 重写全部历史 annotation。

### 13.4 原 PASS 证据失效机制

#### 13.4.1 gate 失效

`approve-code` gate 增加一个 purpose-specific 检查：

```text
scopeChangeClosed(stage=code)
```

行为：

- 无 scope-change.yml：通过；
- code stage 无 open change：通过；
- 存在 open change：`GATE_BLOCKED`；
- 原 code annotation 仍保留，但不再允许审批。

错误示例：

```json
{
  "code": "GATE_BLOCKED",
  "message": "存在未闭合的 code scope change SC-001；attempt-1 PASS 已失效，请完成 implement-code → test → review-code"
}
```

#### 13.4.2 `crctl next` 路由

`code-reviewing` 状态下：

```text
若有 open scope change
→ next=implement-code
→ humanApproval=false
```

不得继续返回 `crctl approve --stage code`。

#### 13.4.3 review-record 闭合

attempt-2 PASS 后，`review-code/finalize.mjs` 必须显式传入：

```json
{
  "resolvedScopeChanges": ["SC-001"]
}
```

Runner 先验证：

- promoted suggestion 已出现在 fixed-blockers 或实现摘要中；
- 新代码 subject digest 不等于旧 digest；
- test evidence 针对新 HEAD；
- attempt-2 verdict=pass；
- blockers=[]。

随后调用：

```text
crctl scope-change resolve
```

scope-change.yml 记录：

```yaml
status: resolved
resolved-by:
  review-stage: code
  review-attempt: 2
  annotation-sha256: "..."
  resolved-at: "..."
```

review evidence、scope-change resolution 和状态推进进入同一 finalize commit。

### 13.5 测试证据同步失效

scope change 进入 developing 后，旧 test-report 即使 `status=pass` 也不能继续使用。

test-report 受保护区应增加：

```yaml
subjects:
  - repo: tools
    base: "..."
    head: "..."
    dirty: false
scope-changes: []
```

scope change 后：

- 原 report 的 subject HEAD 与当前 HEAD 不一致；
- 或 report 未包含 `SC-001`；
- `crctl next` 判定测试证据 stale；
- 必须重新执行 write-test-report。

新 report：

```yaml
scope-changes:
  - SC-001
```

表明它覆盖了该 scope change 引入的代码。

### 13.6 控制面与候选实现分离

本轮出现的自举冲突：

```text
候选 gates.json 增加 dev-plan 门禁
→ 候选 crctl 立即用新门禁治理当前 CR
→ 当前 CR 的 dev-start 发生在旧规则下
→ code-reviewing 回 developing 被 GATE_BLOCKED
```

这不是 scope change 本身的问题，而是控制面和候选实现混用。

requirement-register 输出应增加：

```yaml
control-plane:
  tools-root: C:/.../stable-tools
  commit: abcdef...
candidate-repositories:
  - id: tools
    worktree: C:/.../requirement/CR-2026-026
    branch: requirement/CR-2026-026
```

规则：

- CR 状态、gate、approval、review-record 使用注册时 pin 的稳定控制面；
- candidate crctl、gates 和 Pipeline 只在测试夹具中执行；
- 当前 CR 不被自己尚未合并的候选治理规则反向约束；
- 合并到 trunk 后，后续 CR 才使用新规则；
- 若要 dogfood 新 Pipeline，创建隔离 fixture workspace/CR，不在当前 CR 上自举。

这仍保持 crctl 唯一状态写者，只是明确唯一写者的发布版本。

### 13.7 implement-code 确定性 Runner

#### 13.7.1 prepare

新增：

```text
skills/develop/implement-code/scripts/prepare.mjs
skills/develop/implement-code/scripts/prepare-task.mjs
```

`prepare.mjs`：

- 读取 control-plane context；
- 解析 repo map 和所有 CR worktree；
- 检查 developing；
- 读取 PRD、SDD、Plan、TASK index；
- 读取 open scope changes；
- 检查 approval 已提交；
- 识别 EOL-only dirty；
- 输出 TASK DAG 和可执行层。

`prepare-task.mjs`：

- 校验前置 TASK done；
- 返回目标 repo/worktree；
- 返回涉及文件；
- 返回上游接口；
- 返回定向测试计划；
- scope change 回修时只返回 promoted suggestions 对应任务。

#### 13.7.2 LLM 编辑方式

普通代码变更优先使用宿主 patch 原语，不生成 `_scratch/*-patch.mjs`。

允许版本化脚本的场景：

- 数据迁移本身是交付物；
- 结构化生成器会被后续复用；
- 账本/索引操作已有固定 schema；
- 转换逻辑有独立测试。

禁止：

- 为五处字符串替换创建会话临时脚本；
- 使用 exact multiline match 处理 CRLF 文件；
- 用 inline `node -e` 承载复杂逻辑；
- 通过脚本向 JSON 写注释；
- 把修补脚本提交进产品代码。

#### 13.7.3 finalize-task

新增：

```text
skills/develop/implement-code/scripts/finalize-task.mjs
```

执行：

1. 校验 declared files 和实际 changed files；
2. 运行结构化定向测试计划；
3. 保存日志和退出码；
4. 调用 `crctl task done`；
5. 记录 scope change fixed evidence；
6. 输出下一批 TASK；
7. 按 TASK 或同层 batch 形成显式提交；
8. 不执行 `git add -A`。

### 13.8 Shell 与行尾摩擦优化

#### 13.8.1 结构化进程执行

所有 Runner 使用：

```js
spawnSync(exe, args, {
  shell: false,
  encoding: "utf8"
})
```

不使用：

```text
&&
head/tail
Select-String 判断测试是否通过
inline node -e 复杂脚本
```

#### 13.8.2 `crctl test --plan`

增加：

```text
crctl test <CR-ID> --plan <test-plan.json> --bump-attempt
```

测试计划：

```json
{
  "commands": [
    {
      "id": "crctl-tests",
      "exe": "node",
      "args": ["--test", "skills/shared/crctl/scripts/test/crctl.test.mjs"],
      "cwd": "C:/.../tools",
      "timeoutSeconds": 600
    }
  ]
}
```

避免 PowerShell 转义和 shell 语义差异。

#### 13.8.3 EOL-only 分类

implement-code prepare 对 dirty 文件计算：

```text
git status
→ 工作树内容 CRLF→LF
→ 与 index/blob 规范化内容比较
```

返回：

```json
{
  "dirty": true,
  "semanticDirty": false,
  "eolOnly": true
}
```

只报告，不自动 checkout、reset 或覆盖用户文件。

所有跨行解析和 hash 继续遵守 CRLF→LF 纪律。

### 13.9 测试报告 Runner

#### 13.9.1 当前摩擦

记录中测试报告阶段仍执行：

- 读取历史 CR test-report 模板；
- 手动执行验证；
- 手写 test-report；
- 读取 traceability；
- 手写 tests 投影。

当前 Skill 已声明使用 `crctl test`，说明 Skill 协议和实际执行未完全收敛。

#### 13.9.2 推荐接口

新增：

```text
skills/develop/write-test-report/scripts/prepare.mjs
skills/develop/write-test-report/scripts/finalize.mjs
```

`prepare`：

- 从 implement-code 结构化输出收集测试计划；
- 从 TASK 验收条件生成 coverage skeleton；
- 读取当前 repo HEAD；
- 读取 open scope changes；
- 调用 `crctl test --plan`。

深化 `crctl test`：

- 真实退出码；
- 原始日志；
- repo base/head；
- dirty 状态；
- command argv；
- log hash；
- test-report 受保护区；
- write-test-report attempt；
- traceability tests 投影；
- CAS 多文件写入。

LLM 只补充：

- 测试结果解释；
- TASK 覆盖矩阵；
- 未覆盖风险；
- 不适用说明。

`finalize`：

- 校验受保护区未被修改；
- 校验 scope-change ID 已覆盖；
- 提交 report、evidence、traceability、review-loop；
- 输出 next。

### 13.10 Code Review Runner

#### 13.10.1 固定 CR diff base

首次 `merge-base origin/main HEAD` 得到过宽 diff。requirement-register 应记录每个 repo 的 branch base：

```yaml
branch-bases:
  - repo: tools
    trunk: main
    sha: "..."
```

增加 purpose-specific 原语：

```text
crctl branch-base-set <CR-ID> --repo <id> --trunk <name> --sha <sha>
```

这是跨 Skill 权威元数据，适合 crctl 管理；不要让 review-code 从 Git log 猜提交范围。

#### 13.10.2 prepare

新增：

```text
skills/develop/review-code/scripts/prepare.mjs
```

一次完成：

- 读取 branch base 和 HEAD；
- 生成 changed files；
- 保存完整 diff；
- 读取 SDD、TASK、test-report、SDD annotation；
- 校验 test subject freshness；
- 读取 open scope changes；
- 无条件重放验证命令；
- 判断前端质量维度是否触发；
- 输出 review manifest。

大 diff 落盘：

```text
.crctl/review-evidence/code/attempt-02/manifest.json
.crctl/review-evidence/code/attempt-02/tools.diff
.crctl/review-evidence/code/attempt-02/verification.json
```

LLM 只读取 manifest 指向的必要证据。

#### 13.10.3 保留无条件重验，但合并调用

无条件重跑 lint/test/build 是现有代码质量门，首期不删除。

增加：

```text
crctl test --replay-from test-report.md --evidence-only
```

一次重放所有命令，避免多次 Shell 调用和文本解析。

如果未来数据证明全量重验是主要耗时，再单独评估基于 subject digest 的缓存；当前不增加复杂缓存。

#### 13.10.4 finalize

新增：

```text
skills/develop/review-code/scripts/finalize.mjs
```

职责：

1. 接受 LLM 判断；
2. 调用 review-record；
3. review-record 写后三账本自检；
4. PASS embedded 进入 code-reviewing；
5. BLOCK 保持/回到 developing；
6. attempt-2 可解析并关闭 scope change；
7. 显式暂存 annotation、loop、trace、scope-change、cr.md；
8. 单次提交；
9. 输出 next。

不再执行：

```text
Get-Content traceability
crctl status
git status
git log
```

来验证刚完成的 finalize。

### 13.11 测试基础设施优化

#### 13.11.1 共享夹具

反复创建 dbg 脚本说明 crctl 测试夹具接口过浅。增加共享 helper：

```text
makeReviewWorkspace({ stage, status, git })
writeReviewPayload({ stage, verdict, blockers, dimensions })
writeApprovalEvidence({ stage, digest })
assertReviewProjection({ stage, attempt, verdict })
```

新测试不再分别猜：

- 是否需要 git init；
- payload 必填字段；
- approval 形态；
- traceability 缩进。

#### 13.11.2 结构化失败输出

增加版本化测试入口：

```text
scripts/run-tools-tests.mjs
```

输出：

```json
{
  "passed": 120,
  "failed": 1,
  "failures": [
    {
      "name": "approve should...",
      "message": "expected 0, actual 1"
    }
  ]
}
```

不依赖中文 TAP 输出和 `Select-String`。

#### 13.11.3 分层验证顺序

配置变更后执行：

```text
语法/schema
→ 相关单测
→ crctl 全量测试
→ skill matrix/checker
→ lint-prompts
```

JSON.parse 失败应在运行 111 个测试之前终止。

### 13.12 三层架构映射

#### crctl 权威原语

新增或深化：

- approve 原子提交；
- scope-change record/resolve；
- branch-base-set；
- test structured execution；
- test evidence 和 trace projection；
- review-record 写后自检；
- gate 检查 open scope changes。

这些均为跨 Skill、需要 identity/CAS/audit 的权威能力。

#### Skill 确定性 Runner

新增：

```text
implement-code/scripts/prepare.mjs
implement-code/scripts/prepare-task.mjs
implement-code/scripts/finalize-task.mjs
write-test-report/scripts/prepare.mjs
write-test-report/scripts/finalize.mjs
review-code/scripts/prepare.mjs
review-code/scripts/finalize.mjs
```

Runner 组合原语，完成上下文、证据、路由和提交。

#### LLM 语义步骤

LLM 负责：

- TASK 代码实现；
- blocker 根因诊断；
- 测试结果解释；
- 代码质量评审；
- 将用户 scope change 决策转为修复说明。

LLM 不负责：

- 自行改变 scope；
- 手写 scope-change.yml；
- 更新 traceability；
- 推断 diff base；
- 解析测试终端文本；
- 创建字符串替换补丁脚本；
- 决定原 PASS 是否仍有效。

### 13.13 分阶段实施计划

#### P0：政策与高收益修复

1. 在 code human approval 中增加“promote suggestions”显式选择；
2. 修复 approve 原子提交；
3. review-record 返回 verified/files/next；
4. 禁止 `git add -A` 和会话临时文本替换脚本；
5. write-test-report 强制使用 `crctl test`；
6. 配置变更先 schema 后测试；
7. 当前代码评审 PASS 后修改代码时，明确使旧 PASS stale。

#### P1：scope change 权威链路

实现：

```text
commands/scope-change.mjs
scope-change.yml
scopeChangeClosed gate
crctl next open-scope-change 路由
review-code finalize resolve
```

保持现有 reject 转换，不新增状态和转换。

#### P1：开发与测试 Runner

实现：

- implement-code prepare/task/finalize；
- structured test plan；
- EOL-only 分类；
- per-TASK done；
- test evidence subject；
- test trace CAS。

#### P1：Code Review Runner

实现：

- branch base；
- diff manifest；
- test replay；
- scope change 上下文；
- review finalize。

#### P2：稳定控制面 pin

requirement-register 记录 control-plane tools SHA，候选治理代码不再治理当前 CR。

#### P2：测试基础设施

共享夹具、结构化测试输出、Pipeline/Skill/config schema checker。

### 13.14 测试计划

#### scope change

- 仅 code-reviewing 可 promote；
- 非 PASS annotation 拒绝；
- 有 blockers 拒绝；
- suggestion index 不存在拒绝；
- annotation hash 漂移拒绝；
- 非 TTY/无 grant 拒绝；
- scope-change.yml CAS；
- 原 PASS gate 失效；
- `crctl next` 返回 implement-code；
- 现有 reject 转换成功；
- attempt-2 PASS 可 resolve；
- 未覆盖 promoted suggestion 时不能 resolve；
- resolve 后允许 approve-code；
- 历史无 scope-change CR 行为不变。

#### control plane

- candidate gates 不影响当前 CR；
- candidate crctl 只在显式测试模式使用；
- merge 后新 CR 使用新 control plane；
- pinned tools SHA 不存在时硬失败；
- resume CR 恢复同一 control-plane commit。

#### implement Runner

- TASK DAG；
- 前置未 done；
- 同文件 TASK 串行；
-跨 repo 可并行；
- EOL-only；
-真实 dirty；
- target validation；
- `task done` 即时登记；
- scope change 回修只处理 promoted suggestions。

#### test Runner

- shell=false；
- PowerShell/Linux 参数一致；
- 多命令退出码；
- timeout；
- log hash；
- subject HEAD；
- scope change coverage；
- traceability CAS；
-旧 test report stale。

#### code review

-固定 branch base；
-多 repo diff；
-空 diff；
-过宽 merge-base 不再参与；
-验证 replay；
-前端维度条件触发；
-PASS；
-BLOCK；
-scope change attempt-2；
-review evidence + 状态单次提交。

### 13.15 最终目标流程

#### 正常 PASS

```text
implement-code Runner
→ write-test-report Runner
→ review-code prepare
→ LLM review
→ review-code finalize PASS
→ code-reviewing
→ 人工批准
```

#### PASS 后用户扩大范围

```text
attempt-1 PASS
→ code-reviewing
→ 用户选择 promote suggestions
→ crctl scope-change promote-suggestions
→ scope-change.yml(open)
→ 原 PASS/test evidence 失效
→ existing approve-code:reject -> implement-code
→ developing
→ implement-code Runner 修复 SC-001
→ write-test-report 覆盖 SC-001
→ review-code attempt-2
→ scope-change resolve
→ code-reviewing
→ 人工批准
```

### 13.16 成功标准

- 用户仍可显式要求在当前 CR 实现 suggestions；
- 该决定有 human identity、reason、原 suggestion 和证据 hash；
- 原 PASS 不被删除，但会被 open scope change 明确失效；
- 旧 test-report 自动 stale；
- scope change 未闭合时不能 approve-code；
- attempt-2 PASS 后 scope change 可审计闭合；
- 不新增 CR 状态；
- 不增加状态机转换数量；
- 不用通用 patch 或 workflow；
- 新 crctl 能力放独立 command module，不继续堆进 crctl.mjs；
- implement-code 调用目标降到 25–35；
- test-report 调用目标降到 2–3；
- review-code 调用目标降到 3–4；
- 显式 scope change 回修目标降到 12–20；
- 控制面、worktree、CAS、人工审批和审计边界保持不变。

## 14. 合并、回写与归档流程优化

### 14.1 分析对象与调用规模

本节基于：

```text
change-requests/CR-2026-026/合并回写归档过程操作记录.md
```

记录时间为 2026-08-09 14:45–15:25（Asia/Shanghai），共 40 次工具调用：

| 阶段 | 调用数 | 主要内容 |
|---|---:|---|
| merge-feature-branch | 14 | 多仓预检、本地合并、远端 push、metadata 和状态 |
| writeback | 18 | PRD/SDD、TASK、traceability 回写 |
| cr-archive | 8 | 归档账本发布、worktree/远端分支清理、cleanup-report |

该阶段真正需要 LLM 的语义工作非常少，主要集中在 traceability milestone 中：

- FR title 的编辑性描述；
- SDD 实现摘要；
- code/evidence 解释；
-异常失败时给人的风险说明。

其余步骤均具备固定输入、明确状态、可验证结果和可恢复规则，应由 Skill Runner 执行。

目标调用量：

| 阶段 | 当前 | 优化目标 |
|---|---:|---:|
| merge | 14 | 2–4 |
| writeback | 18 | 4–7 |
| archive | 8 | 2–3 |
| 合计 | 40 | 8–14 |

### 14.2 Merge 流程的确定性下沉

#### 14.2.1 当前 LLM 承担的机械操作

当前 merge 节点由 LLM 逐步编排：

- 解析 repositories、trunk 和 worktree；
- 查询历史 CR 的 merge-commits 形态；
- 检查 requirement 分支是否 push；
- fetch、rev-parse 和 merge-tree dry-run；
- checkout、pull、merge、commit；
- push 前远端新鲜度复核；
-逐仓 push；
-失败补偿；
-状态推进；
-逐仓 merge-metadata；
-读取 backlog 核对；
-metadata commit/push。

这些操作没有语义创作，属于确定性分布式发布协议。把协议保留在 200 多行 Skill prose 中由 LLM执行，会引入：

-命令漏执行；
-不同 Shell 形态；
-错误后继续执行；
-补偿步骤不完整；
-metadata 局部写入；
-通过历史先例恢复 schema。

#### 14.2.2 Merge Runner

新增：

```text
skills/writeback/merge-feature-branch/scripts/prepare.mjs
skills/writeback/merge-feature-branch/scripts/execute.mjs
skills/writeback/merge-feature-branch/scripts/finalize.mjs
```

该节点不需要 LLM，可由 Pipeline 直接调用 Runner。

`prepare.mjs`：

1. 校验 CR status=code-approved；
2. 校验 code review、test-report 和 code approval；
3. 读取 registration execution context；
4. 解析全部参与 repo；
5. 校验本地 CR HEAD 与已批准远端 checkpoint 一致；
6. 识别 changed、no-change 和 direct 模式 repo；
7. 并行执行 fetch、trunk/source rev-parse、worktree clean；
8. 并行执行 merge-tree dry-run；
9. 生成 merge plan 和恢复 journal。

`execute.mjs`：

1. 读取并校验 plan 输入 hash；
2. 对参与 repo 执行本地 no-commit merge；
3. 任一失败时对全部已 prepare repo 执行 merge --abort；
4. 全部成功后生成本地 merge commit；
5. 并行执行 push 前 freshness 复核；
6. 按固定 repo 顺序 push；
7. push 部分失败时按 journal 补偿；
8. 输出 merge-result.json。

`finalize.mjs`：

1. 校验全部远端 trunk 包含 merge result；
2. 调用 crctl merge-record；
3. 提交并 push knowledge-base metadata；
4. metadata 发布失败时调用 execute 的补偿入口；
5. 输出 merging 状态、merge SHAs 和下一步。

#### 14.2.3 Merge journal

Runner 持久化：

```text
.crctl/merge-runs/{CR-ID}/run.json
```

示例：

```json
{
  "cr": "CR-2026-026",
  "runId": "...",
  "phase": "remote-push",
  "repositories": [
    {
      "repo": "ai-first-platform-docs",
      "trunk": "master",
      "preflightTrunkSha": "...",
      "sourceSha": "...",
      "localMergeSha": "...",
      "remotePush": "done",
      "compensation": null
    }
  ]
}
```

用途：

-进程中断后恢复；
-区分尚未 push、已 push、已补偿；
-metadata 发布失败时找到需要补偿的 repo；
-不依赖会话记忆判断当前阶段。

journal 是 Runner 运行态文件，不是 CR 业务账本，不由 LLM 编辑，也不提交进仓库。

### 14.3 合并参与仓单一事实源

#### 14.3.1 当前隐藏 tools 特例

当前 Skill 同时声明：

```text
参与仓从 dir-graph.yaml#repositories 解析
```

又把未声明的 tools 仓作为特例，写死：

```text
path=../tools
trunk=custom/main
直接提交、无 worktree
```

这会导致：

- registration 不知道 tools 是参与仓；
- implement-code、push-progress、merge、archive 使用不同 repo 集合；
-merge metadata 需要查看历史 CR 恢复形态；
- tools 代码可能直接写 custom/main，绕过 CR worktree。

#### 14.3.2 推荐声明

所有可能被修改、测试、合并和清理的仓必须进入机器可读声明：

```yaml
repositories:
  - id: tools
    path: ../tools
    trunk: custom/main
    role: methodology
    participation: on-change
```

`participation: on-change` 表示：

- registration 可创建或记录其 CR worktree；
-没有变更时 merge 自动标记 no-change；
-有变更时使用同一合并协议；
- archive 总能从 execution context 找到待清理 worktree。

如果 tools 不允许出现在业务 repositories，则新增独立但同样权威的：

```yaml
governance-repositories:
```

不得继续把特殊仓库写在 Skill prose 中。

#### 14.3.3 不再查历史 CR 先例

merge-result schema 应由代码定义：

```json
{
  "repo": "tools",
  "mode": "merge | direct | no-change",
  "trunk": "custom/main",
  "sourceSha": "...",
  "resultSha": "...",
  "branch": "requirement/CR-2026-026"
}
```

Runner 不读取 CR-2026-025 或 CR-2026-023 来判断 merge-commits 应该长什么样。

### 14.4 批量 merge metadata 原语

#### 14.4.1 当前局部 CAS 问题

当前逐仓调用：

```text
crctl merge-metadata repo-A
crctl merge-metadata repo-B
```

每次独立 CAS `_backlog.yml`。第二次失败时，第一条 metadata 已落盘。

#### 14.4.2 `crctl merge-record`

新增 purpose-specific 原语：

```text
crctl merge-record <CR-ID> --from <merge-result.json>
```

实现放入：

```text
skills/shared/crctl/scripts/commands/merge-record.mjs
```

而非继续堆入 `crctl.mjs`。

职责：

1. 校验当前 status=code-approved；
2. 校验所有 resultSha、repo 和 trunk；
3. 校验 repo 无重复；
4. 过滤 no-change repo；
5. 使用现有状态机校验 code-approved → merging；
6. 一次构造全部 merge-commits；
7. `casWriteMulti` 写 `cr.md` 和 `_backlog.yml`；
8. 写审计事件；
9. 输出 expected commit files。

Runner 再把这两个文件作为同一 metadata commit 发布。

不新增状态或状态机转换。

### 14.5 Merge 前 approved checkpoint

记录中 remote requirement 分支直到 merge 阶段才补 push。这意味着 code approval 已完成，但远端没有审批所对应的源分支。

推荐固定顺序：

```text
approve-code
→ approval + cr.md 原子提交
→ final push-progress
→ checkpoint-add
→ merge-feature-branch
```

merge prepare 只验证：

```text
local HEAD
== origin/requirement/{CR-ID}
== approval evidence subject
```

缺失返回：

```text
MERGE_SOURCE_CHECKPOINT_MISSING
```

merge Runner 不负责临时补推，也不改变被批准的 source SHA。

### 14.6 可并行与应串行的 merge 步骤

允许并行：

-各 repo fetch；
- trunk/source rev-parse；
- worktree clean 检查；
- merge-tree dry-run；
- push 前 freshness 复核；
- no-change 判断。

本地 no-commit merge 可按独立 repo 并行，但全部成功前不得 commit。

建议保持串行：

-远端 push 按稳定 repo 顺序执行；
-补偿按 push 逆序执行；
-metadata 只在全部 push 成功后执行。

当前 repo 数量较少。并行 push 节省有限，却会增加补偿竞态，不建议首期实现。

### 14.7 Writeback 现有脚本评估

现有：

```text
writeback-prd-sdd.mjs
writeback-tasks.mjs
writeback-traceability.mjs
```

已经符合第二层 Skill Runner 的方向：

-版本化；
-可测试；
-幂等；
- dry-run；
-自检；
-不让 LLM 手写累积基线。

优化重点是统一 prepare/finalize 和输入契约，不应把这些逻辑迁进 `crctl.mjs`。

### 14.8 spec/version 输入收敛

feature-writeback Pipeline 已要求：

```text
spec_id
target_version
```

记录中仍读取 specs/_index.yml 自行推导下一版本。

新增：

```text
skills/writeback/scripts/prepare-writeback.mjs
```

输入必须来自 Pipeline：

```json
{
  "cr": "CR-2026-026",
  "spec": "ai-first-platform",
  "targetVersion": "0.27"
}
```

Runner 只校验：

- spec 存在；
- version 格式；
- targetVersion 与 current 的后继关系；
-该 CR 尚未写入；
-merge metadata 完整。

输入缺失或不一致时硬失败，不重新替用户决定版本。

### 14.9 Writeback 全局前置校验

当前 PRD/SDD 已回写并进入 writing-back 后，才发现全部 TASK pending。

`prepare-writeback.mjs` 必须在任何 specs/delivery 写入前统一校验：

- status=merging；
- code approval PASS；
- merge-record 已发布；
- PRD/SDD 存在；
- tasks/_index.yml 存在；
-全部 TASK status=done；
- test-report PASS；
- code review PASS；
- spec_id 和 version；
- delivery/specs 目标结构；
- traceability 所需 evidence；
-无 open scope change。

任一失败时零写入。

### 14.10 TASK done 门禁修复

#### 14.10.1 正常路径

implement-code finalize 必须：

```text
每完成 TASK
→ 定向验证
→ crctl task done
```

writeback 不承担补标。

#### 14.10.2 修复归档 gate

当前 `checkDeliveryIndexComplete` 在 `doneIds=[]` 时直接通过，无法区分：

- CR 没有 TASK；
-有 7 个 TASK 但全 pending。

调整为：

```text
tasks 不存在或 tasks=[]：
  no-task CR，允许

tasks 存在且存在非 done：
  TASK_STATUS_INCOMPLETE，阻止 writeback/archive

全部 done：
  检查 delivery/task/_index.yaml
```

#### 14.10.3 受控恢复命令

不要放宽普通 `task done` 的 developing 前置态。

新增恢复原语：

```text
crctl task reconcile <CR-ID>
  --all
  --reason "<reason>"
  [--grant <human-decision>]
```

实现放入独立 command module。

仅允许：

- code-approved；
- merging；
- writing-back。

并要求：

- code review PASS；
- test-report PASS；
- TASK 验收覆盖完整；
-人类确认；
-前置依赖满足。

一次 CAS 补齐可证明完成的 TASK，并写 audit。禁止手工 SearchReplace `tasks/_index.yml`。

### 14.11 Writeback plan/apply

#### 14.11.1 当前 dry-run 重复计算

三种脚本均执行：

```text
--dry-run
→ 人工核对
→ 去掉 --dry-run 重跑
```

安全语义正确，但存在：

-重复解析；
-重新生成时间戳；
- dry-run 后输入变化；
-第二次执行不保证与第一次计划完全一致。

#### 14.11.2 Plan artifact

扩展脚本支持：

```text
--plan-out <file>
--apply-plan <file>
```

plan 保存：

-所有输入文件 SHA-256；
-目标文件原 hash；
- planned writes；
- diff 摘要；
-生成时间；
-自检断言；
-幂等判断。

apply 前重算 hash：

```text
任一输入或目标变化
→ PLAN_STALE
→ 不写
```

这保留 dry-run 审核，同时消除 TOCTOU 和重复规划。

### 14.12 Traceability skeleton

当前 LLM 手写 137 行 milestone draft。应由：

```text
skills/writeback/writeback-traceability/scripts/prepare.mjs
```

自动提取：

- PRD FR 集合；
- SDD FR 映射；
- TASK refs；
- changed files；
- test evidence；
- review annotations；
- merge results。

生成：

```text
.crctl/writeback/{CR-ID}/traceability-skeleton.yml
.crctl/writeback/{CR-ID}/unresolved-links.json
```

示例：

```yaml
cr: CR-2026-026
milestone: 编码前质量门禁
target-version: "0.27"
fr-chain:
  - fr: FR-1
    title: "__LLM_FILL__"
    sdd:
      - "sdd.md#..."
    tasks:
      - CR-2026-026-TASK-01
    code:
      - "skills/shared/crctl/scripts/crctl.mjs"
    evidence:
      - "test-report.md"
```

LLM 只填写 `__LLM_FILL__` 和代码无法可靠生成的解释字段。

finalize 校验：

-所有 PRD FR 恰好一条；
-无 unknown FR；
- TASK ID 存在；
- code path 位于 merge diff；
- evidence 文件存在；
-merge commits 与 merge-record 一致。

### 14.13 Writeback 提交边界

当前有：

- PRD/SDD commit；
- writing-back status commit；
- TASK commit；
- traceability commit；
-每步 push。

建议保留恢复检查点，但压缩为两个发布提交。

#### 提交 1：baseline 与状态

```text
specs/{spec}/PRD.md
specs/{spec}/SDD.md
specs/_index.yml
change-requests/{CR}/cr.md
```

流程：

```text
apply PRD/SDD plan
→ advance merging → writing-back --embedded --spec-id
→ 单次 commit/push
```

#### 提交 2：delivery 与 traceability

```text
delivery/task/*
delivery/task/_index.yaml
specs/{spec}/traceability.yml
```

tasks 和 traceability 都完成后一次 commit/push。

如果任一步失败，工作区保留未提交现场，plan/apply 幂等重试。不需要每个 writeback 子节点单独 push。

### 14.14 Archive 事件竞态

#### 14.14.1 当前失败路径

当前要求：

```text
inbox-emit archived
→ advance archived
→ archive-move
```

但 archive event payload 因 Shell 中文 JSON 转义失败，后两个动作仍继续，导致条目移出 backlog 后无法重试事件。

归档事件永久丢失，只剩 audit.log。

#### 14.14.2 事件必须进入 archive CAS

扩展：

```text
crctl archive-move <CR-ID>
  --final-status archived
  --spec-id <id>
  --event-file <archive-event.json>
```

archive-event.json：

```json
{
  "event": "archived",
  "to": [],
  "payload": {
    "final_status": "archived",
    "writeback_spec_id": "ai-first-platform",
    "archive_reason": "writeback complete"
  }
}
```

archive-move 在同一 backlog/history CAS 中：

1. 校验 event schema；
2. 把 archive event 追加到 entry；
3. 富化 final-status、reason、spec-id 和 archived-at；
4. 移入 history；
5. event 随 history 条目永久保留。

不再单独调用 inbox-emit，因此没有 Shell JSON quoting 和时序窗口。

### 14.15 Archive `_index.yml` 契约漂移

Skill 和 Pipeline 声称 archive-move 同步：

```text
cr.md
_backlog.yml
_history.yml
_index.yml
```

当前 `cmdArchiveMove` 的 `casWriteMulti` 只写 backlog/history。

实施 archive Runner 前必须拍板 `_index.yml` 语义：

#### 方案 A：index 只包含 active CR

archive-move 同时从 `_index.yml` 删除或迁移条目，使用三文件 CAS。

#### 方案 B：index 是全生命周期目录

archive-move 在 `_index.yml` 将条目标记：

```yaml
status: archived
history-ref: change-requests/_history.yml
```

同样使用三文件 CAS。

#### 方案 C：index 不参与归档

若 `_index.yml` 永久保持注册目录且无需更新，则删除 Skill/Pipeline 中同步 index 的表述。

禁止维持“文档声称写、代码实际不写”的状态。

### 14.16 Archive Runner

新增：

```text
skills/cr/cr-archive/scripts/prepare.mjs
skills/cr/cr-archive/scripts/publish.mjs
skills/cr/cr-archive/scripts/cleanup.mjs
```

#### prepare

-识别 normal、archive-repair、publish-retry、cleanup-retry、done；
-校验 specs traceability；
-校验 delivery TASK 完整；
-校验 merge metadata；
-生成 archive event；
- embedded 推进 archived；
-调用 archive-move；
-输出待提交文件清单。

#### publish

-显式暂存 cr.md/backlog/history/index/CR 历史文件；
- commit；
- push；
- fetch 并确认远端包含 archive commit；
-失败时停止，不进入 cleanup；
-支持只重试 push。

#### cleanup

-解析全部 active/on-change repo，包括无改动仓；
-预检 trunk 包含 merge SHA；
-全部预检通过后执行清理；
-移除本地 worktree；
- prune worktree metadata；
-仅存在远端 requirement 分支时删除；
- rejected/withdrawn 默认不删远端；
-自动生成 cleanup-report；
- commit/push；
-支持 cleanup retry。

### 14.17 Cleanup 并行边界

可并行：

-各 repo trunk 包含性检查；
-远端 branch existence 查询；
-独立 repo 的 worktree remove；
- prune；
-无改动仓清理。

删除远端分支前应先完成全部有 merge SHA repo 的预检。任一失败时：

-不删除任何远端分支；
-可保留已完成的本地 worktree 清理结果；
-写 cleanup-pending。

不建议为少量 repo 构建复杂的分布式 cleanup 事务。

### 14.18 Cleanup report 代码化

当前 cleanup-report 由 LLM 手写。应由 cleanup Runner 生成：

```yaml
schema: cr-cleanup-report/v1
cr-id: CR-2026-026
cleanup-status: done
attempt: 1
started-at: "..."
completed-at: "..."
repositories:
  - repo: ai-first-platform-docs
    worktree: removed
    worktree-prune: done
    remote-branch: deleted
  - repo: multica
    worktree: removed
    worktree-prune: done
    remote-branch: skipped-missing
```

所有时间、repo、动作、stdout/stderr 摘要由 Runner 产生。

LLM 仅在 cleanup-pending 时补充面向人的风险解释。

### 14.19 Archived status 查询

archive-move 后 CR 已不在 backlog，当前 `crctl status` 返回 not found，调用方需要 grep history。

扩展只读状态解析：

```text
active：
  cr.md + backlog

terminal archived：
  cr.md + history
```

输出：

```json
{
  "cr": "CR-2026-026",
  "status": "archived",
  "terminal": true,
  "source": "change-requests/_history.yml",
  "writebackSpecId": "ai-first-platform",
  "cleanup": "done",
  "next": null
}
```

不允许通过 status 命令恢复终态。

### 14.20 三层架构映射

#### crctl 权威原语

新增或深化：

- merge-record；
- task reconcile；
- archive-move event；
- archive index projection；
- archived history status；
- CAS、identity、audit。

这些能力跨 Skill 且涉及权威账本，属于第一层。

#### Skill 确定性 Runner

新增：

```text
merge-feature-branch/scripts/prepare.mjs
merge-feature-branch/scripts/execute.mjs
merge-feature-branch/scripts/finalize.mjs

writeback/scripts/prepare-writeback.mjs
writeback/scripts/finalize-writeback.mjs
writeback-traceability/scripts/prepare.mjs

cr-archive/scripts/prepare.mjs
cr-archive/scripts/publish.mjs
cr-archive/scripts/cleanup.mjs
```

现有三个 writeback 脚本继续复用。

#### LLM 语义步骤

LLM 只负责：

- traceability 编辑性字段；
-异常补偿或 cleanup-pending 的风险说明；
-需要人类拍板的恢复选择说明。

LLM 不再：

-执行 Git merge/push/revert；
-查询历史 CR 先例；
-推导 spec/version；
-手改 TASK 状态；
-写 archive event JSON；
-写 cleanup-report；
-grep history 验证终态。

### 14.21 过度设计控制

#### 必须保留

- merge-tree dry-run；
- push 前 freshness 二次检查；
-部分 push 自动补偿；
-metadata publish 失败补偿；
- publish-before-cleanup；
- writeback 幂等和自检；
- cleanup retry；
-累积 specs 逐字节保护。

这些不是冗余，而是远端多仓发布和累积基线的必要安全机制。

#### 不建议

-通用 `crctl run-writeback`；
-通用 `crctl patch`；
-通用分布式事务框架；
-所有 repo 并行 push；
-为三个 writeback 脚本建立后台服务；
-放宽普通 task done 到 writing-back；
-归档发布失败后自动删除现场；
-从历史 CR 猜 metadata schema。

### 14.22 分阶段实施计划

#### P0：修复正确性问题

1. 修复 approve 原子提交，merge 前不再补 approval；
2. final push-progress 成为 merge 必须前置；
3. archive event 失败时禁止 archive；
4.修复 pending TASK 被 delivery gate 放行；
5.拍板并统一 archive `_index.yml` 契约；
6. archived status 支持 history 查询；
7. feature-writeback 强制使用输入 spec/version；
8.禁止手改 tasks/_index.yml。

#### P1：Merge Runner

实现：

- prepare/execute/finalize；
- merge journal；
- participant schema；
- merge-record；
-补偿测试；
- no-change/direct/merge 三模式。

#### P1：Writeback Runner

实现：

-全局 prepare；
- plan-out/apply-plan；
- traceability skeleton；
-两个发布提交；
- task reconcile 恢复入口。

#### P1：Archive Runner

实现：

- prepare/publish/cleanup；
- event-file；
- cleanup report；
- publish/cleanup retry；
-无改动仓清理；
- Windows 路径安全处理。

#### P2：仓库声明与 Pipeline outputs

-隐藏 tools 仓进入机器可读声明；
- registration 持久化 repo participation、worktree、branch base 和 checkpoint；
- Pipeline 使用结构化 outputs；
- merge/writeback/archive journal 纳入统一运行审计。

### 14.23 测试计划

#### Merge

-多仓全部成功；
- no-change repo；
- direct repo；
-分支未 push；
-本地 HEAD 与 remote 不一致；
- merge-tree 冲突；
-第二仓 local merge 失败时全部 abort；
- push 前 trunk stale；
-第二仓 push 失败；
-补偿成功；
-补偿受阻；
-metadata publish 失败；
-metadata 已到远端但本地误报；
-merge-record 多 repo 一次 CAS；
-重复执行幂等。

#### Writeback

-缺 spec/version；
-版本非合法后继；
- TASK pending；
- code/test evidence 非 PASS；
- PRD/SDD plan；
- plan stale；
- tasks 幂等；
- trace skeleton 全 FR；
- unknown/missing FR；
- code path 不在 diff；
-两个 commit 恢复；
-重复执行 noop。

#### Task reconcile

-正常 developing 禁止使用 reconcile；
- writing-back 有 pass evidence；
-无人工 grant 拒绝；
-依赖未 done 拒绝；
-覆盖矩阵缺失拒绝；
-一次 CAS 全部补齐；
-审计 reason；
-重复 reconcile 幂等。

#### Archive

- normal archive；
- event JSON 非法时零写；
- archive event 随 history 保留；
- archive-repair；
- publish-retry；
- cleanup-retry；
-history 重复；
-index projection；
-archive publish 失败不 cleanup；
-无改动仓 cleanup；
-远端分支不存在；
-trunk 未包含 merge SHA；
-worktree remove 失败；
-prune 失败；
-cleanup pending/done；
-status 从 history 查询。

### 14.24 成功标准

- merge 调用降至 2–4；
- writeback 调用降至 4–7；
- archive 调用降至 2–3；
-所有参与仓来自机器可读声明；
-不再读取历史 CR 推断 metadata；
- approved source branch 在 merge 前已远端发布；
-多仓 merge metadata 一次 CAS；
- TASK pending 时 writeback/archive 硬失败；
-不再手改 tasks/_index.yml；
- traceability 草稿由代码预生成；
- dry-run 和 apply 通过 hash 计划绑定；
-归档事件不会因 quoting 或时序丢失；
-archive index 文档与实现一致；
-cleanup-report 由 Runner 生成；
- archived CR 可直接查询；
-不新增状态或转换；
-不增加通用 patch/workflow；
-保留补偿、publish-before-cleanup、CAS 和审计能力。
