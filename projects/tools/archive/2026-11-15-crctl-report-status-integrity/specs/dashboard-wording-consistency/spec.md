# Spec: dashboard-wording-consistency

> Change: 2026-11-15-crctl-report-status-integrity | Auto-generated Human View

## Requirements

### Requirement: `skills/spec/spec-dashboard/SKILL.md` 对在途 CR 的口径引用 `crctl report` 的输出，不再自行定义分组规则、不再把终态行放在「在途」表里、 不再用 `_backlog.yml` 判空。

#### Scenario: SC-DWC-001

- **GIVEN** 改后的 spec-dashboard/SKILL.md
- **WHEN** 检查文件内容并运行 `lint-prompts.mjs --mode enforce`
- **THEN** SHALL 文件含 `report.statusHistogram` 与 `report.active`；不含旧分组句（按 cr.md frontmatter status 分组计数）、旧判空句（`change-requests/_backlog.yml` 为空）、表内终态行（`archived / rejected / withdrawn` 的数量行）；lint 为 0 findings
- **AND** 表后有一句说明：上表只列非终态状态，终态 CR 不属于在途，在途总数取 `report.active`
