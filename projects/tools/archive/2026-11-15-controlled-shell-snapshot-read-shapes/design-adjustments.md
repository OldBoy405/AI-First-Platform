# 设计调整说明 — 2026-11-15-controlled-shell-snapshot-read-shapes

> 原始设计基线：Phase 2 产出的 design.md + specs/*.md + test-plan.md
> 调整来源：Phase 3 (BUILD) 实现过程中的发现（逐条原始记录见 `pending-adjustments.md`）

## 调整汇总

| # | 调整类型 | 涉及文档 | 严重程度 | 调整阶段 | 影响 TC | 用户已知 |
|---|---------|---------|---------|---------|---------|---------|
| 1 | 范围补充：测试登记面 | `skills/shared/crctl/scripts/test/gate-registry.json` | Minor | Phase 3 | TC-CSS-001、TC-CSS-002 | 是（Gate 3 报告） |
| 2 | 文档事实校正 | `skills/shared/controlled-shell/SKILL.md` | Minor | Phase 3 | TC-CSS-005 | 是（Gate 3 报告） |
| 3 | 引用路径修正 | `CUSTOM.md`（CUSTOM-TODO-017） | Minor | Phase 3 | TC-CSS-005 | 是（Gate 3 报告） |
| 4 | 取证时点后移 | spec SC-004 的「已提交」措辞 | Minor | Phase 3 | TC-CSS-004 | 是（Gate 3 报告） |

## 调整详细说明

### 调整 1: 新测试登记到 suite-gate manifest

- **原始设计**：design「Architecture」只列 `rules.json` + 1 个测试文件 + 2 个文档。
- **调整内容**：`gate-registry.json` 的 `manifest.files` 与 `manifest.cases` 各加一条（2 个顶层用例）。
- **调整原因**：`suite-gate.mjs:666-669` 对「磁盘测试文件集合 ≠ manifest」直接 BLOCK，CI 的 crctl 全量套件必走该门禁；不登记则该 change 会让 CI 在启动前阻断。
- **影响范围**：登记面；无运行时行为变化。
- **影响 TC**：TC-CSS-001/002 的 CI 可执行性。
- **调整阶段**：Phase 3
- **用户已知**：Gate 3 报告列出。

### 调整 2: SKILL.md 版本与子命令计数校正

- **原始设计**：design 决策 4 只要求「`show` 说明增加三种形状」。
- **调整内容**：新增 `show` 行（顺序同 `rules.json`，注明 40 位小写 hex、KEY 片段见 rules.json）；子命令计数 19 → 21（表格为常用 20 行，`symbolic-ref` 未列出）；头部版本 v0.1.0 → v0.3.0 并补版本历史一行。
- **调整原因**：`rules.json` 实有 21 条（实测）；新增 `show` 行后仍写 19 条即自相矛盾，撞 SC-005「不含相互矛盾的说法」。头部版本与历史最新行原本也不一致。
- **影响范围**：`SKILL.md` 说明文字与版本表；规则文件与测试未受影响。
- **影响 TC**：TC-CSS-005。
- **调整阶段**：Phase 3
- **用户已知**：Gate 3 报告列出。

### 调整 3: CUSTOM-TODO-017 证据路径改指归档位置

- **原始设计**：沿用原行文本，未提路径。
- **调整内容**：`projects/multica/changes/...` → `projects/multica/archive/...`。
- **调整原因**：该 change 已归档，`changes/` 下不存在此证据目录（已核实）。
- **影响范围**：`CUSTOM.md` 一行引用。
- **影响 TC**：TC-CSS-005。
- **调整阶段**：Phase 3
- **用户已知**：Gate 3 报告列出。

### 调整 4: TC-CSS-004 的「已提交 rules.json」留到交付后复验

- **原始设计**：spec SC-004 要求规则文件处于「已提交」状态。
- **调整内容**：Gate 3 前以工作区文件验证并记录 multica HEAD；提交态复验在 DELIVER 提交后补跑。
- **调整原因**：Git 提交需单独授权，STDD Gate 不授权提交；不能为满足措辞先提交。
- **影响范围**：TC-CSS-004 的取证时点；验证内容不变。
- **影响 TC**：TC-CSS-004。
- **调整阶段**：Phase 3
- **用户已知**：Gate 3 报告列出；若提交未获授权，SC-004 的「已提交」措辞不成立。

## 明确不调整（记录为已知边界）

1. **40 位 hex 不区分对象类型**：`git show --name-only --format= <blob-sha>` 会输出 blob 内容（已实测）。三条形状由 spec SC-001 与 multica `TestProposedSnapshotReadShapes` 逐字固化，改成 `^{commit}` 会破坏消费方；`callers` 不强制是 design 已声明的既有事实。作为边界记录，不在本 change 修。
2. **JS `$` 与 Go RE2 `$` 的尾换行差异**：JS 放行 `…md\n`，Go 拒绝。真实 daemon 走 Go 侧（更严）；crctl 侧该参数只会指向不存在的路径。不修，记录。
3. **test-plan.md 头部引用的 canonical spec 路径不存在**（真实文件为 `canonical/specs/code/controlled-shell-git-show-shapes.yaml`）。test-plan 是 Gate 2 受审字节，本 change 不改，留待后续修订。
4. **既有测试样本重叠**：`pipeline-structure.test.mjs`、`cr-id-format.test.mjs` 与本 change 的拒绝表有样本交集（消费方维度 vs 完整清单），语义不同；不改 test-plan 的「不重复检查」措辞。
