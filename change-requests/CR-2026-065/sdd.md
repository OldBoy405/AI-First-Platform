---
id: CR-2026-065-sdd
type: SDD
cr-ref: CR-2026-065
title: CR-S：测试基线与门禁可信化 — 断言去硬编码、4 条基线漂移转绿、CI 全量步骤成为真门禁 技术设计
target-version: 0.38
status: draft
created: 2026-09-13T03:26:00+08:00
updated: 2026-09-13T03:52:00+08:00
---

> 输入：`change-requests/CR-2026-065/prd.md`（sha256(LF) `467b5d47…`，已评审 PASS 并经人工审批）。
> 修订（`review-tech-design` attempt 1/3 BLOCK 后的定点回修）：**B-1** §4.4 BR-2 行——三词改为「否定辖域」机械判据、零命中面收缩为已核对为真的 `latest-checkpoint` / `checkpoints[]`；**B-2** §6.3 第 5 项拆为两项——按本机实测登记 `merge-fixture.mjs` 的真实导出，新增第 6 项承载 `archive-tx.test.mjs` 的文件内局部 helper；**B-3** §3.1/§4.3/§2.2 统一 VOLATILE 键空间（`OUTBOX_VOLATILE_PAYLOAD_KEYS`，payload 根下相对键）并补「投影闭合」不变量。本轮一并关闭 3 条 in-scope suggestions（S-1 非收敛例外的判读、S-2 恒真结构自检、S-3 显式钉 TAP reporter + 解析自测），逐条落点见 §6.5 `SDD-CLOSE-09`…`SDD-CLOSE-11`。
> 目标代码仓：**`tools` 仓自身**（本 CR 改 `skills/`、`skills/shared/crctl/scripts/`、`.github/workflows/crctl-ci.yml`），故按 `write-tech-design` Step 1.2 的特殊分支读取 `tools/ARCHITECTURE.md`（**只读不改**，13562 B，已存在）。
> 本文档只描述设计与实现契约；实测证据（负控、收敛、耗时）由实施与测试期产出，格式由 §4.6 与 §3.2 固定。

---

## 1. 架构概览

### 1.1 本 CR 在 tools 包中的位置

tools 包的分层（`tools/ARCHITECTURE.md` §4）：使用方仓库 → Pipeline → Skill → `crctl`。本 CR **不改 Pipeline 节点序列、不改 Skill 语义、不改状态机、不改错误码、不改事务语义**；它改的是三处「断言与门禁」：

1. **断言层**：`skills/shared/crctl/scripts/test/*.test.mjs` 中把「会随合理变更而变的既有事实」钉成快照的 4 条断言（BR-1…BR-4）+ 1 条构造失真的冻结向量（BR-5）。
2. **门禁层**：`.github/workflows/crctl-ci.yml:109-111` 的全量测试步骤（当前裸 `node --test --test-concurrency=2 …`）。
3. **最小产品面**：`crctl.mjs#emitOutboxEvent` 的去重比较字段契约从「注释里的口头约定」提为「可机器检查的声明」（FR-10）。

因此本 CR 不新增架构不变量，也不触碰 `ARCHITECTURE.md` §5 的 8 条不变量；相反，本 CR 让第 5 条（状态机口径唯一）与第 4 条（行尾与硬失败纪律）在**测试侧**第一次变成机器可查的。

### 1.2 变更面总览（文件 → 动作 → 归属）

| 文件（相对 tools 仓根） | 动作 | 归属 FR | 性质 |
|---|---|---|---|
| `skills/shared/crctl/scripts/lib/outbox-contract.mjs` | **新增** | FR-8 / FR-10 | 产品面（最小） |
| `skills/shared/crctl/scripts/crctl.mjs` | 改 `emitOutboxEvent`：内联比较块 → 调用契约模块（注释合并，语义零变化） | FR-8 / FR-10 | 产品面（最小） |
| `skills/shared/crctl/scripts/test/assertion-sources.mjs` | **新增**（不匹配 `*.test.mjs`，不被 runner 当测试执行） | FR-1 / FR-3 / FR-6 | 测试辅助（只读） |
| `skills/shared/crctl/scripts/test/gate-registry.json` | **新增**（受控清单数据文件） | FR-3 / FR-6 / FR-14 | 治理数据（人工提交） |
| `skills/shared/crctl/scripts/test/suite-gate.mjs` | **新增**（全量套件门禁包装器，不匹配 `*.test.mjs`） | FR-11 / FR-12 / FR-14 | CI 门禁 |
| `.github/workflows/crctl-ci.yml` | 改第 109-111 步骤：调用 `suite-gate.mjs --run` | FR-11 / FR-12 | CI 配置 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 改 3 条断言（`:1337` BR-1、`:4777` BR-3、`:4989` BR-4） | FR-4 / FR-6 / FR-7 | 测试 |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 改 `:480` BR-2 断言 | FR-5 | 测试 |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 改 `:373` RED-7 构造 + 新增「同名不同内容」用例 | FR-8 / FR-9 | 测试 |
| `skills/shared/crctl/scripts/test/trace-outbox.test.mjs` | 新增去重契约断言（含字段分类负例） | FR-10 | 测试 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 新增受控清单 / 例外登记面 / 写入口静态断言 + `suite-gate` 报告解析自测（内联 TAP 片段，关闭 S-3） | FR-14 / FR-17 | 测试 |

**不新增测试文件**：`*.test.mjs` 文件集合保持基线 21 个（`AC-01` 的「21 个文件全部被真实执行」按此口径成立）。新增的两个 `.mjs` 都不匹配 `*.test.mjs`，不被 runner 采集。

### 1.3 依赖方向（只朝下，且不新增第二写入口）

```
.github/workflows/crctl-ci.yml
        │  run: node .../test/suite-gate.mjs --run
        ▼
test/suite-gate.mjs ──读──▶ test/gate-registry.json        （只读；唯一写入口 = 人类编辑 + git commit）
        │
        │  spawn: node --test <glob>   （单一命令来源）
        ▼
*.test.mjs（21 个）──读──▶ test/assertion-sources.mjs ──▶ lib/yaml-subset.mjs（既有解析器）
        │
        └──读──▶ lib/outbox-contract.mjs ◀──用── crctl.mjs#emitOutboxEvent（唯一契约事实源）
```

- 断言一律**只读**：不改状态、不写 `cr.md` / `_backlog.yml` / `tasks/_index.yml` / `approval.yml`，不调用任何 crctl 写命令。
- 不新增 crctl 子命令或 flag（FR-17）；`gate-registry.json` 与 `suite-gate.mjs` 是仓库内 CI 面，不是用户可调用契约。
- 零新增第三方依赖：只用 Node 标准库与仓库既有 `lib/`（FR-15.6）。

### 1.4 关键流程（一次门禁运行）

```text
CI step「crctl full test suite」
  └─ suite-gate --run
       1. 读 gate-registry.json（缺失/坏 schema → 硬失败，零静默）
       2. 用固定命令跑全量套件，边跑边落 TAP 报告（--report-out）
       3. 解析 TAP → 实际执行的文件集合 / 每文件用例数 / 失败用例名 / 文件级 skip 数
            （解析失败 → SUITE_REPORT_UNPARSEABLE 硬失败，禁止降级为空结果；进程未自行结束的分支见 §3.2 非收敛口径）
       4. 受控清单核对（文件集合相等、每文件用例数 ≥ 基线）
       5. 例外面核对（schema / owner / 到期 / 与真实失败集合的双向匹配）
       6. 结论：退出码 0 当且仅当 §3.2 check code 表中无任一**未被抑制**的触发
            （正常收敛：失败集合差为空且 3/4/5 全过；非收敛分支：改判 `SUITE_NONCONVERGENCE` 行，不做 3/4 核对）
```

---

## 2. 数据模型

### 2.1 术语硬化（Step 2.5）

只处理进入数据模型 / 接口契约且存在歧义或别名风险的术语。先验结论：**不存在需要需求负责人澄清的语义冲突**（SPRD 与本 CR 输入约束已给出唯一含义），因此未触发「首次 advance 前停止」；下表把 PRD canonical term 与代码落点一次性钉死，避免实现期两种读法。

| PRD canonical term | 代码落点 / 别名 | 边界规则（唯一读法） |
|---|---|---|
| 受控清单 | `test/gate-registry.json`（git 跟踪数据文件） | 是**清单**不是**账本**：不进 `crctl` 写路径，唯一变更入口 = 人类编辑 + `git commit`（审计 = git history）。与「受控账本」（`_backlog.yml` / `tasks/_index.yml` / `cr.md`，只能经 crctl 写）严格区分 |
| 例外 / 例外清单 | `gate-registry.json#exceptions` | 例外 = **对已知失败的、有主有期的容忍登记**；不是「跳过测试」、不是「放宽断言」。登记不替代执行：被容忍的失败仍必须由 runner 真实报告 |
| 到期 | `exceptions[].expires` | 只能是一个**带显式时区偏移的 ISO-8601 时间戳**（`YYYY-MM-DDTHH:MM:SS(Z|±HH:MM)`）；比较基准 = 门禁运行时的 UTC 瞬时（`Date.now()`）；`now >= expires` 即过期。不接受「日期或可判定的条件」这类开放形态（关闭 S-5） |
| 失败集合 | TAP 观测到的 `not ok` 用例名集合 | 口径 = 「本次运行实际报告的失败用例」，与文件级加载失败（不可例外化）分开计数 |
| 可推导的事实 | §6.6 表 D1…D6 | 由事实源结构推导，硬编码其快照 = 缺陷 |
| 必须钉死的目标值 | §6.6 表 P1…P7 | 显式登记；变更时必须在本 CR/本变更内显式更新登记值才允许转绿 |
| 漂移当场红 | §4.6 注入协议 | = 真实漂移注入后**全量命令**变红，且注入物不留在交付分支 |

### 2.2 既有实体：outbox 事件对象（只归类，不改字段）

现网事件对象（`crctl.mjs#emitOutboxEvent` 构造，写入 `.crctl/outbox/<name>.json`）：

| 字段 | 是否参与去重比较 | 说明 |
|---|---|---|
| `v` / `event_kind` / `cr_id` / `from_status` / `to_status` / `trigger` / `commit_sha` / `actor` / `evidence` / `payload` | **参与** | 内容面；`payload` 逐键参与 |
| `occurred_at` | **不参与**（顶层易变） | 每次 `nowIso()` 重新生成；排除后同名文件重放不产生假冲突 |
| `payload.detected_at` | **不参与**（唯一登记的 payload 易变键） | 键名读法 = `payload` 根下的 `detected_at`（**相对键**，不是事件对象全路径），由 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 枚举排除；CR-2026-052 TASK-08 语义：同一漂移在被采集前重复观测不产生 `OUTBOX_DEDUP_CONFLICT` |

语义不变（FR-8）：文件名存在且比较面**逐字段相等** → 视为已发送（返回文件名、不覆盖、不新增）；比较面**不等** → `OUTBOX_DEDUP_CONFLICT` → 调用方 `EMIT_FAILED` → 不覆盖、不静默去重。本 CR 只把上表从注释提为可检查声明（§3.1），**不改变任何字段语义**。

### 2.3 新增实体 1：`gate-registry.json`（受控清单）

Schema `crctl-suite-gate/v1`（字段全部必填，缺 = 红）：

```json
{
  "schema": "crctl-suite-gate/v1",
  "manifest": {
    "files": ["archive-tx.test.mjs", "..."],
    "cases": { "archive-tx.test.mjs": 0, "crctl.test.mjs": 0 }
  },
  "stateMachine": {
    "namedStates": ["drafting", "..."],
    "wildcards": { "any-active": ["drafting", "..."] },
    "transitions": [{ "from": "(new)", "to": "drafting", "trigger": "requirement-register" }]
  },
  "exceptions": []
}
```

| 段 | 语义 | 谁读 | 变更后果 |
|---|---|---|---|
| `manifest.files` | 全量命令必须执行的测试文件集合（仓库相对文件名） | `suite-gate` | 实际执行集合 ≠ 登记集合 → `SUITE_MANIFEST_FILE_DRIFT` 红 |
| `manifest.cases` | 每文件用例数**基线**（实施期实测登记，见 FR-16） | `suite-gate` | 实际用例数 < 基线 → `SUITE_MANIFEST_CASE_DROP` 红（关闭 S-1：删用例换绿在门禁上留痕） |
| `stateMachine.namedStates` | 具名状态集合（15 个；注册前态 `(new)` 单列，不入集合） | 状态机断言 | 与推导集合不等 → 红（FR-6.2） |
| `stateMachine.wildcards` | wildcard 名 → 目标集合（当前 `any-active` → 12 个） | 状态机断言 | 增删目标即红（关闭 S-3） |
| `stateMachine.transitions` | 每条声明转换的稳定标识 `(from,to,trigger)`（当前 31 条） | 状态机断言 | 增删改名任一转换即红，除非显式更新登记值 |
| `exceptions` | 例外单一登记处；本 CR 交付态 = **空数组**（显式声明为空，非「文件不存在」） | `suite-gate` | 见 §3.2 错误码表 |

**登记值的初值来源**：`stateMachine.*` 由实施期从 `dir-graph.yaml` 推导后原样登记（当前实测：具名状态 15、声明转移 31、`from: any-active` 2 条、`any-active` 目标 12 个、展开 31−2+12×2 = **53**）；`manifest.cases` 由实施期在 5 条修复与新增用例落地后实测登记。登记后**不得**再由脚本自动改写（受控写入 = 人工提交）。

### 2.4 新增实体 2：门禁运行报告（`suite-gate` 的固定字段，关闭 S-2）

`--json-out <path>` 落盘的报告模型（同时是人类可读摘要的输出源）：

```text
schema        "crctl-suite-gate-report/v1"
command       实际执行的完整命令（含并发参数，字符串）
duration_ms   全量命令耗时（整数）
converged     进程是否自行结束（false = 触发 --max-runtime-ms 被终止，即停滞）
exit_code     被测命令退出码（被终止时为 null）
files_executed / cases_executed / skipped_file_level
failures[]    失败用例名
checks[]      [{ code, ok, detail, suppressed_by?, not_evaluated? }] 逐项门禁结论（固定 check code；被例外抑制时 ok=false 且带 suppressed_by=<exception-id>；非收敛分支未做的核对项带 not_evaluated=true）
registry      { sha256, exceptions_count }
platform      { platform, node }
verdict       "pass" | "block"
```

字段名固定（S-2 要求「交付物字段写死」），实施期不得改名；`test-report` 的 `test-evidence/cmd-NN.log` 直接落该 JSON。

**数据/schema 变更触发声明**：本 CR 不涉及数据库 schema、数据迁移或写路径鉴权（N/A，理由：断言只读 + 唯一新数据文件为 git 跟踪的受控清单，无事务/回滚语义）。故本节不含 down/回滚设计。

---

## 3. 接口契约

### 3.1 `lib/outbox-contract.mjs`（产品面，FR-10 单一事实源）

```js
// 单一事实源：字段分类 + 投影函数。产品与测试共同 import，禁止第二份副本。
export const OUTBOX_COMPARED_FIELDS = Object.freeze([...]);      // 参与比较（§2.2 上半表）
export const OUTBOX_EXCLUDED_FIELDS = Object.freeze(['occurred_at']);          // 顶层不参与
export const OUTBOX_VOLATILE_PAYLOAD_KEYS = Object.freeze(['detected_at']);    // payload 根下键名（相对键）
export function buildOutboxEvent(input, nowIsoString) { /* 规范化事件对象 */ }
export function buildOutboxComparable(event) { /* 由上面三个声明驱动的投影 */ }
```

契约：

1. `crctl.mjs#emitOutboxEvent` 改用 `buildOutboxEvent` + `buildOutboxComparable`；`crctl.mjs` 中**不得**再出现字段枚举或 `detected_at` 的语义副本（只允许指向本模块的指针注释）。
2. 不变性（测试断言）：`Object.keys(buildOutboxEvent(sample, now)) ≡ OUTBOX_COMPARED_FIELDS ∪ OUTBOX_EXCLUDED_FIELDS`（集合相等）。⇒ 任何新增字段若未登记进两类之一，契约检查直接红（这就是 AC-09 负控的落点）。
3. 不变性：`OUTBOX_VOLATILE_PAYLOAD_KEYS` 只做**枚举排除**，不得实现为「按名字/类型自动排除所有时间类字段」；测试用反例证明：`payload.observed_at`（未登记）**仍参与比较**。
4. 不变性（投影闭合）：对任意入参，`Object.keys(buildOutboxComparable(ev).payload) ∩ OUTBOX_VOLATILE_PAYLOAD_KEYS = ∅` —— 登记键绝不出现在投影结果中；键缺失、`payload` 为空、嵌套对象三种边界同样成立。⇒ 常量与投影必须处于**同一键空间**（声明与实现同读法），否则本条直接红。
5. 不变性：投影只读不改入参（不得就地 delete 原事件字段）。
6. 行为等价：对同一比较面的事件重放仍视为已发送（返回文件名）；比较面不等仍抛 `OUTBOX_DEDUP_CONFLICT`（FR-8 语义零变化）。

### 3.2 `test/suite-gate.mjs`（CI 门禁契约；「例外登记面」四查在此闭合）

**调用形态**

```text
node skills/shared/crctl/scripts/test/suite-gate.mjs --run [--report-out <tap>] [--json-out <json>]
                                                           [--max-runtime-ms <n>] [--cwd <tools-root>]
node skills/shared/crctl/scripts/test/suite-gate.mjs --report <tap> --rc <exit-code> [--json-out <json>]
```

- `--run`（CI 与本地证据的唯一形态）：由包装器**自己**以固定命令 spawn 全量套件（并发参数由包装器内常量决定，见 §5.4）。
- `--report/--rc`：只做判定，不跑套件（负控与回归自测用）。

**四查（FR-17 对例外登记面的确定性要求）**

| 查 | 结论 |
|---|---|
| 幂等 | 同一稳定标识重复登记 → `EXCEPTION_DUPLICATE` 红（不产生重复条目）；同一例外在同一到期日内重复检查结论一致（判定只读登记值 + 运行时瞬时，不看检查次数）；`--report/--rc` 模式判定与 `--run` 判定同源同一函数 |
| 权限与写入边界 | 唯一写入口 = **人类编辑 `gate-registry.json` + git commit**（谁=commit author、何时=commit time、为什么=commit message；`git log -- gate-registry.json` 即审计）。不新增 crctl 子命令/flag（FR-17）；门禁与测试**只读**该文件；静态断言：仓库内不存在对该文件的写入调用（`writeFileSync`/`appendFileSync`/`rmSync`/`renameSync`/`truncate`），且 `suite-gate` 自身无写路径 |
| 错误闭包 | 见下表；每类 = 固定 check code + 非零退出（唯一例外：表中明列为「可抑制」的 `SUITE_NONCONVERGENCE` 在有匹配未到期例外时不产生非零退出）+ 零写入（门禁从不写登记面，故「零写入」恒成立） |
| 副作用 | 登记只影响**判定**，不改变执行：`--run` 永远先真实执行全量命令；即使失败被容忍，报告仍列出 `failures[]`（登记不得替代执行）。门禁不修改被测仓、不写 `gate-registry.json`、不写 `.crctl/` 受治理账本 |

**固定 check code（关闭 S-4：可机械核对的固定标识，风格与既有 crctl gate check code 一致）**

| check code | 触发条件 | 可否被例外容忍 |
|---|---|---|
| `SUITE_REGISTRY_MISSING` / `SUITE_REGISTRY_SCHEMA_INVALID` | 登记文件缺失 / schema 不符（含字段缺失、类型错误、`expires` 无时区偏移） | 否 |
| `SUITE_REPORT_UNPARSEABLE` | TAP 解析失败或结构不完整（硬失败，禁止降级为空结果） | 否 |
| `SUITE_FILE_LOAD_FAILURE` | 某文件整体加载/执行失败（文件级 `not ok`，无 file 级 plan） | 否（FR-11.2：文件必须被真实执行） |
| `SUITE_MANIFEST_FILE_DRIFT` | 实际执行文件集合 ≠ `manifest.files` | 否 |
| `SUITE_MANIFEST_CASE_DROP` | 某文件实际用例数 < `manifest.cases` 基线 | 否 |
| `EXCEPTION_FIELD_MISSING` / `EXCEPTION_SCHEMA_INVALID` / `EXCEPTION_DUPLICATE` | 例外条目缺 id/kind/reason/owner/expires、kind 非枚举、重复 id | 否 |
| `EXCEPTION_EXPIRED` | `now >= expires`（UTC 瞬时，见 §2.1） | 否 |
| `EXCEPTION_NOT_OBSERVED` | 登记的例外在本次运行中**未出现**（陈旧登记） | 否 |
| `SUITE_FAILURES_UNREGISTERED` | 观测失败集合中存在未被未到期例外覆盖的失败 | 否（容忍在**触发条件内**实现：未到期例外覆盖的失败不计入本项，故已登记的失败不会触发本项；本项一旦触发即不可抑制） |
| `SUITE_NONCONVERGENCE` | `--run` 超过 `--max-runtime-ms` 仍未结束（被终止） | **可抑制（可绿）**：仅当存在一条未到期、`kind: suite-nonconvergence` 且稳定标识与本项匹配的登记例外；报告仍记 `converged: false` 与 `checks[SUITE_NONCONVERGENCE]`（事实永不隐藏）；无匹配例外 / 例外已过期 → 红 |

退出码：**0 当且仅当**上表无任一触发。例外的「容忍」只有两个确定落点（均已写死，不存在两读法）：

- `SUITE_FAILURES_UNREGISTERED`：容忍落在**触发条件内** —— 观测失败 − 未到期例外覆盖的失败；本项一旦触发即不可抑制；
- `SUITE_NONCONVERGENCE`：容忍落在**已触发项的退出码**上 —— 可抑制（可绿），条件 = 存在未到期、`kind: suite-nonconvergence` 且稳定标识匹配的登记例外（= PRD `FR-14` 示例「已知不收敛的配置」的落地形态）。

其余 check code（登记缺失 / schema 不符、报告不可解析、文件加载失败、清单漂移 / 用例数下降、例外面自身错误、陈旧例外登记）**一律不可容忍**。被抑制的项仍全程可见：`checks[]` 保留该 code（`ok:false` 且标注 `suppressed_by:<exception-id>`）、`failures[]` 与 `converged` 原样上报 —— 抑制只影响退出码，不影响事实面（关闭本轮 S-1）。

**非收敛分支的判定口径（关闭 S-1 的两种读法）**：`converged = false` 时不做清单核对与失败集合核对（报告记 `files_executed = null` / `cases_executed = null` / 相关 `checks[].not_evaluated = true`），只判定 `SUITE_NONCONVERGENCE` 与登记面自身错误（`EXCEPTION_*`）。`SUITE_REPORT_UNPARSEABLE` 只在「进程已自行结束（`converged = true`）而 TAP 结构仍不完整」时触发 —— 终止导致的不完整是终止的后果，不是解析缺陷，两者不混算。
特例（本 CR 交付态）：`exceptions = []` ⇒ 退出码 0 当且仅当失败集合为空 —— 与 `AC-01` 逐字一致。

### 3.3 不新增用户可调用契约（FR-17）

不新增 crctl 子命令/flag、不新增 HTTP 端点、不改 Skill 参数契约、不新增受治理账本写路径。新增的 `suite-gate.mjs` / `assertion-sources.mjs` / `gate-registry.json` / `outbox-contract.mjs` 全部是仓库内部面（CI 与测试），使用方 workspace 不可调用。

### 3.4 HTTP / REST 契约

N/A —— 本 CR 不新增或修改任何 HTTP API（PRD 无 HTTP 契约；tools 包无服务端）。

---

## 4. 关键算法与流程

### 4.1 状态机推导（FR-1 / FR-3 / FR-6）

`assertion-sources.mjs#deriveStateMachine(toolsRoot)`：

```text
1. 读 dir-graph.yaml → 先做 \r\n → \n 规范化（工程纪律 #1）
2. doc = parseYaml(norm, { strict: true })                     // lib/yaml-subset.mjs（既有、零依赖）
3. sm = doc['change-request-track'].state_machine
   缺字段 / 结构不符 → throw（硬失败，禁止返回空集合）
4. declarations = sm.transitions                      // 每条 { from, to, trigger }
5. wildcards    = sm.wildcards || {}                  // 名 → 目标数组
6. namedStates  = 所有 from/to ∪ 所有 wildcard 目标，剔除 '(new)' 与 wildcard 名（按声明序去重）
7. expanded     = Σ declarations: wildcards[t.from]?.length ?? 1
   当前实测：31 条声明、2 条 from=any-active、any-active 12 个目标 → 31 − 2 + 12×2 = 53
8. identifiers  = declarations.map(t => `${t.from}|${t.to}|${t.trigger}`)（集合比较，抗行序变化）
9. 结构自检（推导侧；对同一批 declarations **恒真**，不作为覆盖率或断言项，只把「推导自身写错」暴露成异常）：
   - 每条声明的 from/to ∈ namedStates ∪ {'(new)'} ∪ wildcard 名
   - 每条 wildcard 的目标 ⊆ namedStates
   - namedStates ∩ wildcard 名 = ∅
```

断言（`crctl.test.mjs` BR-3 位置，替换 `:4789`/`:4792` 的 28/50）：

```text
推导集合 ≡ gate-registry.stateMachine.*（具名状态集合 / wildcard 目标集合 / 转换标识集合）
且 expanded 计数 ≡ 由登记集合自洽推出的值
⇒ 向 dir-graph.yaml 增删任意一条转换或 wildcard 目标，集合比较失败 → 本测试红（AC-06 负控）
```

**反恒真设计**：登记值不是「当前读到的值」（不是 `declared.length === declared.length` 型重述），而是**上一轮显式登记的目标值**；推导与登记是两条独立来源，二者相等才通过。承重断言只有上面三条集合/计数等价；**推导侧结构自检恒真、不计入覆盖**（关闭本轮 S-2，避免被读成检查项）。

### 4.2 全量套件门禁（FR-11 / FR-12 / FR-14）

`suite-gate --run` 主干（伪代码）：

```text
registry = readJson(gateRegistryPath)          // 缺失/坏 → 硬失败（check code 表）
cmd      = ['node', '--test', '--test-reporter=tap',
            ...(CONCURRENCY ? ['--test-concurrency=' + CONCURRENCY] : []),
            'skills/shared/crctl/scripts/test/*.test.mjs']
（glob 由包装器展开为 21 个文件绝对路径：单参数太长时按批传参；展开后必须非空，否则硬失败）
（`--test-reporter=tap` **显式钉死**：解析器硬依赖 TAP 结构，而 reporter 默认值随 Node 版本与是否 TTY 变化 ——
 不把门禁结论交给未登记的外部默认值；该命令是唯一来源（§5.4 / TDEC-4），关闭本轮 S-3）

child = spawn(cmd, { cwd: toolsRoot, shell: false })
  ├─ stdout → TAP 报告文件（--report-out）+ 摘要
  └─ 计时；超过 --max-runtime-ms → killTree(child) → converged = false（SUITE_NONCONVERGENCE）
rc = child.exitCode

tap = parseTap(report)                          // 见 4.3；失败 → SUITE_REPORT_UNPARSEABLE
checks = []
checks += manifestCheck(tap, registry.manifest)  // 文件集合相等；每文件用例数 ≥ 基线；文件级 skip = 0
checks += exceptionCheck(registry.exceptions, tap, nowUtc)   // schema/到期/双向匹配
checks += failureCheck(tap.failures, liveExceptionIds, rc)    // 差集为空
print human summary (command / duration_ms / converged / files / cases / failures / checks)
writeJson(--json-out)  → §2.4 报告模型
exit(checks.anyFail ? 1 : 0)
```

**TAP 解析规则（必须硬失败）**：以缩进栈识别 `# Subtest: <name>` 块；文件名块（`<name>` 以 `.test.mjs` 结尾）必须有 file 级 plan `1..N`，其 N = 该文件**实际执行的用例数**；块内 `not ok` 行 = 失败用例名（`# SKIP` / `# TODO` 后缀分别计入 skip / todo）；无 file 级 plan、块不成对、plan 与实际行数矛盾 → 抛错。任何解析异常都不得返回「零失败」结果（工程纪律 #1：跨行解析失败必须硬失败）。

**解析自测（关闭本轮 S-3）**：`contract-scan.test.mjs` 用**内联 TAP 片段**（合法片段 + 三类畸形片段：无 file 级 plan、块不成对、plan 与实际行数矛盾）走 `--report/--rc` 形态，断言合法片段判绿、三个畸形片段各自落 `SUITE_REPORT_UNPARSEABLE` 且退出非零 —— 不新增测试文件、不新增 fixture 目录（`*.test.mjs` 集合仍为 21）。

**收敛与停滞的可观测化**：`converged=false` 时 `duration_ms` 记实际墙钟、`exit_code=null`、报告保留终止前已落盘的 TAP 内容；`--run` 的 stdout 打印固定字段（S-2：命令 / 耗时 / 是否停滞 / 结论），使 AC-10 的证据无需人工回忆。

**进程树终止**：POSIX 用 `detached:true` + `process.kill(-pid, 'SIGKILL')`；Windows 用 `taskkill /PID <child.pid> /T /F`。**只终止本包装器自己 spawn 的 PID 树**，不按名字终止任何进程。

### 4.3 去重比较投影（FR-8 / FR-10）

```text
buildOutboxEvent(input, now):
  返回 { v:1, event_kind, cr_id, from_status:'', to_status:'', trigger:'',
         commit_sha:'', actor:'', evidence:{}, payload:{}, occurred_at: now }
  （字段集合 = OUTBOX_COMPARED_FIELDS ∪ OUTBOX_EXCLUDED_FIELDS，顺序固定）

buildOutboxComparable(event):
  out = {}; for (f of OUTBOX_COMPARED_FIELDS) out[f] = event[f]
  payload = { ...event.payload }
  for (k of OUTBOX_VOLATILE_PAYLOAD_KEYS) delete payload[k]   // 'detected_at' = payload 根下键名（与 §3.1 常量同一键空间）
  out.payload = payload
  return out
```

判重不变（与现状逐字等价）：`exists(target) && comparable(existing) === comparable(event) → 命中`；否则不等 → `OUTBOX_DEDUP_CONFLICT`。

### 4.4 文本语义断言（FR-2 / FR-4 / FR-5 / FR-7）

统一两步法：**先规范化行尾**（`replaceAll('\r\n','\n')`），再做「要素 + 零命中」两类断言；禁止把连接词、标点、语序、换行写进模式。

| 目标 | 机械断言（语义面） | 变红条件（负控） |
|---|---|---|
| BR-1 指令载体 | `skills/develop/write-dev-tasks/SKILL.md`：含 `crctl task init`；含对其受控账本 `tasks/_index.yml` 的「禁止手写」约束 | 删除任一要素 → 红 |
| BR-1 pipeline 语义 | `code-implementation.pipeline.json`：节点数 ≡ `pipeline-templates/_index.yml#code-implementation-v1.nodes`（跨文件投影）；所有节点 prompt 对受治理账本写指令零命中（命令面 `crctl (task init|task append|task done|advance|review-record|approve|owner-set|version-set)` 与账本文件名 `_index.yml` / `_backlog.yml`）；skill 节点 `ref` 存在 | 向任一 prompt 注入账本写指令 → 红 |
| BR-2 reader 事实源 | `skills/review/review-alignment/SKILL.md`：读取契约命中 `change-requests/_backlog.yml` 与 `cr.md`；`checkpoints[]` 零命中；`latest-checkpoint` **零命中**；`mtime` / `merge-commit` / `fingerprint` **不得作为事实源被读出**（机械判据见下方「否定辖域」） | 回退事实源（写回 `latest-checkpoint`、删 `_backlog.yml` 引用、或把 `mtime` / `merge-commit` / `fingerprint` 写成读取依据）→ 红 |
| BR-4 落盘校验语义 | `write-requirement-prd/SKILL.md`：定位含「重新读取」的校验句（先规范化行尾），断言该句内同时含三类对象——frontmatter 必填字段 / `七个章节` / `未替换占位符`；5 个禁用词零命中；`crctl validate` 与手工 commit 配方零命中 | 删除任一类对象或注入禁用词 → 红 |

> 「句内要素」判据：以中文句读（`。`/`；`/换行）切句后取命中断言锚点（`重新读取`）的那一句，再做要素包含判断。锚点本身就是被断言语义的一部分（该校验步骤的动词），不是措辞钉死对象。
> 「否定辖域」判据（BR-2 三词）：以**同一**句读切句后，对每个命中 `mtime` / `merge-commit` / `fingerprint` 的句子断言含否定锚点 `不读`；零命中同样满足。⇒ 把三词写成读取依据（非否定句）即红，而既有的「不读 mtime/merge-commit/fingerprint」表述不再被误判。**不对该文件要求零命中、也不回写该文件**：本机实测 `review-alignment/SKILL.md` 现共 2 处命中（`:33` 读取契约括号、`:51` 说明引用），均在含「不读」的否定句内。
> 现有实现提示：`write-requirement-prd/SKILL.md` 在 Windows 检出为 CRLF（本机实测失败输出含 `\r\n`），上述「先规范化」是硬要求。

### 4.5 BR-5 构造修正（FR-8 / FR-9）

**构造 A：真实崩溃窗口（替换 RED-7 r2）**

```text
1. 正常跑一次 archive（r1）：归档 commit + archive 事件真实写入（内容 = 该 commit 的真实事件）
2. 定位 journal：<kb>/.crctl/transactions/archive/<cr>/<txId>/journal.json
   把 payload.outboxEmitted 置回 false（模拟「文件已写、journal 未标记」的崩溃窗口）；
   顺带确认 archive 事件文件仍在、内容未变
3. 重放 archive（r2，同一 spec-id）：
   断言 warnings = []、outbox = `archive-<cr>-<commit>.json`、事件文件数量仍为 1、
   文件字节内容与 r1 完全一致（不覆盖）、origin master commit 数不变、r3 重放不再生成事件
```

该构造不改任何产品语义与断言，只把「预写同名不同内容的占位文件」换成**内容确实与本事件一致的文件 + 未标记 journal**——即真实崩溃窗口。

**构造 B：同名但内容不同（新增用例）**

```text
1. r1 正常归档 → 事件文件 E 存在
2. 将 E 的内容替换为不同内容（例如 {"placeholder":true}），并把 journal 的 outboxEmitted 置回 false
3. 重放 archive：
   断言 warnings 含 EMIT_FAILED（event_kind=archive）；.crctl/audit.log 出现
   `OUTBOX_DEDUP_CONFLICT`（可见信号至少其一，二者此处同时具备）；
   E 的内容仍是步骤 2 写入的内容（未覆盖）；journal 的 payload.outboxEmitted !== true（保持 pending）
4. 删除冲突文件 → 再重放：outbox 返回 `archive-<cr>-<commit>.json`、warnings = []、
   origin master commit 数不变（零新 commit）、E 内容为真实 archive 事件、outboxEmitted === true（补发成功）
```

**回归保护**：CR-2026-052 TASK-08 的 `detected_at` 语义测试（`crctl.test.mjs` 既有 drift-audit 用例）必须保持绿（FR-8.3）。

### 4.6 三类漂移负控协议（FR-13 / AC-11）

对每一类断言各做一次**真实注入**，注入后运行**全量命令**（`suite-gate --run`，即 CI 同款命令）记录非零退出与命中失败名，然后还原并确认重新变绿；注入物不得留在交付分支。

| # | 类别 | 注入动作（真实漂移） | 预期红点 | 还原 |
|---|---|---|---|---|
| N-1 | 状态机口径 | 向 `tools/dir-graph.yaml#state_machine.transitions` 增加一条真实转换（例如 `from: developing, to: developing, trigger: "crctl-test-injection"`） | `crctl.test.mjs` BR-3 用例（集合/计数不等） | 删除该行，`git status --short` 确认该文件干净 |
| N-2 | pipeline/Skill 文本语义 | 向 `write-requirement-prd/SKILL.md` 注入一个禁用词（例如 `validate-doc`）或删除「七个章节」要素 | `crctl.test.mjs` BR-4 用例 | 同上 |
| N-3 | 去重比较字段契约 | 在 `lib/outbox-contract.mjs#buildOutboxEvent` 增加一个未登记字段（例如 `observed_at`），或在 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 增加未登记键 | `trace-outbox.test.mjs` 契约用例（字段分类不变性） | 同上 |

证据留存（S-2 固定字段）：每个注入点存 1 份 `test-evidence/cmd-NN.log`，内容 = 命令、`duration_ms`、`converged`、`exit_code`、失败名、注入 diff 摘要、还原后的重跑结论。**注意**：全量命令每轮耗时以实测为准（基线既有实测 894.8 s；本机名字过滤子集实测 23.8 s），负控总计需要 6 次全量运行（3 注入 + 3 还原），实施/测试期需按其预算排期。

---

## 5. 技术选型与替代方案

（决策记录仅在同时满足「难以逆转 + 无上下文会疑惑 + 有真实权衡替代」时记录，共 4 条。）

### TDEC-1 门禁形态：包装器 + TAP 报告

- **Decision**：全量测试门禁由 `test/suite-gate.mjs` 包装 `node --test`，解析 TAP 后判定；CI 步骤只调用包装器。
- **Context**：FR-14 需要「登记但不得替代执行 + 到期即红 + 与真实失败集合双向匹配」，这些判定必须在**运行结果之上**做；FR-12 需要机械化的「耗时 / 是否停滞」证据；S-1 需要「每文件用例数」——三者都不是单个 `node --test` 进程能自报的。
- **Alternatives**：（a）全部塞进某个 `*.test.mjs`（否决：测试进程看不到其他文件的执行结果，且会让被测集合包含判定器本身）；（b）CI YAML 内联 shell+node 脚本（否决：命令与并发参数会同时出现在 CI 与文档两处，违反 FR-12.3「同一口径」）；（c）不引入包装器、只在测试里断言登记面（否决：残缺——无法覆盖「到期/集合差」语义）。
- **Consequences**：多一个新脚本与 TAP 解析面；TAP 结构是唯一外部耦合点，用「reporter 显式钉死（§4.2）+ 解析失败即硬失败」换取不静默降级。

### TDEC-2 受控清单承载：仓库内 git 跟踪的 JSON 数据文件

- **Decision**：`test/gate-registry.json` 承载状态机登记值、测试清单基线与例外登记处；唯一变更入口 = 人类编辑 + commit。
- **Context**：需要「单一登记处」（FR-14.1）、「可审计的受控写入」（FR-17/S-4）、「测试代码不得自证绿」（FR-14.4），且不能新增 crctl 子命令（FR-17）。
- **Alternatives**：（a）新建 `crctl exceptions` 子命令（否决：直接违反 FR-17，且账本写路径违背本 CR「断言只读」边界）；（b）把清单写死在测试代码里（否决：测试文件被改与被测对象被删会在同一处，留痕弱；且门禁包装器需要读同一份清单）；（c）放 `docs/` 或 `.github/`（否决：与测试同生命周期、由同一批 CR 维护，放在测试目录最贴近消费方，但**不是** `*.test.mjs` 所以不被 runner 采集）。
- **Consequences**：登记值变更必须显式提交（这正是「漂移当场红、除非显式更新目标值」的实现方式）；数据文件 schema 校验必须硬失败。

### TDEC-3 去重契约落点：库模块代码常量

- **Decision**：字段分类与投影函数落在 `lib/outbox-contract.mjs`，产品（`crctl.mjs`）与测试共同 import。
- **Context**：FR-10 要求「单一事实源，不得同时存在两份（注释一份、代码一份）」，并要能被测试断言。
- **Alternatives**：（a）运行时读 JSON 数据文件（否决：新增运行时 I/O 失败面，且 `emitOutboxEvent` 已在失败路径上，读文件失败会放大为业务失败）；（b）仅保留注释 + 测试内复制一份期望（否决：正是 FR-10 要消灭的双份）；（c）`gates.json` 加段（否决：该文件语义是状态/审批门禁映射，混入 outbox 契约会破坏其「运行时适配信息」定位）。
- **Consequences**：产品 import 面新增一个本地模块（零依赖、无副作用）；`crctl.mjs` 中原来的长注释收敛为指针，避免第二份语义描述。

### TDEC-4 `--test-concurrency=2` 的处置：按有界实测协议决定，默认去参

- **Decision**：设计默认 = **移除显式 `--test-concurrency=2`**（使用 runner 默认并发），并把该值作为唯一常量放在 `suite-gate.mjs` 内（命令单一来源）；若实测表明默认并发不收敛，则按 FR-12.2 改为 `--test-concurrency=1` 并同样留存证据。**不论哪个分支，交付必须带 §4.6 口径的实测证据。**
- **Context**：CR 输入约束（owner 转交）记录该参数下「本机 30+ 分钟不收敛（父进程空闲、子进程停滞）」；既有实测的全量 894.8 s（失败恰 5 条）未标注并发口径。即：唯一有「不收敛」观测的配置就是 `=2`，没有任何观测支持必须保留它。本机名字过滤子集实测 23.8 s/22 用例，说明断言面本身并不慢，慢/挂来自全量并发调度。
- **Alternatives**：（a）原样保留 `=2` 并只补文档（否决：会把「已知不收敛观测」的配置固化成门禁，且 FR-12.1 要求「保留须有 CI 可收敛证据」，本地不可得）；（b）直接写死 `--test-concurrency=1`（否决：无实测依据的顺序化可能使全量时间翻倍，且掩盖真正的停滞根因）；（c）删参数但不留测量（否决：AC-10 要求可复现证据）。
- **Consequences**：CI 与本地同命令；并发值变更只改一个常量；由 `--max-runtime-ms`（默认 30 min）把「停滞」从「无限挂起」变为「可观测、可登记的非收敛」。

---

## 6. FR 到技术实现映射

### 6.1 FR 映射表

| FR | 技术方案条目 | 落点 |
|---|---|---|
| FR-1 计数类推导 | §4.1 状态机推导 + §4.6-D2/D3 跨文件投影与目录事实源 | `assertion-sources.mjs`、`crctl.test.mjs` BR-3、`suite-gate` 清单核对 |
| FR-2 文本类只查语义 | §4.4 两步法（规范化 + 要素/零命中） | BR-1/2/4 三条断言 |
| FR-3 反风险与归类 | §6.6 归类清单（D1…D6 / P1…P7）+ §4.1 反恒真设计 + 负控 | 本 SDD §6.6、`crctl.test.mjs` |
| FR-4 BR-1 对齐真实载体 | §4.4 第 1、2 行 | `crctl.test.mjs:1337` |
| FR-5 BR-2 对齐 reader 事实源 | §4.4 第 3 行 | `checkpoint-tx.test.mjs:480` |
| FR-6 BR-3 推导 + 登记 | §4.1 + §2.3 `stateMachine` 段 | `crctl.test.mjs:4777`、`gate-registry.json` |
| FR-7 BR-4 语义要素 | §4.4 第 4 行 | `crctl.test.mjs:4989` |
| FR-8 保留去重语义 | §3.1 行为等价 + §2.2 字段归类 | `lib/outbox-contract.mjs`、`crctl.mjs` |
| FR-9 冻结向量构造改对 + 真实冲突用例 | §4.5 构造 A / B | `archive-tx.test.mjs:373` 与新增用例 |
| FR-10 去重契约可检查 | §3.1 不变性（字段分类 / 枚举排除 / 投影闭合 / 只读投影） | `lib/outbox-contract.mjs` + `trace-outbox.test.mjs` |
| FR-11 CI 真门禁 | §4.2 全流程 + 清单核对（21 文件集合相等） | `suite-gate.mjs`、`crctl-ci.yml:109-111` |
| FR-12 并发收敛决定 | TDEC-4 + §3.2 报告字段 + §4.2 停滞可观测化 | `suite-gate.mjs`（常量 + `--max-runtime-ms`） |
| FR-13 漂移负控 | §4.6 协议（3 类注入 + 全量命令 + 证据字段） | 实施/测试期证据 `test-evidence/cmd-NN.log` |
| FR-14 例外治理 | §2.3 `exceptions` + §3.2 四查与 check code 表 | `gate-registry.json`、`suite-gate.mjs`、`contract-scan.test.mjs` |
| FR-15 最小改写 | §1.2 变更面（产品面仅 outbox 契约提级）+ §9 scope_in/out | 全 diff |
| FR-16 零回归 | §4.4/§4.5 的负控与回归保护 + §2.3 `manifest.cases` ≥ 基线 | 全量套件 |
| FR-17 契约面与四查 | §3.3 无新增用户可调用契约 + §3.2 四查结论 | 本 SDD §3.2/§3.3 |

### 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-01 | `suite-gate --run`（§4.2）；`exceptions=[]` 时退出码 ≡ 失败集合为空 | CI 步骤退出码 0；报告 `failures=[]`、`files_executed=21`、`skipped_file_level=0`、`cases_executed>0` | 5 条红的修复（FR-4…FR-9）都在本 CR 内；`21` 由 `manifest.files` 登记并由实际执行集合核对；不依赖任何 skip/删除 |
| AC-02 | §4.4 断言→事实源两列表 + §6.6 分类清单 | 交付内含映射表；每条可用命令复取事实源；负控 N-1/N-2 使其变红 | 映射覆盖 BR-1…BR-4 涉及的计数/文本/跨文件投影三类；负控为可重放命令 |
| AC-03 | §6.6（D/P 两张表）+ §4.1 反恒真 | 归类清单逐条；`stateMachine.*` 显式登记；无「等于文件行数」型重述 | P 表由登记值承载，D 表由推导承载，二者独立来源 → 恒真式不可能同时满足集合比较与负控 |
| AC-04 | §4.4 BR-1 两行 | `crctl.test.mjs:1337` 用例绿；pipeline 零账本写指令；`write-dev-tasks` 载体含指令 | 只改测试断言（FR-15.1），产品文本零 diff |
| AC-05 | §4.4 BR-2 行 | `checkpoint-tx.test.mjs:480` 绿；`review-alignment/SKILL.md` 未新增 `latest-checkpoint`；三词仅在否定句内出现 | 断言对象是**当前**事实源（`cr.md` + `_backlog.yml` 条目信息），不需要改 SKILL 文本——该文件对 `latest-checkpoint` / `checkpoints[]` 当前零命中，三词的 2 处既有命中均在含「不读」的否定句内（本机实测），故断言按事实源现状成立 |
| AC-06 | §4.1 + §2.3 | 状态机用例绿；声明/展开由推导得出；具名状态与转换标识集合显式登记；负控 N-1 变红 | 推导源（`dir-graph.yaml`）与登记源（registry）独立，承重断言 = 三条集合/计数等价；推导侧结构自检恒真、仅作诊断（不计入覆盖） |
| AC-07 | §4.4 BR-4 行 | `crctl.test.mjs:4989` 绿；5 禁用词零命中；负控 N-2 变红 | 句内要素检查覆盖「删除校验步骤语义」与「注入禁用词」两种注入 |
| AC-08 | §4.5 构造 A/B + 回归保护 | RED-7 绿且构造为「内容一致 + journal 未标记」；新用例断言 `EMIT_FAILED`/`OUTBOX_DEDUP_CONFLICT`、pending、补发成功零新 commit；BR-5 语义未变 | 构造只动测试与 fixture journal 状态；产品零语义变更（§3.1 契约等价），drift-audit 既有用例不在改写面内 |
| AC-09 | §3.1 不变性 2/3/4 + §4.3 | `trace-outbox` 契约用例绿；字段分类集合相等；`payload.observed_at` 反例证明非自动排除；投影结果与 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 交集为空；负控 N-3 变红 | 新增字段必须登记进两个集合之一、新增易变键必须登记进 `OUTBOX_VOLATILE_PAYLOAD_KEYS`，否则集合相等 / 投影闭合断言直接失败（不依赖人工比对） |
| AC-10 | TDEC-4 + §3.2/§2.4 固定字段 | 交付含 `command/duration_ms/converged/exit_code` 与结论；CI 与文档同口径（命令只来自包装器常量） | 默认分支（去参）与回退分支（`=1`）都在包内可执行；`--max-runtime-ms` 保证「停滞」可产出证据而不是无限挂起 |
| AC-11 | §4.6 | N-1/N-2/N-3 各一次注入 → 全量命令红 → 还原后绿；命令与关键输出留 `test-evidence/` | 注入点全部在本 CR 的断言覆盖面上；注入物由 `git checkout -- <path>` 还原并核验干净 |
| AC-12 | §2.3 `exceptions` + §3.2 | 交付态 `exceptions: []`（显式空，非文件缺失）；构造到期条目 → `EXCEPTION_EXPIRED` 非零；登记面写入口仅人工提交；`contract-scan` 静态断言无代码写路径 | 到期判定只用运行时瞬时 + 登记时间戳，确定性；「不匹配即红」由双向集合比较实现 |
| AC-13 | §1.2 变更面 + §9 scope | diff 仅 tests / CI / `lib/outbox-contract.mjs` + `crctl.mjs` 的最小改点；BR-1…BR-4 产品面零 diff；无新增依赖/框架 | 产品面改点仅 `emitOutboxEvent` 的契约提级，`git diff --stat` 可逐条核 |
| AC-14 | §2.3 `manifest.cases` + §4.4/§4.5 | 全量 21 文件无新增红、无新增 skip（`skipped_file_level=0`）；交付含与 894.8 s 同口径的耗时对比 | 用例数 ≥ 基线为门禁硬约束；耗时同口径由 `suite-gate` 报告字段保证 |
| AC-15 | §3.2 四查 + §3.3 + §8 | 交付声明无新增用户可调用契约；例外面四查逐条结论；未新增对外入口 | 本 CR 无 crctl dispatch/deny 面变更（§8 已核） |

### 6.3 既有实现依赖与事实

按正文首次出现顺序登记（固定结构）。所有 `commit SHA` = `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`（本机实测 `git rev-parse HEAD`，CR worktree clean）。

```text
1. repo: tools
   relative path: dir-graph.yaml
   stable symbol/对象: change-request-track.state_machine.{transitions, wildcards.any-active, terminal}
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 推导的唯一事实源。本机实测（lib/yaml-subset.parseYaml 解析）：声明转移 31 条、
             其中 from=any-active 2 条、any-active 目标 12 个、结构推导展开数 31-2+12*2=53；
             具名状态 15 个，注册前态 (new)。本 CR 不改该文件，只把它读成推导输入。

2. repo: tools
   relative path: skills/shared/crctl/scripts/lib/yaml-subset.mjs
   stable symbol/对象: parseYaml(text, { strict })
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 零依赖 YAML 子集解析器，本机实测可正确解析上述状态机段（transitions/wildcards 结构完整）。
             本 CR 复用它做推导，避免新增解析依赖与第二套正则口径（ARCHITECTURE 不变量 3）。

3. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: emitOutboxEvent（:293 起）；内联比较块（:320-346，含 comparable() 与 payload.detected_at 特例）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 现状判重语义 = 逐字段内容相等（排除 payload.detected_at）；不等 → OUTBOX_DEDUP_CONFLICT →
             调用方 EMIT_FAILED。本 CR 保留该语义，仅把「哪些字段参与比较」从注释提为可检查声明（§3.1）。

4. repo: tools
   relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
   stable symbol/对象: archiveCr（:3449）/ emitArchiveIfNeeded（:3510 附近，payload.outboxEmitted 语义）/
                       archive 事件发送点（:3520）/ cleanup-pending 落盘（:3683, :3705）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: archive 事件在 origin confirmed 后、cleanup 前发送；发送失败只追加
             {code:'EMIT_FAILED'} warning、不改变 phase、且不置 payload.outboxEmitted；
             phase=complete 的历史 journal 重放仍会重试事件且不新增 commit。
             本 CR 的 RED-7 构造与「同名不同内容」用例据此断言 pending 与可补发（§4.5）。

5. repo: tools
   relative path: skills/shared/crctl/scripts/test/merge-fixture.mjs
   stable symbol/对象: 导出 `sha256`(:11) / `git`(:14) / `runCrctl`(:20) / `makeFixture`(:27) / `makeCodeApprovedFixture`(:95) / `originMasterCount`(:197)
                       （本机实测：该文件共 6 个 `export`，无其他导出形式）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 既有共享 fixture；本 CR 的 archive 用例与状态机用例沿用同一构造方式（`makeCodeApprovedFixture` 造 code-approved 场景，
             `git` / `runCrctl` / `sha256` / `originMasterCount` 做断言与计数），不新增 fixture 框架。

6. repo: tools
   relative path: skills/shared/crctl/scripts/test/archive-tx.test.mjs
   stable symbol/对象: 文件内局部 helper `makeWritebackFixture`(:14) 与 `archiveOutboxFiles`(:231)
                       （两者是本文件局部函数，**不在 `merge-fixture.mjs` 中**；本机实测）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: RED-7 所在文件的构造面——用例体（:374）用 `makeWritebackFixture` 造 kb 场景、:393 用
             `archiveOutboxFiles` 枚举 outbox 事件文件。本 CR 的 RED-7 构造改对与「同名不同内容」新用例
             沿用这两个局部 helper，**不上提**到共享 fixture（不扩大 diff、不影响其他测试文件）。

7. repo: tools
   relative path: .github/workflows/crctl-ci.yml
   stable symbol/对象: 步骤 `crctl full test suite`（:109-111）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 现状命令 = `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`
             （无例外、无 skip 白名单）。本 CR 把该步骤改为调用 suite-gate（§4.2），命令单一来源迁入包装器常量。

8. repo: tools
   relative path: skills/develop/write-dev-tasks/SKILL.md
   stable symbol/对象: `crctl task init` 指令（:106）与受控账本禁手写约束（:115）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: BR-1 断言对象的真实载体——该指令的权威落点是本 SKILL，而不是 pipeline JSON。

9. repo: tools
   relative path: pipeline-templates/code-implementation.pipeline.json
   stable symbol/对象: nodes[16]；`crctl task init` / `_index.yml` / 手写索引 指令均为零命中（本机实测）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: BR-1 的另一半断言对象（pipeline 只编排 Skill）。节点数的登记处 =
             pipeline-templates/_index.yml#code-implementation-v1.nodes（本机实测 = 16），
             断言以跨文件投影形式读取该值，不在测试里写第二份 16。

10. repo: tools
   relative path: skills/review/review-alignment/SKILL.md
   stable symbol/对象: 读取契约第 2 条（读 cr.md frontmatter + _backlog.yml 条目基本信息；不读 mtime/merge-commit/fingerprint；检查清单 AL-01…AL-06）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: BR-2 断言对象。本机实测该文件对 `checkpoint` 零命中；当前事实源是 cr.md + _backlog.yml 条目信息。

11. repo: tools
    relative path: skills/requirement/write-requirement-prd/SKILL.md
    stable symbol/对象: Step 4 落盘后重新读取校验句（:89）
    commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    依赖结论: BR-4 断言对象。现文为「七个章节、未替换占位符」（连接词已由 AIFI-22 改为顿号），
              5 个禁用词零命中；本机实测该文件在 Windows 检出为 CRLF → 断言必须先做行尾规范化。

12. repo: tools
    relative path: skills/shared/crctl/scripts/test/*.test.mjs
    stable symbol/对象: 测试文件集合 = 21 个（本机实测目录计数）
    commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    依赖结论: manifest 基线的登记对象；本 CR 不新增测试文件，交付后仍为 21 个。

13. repo: tools
    relative path: skills/shared/crctl/scripts/test/archive-tx.test.mjs
    stable symbol/对象: `TASK-01 RED-7`（:373）——当前构造预写「同名但内容不同」的占位文件
    commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    依赖结论: owner 裁定「构造改对」的对象（§4.5）；原断言集合全部保留。

14. 基线红登记（本 CR 的起点事实，不是方案前提）
    repo: tools / commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    本机实测（SDD 作者，2026-09-13，Windows / Node v24.15.0，CR worktree clean）：
      命令: node --test --test-name-pattern="CR-2026-037|checkpoint T05|TASK-06|CR-2026-042|RED-7"
            skills/shared/crctl/scripts/test/{crctl,checkpoint-tx,archive-tx}.test.mjs
      结果: exit 1；tests 22 / pass 17 / **fail 恰 5** / skipped 0；duration 23.8 s
            （其中 RED-7 单独 23.7 s）
      5 条失败与本 CR 的 BR 编号一一对应:
        BR-1 crctl.test.mjs:1337 `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引`（引入 14b4458）
        BR-2 checkpoint-tx.test.mjs:480 `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]`（引入 fc2b142）
        BR-3 crctl.test.mjs:4777 `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）`（实测 31 ≠ 登记 28；引入 bef1f4d + 2e4442d + 49c46dd）
        BR-4 crctl.test.mjs:4989 `CR-2026-042 静态合同：已知 Skill 越界文本零命中`（断言「和」措辞，现文为「、」；引入 fc797ed）
        BR-5 archive-tx.test.mjs:373 `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖`（构造失真）
    既有实测（非本机本轮，来自 CR 输入与 PRD §1.3，作者与 reviewer 各自独立跑过一次）：
      全量 21 个 *.test.mjs（不带例外）= exit 1 / 894.8 s / 失败恰 5 条；
      CI `contracts` job 其余 5 步（lint-prompts / skill-matrix / agents-contract / pipeline JSON 结构 / writeback 单测）
      在本机（Windows / Node v24.15.0）逐步全绿，CI 平台为 ubuntu+windows / Node 20，跨平台差异未验证。
    依赖结论: 上述红是**既有事实**，本 CR 的交付目标正是把它清空（AC-01）。
              本 SDD 全文不把「CI 现在是绿的」作为前提或依赖断言；「绿」只作为本 CR 变更后的实测结论出现。
```

### 6.4 待核实依赖

| 项 | 状态 | 处理 |
|---|---|---|
| `tools/ARCHITECTURE.md` §5 不变量 5 的「28 条声明、wildcard 展开 50 条」 | 与 `dir-graph.yaml` 当前内容（31 / 53）**不一致**（既有文档口径滞后，非本 CR 引入） | **不作为本 CR 方案前提**：本 CR 的登记目标值全部从 `dir-graph.yaml` 推导并登记到 `gate-registry.json`，方案不读该段文本；修正该段列入 §9 `follow_up`（ARCHITECTURE.md 对普通 CR 只读，其 §8 维护规则规定该类修订需独立触发） |
| CI（ubuntu+windows / Node 20）上的全量耗时与收敛性 | 本机不可得 | 按 S-2 口径：证据以「本机复现 + 可得时的 CI 运行」交付；AC-10 只要求「可复现证据」，不在本地伪造 CI 事实 |
| `--test-concurrency` 两个候选配置的收敛性 | 需实测 | TDEC-4 的协议：默认（去参）与 `=1` 各 ≥2 次连续运行；选中者写入包装器常量 |

### 6.5 SDD-CLOSE（PRD/评审显式延后到 SDD 的设计项，逐项关闭）

| 编号 | 来源 | 关闭结论 |
|---|---|---|
| SDD-CLOSE-01 | S-1（测试清单受控） | 关闭：`gate-registry.json#manifest`（文件集合相等 + 每文件用例数 ≥ 基线）由 `suite-gate` 在 CI 硬校验；「删测试换绿」必须同时改受控数据文件并在 diff 中留痕 |
| SDD-CLOSE-02 | S-2（证据口径与固定字段） | 关闭：口径 = 本机复现 + 可得时的 CI 运行；字段写死 = §2.4 报告模型（command/duration_ms/converged/exit_code/files/cases/failures/checks） |
| SDD-CLOSE-03 | S-3（any-active 目标集合并入受控清单） | 关闭：`gate-registry.json#stateMachine.wildcards`；目标增删即红（§4.1） |
| SDD-CLOSE-04 | S-4（受控写入入口 + 固定 check code） | 关闭：写入口 = 人类编辑 + git commit（审计 = `git log -- gate-registry.json`），无新 crctl 入口；check code 表见 §3.2 |
| SDD-CLOSE-05 | S-5（到期定义收紧） | 关闭：带时区偏移的 ISO-8601 时间戳，比较基准 = 门禁运行时 UTC 瞬时，`now >= expires` 即过期（§2.1） |
| SDD-CLOSE-06 | FR-14.4（不得自证绿） | 关闭：门禁只读登记面（无写路径）+ `contract-scan` 静态断言「仓库内无对登记文件的写调用」+ 登记不替代执行（失败始终上报） |
| SDD-CLOSE-07 | FR-10（契约落点） | 关闭：`lib/outbox-contract.mjs` 单一事实源（TDEC-3），产品与测试共同 import |
| SDD-CLOSE-08 | FR-17（契约面声明） | 关闭：不新增用户可调用契约（§3.3）；例外登记面四查逐条结论见 §3.2 |
| SDD-CLOSE-09 | 本轮评审 S-1（`SUITE_NONCONVERGENCE` 的可容忍性两读法） | 关闭：显式定为「可抑制（可绿）」，条件 = 未到期 + `kind: suite-nonconvergence` + 稳定标识匹配；事实面（`converged:false`、`checks[]`、`failures[]`）永不隐藏；非收敛分支不做清单/失败集合核对、不混算 `SUITE_REPORT_UNPARSEABLE`；其余 check code 一律不可容忍（§3.2 退出码段） |
| SDD-CLOSE-10 | 本轮评审 S-2（推导侧结构不变量恒真） | 关闭：§4.1 步 9 标注为「推导侧自检，恒真」并从断言块移出、不计入覆盖；承重断言只有三条集合/计数等价（§4.1、§6.2 AC-06） |
| SDD-CLOSE-11 | 本轮评审 S-3（TAP reporter 依赖未登记默认值） | 关闭：包装器唯一命令来源显式钉 `--test-reporter=tap`（§4.2），并以**内联 TAP 片段**在 `contract-scan.test.mjs` 做 `--report/--rc` 解析自测（合法 + 三类畸形），不新增测试文件（§4.2、§1.2） |

### 6.6 FR-3 归类清单：可推导的事实 vs 必须钉死的目标值

**可推导的事实（硬编码其快照 = 缺陷）**

| # | 事实 | 事实源 | 推导方式 | 防恒真设计 |
|---|---|---|---|---|
| D1 | 状态机声明转移数 / 展开数 / wildcard 目标集合 | `dir-graph.yaml#state_machine` | `deriveStateMachine()`（parseYaml，硬失败） | 与显式登记的 P2/P3 集合比较；两条独立来源 |
| D2 | pipeline 节点数与节点结构 | `pipeline-templates/*.pipeline.json` ↔ `_index.yml#nodes` | 跨文件投影比较 | 任一侧单独漂移即红 |
| D3 | 测试文件集合与执行规模 | 目录实际执行集合（runner 报告）↔ `manifest` | 集合相等 + 计数 ≥ 基线 | 实际值由 runner 产出，登记值由人工维护 |
| D4 | pipeline 是否指导直写受治理账本 | pipeline JSON prompt 文本 | 命令面/账本文件名扫描（零命中） | 注入即红（N-2 同类） |
| D5 | Skill 文本的禁用词与结构性载荷 | 相关 `SKILL.md` | 零命中 + 句内要素 | 注入/删除即红 |
| D6 | reader 事实源引用 | `review-alignment/SKILL.md` 读取契约段 | 命名标识在/不在 + 三词否定辖域（§4.4） | 回退事实源（写回 `latest-checkpoint` 或把三词写成读取依据）即红 |

**必须钉死的目标值（显式登记，不得由推导自动接受）**

| # | 目标值 | 登记处 | 变更纪律 |
|---|---|---|---|
| P1 | 具名状态集合（15 个；注册前 `(new)` 单列） | `gate-registry.json#stateMachine.namedStates` | 变更须显式更新登记值 |
| P2 | 每条声明转换的稳定标识 `(from,to,trigger)` | `#stateMachine.transitions` | 同上 |
| P3 | wildcard 名 → 目标集合（`any-active` → 12） | `#stateMachine.wildcards` | 同上 |
| P4 | pipeline 结构不变量（code-implementation 节点数 = 16） | `pipeline-templates/_index.yml#nodes`（既有登记处） | 变更须显式更新该字段 |
| P5 | 测试清单基线（文件集合 + 每文件用例数） | `#manifest` | 变更须在 diff 中显式提交 |
| P6 | 去重比较字段集合 + 必须排除的易变字段集合 | `lib/outbox-contract.mjs`（+ 测试中的钉死期望） | 变更须显式登记，否则字段分类不变性红 |
| P7 | 例外清单（交付态 = 空） | `#exceptions` | 逐条含 owner + 到期；到期未清即红 |

**不属本分类（fixture 局部计数，本 CR 不改动）**：测试自建 fixture 产生的计数断言（如 `events.length === 1`、`audits.length === 1`、`files.length === 1`、`repos.length === 3`）。判据：**被断言的数量由测试自身构造决定，不由仓库事实源读取**——这类断言随场景变化，硬编码是正确形态。属 `scope_out`（§9）。

---

## 7. 安全与性能考量

### 7.1 边界条件与错误处理

- **行尾纪律**（ARCHITECTURE 不变量 4）：所有新断言与解析在 `replaceAll('\r\n','\n')` 之后进行（本机实测 `write-requirement-prd/SKILL.md` 为 CRLF 检出，BR-4 的失败输出即含 `\r\n`）。
- **解析硬失败**：状态机推导（结构不符）、TAP 解析（结构不符 / 无 plan / 数量矛盾）、`gate-registry.json`（缺失 / schema 不符）一律抛错 → 非零退出，**禁止**降级为空集合或「零失败」。唯一例外是登记面自身的可抑制项（§3.2）：进程未自行结束时改判 `SUITE_NONCONVERGENCE`，且该分支不产生 `SUITE_REPORT_UNPARSEABLE`。
- **空集合必须显式**：`exceptions: []` 是显式声明；文件缺失是 `SUITE_REGISTRY_MISSING`（红），不是「无例外」。
- **不静默改写**：门禁判定全程只读；任何失败都不写 `gate-registry.json`、不写受治理账本、不改被测仓。
- **进程管理**：超时终止只针对本包装器自己的子进程树（POSIX 进程组 / Windows `taskkill /T`），不按进程名终止。

### 7.2 安全控制点

- 例外登记面不得成为自证绿通道（FR-14.4）：写入口唯一（人工提交）、代码侧零写路径（静态断言）、失败始终上报。
- 断言不得被弱化为恒真（FR-3）：登记值与推导值独立来源 + 负控可重放。
- 断言只读：不改 `_backlog.yml` / `cr.md` / `approval.yml` / `tasks/_index.yml` 的写入路径（无新增写路径）。

### 7.3 性能

- 推导与静态断言只读本地文件；**每个测试文件内不重复遍历全仓**——`assertion-sources.mjs` 对同一文件提供带缓存的读取；不引入网络与子进程风暴。
- 全量套件耗时：基线既有实测 894.8 s（失败恰 5 条）；本机名字过滤子集实测 23.8 s。TDEC-4 的协议要求交付同口径对比（`--run` 报告字段）。
- `--max-runtime-ms` 默认 30 min：把「停滞」从无限挂起变为可观测事件（`converged=false` + `SUITE_NONCONVERGENCE`）。
- 负控实验（§4.6）需 6 次全量运行，实施/测试期按实际耗时排期；不要求额外的基础设施。

### 7.4 兼容性

- 双环境一致：命令与断言不依赖 shell 特性（`shell:false` spawn + 在包装器内展开 glob），Windows（本机 CR worktree，autocrlf 检出）与 CI（bash）同结论。
- Node 版本：只用 Node ≥ 18 标准库（本机 v24.15.0；CI 为 Node 20）；`--test-reporter=tap` 显式钉死（§4.2），TAP 解析不依赖 Node 版本专有输出格式，结构不符即硬失败。
- 历史证据不改写：不动历史 CR 产物与归档；不改 `specs/`、`delivery/`。

---

## 8. Prompt 采纳影响

**判定：不适用（N/A）。** 本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（新增/变更子命令面），也**不触及** `skills/shared/controlled-shell/rules.json#protectedPaths.deny`；本 CR 不新增 crctl 子命令或 flag（FR-17/§3.3），因此不存在「crctl 新增了能力、某 skill 该采纳却还没采纳」的清单。

核查（实施期同款命令）：

```powershell
# 1) 本 CR 的 crctl.mjs 改点只在 emitOutboxEvent（非 dispatch 分支）
git diff --stat -- skills/shared/crctl/scripts/crctl.mjs
git diff -U0 -- skills/shared/crctl/scripts/crctl.mjs | Select-String '^\+' | Select-String 'emitOutboxEvent|outbox-contract'
# 2) rules.json 零 diff
git diff --stat -- skills/shared/controlled-shell/rules.json
# 3) 无新增子命令：dispatch 表未变
git diff -U0 -- skills/shared/crctl/scripts/crctl.mjs | Select-String 'case .(task|advance|approve|review-record|checkpoint|archive|merge|writeback-apply)'
```

---

## 9. 批准范围

### `scope_in`（本 CR 必须交付）

- FR-1 / FR-2 / FR-3：断言去硬编码与归类清单（§4.1、§4.4、§6.6）。
- FR-4 / FR-5 / FR-6 / FR-7：BR-1…BR-4 四条断言按其事实源对齐转绿（`crctl.test.mjs:1337/4777/4989`、`checkpoint-tx.test.mjs:480`）。
- FR-8 / FR-9 / FR-10：BR-5 构造改对 + 新增「同名不同内容」用例 + 去重契约提为可检查声明（`lib/outbox-contract.mjs`、`crctl.mjs#emitOutboxEvent` 最小改点、`archive-tx.test.mjs`、`trace-outbox.test.mjs`）。
- FR-11 / FR-12：CI 全量步骤成为真门禁（`suite-gate.mjs` + `crctl-ci.yml:109-111`）与并发收敛决定 + 实测证据。
- FR-13：三类漂移负控注入的全量运行证据（`test-evidence/`）。
- FR-14：例外单一登记处 + owner + 到期 + 到期即红 + 不得自证绿（`gate-registry.json#exceptions`、`suite-gate.mjs`、`contract-scan.test.mjs` 静态断言）。
- FR-15 / FR-16 / FR-17：最小改写、零回归、契约面声明与四查。

### `scope_out`（明确不做）

- 包 B：不改 `write-tech-design` / `review-tech-design` 的 SDD 评审合同（owner 已裁）。
- CR-2026-064 的恢复合同迁移本身（冻结在 `tech-design-review-pending`）；本 CR 不依赖也不改变 `recoverCommand` / `recover_command` 现状。
- 不改 5 条红的根因对象**本身**：pipeline 文本、状态机条目、`write-requirement-prd` 文本、alignment reader 合同、archive outbox 链路的业务语义（只对齐断言/构造）。
- 不改 CI 之外的交付/发布流程（push-progress / merge / archive / writeback 的算法与门禁语义）。
- 不含 multica 仓测试面；不新增测试框架或第三方依赖（含 YAML 解析依赖）。
- 不改写历史证据（历史 CR 产物、归档 traceability/delivery）。
- 不把 fixture 局部计数断言（§6.6 末段）纳入「必须推导」改造面——它们不是事实源快照。
- 不做平台 Prompt 部署（tools 侧文本变化在平台侧生效由 owner 另行执行）。

### `zero_diff`（明确不得改动的调用点/签名）

- `crctl.mjs` 顶层 dispatch 与所有既有子命令的**签名、参数、错误码**零 diff（`emitOutboxEvent` 内部实现改点除外，且其返回语义不变）。
- `skills/shared/crctl/scripts/lib/yaml-subset.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs` 零 diff。
- `skills/shared/controlled-shell/rules.json` 零 diff；`dir-graph.yaml` 零 diff；`pipeline-templates/*` 零 diff；所有 `SKILL.md` 零 diff。
- 状态机、错误码、事务语义、`reviewLoop` / archive / merge / checkpoint / writeback 业务算法零 diff。
- `approval.yml` / `cr.md` / `_backlog.yml` / `tasks/_index.yml` / `traceability.yml` / `review-annotations/**` 的写入路径零新增（断言只读）。
- 历史 CR 产物与 `specs/`、`delivery/` 零 diff。

### `follow_up`（发现但留给后续 CR）

1. `tools/ARCHITECTURE.md` §5 不变量 5 的「28 条声明 / wildcard 展开 50 条」已滞后于 `dir-graph.yaml` 当前内容（31 / 53）；按该文档 §8 维护规则，属需独立触发的文档修订，不在本 CR 内改（本 CR 未改变状态机，登记目标值一律从 `dir-graph.yaml` 推导）。建议随下一次触及状态机口径的 CR 一并修正，或单开文档修订 CR。
2. 其余 pipeline 节点数硬编码断言（本轮评审 S-4，本机核对）未纳入本次「跨文件投影」改造：`crctl.test.mjs:4961`（读 `_index.yml#nodes` 后钉死 16）、`pipeline-structure.test.mjs:41`（`ids.length` 钉死 16；同文件 `:94-96` 已有同口径跨文件投影断言）、`pipeline-structure.test.mjs:183`（requirement-authoring 钉死 7）。三条当前均为绿；若后续 CR 触及 `_index.yml#nodes`，应在同一 CR 内一并改为投影断言（本 CR 只改 BR-1 触及处，避免扩大 diff）。
3. 例外登记面若在后续 CR 首次出现真实例外，需同步在 `test-report` 与回写产物中记录「例外 → owner → 到期」闭环；本 CR 交付态为空，未产生该流程的运行实例。
