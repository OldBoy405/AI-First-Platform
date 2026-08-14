# 代码评审前 LLM 选择暂停方案（code-implementation pipeline 改造）

- 日期：2026-08-06
- 范围：tools 包（phase0）`pipeline-templates/code-implementation.pipeline.json` 及其台账/文档同步
- 需求：代码评审（review-code）前流水线暂停，由人工选择执行评审的 LLM
- 结论摘要：在节点 8（push-progress 统一 checkpoint）与节点 9（review-code）之间插入 human_approval 暂停节点，配合触发参数 `review_llm` 双保险；repair 循环不重问；同步 `_index.yml` nodes 计数与 README。

---

## 一、现状与问题

code-implementation pipeline（`/coding`，12 节点，UUID 前缀 `0015-*`）当前顺序：

```text
1 write-dev-plan → 2 write-dev-tasks → 3 push-progress(可跳过) → 4 human_approval(确认开发)
→ 5 approve-dev-start → 6 implement-code(code_generation) → 7 write-test-report(reviewLoop)
→ 8 push-progress(统一 checkpoint) → 9 review-code(reviewLoop) → 10 human_approval(代码审查通过)
→ 11 approve-code → 12 push-progress(审批结果)
```

节点 8 推送完成后**直接进入节点 9 自动评审**，中间没有任何暂停点，无法干预由哪个 LLM 执行评审。

### 现有机制盘点

| 机制 | 能力 | 是否满足需求 |
|---|---|---|
| pipeline `inputs` | 触发时填表（text/select/boolean），注入 prompt | 只能触发时预选，无法"评审前暂停" |
| `human_approval` 节点 | 声明式模板中**唯一合法的暂停机制**，approve/reject + approvalPrompt 引导会话 | ✅ 作为暂停点；选择动作通过会话完成 |
| `code_generation` kind 的 runtime 选择 | 节点 6 implement-code 按 `defaultRuntimeId` → fallback external CLI runner 解析 | 仅 code_generation 节点适用；review-code 是 skill 节点，需 prompt 层承接选择结果 |

AGENTS.md 约束核对：`human_approval` 不得替代状态写入——本方案该节点只做暂停确认，不写 CR 状态，合规。

---

## 二、完整方案（四步改动 + 两项同步）

### 2.1 新增 pipeline 输入 `review_llm`（触发时预选，可选）

在 `pipeline-templates/code-implementation.pipeline.json` 的 `inputs` 数组追加：

```json
{
  "key": "review_llm",
  "label": "代码评审 LLM",
  "type": "text",
  "required": false,
  "placeholder": "留空则在评审前暂停由人工选择",
  "description": "指定执行 review-code 的模型/runner；留空时节点「选择代码评审 LLM」会暂停等待人工选择"
}
```

作用：熟手触发 `/coding` 时一次选定，暂停节点快速确认；留空则走现场选择流程。

### 2.2 插入 human_approval 节点「选择代码评审 LLM」

pipeline 节点执行顺序由数组顺序决定（UUID 仅作标识）。在节点 8（`0015-000000000008` push-progress）之后、节点 9（`0015-000000000009` review-code）之前插入：

```json
{
  "id": "00000000-0000-0000-0015-000000000013",
  "kind": "human_approval",
  "label": "选择代码评审 LLM",
  "approvalPrompt": "代码与测试证据已推送统一 checkpoint，即将进入代码评审。\n\n若触发参数 review_llm 已指定，请按该模型执行；否则请在此暂停并询问用户选择评审 LLM：\n① 当前会话默认模型\n② 外部 CLI runner（按代码执行设置中可用 runner 列出选项）\n③ 其他指定模型\n\n记录用户选择后再勾选继续；驳回则中止本轮评审。",
  "onFail": "abort",
  "timeoutMinutes": 4320
}
```

设计说明：

- 选择结果通过会话上下文传给下一节点——pipeline 在 Agent 会话内执行，用户答复对 review-code 节点天然可见，无需 JSON 层新增变量机制；
- `timeoutMinutes: 4320` 与既有人工确认节点（节点 4/10）保持一致；
- `onFail: abort`：驳回即中止，不允许无选择进入评审。

### 2.3 修改节点 9（review-code）prompt 头部

在现有 prompt 最前面追加一段（其余取证与落盘要求不变）：

```text
执行评审前确认上一节点选定的评审 LLM（触发参数 {{inputs.review_llm}} 或人工审批环节的用户选择）；
按该模型/runner 执行本评审，并在 .crctl/tmp/review-code.yml 的 dimensions 中记录 reviewer-model 字段，
使评审证据可追溯由哪个模型产出。其余取证与落盘要求不变
（评审判断写临时 payload，经 crctl review-record --stage code --bump-attempt 落盘 review-annotations/code.yml）。
```

评审落盘链路不变（临时 payload → `crctl review-record` canonical 写入），仅增加 reviewer-model 留痕维度。注意：canonical 文件的 `reviewer` 字段仍由 crctl 注入 `identity(ws)`，模型名记录在 dimensions 内，不改 crctl 契约。

### 2.4 repair 循环取舍：重放序列不加入选择节点

节点 9 review-code 的 `reviewLoop.replayNodes` 声明 block 后重放序列：

```text
0015-…-0006 implement-code → 0015-…-0007 write-test-report → 0015-…-0008 push-progress → 0015-…-0009 review-code
```

**新插入的选择节点（0013）不加入 replayNodes**——否则每轮自修复都重新询问一次 LLM。原则：一次选择、全程复用；若某轮修复后确需换模型重审，由人工在 human_approval（节点 10）驳回后重走。write-test-report 的 reviewLoop（重放 006→007）同理，不受影响。

### 2.5 台账同步：`pipeline-templates/_index.yml`

AGENTS.md 规定「修改节点数量后同步 `_index.yml` 的 nodes 字段」：

```yaml
- id: code-implementation-v1
  nodes: 13          # 原 12
  brief: >-
    ... → 生成测试报告 → 统一 checkpoint → 选择代码评审 LLM（人工确认）
    → 代码评审 → 代码审批（人工）→ approve-code 状态推进 → 审批结果 checkpoint。
```

### 2.6 文档同步：`README.md` 代码编写期节点表

在「推送代码+文档统一 checkpoint」与「代码评审」两行之间插入：

```markdown
| 选择代码评审 LLM | 统一 checkpoint 结果、触发参数 `review_llm` | 暂停等待人工选择执行评审的模型/runner；已指定 review_llm 时快速确认 | 无状态写入 | 否 |
```

---

## 三、改动后的完整节点序列（13 节点）

```text
1  write-dev-plan          skill            0015-…-0001
2  write-dev-tasks         skill            0015-…-0002  → task-breakdown
3  push-progress           skill(可跳过)     0015-…-0003
4  确认进入代码开发         human_approval    0015-…-0004
5  approve-dev-start       skill            0015-…-0005  → developing
6  implement-code          code_generation   0015-…-0006
7  write-test-report       skill(reviewLoop) 0015-…-0007
8  push-progress 统一checkpoint skill        0015-…-0008
9  选择代码评审 LLM         human_approval    0015-…-0013  ← 新增
10 review-code             skill(reviewLoop) 0015-…-0009  → code-reviewing
11 代码审查通过             human_approval    0015-…-0010
12 approve-code            skill            0015-…-0011  → code-approved
13 push-progress 审批结果   skill            0015-…-0012
```

---

## 四、备选简化方案（不推荐，仅留档）

只做 2.1 + 2.3（加输入 + prompt 引用），不插入 human_approval 节点：

- 优点：零节点插入，`_index.yml` nodes 不变，改动最小；
- 缺点：无法满足"评审前停下来选择"的核心诉求——只能在触发 `/coding` 时预选，评审时刻不可再干预。

用户诉求明确为「停下来让我选择」，故采用完整方案。

---

## 五、任务接收声明（AGENTS.md 格式）

| 项目 | 内容 |
|---|---|
| 目标范围 | `pipeline-templates/code-implementation.pipeline.json`（inputs + 新节点 + 节点 9 prompt）、`pipeline-templates/_index.yml`（nodes/brief）、`README.md`（代码编写期节点表） |
| 不在范围 | crctl.mjs、gates.json、rules.json、其他 7 条 pipeline、develop/ skill 文档、agent-skill-matrix.yml（未新增 skill 无需变更）、skills/_index.yml（无 skill 增删） |
| 计划产出 | 上述 3 文件修改 + 自检（见下） |

## 六、自检清单

```bash
# 1. pipeline JSON 可解析（AGENTS.md 规定自检）
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"

# 2. pre-commit 三件套（新节点 prompt 不含 crctl advance 参数形态违例、裸 git 等，应全绿）
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce

# 3. 台账一致性：_index.yml nodes=13 与 JSON 实际节点数一致（人工核对或 check 脚本覆盖）
```

### 6.1 落地前实测核对记录（2026-08-06，tools 包 `C:\Users\GOBAO\Downloads\AI\tools` 实测）

方案承重假设已在 tools 包源码实跑核对，全部对上：

```bash
# 现状节点数与序列
node -e "const p=require('./pipeline-templates/code-implementation.pipeline.json'); console.log('nodes:',p.nodes.length); p.nodes.forEach((n,i)=>console.log(i+1,n.id.slice(-4),n.kind,n.label))"
```

- **12 节点、序列与 §一 完全一致**（0001–0012 严格按数组序，label 逐条对上）→ 12→13 的插入前提成立。
- `inputs` 现为 `[cr_id, target_version, auto_push_after_task]` → §2.1 追加 `review_llm` 无冲突。
- `_index.yml` 该条 `nodes: 12` → §2.5 需改 13，确认。

```bash
# reviewLoop.replayNodes 现状（§2.4 前提）
node -e "const p=require('./pipeline-templates/code-implementation.pipeline.json'); p.nodes.filter(n=>n.reviewLoop).forEach(n=>console.log(n.label,JSON.stringify(n.reviewLoop.replayNodes.map(r=>r.ref))))"
```

- review-code 的 `replayNodes` = `implement-code → write-test-report → push-progress → review-code`，且**按显式 `nodeId` 引用而非位置序**。→ 新节点 `0013` 不在任何 replay 列表内，天然不被重放，§2.4"一次选择全程复用"成立，且不因位置插入而误入重放循环。

结论：Doc 1 承重假设无需修订，仅保留正文两条建议（§四已论证的 `review_llm` 输入可按 YAGNI 缓上；`reviewer-model` 措辞改为"留痕（自报）"，并点明节点 10 人工审批为选择被忽略时的兜底）。

## 七、流程决策

与 `docs/review-skip-drift-and-r9-guard-2026-08-06.md` 第五章同理：本改动属 tools 包模板治理，**不开 CR，直接提交 tools 仓**，commit message 延续漂移治理编号风格并注明需求来源。

## 八、遗留与后续

1. 外部 CLI runner 的可用清单在 approvalPrompt 中要求"按代码执行设置列出"，具体枚举由目标运行时提供，tools 包不硬编码模型名（可移植性约束）；
2. 若 R9 护栏（见 review-skip-drift 文档）先行落地，新增节点的 prompt 文案需同步过 lint；
3. reviewer-model 目前记录在 dimensions 内；若未来需要机器可读的评审模型审计（如按模型统计 blocker 率），再评估扩展 `crctl review-record` 的 `--reviewer-model` 旗标（需同步 gates.json 与 digest 计算，属独立 CR 级改动）。
