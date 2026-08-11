# 需求期跳评审漂移分析与 R9 护栏方案

- 日期：2026-08-06
- 范围：tools 包（phase0）需求期及全部 CR 上下文域的 skill 输出提示漂移
- 关联：`docs/prompt-audit-report-2026-08-05.md`（G5 lint 规则思路）、漂移治理 v2（crctl TASK-11 lint-prompts）
- 结论摘要：机器门禁无法绕过需求评审，观测到的「写完 PRD 未评审就到下一步」是**提示链层漂移**；修复方式为 lint-prompts 新增 R9 规则 + 16 处存量手写副本清零；变更**不开 CR**，直接提交 tools 仓。

---

## 一、问题现象

requirement-authoring pipeline（`/requirement`）运行中，CR 在写完 PRD 后，有时未执行 `review-requirement` 就「进入下一环节」。需要定位漂移发生的位置。

pipeline 节点顺序（6 节点，UUID 前缀 `0011-*`）：

```text
1 requirement-register → 2 write-requirement-prd → 3 push-progress(可跳过)
→ 4 review-requirement(reviewLoop) → 5 human_approval → 6 approve-requirement
```

节点 4 无 `skip_*` 参数、`onFail: abort`，pipeline JSON 层不存在合法跳过路径。

---

## 二、逐层核查：机器门禁 fail-closed，台账层跳不过

### 2.1 `crctl advance` 门禁（进入评审态）

`skills/shared/crctl/gates.json#statusGates`：

```json
"requirement-reviewing": [
  { "type": "fileExists", "path": "change-requests/{cr}/prd.md" },
  { "type": "passCondition", "stage": "requirement" }
]
```

`crctl.mjs cmdAdvance` 对目标态执行 `runGateChecks`，未过即 `GATE_BLOCKED` 拒绝写入。**没有评审通过证据，连 `requirement-reviewing` 都进不去。**

### 2.2 `crctl approve` 三重硬检查（推进 requirement-approved）

`crctl.mjs cmdApprove`（L1039-1069）：

1. **TTY/grant 检查**：非交互式会话一律 `APPROVAL_REQUIRES_HUMAN` 拒绝，无旁路；
2. **前置态检查**：`stageCfg.expect = ["requirement-reviewing"]`，不符即 `CR_STATUS_CURRENT_MISMATCH`；
3. **证据检查**：`evaluatePassCondition` 校验 `review-annotations/requirement.yml` verdict=pass 且 blockers=[]，未过即 `GATE_BLOCKED`。

### 2.3 passCondition 解析 fail-closed

`evaluatePassCondition`（L528-559）与 `loadPipeline`（L320-329）：

- pipeline 模板找不到 → `PIPELINE_NOT_FOUND` 硬失败；
- 节点或 reviewLoop 缺失 → `pass: false`；
- 证据文件缺失 → 该条件 FAIL。

**不存在 fail-open 路径。**

### 2.4 结论

若某 CR 的 `_backlog.yml` 真的到达 `requirement-approved`，则必然存在通过的评审证据。**观测到的「跳评审」是会话流/Todo 推进跑在状态台账前面**——Agent 在对话里"进入下一环节"，但实际未调用 review-requirement，台账通常仍停在 `drafting`。验证手段：对实际漂移的 CR 跑 `crctl status {cr_id}` / `crctl gate {cr_id}` 确认。

---

## 三、漂移点定位（D1–D5）

### D1（主因）：write-requirement-prd 的「下一步」提示给出等价分叉

`skills/requirement/write-requirement-prd/SKILL.md` 输出摘要：

```text
下一步 : 执行 review-requirement 或 push-progress
```

「或」把可选 checkpoint 推送与强制评审并列成等价选项。pipeline 顺序本身是 PRD→push→review（推送夹在中间），选 push 不算错，问题在下一步。

### D2（放大器）：push-progress 输出摘要没有「下一步」指引

对比其他 skill 输出均有明确「下一步」行，`skills/sync/push-progress/SKILL.md` 的摘要到 `last-push-at` 即止。**引导链在此断裂**：Agent 推完 checkpoint 后无任何显式指令要求回到评审，易判定"本环节完成"直接收尾，或下一轮对话直奔审批。

### D3：requirement-writer 意图映射表无前置条件

`agents/requirement-writer.md` Skill 映射表「批准需求 / 推进状态 → approve-requirement」直连，无前置注记。用户意图为"批准/继续"时映射表先命中；Agent 被 crctl 拒绝后常见降级行为是把失败翻译成"那先讨论架构设计"——流程上即"到下一步"。禁止行为第 4 条虽有「不得跳过 review-requirement 直接 approve」，但约束与引导分离，引导侧先命中。

### D4：reviewLoop maxAttempts 耗尽后无机器级停止

pipeline 节点 4 prompt 与 `review-requirement/SKILL.md` 错误表均只有文字约定「达到 maxAttempts=3 后停止」。耗尽后 pipeline 运行时的行为**不受 tools 包约束**；若运行时把重试用尽的节点标记为"已完成"并推进 human_approval，人工看到 Todo 呈现即可能点批准。兜底仅剩 crctl approve 证据门。

### D5（根因模式）：skill 输出手写「下一步」副本，未收敛到 crctl next

`crctl next` 的推荐逻辑权威且正确（`crctl.mjs` L2214-2222：`drafting` 且 prd.md 存在 → review-requirement；`requirement-reviewing` 且无评审记录 → "先跑 review-requirement"）。cr-show 已在 FR-22 完成「废除本地硬编码映射表、统一跑 crctl next」的修复，但需求期各 skill 的输出提示仍是手写副本——**同一漂移模式，尚未扫到需求期 skill 组**。

---

## 四、护栏方案：lint-prompts R9 规则

### 4.1 边界原则：不是「需求期目录」，而是「CR 状态机上下文」

`crctl next {cr_id}` 的本质是读取某 CR 的当前 status + 评审证据 + 门禁缺口给出权威下一步，**必须有 cr_id**。因此：

| 分类 | 域 | 是否适用 R9 | 理由 |
|---|---|---|---|
| CR 上下文 | requirement / develop / develop 审批组 / writeback / sync / cr | ✅ 适用 | 全部围绕在途 CR 工作；cr-show 已验证 crctl next 覆盖全部非终态 |
| 无 CR 上下文 | planning / competitive / spec | ❌ 不适用 | 主分支流程无 CR，写「以 crctl next 为准」反而是新漂移 |
| 权威本体 | cr/cr-show | ❌ 豁免 | 它就是执行 crctl next 生成建议的视图 skill |

**初版「只扫 skills/requirement/」是过度保守**：全库 grep 证实 develop/ 与 writeback/ 存在完全同构的手写副本（13 处），漂移风险一致（跳过 review-tech-design / review-code 直接审批、测试 block 未修进评审、跳过回写步直接归档）。正确范围是全部 CR 上下文域。

### 4.2 手写副本存量全景（17 处）

| 域 | 文件（相对 tools 根） | 行 | 现行文本（要点） |
|---|---|---|---|
| requirement | `skills/requirement/requirement-register/SKILL.md` | L106 | 下一步：在 worktree 中执行 write-requirement-prd |
| requirement | `skills/requirement/write-requirement-prd/SKILL.md` | L98 | 下一步：执行 review-requirement 或 push-progress |
| requirement | `skills/requirement/review-requirement/SKILL.md` | L101 | 下一步：{通过→等待人工审批 \| 阻塞→回 write-requirement-prd} |
| requirement | `skills/requirement/approve-requirement/SKILL.md` | L37 | 下一步：write-tech-design |
| develop | `skills/develop/write-tech-design/SKILL.md` | L102 | 下一步：执行 review-tech-design |
| develop | `skills/develop/review-tech-design/SKILL.md` | L82 | 下一步：{PASS→approve-tech-design \| BLOCK→回 write-tech-design} |
| develop | `skills/develop/approve-tech-design/SKILL.md` | L31 | 下一步：write-dev-plan |
| develop | `skills/develop/write-dev-plan/SKILL.md` | L69 | 下一步：执行 write-dev-tasks （★ 实测补录，初版遗漏） |
| develop | `skills/develop/write-dev-tasks/SKILL.md` | L91 | 下一步：push-progress 或等待人工确认后开始编码 |
| develop | `skills/develop/approve-dev-start/SKILL.md` | L36 | 下一步：implement-code |
| develop | `skills/develop/write-test-report/SKILL.md` | L91 | 下一步：{pass→review-code \| block→回 implement-code} |
| develop | `skills/develop/review-code/SKILL.md` | L108 | 下一步：{PASS→approve-code \| BLOCK→回 implement-code} |
| develop | `skills/develop/approve-code/SKILL.md` | L31 | 下一步：writeback pipeline |
| writeback | `skills/writeback/merge-feature-branch/SKILL.md` | L191 | 下一步：执行 writeback-prd-sdd |
| writeback | `skills/writeback/writeback-prd-sdd/SKILL.md` | L76 | 下一步：执行 writeback-tasks |
| writeback | `skills/writeback/writeback-tasks/SKILL.md` | L67 | 下一步：writeback-traceability → cr-archive |
| writeback | `skills/writeback/writeback-traceability/SKILL.md` | L97 | 下一步：cr-archive |

补充建议（R9 扫不到但补上引导链才闭环）：`skills/sync/push-progress/SKILL.md` 输出摘要 `last-push-at` 行后追加 `下一步 : 以 crctl next {cr_id} 为准`。

不命中/豁免项：`write-tech-design` L50（描述性文字无硬编码名）、`merge-feature-branch` L154（同上）、`write-test-report` L58（仅「下一步建议」标题）、`cr-show` L85/91（权威本体）、`planning/record-idea` L74（明确不追加提示）。

### 4.3 统一改写形态

分支语义保留、权威指针收敛：

```text
下一步 : 以 `crctl next {cr_id}` 为准（PASS→等待人工审批；BLOCK→pipeline 自动回 {修复节点} 修复重审）
```

### 4.4 R9 规则实现（`skills/shared/crctl/scripts/lint-prompts.mjs`）

判据源直读 `skills/_index.yml` 台账提取全部 skill id（对齐 R7 直读 crctl.mjs 常量、R8 直读 inbox-emit 枚举的既有模式；新增 skill 自动覆盖，零维护副本）：

```js
// loadJudgements() 内追加：
const skillIndex = fs.readFileSync(SKILLS_INDEX_PATH, 'utf8').replaceAll('\r\n', '\n');
const skillIds = new Set([...skillIndex.matchAll(/^\s*-\s*id:\s*([\w-]+)/gm)].map((m) => m[1]));
```

```js
// runRules() 内，R8 块之后追加：
// R9：CR 上下文 skill 的"下一步"提示必须收敛到 crctl next，禁止手写 skill/pipeline 副本
const CR_CONTEXT_SCOPE = /^skills\/(requirement|develop|writeback|sync|cr)\//;
if (CR_CONTEXT_SCOPE.test(ctx.file) && !ctx.file.includes('/cr-show/')) {
  const names = [...ctx.skillIds].filter((s) => t.includes(s));
  for (let li = 0; li < lines.length; li++) {
    const l = lines[li];
    if (!l.includes('下一步') || l.includes('crctl next')) continue;
    const hit = names.filter((s) => l.includes(s));
    const plHit = l.match(/\b(requirement-authoring|architecture-design|code-implementation|feature-writeback|resume-cr|writeback|coding|architecture)\s+pipeline\b/);
    if (hit.length || plHit) {
      findings.push({ rule: 'R9', level: 'CONTRADICTS', file: ctx.file, line: para.startLine + li, why: 'CR 上下文 skill 的"下一步"提示必须写「以 crctl next {cr_id} 为准」，禁止手写副本' });
    }
  }
}
```

设计决策：

| 决策 | 理由 |
|---|---|
| 级别 CONTRADICTS | 仅 CONTRADICTS/STALE-REF 被 enforce 阻断；OUTDATED 只报告，起不到护栏作用 |
| cr-show 豁免 | 它是执行 crctl next 的视图 skill，引用 skill 名合法 |
| 分支式提示一并收敛 | review-*/write-test-report 的 PASS/BLOCK 表正是 cr-show FR-22 废除的硬编码映射表同构物 |
| `<!-- lint-prompts:ignore -->` ±1 行豁免自动适用 | 个别确有理由手写的行可单行豁免留痕 |
| pipeline 名模式一并捕获 | approve-code「下一步：writeback pipeline」指向 pipeline 而非 skill，skill id 集合扫不到 |

文件头注释同步：规则清单行追加「+ R9（CR 上下文"下一步"提示收敛 crctl next）」。

### 4.5 测试向量（`skills/shared/crctl/scripts/test/lint-prompts.test.mjs`）

按既有 R7/R8 fixture 模式追加；注意 fixture 路径必须落在 `skills/requirement/…` 等 CR 上下文域才会触发 R9（现有 `skills/x/SKILL.md` 会被跳过，不能复用）：

```js
test('R9：CR 上下文"下一步"手写 skill 副本 → CONTRADICTS；crctl next 形态不报', () => {
  const dir = makeFixture({
    'skills/requirement/x/SKILL.md': '# 输出\n\n下一步 : 执行 review-requirement 或 push-progress\n\n# 合规\n\n下一步 : 以 `crctl next {cr_id}` 为准\n',
  });
  try {
    const r = runLint(['--mode', 'report', '--root', dir]);
    assert.ok(r.stdout.includes('R9') && r.stdout.includes('CONTRADICTS'), `应命中 R9: ${r.stdout}`);
    assert.ok(!r.stdout.includes('合规'), 'crctl next 形态不报');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('R9：域外 SKILL.md 的"下一步"不受 R9 约束', () => {
  const dir = makeFixture({
    'skills/planning/x/SKILL.md': '# 输出\n\n下一步 : 执行 write-planning-entry\n',
  });
  try {
    const r = runLint(['--mode', 'report', '--root', dir]);
    assert.ok(!r.stdout.includes('R9'), `域外不报: ${r.stdout}`);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
```

### 4.6 可选配套：AGENTS.md 行为约束条目

「编辑规则 → 修改 Skill」追加一条：

```markdown
7. CR 上下文 skill（requirement/develop/writeback/sync/cr 域）的输出摘要中"下一步"提示一律写「以 `crctl next {cr_id}` 为准」，不得手写 skill/pipeline 名映射副本（lint-prompts R9 强制）。
```

---

## 五、流程决策：不开 CR，直接提交 tools 仓

| 论据 | 说明 |
|---|---|
| 仓库定位 | 本目录是可安装到目标 workspace 的模板包；CR 状态机/worktree/specs 回写机制全部面向目标 workspace 运行时，tools 仓内无 specs/ 基线、无 delivery/task/、无 knowledge-base repo 声明，`requirement-register` 第一步即解析失败 |
| 历史惯例 | crctl.mjs / lint-prompts.mjs 中的「CR-2026-021 / CR-2026-022」均为溯源引用（改动落地某 CR 的决策），改动本身直接提交 tools 仓；本仓 pre-commit 只跑三个自检，无 CR 门禁 |
| 变更性质 | 质量治理/护栏加固，非带用户故事、验收标准、三角色 owner 的产品需求；CR 三角色 owner 模型对此无意义 |

不开 CR ≠ 不走纪律，提交时必须满足：

1. **单一事实源同步**：本次不增删 skill、不改归属 → `skills/_index.yml`、`agent-skill-matrix.yml`、`pipeline-templates/_index.yml` 均无需变更；若动 AGENTS.md 编辑规则需同步确认无冲突；
2. **pre-commit 自检全绿**：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce`；
3. **同批约束**：R9 规则 + 测试向量 + 16 处存量清零必须在**同一 commit**，否则 enforce 钩子阻断自身；
4. **溯源标注**：commit message 与代码注释延续「漂移治理 v2」编号风格，与 `docs/prompt-audit-report-2026-08-05.md` G5 项呼应；
5. **可移植路径**：全部改动不引入本机绝对路径。

---

## 六、落地清单与自检

### 6.1 修改文件清单

| # | 文件 | 改动 |
|---|---|---|
| 1 | `skills/shared/crctl/scripts/lint-prompts.mjs` | loadJudgements 增加 skillIds 判据；runRules 增加 R9 块；头注释规则清单追加 R9 |
| 2 | `skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 追加 R9 正/反向测试向量（含域外豁免用例） |
| 3 | 4.2 表中 17 个 SKILL.md | 「下一步」行改写为 4.3 统一形态 |
| 4 | `skills/sync/push-progress/SKILL.md` | 输出摘要补「下一步 : 以 crctl next {cr_id} 为准」（引导链闭环） |
| 5 | `agents/requirement-writer.md` | Skill 映射表 approve-requirement 行加前置注记（仅当评审 verdict=pass 且 blockers=[]）——D3 修复 |
| 6 | `AGENTS.md`（可选） | 「修改 Skill」规则追加第 7 条 |

### 6.2 自检顺序

```bash
# 1. 规则上线前：确认存量命中恰为 4.2 表所列（不多不少）
node skills/shared/crctl/scripts/lint-prompts.mjs --mode report

# 2. 测试向量
node skills/shared/crctl/scripts/test/lint-prompts.test.mjs

# 3. 存量清零后 enforce 归零（pre-commit 即此命令）
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce

# 4. pipeline JSON 可解析（AGENTS.md 规定自检）
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
```

### 6.3 验证漂移修复效果

对整改后任一在途 CR：

```bash
crctl status {cr_id}    # 权威状态指针
crctl next {cr_id}      # drafting+prd.md 存在时应推荐 review-requirement
```

---

### 6.4 落地前实测核对记录（2026-08-06，tools 包 `C:\Users\GOBAO\Downloads\AI\tools` 实测）

方案初稿基于文档行号断言。落地前在 tools 包源码实跑核对,结果如下。

**① gates fail-closed 诊断根基 —— 确认。**

```bash
node -e "const g=require('./skills/shared/crctl/gates.json'); console.log(JSON.stringify(g.statusGates['requirement-reviewing']))"
# → [{fileExists prd.md},{passCondition requirement}]  与 §2.1 一致
grep -nE 'APPROVAL_REQUIRES_HUMAN|CR_STATUS_CURRENT_MISMATCH|GATE_BLOCKED' skills/shared/crctl/scripts/crctl.mjs
# → L1048 APPROVAL_REQUIRES_HUMAN / L1053 MISMATCH / L1065 GATE_BLOCKED  三重硬检查在位（行号较 §2.2 的 L1039-1069 略移，同块）
```

crctl.mjs 实际路径为 `skills/shared/crctl/scripts/crctl.mjs`（§2 引用省略了 `scripts/` 一级，落地脚本按实际路径）。

**② 存量副本命中 —— 实测 17 处，初版少列 1 处（已在 §4.2 补录）。**

```bash
grep -rnE '下一步' skills/requirement skills/develop skills/writeback skills/sync skills/cr \
  | grep -v 'crctl next' | grep -v 'cr-show'
```

实测命中 17 条可整改副本，初版 §4.2 表仅列 16 条。遗漏项：

```
skills/develop/write-dev-plan/SKILL.md:69   下一步     : 执行 write-dev-tasks
```

该行命中 R9 scope（`^skills/develop/`、非 cr-show），`write-dev-tasks` 是 `skills/_index.yml` 内合法 skill id，且不含 `crctl next` → R9 判 CONTRADICTS。既不在原命中表、也不在"不命中/豁免"清单，属纯遗漏。**若照初版只改 16 条，§6.2 step 3 的 enforce 会因本行保持红灯，触发 §五"同批 commit"纪律的自阻断。** §6.2 step 1「命中恰为表所列，不多不少」的自检正是为此设计，已按实测把清单修正为 17 条。

**③ §4.3 替换文案自触发风险 —— 待落地时确认。** 括号内 `{修复节点}` 必须是占位文本或语义方向（PASS/BLOCK 走向），不得写字面 skill id，否则新形态自身命中 R9。

## 七、遗留与后续

1. **D4 的运行时层缺口**（reviewLoop maxAttempts 耗尽后的行为）不在 tools 包管辖范围，需向平台运行时方确认耗尽语义；tools 侧已通过 crctl approve 证据门兜底；
2. 若后续 spec/ 域出现 CR 关联视图需求，R9 的域白名单需重新评估；
3. 本次修复与审计报告 G5（lint R6/R7 规则设计建议）属同一护栏族，建议在 `docs/漂移治理.md` 系列中登记 R9 条目，保持台账完整。
