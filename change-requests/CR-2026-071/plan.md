---
id: CR-2026-071-plan
type: PLAN
cr-ref: CR-2026-071
sdd-ref: "change-requests/CR-2026-071/sdd.md"
target-version: 0.44
status: draft
created: 2026-09-27T16:37:21+08:00
updated: 2026-09-27T22:10:00+08:00
---

# CR-2026-071 开发计划

来源：`prd.md`（FR-1～FR-4，AC-1～AC-6）与 `sdd.md`（§4.1～§4.4，dep-1～dep-7）。
目标版本 0.44 自 `cr.md` 继承。AIFI-35 / CR-2026-001 只读，不触发其 reviewer，不改其账本。

## 1. 交付里程碑

- **M1 — multica 判定修复与合同回归编写（0.5 人天）**：§4.1 四份提示词全文替换 + `delegation-contract.md` 新建 + §4.3 回归脚本三组断言；合同↔四份提示词↔平台枚举自洽子集绿灯（bak 集合不断言全绿，见 §2 B-01 说明）。对应 TASK-01、TASK-03。
- **M2 — tools checkpoint 节点恢复（0.5 人天）**：§4.4 `...0003` 节点恢复 + `_index.yml` nodes 5→6 + `pipeline-structure.test.mjs` 断言同步；结构测试全绿。对应 TASK-02。
- **M3 — bak 审计与线上同步（0.5 人天）**：§4.1 bak 审计（保留/排除理由落盘）+ §4.2 四个线上 Agent 同源同步 + 逐个 `agent get` 核验；以 TASK-03 合同源**文本**为输入（不以其 cmd-01 全绿为前置）；bak 修正完成后 cmd-01 含 bak 集合全绿为本里程碑完成门禁。对应 TASK-04。
- **M4 — 全量验证与交付记录（0.5 人天）**：cmd-01～cmd-13 全绿 + 线上核验原文留存 + AIFI-35 六证据零变化核验（Issue 三证据 cmd-08/cmd-09/cmd-10 ∧ 文件账本三证据 cmd-11/cmd-12/cmd-13，合取） + 交付记录。发布（`crctl checkpoint` / `push-progress`）由 `review-dev-plan` PASS 分支承接，不在本里程碑及 TASK-05 完成条件内（B-03）。对应 TASK-05。

估算总工时：2 人天。顺序 M1 → M2 → M3 → M4；M1 与 M2 无代码依赖可并行，但同属一人执行故串行。

## 2. 任务依赖图

```text
TASK-01 (multica 四份提示词 §4.1)
  ├─► TASK-03 (合同源 + 回归 §4.3, 消费 TASK-01 的替换文本；完成条件为文件落盘 + 自洽子集绿灯，
  │     bak 集合全绿不是其完成条件，见 B-01)
  └─► TASK-04 (bak 审计 + 线上同步 §4.1/§4.2, 消费 TASK-01 文本与 TASK-03 合同源文本；
        不以 TASK-03 的 cmd-01 全绿为前置；本 TASK 修正 bak 后 cmd-01 含 bak 全绿为其完成门禁)
TASK-02 (tools ...0003 + index + 结构测试 §4.4, 独立可并行)
  └─► TASK-05 (全量验证 + 交付, 依赖 TASK-03/TASK-04/TASK-02 全部完成；复验 cmd-01～cmd-10 全绿)
```

B-01（首评 BLOCK 回修）：旧依赖把 TASK-03 完成条件写成"cmd-01 全绿（含 bak 集合）"而 TASK-04 又依赖 TASK-03 绿灯，但 bak 漂移只能由 TASK-04 修复——死锁。现拆开"合同测试编写"与"最终全绿验证"：全绿门禁落在 TASK-04（含 bak 修正后）与 TASK-05（最终复验），TASK-03 只对自洽子集负责。

跨仓依赖仅在 M4 会合；multica 与 tools 无共享代码依赖（SDD §1）。

## 3. 资源与分工

- 执行人：dev-agent（设计期与开发期责任）；owner 三角色均为 Ray，仅人工审批与线上指令 owner 确认由 Ray 执行。
- 工时分配：M1 0.5（含 dep-1～dep-4 取证复核）、M2 0.5（含 dep-5～dep-7 基线复核）、M3 0.5（更新前快照 4 次 + 4 次 `agent update` + cmd-01/cmd-04～cmd-07 核验）、M4 0.5（10 条证据命令 + 交付记录）。
- 工具：`crctl checkpoint`（发布）、`node --test`（回归/结构）、`multica agent update/get`（线上同步核验）。

## 4. 风险与回滚策略

- **R1 平台枚举未来新增 status**：合同回归枚举对齐断言变红。回滚（文件侧）：经受控入口 `crctl git revert --no-edit <TASK-03 commit>`（禁止原生 git），下游 TASK-04（含线上同步）一并回滚；顺序 TASK-04 线上先回滚（见 R2）→ TASK-04 文件侧 → TASK-03（逆拓扑）。
- **R2 线上指令更新部分失败**：某 Agent `agent get` 与合同不一致。B-04（首评 BLOCK 回修；复评 BLOCK 2/3 深化）：`git revert` 只恢复仓库文件提交，**不能**恢复已 `multica agent update` 的线上运行时 instructions，故线上回滚不用 revert，必须走以下在线回滚步骤。本条已消费复评实测事实：当前 dev-agent（`ff6fcbb6…`）、cr-coordinator-agent（`87ca2271…`）线上 instructions 仍含 `enqueued` 成功语义——此刻抓取的"更新前快照"即为错误版本，快照≠安全回滚目标：
  1. 快照前置（审计/取证用，不默认等于恢复源）：TASK-04 更新任一线上 Agent 之前，先 `multica agent get <id> --output json` 取其更新前 instructions 全文，落盘为 `change-requests/CR-2026-071/agent-snapshots/<agent>-before.json`（4 个文件，随 TASK-04 文件侧改动同批受控提交）。
  2. 回滚目标分级（操作与验收判据一致性核心）：首选安全目标为**修复后已验证的合同正文**（SDD §4.1 / TASK-03 `delegation-contract.md`），即若 TASK-04 本次更新引入漂移，向前恢复到合同正文（`multica agent update <id>` 写入合同判定段落）再按 cmd-04～cmd-07 重验（须含规范三元组、无 `enqueued` 成功语义、无 `target_unavailable` status 语义），通过方可继续。快照仅在其**自身已通过同一清洁判据**（以快照文本按 cmd-04～cmd-07 判据离线比对）时才可用作恢复源。
  3. 错误版本恢复即故障中止：若唯一可用快照本身含 `enqueued` 成功语义（当前两份线上指令即属此类），将其写回即重现故障，**定义为故障中止而非恢复**：立即停止，不得进入 TASK-05；隔离措施为停止使用受影响 Agent 承担进一步委派验证（后续验证只读、不再向其发更新），在交付记录中标明受影响 Agent 名与漂移段落；责任 dev-agent 执行、Ray（Agent owner）确认处置；验收判据为中止记录 + `status`/`reason_code` 两侧事实报告（预期清洁 vs 实际含 `enqueued`），**不得**声称重验绿灯。部分漂移未消除前不得重做同步；不触碰 TASK-01/TASK-03 文件侧（上游保留）。
  4. 文件侧回滚经受控 `crctl git revert --no-edit <commit>`（禁止原生 git），且文件侧 revert 永不触碰线上 instructions（两侧回滚通道正交）。完整命令与判据见 TASK-04 §3/§4，回滚顺序见本节末。
- **R3 结构测试基线误改**：`pipeline-structure.test.mjs` 断言与 JSON 不一致。回滚：经受控入口 `crctl git revert --no-edit <TASK-02 commit>`（节点 + index + 测试同属一个回滚单元）。
- **R4 bak 排除副本被误部署**：排除理由未留痕。回滚：经受控入口 revert TASK-04 的 bak 部分；下游无消费者，单点 revert 安全。
- **R5 共享改动回滚牵连**：TASK-03 合同源被 TASK-01/TASK-04 消费，其回滚单元含下游 TASK-04；单点 revert TASK-03 而保留 TASK-04 会造成提示词与合同不一致，故禁止单点回滚，必须连带 TASK-04（文件侧 + 线上侧按 R2 回滚）。

回滚顺序（逆拓扑）：TASK-05（验证记录，无代码）→ TASK-04（线上侧按 R2 先行，文件侧随后）→ TASK-03 → TASK-01；TASK-02 独立分支单独 revert。文件侧一律经受控 `crctl git revert`，禁止原生 git。

## 5. 验收与发布策略

发布前 checklist：cmd-01～cmd-13 全绿（判据见下；其中 cmd-11～cmd-13 的"绿"指 §6 机械判定通过——回执绿 ∧ 正文零差异 + 同次阳性对照，**不是** raw stdout 为空）；四份 `agent get` 成品与合同逐字一致（cmd-04～cmd-07 输出留存交付记录）；AIFI-35 零触发零改动六证据合取——Issue 可观测面 cmd-08（新根零新增）∧ cmd-09（逐线程尾零新增 verdict/零新 reviewer run）∧ cmd-10（Issue 对象与基线一致），文件账本面 cmd-11（CR-2026-001 目录零文件变更）∧ cmd-12（`_backlog.yml` 无 CR-2026-001 行变更）∧ cmd-13（`_history.yml`/`_index.yml` 零变更），任一变化即失败；feature-flag 不适用（提示词与 Pipeline JSON 即时生效，无灰度开关）。范围声明（B-02 cycle-2 回修）：三仓远端均无 `requirement/CR-2026-001` live 分支（本轮 `git ls-remote --heads origin` 实测：KB 仅 master + CR-2026-071；multica 仅 main + CR-2026-071；tools 仅 main + agent 分支 + CR-2026-071），故无 CR-2026-001 live 工作区可比对；文件账本零 diff 锚定为"本 CR 分支 vs trunk 合并基点"（KB 以 `merge-base origin/master HEAD` 为 BASE，实测 `9ce4cde5…`），语义是"本 CR 未改动 CR-2026-001 文件与账本条目"——正是 SDD AC-6/§9 zero_diff 对本 CR 的要求，不是"CR-2026-001 自身历史无变化"；multica/tools 两仓无 CR-2026-001 路径，其改动集由各 TASK 文件侧范围核验（本 §6 标准）锁定为 SDD §4 声明集，不另立无路径可锚定的假证据命令。基线捕获与比对程序见 §6 证据命令表注与 TASK-05 §3。

B-03（首评 BLOCK 回修）：`crctl checkpoint`（`push-progress` 深原语）发布是 `review-dev-plan` PASS 分支的职责，不属于 developing 内 TASK 完成条件。TASK-05（含本 checklist）的完成边界是 developing 内可被 `crctl task done` 登记的事件（验证输出留存 + 交付记录落盘），**不含** checkpoint/发布/merge/审批；checkpoint 审计事实以 checkpoint 元数据为准，不进 TASK ledger。

环境前提与即时验证口径：本计划验收证据均为离线命令与只读线上核验，无常驻服务、浏览器或数据库依赖。

- 环境 owner、建立方式、可获得性：multica / tools CR worktree 由 CR 注册派生，责任人 Ray，已存在于本机，无需新建；`node`（v24）与 `multica` CLI 本机可用。
- readiness 证据：复用本计划既有 `cmd-01`（multica 回归全绿即 worktree 可读且依赖基线在位）与 `cmd-02`（tools 结构测试全绿即 Pipeline JSON 可解析）；证据 ID 照抄第 6 章证据命令表，不新增命令行。
- 缺失时处置：worktree 缺失或命令无法执行按 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（详细事实源见 `implement-code`，此处只引用不复述）。

## 6. 两张稳定表

### 交付覆盖表

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 委派回执按目标判定 | §4.1 四份提示词全文替换（dep-3 行号） | CR-2026-071-TASK-01 / 关联 CR-2026-071-TASK-03 | cmd-01 | 经受控 `crctl git revert` 回滚 TASK-01 commit（被 TASK-03/04 消费时连带下游，见 §4 R5） |
| FR-2 源部署副本与线上一致 | §4.1 bak 审计 + §4.2 线上同源同步 | CR-2026-071-TASK-04 / 关联 CR-2026-071-TASK-01、CR-2026-071-TASK-03 | cmd-01、cmd-04、cmd-05、cmd-06、cmd-07 | 文件侧经受控 revert 回滚 TASK-04 commit（上游保留）；线上侧按 §4 R2 快照在线回滚并 `agent get` 重验 |
| FR-3 单一合同与漂移回归 | §4.1 合同源 + §4.3 三组断言 | CR-2026-071-TASK-03 / 关联 CR-2026-071-TASK-04、CR-2026-071-TASK-05 | cmd-01 | 经受控 revert 回滚 TASK-03 commit（含下游 TASK-04 文件侧 + 线上侧，见 §4 R5/R2） |
| FR-4 恢复 node-2 后评审前 checkpoint | §4.4 `...0003` 节点 + `_index.yml` + 结构测试同步 | CR-2026-071-TASK-02 | cmd-02 | 经受控 revert 回滚 TASK-02 commit（节点 + index + 测试同一单元） |

说明：cmd-01 观测文件侧全量（四份 + 需维护 bak 与合同一致）；FR-2 的线上四份 `agent get` 原文核验由 cmd-04～cmd-07 直接观测，不存在以子集声称全量。各 TASK 的 Git 范围核验一律按本 §6 文件侧范围核验标准执行（BASE 锚定三步，禁止原生 git），双向引用见各 TASK §4。

### 证据命令表

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | multica | . | node | ["--test", "cr-prompts-revised/test/delegation-contract.test.mjs"] | 120 |
| cmd-02 | tools | . | node | ["--test", "skills/shared/crctl/scripts/test/pipeline-structure.test.mjs"] | 120 |
| cmd-03 | tools | . | node | ["-e", "JSON.parse(require('fs').readFileSync('pipeline-templates/requirement-authoring.pipeline.json','utf8'));console.log('pipeline-json-ok')"] | 60 |
| cmd-04 | multica | . | multica | ["agent", "get", "6317495b-d913-4d47-be79-0c0b342b03fd", "--output", "json"] | 60 |
| cmd-05 | multica | . | multica | ["agent", "get", "ff6fcbb6-6bb6-42fb-9d88-03493c771411", "--output", "json"] | 60 |
| cmd-06 | multica | . | multica | ["agent", "get", "2ed1a9de-4c8e-4b78-bfb1-055af99c6681", "--output", "json"] | 60 |
| cmd-07 | multica | . | multica | ["agent", "get", "87ca2271-f4d8-4865-aef1-9a24523e1a20", "--output", "json"] | 60 |
| cmd-08 | multica | . | multica | ["issue", "comment", "list", "01a0ddf8-ea5a-7b11-9da5-8d753d34d5f1", "--roots-only", "--summary", "--output", "json"] | 60 |
| cmd-09 | multica | . | multica | ["issue", "comment", "list", "01a0ddf8-ea5a-7b11-9da5-8d753d34d5f1", "--thread", "<root-id>", "--tail", "30", "--output", "json"] | 60 |
| cmd-10 | multica | . | multica | ["issue", "get", "01a0ddf8-ea5a-7b11-9da5-8d753d34d5f1", "--output", "json"] | 60 |
| cmd-11 | ai-first-platform-docs | . | node | ["C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-071/skills/shared/crctl/scripts/crctl.mjs", "git", "diff", "--stat", "origin/master", "HEAD", "--", "change-requests/CR-2026-001"] | 60 |
| cmd-12 | ai-first-platform-docs | . | node | ["C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-071/skills/shared/crctl/scripts/crctl.mjs", "git", "diff", "--unified=3", "origin/master", "HEAD", "--", "change-requests/_backlog.yml"] | 60 |
| cmd-13 | ai-first-platform-docs | . | node | ["C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-071/skills/shared/crctl/scripts/crctl.mjs", "git", "diff", "--stat", "origin/master", "HEAD", "--", "change-requests/_history.yml", "change-requests/_index.yml"] | 60 |

命令算法唯一事实源为本表行；`cwd` 为对应 repo CR worktree 内相对路径（`.` 即 worktree 根）；`executable` 直接可 spawn，无 shell 内建/管道/重定向；不涉及 Git 写操作，不改 `rules.json`。cmd-04～cmd-10 为工作区作用域只读 CLI（`multica` 在 PATH），`cwd` 仅为 spawn 占位、不参与判定，判定以 stdout JSON 为准：cmd-04～cmd-07 判据为 instructions 含规范三元组、无 `enqueued` 成功语义、无 `target_unavailable` status 语义（详见 TASK-04 §4）；cmd-08 判据窄化为**新根线程数零新增**（根 id 集合与基线一致；本命令看不见既有线程内新增回复，不得单独用作 verdict 证据——B-02 复评）；cmd-09 为模板命令，对 cmd-08 输出的**每一个**根 id 各执行一次，判据为各线程尾 30 条内无新增评论 id、无 reviewer verdict（PASS/BLOCK/TECHNICAL_ABORT）评论、无新的 AIFI-35 reviewer run（执行程序与基线比对见 TASK-05 §3）；cmd-10 判据窄化为 Issue 可观测面（`status`/`revision`/`updated_at` 与基线一致），不得单独声称文件级零 diff（B-02 复评）。cmd-11～cmd-13 为 B-02 cycle-2 回修新增的文件账本面证据（受控 `crctl git` 只读子命令，均经白名单实测可用；`args[0]` 为 tools CR worktree 内 `crctl.mjs` 绝对路径，属本 CR pipeline resource，本轮已验证可执行；cycle-2 首评 BLOCK 后修正判定口径，见本段后半）。语义目标：cmd-11（`change-requests/CR-2026-001` 目录零文件变更）∧ cmd-12（`_backlog.yml` 变更仅限本 CR 自身条目行，实测仅 `prd-path` 与本 CR `latest-checkpoint`）∧ cmd-13（`_history.yml`/`_index.yml` 零变更）。stdout 解剖（`crctl git` 输出结构唯一事实源：`crctl.mjs` cmdGit 先把 git 原生输出写 stdout、再把 `{"ok","exit"}` 回执写同一 stdout）：单次调用 stdout = [diff 正文] + [末尾 JSON 回执块]。零差异时正文为空串，stdout 整体即仅回执块 `{"ok":true,"exit":0}`——**永不为 truly empty**；且 git diff 有无差异都 exit 0，故"stdout 为空"恒不可满足、"exit==0"恒不能证明零差异（cycle-2 首评 BLOCK 教训；本轮在 KB worktree 以显式 `--workspace` 实测复现：cmd-11/cmd-13 均 exit=0 且仅回执块）。机械判定（对 cmd-11/cmd-12/cmd-13 每条 stdout 执行，无 shell 管道、无新命令，目视逐行即可复验；回执与正文都必须看，不得跳过任何一边）：① 回执检查：末尾 JSON 块须存在且 `exit==0`、`ok==true`，否则命令失败、判据不成立（上报人类，不判通过）；② 正文剥离：回执块 = 最后一个行首为 `{` 的行起至文末，diff 正文 = 其之前全部内容；③ 零差异判定：cmd-11/cmd-13 通过 ⟺ 回执绿 ∧ 正文去空白后长度为 0；cmd-12 通过 ⟺ 回执绿 ∧ 正文中无 `CR-2026-001` 子串；④ 非空阳性对照（防错路径/锚定漂移假空，与 cmd-11/cmd-13 同次执行、同一受控入口）：同次 `diff --stat origin/master HEAD`（无路径限定）的正文须**非空**，且文件集仅含 `change-requests/CR-2026-071/` 自身路径与 `change-requests/_backlog.yml`（本轮实测 17 文件，无 `CR-2026-001` 路径；阳性对照缺失/为空/含界外路径时 cmd-11/cmd-13 不得判通过）。锚定 `origin/master` 为 KB trunk（`ls-remote` 实测），`HEAD` 为本 CR 分支 tip，均为符号引用故执行期有效——TASK-05 启动时记录 `rev-parse origin/master` 与 `rev-parse HEAD` 作审计基线，结束复测，若 trunk 前移（两值变化）如实记录并以复测时 trunk 为准，不得静默。AC-6 通过条件为 cmd-08 ∧ cmd-09 ∧ cmd-10 ∧ cmd-11 ∧ cmd-12 ∧ cmd-13 六者合取（cmd-11～cmd-13 按本段机械判定，非 raw-stdout 为空）。

文件侧范围核验标准（各 TASK §4 统一引用，B-02 复评）：一律经受控 `crctl git` 只读子命令（禁止原生 git），三步可复验——(a) TASK 启动时 `crctl git rev-parse HEAD --cwd <worktree>` 记录 BASE（40 位）；(b) TASK 完成后 `crctl git log --oneline -5 --cwd <worktree>` 定位本 TASK 提交 C；(c) `crctl git diff --stat BASE C --cwd <worktree>` 列出精确文件集，判据为文件集 == 本 TASK §2 声明集（多一少一即失败），另 `crctl git status --short --cwd <worktree>` 须干净（无未提交夹带）。裸 `diff --stat`（无 BASE）在提交后恒为空，不得用作范围证据，各 TASK §4 已按此模板实例化并双向引用本段。

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 queued/coalesced/deferred 判成功零误报 | §4.1 + §4.3 向量前 3 例 | CR-2026-071-TASK-03 | cmd-01 |
| AC-2 blocked/缺失 outcome/human-only/未知 status | §4.1 四分支 + §4.3 向量后 4 例 + 2 例否定 | CR-2026-071-TASK-03 | cmd-01 |
| AC-3 源/bak/合同/回归/线上四份一致 | §4.2 + bak 审计 | CR-2026-071-TASK-04 | cmd-01、cmd-04、cmd-05、cmd-06、cmd-07 |
| AC-4 回归覆盖与枚举对齐漂移变红 | §4.3 三组断言 | CR-2026-071-TASK-03 | cmd-01（编写与子集自洽归本 TASK；含 bak 全绿的最终门禁在 CR-2026-071-TASK-05 复验） |
| AC-5 node-2 → checkpoint → review 顺序与回修重发 | §4.4 + _index/结构测试 | CR-2026-071-TASK-02 | cmd-02 |
| AC-6 AIFI-35 零触发零账本改动、新 CR 未来流程 | §9 zero_diff/scope | CR-2026-071-TASK-05 | cmd-03、cmd-08、cmd-09、cmd-10、cmd-11、cmd-12、cmd-13（cmd-08 新根零新增 ∧ cmd-09 逐线程尾零新增 verdict ∧ cmd-10 Issue 对象一致 ∧ cmd-11 CR-2026-001 目录正文零差异 ∧ cmd-12 `_backlog.yml` 正文无 CR-2026-001 行 ∧ cmd-13 `_history.yml`/`_index.yml` 正文零差异；文件账本面三项按 §6 机械判定执行——回执绿 ∧ 正文判定 + 阳性对照，双向引用 TASK-05 §3/§4；Issue 面 + 文件账本面（分支-vs-trunk 合并基点锚定），未来流程由 cmd-02/cmd-03 结构保证，见 TASK-05 §4） |
