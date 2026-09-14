---
id: CR-2026-066-TASK-01
type: TASK
cr-ref: CR-2026-066
plan-ref: "change-requests/CR-2026-066/plan.md"
sdd-ref: "change-requests/CR-2026-066/sdd.md"
target-version: 0.39
title: "pipeline 节点退役与测试面连带闭合：审批后/冗余 checkpoint 节点对象删除 + _index.yml 与四个既有测试文件的同步改写"
slug: pipeline-node-retirement
status: pending
estimate: 24h
depends-on: []
created: 2026-09-14T15:25:00+08:00
---

# CR-2026-066-TASK-01 pipeline 节点退役与测试面连带闭合（G1，FR-4 / FR-5）

## 1. 任务描述

**目标**：把三份 pipeline 中的 checkpoint 节点**按对象删除**（不是改 `onFail`、不是加开关），并把 `pipeline-templates/_index.yml` 的计数与 brief、以及**被删除直接证伪的四个既有测试文件**在同一份 diff 内闭合。删除后三份 JSON 中 **`ref=push-progress` 的节点对象计数 = 0**，节点数 requirement **7→5**、architecture **5→4**、code **16→12**。

**背景**：阶段终点发布点前移到评审 PASS 之后（FR-1，由 TASK-02 落地），门后 checkpoint 节点在 agent 驱动模式下没有强制力且必须新开唤醒（CR-2026-063 实测）。本 CR 的删除是**对象级**的：`id` 不回收不复用、不新增替代节点、不以 `onFail: skip`＋输入端开关变相恢复。

**输入条件**：CR status 进入实施期后为 `developing`；`sdd.md` rev 0.4 已审批（`subject-sha256 78846c1b…`，**不得改一字**）；`plan.md` §0.5/§6/§7/§9 已冻结；`tools` worktree HEAD = `5d5a4ada96b882eb2c640e34bb72857a7073b668`（diff 审计基线）。

**范围边界（`zero_diff`，本卡逐条不触碰）**：`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/controlled-shell/rules.json`、`skills/shared/crctl/gates.json`、`skills/shared/crctl/scripts/test/gate-registry.json`、`pipeline-templates/emit-registry.mjs`、`ARCHITECTURE.md`、`dir-graph.yaml`（其 `pipeline_templates.contract` 第 5 条归 TASK-04，本卡零触碰）、所有 `SKILL.md`（归 TASK-02/04）、`agents/**`（归 TASK-02/04）。**不新增测试文件**（`manifest.files` 保持 21）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 说明 |
|---|---|---|
| `pipeline-templates/requirement-authoring.pipeline.json` | 删 2 节点 + 1 输入 | 删 `…0011-000000000003`（推送 PRD 草稿，`onFail=skip`）、`…0011-000000000007`（推送需求审批结果 checkpoint，`onFail=abort`）对象；删输入 `auto_push_after_prd` |
| `pipeline-templates/architecture-design.pipeline.json` | 删 1 节点 | 删 `…0016-000000000005`（推送架构设计到远端，唯一 `push-progress`，位于 `…0003` human_approval 之后） |
| `pipeline-templates/code-implementation.pipeline.json` | 删 4 节点 + 1 输入 + 1 replayNodes 项 + 1 前提句 | 删 `…0015-000000000003`（TASK 可选 checkpoint）、`…0015-000000000008`（统一 checkpoint）、`…0015-000000000012`（审批后 checkpoint）、`…0015-000000000015`（评审后审批前 checkpoint）对象；删输入 `auto_push_after_task`；`…0009.reviewLoop.replayNodes` 删 `…0008` 项（5→4）；`…0010.approvalPrompt` 删「且评审后 checkpoint `phase=complete`」前提句 |
| `pipeline-templates/_index.yml` | 改 3 行计数 + 3 条 brief | `nodes:` 5 / 4 / 12；三条 `brief` 不再描述已删节点，并补一句「阶段终点发布发生在评审 PASS 的 review SKILL 内」 |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 改 9 处 + 新增 AC-1 断言 | 见 §3.2；**保留既有用例名**（`cmd-03` 的定点模式依赖） |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 改 1 处用例 | `CR-2026-042 静态合同：…`：`inputs` → `['cr_id','target_version']`；节点数改由事实源推导（12）；**保留 `…0017` 直接前驱 `…0009`**；**保留用例名** |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 改 1 条 test 的 L491 | 见 §3.4；**保留用例名**（`checkpoint T05 contract…`） |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 改 replayNodes 快照（L81-98） | code replayNodes 的 ref 快照 5 项 → **4 项**（去 `push-progress`）；`RETIRED_RECOVERY` 段不动（归 TASK-04 追加静态断言） |

## 3. 实现要点

### 3.1 删除顺序与不变量（三份 JSON）

1. 只删**节点对象**与**输入对象**：`id` 不重编号、不复用；不删 `workspace-freshness`（`…0016`/`…0017`）、不删 `code_generation` 节点、不动 `human_approval` 与 `approve-*` 的配对关系。
2. 删除节点的 prompt 中「阶段终点完成条件（CR-2026-044 FR-07）」与 `{{inputs.auto_push_*}}` 字面量随对象一并消失；**存活节点的 prompt 不得残留** `auto_push_after_*` / `SKIPPED` 字面量（`cmd-05` 的 CI 结构断言与全文检索兜底）。
3. `node-N.md` 输出文件名**不改名**（SDD §4.4.2-3：N = 节点 id 末段而非位置序号）；删除后**无悬空引用**（§4.4.2-4 已实测零命中，本卡只需不改名、不新增引用）。
4. `…0014`（review-dev-plan）写 `node-3.md` 的既有命名不一致**不动**（登记为 `follow_up`，不扩大本卡 diff）。

### 3.2 `pipeline-structure.test.mjs` 的 9 处处置（逐条，SDD §6.4）

| # | 既有断言（用例名 / 位置） | 处置 |
|---|---|---|
| 1 | `AC-1: 节点序 review-code(…0009) < checkpoint(…0015) < human_approval(…0010) < approve-code(…0011)` | **删除**该序关系断言，替换为 AC-1 两条判据（§3.3） |
| 2 | `AC-2: checkpoint 节点 onFail=abort、ref=push-progress；节点 id 全局唯一（CR-2026-042 后 16 节点）` | **改写**：节点数按事实源推导（12）；删 `…0015` 相关断言；保留「id 全局唯一」 |
| 3 | `AC-3: review-code reviewLoop.replayNodes 为 5 项…` | **改写**：4 项（去掉 `…0008`），仍由 JSON 事实源推导 |
| 4 | `…0008 < …0017 < …0009` 相邻关系（L70-72） | **改写**：删除 `…0008` 参与的前置，保留 `…0017` < `…0009` |
| 5 | `…0010.approvalPrompt` 含「评审后 checkpoint phase=complete」（L114-116、L135-137） | **改写为反向断言**：`…0010.approvalPrompt` **不含**该句 |
| 6 | `CR-2026-044 AC-13/14: requirement-authoring 审批后强制 checkpoint（7 节点），草稿 checkpoint 仍可选`（L168-183） | **改写**：5 节点；**「approve-requirement 之后不得有 push-progress」**；`_index.yml#nodes = 5`；删草稿 checkpoint 分支断言 |
| 7 | `CR-2026-044 AC-14: architecture-design 删除 auto_push_after_sdd，审批后 checkpoint abort，5 节点不变`（L186-203） | **改写**：`push.length === 0`、4 节点；保留「prompt 无 `crctl checkpoint` 字面量」与 `<installation-workspace>` 负向断言（对象消失后按事实源推导重写） |
| 8 | `CR-2026-044 AC-13: code-implementation 审批后 checkpoint abort、TASK checkpoint 仍可选、16 节点不变`（L205-213） | **改写**：`ref=push-progress` 计数 = 0 + 12 节点 + `inputs` 不含 `auto_push_after_task` |
| 9 | `CR-2026-045 AC-03: emit-registry 输出 canonical registry 且 digest 稳定`（L262-278） | **改写**：architecture 的 `nodePermissions.length` 4 → **3**（随 `…0005` 删除）；去掉 `byRef['push-progress']` 行；digest 只断格式 `^sha256:[0-9a-f]{64}$`，**不得钉死旧 digest**（删除必然改变 digest，FR-11 只登记不重生成） |
| 10 | `CR-2026-050 AC-12: 8 条 Pipeline 节点数与 UUID 全局唯一保持不变`（L516-530） | **改写**：节点数 5 / 4 / 12（其余 5 条不变）；UUID 全局唯一保持 |
| 11 | FR-12.2/FR-12.3 段（L306-320、L341-375，含 `auto_push_after_prd` 分支与 `…0008` 快照、字面量保留断言） | **改写**：requirement 5 节点顺序 `[requirement-register, write-requirement-prd, review-requirement, human_approval, approve-requirement]`；删 `auto_push_*`/checkpoint label 断言；保留 gate 名与 task done 面 |
| 12 | `L229`（architecture 后续节点不得依赖 `node-1.md`） | **保留**（本卡不涉及） |

### 3.3 新增断言（AC-1 两条判据，单条用例内）

```text
① 三份 JSON（requirement / architecture / code）节点数 ≡ pipeline-templates/_index.yml 的 nodes 计数，且 = 5 / 4 / 12；
② 每份 JSON 中：不存在任何位于 human_approval 之后的 ref=push-progress 节点（按节点序求值）；
   且 nodes[].ref === 'push-progress' 的计数 = 0；
   且被删的 7 个 id 后缀（…0003/…0007/…0005/…0012/…0008/…0015 ＋ requirement 侧 …0003）在任何 JSON 中零出现。
```

- 断言一律**从 JSON 与 `_index.yml` 事实源推导**（NFR-5：不钉死措辞与标点、不写成「等于当前行数」式恒真式）。
- 所有读入先 `\r\n → \n`；解析用 `split(/\r?\n/)`；**跨行解析失败硬失败**（工程纪律 #1：禁止「匹配不到 → 空集 → 静默通过」）。这是本卡最容易被咬的一处：`AC-1` 的判据若写成 `nodes.filter(...)` 后 `assert.equal(hits.length, 0)` 而不先断言 `nodes.length > 0`，JSON 解析失败时会静默通过 —— **必须先断言节点集非空**。

### 3.4 `checkpoint-tx.test.mjs` 的精确锚点（S-14，逐字）

- 用例名（**保留不改**）：`checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]`。
- **整条 test 起于 L487、`filter(...)` 在 L491、止于 L506**；其中 **L495-506** 是 review-alignment 事实源断言（`change-requests/_backlog.yml` / `cr.md` 命中、`latest-checkpoint` 与 `checkpoints[]` 零命中、三词否定辖域），**必须逐字保留**。
- **只改 L491 的 `filter` 形态**：现文 `doc.nodes.filter(n => n.ref === 'push-progress' || n.ref === 'list-remote-checkpoints')` 在删除 7 个节点后退化为单元素集合（只剩 `resume-cr` 的 `list-remote-checkpoints`），**禁止**保留会随删除退化为空集的 `filter` 形态。
- 改法：改为**显式枚举**剩余节点集合 —— `resume-cr` 的 `list-remote-checkpoints` 逐条负向断言；requirement / architecture / code 三份断言其 `push-progress` 节点集合为**空集**（显式 `deepEqual(..., [])`）；并断言该枚举**非空**（防「过滤为空 → 断言静默失效」）。

### 3.5 通用纪律

- 断言只读：不写 `cr.md` / `_backlog.yml` / `tasks/_index.yml` / `approval.yml` / `review-annotations/**`。
- 不新增测试文件、不改 `gate-registry.json`（`manifest.cases` 是下界，新增用例数不需要登记）；**本卡不新增用例数**（新增断言并入既有用例体）。
- 落盘后自查：`node --test --test-reporter=dot <本卡改动的四个测试文件>` 全绿；`crctl git status --short` 仅本卡 8 个文件。

## 4. 验收条件（可执行）

1. **`cmd-02`**（plan §6.2，`repo=tools`）：`node --test --test-reporter=dot skills/shared/crctl/scripts/test/pipeline-structure.test.mjs skills/shared/crctl/scripts/test/contract-scan.test.mjs` → **exit 0**（变更前实测 exit 0 / 各 ≈ 1 s；变更后须在新断言下仍绿）。
2. **`cmd-03`**（plan §6.2）：定点跑 `CR-2026-042 静态合同` / `checkpoint T05 contract` / `CR-2026-044 AC-13` / `CR-2026-044 AC-14` / `CR-2026-050 AC-12` → **exit 0**，且 stdout 命中数 ≥ 5（证明 5 个既有用例名仍在、断言体已按新事实改写）。
3. **`cmd-01`** 全量套件（`suite-gate.mjs --run`）→ `verdict=pass` / `failures=0` / `files_executed=21` / `cases_executed ≥ 588`；`cmd-05` 的 tools diff 白名单在本卡覆盖的 8 个文件上无「缺少应改文件」。
4. 负控自检（非证据、不进 `test-evidence/`）：临时把某份 JSON 的节点数改回旧值（或把 `_index.yml` 的 `nodes` 改回 7/5/16）→ 对应断言**必须红** → 还原 → `crctl git status --short` 干净。
5. `zero_diff` 面自查：`crctl git diff --stat -- <§1 范围边界的文件清单>` 为空。

## 5. 完成标志

- 8 个文件就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-02` / `cmd-03` exit 0；`cmd-01` 全量套件绿（无例外）。
- SDD §6.4 的 14 处连带改写**逐行核对表**写入本任务完成记录（每行 = 断言 → 处置 → 新落点），不得遗漏任一行为「无需改」（若判定无需改，写明理由）。
- `pipeline-templates/_index.yml` 的三条 brief 与三份 JSON 事实一致；三份 JSON 中 `ref=push-progress` 计数 = 0（在完成记录中留 `grep` 证据）。
- **任务账本登记**：`crctl task done CR-2026-066 --task CR-2026-066-TASK-01`（`tasks/_index.yml` 即时标 `done` 并带 `done-at`，不积压到回写期，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `pipeline-templates/*.pipeline.json`：既有节点 id（`…0011-000000000003` 等 7 个删除对象）与 `inputs[].key` 命名；`reviewLoop.replayNodes[]` 的 `{nodeId, ref, purpose}` 形状。
- `pipeline-templates/_index.yml`：`pipeline-templates[].{id, path, nodes, brief}`（`dir-graph.yaml#pipeline_templates.contract` 第 1 条要求同步 `nodes` 计数）。
- `skills/_index.yml`：`status: active` 的 skill id 集合（CI 结构断言要求 pipeline 的 `ref` 必须在其中）。
- `gate-registry.json`：**只读**（`manifest.cases` 作为下界基线；本卡不改）。

**产出（下游 TASK 消费方不得缩略）**

- 三份 JSON 的**终态节点集**：requirement 5 / architecture 4 / code 12，且 `ref=push-progress` 节点数为 0 —— 这是 TASK-02 的发布点唯一性前提（发布只发生在 review SKILL 内）与 TASK-04 的口径改写前提（`push-progress` SKILL 的「调用时机」不再描述节点）。
- `pipeline-structure.test.mjs` 的**改写后断言块**：TASK-02 将在同一文件**追加** AC-3/AC-4 断言（含四个 review SKILL 的 token 断言与 S-13 的负向 token 断言）——TASK-02 追加时不得改动本卡已改写的既有用例名与断言语义。
- `contract-scan.test.mjs` 的 code replayNodes **4 项 ref 快照**：TASK-04 在同一文件追加 FR-7 静态文本断言时以本快照为基线。
