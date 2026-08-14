---
id: CR-2026-023-sdd
type: SDD
cr-ref: CR-2026-023
title: 治理工具链 — 代码评审 LLM 选择暂停节点 + R9 护栏（CR 上下文下一步收敛 crctl next）技术设计
status: draft
created: "2026-08-07T00:05:00+08:00"
updated: "2026-08-07T00:05:00+08:00"
---

# SDD — 代码评审 LLM 选择暂停节点 + R9 护栏 技术设计

> 输入：`prd.md`（14 FR / 8 US / 11 AC）。目标仓：**tools 方法论包**（本 CR 目标代码仓即 tools 仓自身，架构基线读 `tools/ARCHITECTURE.md`，已存在、只读引用）。
> 所有落点行级定位已于技术设计期实跑核对；实施期行号若漂移，以结构锚点为准并在任务内订正（纪律 #4）。

## 1. 架构概览

### 1.1 改动面与模块边界

本 CR 触及 tools 包四个既有模块，**不新增模块、不改依赖方向**（ARCHITECTURE.md §4：依赖只朝下，Skill 不绕过 crctl）：

```
pipeline-templates/code-implementation.pipeline.json   ← 块 A：inputs + 新 human_approval 节点 + review-code prompt
pipeline-templates/_index.yml · README.md              ← 块 A：台账与文档同步（12→13 节点）
skills/shared/crctl/scripts/lint-prompts.mjs(+test)    ← 块 B：R9 规则 + 测试向量
skills/{requirement,develop,writeback,sync}/*/SKILL.md ← 块 B：17 处存量清零 + push-progress 引导链闭环
agents/requirement-writer.md · AGENTS.md（tools 仓）   ← 块 B：前置注记 + 编辑规则第 7 条
```

硬不变量核对（ARCHITECTURE.md §5）：
- **crctl 单一状态写者**：新 human_approval 节点只做暂停确认，不写 CR 状态、不调 crctl 状态子命令——合规。
- **Skill 文档不得描述账本手工编辑**：17 处改写仅动「下一步」提示行，不涉账本编辑步骤——合规。
- **lint-prompts 与 crctl 平行**：R9 判据源直读 `skills/_index.yml`（台账只读消费），不引入对 crctl 运行时状态的依赖——合规。

### 1.2 关键流程（改动后）

**流程 A（/coding 评审前暂停）**：

```text
… 0008 push-progress（统一 checkpoint）
 → 0013 选择代码评审 LLM（human_approval：review_llm 已指定→快速确认；留空→三选一询问；驳回→abort）
 → 0009 review-code（prompt 头部承接选择结果，dimensions 记录 reviewer-model）
 → 0010 代码审查通过 → 0011 approve-code → 0012 push-progress
repair 循环：replayNodes 仍为 implement-code→write-test-report→push-progress→review-code（显式 nodeId 引用，0013 不在列表内，天然不被重放）
```

**流程 B（R9 护栏生效路径）**：

```text
pre-commit 钩子 → lint-prompts --mode enforce → runRules 逐段扫描
 → 文件路径 ∈ CR 上下文域 且非 cr-show → 行含「下一步」且不含「crctl next」且含 skill id/pipeline 名 → R9 CONTRADICTS → enforce 阻断提交
```

## 2. 数据模型

本 CR 无数据库/持久化模型变更，以下为改动涉及的结构定义（均为既有 schema 内的增补）：

### 2.1 pipeline JSON 新增输入（inputs[]）

```json
{ "key": "review_llm", "label": "代码评审 LLM", "type": "text", "required": false,
  "placeholder": "留空则在评审前暂停由人工选择",
  "description": "指定执行 review-code 的模型/runner；留空时节点「选择代码评审 LLM」会暂停等待人工选择" }
```

### 2.2 pipeline JSON 新增节点（nodes[]，数组位置 = 执行顺序）

```json
{ "id": "00000000-0000-0000-0015-000000000013", "kind": "human_approval", "label": "选择代码评审 LLM",
  "approvalPrompt": "<三分支引导文案，见 §3.1>", "onFail": "abort", "timeoutMinutes": 4320 }
```

插入位置：`nodes[8]`（0008 push-progress）之后、`nodes[9]`（0009 review-code）之前；插入后数组长度 12→13，`nodes[9..12]` 整体后移一位（UUID 不变，仅数组序变化）。

### 2.3 reviewer-model 留痕字段

写入 review-code 临时 payload `.crctl/tmp/review-code.yml` 的 `dimensions` 映射内（自报字符串，如模型名或 runner 标识），随 `crctl review-record --stage code --bump-attempt` canonical 化进 `review-annotations/code.yml#dimensions`。**不改 crctl 契约**：canonical `reviewer` 字段仍由 crctl 注入 `identity(ws)`，reviewer-model 仅是 dimensions 内的附加留痕维度。

### 2.4 lint finding 结构（R9 复用既有）

```js
{ rule: 'R9', level: 'CONTRADICTS', file, line, why }
```

## 3. 接口契约

### 3.1 节点 0013 approvalPrompt（定稿文案契约）

```text
代码与测试证据已推送统一 checkpoint，即将进入代码评审。

若触发参数 review_llm 已指定，请按该模型执行并快速确认；否则请在此暂停并询问用户选择评审 LLM：
① 当前会话默认模型
② 外部 CLI runner（按代码执行设置中可用 runner 列出选项）
③ 其他指定模型

记录用户选择后再勾选继续；驳回则中止本轮评审。
```

契约要点（AC-1 对应）：三分支齐全；**不含「下一步」关键词、不含任何字面 skill id**（approvalPrompt 文本需过 R9 扫面不命中——pipeline-templates/ 本不在 R9 scope，此约束为纵深防御，防止文案被抄入 SKILL.md 后触发）。

### 3.2 review-code prompt 头部追加段（定稿契约）

```text
执行评审前确认上一节点选定的评审 LLM（触发参数 {{inputs.review_llm}} 或人工审批环节的用户选择）；
按该模型/runner 执行本评审，并在 .crctl/tmp/review-code.yml 的 dimensions 中记录 reviewer-model 留痕（自报），
使评审证据可追溯由哪个模型产出。其余取证与落盘要求不变
（评审判断写临时 payload，经 crctl review-record --stage code --bump-attempt 落盘 review-annotations/code.yml）。
```

追加于现有 prompt **最前面**，其余取证与落盘文本零改动。

### 3.3 R9 统一改写形态（17 处存量 + 新增提示的行级契约）

```text
下一步 : 以 `crctl next {cr_id}` 为准（PASS→等待人工审批；BLOCK→pipeline 自动回对应修复节点重审）
```

- 有 PASS/BLOCK 分支语义的（review-*/write-test-report）：保留括号内语义方向；
- 纯顺序流转的（register/prd/approve-* 链）：只写「下一步 : 以 `crctl next {cr_id}` 为准」；
- **括号内不得出现任何字面 skill id**（D-4，防自触发；"对应修复节点"是语义方向占位）。

### 3.4 AGENTS.md（tools 仓）新增条目

「编辑规则 → 修改 Skill」第 7 条：

```markdown
7. CR 上下文 skill（requirement/develop/writeback/sync/cr 域）的输出摘要中「下一步」提示一律写「以 `crctl next {cr_id}` 为准」，不得手写 skill/pipeline 名映射副本（lint-prompts R9 强制）。
```

## 4. 关键算法与流程

### 4.1 R9 判定算法（lint-prompts.mjs）

落点结构（实跑核对）：常量区在 L27-28（`CRCTL_PATH`/`INBOX_SKILL_PATH` 模式）、`loadJudgements()` L32-46、`runRules(para, ctx)` L116 起、R8 块结束于 L196 附近、`ctx = { ...loadJudgements() }` L238（返回值自动 spread 进 ctx）。

```js
// ① 常量区追加（对齐 CRCTL_PATH 模式，__dirname 固定解析——不随 --root 变，见 §5.2 决策）
const SKILLS_INDEX_PATH = path.resolve(__dirname, '..', '..', '..', '_index.yml'); // R9 判据源：全部 skill id

// ② loadJudgements() 追加（纪律 #1：\r\n 规范化）
const skillIndex = fs.readFileSync(SKILLS_INDEX_PATH, 'utf8').replaceAll('\r\n', '\n');
const skillIds = new Set([...skillIndex.matchAll(/^\s*-\s*id:\s*([\w-]+)/gm)].map((m) => m[1]));
// 返回值追加 skillIds

// ③ runRules() R8 块后追加
const CR_CONTEXT_SCOPE = /^skills\/(requirement|develop|writeback|sync|cr)\//;
const PIPELINE_NAME_HIT = /\b(requirement-authoring|architecture-design|code-implementation|feature-writeback|resume-cr|writeback|coding|architecture)\s+pipeline\b/;
if (CR_CONTEXT_SCOPE.test(ctx.file) && !ctx.file.includes('/cr-show/')) {
  for (let li = 0; li < lines.length; li++) {
    const l = lines[li];
    if (!l.includes('下一步') || l.includes('crctl next')) continue;
    const hit = [...ctx.skillIds].filter((s) => l.includes(s));
    if (hit.length || PIPELINE_NAME_HIT.test(l)) {
      findings.push({ rule: 'R9', level: 'CONTRADICTS', file: ctx.file, line: para.startLine + li,
        why: 'CR 上下文 skill 的「下一步」提示必须写「以 crctl next {cr_id} 为准」，禁止手写副本' });
    }
  }
}
// ④ 文件头注释规则清单追加：+ R9（CR 上下文「下一步」提示收敛 crctl next）
```

行号语义与既有 R7/R8 一致（`para.startLine + li`）；`<!-- lint-prompts:ignore -->` ±1 行豁免由既有的段落级豁免机制自动适用，R9 无需新增豁免代码。

### 4.2 节点插入流程（块 A）

1. `inputs` 数组追加 review_llm 条目（与既有三条并列，无顺序依赖）；
2. `nodes` 数组在 0008 与 0009 之间插入 0013 节点对象；
3. review-code（0009）节点 `prompt` 字段头部拼接 §3.2 追加段；
4. `reviewLoop.replayNodes` **零改动**（显式 nodeId 引用，插入不影响）；
5. JSON 解析自检 + `_index.yml` nodes 12→13、brief 补环节 + README 两处同步（§6 FR-6：代码编写期节点表 L453 checkpoint 行之后插入新行；mermaid 流程图 L425-426 `D8 --> D9` 直连改为经新节点中转，节点总数描述同步 12→13）。

### 4.3 提交批次序列（NFR-1 同批约束的执行编排）

```text
commit 1（块 B，原子）：lint-prompts.mjs（R9）+ test 向量 + 17 处 SKILL.md 清零 + push-progress 闭环 + requirement-writer 注记 + AGENTS.md 第 7 条
   ↳ 上线前先跑 --mode report 确认命中恰为 17 处 → 改完跑 enforce 归零 + 测试全绿，同一 commit 过 pre-commit
commit 2（块 A）：code-implementation.pipeline.json + _index.yml + README
   ↳ pipeline-templates/ 不在 R9 scope，块 A 不触发 R9；块 A 亦不依赖 R9，但顺序上护栏先行（批 3.5 先例）
```

**基线协调（NFR-6）**：tools 仓工作区现有 3 个未提交 pipeline JSON 修改（`auto_push_after_task` default true→false ×2、`source` required→true），其中 `code-implementation.pipeline.json` 与本 CR 同文件不同 hunk——commit 2 前须先与用户确认该三处变更的归属（由其自行提交或声明放弃），本 CR 只 add 本 CR 的 hunk，不得混提。

## 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| 暂停机制 | 既有 `human_approval` 节点 | 新增 pipeline 运行时暂停指令 / inputs 触发时预选-only | human_approval 是声明式模板唯一合法暂停机制（AGENTS.md）；备选简化方案（只加输入不插节点）无法满足"评审时刻干预"核心诉求（附件1 §四） |
| 选择结果传递 | 会话上下文 | pipeline JSON 新增变量机制 | pipeline 在 Agent 会话内执行，用户答复对下一节点天然可见；新增变量机制属运行时契约变更，超出本 CR 范围 |
| R9 判据源 | `__dirname` 固定解析 `skills/_index.yml` | `--root` 相对解析 | 对齐 R7/R8 判据源固定模式（CRCTL_PATH/INBOX_SKILL_PATH 先例）；黑盒测试用真实 skill id（如 review-requirement）作违例文本即可命中，fixture 无需自带索引；R9 治理对象就是 tools 包自身 skill 名 |
| R9 级别 | CONTRADICTS | OUTDATED / STALE-REF | 仅 CONTRADICTS/STALE-REF 被 enforce 阻断，OUTDATED 只报告起不到护栏作用（附件2 §4.4） |
| reviewer-model 落点 | dimensions 自报留痕 | `crctl review-record --reviewer-model` 机器可读字段 | 后者需 gates.json/digest 联动，属独立 CR 级改动（附件1 §八.3，列入范围排除） |
| replayNodes | 不加入 0013 | 加入重放 | 一次选择全程复用；显式 nodeId 引用下新节点天然不在重放列表，换模型需求由节点 10 驳回重走承接 |

## 6. FR 到技术实现映射

| FR | 技术实现 | 文件 |
|---|---|---|
| FR-1 | inputs 追加 review_llm（§2.1） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-2 | nodes 插入 0013（§2.2 + §3.1 定稿文案） | 同上 |
| FR-3 | review-code prompt 头部追加（§3.2） | 同上 |
| FR-4 | replayNodes 零改动验证（数组 diff 为空） | 同上（验证项） |
| FR-5 | nodes 12→13 + brief 补「选择代码评审 LLM（人工确认）」 | `pipeline-templates/_index.yml` |
| FR-6 | 节点表插行（L453 后）+ mermaid D8→新节点→D9（L425-426）+ 节点数描述 12→13 | `README.md` |
| FR-7 | R9 四处改动（§4.1 ①~④） | `skills/shared/crctl/scripts/lint-prompts.mjs` |
| FR-8 | 附件2 §4.2 表 17 行按 §3.3 形态逐行改写（requirement 4 + develop 9 + writeback 4） | 17 个 `skills/**/SKILL.md` |
| FR-9 | 输出摘要 `last-push-at` 行（L84）后追加「下一步 : 以 crctl next 为准」行 | `skills/sync/push-progress/SKILL.md` |
| FR-10 | 映射表 approve-requirement 行（L33）加前置注记（verdict=pass 且 blockers=[]） | `agents/requirement-writer.md` |
| FR-11 | 「修改 Skill」规则追加第 7 条（§3.4） | tools 仓 `AGENTS.md` |
| FR-12 | 三类向量（§4.1 落点旁测试文件，makeFixture/runLint 既有基建） | `test/lint-prompts.test.mjs` |
| FR-13 | 提交批次序列 §4.3 + 五步自检 | 流程约束 |
| FR-14 | commit message 延续漂移治理编号（R9 条目标注 G5 呼应 + CR-2026-023 溯源） | 提交规范 |

## 7. 安全与性能考量

- **lint 性能**：R9 每行 3 次字符串判定 + 一次 skillIds 过滤（55 元素），相对既有 R7/R8 同量级；skillIds 集合 loadJudgements 一次载入，不逐文件重读。
- **误报边界**：①「下一步」+「crctl next」同行直接 continue（豁免主形态）；②cr-show 路径豁免；③域外文件零命中（planning/spec/competitive 无 CR 上下文，写 crctl next 反而是新漂移——附件2 §4.1）；④确需手写的单行用 `<!-- lint-prompts:ignore -->` ±1 行豁免留痕。
- **漏报边界**：skill id 判定基于子串包含，短名 skill 理论上可能误命中普通文本——17 处清零时逐行人工核对，测试向量含域外反向用例兜底；pipeline 名模式要求 `pipeline` 词尾共现，收窄误报面。
- **回滚**：commit 1 整体 revert 即恢复（规则 + 清零同批，revert 后 enforce 恢复旧基线）；commit 2 revert 后 pipeline 恢复 12 节点。两 commit 无相互依赖，可独立回滚。
- **边界条件**：review_llm 留空是该输入的主路径（现场三选一），非异常态；超时 4320 分钟与节点 4/10 一致；驳回 abort 后无状态残留（该节点不写状态）。

## 8. Prompt 采纳影响

本 CR diff **不触及** `crctl.mjs` dispatch 分支与 `rules.json#protectedPaths.deny`（R9 是 lint-prompts 新增规则，属平行治理工具；pipeline/SKILL 改动不含 crctl 命令面新增）——按 SDD 模板条件性约定，本节无应采纳清单，留此说明备查。

## 9. 风险与残余

| 风险 | 缓解 |
|---|---|
| 17 处改写漏改/多改导致 enforce 自阻断或遗漏 | FR-13 自检①：上线前 `--mode report` 命中数恰为 17（对照附件2 §4.2 表），实施期以实测为准（行号可能已漂移，以内容锚点定位） |
| tools 仓 3 处未提交修改与本 CR 同文件冲突 | §4.3 基线协调：commit 2 前与用户确认归属，按 hunk 拆分 add |
| README mermaid 图遗漏同步（附件1 §2.6 只提了节点表） | 本 SDD §4.2 第 5 步显式列入 mermaid 改动（实跑核对 README L425-426 存在 D8→D9 直连） |
| R9 对既有 `<!-- lint-prompts:ignore -->` 豁免语义理解偏差 | 豁免为段落级既有机制，R9 不新增豁免代码；测试向量补一条豁免生效用例 |
| D4 运行时层缺口（maxAttempts 耗尽行为） | 不在 tools 包管辖，crctl approve 证据门兜底；PRD 范围排除已声明 |
