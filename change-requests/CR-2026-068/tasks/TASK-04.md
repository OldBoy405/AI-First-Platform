---
id: CR-2026-068-TASK-04
type: TASK
cr-ref: CR-2026-068
plan-ref: "change-requests/CR-2026-068/plan.md"
sdd-ref: "change-requests/CR-2026-068/sdd.md"
target-version: 0.41
title: "implement-code 环境节追加 readiness 两条 bullets + …0004 approvalPrompt 值替换 + 交付面/零 diff 收口"
slug: implement-devstart-and-closeout
status: pending
estimate: 6h
depends-on: [CR-2026-068-TASK-01, CR-2026-068-TASK-02, CR-2026-068-TASK-03]
created: 2026-09-15T23:25:00+08:00
---

# CR-2026-068-TASK-04 implement 侧 + dev-start 提示 + 收口（G4，FR-5 implement/dev-start 两侧 / FR-6）

## 1. 任务描述

**目标**：完成 SDD §6.5-F/G 两处落点——`skills/develop/implement-code/SKILL.md` 环境节末追加 readiness 即时性与环境无关 TASK 隔离两条 bullets（既有六条逐字保留）；`pipeline-templates/code-implementation.pipeline.json` 节点 `…0004` 的 `approvalPrompt` **字符串值整体替换**（节点对象其余字段与节点集零变化）。随后执行**交付面/零 diff 收口**：`cmd-03` / `cmd-04` / `cmd-05` 全部清零、`cmd-06` / `cmd-02` exit 0，diff 面恰 5 文件。

**背景**：FR-5 的 implement 侧与 dev-start 侧唯一落点（SDD §6.1）；FR-6 的零 diff 面由本卡收口审计承载。

**输入条件**：同 TASK-01；依赖 TASK-01/02/03 先落地（收口审计对象是全部改动的终态 diff；`…0004` 提示文字消费 plan 侧修复路径语义）。

**范围边界（本卡只改 2 个文件）**：`skills/develop/implement-code/SKILL.md`（追加 2 条 bullets）＋ `pipeline-templates/code-implementation.pipeline.json`（1 个字符串值）。**逐条不触碰**：其余 3 个交付文件、`pipeline-templates/**` 中 `…0004.approvalPrompt` 以外的全部内容（含 `_index.yml` 计数 5/4/12、`…0014.reviewLoop`、其余节点 prompt）、全部 `zero_diff` 面。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点 |
|---|---|---|
| `skills/develop/implement-code/SKILL.md` | 追加 2 条 bullets（环境节末，同节共生，不改写既有 bullets） | L102 `## 环境验证与 ENVIRONMENT_MISMATCH`（唯一详细事实源声明 + 六条既有 bullets：一次环境检查 / 最多一次重跑 / timeout 与测试入口 / 标签不写 crctl 面 / 临时隔离实例例外 / 受控建立归因）；追加位置 = 第六条（「验证环境已受控建立时……」）之后、`## 禁止事项` 之前 |
| `pipeline-templates/code-implementation.pipeline.json` | 1 处：`…0004.approvalPrompt` 字符串值整体替换 | 节点 id `00000000-0000-0000-0015-000000000004`（L92）；现行值含「❌ 暂缓：补充任务拆分意见，重新执行 write-dev-tasks 后再确认」；节点对象其余字段：kind=human_approval、label「确认进入代码开发」、onFail=abort、timeoutMinutes=4320 |

**段级零 diff（本卡逐字保留）**：implement-code 的环境节既有六条 bullets、唯一事实源声明、其余全部章节；pipeline 的节点集/顺序/id、`…0014.reviewLoop`（repairRef=write-dev-plan、replayNodes 三项 purpose 文本、maxAttempts=3、passCondition、onBlock）、全部其余节点对象。

## 3. 实现要点

### 3.1 修订 ①（SDD §6.5-F）：implement-code 环境节末追加以下**逐字**两条 bullets

```text
- 即时 readiness：在**第一个依赖环境的 TASK 前**执行 plan 指定的 readiness `cmd-NN`；该命令是既有「一次环境检查」在环境依赖 TASK 上的执行内容（不是新的反复探测），仍受「最多一次重跑」、测试计划 timeout 与受控入口约束。
- 失败时按既有 `ENVIRONMENT_MISMATCH` 中止并报告所需建立动作；**环境无关 TASK 不被提前阻断**（readiness 未通过只阻断依赖该环境的 TASK）。
```

**保持性**：既有六条 bullets 逐字保留（含「一次环境检查：任务开始时只做一次有界前提检查（依赖、路径、权限、端口等），不反复探测。」与「最多一次重跑」句）；`本 Skill 是有界验证与 \`ENVIRONMENT_MISMATCH\` 的唯一详细事实源` 声明不动（write-dev-plan 侧只引用不复述的单一事实源地位）。

### 3.2 修订 ②（SDD §6.5-G）：`…0004.approvalPrompt` 值替换为以下**逐字** JSON 字符串值

```json
"approvalPrompt": "TASK 拆分已完成（change-requests/{{inputs.cr_id}}/plan.md 与 tasks/），当前应为 task-breakdown。请确认是否进入代码开发，并一并确认 plan.md「验收与发布策略」声明的环境静态前提：\n\n环境静态前提（只确认静态事实，不要求审批时所有服务在线）：环境 owner 已明确、建立方式已写明、可获得性已声明。动态健康状态由 implement-code 在第一个依赖环境的 TASK 前用 plan 指定的 readiness 证据即时验证，审批不为其背书。\n\n✅ 通过：勾选此 Todo，下一节点 approve-dev-start 会记录确认并推进到 developing\n❌ 暂缓：补充任务拆分意见或环境前提说明后，按缺口所属产物回到对应写作节点（plan 侧环境声明回 write-dev-plan、TASK 拆分侧回 write-dev-tasks）重新执行后再确认"
```

**保持性**：节点 `id` / `kind` / `label` / `onFail` / `timeoutMinutes` 不变；节点集 12 个不变；`{{inputs.cr_id}}` 模板占位符形态保留。

**字面量自查（逐条对应 `dep-15`）**：不含 `git` / `journal`（词边界零命中）；不含 `review-annotations` / `reject_reason`；不含旧 `❌` 分支残留（`重新执行 write-dev-tasks 后再确认` 零命中）；保留 ✅ 通过 / ❌ 暂缓两分支结构化决定。

### 3.3 收口（FR-6 / plan §5.1）

- 按 plan §6.2.5 转录纪律把 `.crctl/tmp/audit-{skill,ci,diff}.js` 平面化为 `cmd-03`~`cmd-05` 的单 `-e` 参数（无裸双引号/反斜杠/换行/竖线），在本机干跑确认与 plan §6.3 语义一致后交付 `write-test-report`。
- 收口断言：`cmd-03` failures = 0（写侧 + tasks + review + pipeline + implement 五组全清零）、`cmd-04` failures = 0、`cmd-05` 输出 `tools diff paths = 5` 且 failures = 0、`cmd-06` exit 0、`cmd-02` exit 0。
- `git status --short`（经 `crctl git status --short`）只显示本卡 2 个文件（TASK-01/02/03 已各自提交后为空增量）。

### 3.4 通用纪律

同 TASK-01 §3.4；额外注意 pipeline JSON 的落盘必须保持既有缩进与键序（除目标值外逐字节不变），落盘后 `cmd-04` 的字段不变断言兜底。

## 4. 验收条件（可执行）

1. **`cmd-03` / `cmd-04` / `cmd-05` 全部 failures = 0**（plan §6.2；`repo=tools`，`cwd=.`）——含 `cmd-05` 输出 `tools diff paths = 5` 且白名单双向相等、zero_diff 前缀表零命中。
2. **`cmd-02` exit 0**：`dep-15` CR-2026-043（`\bgit\b` / `\bjournal\b` 对全部 prompt 与 approvalPrompt 零命中）与 CR-2026-050（human_approval 无 `review-annotations` / `reject_reason`、保留 approve/reject）用例真实执行仍绿。
3. **`cmd-06` exit 0**（lint-prompts / skill-matrix / agents-contract / writeback-tests / pipeline JSON 结构断言）。
4. **负控自检**（非证据）：临时在 `…0004.approvalPrompt` 写入 `journal` 一词 → `cmd-02` 的 CR-2026-043 用例必须红 → 还原 → `cmd-03` 的 `FAIL pipeline residual 重新执行 write-dev-tasks 后再确认` 消失确认。
5. **边界自查**：`gate-registry.json`、全部测试文件、其余 `zero_diff` 面的 `git diff --stat` 为空；`_index.yml` 三处计数 5/4/12 不变。

## 5. 完成标志

- 2 个文件修订就位并随 CR 提交；`cmd-03`/`cmd-04`/`cmd-05` 全清零、`cmd-02`/`cmd-06` exit 0，输出留档（diff 面恰 5 文件 = SDD §9 `scope_in` 双向相等）。
- 可机械核对事实写入任务完成记录：① `…0004` 五个其余字段值逐项留档；② implement 环境节 bullets 数 6 → 8 且既有六条逐字在位；③ diff 白名单输出原样粘贴。
- **任务账本登记**：`crctl task done CR-2026-068 --task CR-2026-068-TASK-04`（即时标 `done`，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/develop/implement-code/SKILL.md` 既有环境节六条 bullets 与唯一事实源声明；`…0004` 节点对象现行 approvalPrompt 值与其余字段。
- TASK-01 产出的 plan 侧环境五要素与 readiness 复用判据（`…0004` 提示文字的「plan.md「验收与发布策略」声明的环境静态前提」承接句与修复路径句）。
- `change-requests/CR-2026-068/sdd.md#§6.5-F/G` 与 §4.5（逐字目标文本与三侧流程；冲突时以 SDD 为准）。

**产出（下游 TASK 消费方不得缩略）**

- implement 侧即时 readiness 执行合同（第一个依赖环境的 TASK 前执行、最多一次重跑、失败 `ENVIRONMENT_MISMATCH` 中止、环境无关 TASK 不提前阻断）——`implement-code` 执行期行为与 `review-code` 的消费面。
- dev-start 侧静态前提确认文本（✅/❌ 两分支）——human_approval 节点展示 + `approve-dev-start` 的消费面。
- 收口审计的终态 diff 事实（恰 5 文件）——`write-test-report`（`cmd-03`~`cmd-06`）与 `review-code` 的证据面。
