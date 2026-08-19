# tools

- 仓库：https://github.com/OldBoy405/AI-First-tools.git（自有仓库）
- 分支：custom/main
- 引用 commit：`75d72a3583d08795d9a0f4b39ece20d7e9eddd38`（2026-08-19 刷新；`feat(crctl): register 支持 --origin 显式归因字段`；前值 `40447db4244ac8cee4b12a6842b620fd9ae1c954`）
- 本地路径（评审/开发时按需 clone）：`C:\Users\GOBAO\Downloads\AI\tools`
- 用途：研发方法论包（**9 Agent / 56 Skill / 8 Pipeline** + `skills/shared/crctl` 治理 CLI），五方组装中的方法论层
- 数量口径（**2026-08-19 重核并订正**）：
  - **Skill = 56**（`tools/skills/_index.yml` 内 `status: active` 计数，废弃项已迁至 `tools/old/skills/_index.yml` 不再登记）。历史值演变：66 → 59 → **56**。旁证：tools 仓 pre-commit 钩子 `check-skill-matrix` 输出“56 个 active skill，8 个 actor”
  - **Agent = 9**（`tools/agents/_index.yml`：product-planning-agent / requirement-writer / dev-agent / spec-agent / delivery-agent / quality-reviewer-agent / knowledge-agent / competitive-analyst-agent / customer-support-agent）。注：`agent-skill-matrix.yml` 的 **actor 为 8 个**（比 agent 少一）——两个数字口径不同，引用时必须指明是哪一个
  - **Pipeline = 8**（`tools/pipeline-templates/_index.yml`：product-planning-v1 / requirement-authoring-v1 / architecture-design-v1 / code-implementation-v1 / feature-writeback-v1 / resume-cr-v1 / competitive-radar-v1 / market-to-plan-v1）
  - ⚠️ **本仓尚有两处写着旧值 59**：`AGENTS.md:3`、`dir-graph.yaml:30`。两处均为 prose 描述（非机器读取的声明），已于 2026-08-19 同步订正
- 最后核对日期：**2026-08-19**（本次核对了 commit 指针与上述三个计数；上次 2026-07-30）
