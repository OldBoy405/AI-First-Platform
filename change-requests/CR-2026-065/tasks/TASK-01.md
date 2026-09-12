---
id: CR-2026-065-TASK-01
type: TASK
cr-ref: CR-2026-065
plan-ref: "change-requests/CR-2026-065/plan.md"
sdd-ref: "change-requests/CR-2026-065/sdd.md"
target-version: 0.38
title: 断言层去硬编码：assertion-sources 推导模块 + gate-registry 受控登记 + BR-1…BR-4 四条断言按事实源重写
slug: assertion-sources-and-br1-4
status: pending
estimate: 16h
depends-on: []
created: 2026-09-13T05:05:00+08:00
---

# CR-2026-065-TASK-01 断言层去硬编码（G1，FR-1…FR-7）

## 1. 任务描述

**目标**：把「会随合理变更而变的既有事实」从硬编码快照改成从事实源推导/语义要素判断，并让 BR-1…BR-4 四条基线红（`tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 上 exit 1 的既有红）按其**真实载体**对齐转绿。

**背景**：BR-1（`crctl.test.mjs:1337`，引入 `14b4458`）、BR-2（`checkpoint-tx.test.mjs:480`，引入 `fc2b142`）、BR-3（`crctl.test.mjs:4777`，引入 `bef1f4d` + `2e4442d` + `49c46dd`）、BR-4（`crctl.test.mjs:4989`，引入 `fc797ed`）**当前都是红的**——AC-01 的「exit 0 / 失败集合为空」是本 CR 的**交付目标**，本卡的任务就是把它们变绿，**不得**以「CI 现在是绿的」为前提，也**不得**为转绿回改被断言文件。

**输入条件**：CR status = `developing`（`approve-dev-start` 之后）；`plan.md` §4.1/§4.4/§6.5（J-1…J-4）/§6.6（表 D1…D6 与 P1…P3）、`sdd.md` §2.3/§4.1/§4.4/§6.5 已审批（`subject-sha256=1e6af84f…`，不改一字）。

**范围边界（`zero_diff`，逐条不得触碰）**：`dir-graph.yaml`、`pipeline-templates/*`、所有 `SKILL.md`、`lib/yaml-subset.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`skills/shared/controlled-shell/rules.json`、`crctl.mjs` 顶层 dispatch 与既有子命令签名/参数/错误码、历史 CR 产物与 `specs/`、`delivery/`。**BR-1…BR-4 的正确修法一律在断言侧**（被断言文件于本卡只读）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 说明 |
|---|---|---|
| `skills/shared/crctl/scripts/test/assertion-sources.mjs` | **新增** | 测试辅助只读模块；不匹配 `*.test.mjs`，不被 runner 采集（`*.test.mjs` 集合保持 21） |
| `skills/shared/crctl/scripts/test/gate-registry.json` | **新增** | 受控清单；唯一写入口 = 人类编辑 + `git commit`，本卡落初值 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 改 3 条断言 | BR-1（锚点 `:1337`）、BR-3（锚点 `:4777`）、BR-4（锚点 `:4989`）；行号为定位线索，以实时搜索结果为准 |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 改 1 条断言 | BR-2（锚点 `:480`） |

## 3. 实现要点

### 3.1 `assertion-sources.mjs`（只读、带缓存）

1. `readTextNormalized(absPath) -> string`：按 UTF-8 读入后**先** `replaceAll('\r\n','\n')`（工程纪律 #1：Windows autocrlf 会改写检出内容；本机实测 `write-requirement-prd/SKILL.md` 为 CRLF，`\r` 计数 119）。
2. `deriveStateMachine(toolsRoot)`：**逐字按 SDD §4.1 步 1–9**：
   - 读 `dir-graph.yaml` → 行尾规范化 → `parseYaml(norm, { strict: true })`（复用 `lib/yaml-subset.mjs`，零新增依赖）；
   - `sm = doc['change-request-track'].state_machine`；缺字段/结构不符 → **throw**（硬失败，**禁止**返回空集合）；
   - `declarations = sm.transitions`；`wildcards = sm.wildcards || {}`；
   - `namedStates` = 所有 from/to ∪ 所有 wildcard 目标，剔除 `'(new)'` 与 wildcard 名（按声明序去重）；
   - `expandedCount = Σ declarations: wildcards[t.from]?.length ?? 1`；
   - `identifiers = declarations.map(t => `${t.from}|${t.to}|${t.trigger}`)`（集合语义，抗行序变化）；
   - 步 9 结构自检：**推导侧、恒真、只暴露推导自身写错**，不得作为断言/覆盖项（SDD-CLOSE-10）。
   - 期望值（本机实测，写入登记）：`declaredCount=31`、`namedStates=15`（+ 注册前 `(new)`）、`wildcards['any-active']=12`、`expandedCount=53`。
3. `readTestFileSet(toolsRoot) -> string[]`：返回 `skills/shared/crctl/scripts/test/*.test.mjs` 的**升序文件名**（当前 21 个）。
4. 缓存：同一文件在一次进程内只读一次（SDD §7.3：不重复遍历全仓）。

### 3.2 `gate-registry.json`（受控清单，schema `crctl-suite-gate/v1`）

四段齐备（字段全部必填，缺 = 红）：

- `manifest.files` = `readTestFileSet()` 的实际值（21 个仓库相对文件名，升序）；
- `manifest.cases` = 逐文件用例数**初值**：以实测为准（`node --test --test-reporter=tap <file>` 的**文件级 plan** `1..N` 数）；单文件整跑成本过高时允许登记**只可能偏低**的正整数下界（`SUITE_MANIFEST_CASE_DROP` 只判「实际 < 基线」，偏低不会假红），并在完成标志中写明所用口径与偏低文件清单。**终值由 TASK-04 在全量 `--run` 报告上刷新**（plan §4.1 R-10）；
- `stateMachine.namedStates`（15）/ `stateMachine.wildcards`（`any-active` → 12 目标）/ `stateMachine.transitions`（31 条 `{from,to,trigger}` 稳定标识）＝ 由 `deriveStateMachine` 推导后**原样登记**；
- `exceptions` = `[]`（**显式空数组**，不是「文件不存在」）。

本卡只**创建/登记**该文件；此后不得由任何脚本自动改写（受控写入 = 人工提交）。

### 3.3 四条断言（判据面逐字，plan §6.5 J-1…J-4）

- **J-1 / BR-1（断言落真实载体）**：
  - `skills/develop/write-dev-tasks/SKILL.md`：含 `crctl task init`；含对受控账本 `tasks/_index.yml` 的「禁止手写」约束；
  - `pipeline-templates/code-implementation.pipeline.json`：节点数 ≡ `pipeline-templates/_index.yml#code-implementation-v1.nodes`（**跨文件投影**，不得在测试里写第二份 `16`）；所有节点 prompt 对命令面 `crctl (task init|task append|task done|advance|review-record|approve|owner-set|version-set)` 与账本名 `_index.yml` / `_backlog.yml` **零命中**；每个 skill 节点 `ref` 存在。
  - 现状（本机实测）：`write-dev-tasks/SKILL.md:106` 含指令、`:115` 含禁手写；pipeline 对二者零命中、16 节点、`_index.yml:57` = `nodes: 16`。
- **J-2 / BR-2（reader 事实源 + 否定辖域）**：`skills/review/review-alignment/SKILL.md`
  - 正向：读取契约命中 `change-requests/_backlog.yml` 与 `cr.md`（本机各 1 处，`:33`）；
  - 零命中：`latest-checkpoint`、`checkpoints[]`（本机各 0）；
  - `mtime` / `merge-commit` / `fingerprint`：按**否定辖域**判——以 `。`/`；`/换行切句后，对每个命中句断言含否定锚点 `不读`；零命中同样满足（本机 2 处命中、均在否定句内）。**不要求该文件零命中、不回写该文件**。
- **J-3 / BR-3（推导 ≡ 登记）**：三条集合/计数等价 ——
  - `deriveStateMachine(...).namedStates` ≡ `gate-registry.json#stateMachine.namedStates`（集合相等）；
  - `.wildcards` ≡ `#stateMachine.wildcards`（名与目标集合双向相等）；
  - `.identifiers` ≡ 登记 `transitions` 的 `${from}|${to}|${trigger}` 集合；
  - `expandedCount` ≡ 由**登记集合**自洽推出的值（`Σ wildcards[from]?.length ?? 1`）。
  - **用例名保留历史字样**（含「28 声明/50 展开」），不改名（名字不是断言；避免与 SDD §6.3 登记名与证据模式漂移）；
  - 承重断言只有这三条；步 9 结构自检不计入覆盖（SDD-CLOSE-10）。
- **J-4 / BR-4（语义要素 + 零命中；E-1 收口）**：`skills/requirement/write-requirement-prd/SKILL.md`
  - 定位含「重新读取」的校验句（**先规范化行尾**）：以 `。`/`；`/换行切句取命中锚点 `重新读取` 的那一句，断言该句内同时含 `frontmatter 必填字段` / `七个章节` / `未替换占位符`；
  - 5 个禁用词零命中；`/crctl validate|Commit：/` 零命中（在**该文件**上）；
  - `crctl git commit` 零命中（在 `skills/develop/write-dev-tasks/SKILL.md` 上，= 既有测试同款模式）；
  - **禁止**改用子串「手工 commit」做零命中：`SKILL.md:89` 现有否定表述「Skill 不输出手工 commit 指令」，且该文件在 `zero_diff` 内不可改。

### 3.4 通用纪律

- 所有读文本断言先 `\r\n → \n`；解析用 `split(/\r?\n/)`；**跨行正则/解析失败必须硬失败**（不得静默降级为空集合）。
- 断言只读：不写 `cr.md` / `_backlog.yml` / `tasks/_index.yml` / `approval.yml`，不新增任何账本写路径。
- 只改测试断言与新增两个辅助文件；**不做** BR-1…BR-4 根因对象本身的修改。

## 4. 验收条件（可执行）

1. `cmd-02`（§6.2 证据命令表，tools cwd `.`）：`node --test --test-reporter=dot --test-name-pattern "CR-2026-037 Prompt 采纳" --test-name-pattern "checkpoint T05 contract" --test-name-pattern "TASK-06 ⑤" --test-name-pattern "CR-2026-042 静态合同：已知 Skill 越界文本零命中" skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` → **exit 0**（基线现状 exit 1 / 135 ms，命中 BR-1、BR-2）。
2. `cmd-04`（§6.2，登记面 schema + `stateMachine` 数量 + diff 白名单）→ **exit 0**：`gate-registry.json` 存在且 `schema=crctl-suite-gate/v1`；`manifest.files` 与实际 21 个测试文件集合相等；`manifest.cases` 键集 = 文件集合且值均为正整数；`namedStates=15` / `transitions=31` / `wildcards['any-active']=12`；`exceptions` 为显式空数组；diff 路径全部落在 `skills/shared/crctl/scripts/test/**`（本卡改动的唯一落点）。
3. 负控自检（非证据、不进 `test-evidence/`）：临时向 `dir-graph.yaml` 注入一条转换 → 重跑 BR-3 用例（`--test-name-pattern "TASK-06 ⑤"`）**必须红** → `crctl git checkout -- dir-graph.yaml` 还原 → `crctl git status --short` 干净（正式的 N-1 全量注入证据由 TASK-04 执行，本卡只做本地自检）。
4. `crctl git status --short` 在提交前一览：仅上述 4 个文件；`git diff --stat -- dir-graph.yaml pipeline-templates skills/*/*/*/SKILL.md` 为空（`zero_diff` 面零 diff）。

## 5. 完成标志

- 4 个文件就位并随 CR 提交；`cmd-02` exit 0、`cmd-04` exit 0；`zero_diff` 面零 diff；
- 负控自检通过（注入即红、还原即净），注入物**不在**工作区/提交中；
- `gate-registry.json` 初值登记说明（`manifest.cases` 实测口径 + 偏低文件清单，若采用下界）写入本任务完成记录；
- 任务账本登记：`crctl task done CR-2026-065 --task CR-2026-065-TASK-01`（`tasks/_index.yml` 即时标 `done` 并带 `done-at`，不积压到回写期）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/shared/crctl/scripts/lib/yaml-subset.mjs`：`parseYaml(text, { strict }) `——只读复用，**不得**修改该文件、**不得**新增 YAML 依赖；
- `pipeline-templates/_index.yml`：`code-implementation-v1.nodes`（跨文件投影的唯一登记处，P4）；
- 只读取证（不改）：`skills/develop/write-dev-tasks/SKILL.md`、`skills/review/review-alignment/SKILL.md`、`skills/requirement/write-requirement-prd/SKILL.md`、`pipeline-templates/code-implementation.pipeline.json`、`dir-graph.yaml#change-request-track.state_machine`。

**产出（下游 TASK 消费方不得缩略）**

- `skills/shared/crctl/scripts/test/assertion-sources.mjs` 导出（逐字对齐 plan §2 共享契约）：
  - `readTextNormalized(absPath) -> string`
  - `deriveStateMachine(toolsRoot) -> { namedStates: string[], wildcards: Record<string, string[]>, transitions: { from: string, to: string, trigger: string }[], identifiers: string[], expandedCount: number, declaredCount: number }`（推导失败 **throw**，禁返回空集合）
  - `readTestFileSet(toolsRoot) -> string[]`
- `skills/shared/crctl/scripts/test/gate-registry.json`：`schema: "crctl-suite-gate/v1"` + `manifest { files: string[], cases: Record<string, number> }` + `stateMachine { namedStates: string[], wildcards: Record<string, string[]>, transitions: { from: string, to: string, trigger: string }[] }` + `exceptions: []`；被 TASK-03 的 `suite-gate.mjs`（清单/例外核对）与 `contract-scan.test.mjs`（静态断言）消费，被 TASK-04 刷新 `manifest.cases` 终值。
