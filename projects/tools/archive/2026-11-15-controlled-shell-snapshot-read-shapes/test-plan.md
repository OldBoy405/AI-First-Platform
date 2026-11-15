# controlled-shell git show 形状 测试方案与详细案例

> 版本：2026-11-15-controlled-shell-snapshot-read-shapes
> 创建日期：2026-11-15
> 对应 Phase 2 Spec：`canonical/specs/code/2026-11-15-controlled-shell-snapshot-read-shapes.yaml`（capability `controlled-shell-git-show-shapes`）

## 一、测试策略

### 1.1 测试金字塔

只有数据文件（rules.json）和 1 个新测试文件。命令检查 2 个（放行表、拒绝表），人工检查 3 个（修改范围、跨仓 6 测试、文档一致）。不设集成或端到端层：真实消费方接入 CI 是 multica 的 M3。

### 1.2 测试原则

- 每个检查只对应一条保证；不为同一保证堆叠多个检查。
- 拒绝表是防止「放宽」变成「放得过宽」的唯一护栏，必须覆盖 multica 已固化的 11 种近似形状。
- 匹配语义与真实消费方一致：`args.join(' ')` 后用 `new RegExp(shape).test`（与 `crctl.mjs controlledGit`、Go `gitguard.Check` 相同）。
- 断言须含能区分对错的观测值（具体计数、被拒绝的具体参数），不得只匹配 PASS 标签；本计划的 CP 另断言 `pass 1 fail 0`。 / Assertions must carry observable values that distinguish right from wrong.
- 人工检查如实标注为人工，不伪装成自动化。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| `skills/shared/crctl/scripts/test/guard-protected-paths.test.mjs` | 既有 | 单元（黑盒） | rules.json#protectedPaths 的写保护，本 change 不改 |
| multica `server/internal/daemon/crevents_test.go::TestProposedSnapshotReadShapes` 与 5 个 `TestM26B2/B4*` | 6 | 单元 | 消费方对 3 种形状的需求（TC-CSS-004 用它做一次性跨仓验证） |
| `controlled-shell-rules.test.mjs`（本 change 新增） | 2 | 单元 | 放行表、拒绝表 |

## 二、详细测试案例

### 功能 1：放行与拒绝（REQ-CSS-001、REQ-CSS-002）

#### 案例 1.1 — 放行表

| 字段 | 内容 |
|------|------|
| **ID** | TC-CSS-001 |
| **对应 Spec** | controlled-shell-git-show-shapes → SC-001 |
| **优先级** | P0 |
| **预置条件** | 真实 rules.json 的 `git[sub=show]` 形状，按 `new RegExp` 构造 |
| **输入** | 放行表每个参数组合：`--name-only --format= <40hex>`；`<sha>:change-requests/CR-2026-002/test-report.md`；`…/trace.tests`、`.yml`、`.yaml`、`.json`；`CR-FS-2026-003`、`CR-AFP-2026-1000` 的账本式 KEY；原两种形状各一个正例 |
| **预期结果** | 全部被放行；用例标题含 `TCCSS001`，`node --test` 输出 `pass 1 fail 0` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 1.2 — 拒绝表

| 字段 | 内容 |
|------|------|
| **ID** | TC-CSS-002 |
| **对应 Spec** | controlled-shell-git-show-shapes → SC-002 |
| **优先级** | P0 |
| **预置条件** | 同 TC-CSS-001 |
| **输入** | 11 种：`HEAD:change-requests/_backlog.yml`；`1111111:change-requests/_backlog.yml`；`<sha>:change-requests/_backlog.yml/../_history.yml`；`<sha>:change-requests/CR-2026-002/prd.md`；`…/trace.tests.exe`；`…/test-report.md/../cr.md`；`…/approval.yml`；`<sha>:package.json`；`<sha>:change-requests/_backlog.yml_extra`；`CR-fs-2026-003/cr.md`；`CR-ABCDEFGHI-2026-003/cr.md` |
| **预期结果** | 11 个全部不被任何 show 形状放行；用例标题含 `TCCSS002`，`pass 1 fail 0` |
| **当前状态** | ❌ 测试缺（该表在加形状前后都应通过，RED 阶段只因文件不存在而失败；BUILD 变异检查须把某条新形状改宽后看到它红） |

### 功能 2：修改范围与一致性（REQ-CSS-003、REQ-CSS-004、REQ-CSS-005）

#### 案例 2.1 — rules.json 只动 show.shapes

| 字段 | 内容 |
|------|------|
| **ID** | TC-CSS-003 |
| **对应 Spec** | controlled-shell-git-show-shapes → SC-003 |
| **优先级** | P0 |
| **预置条件** | 改前 HEAD 与改后的 rules.json |
| **输入** | 把两个版本去掉 `git[sub=show].shapes` 后做结构化比较，并核对 show 的原两条形状逐字保留 |
| **预期结果** | 其余字段完全相同；show.shapes 只增不减。人工检查，结果与命令输出写入 test-report |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

#### 案例 2.2 — multica 6 个测试对已提交 rules.json 通过

| 字段 | 内容 |
|------|------|
| **ID** | TC-CSS-004 |
| **对应 Spec** | controlled-shell-git-show-shapes → SC-004 |
| **优先级** | P0 |
| **预置条件** | multica 工作区；`MULTICA_CONTROLLED_SHELL_RULES` 指向本仓已提交的 rules.json |
| **输入** | spec SC-004 所列的 `go test ./internal/daemon -run …` |
| **预期结果** | 6 个测试全部 PASS；multica HEAD sha 与完整输出写入 test-report。人工检查：证据依赖相邻仓当时的 HEAD，不绑定 CP |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行；改前基线 6 个失败已于 2026-11-15 实测） |

#### 案例 2.3 — 文档与规则一致

| 字段 | 内容 |
|------|------|
| **ID** | TC-CSS-005 |
| **对应 Spec** | controlled-shell-git-show-shapes → SC-005 |
| **优先级** | P1 |
| **预置条件** | 改后的 controlled-shell/SKILL.md、CUSTOM.md、rules.json |
| **输入** | 人工逐条对照 show 形状清单与 TODO-017 的描述 |
| **预期结果** | 5 种形状在 SKILL.md 中逐条列出；TODO-017 的描述与代码相符，并说明 `callers` 当前仅声明不强制；无矛盾说法 |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E | 状态 |
|----------|---------|----------|-----|------|
| show 放行表 / 拒绝表 | TC-CSS-001、TC-CSS-002 | — | — | 🔴 待 BUILD |
| 修改范围、跨仓、文档 | 人工 TC-CSS-003/004/005 | 跨仓一次性（TC-CSS-004） | — | 🔴 待 BUILD |

## 四、回归风险矩阵

| 风险区域 | 本次改动 | 已有回归保护 | 风险等级 |
|---------|---------|-------------|---------|
| `show` 白名单被放宽 | 追加 3 条锚定形状 | TC-CSS-002 的 11 种拒绝；TC-CSS-003 的范围复核 | 🟡 |
| protectedPaths、forbiddenFlags、其他子命令 | 不改 | `guard-protected-paths.test.mjs`；TC-CSS-003 | 🟢 |
| `callers` 未强制 | 不改变，仅文档说明 | 无（既有事实） | 🟡 |

## 五、建议补充顺序

1. **第一优先**：TC-CSS-001、TC-CSS-002（先 RED）、TC-CSS-003。
2. **第二优先**：TC-CSS-004、TC-CSS-005。
3. **第三优先**：无。

## 六、同次执行证据计划

```stdd-evidence-plan-v1
{
  "task": "controlled-shell-git-show-shapes",
  "inputs": [
    {"root": "project", "path": "skills/shared/controlled-shell/rules.json"},
    {"root": "project", "path": "skills/shared/controlled-shell/SKILL.md"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/controlled-shell-rules.test.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/crctl.mjs"},
    {"root": "project", "path": "CUSTOM.md"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Node 栈，仓库覆盖率检查只支持 pytest-cov"},
  "checks": [
    {"tc": "TC-CSS-001", "case_id": "show-allow-table", "requirement": "REQ-CSS-001",
     "scenarios": ["SC-001"], "cp": "CP-CSS-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-CSS-002", "case_id": "show-deny-table", "requirement": "REQ-CSS-002",
     "scenarios": ["SC-002"], "cp": "CP-CSS-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-CSS-003", "case_id": "rules-change-scope", "requirement": "REQ-CSS-003",
     "scenarios": ["SC-003"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-CSS-004", "case_id": "multica-six-tests", "requirement": "REQ-CSS-004",
     "scenarios": ["SC-004"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-CSS-005", "case_id": "docs-consistent", "requirement": "REQ-CSS-005",
     "scenarios": ["SC-005"], "kind": "manual", "applicability": "required"}
  ]
}
```
