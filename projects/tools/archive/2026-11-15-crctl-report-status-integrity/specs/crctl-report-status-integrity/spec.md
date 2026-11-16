# Spec: crctl-report-status-integrity

> Change: 2026-11-15-crctl-report-status-integrity | Auto-generated Human View

## Requirements

### Requirement: `crctl report` 对每个 `change-requests/CR-*` 目录要么计入 total 与直方图，要么硬失败并指出该目录； 没有 `cr.md`、没有 frontmatter、或 `status` 为空的目录不再被静默跳过，错误码与 `crctl status` 一致（`CR_MD_STATUS_MISSING`）。

#### Scenario: SC-RSI-001

- **GIVEN** 三个独立工作区，各含一个目录 `CR-A`：(a) cr.md 有 frontmatter 但没有 status 字段；(b) 目录下没有 cr.md（或 cr.md 没有 frontmatter）； (c) cr.md 的 `status: ""`（空字符串）。每个工作区另含目录 `CR-B`（status 为 developing）作对照
- **WHEN** 对每个工作区运行 `crctl report --workspace <ws>`
- **THEN** SHALL 每个都退出码 1，错误码 `CR_MD_STATUS_MISSING`，错误对象的 cr 为 `CR-A`、path 为 `change-requests/CR-A/cr.md`、field 为 `status`
- **AND** 标准输出没有 JSON 报表

### Requirement: 状态集合 = 状态机 `transitions[].to` ∪ `terminal`。目录 `cr.md` 的 `status` 与 `_history.yml` 的 `final-status` 不在该集合内时硬失败（`SCHEMA_INVALID`，点名 CR 与取值），声明内的状态不受影响；状态机的 `transitions` 不可用时按 `REPORT_TERMINAL_UNAVAILABLE` 失败。

#### Scenario: SC-RSI-002

- **GIVEN** 真实 tools 根；独立工作区分别含 (a) 目录 CR-T 的 develping；(b) history 中 CR-H 的 archvied；(c) 目录 CR-P 的未声明 __proto__；另含 false、0、数组及带首尾空白的 status 样本
- **WHEN** 对每个工作区运行 `crctl report`
- **THEN** SHALL 每个都退出码 1、错误码 SCHEMA_INVALID，错误对象点名对应的 CR、路径、字段与取值；false/0 不得被误分类为字段缺失
- **AND** 标准输出没有 JSON 报表（`__proto__` 既不丢计数也不静默通过：要么计入要么失败，这里是失败）

#### Scenario: SC-RSI-003

- **GIVEN** 真实 tools 根；一个工作区按真实声明的状态集合各建一个 CR，无 history；另一个权威 tools 夹具合法声明 __proto__、constructor、toString 并为其各建一个 CR
- **WHEN** 分别运行 `crctl report`
- **THEN** SHALL 两个工作区均退出码 0；total 等于对应声明状态数，active 等于非终态 CR 数，直方图键集合与各 CR 状态集合相同、每个值为 1
- **AND** 真实声明当前为 15 个状态、12 个在途；期望从声明推导，不把该数字作为未来状态集合的固定上限
- **AND** 合法动态键均为 JSON 自有属性、值为 1，不受继承属性影响；未声明的 __proto__ 仍按 SC-RSI-002 拒绝

#### Scenario: SC-RSI-004

- **GIVEN** 一个 tools 根夹具：dir-graph 声明了 `terminal`，但 `transitions` 缺失、为空、或某个 `to` 不是合规字符串（三种各一个夹具）
- **WHEN** 运行 `crctl report`
- **THEN** SHALL 退出码 1，错误码 `REPORT_TERMINAL_UNAVAILABLE`，错误对象 reason 为 `transitions-missing-or-invalid`，标准输出没有 JSON 报表

### Requirement: 归档已发布（journal 的 `pushed=true`）但本地主 checkout 未同步时，`crctl report` 与 `crctl status` 对该 CR 同口径： 以已发布的归档状态计入直方图，不计入 active；未发布的归档意图不算完成。

#### Scenario: SC-RSI-005

- **GIVEN** `makeWritebackFixture`：本地 KB 主 checkout dirty，归档已发布，本地 `_history.yml` 尚无该 CR，本地 cr.md 仍是归档前的 `merging`
- **WHEN** 先运行 `crctl status <cr>` 确认其为 archived 且 terminal，再运行 `crctl report`
- **THEN** SHALL report 退出码 0，total 为 1，active 为 0，statusHistogram 为 `{archived: 1}`，archived 为 0（`archived` 只计 history 里带 archived-at 的条目）
- **AND** 未发布的情形（`archive-after-commit` 故障点，journal 中无 pushed=true）：report 仍计 active 为 1，statusHistogram 为本地状态，不得被报成 archived

### Requirement: 在真实 `change-requests/` 数据上，`crctl report` 的 total、active、archived、statusHistogram 与改前逐项相同； 既有 `report` 测试全部通过。

#### Scenario: SC-RSI-006

- **GIVEN** 真实 `AI First Platform` 工作区，改前与改后各运行一次 `crctl report`
- **WHEN** 逐项比较 total、active、archived、statusHistogram
- **THEN** SHALL 四项完全相同；`crctl.test.mjs` 中全部 `report` 相关用例（TCRPT001–004、AC-6 两个）改后通过
- **AND** 新基线若因期间新增 CR 而不同，须逐项解释差异来自数据而非代码（对照 git log 与目录清单）

### Requirement: `tools/CUSTOM.md` 的「AIFI-45 局部修复登记」节登记本 change 对 tools 的修改。

#### Scenario: SC-RSI-007

- **GIVEN** 改后的 `tools/CUSTOM.md`
- **WHEN** 人工检查新增行
- **THEN** SHALL 新增一行，列为 日期｜位置｜改动｜边界，位置含 `crctl.mjs#cmdReport` 与 `spec-dashboard/SKILL.md`，边界写明成功时输出字段不变、保留 history 对重复 id/缺 final-status 的拒绝及覆盖优先级、不改其他命令；文件保持 LF，不含编造的 CR 编号
