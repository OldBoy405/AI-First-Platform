---
id: CR-2026-026-sdd
type: SDD
cr-ref: CR-2026-026
title: 开发计划与 TASK 合并评审门禁 — 新增 review-dev-plan 编码前质量门禁 技术设计
status: draft
created: "2026-08-09T12:10:00+08:00"
updated: "2026-08-09T12:10:00+08:00"
---

# SDD — review-dev-plan 编码前质量门禁技术设计

> 上游事实源：PRD v0.2.x（已审批）+ `docs/analysis/开发计划与TASK合并评审门禁方案.md`
> 目标代码仓：tools 仓自身（`../tools`），ARCHITECTURE.md 已存在（CR-2026-021 登记版），本 CR 按 §8 维护规则追加登记
> 口径：状态机 15 具名状态 + (new)；转移 25 声明 / 47 展开（本 CR 新增 2 声明后为 27 / 49，以实现期测试固化为准）

## 1. 架构概览

### 1.1 模块边界

本 CR 改动分布在 tools 仓四个既有模块，全部复用现有写入路径，不新建模块：

| 模块 | 改动性质 | 关键文件 |
|---|---|---|
| Skill 提示词层 | 新增 1 个 + 修订 2 个 | `skills/develop/review-dev-plan/SKILL.md`（新）、`write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`（回修支持） |
| Pipeline 编排 | 插入 1 个 reviewLoop 节点 | `pipeline-templates/code-implementation.pipeline.json` |
| crctl 治理工具 | 映射扩展（零新增子命令） | `skills/shared/crctl/scripts/crctl.mjs`（REVIEW_STAGE_* 四映射 + 路由判定） |
| 门禁与状态机 | 声明变更 | `skills/shared/crctl/gates.json`、`dir-graph.yaml`（state_machine） |
| 索引与矩阵 | 登记 | `skills/_index.yml`、`agent-skill-matrix.yml` |
| 文档 | 同步 | `README.md`、`ARCHITECTURE.md`（§8 登记）、`skills/shared/crctl/SKILL.md`（用途表） |

### 1.2 依赖图

```text
write-dev-plan ──> write-dev-tasks ──> review-dev-plan（新增，reviewLoop）──> push-progress ──> human_approval ──> approve-dev-start
                    （status → task-breakdown）        │
                                     ┌─────────────────┴─────────────────┐
                              PASS：保持 task-breakdown            普通 blocker：task-breakdown → tech-design-reviewed
                                                              上游设计疑点：task-breakdown → tech-design-review-pending
```

依赖方向遵守 ARCHITECTURE.md §4：Skill 层只经 crctl 读写账本；crctl 不依赖 Skill/Pipeline 定义；pipeline 的 `reviewLoop.passCondition` 运行时从 pipeline JSON 读取（PRD FR-10/B-15 同口径）。

### 1.3 关键流程（双轨路由）

```text
review-dev-plan 评审完成
  ├─ verdict=pass && blockers=[]          → PASS：保持 task-breakdown，进入人工开发启动审批
  ├─ blockers 含 repair-target=write-tech-design（upstream-design blocker）
  │                                        → 上游疑点轨：task-breakdown --review-dev-plan:upstream-design-blocker--> tech-design-review-pending
  │                                          停止自动重放，人工走技术设计修订→评审→审批
  └─ 其余 blockers（repair-target=write-dev-plan）
                                           → 普通轨：task-breakdown --review-dev-plan:block--> tech-design-reviewed
                                             重放 write-dev-plan → write-dev-tasks → review-dev-plan（≤3 轮）
```

优先级（PRD FR-6b/D-14）：同一轮同时出现两类 blocker 时，上游疑点优先——进入上游轨，且本轮不消耗普通轨 attempt。

## 2. 数据模型

### 2.1 阶段证据 `review-annotations/dev-plan.yml`

与既有 stage annotation 同构（verdict/blockers/dimensions/suggestions），crctl `review-record` 注入 reviewer/reviewed-at 后落盘。新增语义字段仅复用既有 `repair-target` 表达分流（PRD D-13）：

```yaml
verdict: pass | block
repair-target: write-dev-plan | write-tech-design   # 顶层可选字段，缺省 write-dev-plan（TD-BL-1 闭合）；pass 轨不写（v0.4.0）
blockers: []                    # 纯字符串列表，不解析结构化路由（D-13 修订）
dimensions:                     # 八类维度 + 元信息（对齐方案 §5.2 临时 payload）
  sdd-to-plan: pass | block
  plan-to-tasks: pass | block
  task-executability: pass | block
  dependency-topology: pass | block
  interface-contracts: pass | block
  acceptance-verifiability: pass | block
  scope-and-simplicity: pass | block
  risk-and-rollback: pass | block
  suggestion-policy: strict
  reviewer-model: "<model self report>"
suggestions: []
```

**关键设计（TD-BL-1 修订，v0.4.0 补充）**：`repair-target` 是 dev-plan payload/annotation 的**顶层可选字段**：缺省 `write-dev-plan`；`verdict=block` 且显式 `repair-target: write-tech-design` 时走上游疑点轨。**pass 轨不落 repair-target**（annotation 与 traceability 投影顶层省略，v0.4.0 code review suggestion-1 落地；attempts 轮次历史条目保留缺省值，schema 稳定）。blockers 保持纯字符串列表，**不在字符串中解析结构化路由**。crctl 对 `--stage dev-plan` 校验该字段枚举（缺省或 ∈ {`write-dev-plan`, `write-tech-design`}），并将解析后的值写入 canonical annotation 顶层与 traceability 投影（替代既有 `REVIEW_REPAIR_TARGETS` 默认值注入：dev-plan stage 下 payload 显式提供时用之，否则用映射默认值）。不新增 blocker-type 字段。

### 2.2 临时 payload

`.crctl/tmp/review-dev-plan.yml`（非受控路径，`--from` 缺省即此路径），LLM 只写判断，crctl 负责 schema 校验/CAS/身份注入/删除。

### 2.3 轮次与追溯（零新增账本）

- `review-loop.yml`：`review-record --bump-attempt` 级联写 `loops.review-dev-plan`（复用 025 的 review-loop 记账）。
- `traceability.yml#reviews.dev-plan`：由 crctl 通用投影路径渲染（复用 025 交付的 `renderReviewsStageBlock` + 定点编辑），字段集与 requirement/tech-design/code 一致（reviewer/verdict/reviewed-at/blocker-count/annotation/repair-target/review-loop）。
- **attempt 计费规则**（PRD FR-6b/FR-7，TD-BL-2 修订）：路由判定**发生在 bump 之前**——`cmdReviewRecord` 在读取 payload 后、执行 review-loop 读取/校验/递增之前，先解析顶层 `repair-target` 得出 route（pass/normal/upstream）。NORMAL/PASS 走既有 `--bump-attempt` 记账（current-attempt+1、attempts 追加该轮）；UPSTREAM **跳过 bump**——review-loop.yml 写入块整体不执行（`if (bump)` 分支跳过，文件字节不变），仅写 annotation 与 traceability 投影（attempt=当前值、attempts 保持既有历史），三账本与 audit 保持同批一致（NFR-2）。

## 3. 接口契约

### 3.1 crctl.mjs — REVIEW_STAGE 四映射扩展（PRD FR-14）

在既有映射（`crctl.mjs:1413-1424`）追加：

```js
REVIEW_STAGE_FILES['dev-plan']    = 'dev-plan.yml';
REVIEW_STAGE_LOOPS['dev-plan']    = 'review-dev-plan';
REVIEW_STAGE_EXPECT['dev-plan']   = ['task-breakdown'];
REVIEW_REPAIR_TARGETS['dev-plan'] = 'write-dev-plan';
```

- `review-record --stage dev-plan`：走既有 `cmdReviewRecord` 通用路径（schema 校验 → traceability 读/合并 → casWriteMulti 三账本），零分支特化。
- `--stage dev-plan` 的 expect 前置态为 `task-breakdown`（与 write-dev-tasks 推进到的状态一致；评审 PASS 不推进、BLOCK 由 advance 级联，因此 expect 校验在 review-record 入口检查当前 status=task-breakdown）。

### 3.2 路由判定（crctl.mjs，PRD FR-6/FR-6a/FR-6b，TD-BL-1/2 修订）

**判定发生在 `cmdReviewRecord` 内部、bump 之前**。新增纯函数 `resolveDevPlanRoute(payload)`：

```text
输入：临时 payload（verdict + 顶层 repair-target）
判定：
  1. verdict=pass → PASS
  2. verdict=block 且 payload.repair-target === 'write-tech-design' → UPSTREAM
  3. 其余 → NORMAL
输出：{ route: 'pass' | 'upstream' | 'normal' }
```

`cmdReviewRecord` 对 `--stage dev-plan` 的执行顺序（既有通用流程内分支）：

```text
1. 读取临时 payload（.crctl/tmp/review-dev-plan.yml）并做 schema 校验
   （verdict 枚举 / blockers 列表 / dimensions 非空映射 / repair-target 枚举校验：缺省或 ∈ {write-dev-plan, write-tech-design}）
2. resolveDevPlanRoute(payload) → route
3. route === 'upstream'：跳过 bumpAttempt 级联（review-loop current-attempt 不递增、attempts 不追加），
   仅写 canonical annotation（repair-target=write-tech-design）与 traceability 投影（attempt=当前值）
   route === 'normal' 或 'pass'：走既有 --bump-attempt 记账（attempt+1、attempts 追加该轮）
4. casWriteMulti 统一写三账本（NFR-2 同批语义）
```

- 路由结果（route + repair-target）写入 canonical annotation 顶层，随三账本投影。
- 调用方（pipeline/Skill）按 route 推进：PASS → 人工审批；UPSTREAM → `advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker`；NORMAL → `advance --to tech-design-reviewed --trigger review-dev-plan:block`。
- 同轮并存时 UPSTREAM 优先（FR-6b）：payload 顶层 repair-target=write-tech-design 时，普通 blocker 并入 suggestions 摘要展示，路由仍为 UPSTREAM；不消耗普通 attempt（步骤 3）。
- **不解析 blockers 字符串**：LLM 在 payload 顶层写 `repair-target: write-tech-design` 表达上游疑点（Skill 文档定义该写法），crctl 只校验枚举、不解析字符串（D-13）。

### 3.3 gates.json 变更（PRD FR-10/FR-11/FR-12）

**approvalStages.dev-start**（现状：仅 requireFiles plan.md + tasks/_index.yml）：

```json
"dev-start": {
  "to": "developing",
  "trigger": "approve-dev-start",
  "expect": ["task-breakdown"],
  "approvalSection": "development-start",
  "evidence": {
    "$default": "change-requests/{cr}/review-annotations/dev-plan.yml",
    "plan": "change-requests/{cr}/plan.md",
    "task-index": "change-requests/{cr}/tasks/_index.yml"
  },
  "passCondition": { "pipeline": "code-implementation", "nodeRef": "review-dev-plan" },
  "requireFiles": [
    "change-requests/{cr}/plan.md",
    "change-requests/{cr}/tasks/_index.yml"
  ]
}
```

- `passCondition` 复用既有解释器（运行时读 pipeline JSON 的 reviewLoop.passCondition：verdict=pass && blockers=[]）。
- `evidence` 三键 → canonical evidence digest 覆盖 annotation/plan/task-index（FR-11）；审批后修改三者触发既有 EVIDENCE_DRIFT。TASK-*.md 正文不在 digest（D-9/FR-11 首版边界，AC-12a）。

**statusGates.developing**（现状：仅 approval 一项）→ 按 FR-12 补全（实现期修订：passCondition 引用 `stage=dev-start` 而非 `dev-plan`——`evaluatePassCondition` 从 `approvalStages[stage]` 取 stageCfg（pipeline+evidence），dev-plan 不在 approvalStages（自动评审 stage 非人工审批）；dev-start 的 approvalStages 配置含 evidence 三键 + passCondition，完全复用同一判据与证据）：

```json
"developing": [
  { "type": "fileExists", "path": "change-requests/{cr}/plan.md" },
  { "type": "fileExists", "path": "change-requests/{cr}/tasks/_index.yml" },
  { "type": "globNonEmpty", "dir": "change-requests/{cr}/tasks", "pattern": "^TASK-\\d+.*\\.md$" },
  { "type": "passCondition", "stage": "dev-start" },
  { "type": "approval", "section": "development-start" }
]
```

全部使用现有门禁类型（fileExists/globNonEmpty/passCondition/approval），零新增解释器（FR-12）。

**reviewLoops** 追加：`"review-dev-plan": { "pipeline": "code-implementation" }`。

### 3.4 状态机变更（dir-graph.yaml，PRD FR-13）

追加两条声明（不新增具名状态）：

```yaml
- { from: task-breakdown, to: tech-design-reviewed, trigger: "review-dev-plan:block -> write-dev-plan" }
- { from: task-breakdown, to: tech-design-review-pending, trigger: "review-dev-plan:upstream-design-blocker" }
```

- 既有 `task-breakdown → tech-design-reviewed`（approve-dev-start:reject）与本 CR 新增的 block 转换目标相同，状态机允许同 from/to 多 trigger。
- 转移口径：25 → 27 声明；47 → 49 展开（wildcard 展开数按既有展开器计算，实现期测试固化，PRD B-7/D-3 已声明）。

### 3.5 pipeline 节点插入（code-implementation.pipeline.json，PRD FR-1）

在 node-2（write-dev-tasks）之后、node-3（push-progress）之前插入 reviewLoop 节点：

```json
{
  "id": "00000000-0000-0000-0015-000000000099",
  "kind": "skill",
  "label": "开发计划与 TASK 合并评审",
  "ref": "review-dev-plan",
  "prompt": "…（读取 sdd.md/plan.md/tasks/_index.yml/TASK-*/review-annotations/sdd.yml，八类维度评审，判断写 .crctl/tmp/review-dev-plan.yml，经 crctl review-record --stage dev-plan --bump-attempt 落盘；按 §3.2 路由：pass→保持；block 普通轨→advance --to tech-design-reviewed --trigger review-dev-plan:block；上游疑点轨→advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker；输出 verdict/blockers/repair-target/attempt…）",
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
  },
  "onFail": "abort",
  "timeoutMinutes": 30
}
```

后续节点（push-progress / human_approval / approve-dev-start / …）顺序后移；UUID 按仓库规则分配（此处为示意值）。

**onBlock 分流契约（TD-BL-3 修订）**：`onBlock: route-to-repair-node` 对 dev-plan 节点按 route 二分：
- NORMAL：按 `replayNodes`（write-dev-plan → write-dev-tasks → review-dev-plan）重放；节点 prompt 先 `advance --to tech-design-reviewed --trigger review-dev-plan:block`（embedded）；
- UPSTREAM：**不进入 replayNodes**——节点 prompt 执行 `advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker`（embedded）后，输出 `upstream-design-blocker` 并 **abort 当前 code-implementation pipeline**（onFail: abort），等待人工走 architecture-design 技术设计修订链路；不在本 pipeline 内消耗 attempt（§2.3/§3.2 步骤 3）。

## 4. 关键算法与流程

### 4.1 普通轨重放闭环（FR-6/FR-8/FR-9）

```text
review-dev-plan BLOCK（普通轨）
  → advance --to tech-design-reviewed --trigger review-dev-plan:block（embedded，cr.md 状态落盘）
  → reviewLoop 重放：write-dev-plan（消费 review_feedback/self_repair_attempt，输出 fixed-blockers）
    → write-dev-tasks（重新生成 TASK 与 _index.yml，不保留已被删除的旧 TASK）
    → review-dev-plan（重新评审，attempt+1）
  → ≤3 轮；耗尽仍 block → LOOP_EXHAUSTED 停止，不进入 human approval（FR-7/AC-13）
```

空转防线（FR-9）：首版不做 blocker→产物 diff 对账器；下一轮 review-dev-plan 重新读取实际产物，未修复的问题继续 BLOCK（AC-13 兜底）。

### 4.2 上游疑点轨（FR-6a/AC-8a，TD-BL-1 修订）

```text
发现 SDD 自相矛盾/不可实施/需改已审批设计
  → payload 顶层写 repair-target: write-tech-design（blockers 保持纯字符串）
  → review-record 内 route=upstream：不 bump，annotation 落 repair-target=write-tech-design
  → 节点 prompt advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker
  → abort code-implementation pipeline
  → 人工走既有技术设计修订（write-tech-design 回修）→ review-tech-design → approve-tech-design
  → 审批通过后重新进入 plan → TASK → review（既有 tech-design-reviewed → task-breakdown 转换）
```

本节点不修改/不覆盖 `review-annotations/sdd.yml`（US-5）；`tech-design-review-pending` 是既有具名状态（dir-graph L219-222 已有转换），复用其语义。

### 4.3 attempt 计费（FR-6b/FR-7/AC-8b，TD-BL-2 修订）

- 路由判定在 bump 之前（§3.2 步骤 2-3）：NORMAL/PASS 走既有 `--bump-attempt`（current-attempt+1，attempts 追加该轮）；UPSTREAM **跳过 bump**——review-loop.yml 不写（字节不变，见 §2.3），仅写 annotation + traceability 投影（attempt=当前值、attempts 保持既有历史）。
- PASS 与既有 stage 一致：bump 一次，attempts 保留 pass 记录（AC-9：第 2 轮通过时同时保留第 1 轮 block 与第 2 轮 pass）。
- UPSTREAM 后的普通回修 attempt 从当前值继续计费（AC-8b：不递增后续普通 dev-plan 回修 attempt）。

### 4.4 evidence digest（FR-11）

复用既有 `canonicalEvidenceDigest`：按 approvalStages.dev-start.evidence 映射对 dev-plan.yml/plan.md/tasks/_index.yml 计算规范化摘要（CRLF→LF 后哈希），写入 approval.yml#development-start.evidence-digest；审批后任一文件变更 → EVIDENCE_DRIFT（AC-12）。

## 5. 技术选型与替代方案

| 决策 | 本 SDD 选择 | 被否方案与理由 |
|---|---|---|
| 分流表达 | 复用 `repair-target` 字段（D-13） | 新增 `blocker-type`/`upstream-design` 专用字段：改 annotation schema，破坏既有 stage 同构；且 CR-2026-025 已让 repair-target 进三账本投影，零新增字段即达可观测 |
| 上游轨目标态 | `tech-design-review-pending`（既有） | 新增 `plan-reviewing` 类状态：违反 D-3 不新增状态；既有待评审态语义完全匹配 |
| 评审落盘 | 复用 `review-record` 通用路径 | 为 dev-plan 特写落盘实现：违反 ARCHITECTURE.md §4 依赖方向与"通用实现"原则，且 025 已交付通用三账本能力，特化即重复 |
| 轮次上限 | 3 轮（与 requirement/tech-design/code 一致） | 无上限/更高上限：既有 reviewLoop 契约统一为 3，特例需专门文档说明 |
| 首版 TASK 正文 freshness | 不做（D-9/D-12） | 为 dev-plan 特化 glob 摘要协议：AC-12a 显式排除；通用多文件 digest 留跨 stage 统一方案 |
| 评审模型 | 同一模型可执行，reviewer-model 留痕（方案 §10.1） | 模型选择暂停节点：新增人工节点类型，违反 NFR-5 |

## 6. FR 到技术实现映射

| FR | 实现落点 |
|---|---|
| FR-1 | §3.5 pipeline 节点插入（UUID 按仓库规则分配，后续节点顺序后移） |
| FR-2 | §3.5 节点 prompt：强制输入清单（sdd.md/plan.md/tasks/_index.yml/TASK-*/review-annotations/sdd.yml）+ PRD 抽查边界（D-15） |
| FR-3 | review-dev-plan/SKILL.md 八类维度定义 + §2.1 dimensions schema（含估算一致性边界：结构性问题时才 blocker） |
| FR-4 | §3.1 映射扩展 + review-record 通用路径（三账本同批，025 FR-16/17 复用） |
| FR-5 | §3.3 passCondition + pipeline 节点 prompt（PASS 保持 task-breakdown） |
| FR-6 | §3.2 NORMAL 路由 + §3.4 转换 1 + §4.1 重放闭环 |
| FR-6a | §3.2 UPSTREAM 路由（repair-target 顶层字段）+ §3.4 转换 2 + §4.2 人工链路 |
| FR-6b | §3.2 步骤 2-3 优先级判定（bump 前路由）+ §4.3 attempt 计费分支 |
| FR-7 | §3.5 maxAttempts=3 + §4.3 计费 + LOOP_EXHAUSTED 语义 |
| FR-8 | write-dev-plan/write-dev-tasks SKILL 修订：review_feedback/self_repair_attempt 输入 + fixed-blockers 输出 |
| FR-9 | §4.1 空转防线（下一轮重读产物兜底）+ SKILL 固定措辞 |
| FR-10 | §3.3 approvalStages.dev-start（evidence + passCondition + requireFiles） |
| FR-11 | §3.3 evidence 三键 + §4.4 canonicalEvidenceDigest |
| FR-12 | §3.3 statusGates.developing 五条件（全部既有门禁类型） |
| FR-13 | §3.4 两条转换（口径 25→27 声明 / 47→49 展开，测试固化） |
| FR-14 | §3.1 四映射 + §3.2 路由判定（含 repair-target 枚举校验）+ gates.json reviewLoops 追加 |
| FR-15 | 新建 `skills/develop/review-dev-plan/SKILL.md`（§3.5 prompt 为骨架） |
| FR-16 | `skills/_index.yml` 登记 + agent-skill-matrix.yml：dev-agent owns、quality-reviewer-agent can-call |
| FR-17 | README/ARCHITECTURE §8 登记（crctl 命令面语义扩展 + pipeline 结构变化 + 状态机口径变化） |
| FR-18 | 既有四 stage（requirement/tech-design/write-test-report/code）回归测试（AC-14） |
| FR-19 | §8 测试设计 + check-skill-matrix/check-agents-contract/lint-prompts 全绿 |
| FR-20 | commit message 溯源标注（方案文档 + CR 编号） |

## 7. 安全与性能考量

### 7.1 安全控制点

- **审计**：review-record/advance 全部走既有 `.crctl/audit.log` 审计路径，无旁路（ARCHITECTURE.md §5 不变量 2）。
- **无越权写入**：本 CR 不触碰 sdd.yml/approval.yml 既有段；dev-plan annotation 仅由 review-record 写（模型禁手写，guard deny 面不变）。
- **人工审批无旁路**：dev-start 审批仍只经 `crctl approve`（TTY/签名），本 CR 只升级其校验（不变量 7 保持）。

### 7.2 性能

- 评审读取文件数：sdd.md + plan.md + tasks/_index.yml + TASK-*（线性于 TASK 数），与 review-code 同量级，无新增热点。
- crctl 侧零新增解析器：路由判定只读已解析的 annotation 对象（O(blockers)），无额外文件 IO。
- traceability 定点编辑复用 025 的行级函数，单 stage 写入 O(文件行数)。

### 7.3 边界与一致性（行尾纪律 NFR-3）

- 所有涉及哈希/解析的路径（evidence digest、payload 读取、traceability 编辑）沿用 `\r\n → \n` 规范化 + `split(/\r?\n/)` + 硬失败（不变量 4），本 CR 新增代码零例外。

## 8. Prompt 采纳影响（必填：本 CR 触及 crctl REVIEW_STAGE 映射与 gates.json）

本 CR 扩展 `crctl review-record` 的 stage 面（新增 dev-plan）与 `gates.json` 的 dev-start/developing 门禁。需要同步采纳的 Skill/文档清单：

| Skill / 文档 | 现状 | 应改为 |
|---|---|---|
| `skills/develop/write-dev-plan/SKILL.md` | 不消费 review_feedback；写 plan.md 后无回修输出 | 接受 `review_feedback`/`self_repair_attempt` 输入，逐条修复并输出 `fixed-blockers`（FR-8/FR-9） |
| `skills/develop/write-dev-tasks/SKILL.md` | 推进 task-breakdown 后即完成；不消费 review_feedback | 同上；回修时重新生成 TASK 与索引，不保留已删旧 TASK（FR-8） |
| `skills/develop/approve-dev-start/SKILL.md` | 只校验 plan/tasks 文件存在 | 补充：dev-start 审批前须有 dev-plan.yml 且 passCondition 通过；evidence digest 覆盖三键（FR-10/FR-11 的调用方表述） |
| `skills/shared/crctl/SKILL.md` | 用途表无 dev-plan stage | 用途表补 `review-record --stage dev-plan`、两条新 trigger（review-dev-plan:block / :upstream-design-blocker）、reviewLoops 映射（FR-14 配套文档） |
| `skills/develop/implement-code/SKILL.md` | 无涉及 | 不需要改（普通轨重放不含 implement-code；上游轨走既有技术设计链路）——仅确认不回归 |
| `README.md` | 节点流程无 review-dev-plan | 更新 code-implementation 流程、受控评审 stage 列表、状态转换说明（FR-17） |
| `ARCHITECTURE.md` | §3 代码地图无 dev-plan | §8 维护规则登记本 CR（crctl stage 扩展 + pipeline 结构变化 + 状态机口径 27/49） |

## 9. 测试设计（对应 PRD §5 AC）

| 测试文件 | 覆盖 |
|---|---|
| `crctl.test.mjs`（追加向量） | ① REVIEW_STAGE 映射含 dev-plan 且 `review-record --stage dev-plan` 在 task-breakdown 落盘三账本（pass 轨省略 repair-target，suggestion-1）；② repair-target schema 校验（缺省→write-dev-plan、显式 write-tech-design→upstream、非法值→SCHEMA_INVALID 且三账本不变）；③ UPSTREAM 路由判定：payload 顶层 repair-target=write-tech-design → upstream 且 bump 跳过（review-loop.yml 字节不变——current-attempt 不递增、attempts 不追加；traceability 投影同语义，AC-8b）；④ NORMAL/PASS 走既有 bump（attempt+1，普通 block 轨缺省 repair-target 落盘）；⑤ 同轮并存时 UPSTREAM 优先（普通项进 suggestions 摘要）；⑥ dev-start approval 门禁升级生效——grant 非 TTY 通过路径（evidence+passCondition）放行到 developing / passCondition 不过 → GATE_BLOCKED 且不写 approval 段（AC-10，v0.4.0 自动化）；⑦ developing 目标态删 TASK-*.md 或篡改 approval → 门禁拦截，补齐后放行（AC-11a，v0.4.0 自动化）；⑧ evidence digest 覆盖三键，改 dev-plan.yml 后 EVIDENCE_DRIFT（AC-12，v0.4.0 自动化）；⑨ 三轮 BLOCK → LOOP_EXHAUSTED（AC-13，v0.4.0 自动化）；⑩ requirement/tech-design/write-test-report/code 四 stage 回归（AC-14，既有用例全量覆盖） |
| `lint-prompts.test.mjs` / `check-skill-matrix.mjs` / `check-agents-contract.mjs` | 新 Skill 登记、dev-agent owns + quality-reviewer-agent can-call、prompt 无漂移（AC-15/AC-15a） |
| 状态机断言（crctl.test.mjs 内） | 新增两条转换可 advance；口径 27 声明 / 49 展开断言（PRD B-7） |

## 10. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 双轨路由判定歧义（blockers 混写两类） | FR-6b 优先级硬编码 + AC-8b 测试固化；Skill 文档规定上游疑点 blocker 写法 |
| 既有 approve-dev-start 审批流程回归 | FR-18/AC-14 回归测试；gates 变更只增条件不删条件 |
| 状态机口径漂移（25→27 声明的连锁） | PRD B-7 已声明；实现期测试固化精确展开数；ARCHITECTURE §8 登记 |
| 评审轮次空转（回修不改产物） | FR-9 下一轮重读兜底 + AC-13 轮次上限；不引入对账器（YAGNI） |
| traceability 投影与既有三 stage 冲突 | 复用 025 定点编辑（AC-19 语义：非目标段字节保留），测试断言 |

回滚：本 CR 全部改动可经 revert 单次提交回退；gates.json 与 dir-graph.yaml 声明为可逆追加（不删既有条目），无数据迁移。

## 11. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于 PRD v0.2.x + 实测代码基线；双轨路由/attempt 计费/gates 三处变更详设） |
| 2026-08-09 | v0.2.0 | Ray | 技术评审 attempt-1 回修（3 blocker，TD-BL-1/2/3）：repair-target 定为 dev-plan payload/annotation 顶层可选字段（枚举校验，blockers 不解析字符串）；路由判定移到 cmdReviewRecord 内部 bump 之前，UPSTREAM 跳过 bump；pipeline onBlock 分流契约（NORMAL replay / UPSTREAM abort code-implementation） |
| 2026-08-09 | v0.3.0 | Ray | 实现期偏差修订（TASK-01~07 落地后回写）：① §3.3 developing 门禁 passCondition 引用改为 `stage=dev-start`——`evaluatePassCondition` 仅从 `approvalStages[stage]` 取 stageCfg，dev-plan 不在 approvalStages（自动评审 stage），dev-start 配置含同一 evidence/passCondition 完全复用；② §2.3/§4.3 明确 UPSTREAM 时 review-loop.yml 写入块整体跳过（字节不变），不只 traceability 不递增；③ §9 测试③补 review-loop.yml 字节不变断言（测试实际落地为 5 向量 + 加强断言，116 例全绿） |
| 2026-08-09 | v0.4.0 | Ray | code review suggestion-1/2 落地（实现期修订，d395d04）：① §2.1 pass 轨不落 repair-target（annotation 与投影顶层省略，attempts 轮次历史保留缺省，schema 稳定）；② §9 ⑥-⑩ 门禁向量自动化——⑥/⑥b grant 非 TTY 通过/拦截、⑦ developing 目标态删 TASK 拦截+补齐放行、⑧ 篡改 dev-plan.yml → EVIDENCE_DRIFT、⑨ 三轮 BLOCK → LOOP_EXHAUSTED，⑩ 由既有用例全量覆盖（crctl.test 121 例全绿 + lint 19 + checker 8）；结论：不影响既有判据（pass 轨无回修消费方；门禁判据与证据来源不变） |
