---
id: CR-2026-065-plan
type: PLAN
cr-ref: CR-2026-065
sdd-ref: "change-requests/CR-2026-065/sdd.md"
target-version: 0.38
status: draft
created: 2026-09-13T04:34:00+08:00
updated: 2026-09-13T04:34:00+08:00
---

# CR-2026-065 开发计划（CR-S：测试基线与门禁可信化 — 断言去硬编码、4 条基线漂移转绿、CI 全量步骤成为真门禁）

**权威输入（人工审批绑定，本计划不修改其一个字节）**

| 输入 | 绑定 | 摘要证据 |
|---|---|---|
| `change-requests/CR-2026-065/sdd.md` | `review-annotations/sdd.yml#subject-sha256`（cycle 1 / attempt 2，`verdict=pass`、`blockers=[]`）+ `approval.yml#tech-design`（`via: crctl-approve`、`2026-09-13T04:11:04+08:00`、approver `OldBoy405`） | sha256(LF) `1e6af84f6645879c09180ec5e11048d94b1f1ff48fe2caa82b44a5b337fe12b4` / 68,768 B / 731 LF / `\r` 计数 0（本计划落笔前按 worktree 实际文件重算，与 annotation 全等） |
| `change-requests/CR-2026-065/prd.md` | 需求人工审批 evidence-digest（SDD §输入引用） | sha256(LF) `467b5d47…`（SDD 头部登记值；本计划只按 SDD 引用定位抽查，不全量复审 PRD） |
| `cr.md#target-version` | 注册期继承 | `0.38`（禁止 tbd / 自行改写，CR-2026-057 FR-13） |

- **两个硬边界**：① 不改 `sdd.md`（任何正文修订都会使 `subject-sha256` 失配、让已通过的评审与已落盘的人工审批失效，正确出口是状态机既有回退）；② 不改 `prd.md`。
- **目标代码仓 = `tools` 仓自身**（`skills/`、`skills/shared/crctl/scripts/**`、`.github/workflows/crctl-ci.yml`）；`ai-first-platform-docs`（KB）只承载本 CR 的过程文档（plan / tasks / test-report / test-evidence）；`multica` 仓**零改动**。
- **本计划交付面**：`FR-1…FR-17` 全部在 scope；`zero_diff` 面（`dir-graph.yaml`、`pipeline-templates/*`、所有 `SKILL.md`、`lib/yaml-subset.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`skills/shared/controlled-shell/rules.json`）零 diff；§9 `follow_up` 三处硬编码断言（`crctl.test.mjs:4961`、`pipeline-structure.test.mjs:41`、`:183`）不进本轮 diff。

---

## 0. 基线与工作区事实（本节点实测，落笔即读，未轮询）

- `crctl status CR-2026-065`（`--workspace` = CR worktree）= **`tech-design-reviewed`**；`crctl next` = **`write-dev-plan`**（`humanApproval=false`，why：技术设计已审批，编写开发计划）。`legalNext` 含 `write-dev-tasks` 与 reject/withdraw 轨。
- `crctl workspace inspect CR-2026-065`：三仓 `classification=healthy`、`dirty=false`、`localBranch/remoteBranch=true`；`operationalWorkspace` 非空。
- 架构阶段终点 checkpoint 已在本节点首位执行：`crctl checkpoint CR-2026-065 --message 架构设计已审批` → `phase=complete`、`changed=true`、`batchId=ea4a2e983ad72769`、`metadataCommit=0ef787ef7dcdef755427cc9e123a3c5da469b158`，三仓 `confirmed=true`（`sourceSha`：KB `de8b5110…` / multica `ab960948…` / tools `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`）。
- 路径 authority（`crctl workspace inspect` 的 `resources[]` 原样值，**不拼接、不回退主工作区**）：

| repo | worktreePath | 分支 | HEAD |
|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-065` | `requirement/CR-2026-065` | `de8b5110…`（KB HEAD 随 CR 产物提交前移，不作代码依赖证据） |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-065` | `requirement/CR-2026-065` | `ab960948…`（本 CR 零改动） |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-065` | `requirement/CR-2026-065` | `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`（clean，本 CR 的实施与证据基线） |

**本节点第一手实测（2026-09-13，Windows / Node v24.15.0 / Windows 10 x64 / 16 逻辑核）**

| 项 | 实测事实 | 方式 |
|---|---|---|
| 测试文件集 | `skills/shared/crctl/scripts/test/*.test.mjs` = **21 个**；同目录非测试 `.mjs` 只有 `merge-fixture.mjs` | 目录计数 |
| 新增面尚不存在 | `lib/outbox-contract.mjs`、`test/gate-registry.json`、`test/suite-gate.mjs`、`test/assertion-sources.mjs` 四项**均不存在**（本 CR 新建） | `fs.existsSync` |
| CI 全量步骤 | `.github/workflows/crctl-ci.yml:111` = `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`（无例外、无 skip 白名单）；`:115` = writeback 单文件 | 逐行读 |
| pipeline | `code-implementation.pipeline.json` 节点 **16**（`nodes[0].ref=write-dev-plan`，`timeoutMinutes=15`；`write-test-report` 节点 `timeoutMinutes=20`）；`architecture-design.pipeline.json` 节点 5，node-5 `ref=push-progress`（本节点已消费） | `JSON.parse` + `_index.yml` 登记行 `nodes: 16` |
| BR-1 事实 | `write-dev-tasks/SKILL.md` 含 `crctl task init` 与「禁止 Agent/Skill 手写」；`code-implementation.pipeline.json` 对 `crctl task init` / `_index.yml` **零命中** | 文本计数 |
| BR-2 事实 | `review-alignment/SKILL.md`：`latest-checkpoint` **0**、`checkpoints[]` **0**、`_backlog.yml` **1**、`cr.md` **1**；`mtime` / `merge-commit` / `fingerprint` **各 2 处命中**（均为含「不读」的否定句，`mtime` 命中率为 2 的判据面见 §6.5） | 文本计数 |
| BR-4 事实 | `write-requirement-prd/SKILL.md`：`七个章节` ✓、`未替换占位符` ✓、含「重新读取」的校验句 **1 处**；5 个禁用词 **全 0**；`crctl validate` / `Commit：` / `crctl git commit` **全 0**；文件本机为 **CRLF 检出**（`\r` 计数 119） | 文本计数 + 字节计数 |
| BR-3 事实 | 用 `lib/yaml-subset.parseYaml(text,{strict:true})` 解析 `dir-graph.yaml`：声明转移 **31**、具名状态 **15**（+ 注册前 `(new)`）、wildcard `any-active` 的 `from` 声明 **2** 条、目标 **12** 个、展开 **31−2+12×2 = 53** | 自写脚本（strict 解析），与 SDD §4.1/§6.3 登记值一致 |
| 断言锚点 | BR-1 `crctl.test.mjs:1337`、BR-3 `:4777`、BR-4 `:4989`、BR-2 `checkpoint-tx.test.mjs:480`、BR-5 `archive-tx.test.mjs:373`（行号为定位线索，实施定位以实时搜索结果为准） | 搜索命中行 |
| 失败向量形态 | cmd-03 收窄形态（`--test-name-pattern` 只跑 `TASK-01 RED-7` + `CR-2026-065`）实测 **exit 1 / 22.6 s**，失败断言 `actual: [{ code: 'EMIT_FAILED', event_kind: 'archive' }]` vs `expected: []` —— BR-5 的红与 SDD §4.5/§6.3 登记一致 | 同 `crctl test` 的 spawn 语义 |

**基线红登记（本 CR 的起点事实，不是方案前提）**

- 固定 `tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 上不带例外跑全量 21 个 `*.test.mjs`：**exit 1 / 894.8 s / 失败恰 5 条**（**既有实测**：AIFI-25 作者与 reviewer 各独立跑过一次；本节点 15 min 预算不足以重跑全量，未复跑）。
- **AC-01 的「exit 0 / 失败集合为空」是本 CR 的交付目标，不是变更前事实。** 5 条红在本计划与 TASK 里一律按「**待修的红**」登记：

| # | 用例（逐字） | 载体文件、断言锚点 | 引入变更 | 本 CR 处置 TASK |
|---|---|---|---|---|
| BR-1 | `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引` | `crctl.test.mjs:1337` | `14b4458`（CR-2026-050 只改 pipeline、未同步测试） | TASK-01 |
| BR-2 | `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]` | `checkpoint-tx.test.mjs:480` | `fc2b142`（CR-2026-060 TASK-04 改 reader 事实源） | TASK-01 |
| BR-3 | `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）` | `crctl.test.mjs:4777` | `bef1f4d` + `2e4442d`（CR-2026-061）、`49c46dd`（AIFI-17） | TASK-01 |
| BR-4 | `CR-2026-042 静态合同：已知 Skill 越界文本零命中` | `crctl.test.mjs:4989` | `fc797ed`（AIFI-22 把「和」改成「、」） | TASK-01 |
| BR-5 | `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖` | `archive-tx.test.mjs:373` | 冻结向量构造失真（非产品缺陷） | TASK-02 |

- 全量耗时口径未标注并发参数（既有实测 894.8 s 与「`--test-concurrency=2` 下本机 30+ min 不收敛」两种观测并存）；本节点实测到的**量级线索**（供 TASK-04 定协议）：`trace-outbox.test.mjs` 单文件整跑 **134.5 s**、`archive-tx.test.mjs` 单文件整跑 **>150 s（超时截断）**、两文件整跑 **>600 s（超时截断）**，而收窄形态同命令 22.6 s —— 说明**慢来自整文件粒度的调度与 fixture 成本，不来自断言本身**，TDEC-4 的并发结论必须按同一文件的整跑口径给出。
- 本机 `--test-concurrency` 默认值随核数变化（本机 16 逻辑核），CI 为 `ubuntu-latest` + `windows-latest`（Node 20）；跨平台差异未验证（SDD §6.4 已登记，不伪造 CI 事实）。

---

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 设计与审批 | PRD + SDD（`subject-sha256=1e6af84f…`）+ 人工架构审批 + 架构阶段终点 checkpoint（§0） | 已完成 | 0 |
| M2 计划与任务拆分 | 本 `plan.md` + `tasks/TASK-01…04.md` + `tasks/_index.yml`（`crctl task init --count-hint 4`）→ `task-breakdown` | 流程节点（非交付 TASK） | 0.5 人天 |
| M3 断言层去硬编码 + 四条漂移转绿 | `assertion-sources.mjs` + `gate-registry.json`（受控清单，含 `stateMachine.*`）+ BR-1…BR-4 四条断言按其事实源重写 | CR-2026-065-TASK-01 | 16h |
| M4 去重契约提级 + BR-5 构造改对 | `lib/outbox-contract.mjs` + `crctl.mjs#emitOutboxEvent` 最小改点 + RED-7 构造 A（真实崩溃窗口）+ 新用例 B（同名不同内容）+ 契约断言 | CR-2026-065-TASK-02 | 16h |
| M5 CI 真门禁 + 例外治理 | `suite-gate.mjs`（TAP 解析 / 清单核对 / 例外面四查 / 退出码）+ `contract-scan.test.mjs` 静态断言与解析自测 + `crctl-ci.yml:109-111` 改造 | CR-2026-065-TASK-03 | 20h |
| M6 收敛决定 + 漂移负控证据 + 范围收口 | `--test-concurrency` 有界实测（≥2 次/候选）→ 定常量；三类注入 → 全量红 → 还原绿（6 次全量）；`manifest.cases` 终值刷新；diff 白名单审计 | CR-2026-065-TASK-04 | 16h |
| M7 评审与人工门禁 | `review-dev-plan` → `approve --stage dev-start` → `implement-code` → `write-test-report`（§6.2 五条命令）→ `review-code` → `approve --stage code` | 流程节点 | 流程 |
| M8 发布 | `merge-feature-branch` → writeback → archive（既有 CR 流程，**不建交付 TASK**） | 流程控制节点 | 流程 |

**估算总工时（TASK 账本口径）：68h**（16 + 16 + 20 + 16），与 `tasks/_index.yml#totalEstimateHours` 一致（`crctl task init` 返回值交叉校验）。M2 的 0.5 人天与 M7/M8 是流程节点，不进 TASK 账本。**不建流程控制 TASK**（完成边界必须是 `developing` 内可被 `crctl task done` 登记的事件，禁 `merge` / `writeback` / `archive` / `code-reviewing` / `code-approved` 前置）。

---

## 2. 任务依赖图

```text
TASK-01 断言层（assertion-sources.mjs + gate-registry.json + BR-1…BR-4）
   │  (gate-registry.json#stateMachine.* 被 BR-3 断言消费)
   ├──────────────────────────────┐
TASK-02 outbox 契约与 BR-5         │
   │  (lib/outbox-contract.mjs 被  │
   │   suite-gate 的静态断言消费)  │
   ├──────────────▶ TASK-03 CI 真门禁（suite-gate.mjs + contract-scan + crctl-ci.yml）
   │                     │  (需要三条断言面都落地，才能在注入时看到「本 CR 内变红」)
   └─────────────────────┴──────▶ TASK-04 收敛决定 + 三类负控 + manifest.cases 终值 + 范围审计
```

| 边 | 依赖内容（精确面） | 理由 |
|---|---|---|
| TASK-03 → TASK-01 | `gate-registry.json`（`schema` / `manifest.files` / `manifest.cases` / `stateMachine.*` / `exceptions: []`） | `suite-gate` 读该文件做清单与例外核对；缺文件即 `SUITE_REGISTRY_MISSING` 红 |
| TASK-03 → TASK-02 | `lib/outbox-contract.mjs` 的三个导出常量 + 两个函数 | `contract-scan` 静态断言「产品面无第二份字段枚举」需要一个已存在的单一事实源 |
| TASK-04 → TASK-01/02/03 | 三条断言面 + 门禁包装器 | 负控注入必须能在**本 CR 内**让全量命令变红；收敛测量必须跑最终命令来源 |
| 无环 | 依赖为 DAG（01/02 → 03 → 04） | TASK-01/02 互不依赖，可并行 |

**跨 TASK 共享契约（完整锁定，消费方不得缩略）**

- `assertion-sources.mjs` 导出：`deriveStateMachine(toolsRoot) -> { namedStates: string[], wildcards: Record<string,string[]>, transitions: {from:string,to:string,trigger:string}[], identifiers: string[], expandedCount: number, declaredCount: number }`（推导失败 throw，禁返回空集合）；`readTextNormalized(absPath) -> string`（`\r\n → \n`）；`readTestFileSet(toolsRoot) -> string[]`（升序文件名）。
- `lib/outbox-contract.mjs` 导出（逐字对齐 SDD §3.1）：`OUTBOX_COMPARED_FIELDS`、`OUTBOX_EXCLUDED_FIELDS`、`OUTBOX_VOLATILE_PAYLOAD_KEYS`（三者 `Object.freeze` 数组）、`buildOutboxEvent(input, nowIsoString) -> object`、`buildOutboxComparable(event) -> object`。
- `gate-registry.json`：`schema: "crctl-suite-gate/v1"`，四段（`manifest` / `stateMachine` / `exceptions`，见 SDD §2.3），唯一写入口 = 人类编辑 + `git commit`。
- `suite-gate.mjs` CLI（SDD §3.2）：`--run [--report-out <tap>] [--json-out <json>] [--max-runtime-ms <n>] [--cwd <root>]` 与 `--report <tap> --rc <exit-code> [--json-out <json>]`；固定 check code 11 个（SDD §3.2 表）。

---

## 3. 资源与分工

| 项 | 分配 |
|---|---|
| 实施仓 | `tools`（唯一交付仓）；KB 承载 `change-requests/CR-2026-065/{plan,tasks,test-report,test-evidence}`；`multica` 零改动 |
| 实施者 | `cr.md owners.development.id` = `Ray`（`implement-code` 节点消费 `resources[].worktreePath`，不拼接路径） |
| 测试执行者 | `cr.md owners.test.id` = `Ray`（`write-test-report`） |
| 评审 | `quality-reviewer-agent` 新建独立 run：`review-dev-plan`（本计划与 TASK）、`review-code`（实现 + 测试报告），均不得在作者会话内自评 |
| 人工门禁 | `approve --stage dev-start` / `approve --stage code`（TTY，人类；本 Agent 不代签） |
| 环境前提 | Windows 本机 Node v24.15.0；CI 为 ubuntu+windows / Node 20（跨平台证据以「本机复现 + 可得时的 CI」交付，SDD-CLOSE-02） |

---

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合回滚，唯一事实）

| 单元 | 覆盖 TASK | 回滚动作 | 回滚后状态 |
|---|---|---|---|
| RU1 | TASK-01 | `crctl git` 反向 revert `assertion-sources.mjs` + `gate-registry.json` + 四条断言文件改动 | 断言回到「硬编码快照」形态（基线 4 条红回来）；其余交付不受影响 |
| RU2 | TASK-02 | revert `lib/outbox-contract.mjs` + `crctl.mjs` 改点 + `archive-tx.test.mjs` / `trace-outbox.test.mjs` | 去重语义回到「注释口径」（产品语义本就等价，无行为回退）；BR-5 回到构造失真态 |
| RU3 | TASK-03 | revert `suite-gate.mjs` + `contract-scan.test.mjs` + `crctl-ci.yml` 改动 | CI 回到裸 `node --test --test-concurrency=2 …`；登记面无消费者（保留文件不构成门禁） |
| RU4 | TASK-04 | revert `manifest.cases` 终值与 `test-evidence/**`、`NC-summary.md`；不触碰产品面 | 回到「未做负控/未定并发」态，AC-10/AC-11/AC-13 重新不可达 |

组合回滚顺序 = **RU4 → RU3 → RU2 → RU1**（逆拓扑；RU1 会删掉 RU3 消费者依赖的登记文件，必须最后回滚）。单单元回滚不得跳过逆拓扑顺序。

### 4.1 风险表

| # | 风险 | 级别 | 应对 |
|---|---|---|---|
| R-01 | 证据集超出 `write-test-report` 节点 20 min 预算 | 高 | 本节点实测分量：cmd-02 = 11.0 s～135 ms、cmd-03 = 22.6 s、cmd-04/05 ≈ 2 s；**全部不确定性在 cmd-01（全量整跑）**。按 §5.4 预算（≈ 900 s + 145 s）留 ≈ 155 s 余量；若 TASK-04 测得全量整跑 > 1000 s，则**优先调 `--test-concurrency` 常量选更快且收敛的配置**，而不是删命令或放宽 AC |
| R-02 | 全量整跑超 `--max-runtime-ms`（cmd-01 传 1200000 ms）被判非收敛 | 中 | cmd-01 的 `--max-runtime-ms` 刻意取 1200 s < cmd 超时 1500 s，使「停滞」以门禁自己的 `converged=false` + `SUITE_NONCONVERGENCE` 落证据（而非 crctl 超时）；TASK-04 的并发决定必须同时满足「整跑 ≤ 1200 s」，不满足则按 R-01 处理 |
| R-03 | 并发根因未知（`=2` 本机 30+ min 不收敛，与同配置 894.8 s 的既有实测矛盾） | 中高 | TDEC-4 有界协议：两候选各 ≥2 次连续整跑，证据写入 `test-evidence/concurrency/`；若不收敛可在 `--max-runtime-ms` 下复现为可观测事件；**禁止**把「已知不收敛观测」的配置不经实测就写进门禁常量 |
| R-04 | TAP 解析是唯一外部耦合点（reporter 默认值随 Node 版本 / 是否 TTY 变化） | 中 | 命令单一来源显式钉 `--test-reporter=tap`；解析失败硬失败（`SUITE_REPORT_UNPARSEABLE`）；`contract-scan.test.mjs` 用内联 TAP 片段做合法 + 三类畸形自测（不新增测试文件） |
| R-05 | 例外登记面成为「自证绿」通道 | 中 | 交付态 `exceptions: []`（显式空数组）；`contract-scan` 静态断言仓库内无对 `gate-registry.json` 的写入调用；登记不替代执行（失败始终上报）；到期即红 |
| R-06 | 推导退化为等价重述（恒真式），绿无约束力 | 中高 | 登记值与推导值是两条独立来源（推导 → `dir-graph.yaml`；登记 → `gate-registry.json`），集合/计数比较 + 三类负控注入（§6.4）证明「注入即红」 |
| R-07 | BR-5 新用例构造复杂（journal 置 pending + 同名不同内容 + 补发）易脆 | 中 | 沿用 `archive-tx.test.mjs` 文件内局部 helper（`makeWritebackFixture`:14 / `archiveOutboxFiles`:231），不上提共享 fixture；构造 B 的四步断言按 SDD §4.5 逐条落地；断言面用文件内容比较而非时间/顺序 |
| R-08 | 行尾与解析陷阱（Windows autocrlf；跨行正则静默失败） | 中 | 所有读文本断言先 `replaceAll('\r\n','\n')`；解析用 `split(/\r?\n/)`；解析失败硬失败报错（工程纪律 #1；本机实测 BR-4 载体文件为 CRLF 检出） |
| R-09 | 证据命令转录错误（args 转义 / 路径注入） | 中 | `args` 为 JSON token 数组且**直接就是** `cr-test-plan/v1` 的 `args` 原文；`cmd-04`/`cmd-05` 脚本内**不含**双引号、反斜杠、换行与竖线字符（已实测 JSON 往返逐字相同）；跨仓/绝对路径一律正斜杠化；每条命令已按 `spawnSync(executable,args,{shell:false})` 干跑（§6.3） |
| R-10 | `manifest.cases` 基线登记时机错位（新用例后置落地） | 中 | TASK-01 登记初值（**只可能偏低**，`SUITE_MANIFEST_CASE_DROP` 只判「实际 < 基线」，故不会假红）；TASK-04 在全部新用例落地后刷新终值，差异在 diff 中留痕（受控写入 = 人工提交） |
| R-11 | 实施期实验量（10 次全量整跑）吞掉 `implement-code` 240 min 预算 | 高 | 按 §5.4 排序：先做并发测量（4 次）定常量，再做负控（6 次）；整跑单次 ≤ 1200 s 时总计 ≈ 3.3 h，余量给编码；若超时，按 reviewLoop 允许的节点重跑分批完成，**不削减任何一次注入或还原** |

---

## 5. 验收与发布策略

### 5.1 发布前 checklist

1. TASK-01…04 全部 `done`（`tasks/_index.yml` 状态同步，不积压到回写期）。
2. `cmd-01` exit 0 且报告 `failures=[]`、`files_executed=21`、`skipped_file_level=0`、`cases_executed>0`；`converged=true`。
3. `cmd-02`（BR-1…BR-4）与 `cmd-03`（BR-5 + 去重契约）exit 0。
4. `cmd-04`（登记面 schema + §9 `zero_diff` 边界 + diff 白名单）exit 0；`cmd-05`（负控 + 收敛证据形态）exit 0。
5. §6.4 的三类注入证据齐备（每类「注入红 / 还原绿」各 1 份），注入物**不在**交付 diff 中；收敛决定与 `suite-gate.mjs` 常量一致。
6. `exceptions: []` 显式为空；无整文件跳过、无新增红、无降级断言。
7. `test-report.md#status=pass` → checkpoint → `review-code` PASS（`blockers=[]`）→ 人工代码审批。

### 5.2 发布与观测

- 合并后 `contracts` job 的 `crctl full test suite` 步骤连续若干次为绿；观察窗口内任何事实源漂移（状态机条目、pipeline/Skill 语义、去重易变字段）都必须在**引入它的 CR** 内使该步骤变红（PRD §6「CI 步骤连续可信」）。
- 本 CR 不改交付/发布流程算法（`push-progress` / merge / archive / writeback 语义零 diff）。

### 5.3 例外治理与零例外口径

- **交付态 `exceptions: []`（显式空数组，非「文件不存在」）**：文件缺失 = `SUITE_REGISTRY_MISSING` 红。
- 若届时仍有例外：单一登记处 = `gate-registry.json#exceptions`，每条含稳定标识 + 原因 + owner + 到期（带时区偏移的 ISO-8601）；`now >= expires` → `EXCEPTION_EXPIRED` 红；登记面变更只能人工提交（审计 = `git log -- gate-registry.json`）；测试/产品代码零写入（静态断言）。
- 容忍只有两个确定落点（SDD §3.2）：`SUITE_FAILURES_UNREGISTERED` 的容忍在**触发条件内**（本项一旦触发即不可抑制）；`SUITE_NONCONVERGENCE` 的容忍在**已触发项的退出码**上（可抑制为绿，条件 = 未到期 + `kind: suite-nonconvergence` + 稳定标识匹配）。其余 check code 一律不可容忍。
- **非收敛分支口径（本轮评审 E-2 收口）**：`converged=false` 时不做清单核对与失败集合核对（相应 `checks[].not_evaluated=true`），只判 `SUITE_NONCONVERGENCE` 与登记面自身错误；**已匹配的 `kind: suite-nonconvergence` 例外在该分支视为已观测**（不得用空观测集合判 `EXCEPTION_NOT_OBSERVED`）。交付态 `exceptions=[]` 不受本口径影响。

### 5.4 预算（证据命令集 + 实施期实验）

- **`write-test-report` 节点预算 20 min（pipeline 声明 `timeoutMinutes=20`）**：本表五条命令实测/估算 = cmd-01「全量整跑（基线既有实测 894.8 s，收窄后待实测）」+ cmd-02 11.0 s + cmd-03 22.6 s + cmd-04 ≈ 1 s + cmd-05 ≈ 1 s ≈ **930 s ± 全量波动**，余量 ≈ 155 s（以 894.8 s 计）。**若 TASK-04 实测全量整跑 > 1000 s，必须先按 R-01/R-02 调并发常量，不得靠删命令达成预算。**
- **实施期实验（`implement-code`，预算 240 min）**：并发测量 2 候选 × ≥2 次 = 4 次整跑 + 负控 3 类 × 2 次 = 6 次整跑，合计 10 次整跑；单次 ≤ 1200 s 时 ≈ 3.3 h，与编码工作并存（按 R-11 排序执行）。
- 全量整跑参数口径统一由 `suite-gate.mjs` 内**唯一常量**决定（命令单一来源，FR-12.3）；本计划与本行不复制该常量的取值。

---

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 计数类断言从事实源推导（AC-02、AC-03） | §4.1 推导算法（parseYaml strict、硬失败、`identifiers` 集合比较、`expanded` 公式）+ §6.6 D1/D2/D3 | CR-2026-065-TASK-01 | cmd-02（BR-3 用例绿：推导集 ≡ 登记集）、cmd-04（登记值 schema 与数量） | RU1 |
| FR-2 文本类断言只查语义（AC-02、AC-07） | §4.4 两步法（行尾规范化 + 要素/零命中）+「句内要素」判据 | CR-2026-065-TASK-01 | cmd-02（BR-1/BR-2/BR-4 三条用例绿） | RU1 |
| FR-3 反风险：推导不得宽到接受产品错误（AC-03） | §6.6 D/P 两张表 + §4.1 反恒真设计（登记值与推导值两条独立来源） | CR-2026-065-TASK-01 | cmd-04（登记面数量与 schema）、cmd-02（集合比较断言） | RU1 |
| FR-4 BR-1 对齐真实载体（AC-04） | §4.4 表第 1、2 行 + §6.3 第 8/9 项（`write-dev-tasks/SKILL.md:106`、`_index.yml#nodes` 跨文件投影） | CR-2026-065-TASK-01 | cmd-02（`CR-2026-037 Prompt 采纳` 用例绿） | RU1 |
| FR-5 BR-2 对齐 reader 事实源（AC-05） | §4.4 表第 3 行 +「否定辖域」判据 | CR-2026-065-TASK-01 | cmd-02（`checkpoint T05 contract` 用例绿） | RU1 |
| FR-6 BR-3 推导 + 显式登记（AC-06） | §4.1 三条集合/计数等价 + §2.3 `stateMachine` 段 + §6.6 P1/P2/P3 | CR-2026-065-TASK-01 | cmd-02（`TASK-06 ⑤` 用例绿）、cmd-04（`namedStates`=15 / `transitions`=31 / `any-active`=12） | RU1 |
| FR-7 BR-4 语义要素（AC-07） | §4.4 表第 4 行（句内三类对象 + 5 禁用词 + 禁 `crctl validate` / 命令形态 `Commit：`） | CR-2026-065-TASK-01 | cmd-02（`CR-2026-042 静态合同：已知 Skill 越界文本零命中` 用例绿） | RU1 |
| FR-8 保留「内容相等才算已发送」语义（AC-08） | §3.1 行为等价 + §2.2 字段归类（含 `payload.detected_at` 排除） | CR-2026-065-TASK-02 | cmd-03（archive/trace 用例绿，含 drift-audit 不回归） | RU2 |
| FR-9 冻结向量构造改对 + 真实冲突用例（AC-08） | §4.5 构造 A（真实崩溃窗口）+ 构造 B（同名不同内容四步断言） | CR-2026-065-TASK-02 | cmd-03（`TASK-01 RED-7` + 新用例名 `CR-2026-065 BR-5 同名不同内容：可见信号 + journal pending + 补发成功`） | RU2 |
| FR-10 去重比较字段契约可检查（AC-09） | §3.1 六条不变性（字段分类集合相等 / 枚举排除非自动 / 投影闭合 / 只读投影 / 单一事实源 / 行为等价） | CR-2026-065-TASK-02 | cmd-03（`CR-2026-065` 前缀的契约用例绿，含 `payload.observed_at` 反例） | RU2 |
| FR-11 CI 全量步骤成为真门禁（AC-01、AC-12） | §4.2 全流程 + §2.3 `manifest`（文件集合相等 + 用例数 ≥ 基线）+ `crctl-ci.yml:109-111` 改造 | CR-2026-065-TASK-03 | cmd-01（exit 0 / `failures=[]` / `files_executed=21` / `skipped_file_level=0`） | RU3 |
| FR-12 并发收敛决定（AC-10） | TDEC-4 有界协议 + §2.4 报告固定字段（`command`/`duration_ms`/`converged`/`exit_code`）+ 命令单一来源常量 | CR-2026-065-TASK-04 | cmd-01（最终配置的 `command`/`converged`/`duration_ms`）、cmd-05（两候选 ≥2 次整跑记录形态） | RU4 |
| FR-13 漂移当场红负控证据（AC-11） | §4.6 三类注入协议（N-1 状态机 / N-2 文本语义 / N-3 去重字段）+ 证据固定字段 | CR-2026-065-TASK-04 | cmd-05（`NC-{1,2,3}-{inject,restore}.json` + `NC-summary.md` 形态：注入 `verdict=block` 且失败集非空、还原 `verdict=pass` 且失败集空、`converged=true`） | RU4 |
| FR-14 例外单一登记处 + owner + 到期 + 到期即红（AC-12） | §2.3 `exceptions` + §3.2 四查与 11 个 check code + §5.3 口径 | CR-2026-065-TASK-03 | cmd-01（`exceptions=[]` 时退出码 ≡ 失败集合为空）、cmd-04（`exceptions` 为显式空数组） | RU3 |
| FR-15 范围与产品语义最小改写（AC-13） | §1.2 变更面（产品面仅 `lib/outbox-contract.mjs` + `crctl.mjs#emitOutboxEvent`）+ §9 `scope_in`/`scope_out`/`zero_diff` | CR-2026-065-TASK-04 | cmd-04（diff 路径白名单：`test/**`、`lib/outbox-contract.mjs`、`crctl.mjs`、`.github/workflows/crctl-ci.yml`，其余越界即红） | RU4 |
| FR-16 零回归与覆盖不降级（AC-14） | §2.3 `manifest.cases` ≥ 基线 + §4.4/§4.5 回归保护 + §7.3 耗时对比 | CR-2026-065-TASK-04 | cmd-01（21 文件全绿、`skipped_file_level=0`、`duration_ms` 与 894.8 s 同口径对比） | RU4 |
| FR-17 契约面声明与确定性四查（AC-15） | §3.3 不新增用户可调用契约 + §3.2 四查（幂等 / 写入边界 / 错误闭包 / 副作用） | CR-2026-065-TASK-03 | cmd-01（`contract-scan` 静态断言随全量套件执行）、cmd-04（登记面 schema 与零写路径判据） | RU3 |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` 三者全等。
② **FR-13 的执行面在实施期、证据面在 cmd-05**：三类注入各需「注入 → 全量整跑 → 还原 → 全量整跑」，共 6 次整跑，无法装入 `write-test-report` 的 20 min 预算（§5.4）；因此协议在 `implement-code`（`TASK-04`）内执行并落证据文件，`cmd-05` 只核对记录形态（`verdict` / `failures` / `converged`）。**这不是假绿**：注入确实在交付分支内真实发生过并留下逐次日志，注入物不在交付 diff 中（由 `cmd-04` 的 diff 白名单兜底）。
③ FR-1…FR-3 的「断言 → 事实源」映射 = SDD §4.4 两列表 + §6.6 D/P 两张表（已审批，本计划不复述其内容），其**机器可核面**是 cmd-02（集合/计数等价）与 cmd-04（登记值 schema），不靠人工比对。
④ FR-16 的「无新增 skip」由 cmd-01 的 `skipped_file_level=0` + crctl `commands[].skipped=false` 双向承载。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["skills/shared/crctl/scripts/test/suite-gate.mjs","--run","--max-runtime-ms","1200000"]` | 1500 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","--test-name-pattern","CR-2026-037 Prompt 采纳","--test-name-pattern","checkpoint T05 contract","--test-name-pattern","TASK-06 ⑤","--test-name-pattern","CR-2026-042 静态合同：已知 Skill 越界文本零命中","skills/shared/crctl/scripts/test/crctl.test.mjs","skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs"]` | 600 |
| cmd-03 | tools | . | node | `["--test","--test-reporter=dot","--test-name-pattern","TASK-01 RED-7","--test-name-pattern","CR-2026-065","skills/shared/crctl/scripts/test/archive-tx.test.mjs","skills/shared/crctl/scripts/test/trace-outbox.test.mjs"]` | 600 |
| cmd-04 | tools | . | node | `["-e","const fs=require('fs'),cp=require('child_process'),path=require('path');const T='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-065';const BASE='dddd0ad63fb79bd7608314b4553f30e8ce7b7289';const NL=String.fromCharCode(10);const bad=[];const rp=path.join(T,'skills/shared/crctl/scripts/test/gate-registry.json');let reg=null;if(!fs.existsSync(rp)){bad.push('gate-registry.json 缺失');}else{try{reg=JSON.parse(fs.readFileSync(rp,'utf8'));}catch(e){bad.push('gate-registry.json 非法 JSON');}}if(reg!==null){if(reg.schema!=='crctl-suite-gate/v1'){bad.push('registry schema 不符: '+reg.schema);}const files=fs.readdirSync(path.join(T,'skills/shared/crctl/scripts/test')).filter(f=>f.endsWith('.test.mjs')).sort();let mf=[];if(reg.manifest&&reg.manifest.files){mf=reg.manifest.files;}if(JSON.stringify([...mf].sort())!==JSON.stringify(files)){bad.push('manifest.files 与实际 '+files.length+' 个测试文件集合不等: '+mf.length);}let cs={};if(reg.manifest&&reg.manifest.cases){cs=reg.manifest.cases;}if(JSON.stringify(Object.keys(cs).sort())!==JSON.stringify(files)){bad.push('manifest.cases 键集与文件集合不等');}for(const f of Object.keys(cs)){if(!(Number.isInteger(cs[f])&&cs[f]>0)){bad.push('manifest.cases['+f+'] 非正整数');}}let sm={};if(reg.stateMachine){sm=reg.stateMachine;}if(!Array.isArray(sm.namedStates)){bad.push('stateMachine.namedStates 非数组');}else if(sm.namedStates.length!==15){bad.push('stateMachine.namedStates 数量 != 15');}if(!Array.isArray(sm.transitions)){bad.push('stateMachine.transitions 非数组');}else if(sm.transitions.length!==31){bad.push('stateMachine.transitions 数量 != 31');}let wc={};if(sm.wildcards){wc=sm.wildcards;}if(!Array.isArray(wc['any-active'])){bad.push('stateMachine.wildcards.any-active 非数组');}else if(wc['any-active'].length!==12){bad.push('stateMachine.wildcards.any-active 目标数 != 12');}if(!Array.isArray(reg.exceptions)){bad.push('exceptions 非数组');}else if(reg.exceptions.length!==0){bad.push('exceptions 不是显式空数组');}}const r=cp.spawnSync(process.execPath,[T+'/skills/shared/crctl/scripts/crctl.mjs','git','diff','--name-only',BASE,'--cwd',T],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');}else{const out=String(r.stdout==null?'':r.stdout).split(NL);const b=out.findIndex(l=>l.trim()==='{');const changed=out.slice(0,b<0?out.length:b).map(s=>s.trim()).filter(Boolean);console.log('FR-15 diff paths = '+changed.length);changed.forEach(p=>console.log('  '+p));const okPath=p=>{if(p.startsWith('skills/shared/crctl/scripts/test/')){return true;}if(p==='skills/shared/crctl/scripts/lib/outbox-contract.mjs'){return true;}if(p==='skills/shared/crctl/scripts/crctl.mjs'){return true;}if(p==='.github/workflows/crctl-ci.yml'){return true;}return false;};for(const p of changed){if(!okPath(p)){bad.push('越界改动: '+p);}}}if(bad.length>0){console.log('registry-scope-audit failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);}console.log('registry-scope-audit failures = 0');"]` | 120 |
| cmd-05 | tools | . | node | `["-e","const fs=require('fs'),path=require('path');const EV='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-065/change-requests/CR-2026-065/test-evidence';const bad=[];const need=(p,label)=>{if(fs.existsSync(p)){return;}bad.push('缺失 '+label);};const readJson=p=>{try{return JSON.parse(fs.readFileSync(p,'utf8'));}catch(e){return null;}};const pairs=[['NC-1','inject','block'],['NC-1','restore','pass'],['NC-2','inject','block'],['NC-2','restore','pass'],['NC-3','inject','block'],['NC-3','restore','pass']];for(const t of pairs){const p=path.join(EV,'drift',t[0]+'-'+t[1]+'.json');need(p,t[0]+' '+t[1]);const d=readJson(p);if(d===null){bad.push(t[0]+' '+t[1]+' 非法 JSON');}else{if(d.verdict!==t[2]){bad.push(t[0]+' '+t[1]+' verdict != '+t[2]);}if(d.converged!==true){bad.push(t[0]+' '+t[1]+' converged != true');}if(!Array.isArray(d.failures)){bad.push(t[0]+' '+t[1]+' 缺 failures');}else{if(t[1]==='inject'&&d.failures.length===0){bad.push(t[0]+' inject 失败集合为空');}if(t[1]==='restore'&&d.failures.length!==0){bad.push(t[0]+' restore 失败集合非空');}}}}for(const n of ['default-run1','default-run2','conc1-run1','conc1-run2']){need(path.join(EV,'concurrency',n+'.json'),'收敛实测 '+n);}need(path.join(EV,'NC-summary.md'),'NC-summary.md');if(bad.length>0){console.log('evidence-form-audit failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);}console.log('evidence-form-audit failures = 0');"]` | 120 |

**args 列口径（转录纪律，逐条可机械核对）**

① `args` 为 JSON token 数组，**直接就是** `cr-test-plan/v1` 的 `args` 字段原文：`write-test-report` 逐字转录，不得重排、不得取消转义、不得改写引号。
② `cmd-02`/`cmd-03` 用**可重复的 `--test-name-pattern`** 逐条给出用例名片段（Node 支持同一 flag 多次出现，实测 135 ms 命中预期用例），因此单元格内**不含** `|` 交替符、不含 Markdown 表格分隔冲突；`cmd-03` 的 `CR-2026-065` 是一条**约定前缀**：TASK-02 新增的去重契约用例与新 BR-5 用例的 `test(...)` 名必须以 `CR-2026-065` 起始。
③ `cmd-04` / `cmd-05` 的 `-e` 脚本是**单参数**：脚本内**不含**双引号、反斜杠、换行与 `|`（需要换行常量处用 `String.fromCharCode(10)` 构造），因此 `JSON.stringify` 往返逐字相同（已实测：`dq=0 / bs=0 / pipe=0 / newline=0`）。
④ **路径注入一律正斜杠化**（`C:/Users/…`）；`cwd` 为对象仓 worktree 内的相对路径（本 CR 全部为 `.`）；`repo` 列 = **验收对象仓**，即 `crctl test` 计算 `sourceRevision` 的绑定面。
⑤ `cmd-01` 的被测命令由包装器内部常量决定（`node --test --test-reporter=tap [--test-concurrency=<常量>] <21 个文件>`），本表**不复制**该常量（命令单一来源，FR-12.3）。
⑥ 无 shell 字符串、无 pipe/redirect、无 env、无 `command` 字段、无绝对 `cwd`；`executable` 直接可 spawn（`node`）。
⑦ **`cmd-01` 的 stdout 禁词约束（防 crctl `skipped` 误判）**：包装器的人类摘要与 JSON 不得出现独立单词 `skipped`（含大小写）、`# skip`、`no tests to run`；固定字段名用 `skipped_file_level`（下划线使 `\bSKIPPED\b` / `\bskipped:\s*[1-9]\d*` 均不命中）。依据：`runTestPlan` 的冻结 skip 模式表（`lib/workspace-transactions.mjs:3992-3998`）。
⑧ **`cmd-05` 的证据路径是 KB 仓的绝对路径**（`…/.rayai-worktrees/knowledge-base/requirement/CR-2026-065/change-requests/CR-2026-065/test-evidence`）：证据文件随 CR 提交在 KB worktree（与 `test-evidence/cmd-NN.log` 同址），脚本以 `repo=tools` 执行、以绝对路径读取 KB；`sourceRevision` 绑定面仍是 tools（被读仓证据由 `cmd-01`/`cmd-04` 绑定）。

### 6.3 干跑/可达性记录（冻结前按同一语义实跑）

干跑语义 = `spawnSync(executable, args, { cwd: <repo worktree>/<cwd>, shell:false })`，2026-09-13 在真实 CR worktree 上执行。

| 证据ID | 可达性 | 实测 | 干跑结论（当前预期失败集 / 命中清单） |
|---|---|---|---|
| cmd-01 | **实施后可达**（`suite-gate.mjs` 由 TASK-03 新建，当前不存在） | 未执行 | 依据 = 基线整跑既有实测 exit 1 / 894.8 s / 失败恰 5 条 + 命令形态与 CI 同源；首次干跑单位 = TASK-03 完成后的首次 `--run`（TASK-03 完成标志之一）。**本节点 15 min 预算不足以整跑，未复跑** |
| cmd-02 | 可达 | exit 1 / **135 ms**（repeatable 形态，命中 BR-1/BR-2 两条）；同语义四模式单次形态另测 exit 1 / 11.0 s | 预期失败：BR-1、BR-2 报红（BR-3/BR-4 需 `crctl.test.mjs` 内匹配，见下一行）；实施后 exit 0 |
| cmd-03 | 可达 | exit 1 / **22.6 s** | 预期失败：`TASK-01 RED-7` 报红，失败断言 `actual: [{ code: 'EMIT_FAILED', event_kind: 'archive' }]` vs `expected: []`（= BR-5 构造失真，与 SDD §4.5/§6.3 一致）；实施后 exit 0 |
| cmd-04 | 可达 | exit 1 / ≈ 1 s | 预期失败：`gate-registry.json 缺失`，`FR-15 diff paths = 0`（实施前基线）；实施后二者均须通过 |
| cmd-05 | 可达 | exit 1 / ≈ 1 s | 预期失败：`NC-1 inject` 等 17 项缺失（实施前基线）；实施后须 `failures = 0` |
| 反证（收窄必要性） | — | `trace-outbox.test.mjs` 整跑 134.5 s（exit 0）；`archive-tx.test.mjs` 整跑 > 150 s（截断）；两文件整跑 > 600 s（截断） | 故 cmd-03 只取收窄形态（用例名过滤），整文件粒度不进证据集 |

### 6.4 实施期实验协议（负控与收敛；证据随 CR 提交，非 cmd-NN 执行面）

**执行面**：`implement-code`（`CR-2026-065-TASK-04`），工具同样为 `suite-gate.mjs --run`（与 cmd-01 同命令、同 `--max-runtime-ms`）。

| 实验 | 注入动作（真实漂移） | 预期红点 | 还原 | 证据文件（KB `test-evidence/`） |
|---|---|---|---|---|
| N-1 状态机口径 | 向 `tools/dir-graph.yaml#state_machine.transitions` 增加一条真实转换（如 `from: developing, to: developing, trigger: "crctl-test-injection"`） | `crctl.test.mjs` 的 `TASK-06 ⑤` 用例（集合/计数不等） | 删除该行；`crctl git status --short` 确认该文件干净 | `drift/NC-1-inject.json`、`drift/NC-1-restore.json` |
| N-2 文本语义 | 向 `write-requirement-prd/SKILL.md` 注入一个禁用词（如 `validate-doc`）或删除「七个章节」要素 | `crctl.test.mjs` 的 `CR-2026-042 静态合同：已知 Skill 越界文本零命中` 用例 | `crctl git checkout -- <path>` 还原并核验干净 | `drift/NC-2-inject.json`、`drift/NC-2-restore.json` |
| N-3 去重字段契约 | 在 `lib/outbox-contract.mjs` 的 `buildOutboxEvent` 增加一个未登记字段（如 `observed_at`），或向 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 增加未登记键 | `trace-outbox.test.mjs` 的 `CR-2026-065` 契约用例（字段分类 / 投影闭合不变性） | 同 N-2 | `drift/NC-3-inject.json`、`drift/NC-3-restore.json` |

- 每个证据 JSON 的固定字段（S-2 口径，与 §2.4 同源）：`command` / `duration_ms` / `converged` / `exit_code` / `failures[]` / `injection`（diff 摘要）/ `restore`（还原后结论）。
- **注入物不得留在交付分支**：每轮还原后以 `crctl git status --short` 留痕，并由 `cmd-04` 的 diff 白名单二次兜底。
- 汇总：`test-evidence/NC-summary.md`（三类注入的「命令 / 耗时 / 是否停滞 / 结论」表 + 逐条还原结论）。
- **收敛协议（FR-12）**：候选 = 去参（runner 默认并发）与 `--test-concurrency=1`；各 ≥2 次**连续**整跑；记录 `command`（含实际并发值或「无参数」）/`duration_ms`/`converged`/`failures`；写入 `test-evidence/concurrency/{default-run1,default-run2,conc1-run1,conc1-run2}.json`；选中者写入 `suite-gate.mjs` 的唯一常量，未选中者的观测保留在汇总中（**证据可复现，不只写结论**）。

### 6.5 判据面钉死清单（含本轮评审 E-1 / E-2 收口）

| # | 判据面（写死在断言/实现里，逐字） | 出处 | 备注（防自造冲突断言） |
|---|---|---|---|
| J-1 BR-1 | `write-dev-tasks/SKILL.md` 含 `crctl task init` 与「禁止 Agent/Skill 手写」；`code-implementation.pipeline.json`：节点数 ≡ `pipeline-templates/_index.yml#code-implementation-v1.nodes`（**跨文件投影，不写第二份 16**）、所有节点 prompt 对命令面 `crctl (task init\|task append\|task done\|advance\|review-record\|approve\|owner-set\|version-set)` 与账本名 `_index.yml` / `_backlog.yml` 零命中、`ref` 存在 | SDD §4.4 第 1/2 行；本机实测 pipeline 对二者 0 命中 | 不改 pipeline 文本 |
| J-2 BR-2 | `review-alignment/SKILL.md`：读取契约命中 `change-requests/_backlog.yml` 与 `cr.md`（本机各 1）；`checkpoints[]` 与 `latest-checkpoint` 零命中（本机各 0）；`mtime` / `merge-commit` / `fingerprint` 按**否定辖域**判（切句后每个命中句含 `不读`；零命中亦满足） | SDD §4.4 第 3 行；本机实测三词各 2 处命中、均在否定句内 | **不要求该文件零命中**、不回写该文件（§9 `zero_diff`；回退事实源即红） |
| J-3 BR-3 | 推导（`parseYaml(dir-graph.yaml,{strict:true})`）≡ 登记（`gate-registry.json#stateMachine.{namedStates,transitions,wildcards}`）三条集合/计数等价；`expanded ≡ 31−2+12×2` 由登记集合自洽推出 | SDD §4.1；本机实测 31/15/2/12/53 | 推导侧结构自检恒真、**不计入覆盖**（SDD-CLOSE-10）；用例名保留历史口径字样（不改名，避免与 SDD §6.3 登记名与证据模式漂移——名字不是断言） |
| J-4 BR-4 | 定位含「重新读取」的校验句（先 `\r\n→\n`），断言句内同时含 `frontmatter 必填字段` / `七个章节` / `未替换占位符`；5 禁用词零命中；**`crctl validate` / 命令形态 `Commit：` 零命中**（在 `write-requirement-prd/SKILL.md` 上）；`crctl git commit` 零命中（在 `write-dev-tasks/SKILL.md` 上，= 既有测试同款模式） | SDD §4.4 第 4 行 + **E-1 收口**；本机实测：三对象齐备、5 禁用词 0、`crctl validate` 0、`Commit：` 0、`crctl git commit` 0 | **不得**改用子串「手工 commit」做零命中：`SKILL.md:89` 现有否定表述「Skill 不输出手工 commit 指令」，且该文件在 §9 `zero_diff` 内不可改 —— 判据面只落到既有测试同款模式（`/crctl validate\|Commit：/` 与 `/crctl git commit/`） |
| J-5 BR-5 | 构造 A（预写与本次事件**内容一致**的文件 + journal `payload.outboxEmitted=false`）保留原断言；构造 B（同名不同内容）断言 `EMIT_FAILED` / `OUTBOX_DEDUP_CONFLICT` 可见信号、journal 保持 pending、补发成功且零新 commit | SDD §4.5；本机实测 BR-5 失败向量与「文件名存在但内容不同 → `OUTBOX_DEDUP_CONFLICT`」（`crctl.mjs:336/339`）一致 | 不改产品去重语义；`detected_at` 的 drift-audit 用例（`crctl.test.mjs` 既有）不得回归 |
| J-6 FR-10 契约 | `OUTBOX_VOLATILE_PAYLOAD_KEYS = ['detected_at']`（payload 根下**相对键**）+ 投影 `delete payload[k]`（同一键空间）；不变性：字段分类集合相等、枚举排除非自动（`payload.observed_at` 仍参与）、投影闭合（交集为空） | SDD §3.1/§4.3 | 常量与投影只能有一种读法；不得保留 `split/slice` 旧读法 |
| J-7 门禁退出码 | `exit 0 ⟺ 无任何未抑制触发`；`SUITE_NONCONVERGENCE` 可抑制（未到期 + `kind: suite-nonconvergence` + 稳定标识匹配）；**非收敛分支已匹配例外视为已观测**（E-2 收口，`EXCEPTION_NOT_OBSERVED` 不得用空观测集合判） | SDD §3.2 + **E-2 收口** | 交付态 `exceptions=[]` 不受影响 |
| J-8 cmd-01 stdout 禁词 | 不得输出独立词 `skipped`（含大小写）/ `# skip` / `no tests to run`；固定字段用 `skipped_file_level` | `lib/workspace-transactions.mjs:3992-3998` 冻结模式表 | 避免 crctl 把绿判成 skip 态 |

---

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01（FR-11）CI 全量步骤 exit 0 / 失败集合为空 / 21 文件真实执行 / 文件级 skip 为 0 | §4.2 + §6.2 AC-01 | CR-2026-065-TASK-03 | cmd-01 |
| AC-02（FR-1、FR-2）断言→事实源映射覆盖三类断言类别，取值随事实源变化 | §4.4 两张表 + §6.6 D1…D6 | CR-2026-065-TASK-01 | cmd-02；cmd-04 |
| AC-03（FR-3）可推导事实 vs 必须钉死目标值分界，无等价重述 | §6.6 D/P 两表 + §4.1 反恒真 | CR-2026-065-TASK-01 | cmd-04；cmd-02 |
| AC-04（FR-4）BR-1 转绿且断言落在真实载体 + pipeline 语义约束保留 | §4.4 第 1/2 行 + §6.3 第 8/9 项 | CR-2026-065-TASK-01 | cmd-02 |
| AC-05（FR-5）BR-2 转绿且 `review-alignment/SKILL.md` 未新增 `latest-checkpoint` | §4.4 第 3 行（否定辖域）+ §6.2 AC-05 | CR-2026-065-TASK-01 | cmd-02 |
| AC-06（FR-6）BR-3 转绿 + 声明/展开由推导得出 + N-1 注入变红 | §4.1 + §2.3 + §6.2 AC-06 | CR-2026-065-TASK-01 | cmd-02；cmd-05（N-1） |
| AC-07（FR-2、FR-7）BR-4 转绿 + 5 禁用词零命中 + N-2 注入变红 | §4.4 第 4 行 + §6.2 AC-07 | CR-2026-065-TASK-01 | cmd-02；cmd-05（N-2） |
| AC-08（FR-8、FR-9）RED-7 构造为真实崩溃窗口 + 原断言全保留 + 同名不同内容用例 + drift-audit 不回归 | §4.5 构造 A/B + §3.1 行为等价 | CR-2026-065-TASK-02 | cmd-03 |
| AC-09（FR-10）去重契约单一事实源可检查 + 未登记易变字段即红 + N-3 注入变红 | §3.1 不变性 1…6 + §4.3 | CR-2026-065-TASK-02 | cmd-03；cmd-05（N-3） |
| AC-10（FR-12）并发决定 + 可复现证据（命令/耗时/是否停滞）+ CI 与文档同口径 | TDEC-4 + §2.4 + §4.2 | CR-2026-065-TASK-04 | cmd-01（最终配置字段）；cmd-05（两候选记录） |
| AC-11（FR-13）状态机 / 文本语义 / 去重契约三类注入各一次 → 全量红 → 还原绿，注入物不在交付分支 | §4.6 + §6.4 协议 | CR-2026-065-TASK-04 | cmd-05（`NC-*` 记录形态）；cmd-01（还原后全量绿）；cmd-04（注入物不在 diff） |
| AC-12（FR-14）例外单一登记处 + owner + 到期 + 到期即红 + 不得自证绿；无例外显式为空 | §2.3 + §3.2 四查与 check code | CR-2026-065-TASK-03 | cmd-01（`exceptions=[]` 时退出码 ≡ 失败集合为空）；cmd-04（显式空数组 + 零写路径） |
| AC-13（FR-15）diff 只落 tests / CI / 去重契约最小产品面；无新依赖；不含包 B 与 CR-2026-064 面 | §1.2 + §9 `scope_in`/`zero_diff` | CR-2026-065-TASK-04 | cmd-04 |
| AC-14（FR-16）无新增红、无新增 skip、含与 894.8 s 同口径的耗时对比 | §2.3 `manifest.cases` + §7.3 | CR-2026-065-TASK-04 | cmd-01 |
| AC-15（FR-17）声明无新增用户可调用契约 + 例外登记面四查结论 | §3.3 + §3.2 四查 + §8 | CR-2026-065-TASK-03 | cmd-01（`contract-scan` 静态断言随套件执行）；cmd-04 |
| 业务闭环：绿有约束力 —— 漂移在引入它的 CR 内当场变红（而非攒到第 5 次变更） | §4.6 + §4.1 反恒真 + §3.2 错误闭包 | CR-2026-065-TASK-04 | cmd-05（三类注入证据）；cmd-01 |
| 业务闭环：断言只读 —— 不新增受治理账本（`_backlog.yml` / `cr.md` / `approval.yml` / `tasks/_index.yml`）写路径 | §3.3 + §7.2 | CR-2026-065-TASK-03 | cmd-04（登记面零写路径判据）；cmd-01（`contract-scan` 静态断言） |
| 业务闭环：`crctl test` 证据集与 plan 全等（cmd-NN ↔ 机器区下标 ↔ `test-evidence/cmd-NN.log`） | §2.4 + §6.2 表 | CR-2026-065-TASK-04 | cmd-01；cmd-02；cmd-03；cmd-04；cmd-05 |

> **关键 AC 唯一 owner 说明（机械可判）**
> - **AC-04 / AC-05 / AC-06 / AC-07 唯一 owner = TASK-01**（四条断言的实际产生层；证据 cmd-02，注入面 cmd-05）。
> - **AC-08 / AC-09 唯一 owner = TASK-02**（`emitOutboxEvent` 契约提级与 archive/trace 用例的实际产生层；证据 cmd-03）。
> - **AC-01 / AC-12 / AC-15 唯一 owner = TASK-03**（`suite-gate.mjs` + `gate-registry.json` 消费面 + `crctl-ci.yml` 的实际产生层；证据 cmd-01、cmd-04）。
> - **AC-10 / AC-11 / AC-13 / AC-14 唯一 owner = TASK-04**（收敛实测、负控实验、diff 审计与整跑口径的收口层；证据 cmd-01、cmd-04、cmd-05）。
> - AC-02 / AC-03 的唯一 owner = TASK-01（断言与事实源的推导层；证据 cmd-02、cmd-04）。
> - 四个 TASK 均在矩阵中出现，与 `tasks/_index.yml#id` 集双向一致；业务闭环行不与关键 AC 行争用同一证据语义。

---

## 8. 任务输入约束与残余项收口对照

**A. 本轮任务输入约束（逐条生效，来自协调人转交）**

| # | 约束 | 本计划落点 |
|---|---|---|
| C-1 | SDD 是设计基线，`plan.md` / TASK 不得静默改动 AC 目标、§9 `zero_diff` 面、最小改写边界 | 头部绑定表 + §6.2 表注② + §6.5 J-1…J-8 + §9 `zero_diff` 清单；本计划**不写入任何 SDD 正文修改**；若实施期发现 SDD 不可实施，出口 = 状态机既有回退（`review-dev-plan:upstream-design-blocker` → `write-tech-design`），不作就地放宽 |
| C-2 | AC-01 的「exit 0 / 失败集合为空」是交付目标，不是变更前事实 | §0 基线红登记（5 条「待修的红」，注明既有实测口径与「本节点未复跑全量」）+ §5.1 第 2 条 + §6.1 FR-11 行；全文无一处以「CI 现在是绿的」为前提 |
| C-3 | 不扩范围：不碰 CR-2026-064、不碰包 B、不碰 §9 `follow_up` 三处硬编码断言 | §0 末条 + §9 `scope_out`；`cmd-04` 的 diff 白名单把「越界改动」做成机器判据（含 `dir-graph.yaml` / `pipeline-templates/*` / 所有 `SKILL.md` 零 diff 的间接兜底） |

**B. 上一轮技术设计评审残余非阻塞项（不设 gate，逐条给结论）**

| # | 残余项 | 结论 | 落点 |
|---|---|---|---|
| E-1 | §4.4 BR-4 行的「`crctl validate` 与手工 commit 配方零命中」缺机械匹配面，且 `write-requirement-prd/SKILL.md:89` 有含「手工 commit」子串的否定表述、该文件在 `zero_diff` 内不可改 | **已处理**：判据面钉为既有测试同款模式 —— `write-requirement-prd/SKILL.md` 上 `/crctl validate\|Commit：/` 零命中（本机实测两词 0 命中），`write-dev-tasks/SKILL.md` 上 `/crctl git commit/` 零命中（既有测试 `crctl.test.mjs:4997` 同款）；**不使用**子串「手工 commit」做零命中，且不回改被断言文件 | §6.5 J-4；TASK-01 实现要点 |
| E-2 | §3.2 非收敛分支与 `EXCEPTION_*` 的口径：已匹配的 `kind: suite-nonconvergence` 例外在该分支视为已观测 | **已处理**（交付态 `exceptions=[]` 不受影响，首次登记非收敛例外时才生效）：非收敛分支不做清单/失败集合核对（`not_evaluated=true`），只判 `SUITE_NONCONVERGENCE` 与登记面自身错误；匹配例外视为已观测，禁用空观测集合判 `EXCEPTION_NOT_OBSERVED` | §5.3 + §6.5 J-7；TASK-03 实现要点 |

**C. 上游交付物的非阻塞观察（本计划不改写，仅登记）**

- SDD §6.4 登记的 `tools/ARCHITECTURE.md` §5 不变量 5 的「28/50」滞后事实 → 保持 `follow_up`（本 CR 不读该段文本作方案前提，`cmd-04` 也不断言该文件）。
- SDD §9 `follow_up` 的另两处 pipeline 节点数硬编码（`pipeline-structure.test.mjs:41`、`:183`）→ 保持 `follow_up`，不进本轮 diff。
- 上一轮技术评审的 S-1/S-2/S-3 已在 SDD §6.5 关闭（本计划按关闭后的口径落点，不复述其内容）。

---

## 9. TASK 拆分预分配（`write-dev-tasks` 的输入，共 4 个，组映射 1:1）

| 变更组 | 覆盖 FR | TASK id | 仓库 | 粒度 | 依赖 |
|---|---|---|---|---|---|
| G1 断言推导与四条漂移转绿 | FR-1、FR-2、FR-3、FR-4、FR-5、FR-6、FR-7 | CR-2026-065-TASK-01 | tools | 2 天（16h） | — |
| G2 去重契约提级与 BR-5 修正 | FR-8、FR-9、FR-10 | CR-2026-065-TASK-02 | tools | 2 天（16h） | — |
| G3 CI 真门禁与例外治理 | FR-11、FR-14、FR-17 | CR-2026-065-TASK-03 | tools | 2.5 天（20h） | CR-2026-065-TASK-01、CR-2026-065-TASK-02 |
| G4 收敛决定、漂移负控与范围收口 | FR-12、FR-13、FR-15、FR-16 | CR-2026-065-TASK-04 | tools | 2 天（16h） | CR-2026-065-TASK-01、CR-2026-065-TASK-02、CR-2026-065-TASK-03 |

- 每个 in-scope FR 在 §6.1 交付覆盖表**恰出现一次**，主责 TASK 唯一（关联 TASK 不改变主责）。
- `task_count_hint = 4`（= 上表组数 = `tasks/_index.yml` 的 TASK 数 = §6.1/§7 出现的 canonical id 集）；`totalEstimateHours` 期望 = **68h**，与 §1/§5.4 口径一致。
- 回滚单元按 §4.0（RU1…RU4，逆拓扑）；TASK 卡接口契约逐字对齐 SDD（`deriveStateMachine` 由 TASK-01 产出、`lib/outbox-contract.mjs` 由 TASK-02 产出并被 TASK-03 的静态断言消费、`suite-gate.mjs` 的 CLI 由 TASK-03 产出、被 TASK-04 的实验协议消费）。
- 四张 TASK 卡的完成边界全部落在 `developing` 内可被 `crctl task done` 登记的事件（实现已落盘 + 证据命令绿 + 任务账本登记），**无 merge / writeback / archive / code-reviewing / code-approved 前置**（流程控制 TASK 禁止）。
- TASK-02 新增用例的 `test(...)` 名必须以 `CR-2026-065` 起始（§6.2 表注②）；TASK-04 负责 `manifest.cases` 终值刷新（§4.1 R-10）。
- **`zero_diff` 复核清单（TASK 卡须逐条声明不触碰）**：`dir-graph.yaml`、`pipeline-templates/*`、所有 `SKILL.md`、`lib/yaml-subset.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`skills/shared/controlled-shell/rules.json`、`crctl.mjs` 顶层 dispatch 与既有子命令签名/参数/错误码、历史 CR 产物与 `specs/`、`delivery/`。
