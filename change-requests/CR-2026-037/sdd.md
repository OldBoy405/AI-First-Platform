---
id: CR-2026-037-sdd
type: SDD
cr-ref: CR-2026-037
title: crctl TASK 索引初始化与 task-breakdown 门禁闭环技术设计
status: draft
created: "2026-08-13T10:30:00+08:00"
updated: "2026-08-13T10:30:00+08:00"
---

# SDD - crctl TASK 索引初始化与 task-breakdown 门禁闭环

## 1. 架构概览

### 1.1 已有基础设施（直接复用）

目标仓是 tools 自身，其 `ARCHITECTURE.md` 已存在且不修改。当前已具备：

| 能力 | 现有落点 | 本次用法 |
|---|---|---|
| YAML 子集解析 | `lib/yaml-subset.mjs#parseYaml` | 解析 TASK frontmatter 与已有索引，禁止新解析器 |
| frontmatter 提取 | `workspace-transactions.mjs#matchFrontmatter` | 读取 TASK 卡元数据 |
| 状态权威读取 | `crctl.mjs#resolveCrState` | 限定 init 前置态 |
| 受控文件读取/摘要 | `readFileChecked` / `sha256` | TASK 集合 freshness 与索引 CAS |
| CAS replace | `casWrite` | 刷新全 pending 索引 |
| 原子 create-only | Node `fs.openSync(path, 'wx')` | 首次创建索引；文件已存在则失败重读，不覆盖 |
| 审计/输出 | `auditLog` / `ok` / `fail` | 记录 changed=true 写入与结构化结果 |
| TASK 进度写入 | `cmdTaskDone` + `guardDependsOn` | 保持不变；init 不处理 done |
| 门禁声明 | `gates.json` 既有 `fileExists` | task-breakdown 增一个文件存在检查 |
| 开发计划评审 | `review-dev-plan` | 继续判断业务质量、接口与验收，不下沉 crctl |

### 1.2 本次最小改造

| 文件 | 改动 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | 增加 `task init` dispatch、TASK 集合机械校验、确定性渲染、create/CAS、审计；`cmdNext(task-breakdown)` 补缺索引恢复建议 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 增加 init/gate/幂等/错误/CRLF 测试 |
| `skills/shared/crctl/gates.json` | task-breakdown 增 `_index.yml` fileExists |
| `skills/shared/crctl/SKILL.md` | 登记命令接口与错误语义 |
| `skills/develop/write-dev-tasks/SKILL.md` | TASK 内容生成后调用 task init，不再手写索引 |
| `pipeline-templates/code-implementation.pipeline.json` | 节点 prompt 只同步调用顺序与失败中止 |

不新增文件、模块、依赖、事务、manifest、状态或 gate type；不修改 README、Agent/matrix、状态机、版本化脚本或 Multica。

### 1.3 分层与依赖

```text
Agent
  -> 选择 code-implementation Pipeline
Pipeline
  -> write-dev-plan -> write-dev-tasks -> review-dev-plan
write-dev-tasks Skill
  -> 业务拆解并写 TASK-NN.md
  -> crctl task init CR-ID
  -> crctl advance ... task-breakdown
crctl task init
  -> 机械解析 TASK frontmatter
  -> 确定性生成 tasks/_index.yml
  -> create-only / CAS + audit
review-dev-plan
  -> 判断拆分质量、依赖合理性、接口与验收
```

业务判断不进入 crctl；账本算法不留在 Skill/Pipeline；Agent 不拥有状态、Git 或受控写入。

## 2. 数据模型

### 2.1 TASK 输入投影

仅消费每张 `TASK-NN.md` frontmatter：

```ts
type TaskCardProjection = {
  file: string;             // TASK-NN.md，仅错误 detail 使用
  number: number;           // 文件名 NN
  id: string;               // {CR-ID}-TASK-NN
  title: string;
  status: "pending";
  estimate: `${number}h`;   // 正整数
  dependsOn: string[];
  sourceSha256: string;     // 原始文件字节摘要，仅 freshness 重核
};
```

`slug`、正文、验收条件、plan/sdd ref 不进入索引；`cr-ref`、type 仅校验不投影。

### 2.2 Canonical `_index.yml`

```yaml
cr-id: CR-2026-037
tasks:
  - id: CR-2026-037-TASK-01
    title: "含冒号: 也安全"
    status: pending
    estimate: 4h
    depends-on: []
  - id: CR-2026-037-TASK-02
    title: "第二项"
    status: pending
    estimate: 6h
    depends-on: [CR-2026-037-TASK-01]
```

约束：

- TASK 按 `number` 数值升序；
- `title` 使用现有 `yamlStringScalar()`（JSON quoted string 是合法 YAML）；
- `id/estimate/depends-on` 已受格式校验，可用 `yamlScalar`/JSON 数组稳定渲染；
- 仅上述字段，末尾单个 LF；
- 无时间戳、hash、schema-version、slug、路径或评审字段；
- 相同 TASK 集合产生逐字节相同文本。

### 2.3 已有索引进度判定

刷新前解析已有索引：

```text
顶层必须是映射
现有 cr-id 若存在必须等于当前 CR
必须有 tasks 数组
每项必须有 id/status
全部 status 必须精确等于 pending
任何层级出现 done-at 都视为已有进度
```

无法证明“全部 pending”的任何形状都返回 `TASK_INDEX_HAS_PROGRESS`，不尝试修复或迁移。

## 3. 接口契约

### 3.1 CLI

```text
crctl task init <CR-ID> --workspace <knowledge-base CR worktree>
```

成功响应：

```ts
type TaskInitResult = {
  op: "task-init";
  cr: string;
  file: string;
  taskCount: number;
  totalEstimateHours: number;
  changed: boolean;
};
```

无新增 flags；不接受 TASK 数据、candidate、owner、status、timestamp 或 force。CLI help 与 `crctl/SKILL.md` 同步这一行接口，不复制内部算法。

### 3.2 允许状态

```text
tech-design-reviewed -> allow create/refresh
 task-breakdown       -> allow pre-development refresh
其他                  -> ILLEGAL_LEDGER_STATE
```

`task init` 不推进 status。Skill 在成功后调用：

```text
crctl advance <CR-ID> --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed
```

当开发启动暂缓后保持 task-breakdown，Skill 只刷新索引，不再次执行该跨态 advance；按状态机现有 `write-dev-tasks` 自环处理，具体状态推进继续由 Skill 调用现有合法转换，不由 init 猜测。

### 3.3 错误码

| code | 条件 |
|---|---|
| `TASK_SET_EMPTY` | tasks 目录不存在或无 `TASK-NN.md` |
| `TASK_CARD_INVALID` | frontmatter/字段/ID/编号/CR/estimate/status/depends-on 非法 |
| `DEPENDS_ON_UNKNOWN` | 依赖不在本批 TASK 集合（复用既有码） |
| `TASK_DEPENDENCY_CYCLE` | DFS 发现自环或多节点环 |
| `TASK_INDEX_HAS_PROGRESS` | 已有索引不全 pending、含 done-at 或形状损坏 |
| `TASK_SET_CHANGED` | 初读后 TASK 文件集合或任一原始字节摘要变化 |
| `CAS_CONFLICT` | 已有索引在读取后变化（复用既有码） |
| `ILLEGAL_LEDGER_STATE` | 当前状态不允许 init（复用既有码） |

所有失败发生在索引写入和成功审计前。

### 3.4 幂等与审计

- canonical 文本等于现有索引 LF 规范化文本：返回 `changed=false`，不写文件、不追加成功 audit；
- create/replace 成功：返回 `changed=true`，追加一条 `{kind:'ledger',op:'task-init',cr,actor,taskCount,changed:true}`；
- no-op 不追加审计，保证重复执行没有时间/审计漂移；
- 不发 outbox：TASK 规划索引不是跨设备状态事件，后续 status/checkpoint 走既有通道。

## 4. 关键算法与流程

### 4.1 读取与校验 TASK 集合

```text
loadTaskCards(ws, cr):
  dir = change-requests/{cr}/tasks
  names = readdir(dir).filter(/^TASK-(\d{2})\.md$/).sort(number)
  if empty -> TASK_SET_EMPTY

  for each name:
    raw = readFileChecked
    norm = raw.replaceAll('\r\n', '\n')
    fm = matchFrontmatter(norm); missing -> TASK_CARD_INVALID(file, frontmatter)
    doc = parseYaml(fm.body); shape invalid -> TASK_CARD_INVALID
    require:
      doc.id == `${cr}-TASK-${NN}`
      doc.type == TASK
      doc['cr-ref'] == cr
      non-empty string title
      doc.status == pending
      estimate matches /^[1-9]\d*h$/
      depends-on is array of strings
    reject duplicate number/id
    collect sourceSha256 = sha256(raw)

  byId = Map(cards)
  for each dependency:
    missing -> DEPENDS_ON_UNKNOWN
  DFS white/gray/black:
    gray revisit -> TASK_DEPENDENCY_CYCLE
  return cards
```

只识别两位编号的 canonical 文件；其他 Markdown 不作为 TASK 输入，也不报错，避免 README/说明文件误入。`write-dev-tasks` 已规定两位编号。

### 4.2 Freshness 重核

写索引前再次读取目录：

1. 重新计算匹配文件名列表，必须与初读完全相同；
2. 每个文件重新读取原始字节并比较 SHA-256；
3. 任一差异返回 `TASK_SET_CHANGED`。

该重核只防止“解析后、写索引前”的并发陈旧投影，不提供多文件事务，也不锁 TASK 内容文件；调用方重跑即可。

### 4.3 确定性渲染

局部纯函数 `renderTaskIndex(cr, cards)` 用数组 `join('\n')` 构造 canonical 文本。它不读写文件、不取时间、不访问状态，直接由单元测试覆盖特殊 title、依赖数组和顺序。

### 4.4 Create / refresh / no-op

```text
cmdTaskInit:
  validate state
  cards = loadTaskCards()
  canonical = renderTaskIndex()
  indexRaw = readFileChecked(indexPath)

  if indexRaw != null:
    validateExistingIndexHasNoProgress(indexRaw)
    expectedHash = sha256(indexRaw)
    recheckTaskCardsFreshness()
    if normalizeLF(indexRaw) == canonical:
      ok(changed=false); return
    casWrite(indexPath, expectedHash, canonical)
  else:
    recheckTaskCardsFreshness()
    try:
      fd = fs.openSync(indexPath, 'wx')
      fs.writeFileSync(fd, canonical, 'utf8')
      fs.closeSync(fd)
    catch EEXIST:
      fail CAS_CONFLICT
    finally close fd if needed

  auditLog(changed=true)
  ok(changed=true)
```

`wx` 是 Node/文件系统原生原子 create-only；不先“exists then write”制造 TOCTOU，不为单文件初始化引入 durable transaction。replace 继续复用现有 CAS。

### 4.5 门禁与 next

`gates.json`：

```json
"task-breakdown": [
  {"type":"fileExists","path":"change-requests/{cr}/plan.md"},
  {"type":"fileExists","path":"change-requests/{cr}/tasks/_index.yml"},
  {"type":"globNonEmpty","dir":"change-requests/{cr}/tasks","pattern":"^TASK-\\d+.*\\.md$"}
]
```

`cmdNext(task-breakdown)` 在检查 tasks 目录后增加 index 文件检查；缺失时建议 `write-dev-tasks`，why 指明先调用 `crctl task init`。这只修复恢复提示，不复制 gate 判定算法。

### 4.6 Skill/Pipeline 采纳

`write-dev-tasks`：

```text
生成/回修 TASK-NN.md
-> crctl task init CR
-> 对比 result.totalEstimateHours 与 plan 总估算
-> 初次：advance tech-design-reviewed -> task-breakdown
-> task-breakdown 自环重拆：按现有合法 write-dev-tasks 转换处理
-> crctl git add/commit
```

Pipeline prompt 只保留“写 TASK → 调 task init → advance → 输出列表”的顺序和失败中止；删除“同时生成 `_index.yml`”的直写表述，不嵌入字段校验、DAG、CAS 或 YAML 格式。

### 4.7 Bootstrap

CR-2026-037 在命令合入前仍需人类一次性创建自身 `_index.yml`。该动作不由 Agent/Skill/脚本执行；内容必须与本 CR 已审批 Plan/TASK frontmatter一致，在开发启动前由人类审阅并提交。例外只覆盖该文件首次创建，不覆盖 status、审批、后续 done 写入或其他 CR；task init 合入后失效。

CR-2026-032 必须等待修复合入 `custom/main`，再从权威 Tools Root 调正式命令，禁止调用候选 worktree 的 crctl。

## 5. 技术选型与替代方案

| 决策 | 采纳 | 否决 | 原因 |
|---|---|---|---|
| 输入来源 | 扫描 TASK frontmatter | JSON/YAML manifest 或 CLI 多参数 | TASK 卡已是唯一业务输入，manifest 会多一份事实源 |
| 代码落点 | 现有 `crctl.mjs` 局部 helper | 新 task-index 模块/版本化脚本 | 改动小、单一调用者；账本写必须留 crctl |
| 创建原语 | Node `openSync('wx')` | durable transaction / exists+write | 单文件 create-only 已由原生原子语义覆盖 |
| 刷新原语 | 现有 `casWrite` | 新 WAL/锁 | 全 pending 单文件替换，CAS 足够 |
| YAML | 现有 parseYaml + 字符串渲染 | 第三方 YAML 库 | 零依赖不变量；输出 shape 固定且很小 |
| DAG | 简单 DFS | 图依赖/拓扑库 | O(n+e) 标准算法，几十行内完成 |
| Gate | 新增 fileExists | 新 gate 类型/深内容校验 | 可信入口 + review-dev-plan 已覆盖语义 |
| generic validate | 不做 | 同 CR 接 PLAN/TASK schema | schema ID 与实际文档冲突，属于独立治理问题 |
| 审计 | changed=true 才写 | no-op 也追加 | 幂等重放不应制造时间/审计漂移 |

## 6. FR 到技术实现映射

| FR | 落点 | 测试 |
|---|---|---|
| FR-01 | §3.1、§4.1、dispatch/help | 创建成功、无数据参数、无状态推进 |
| FR-02 | §2.1、§4.1 | 空集、坏 frontmatter、字段/ID/estimate/depends 错、悬空、环 |
| FR-03 | §2.2、§4.3 | 排序、title 转义、字节稳定、字段白名单 |
| FR-04 | §2.3、§3.2、§4.4 | 两允许态、developing 拒绝、done/损坏拒绝 |
| FR-05 | §3.4、§4.2～4.4 | create-only race、replace CAS、TASK freshness、no-op、audit |
| FR-06 | §4.5 | 缺索引 gate/advance block，补齐后 pass |
| FR-07 | §4.6、§8 | Skill/Pipeline/crctl Skill/help 文案与 JSON parse |
| FR-08 | §4.7 | 人类 bootstrap 边界审计；CR-032 只用已合入 Tools Root |
| FR-09 | §1.2、§5、§7.4 | changed-files 白名单与排除项 |

覆盖率：9/9。

## 7. 安全、性能、兼容与回滚

### 7.1 安全与一致性

- 路径由固定 CR 根和严格文件名构造，不接受任意 path；
- TASK 文本不进入 audit/outbox；错误只含文件名、字段和 ID；
- create 用 `wx`，refresh 用 hash-CAS；TASK 集合另做 freshness 重核；
- 已有进度 fail-closed，不尝试保留/合并 done 状态；
- parser 读入先 CRLF→LF，解析失败硬失败。

### 7.2 性能

单次两遍读取 TASK 卡，时间 O(n+e+bytes)，空间 O(n+e+bytes)。TASK 数量小，无缓存、并发或网络需求。

### 7.3 兼容性

- `task done` 与其一跳依赖守卫零改动；
- 现有索引 reader 继续消费相同 tasks 数组；新增顶层 `cr-id` 已被现有 YAML reader容忍，近期 CR 已使用该字段；
- 老索引只在显式调用 init 且能证明全 pending 时才 canonicalize，不做批量迁移；
- 状态机、reviewLoop、审批和 Pipeline 节点数不变。

### 7.4 回滚

按单个实现提交 revert 六个白名单文件。回滚后不删除已生成索引：它仍是现有 `task done`/review/writeback 可读的合法账本；只会恢复“无法由 crctl 首次生成”的旧缺口。不得回滚为 Skill 手写索引。

## 8. Prompt 采纳影响

本 CR 新增 `crctl.mjs` dispatch 分支，因此本节必填：

| 消费方 | 现状 | 改为 |
|---|---|---|
| `skills/develop/write-dev-tasks/SKILL.md` | 指导模型生成 TASK 和 `_index.yml` | 只写 TASK 内容卡，然后调用 `crctl task init`；按返回总工时交叉校验，再 advance |
| `pipeline-templates/code-implementation.pipeline.json` 的“拆分开发任务”节点 | prompt 写“同时生成 tasks/_index.yml” | 改为“生成 TASK-NN.md 后调用 task init”；不复制算法 |
| `skills/shared/crctl/SKILL.md` | task 只有 done | 增 init 一行接口、状态与核心错误语义 |
| CLI `HELP` / task dispatch 错误 | 仅列 done | 同步 init 与 done 两个子命令 |

Agent 不需要知道 task-init 算法或新增权限；README 不承担命令细节；其他 Pipeline 不调用该能力。

## 9. 验证计划

定向测试全部追加在现有 `crctl.test.mjs`，复用 fixture helper：

1. 合法 4 卡 create：顺序/字段/总工时/audit；
2. 同内容 no-op：changed=false、字节与 audit 数不变；
3. 全 pending refresh：CAS replace；
4. existing done/done-at/损坏：原字节不变；
5. tech-design-reviewed/task-breakdown 放行，developing 拒绝；
6. 空目录、无 frontmatter、ID/文件/CR/type/title/status/estimate/depends-on 错；
7. 悬空、自环、双节点环；
8. LF/CRLF 等价、特殊 title 安全；
9. TASK 集合/字节 freshness 变化；
10. create EEXIST 与 replace CAS 冲突；
11. task-breakdown 缺 index gate/advance block，补齐 pass；
12. cmdNext 缺 index 建议 write-dev-tasks；
13. 现有 task done/dev-plan/dev-start 回归；
14. lint-prompts、Skill/Agent contract、Pipeline JSON parse。

不新增 production fault point或测试文件。

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 初始设计：单一 task init、原生 create-only + CAS refresh、TASK freshness/DAG/progress guard、索引门禁、Skill/Pipeline 采纳与 bootstrap 边界；FR 9/9 |
