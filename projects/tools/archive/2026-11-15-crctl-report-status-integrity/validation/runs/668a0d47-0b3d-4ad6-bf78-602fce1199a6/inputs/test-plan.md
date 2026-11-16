# crctl report 状态完整性 测试方案与详细案例

> 版本：2026-11-15-crctl-report-status-integrity
> 创建日期：2026-11-15
> 对应 Phase 2 Spec：`canonical/specs/code/` 下 `crctl-report-status-integrity.yaml`、`dashboard-wording-consistency.yaml`

## 一、测试策略

### 1.1 测试金字塔

- 2026-11-16 修订：保留八个 Scenario，验收从八项收敛为三组命令、两项人工，共五个 TC；尚无执行证据，不把旧条目转换为 PASS。
- 状态边界矩阵（TC-RSI-001）：一次 Node 调用运行 TCRSI001..004，覆盖 SC-RSI-001..004，内部断言缺失/非法输入、合法状态与动态键、坏声明；原 TC-RSI-002/003/004 并入此项。
- 真实 Git 夹具（TC-RSI-005）：覆盖 SC-RSI-005 的已发布/未发布两侧。夹具只推本地 bare remote，不访问真实项目远端。
- 文档检查（TC-DWC-001）：既有 lint 加窄内容核对，不新增 lint 规则。
- 人工检查：同一真实数据快照前后比较及既有 report 回归（TC-RSI-006）、CUSTOM 登记（TC-RSI-007）。

### 1.2 测试原则

- 每个检查只对应一条保证；错误路径的检查必须同时断言「标准输出没有 JSON 报表」，防止失败时仍打印部分结果。
- 先 RED 再 GREEN：TC-RSI-001、TC-RSI-005 与 TC-DWC-001 在改前应失败；状态矩阵中的 TCRSI003 保留全部合法状态正向对照，不能因为合并 TC 删除它。
- 失败样本和成功样本成对：TCRSI003 证明合法集合不被误拒，另用权威夹具声明 __proto__/constructor/toString 证明动态键正确计数。
- 命令直接运行 Node TAP；同时核对明确测试标识、pass/fail 计数与原进程退出码，不使用 Python 日志管道，不将零匹配当通过。
- 校验类脚本先对已知好样本自测（记取证教训：校验逻辑本身也会出错）。
- 断言须含能区分对错的观测值（具体错误码、点名的 CR、total/active/直方图的具体数字），不得只匹配 PASS 标签。 / Assertions must carry observable values that distinguish right from wrong.
- 人工检查如实标注为人工；真实数据回归是基线对比，不做成永久 CP（新增 CR 会让固定数字过期）。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| `skills/shared/crctl/scripts/test/crctl.test.mjs`（TCRPT001–004、AC-6 两个） | 6 | 黑盒 | report 的去重、终态、history 冲突与不可判数据；本 change 不改其断言，仅补默认夹具的一条转移 |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs`（AIFI-65 R3） | 1 | 集成（真实 git 夹具） | `status` 对已发布未同步归档的结论；TCRSI005 复用其 `makeWritebackFixture` |
| `skills/shared/crctl/scripts/lint-prompts.mjs` | — | 静态检查 | SKILL.md 与 crctl 口径漂移 |

## 二、详细测试案例

### 功能 1：状态输入矩阵（REQ-RSI-001、REQ-RSI-002）

#### 案例 1.1 — 缺失、未知、合法状态与坏声明

| 字段 | 内容 |
|------|------|
| **ID** | TC-RSI-001 |
| **对应 Spec** | crctl-report-status-integrity → SC-RSI-001、002、003、004 |
| **优先级** | P0 |
| **预置条件** | 独立临时工作区与权威 tools 夹具；保留 developing 正向对照，不改真实账本 |
| **输入** | TCRSI001：无 status、无 cr.md/frontmatter、空 status；TCRSI002：目录 develping、history archvied、未声明 __proto__，以及 false/0/数组/带首尾空白的 status；TCRSI003：真实声明全部状态与另一个合法声明 __proto__/constructor/toString 的夹具；TCRSI004：transitions 缺失、为空、to 非法 |
| **预期结果** | TCRSI001 为 CR_MD_STATUS_MISSING；TCRSI002 为 SCHEMA_INVALID，均点名 CR/路径/字段/取值且无 JSON；TCRSI003 的 total/active 从声明推导，直方图键集合精确且每值为 1、动态键为 JSON 自有属性；TCRSI004 为 REPORT_TERMINAL_UNAVAILABLE、reason=transitions-missing-or-invalid 且无 JSON。四个顶层测试内部逐样本断言；一次 TAP 运行须包含四个标识、# pass 4、# fail 0、退出 0 |
| **当前状态** | 测试待 BUILD；本轮未运行验收。原 TC-RSI-002/003/004 合并，全部八个 Scenario 仍保留 |

### 功能 3：已发布未同步的归档（REQ-RSI-003）

#### 案例 3.1 — report 与 status 同口径

| 字段 | 内容 |
|------|------|
| **ID** | TC-RSI-005 |
| **对应 Spec** | crctl-report-status-integrity → SC-RSI-005 |
| **优先级** | P0 |
| **预置条件** | `archive-tx.test.mjs` 的 `makeWritebackFixture`（真实 git，本地 KB dirty 使同步被跳过）；另一个夹具用故障点 `archive-after-commit` 制造「已提交未发布」 |
| **输入** | 已发布：先 `crctl status`（须为 archived 且 terminal），再 `crctl report`；未发布：`crctl report` |
| **预期结果** | 已发布：report 退出码 0，total 1，active 0，statusHistogram `{archived: 1}`，archived 0；未发布：active 1，直方图为本地状态，不得为 archived；标题含 `TCRSI005`，TAP 包含 `# pass 1`、`# fail 0`，直接运行 Node 的退出码为 0。改前已发布情形 active 为 1、直方图为 `{merging: 1}`（2026-11-15 实测）是现成红样本 |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

### 功能 4：真实数据回归与登记（REQ-RSI-004、REQ-RSI-005）

#### 案例 4.1 — 真实数据逐项相同

| 字段 | 内容 |
|------|------|
| **ID** | TC-RSI-006 |
| **对应 Spec** | crctl-report-status-integrity → SC-RSI-006 |
| **优先级** | P0 |
| **预置条件** | 真实 `AI First Platform` 工作区；改前基线（2026-11-15）total 76、active 0、archived 76、statusHistogram `{archived: 68, withdrawn: 8}` |
| **输入** | 改后运行 `crctl report --workspace <ws>`，并运行 `crctl.test.mjs` 中全部 report 用例 |
| **预期结果** | 四项与基线逐项相同（若期间新增 CR 而不同，逐项解释差异来自数据）；既有 report 用例全部通过。人工检查，输出写入 test-report |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

#### 案例 4.2 — 登记

| 字段 | 内容 |
|------|------|
| **ID** | TC-RSI-007 |
| **对应 Spec** | crctl-report-status-integrity → SC-RSI-007 |
| **优先级** | P1 |
| **预置条件** | 改后的 `tools/CUSTOM.md`（LF 文件） |
| **输入** | 人工检查新增行 |
| **预期结果** | 「AIFI-45 局部修复登记」节新增一行，列 日期｜位置｜改动｜边界；位置含 `crctl.mjs#cmdReport` 与 `spec-dashboard/SKILL.md`；边界写明成功输出字段不变、保留 history 的重复 id/缺 final-status 拒绝及覆盖优先级、不改其他命令；文件保持 LF，不含编造的 CR 编号 |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

### 功能 5：dashboard 措辞（REQ-DWC-001）

#### 案例 5.1 — spec-dashboard 引用 crctl report

| 字段 | 内容 |
|------|------|
| **ID** | TC-DWC-001 |
| **对应 Spec** | dashboard-wording-consistency → SC-DWC-001 |
| **优先级** | P1 |
| **预置条件** | 改后的 spec-dashboard/SKILL.md |
| **输入** | `lint-prompts.mjs --mode enforce`，再检查文件内容 |
| **预期结果** | `0 findings`；文件不含 `cr.md` frontmatter `status` 分组句、`change-requests/_backlog.yml` 判空句、`archived / rejected / withdrawn |` 终态行；含 `report.statusHistogram` 与 `report.active`；输出 `bad [] need []` 与 `CP-DWC-001 PASS` |
| **当前状态** | ❌ 测试缺（改前 `bad` 含三项，是现成红样本） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | 人工 | 状态 |
|----------|---------|----------|------|------|
| 缺 status | TC-RSI-001 | — | — | 🔴 待 BUILD |
| 状态集合与字典 | TC-RSI-001（SC-RSI-002/003/004） | — | — | 待 BUILD |
| 已发布未同步归档 | — | TC-RSI-005 | — | 🔴 待 BUILD |
| 真实数据回归、登记 | — | — | TC-RSI-006、007 | 🔴 待 BUILD |
| dashboard 措辞 | TC-DWC-001 | — | — | 🔴 待 BUILD |

## 四、回归风险矩阵

| 风险区域 | 本次改动 | 已有回归保护 | 风险等级 |
|---------|---------|-------------|---------|
| report 成功路径的输出 | 不改字段与语义 | TCRPT001–003、AC-6 两个；TC-RSI-001 的合法状态矩阵、TC-RSI-006 | 低 |
| report 失败面扩大 | 缺 status 与未声明状态由静默变失败 | TC-RSI-001 点名断言；TC-RSI-006 核实当前真实数据而非依赖历史 0 缺失 | 中 |
| 归档兜底新调用点 | 对非终态、仅目录来源的 CR 调用 `publishedArchiveStatus` | TC-RSI-005 覆盖已发布与未发布两侧 | 🟡 |
| 默认夹具补转移 | `makeReportToolsFixture` 默认声明增加一条 `to: developing` | TCRPT001–004 原断言不改，BUILD 阶段全部重跑 | 🟢 |

## 五、建议补充顺序

1. 实施前取得真实数据基线；TC-RSI-001 固化全部状态输入矩阵，先 RED 再 GREEN。
2. TC-RSI-005 固化真实 Git 的已发布/未发布对照；TC-DWC-001 对齐看板引用。
3. TC-RSI-006/007 在 BUILD 收尾分别比较真实数据与核对登记；不新增重复的整套扫描。

## 六、同次执行证据计划

```stdd-evidence-plan-v1
{
  "task": "crctl-report-status-integrity",
  "tasks": [
    "crctl-report-status-integrity",
    "dashboard-wording-consistency"
  ],
  "inputs": [
    {"root": "project", "path": "skills/shared/crctl/scripts/crctl.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/crctl.test.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/archive-tx.test.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/lint-prompts.mjs"},
    {"root": "project", "path": "skills/spec/spec-dashboard/SKILL.md"},
    {"root": "project", "path": "dir-graph.yaml"},
    {"root": "project", "path": "CUSTOM.md"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Node 栈，仓库覆盖率检查只支持 pytest-cov"},
  "checks": [
    {"tc": "TC-RSI-001", "case_id": "state-boundary-matrix", "requirement": "REQ-RSI-001",
     "scenarios": ["SC-RSI-001", "SC-RSI-002", "SC-RSI-003", "SC-RSI-004"], "cp": "CP-RSI-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-RSI-005", "case_id": "published-unsynced-archive", "requirement": "REQ-RSI-003",
     "scenarios": ["SC-RSI-005"], "cp": "CP-RSI-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-RSI-006", "case_id": "real-data-regression", "requirement": "REQ-RSI-004",
     "scenarios": ["SC-RSI-006"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-RSI-007", "case_id": "custom-ledger", "requirement": "REQ-RSI-005",
     "scenarios": ["SC-RSI-007"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-DWC-001", "case_id": "dashboard-wording", "requirement": "REQ-DWC-001",
     "scenarios": ["SC-DWC-001"], "cp": "CP-DWC-001", "kind": "command", "applicability": "required"}
  ]
}
```
