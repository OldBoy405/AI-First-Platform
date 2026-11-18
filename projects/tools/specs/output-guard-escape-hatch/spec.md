# Spec: output-guard-escape-hatch

> Change: 2026-11-18-defensive-trim-tools | Auto-generated Human View

## Requirements

### Requirement: OutputGuard 的 Pre 与 Post 对同次 shell 调用只认命令首行的逃生标记。

#### Scenario: SC-OGE-001

- **GIVEN** 同一 shell 调用首行有合法逃生标记及原因，后续有命令（含 CRLF 的情形）。
- **WHEN** 用同一命令调用 Pre 与 Post。
- **THEN** SHALL 在两端以 escape-hatch 跳过封顶，Post 返回完整正文。

#### Scenario: SC-OGE-002

- **GIVEN** 首行是普通 shell 命令，只有第二行有合法标记。
- **WHEN** 用同一命令调用 Pre 与 Post。
- **THEN** SHALL 在两端执行普通判定，ruleId 均非 escape-hatch。
