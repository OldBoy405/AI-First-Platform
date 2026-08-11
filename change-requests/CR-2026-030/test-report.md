---
cr: CR-2026-030
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-11T10:02:37+08:00"
commands:
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-01.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-02.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-03.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-04.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-05.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node -e \"const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));\"", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-06.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server\" && go vet ./internal/governance/", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-07.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server\" && set CRCTL_PATH=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030/skills/shared/crctl/scripts/crctl.mjs&& go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -v", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-08.log" }
---

# 测试报告 · CR-2026-030

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-030/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-01.log |
| 2 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-030/test-evidence/cmd-02.log |
| 3 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-03.log |
| 4 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-04.log |
| 5 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-05.log |
| 6 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));"` | 0 | change-requests/CR-2026-030/test-evidence/cmd-06.log |
| 7 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server" && go vet ./internal/governance/` | 0 | change-requests/CR-2026-030/test-evidence/cmd-07.log |
| 8 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server" && set CRCTL_PATH=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030/skills/shared/crctl/scripts/crctl.mjs&& go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -v` | 0 | change-requests/CR-2026-030/test-evidence/cmd-08.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

- `cr-init` 三 Owner 生成与 `owner-set` 双投影由 223 项 crctl 测试覆盖；新增断言以结构化 YAML 层级检查 backlog 的三角色 Owner。
- R7 覆盖唯一 `transitions:` 约束、缺失、空、截断与畸形状态机，解析失败统一为 `STATE_MACHINE_PARSE_FAILED`。
- Go 到 crctl 跨接缝实际执行并通过 approve 新消费、reject 权威回退、相邻状态幂等三个子场景；该定向测试不依赖 PostgreSQL。其余 governance 数据库集成测试仍需可用 PostgreSQL 后另行执行。
- 本次命令均由 crctl 依据实际退出码生成；原始输出保存在 `test-evidence/`。
