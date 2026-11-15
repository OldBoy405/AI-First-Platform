# Spec: crctl-report

> Change: 2026-11-15-crctl-report-active-count | Auto-generated Human View

## Requirements

### Requirement: `crctl report` 的 `active` 只统计状态不在终态集合内的 CR；`total` 与 `statusHistogram` 按 CR 编号去重，同一 CR 在 CR 目录与 `_history.yml` 同时出现时只计一次。

#### Scenario: SC-001

- **GIVEN** 夹具工作区有 3 个 CR 目录（frontmatter 分别为 archived、withdrawn、archived）， 3 个 id 全部同时登记在 `change-requests/_history.yml` 且 final-status 一致；tools 包 `dir-graph.yaml` 声明 `change-request-track.state_machine.terminal: [archived, rejected, withdrawn]`
- **WHEN** 执行 `crctl report --workspace <ws>`
- **THEN** SHALL 返回 `active` 为 0、`total` 为 3
- **AND** `archived` 为 3
- **AND** `statusHistogram` 为 `{archived: 2, withdrawn: 1}`
- **AND** `statusHistogram` 各状态计数之和等于 `total`

#### Scenario: SC-002

- **GIVEN** 夹具含：目录 CR `developing`（不在 history）；目录 CR `archived` 且在 history； 目录 CR `rejected`（终态，不在 history）；仅 history 的 `CR-OLD`（final-status withdrawn）
- **WHEN** 执行 `crctl report --workspace <ws>`
- **THEN** SHALL 返回 `active` 为 1（`active` 是计数，不输出逐条列表），且 `statusHistogram` 中唯一的非终态键为 `developing`
- **AND** `total` 为 4
- **AND** `archived` 为 2
- **AND** `statusHistogram` 为 `{developing: 1, archived: 1, rejected: 1, withdrawn: 1}`

#### Scenario: SC-007

- **GIVEN** 目录 `cr.md` frontmatter 为 `developing`，同一 id 在 `_history.yml` 中 final-status 为 `withdrawn`
- **WHEN** 执行 `crctl report --workspace <ws>`
- **THEN** SHALL 以 history 的 final-status 为准：`active` 为 0
- **AND** `statusHistogram` 为 `{withdrawn: 1}`，不出现 `developing`

### Requirement: `report` 的终态集合只取自 tools 包 `dir-graph.yaml#change-request-track.state_machine.terminal`； 取不到时命令硬失败，不猜、不回退。

#### Scenario: SC-003

- **GIVEN** tools 包 `dir-graph.yaml` 的 `state_machine` 不含 `terminal`，或 `terminal` 不是字符串数组
- **WHEN** 执行 `crctl report --workspace <ws>`
- **THEN** SHALL 以非零状态退出，`stderr.error.code` 为 `REPORT_TERMINAL_UNAVAILABLE`
- **AND** stdout 不输出 `op: report` 报表

### Requirement: 既有 `report` 与 `report --period` 行为不回归：断言与输出字段保持不变。

#### Scenario: SC-004

- **GIVEN** 既有两条 `report` 用例逐字未改
- **WHEN** 运行整个 `crctl.test.mjs`（不加名称过滤）
- **THEN** SHALL 全部通过：`fail 0`，且通过数不少于 305（原有 301 + 新增 4）
- **AND** `period`、`periodActivity`、`sla`、`archived` 的语义与旧实现一致

### Requirement: 对真实知识库工作区，在途数不再包含已归档 CR，总数不再重复计数。

#### Scenario: SC-005

- **GIVEN** 知识库主 checkout（76 个 CR 目录全部登记在 `_history.yml`）
- **WHEN** 执行 `crctl report --workspace '../AI First Platform'`
- **THEN** SHALL 返回 `active` 为 0
- **AND** `total` 等于目录与 history 的不同编号数
- **AND** `statusHistogram` 各状态计数之和等于 `total`

### Requirement: `cr-dashboard` 技能文档对 `report` 口径的描述与实现一致，且不内建终态枚举副本。

#### Scenario: SC-006

- **GIVEN** `skills/cr/cr-dashboard/SKILL.md` 的 Step 2 口径段
- **WHEN** 人工阅读该段
- **THEN** SHALL 明示终态不计入在途、重复登记不重复计数
- **AND** 终态来源指向 `dir-graph.yaml#change-request-track.state_machine.terminal`，不复制枚举
