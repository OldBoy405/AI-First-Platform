# prompt-governance — 规格

> 依据：[已确认提案](../../canonical/proposals/2026-11-06-stdd-default-cr-opt-in.yaml) 的 C1、C3–C6、constraints 与成功标准；设计见 [design.md](../../design.md) D2、D4–D6。
> 证据：TC-PG-001（人工）、TC-PG-002（命令）、TC-PG-003（命令），见 [test-plan.md](../../test-plan.md)。静态检查与人工评审不证明运行时路由、部署或 token 占比。

## REQ-PG-001 — 精简入口不丢失保护条款

#### Scenario: SC-PG-001 — 保护点对照

- **TC**：TC-PG-001；**Confidence**：high。
- **GIVEN**：知识库入口、README、CONTEXT 与 tools 入口已按本 change 修改。
- **WHEN**：评审者对照写前基线，逐项核对 design D2 的八个保护点以及 README、CONTEXT、tools 入口的差异。
- **THEN**：SHALL 每个保护点在成品中语义保留，或明确迁往某个权威文件，没有保护点缺失。
- **AND**：README 与 CONTEXT 只有批准的入口说明差异，领域定义未变。
- **AND**：tools 入口的包边界、矩阵／索引要求仍在，且不再含复写的状态转换表或固定计数。

## REQ-PG-002 — 说明性修改不改变配置

#### Scenario: SC-PG-002 — 图配置与全局行

- **TC**：TC-PG-002；**Confidence**：high。
- **GIVEN**：`dir-graph.yaml` 与全局 `APPEND_SYSTEM.md` 已修改。
- **WHEN**：与固定基线比较。
- **THEN**：SHALL `dir-graph.yaml` 除 `ai-first-platform-docs`、`tools` 两个仓库的 `description` 外与基线完全相等，且全局文件第 2 行等于批准原文。
- **AND**：比较在同一次运行中打印五个文件的 LF SHA-256，供人工评审引用。

## REQ-PG-003 — 既有机器消费者不被破坏

#### Scenario: SC-PG-003 — tools 入口的结构依赖

- **TC**：TC-PG-003；**Confidence**：high。
- **GIVEN**：tools `AGENTS.md` 已修改。
- **WHEN**：运行对其内容有结构依赖的既有测试 `contract-scan.test.mjs`。
- **THEN**：SHALL 全部通过。

## 覆盖与评审边界

3 个 Requirement、3 个 Scenario、3 个 TC（1 人工、2 命令）。字符量只作测量值，不是通过条件。
