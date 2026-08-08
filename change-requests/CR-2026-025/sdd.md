---
id: CR-2026-025-sdd
type: SDD
cr-ref: CR-2026-025
title: crctl 守卫与回显收敛（check-skill-matrix external 引用校验 + depends-on 依赖守卫 + gate/advance blockers 回显截断 + review-record 投影一致性）技术设计
status: draft
created: "2026-08-09T01:20:00+08:00"
updated: "2026-08-09T01:20:00+08:00"
---

# SDD — crctl 守卫与回显收敛

> **实施顺序前提（PRD D-3 / NFR-5）**：本 CR 项①的实施与验证必须在 CR-2026-024 批次一合入 `custom/main` 之后进行；否则 B-3 的存量零引用声明会让新规则上线即报红。项②③④与 CR-2026-024 无顺序耦合，可先行。

## 1. 架构概览

### 1.1 目标仓与改动面

目标代码仓 = **tools 仓自身**（方法论包）。全部改动收敛在四个既有执行面，不新增模块、不新增目录（测试文件落在既有 `scripts/test/`）：

| # | 文件 | 改动性质 | 承载项 |
|---|---|---|---|
| F-1 | `skills/shared/crctl/scripts/check-skill-matrix.mjs` | 修改（新增检查 4 + 解析扩展 + CRLF 规范化） | ① |
| F-2 | `skills/shared/crctl/scripts/crctl.mjs` | 修改（`cmdTaskDone` 守卫 / `evaluatePassCondition` 回显收敛 / `cmdReviewRecord` 三账本一致写 / `cmdNext` drafting 路由） | ②③④ |
| F-3 | `skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` | **新建**（该脚本首个测试，B-13） | ① |
| F-4 | `skills/shared/crctl/scripts/test/crctl.test.mjs` | 追加向量 | ②③④ |
| F-5 | `agent-skill-matrix.yml` | 顶层 `external-skills:` 块上方加注释（块内容不动，D-2） | ① |
| F-6 | `AGENT-SKILL-MATRIX.md` | L57 声明位置表述收敛（D-2） | ① |
| F-7 | `skills/_index.yml` | L313-317 注释去点名化（FR-4） | ① |
| F-8 | `skills/shared/crctl/SKILL.md` | 用途表补 `task done` 守卫与两错误码（FR-9） | ② |
| F-9 | `skills/develop/implement-code/SKILL.md` | 拓扑排序表述补一句机械强制（FR-9） | ② |
| F-10 | `README.md` | 若含 `task done` 行为描述则同步（FR-9 条件项，实施期确认） | ② |
| F-11 | `ARCHITECTURE.md` | §8 登记本 CR（FR-24） | 收尾 |

**不改动**：`dir-graph.yaml`（状态机）、`gates.json`、`controlled-shell/rules.json`、pipeline JSON——与 NFR-2/NFR-4 一致。FR-24 中"dir-graph.yaml 同步"一项经实测：tools 仓 `dir-graph.yaml` 无脚本级文件清单面（grep `test.mjs`/`scripts/` 零命中），登记落点收敛为 `ARCHITECTURE.md` §8；若实施期发现可登记面再按 PRD 补。

### 1.2 依赖方向与不变量符合性

改动全部发生在 ARCHITECTURE.md §4 依赖图的最底层（crctl 执行器）与平行的校验脚本层，无向上依赖引入：

- **不变量 1（状态单一写者）**：四项均不写 status。
- **不变量 2（账本单一写入通道）**：项④把 `traceability.yml#reviews.<stage>` 投影**收编进 crctl `review-record`**（CAS + 审计同一条写入路径），正是强化该不变量；收编后三个 review-* SKILL 的手工投影步骤废弃（见 §8）。
- **不变量 3（零第三方依赖）**：全部 `node:` 内置模块；测试仅 `node:test`/`node:assert` + `spawnSync`（B-14）。
- **不变量 4（行尾与硬失败）**：F-1/F-2 所有新增读入点先 `\r\n → \n`，解析失败硬失败（§4 逐项落实）。
- **不变量 7（审批无旁路）**：项②③④不触审批路径。
- **§6 否决面**：不引入独立账本脚本库、不引入 WAL、不引入 YAML 序列化库（项④复用行级定点编辑 + `casWriteMulti`）。

## 2. 数据模型

### 2.1 项① — `externalByActor`（进程内结构，不持久化）

```js
// check-skill-matrix.mjs 解析期产物
externalSkills: Set<string>            // 既有，保持不变（检查 2 继续消费）
externalByActor: Map<actor, string[]>  // 新增：记录声明来源，仅供检查 4 错误文案
```

持久化数据（`agent-skill-matrix.yml`）结构不变，只加注释行。

### 2.2 项② — `depends-on`（既有字段，无 schema 变化）

`tasks/_index.yml` 任务条目既有形态（B-7/B-8 实测）：

```yaml
- id: CR-2026-XXX-TASK-02
  slug: xxx
  status: pending
  depends-on: [CR-2026-XXX-TASK-01]      # 内联流式数组；可缺失；可带引号 ["ID"]
```

守卫只消费该字段，不新增字段、不改写形态；`task allocate` 生成的无 `depends-on` 条目按 D-5 视为无依赖。

### 2.3 项③ — 无数据模型变化

`gate.checks[].detail[]` 的 JSON 结构层级与字段名不变（NFR-3）；仅 `isEmpty` 数组失败分支的 `actual` 元素内容被截断、`why` 改为条数指针。

### 2.4 项④ — annotation 新增字段与 traceability 投影形态

**requirement annotation**（`review-annotations/requirement.yml`）新增两个向后兼容标量（NFR-2）：

```yaml
subject-file: change-requests/CR-2026-025/prd.md
subject-sha256: "<LF 规范化后全文的 SHA-256 全量 hex>"
```

**traceability 投影**（三 stage 同构，字段集与 review-requirement SKILL.md Step 4 既有模板对齐）：

```yaml
reviews:
  requirement:                      # tech-design / code 同构
    reviewer: "<identity(ws)>"
    verdict: pass | block
    reviewed-at: "<recordedAt>"     # 与 annotation、review-loop 同一时间戳（FR-17）
    blocker-count: <N>
    annotation: "change-requests/{cr}/review-annotations/<stage-file>"
    repair-target: write-requirement-prd | write-tech-design | implement-code
    review-loop:
      current-attempt: <N>
      max-attempts: <M>             # 运行时读自 pipeline JSON reviewLoop.maxAttempts
      attempts:
        - attempt: <N>
          reviewed-at: "<ts>"
          result: pass | block
          blocker-count: <N>
          repair-target: <同上>
```

`review-loop.yml` 形态完全不变（仍由 crctl 全量生成，B-16 后半段只是并入同批写入）。

## 3. 接口契约

### 3.1 CLI 行为契约（无新增子命令/旗标，NFR-2）

| 命令 | 新增/变更行为 | 错误码 |
|---|---|---|
| `crctl task done <cr> --task <id>` | CAS 写入前校验目标 TASK 直接 `depends-on`（一跳） | `DEPENDS_ON_NOT_DONE`（detail 列出每个未完成前置的 `{id, status}`；message 末尾追加"若前置互相等待，检查 depends-on 是否成环"）；`DEPENDS_ON_UNKNOWN`（引用不存在于 `_index.yml` 的 TASK-ID） |
| `crctl gate / advance`（失败路径） | `isEmpty` 数组失败 detail：`actual` 保持数组、逐项 ≤120 字符截断；`why` 只给条数与证据文件指针 | 错误码不变（`GATE_BLOCKED` 等） |
| `crctl review-record <cr> --stage <s> [--bump-attempt]` | 一次写入 annotation + review-loop.yml（仅 bump 时）+ traceability 投影；`--stage requirement` 额外写 `subject-file`/`subject-sha256` | 新增结构化失败：`TRACE_SHAPE`（traceability CR-ID 不匹配/无法唯一定位），失败时三文件均不落盘、临时 payload 保留 |
| `crctl next <cr>`（仅 `drafting`） | 按 §4.4 决策表路由 | 只读命令，无错误码变化 |
| `node check-skill-matrix.mjs` | 新增检查 4：external 零引用点报红 | 退出码非 0，stderr 含技能名与声明 actor 列表 |

### 3.2 调用方兼容承诺

- `actual` 数组类型不变，`.length`/索引取值安全（FR-13/US-6）。
- 缺 `subject-sha256` 的旧 annotation：`cmdNext` 维持改动前行为（PRD 存在即 `review-requirement`），不做历史迁移（FR-20⑤）。
- `equals` 分支、`runGateChecks` 顶层 check、`cmdAdvance` 汇总、`fail()` 输出形态零变化（D-9）。

## 4. 关键算法与流程

### 4.1 项① — external 引用点扫描（检查 4）

```text
输入: externalByActor（§2.1）
scanRoots = [skills/, pipeline-templates/]
excludeDirs = {openwiki, old, node_modules, .git}           # 目录级排除（FR-2）
selfFiles = {agent-skill-matrix.yml, AGENT-SKILL-MATRIX.md} # 声明面不自证（FR-2）

files = walk(scanRoots) 中扩展名为 .md/.json 且路径不含 excludeDirs 的文件
for name in union(externalByActor.values()):
    refs = files.filter(f => readText(f).includes(name))   # 子串匹配，与 CR-2026-024 口径一致
    if refs.length == 0:
        errors.push(`[零引用点] external "${name}" 由 ${声明 actors 全列} 声明，但扫描范围内无任何引用点`)
```

要点：
- 粒度为**全局名级**（D-1）：任一文件命中即通过，不要求命中位于声明 actor 的 owns 面。
- 文件读入统一经一个 `readNorm(path)` 辅助（readFileSync → `replaceAll('\r\n','\n')`），现有三个解析段的读入点同步改经该函数（FR-3 行尾纪律）。
- 检查 1/2/3 逻辑零改动；文件头注释"检查项"清单补第 4 条（FR-1/AC-3）。
- 复杂度：O(文件数 × 平均文本长 × external 名数)，tools 仓当前量级（<500 文件）毫秒级，无缓存需求。

### 4.2 项② — `task done` 一跳依赖守卫

插入位置：`cmdTaskDone` 既有三项校验（status=developing / 文件存在 / —— TASK 存在与已 done 由 `editTaskDone` 内校验）之后、`casWrite` 之前。守卫读的是**同一份已读入的 `_index.yml` 文本**，不重复读盘：

```text
guardDependsOn(normText, taskId):          # normText = 已 CRLF 规范化的 _index.yml
    idx = parseYaml(normText)              # 复用既有 parseYaml（FR-8/NFR-8，禁新写解析）
    tasks = idx.tasks || []
    byId = Map(tasks.map(t => [t.id, t]))
    target = byId.get(taskId)              # 缺失由后续 editTaskDone 的 TASK_NOT_FOUND 兜底
    deps = target?.['depends-on']
    if deps == null or deps == []: return  # D-5：缺失/空数组 = 无依赖，放行
    unknown = deps.filter(d => !byId.has(d))
    if unknown.length: fail('DEPENDS_ON_UNKNOWN', ..., { unknown })
    notDone = deps.filter(d => byId.get(d).status != 'done')
    if notDone.length:
        fail('DEPENDS_ON_NOT_DONE', `...未完成前置 ${...}。若前置互相等待，检查 depends-on 是否成环`,
             { notDone: notDone.map(d => ({ id: d, status: byId.get(d).status })) })
```

要点：
- 一跳口径（D-6）：不做传递闭包、不检测环；A→B→A 与 A→A 夹具下环上成员直接前置互不 done，天然全部拒写，无遍历死循环（AC-10）。
- 带引号形态 `["ID"]` 由 `parseYaml` 的标量 unquote 路径消化（B-7 实测），测试向量⑤钉住（FR-10）。
- `depends-on` 解析出非数组形态（如标量）时按 `TRACE_SHAPE` 同类硬失败原则报 `DEPENDS_ON_SHAPE`——宁硬失败不猜语义（纪律 #1）。

### 4.3 项③ — `isEmpty` 失败回显收敛

仅改 `evaluatePassCondition` 的 `isEmpty === true` 失败分支（L552-554）：

```js
const ITEM_MAX = 120;
// 纯函数：数组逐项截断；非字符串项原样保留；超长字符串追加 …(+N字)
function briefArray(v) {
  return v.map((x) => (typeof x === 'string' && x.length > ITEM_MAX)
    ? x.slice(0, ITEM_MAX) + `…(+${x.length - ITEM_MAX}字)` : x);
}
// 失败分支改为：
actual: Array.isArray(val) ? briefArray(val) : (val ?? null),
why: Array.isArray(val)
  ? `期望 ${fieldPath} 为空，实际 ${val.length} 条（详见 ${doc.path}）`
  : `期望 ${fieldPath} 为空，实际 ${JSON.stringify(val)}`,
```

改动处注释必须写明（FR-14）：**只封单条长度、不封条数**，条目极多时输出仍线性增长；全量原文唯一来源是 `file` 字段指向的 `review-annotations/{stage}.yml`。`equals` 分支与标量 `isEmpty`（非数组）路径保持现状（D-9）。

### 4.4 项④ — 三账本一致写与 cmdNext 路由

**a. `cmdReviewRecord` 重构为「全校验 → 一次生成 → `casWriteMulti`」**（FR-17/D-11）：

```text
1. 前置校验（全部在写任何文件之前）：
   stage 映射合法 → 前置态合法（REVIEW_STAGE_EXPECT）→ payload schema（现有三项）
   → --bump-attempt 时 readAttempts 未 exhausted → traceability 若存在则结构校验（§4.4c）
   → CR-ID 一致性（traceability 头 cr-id == cr）
2. const recordedAt = nowIso()                # 一次生成，三账本共用
3. 构造三份新文本：
   annotationText  ← 现有 lines 拼装 + requirement 时追加 subject-file/subject-sha256
   traceText       ← upsertReviewsStage(traceText 或最小骨架, stage, 投影块)
   loopText        ← bump 时：基于 readAttempts + recordedAt 生成的新轮次文本
                     非 bump 时：review-loop.yml 不写（保留原文），投影取其当前轮次
4. casWriteMulti([annotation(首建 expectedHash=null), trace, ...(bump?[loop]:[])])
5. 审计 + outbox（现有），删除临时 payload（现有）
```

实施要点：`bumpAttempt` 现读-写一体（L872-892 直接 `writeFileSync`）；拆出纯函数 `nextLoopText(loops, loopRef, recordedAt, identity)` 供 review-record 组装文本，`bumpAttempt` 本体改为「read → nextLoopText → write」组合，`crctl attempt` 独立子命令行为不变。这是消除"annotation 已写而 loop 写失败"半状态（B-16）的最小改法。

**b. `subject-sha256` 计算**（FR-19/D-12）：

```js
sha256(readFileSync(prdPath, 'utf8').replaceAll('\r\n', '\n'))  // 全量 hex
```

仅 `--stage requirement` 写入；tech-design/code 本次不新增摘要消费（PRD §7 排除项）。

**c. `upsertReviewsStage` 行级定点编辑**（FR-18，风格对齐既有 `matchEntryBlock`/`editTaskDone`）：

```text
输入: trace 原文（已 LF 规范化）或 null, stage, 投影块文本（2 空格基准缩进）
- null → 返回最小骨架：`cr-id: {cr}\nreviews:\n` + 投影块
- 顶层 cr-id 解析 != cr → fail('TRACE_SHAPE')
- 定位 `reviews:` 行（顶层，0 缩进）：
    无 → fail('TRACE_SHAPE')（不猜位置插入顶层键，避免破坏未知结构）
- 在 reviews 块内定位 `  {stage}:` 子块（2 缩进，到下一个 ≤2 缩进键为止）：
    命中 → 整块替换为新投影
    未命中 → 在 reviews 块末尾追加
- 其余行逐字节保留（tests/未知扩展段不受影响，AC-19/AC-21）
- 同一段内出现两个同名 stage 键 → fail('TRACE_SHAPE')（不静默择一）
```

**d. `cmdNext` drafting 决策表**（FR-20，替换 L2215-2218）：

| 优先级 | 条件 | 建议节点 | why 要点 |
|---|---|---|---|
| ① | `prd.md` 缺失 | `write-requirement-prd` | 现状保留 |
| ② | requirement annotation `verdict=block` 或 `blockers` 非空，且 `subject-sha256` == 当前 PRD 规范化摘要 | `write-requirement-prd` | blocker 条数 + annotation 路径 |
| ③ | 同上失败证据但摘要不同（PRD 已变化） | `review-requirement` | 证据已过时，需刷新 |
| ④ | 无失败证据（含 pass/缺失/无摘要旧证据） | `review-requirement` | 现状保留（兼容，FR-20⑤） |

"失败证据"定义 = `verdict=block` 或 `blockers.length>0`；`passAndClean` 语义不受影响。不使用 mtime（D-12）。

### 4.5 端到端流程（项④闭环示意）

```text
review-requirement(block) → review-record 落盘(annotation 含 prd 摘要)
  → cmdNext: 摘要相同 → write-requirement-prd（回修）
  → PRD 实质修订 → cmdNext: 摘要不同 → review-requirement（重审）
  → review-record(pass, --bump-attempt) → 三账本同批落盘 → advance requirement-reviewing
```

## 5. 技术选型与替代方案

PRD D-1~D-12 已全部拍板，此处不复述理由，只补两个实施级选择：

| # | 选择 | 采纳 | 否决的替代 | 理由 |
|---|---|---|---|---|
| I-1 | `bumpAttempt` 拆读-算-写 | 拆出 `nextLoopText` 纯函数 | review-record 内直接调用现有 `bumpAttempt` | 现有实现读后立即落盘，无法满足"三文件同批 CAS"（FR-17）；拆分后 `crctl attempt` 组合调用行为不变 |
| I-2 | traceability 投影用行级定点编辑 | `upsertReviewsStage`（§4.4c） | parseYaml→改对象→序列化回写 | 违反不变量 3（禁通用序列化器）且全量重排打乱注释/字段序（§6 否决记录） |
| I-3 | 检查 4 用子串匹配 | `text.includes(name)` | 词法级精确匹配（word boundary） | 与 CR-2026-024 认定死声明的口径一致（FR-2）；精确匹配是另一取舍，PRD 已把"引用有效性"列为排除项 |

## 6. FR 到技术实现映射

| FR | 落点 | 测试锚点 |
|---|---|---|
| FR-1 | F-1 检查 4 + 头注释 | AC-1/AC-3，F-3 向量②④ |
| FR-2 | F-1 §4.1 扫描口径 | AC-2，F-3 向量①② |
| FR-3 | F-1 `externalByActor` + `readNorm` | F-3 向量③④⑤ |
| FR-4 | F-5/F-6/F-7 三处声明面修订 | AC-4 |
| FR-5 | F-3 新建测试文件 | AC-6 |
| FR-6 | F-2 `guardDependsOn`（§4.2） | AC-7/AC-8，F-4 向量①② |
| FR-7 | F-2 缺失/空放行 + `DEPENDS_ON_UNKNOWN` | AC-9，F-4 向量③④ |
| FR-8 | F-2 复用 `parseYaml`，零新解析 | AC-10，F-4 向量⑤ |
| FR-9 | F-8/F-9/F-10 文档同步 | AC-11 |
| FR-10 | F-4 五类向量 | AC-15 |
| FR-11 | F-2 `ITEM_MAX`/`briefArray`（§4.3） | AC-12，F-4 项③向量①② |
| FR-12 | F-2 `why` 收敛（§4.3） | AC-12/AC-13 |
| FR-13 | F-2 数组类型保持 | AC-12，F-4 断言② |
| FR-14 | F-2 改动处注释 | AC-14 |
| FR-15 | F-4 五类向量 | AC-15 |
| FR-16 | F-2 `upsertReviewsStage` 三 stage 同一函数（§4.4c） | AC-19，F-4 项④向量① |
| FR-17 | F-2 全校验→单时间戳→`casWriteMulti`（§4.4a） | AC-20，F-4 向量②④ |
| FR-18 | F-2 骨架创建 + 定点替换 + 硬失败（§4.4c） | AC-21，F-4 向量③④ |
| FR-19 | F-2 `subject-file`/`subject-sha256`（§4.4b） | AC-22 |
| FR-20 | F-2 `cmdNext` drafting 决策表（§4.4d） | AC-22，F-4 向量⑤⑥⑦⑧ |
| FR-21 | F-4 八类向量 | AC-23 |
| FR-22 | 验证关卡（三件套 + 三测试文件） | AC-16 |
| FR-23 | commit 溯源标注 + 无本机绝对路径 | AC-17 |
| FR-24 | F-11 `ARCHITECTURE.md` §8 登记（§1.1 注：dir-graph.yaml 无脚本清单面） | AC-17 |

覆盖率：24/24。

## 7. 安全与性能考量

**一致性/安全**：
- 项④三账本写入沿用 `casWriteMulti` 三阶段语义；连续 rename 间的微秒级崩溃窗口继承 B-18 已接受的判定（§6 否决 WAL），不另造恢复机制。
- 所有新增失败路径走既有 `fail(code, message, extra)`，无裸异常；审计/outbox 挂接现有管道。
- 无新增外部输入面（全部本地文件读写）；`DEPENDS_ON_*` detail 只回显账本内已有 id/status，无信息扩散。

**性能**：
- 检查 4 扫描为 O(文件 × 文本 × 名称数)，tools 仓量级毫秒级，不引入缓存。
- `task done` 守卫复用 `cmdTaskDone` 已读入文本，只增一次 `parseYaml`（同文件），无新增 I/O。
- `cmdNext` 新增一次 annotation 读取与一次 PRD 摘要计算，仅 drafting 态触发，可忽略。

**边界条件清单**（全部进测试向量）：环（A→B→A / A→A）、带引号 TASK-ID、`depends-on` 缺失/空/悬空/非数组、CRLF↔LF 等价、traceability 缺失/含未知段/CR-ID 不匹配/重复 stage、无摘要旧 annotation、CAS 注入失败三文件不动。

**已知文档同步缺口（非 blocker）**：`openwiki/architecture/agent-skill-matrix.md` 描述 checker 为"3 项检查"，项①上线后过时；openwiki 为文档镜像、非门禁面，实施期顺手同步一句，不单独成任务。

## 8. Prompt 采纳影响（必填：触及 crctl.mjs 子命令语义）

本 CR 不新增 crctl dispatch 分支、不触 `rules.json` deny 面，但**三个既有子命令的行为语义扩展**需以下 Skill 采纳核对（lint-prompts 机械抓不到此类）：

| # | Skill | 现状 | 应改为 |
|---|---|---|---|
| P-1 | `skills/develop/implement-code/SKILL.md` | prompt 层拓扑排序建议（CR-2026-024 落） | 补一句「依赖顺序由 `crctl task done` 机械强制」（FR-9，PRD 已列） |
| P-2 | `skills/requirement/review-requirement/SKILL.md` Step 4 | 指导模型手写 `traceability.yml#reviews.requirement` 投影（本 worktree 现存陈旧投影即该手工路径的实证漂移） | 改为「投影由 `crctl review-record` 同步写入，本步骤只做落盘后核对」 |
| P-3 | `skills/develop/review-tech-design/SKILL.md` Step 4（"更新 traceability.yml 并处理 status"） | 同上手写投影语义 | 同 P-2 改法 |
| P-4 | `skills/develop/review-code/SKILL.md`（若有对应投影步骤，实施期核实；B-17 三 stage 同契约） | 同上 | 同 P-2 改法 |
| P-5 | `skills/shared/crctl/SKILL.md` 用途表 | `task done` 无守卫描述、`review-record` 无投影描述 | 补守卫与两错误码（FR-9）+ review-record 投影语义一句 |

P-2~P-4 的提示词修订随本 CR 代码同批提交（纯 prompt 修改不另开 CR，符合本仓 prompt 免 CR 规范），由 `lint-prompts --mode enforce` 兜底校验无 CONTRADICTS/STALE 残留。`crctl next` 消费方（最小 pipeline-runner 等）按输出字段消费，drafting 路由变化无需 prompt 适配。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿：四项目标落点映射、`guardDependsOn`/`briefArray`/`upsertReviewsStage`/`cmdNext` 决策表设计、I-1~I-3 实施级选型、P-1~P-5 采纳清单；FR 覆盖 24/24 |
