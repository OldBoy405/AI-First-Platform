---
id: CR-2026-075-effective-version
type: EVIDENCE
cr-ref: CR-2026-075
source-task: CR-2026-075-TASK-09
target-version: 0.48
updated: 2026-10-06T04:37:14.835+00:00
---

# CR-2026-075 生效版本台账（部署副本收敛 / 合同对齐 / 平台同步清单）

## 1. 状态（机器事实，不采信评论文本）

| 项 | 事实 | 判定 |
|---|---|---|
| 仓库侧收敛（四份部署副本 + 两份维护副本 + 合同对齐 + CHANGES.md + `CUSTOM.md` 登记） | 已完成（见 §2） | ✅ |
| `cmd-08`（合同与副本无漂移） | 19/19 pass（修正前基线 18 pass / 1 fail） | ✅ |
| `cmd-09` ① 部署副本收敛 + 显式 CR-ID 保留 | 四份 `--workspace <workspace>` 出现次数全为 0；`CR-ID`/`cr_id` 均在；四份副本 LF sha256 见 §5 | ✅ |
| `cmd-09` ② 14 个 imported Skill 取用路径台账 | 14 行 `imported-skill` 与声明一致（`AI-First-tools@main/skills/...`） | ✅ |
| `cmd-09` ③ 四份 CR Agent 线上 instructions 与部署副本逐字一致 | **一致（4/4，LF 全等）**，线上 sha256 = §3 A 段目标值 | ✅ |
| `cmd-10` 线上发布文件集与仓库目标逐字一致 | **一致（30/30 逐文件存在且逐字相等）**；范围外既有漂移 4 项（R8，单列、不参与通过判定） | ✅ |
| 平台侧同步（TASK-09 验收前置） | **已执行**：owner Ray，2026-10-06 12:27–12:29 +08:00（平台 `updated_at`），逐条目标与同步后 sha256 见 §4 | ✅ |

按 TASK-09 卡「前置未完成或比对仍红时：本 TASK 不 done」，本轮前置已闭合且三条命令全绿：**AC-B14 的通过条件（§4 人类执行记录 + `cmd-08`/`cmd-09`/`cmd-10` 全绿）已满足**，TASK-09 由 `crctl task done CR-2026-075 --task CR-2026-075-TASK-09` 登记。证据以 §4 / §5 与 §3 C′ 为准；本行不对 merge / 人工审批作任何断言，也不得把「仓库侧已收敛」单独读作 AC-B14 通过。

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
| `CUSTOM.md` | **已登记**：正文行 `#114`（M10 daemon 运行时与 CR 事件采集；TASK-02 的 daemon 改动 `pipeline_task.go` / `daemon.go` / `pipeline_task_test.go` / `cr_workspace_binding_test.go`，4 文件 +632/−64，基线 `ae90689fa`）+ 《模块索引》M10 行（7 → 8 行、行号补 `#114`）+ 《CR 索引》CR-2026-075 行（`🚧 developing（未合并）`、行号 `#114`、模块 `M10+M12`）+ 文件头《CR-2026-075 落码后复核》计数基线（现行口径 414 文件 / 1151 处 / `AIFIRST` 442 处 / `packages/` 278 处，三数较第七次基线只升不降） | ✅ |

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

### C′. 30 个 EXPECT 文件的同步后逐文件 sha256（= §3 C 同名逐文件目标值）

来源：`multica skill get <id> --with-content` 的线上 `content`（`SKILL.md`）与 `files[].content`，逐文件 LF 归一后取 sha256。本节点独立复算 `same=30 / diff=0`（与 §3 C 元数据同源的仓库目标逐字节相等，LF、尾换行不裁剪）。`#7` 行的复合值口径见 §4。

**crctl** id=`ab178d6f-f007-4150-a576-c1d9c5c0a0e2` origin=`skills/shared/crctl`
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

**validate-doc** id=`828a1d26-cc73-4b45-b9dc-708ca117cf66` origin=`skills/shared/validate-doc`
- `skills/shared/validate-doc/SKILL.md` sha256=c8601d37171b10b8b1e15432fcd9edb0a003dbe9f11099dbdc126872900821a0

**engineering-docs** id=`13c91eb2-1f3b-4fec-8035-cd94eca3dc09` origin=`skills/shared/engineering-docs`
- `skills/shared/engineering-docs/SKILL.md` sha256=51043b283e8ef6cbb02cab29dc08c2dc9e1a073837350982f4afbbf0f642b1f6
- `skills/shared/engineering-docs/scripts/src/utils/slug.ts` sha256=2359edc2745946452e1cb4b19e78b5b9a371508a6467df47352ab9acafae142c
- `skills/shared/engineering-docs/scripts/src/generators/base.ts` sha256=78882032b8470926a994c570483e541110c7f906ff9c28d218771d2baab6800f
- `skills/shared/engineering-docs/scripts/src/validators/index-sync.ts` sha256=075b29e9c2ede6f4308b5cd9978b635ffb6f1567886981eac0c149237a21a5d6
- `skills/shared/engineering-docs/scripts/src/__tests__/generators.test.ts` sha256=43115442dcb919e47ad6aaaa20ae78113056aa239f8a94016b29ce8517cfd211
- `skills/shared/engineering-docs/scripts/src/__tests__/validators.test.ts` sha256=a26a097021b1e51c1d6229e1225ed3e2de6f4ce0ececc21dbfa571f5e8ae7b40

**cr-review-record** id=`bab10e81-6aee-47fa-b94e-eba248ccb57b` origin=`skills/cr/cr-review-record`
- `skills/cr/cr-review-record/SKILL.md` sha256=f02c076c221e2f2cc20b7df3d8deb356a23b71ae29c55664369616fc2ed9d299

**review-code** id=`c40d36e6-7107-4068-b246-d6d61b31aa0b` origin=`skills/develop/review-code`
- `skills/develop/review-code/SKILL.md` sha256=20f803ad16193d8646213fbce8c6d43b2a7c893d5763cc2f8f48622e76f96ac2

**review-dev-plan** id=`a0df9007-bec4-42fe-97ae-00e0a94f55d4` origin=`skills/develop/review-dev-plan`
- `skills/develop/review-dev-plan/SKILL.md` sha256=4812a020cd1b2ebcb61c3d1c2836a08d30c9eff44f0a0c6aa8b726fe5a09d57a

**review-tech-design** id=`de47861c-d587-48e0-a97b-765534234bcf` origin=`skills/develop/review-tech-design`
- `skills/develop/review-tech-design/SKILL.md` sha256=6f9fe499cb3608c26596cd6f049c0c839735c8b7346848c692f0f63c3fd4c9fe

**write-dev-tasks** id=`97dd7cae-8a62-4a8e-b128-54a53aabffc8` origin=`skills/develop/write-dev-tasks`
- `skills/develop/write-dev-tasks/SKILL.md` sha256=ca0c0aa5a2e92472f5f90d9b4d2c4b85d62612e078414763216d9ca637e1a2ff

**write-tech-design** id=`b5a3d433-27c1-4163-bf6b-fa4338d9de1c` origin=`skills/develop/write-tech-design`
- `skills/develop/write-tech-design/SKILL.md` sha256=0e4f0c44b9c0bcfc1e6ff38d5adfd7862dc482a6ef3b637a1d6e6692d485b45e

**review-requirement** id=`e548be57-beb2-46f3-b129-952fe545da86` origin=`skills/requirement/review-requirement`
- `skills/requirement/review-requirement/SKILL.md` sha256=9cc8d6f5d490ef4646210c1357e0207ba0ef1cebcda06a2837343b01a7af0e82

**write-planning-entry** id=`56c66d7a-2b87-4f5a-978b-c28c1ed730b4` origin=`skills/planning/write-planning-entry`
- `skills/planning/write-planning-entry/SKILL.md` sha256=6bfad97b627fdc4a1bb1bf0ba6f9a30eced090af3778b88e41405fff192e955e

**planning-draft** id=`1e2c7337-42e7-4104-ab65-a3a91e652261` origin=`skills/planning/planning-draft`
- `skills/planning/planning-draft/SKILL.md` sha256=77528dfd05b44677b977e6e619512f11060e7154e5592f053e13ad01caf20257

**write-competitive-report** id=`8e21e287-2c35-4b07-a493-716e9b06e966` origin=`skills/competitive/write-competitive-report`
- `skills/competitive/write-competitive-report/SKILL.md` sha256=04c626267429bb2201d18f5b4dab14fde9e4a517419e53a32b37608ac52744c6

**requirement-register** id=`fc84ae1a-2417-4a69-8d4f-64b0261c1314` origin=`skills/requirement/requirement-register`
- `skills/requirement/requirement-register/SKILL.md` sha256=2368164029dc5e5946781a843035fd9d972ff0367e4b173cf3f61a03ed5cbfdd

### 3.1 命令形态

- 四份 CR Agent 与两个业务调用方 Agent：`multica agent update <agent-id> --instructions <目标正文>`（单值字符串参数；按所用 shell 传入源文件的 LF 正文）。
- Skill 根正文：`multica skill update <skill-id> --content-file <SKILL.md 绝对路径>`。
- 技能内其他文件：`multica skill files upsert <skill-id> --path <技能内相对路径> --content-file <仓库文件绝对路径>`。
- 源文件根：四份 CR Agent = multica CR worktree `cr-prompts-revised/`；两个业务 Agent 与 14 个 Skill = tools CR worktree（`origin.path` 决定技能内相对路径）。

### 3.2 同步前实测的线上红项（**已于 2026-10-06 由 owner Ray 同步闭合**，见 §4/§5；本节保留为同步前清单）

- 4 份 CR Agent instructions（`cmd-09` ③，live/target sha256 见 §5）。
- 28 项 Skill 线上文件（含 4 项线上尚不存在：`planning-entry.mjs`、`competitive-report.mjs`、`planning-entry.test.mjs`、`competitive-report.test.mjs`）。
- 2 个业务调用方 Agent instructions（`product-planning-agent`、`competitive-analyst-agent`）。

## 4. 人类 owner 执行记录（owner Ray 执行，2026-10-06；`同步后 sha256` 由本节点从平台现值复算）

**复算口径**（取值来源与算法，便于第三方独立重算）：

- **执行人 / 时间**：执行人为人类 owner Ray（平台侧写权限唯一在 owner，本节点不代写）；时间取平台记录时间 `updated_at`（`multica agent list` / `multica skill get <id> --with-content`，UTC → Asia/Shanghai 换算），不取任何一方的自报时间。

- **单目标 sha256（`#1`–`#6`）** = `sha256(LF 归一后的线上 instructions 正文)`，尾换行不裁剪。与 `cmd-09` 的 `agent-in-sync … sha256=` 同值、与 §3 A/B 段仓库目标值全等。

- **逐文件 sha256（`#7` 的 30 个文件）** = 线上 `content` / `files[].content` 逐个 LF 归一后取 sha256；30 个文件线上值与 §3 C 段仓库目标值**逐字节相等**（本节点独立复算 `same=30 / diff=0`；`cmd-10` 以尾换行宽容口径同向断言）。逐文件值见 §3 C′。

- **`#7` 行复合值（本表单元格内）** = `sha256(30 行 "<relative-path>:<sha256(LF 正文)>" 按该串升序以 LF 连接、末尾保留 LF)` = `c0a1b015ff755698bb973a6379556d426a3114f5e8ed4886a8901dd01c288d45`。14 个 Skill / 30 个文件无法用单个字节级标量表达，故用本口径并把 30 行原样放在 §3 C′；口径与 `cmd-10` 的 per-skill 复合值不同（后者为 `sha256(EXPECT 顺序 "<skill 内相对路径>:<sha256>" 以 LF 连接)`，仅该命令自身对账用，原样见 §5）。

| # | 目标（平台 id） | 执行人 | 时间（平台 `updated_at`，+08:00） | 同步后 sha256（平台现值复算） | 备注 |
|---|---|---|---|---|---|
| 1 | requirement-writer `6317495b-d913-4d47-be79-0c0b342b03fd` | Ray | 2026-10-06 12:27:18 | `9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08` | §3 A 段仓库目标值全等；`cmd-09` ③ 绿 |
| 2 | dev-agent `ff6fcbb6-6bb6-42fb-9d88-03493c771411` | Ray | 2026-10-06 12:28:54 | `4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218` | 同上 |
| 3 | quality-reviewer-agent `2ed1a9de-4c8e-4b78-bfb1-055af99c6681` | Ray | 2026-10-06 12:27:18 | `daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c` | 同上 |
| 4 | cr-coordinator-agent `87ca2271-f4d8-4865-aef1-9a24523e1a20` | Ray | 2026-10-06 12:29:36 | `b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3` | 同上 |
| 5 | product-planning-agent `d0293197-e57a-44e2-9362-8a31b757b79a` | Ray | 2026-10-06 12:27:18 | `317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb` | 与 §3 B 段目标值全等；`cmd-10` 绿 |
| 6 | competitive-analyst-agent `cd75e333-57cb-4bf5-b418-7dc9e55799c5` | Ray | 2026-10-06 12:27:18 | `d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366` | 同上 |
| 7 | 14 个 imported Skill（§3 C′ 的 30 个文件） | Ray | 2026-10-06 12:27:18–12:27:19（本批未写入：planning-draft=2026-09-28 20:24:57——内容本已一致，见 §5 `cmd-10`） | 逐文件值见 §3 C′；复合值 `c0a1b015ff755698bb973a6379556d426a3114f5e8ed4886a8901dd01c288d45` | 口径见本节第 4 条；14 个 Skill 的 per-skill 复合值原样见 §5 `cmd-10` 的 `skill-in-sync` 行 |

## 5. 证据命令原始输出（`plan.md` §6.2 原样，2026-10-06 本轮（平台同步后）复跑）

### `cmd-08`（repo=multica，cwd=.，exit 0）

```text
✔ 枚举对齐：合同成功集合 = 平台 DispatchStatus - blocked，失败集合含 blocked (1.3322ms)
✔ 枚举对齐：target_unavailable 只在 reason_code 语境出现，合同内不作 status (0.5842ms)
✔ 场景向量：AC-1 AIFI-35 回执重放：status=queued / reason_code=queued 判成功且零误报 (0.1503ms)
✔ 场景向量：coalesced 判成功 (0.0727ms)
✔ 场景向量：deferred 判成功（含 suppress_run / backlog parked） (0.069ms)
✔ 场景向量：AC-2 blocked + reason_code=target_unavailable 判失败 (0.0959ms)
✔ 场景向量：blocked + 其他 reason_code（runtime_offline）判失败 (0.0667ms)
✔ 场景向量：被 mention 目标缺失 outcome 判失败 (0.4842ms)
✔ 场景向量：AC-2 仅 mention 人类成员（如 PASS 后 @owner）且评论发布成功：不失败 (0.0705ms)
✔ 场景向量：否定 1：未知 status 不判成功（fail-closed） (0.1164ms)
✔ 场景向量：否定 2：评论写入失败不得伪称投递成功 (0.0557ms)
✔ 场景向量：多目标互不掩盖：一成功一 blocked 整体判失败 (0.0676ms)
✔ 无漂移：需维护集合已解析（四份提示词 + 至少一份 bak 副本） (0.3229ms)
✔ 无漂移：requirement-writer.md 内联合同全文且零 enqueued (0.3794ms)
✔ 无漂移：dev-agent.md 内联合同全文且零 enqueued (0.2889ms)
✔ 无漂移：quality-reviewer-agent.md 内联合同全文且零 enqueued (0.2708ms)
✔ 无漂移：cr-coordinator-agent.md 内联合同全文且零 enqueued (0.495ms)
✔ 无漂移：bak\cr-coordinator-agent.md 内联合同全文且零 enqueued (0.3156ms)
✔ 无漂移：bak\quality-reviewer-agent.md 内联合同全文且零 enqueued (0.2784ms)
ℹ tests 19
ℹ suites 0
ℹ pass 19
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 65.997
```

### `cmd-09`（repo=multica，cwd=.，exit 0）

```text
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
agent-in-sync requirement-writer sha256=9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08
agent-in-sync dev-agent sha256=4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218
agent-in-sync quality-reviewer-agent sha256=daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c
agent-in-sync cr-coordinator-agent sha256=b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3
cmd-09 ok: 部署副本收敛与 imported Skills 取用路径零漂移；四份 CR Agent 线上 instructions 与部署副本逐字一致（LF）
```

### `cmd-10`（repo=tools，cwd=.，exit 0）

```text
out-of-scope-drift crctl N=4（R8 范围外既有漂移，单列、不参与本 CR 通过判定）: scripts/test/fault-harness.test.mjs,scripts/test/merge-fixture.mjs,scripts/test/register-tx.test.mjs,scripts/test/test-cr.test.mjs
skill-in-sync crctl expected=12 online=65 sha256=32b64ffe4d52f4c46226ed0a41e6a87eb19583b0502325b0e77654ef67019ed7
skill-in-sync validate-doc expected=1 online=1 sha256=81fe35097c7183358287279d5591469e0480f99dc3a7255c38478bcbf5af23ac
skill-in-sync engineering-docs expected=6 online=46 sha256=786931349b65656121ecd7ace84710d5eb5f4b0993bfd57af0a02cdad5c83c5b
skill-in-sync cr-review-record expected=1 online=1 sha256=85efa748526d46e30928246786bfe93db74a94ba5af4f2989ef98a349af9615b
skill-in-sync review-code expected=1 online=1 sha256=b376a8fbceaa6c836ddb85e5690800999a51b7127159257a1bd69359032e6ca4
skill-in-sync review-dev-plan expected=1 online=1 sha256=21c3ce2a62409f6ab668c62a441507d22f863310a28e42f353df7172c118b264
skill-in-sync review-tech-design expected=1 online=1 sha256=ad232d7bae285ab1c2603aa0fae35275d341e6cec5f385cabaa5d1c471658129
skill-in-sync write-dev-tasks expected=1 online=1 sha256=5988d3907a49ad2e0247d3c23007a87e0e716df20b8fa2563b3eb373810420fa
skill-in-sync write-tech-design expected=1 online=1 sha256=a35d5cb3ccc464421bd306de99efac4e53ded0a5a09b5b38a5ac96fec922adf4
skill-in-sync review-requirement expected=1 online=1 sha256=d1da5aae30b98ca2fe72eb3db19d0163723ae19bac4c71216d226f781926848b
skill-in-sync write-planning-entry expected=1 online=1 sha256=5926803104836c1dcb08dd7b2b0b22a0ac62fc0545bbd62bf79a6b6e58550e8c
skill-in-sync planning-draft expected=1 online=1 sha256=3a375992069a882126e38a2f90bfaaf68c3098c1626a013fa062ede71435885f
skill-in-sync write-competitive-report expected=1 online=1 sha256=48a5a66f7ed9c9f5389c8f29a085c213ff9ccb14b5d601371e61c2631e7b33bc
skill-in-sync requirement-register expected=1 online=3 sha256=1c955be7799b69cbd4400edb1bbe6a4bcf0bf8789a031e8f2c0863053f8a7fe7
agent-in-sync product-planning-agent sha256=317d5e31d9eb91277b8c3e9bac7ee0de49d25c2113820073696779ad52c9adfb
agent-in-sync competitive-analyst-agent sha256=d899dbe978db7ac2394af5ec0fa568c5984d8353196f1226515abef7bbcce366
cmd-10 ok: 本 CR 声明发布集全覆盖（expected=30 个文件线上存在且与仓库目标逐字一致，LF）；范围外既有漂移单列 4 项不计入通过判定（R8）；规划/竞品两个业务调用方 Agent instructions 与仓库目标逐字一致
```
### `cmd-01` / `cmd-05` / `cmd-07`（TASK-08 轮次的阈值与回归记录，本轮未复跑；全量回归归档属 TASK-10）

| 命令 | repo | exit | 结果 |
|---|---|---|---|
| `cmd-01` | tools | 0 | 247/247 pass（含 TASK-08 新增的有效绑定段①断言） |
| `cmd-05` | tools | 0 | 125/125 pass（含 `caller-14`/`caller-15` 的 FR-04 逐条断言） |
| `cmd-07` | multica | 0 | 18 PASS（`--- PASS` 行数），`ok .../internal/daemon` |

## 6. 结论与后续动作

1. **AC-B14 已闭合**：平台侧同步由 owner Ray 执行（§4 逐条记录 + 平台 `updated_at`），`cmd-08` 19/19、`cmd-09` exit 0（①副本收敛/②取用路径台账/③线上 instructions 三条全绿）、`cmd-10` exit 0（30/30 本 CR 声明发布文件线上存在且与仓库目标逐字相等 + 2 个业务调用方 Agent 一致）。R8 范围外既有漂移 4 项（`skills/shared/crctl/scripts/test/{fault-harness,merge-fixture,register-tx,test-cr}.test.mjs`）单列、不计入本 CR 通过判定，也不以现存线上子集声称一致。
2. **仓库侧与台账侧已闭合**：四份部署副本 + 两份维护副本收敛（短提示零逐命令 workspace 示例、显式 CR-ID 保留）、`delegation-contract.md` 成功集合对齐平台枚举（补 `steered`，`cmd-08` 19/19）、`CUSTOM.md` 三表登记（正文 `#114` / 《模块索引》M10 8 行 / 《CR 索引》CR-2026-075 行 / 文件头计数基线）。
3. **后续 TASK**：`CR-2026-075-TASK-10`（按 plan §6.2 原样复跑 `cmd-01`～`cmd-11`、归档 `test-evidence/` 与未覆盖风险清单）在 TASK-09 登记后解除 `depends-on`；`write-test-report` 与 `review-code` 引用同一份 `test-evidence/`，不复制、不改写结果。
4. **范围外残余登记（不自行扩大范围）**：`cr-prompts-revised/delivery-agent.md`（实测 3 处）与 `squad-CR协调小组.md`（实测 2 处）仍含逐命令 `--workspace <workspace>` 示例，均不在本 CR 的声明文件集内，作为后续 CR 的收敛面登记。
5. **不得**把「仓库侧已收敛」单独读作 AC-B14 通过；通过判定以 §4 的人类同步记录 + §5 三条命令全绿为准（本轮两者均已具备，判定为闭合）。
