# 工作区入口精简与 STDD／CR 流程隔离 — 测试方案与详细案例

> Change：`2026-11-06-stdd-default-cr-opt-in`；模式：standard；task_type：documentation。
> 本方案支撑 design 的四条保证（G1–G4），共四个 TC：两个人工、两个命令。执行结果见 `test-report.md`；未运行不等于通过。

## 一、测试策略

### 1.1 能证明什么

文档变更没有产品代码。本方案只证明：入口文案给出的路由决定正确（G1）、保护点没有丢失（G2）、配置与全局行没变（G3）、既有机器消费者没坏（G4）。它不证明运行时路由、真实模型遵循、部署或最终请求 token 占比。

### 1.2 原则

- 每个检查对应一条保证，不为同一保证重复检查，也不为措辞钉死字符串；字符量只作测量值。
- 人工 TC 的确认语句由用户在阅读评审结果后给出原文（`--channel dialog`）；AI 不代签，也不提交 AI 自拟的“人工确认”。
- 文本读入先 CRLF → LF；YAML 用 STDD venv 的 PyYAML 解析；解析失败即失败，不降级为空。
- 命令检查只读：不 register、approve、merge 或 writeback，不修改文件、状态或账本。
- 知识库顶层文件和全局文件无法被 CLI 冻结：TC-PG-002 同次运行打印它们的 LF SHA-256，人工确认语句须引用这些哈希；交付前在提交清单确认时重算核对。这是人工纪律，不是机器保证。
- tools 全量 `quality.test` 不属于本 change 的保证（理由见 design D6），C2 按“未运行及原因”记录，由用户在 Gate 3 确认。

## 二、详细测试案例

### 功能一：workflow-routing

#### TC-WFR-001 — 六类输入的入口决定（人工，盲评）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WFR-001 |

- **对应 Spec**：REQ-WFR-001 / SC-WFR-001；**优先级**：P0。
- **预置条件**：tools `AGENTS.md` 的 CR 驳回段已按 design D5 改完；评审者不是写入者本人，且不阅读 design D1 表。
- **输入**：评审者只读知识库 `AGENTS.md` 与 tools `AGENTS.md`，对六类输入各答“选哪个流程、是否创建／修改、还需何种授权、何时停止”：只读分析；已有 STDD change 或 CR；未指定流程的新开发（含知识库 cwd 无绑定但目标 tools 明确）；显式选择 tools CR；目标、绑定或归属不明；仅持有一个 STDD Gate 或另一流程批准却要求推进 CR、提交、推送或部署。
- **预期**：六个答案与 design D1 表一致；两份入口中没有相反的无条件要求（无条件读取完整 CR 手册、对已有 CR 套用 STDD 默认值）。主会话逐行比对并把答案和比对结果写入 `test-report.md`。
- **确认**：用户阅读答案与比对结果后以 `agent confirm --tc TC-WFR-001` 给出原文。

### 功能二：prompt-governance

#### TC-PG-001 — 保护点对照（人工）

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-001 |

- **对应 Spec**：REQ-PG-001 / SC-PG-001；**优先级**：P0。
- **预置条件**：写前基线见 design 末节；成品为 tools 与知识库的当前工作副本。
- **输入**：对 design D2 的八个保护点，在成品中逐项指出所在文件与位置（或迁往的权威文件）；查看 README、CONTEXT 相对基线的差异；检查 tools `AGENTS.md` 的包边界、矩阵／索引要求，以及它是否仍含复写的状态转换表或固定计数。
- **预期**：八项均为“保留”或“已迁往某权威文件”，没有缺失；README、CONTEXT 只有批准的入口说明差异，领域定义未变；tools `AGENTS.md` 保留包边界与矩阵／索引要求，不含复写的转换表或固定计数。对照表写入 `test-report.md`。
- **确认**：用户阅读对照表后以 `agent confirm --tc TC-PG-001` 给出原文。

#### TC-PG-002 — 图配置与全局行（命令）

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-002 |

- **对应 Spec**：REQ-PG-002 / SC-PG-002 / CP-PG-001；**优先级**：P0。
- **输入**：执行 CP-PG-001（见 `canonical/specs/agent/prompt-governance.yaml`）。
- **预期**：退出 0 并输出 `CP-PG-001 PASS`：`dir-graph.yaml` 除两个仓库的 `description` 外与基线提交的版本完全相等；全局文件第 2 行的 SHA-256 等于批准原文的哈希（原文见 design D5）。输出的五个 LF SHA-256 记入 `test-report.md`。

#### TC-PG-003 — tools 入口的既有结构依赖（命令）

| 字段 | 内容 |
|---|---|
| **ID** | TC-PG-003 |

- **对应 Spec**：REQ-PG-003 / SC-PG-003 / CP-PG-002；**优先级**：P1。
- **输入**：执行 CP-PG-002：`node --test skills/shared/crctl/scripts/test/contract-scan.test.mjs`。
- **预期**：退出 0，全部用例通过。该文件读取 tools `AGENTS.md` 的 `### 修改 Pipeline` 节并断言其第 9 条；2026-11-15 在当前工作副本上的预跑结果为 44/44 通过，仅作参考，不是证据。

## 三、证据计划

```stdd-evidence-plan-v1
{
  "task": "prompt-governance",
  "inputs": [
    {"root": "project", "path": "AGENTS.md"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/contract-scan.test.mjs"}
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "文档变更，没有产品代码；覆盖率采集目前只支持 pytest-cov"
  },
  "checks": [
    {"tc": "TC-WFR-001", "case_id": "main", "requirement": "REQ-WFR-001", "scenarios": ["SC-WFR-001"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-PG-001", "case_id": "main", "requirement": "REQ-PG-001", "scenarios": ["SC-PG-001"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-PG-002", "case_id": "main", "requirement": "REQ-PG-002", "scenarios": ["SC-PG-002"], "cp": "CP-PG-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-PG-003", "case_id": "main", "requirement": "REQ-PG-003", "scenarios": ["SC-PG-003"], "cp": "CP-PG-002", "kind": "command", "applicability": "required"}
  ]
}
```

## 四、执行顺序

1. 完成 tasks B1（tools `AGENTS.md` 驳回段），并确认 tools 的 `AGENTS.md` 与 `contract-scan.test.mjs` 不再变化。
2. 调用方自选 run id（`[A-Za-z0-9_-]{1,128}`，如 uuid），依次执行并使用同一个 id：
   - `stdd agent verify prompt-governance --change 2026-11-06-stdd-default-cr-opt-in --run <run-id>`（执行 CP-PG-001、CP-PG-002）。
   - 盲评与保护点对照，结果写入 `test-report.md`；该文件不是证据计划的冻结输入。
   - 用户给出确认原文后：`stdd agent confirm prompt-governance --change 2026-11-06-stdd-default-cr-opt-in --run <run-id> --tc <TC> --statement "<原文>" --channel dialog`（TC-WFR-001、TC-PG-001 各一次）。
   - `stdd ci check-failures 2026-11-06-stdd-default-cr-opt-in --run <run-id>`。
3. 两次执行之间不再运行别的 `agent verify`；确认之前如受审输入变化，必须重新执行。
4. 汇总 `test-report.md`（引用该 run），再请求 Gate 3。

## 五、回归风险

| 区域 | 风险 | 保护 |
|---|---|---|
| 已有 CR／审批／操作根 | 默认值误接管或放宽旧门禁 | TC-WFR-001、TC-PG-001 |
| 知识库 `AGENTS.md` 的既有保护条款 | 精简时丢失 | TC-PG-001 |
| graph／全局文件 | 说明性修改引入配置漂移 | TC-PG-002 |
| tools `AGENTS.md` 的机器消费者 | 改动破坏结构依赖 | TC-PG-003 |
