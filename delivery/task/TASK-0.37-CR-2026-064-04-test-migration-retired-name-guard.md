---
spec-id: ai-first-platform
version: "0.37"
id: CR-2026-064-TASK-04
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "测试迁移与契约退役保护：7 个既有测试改结构断言、contract-scan 整树扫描面与八条命中用例、shell 逃逸守卫"
slug: test-migration-retired-name-guard
status: pending
estimate: 16h
depends-on: [CR-2026-064-TASK-01, CR-2026-064-TASK-02, CR-2026-064-TASK-03]
created: 2026-09-13T22:15:00+08:00
---

# CR-2026-064-TASK-04 —— 测试迁移、契约退役保护与守卫断言

覆盖 FR：**FR-9、FR-11、FR-12、FR-14（六类归档的实现面）、FR-13（回归面）**（SDD §4.4、§4.5、§4.5-7）；变更组 **G4**；主责仓：`tools`。

## 1. 任务描述

**目标**：把 7 个既有测试文件的字符串包含断言原位迁移为结构与 argv 断言（含 6 类 reason 向量与参数边界向量）；扩展 `contract-scan.test.mjs`（新增 `RETIRED_RECOVERY` 退役名单、整树派生扫描面、两项精确路径排除、八条代表性命中用例、不误报正反用例、索引一致性硬失败）；新增 `shell: true` / `Invoke-Expression` 守卫断言。

**背景**：既有断言只能证明「某片段出现过」，不能证明 argv 边界正确（PRD §1.1 第 4 类缺陷）。退役保护复用 CR-2026-041 建立的既有静态扫描机制（不新建扫描器），并把两个恢复字段名的扫描面改为**整树派生 + 两项被断言的精确路径排除**——活跃性由「是否被显式排除」定义（D-5）。

**输入条件**：`tools` CR worktree（HEAD `81d31b8…`）；**CR-2026-064-TASK-01 / CR-2026-064-TASK-02 / CR-2026-064-TASK-03 全部完成**（断言对象即它们的输出与文本）；SDD `6c5c9a11`（sha256 `d9f727b6…`）只读。

### 1.1 合并后门禁的硬约束（本 TASK 的最高优先级约束，SDD §4.5-7 / 计划 R-13）

合并后 CI 全量步骤为 `node skills/shared/crctl/scripts/test/suite-gate.mjs --run`，它对 `skills/shared/crctl/scripts/test/` 施加两条机器判定（`suite-gate.mjs:437-453`）：

- **(a) 文件集合等式**：磁盘测试文件集合 ≡ `gate-registry.json#manifest.files`（恰 **21** 个文件），**且被真实 spawn 的集合也须与之一致**（`SUITE_MANIFEST_FILE_DRIFT`）；
- **(b) 用例数下限**：每个文件的顶层用例数不得低于 `manifest.cases`（`SUITE_MANIFEST_CASE_DROP`，`suite-gate.mjs:452-453`）。

本 TASK 迁移的 7 个文件与 `contract-scan.test.mjs` 全部落在该目录内，因此：

1. 字符串包含断言 → 结构断言的改写必须**逐用例原位替换**，**不得删除、合并、重命名或跳过任何顶层用例**（新增用例允许，只增不减）；
2. **不得新增该目录下的测试文件**（会撞文件集合等式）；
3. **不得修改** `gate-registry.json` 的 `manifest.files` / `manifest.cases` / `exceptions`——其唯一写入口是人类编辑 + git commit（CR-2026-065 SDD TDEC-2），不属本 CR `scope_in`；因 `exceptions: []`，**本 CR 内没有可用例外通道**，迁移必须自证全绿。

本节点实测基线（`tools@81d31b8`）：`manifest.files` = 21、`manifest.cases` 合计 = **578**、`exceptions: []`、磁盘集合 ≡ `manifest.files`。逐文件下限：`archive-tx` 24 / `checkpoint-tx` 23 / `crctl` 224 / `merge-tx` 17 / `register-tx` 26 / `workspace-freshness` 32 / `writeback-tx` 33 / `contract-scan` 17。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | `TASK-01 RED-1` 标题、`L259`、`L317` → 结构断言（`executable`/`args`/`requiresTTY`/`promptFor`） |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 测试标题、`L224` → 同上 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 成功结果字段集用例、reset 双向量用例、rollback 用例、gate 双向量用例 → 同上；补 6 类 reason 向量与 `promptFor` 断言 |
| `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 测试标题、`L286`、`L301` → 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot |
| `skills/shared/crctl/scripts/test/register-tx.test.mjs` | `L143`、`L164`、`L637` 标题、`L650`（`recover_command`）→ 同上；双投影用例改为单投影断言 |
| `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | `L269` → 同上 |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | `L818` 标题、`L831` → 断言 `--target-version` 为独立元素且值正确 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 新增 `RETIRED_RECOVERY`、整树扫描面与排除断言、八条命中用例、不误报正反用例、`shell: true`/`Invoke-Expression` 守卫；**既有 `FORBIDDEN` / `RETIRED` / `ACTIVE_PATHS` 与既有断言逐字不动**（CR-2026-041 的 `zero_diff` 面） |

**不得触碰**（§9 `zero_diff` / 非本 CR 范围）：`gate-registry.json`（登记面唯一写入口是人类编辑 + git commit）、`suite-gate.mjs`（CR-2026-065 交付物）、`assertion-sources.mjs`、`skills/writeback/scripts/test/**`（不在登记面内，本 CR 无需改动）、`.github/workflows/**`、`pipeline-templates/**`。

## 3. 实现要点

1. **结构断言模板**（SDD §4.5-1，逐字）：

   ```js
   const CRCTL_JS = path.resolve(import.meta.dirname, '..', 'crctl.mjs');   // 每个测试文件内一行

   assert.equal(res.recovery.executable, 'node');
   assert.deepEqual(res.recovery.args, [CRCTL_JS, 'checkpoint', cr, '--workspace', ws]);
   assert.equal(res.recovery.cwd, ws);
   assert.equal(res.recovery.requiresTTY, false);
   assert.deepEqual(res.recovery.promptFor, []);
   ```

2. **不做脆弱快照**（§4.5-2）：只断言 `recovery` 内的确定字段与该生产者相关的其它字段；临时路径按元素与顺序断言，**不对完整 JSON 做快照**。
3. **参数边界向量**（§4.5-3，每类生产者至少一条）：CR-ID / workspace / branch-ref 各占独立元素；含空格的临时路径无需引号即正确传递；元素顺序与 CLI 合同一致。
4. **用户输入向量**（§4.5-4，`review-loop reset` 6 类）：`normal reason`、含双引号、含分号、含换行、`$(substitution)`、反引号表达式 —— 每类断言四件事：`args` 不含该值、`promptFor` 含 `reason`、`requiresTTY === true`、`JSON.stringify(recovery)` 中该值不出现（数据而非 shell command）。**必须用既有 `runCrctlInTty` 包装**（reset 是 TTY 专用入口，否则用例会因非 TTY 提前退出而恒真/恒假）。
5. **合同缺失向量**（§4.5-5）：四类场景由提示词合同承接（CR-2026-064-TASK-03），生产者侧对应保证是「构造器只产出合法形状 + 每类生产者结构断言」，**不新增运行期校验代码**（D-6：不伪造运行期测试）。
6. **shell 逃逸守卫**（§4.5-6）：新增断言 —— `crctl.mjs` 与 `lib/*.mjs` 内不存在 `shell: true` / `Invoke-Expression`（AC-04），与既有 `spawnSync(..., { shell: false })` 事实一致。
7. **contract-scan 扩展**（SDD §4.4，逐条落实）：
   - `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']` 适用于**整树扫描面**；既有 `RETIRED`（三个退役 Skill 名）**保持既有显式 `ACTIVE_PATHS` 与既有范围不变**（§4.4-1 分名分范围；不可并入整树面，否则历史报告/夹具与合法名单立刻误报）；
   - 扫描面 = 工作树整树枚举（`readdirSync(..., { withFileTypes: true, recursive: true })`，按**路径段**跳过 `.git` 与 `node_modules`）− 两项**精确路径**排除（扫描器自身 `contract-scan.test.mjs`、历史 traceability `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`）；**不按目录、不按扩展名、不按文件名推断活跃性**；
   - 冻结：`assert.deepEqual(EXCLUDED, [<扫描器自身>, '…/fixtures/traceability-191k.yml'])` 与 `assert.deepEqual(SKIP_DIRS, ['.git', 'node_modules'])` —— 两项排除都是精确路径、无任何模式匹配，**新增 fixture 默认入面**；
   - 判定：纯谓词 `retiredHits(text, names)`（先 `\r\n → \n` 规范化，再大小写敏感 `includes`）；`scanScope(files, names)` 返回命中文件列表；
   - **零命中断言**：`scanScope(扫描面, RETIRED_RECOVERY)` 为空；
   - **命中即失败的八条代表性用例**（§4.4-4 表，取真实路径的真实文本并在内存中追加一行含 `recoverCommand` 的合成行，断言 `scanScope` 对同一路径判为命中）：① `lib/workspace-transactions.mjs` ② `skills/shared/crctl/adapters/claude-code/hooks/pretooluse-guard.mjs` ③ `skills/requirement/requirement-register/scripts/promotion-bind.mjs` ④ `…/requirement-register/scripts/test/promotion-bind.test.mjs` ⑤ `skills/writeback/scripts/writeback-prd-sdd.mjs` 与 `skills/writeback/scripts/test/writeback.test.mjs` ⑥ `pipeline-templates/emit-registry.mjs` ⑦ 活跃提示词（`skills/cr/cr-archive/SKILL.md`、`agents/delivery-agent.md`）⑧ 活跃测试向量（`test/fixtures/digest-vectors/{expected.json,review-annotations-code.yml,test-report.md}`）；
   - **不误报正反用例**：唯一被排除的夹具（`traceability-191k.yml`）仍合法含旧名，断言 `retiredHits(排除项文本) === true` 且 `scanScope(扫描面)` 不含它；同目录其余三个文件断言相反（在面内且零命中）——两者并置才证明排除是刻意、精确且必要的；
   - **硬失败（不静默降级）**：索引解析出 0 条 active、目录枚举为空、active 索引条目在磁盘上不存在或落在排除项内、Pipeline 索引与目录枚举集合不相等 —— 任一发生即硬失败；索引与文件读取一律先 `replaceAll('\r\n', '\n')` 再 `split(/\r?\n/)`；扫描结果按路径排序输出；
   - **规模只作报告值，不写脆弱等式**（§4.4-4 末段）：规模（216 / 43 / 17 / 26 / 56 / 9 / 8）写进断言消息作覆盖度报告；真实保证由四条结构性断言给出（索引条目存在于磁盘且在面内、八条代表性路径在面内、`EXCLUDED` 与 `SKIP_DIRS` 被 `deepEqual` 冻结、排除项恰两条精确路径且无通配）。
8. **`import.meta.dirname` 口径**：每个测试文件顶部一行 `const CRCTL_JS = path.resolve(import.meta.dirname, '..', 'crctl.mjs')`（node ≥ 20.11 提供 `import.meta.dirname`；本仓 CI 与本地均为 node 24.x，实测可用）。

## 4. 验收条件

1. `cmd-01` 全绿（合并后 CI 入口，登记的 21 个文件全部被真实 spawn）：
   ```bash
   node skills/shared/crctl/scripts/test/suite-gate.mjs --run   # 期望：verdict=pass、exit 0、files_executed=21、cases_executed>=578、failures 空、exceptions_count=0
   ```
2. `cmd-03` 零失败（整树零命中 + 排除面恰两项且无通配 + 唯一被排除文件仍含旧名 + `fixtures/` 在面 3 个 + `manifest.files` 恰 21 且 ≡ 磁盘集合、`exceptions: []`）。
3. 用例数下限不破：逐文件顶层用例数 ≥ §1.1 列出的 `manifest.cases`（`cmd-01` 的 `SUITE_MANIFEST_CASE_DROP` 检查即证明）。
4. 未新增该目录测试文件：`git diff --name-status 81d31b8 -- skills/shared/crctl/scripts/test` 中无 `A`（新增）条目、无 `D`（删除）条目（由 `cmd-05` 的 diff 面白名单兜底）。
5. `gate-registry.json` 零改动（由 `cmd-05` 的 `zero_diff` 断言兜底），且 `exceptions` 仍为 `[]`（`cmd-03`）。
6. 守卫断言存在且通过：`crctl.mjs` 与 `lib/*.mjs` 内 `shell: true` / `Invoke-Expression` 零命中（`cmd-05`）。
7. 既有 CR-2026-041 断言未被波及：`RETIRED` 三项名单与 `ACTIVE_PATHS` 既有断言逐字保留（`cmd-01` 内 `contract-scan.test.mjs` 全绿）。

## 5. 完成标志

- 上列七条验收条件全部通过；7 个迁移文件 + `contract-scan.test.mjs` 旧名零命中（`cmd-03`）。
- 7 个文件的改写**逐用例原位替换**（顶层用例只增不减），`manifest.cases` 下限未破；未新增该目录测试文件；未改 `gate-registry.json`。
- 6 类 reason 向量与参数边界向量就位，且 reset 用例经 `runCrctlInTty` 走 TTY 路径（非 TTY 提前退出即视为未完成）。
- 整树扫描面的四条结构性断言 + 八条命中用例 + 不误报正反用例 + 硬失败清单全部落盘，规模仅作报告值。
- 未触碰「不得触碰」清单（`git status --porcelain` 只列本 TASK 的 8 个文件）。
- 最终机器证据：`cmd-01`（全绿，即 AC-07 第一条）、`cmd-03`（零命中）、`cmd-05`（守卫与 diff 面）。`cmd-02`（writeback 单测）由 `write-test-report` 节点统一执行，用于 AC-07 第二条。
- `tasks/_index.yml` 中本 TASK 标记 `done`。

## 6. 接口契约

**消费（上游 CR-2026-064-TASK-01 / CR-2026-064-TASK-02 / CR-2026-064-TASK-03 的产出；断言对象）**

- 生产者/投影面：`recovery` 对象（5 键、固定键序）与 `error.recovery`；`buildRecovery(args, { cwd, requiresTTY, promptFor })` 的入参语义（CR-2026-064-TASK-01）。
- 命令面：`register`（单投影）、`gate --mode pre-review` 错配、`review-loop reset` 提交失败三处的 `args` 取值（CR-2026-064-TASK-02 §6 表）。
- 提示词/文档面：`skills/shared/crctl/SKILL.md` 的「`recovery` 消费合同」小节文本（CR-2026-064-TASK-03 产出，本 TASK 的扫描面覆盖它）。
- 既有机制（只读复用）：`contract-scan.test.mjs` 的 `FORBIDDEN` / `RETIRED` / `ACTIVE_PATHS` 与 `readFileSync + replaceAll('\r\n','\n') + includes` 判定；`.githooks/pre-commit`（reset 失败分支的既有触发手法）；`runCrctlInTty`（TTY 包装既有工具函数）。

**产出（供 `write-test-report` / `review-code` 消费的机器证据口径）**

- 证据命令：`cmd-01` = `node skills/shared/crctl/scripts/test/suite-gate.mjs --run`（合并后 CI 入口；`verdict: pass`、`files_executed=21`、`cases_executed ≥ 578`、`failures` 空、`registry.exceptions_count=0`）；`cmd-03` = plan.md §6.2 的整树扫描审计；`cmd-05` = 守卫与 diff 面审计。
- 上述命令的 `args` 与 timeout 以 `plan.md §6.2` 为唯一来源逐条转录（`cr-test-plan/v1`），不得在 plan 之外另造命令集；`cmd-NN` 与 plan 覆盖矩阵「验收证据」列全等。
- 冻结 skip 模式注记（计划 R-14）：`cmd-01` 的输出不含独立词 `skipped`（用 `skipped_cases` / `skipped_file_level`），本 TASK 的迁移不得破坏该性质（`contract-scan.test.mjs` 的既有禁词自测对 `cmd-01` stdout 生效）；`cmd-02` 使用 `--test-reporter=dot`（见 `plan.md §6.2.1`）。
