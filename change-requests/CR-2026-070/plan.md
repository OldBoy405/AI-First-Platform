---
id: CR-2026-070-plan
type: PLAN
cr-ref: CR-2026-070
sdd-ref: "change-requests/CR-2026-070/sdd.md"
target-version: 0.43
status: draft
created: 2026-09-18T11:30:00+08:00
updated: 2026-09-18T11:30:00+08:00
---

# CR-2026-070 开发计划（Agent Skill 路由 + Pi bash 默认超时）

| 输入 | 绑定 | 摘要证据 |
|---|---|---|
| `change-requests/CR-2026-070/sdd.md`（698 行 / LF，唯一权威） | `review-annotations/sdd.yml#subject-sha256`（cycle 1 / attempt 2，`verdict=pass`、`blockers=[]`）+ `approval.yml#tech-design`（`via: crctl-approve`、`approver Ray`、`2026-09-18T10:52:38+08:00`、`evidence-digest 023dc280c0c50436d82a2efc5f1ac659bfcca6f3ddb995a21bd0427cf855ce7a`、`target-status: tech-design-reviewed`，提交 `349ae227`） | sha256(LF) = `00a3f7274b1081f87776b7e68c8ce6a6be2b3f899a87bae23fe2699952536e4d`（本节点按 worktree 实际文件复算，与 `review-annotations/sdd.yml#subject-sha256` 全等） |
| `change-requests/CR-2026-070/prd.md`（冻结，零触碰） | 需求人工审批冻结（`evidence-digest 1e4d3d9ea4f351e5860dcc9329fd7dfb509d3e1d02c9f03c4486f68898b415eb`）；SDD `dep-1` 的 sha256 | sha256(LF) = `8972e5c5d8e62389c1cb44b7d8bd7974378da03be754d145c5cb46884a3130f8`（= 需求评审 `subject-sha256` = SDD `dep-1`）；本计划只按 SDD 引用定位，不全量复审 PRD |
| `cr.md#target-version` | 注册期继承 | `0.43`（禁止 tbd / 自行改写，CR-2026-057 FR-13） |

---

## 0. 基线与工作区事实（本节点实测，落笔即读，未轮询）

### 0.1 入口状态与门禁（crctl 权威值；全部显式带 `--workspace <KB worktree>`）

| 项 | 实测 |
|---|---|
| `crctl status CR-2026-070 --workspace <KB>` | `status=tech-design-reviewed`；`legalNext` = `task-breakdown`(`write-dev-tasks`) / `rejected` / `withdrawn`；`reviewLoops.review-requirement=2/3`、`review-tech-design=2/3`；`gateBlockers.task-breakdown = ["文件不存在","文件不存在","目录缺失或无匹配文件"]`（= `plan.md` / `tasks/_index.yml` / `tasks/TASK-*.md` 尚未生成，符合本节点开工前预期） |
| `crctl next CR-2026-070 --workspace <KB>` | `{"status":"tech-design-reviewed","next":"write-dev-plan","humanApproval":false,"why":"技术设计已审批，编写开发计划"}` |
| `--workspace` 纪律（本轮实测） | 在 KB worktree 内**不带** `--workspace` 调 `crctl status/next` 会回退主工作区并返回陈旧事实（实测原样：`{"cr":"CR-2026-070","status":"drafting","next":"write-requirement-prd","why":"prd.md 缺失"}`）。本节点与后续节点的每次 `crctl status/next/gate/test` 一律显式带 `--workspace` |
| `crctl workspace inspect CR-2026-070 --detail --workspace <KB>` | 三仓 `classification=healthy`、`dirty=false`；`operationalWorkspace` = `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-070` |

### 0.2 上一阶段发布收口（协调者指定的闭合项，本节点只回报事实）

```text
node <TOOLS>/skills/shared/crctl/scripts/crctl.mjs git ls-remote --heads origin requirement/CR-2026-070 --cwd <KB>
⇒ 938e4a06a665cadd7b4f0b0a9c6b222c099136be	refs/heads/requirement/CR-2026-070
KB 本地 HEAD = 349ae2271cfa53009dd90bbbb967d11ce98892c9（= 技术设计人工审批提交）
⇒ 差 1 个提交：审批写入（approval.yml#tech-design + cr.md status）已 commit、**未推**
```

按 `push-progress` SKILL 的既定口径（「审批之后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担」，CR-2026-044 FR-07 经 CR-2026-066 修正）：**本节点不单独开 checkpoint、不为该动作单独开委派**；该提交随 `review-dev-plan` PASS 分支的 checkpoint 与前序未推提交（`349ae227` 之前的 `c1db7b9e`/`938e4a06` 之后新增项）一并闭合。上一阶段的同类处理已在技术设计节点执行并被接受（作者 run `5122e930` 批次）。

### 0.3 三仓 worktree（路径 authority = `resources[].worktreePath` 原样值，不拼接、不回退主工作区）

| repo | worktreePath | 分支 | HEAD（本节点实测） | 本 CR 角色 |
|---|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-070` | `requirement/CR-2026-070` | `349ae227…`（技术设计审批提交） | 过程文档（prd/sdd/plan/tasks/evidence）；零代码 |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-070` | `requirement/CR-2026-070` | `59b47993810fabd12fcc393c2fa2e46611f9530d`（= SDD `dep-3`～`dep-9`／`dep-13` 的登记 SHA；**diff 审计基线**） | 单元 A（FR-1 落点）+ 台账登记 |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-070` | `requirement/CR-2026-070` | `c3e7c934ef2636c56cc840543cadb4feb5f554aa`（= SDD `dep-10`／`dep-12`／`dep-14` 的登记 SHA） | **零 diff**（AC-9／AC-10 的取证面与零复制面） |

**单元 B 的 Pi 源码检出（本节点按 §10 路线决策建立，**不在** CR worktree 集合内——DEC-3）**：

| 项 | 实测 |
|---|---|
| checkoutPath | `C:\Users\GOBAO\Downloads\AI\pi-mono`（本机 sibling，非 `.rayai-worktrees` 成员、不被 checkpoint 覆盖） |
| 建立方式 | `git clone --branch v0.85.1 --depth 1 https://github.com/earendil-works/pi-mono pi-mono`（**21.5 s**） |
| 钉定基线 | `d981de1229ef899957bbe968bc8dcda02a21f477` = 上游 tag `v0.85.1`（与本机已安装包 `@earendil-works/pi-coding-agent` 0.85.1 同版本线；`git ls-remote --tags` 实测） |
| 工作树状态 | `git status --porcelain` 空（clean，detached HEAD @ tag） |
| 工具链 | `npm ci --no-audit --no-fund` **2 m 14 s**（318 包）+ `npm --prefix packages/ai run hydrate-model-data` **4.9 s**（`packages/ai/src/providers/data/**` 被 .gitignore，缺失则 vitest 无法导入 model catalog）+ `npm run build:offline` **9.7 s**（tsgo 全仓构建，产出 `packages/coding-agent/dist`） |

### 0.4 基线实测（本节点未改任何 CR 文件；win32 / node v24.15.0 / go 1.26.4 / bun 1.3.14）

| 面 | 实测值（本条 run） |
|---|---|
| **cmd-01（tools，既有）** | **exit 0** / **5.995 s**：`node --test --test-reporter=dot output-guard/test/{core,conformance,adapters-contract}.test.mjs`（38 pass）⇒ AC-9 的复跑入口在变更前全绿 |
| **cmd-02（multica，既有测试面）** | **exit 0** / **3.649 s**：`go test ./internal/daemon/execenv/ -count=1 -v -run TestBriefSkills` ⇒ `--- PASS: TestBriefSkillsListIsNamesOnly`，7 个 provider 子用例（claude/opencode/grok/codex/hermes/traecli/some-unknown-provider） |
| multica `execenv` 整包（口径事实，非本 CR 门禁） | 整包在基线即非全绿（CR-2026-069 §0.4 记录：`openclaw_config_test.go` panic + 24 项上游既有失败）⇒ 本计划**不**以整包绿为门禁，cmd-02 用定点 `-run` + cmd-03 的源码级存在性断言替代（表注④） |
| **Pi 检出基线（变更前）** | `test/tools.test.ts` 全文件 **77 passed / 4 failed**（4 项均为 Windows 环境类：EACCES×2、grep flag-like、bash ctx.cwd 路径；与本 CR 的 timeout 面无关）；该文件内 `bash tool > should respect timeout` 通过 ⇒ 新用例必须落在**独立新增文件**内，不以「整包绿」为判据 |
| **Pi 侧缺陷的机械基线（本节点探针，已删除探针文件）** | 以 `vi.spyOn(globalThis,'setTimeout')` 捕获 `createBashTool(cwd)` 本地执行路径调度的计时器：**未传 `timeout` → 捕获集 = `[]`（完全不挂计时器，即 PRD §1.4 事实 5 的缺口）**；显式 `timeout: 300` → 捕获 `[300000]`，手动触达该回调后抛出的文本为 `Command timed out after 300 seconds`（与 `dep-1` FR-2 超时结果第 2 项逐字一致） |
| **安装包现状（AC-12 负向基线）** | `D:\tools\npm-global\node_modules\@earendil-works\pi-coding-agent`：`package.json` version `0.85.1`；`dist/core/tools/bash.js` sha256(`LF`) = `5f5bc414757f2b48…`（13565 B）、仍含字面 `no default timeout`；`dist/core/tools/bash.d.ts` 零 `resolveTimeoutMs` 导出（S-6 的前提事实） |
| **运行中平台二进制（AC-2～AC-4 的环境事实）** | `multica --version` 实测 `v0.4.41-469-g947386318 (commit: 947386318, built 2026-09-16T09:05:32Z)`（Go 1.26.6）⇒ 规则文本要进入真实 run 的 brief，必须由 owner 在部署窗口用本 CR 的 multica 构建替换运行中的 daemon/CLI（§5.0） |
| KB 工作区 | `git status --porcelain` 空（clean）；`prd.md`／`sdd.md` 零改动（sha256(LF) 与审批绑定值全等） |

### 0.5 关键锚点（实施定位线索；行号为上述基线 SHA／tag 上实测，实施期以实时搜索为准）

| 文件 | 既有对象（本节点实测事实） | 本 CR 处置 |
|---|---|---|
| `server/internal/daemon/execenv/runtime_config_sections.go`（multica@59b47993） | `writeSkills(b *strings.Builder, ctx TaskContextForEnv)` L833（段头 L838、`discovered automatically` 列表 L839；函数注释 L818「Names only, deliberately」）；brief 装配调用点 L1058 | TASK-01：只在 `writeSkills` 末尾追加常量 `skillsRoutingRule`（§3.2 逐字文本）+ 一次 `b.WriteString`；`## Skills` 段形状（Z-7）、空集早退（B-1）逐字不变 |
| `server/internal/daemon/execenv/runtime_config_test.go`（multica@59b47993） | `TestBriefSkillsListIsNamesOnly` L2135（7 provider 子用例）；同文件另有 `TestInjectRuntimeConfig*` 系列 | TASK-01：在既有形状钉子测试内**追加**断言（引用常量符号 `skillsRoutingRule`，**不内联**检索锚短语——否则落点面由 1 文件扩为 2 文件，违反 SDD §6.4） |
| `../multica/CUSTOM.md`（multica@59b47993） | 《代码改动明细（按 CR 分组）》末段章节 = `### CR-2026-066 …`（L487）；全表最大稳定行号 **#95**；「合并注意」四种标准口径 + 末尾「验证：」尾句 | TASK-03：新增 **#96** 行（按其当时实际结构顺延），原因追溯含 CR-2026-070 与 TASK-01／TASK-02，含「验证：」最小命令 |
| `packages/coding-agent/src/core/tools/bash.ts`（pi-mono@v0.85.1 = d981de12） | `MAX_TIMEOUT_MS = 2_147_483_647` L22、`MAX_TIMEOUT_SECONDS` L23、`function resolveTimeoutMs(timeout: number \| undefined): number \| undefined` L25（undefined 直接返回、非法值 L28、超上限 L32-33）、`bashSchema` L38（`timeout` 描述 L40 = `Timeout in seconds (optional, no default timeout)`）、本地执行路径 L83-84 调 `resolveTimeoutMs`、`killProcessTree(child.pid)` L110／L118、`setTimeout` L116、超时信号 `` `timeout:${timeout}` `` L136、工具层文本拼接 L355 | TASK-02：`DEFAULT_TIMEOUT_MS = 300_000`（唯一 owner）+ `undefined` 分支返回默认值 + 信号值改为实际生效秒数 + schema 文案同步；`resolveTimeoutMs` **不导出**（S-6 取舍，见 TASK-02 §6 与 §11） |
| `packages/coding-agent/test/tools.test.ts`（pi-mono@v0.85.1） | `describe('bash tool')` 内含 `should respect timeout`（`timeout: 0.05` → `/timed out/i`）与 `should include full output path for truncated timeout and abort errors`（stub `operations` 回放 `timeout:5` → `Command timed out after 5 seconds`） | TASK-02：新用例落在新增文件 `test/bash-default-timeout.test.ts`（既有文件零改动，避免把该文件既有 4 项环境红计入本 CR 判据） |
| `packages/coding-agent/vitest.config.ts` / 根 `package.json`（pi-mono@v0.85.1） | `test: vitest --run`；`testTimeout 30000`、`env: { PI_OFFLINE: "1" }`；根 workspaces = `packages/*`、`engines.node >= 22.19.0`；`package-lock.json` 存在（无 bun lock） | TASK-02：以 `npm ci` + `node <checkout>/node_modules/vitest/vitest.mjs run <file>` 复跑（不经 shell 包装） |
| `tools/skills/shared/controlled-shell/rules.json`（tools@c3e7c934） | git 白名单 shape 表（`rev-parse ^(HEAD\|origin/\S+)$`、`diff ^--name-only .+$`、`commit ^-m (wip: \|\[cr\] \|merge\().*$` 等）+ `forbiddenFlags` | 全部 diff／rev-parse 取证经 `crctl git`（含外部 checkout），Pi 侧提交信息用 `[cr] ` 前缀（未改本文件，Z-5／AC-10） |

---

## 1. 交付里程碑

| # | 阶段 | 内容 | 产出 | 估算 | 状态 |
|---|---|---|---|---|---|
| M1 | 需求与架构（已完成） | 注册 → PRD → 评审（2/3）→ 人工审批 → SDD → 回修 → 复评 PASS（2/3）→ 人工审批 → 技术设计审批提交 `349ae227` | `prd.md`、`sdd.md`、`approval.yml#requirement`/`#tech-design` | — | **done** |
| M2 | 开发计划与拆分（本节点） | `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan` | `plan.md`、`tasks/TASK-01..04.md`、`tasks/_index.yml`、`status=task-breakdown` | 本条 run | **本条 run（评审由独立 reviewer run 执行）** |
| M3 | 实现 | TASK-01 ∥ TASK-02 → TASK-03 → TASK-04（依赖序见 §2） | multica：`runtime_config_sections.go` + `runtime_config_test.go` + `CUSTOM.md#96`；Pi 检出：`bash.ts` + `test/bash-default-timeout.test.ts`；KB：`evidence/{pi-vitest.log,fr1-smoke.json,pi-source.json}`；4 张 TASK 在 `tasks/_index.yml` 即时标 `done`（工程纪律 8，不积压到回写期） | **36 h（≈ 4.5 人天）** | pending |
| M4 | 测试 | `write-test-report`（`crctl test --plan`，**6 条证据命令**：2 条既有测试面 + 1 条 multica 内容审计 + 1 条三仓 diff 审计 + 2 条 KB 证据/活体审计） | `test-report.md` + `test-evidence/cmd-01…06.log` | 见 §5.4 预算 | pending |
| M5 | 代码评审与审批 | 独立 `review-code` → 人工 `approve-code` | `review-annotations/code.yml`、`approval.yml#code` | — | pending |
| M6 | 交付回写 | `delivery-agent` 的 merge / writeback / archive | merge 提交、`delivery/task/**`、`specs/ai-first-platform` 基线 | — | pending |

---

## 2. 任务依赖图

```text
TASK-01（FR-1 单元 A：multica 单点规则文本 + 既有形状钉子测试增项）
   │  改：server/internal/daemon/execenv/runtime_config_sections.go、runtime_config_test.go
   │
   ├──────────────► TASK-03（治理登记：multica CUSTOM.md #96，原因追溯含 CR-ID + TASK-01/TASK-02）
   │                  改：CUSTOM.md
   │                  （输入 = TASK-01 与 TASK-02 的最终落点与文件清单）
   │
   └──────────────┐
TASK-02（FR-2 单元 B：Pi 版本化源码默认值 + 既有测试框架内新增用例 + 本地构建）
   │  改：<pi checkout>/packages/coding-agent/src/core/tools/bash.ts、test/bash-default-timeout.test.ts
   │  （检出 d981de12… 已就位；构建产物不进交付 diff）
   │
   └──────────────┴──► TASK-04（过程产物与验收记录：FR-1 真实 run 记录 + Pi 侧交付证据）
                          KB：change-requests/CR-2026-070/evidence/{fr1-smoke.json,pi-source.json}
```

- **依赖序固定为 `{TASK-01, TASK-02} → TASK-03 → TASK-04`**：TASK-01 与 TASK-02 落在不同仓／不同目录（multica worktree vs 机器本地 Pi 检出），**互不共用文件**、可并行；TASK-03 的台账行必须按两者的**最终**文件清单与原因追溯填写；TASK-04 的证据记录引用两者的交付事实（`pi-source.json` 记录 TASK-02 的分支/commit/file 集，`fr1-smoke.json` 记录 TASK-01 落地后运行环境的 run 事实）。
- **无环、无悬空**：`depends-on` 只引用本 CR 的 canonical id；TASK-04 的依赖闭包由 TASK-01／02 传递覆盖，仍逐条显式声明。
- **中间态不红**：TASK-01 单独落地后 `## Skills` 段形状不变（追加文本）→ 既有 7 provider 子用例与空集/全隐藏语义不受影响；TASK-02 单独落地后 Pi 侧仅新增默认值分支（显式路径逐字不变，`tools.test.ts` 的 4 项既有环境红与本 CR 无关）；TASK-04 落地前 cmd-05／cmd-06 处于「证据文件缺席」的显式红（§6.3 基线即此形态），不构成假绿。
- **回滚单元**（§4.0）与依赖图逆序一致。

### 2.1 TASK-04 的完成边界（防 `deliveryIndexComplete` 永久不可达）

TASK-04 的产物是**过程证据与验收记录**，其完成边界限定在 `status=developing` 内可被 `crctl task done` 登记的事件：

1. `evidence/pi-source.json` 落盘（schema `cr-2026-070-pi-source/v1`，字段集见 TASK-04），且 cmd-06 的**活体复跑**（变更文件集核对 + Pi 用例 exit 0 + 安装包 sha256 负向）在作者 run 内 exit 0；
2. `evidence/pi-vitest.log` 落盘（TASK-02 的用例执行原文，含 `--- stdout ---`/`--- stderr ---` 两段与退出码），sha256 记入 `pi-source.json`；
3. `evidence/fr1-smoke.json` 落盘（schema `cr-2026-070-fr1-smoke/v1`，三条 run 记录 + AC-4 的受控文件 before/after sha256），且 cmd-05 在作者 run 内 exit 0；
4. 4 张 TASK 的 `crctl task done` 全部登记（工程纪律 8）。

**不得**把「`review-code` 通过」「merge 完成」「回写完成」写入任何 TASK 的完成标志（CR-2026-057 FR-10）：merge / 审批 / checkpoint 的审计事实以既有 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准，不进 TASK ledger。

---

## 3. 资源与分工

| 角色 | 承接面 | 依据 |
|---|---|---|
| `owners.development` = **Ray** | 单元 A／B 的代码、台账、证据记录；开发启动与代码审批的人工节点；Pi 侧检出的建立与运行环境二进制替换（部署窗口） | `cr.md#owners` |
| `owners.test` = **Ray** | 测试报告与验证证据的消费与登记（`write-test-report`） | `cr.md#owners` |
| 独立 `quality-reviewer-agent` | `review-tech-design`（首轮已完成）／`review-dev-plan`（本节点委派）／`review-code`（后续） | Pipeline `code-implementation.pipeline.json` |
| Agent 作者侧 | 本计划与 TASK 的编写、回修、证据采集；**不自评** | Agent 独立评审合同 |

预计工时分配（= §9 预分配的合计，36 h）：TASK-01 6 h（multica 落点 + 既有测试面 + 零复制面自查）、TASK-02 16 h（检出变更 + 5 类用例 + 进程树清理 + 构建 + 证据）、TASK-03 2 h（台账行）、TASK-04 12 h（FR-1 三次真实 run 的记录与审计 + Pi 侧证据记录）。

---

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合，唯一事实）

| 单元 | 对象 | 回滚动作 | 下游消费者（必须同批处理的对象） |
|---|---|---|---|
| RU1 | TASK-01 的 multica 提交（`runtime_config_sections.go` + `runtime_config_test.go`） | 单点 revert 该提交 | 无代码消费者（规则文本是 brief 文本，无调用方）；**TASK-03 的 `CUSTOM.md#96` 行与之同批**（回滚时一并撤销，避免台账残留） |
| RU2 | TASK-02 在 Pi 检出分支上的提交（`src/core/tools/bash.ts` + `test/bash-default-timeout.test.ts`） | 在检出内 revert 该提交（检出非 CR 仓，不进 checkpoint 面） | 无（未发布、未安装；运行环境替换发生在 CR 合并之后） |
| RU3 | TASK-03 的 `CUSTOM.md#96` 行 | 删除该行（台账行只增不改，回滚即删除） | RU1（同一提交内的两个面） |
| RU4 | TASK-04 的 KB 证据文件（`evidence/fr1-smoke.json`、`evidence/pi-source.json`、`evidence/pi-vitest.log`） | 删除证据文件 | 随 RU1／RU2 同批撤销（证据描述的是两者的交付事实，被回滚对象消失后证据无意义） |

**逆拓扑顺序 = RU4 → RU3 → RU2 → RU1**（先撤证据与台账，再撤改动面）。回滚粒度为「单一共享规则」（RU1+RU3）与「Pi 默认值」（RU2）两处，与 `dep-1` §6 的回滚口径逐字一致；OutputGuard、crctl、Pipeline、状态机、受控账本因本 CR 零改动不参与回滚。

### 4.1 风险表

| 编号 | 风险 | 口径与处置 |
|---|---|---|
| R-1 | 300 秒误伤**隐式长调用**（未显式声明 timeout 的长测试／build／migration、共享 brief 要求的前台阻塞命令） | `dep-1` NFR-1 与 §7 第 13 条已把该面排除在本 CR 之外（属调用方运行约定）；回滚粒度 = RU2（Pi 版本／固定默认值单一处）；观察点 = 后续 CR 流程记录与 `suite-gate` 冒烟。若实测误伤：按 §5.2 回滚并另立需求，不在本 CR 内加配置开关（`dep-1` §7 第 8 条） |
| R-2 | AC-2／AC-3 依赖**真实 smoke run**，无法由单元测试替代；且需要运行环境跑本 CR 构建的 daemon | `dep-1` §5 明文要求真实行为验证。环境不可用 → 按 `ENVIRONMENT_MISMATCH` 技术中止并报告所需建立动作（TASK-04 与 §5.0），**不得**退化为静态断言顶替（禁止自报替代证据） |
| R-3 | 零 Skill／全 `disable-model-invocation` 任务的规则不在场（B-1） | 显式边界：既有测试钉住该语义，本 CR 不为它新增第二条注入路径（`follow_up` F-3、§9 scope_out 3） |
| R-4 | 单元 B 的验证时点受路线影响 | 选定 R-C（§10）：源码侧验证可在本 CR 内完成；运行环境 PATH 上 `pi` 的替换发生在 CR 合并之后（`dep-1` §1.3.2 共用边界 2），不进交付 diff |
| R-5 | 安装树存在历史就地修改痕迹（`dep-1` 事实 9 邻域、SDD `V-6`） | 不清理、不依赖；cmd-06 以安装包 `dist/core/tools/bash.js` 的 sha256 负向（+ 仍声明 `no default timeout`）机械证明本 CR 未以安装包为改动载体；若环境合法升级导致漂移 → 按 §5.3 重新基线并注明版本，不得静默通过 |
| R-6 | 规则文本与 Skill 列表的语义分工可能被 Agent 误读为「列表外的 Skill 也存在」 | 文本第 4 子句给出唯一合法动作（中止并报告）；AC-4 用零账本写入与零兜底搜索双侧取证（cmd-05） |
| R-7 | Pi 检出是**机器本地资产**，不进 checkpoint 面（DEC-3 后果）：跨机续接时源码归属判定可复现（URL + tag SHA + 文件集 + 日志 sha256），但用例复跑需按 TASK-02 的建立步骤重建检出 | cmd-06 在检出／`node_modules`／`dist` 缺失时**硬失败**（`ENVIRONMENT_MISMATCH`），不降级为「只审记录」；重建成本已实测（clone 21.5 s + `npm ci` 2 m 14 s + hydrate 4.9 s + build 9.7 s） |
| R-8 | 本机既有红面（Pi `test/tools.test.ts` 4 项环境类失败；multica `execenv` 整包非全绿） | 不以整包绿为门禁：TASK-02 的新用例落在独立新增文件；cmd-02 用定点 `-run TestBriefSkills` + cmd-03 的源码级存在性断言；两者均不把上游既有红算作本 CR 假红（§5.3） |
| R-9 | 证据命令的**观测面**窄于声称面（尤其 AC-2／AC-3 的 run 期记录） | cmd-05 对 `toolCalls` 做**独立重算**（搜索类调用数／猜测路径访问数）并要求 `toolCalls` 非空（空提取不可判 → 硬失败），另以 `multica agent tasks` 锚定 run 真实存在；运行期记录的采集窗口与来源由 TASK-04 按 SDD §4.4 固定，禁止用静态断言替代（§6.2 表注⑤） |

---

## 5. 验收与发布策略

### 5.0 环境静态前提与即时 readiness

本 CR 有**两个**带环境依赖的验收面（其余证据命令全部为本机一次性进程）：

| 项 | 环境 1：Multica 平台真实 run（AC-2／AC-3／AC-4） | 环境 2：Pi 版本化源码检出与工具链（AC-5～AC-8、AC-12） |
|---|---|---|
| 内容 | 运行中的平台须由**本 CR 的 multica 构建**服务任务（规则文本在任务准备期由 `InjectRuntimeConfig` 写入各 Provider 配置文件，早于任何工具调用），并可按 SDD §4.4 复现三次场景（review-requirement 重放、review-dev-plan 重放、Skill 缺失构造） | `checkoutPath` 上的 pi 源码检出 + `node_modules` + `dist`（`npm ci` + `hydrate-model-data` + `build:offline` 的产物），用于活体复跑 Pi 用例 |
| owner | `owners.development` = **Ray**（部署窗口）；`owners.test` = Ray 只消费记录，不建立环境 | `owners.development` = **Ray** |
| 建立方式 | 由 owner 在部署窗口用本 CR multica worktree 的构建替换运行中的 daemon/CLI（现网实测 `multica --version` = `v0.4.41-469-g947386318, built 2026-09-16`），并按 §4.4 的窗口采集 run 记录；**不写具体命令**（替换动作是运行环境维护，`dep-1` §1.3.2 共用边界 2） | `git clone --branch v0.85.1 --depth 1 <upstreamUrl> <checkoutPath>`；`npm ci`；`npm --prefix packages/ai run hydrate-model-data`；`npm run build:offline`（四条均已在本节点实跑，耗时见 §0.3） |
| 可获得性 | 平台已在本机运行、三仓 worktree healthy；需 owner 的部署窗口建立「跑本 CR 构建」的运行态 | 已就位（`C:\Users\GOBAO\Downloads\AI\pi-mono` @ `d981de12…`，clean）；node 24.15.0 / bun 1.3.14 / 网络可达（`git ls-remote` 实测） |
| **readiness 证据** | **复用 `cmd-05`**（FR-1 那一行的既有证据命令）：证据文件缺席、字段不全、`toolCalls` 空、平台 run 不可判 → 硬失败，即环境未建立的可机械观测面 | **复用 `cmd-06`**（FR-2 那一行的既有证据命令）：检出／`node_modules/vitest/vitest.mjs`／`dist` 任一缺失或用例复跑非零退出 → 硬失败 |
| 缺失时处置 | 按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告**所需建立动作**（该标签的唯一详细事实源是 `implement-code`，本章只引用、不复述细节）；不得用「静态断言 / 单进程冒烟」冒充真实 run | 同左（缺失即硬失败，不得退回「只审记录」） |
| 不适用声明 | 本 CR **不**启停/重启任何共享服务、**不**跑数据库迁移（SDD §2.4 = N/A）、**不**新增可观测性设施 | 本 CR **不**安装／替换 PATH 上的 `pi`（合并后运行环境维护）；**不**修改任何已安装包文件（AC-12 负向） |

### 5.1 发布前 checklist（全部机器可判或逐行可核）

| # | 判据 | 落点 |
|---|---|---|
| 1 | 六条证据命令全绿（`crctl test CR-2026-070 --plan` 机器区 `commands` 1-based 下标 = `cmd-01…cmd-06`，与 `test-evidence/cmd-NN.log` 全等） | `test-report.md` 机器区 |
| 2 | multica diff 白名单**双向相等**（恰 `runtime_config_sections.go` + `runtime_config_test.go` + `CUSTOM.md`，无越界、无缺项） | cmd-04 |
| 3 | tools diff **为空**（zero diff）+ KB diff 全部落在 `change-requests/CR-2026-070/**` 与三个受控账本内，`specs/`／`delivery/`／`docs/`／`dir-graph.yaml`／`prd.md`／`sdd.md` 零写入 | cmd-04 |
| 4 | FR-1 落点面锚短语命中数 = 1、零复制面命中数 = 0、测试文件不内联锚短语、规则窗口无 Provider 私有目录字面量 | cmd-03 |
| 5 | 既有形状钉子测试执行面全绿（7 provider 子用例）+ 新断言引用常量符号 | cmd-02 / cmd-03 |
| 6 | OutputGuard conformance 复跑全绿（`output-guard/**` 零 diff） | cmd-01 / cmd-04 |
| 7 | 三条 FR-1 真实 run 记录齐备且搜索类调用数 = 0、猜测路径访问数 = 0；AC-4 受控文件 run 前后 sha256 逐一致 + 无业务 verdict | cmd-05 |
| 8 | Pi 侧变更文件集全部落在 `packages/coding-agent/{src,test}/**`、无 `dist`／`node_modules`、无安装包路径；用例活体复跑 exit 0 且断言名齐备；安装包 `bash.js` sha256 无漂移 | cmd-06 |
| 9 | 零新增依赖、无迁移目录、无错误码常量、无 metrics 注册（diff 面 + 内容面双查） | cmd-04 / cmd-03 |
| 10 | `crctl next CR-2026-070 --workspace <KB>` 原样返回 `review-code`（或 pipeline 对应下一步），`gateBlockers` 为空 | crctl 只读调用 |

### 5.2 发布与观测

- **本 CR 不新增发布节点、不新增 checkpoint**：阶段终点的发布由 `review-dev-plan` / `review-code` 的 PASS 分支按既有口径执行一次（`push-progress`）；开发期作者 run 不承担发布。上一阶段人工审批提交的发布收口见 §0.2（搭车闭合）。
- **无 feature flag**：默认值是固定常量，`dep-1` §7 第 8 条明示不引入配置文件／环境变量／远程开关 ⇒ 本节不声明 feature-flag 计划。
- **观测面恰两处**：Pi 侧超时错误文本 `Command timed out after <实际生效秒数> seconds` 与 `timeout` 参数的 schema 说明文案（`dep-1` AC-5 的 S-4 核对点）；Multica 侧 `## Skills` 段末尾的规则文本（只读文本，不新增埋点／metrics／UI，I5）。
- **回滚粒度**：单一共享规则（RU1+RU3）与 Pi 固定默认值（RU2），二者都不需要补偿流程。

### 5.3 例外治理与零例外口径

- `tools/skills/shared/crctl/scripts/test/gate-registry.json#exceptions` **保持空数组**，本 CR 不签任何新例外（本 CR 在 tools 仓零 diff）。
- 上游既有红面（Pi `test/tools.test.ts` 4 项 Windows 环境失败；multica `execenv` 整包非全绿）**不登记为本 CR 的例外**：本 CR 不对它们声明「必须整包绿」，而是以独立新增测试文件 + 定点 `-run` + 源码级存在性断言取证（R-8）。
- **安装包 sha256 负向的漂移处置**（cmd-06 的暴露项）：若在 CR 窗口内运行环境合法升级了 `@earendil-works/pi-coding-agent`，`dist/core/tools/bash.js` 的 sha256 会与 §0.4 的基线不同 → cmd-06 硬失败并打印漂移哈希。处置 = 在证据文件内重新基线（记录新版本号与哈希）并说明来源；**不得**为了让命令变绿而忽略或绕过该负向。

### 5.4 预算（证据命令集）与估算

| 证据ID | 预算（本节点实测 / 预期） | 依据 |
|---|---|---|
| cmd-01 | ≤ 30 s（实测 **5.995 s**，38 pass） | §0.4 同款命令基线 |
| cmd-02 | ≤ 60 s（实测 **3.649 s**，含 `go test` 编译；变更后 +新断言预期 ≤ 15 s） | §0.4 实跑 |
| cmd-03 | ≤ 30 s（实测 **0.187 s**，扫描 1492 文件） | §6.3 干跑 |
| cmd-04 | ≤ 60 s（实测 **0.823 s**，含 3 次 `crctl git diff` + 1 次 `workspace inspect`） | §6.3 干跑 |
| cmd-05 | ≤ 60 s（实测 **0.037 s** 于证据缺席态；含平台查询预期 ≤ 20 s） | §6.3 干跑 |
| cmd-06 | ≤ 300 s（实测 **0.469 s** 于证据缺席态；含 vitest 活体复跑预期 ≤ 60 s，探针实测 2 用例 2.7 s） | §6.3 干跑 + §0.4 探针 |
| **合计** | ≤ **540 s**（预期 ≈ **80 s**；< 1200 s，余量 ≥ **600 s**） | `write-test-report` 节点 `timeoutMinutes=20`（1200 s） |

**估算总工时 = 36 h**（= 四张 TASK 卡 `estimate` 之和 = §9 预分配之和；与 `crctl task init --count-hint 4` 的 `totalEstimateHours` 交叉校验，不一致时按 `write-dev-tasks` 的口径输出 WARN 而不静默覆盖本计划）。

---

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 Agent 直接使用 Runtime 已发现的 Skill（AC-1～AC-4） | §2.2.1 形状 1（规则文本常量）＋ §3.2 逐字文本与零复制面 ＋ §3.3 注入面契约（零改动）＋ §4.3 A3 单点合成与唯一性 ＋ §4.4 A4 重放与场景设计 ＋ §6.4 既有测试面增项清单 ＋ §6.5 SDD-CLOSE-01 | CR-2026-070-TASK-01（关联 CR-2026-070-TASK-03：`CUSTOM.md#96` 台账登记；关联 CR-2026-070-TASK-04：AC-2／AC-3／AC-4 的真实 run 记录与独立重算） | cmd-03（落点面单点性 + 零复制面 + 测试面增项）、cmd-02（既有形状钉子测试执行面）、cmd-04（三仓 diff 白名单）、cmd-05（行为验收记录与平台 run 锚定） | RU1 |
| FR-2 Pi 内置 bash 未显式传 timeout 时默认 300 秒（AC-5～AC-8、AC-12） | §2.2.2 形状 2（`DEFAULT_TIMEOUT_MS` 与 schema 文案）＋ §3.1 参数契约与边界值表 ＋ §4.1 A1 解析算法 ＋ §4.2 A2 秒数传递 ＋ §4.6 A6 交付证据取证算法 ＋ §6.4 Pi 侧用例清单 ＋ §6.5 SDD-CLOSE-02 | CR-2026-070-TASK-02（关联 CR-2026-070-TASK-03：台账行原因追溯含 TASK-02；关联 CR-2026-070-TASK-04：交付证据与日志记录） | cmd-06（Pi 侧活体取证：变更文件集 + 用例复跑 + 安装包负向）、cmd-04（三仓 diff 白名单；Pi 侧不属 CR 仓集合，按 §1.3 证据形态） | RU2 |
| FR-3 既有能力的复用合同（AC-9～AC-11） | §1.1 不变量 I1～I8 ＋ §4.5 A5 回归面复跑设计 ＋ §6.4 零改动核对清单 ＋ §9 zero_diff Z-1～Z-8 | CR-2026-070-TASK-01（关联 CR-2026-070-TASK-02、CR-2026-070-TASK-03、CR-2026-070-TASK-04：各自文件面的零改动半边） | cmd-01（OutputGuard conformance 复跑）、cmd-04（三仓 zero_diff 面 + 零新增基础设施的 diff 面）、cmd-03（无第二份规则副本 + 无第二套计时器／错误码的内容面） | RU1 ∪ RU2（零改动面本身无独立回滚单元；回滚即恢复被回滚单元的原状） |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` **三者全等**（CR-2026-057 FR-16）。
② **3 个 in-scope FR 各出现一次**（FR-1／FR-2／FR-3），主责 TASK 唯一（FR-1 → TASK-01、FR-2 → TASK-02、FR-3 → TASK-01）；**四张 TASK 全部在表中出现**（TASK-01／02 为主责，TASK-03／04 为关联），与 `tasks/_index.yml#id` 双向一致；关联 TASK 不改变主责。FR-3 是跨 FR 约束、无独立落点（SDD §6.1），其主责归属两个改动单元中承担零复制面落点者（TASK-01）。
③ **观测面 ≥ 声称面逐条对齐**：`cmd-01` = `dep-14` 的既有 CI 命令（显式 3 文件清单，不依赖目录 glob，目录或文件缺失即非零退出）；`cmd-02` = 既有形状钉子测试的**定点执行面**（`-run TestBriefSkills`），与 `cmd-03` 的源码级存在性断言**必须同批判读**；`cmd-03`／`cmd-04`／`cmd-05`／`cmd-06` 是本次计划自有的只读审计命令（不新增测试文件、不改 `rules.json`、不改 `gate-registry.json`）。
④ **`cmd-02` 的假绿口子双向闭合**：`go test` 在 `-run` 无匹配时仍 **exit 0** 且 stdout 含 `testing: warning: no tests to run`（上游既有形态）⇒ 单靠退出码不构成存在性证据。闭合两道：① `-v` 使日志带 `--- PASS: <测试名>`，`no tests to run` 命中 `write-test-report` 的冻结模式表 ⇒ 机器区 `skipped=true`；② cmd-03 的源码级断言要求 `runtime_config_test.go` 内 `TestBriefSkills` 系列断言计数 ≥ 1 且引用常量符号 `skillsRoutingRule`。**命名约定**：TASK-01 在本 CR 内新增的断言一律放在既有 `TestBriefSkillsListIsNamesOnly` 内或新增 `TestBriefSkills*` 前缀函数（`-run` 只按该单一前缀过滤，不引入正则竖线）。
⑤ **`cmd-05` 的观测面声明**（AC-2／AC-3／AC-4 的判据来源）：这三条 AC 是**行为**验收，判据只能在真实 run 的会话记录上成立（`dep-1` §5 明文：静态断言不能替代）。因此 `fr1-smoke.json` 必须携带**原始 `toolCalls` 提取**（`{name, command}` 数组，非摘要计数），由 cmd-05 对提取**独立重算**搜索类调用数／猜测路径访问数（重算 ≠ 记录的自报值），并以 `multica agent tasks <agentId> --output json` **活体锚定** run 真实存在；`toolCalls` 为空即硬失败（空的提取不可判，禁止「匹配不到 → 静默通过」）。运行期采集窗口、场景构造与观测面由 SDD §4.4 固定，本计划不放宽、不新增可观测性设施。
⑥ **`cmd-03` 的读空硬失败阈值**：零复制面扫描文件数 < 1000 即硬失败（本节点实测 1492 = `server/internal/**` 文本面 + `cr-prompts-revised/**`，排除 `.git`／`node_modules`）；落点文件与测试文件读空（< 1000 字符）即硬失败；`CUSTOM.md` 读空（< 5000 字符）即硬失败——不存在「匹配不到 → 空集 → 静默通过」（工程纪律 1）。
⑦ **`cmd-04` 的三个基线 SHA 与零绝对路径**：tools `c3e7c934…` / multica `59b47993…`（= SDD §6.3 各条 `commit SHA` 登记值）、KB `349ae227…`（= 技术设计人工审批提交）。三仓路径**不拼接**：由 `crctl workspace inspect CR-2026-070` 的 `resources[].worktreePath` 取原样值；全部 Git 访问经 `crctl git` 受控入口（`diff --name-only <sha>`／`rev-parse HEAD` 均在 `rules.json` 白名单内，不新开裸面、不改 `rules.json`）。
⑧ **`cmd-06` 的 repo 列语义**：`repo=tools` 是**证据命令的执行仓**（crctl 与 `workspace inspect` 的入口），不是单元 B 的交付仓——单元 B 的落点在 CR worktree 集合之外（DEC-3），其路径只能从 `<KB>/change-requests/CR-2026-070/evidence/pi-source.json` 的 `checkoutPath` 读取（表内**不含任何跨仓绝对路径**，`dep-1` §1.3 禁止目录名拼接）。Pi 用例的**活体复跑**（`node <checkout>/node_modules/vitest/vitest.mjs run <testFile> --reporter=verbose`）由 cmd-06 内联执行，其退出码与断言名即 AC-5～AC-8 的源码侧观测面；AC-12 的归属判据取 `crctl git diff --name-only <baseCommit> --cwd <checkoutPath>` 的文件集。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | ["--test","--test-reporter=dot","output-guard/test/core.test.mjs","output-guard/test/conformance.test.mjs","output-guard/test/adapters-contract.test.mjs"] | 60 |
| cmd-02 | multica | server | go | ["test","./internal/daemon/execenv/","-count=1","-v","-run","TestBriefSkills"] | 300 |
| cmd-03 | multica | . | node | ["-e","const fs = require('fs'), P = require('path'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const read = (p) => fs.readFileSync(P.join(R, p), 'utf8').split(CRLF).join(NL); const exists = (p) => fs.existsSync(P.join(R, p)); const bad = []; const AN = 'Treat that list as the authoritative entry point for skill selection'; const LAND = 'server/internal/daemon/execenv/runtime_config_sections.go'; const TESTF = 'server/internal/daemon/execenv/runtime_config_test.go'; const CONST = 'skillsRoutingRule'; if (!exists(LAND)) { bad.push('FAIL 缺 ' + LAND); } else { const t = read(LAND); if (t.length < 1000) { bad.push('FAIL ' + LAND + ' 读空或过短 length=' + t.length); } const n = t.split(AN).length - 1; if (n !== 1) { bad.push('FAIL 落点面锚短语命中数 = ' + n + '（期望恰 1）'); } for (const k of ['use the discovered copy directly, before any repository exploration', 'no recursive search for', 'stop the current node and report the missing capability', 'do not produce a business verdict']) { if (t.indexOf(k) < 0) { bad.push('FAIL 落点面缺规则子句 ' + k); } } const i = t.indexOf(AN); const win = i < 0 ? '' : t.slice(Math.max(0, i - 1200), i + 2400); for (const p of ['.pi/skills', '.claude', '.codex', '.qwen', '.multica', 'AGENTS.md', 'CLAUDE.md', 'QWEN.md']) { if (win.indexOf(p) >= 0) { bad.push('FAIL 规则文本窗口出现 Provider 私有面字面量 ' + p); } } if (t.indexOf(CONST) < 0) { bad.push('FAIL 落点面缺常量符号 ' + CONST); } } if (!exists(TESTF)) { bad.push('FAIL 缺 ' + TESTF); } else { const t = read(TESTF); if (t.indexOf(AN) >= 0) { bad.push('FAIL 测试文件内联了锚短语（落点面会扩为 2 文件，违反 SDD 6.4）'); } if (t.indexOf(CONST) < 0) { bad.push('FAIL 测试文件未引用被测常量符号 ' + CONST); } if (t.split('TestBriefSkills').length - 1 < 1) { bad.push('FAIL 测试文件缺 TestBriefSkills 系列断言'); } } let scanned = 0; const hits = []; const walk = (dir) => { if (!fs.existsSync(dir)) { bad.push('FAIL 零复制面目录缺失（硬失败） ' + dir); return; } for (const e of fs.readdirSync(dir, { withFileTypes: true })) { if (['node_modules', '.git'].indexOf(e.name) >= 0) { continue; } const p = P.join(dir, e.name); if (e.isDirectory()) { walk(p); continue; } const dot = e.name.lastIndexOf('.'); const ext = dot < 0 ? '' : e.name.slice(dot); if (['.go', '.md', '.ts', '.tsx', '.json', '.yml', '.yaml', '.txt', '.js', '.mjs'].indexOf(ext) < 0) { continue; } scanned++; const rel = P.relative(R, p).split(P.sep).join('/'); if ([LAND, TESTF].indexOf(rel) >= 0) { continue; } const txt = fs.readFileSync(p, 'utf8').split(CRLF).join(NL); if (txt.indexOf(AN) >= 0) { hits.push(rel); } } }; walk(P.join(R, 'server/internal')); walk(P.join(R, 'cr-prompts-revised')); if (scanned < 1000) { bad.push('FAIL 零复制面扫描文件数 = ' + scanned + '（期望 >1000；读空即硬失败）'); } if (hits.length > 0) { bad.push('FAIL 零复制面锚短语命中数 = ' + hits.length + '：' + hits.slice(0, 5).join(',')); } if (!exists('CUSTOM.md')) { bad.push('FAIL 缺 CUSTOM.md'); } else { const t = read('CUSTOM.md'); if (t.length < 5000) { bad.push('FAIL CUSTOM.md 读空或过短 length=' + t.length); } if (t.indexOf('CR-2026-070') < 0) { bad.push('FAIL CUSTOM.md 缺 CR-2026-070 台账行'); } if (t.indexOf('runtime_config_sections.go') < 0) { bad.push('FAIL CUSTOM.md 台账行未登记落点文件'); } } console.log('audit-multica scanned=' + scanned + ' copyFaceHits=' + hits.length); if (bad.length) { console.log('audit-multica failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-multica failures = 0');"] | 60 |
| cmd-04 | tools | . | node | ["-e","const cp = require('child_process'), fs = require('fs'), P = require('path'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const bad = []; const CRCTL = P.join(R, 'skills/shared/crctl/scripts/crctl.mjs'); const jrun = (args, cwd) => { const r = cp.spawnSync(process.execPath, [CRCTL].concat(args), { cwd, encoding: 'utf8', shell: false }); if (r.status !== 0) { bad.push('FAIL crctl ' + args.join(' ') + ' exit=' + r.status); console.log(String(r.stderr == null ? '' : r.stderr).slice(-300)); return null; } return String(r.stdout == null ? '' : r.stdout).split(CRLF).join(NL); }; const lines = (out) => { const p = out.split(NL); const i = p.findIndex((l) => l.trim() === '{'); return p.slice(0, i < 0 ? p.length : i).map((s) => s.trim()).filter(Boolean); }; const wsRaw = jrun(['workspace', 'inspect', 'CR-2026-070'], R); let ws = null; if (wsRaw !== null) { try { ws = JSON.parse(wsRaw); } catch (e) { bad.push('FAIL workspace inspect 输出不可解析 ' + e.message); } } const pathOf = (id) => { if (!ws) { return null; } if (!Array.isArray(ws.resources)) { return null; } const x = ws.resources.filter((r) => r.repo === id)[0]; return x ? x.worktreePath : null; }; const MUL = pathOf('multica'), KB = pathOf('ai-first-platform-docs'); if (!MUL) { bad.push('FAIL 取不到 multica worktreePath'); } if (!KB) { bad.push('FAIL 取不到 ai-first-platform-docs worktreePath'); } const names = (root, base) => { const out = jrun(['git', 'diff', '--name-only', base, '--cwd', root], R); return out === null ? null : lines(out); }; const T0 = 'c3e7c934ef2636c56cc840543cadb4feb5f554aa'; const M0 = '59b47993810fabd12fcc393c2fa2e46611f9530d'; const K0 = '349ae2271cfa53009dd90bbbb967d11ce98892c9'; const tz = names(R, T0); if (tz === null) { bad.push('FAIL tools diff 不可判'); } else { console.log('tools diff paths = ' + tz.length); for (const f of tz) { console.log('  ' + f); } if (tz.length !== 0) { bad.push('FAIL tools diff 非空 = ' + tz.length + '（AC-9/AC-10 的 zero_diff 面）'); } } const MZ = ['CUSTOM.md', 'server/internal/daemon/execenv/runtime_config_sections.go', 'server/internal/daemon/execenv/runtime_config_test.go']; if (MUL) { const mz = names(MUL, M0); if (mz === null) { bad.push('FAIL multica diff 不可判'); } else { console.log('multica diff paths = ' + mz.length); for (const f of mz) { console.log('  ' + f); } if (mz.length === 0) { bad.push('FAIL multica diff 为空（硬失败：基线或分支不对，不得静默通过）'); } for (const f of mz) { if (MZ.indexOf(f) < 0) { bad.push('FAIL multica diff 越界路径 ' + f); } } for (const f of MZ) { if (mz.indexOf(f) < 0) { bad.push('FAIL multica diff 缺应改文件 ' + f); } } if (mz.length > 3) { bad.push('FAIL multica diff 路径数 = ' + mz.length + '（上界 3）'); } } } if (KB) { const kz = names(KB, K0); if (kz === null) { bad.push('FAIL KB diff 不可判'); } else { console.log('KB diff paths = ' + kz.length); for (const f of kz) { console.log('  ' + f); } const KZ = ['AGENTS.md', 'dir-graph.yaml', 'CONTEXT.md', 'README.md', 'maturity-config.yaml', 'change-requests/CR-2026-070/prd.md', 'change-requests/CR-2026-070/sdd.md']; const KP = ['specs/', 'delivery/', 'docs/']; const ALLOW = ['change-requests/CR-2026-070/', 'change-requests/_backlog.yml', 'change-requests/_history.yml', 'change-requests/_index.yml']; for (const f of kz) { if (KZ.indexOf(f) >= 0) { bad.push('FAIL KB zero_diff 面被写入 ' + f); } for (const z of KP) { if (f.indexOf(z) === 0) { bad.push('FAIL KB zero_diff 前缀面被写入 ' + f); } } let okK = false; for (const a of ALLOW) { if (f.indexOf(a) === 0) { okK = true; } } if (!okK) { bad.push('FAIL KB diff 越界路径 ' + f); } } for (const f of ['change-requests/CR-2026-070/plan.md', 'change-requests/CR-2026-070/tasks/_index.yml', 'change-requests/CR-2026-070/evidence/fr1-smoke.json', 'change-requests/CR-2026-070/evidence/pi-source.json']) { if (kz.indexOf(f) < 0) { bad.push('FAIL KB diff 缺少应交付文件 ' + f); } } } } if (bad.length) { console.log('audit-diff failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-diff failures = 0');"] | 120 |
| cmd-05 | ai-first-platform-docs | . | node | ["-e","const cp = require('child_process'), fs = require('fs'), P = require('path'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const bad = []; const EV = 'change-requests/CR-2026-070/evidence/fr1-smoke.json'; if (!fs.existsSync(P.join(R, EV))) { bad.push('FAIL 缺 FR-1 行为验收证据 ' + EV); } else { const raw = fs.readFileSync(P.join(R, EV), 'utf8').split(CRLF).join(NL); if (raw.length < 500) { bad.push('FAIL fr1-smoke.json 读空或过短 length=' + raw.length); } let d = null; try { d = JSON.parse(raw); } catch (e) { bad.push('FAIL fr1-smoke.json 解析失败 ' + e.message); } if (d) { if (d.schema !== 'cr-2026-070-fr1-smoke/v1') { bad.push('FAIL fr1-smoke.json schema = ' + d.schema); } const runs = Array.isArray(d.runs) ? d.runs : null; const runCount = runs ? runs.length : 0; if (runCount < 3) { bad.push('FAIL fr1-smoke.json runs 缺失或少于 3 条'); } for (const ac of ['AC-2', 'AC-3', 'AC-4']) { const r0 = runs ? runs.filter((x) => x.ac === ac)[0] : null; if (!r0) { bad.push('FAIL 缺 ' + ac + ' 运行记录'); continue; } for (const k of ['scenario', 'agentId', 'runId', 'observedAt', 'provider', 'toolCalls']) { if (r0[k] === undefined) { bad.push('FAIL ' + ac + ' 缺字段 ' + k); } } const tc = Array.isArray(r0.toolCalls) ? r0.toolCalls : []; if (tc.length < 1) { bad.push('FAIL ' + ac + ' toolCalls 为空（取证面不可判，硬失败）'); } let search = 0, guess = 0; for (const c of tc) { const cmd = String(c && c.command == null ? '' : c.command); const fam = ['find ', 'find.exe', 'Get-ChildItem', '-Recurse', 'dir /s', 'rg --files'].some((x) => cmd.indexOf(x) >= 0); if (cmd.indexOf('SKILL.md') >= 0 && fam) { search++; } if (['.pi/agent/skills', '.multica/skills', '.claude/skills', '.claude/agents'].some((x) => cmd.indexOf(x) >= 0)) { guess++; } } if (search !== 0) { bad.push('FAIL ' + ac + ' 内 SKILL.md 搜索类 bash 调用数 = ' + search + '（期望 0）'); } if (guess !== 0) { bad.push('FAIL ' + ac + ' 内猜测私有目录访问数 = ' + guess + '（期望 0）'); } const rr = cp.spawnSync('multica', ['agent', 'tasks', String(r0.agentId), '--output', 'json'], { encoding: 'utf8', shell: false, timeout: 120000 }); const so = String(rr.stdout == null ? '' : rr.stdout).split(CRLF).join(NL); if (rr.status !== 0) { bad.push('FAIL multica agent tasks ' + r0.agentId + ' exit=' + rr.status + '（平台 run 记录不可判）'); } else if (so.indexOf(String(r0.runId)) < 0) { bad.push('FAIL 平台 run 列表未见 ' + ac + ' 的 runId ' + r0.runId + '（记录与平台不一致）'); } else { console.log(ac + ' run ' + r0.runId + ' 平台可见'); } } const ac4 = runs ? runs.filter((x) => x.ac === 'AC-4')[0] : null; if (ac4) { if (ac4.businessVerdictWritten !== false) { bad.push('FAIL AC-4 businessVerdictWritten 必须为 false'); } if (ac4.missingCapabilityReported !== true) { bad.push('FAIL AC-4 missingCapabilityReported 必须为 true'); } const cf = ac4.controlledFiles && typeof ac4.controlledFiles === 'object' ? ac4.controlledFiles : null; if (!cf) { bad.push('FAIL AC-4 缺 controlledFiles'); } else { const ks = Object.keys(cf); if (ks.length < 4) { bad.push('FAIL AC-4 controlledFiles 少于 4 条'); } for (const k of ks) { const v = cf[k] ? cf[k] : {}; const hasB = v.beforeSha256 ? 1 : 0, hasA = v.afterSha256 ? 1 : 0; if (hasB + hasA < 2) { bad.push('FAIL AC-4 controlledFiles ' + k + ' 缺 before/after sha256'); } else if (v.beforeSha256 !== v.afterSha256) { bad.push('FAIL AC-4 controlledFiles ' + k + ' run 前后 sha256 不一致（run 期有写入）'); } } } } } } if (bad.length) { console.log('audit-fr1-smoke failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-fr1-smoke failures = 0');"] | 120 |
| cmd-06 | tools | . | node | ["-e","const cp = require('child_process'), fs = require('fs'), P = require('path'), crypto = require('crypto'); const R = process.cwd(), NL = String.fromCharCode(10), CRLF = String.fromCharCode(13, 10); const bad = []; const CRCTL = P.join(R, 'skills/shared/crctl/scripts/crctl.mjs'); const jrun = (args, cwd) => { const r = cp.spawnSync(process.execPath, [CRCTL].concat(args), { cwd, encoding: 'utf8', shell: false, timeout: 120000 }); if (r.status !== 0) { bad.push('FAIL crctl ' + args.join(' ') + ' exit=' + r.status); console.log(String(r.stderr == null ? '' : r.stderr).slice(-300)); return null; } return String(r.stdout == null ? '' : r.stdout).split(CRLF).join(NL); }; const lines = (out) => { const p = out.split(NL); const i = p.findIndex((l) => l.trim() === '{'); return p.slice(0, i < 0 ? p.length : i).map((s) => s.trim()).filter(Boolean); }; const wsRaw = jrun(['workspace', 'inspect', 'CR-2026-070'], R); let ws = null; if (wsRaw !== null) { try { ws = JSON.parse(wsRaw); } catch (e) { bad.push('FAIL workspace inspect 输出不可解析 ' + e.message); } } const pathOf = (id) => { if (!ws) { return null; } if (!Array.isArray(ws.resources)) { return null; } const x = ws.resources.filter((r) => r.repo === id)[0]; return x ? x.worktreePath : null; }; const KB = pathOf('ai-first-platform-docs'); if (!KB) { bad.push('FAIL 取不到 KB worktreePath（Pi 侧证据不可判）'); } const EV = KB ? P.join(KB, 'change-requests/CR-2026-070/evidence/pi-source.json') : null; let ev = null; if (EV === null) { bad.push('FAIL 缺 KB worktreePath，Pi 侧交付证据不可判'); } else if (!fs.existsSync(EV)) { bad.push('FAIL 缺 Pi 侧交付证据 ' + EV); } else { const raw = fs.readFileSync(EV, 'utf8').split(CRLF).join(NL); if (raw.length < 300) { bad.push('FAIL pi-source.json 读空或过短 length=' + raw.length); } try { ev = JSON.parse(raw); } catch (e) { bad.push('FAIL pi-source.json 解析失败 ' + e.message); } } if (ev) { for (const k of ['schema', 'upstreamUrl', 'baseCommit', 'checkoutPath', 'branch', 'headCommit', 'changedFiles', 'testFile', 'testLogPath', 'testLogSha256', 'buildCommand', 'artifactVersion', 'installedPackage']) { if (ev[k] === undefined) { bad.push('FAIL pi-source.json 缺字段 ' + k); } } if (ev.schema !== 'cr-2026-070-pi-source/v1') { bad.push('FAIL pi-source.json schema = ' + ev.schema); } if (ev.baseCommit !== 'd981de1229ef899957bbe968bc8dcda02a21f477') { bad.push('FAIL baseCommit 未钉在 v0.85.1 tag SHA：' + ev.baseCommit); } const CO = ev.checkoutPath; const coOk = CO ? fs.existsSync(CO) : false; if (!coOk) { bad.push('FAIL Pi 源码检出不存在（ENVIRONMENT_MISMATCH：需先按 TASK-02 建立检出）' + CO); } else { const hv = jrun(['git', 'rev-parse', 'HEAD', '--cwd', CO], R); const head = lines(hv === null ? '' : hv); if (head[0] !== ev.headCommit) { bad.push('FAIL checkout HEAD = ' + head[0] + ' != 记录的 headCommit ' + ev.headCommit); } const fv = jrun(['git', 'diff', '--name-only', String(ev.baseCommit), '--cwd', CO], R); const files = lines(fv === null ? '' : fv); const rec = (Array.isArray(ev.changedFiles) ? ev.changedFiles : []).slice().sort(); const act = files.slice().sort(); if (JSON.stringify(rec) !== JSON.stringify(act)) { bad.push('FAIL 变更文件集不一致 rec=' + JSON.stringify(rec) + ' act=' + JSON.stringify(act)); } if (act.length < 1) { bad.push('FAIL 变更文件集为空（硬失败）'); } for (const f of act) { const inFace = (f.indexOf('packages/coding-agent/src/') === 0) ? true : (f.indexOf('packages/coding-agent/test/') === 0); if (!inFace) { bad.push('FAIL 变更文件越出 AC-12 面（仅版本化源码与其测试）：' + f); } const artefact = (f.indexOf('dist') >= 0) ? true : (f.indexOf('node_modules') >= 0); if (artefact) { bad.push('FAIL 变更文件含构建产物或依赖目录：' + f); } } const VITEST = P.join(CO, 'node_modules', 'vitest', 'vitest.mjs'); if (!fs.existsSync(VITEST)) { bad.push('FAIL 缺 vitest（ENVIRONMENT_MISMATCH：检出未 npm ci）' + VITEST); } else { const r2 = cp.spawnSync(process.execPath, [VITEST, 'run', String(ev.testFile), '--reporter=verbose'], { cwd: P.join(CO, 'packages', 'coding-agent'), encoding: 'utf8', shell: false, timeout: 900000 }); const so = String(r2.stdout == null ? '' : r2.stdout).split(CRLF).join(NL); const se = String(r2.stderr == null ? '' : r2.stderr).split(CRLF).join(NL); console.log('pi-side vitest exit=' + r2.status); console.log(so.slice(-1500)); if (r2.status !== 0) { bad.push('FAIL Pi 侧用例活体复跑 exit=' + r2.status + ' stderr=' + se.slice(-300)); } for (const k of ['300 second default', 'reports 300 seconds and kills the process tree', 'explicit timeout 1200 is not overridden', 'keeps existing errors before spawn', 'schema description matches the default']) { if (so.indexOf(k) < 0) { bad.push('FAIL Pi 侧用例输出缺断言名 ' + k); } } } } const LG = ev.testLogPath; const LGA = LG && fs.existsSync(LG) ? LG : (KB ? P.join(KB, String(LG)) : null); const lgOk = LGA ? fs.existsSync(LGA) : false; if (!lgOk) { bad.push('FAIL 缺 Pi 侧测试日志 ' + LG); } else { const t = fs.readFileSync(LGA); if (t.length < 200) { bad.push('FAIL Pi 侧测试日志读空或过短 length=' + t.length); } const h = crypto.createHash('sha256').update(t).digest('hex'); if (h !== ev.testLogSha256) { bad.push('FAIL Pi 侧测试日志 sha256 漂移 ' + h); } } const IP = ev.installedPackage ? ev.installedPackage.path : null; const ipOk = IP ? fs.existsSync(IP) : false; if (!ipOk) { bad.push('FAIL 记录的已安装包路径不存在 ' + IP); } else { const f = P.join(IP, 'dist', 'core', 'tools', 'bash.js'); if (!fs.existsSync(f)) { bad.push('FAIL 已安装包缺 dist/core/tools/bash.js'); } else { const t = fs.readFileSync(f, 'utf8').split(CRLF).join(NL); const h = crypto.createHash('sha256').update(t).digest('hex'); if (h !== ev.installedPackage.bashJsSha256) { bad.push('FAIL 已安装包 dist/core/tools/bash.js sha256 漂移（可能被就地修改，AC-12 负向）：' + h); } if (t.indexOf('no default timeout') < 0) { bad.push('FAIL 已安装包不再声明 no default timeout（本 CR 不得以安装包为改动载体；若环境已升级请按 plan 5.3 重新基线）'); } } } } if (bad.length) { console.log('audit-pi-source failures = ' + bad.length); for (const x of bad) { console.log(x); } process.exit(1); } console.log('audit-pi-source failures = 0');"] | 600 |

### 6.2.1 转录纪律（`write-test-report` Step 3 的唯一输入）

`args` 列是**字面 JSON token 数组**，由 `write-test-report` 逐字转录进 `.crctl/tmp/test-plan.json` 的 `commands[].args`，`crctl test` 以 `spawnSync(executable, args, {shell:false})` 执行——**表内 cell 即字面值**，无第二生成步骤、不依赖任何临时脚本文件、不得在实现期改写或补写命令算法。脚本体制约束（本表四条 `-e` 命令逐字满足）：单行、无裸双引号（字符串一律单引号）、无反引号、无反斜杠、无竖线（需竖线语义时以 `String.fromCharCode` 构造）、无换行（多行语义以 `String.fromCharCode(10)` 构造）。

### 6.3 干跑/可达性记录（按 §6.2 表内字面命令实跑；只读，未改任何被审文件）

| 证据ID | 可达性 | 本条 run 实测（变更前基线） | 结论（变更后预期） |
|---|---|---|---|
| cmd-01 | 可达 | **exit 0** / 5.995 s / 38 pass（三文件） | 变更前后均须 exit 0（本 CR 在 tools 仓零 diff） |
| cmd-02 | 可达 | **exit 0** / 3.649 s / `--- PASS: TestBriefSkillsListIsNamesOnly`（7 provider 子用例）——与本条审计面同批 | 变更后须仍 exit 0 且包含新增断言（`cmd-03` 提供源码级存在性守卫） |
| cmd-03 | 可达 | **exit 1 / 8 failures**：规则四子句缺失 4 项、缺常量符号 `skillsRoutingRule` 1 项、测试文件未引用常量 1 项、`CUSTOM.md` 缺 CR-2026-070 台账行 1 项；`scanned=1492 copyFaceHits=0`（零复制面本已干净，**无一项来自 zero_diff 面**） | 变更后须 failures = 0（八项逐条对应 TASK-01 的 4 个交付面与 TASK-03 的台账面） |
| cmd-04 | 可达 | **exit 1 / 8 failures**：tools diff 0 路径（正确，zero diff 面）+ multica diff 0 路径 ⇒ 应改文件缺失 3 项 + KB 应交付文件缺失 4 项 + KB diff 为空（基线 = 当前 HEAD，故 0 路径符合预期） | 变更后须 failures = 0（multica 白名单双向相等 + KB 交付面齐备 + tools 零 diff + zero_diff 前缀面零命中） |
| cmd-05 | 可达 | **exit 1 / 1 failure**（`evidence/fr1-smoke.json` 未落地；本节点无该证据文件，属**显式红**而非假绿） | 变更后须 failures = 0（三条 run 记录 + 独立重算零命中 + 平台 run 活体锚定） |
| cmd-06 | 可达 | **exit 1 / 1 failure**（`evidence/pi-source.json` 未落地）；**Pi 侧基础设施本节点已实跑就位**：clone 21.5 s、`npm ci` 2 m 14 s、hydrate 4.9 s、`build:offline` 9.7 s、探针复跑 2.7 s | 变更后须 failures = 0（变更文件集 + 用例复跑 + 日志 sha256 + 安装包负向） |

> 干跑纪律：四条 `-e` 审计命令均已按**表内字面 args**（`spawnSync(process.execPath, args, {shell:false})` 同语义）实跑并留下变更前基线；所有读入先 `\r\n → \n` 归一，读空／过短／解析失败／`crctl` 非零退出**均硬失败**，不存在「匹配不到 → 空集 → 静默通过」的降级路径（工程纪律 1）。

---

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 规则只增一处、零复制面命中 0 | §3.2 文本契约 + §4.3 唯一性论证 + §6.4 零改动清单 | CR-2026-070-TASK-01（关联 CR-2026-070-TASK-03） | cmd-03；cmd-02；cmd-04 |
| AC-2 重放 review-requirement 场景无 `SKILL.md` 搜索调用 | §3.2／§3.3（规则在场）+ §4.4 A4 | CR-2026-070-TASK-04（关联 CR-2026-070-TASK-01） | cmd-05 |
| AC-3 重放 review-dev-plan 场景无根目录／HOME 递归检索 | §3.2／§3.3 + §4.4 A4 | CR-2026-070-TASK-04（关联 CR-2026-070-TASK-01） | cmd-05 |
| AC-4 Skill 缺失时技术中止、零账本写入、零兜底搜索 | §3.2 第 4 子句 + §4.4 场景构造（依赖 B-1 边界） | CR-2026-070-TASK-04（关联 CR-2026-070-TASK-01） | cmd-05 |
| AC-5 未传 timeout 用 300 秒默认值 + schema 文案一致 | §4.1 A1 + §2.2.2 | CR-2026-070-TASK-02 | cmd-06 |
| AC-6 超时后 `killProcessTree()` 清理父与后代、daemon 不受影响 | §4.1 第 2 条 + 既有 `killProcessTree` 调用 | CR-2026-070-TASK-02 | cmd-06 |
| AC-7 显式 `timeout: 1200` 原样生效、不被默认值覆盖 | §3.1 档 3 | CR-2026-070-TASK-02 | cmd-06 |
| AC-8 非法值／超上限／AbortSignal 与既有错误文本无回归 | §3.1 档 1／2 + signal 分支 | CR-2026-070-TASK-02 | cmd-06 |
| AC-9 OutputGuard conformance 全绿 + `core.mjs`／`policy.json`／`capabilities.json`／compound passthrough 零改动 | §4.5 A5 + §6.4 零改动清单 | CR-2026-070-TASK-01（关联 CR-2026-070-TASK-02） | cmd-01；cmd-04 |
| AC-10 Pipeline／四类 `review-*`／crctl／状态机／受控账本／转换脚本／审批合同零业务 diff | §9 zero_diff Z-5～Z-8 + §6.4 | CR-2026-070-TASK-01（关联 CR-2026-070-TASK-02、CR-2026-070-TASK-03） | cmd-04；cmd-03 |
| AC-11 未新增依赖／数据库／sidecar／metrics／错误码／状态／事务框架 | §1.2 变更面 + §2.1 | CR-2026-070-TASK-01（关联 CR-2026-070-TASK-02） | cmd-04；cmd-03 |
| AC-12 Pi 侧改动只出现在版本化源码与其测试、安装包 `dist` 零出现 | §1.3 证据形态 + §4.6 A6 + §6.4 | CR-2026-070-TASK-02（关联 CR-2026-070-TASK-04） | cmd-06；cmd-04 |

**矩阵表注**：每条关键 AC（AC-1～AC-8、AC-12）均有**唯一** TASK owner 且「验收证据」列为稳定标识 `cmd-NN`；AC-9～AC-11 是零改动／零新增约束，其 owner 归属承担对应 diff 面的落点单元（TASK-01），关联 TASK 覆盖各自文件面的零改动半边。AC-12 的「不要求验证运行环境已升级」按 `dep-1` AC-12 明文执行（判据只看交付 diff 的文件集合归属）。

---

## 8. 本计划不得越界（`zero_diff` 与本 CR 边界，逐条生效）

| 编号 | 对象 | 本计划对应保证 |
|---|---|---|
| Z-1 | `dep-7` 的 `writeContextFiles`／`resolveSkillsDir`／`skillsDirPath`／`writeSkillFiles` | cmd-04 的 multica 白名单不含这些文件（越界即红） |
| Z-2 | `dep-6` 的 `modelVisibleSkills`／`resolveSkillSlugs`／`skillModelInvocationVisible` | 同上（`skill_visibility.go` 零 diff） |
| Z-3 | Pi 侧 `BashOperations` 接口签名与「工具入参 → `ops.exec`」传参 | TASK-02 的改动只落在 `resolveTimeoutMs` 与 schema 文案；`operations` 面零改动（B-2），cmd-06 的变更文件集为单一源码文件 + 单一测试文件 |
| Z-4 | Pi 侧 `killProcessTree`／AbortSignal 分支／`MAX_TIMEOUT_MS` 上限与档 1／2 错误文本 | TASK-02 §3「不改动清单」+ cmd-06 的用例面（档 1／2／abort 逐字断言） |
| Z-5 | `dep-10` 全部路径 + `dep-13`（落点外文件） | cmd-04（tools diff 必空、KB `docs/`／`specs/`／`delivery/` 零写）；cmd-03（零复制面命中 0） |
| Z-6 | `dep-14`（`output-guard/**` 与 CI 触发/步骤） | cmd-01（既有命令复跑）+ cmd-04（tools 零 diff） |
| Z-7 | `dep-11`（KB `dir-graph.yaml`）、`dep-1`／`dep-2`、`specs/`、`delivery/`、受控账本、`## Skills` 段形状 | cmd-04 的 KB zero_diff 清单；`## Skills` 段形状由 cmd-02 的既有钉子测试钉住 |
| Z-8 | `dep-3` §5 的生成物（sqlc/governance） | 本 CR 不触碰 multica 生成物（cmd-04 白名单不含生成物路径） |

**流程控制 TASK 禁令**（CR-2026-057 FR-10）：四张 TASK 的标题、正文与完成标志均不含 `merge`／`writeback`／`archive` 或 `code-reviewing`／`code-approved` 前置；全部完成边界均为 `developing` 内可被 `crctl task done` 登记的事件（§2.1）。

---

## 9. TASK 拆分预分配（`write-dev-tasks` 的输入，共 4 个，组映射 1:1）

| TASK | 变更组 | 标题 | estimate | depends-on | 落点文件 |
|---|---|---|---|---|---|
| CR-2026-070-TASK-01 | G1 单元 A（FR-1） | FR-1 单点规则文本：`writeSkills` 追加常量 + 既有形状钉子测试增项 | 6h | `[]` | multica：`server/internal/daemon/execenv/runtime_config_sections.go`、`server/internal/daemon/execenv/runtime_config_test.go` |
| CR-2026-070-TASK-02 | G2 单元 B（FR-2） | Pi bash 默认 300 秒：解析点默认值 + 生效秒数传递 + schema 文案 + 既有测试框架内新增用例与本地构建 | 16h | `[]` | Pi 检出：`packages/coding-agent/src/core/tools/bash.ts`、`packages/coding-agent/test/bash-default-timeout.test.ts`；KB：`change-requests/CR-2026-070/evidence/pi-vitest.log`（本 TASK 自身的用例执行原文） |
| CR-2026-070-TASK-03 | G3 治理登记 | `CUSTOM.md#96` 台账行（原因追溯含 CR-2026-070 与 TASK-01／TASK-02） | 2h | `[CR-2026-070-TASK-01, CR-2026-070-TASK-02]` | multica：`CUSTOM.md` |
| CR-2026-070-TASK-04 | G4 过程产物与验收记录 | FR-1 真实 run 记录 + Pi 侧交付证据记录（cmd-05／cmd-06 的取证面） | 12h | `[CR-2026-070-TASK-01, CR-2026-070-TASK-02]` | KB：`change-requests/CR-2026-070/evidence/fr1-smoke.json`、`change-requests/CR-2026-070/evidence/pi-source.json` |

组映射核对：G1↔TASK-01、G2↔TASK-02、G3↔TASK-03、G4↔TASK-04，每个变更组恰一个 TASK、每个 TASK 恰属一组；合计 **36 h**。

---

## 10. Pi 侧交付路线决策（SDD-CLOSE-03 的关闭动作：本阶段选定）

**选定路线 = R-C（版本化源码本地构建），检出钉定在上游 tag `v0.85.1`。**

| 项 | 结论 | 依据（本节点实测） |
|---|---|---|
| 上游与基线 | `https://github.com/earendil-works/pi-mono`，基线 `d981de1229ef899957bbe968bc8dcda02a21f477`（tag `v0.85.1`，与本机已安装 0.85.1 同版本线） | `git ls-remote --tags` 实测；clone 21.5 s |
| 产出方 | **本团队构建产物**（本地检出 + `npm run build:offline`），版本随检出分支的 `packages/coding-agent/package.json` 版本号 | `dep-1` §1.3.2 路线表 R-C 行 |
| 升级动作时点 | **CR 合并之后**，属运行环境维护（替换 PATH 上的 `pi` 可执行文件）；不进 CR 交付 diff | `dep-1` §1.3.2 共用边界 2 |
| 交付证据形态 | 检出 URL + 基线 SHA + 分支/HEAD commit + 变更文件清单 + 用例执行日志（`evidence/pi-source.json` + `evidence/pi-vitest.log`） | SDD §1.3／§4.6 |
| R-A（自建 fork + 本团队发布） | **否决（当前不可执行）**：`npm whoami` 实测 `ENEEDAUTH`（无 registry 登录），本机无 `gh` CLI、环境无 GitHub 写凭据 ⇒「本团队可控位置发布」的两个前置（建仓/推送权 + 发布凭据）都不具备 | §0.4 实测 |
| R-B（向上游提 PR 等上游发版） | **否决（不作为本 CR 路线）**：同样缺 fork/推送凭据，且上游接受与发版时点不受本团队控制，会把 AC-5～AC-8 的运行环境侧验证无限期顺延（SDD R-4）；`dep-1` §7 第 14 条亦明示不含「向上游提 PR 的结果保障」 | SDD R-4、`dep-1` §7 第 14 条 |
| 是否纳入 CR worktree 集合 | **否**（DEC-3）：`dir-graph.yaml#repositories` 本 CR 零 diff（Z-7）；若日后需要 checkpoint/对账覆盖 Pi 改动，走既有仓库声明变更流程（`follow_up` F-2，属后续 CR） | SDD DEC-3／F-2 |
| 后续可选 | 检出分支日后可作为 fork/PR 的推送源（不改本 CR 的任何设计与判据） | SDD §1.3 证据形态的路线无关性 |

**S-6 取舍（评审 suggestion，非阻塞）**：`resolveTimeoutMs` 是模块私有符号（`bash.ts` L25 无 `export`，`dist/core/tools/bash.d.ts` 零命中），因此 AC-5 的判据 ① 采用「**从工具入口取证**」而非「显式导出该函数」：

- 断言走公开入口 `createBashTool(cwd)`（本地执行路径）与 `createBashToolDefinition(cwd)`（schema 面），**不导出** `resolveTimeoutMs`——避免改动模块公开面与其 `.d.ts` 构建产物（超出本 CR 批准范围；`dep-1` §9 Z-3 的边界精神）；
- 本节点已用探针实测该取证的机械可行性（§0.4）：未传 timeout 时捕获集为空（缺陷本体）、显式 `timeout: 300` 捕获 `[300000]`、触达后文本为 `Command timed out after 300 seconds` ⇒ 默认值生效后「未传」与「传 300」走同一分支、同一文本（`dep-1` §1.3.3 的等价性口径）。

---

## 11. 修订记录

| 版本 | 时间 | 作者 | 说明 |
|---|---|---|---|
| 0.1 | 2026-09-18 | dev-agent | 初稿：按 SDD v0.2（`00a3f727…`）出具开发计划；4 个变更组 → 4 张 TASK；两张稳定表（3 条 FR 行 + 6 条证据命令）；AC 覆盖矩阵 12 行；§10 选定 Pi 侧路线 R-C 并记录 R-A／R-B 的否决依据；S-6 取舍（工具入口取证、不导出模块私有符号）并附探针实测；§0.2 记录上一阶段审批提交的发布收口口径（搭车 review-dev-plan 的 checkpoint） |
