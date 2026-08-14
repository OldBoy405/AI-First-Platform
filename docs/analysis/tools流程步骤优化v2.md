# tools 全流程优化方案 v2

> 文档日期：2026-08-09
> 文档定位：后续 Spec 的设计依据，不直接授权修改 tools 代码。
> 上游分析：`docs/analysis/tools流程步骤优化.md`。
> 本版目标：删除重复方案、收缩过度设计、统一架构边界，并按实施依赖重新排序。
> 质询决策（2026-08-09）：Phase 2～6 是按证据逐项晋升的候选路线，不是预先批准的实现合同。

本方案的候选演进顺序为：

```text
Phase 0 基线统一
→ Phase 1 正确性修复
→ Phase 2 PRD Runner 垂直试点
→ Phase 3 最小公共能力与 Registration
→ Phase 4 其余 Authoring/Review（逐项）
→ Phase 5 Implement/Test/Code Review（逐项）
→ Phase 6 Merge/Writeback/Archive
```

**当前实施授权只覆盖 Phase 0 和 Phase 1。**Phase 2 的 PRD 垂直试点也是后续候选，
必须在 Phase 0/1 完成后重新确认并另写 Spec。保留候选目标不等于批准其中的文件布局、
JSON schema、公共 API 或 retry mode。

## 1. 背景

CR-2026-026 对 tools 全生命周期进行了实际演练，覆盖：

```text
注册
→ PRD 编写与评审
→ SDD 编写与评审
→ Plan/TASK 编写与评审
→ implement-code
→ 测试报告
→ 代码评审与人工 scope change
→ 多仓合并
→ specs/delivery 回写
→ 归档与 worktree 清理
```

操作记录暴露的共性问题不是 LLM 的语义能力不足，而是 LLM 同时承担了过多确定性职责：

- 搜索 Skill 和仓库路径；
- 解析 worktree、trunk 和 Git 历史；
- 拼接平台相关 Shell 命令；
- 手工生成 frontmatter、索引和账本投影；
- 推进状态和组织提交；
- 重复核对刚由 crctl 写入的证据；
- 根据历史 CR 猜测当前 schema；
- 在异常阶段临时编写补丁或账本修复脚本。

本方案将优化目标从“减少几个工具调用”提升为：

```text
让每类事实只有一个权威写者；
让每个调用者只理解自己必须理解的最小接口；
让语义判断与机械执行彻底分离；
让失败现场可恢复且不依赖会话记忆。
```

## 2. 当前基线冲突

后续 Spec 开始前必须先解决以下事实冲突。

### 2.1 状态机口径

当前 `../tools/dir-graph.yaml` 实测包含：

```text
15 个具名状态 + 注册前 (new)
27 条声明转换
wildcard 展开后 49 条转换
```

但以下位置仍存在 25/47 旧口径：

- workspace `AGENTS.md`；
- `../tools/ARCHITECTURE.md` 前文；
- 旧版优化方案的部分成功标准。

同时 `../tools/ARCHITECTURE.md` 的 CR-2026-026 维护记录已写 27/49。

**决策：**

1. 状态机事实以 `../tools/dir-graph.yaml` 为准；
2. Phase 0 统一所有文档、断言和测试注释；
3. 在统一完成前，新代码不得硬编码转换数量；
4. Spec 必须明确引用的是 declared 还是 wildcard-expanded 口径。

### 2.2 crctl 是否允许拆分

`../tools/ARCHITECTURE.md` 当前明确规定：

```text
crctl.mjs 刻意保持单文件，不因体量拆分。
```

**决策（CR-2026-027 Phase 0 落地）：**

- v2 默认保持 crctl 单文件；
- 本轮优化不创建 `commands/` 模块目录；
- 若未来需要模块化，必须独立立项并先修改 ARCHITECTURE；
- Skill Runner 的引入不依赖 crctl 模块化。

### 2.3 crctl 与 Pipeline 的依赖描述

ARCHITECTURE 当前声称 crctl 不依赖 Pipeline，但实现已通过 Pipeline 的 reviewLoop/passCondition 执行 gate。

**建议修订后的准确描述：**

```text
crctl 不执行 Skill，也不依赖 Skill 的自然语言语义；
crctl 可以读取 dir-graph、gates 和 Pipeline 中的声明式 gate/reviewLoop 配置；
Pipeline 不得调用 crctl 之外的账本写入口。
```

### 2.4 archive `_index.yml` 语义

cr-archive Skill/Pipeline 声称 archive-move 同步 `_index.yml`，但当前 `cmdArchiveMove` 只写 `_backlog.yml` 和 `_history.yml`。

**质询决策（2026-08-09）：**

`_index.yml` 是全生命周期轻量目录。归档时不删除条目，由现有 `archive-move` 复用
`casWriteMulti` 同时更新 `_backlog.yml`、`_history.yml` 与 `_index.yml`。索引条目只
更新：

```yaml
status: archived | rejected | withdrawn
archived-at: <timestamp>
writeback-spec-id: <spec-id>   # 有则写
```

不复制完整 history 条目，不新增固定路径即可推导的 `history-ref`。`_index.yml` 不成为
新的查询或状态事实源：查询仍读 `_backlog.yml + _history.yml`，在途状态仍以 `cr.md`
为准。

### 2.5 可写仓声明

当前 workspace `dir-graph.yaml#repositories` 只声明 docs 与 multica，但
`merge-feature-branch` 又通过 prose 硬编码 tools 仓特例；历史记录中 tools 已参与多个
CR。这违反“所有参与仓来自机器可读声明”。

**质询决策（2026-08-09）：**

Phase 0 将 tools 加入 workspace repositories：

```yaml
- id: tools
  path: "../tools"
  trunk: custom/main
  role: code
  active: true
```

继续复用当前模型：所有 `active != false` 的 repo 都参与每个 CR。删除
`merge-feature-branch` 中“tools 不在声明但特殊参与”的 prose 和实现分支；注册、同步、
合并、清理都只遍历 repositories。

本轮不新增每 CR 仓库选择字段。只有真实指标证明多余 worktree 成本不可接受时，才另立
设计。

## 3. 目标架构

### 3.1 编排平面：Pipeline

Pipeline 继续负责：

- 节点顺序；
- typed inputs；
- reviewLoop；
- replayNodes；
- human approval；
- 失败路由；
- 阶段超时。

当前 Multica 尚无执行非 human 节点的真正 Pipeline Runner，因此本轮不定义 Pipeline
typed outputs，也不创建 `.crctl/runs/{pipeline-run-id}/{node-id}.json` 协议。各确定性
脚本只需输出稳定 JSON；typed outputs 待 Pipeline Runner 独立立项时与运行时一起设计。

Pipeline 不复制：

- 状态机；
- gate；
- 账本 schema；
- Git 操作细节；
- Runner 内部步骤。

Pipeline 是编排平面，不计入三个执行层。

### 3.2 第一执行层：crctl 权威原语

crctl 继续作为唯一状态和账本写者，负责：

- 状态机；
- gate；
- CAS 和 casWriteMulti；
- `cr.md`、`_backlog.yml`、`_history.yml`、`tasks/_index.yml`；
- review、approval、test 等 canonical evidence；
- identity 和时间戳；
- audit/outbox；
- 受控 Git；
- 只读状态与下一步计算。

新增 crctl 能力必须满足至少一个条件：

1. 写权威状态或账本；
2. 需要 CAS；
3. 需要 identity/audit；
4. 多个 Skill 必须共享完全相同的语义；
5. 绕过该入口会破坏 gate。

禁止新增：

```text
crctl patch
crctl run-workflow
crctl stage-context
crctl registration-check
crctl register-preflight
```

这些属于 Runner 编排，不属于权威原语。

### 3.3 第二执行层：Skill 确定性 Runner（候选）

只有真实试点证明 Skill 存在足够多的确定性步骤时，才增加 Runner。Runner 位于 Skill
自己的 `scripts/` 目录；只有少量机械步骤的 Skill 可以继续保留 prose，不强制脚本化。

#### 有 LLM 语义断点的 Skill

最多两个入口：

```text
prepare.mjs
finalize.mjs
```

`prepare`：

- 解析权威 workspace/worktree；
- 批量读取上下文；
- 执行只读验证；
- 生成受保护骨架；
- 输出结构化 JSON。

`finalize`：

- 校验 LLM 产物；
- 调用 crctl purpose-specific 原语；
- 执行显式 Git add/commit/push；
- 输出结构化结果和 next。

#### 完全确定性的 Skill

若确定需要 Runner，只使用：

```text
run.mjs
```

候选适用范围：

- requirement-register；
- merge-feature-branch；
- writeback-prd-sdd；
- writeback-tasks；
- cr-archive cleanup。

#### Runner 硬边界

Runner：

- 可以写普通内容文件；
- 不得直接写状态和账本；
- 所有 Git 通过 `crctl git`；
- 不复制状态机和 gate；
- 不持久化第二套 CR 状态；
- 不依赖历史 CR 作为 schema；
- 失败时输出稳定 error code。

### 3.4 第三执行层：LLM 语义步骤

LLM 只负责语义产物和语义判断：

- PRD、SDD、Plan、TASK；
- 代码实现；
- traceability 编辑性说明；
- blocker 修复；
- verdict、suggestions、repair-target；
- 风险和范围判断。

LLM 不再负责：

- 账本；
- 状态推进；
- worktree/trunk 解析；
- Git 历史推断；
- TASK ID 和 `_index.yml`；
- 测试退出码；
- canonical evidence；
- 提交、push、merge、archive；
- 临时 YAML 修复脚本。

## 4. Runner 试点约束与公共能力晋升门槛

### 4.1 首个试点不预建公共库

未来若 PRD Runner 候选获批，首个试点只在本 Skill 下增加：

```text
write-requirement-prd/scripts/prepare.mjs
write-requirement-prd/scripts/finalize.mjs
```

不先创建 `skills/shared/runner/lib.mjs`。出现第二个真实 Runner 后，比较两个调用者，只
提取已经重复且语义一致的最小交集。现有 `skills/writeback/scripts/lib.mjs` 是必须先
审查的复用来源，不得平行复制一套同义实现。

候选公共能力上限：

- UTF-8 和 CRLF→LF 读取；
- 结构化 JSON 输出；
- 统一 fail(code, message, extra)；
- `spawnSync(exe, args, {shell:false})`；
- 文件 hash；
- 显式路径验证；
- 调用 crctl CLI 的薄封装。

不得提供：

- 通用 workflow；
- 通用文件 patch；
- YAML 全量序列化；
- 状态缓存；
- Plugin/Skill 动态加载框架。

### 4.2 Prepare 最小输出

```json
{
  "op": "write-requirement-prd.prepare",
  "cr": "CR-2026-026",
  "workspace": "C:/...",
  "status": "drafting",
  "mode": "create",
  "inputs": {},
  "artifacts": {},
  "constraints": {},
  "warnings": []
}
```

该对象是 PRD 试点的局部输出，不是提前冻结的跨 Skill schema。只有第二个消费者出现后
才讨论版本化 `schema` 字段。

### 4.3 Finalize 最小输出

```json
{
  "op": "write-requirement-prd.finalize",
  "cr": "CR-2026-026",
  "files": [],
  "commit": {
    "repo": "ai-first-platform-docs",
    "sha": "..."
  },
  "status": "drafting",
  "next": "review-requirement",
  "warnings": []
}
```

### 4.4 公共能力晋升条件

创建 `skills/shared/runner/lib.mjs` 前必须同时满足：

1. 已有至少两个真实 Runner；
2. 两者出现语义相同的重复机械逻辑；
3. 抽取后接口比局部保留更少、更稳定；
4. 不复制 writeback `lib.mjs` 已有能力；
5. 有调用方测试证明公共接口，而不只是工具自身单测。

Pipeline 输出传递不属于本轮公共 Runner 契约。

## 5. Phase 0：统一事实和架构契约

### 5.1 目标

在新增代码前消除所有基础口径冲突。

### 5.2 修改范围

```text
AGENTS.md
CONTEXT.md
dir-graph.yaml
docs/analysis/tools流程步骤优化v2.md
../tools/ARCHITECTURE.md
../tools/skills/writeback/merge-feature-branch/SKILL.md
```

`../tools/dir-graph.yaml` 的状态机本身已经是 27/49，不修改；`../tools/AGENTS.md` 与
`../tools/README.md` 未发现需要本轮修正的事实，不为凑齐“修改范围”而改动。

### 5.3 步骤

1. 统计并固定当前状态机 declared/expanded 数量；
2. 修正所有 25/47 旧表述；
3. 修正 crctl 与 Pipeline 依赖说明；
4. 确认 crctl 继续单文件；
5. 拍板 archive `_index.yml`；
6. 将 tools 声明为 active repository，删除 merge Skill 隐藏特例；
7. 删除旧方案中的 command module 描述；
8. 删除旧方案中的通用上下文 crctl 命令；
9. 建立优化指标基线。

### 5.4 验收

- 所有权威文档状态机口径一致；
- ARCHITECTURE 无前后矛盾；
- `crctl.mjs` 单文件边界明确；
- archive index 语义明确；
- repositories 无 Skill prose 隐藏特例；
- 后续 Spec 不再需要自行解释这些问题。

## 6. Phase 1：修复现有架构中的正确性问题

本阶段不引入 Runner 框架。

### 6.1 `crctl approve` 原子提交

当前 approval 和 status 被拆成不同提交。

**质询决策（2026-08-09）：采用两文件 CAS + 单次 commit。**

目标流程：

```text
预检 current state / transition / evidence / signature / passCondition / requireFiles
→ 在内存生成 approval.yml 与目标 status 的 cr.md
→ 按候选 approval 复核目标 gate
→ casWriteMulti(approval.yml, cr.md)
→ crctl git add 两文件
→ 单次 commit
→ commit 成功后发送 status outbox
→ audit 记录最终结果
```

边界：

- TTY approve 与 `--grant` 共用一个内部 approve-and-advance helper；
- 不新增 crctl 子命令、WAL 或通用事务框架；
- gate/签名/证据预检失败时零文件写入；
- CAS 冲突时两文件均不写；
- commit 失败时两文件共同留在工作区，返回结构化恢复信息，不出现单文件半状态；
- 拒绝路径不写批准段，继续复用现有合法 reject 转换。

涉及：

```text
../tools/skills/shared/crctl/scripts/crctl.mjs
../tools/skills/shared/crctl/scripts/test/crctl.test.mjs
```

四个 approve Skill 已只描述“调用 crctl approve 后写审批并级联推进”的稳定行为，不含
分提交细节，无需修改。

验收：

- 四 stage approval 均一次提交；
- gate 失败零写入；
- CAS 冲突两文件均不写；
- commit 失败两文件共同保留且不发 status outbox；
- TTY/grant 走同一原子 helper；
- 拒绝路径保持现有合法转换；
- approval 不再由下一阶段补提交。

### 6.2 TASK 完成门禁

修复：

```text
存在 TASK 但全部 pending
```

被误判为无任务并允许归档的问题。

核验现有状态机与历史数据：

```text
正常 archived 必经 task-breakdown/developing；
developing 已要求 task index + 非空 TASK 文件；
当前所有已归档 CR 均有非空 TASK。
```

**质询决策（2026-08-09）：正常归档不允许隐式 no-task。**

`advance --to archived` 的任务门禁：

1. `tasks/_index.yml` 必须存在；
2. `tasks[]` 必须是非空列表；
3. 任一 TASK 非 done → `TASK_STATUS_INCOMPLETE`；
4. 全部 done 后校验 `delivery/task/_index.yaml`；
5. 缺文件、空数组不得被解释为 no-task。

`rejected/withdrawn` 属提前终止，可在无 TASK/writeback 时进入 history；不走 archived
门禁。`archive-move` 接受当前状态 `archived|rejected|withdrawn`，且
`--final-status` 必须与当前 `cr.md` status 完全一致，否则硬失败。

首期不新增永久 `task reconcile` 命令，也不新增 no-task 标志。历史数据若需修复，使用
一次性版本化迁移脚本。

### 6.3 Archive event 与账本移动原子化

CR-2026-026 实测发生：

```text
inbox-emit 因中文 JSON Shell 转义失败
→ 后续 advance/archive-move 仍继续
→ CR 移出 backlog 后事件永久无法重试
```

**质询决策（2026-08-09）：归档事件进入 archive-move CAS。**

```text
embedded advance 到最终态
→ archive-move 在内存构造 archive event
→ 复用现有 editInboxEmit 逻辑写入候选条目
→ 富化 final-status / archive-reason / writeback-spec-id / archived-at
→ backlog→history + index 终态更新
→ casWriteMulti(backlog, history, index)
→ CAS 成功后发送 archive outbox
```

不新增 `inbox-emit --payload-file`、archive 专用幂等键或新命令。普通通知继续使用
`inbox-emit`；只有与归档不可分割的 lifecycle event 进入 `archive-move`。

归档事件收件人复用现有 owner 模型：

```text
to = unique(
  owners.requirement.id,
  owners.development.id,
  owners.test.id
)
```

旧条目缺少 `owners` 时才回退顶层 `owner`；最终仍为空则在 CAS 前返回
`ARCHIVE_RECIPIENTS_MISSING`。不新增 submitter/reviewer 字段。

同时修正普通 `inbox-emit` 的实现与既有 Skill 契约不一致：`--to` 缺失、解析后非列表或
去重后为空均返回 `BAD_ARGS`，不得写入无收件人的 notify-log。

### 6.3a Archive index 原子一致性

与 §6.3 同一实现修复 `archive-move` 已承诺、但遗漏的 `_index.yml` 更新：

```text
读 backlog + history + index
→ 生成三份新文本
→ casWriteMulti 一次校验与写入
→ audit
```

任一 event/文件结构错误或 CAS 冲突时事件与三份账本均不写。测试覆盖
archived/rejected/withdrawn、final-status 与 cr.md 不一致、中文 archive reason、
三角色收件人去重、legacy owner 回退、空收件人、可选 spec-id、重复归档、outbox 时序
与 CRLF。

### 6.4 Archived status 查询

当前 `resolveCrState` 强制先从 backlog 找 CR，归档后 `status/next` 均返回
`CR_STATUS_NOT_FOUND`。

**质询决策（2026-08-09）：增加仅供 status/next 使用的终态只读 resolver。**

输出最小契约：

```json
{
  "cr": "CR-2026-026",
  "status": "archived",
  "terminal": true,
  "source": {
    "history": "change-requests/_history.yml"
  },
  "legalNext": [],
  "reviewLoops": {},
  "gateBlockers": {},
  "next": null
}
```

规则：

- active CR 继续从 cr.md/backlog 读取；
- archived/rejected/withdrawn 从 history `final-status` 读取；
- `crctl next` 对终态返回 `next:null`，不报错；
- 写命令继续使用现有 active resolver，不允许终态写入；
- backlog/history 同时存在同一 CR 时 `CR_LOCATION_CONFLICT`；
- history 重复条目或缺 final-status 时硬失败；
- cr.md 与 history 不一致时以 history 为准并输出 warning；
- 不新增 archive reason/spec-id 等非必要返回字段；
- 不新增 `archive-status` 命令。

测试覆盖三种终态、位置冲突、重复 history、缺 final-status、cr.md 漂移和 active 回归。

### 6.5 review-record 输出深化

当前各 review Skill 会在 `review-record` 成功后重新读取 traceability，核对刚由
`casWriteMulti` 写入的投影；dev-plan 又需要 route/repair-target，但当前命令未返回。

**质询决策（2026-08-09）：只增加有真实消费者的字段。**

保持现有 `file`、`trace` 字段兼容，并增加：

```json
{
  "files": [
    "change-requests/{cr}/review-annotations/{stage-file}",
    "change-requests/{cr}/traceability.yml",
    "change-requests/{cr}/review-loop.yml"
  ],
  "attempt": {
    "current": 1,
    "max": 3,
    "bumped": true
  },
  "route": "pass | repair | upstream",
  "repairTarget": "write-requirement-prd | write-tech-design | write-dev-plan | implement-code | null"
}
```

`files` 只列本次实际写入的文件；未 bump 时不得虚列 review-loop.yml。

不返回：

- `verified`：与退出码和 CAS 成功重复；
- subject digest：仅供 crctl 内部 freshness 判断；
- `next`：继续由 `crctl next` 唯一计算，避免 status 推进后立即过时。

删除四个 review Skill 的“重新读取 traceability 核对刚写入结果”步骤；命令成功即表示
三账本同批写入完成，调用方按 `files` 组织提交、按 route 处理分流、最后调用
`crctl next`。

### 6.6 配置文件最小验证

**质询决策（2026-08-09）：复用现有检查器，不新增统一校验框架。**

当前 Phase 0/1 最小验证：

```text
1. git diff --check
2. JSON.parse(feature-writeback.pipeline.json)
3. node --test skills/shared/crctl/scripts/test/crctl.test.mjs
4. node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
5. grep 核对 tools 隐藏特例与把 25/47 当现状的表述已清零
```

不修改、不运行：

- agent-skill matrix 检查族；
- agents contract 检查族；
- writeback scripts 测试；
- engineering-docs 测试；
- 新的 validate-config/schema/Runner。

若实施时实际触及这些权威文件或代码，再按“改了什么测什么”追加对应检查。

## 7. Phase 2：PRD Runner 垂直试点

本阶段是 Phase 0/1 完成后的首个 Runner 候选，不在当前实施范围。只有用户重新确认并
为其建立独立 Spec 后，才用一个低风险完整闭环验证边界；不先建设公共框架。

### 7.1 文件

```text
write-requirement-prd/scripts/prepare.mjs
write-requirement-prd/scripts/finalize.mjs
```

### 7.2 复用边界

复用：

- `write-requirement-prd/SKILL.md` 已形成的 CR 阶段 PRD frontmatter、章节与回修语义；
- `crctl backlog-set`；
- `crctl next`；
- `crctl review-record` 生成的上一轮 feedback；
- `crctl git`；
- `dir-graph.yaml#repositories`。

不恢复：

```text
engineering-docs MCP/CLI
历史 Ajv/gray-matter validator
通用 PRD schema 统一工程
```

现有 engineering-docs 通用 PRD schema 与 CR 阶段 PRD 的 id、必填字段和时间格式不兼容；
本试点只校验 CR 阶段 PRD，不顺手统一两套文档模型。

### 7.3 Prepare

- 解析权威 CR/worktree；
- 读取 CR 元数据、source、现有 PRD；
- 读取上一轮 requirement review feedback；
- 输出本 Skill 的 CR PRD 契约与受保护字段；
- 支持 `--mode create|repair`。

### 7.4 Finalize

- 校验 frontmatter 必填字段与 CR 归属；
- 校验必需章节及 FR/AC 编号；
- 调用 `backlog-set`；
- 经 `crctl git` 显式提交；
- 输出 changed files、commit、status、next 和 warnings。

### 7.5 晋升验收

必须覆盖：

- 首次 create；
- review BLOCK 后 repair；
- repair 后重新 review PASS；
- 非法 frontmatter/章节/编号硬失败；
- CRLF 规范化；
- crctl 非零退出透传；
- Runner 不直接写状态或账本；
- 人工审批与 reviewLoop 强度不变。

## 8. Phase 3：最小公共能力与注册上下文（候选）

只有 Phase 2 通过且 requirement-register 构成第二个真实 Runner 时，本阶段才晋升为
确定 Spec。

### 8.1 公共能力按需提取

若 PRD 与 Registration 确有重复，才新增：

```text
../tools/skills/shared/runner/lib.mjs
../tools/skills/shared/runner/test/runner.test.mjs
```

只允许提取 §4.4 已证明的最小交集。不得为了“后续可能需要”加入通用 workflow、patch、
YAML serializer、状态缓存或动态加载框架。

### 8.2 Requirement Register Runner

候选新增：

```text
../tools/skills/requirement/requirement-register/scripts/run.mjs
```

复用：

- `crctl cr-init`；
- `crctl worktree-path`；
- `crctl git`；
- dir-graph repositories。

不新增：

- register-preflight；
- registration-check；
- stage-context。

### 8.3 Tools root

Runner 统一解析：

1. `workspace.tools_package_path`；
2. `<workspace>/tools`；
3. 当前 package root。

每个候选验证最小标志文件。

### 8.4 Repo context

每个可写 repo 必须出现在机器可读声明中，不允许 Skill 特例。

注册输出至少包括：

```yaml
repositories:
  - id:
    role:
    trunk:
    worktree:
    base-sha:
    branch:
```

### 8.5 Checkpoint 复用

不要新增 `branch-base-set`。

先只复用现有 `checkpoint-add`。只有真实恢复案例证明 remote progress 无法表达
branch-base 或 approved-source 时，才论证 `kind` 扩展；本阶段不预先批准三个 kind。

### 8.6 晋升与验收

- 注册不搜索 Skill 路径；
- CR-ID 仍由 cr-init 分配；
- registration commit 先于 worktree；
- 后续节点不解析 node Markdown；
- 每仓 base/source/worktree 可恢复；
- 隐藏 tools repo 特例消失。

## 9. Phase 4：其余需求、设计与任务文档链路（候选）

Phase 2 的完整 create→BLOCK→repair→PASS→approval 闭环稳定后，按依赖顺序逐个晋升，
不并行铺开所有 Runner。某个 Skill 只有少量机械步骤时可以不 Runner 化。

### 9.1 Requirement Review

新增 prepare/finalize。

评审维度 schema 位于：

```text
review-requirement/
```

不放入 gates.json。

crctl 继续验证通用 payload 形态，Runner 验证 stage 维度。

### 9.2 SDD

prepare：

- PRD；
- 目标 repo；
- ARCHITECTURE；
- 相关 Pipeline/gates；
- 真实代码基线；
- review feedback。

finalize：

- frontmatter；
- 章节；
- FR 覆盖；
- Prompt 采纳影响；
- embedded 状态；
- 提交。

### 9.3 Plan/TASK

LLM 输出 TASK 草稿对象。

Runner 负责：

- TASK-ID；
- slug；
- frontmatter；
- `_index.yml`；
- 依赖图；
- estimate；
- 接口签名；
- 验收条件结构。

每个 TASK 完成后的 done 不在本阶段处理，由 implement-code Runner 处理。

### 9.4 Review Runners

所有 review Runner 统一模式：

```text
prepare：subject + contract + previous evidence + attempt
LLM：verdict/blockers/dimensions/suggestions
finalize：review-record + 状态路由 + commit
```

不得再出现每个 review Skill 自定义账本流程。

## 10. Phase 5：实现、测试与代码评审（候选）

本阶段只在 Authoring/Review Runner 已稳定，且至少完成一个单仓代码 CR、一个多仓代码
CR、一次 code review BLOCK→repair→PASS 后逐项晋升。不得把 Implement、Test 和 Code
Review 作为一个通用执行框架一次性建设。

### 10.1 Implement Code Runner

新增：

```text
implement-code/scripts/prepare.mjs
implement-code/scripts/finalize.mjs
```

prepare 支持：

```text
--task <TASK-ID>
--mode implement|repair
```

输出：

- repo/worktree；
- 依赖；
- 涉及文件；
- 上游接口；
- 定向测试计划；
- review feedback。

finalize：

- changed files；
- 定向测试；
- `crctl task done`；
- 显式 commit；
- 下一批 TASK。

普通代码修改使用宿主 patch 工具，不创建会话临时字符串替换脚本。

### 10.2 Structured Test

优先继续使用现有：

```text
crctl test --cmd
```

只有真实多命令测试计划证明重复传递 cwd/timeout/命令列表无法可靠恢复时，才候选扩展：

```text
crctl test --plan <test-plan.json>
```

使用：

```js
spawnSync(exe, args, {shell:false})
```

记录：

- argv；
- cwd；
- timeout；
- exit；
- log；
- repo HEAD；
- dirty；
- generated-at。

### 10.3 Test Report Runner

prepare 调用 crctl test，并生成 TASK coverage skeleton。

LLM 只补：

- 结果解读；
- 覆盖矩阵；
- 未覆盖风险。

finalize：

- 保护 crctl 生成区；
- 更新 canonical test evidence；
- 提交；
- 输出 next。

### 10.4 Code Review Runner

diff base 来自 registration/checkpoint context，不从 Git log 猜测。

prepare：

- changed files；
- 完整 diff evidence；
- SDD/TASK/test-report；
- 验证命令 replay；
- subject digest。

finalize：

- review-record；
- PASS/BLOCK 状态；
- 提交；
- next。

### 10.5 用户主动扩大范围

首期复用现有机制：

```text
review-note 记录用户决定和 promoted suggestions
→ approve-code:reject -> implement-code
→ code HEAD 改变使 attempt-1 subject digest stale
→ test/report/review attempt-2
```

不新增 `scope-change.yml`。

只有出现多个并行 scope change、跨设备 open-change 恢复或独立统计需求后，再立项 scope-change ledger。

## 11. Phase 6：合并、回写与归档（候选）

本阶段依赖：

- repo context；
- approved checkpoint；
- 全部 TASK done；
- code review/test evidence；
- Runner 基础。

还必须先完成：

- archive `_index.yml` 生命周期语义拍板；
- merge 顺序 push 与补偿边界验证；
- notification/publish/cleanup 三类失败边界定义；
- 使用临时远端完成一次多仓端到端演练。

### 11.1 Merge Runner

新增：

```text
merge-feature-branch/scripts/run.mjs
```

职责：

- 全仓预检；
- merge-tree；
- 本地 no-commit merge；
- commit；
- freshness；
- 顺序 push；
- 补偿；
- merge journal；
- 调用 existing advance/merge-metadata；
- metadata commit/push。

首期不新增大型 `merge-record`。

可对现有 `merge-metadata` 增加 `--from result.json` 批量写入，以一次 CAS 更新 backlog。

### 11.2 Writeback

继续复用：

```text
writeback-prd-sdd.mjs
writeback-tasks.mjs
writeback-traceability.mjs
```

增加一个纯机械入口：

```text
writeback/scripts/run.mjs
```

run.mjs：

1. 全局前置校验；
2. dry-run PRD/SDD；
3. apply PRD/SDD；
4. 推进 writing-back；
5. dry-run/apply TASK；
6. 调用 traceability prepare；
7. 等待 LLM 填编辑性字段；
8. finalize traceability；
9. 按现有恢复边界 commit/push。

首期不增加持久化 plan artifact。apply 前重新验证关键 hash 即可。

### 11.3 Traceability

新增：

```text
writeback-traceability/scripts/prepare.mjs
writeback-traceability/scripts/finalize.mjs
```

prepare 生成完整 skeleton，LLM 只填编辑性字段。

### 11.4 Archive Runner

首次只候选新增：

```text
cr-archive/scripts/run.mjs
```

首版只支持：

```text
--mode normal
```

仅在真实出现可独立恢复的 publish 失败后增加 `publish-retry`；仅在真实出现 cleanup
半完成案例后增加 `cleanup-retry`。不得为假设故障预建两个 mode。

流程：

1. 前置 gate；
2. embedded archived；
3. archive-move（事件 + backlog/history/index 同一 CAS）；
4. 归档 commit/push；
5. 确认远端发布；
6. 清理全部 repo worktree；
7. 删除允许删除的远端分支；
8. 生成 cleanup-report；
9. cleanup commit/push。

publish 失败不得 cleanup。

## 12. Phase 7：按数据决定的可选机制

以下机制首期不实施。

### 12.1 强制 control-plane SHA pin

首期只要求 lifecycle 命令使用稳定 tools root，并在 audit 中记录版本。

出现第二次候选 gate 自举冲突后再实施 SHA pin。

### 12.2 永久 scope-change ledger

只有现有 review-note/reject/subject freshness 无法满足审计时实施。

### 12.3 永久 task reconcile

第二个真实 late-done 恢复案例出现后再升格为 crctl 命令。

### 12.4 Writeback plan artifact

出现真实 dry-run/apply TOCTOU 故障后再增加。

### 12.5 crctl 模块化

单独架构 CR，不能作为 Runner 优化的附带改动。

### 12.6 并行 remote push

当前 repo 数量少，顺序 push 更易补偿。只有指标证明 push 是瓶颈时考虑。

## 13. Spec 拆分建议

该方案覆盖多个独立子系统，不应写成一个超大 CR。

### Spec A：基线与正确性

范围：

- 状态机口径；
- ARCHITECTURE；
- approve 原子提交；
- TASK delivery gate；
- archive event 与账本移动原子化；
- archive 收件人复用 owners；
- archived status；
- archive index 契约；
- review-record 返回。

完成后现有 Pipeline 即更可靠，不依赖 Runner。

### Spec B：PRD Runner 垂直试点

仅在 Phase 0/1 完成并重新确认后创建。候选范围：

- write-requirement-prd prepare/finalize；
- create/repair 双模式；
- CR 阶段 PRD 最小确定性校验；
- backlog-set/next/review-record/crctl git 复用；
- 完整 BLOCK→repair→PASS 闭环。

### Spec C：最小公共能力与 Registration

仅在 Spec B 通过且 Registration 构成第二个真实 Runner后创建。范围：

- 从两个真实调用者提取最小 shared runner lib；
- requirement-register Runner；
- tools root；
- repo/worktree/base context；
- 现有 checkpoint 是否足够的实证结论。

不包含 Pipeline typed outputs。

### Spec D：Authoring 与 Review Runner

范围：

- requirement review；
- SDD；
- tech review；
- Plan/TASK；
- dev-plan review。

### Spec E：Implement/Test/Code Review

范围：

- implement Runner；
- structured test；
- test-report；
- diff evidence；
- code review；
- 用户 scope change 复用方案。

### Spec F：Merge/Writeback/Archive

范围：

- merge Runner/journal；
- merge metadata batch；
- writeback orchestration；
- traceability skeleton；
- archive Runner；
- cleanup-report。

### Spec G：可选高级恢复

仅在数据满足触发条件后创建：

- control-plane pin；
- scope-change ledger；
- task reconcile；
- plan artifact；
- crctl 模块化。

## 14. 实施优先级

| 优先级 | 内容 | 原因 |
|---|---|---|
| P0 | Phase 0 基线统一 | 当前事实源自相矛盾，继续实施会产生错误 Spec |
| P0 | Phase 1 正确性修复 | 已发生 approval、TASK、archive 真实故障 |
| P1（候选，未授权） | PRD 垂直试点 | Phase 0/1 完成后需重新确认 |
| P1（条件式） | 最小公共能力 + Registration | PRD 试点通过且出现第二个真实 Runner 后才晋升 |
| P2（条件式） | 其余 Authoring/Review | 逐个验证，不要求所有 Skill Runner 化 |
| P2（条件式） | Implement/Test/Code Review | 需单仓、多仓和 BLOCK 回修案例证明 |
| P2（最后） | Merge/Writeback/Archive | 高风险远端操作，且依赖 archive/补偿语义拍板 |
| P3 | 可选高级机制 | 必须由真实指标或第二案例触发 |

## 15. 全局测试策略

### 15.0 当前 Phase 0/1

以 §6.6 的 5 项最小验证为完整清单，不因后续候选路线预跑无关测试族。

### 15.1 crctl

- 所有现有测试全绿；
- 新增原语必须含正常、非法状态、CAS、幂等、审计测试；
- 状态机 declared/expanded 数量断言；
- 不引入第三方依赖；
- CRLF 规范化。

### 15.2 Runner（Phase 2+ 候选）

- 每个 Runner 使用临时 workspace；
- 验证 stdout JSON schema；
- 验证非零错误码；
- 验证不直接写账本；
- 验证 Git 文件白名单；
- 验证 Windows/Linux 参数一致；
- 验证 retry/idempotency。

### 15.3 Pipeline（Phase 2+ 候选）

- node ref active；
- reviewLoop/replayNodes 有效；
- human approval 不可跳过；
- Skill/Agent matrix 一致；
- lint-prompts 无 stale/contradicts。

typed outputs 待真正 Pipeline Runner 立项后再加入本节。

### 15.4 端到端（Phase 2+ 候选）

至少覆盖：

1. 无代码的文档 CR；
2. 单仓代码 CR；
3. 多仓 CR；
4. review BLOCK→repair→PASS；
5. 用户主动扩大 scope；
6. merge push 补偿；
7. writeback retry；
8. archive normal；
9. Windows worktree 长路径。

只有对应 retry mode 已由真实案例触发并实现后，才追加 archive publish-retry /
cleanup-retry 端到端用例。

## 16. 成功指标

### 16.1 正确性

- 状态和账本无旁路；
- approval 与 status 同一提交；
- TASK pending 不可回写/归档；
- archive event 不丢失；
- archived CR 可查询；
- 所有参与仓来自机器可读声明；
- 候选工具不会通过隐藏路径治理当前 CR。

### 16.2 效率

目标外部调用量：

| 阶段 | 当前 | 目标 |
|---|---:|---:|
| 注册 | 24 | 8–12 |
| PRD 编写 | 9 | 3 |
| PRD 评审 | 6 | 2–3 |
| SDD 编写 | 14 | 4–6 |
| SDD 回修评审 | 10 | 4–6 |
| Plan/TASK | 11 | 4–5 |
| implement-code | 63 | 25–35 |
| test-report | 7 | 2–3 |
| code review | 10 | 3–4 |
|用户 scope change 回修 | 53 | 12–20 |
| merge | 14 | 2–4 |
| writeback | 18 | 4–7 |
| archive | 8 | 2–3 |

调用量是观测指标，不得通过删除 gate、测试、补偿或人工审批达成。

### 16.3 维护性

- 已证明需要 Runner 的语义 Skill 最多 prepare/finalize 两个入口；
- 已证明需要 Runner 的机械 Skill一个 run 入口；
- 少量机械步骤的 Skill 允许继续保留 prose；
- 无通用 patch/workflow；
- 无基于历史 CR 的 schema 推断；
- 无会话临时账本脚本；
- 无重复 Runner 基础设施；
- 现有 writeback scripts 得到复用。

## 17. 非目标

本方案不包含：

- 重新设计 CR 状态机业务流程；
- 删除 reviewLoop；
- 跳过人工审批；
- 引入数据库账本；
- 引入 YAML 第三方库；
- 建立通用 Workflow Engine；
- 自动实施 review suggestions；
- 并行所有远端 push；
- 一次性重写全部 Skills；
- 附带拆分 crctl.mjs。

## 18. 后续 Spec 的强制问题

每个后续 Spec 必须回答：

1. 为什么该能力属于 crctl、Runner 或 LLM？
2. 是否复用了现有 purpose-specific command？
3. 是否新增权威事实源？
4. 是否直接或间接写账本？
5. 失败后如何重试？
6. 是否依赖历史 CR 形态？
7. 是否改变状态机 declared/expanded 数量？
8. 是否改变人工审批强度？
9. 为什么不能用更少的文件和接口实现？
10. 验收命令和预期输出是什么？
11. 哪个真实案例证明现在必须实施？
12. 现有 crctl/Skill/script 为什么不足？
13. 若新增公共能力，第二个真实调用者是谁？
