# tools

- 仓库：https://github.com/OldBoy405/AI-First-tools.git（自有仓库）
- 分支：custom/main
- 引用 commit：`c4b10d505d737c423c81ee9a4f3dd6980647f46a`（2026-08-21 刷新；`merge CR-2026-050: tools`——pipeline 合约修复与 architecture-design prompt 收敛；前值 `75d72a3583d08795d9a0f4b39ece20d7e9eddd38`）
- 本地路径（评审/开发时按需 clone）：`C:\Users\GOBAO\Downloads\AI\tools`
- 用途：研发方法论包（**9 Agent / 56 Skill / 8 Pipeline** + `skills/shared/crctl` 治理 CLI），五方组装中的方法论层
- 数量口径（**2026-08-19 重核并订正**）：
  - **Skill = 56**（`tools/skills/_index.yml` 内 `status: active` 计数，废弃项已迁至 `tools/old/skills/_index.yml` 不再登记）。历史值演变：66 → 59 → **56**。旁证：tools 仓 pre-commit 钩子 `check-skill-matrix` 输出“56 个 active skill，8 个 actor”
  - **Agent = 9**（`tools/agents/_index.yml`：product-planning-agent / requirement-writer / dev-agent / spec-agent / delivery-agent / quality-reviewer-agent / knowledge-agent / competitive-analyst-agent / customer-support-agent）。注：`agent-skill-matrix.yml` 的 **actor 为 8 个**（比 agent 少一）——两个数字口径不同，引用时必须指明是哪一个
  - **Pipeline = 8**（`tools/pipeline-templates/_index.yml`：product-planning-v1 / requirement-authoring-v1 / architecture-design-v1 / code-implementation-v1 / feature-writeback-v1 / resume-cr-v1 / competitive-radar-v1 / market-to-plan-v1）
  - ⚠️ 历史残留说明：tools 仓 `AGENTS.md:3`、`dir-graph.yaml:30` 已于 2026-08-19 订正为 56；`ARCHITECTURE.md:19` 残留的 59 已于 2026-08-21 订正（本包 README/CLAUDE.md/AGENT-SKILL-MATRIX.md 无固定计数）。工作区历史审计/快照文档（docs/2026-08-10/、docs/analysis/、docs/product/done/）内的 59/57 为当时记录，不追改
- 最后核对日期：**2026-08-21**（本次刷新 commit 指针至 CR-2026-050 merge，并订正 tools/ARCHITECTURE.md 残留 59；上次 2026-08-19）
