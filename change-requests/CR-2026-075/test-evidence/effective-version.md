---
id: CR-2026-075-effective-version
type: EVIDENCE
cr-ref: CR-2026-075
source-task: CR-2026-075-TASK-09
target-version: 0.48
updated: 2026-10-06T01:54:27.980+00:00
---

# CR-2026-075 生效版本台账（部署副本收敛 / 合同对齐 / 平台同步清单）

## 1. 状态（机器事实，不采信评论文本）

| 项 | 事实 | 判定 |
|---|---|---|
| 仓库侧收敛（四份部署副本 + 两份维护副本 + 合同对齐 + CHANGES.md） | 已完成（见 §2）；CUSTOM.md 登记为剩余项 | ⚠️ |
| `cmd-08`（合同与副本无漂移） | 19/19 pass（修正前基线 18 pass / 1 fail） | ✅ |
| `cmd-09` ① 部署副本收敛 + 显式 CR-ID 保留 | 四份 `--workspace <workspace>` 出现次数全为 0；`CR-ID`/`cr_id` 均在 | ✅ |
| `cmd-09` ② 14 个 imported Skill 取用路径台账 | 14 行 `imported-skill` 与声明一致（`AI-First-tools@main/skills/...`） | ✅ |
| `cmd-09` ③ 四份 CR Agent 线上 instructions 与部署副本逐字一致 | **不一致（4/4）** | ❌ 待人类同步 |
| `cmd-10` 线上发布文件集与仓库目标逐字一致 | **不一致（28 项）+ 线上缺失（4 项）**；另有范围外既有漂移 4 项（R8，单列、不参与通过判定） | ❌ 待人类同步 |
| 平台侧同步（TASK-09 验收前置） | **未执行** | ❌ 待人类 owner |

按 TASK-09 卡「前置未完成或比对仍红时：本 TASK 不 done，按缺失环境前提报告所需人工动作」，**TASK-09 本轮不登记 done**；`cmd-09`/`cmd-10` 的红项全部落在平台侧同步这一项前置上，仓库侧无红项。不得以 `pending-deploy`、来源路径/ref 一致或「仓库已改」充作 AC-B14 通过。

## 2. 仓库侧改动与收敛核对（multica CR worktree）

| 载体 | 改动 | 收敛核对 |
|---|---|---|
| `cr-prompts-revised/requirement-writer.md` | 3 处逐命令 `--workspace <workspace>` 示例收敛（阶段出口 / 路由表「查询与下一步」/ 状态·下一步事实源） | 出现次数 0；显式 CR-ID 在 |
| `cr-prompts-revised/dev-agent.md` | 5 处收敛（阶段出口 / SDD 入口 / 路由表「状态·查询·同步」/ 状态·下一步 / 恢复返工读取） | 出现次数 0；显式 CR-ID 在 |
| `cr-prompts-revised/quality-reviewer-agent.md` | 1 处收敛（阶段判定） | 出现次数 0；显式 CR-ID 在 |
| `cr-prompts-revised/cr-coordinator-agent.md` | 4 处收敛（事实源表「CR 当前状态与下一步」/ 每 turn 读取纪律 / 人工门禁承接 / 禁止行为条） | 出现次数 0；显式 CR-ID 在 |
| `cr-prompts-revised/delegation-contract.md` | 成功集合补 `steered`（对齐 `server/internal/handler/admission.go` 的 `DispatchStatus`） | `cmd-08` 19/19 绿 |
| `cr-prompts-revised/bak/{cr-coordinator-agent,quality-reviewer-agent}.md` | 内联合同同等修正（`bak/README.md` 的 `maintainedBak()` 口径，两份均在「维护」集合内） | `cmd-08` 的同源断言绿 |
| `cr-prompts-revised/CHANGES.md` | 新增「2026-10-06 第 4 版」章节（按现有小节结构顺延：起因/基线/修订原则/落点/校验/落地/未纳入本次） | 与四份副本实际字符数逐行对账；未纳入项给出实测次数 |
| `CUSTOM.md` | **未登记（剩余项）**：TASK-02 的 daemon 改动（`pipeline_task.go` / `daemon.go` / `pipeline_task_test.go` / `cr_workspace_binding_test.go`，4 文件 +632/−64，基线 `ae90689fa`）待按三表结构登记为行号 `#114` 并同步《模块索引》M10 行、`CR 索引` 与本文件头计数基线 | ❌ 见 §6 第 2 条 |

收敛口径与 CR-2026-075-TASK-08 的 tools 侧一致（不引入第二套写法）：删除逐命令 workspace 示例，改为「绑定环境可省根；确需显式传时取 `execution_context.operational_workspace`」；保留项（显式 CR-ID、业务阶段、职责/产出、写入/检查/发布要求）逐项仍在。

### 2.1 `cr-coordinator-agent.md`「禁止行为」条的收敛说明

原句为「本 Agent 只用 `crctl status` / `crctl next`（均显式带 `--workspace <workspace>`）与只读查询 Skill 读取事实」。该句是**逐命令命令示例**（`cmd-09` 按出现次数判定，出现 1 次即判「短提示未收敛」），故一并收敛；「显式根」这一说明本身未删——收敛后的措辞仍要求「确需显式传时取 `execution_context.operational_workspace`」。

## 3. 同步清单（人类 owner Ray 执行；命令算法的唯一事实源）

同步清单逐目标 sha256 由本 TASK 从源文件按 LF 规范化算出，供同步后核对。目标集合与文件集合直接取自 `plan.md` §6.2 的 `cmd-10` args 内 `EXPECT`（不从别处另立第二套）。

| 目标 | 平台 id | 源文件（仓库） | 目标 sha256（LF） | 同步命令形态 |
|---|---|---|---|---|

### A. 四份 CR Agent（multica 部署副本）

- `requirement-writer` id=`6317495b-d913-4d47-be79-0c0b342b03fd` 源=`cr-prompts-revised/requirement-writer.md` sha256=9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08
- `dev-agent` id=`ff6fcbb6-6bb6-42fb-9d88-03493c771411` 源=`cr-prompts-revised/dev-agent.md` sha256=4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218
- `quality-reviewer-agent` id=`2ed1a9de-4c8e-4b78-bfb1-055af99c6681` 源=`cr-prompts-revised/quality-reviewer-agent.md` sha256=daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c
- `cr-coordinator-agent` id=`87ca2271-f4d8-4865-aef1-9a24523e1a20` 源=`cr-prompts-revised/cr-coordinator-agent.md` sha256=b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3

### B. 两个业务调用方 Agent（tools 登记文本）

- `product-planning-agent` id=`d0293197-e57a-44e2-9362-8a31b757b79a` 源=`agents/product-planning-agent.md`（tools CR worktree） sha256=317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb
- `competitive-analyst-agent` id=`cd75e333-57cb-4bf5-b418-7dc9e55799c5` 源=`agents/competitive-analyst-agent.md`（tools CR worktree） sha256=d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366

### C. imported Skills（EXPECT 逐项 = cmd-10 的同一来源）


**crctl** id=`ab178d6f-f007-4150-a576-c1d9c5c0a0e2` origin=`AI-First-tools@main/skills/shared/crctl`
- `skills/shared/crctl/SKILL.md` sha256=53e3f39895f2cc81716e733b091d9c489435470d9bf5d987df3d136f6d53db99
- `skills/shared/crctl/scripts/crctl.mjs` sha256=d6c12c3748cac38e6c42469276e58d3e67745773950d88a5db43b7333d99eec6
- `skills/shared/crctl/scripts/lib/durable-tx.mjs` sha256=57d5b5023591c797db06b5fa3c91089ef8f1cc7d4cd73d9042cad87b365a223e
- `skills/shared/crctl/scripts/lib/planning-entry.mjs` sha256=ba0f7161da42e5b383292370618b5a47b791799975072d71fe92de49f16e6806
- `skills/shared/crctl/scripts/lib/competitive-report.mjs` sha256=865857bb6a2284795962ed35543c6d5142101c19d205029185cece5dfac4bef0
- `skills/shared/crctl/scripts/test/crctl.test.mjs` sha256=76bf5ed91620e55271a8cfdff04df90aebdaeeafa97c8afbca9ac4d7721a0a38
- `skills/shared/crctl/scripts/test/planning-entry.test.mjs` sha256=7541d7b23a680865fcbe981454490c75e61572537ac81996e86e854a3097471c
- `skills/shared/crctl/scripts/test/competitive-report.test.mjs` sha256=7d8d84cfb88a37c56d8e150357b4295cf9e13fe229ddfb872cecbd3f5d92c89f
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs` sha256=8c391329d0bbde33c009cedfbdc88794e7eb264a9b177dfd19e274237d521617
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` sha256=6504a3c3fa3b4fbe461445e0a962454d9157b8df3a72d493a12f85ffbd6af65d
- `skills/shared/crctl/scripts/test/durable-tx.test.mjs` sha256=4d30b7b1ffda58331f1128f95c7edd267a54aff4e81bbeea788c3aff99221b70
- `skills/shared/crctl/scripts/test/gate-registry.json` sha256=f0eaaa944d1a658b4b4c9657289635aa92f9d9a6914c40133ae3234ee10c5db2

**engineering-docs** id=`13c91eb2-1f3b-4fec-8035-cd94eca3dc09` origin=`AI-First-tools@main/skills/shared/engineering-docs`
- `skills/shared/engineering-docs/SKILL.md` sha256=51043b283e8ef6cbb02cab29dc08c2dc9e1a073837350982f4afbbf0f642b1f6
- `skills/shared/engineering-docs/scripts/src/utils/slug.ts` sha256=2359edc2745946452e1cb4b19e78b5b9a371508a6467df47352ab9acafae142c
- `skills/shared/engineering-docs/scripts/src/generators/base.ts` sha256=78882032b8470926a994c570483e541110c7f906ff9c28d218771d2baab6800f
- `skills/shared/engineering-docs/scripts/src/validators/index-sync.ts` sha256=075b29e9c2ede6f4308b5cd9978b635ffb6f1567886981eac0c149237a21a5d6
- `skills/shared/engineering-docs/scripts/src/__tests__/generators.test.ts` sha256=43115442dcb919e47ad6aaaa20ae78113056aa239f8a94016b29ce8517cfd211
- `skills/shared/engineering-docs/scripts/src/__tests__/validators.test.ts` sha256=a26a097021b1e51c1d6229e1225ed3e2de6f4ce0ececc21dbfa571f5e8ae7b40

### 3.1 命令形态

- 四份 CR Agent 与两个业务调用方 Agent：`multica agent update <agent-id> --instructions <目标正文>`（单值字符串参数；按所用 shell 传入源文件的 LF 正文）。
- Skill 根正文：`multica skill update <skill-id> --content-file <SKILL.md 绝对路径>`。
- 技能内其他文件：`multica skill files upsert <skill-id> --path <技能内相对路径> --content-file <仓库文件绝对路径>`。
- 源文件根：四份 CR Agent = multica CR worktree `cr-prompts-revised/`；两个业务 Agent 与 14 个 Skill = tools CR worktree（`origin.path` 决定技能内相对路径）。

### 3.2 必须同步的线上红项（由 `cmd-09`/`cmd-10` 实测逐条列出）

- 4 份 CR Agent instructions（`cmd-09` ③，live/target sha256 见 §5）。
- 28 项 Skill 线上文件（含 4 项线上尚不存在：`planning-entry.mjs`、`competitive-report.mjs`、`planning-entry.test.mjs`、`competitive-report.test.mjs`）。
- 2 个业务调用方 Agent instructions（`product-planning-agent`、`competitive-analyst-agent`）。

## 4. 人类 owner 执行记录（待执行，执行后由人类或后续 TASK 逐行补填）

| # | 目标（id） | 执行人 | 时间 | 同步后 sha256 | 备注 |
|---|---|---|---|---|---|
| 1 | requirement-writer `6317495b-d913-4d47-be79-0c0b342b03fd` | — | — | — | 待执行 |
| 2 | dev-agent `ff6fcbb6-6bb6-42fb-9d88-03493c771411` | — | — | — | 待执行 |
| 3 | quality-reviewer-agent `2ed1a9de-4c8e-4b78-bfb1-055af99c6681` | — | — | — | 待执行 |
| 4 | cr-coordinator-agent `87ca2271-f4d8-4865-aef1-9a24523e1a20` | — | — | — | 待执行 |
| 5 | product-planning-agent `d0293197-e57a-44e2-9362-8a31b757b79a` | — | — | — | 待执行 |
| 6 | competitive-analyst-agent `cd75e333-57cb-4bf5-b418-7dc9e55799c5` | — | — | — | 待执行 |
| 7 | 14 个 imported Skill（§3 的 C 段逐文件） | — | — | — | 待执行 |

## 5. 证据命令原始输出（`plan.md` §6.2 原样，2026-10-06 本 run 实跑）

### `cmd-08`（repo=multica，cwd=.，exit 0）

```text
✔ 枚举对齐：合同成功集合 = 平台 DispatchStatus - blocked，失败集合含 blocked (1.2629ms)
✔ 枚举对齐：target_unavailable 只在 reason_code 语境出现，合同内不作 status (0.6352ms)
✔ 场景向量：AC-1 AIFI-35 回执重放：status=queued / reason_code=queued 判成功且零误报 (0.1542ms)
✔ 场景向量：coalesced 判成功 (0.0709ms)
✔ 场景向量：deferred 判成功（含 suppress_run / backlog parked） (0.0711ms)
✔ 场景向量：AC-2 blocked + reason_code=target_unavailable 判失败 (0.0965ms)
✔ 场景向量：blocked + 其他 reason_code（runtime_offline）判失败 (0.0662ms)
✔ 场景向量：被 mention 目标缺失 outcome 判失败 (0.6127ms)
✔ 场景向量：AC-2 仅 mention 人类成员（如 PASS 后 @owner）且评论发布成功：不失败 (0.0753ms)
✔ 场景向量：否定 1：未知 status 不判成功（fail-closed） (0.1668ms)
✔ 场景向量：否定 2：评论写入失败不得伪称投递成功 (0.0588ms)
✔ 场景向量：多目标互不掩盖：一成功一 blocked 整体判失败 (0.0606ms)
✔ 无漂移：需维护集合已解析（四份提示词 + 至少一份 bak 副本） (0.5701ms)
✔ 无漂移：requirement-writer.md 内联合同全文且零 enqueued (0.5887ms)
✔ 无漂移：dev-agent.md 内联合同全文且零 enqueued (0.3037ms)
✔ 无漂移：quality-reviewer-agent.md 内联合同全文且零 enqueued (0.273ms)
✔ 无漂移：cr-coordinator-agent.md 内联合同全文且零 enqueued (0.3207ms)
✔ 无漂移：bak\cr-coordinator-agent.md 内联合同全文且零 enqueued (0.259ms)
✔ 无漂移：bak\quality-reviewer-agent.md 内联合同全文且零 enqueued (0.2553ms)
ℹ tests 19
ℹ suites 0
ℹ pass 19
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 65.8275
```

### `cmd-09`（repo=multica，cwd=.，exit 1）

```text
# stdout
deployment-copy requirement-writer sha256=9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08
deployment-copy dev-agent sha256=4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218
deployment-copy quality-reviewer-agent sha256=daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c
deployment-copy cr-coordinator-agent sha256=b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3
imported-skill crctl AI-First-tools@main/skills/shared/crctl
imported-skill validate-doc AI-First-tools@main/skills/shared/validate-doc
imported-skill engineering-docs AI-First-tools@main/skills/shared/engineering-docs
imported-skill cr-review-record AI-First-tools@main/skills/cr/cr-review-record
imported-skill review-code AI-First-tools@main/skills/develop/review-code
imported-skill review-dev-plan AI-First-tools@main/skills/develop/review-dev-plan
imported-skill review-tech-design AI-First-tools@main/skills/develop/review-tech-design
imported-skill write-dev-tasks AI-First-tools@main/skills/develop/write-dev-tasks
imported-skill write-tech-design AI-First-tools@main/skills/develop/write-tech-design
imported-skill review-requirement AI-First-tools@main/skills/requirement/review-requirement
imported-skill write-planning-entry AI-First-tools@main/skills/planning/write-planning-entry
imported-skill planning-draft AI-First-tools@main/skills/planning/planning-draft
imported-skill write-competitive-report AI-First-tools@main/skills/competitive/write-competitive-report
imported-skill requirement-register AI-First-tools@main/skills/requirement/requirement-register

# stderr
线上 instructions 与部署副本不一致: requirement-writer live=e2457e142c68b260b967a7d348941e2961c98b73cee3e3f645aa6af203faf191 target=9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08
线上 instructions 与部署副本不一致: dev-agent live=8df8eb8836aa21337c7d38ed7012fb401064d6595d26a0d51928a6864c922e5e target=4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218
线上 instructions 与部署副本不一致: quality-reviewer-agent live=7f4bd356af6c8b4226732370e0d5877dc2c48cac45507dd738f4aac2a9d5a27d target=daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c
线上 instructions 与部署副本不一致: cr-coordinator-agent live=9285c4301400305d61cc0fd6ec44790fda8228164c53cc7783778b5975036504 target=b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3
```

### `cmd-10`（repo=tools，cwd=.，exit 1）

```text
# stdout
out-of-scope-drift crctl N=4（R8 范围外既有漂移，单列、不参与本 CR 通过判定）: scripts/test/fault-harness.test.mjs,scripts/test/merge-fixture.mjs,scripts/test/register-tx.test.mjs,scripts/test/test-cr.test.mjs
skill-in-sync planning-draft expected=1 online=1 sha256=3a375992069a882126e38a2f90bfaaf68c3098c1626a013fa062ede71435885f

# stderr
线上内容与仓库目标不一致: skills/shared/crctl/SKILL.md
线上内容与仓库目标不一致: skills/shared/crctl/scripts/crctl.mjs
线上内容与仓库目标不一致: skills/shared/crctl/scripts/lib/durable-tx.mjs
本 CR 声明发布文件线上缺失: skills/shared/crctl/scripts/lib/planning-entry.mjs
本 CR 声明发布文件线上缺失: skills/shared/crctl/scripts/lib/competitive-report.mjs
线上内容与仓库目标不一致: skills/shared/crctl/scripts/test/crctl.test.mjs
本 CR 声明发布文件线上缺失: skills/shared/crctl/scripts/test/planning-entry.test.mjs
本 CR 声明发布文件线上缺失: skills/shared/crctl/scripts/test/competitive-report.test.mjs
线上内容与仓库目标不一致: skills/shared/crctl/scripts/test/caller-contract.test.mjs
线上内容与仓库目标不一致: skills/shared/crctl/scripts/test/durable-tx.test.mjs
线上内容与仓库目标不一致: skills/shared/crctl/scripts/test/gate-registry.json
线上内容与仓库目标不一致: skills/shared/validate-doc/SKILL.md
线上内容与仓库目标不一致: skills/shared/engineering-docs/SKILL.md
线上内容与仓库目标不一致: skills/shared/engineering-docs/scripts/src/utils/slug.ts
线上内容与仓库目标不一致: skills/shared/engineering-docs/scripts/src/generators/base.ts
线上内容与仓库目标不一致: skills/shared/engineering-docs/scripts/src/validators/index-sync.ts
线上内容与仓库目标不一致: skills/shared/engineering-docs/scripts/src/__tests__/generators.test.ts
线上内容与仓库目标不一致: skills/shared/engineering-docs/scripts/src/__tests__/validators.test.ts
线上内容与仓库目标不一致: skills/cr/cr-review-record/SKILL.md
线上内容与仓库目标不一致: skills/develop/review-code/SKILL.md
线上内容与仓库目标不一致: skills/develop/review-dev-plan/SKILL.md
线上内容与仓库目标不一致: skills/develop/review-tech-design/SKILL.md
线上内容与仓库目标不一致: skills/develop/write-dev-tasks/SKILL.md
线上内容与仓库目标不一致: skills/develop/write-tech-design/SKILL.md
线上内容与仓库目标不一致: skills/requirement/review-requirement/SKILL.md
线上内容与仓库目标不一致: skills/planning/write-planning-entry/SKILL.md
线上内容与仓库目标不一致: skills/competitive/write-competitive-report/SKILL.md
线上内容与仓库目标不一致: skills/requirement/requirement-register/SKILL.md
线上 instructions 与仓库目标不一致: product-planning-agent live=fc96f7e30d2f5a47951ce3e2c57bf65209a96bf303ccf8fda756c189c3ef1d77 target=317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb
线上 instructions 与仓库目标不一致: competitive-analyst-agent live=8604a61647e9e2c04e0877df942fb8d9b9830cfd036c0c6210ea52d16678b2be target=d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366
```

### `cmd-01` / `cmd-05` / `cmd-07`（TASK-08 与本 TASK 的门槛与回归）

| 命令 | repo | exit | 结果 |
|---|---|---|---|
| `cmd-01` | tools | 0 | 247/247 pass（含 TASK-08 新增的有效绑定段①断言） |
| `cmd-05` | tools | 0 | 125/125 pass（含 `caller-14`/`caller-15` 的 FR-04 逐条断言） |
| `cmd-07` | multica | 0 | 18 PASS（`--- PASS` 行数），`ok .../internal/daemon` |

## 6. 结论与所需人类/后续动作

1. **所需人类动作（AC-B14 的硬前置）**：Ray 在交互式终端按 §3 + §3.1 的命令形态，对 §3.2 列出的 4 个 Agent、2 个业务 Agent 与 28 个 Skill 文件执行 `multica agent update` / `multica skill update` / `multica skill files upsert`，并把执行人/时间/同步后 sha256 记入 §4。
2. **剩余仓库侧项（不需人工，需下一轮本 TASK 完成）**：`CUSTOM.md` 登记 TASK-02 的 daemon 改动（行号 `#114`，M10 daemon 模块；同步《模块索引》M10 行与《CR 索引》）。本轮**未**写入该台账：文件头「`AIFIRST` 计数只升不降」要求同口径实测，而本 run 按 §CUSTOM.md 文件头的口径命令在 `server/ packages/` 实测得 **420 文件 / 443 处 `AIFIRST` / `packages/` 282 处**（三个可比数较第七次同步基线 407 / 420 / 277 均只升不降），但同一命令下「命中处数」实测 2575 与台账记录的 1116 不可比（口径不一致），故本轮不写不可复现的计数行，留给下一轮同口径复测后再登记。
3. **同步后的收口**：重跑 `cmd-09` 与 `cmd-10`（`plan.md` §6.2 原样）应全绿；届时 `CR-2026-075-TASK-09` 方可由 `crctl task done` 登记（`depends-on` 已满足：TASK-07、TASK-08 均 done）。
4. **不得**把本台账的「仓库侧已收敛」读作 AC-B14 通过；AC-B14 的通过条件是 §5 两条命令转绿 + §4 的人类同步记录。
5. **范围外残余登记（不自行扩大范围）**：`cr-prompts-revised/delivery-agent.md`（实测 3 处）与 `squad-CR协调小组.md`（实测 2 处）仍含逐命令 `--workspace <workspace>` 示例，但不在本 CR 的声明文件集内，作为后续 CR 的收敛面登记。
6. **`TASK-09` 与 `TASK-10` 本轮均不 done**：`TASK-10` 的 `depends-on` 含 `TASK-09`，即本 TASK 的登记是 `TASK-10` 完成的前置。
