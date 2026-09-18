---
id: CR-2026-070-TASK-04
type: TASK
cr-ref: CR-2026-070
plan-ref: "change-requests/CR-2026-070/plan.md"
sdd-ref: "change-requests/CR-2026-070/sdd.md"
target-version: 0.43
title: FR-1 真实 run 记录 + Pi 侧交付证据记录（cmd-05／cmd-06 的取证面）
slug: fr1-smoke-and-pi-delivery-evidence
status: pending
estimate: 12h
depends-on: [CR-2026-070-TASK-01, CR-2026-070-TASK-02]
created: 2026-09-18T11:30:00+08:00
---

## 1. 任务描述

**目标**：产出两份证据文件，使 AC-2／AC-3／AC-4 与 AC-5～AC-8／AC-12 的验收可被机械观测：

1. `change-requests/CR-2026-070/evidence/fr1-smoke.json` —— FR-1 的**三次真实 run** 记录（review-requirement 重放、review-dev-plan 重放、Skill 缺失构造），携带**原始 `toolCalls` 提取**，与 AC-4 的受控文件 before/after sha256（**含 `change-requests/CR-2026-070/review-annotations/*.yml` 至少 1 条**）与 `reviewAnnotationsNewFiles` 空数组；
2. `change-requests/CR-2026-070/evidence/pi-source.json` —— Pi 侧交付事实（上游 URL、基线 SHA、检出路径、检出形态（`detached@v0.85.1` = detached HEAD @ `d981de12`，**无分支**）/HEAD commit、变更文件集、用例与日志哈希、构建命令与产物版本、安装包负向基线）。

**背景**：`dep-1` §5 补充判定口径明示「AC-2／AC-3 必须用真实 smoke run 留证，Prompt 静态断言只证明规则存在，不能替代真实行为验证」；SDD §4.4 固定观察面（Multica 任务 run 的会话记录）与三条场景构造；SDD §4.6 固定 Pi 侧证据的取证算法（文件路径清单 → 归属判定 → 安装包零出现 → 产出方与时点）。

**输入条件**：

- **环境 1（真实 run）**：运行中的平台须由**本 CR 的 multica 构建**服务任务（owner = `owners.development` = Ray 的部署窗口；现网实测二进制 `multica v0.4.41-469-g947386318, built 2026-09-16`）。环境不可用 → 按 `ENVIRONMENT_MISMATCH` 技术中止并报告所需建立动作，**不得**以静态断言顶替；
- **环境 2（Pi 检出）**：`C:\Users\GOBAO\Downloads\AI\pi-mono`（tag `v0.85.1` = `d981de1229ef899957bbe968bc8dcda02a21f477`，`npm ci` + `hydrate-model-data` + `build:offline` 已就位）；
- TASK-01（multica 规则文本）与 TASK-02（Pi 侧改动 + `evidence/pi-vitest.log`）均已完成。

## 2. 涉及文件 / 模块

| 文件 | 动作 |
|---|---|
| `change-requests/CR-2026-070/evidence/fr1-smoke.json` | 新建（schema 见 §6） |
| `change-requests/CR-2026-070/evidence/pi-source.json` | 新建（schema 见 §6） |

**零改动**：`prd.md`／`sdd.md`／`plan.md`／`tasks/**`／五类受控账本／`specs/`／`delivery/`／`docs/`／`dir-graph.yaml`；本 TASK 不新增可观测性设施、不新增 metrics、不引入依赖（I5／NFR-5）。

## 3. 实现要点

1. **AC-2／AC-3 的场景与观测窗口**（SDD §4.4，逐条照做，不扩面）：
   - AC-2：以 `quality-reviewer-agent` 重放第一次事故场景（读取 Issue 上下文后**首次加载当前 `review-*` Skill**，即 `review-requirement`）；
   - AC-3：同形重放 `review-dev-plan` 复评场景（先尝试 HOME 级 Skill 目录 → 再根目录检索的形态）；
   - 观察面 = run 的会话记录（`toolCall` 名称 + `arguments.command` 文本）⇒ 记录 `toolCalls` 的**原始数组**（`{name, command}`），不得只记摘要计数；`toolCalls` 为空即取证不成立（硬失败，禁止「空提取 → 静默通过」）。
   - **采集口径（run 期自采集；实施期裁定 A＋轻路径，2026-09-18，issue AIFI-33 评论 `01a0b34d`）**：run 的会话记录**事后不可读**——run 结束时平台调用 `agent.InvalidatePiSession`（`server/pkg/agent/pi.go`）删除该 run 的会话文件（实测：**本次事故 run** 的会话文件 `20260918T070647.742524200.jsonl` 事后只剩同名 0 B 的 `.lock`、内容不可读；该事实按本次事故 run 实测，不等于 `pi-sessions/**` 的全局规律，`InvalidatePiSession` 在 `sessionID` 不是 `pi-sessions` 直接子项时直接返回、不删文件），平台侧 `multica agent tasks` 的 `tool_calls` 只给 `seq`／`status`／`tool`（read／write 另给 `target`）、**无 `command` 文本**。故由**被观测节点自己**在其 run 结束前读取环境变量 `PI_SESSION_FILE` 指向的会话文件，取出全部 `{type:'toolCall'}` 项，把 `{name, command}` **原始数组原样**随回报评论发出。`command` 取该调用 `arguments.command` 原文；无 `arguments.command` 的调用（如 `read`／`write`）**不得省略或折叠**，记 `JSON.stringify(arguments)`——与被观测节点同源、机械可复算，且保持数组长度／顺序能与平台 `tool_calls` 逐条对账、猜测路径访问在文本面可见。
   - **对账规则（平台数据可见后执行；执行与登记主体＝采集 run 之后的实施 run）**：节点发出的数组必须与 `multica agent tasks <agentId> --output json` 中该 run 的 `tool_calls.calls[].tool` 序列**同序前缀相等**；平台尾部差集 ≤ 3 条，且必须逐条落在下列允许集合：① 写回报正文文件（`write`，其 `target` 平台可见）；② 发布回报评论（`multica issue comment add`）；③ 清理该临时正文文件。**2026-09-18 尾口径更正**：发布回报评论在工具调用面上本身就是**三段**（写正文 + 发布 + 清理，平台评论纪律的强制形态），旧文本写的「尾部差集 ≤ 2 条」与平台发布机制不符、且当时把这三段当成两段。平台实测（AC-2 首次重跑，run `01a0b354-e674-774a-b4a9-202d404fe71e`，`tool_calls.total=17`）＝前 14 条与节点自采集数组同序前缀相等，尾部 3 条即 `130:write`／`140:bash`／`145:bash`。若取数调用未被数组自身覆盖（即数组末条不是取数调用），该调用亦计入尾部，此时上限为 4 条——出现任何其他调用即对账不成立，硬失败（**禁止**以平台名单臆造或补写 `command` 文本，那会把节点自证面扩大成臆造面）。文本面（`command`）仍是节点自证项，平台面独立核验的是 `seq`／`tool` 与 run 存在性。**执行主体与窗口（2026-09-18 更正）**：平台 `tool_calls` 只在 run 结束时随 `result` 落盘才可见（实测：`multica agent tasks` 中仅 `status=completed` 的 run 带 `result.tool_calls`，`running`／`failed`／`cancelled` 一律无该字段），而采集 run 的取数调用已被钉成其结束前的最后一次调用（节点边界①，其后只发布三段）⇒ **采集 run 内不存在执行本对账的窗口，本对账不在采集 run 内执行**。对账由采集 run 之后的**实施 run** 在平台数据可见时执行，并按本 TASK §3 第 4 项把逐条结果（前缀相等 ＋ 尾部差集枚举）登记进实施说明与 `test-report.md` 的语境。**采集 run 的义务 = 让尾部可判**（节点边界①本身）；它只负责把 `{name, command}` 原始数组随回报评论发出，不承担对账。
   - **节点边界（下发时必须逐条写入节点指令）**：① 取数调用是该节点结束前的**最后一次**工具调用，其后只允许发布回报评论的**强制三段**（写正文 + `comment add` + 清理，见上；否则尾部差集不可判）；② 回报必须 mention `dev-agent`（否则下一跳采集 run 不被唤醒）；③ 只读边界不变（不产出 verdict、不写 `review-annotations/**`、不调用 `crctl`、不改仓库文件）；④ **溯源中立（节点指令不得诱导检索）**：只要求节点**如实回报它实际取得内容的调用与位置**（照平时取数方式），模板内不得出现任何检索动作，也不得要求它为「避免搜索」改变取数方式；**不得**要求它追溯或核对内容的「来源」「源本」，也不得要求「相对路径 ＋ 绝对路径 ＋ 文件字节数」这类需额外探查才能凑齐的溯源信息——内容**以 `read` 取得时**，取自何处由平台 `tool_calls` 的 `read(target)` 独立锚定（平台只对 `read`／`write` 给出 `target`；以 `bash` 等取得时该锚定不成立、回落到文本面自证），故本项的强制句只要求「如实回报它实际取得内容的调用与位置」，无需节点自证来源。AC-2 首次重跑的 `search=1` 命中（该节点在 tools 包内检索 Skill 源本，见 issue AIFI-33 评论 `01a0b361`）与旧节点指令里这类溯源取证要求一致（单次观测上的对应关系，不作因果断言；该指令文本不在本卡内，属作者下发面，本项把它固化为卡内合同）。判据不放宽：`cmd-05` 仍按同一字面 args 对 `toolCalls` 独立重算并要求搜索类调用数 = 0。
2. **AC-4 的构造与取证**（SDD §4.4）：保留 ≥1 个其他 Skill（保证 `## Skills` 段与规则文本在场——**不得**使用零 Skill／全 `disable-model-invocation` 情形，否则构造无效，B-1），移除被评估节点的预期 Skill；run 前后对受控文件逐一取 sha256（记录键为仓库内相对路径）：`change-requests/CR-2026-070/cr.md`、`change-requests/_backlog.yml`、`change-requests/CR-2026-070/review-loop.yml`、`change-requests/CR-2026-070/traceability.yml`，以及**当时实际存在的全部** `change-requests/CR-2026-070/review-annotations/*.yml`——该目录是业务 verdict 的落盘位置，**强制必录（至少 1 条，建议全量）**，不得以「≥4 条」的旧口径把它漏出观测面（评审 B-3）。另：run 窗口内若出现 run 前不存在的 `review-annotations/<stage>.yml`（新文件不在 before 集内，sha256 对等检查天然覆盖不到），必须逐条记入 `reviewAnnotationsNewFiles`——该数组必须为空，非空即判 AC-4 不成立。判据：run 报告缺失能力事实（Skill 名／Runtime／任务）、**无业务 verdict 落盘**（`businessVerdictWritten=false` ＋ `reviewAnnotationsNewFiles` 为空 ＋ 上述受控文件前后 sha256 全等，观测面与声称面一致）、零兜底搜索。
3. **哈希与解析纪律（工程纪律 1）**：所有读入先 `\r\n → \n` 归一后计算 sha256；SHA 取 40 位小写十六进制；JSON 写盘用 UTF-8，键名逐字照 §6。
4. **平台锚定**：记录每个 run 的 `agentId`（`multica agent list --output json` 现查）与 `runId`（`multica agent tasks <agentId> --output json` 的对应项），`cmd-05` 会用同一命令**活体复核**这些 run 存在；不得手写未在平台出现的 id。逐条对账结果（前缀相等 + 尾部差集枚举）记入本 TASK 的实施说明与 `test-report.md` 的语境——`fr1-smoke.json` 的 schema 不变（`cr-2026-070-fr1-smoke/v1`），不新增字段。
5. **Pi 侧证据的取值**（SDD §4.6，路线无关）：`baseCommit` 必须逐字为 `d981de1229ef899957bbe968bc8dcda02a21f477`；`branch` 记录检出的**实际形态**——本 CR 的落点是既有 detached HEAD（tag `v0.85.1` = `d981de12…`，`git branch --show-current` 输出为空；受控 git 入口不提供建分支形态，见 TASK-02 §3.6），故逐字记为 `detached@v0.85.1`（`cmd-06` 只校验该字段存在，取值语义以本句为准）；`headCommit` = 检出 HEAD（TASK-02 在该 detached HEAD 上提交后的 commit）；`changedFiles` 由 `crctl git diff --name-only <baseCommit> --cwd <checkoutPath>` 实测（非手抄）；`installedPackage.path` = `npm root -g` 下的安装目录，`bashJsSha256` = 该目录 `dist/core/tools/bash.js` 归一后的 sha256；`testLogPath` = `change-requests/CR-2026-070/evidence/pi-vitest.log`（KB 相对路径），`testLogSha256` = 该文件归一后的 sha256。
6. **自检**：落盘后在 KB worktree 根按 plan §6.2 的表内字面命令执行 `cmd-05`、在 tools worktree 根执行 `cmd-06`，双双 exit 0 后方可登记完成。

## 4. 验收条件

| # | 验收步骤（可执行） | 期望 |
|---|---|---|
| 1 | 在 KB worktree 根执行 `cmd-05` 表内字面命令（plan §6.2） | exit 0：三条 run 记录齐备、字段完整、`toolCalls` 非空、独立重算的搜索类调用数与猜测路径访问数均为 0、AC-4 受控文件前后 sha256 逐一致（**含 `change-requests/CR-2026-070/review-annotations/*.yml` 至少 1 条**）、`businessVerdictWritten=false`、`reviewAnnotationsNewFiles` 为空数组、每个 `runId` 经 `multica agent tasks` 活体可见 |
| 2 | 在 tools worktree 根执行 `cmd-06` 表内字面命令（plan §6.2） | exit 0：检出 HEAD 与记录一致、变更文件集与 git 实测全等且全部落在 `packages/coding-agent/{src,test}/**`、无 `dist`／`node_modules`、vitest 活体复跑 exit 0 且 5 条断言名齐备、日志 sha256 一致、安装包 `bash.js` sha256 无漂移且仍含 `no default timeout` |
| 3 | 负向自检：把 `fr1-smoke.json` 的任一 `toolCalls` 替换为一条含 `SKILL.md` 与 `find` 的调用后重跑 `cmd-05` | **必须 exit 1**（证明重算不是装饰：命中即红），随后恢复文件并复跑确认 exit 0 |
| 4 | 负向自检：把 `pi-source.json#changedFiles` 删去一个路径后重跑 `cmd-06` | **必须 exit 1**（文件集不一致即红），随后恢复并复跑确认 exit 0 |

## 5. 完成标志

1. 两份证据文件落盘并在 KB worktree 内提交（`[cr] ` 前缀，可与其它 TASK 分批）；
2. 验收条件 1～4 全部满足（3／4 的负向自检结果记入本 TASK 的实施说明或 `test-report` 的语境，不新增文件）；
3. 本 TASK 已在 `tasks/_index.yml` 登记 `done`（`crctl task done CR-2026-070 --task CR-2026-070-TASK-04`，工程纪律 8：做完一个标一个，不积压到回写期）；
4. **完成边界**：到「证据文件落盘 + cmd-05／cmd-06 作者 run 内 exit 0」为止；**不**包含 `review-code`／`merge`／`writeback`／`archive` 的完成（CR-2026-057 FR-10：`crctl task done` 仅允许 `status=developing`；merge/审批的审计事实以 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准）。

## 6. 接口契约

**产出 1 —— `change-requests/CR-2026-070/evidence/fr1-smoke.json`**（schema 逐字 `cr-2026-070-fr1-smoke/v1`；被 `cmd-05` 消费）：

```json
{
  "schema": "cr-2026-070-fr1-smoke/v1",
  "generatedAt": "<RFC3339>",
  "runtimeBuild": { "repo": "multica", "commit": "<40hex>", "binaryVersion": "<multica --version 原文首行>" },
  "runs": [
    {
      "ac": "AC-2",
      "scenario": "review-requirement replay",
      "agentId": "<uuid>",
      "runId": "<string，平台 run id>",
      "observedAt": "<RFC3339>",
      "provider": "<runtime provider 名>",
      "toolCalls": [ { "name": "<tool>", "command": "<arguments.command 原文>" } ],
      "businessVerdictWritten": false
    },
    { "ac": "AC-3", "scenario": "review-dev-plan replay", "agentId": "<uuid>", "runId": "<string>", "observedAt": "<RFC3339>", "provider": "<string>", "toolCalls": [ { "name": "<tool>", "command": "<string>" } ], "businessVerdictWritten": false },
    {
      "ac": "AC-4",
      "scenario": "expected skill missing -> technical abort",
      "agentId": "<uuid>",
      "runId": "<string>",
      "observedAt": "<RFC3339>",
      "provider": "<string>",
      "toolCalls": [ { "name": "<tool>", "command": "<string>" } ],
      "missingCapabilityReported": true,
      "businessVerdictWritten": false,
      "reviewAnnotationsNewFiles": [],
      "controlledFiles": {
        "change-requests/CR-2026-070/cr.md": { "beforeSha256": "<64hex>", "afterSha256": "<64hex，必须与 before 全等>" },
        "change-requests/_backlog.yml": { "beforeSha256": "<…>", "afterSha256": "<…>" },
        "change-requests/CR-2026-070/review-loop.yml": { "beforeSha256": "<…>", "afterSha256": "<…>" },
        "change-requests/CR-2026-070/traceability.yml": { "beforeSha256": "<…>", "afterSha256": "<…>" },
        "change-requests/CR-2026-070/review-annotations/requirement.yml": { "beforeSha256": "<…>", "afterSha256": "<…>" }
      }
    }
  ]
}
```

（sha256 为 64 位小写十六进制；上表以 `<64hex>` 标记该位置的实际取值。）**字段语义补充**：`controlledFiles` 的键名逐字为仓库内相对路径，其中 `change-requests/CR-2026-070/review-annotations/` 下的键必须覆盖 run 前**实际存在的全部**该目录文件（至少 1 条，建议全量；示例仅列 1 条，此处只是示例不是上限）；`reviewAnnotationsNewFiles` 必须在场且为空数组（run 期新落盘的 `review-annotations/<stage>.yml` 即判 AC-4 不成立）。

**产出 2 —— `change-requests/CR-2026-070/evidence/pi-source.json`**（schema 逐字 `cr-2026-070-pi-source/v1`；被 `cmd-06` 消费）：

```json
{
  "schema": "cr-2026-070-pi-source/v1",
  "upstreamUrl": "https://github.com/earendil-works/pi-mono",
  "baseCommit": "d981de1229ef899957bbe968bc8dcda02a21f477",
  "checkoutPath": "<绝对路径，检出根>",
  "branch": "<检出实际形态；本 CR 逐字为 detached@v0.85.1（detached HEAD @ tag v0.85.1，无分支）>",
  "headCommit": "<40hex，检出 HEAD>",
  "changedFiles": [ "packages/coding-agent/src/core/tools/bash.ts", "packages/coding-agent/test/bash-default-timeout.test.ts" ],
  "testFile": "test/bash-default-timeout.test.ts",
  "testLogPath": "change-requests/CR-2026-070/evidence/pi-vitest.log",
  "testLogSha256": "<64hex，LF 归一后>",
  "buildCommand": "npm run build:offline",
  "artifactVersion": "<构建产物版本号（packages/coding-agent/package.json version）>",
  "route": "R-C",
  "producerAndTiming": "产出方=本团队本地构建产物；升级动作时点=CR 合并之后（运行环境维护，不进交付 diff）",
  "installedPackage": { "path": "<npm root -g 下安装目录>", "version": "0.85.1", "bashJsSha256": "<64hex，LF 归一后>" }
}
```

**消费**：`cmd-05`（产出 1：结构 + 独立重算 + 平台锚定 + AC-4 前后一致）与 `cmd-06`（产出 2：变更文件集活体比对 + 用例活体复跑 + 日志 sha256 + 安装包负向）。二者对字段缺失／读空／不可判一律硬失败，无静默降级路径。
