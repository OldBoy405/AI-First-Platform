---
id: CR-2026-074-plan
type: PLAN
cr-ref: CR-2026-074
sdd-ref: "change-requests/CR-2026-074/sdd.md"
target-version: 0.47
status: draft
created: 2026-10-01T00:35:38+08:00
updated: 2026-10-02T17:04:00+08:00
---

# CR-2026-074 开发计划

承接已审批 `sdd.md` v0.2（tech-design attempt 2/3 PASS，Blockers 0）。范围：FR-1～FR-10、AC-01～AC-12 全部（SDD §9 scope_in）。交付仓分工：tools 全部生产代码/测试/文档；knowledge-base 承载本 CR 受控文档（由各 Pipeline 节点生成，不占开发 TASK）；multica 无代码变更。本文 TASK 编号即 canonical 完整 id（`CR-2026-074-TASK-NN`），与后续 `tasks/_index.yml` 的 id 集一致。计划层不含步骤粒度表述；步骤切分在 write-dev-tasks / implement-code 按 coding-discipline §2 执行。

## 1. 交付里程碑

| 里程碑 | 内容 | TASK | 预估（人天当量） |
|---|---|---|---|
| M1 实现 | 模块代码 + 所属测试入口定向用例 | TASK-01～TASK-07 | 2.0 |
| M2 集成验证与文档同步 | 端到端 writeback 变体；说明/命令发现/计数同步 | TASK-08、TASK-09 | 1.0 |
| M3 收尾与评审 | ARCHITECTURE 地图维护；全量证据回归（cmd-01～cmd-07）；test-report；review-code | TASK-10 + 全量回归 | 0.5 |
| M4 发布 | review-code PASS → 人工 approve-code → 交付回写 | reviewer / delivery-agent | — |

M4 由 Pipeline 门禁承载，不属于开发 TASK；阶段发布由 reviewer 在评审 PASS 分支内一次闭合。

## 2. 任务依赖图

```text
TASK-01 kb init 入口/CLI/前置/发布重入（crctl.mjs + crctl.test.mjs init 用例）
  ├─→ TASK-02 ensure create 自忽略（workspace-transactions.mjs + register-tx.test.mjs 场景用例）
  │       [依赖 TASK-01 的 kb init 入口]
  │     └─→ TASK-03 source 空缺省 + 历史指纹矩阵（register-tx.test.mjs）
  │             [同测试文件，顺序编辑]
  └─→ TASK-07 rules.json 裸提交 shape + controlled-shell SKILL 同步（+ crctl.test.mjs 受控入口用例）
          [与 TASK-01 同测试文件，顺序编辑；逻辑独立]

TASK-04 buildIndex 缺文件首写 + features 前置校验（writeback-prd-sdd.mjs + writeback.test.mjs）
  └─→ TASK-05 两规范表提取（writeback-traceability.mjs + writeback.test.mjs）
        └─→ TASK-06 YAML trunk 解释（同上）
              [TASK-05/06 与 TASK-04 无逻辑耦合，仅同测试文件顺序编辑]

TASK-04/05/06 ─→ TASK-08 writeback-tx 无索引/证据齐全集成变体
TASK-01、TASK-03～TASK-08 ─→ TASK-09 说明/命令发现/计数同步
TASK-01、TASK-09 ─→ TASK-10 ARCHITECTURE.md 地图维护
        [TASK-10 消费 TASK-09 完成后的 SKILL/README/HELP 最终形态，须待 TASK-09 完成]
全部 TASK ─→ 全量证据回归 cmd-01～cmd-07 ─→ review-code
```

## 3. 资源与分工

单一执行 Agent：dev-agent（owners.development：Ray，人工审批人）。

| 仓库 | 分工 | 承载 TASK |
|---|---|---|
| tools | 全部生产代码、定向测试、文档同步 | TASK-01～TASK-10 全部 |
| knowledge-base | 本 CR 受控文档（plan/tasks/test-report 等） | Pipeline 节点受控生成，不占开发工时 |
| multica | 无代码变更（zero_diff） | 无 |

工时分配（人天当量）：M1 内 TASK-01 0.75、TASK-02 0.15、TASK-03 0.10、TASK-04 0.40、TASK-05 0.25、TASK-06 0.25、TASK-07 0.10；M2 内 TASK-08 0.60、TASK-09 0.40；M3 内 TASK-10 0.10、全量回归与报告 0.40。合计 3.5 人天当量。

## 4. 风险与回滚策略

| # | 风险 | 缓解 | 回滚 |
|---|---|---|---|
| R1 | rules.json 新 shape 扩大受控 Git 面 | 仅追加一条 merge-base shape，与两条旧 shape 并存；两旧 shape 单独回归，非法形态须不匹配全部三条才拒绝（SDD §4.6） | revert TASK-07，独立无下游 |
| R2 | source 缺省值变更影响注册指纹 | 历史 `manual` 不迁移、不做全局别名；冲突按 SDD §2.3 矩阵报原错误，零账本重写 | revert TASK-03；恢复旧默认后新空 source 历史仍不迁移 |
| R3 | features 前置校验对既有索引误拒 | 判据固定 `line.trimStart()==='features:'`，不新增其他收紧项；四类畸形负测覆盖（SDD §4.3、AC-05） | revert TASK-04 及其用例；TASK-05/06 无逻辑耦合 |
| R4 | 共享测试文件（crctl.test.mjs / register-tx.test.mjs / writeback.test.mjs）跨 TASK 编辑 | 依赖图约束顺序编辑；revert 按逆拓扑顺序 | 逆拓扑回滚顺序：TASK-10 → TASK-09 → TASK-08 → TASK-06 → TASK-05 → TASK-04 → TASK-03 → TASK-02 → TASK-07 → TASK-01 |
| R5 | kb init 无跨阶段事务隔离 | 合法模板/暂存/本地 commit 保留是接口合同；远端竞争由普通非快进 push 拒绝；重跑重新执行全部前置（SDD §4.1/§5.3） | 无自动 rollback；失败残留按 §3.2 错误边界报告 |
| R6 | 发布后缺陷 | 发布由门禁承载；不手改受控账本、不 force trunk、不改 durable-tx/apply | 正常 Git revert / 新 CR |
| R7 | ARCHITECTURE.md 地图遗漏 | TASK-10 明确列入 code review 检查项（SDD §8） | revert TASK-10 |

## 5. 验收与发布策略

- **环境静态前提**：无需常驻服务、浏览器或数据库。验收环境 = tools CR worktree（Pipeline `resources[].worktreePath`，`workspace inspect` 为 healthy 且 dirty=false 即就绪）+ Node ≥18 + Git；测试 fixture 均在临时目录自建仓，不触及用户全局 Git 身份。
- **环境 owner 与可获得性**：owner 为 dev-agent；worktree 由 Pipeline resources 建立，缺失/不健康时按 `ENVIRONMENT_MISMATCH` 中止并报告所需建立动作（该标签的唯一详细事实源是 implement-code，此处只引用不复述）。
- **readiness 证据**：复用证据命令表既有 `cmd-01`（其通过即证明 Node/Git/测试入口就绪），不新增命令行，不放宽「验收证据 ↔ 证据ID」双向唯一映射。
- **发布策略**：零新依赖 CLI，无 feature flag；review-code PASS → 人工 approve-code → delivery-agent 交付回写；阶段发布由 reviewer 在评审 PASS 分支一次闭合。

## 6. 两张稳定表

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 | §1/§3.1/§4.1 kb init 入口特判、输出与帮助 | CR-2026-074-TASK-01 | cmd-01 | revert TASK-01；连带下游 TASK-02/03 同批回退（其测试场景依赖 kb init），不声明为单点回滚 |
| FR-2 | §3.2/§4.1 前置顺序、错误优先级与失败残留 | CR-2026-074-TASK-01 | cmd-01 | 同 FR-1 |
| FR-3 | §2.1/§3.1/§4.1 两账本模板、独占创建、发布与重入 | CR-2026-074-TASK-01 / TASK-02 | cmd-01 + cmd-02 | revert TASK-01 与 TASK-02，按逆拓扑顺序先 02 后 01 |
| FR-4 | §4.2 ensure create 自忽略 | CR-2026-074-TASK-02 | cmd-02 | revert TASK-02（TASK-03 用例不依赖其行为，单点可回滚） |
| FR-5 | §2.2/§4.3 缺索引首写与全部既有索引 features 前置校验 | CR-2026-074-TASK-04 / TASK-08 | cmd-03 + cmd-04 | revert TASK-08 → TASK-04；TASK-08 为其下游消费者 |
| FR-6 | §4.4 两规范表提取 | CR-2026-074-TASK-05 / TASK-08 | cmd-03 + cmd-04 | revert TASK-08 → TASK-05 |
| FR-7 | §4.5 YAML trunk 解释 | CR-2026-074-TASK-06 / TASK-08 | cmd-03 + cmd-04 | revert TASK-08 → TASK-06 |
| FR-8 | §8 说明/命令发现/测试计数同步 + §8 ARCHITECTURE.md 地图行（dep-15） | CR-2026-074-TASK-09 / TASK-10 | cmd-05 + cmd-06 + cmd-07 | revert TASK-10 → TASK-09（逆拓扑见 R4；TASK-10 为 TASK-09 下游） |
| FR-9 | §4.6 merge-base 裸提交 shape | CR-2026-074-TASK-07 | cmd-01 | revert TASK-07，独立无下游 |
| FR-10 | §2.3/§4.2 source 空缺省与历史指纹边界 | CR-2026-074-TASK-03 | cmd-02 | revert TASK-03，独立无下游 |

### 6.2 证据命令表（稳定表 2/2）

`cwd` 为 tools CR worktree 内相对路径，`.` 即该仓根；`args` 为 JSON token 数组。

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/crctl.test.mjs"] | 600 |
| cmd-02 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/register-tx.test.mjs"] | 600 |
| cmd-03 | tools | . | node | ["--test","skills/writeback/scripts/test/writeback.test.mjs"] | 600 |
| cmd-04 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/writeback-tx.test.mjs"] | 720 |
| cmd-05 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/caller-contract.test.mjs"] | 300 |
| cmd-06 | tools | . | node | ["--test","skills/shared/crctl/scripts/test/lint-prompts.test.mjs"] | 300 |
| cmd-07 | tools | . | node | ["-e","const fs=require('fs');const t=fs.readFileSync('ARCHITECTURE.md','utf8');const need=['kb init','cmdKbInit','requireExplicitWorkspace','detectWorkspace','_backlog.yml','_index.yml','KB_INIT_PRECONDITION'];const miss=need.filter(s=>!t.includes(s));if(miss.length){console.error('cmd-07 FAIL: ARCHITECTURE.md missing: '+miss.join(', '));process.exit(1);}console.log('cmd-07 ok: '+need.length+' map markers present');"] | 60 |

命令算法唯一事实源为本表行。cmd-01～cmd-06 对应 SDD §5.2 测试表入口；cmd-07 为 SDD §8 ARCHITECTURE.md 地图行（dep-15）的只读取证命令：cwd 即 tools CR worktree 根，argv 内联脚本仅读取该文件并逐项断言比对判据（`kb init`、`cmdKbInit`、`requireExplicitWorkspace`、`detectWorkspace`、`_backlog.yml`、`_index.yml`、`KB_INIT_PRECONDITION`），不写任何文件；判据到 TASK-01/§2.1/§3.2 代码事实的映射与其承载边界见 TASK-10 验收条件 1。SDD §8「随代码评审检查」的人工内容检查（review-code R7）保留，cmd-07 不代替、不删除该检查。

cmd-04 的 `timeout=720` 是 2026-10-02 由 600 上调的结果，依据一次前台实测：在 tools CR worktree（`1f9c603`）以本表原样 argv/cwd 单跑一次 `timeout -s SIGTERM 720 node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` → exit 0、36 pass / 0 fail、`duration_ms 651157.812`（wall 652s），对 720s 余量 ≈9.4%；同一命令此前实测 573.5s / 628.6s / 637.3s，均逼近或越过旧 600s 上限。不取更大值的理由：`write-test-report` 节点声明 `timeoutMinutes: 20`（1200s），同轮其余六条合计 ≈389s（cycle 2 attempt 1 机器区：cmd-04 被 SIGTERM 处累计 ≈989s，即 989−600），cmd-04 取 ≥900 时节点累计上界 ≈1289s 会越过该额度。

## 7. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01 init 精确模板/提交 tree/远端首 trunk/输出/二次 noop | §2.1/§3.1/§4.1/§5.2（dep-16 fixture） | CR-2026-074-TASK-01 | cmd-01 |
| AC-02 前置检查有序、错误 code/reason 固定 | §3.2 | CR-2026-074-TASK-01 | cmd-01 |
| AC-03 wx/续跑/失败残留与去注入恢复 | §4.1/§5.2 | CR-2026-074-TASK-01 | cmd-01 |
| AC-04 init 后首 CR：worktree、runtime ignore、主 KB clean | §4.2/§5.2（dep-16） | CR-2026-074-TASK-02 | cmd-02 |
| AC-05 缺索引首写与四类畸形 STRUCTURE_MISMATCH、apply 不重复 | §2.2/§4.3/§5.2 + apply fixture（dep-17/18） | CR-2026-074-TASK-08（主责：用户可观察的首写/隔离/幂等端到端面，writeback-tx apply 层产生该结果）；TASK-04 关联协作（buildIndex 结构负例与首写模块语义，断言全部保留于 cmd-03） | cmd-03 + cmd-04 |
| AC-06 规范表链/命令 ID 提取与空位/管道/诱饵 | §4.4 | CR-2026-074-TASK-05 | cmd-03 |
| AC-07 表结构正负、LF/CRLF 等价、authority 不变 | §4.4/§5.2 | CR-2026-074-TASK-05 | cmd-03 |
| AC-08 YAML trunk 解析与 TRUNK_UNKNOWN | §4.5 | CR-2026-074-TASK-06 | cmd-03 |
| AC-09 手工模板删除/保留、命令发现与计数一致 | §8 | CR-2026-074-TASK-09 | cmd-05 + cmd-06 |
| AC-10 裸提交祖先判定与拒绝形态 | §4.6 | CR-2026-074-TASK-07 | cmd-01 |
| AC-11 source 空缺省、显式合同不变、历史指纹矩阵 | §2.3/§4.2/§5.2 | CR-2026-074-TASK-03 | cmd-02 |
| AC-12 无索引 merge→三阶段→archive、独立 trace 重放 | §4.3～§4.5/§5.2（dep-17/18） | CR-2026-074-TASK-08 | cmd-04 |

## 8. 修订记录（plan-blocker 治理回退：cmd-04 timeout 600→720 判据修订链）

本节登记本计划在代码实现期的一次**计划侧判据修订**与配套回退的事实链，供后续节点定位证据来源；不改 §6.1/§6.2 两张稳定表的行/列契约，不改 SDD 批准范围。

**① 触发事实（判据失效）**：`cmd-04`（`writeback-tx.test.mjs` 定向用例）在 `write-test-report` cycle 2 / attempt 1 撞 600s 上限——机器区 `started=true`、`exit-code=null`、`signal=SIGTERM`、`timed-out=true`，报告 `status: block`（`test-report.md`，`generated-at 2026-10-02T13:19:31+08:00`；同轮其余 6 条 `exit-code=0`、`skipped=false`）。报告分析区结论：本次 block 的**唯一成因是计划层额度**，`timeout=600` 低于当前工况实际耗时（§6.2 表下注记所列实测 573.5s / 628.6s / 637.3s / 652s）。

**② 判据修订**：§6.2 `cmd-04` 行 `timeout` 由 600 上调为 720（KB 提交 `11c59987`，2026-10-02T16:39:34+08:00；依据与不取更大值的理由见 §6.2 表下注记）。该行是本轮唯一被改动的复合证据主体：`TASK-*.md` 自 `c65b4f04`（2026-10-01T02:16:54）起零改动，`tasks/_index.yml` 的 done 标记不在 dev-start 审批证据摘要内（`gates.json#approvalStages.dev-start.evidence`）。

**③ 门禁后果**：上述修订落在 `review-dev-plan` PASS（`reviewed-at 2026-10-01T02:26:58+08:00`）与 `approve-dev-start`（`approved-at 2026-10-01T20:55:57+08:00`）之后，`developing` 门禁出现两条具名阻塞：dev-plan composite digest 漂移（annotation 记录 `8ae03970…`，当前重算 `d0846dce…`，`repairTarget=review-dev-plan`）与 `approval.yml#development-start` `EVIDENCE_DRIFT`（记录 `860b22fa…`，重算 `9957d96e…`）。

**④ 回退（授权治理回退入口，非 `review-code` 的 plan-blocker 结论）**：按门禁自述的修复方向与 `crctl status` 的 `legalNext`，走状态机既有边退出 `developing`：

```text
crctl advance CR-2026-074 --to tech-design-reviewed \
  --trigger "review-code:plan-blocker -> write-dev-plan" --expect developing
→ advanced=true / from=developing / to=tech-design-reviewed / committed=true
  KB 提交 fc3a47c1（[cr] status CR-2026-074 developing -> tech-design-reviewed，2026-10-02T17:02:30+08:00）
  outbox=20261002T090230819Z-CR-2026-074-status-fc3a47c1.json
```

`review-annotations/code.yml`（attempt 2）的唯一未闭合 blocker 是 **B-CODE-03**（`cmdKbInit` 额外旗标的 `BAD_ARGS` 优先级与缺根优先合同缺陷，code 侧），其回修已由 `implement-code` 于 2026-10-02 交付（tools CR worktree `1f9c6032` + `a259454`），不因本轮回退重跑。本轮回退的成因是**计划层判据在实现/测试期被实测证伪**，故按既有先例（CR-2026-065 §0.0、CR-2026-069 同边用法）使用该边作为受权治理回退入口；**不声称**存在 `review-code` 的 plan-blocker 评审结论，未新增状态转换。

**⑤ 回退后的重放链**：`write-dev-plan`（本节点：本节与 §6.2 注记）→ `write-dev-tasks`（TASK 集合与本次 timeout 修订无耦合，逐字保留；推进 `task-breakdown`）→ `review-dev-plan` 独立复评（刷新 `subject-sha256` 与 PASS 证据）→ 人工 `approve-dev-start` 重签（`expect=[task-breakdown]`，同时刷新 `approval.yml#development-start` 证据摘要）→ `developing`。`review-dev-plan` PASS 前不得进入人工审批。

**⑥ reviewLoop 记账**：`review-dev-plan` cycle 2 / attempt 0（Ray 交互式终端 reset，KB 提交 `b9e9b592`，reset 原因即本轮 cmd-04 600s 超时）；`write-test-report` cycle 2 / attempt 1；`review-code` cycle 1 / attempt 2。

**⑦ 范围边界**：本节仅登记计划侧修订与回退链；`sdd.md` 自技术审批（`2026-10-01T00:24:38+08:00`）后零提交（其最后一次改动为 `d30c049f`，2026-10-01T00:09:54），本轮零 diff；未改 §6.1/§6.2 表结构，未改 tools / multica 代码。
