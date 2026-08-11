---
cr: CR-2026-030
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-11T09:13:52+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-01.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-02.log" }
  - { command: "node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-03.log" }
  - { command: "node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-04.log" }
  - { command: "node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-05.log" }
  - { command: "node -e \"const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));\"", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-06.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030\server\" && go vet ./internal/governance/", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-07.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030\server\" && go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -v", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-08.log" }
---

# 测试报告 · CR-2026-030

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-030/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-01.log |
| 2 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-030/test-evidence/cmd-02.log |
| 3 | `node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-03.log |
| 4 | `node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-04.log |
| 5 | `node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-05.log |
| 6 | `node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));"` | 0 | change-requests/CR-2026-030/test-evidence/cmd-06.log |
| 7 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030\server" && go vet ./internal/governance/` | 0 | change-requests/CR-2026-030/test-evidence/cmd-07.log |
| 8 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030\server" && go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -v` | 0 | change-requests/CR-2026-030/test-evidence/cmd-08.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## TASK 覆盖（CR-2026-030 TASK-01~08）

| TASK | 内容 | 证据 |
|------|------|------|
| TASK-01 | TCA-001~004 失败优先测试基线（222 tests：189 既有 + 33 新向量） | tools@f4c6fd1，TASK-02~05 逐批转绿 |
| TASK-02 | 三 Owner 注册 + register commit 真实 SHA 事件 + worktree branch（AC-1~AC-6） | tools@3fa318c |
| TASK-03 | Owner 正式移交原语（AC-7~AC-16：clean 前置/双投影/隔离 commit/回滚/双 outbox） | tools@f38df8f |
| TASK-04 | 签名 reject 权威回退 + 邻接幂等（AC-17~AC-22） | tools@2aa2107 |
| TASK-05 | R7 权威字面量校验 + review-dev-plan 三路契约（AC-27~AC-29） | tools@a2a2cd4 |
| TASK-06 | 8 Skill/4 Pipeline/crctl SKILL/3 份人读契约同步（AC-30/AC-31） | tools@29e0211 |
| TASK-07 | Multica grant test-only 跨接缝扩展 + CUSTOM.md 台账 | multica@852bcca9a |

## 修改白名单审计（AC-30）

- tools 相对基线 `cab3663` 变更 20 个文件，**全部落在 PRD FR-10.1 白名单内**（零越界）。
- multica 相对基线 `c8c96e5` 变更恰好 2 个文件：`server/internal/governance/approval_crosscheck_test.go`（test-only）+ `CUSTOM.md`（台账）；**production code 零 diff**。
- CI workflow（.github/）零 diff；Pipeline 节点数与 `pipeline-templates/_index.yml#nodes` 未变（requirement-authoring 6 / architecture-design 5 / resume-cr 3 / code-implementation 14）。
- 状态机、gates.json、rules.json、controlled-shell 白名单均未修改（单一事实源仍在 tools 权威文件）。

## 未覆盖 / 环境限制（诚实边界）

1. **Multica 跨接缝真跑被上游 TestMain DB-skip 拦截**：本机无 Docker、无本地 PostgreSQL（5432 拒绝连接），`TestGrantCrossVerifiesWithCrctl` 因包级 TestMain 约定整体 skip（cmd-08 日志见 "Skipping governance integration tests: database not reachable"）。向量代码已通过 `go vet` 编译校验；真跑需在有 DB 的环境执行：`cd server && CRCTL_PATH=<tools worktree crctl.mjs> go test -v ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl`（CUSTOM.md #26 已登记该 skip 边界）。
2. **REJECT_ROLLBACK 回退门禁依赖既有审批链文件**：dev-start/code 两个 stage 的 reject 回退目标态（tech-design-reviewed/developing）门禁需要历史审批段与证据文件，测试 fixture 已按真实链路构造；真实 CR 上 reject 时若历史审批段缺失会正常返回 GATE_BLOCKED（既有语义，非本 CR 引入）。
3. **R7 只拦截静态字面量**：模板变量与 from 完整性仍由运行时 `findTransition()` 裁决（SDD §3.9），模板变量跳过路径由 AC-29 测试锁定。
