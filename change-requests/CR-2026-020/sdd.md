---
id: CR-2026-020-sdd
type: SDD
cr-ref: CR-2026-020
title: 治理工具链 — writeback 机械步骤固化为入库脚本 技术设计
status: draft
created: "2026-08-04T22:11:43+08:00"
updated: "2026-08-04T22:11:43+08:00"
---

# SDD — writeback 机械步骤固化为入库脚本

## 0. 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| `tools/ARCHITECTURE.md` §6 否决记录："独立**账本操作**脚本库（如 `tools/skills/shared/scripts/`）"——否决对象是账本写入第二通道，但字面点名了 PRD FR-4 拟用的路径 | `tools/ARCHITECTURE.md` §6 第一行 |
| `crctl.mjs` 刻意单文件（1636 行），顶层直接执行 `main()`，无任何 `export`——改造成可导入库需要加 `import.meta` 守卫等结构手术，正是 §3 警告的拆分 | `tools/ARCHITECTURE.md` §3；`crctl.mjs:1636`（`main();`） |
| crctl 自身脚本布局先例：`skills/shared/crctl/scripts/`（skill 组目录内挂 scripts/） | `tools/skills/shared/crctl/` 目录结构 |
| **specs 侧 traceability.yml 是跨 CR 累积文件**（989 行，`milestones[]` 每 CR 一段）：`fr-chain` 的 `sdd:`/`code:` 为编辑性措辞，头部含手工缺口注释（CR-2026-003~006 历史段缺失、无法回填）——**不可全量重建** | `specs/ai-first-platform/traceability.yml` 头部注释与 milestones 结构 |
| `_backlog.yml` 注册条目的 `merge-commits[]` 结构：`repo/trunk/sha/branch/source-sha/merged-at` 六字段列表 | `change-requests/_backlog.yml`（CR-2026-007/008 条目实测） |
| `delivery/task/_index.yaml` 条目七字段（id/file/title/status/cr-ref/target-version/estimate）全部可从 `delivery/task/*.md` frontmatter 与文件名投影——**可全量重建** | `delivery/task/_index.yaml` + 任一 TASK 文件 frontmatter |
| `specs/_index.yml` 的 `features[].brief` 为逐版本累积人工长文、`current` 为编辑字段——只能结构化字段更新，不可重建（PRD §1.3 已核实） | `specs/_index.yml` |
| feature-writeback pipeline 四处 prompt 需同步改：node-2（备份指引）、node-3（作废命名 `TASK-{ver}-{NNN}-{NN}`）、node-4（"与 change-requests 侧保持一致"+作废命名示例） | `tools/pipeline-templates/feature-writeback.pipeline.json` |
| 本 CR 目标代码仓 = tools 仓自身（改 `tools/skills/**`），按 write-tech-design SKILL 例外条款，`tools/ARCHITECTURE.md` 是正确的架构判据 | write-tech-design SKILL Step 1 |

## 1. 架构概览

### 1.1 模块边界与落点

```
tools/skills/writeback/
├── writeback-prd-sdd/SKILL.md        # 改调：调脚本 + 核对 dry-run diff + 事实基线段
├── writeback-tasks/SKILL.md          # 同上
├── writeback-traceability/SKILL.md   # 同上
└── scripts/                          # ★ 新增（本 CR 唯一新代码目录）
    ├── writeback-prd-sdd.mjs
    ├── writeback-tasks.mjs
    ├── writeback-traceability.mjs
    ├── lib.mjs                       # 三脚本公用：CRLF 归一/frontmatter 读改/锚点断言/dry-run diff/fail
    └── test/writeback.test.mjs       # node --test 自检（NFR-6/AC-8）
```

依赖方向（与 ARCHITECTURE.md §4 一致，脚本层与 crctl 平行、互不依赖）：

```
Pipeline(feature-writeback) → SKILL(writeback/*) → scripts/*.mjs → specs/ + delivery/ 内容文件（写）
                                                 └→ change-requests/_backlog.yml 等账本（只读）
账本写入仍唯一经 crctl（本 CR 不触碰）
```

### 1.2 架构冲突消解（评审重点，先于一切设计决策）

PRD 与 `tools/ARCHITECTURE.md` 存在三处冲突/事实偏差，本节逐条消解；**详细偏差记录与理由见 §8**：

1. **落点路径**：不用 PRD FR-4 字面路径 `skills/shared/scripts/`（§6 否决条目点名路径，且共享桶目录诱发账本脚本蔓延），改用 `skills/writeback/scripts/`——与 crctl 自身 `skills/shared/crctl/scripts/` 布局对称，按组内聚、目录名即边界。
2. **不抽取 crctl 函数**：FR-4 的"如需抽取 shared 模块"判定为**不需**。crctl.mjs 顶层执行 `main()` 且零导出，改造成库违反其单文件不变量；回写脚本的 YAML 需求（frontmatter 行级读改 + 定向块提取 + 全量生成）远轻于 crctl 通用解析器，由 `lib.mjs` 自带 ~100 行定向实现，与包内"行级定向、非通用序列化器"哲学一致（§6 第三条）。
3. **traceability 处理模式**：FR-3/FR-5 的"全量重建"对该文件不成立（§0 事实基线第 4 行），改为"头部结构化字段更新 + 本 CR milestone 段末尾追加"。

配套按 ARCHITECTURE.md §8 维护规则修订该文档（本 CR 范围内，随本次设计评审确认）：§3 代码地图补 `skills/writeback/scripts/` 条目（职责 + 非账本边界）；§6 否决条目补范围澄清（否决的是"账本操作"脚本库；specs/delivery 内容文件回写脚本落点收窄为 `skills/writeback/scripts/`，防蔓延，ref CR-2026-020）。

### 1.3 关键流程（feature-writeback pipeline 改后形态）

节点 ②③④ 从"现场写脚本→调试→验证"变为统一三步：`脚本 --dry-run 核对 diff` → `脚本实跑（自带自检）` → `git commit`。节点 ①⑤ 不变（merge/archive 仍走 crctl + controlled-shell）。

## 2. 数据模型

### 2.1 各脚本读写面

| 脚本 | 读（只读） | 写 |
|---|---|---|
| writeback-prd-sdd | `change-requests/{cr}/prd.md`、`sdd.md`；`specs/{spec}/PRD.md`、`SDD.md`；`specs/_index.yml` | `specs/{spec}/PRD.md`、`SDD.md`（末尾追加里程碑节 + frontmatter 更新）；`specs/_index.yml`（结构化字段更新） |
| writeback-tasks | `change-requests/{cr}/tasks/_index.yml`（账本，只读）、`tasks/TASK-*.md`；`delivery/task/*.md` | `delivery/task/TASK-{version}-{cr}-{NN}-{slug}.md`（新增拷贝）；`delivery/task/_index.yaml`（全量重建） |
| writeback-traceability | `change-requests/{cr}/cr.md`（只读）、`review-annotations/*.yml`、`test-report.md`；`change-requests/_backlog.yml`（账本，只读，定向提取 merge-commits[]）；`delivery/task/_index.yaml` | `specs/{spec}/traceability.yml`（头部字段更新 + milestone 段追加） |

**硬边界（NFR-5）**：三脚本对 `_backlog.yml`/`_history.yml`/`cr.md`/CR `tasks/_index.yml` 只读；lib.mjs 不提供任何指向这四类路径的写函数。

### 2.2 文件格式契约（脚本内断言的结构）

- **PRD/SDD 里程碑节**：`## {标题}（v{version} · CR-{id}）`，节内原文 H 级整体 +1；幂等判据 = 该标题行已存在。
- **specs/_index.yml**：`features[]` 定位 `- id: {spec_id}` 块；更新 `current`/`cr-ref`/`updated`，`cr-history[]` 按 id 追加去重；`brief` 仅当 `--brief` 传入时整行替换。
- **delivery/task/_index.yaml**：全量重建。条目字段 id/file/title/status/cr-ref/target-version/estimate 全部投影自扫描 `delivery/task/*.md` 的 frontmatter 与文件名；**条目顺序 = 既有文件中已有 id 的原序 + 新增条目按 id 排序追加**（保持 diff 最小、纯增量可读）。
- **traceability.yml**：头部字段 `cr-ref`/`target-version`/`generated-at` 更新、`cr-history[]` 追加去重，**头部手工注释与既有 milestones 段逐字节保留**；本 CR milestone 段追加到文件末尾。段内 `merge-commits` 从 `_backlog.yml` 定向提取（六字段），`fr-chain` 的编辑性内容经 `--milestone-file` 由调用方（Agent 按 SKILL 起草）提供，脚本负责结构校验与放置，不臆造。
- **TASK 命名**：`TASK-{version}-{cr_id}-{NN}-{slug}`（`slug` 取 frontmatter，缺失回退 `task-{NN}`）——三处文档（pipeline node-3、traceability SKILL 示例、writeback-tasks SKILL）统一到此格式（FR-8）。

## 3. 接口契约（CLI）

三脚本统一约定（与 crctl 输出风格对齐，机器可判）：

```
node writeback-prd-sdd.mjs      --workspace <ws> --cr <CR-ID> --spec <spec_id> --version <ver> [--brief "<text>"] [--dry-run]
node writeback-tasks.mjs        --workspace <ws> --cr <CR-ID> --spec <spec_id> --version <ver> [--dry-run]
node writeback-traceability.mjs --workspace <ws> --cr <CR-ID> --spec <spec_id> --version <ver> --milestone-file <path> [--dry-run]
```

- **退出码**：0 = 成功或显式 noop（stdout JSON 含 `"noop": true` 与原因）；非 0 = 硬失败，stderr JSON 含错误码。
- **错误码**（lib.mjs `fail()`，风格同 crctl）：`BAD_ARGS` / `CR_STATUS_MISMATCH`（状态前置不符，读 cr.md 校验但不写）/ `ANCHOR_NOT_FOUND` / `ANCHOR_NOT_UNIQUE`（命中 0 或 ≥2 次，纪律 #1）/ `MERGE_COMMITS_MISSING`（不猜测、不取 trunk 最新提交）/ `STRUCTURE_MISMATCH`（_index/traceability 结构断言失败）/ `SELF_CHECK_FAILED`。
- **dry-run**：打印每个目标文件的变更 diff（旧/新片段），不落盘；实跑末尾执行自检断言（§4.4），失败即 `SELF_CHECK_FAILED` 非零退出（已写入的内容留在工作区由 git 兜底，不自动回滚——工作区未 commit，`git checkout --` 即可复原，不做补偿机制，YAGNI）。
- **状态前置**：prd-sdd 要求 cr.md status=`merging`；tasks/traceability 要求 `writing-back`（与各 SKILL 现行前置一致）。脚本只读校验，状态推进仍由 SKILL 层调 crctl。

## 4. 关键算法与流程

### 4.1 writeback-prd-sdd

```
读 specs/{spec}/PRD.md：
  不存在 → 首次回写：整份拷贝 CR prd.md + frontmatter 补齐（spec_id/version/status/cr_ref）
  存在   → 增量：
    幂等检查：里程碑标题行已存在 → noop
    构造里程碑节：CR prd.md 去 frontmatter，正文 H 级整体 +1，冠以标题行
    追加到文件末尾（EOF 追加，无中段锚点）
    frontmatter 更新：^version:/^cr_ref: 行（首个 --- 块内，行首锚定，唯一性断言）
SDD.md 同法。specs/_index.yml：定位 "- id: {spec}" 块 → 字段行级更新 + cr-history 追加去重。
```

### 4.2 writeback-tasks

```
扫描 delivery/task/*.md frontmatter 收集已交付 id 集合（幂等唯一判据，同 PRD FR-2；
  索引全量重建后与"索引 id 集合"等价，且对 slug 后补导致的文件名变化稳健）
读 CR tasks/_index.yml（只读）筛 status=done → 对每个任务：
  其 id ∈ 已交付集合 → 跳过（幂等，不看文件名、不比内容）
  否则拷贝 + frontmatter 闭合 --- 前插入 spec-id/version 两行
全量重建 delivery/task/_index.yaml：扫描 delivery/task/*.md frontmatter 投影七字段，
  顺序 = 既有 id 原序 + 新增按 id 排序（§2.2）
```

### 4.3 writeback-traceability

```
定向提取 _backlog.yml 中 {cr} 条目的 merge-commits[]（块提取，六字段齐全性断言，缺失硬失败）
读 --milestone-file（Agent 起草的本 CR milestone YAML 段）→ 结构校验（cr/milestone/target-version/
  fr-chain[].fr 必填；merge-commits 由脚本注入提取结果，文件内如有则校验一致）
幂等检查：traceability.yml 已含 "- cr: {cr}" → noop
头部字段更新（行级，行首锚定）+ 注释与既有段逐字节保留 + 末尾追加 milestone 段
```

### 4.4 自检断言（每脚本实跑末尾，NFR-3）

回读目标文件断言：里程碑标题恰出现 1 次；_index 中目标 id 恰 1 条且字段齐全；traceability 中 `- cr: {cr}` 恰 1 段且 merge-commits 数与提取结果一致；全文件无 `\r`（写出统一 LF）。失败 `SELF_CHECK_FAILED`。

### 4.5 lib.mjs 公用函数

`normalize()`（`\r\n→\n`，纪律 #1）、`readFrontmatter()/patchFrontmatterField()`（首个 `---` 块内行级改写 + 唯一性断言）、`extractBlock()`（缩进敏感的 YAML 块定向提取，供 _backlog/_index 只读解析）、`unifiedDiff()`（dry-run 输出）、`ok()/fail()`（JSON 输出与退出码）。总量预期 ~120 行，不是通用 YAML 解析器。

## 5. 技术选型与替代方案

| 决策 | 选择 | 已否决的替代及理由 |
|---|---|---|
| 落点 | `skills/writeback/scripts/` | `skills/shared/scripts/`：§6 否决条目点名路径 + 共享桶蔓延风险（§1.2-1） |
| YAML 能力来源 | lib.mjs 自带定向实现（~120 行） | 抽取 crctl 函数：破坏单文件不变量（§1.2-2）；引入 yaml 依赖：违反零依赖不变量（§5-3）与全量重排副作用 |
| traceability 模式 | 头部更新 + 段追加 | 全量重建：摧毁不可再生的历史里程碑与手工注释（§0 第 4 行）；双份同步：FR-7 已废除 |
| 索引重建顺序 | 既有序 + 新增排序追加 | 整表重排序：diff 面扩大，评审不可读 |
| 自检失败处理 | 非零退出 + git 工作区兜底 | 自动回滚/备份：重复实现 git（FR-6 精神），YAGNI |
| 脚本组织 | 三脚本 + lib.mjs | 单文件三子命令：与 PRD FR-1/2/3 三脚本口径不符，且三节点由 pipeline 独立调用，无共享进程需求 |

## 6. FR → 技术实现映射

| FR | 实现 |
|---|---|
| FR-1 | §4.1 脚本 + `--brief` 入参；AC-1 由 test/writeback.test.mjs 断言（含 brief 落位，回应需求评审 suggestion-1） |
| FR-2 | §4.2 脚本（幂等=扫描 delivery/task/*.md frontmatter 的 id 集合，同 FR-2 字面；索引重建天然幂等） |
| FR-3 | §4.3 脚本；**偏差：全量重建→头部更新+段追加**（§8-D3） |
| FR-4 | §1.1 落点 + §5 选型；**偏差：路径与"抽取共享模块"**（§8-D1/D2）；不接 CAS/审计/门禁，账本只读 |
| FR-5 | 三类处理精化为：重建（delivery 索引）/ 结构化字段更新（specs/_index、traceability 头部）/ 锚点追加（PRD/SDD 节、traceability 段——均为 EOF 追加 + 行级 frontmatter 锚点） |
| FR-6 | writeback-prd-sdd SKILL 删 Step 2 备份与 Step 6 备份行；pipeline node-2 prompt 删备份指引；脚本不实现备份 |
| FR-7 | traceability SKILL + pipeline node-4 prompt 删"与 change-requests 侧保持一致"；CR 侧文件定位为开发期工作稿（归档后不再维护） |
| FR-8 | 三份 SKILL 改为"调脚本 + 核对 dry-run diff"+事实基线段；TASK 命名三处统一（pipeline node-3、traceability SKILL 示例、writeback-tasks SKILL 复核） |
| FR-9 | merge-feature-branch SKILL 增事实基线段（tools 仓 trunk=custom/main、空分支跳过、补 push 规则），不动合并/补偿逻辑 |

**frontmatter 合规**（需求评审 suggestion-2 落实）：脚本按 engineering-docs 模板的**字段规则**实现校验（type/spec_id/version/status/cr_ref 存在性与取值），不调用 skill。

## 7. 安全与性能考量

- **信任边界**：脚本只操作本地仓库文件，无网络、无 shell 外呼；入参 workspace/cr/spec 均做存在性校验（`BAD_ARGS`）。
- **账本保护**：账本四类文件只读（§2.1 硬边界），静态可核查（AC-4 的 grep 判据：脚本中不出现对这些路径的写调用）。
- **失败安全**：所有写落在 git 工作区，commit 前可随时复原；锚点 0/多次命中、结构断言失败、merge-commits 缺失均硬失败不落盘（写前先在内存构造全部新内容，校验通过才写文件——先验证后写，天然避免半写状态）。
- **性能**：目标文件最大 ~1000 行、任务数 <100，全部同步 I/O 一次性读写，无性能敏感点。

## 8. 与已审批 PRD 的偏差记录（供 review-tech-design 与人工审批确认）

| # | PRD 原文 | SDD 决策 | 理由 |
|---|---|---|---|
| D1 | FR-4/§1.2：落点 `tools/skills/shared/scripts/` | `tools/skills/writeback/scripts/` | 字面路径撞 ARCHITECTURE.md §6 否决记录；组内聚 + 防蔓延（§1.2-1）。FR-4 实质约束（版本化、非 crctl 子命令、零新依赖）全部保留 |
| D2 | FR-4："复用 crctl 现有 YAML 工具（如需，抽取 shared 模块）" | 不抽取；lib.mjs 自带定向实现 | "如需"条件判定为不需：crctl.mjs 单文件不变量 + 顶层 main() 不可导入；回写 YAML 需求远轻于通用解析（§1.2-2） |
| D3 | FR-3/FR-5/AC-3："traceability.yml 全量重建" | 头部字段更新 + milestone 段末尾追加 | 真实文件为跨 CR 累积（989 行、编辑性 fr-chain、手工注释、4 段历史缺口不可回填）——全量重建会摧毁历史。PRD 该表述沿袭了过时的 SKILL 描述（§0 第 4 行）。AC-3 判据等效替换为：追加后既有段逐字节不变 + 本 CR 段恰 1 处 + 幂等 noop |

配套修正（开发任务内完成）：`docs/product/writeback-流水线耗时分析与优化方案.md` §4.2 表格同错（traceability 列入"全量重建"），随本 CR 在 knowledge-base worktree 修正；三份偏差同步反映到 tools/ARCHITECTURE.md §3/§6 修订（§1.2 末段）。

## 9. 参与仓与交付物清单

| 仓 | 交付物 |
|---|---|
| tools（trunk=custom/main） | `skills/writeback/scripts/`（3 脚本 + lib + test）；3 份 writeback SKILL.md 改调；merge-feature-branch SKILL 事实基线段；`pipeline-templates/feature-writeback.pipeline.json` node-2/3/4 prompt 修订；`ARCHITECTURE.md` §3/§6 修订 |
| knowledge-base（trunk=master） | CR 产物（prd/sdd/tasks/评审记录）；`docs/product/writeback-流水线耗时分析与优化方案.md` §4.2 修正 |
| multica | 不参与（无代码改动，空分支跳过） |
