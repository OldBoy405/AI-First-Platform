---
id: CR-2026-064-TASK-04
type: TASK
cr-ref: CR-2026-064
plan-ref: "change-requests/CR-2026-064/plan.md"
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
title: "测试迁移与契约退役保护：7 个既有测试改结构断言、contract-scan 整树扫描面与八条命中用例、shell 逃逸守卫"
slug: recovery-test-migration-and-contract-scan
status: pending
estimate: 16h
depends-on: [CR-2026-064-TASK-01, CR-2026-064-TASK-02, CR-2026-064-TASK-03]
created: 2026-09-13T00:20:00+08:00
---

# CR-2026-064-TASK-04 —— 测试迁移与契约退役保护

覆盖 FR：**FR-9、FR-11、FR-12、FR-14（完整性证明面）**（SDD §4.4/§4.5/SDD-CLOSE-05）；变更组 G4；主责仓：`tools`。

## 1. 任务描述

**目标**：① 把 7 个既有测试文件里「`result.recoverCommand.includes('…')`」形式的字符串包含断言原位改为确定的结构与 argv 断言，并补齐参数边界、6 类 reason 用户输入向量与 `shell: true` / `Invoke-Expression` 守卫断言；② 扩展既有 `contract-scan.test.mjs`：新增 `RETIRED_RECOVERY` 退役名单、**整树派生扫描面**（不以目录/扩展名声明活跃）、恰两项**精确路径**排除（`deepEqual` 冻结）、四条结构性断言、八条命中即失败的代表性用例与「排除不误报」正反用例、索引一致性硬失败。

**背景**：PRD FR-9 要求测试能证明 argv 边界而不是证明某个字符串片段出现过；FR-11 要求把两个退役字段名加入既有静态合同扫描，且**不得**把「全仓零命中」作为唯一实现（历史证据合法含旧名）。该扫描面在前几轮技术评审中被连续收窄三次（手工清单 → 索引派生 → 整树派生 + 精确路径排除），本 TASK 落地的就是最终版。

**输入条件**：tools CR worktree（`requirement/CR-2026-064`，HEAD 基线 `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`）；CR-2026-064-TASK-01/02/03 已完成并登记（生产者、CLI、消费方与文档均已迁移，整树扫描面的最终态成立）；`crctl workspace freshness CR-2026-064`（gate=implement-start）通过。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | `TASK-01 RED-1` 标题、`~L259`、`~L317` 的字符串断言 → 结构断言（`executable` / `args` / `requiresTTY` / `promptFor`） |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 测试标题与 `~L224` 同上 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 成功结果字段集用例、reset 双向量用例、rollback 用例、gate 双向量用例 → 结构断言；**补 6 类 reason 向量与 `promptFor` 断言**（`runCrctlInTty` 包装） |
| `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 测试标题、`~L286`、`~L301` → 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot |
| `skills/shared/crctl/scripts/test/register-tx.test.mjs` | `~L143`、`~L164`、`~L637` 标题、`~L650`（`recover_command`）→ 结构断言；**双投影用例改为单投影断言** |
| `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | `~L269` 同上 |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | `~L818` 标题、`~L831` → 断言 `--target-version` 为独立元素且值正确 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 新增 `RETIRED_RECOVERY` + 整树派生扫描面 + 两项精确路径排除（`EXCLUDED` / `SKIP_DIRS` 用 `deepEqual` 冻结）+ 四条结构性断言 + 八条命中用例 + 不误报正反用例 + 索引一致性硬失败 + shell 逃逸守卫断言；**既有 `RETIRED_LEGACY` / `ACTIVE_PATHS` 与两条 CR-2026-041 用例逐字不动** |

**不得触碰**：`skills/shared/crctl/scripts/lib/**` 与 `crctl.mjs`（属 CR-2026-064-TASK-01/02）、`README.md` / `openwiki/**` / 4 份消费方 SKILL / multica 文件（属 CR-2026-064-TASK-03）、`skills/shared/crctl/scripts/test/fixtures/**`（历史 traceability 与 3 个活跃 digest 向量都**零改动**：前者是被排除的历史证据，后者是本 CR 的 `zero_diff` 对象，只是从此进入扫描面受保护）、`skills/writeback/scripts/test/writeback.test.mjs`（只被回归命令执行，不改）。

## 3. 实现要点

1. **结构断言模板（SDD §4.5 第 1 条，每个测试文件内一行 `CRCTL_JS` 常量）**：

```js
const CRCTL_JS = path.resolve(import.meta.dirname, '..', 'crctl.mjs');   // 每个测试文件内一行
assert.equal(res.recovery.executable, 'node');
assert.deepEqual(res.recovery.args, [CRCTL_JS, 'checkpoint', cr, '--workspace', ws]);
assert.equal(res.recovery.cwd, ws);
assert.equal(res.recovery.requiresTTY, false);
assert.deepEqual(res.recovery.promptFor, []);
```

   - **不对完整 JSON 做脆弱快照**（SDD §4.5 第 2 条）；只断言 `recovery` 内的确定字段与该生产者相关的其它字段；临时路径按元素与顺序断言。
2. **向量补齐（SDD §4.5 第 3–4 条）**：
   - 参数边界：CR-ID / workspace / branch-ref 各占独立元素；含空格的临时路径无需引号即正确传递；元素顺序与 CLI 合同一致（每类生产者至少一条）；
   - 用户输入（`review-loop reset`，6 类）：`normal reason`、含双引号、含分号、含换行、`$(substitution)`、反引号表达式——每类断言四件事：`args` 不含该值、`promptFor` 含 `reason`、`requiresTTY === true`、`JSON.stringify(recovery)` 中该值不出现；用既有 `runCrctlInTty` 包装触发提交失败（`.githooks/pre-commit` 手法，SDD §6.3 AC-03 可达性）；
   - 合同缺失四类（无 `executable` / `args` 非数组 / `requiresTTY=true` 但无 TTY / `promptFor` 非空却无输入入口）由消费方提示词合同承接（CR-2026-064-TASK-03 落文本），本 TASK **不新增运行期校验代码**（D-6：无生产调用点的死代码不被引入）。
3. **契约扫描（SDD §4.4，唯一事实源）**：
   - **名单按名分范围**：`RETIRED_RECOVERY = ['recoverCommand', 'recover_command']`（扫描面见下）；既有 `RETIRED_LEGACY`（三个退役 Skill 名）保持既有显式 `ACTIVE_PATHS` 与既有断言，**本 CR 不改其名单与范围**（`zero_diff`：这三个名字在活跃面内合法存在）；
   - **扫描面 = 整树派生 − 两项精确路径排除**：`readdirSync(dir, { withFileTypes: true, recursive: true })` 递归枚举仓库工作树根下全部文件，按**路径段**跳过 `SKIP_DIRS = ['.git', 'node_modules']`（`tools` worktree 下 `.git` 是文件，同样排除）；不按目录、不按扩展名、不按文件名声明活跃性；
   - **排除恰两项、皆精确路径、无通配**：`skills/shared/crctl/scripts/test/contract-scan.test.mjs`（扫描器自身）、`skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（历史 traceability）。`EXCLUDED` 与 `SKIP_DIRS` 用 `assert.deepEqual` 冻结——任何新增排除或跳过目录都必须改测试并被评审看见；
   - **硬失败（不静默降级）**：索引解析出 0 条 active、目录枚举为空、active 索引条目在磁盘上不存在或落在排除项内、Pipeline 索引与 `readdirSync('pipeline-templates')` 的 `*.pipeline.json` 集合不相等——任一发生即硬失败；索引与文件读取一律先 `replaceAll('\r\n', '\n')` 再 `split(/\r?\n/)`，扫描结果按路径排序输出；
   - **判定谓词**：`retiredHits(text, names)`（先 CRLF 规范化，再大小写敏感的 `includes`）+ `scanScope(files, names)` 返回命中文件列表；
   - **零命中断言**：`scanScope(扫描面, RETIRED_RECOVERY)` 为空；
   - **八条命中即失败的代表性用例**（每个派生根一条；取真实路径的真实文本，在内存中追加一行含 `recoverCommand` 的合成行，断言 `scanScope` 对同一路径判为命中）：

| # | 派生根 | 代表性路径 |
|---|---|---|
| 1 | crctl 源码（含 `lib/`） | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` |
| 2 | crctl adapter hook | `skills/shared/crctl/adapters/claude-code/hooks/pretooluse-guard.mjs` |
| 3 | requirement-register 生产 | `skills/requirement/requirement-register/scripts/promotion-bind.mjs` |
| 4 | requirement-register 测试 | `skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs` |
| 5 | writeback 生产 + 测试 | `skills/writeback/scripts/writeback-prd-sdd.mjs`、`skills/writeback/scripts/test/writeback.test.mjs` |
| 6 | `pipeline-templates/**` | `pipeline-templates/emit-registry.mjs` |
| 7 | 活跃提示词（active Skill / active Agent） | `skills/cr/cr-archive/SKILL.md`、`agents/delivery-agent.md` |
| 8 | 活跃测试向量（`fixtures/` 内非历史文件） | `skills/shared/crctl/scripts/test/fixtures/digest-vectors/expected.json`、`…/review-annotations-code.yml`、`…/test-report.md` |

   - **允许排除不误报（正反并置）**：唯一被排除的夹具文件仍合法含旧名，断言 `retiredHits(排除项文本) === true` 且 `scanScope(扫描面)` 不含它；同目录其余三个文件断言相反（在面内且零命中）；
   - **四条结构性断言（规模只作覆盖度报告，不写 `length === 212` 这类脆弱等式）**：(1) 三个 active 索引（`skills/_index.yml` 56 / `agents/_index.yml` 9 / `pipeline-templates/_index.yml` 8）的全部条目存在于磁盘且在扫描面内、Pipeline 索引与目录枚举集合相等；(2) 八条代表性路径全部在扫描面内；(3) `EXCLUDED` 与 `SKIP_DIRS` 被 `deepEqual` 冻结；(4) 排除项恰为两条精确路径且不含任何通配、`fixtures/` 目录下未被排除的文件全部在扫描面内——**新增 fixture 默认入面，无需改测试即被扫到**。规模数字（212 / 40 / 16 / 24 / 56 / 9 / 8）写进断言消息作报告；
   - **shell 逃逸守卫（SDD §4.5 第 6 条 / AC-04）**：新增断言 `crctl.mjs` 与 `lib/*.mjs` 内不存在 `shell: true` / `Invoke-Expression`（与既有 `spawnSync(..., { shell: false })` 事实一致）。
4. **跨仓边界（诚实口径）**：扫描运行在 `tools` 测试套件内，只覆盖 `tools` 仓整树；`multica` 与 KB 侧由 `plan.md §6.2 cmd-04`/`cmd-06` 与评审比对覆盖，**不**在 `tools` 测试里假装覆盖。

## 4. 验收条件

1. **AC-06 命中即失败**：`contract-scan.test.mjs` 的八条代表性用例逐个通过（对每条派生根注入合成命中行后判为命中）；零命中断言在未注入时为真；`EXCLUDED` / `SKIP_DIRS` 冻结断言通过；四条结构性断言通过（含 `fixtures/` 内 3 个活跃向量在面内）。
2. **不误报**：唯一被排除的 `traceability-191k.yml` 仍含旧名且被判为排除；`fixtures/digest-vectors/**` 三个活跃向量在面内且零命中；既有 `RETIRED_LEGACY` / `ACTIVE_PATHS` 两条 CR-2026-041 用例逐字不变且通过。
3. **硬失败**：构造空索引 / 空枚举 / 索引条目缺失 / Pipeline 集合不相等四种故障时测试失败（不得静默通过）——以最小化临时注入核对（不写入入库文件）。
4. **AC-03 用户输入向量**：6 类 reason 向量全部通过，每类四件事（`args` 不含值、`promptFor` 含 `reason`、`requiresTTY === true`、序列化后该值不出现）。
5. **AC-01/AC-02/AC-07/AC-08/AC-10 断言面**：7 个迁移文件的结构与 argv 断言通过；`register` 单投影断言通过（`recover_command` 不再出现）；`merge` publication lag 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot；`writeback` 的 `--target-version` 独立元素断言通过。
6. **AC-04 守卫**：`shell: true` / `Invoke-Expression` 守卫断言通过。
7. **全量回归**：`plan.md §6.2 cmd-01`（21 个 `*.test.mjs`，含 `contract-scan.test.mjs`）exit 0 且机器区 `skipped=false`；`cmd-02`（`skills/writeback/scripts/test/writeback.test.mjs`）exit 0。
8. **范围**：`plan.md §6.2 cmd-05` 的 tools diff 白名单通过——本 TASK 的增量路径 ⊆ {7 个既有测试文件 + `contract-scan.test.mjs`}。

## 5. 完成标志

- 上述 §4 的 8 条全部实测通过，并留下可复核的命令与输出摘要（命令、cwd、exit、关键断言行、注入用例名）。
- `plan.md §6.2 cmd-03` 的整树零命中在实现完成后为真（本 TASK 是整树扫描面最后一个迁移面）。
- 本 TASK 产生的文件（8 个测试文件）由本 TASK 自行提交：`[cr] CR-2026-064 TASK-04 recovery tests and contract scan`（受控 `crctl git` 形态，`[cr] ` 前缀）。
- `crctl task done CR-2026-064-TASK-04 --workspace <KB worktree>` 登记完成（纪律 #8）。
- **不**在本 TASK 内改写 `sdd.md` / `prd.md`；**不**改 `fixtures/**` 内容；**不**改源码与文档（属前三个 TASK）。

## 6. 接口契约

**产出（供后续节点与评审消费，逐字对齐 SDD）**

| 符号 / 断言面 | 精确形态（SDD 落点） |
|---|---|
| 退役名单分范围 | `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']`（扫描面）；`RETIRED_LEGACY`（既有三个 Skill 名）保持既有 `ACTIVE_PATHS` 与既有断言不变（SDD §4.4-1） |
| 扫描面与排除 | `scanScope(整树枚举 − EXCLUDED)`；`EXCLUDED = ['skills/shared/crctl/scripts/test/contract-scan.test.mjs', 'skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml']`、`SKIP_DIRS = ['.git', 'node_modules']`，两者 `deepEqual` 冻结（SDD §4.4-2/§4.4-3） |
| 判定谓词 | `retiredHits(text, names)`（CRLF 规范化后大小写敏感 `includes`）、`scanScope(files, names)` → 命中文件清单（SDD §4.4-4） |
| 结构断言模板 | `res.recovery.{executable,args,cwd,requiresTTY,promptFor}` 逐字段断言，`CRCTL_JS = path.resolve(import.meta.dirname, '..', 'crctl.mjs')`（SDD §4.5 第 1 条） |
| 守卫断言 | `crctl.mjs` / `lib/*.mjs` 内 `shell: true`、`Invoke-Expression` 零命中（SDD §4.5 第 6 条 / AC-04） |

**消费（上游产出，逐字对齐）**

- `recovery` 的 11 站点取值表与键序：CR-2026-064-TASK-01（生产者）+ CR-2026-064-TASK-02（CLI 站点 10/11）产出的实际形状——测试断言的 `args` 期望值必须与 SDD §4.1 表逐元素一致（含 `--workspace` 位置与可选参数条件展开）。
- 消费方 5 步判定与四类闭包：CR-2026-064-TASK-03 落在 `skills/shared/crctl/SKILL.md`；本 TASK 不重复实现该规则，也不为其伪造运行期测试（D-6）。
- 既有测试装置：`runCrctlInTty`（TTY 包装）、`.githooks/pre-commit` 故障注入、`merge-fixture.mjs`（被 `merge-tx.test.mjs` import 的非测试辅助模块，不在 `*.test.mjs` 枚举内）。
