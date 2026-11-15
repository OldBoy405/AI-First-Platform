# 测试方案与详细案例 — crctl report 在途数口径修正

> 版本：1.0（lightweight）
> 创建日期：2026-11-15
> 对应 Phase 2 Spec：`canonical/specs/code/crctl-report.yaml`、`canonical/specs/agent/crctl-report.yaml`

## 一、测试策略

### 1.1 测试金字塔

本次改动是单个只读命令的统计口径，无外部依赖、无并发、无 IO 副作用：**单元测试为主**（`node --test` + 临时工作区夹具，与既有 `report` 测试同构），**一次真实工作区核对**（只读，防“夹具对了但真实数据仍错”），**一次人工文档核对**（技能文字）。

### 1.2 测试原则

- 断言须含能区分对错的观测值：具体 `active` / `total` / `statusHistogram` 键值，不得只断言退出码 0。
- 每个失败路径都要有对应用例（终态不可判必须硬失败，不是跳过）。
- 既有 `report`、`report --period` 用例**断言逐字不改**，作为回归证据。
- 夹具一律建在系统临时目录，跑完删除；不触碰真实 checkout、账本或 `_history.yml`。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 2 条 `report` 相关 | 单元 | 直方图／周期活动计数、`--period` 窗口过滤、非法 period |
| 同上（既有夹具） | — | 单元 | `makeWorkspace()`、`makeToolsFixture()`（其 `dir-graph.yaml` 恰好没有 `terminal`，可直接用于失败路径） |

新增用例标题带 `TCRPT001`…`TCRPT004` 令牌，证据计划用 `--test-name-pattern` 逐条单独执行，避免多条 command 用例共用一次执行结果。

## 二、详细测试案例

### 功能 1：在途数与直方图口径

#### 案例 1.1 — 目录与 history 重复登记的终态 CR 不重复计数、不计入在途

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-001 |
| **对应 Spec** | `crctl-report` → Scenario SC-001 |
| **优先级** | P0 |
| **预置条件** | 夹具 tools 包 `dir-graph.yaml` 含 `terminal: [archived, rejected, withdrawn]`；3 个 CR 目录（frontmatter 分别为 archived／withdrawn／archived）全部同时登记在 `_history.yml`，`final-status` 与之一致 |
| **输入** | `crctl report --workspace <ws>` |
| **预期结果** | `active=0`、`total=3`、`archived=3`、`statusHistogram` 为 `{archived:2, withdrawn:1}`，各状态之和等于 `total` |
| **当前状态** | ❌ 测试缺（现状会给出 `active=3`、`total=6`） |

#### 案例 1.2 — 混合来源只把非终态目录 CR 计入在途

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-002 |
| **对应 Spec** | `crctl-report` → Scenario SC-002 |
| **优先级** | P0 |
| **预置条件** | 夹具含：①目录 CR `developing`（不在 history）②目录 CR `archived` 且在 history ③目录 CR `rejected`（终态，不在 history）④仅 history 的 `CR-OLD`（`final-status: withdrawn`） |
| **输入** | `crctl report --workspace <ws>` |
| **预期结果** | `active=1`（只剩 `developing`）、`total=4`、`archived=2`（history 中带 archived-at 的两条）、`statusHistogram` 为 `{developing:1, archived:1, rejected:1, withdrawn:1}` |
| **当前状态** | ❌ 测试缺 |

#### 案例 1.3 — 目录 frontmatter 与 history 冲突时以 history 为准

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-003 |
| **对应 Spec** | `crctl-report` → Scenario SC-007 |
| **优先级** | P0 |
| **预置条件** | 目录 CR 的 `cr.md` frontmatter 为 `developing`，同一 id 在 `_history.yml` 中 `final-status: withdrawn` |
| **输入** | `crctl report --workspace <ws>` |
| **预期结果** | `active=0`；`statusHistogram` 只有 `withdrawn:1`，`developing` 不出现 |
| **当前状态** | ❌ 测试缺 |

### 功能 2：终态集合不可判时硬失败

#### 案例 2.1 — tools 包缺 terminal 声明 → 非零退出且不输出报表

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-004 |
| **对应 Spec** | `crctl-report` → Scenario SC-003 |
| **优先级** | P0 |
| **预置条件** | 夹具 tools 包 `dir-graph.yaml` 的 `state_machine` **不含** `terminal`（复用 `makeToolsFixture()`）；另建一例 `terminal: "archived"`（非数组） |
| **输入** | `crctl report --workspace <ws>` |
| **预期结果** | 两种夹具都 `status=1`、`stderr.error.code=REPORT_TERMINAL_UNAVAILABLE`，`stdout` 无 `op: report` 输出 |
| **当前状态** | ❌ 测试缺（现状静默按“无终态”出数） |

### 功能 3：既有行为不回归

#### 案例 3.1 — 既有 report 与 report --period 用例不改断言继续通过

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-005 |
| **对应 Spec** | `crctl-report` → Scenario SC-004 |
| **优先级** | P0 |
| **预置条件** | 测试文件仅新增用例，既有两条 `report` 用例逐字不变 |
| **输入** | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`（整文件回归，共 305 条） |
| **预期结果** | 全部通过：`fail 0`、`pass ≥ 305`（原有 301 + 新增 4） |
| **当前状态** | ✅ 已覆盖（既有用例） |

### 功能 4：真实工作区核对

#### 案例 4.1 — 知识库主 checkout 的在途数为 0、总数为不同编号数

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-006 |
| **对应 Spec** | `crctl-report` → Scenario SC-005 |
| **优先级** | P0 |
| **预置条件** | 知识库工作区 `../AI First Platform`（76 个 CR 目录全部登记在 `_history.yml`） |
| **输入** | `node skills/shared/crctl/scripts/crctl.mjs report --workspace "../AI First Platform"`，并由独立脚本重算期望值 |
| **预期结果** | `active=0`；`total` 等于“目录 ∪ history 的不同编号数”；`statusHistogram` 各状态之和等于 `total`；打印实际值供评审 |
| **当前状态** | ❌ 未核对（现状 `active=76, total=152`） |

### 功能 5：技能文档口径

#### 案例 5.1 — cr-dashboard 不再把终态 CR 列入在途

| 字段 | 内容 |
|------|------|
| **ID** | TC-RPT-007 |
| **对应 Spec** | `crctl-report` → Scenario SC-006 |
| **优先级** | P1 |
| **预置条件** | `skills/cr/cr-dashboard/SKILL.md` 已改 |
| **输入** | 人工阅读 Step 2 口径段 |
| **预期结果** | 明示终态不计入在途、重复登记不重复计数，并指向 `dir-graph.yaml#change-request-track.state_machine.terminal`；不内建终态枚举副本 |
| **当前状态** | ❌ 待改 |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E | 状态 |
|----------|---------|----------|-----|------|
| `cmdReport` 口径 | TC-RPT-001/002/003 | TC-RPT-006（真实工作区） | — | 🟡 |
| 终态不可判失败 | TC-RPT-004 | — | — | 🟡 |
| 既有回归 | TC-RPT-005 | — | — | 🟢 |
| 技能文档 | — | — | TC-RPT-007（人工） | 🟡 |

## 四、回归风险矩阵

| 改动区域 | 风险 | 覆盖 |
|----------|------|------|
| `cmdReport` 计数逻辑 | 其他调用方依赖旧口径 | TC-RPT-001/002/003 + 全仓 grep 消费者（只有两份看板技能） |
| 新增终态依赖 | 无 tools 包终态定义的工作区由“出数”变“报错” | TC-RPT-004 + proposal 约束 |
| `--period` / SLA | 被误改 | TC-RPT-005（既有用例逐字不变） |
| 技能文档 | 口径描述与实现不一致 | TC-RPT-007 |

## 五、建议补充顺序

1. P0：TC-RPT-001 → 002 → 003 → 004（先红后绿）
2. P0：TC-RPT-005（回归）
3. P0：TC-RPT-006（真实工作区）
4. P1：TC-RPT-007（文档）

## 六、同次执行证据计划

```stdd-evidence-plan-v1
{
  "task": "crctl-report",
  "inputs": [
    {"root": "project", "path": "skills/shared/crctl/scripts/crctl.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/crctl.test.mjs"},
    {"root": "project", "path": "skills/cr/cr-dashboard/SKILL.md"},
    {"root": "project", "path": "dir-graph.yaml"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Node 栈，仓库覆盖率检查只支持 pytest-cov"},
  "checks": [
    {"tc": "TC-RPT-001", "case_id": "report-dedupe-terminal", "requirement": "REQ-RPT-001",
     "scenarios": ["SC-001"], "cp": "CP-RPT-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-RPT-002", "case_id": "report-mixed-sources", "requirement": "REQ-RPT-001",
     "scenarios": ["SC-002"], "cp": "CP-RPT-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-RPT-003", "case_id": "report-history-wins", "requirement": "REQ-RPT-001",
     "scenarios": ["SC-007"], "cp": "CP-RPT-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-RPT-004", "case_id": "report-terminal-unavailable", "requirement": "REQ-RPT-002",
     "scenarios": ["SC-003"], "cp": "CP-RPT-004", "kind": "command", "applicability": "required"},
    {"tc": "TC-RPT-005", "case_id": "report-regression", "requirement": "REQ-RPT-003",
     "scenarios": ["SC-004"], "cp": "CP-RPT-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-RPT-006", "case_id": "report-real-workspace", "requirement": "REQ-RPT-004",
     "scenarios": ["SC-005"], "cp": "CP-RPT-006", "kind": "command", "applicability": "required"},
    {"tc": "TC-RPT-007", "case_id": "dashboard-text", "requirement": "REQ-RPT-005",
     "scenarios": ["SC-006"], "kind": "manual", "applicability": "required"}
  ]
}
```
