# `cmd-11` 复验记录：`gate-registry.json#exceptions` 登记 R17 4 例

**CR**: CR-2026-075 · **节点**: `implement-code`（自修复轮，`test-report.status=block` 回修）
**写入者**: dev-agent（本文件为 **additive 留档**；`cmd-11.log` / `cmd-11.txt` / `uncovered-risks.md` 的既有内容逐字未改）

**相关提交**: tools CR worktree `dd909e2`（登记提交）；KB CR worktree 本文件与同目录 `cmd-11-rerun-after-R17-registration.txt` 的提交见本 Issue 本轮回报与 `git log -1`。

## 1. 授权与登记面

- **授权原文**（人类 owner Ray，Issue 评论 `01a10fb1-9ff3-7e56-8a64-5216fa98ceb5`，2026-10-06T05:31:01Z，逐字）：

  > *L2：授权在* `gate-registry.json#exceptions` *登记* `cmd-11` *的 4 个既有红例（*`crctl-summary.test.mjs` *的 summary-03/04/05/06），owner = Ray，到期时间* `<2026-12-31>`*。语义为「豁免既有基线红例」，不是本 CR 引入的回归。登记后实跑* `cmd-11` *复验，若未转绿如实上报，不改测试、不放宽* `crctl.mjs`*。*

- **登记文件**: `skills/shared/crctl/scripts/test/gate-registry.json`（repo=tools，worktree = `resources[tools].worktreePath`，分支 `requirement/CR-2026-075`，登记前 HEAD `08cae73c`）。
- **登记面**: 仅 `exceptions`。`manifest`（28 files / 28 cases）与 `stateMachine`（31 transitions / 15 具名态 / 1 wildcard）逐字未动。
- **本文件的定位**: `uncovered-risks.md#R17` 行内「`gate-registry.json#exceptions` 项数 = 0」是该行写入时刻（2026-10-06T12:54+08:00）的**时点快照**，其留档逐字未改；当前登记面项数已因本裁决变为 **4**，据此**不得**再把 R17 读作「未登记例外」（但也**不得**读作已修复——见 §2）。
- **sha256（LF 规范化，含尾换行，即 `suite-gate` 的 `registry.sha256` 口径）**:

  | 状态 | sha256 |
  |---|---|
  | 登记前 | `f0eaaa944d1a658b4b4c9657289635aa92f9d9a6914c40133ae3234ee10c5db2` |
  | 登记后 | `09cffda81d0dc3b343167318e4d37dc4d90ed0c3234f6c946a8abcdca1a77f2f` |

- **4 条登记条目逐字**（字段形状对齐 `suite-gate.mjs#validateExceptions` 契约与 `contract-scan.test.mjs` 既有自测条目：`id` / `kind` / `reason` / `owner` / `expires` / `match`）:

```json
[
  { "id": "CR-2026-075-R17-summary-03", "kind": "suite-failure", "owner": "Ray",
    "expires": "2026-12-31T23:59:59+08:00",
    "match": "summary-03 逐命令：--detail 输出与金样本三层等价（① 字段集合 ② 稳定值 ③ 易变形态）" },
  { "id": "CR-2026-075-R17-summary-04", "kind": "suite-failure", "owner": "Ray",
    "expires": "2026-12-31T23:59:59+08:00",
    "match": "summary-04 注册命令默认面 = compact summary（为 --detail 面的真子集且严格更少字段）" },
  { "id": "CR-2026-075-R17-summary-05", "kind": "suite-failure", "owner": "Ray",
    "expires": "2026-12-31T23:59:59+08:00",
    "match": "summary-05 未注册命令收到 --detail 与未收到 --detail 均与现状等价（D-9 代价项）" },
  { "id": "CR-2026-075-R17-summary-06", "kind": "suite-failure", "owner": "Ray",
    "expires": "2026-12-31T23:59:59+08:00",
    "match": "summary-06 --detail 是布尔开关，不消费后随 token（位置参数不被吃掉）" }
]
```

  `reason` 字段（上表省略）逐条写明：R17 既有基线红例、非本 CR 引入的回归、根因（`os.tmpdir()` 夹具 + 显式异根 `--workspace` 被已批准的显式异根拒绝语义 `WORKSPACE_CONTEXT_MISMATCH` 拒绝 → stdout 空 → `SyntaxError: Unexpected end of JSON input`）、基线 `061a12f` 同集复现、owner 裁决编号与时刻、到期即清不得静默续期。

- **到期时间编码说明（须 owner 确认的编码决定）**: 裁决写作 `<2026-12-31>`（尖括号为占位记法）；`validateExceptions` 要求 `expires` 带时区偏移且可解析（否则落 `EXCEPTION_SCHEMA_INVALID`，反而更红），故编码为 `2026-12-31T23:59:59+08:00`（workspace 时区 `Asia/Shanghai` 当日末）。若 owner 另有到期语义，只需改该字段。

## 2. 复验实跑（`plan.md` §6.2 的 `cmd-11` 行原样：repo=tools、cwd=`.`、`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`、timeout=3600）

- **原始输出**: `test-evidence/cmd-11-rerun-after-R17-registration.txt`（LF sha256 `78ee1079d3f41da3e5f3f9dc4aad1a47a9ce11d47dfc87fc9abca83e4db291e8`；含 `started_utc=2026-10-06T06:03:15Z` / `finished_utc=2026-10-06T06:12:39Z`、duration 563272 ms）。
- **结果：未转绿** —— `verdict=block`、`exit_code=1`、`converged=true`、`files_executed=28`、`cases_executed=693`、`registry.sha256=09cffda8…`、`exceptions_count=4`。
- **check 面变化（本次复验的关键机器事实）**:

| check | 登记前 | 登记后 | 说明 |
|---|---|---|---|
| `SUITE_FAILURES_UNREGISTERED` | **false**（未登记失败 4 例） | **true** | 4 例已被未到期 `suite-failure` 例外覆盖，不再计入未登记失败 |
| `EXCEPTION_NOT_OBSERVED` | true | true | 4 条例外**全部**在本次运行中被观测到（无陈旧登记） |
| `SUITE_REPORT_UNPARSEABLE` | true | **false** | detail：「存在非零退出码但 TAP 未暴露任何失败（结构不完整，禁止静默判绿）」 → `verdict=block` |

- **未转绿根因（读码 + 实跑一致）**: `suite-gate.mjs` 的安全网判据是
  `if (records.some((r) => r.exit_code !== 0) && triggers.length === 0) trigger('SUITE_REPORT_UNPARSEABLE', …)`。
  例外把 4 例失败全部覆盖后不再产生任何 trigger，而**被豁免文件自身仍以 `exit_code=1` 结束**（`crctl-summary.test.mjs` 的 4 例真失败依旧存在），于是安全网把「全部失败均已登记例外」误判为「TAP 未暴露任何失败」。该安全网**没有** `suppressed_by` 通道（对照：非收敛分支的 `SUITE_NONCONVERGENCE` 有）。
- **结论（不预设、按实跑）**: 在 `suite-gate.mjs` 当前实现下，**「豁免某文件的全部失败」无法使聚合门禁转绿**；例外机制只能容忍失败的**真子集**。故 owner 裁决 A（登记例外）单独执行**不解除本 CR 的 block**。
- 该结论**不改变** R17 的事实面：4 例仍是既有基线红项、非本 CR 引入的回归，也**不得**被读作已修复或已通过；`crctl-summary.test.mjs` 本轮 8 例 4 败，与登记前、与本 CR 基线复现同集。
- 副作用面：本次登记**未**影响其余 27 个测试文件与 693 例用例数（逐文件用例数与 `manifest.cases` 基线核对仍全绿，`crctl.test.mjs` 247 例仍全绿，含其「登记集合 ≡ 推导集合」的状态机口径断言）。

## 3. 本次登记引入的新事实（授权文本未预见，须 owner 决策）

- `gate-registry.json` 属本 CR 声明发布集（`cmd-10` 的 `EXPECT` 30 项之一）。
- 登记前后的**线上副本 vs 仓库目标**（`multica skill get <crctl-skill-id> --with-content`，只读）:

| 时点 | 线上副本 (LF, trim) | 仓库目标 (LF, trim) | `cmd-10` 断言 |
|---|---|---|---|
| 登记前 | `af3a208ce3de1220b20f18201319e05ee3032df16c26a08edf754ea7fcf858aa` | 同左（`exceptions: []`） | 相等 ✅（与记录中 `cmd-10` exit 0 一致） |
| 登记后 | `af3a208ce3de1220b20f18201319e05ee3032df16c26a08edf754ea7fcf858aa`（`exceptions: []`，未同步） | `1e37abfaf64b7f47cec4ef8c48ed307d51c0729795abd3db8fced2464437d3c4`（4 条） | **不等** ❌ |

- `cmd-10` 只读复跑（**诊断探针，不属证据命令集、不新增证据 ID**；args 逐字取自 `plan.md` §6.2 的 `cmd-10` 行）: **exit 1**，stderr 原样 `线上内容与仓库目标不一致: skills/shared/crctl/scripts/test/gate-registry.json`（其余 13 个 skill 与 2 个 Agent instructions 仍逐字一致；R8 的 4 项范围外既有漂移仍单列）。
- **影响面**: `crctl test` 的 `overall` 判据是「任一命令非零即 `block`」（`workspace-transactions.mjs`：`if (r.status !== 0 || timedOut) overall = 'block'`）。因此**即使** `cmd-11` 将来转绿，`cmd-10` 仍会使 `test-report.status=block`，**除非**平台侧 crctl skill 副本同步为含 4 条例外的版本。
- **该同步的责任方 = 人类 owner（Ray，平台管理员）**：依据 `tasks/TASK-09.md`「执行人 = 人类 owner（Ray，平台管理员…）；本 TASK 不代执行、不写平台配置」与「环境边界：…不写平台配置、不代人类执行同步」。agent 侧零平台写入。
- **撤回成本**（若 owner 判断该路径不值得继续）：tools CR worktree `git checkout -- skills/shared/crctl/scripts/test/gate-registry.json`，并把本记录标为已撤回；`gate-registry.json` 本身无其它改动面。

## 4. 本轮未做（边界，逐条）

- 未改 `crctl-summary.test.mjs`（不在本 CR 声明文件集）、未改 `suite-gate.mjs`（不在 `sdd.md` §9 `scope_in`）。
- 未放宽 `crctl.mjs` 的显式异根拒绝（FR-04 已批准语义保持原样）。
- 未写平台配置、未同步线上副本、未改 `test-report.md` 机器区 / `review-loop.yml` / `traceability.yml` / `review-annotations`。
- 未代行 `write-test-report` 节点、未委派 `write-test-report` / `review-code`。
- 未删改 R17 留档与既有 `cmd-11.log` / `cmd-11.txt` 的任何内容。

## 5. 无效探针（如实登记）

第一次 `cmd-11` 复跑（`started_utc=2026-10-06T05:53:21Z`）多出 1 例失败：`CR-2026-064 FR-11 零命中断言：整树扫描面对两个恢复字段名零命中`（`contract-scan.test.mjs`）。根因是**本轮诊断脚本**在 tools CR worktree 根写下的临时文件 `_probe-skill.json`（2,181,763 B，平台导入副本全文，含被测测试源码中的退役字段名 `recoverCommand`/`recover_command`），落在该断言的整树扫描面内（扫描面只排除 `.git` / `node_modules` 两个路径段与两条精确路径）。删除该临时文件后复跑该失败即消失。

该次输出**不构成证据**，其原始文件已删除，本段为其事实登记（不隐藏、不充作通过面）。
