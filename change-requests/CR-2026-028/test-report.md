---
cr: CR-2026-028
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-10T18:51:21+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-028/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/writeback.test.mjs", exit: 0, log: "change-requests/CR-2026-028/test-evidence/cmd-02.log" }
  - { command: "node --check skills/shared/crctl/scripts/crctl.mjs", exit: 0, log: "change-requests/CR-2026-028/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-028

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-028/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-028/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/writeback.test.mjs` | 0 | change-requests/CR-2026-028/test-evidence/cmd-02.log |
| 3 | `node --check skills/shared/crctl/scripts/crctl.mjs` | 0 | change-requests/CR-2026-028/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### TASK 验收覆盖矩阵（FR-9）

| TASK | 验收条件 | 证据 |
|---|---|---|
| TASK-01 worktree-path 嵌套 bug | linked-worktree 黑盒：主 checkout 根、无嵌套 `.rayai-worktrees` | crctl.test 新增用例（`linked worktree 内调用以主 checkout 为根`）✅；真实环境 worktree-path 输出验证 ✅ |
| TASK-02 resolveToolsRoot | 表驱动失败场景全部 `TOOLS_PACKAGE_NOT_FOUND` + exit 1；成功 realpath + 缓存 | crctl.test 新增 2 用例（表驱动 5 场景 + 四标志逐一缺失）✅ |
| TASK-03 四 loader 收敛 | 四 sentinel 行为；CRCTL_RULES_PATH 覆盖；显式 ws 参数 | crctl.test 新增 4 用例（状态机/gates+pipeline/rules sentinel + 换 checkout 不变）✅；既有 CRCTL_RULES_PATH 用例保持绿 ✅ |
| TASK-04 双根 worktree 定位 | 多仓 worktree-path 正确；sync 三 Skill 消费核对 | linked-worktree 用例 ✅ + sync 三 SKILL 仅消费 `worktree-path` 返回值（FR-29②，无手拼）✅ |
| TASK-05/06 FR-5 路径统一 | 七禁止模式零命中；`{TOOLS_ROOT}` 统一 | grep 判据 3 次全零命中 ✅；pipeline JSON 合法 + 三件套全绿 ✅ |
| TASK-07 FR-6 Registration | cr-init 一次写齐 summary/source/target-version；提示词无二次补写 | 既有 cr-init metadata 用例（CR-2026-022 AC-4）绿 ✅；SKILL/pipeline 文本无"建档后补 frontmatter" ✅ |
| TASK-08 FR-7 删 target_install_path | grep 零命中（仅保留注释说明）；multica 台账核账一致 | `rg target_install_path` 零消费点 ✅；CUSTOM.md 已登记（cb957b73）✅ |
| TASK-09 测试扩展 | fixture/表驱动/linked-worktree/四 sentinel/rules 覆盖/metadata/AC-8 | 全部 156 用例绿 ✅ |

### 测试命令与结果解读

- **crctl 套件**：156/156 pass（148 既有回归 + 8 新增：TASK-01 linked-worktree、TASK-02 表驱动×2、TASK-03 sentinel×4、AC-8 源码审查）——既有行为零回归。
- **writeback 套件**：9/9 pass（路径表达改动仅注释/提示词，脚本逻辑未动）。
- **语法检查**：crctl.mjs `node --check` pass。
- **lint（三件套）**：check-skill-matrix / check-agents-contract / lint-prompts enforce 在每次 commit 自动执行，9 次实现 commit 全绿（57 skill 一致、9 agent 契约、0 prompt 漂移）。

### 新增/修改测试文件

- `skills/shared/crctl/scripts/test/crctl.test.mjs`（修改）：`makeToolsFixture` + `makeWorkspace({toolsRoot})` 扩展、`BRIEF_GATES` fixture、6 个新用例 + AC-8 源码审查用例、setupBriefWs 改为 fixture 形态。
- `skills/writeback/scripts/test/writeback.test.mjs`：仅注释路径表达更新，无逻辑改动。

### 未覆盖风险

1. **真实 merge 与跨仓联调**（TASK-10）：双仓 merge 后主 checkout 的 Tools Root 解析、真实 worktree 全流程走查属发布期验证，本报告未覆盖——留待代码审批通过后的 merge 与 TASK-10 联调执行。
2. **IDE hooks 物化**：Adapter 模板统一为 `{TOOLS_ROOT}` 占位符，但 claude-code/cursor/codex/qoder 各 IDE 的实际安装物化未在本 CR 逐 IDE 实测（属安装手册执行面，非代码行为）。
3. **CI 工作流**：cr-guard.template.yml 的 `$TOOLS_ROOT` 环境变量表达未在真实 GitHub Actions 跑通（模板无真实仓库可验证）。
4. **多仓 worktree 派生**：tools/multica worktree 以 `--workspace <knowledge_base_worktree>` 显式传入的场景由 linked-worktree 测试覆盖通用逻辑，但真实三仓（含 multica 独立 common-dir）的端到端在 TASK-10 联调验证。

### 下一步建议

- 代码评审（review-code）后人工审批通过 → merge-feature-branch → TASK-10 发布联调（双仓 merge、真实 worktree 走查、CUSTOM.md 台账核账）。
